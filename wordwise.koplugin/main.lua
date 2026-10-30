-- SPDX-License-Identifier: AGPL-3.0-or-later
local Blitbuffer = require("ffi/blitbuffer")
local Core = require("wordwise_core")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Screen = require("device").screen
local TextWidget = require("ui/widget/textwidget")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local WordWise = WidgetContainer:extend{
    name = "wordwise",
    is_doc_only = true,
}

function WordWise:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/wordwise.lua")
    if self.settings:readSetting("grade_scheme") ~= "exam-cn-v1" then
        self.settings:saveSetting("threshold", 2)
        self.settings:saveSetting("grade_scheme", "exam-cn-v1")
        self.settings:delSetting("include_ungraded")
        self.settings:flush()
    end
    self.threshold = self.settings:readSetting("threshold", 2)
    self.limit = self.settings:readSetting("limit", 30)
    if self.settings:readSetting("page_limit_version") ~= 2 then
        if self.limit == 20 then
            self.limit = 30
            self.settings:saveSetting("limit", 30)
        end
        self.settings:saveSetting("page_limit_version", 2)
        self.settings:flush()
    end
    if self.settings:readSetting("font_scheme") ~= "uniform-v1" then
        self.settings:saveSetting("font_scheme", "uniform-v1")
        self.settings:saveSetting("font_size", 8)
        self.settings:flush()
    end
    self.font_size = self.settings:readSetting("font_size", 8)
    self.enabled = self.settings:readSetting("enabled", false)
    self.show_button = self.settings:readSetting("show_button", true)
    self.generation, self.labels, self.visible = 0, {}, false
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function WordWise:onDispatcherRegisterActions()
    Dispatcher:registerAction("wordwise_scan", {
        category = "none", event = "WordWiseScan", title = "生词提示：扫描当前页", reader = true,
    })
    Dispatcher:registerAction("wordwise_toggle", {
        category = "none", event = "WordWiseToggle", title = "生词提示：隐藏／显示", reader = true,
    })
    Dispatcher:registerAction("wordwise_clear", {
        category = "none", event = "WordWiseClear", title = "生词提示：清除当前页", reader = true,
    })
    Dispatcher:registerAction("wordwise_settings", {
        category = "none", event = "WordWiseSettings", title = "生词提示：打开快捷设置", reader = true,
    })
    Dispatcher:registerAction("wordwise_enabled", {
        category = "none", event = "WordWiseEnabled", title = "生词提示：开关自动提示", reader = true,
    })
end

function WordWise:onReaderReady()
    self.view = self.ui.view
    self.view:registerViewModule("wordwise", self)
    self.ui:registerTouchZones({{
        id = "wordwise_button", ges = "tap",
        screen_zone = {ratio_x=0,ratio_y=0,ratio_w=1,ratio_h=1},
        overrides = {"readerhighlight_tap", "tap_forward", "tap_backward", "tap_right_bottom_corner"},
        handler = function(ges)
            local rect = self.show_button and self:buttonRect()
            if rect and ges.pos.x >= rect.x and ges.pos.x < rect.x+rect.w
                and ges.pos.y >= rect.y and ges.pos.y < rect.y+rect.h then
                return self:onWordWiseSettings()
            end
        end,
    }})
    self:applyReadingSpacing()
    self:scheduleAutoScan()
end

function WordWise:notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function WordWise:releaseLabels()
    for _, label in ipairs(self.labels) do label.widget:free() end
    self.labels = {}
    self.visible = false
end

function WordWise:invalidate()
    self.generation = self.generation + 1
    self:releaseLabels()
    self.status = nil
    self.source = nil
    self.cache_page = nil
    -- ReaderView's page/layout handlers request the repaint themselves.
end

function WordWise:canPreload()
    local document=self.ui.document
    return not document.info.has_pages and self.view and self.view.view_mode=="page"
        and document:getVisiblePageCount()==1
end

function WordWise:stopPreload(clear)
    if self.preload_job then self.preload_job:cancel();self.preload_job=nil end
    if clear then self.page_cache={};self.preload_key=nil;self.cache_page=nil end
end

function WordWise:preloadKey()
    local area, offset=self.view.visible_area,self.view.state.offset
    return table.concat({self.ui.document:getDocumentRenderingHash(true),Screen:getWidth(),Screen:getHeight(),
        area.w,area.h,offset.x,offset.y,self.threshold,self.font_size,self.limit,tostring(self.show_button)},":")
end

