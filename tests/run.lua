package.path = "wordwise.koplugin/?.lua;" .. package.path
local Core = require("wordwise_core")
local ffi = require("ffi")
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. "\n" .. err) end
end
local function equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function rejects(fn) assert(not pcall(fn), "expected an explicit error") end
local function occurrence(text, x, y)
    return { text = text, x0 = x or 100, y0 = y or 100, x1 = (x or 100) + 40, y1 = (y or 100) + 20, line_id = 1 }
end
local records = {
    someone = { level = 2, rank = 500 }, precious = { level = 3, rank = 2000 },
    intricate = { level = 5, rank = 7000 }, difficult = { level = 2, rank = 800 },
}
test("normalizes exact case and boundary punctuation", function() equal(Core.normalize("  (SOmeOne). "), "someone") end)
test("preserves internal apostrophe", function() equal(Core.normalize("‘isn’t’"), "isn't"); equal(Core.normalize("isn’t"), "isn't") end)
test("does not guess fragments or OCR digit corrections", function()
    equal(Core.normalize("e"), nil); equal(Core.normalize("some0ne"), nil)
    local out=Core.select({occurrence("somene")},records,0,20)
    equal(out[1].word,"somene") -- only a candidate; dictionary must confirm it
end)
test("threshold is inclusive", function()
    local out = Core.select({occurrence("someone"), occurrence("precious")}, records, 3, 20)
    equal(#out, 1); equal(out[1].word, "precious")
end)
test("deduplicates only spelling and keeps first location", function()
    local out = Core.select({occurrence("someone", 10), occurrence("SOMEONE", 90)}, records, 0, 20)
    equal(#out, 1); equal(out[1].x0, 10)
end)
test("limit selects higher CEFR then lower frequency and restores reading order", function()
    local out = Core.select({occurrence("precious", 5, 100), occurrence("intricate", 5, 200), occurrence("someone", 5, 300)}, records, 0, 2)
    equal(#out, 2); equal(out[1].word, "precious"); equal(out[2].word, "intricate")
end)
test("outside common index uses explicit user policy group", function()
    local out=Core.select({occurrence("unclassified")},records,5,20)
    equal(#out,1);equal(out[1].level,5)
end)
test("every common word has exactly one CEFR or extension group", function()
    local r = {nomenclature={level=5, rank=19821}, significantly={level=3, rank=1804}}
    local words={occurrence("nomenclature"),occurrence("significantly")}
    equal(#Core.select(words,r,4,20),1)
    local out=Core.select(words,r,2,20)
    equal(#out,2);equal(out[1].level,5)
end)
test("plain StarDict definition is paired with source occurrence", function()
    local hints = Core.select({occurrence("precious")}, records, 0, 20)
    local out = Core.definitions(hints, {{ {dict = Core.dictionary_name, definition = "宝贵的\n"} }})
    equal(out[1].gloss, "宝贵的"); equal(out[1].word, "precious"); equal(hints[1].gloss, nil)
end)
test("misaligned dictionary results are rejected", function() rejects(function() Core.definitions({{word="a"}}, {}) end) end)
test("native sdcv leading newline is removed from plain definition", function()
    local out = Core.definitions({{word="preface"}},
        {{{dict=Core.dictionary_name, word="preface", definition="\n序"}}})
    equal(out[1].gloss, "序")
end)
test("embedded definition newlines remain invalid", function()
    rejects(function() Core.definitions({{word="preface"}},
        {{{dict=Core.dictionary_name, definition="序\n前言"}}}) end)
end)
test("dictionary misses are removed and duplicate entries are rejected", function()
    equal(#Core.definitions({{word="a"}}, {{}}),0)
    rejects(function() Core.definitions({{word="a"}}, {{{}, {}}}) end)
end)
test("unreviewed HTML dictionary is rejected", function()
    rejects(function() Core.definitions({{word="a"}}, {{{dict=Core.dictionary_name, definition="<b>一个</b>"}}}) end)
end)
local function hint(x, y, gloss, line_id)
    return { x0=x, y0=y, x1=x+40, y1=y+20, gloss=gloss or "释义", line_id=line_id or 1 }
end
local measure = function() return 40, 12 end
test("positions label immediately above the word", function()
    local out, skipped = Core.place({hint(100,100)}, {{x0=0,y0=100,x1=300,y1=120}}, 400,600, measure,1,2)
    equal(#out,1); equal(skipped,0); equal(out[1].y,84)
end)
test("does not cover previous text line", function()
    local out, skipped = Core.place({hint(100,100,nil,2)},
        {{x0=0,y0=80,x1=300,y1=94},{x0=0,y0=100,x1=300,y1=120}}, 400,600, measure,1,2)
    equal(#out,0); equal(skipped,1)
end)
test("does not shift labels away from clipped page edges", function()
    local out = Core.place({hint(0,10)}, {{x0=0,y0=10,x1=300,y1=30}}, 400,600, measure,1,2)
    equal(#out,0)
end)
test("does not overlap adjacent labels", function()
    local out, skipped = Core.place({hint(100,100),hint(125,100)},
        {{x0=0,y0=100,x1=300,y1=120}}, 400,600, measure,1,2)
    equal(#out,1); equal(skipped,1)
end)
test("equal definitions retain independent render payloads", function()
    local serial=0
    local out = Core.place({hint(100,100),hint(100,200,nil,2)},
        {{x0=0,y0=100,x1=300,y1=120},{x0=0,y0=200,x1=300,y1=220}}, 400,600,function()
        serial=serial+1; return 40,12,serial
    end,1,2)
    equal(out[1].payload,1); equal(out[2].payload,2)
end)
test("low-top word is anchored to its own line rather than its glyph top", function()
    local out = Core.place({hint(100,103)}, {{x0=0,y0=100,x1=300,y1=125}},
        400,600,measure,1,2)
    equal(#out,1);equal(out[1].y,84)
end)
test("fit callback receives exact vertical space excluding frame and gap", function()
    local out = Core.place({hint(100,103,nil,2)},
        {{x0=0,y0=50,x1=300,y1=70},{x0=0,y0=100,x1=300,y1=125}},
        400,600,function(_,height) equal(height,26);return nil end,1,2)
    equal(#out,0)
end)
test("page limit counts placed labels rather than rejected candidates", function()
    local out, skipped, limited = Core.place({hint(0,100),hint(100,100)},
        {{x0=0,y0=100,x1=300,y1=125}},400,600,measure,1,2,1)
    equal(#out,1);equal(out[1].hint.x0,100);equal(skipped,1);equal(limited,0)
end)
test("thirty labels fit and the thirty-first is limited",function()
    local hints,lines={},{}
    for i=1,31 do
        hints[i]=hint(100,i*40,nil,i)
        lines[i]={x0=0,y0=i*40,x1=300,y1=i*40+20}
    end
    local out,omitted,limited=Core.place(hints,lines,400,1600,measure,1,2,30,4)
    equal(#out,30);equal(omitted,0);equal(limited,1)
end)

-- Exercise the native bridge with actual FFI memory and deliberately padded rows.
local bridge_fail, bridge_box, context
package.loaded["ffi/koptcontext"] = {
    k2pdfopt = { bmp_alloc = function() return 1 end },
    new = function()
        context = {
            src = { data=ffi.new("uint8_t[32]"), red={},green={},blue={} }, cleaned=0,
            setDeviceDPI=function() end, setDeviceDim=function() end,
            setLanguage=function() end, setBBox=function() end,
            freeOCR=function(self) self.cleaned=self.cleaned+1 end,
            free=function(self) self.freed=true end,
            getNativeWordBoxes=function()
                local box = bridge_box or {x0=0,y0=0,x1=3,y1=2}
                local row = {box}; row.x0,row.y0,row.x1,row.y1=0,0,3,2
                return {row}
            end,
            getTOCRWord=function(self, bmp,x,y,w,h,model,lang,mode,spaces,standard_process)
                equal(mode,8);equal(standard_process,0)
                if bridge_fail then return nil end; return "someone"
            end,
        }
        return context
    end,
}
local OCR = require("wordwise_ocr")
local gray = {
    data=ffi.new("uint8_t[10]", {1,2,3,99,99,4,5,6,99,99}),stride=5,
    getWidth=function() return 3 end, getHeight=function() return 2 end,
}
local Text = require("wordwise_text")
local function text_bitmap()
    local data=ffi.new("uint8_t[2400]")
    ffi.fill(data,2400,255)
    for y=5,10 do for x=1,34 do data[y*80+x]=0 end end
    return {data=data,stride=80,getWidth=function() return 80 end,getHeight=function() return 30 end}
end
test("source ink bounds exclude line-height whitespace and respect stride",function()
    local ink=Text.inkBounds(text_bitmap(),{x=0,y=0,w=40,h=20})
    equal(ink.x0,1);equal(ink.y0,5);equal(ink.x1,35);equal(ink.y1,11)
end)
test("paged source uses original text and the reader coordinate transform",function()
    local calls=0
    local doc={info={has_pages=true},getPageTextBoxes=function(_,page)
        equal(page,3)
        return {{{word="it",x0=1,y0=0,x1=5,y1=20},{word="was",x0=8,y0=0,x1=14,y1=20}}}
    end,nativeToPageRectTransform=function(_,page,rect) calls=calls+1;return rect end}
    local out=Text.extract(doc,{getCurrentPageList=function() return {3} end,
        pageToScreenTransform=function(_,page,rect) rect.x=rect.x+2;return rect end},text_bitmap())
    equal(out.source,"原文");equal(#out.words,2);equal(out.words[1].text,"it")
    equal(out.words[2].text,"was");equal(calls,2);equal(out.words[1].x0,3)
end)
test("empty page has no text source and remains eligible for declared OCR path",function()
    local doc={info={has_pages=true},getPageTextBoxes=function() return {} end}
    equal(Text.extract(doc,{getCurrentPageList=function() return {1} end},text_bitmap()),nil)
end)
test("PDF contraction joins only explicit punctuation and touching source spans",function()
    local boxes={{{word="what’",x0=1,y0=0,x1=20,y1=20},{word="s",x0=20,y0=0,x1=25,y1=20}}}
    local doc={info={has_pages=true},getPageTextBoxes=function() return boxes end,
        nativeToPageRectTransform=function(_,page,rect) return rect end}
    local view={getCurrentPageList=function() return {1} end,
        pageToScreenTransform=function(_,page,rect) return rect end}
    local out=Text.extract(doc,view,text_bitmap())
    equal(#out.words,1);equal(Core.normalize(out.words[1].text),"what's")
    equal(boxes[1][1].word,"what’") -- never modify cached upstream text
    boxes[1][2].x0=21
    out=Text.extract(doc,view,text_bitmap());equal(#out.words,2)
end)
test("text source errors propagate instead of silently triggering OCR",function()
    rejects(function() Text.extract({info={has_pages=true},getPageTextBoxes=function() error("broken text") end},
        {getCurrentPageList=function() return {1} end},text_bitmap()) end)
end)
test("text outside viewport is not replaced by OCR or hinted off screen",function()
    local doc={info={has_pages=true},getPageTextBoxes=function()
        return {{{word="someone",x0=100,y0=0,x1=140,y1=20}}}
    end,nativeToPageRectTransform=function(_,page,rect) return rect end}
    local out=Text.extract(doc,{getCurrentPageList=function() return {1} end,
        pageToScreenTransform=function() return nil end},text_bitmap())
    equal(out.source,"原文");equal(#out.words,0)
end)
test("rolling source separates it was and preserves literal contraction punctuation",function()
    local original="it was what's"
    local endings={[0]=2,[3]=6,[7]=11,[12]=13}
    local starts={[2]=3,[6]=7,[11]=12}
    local doc={info={has_pages=false},
        getTextFromPositions=function(_,a,b,no_highlight)
            equal(no_highlight,true)
            return {text=original,pos0=0,pos1=13,sboxes={{x=0,y=0,w=50,h=20}}}
        end,
        compareXPointers=function(_,a,b) return a<b and 1 or (a==b and 0 or -1) end,
        getNextVisibleWordEnd=function(_,start) return endings[start] end,
        getNextVisibleWordStart=function(_,ending) return starts[ending] end,
        getTextFromXPointers=function(_,a,b) return original:sub(a+1,b) end,
        getScreenBoxesFromPositions=function(_,a,b) return {{x=a*2,y=0,w=(b-a)*2,h=20}} end}
    local out=Text.extract(doc,{},text_bitmap())
    equal(#out.words,3);equal(out.words[1].text,"it");equal(out.words[2].text,"was")
    equal(out.words[3].text,"what's");equal(#out.lines,1)
end)
test("OCR bridge excludes stride padding and keeps coordinates", function()
    local out=OCR.recognize(gray,"tests/fixtures/model",300)
    for i,value in ipairs({1,2,3,4,5,6}) do equal(context.src.data[i-1],value) end
    equal(#out.words,1); equal(out.words[1].x1,3); equal(out.words[1].line_id,1); equal(context.src.red[128],128)
    equal(context.cleaned,2); equal(context.freed,true)
end)
test("OCR engine error frees native resources", function()
    bridge_fail=true
    rejects(function() OCR.recognize(gray,"tests/fixtures/model",300) end)
    equal(context.cleaned,2); equal(context.freed,true); bridge_fail=false
end)
test("invalid OCR coordinates are rejected before native recognition", function()
    bridge_box={x0=0,y0=0,x1=40,y1=2}
    rejects(function() OCR.recognize(gray,"tests/fixtures/model",300) end)
    equal(context.freed,true); bridge_box=nil
end)

local dirty, snapshots, notices, scan_result, cancel_scan, invalidate_in_scan, scheduled
local manager = {
    setDirty=function() dirty=dirty+1 end,
    show=function(_,widget) notices[#notices+1]=widget.text end,
    nextTick=function(_,fn) fn() end,
    scheduleIn=function(_,delay,fn) scheduled[fn]=true end,
    unschedule=function(_,fn) scheduled[fn]=nil end,
}
local settings = {
    readSetting=function(_,_,default) return default end,
    saveSetting=function() end,delSetting=function() end,flush=function() end,
}
local function module(name, object) package.loaded[name]=object end
module("ui/widget/container/widgetcontainer", {extend=function(_,object) return object end})
module("datastorage", {getSettingsDir=function() return "/tmp" end})
module("luasettings", {open=function() return settings end})
module("dispatcher", {registerAction=function() end})
module("ui/widget/infomessage", {new=function(_,o) return o end})
module("ui/uimanager",manager)
module("logger", {err=function() end})
module("device",{hasMultitouch=function() return true end,screen={getWidth=function() return 400 end,getHeight=function() return 600 end,
    getDPI=function() return 300 end,scaleBySize=function(_,n) return n end}})
module("ui/font",{getFace=function(_,_,size)
    return {size=size,ftsize={getHeightAndAscender=function() return size*3 end}}
end})
module("ui/widget/textwidget",{new=function(_,o)
    o.getSize=function() return {w=40,h=o.face.ftsize:getHeightAndAscender()} end
    o.free=function(self) assert(not self.freed,"widget freed twice"); self.freed=true end
    o.paintTo=function(self) assert(not self.freed,"painted freed widget") end
    return o
end})
module("wordwise_label",{new=function(gloss,face)
    return package.loaded["ui/widget/textwidget"]:new{text=gloss,face=face}
end})
module("ffi/blitbuffer", {TYPE_BB8=1,COLOR_WHITE=255,COLOR_BLACK=0,new=function()
    local bb={getWidth=function() return 400 end,getHeight=function() return 600 end,
        paintRect=function() end,paintBorder=function() end,paintRoundedRect=function() end,
        free=function(self) self.freed=true end}
    snapshots[#snapshots+1]=bb;return bb
end})
module("wordwise_ocr", {recognize=function() return scan_result end})
module("wordwise_names", {load=function() return {filter=function(_,words) return words,0 end} end})
module("ui/trapper", {
    wrap=function(_,fn) fn() end,
    dismissableRunInSubprocess=function(_,fn)
        if invalidate_in_scan then invalidate_in_scan() end
        if cancel_scan then return false end
        return true,fn()
    end,
})
local WordWise=assert(loadfile("wordwise.koplugin/main.lua"))()
local function instance()
    dirty,snapshots,notices,scheduled=0,{},{},{}
    scan_result={words={occurrence("someone",100,200)},lines={{x0=0,y0=200,x1=300,y1=220}}}
    cancel_scan,invalidate_in_scan=false,nil
    local object=setmetatable({path="wordwise.koplugin",records=records}, {__index=WordWise})
    object.ui={registerTouchZones=function(_,zones) object.zones=zones end,
        document={info={has_pages=true}},menu={registerToMainMenu=function() end},dialog={},dictionary={rawSdcv=function(_,words)
        local results={};for _,word in ipairs(words) do
            results[#results+1]=word=="somene" and {} or {{dict=Core.dictionary_name,word=word,definition="某人"}}
        end;return false,results
    end}}
    object.ui.view={footer={getHeight=function() return 30 end},registerViewModule=function() end,paintTo=function()
        equal(object.visible,false) -- old labels must not contaminate the screenshot
    end}
    object:init();object:onReaderReady();return object
end
local function with_saved_settings(saved,fn)
    local read,save=settings.readSetting,settings.saveSetting
    settings.readSetting=function(_,key,default)
        if saved[key]~=nil then return saved[key] end
        return default
    end
    settings.saveSetting=function(_,key,value) saved[key]=value end
    local ok,err=pcall(fn)
    settings.readSetting,settings.saveSetting=read,save
    assert(ok,err)
end
local preload_requests
module("wordwise_prefetch",{start=function(task,callback,failure)
    local job={callback=callback,failure=failure,cancel=function(self) self.cancelled=true end}
    preload_requests[#preload_requests+1]=job
    return job
end})
local function cached_instance()
    local o=instance()
    preload_requests={}
    o.enabled=true
    o.ui.document.info.has_pages=false
    o.view.view_mode="page"
    o.view.visible_area={w=400,h=570}
    o.view.state={offset={x=0,y=0}}
    o.test_page,o.test_hash=2,"layout-a"
    o.ui.document.getVisiblePageCount=function() return 1 end
    o.ui.document.getCurrentPage=function() return o.test_page end
    o.ui.document.getDocumentRenderingHash=function() return o.test_hash end
    o.ui.document.getNextPage=function(_,p) return p+1 end
    o.ui.document.getPrevPage=function(_,p) return p-1 end
    return o
end
local function cached_page(page)
    return {page=page,source="原文",protected=0,
        hints={{word="someone",gloss="某人",level=2,rank=1,x0=100,x1=180,y0=200,y1=220,line_id=1}},
        lines={{x0=0,y0=200,x1=300,y1=220}}}
end
test("prepared next page draws hints in first frame without another dirty request",function()
    local o=cached_instance();o:startPreload()
    preload_requests[1].callback({cached_page(2),cached_page(3),cached_page(1)})
    o.test_page=3;o:onPageUpdate()
    local before=dirty
    o:paintTo({paintRect=function() end},0,0)
    equal(o.cache_page,3);equal(#o.labels,1);equal(dirty,before)
end)
test("layout hash change cannot reuse prepared coordinates and cancels worker",function()
    local o=cached_instance();o:startPreload()
    local job=preload_requests[1]
    o.test_hash="layout-b"
    equal(o:usePageCache(true),false)
    equal(job.cancelled,true);equal(next(o.page_cache),nil)
end)
test("background cache retains only current and adjacent pages",function()
    local o=cached_instance();o:startPreload()
    preload_requests[1].callback({cached_page(2),cached_page(3),cached_page(1)})
    o.page_cache[9]=cached_page(9)
    o:startPreload()
    equal(o.page_cache[9],nil)
    equal(#preload_requests,1)
end)
test("clear and suspend cancel background work without reviving cached labels",function()
    local o=cached_instance();o:startPreload()
    local job=preload_requests[1]
    o:onWordWiseClear();equal(job.cancelled,true)
    equal(next(o.page_cache),nil);equal(#o.labels,0)
    o:startPreload();local second=preload_requests[2]
    o:onSuspend();equal(second.cancelled,true);equal(next(o.page_cache),nil)
end)
test("new installs default to thirty and menu offers thirty",function()
    local o=instance();equal(o.limit,30)
    local menu={};o:addToMainMenu(menu)
    local options=menu.wordwise.sub_item_table[5].sub_item_table
    equal(options[#options].text,"30")
end)
test("font menu offers eighteen without replacing the saved choice",function()
    local o=instance();local menu={};o:addToMainMenu(menu)
    local choices=menu.wordwise.sub_item_table[6].sub_item_table
    equal(choices[#choices].text,'18')
    choices[#choices].callback();equal(o.font_size,18)
end)
test("old twenty setting migrates once while reading level stays unchanged",function()
    local saved={limit=20,threshold=3,grade_scheme="exam-cn-v1",font_scheme="uniform-v1",font_size=8}
    with_saved_settings(saved,function()
        local o=instance();equal(o.limit,30);equal(o.threshold,3)
        equal(saved.limit,30);equal(saved.page_limit_version,2)
        o:saveOption("limit",20)
        equal(instance().limit,20) -- a later explicit choice must survive restart
    end)
end)
test("lower existing page limits are preserved during migration",function()
    with_saved_settings({limit=10},function() equal(instance().limit,10) end)
end)
test("CEFR settings migrate to a distinct exam scheme rather than relabelling",function()
    local saved={threshold=5,grade_scheme="cefr-v1"}
    with_saved_settings(saved,function()
        equal(instance().threshold,2);equal(saved.grade_scheme,"exam-cn-v1")
        equal(#Core.levels,6);equal(Core.levels[1],"小学");equal(Core.levels[6],"专八")
    end)
end)
local function rolling_spacing(o,value)
    local stored={}
    o.ui.document.info.has_pages=false
    o.ui.document.configurable={line_spacing=value}
    o.ui.doc_settings={readSetting=function(_,key) return stored[key] end,
        saveSetting=function(_,key,v) stored[key]=v end,delSetting=function(_,key) stored[key]=nil end}
    o.ui.font={onSetLineSpace=function(_,v) o.ui.document.configurable.line_spacing=v end}
    return stored,o.ui.document.configurable
end
test("enabling maximizes EPUB spacing once and disabling restores the original",function()
    local o=instance();local stored,config=rolling_spacing(o,130)
    o:setEnabled(true);equal(config.line_spacing,200);equal(stored.wordwise_original_line_spacing,130)
    o:setEnabled(true);equal(stored.wordwise_original_line_spacing,130)
    o:setEnabled(false);equal(config.line_spacing,130);equal(stored.wordwise_original_line_spacing,nil)
end)
test("manual line spacing changes while enabled are retained",function()
    local o=instance();local stored,config=rolling_spacing(o,130)
    o:setEnabled(true);config.line_spacing=175;o:setEnabled(false)
    equal(config.line_spacing,175);equal(stored.wordwise_original_line_spacing,nil)
end)
test("fixed layout pages do not receive line spacing mutations",function()
    local o=instance();o:setEnabled(true);o:setEnabled(false)
    equal(o.ui.document.configurable,nil)
end)
test("complete scan links OCR words to StarDict and render labels",function()
    local o=instance();o:onWordWiseScan();equal(#o.labels,1);equal(o.visible,true)
    equal(o.labels[1].hint.gloss,"某人");equal(o.busy,false);equal(snapshots[1].freed,true)
end)
test("available original text bypasses the OCR subprocess entirely",function()
    local original_extract=Text.extract
    local o=instance()
    Text.extract=function() return {words={occurrence("someone",100,200)},
        lines={{x0=0,y0=200,x1=300,y1=220}},source="原文"} end
    cancel_scan=true -- would cancel if OCR were invoked
    local ok,err=pcall(function() o:runScan() end)
    Text.extract=original_extract
    assert(ok,err);equal(#o.labels,1);equal(o.source,"原文")
    assert(o.status:find("原文",1,true))
end)
test("dictionary misses cannot consume the page limit",function()
    local o=instance();o.limit=1
    scan_result.words={occurrence("somene",100,200),occurrence("someone",200,200)}
    o:onWordWiseScan();equal(#o.labels,1);equal(o.labels[1].hint.word,"someone")
end)
test("toggle reuses labels without taking a new screenshot",function()
    local o=instance();o:runScan();o:onWordWiseToggle();equal(o.visible,false)
    o:onWordWiseToggle();equal(o.visible,true);equal(#snapshots,1)
end)
test("cancelled scan cannot show stale labels and frees snapshot",function()
    local o=instance();o:runScan();cancel_scan=true;o:runScan()
    equal(#o.labels,0);equal(o.visible,false);equal(snapshots[2].freed,true)
end)
test("page changed during worker rejects its result",function()
    local o=instance();invalidate_in_scan=function() o:onPageUpdate() end;o:runScan();equal(#o.labels,0)
end)
test("close during worker rejects its result",function()
    local o=instance();invalidate_in_scan=function() o:onCloseDocument() end;o:runScan();equal(#o.labels,0)
end)
test("page position zoom dimensions and layout invalidate labels",function()
    for _,event in ipairs({"onPageUpdate","onPosUpdate","onZoomUpdate","onViewRecalculate","onSetRotationMode","onSetDimensions","resetLayout","onSuspend"}) do
        local o=instance();o:runScan();local widget=o.labels[1].widget
        o[event](o);equal(#o.labels,0);equal(widget.freed,true)
    end
end)
test("same Chinese gloss on two words does not corrupt widget ownership",function()
    local o=instance();local a,b=hint(100,200),hint(100,300)
    b.line_id=2
    o:layoutHints({a,b},{{x0=0,y0=200,x1=300,y1=220},{x0=0,y0=300,x1=300,y1=320}});equal(#o.labels,2)
    assert(o.labels[1].widget~=o.labels[2].widget);o:releaseLabels()
end)
test("all bubbles keep one fixed small font regardless of line gap",function()
    local o=instance()
    o:layoutHints({hint(100,115,nil,2),hint(100,300,nil,3)},
        {{x0=0,y0=50,x1=300,y1=80},{x0=0,y0=115,x1=300,y1=135},{x0=0,y0=300,x1=300,y1=320}})
    equal(#o.labels,2)
    for _,label in ipairs(o.labels) do equal(label.widget.face.size,8) end
end)
test("overbrace geometry is included and spans the original word",function()
    local out = Core.place({hint(100,100)},{{x0=0,y0=100,x1=300,y1=120}},
        400,600,measure,1,2,20,4)
    equal(#out,1);equal(out[1].h,18);equal(out[1].text_h,12)
    equal(out[1].brace_x0,100);equal(out[1].brace_x1,140)
    equal(out[1].tip_x,120);equal(out[1].y+out[1].h,98)
end)
test("omissions distinguish label overlap from line height and page edge",function()
    local out,omitted,limited,reasons=Core.place({hint(100,100),hint(125,100),hint(0,200,nil,2)},
        {{x0=0,y0=100,x1=300,y1=120},{x0=0,y0=200,x1=300,y1=220}},400,600,measure,1,2)
    equal(#out,1);equal(omitted,2);equal(reasons.labels,1);equal(reasons.edge,1);equal(reasons.line_gap,0)
end)
test("button obstacle rejects only intersecting bubbles",function()
    local out,omitted,_,reasons=Core.place({hint(100,100),hint(200,100)},
        {{x0=0,y0=100,x1=300,y1=120}},400,600,measure,1,2,30,0,{{x=90,y=80,w=60,h=18}})
    equal(#out,1);equal(omitted,1);equal(reasons.controls,1)
end)
test("menu lives at tools first level and exposes button and gesture settings",function()
    local o=instance();local menu={};o:addToMainMenu(menu)
    equal(menu.wordwise.sorting_hint,"tools")
    local found=0
    for _,item in ipairs(menu.wordwise.sub_item_table) do
        if item.text=="显示右下角“生词提示”按钮" or item.text=="触发手势" then found=found+1 end
    end
    equal(found,2)
end)
test("reading button sits above footer and captures only its own tap",function()
    local o=instance();o.view.footer_visible=true
    equal(o.ui.footer,nil) -- ReaderFooter belongs to ReaderView, not ReaderUI.
    local rect=o:buttonRect();assert(rect.y+rect.h<600-30)
    local opened=0;o.onWordWiseSettings=function() opened=opened+1;return true end
    equal(o.zones[1].handler({pos={x=rect.x,y=rect.y}}),true);equal(opened,1)
    equal(o.zones[1].handler({pos={x=20,y=20}}),nil)
    o.show_button=false;equal(o.zones[1].handler({pos={x=rect.x,y=rect.y}}),nil)
end)
test("auto mode schedules the settled page and disabling cancels it",function()
    local o=instance();o:setEnabled(true);assert(o.auto_task)
    local first=o.auto_task;o:onPageUpdate();equal(scheduled[first],nil)
    local second=o.auto_task;second();equal(#o.labels,1);equal(o.auto_task,nil)
    o:onPosUpdate();local pending=o.auto_task;o:setEnabled(false)
    equal(scheduled[pending],nil);equal(#o.labels,0);equal(o.enabled,false)
    o:onPageUpdate();equal(o.auto_task,nil)
end)
test("suspend and close cancel automatic work; resume re-arms when enabled",function()
    local o=instance();o:setEnabled(true);local first=o.auto_task
    o:onSuspend();equal(scheduled[first],nil);equal(o.auto_task,nil)
    o:onResume();assert(o.auto_task);local second=o.auto_task
    o:onCloseDocument();equal(scheduled[second],nil);equal(o.auto_task,nil)
end)
test("rapid page turns leave one task and process only the final page",function()
    local o=instance();o:setEnabled(true)
    for i=1,12 do o:onPageUpdate() end
    local count=0;for _ in pairs(scheduled) do count=count+1 end
    equal(count,1);equal(#snapshots,0)
    o.auto_task();equal(#snapshots,1);equal(#o.labels,1)
end)
test("disabling during recognition discards its in-flight result",function()
    local o=instance();o:setEnabled(true)
    invalidate_in_scan=function() o:setEnabled(false) end
    o.auto_task();equal(#o.labels,0);equal(o.enabled,false);equal(o.auto_task,nil)
    equal(o.busy,false)
end)
test("capture excludes both bubbles and the reading button",function()
    local o=instance();o.ui.view.paintTo=function() equal(o.capturing,true) end
    o:runScan();equal(o.capturing,false)
end)
test("reading button paints text only without background or border",function()
    local o=instance();local rect=o:buttonRect();local count=0
    o.button_text.paintTo=function() count=count+1 end
    o:paintTo({paintRoundedRect=function() error("unexpected background") end,
        paintBorder=function() error("unexpected border") end},0,0)
    equal(count,1)
    local after=o:buttonRect();equal(rect.x,after.x);equal(rect.y,after.y)
    equal(rect.w,after.w);equal(rect.h,after.h)
end)
test("gesture options reuse the native editor and preserve existing assignments",function()
    local o=instance();local edited
    o.ui.gestures={genMenu=function(_,id) edited=id;return {} end}
    local choices=o:gestureMenu();equal(#choices,4)
    choices[2].sub_item_table_func();equal(edited,"two_finger_tap_bottom_right_corner")
end)
test("hint paints only overbrace strokes without a bubble background or border",function()
    local o=instance();o.show_button=false;o:runScan()
    local rounded,border,rows=0,0,0
    o:paintTo({paintRoundedRect=function() rounded=rounded+1 end,
        paintBorder=function(_,x,y,w,h,bw,c,r) assert(r>0);border=border+1 end,
        paintRect=function(_,x,y,w,h)
            local label=o.labels[1]
            assert(y>=label.y and y+h<=label.y+label.h)
            rows=rows+1
        end},0,0)
    equal(rounded,0);equal(border,0);assert(rows>0)
end)
test("font never shrinks below readable minimum or covers text",function()
    local o=instance()
    o:layoutHints({hint(100,100,nil,2)},
        {{x0=0,y0=50,x1=300,y1=80},{x0=0,y0=100,x1=300,y1=120}})
    equal(#o.labels,0);equal(o.visible,false)
end)
test("rendering error releases snapshot and clears busy flag",function()
    local o=instance();o.view.paintTo=function() error("render error") end
    o:onWordWiseScan();equal(o.busy,false);equal(snapshots[1].freed,true);equal(#notices,1)
end)
test("busy scan ignores another scan request",function()
    local o=instance();o.busy=true;o:onWordWiseScan();equal(#snapshots,0)
end)
test("queued scan is discarded if reader closed before next UI tick",function()
    local o=instance();local pending
    manager.nextTick=function(_,fn) pending=fn end
    o:onWordWiseScan();o:onCloseDocument();pending()
    equal(#snapshots,0);equal(o.busy,false)
    manager.nextTick=function(_,fn) fn() end
end)
test("cancelled rescan clears previous page status",function()
    local o=instance();o:runScan();assert(o.status)
    cancel_scan=true;o:runScan();equal(o.status,nil)
end)
test("EPUB re-layout during capture binds the final rendered page",function()
    local o=instance();o.view.paintTo=function() o:onViewRecalculate() end
    o:runScan();equal(#o.labels,1)
end)
print(string.format("%d passed, %d failed",passed,failed))
os.exit(failed==0 and 0 or 1)