function WordWise:usePageCache(quiet)
    if not self.enabled or not self:canPreload() then return false end
    local key=self:preloadKey()
    if self.preload_key~=key then self:stopPreload(true);self.preload_key=key end
    local page=self.ui.document:getCurrentPage()
    local entry=self.page_cache and self.page_cache[page]
    if not entry then return false end
    if self.cache_page~=page then
        self.source,self.proper_nouns=entry.source,entry.protected
        self:layoutHints(entry.hints,entry.lines,quiet)
        self.cache_page=page
        self.cache_hits=(self.cache_hits or 0)+1
    end
    return true
end

function WordWise:startPreload()
    self:stopPreload(false)
    self:usePageCache(true)
    local key=self:preloadKey()
    local document=self.ui.document
    local page=document:getCurrentPage()
    local targets,retained={},{}
    for _,number in ipairs({page,document:getNextPage(page),document:getPrevPage(page)}) do
        if number>0 then
            if self.page_cache and self.page_cache[number] then retained[number]=self.page_cache[number]
            else targets[#targets+1]=number end
        end
    end
    self.page_cache=retained
    if #targets==0 then return end
    self.records=self.records or Core.readLevels(self.path.."/data/levels.tsv")
    self.names=self.names or require("wordwise_names").load(self.path.."/models/pos")
    local Prefetch=require("wordwise_prefetch")
    self.preload_job=Prefetch.start(function() return Prefetch.prepare(self,targets) end,function(results)
        self.preload_job=nil
        if self.closed or self.suspended or not self.enabled or key~=self:preloadKey() then return end
        for _,entry in ipairs(results) do self.page_cache[entry.page]=entry end
        -- A cached turn is painted with the page. Only a first/cache-miss page
        -- needs a later UI refresh when its background job completes.
        if not self.cache_page then
            self:usePageCache(true)
            UIManager:setDirty(self.ui.dialog,"ui")
        end
    end,function(err)
        self.preload_job=nil
        logger.err("WordWise preload:",err)
        self:notify("生词提示预处理失败：\n"..tostring(err):match("^[^\n]+"))
    end)
end

function WordWise:cancelAutoScan()
    if self.auto_task then UIManager:unschedule(self.auto_task); self.auto_task = nil end
end

function WordWise:scheduleAutoScan()
    self:cancelAutoScan()
    if not self.enabled or self.closed or self.suspended or not self.view then return end
    self.auto_task = function()
        self.auto_task = nil
        if not self.enabled or self.closed or self.suspended then return end
        if self.busy then self:scheduleAutoScan(); return end
        self:onWordWiseScan(true)
    end
    UIManager:scheduleIn(0.5, self.auto_task)
end

function WordWise:pageChanged()
    self:stopPreload(false)
    self:invalidate()
    self:scheduleAutoScan()
end
function WordWise:resetLayout() self:stopPreload(true);self:pageChanged() end
function WordWise:onPageUpdate() self:pageChanged() end
function WordWise:onPosUpdate() self:pageChanged() end
function WordWise:onZoomUpdate() self:resetLayout() end
function WordWise:onViewRecalculate() self:resetLayout() end
function WordWise:onSetRotationMode() self:resetLayout() end
function WordWise:onSetDimensions() self:resetLayout() end
function WordWise:onDocumentRerendered() self:resetLayout() end
function WordWise:onSuspend()
    self:stopPreload(true)
    self.suspended = true
    self:cancelAutoScan()
    self:invalidate()
end
function WordWise:onResume()
    self.suspended = false
    self:scheduleAutoScan()
end
function WordWise:onCloseDocument()
    self:stopPreload(true)
    self.closed = true
    self:cancelAutoScan()
    if self.controls then UIManager:close(self.controls); self.controls = nil end
    self:invalidate()
    if self.button_text then self.button_text:free(); self.button_text = nil end
    self.settings:flush()
end

function WordWise:onWordWiseClear()
    self:stopPreload(true)
    self:cancelAutoScan()
    self:invalidate()
    UIManager:setDirty(self.ui.dialog, "partial")
    return true
end

function WordWise:setEnabled(enabled)
    local was_enabled=self.enabled
    self.enabled = enabled
    self.settings:saveSetting("enabled", enabled)
    self.settings:flush()
    self:onWordWiseClear()
    if not enabled or not was_enabled then self:applyReadingSpacing() end
    if enabled then self:scheduleAutoScan() end
end

function WordWise:applyReadingSpacing()
    if self.ui.document.info.has_pages then return end -- Fixed-layout PDF cannot be reflowed this way.
    local config=self.ui.document.configurable
    local settings=self.ui.doc_settings
    local key="wordwise_original_line_spacing"
    local original=settings:readSetting(key)
    if self.enabled then
        if config.line_spacing~=200 then
            if original==nil then settings:saveSetting(key,config.line_spacing) end
            self.ui.font:onSetLineSpace(200)
        end
    elseif original~=nil then
        -- A manual change while hints were on belongs to the reader: retain it.
        if config.line_spacing==200 then self.ui.font:onSetLineSpace(original) end
        settings:delSetting(key)
    end
end

function WordWise:onWordWiseEnabled()
    self:setEnabled(not self.enabled)
    return true
end

function WordWise:buttonRect()
    if not self.button_text then
        self.button_text = TextWidget:new{text="生词提示",face=Font:getFace("cfont",14),padding=0}
    end
    local size, margin = self.button_text:getSize(), Screen:scaleBySize(6)
    local footer = self.view and self.view.footer_visible and self.view.footer:getHeight() or 0
    local height = math.max(size.h+2*margin,Screen:scaleBySize(44))
    return {x=Screen:getWidth()-size.w-3*margin, y=Screen:getHeight()-footer-height-margin,
        w=size.w+2*margin,h=height, padding=margin,text_y=math.floor((height-size.h)/2)}
end

function WordWise:onWordWiseSettings()
    if self.closed or self.controls then return true end
    self.controls = require("wordwise_controls").show(self)
    return true
end

function WordWise:onWordWiseToggle()
    if #self.labels == 0 then
        self:notify("当前页还没有生词提示。请先运行“扫描当前页”。")
    else
        self.visible = not self.visible
        UIManager:setDirty(self.ui.dialog, "partial")
    end
    return true
end

function WordWise:paintTo(bb, x, y)
    if self.capturing then return end
    self:usePageCache(true)
    if self.show_button then
        local rect = self:buttonRect()
        self.button_text:paintTo(bb,x+rect.x+rect.padding,y+rect.y+rect.text_y)
    end
    if not self.visible then return end
    for _, label in ipairs(self.labels) do
        label.widget:paintTo(bb,x+label.text_x,y+label.y)
        -- Kindle-style overbrace: word-width horizontal strokes with a small
        -- upward centre notch. No box, background or text-size change.
        local base = y+label.y+label.h-1
        local notch = math.min(label.brace_h-1,math.floor((label.brace_x1-label.brace_x0-1)/2))
        local cx = x+label.tip_x
        bb:paintRect(x+label.brace_x0,base,math.max(0,cx-notch-x-label.brace_x0),1,Blitbuffer.COLOR_DARK_GRAY)
        bb:paintRect(cx+notch+1,base,math.max(0,x+label.brace_x1-cx-notch-1),1,Blitbuffer.COLOR_DARK_GRAY)
        for dx=-notch,notch do
            bb:paintRect(cx+dx,base-notch+math.abs(dx),1,1,Blitbuffer.COLOR_DARK_GRAY)
        end
    end
end

function WordWise:layoutHints(hints, lines, quiet)
    self:releaseLabels()
    self.padding = 0
    local widgets, retained = {}, {}
    local face = Font:getFace("cfont", self.font_size)
    local Label = require("wordwise_label")
    local function measure(gloss, available)
        -- Keep the font unchanged; discard only the font's blank leading.
        local widget = Label.new(gloss,face)
        widgets[#widgets + 1] = widget
        local size = widget:getSize()
        if size.h > available then return end
        return size.w, size.h, widget
    end
    Core.prioritize(hints)
    local obstacles = self.show_button and {self:buttonRect()} or {}
    local placed, omitted, limited, reasons = Core.place(hints, lines, Screen:getWidth(), Screen:getHeight(),
        measure, self.padding, Screen:scaleBySize(1), self.limit, Screen:scaleBySize(3), obstacles)
    for _, label in ipairs(placed) do
        label.widget, label.payload = label.payload, nil
        retained[label.widget] = true
        self.labels[#self.labels + 1] = label
    end
    for _, widget in ipairs(widgets) do
        if not retained[widget] then widget:free() end
    end
    self.visible = #self.labels > 0
    local rare = 0
    for _, label in ipairs(self.labels) do
        if label.hint.level == 5 then rare = rare + 1 end
    end
    self.layout_reasons = reasons
    self.status = string.format("显示 %d 个（未划分等级 %d），超上限 %d\n未显示：行距 %d，正文 %d，释义重叠 %d，页边 %d，按钮 %d",
        #self.labels, rare, limited, reasons.line_gap, reasons.text, reasons.labels, reasons.edge, reasons.controls)
    if self.source then self.status = self.source .. " · " .. self.status end
    if not quiet then UIManager:setDirty(self.ui.dialog, "partial") end
    if #hints > 0 and #self.labels == 0 and not self.auto_scan and not quiet then
        self:notify("本页生词无法放置。\n" .. self.status)
    elseif #hints == 0 and not self.auto_scan and not quiet then
        self:notify("当前页没有达到所选级别且词典有释义的生词。")
    end
end

function WordWise:runScan()
    local Text = require("wordwise_text")
    self.records = self.records or Core.readLevels(self.path .. "/data/levels.tsv")
    self:invalidate()
    UIManager:setDirty(self.ui.dialog, "partial")
    -- Render only the current reader view into a canonical, unrotated BB8.
    -- Menus, the progress dialog and our old labels never enter this snapshot.
    local gray = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Blitbuffer.TYPE_BB8)
    gray:paintRect(0, 0, gray:getWidth(), gray:getHeight(), Blitbuffer.COLOR_WHITE)
    local generation
    self.capturing = true
    local ok, completed, result = pcall(function()
        self.view:paintTo(gray, 0, 0)
        self.capturing = false
        self:cancelAutoScan()
        -- EPUB may finish a partial re-layout during paintTo. Bind the
        -- screenshot to the state actually rendered, not the pre-render page.
        generation = self.generation
        local original = Text.extract(self.ui.document, self.view, gray)
        if original then return true, original end
        return Trapper:dismissableRunInSubprocess(function()
            local OCR = require("wordwise_ocr")
            local success, data = pcall(OCR.recognize, gray, self.path .. "/models", Screen:getDPI())
            if not success then return { error = tostring(data) } end
            return data
        end, "正在离线识别当前页英文…\n点击屏幕取消")
    end)
    self.capturing = false
    gray:free()
    assert(ok, completed)
    if not completed or self.closed or generation ~= self.generation then return end
    assert(type(result) == "table", "取词流程未返回结果，请查看 crash.log。")
    assert(not result.error, result.error)
    self.source = result.source or "截图 OCR"
    -- Filter exact dictionary misses before enforcing the page limit so that
    -- unknown OCR strings cannot consume slots intended for real words.
    self.names = self.names or require("wordwise_names").load(self.path.."/models/pos")
    local words, protected = self.names:filter(result.words)
    self.proper_nouns = protected
    local hints = Core.select(words, self.records, self.threshold, nil)
    if #hints > 0 then
        local words = {}
        for _, hint in ipairs(hints) do words[#words + 1] = hint.word end
        -- rawSdcv only needs data_dir; use a dedicated context for the bundled
        -- StarDict instead of changing the user's dictionary preferences.
        local cancelled, definitions = self.ui.dictionary.rawSdcv(
            { data_dir = self.path .. "/data/dict" }, words, { Core.dictionary_name }, false)
        if cancelled or self.closed or generation ~= self.generation then return end
        hints = Core.definitions(hints, definitions)
    end
    self:layoutHints(hints, result.lines)
end

function WordWise:onWordWiseScan(automatic)
    if self.enabled and not self.closed and self:canPreload() then
        self:cancelAutoScan()
        local ok,err=xpcall(function() self:startPreload() end,debug.traceback)
        if not ok then logger.err("WordWise preload:",err);self:notify("生词提示预处理失败：\n"..tostring(err):match("^[^\n]+")) end
        return true
    end
    if self.busy or self.closed then return true end
    self.busy = true
    self:cancelAutoScan()
    self.auto_scan = automatic == true
    local generation = self.generation
    UIManager:nextTick(function()
        if self.closed or generation ~= self.generation then
            self.busy = false
            self.auto_scan = false
            return
        end
        Trapper:wrap(function()
            local ok, err = xpcall(function() self:runScan() end, debug.traceback)
            self.busy = false
            self.auto_scan = false
            if not ok then
                logger.err("WordWise:", err)
                self:notify("生词提示失败：\n" .. tostring(err):match("^[^\n]+") .. "\n\n详细信息已写入 crash.log。")
            end
        end)
    end)
    return true
end

function WordWise:saveOption(key, value)
    self[key] = value
    self.settings:saveSetting(key, value)
    self.settings:flush()
    self:onWordWiseClear()
    self:scheduleAutoScan()
end

function WordWise:addToMainMenu(menu_items)
    local levels, limits, sizes = {}, {}, {}
    for i, name in ipairs(Core.levels) do
        local level = i - 1
        levels[#levels + 1] = {
            text = name, checked_func = function() return self.threshold == level end,
            callback = function() self:saveOption("threshold", level) end,
        }
    end
    for _, value in ipairs({ 5, 10, 15, 20, 30 }) do
        limits[#limits + 1] = {
            text = tostring(value), checked_func = function() return self.limit == value end,
            callback = function() self:saveOption("limit", value) end,
        }
    end
    for _, value in ipairs({ 8, 9, 10, 12, 14, 16, 18 }) do
        sizes[#sizes + 1] = {
            text = tostring(value), checked_func = function() return self.font_size == value end,
            callback = function() self:saveOption("font_size", value) end,
        }
    end
    menu_items.wordwise = {
        text = "生词提示 · WordWise", sorting_hint = "tools",
        sub_item_table = {
            { text = "扫描当前页", keep_menu_open = false, callback = function() self:onWordWiseScan() end },
            { text_func = function() return self.visible and "隐藏提示" or "显示提示" end,
                enabled_func = function() return #self.labels > 0 end,
                callback = function() self:onWordWiseToggle() end },
            { text = "清除本页提示", callback = function() self:onWordWiseClear() end, separator = true },
            { text_func = function() return "生词起点：" .. Core.levels[self.threshold + 1] end,
                sub_item_table = levels },
            { text_func = function() return "每页上限：" .. self.limit end, sub_item_table = limits },
            { text_func = function() return "统一提示字号：" .. self.font_size end,
                sub_item_table = sizes },
            { text="快捷设置（难度／开关）",callback=function() self:onWordWiseSettings() end },
            { text="显示右下角“生词提示”按钮",checked_func=function() return self.show_button end,
                callback=function() self:saveOption("show_button",not self.show_button) end },
            { text="开启提示，翻页自动更新",checked_func=function() return self.enabled end,
                callback=function() self:onWordWiseEnabled() end },
            { text="触发手势",enabled_func=function() return self.ui.gestures ~= nil end,
                sub_item_table_func=function() return self:gestureMenu() end },
            { text_func = function() return self.status or "尚未扫描当前页" end, enabled = false },
            { text = "使用说明", callback = function()
                self:notify("完全离线，使用随包 ECDICT 短释义词典。\n\n分级为小学、初中、高中、四级、六级，以及未划分等级，每词只存一级，显示所选及以上。小学参考2022课标与人教教材，其余参考对应教材／考试词表；取最早学习阶段，明确屈折变形与本词取最早阶段。不匹配小学至六级的词统一标为未划分等级，不代表更难。旧 CEFR 设置升级后重置为高中，需重新选择。\n\n上下文词性模型略过人名等专有名词，普通名词仍查词；不是仅按大写屏蔽，也不是百分之百准确的人名识别器。\n\n开启提示默认把 EPUB 行距调到最大200%，关闭恢复原值；若期间手动改过行距，保留手动值。固定版PDF行距不变。右下角透明文字按钮可设置难度、开关；翻页自动更新，每页最多30个。\n\nEPUB单页模式后台预处理相邻三页，缓存就绪后正文与译文同帧显示。首次开启、快速跳页仍需等待；不关闭阅读器定期全刷。\n\n版本 0.4.4 · Kindle Scribe 预览版")
            end },
        },
    }
end

function WordWise:gestureMenu()
    local gestures = assert(self.ui.gestures, "请先启用 KOReader 手势插件。")
    local choices = {
        {"multiswipe_north_south", "下滑再上滑（单指连续）"},
    }
    if require("device"):hasMultitouch() then
        table.insert(choices,1,{"two_finger_tap_bottom_right_corner","双指轻点右下角（推荐：快捷设置）"})
        table.insert(choices,2,{"two_finger_tap_bottom_left_corner","双指轻点左下角（推荐：扫描当前页）"})
    end
    local items = {{text="手势说明",callback=function()
        self:notify("推荐双指轻点右下角打开快捷设置，双指轻点左下角扫描当前页。进入对应手势后，在“阅读器”动作中选择生词提示动作。\n\n复用 KOReader 原生手势配置，不自动覆盖已有绑定。单指连续手势需要在 KOReader 手势设置中开启连续手势。")
    end}}
    for _, choice in ipairs(choices) do
        local id, title = choice[1], choice[2]
        items[#items+1] = {text=title,sub_item_table_func=function() return gestures:genMenu(id) end}
    end
    return items
end

return WordWise
