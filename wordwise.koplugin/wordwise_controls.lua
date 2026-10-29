-- SPDX-License-Identifier: AGPL-3.0-or-later
local ButtonDialog = require("ui/widget/buttondialog")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local Core = require("wordwise_core")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalScrollBar = require("ui/widget/horizontalscrollbar")
local Screen = require("device").screen
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalSpan = require("ui/widget/verticalspan")
local Controls = {}

-- Keep KOReader's native tap/drag handling; replace only the bar's drawing.
local DifficultySlider = HorizontalScrollBar:extend{}
function DifficultySlider:paintTo(bb,x,y)
    self.touch_dimen = Geom:new{x=x,y=y-self.extra_touch_on_side,
        w=self.width,h=self.height+2*self.extra_touch_on_side}
    local count = #Core.levels
    local step = self.width/count
    local left, right = math.floor(x+step/2), math.floor(x+self.width-step/2)
    local cy = math.floor(y+self.height/2)
    local thickness, radius = Screen:scaleBySize(2), Screen:scaleBySize(6)
    bb:paintRect(left,cy,right-left+1,thickness,Blitbuffer.COLOR_BLACK)
    for i=0,count-1 do
        bb:paintRect(math.floor(x+step*(i+0.5)),cy-Screen:scaleBySize(12),
            Screen:scaleBySize(1),Screen:scaleBySize(4),Blitbuffer.COLOR_DARK_GRAY)
    end
    local index = self.low*count
    if BD.mirroredUILayout() then index = count-1-index end
    local cx = math.floor(x+step*(index+0.5))
    local centre_y = cy+math.floor(thickness/2)
    bb:paintCircle(cx,centre_y,radius,Blitbuffer.COLOR_WHITE)
    bb:paintCircle(cx,centre_y,radius,Blitbuffer.COLOR_BLACK,Screen:scaleBySize(1))
end

function Controls.show(owner)
    local threshold, enabled = owner.threshold, owner.enabled
    local dialog, slider, level_text, toggle
    dialog = ButtonDialog:new{
        title="生词提示", title_align="center",
        buttons={{
            {text="取消",callback=function() UIManager:close(dialog) end},
            {text="应用",is_enter_default=true,callback=function()
                UIManager:close(dialog)
                owner.threshold = threshold
                owner.settings:saveSetting("threshold",threshold)
                owner:setEnabled(enabled)
            end},
        }},
    }
    local width = dialog:getAddedWidgetAvailableWidth()
    local count = #Core.levels
    level_text = TextWidget:new{text="起点："..Core.levels[threshold+1],face=Font:getFace("cfont",16)}
    level_text.not_focusable = true
    slider = DifficultySlider:new{
        width=width,height=Screen:scaleBySize(32),extra_touch_on_side_heightratio=0.25,
        low=threshold/count,high=(threshold+1)/count,
        scroll_callback=function(ratio)
            threshold = math.max(0,math.min(count-1,math.floor(ratio*count)))
            slider:set(threshold/count,(threshold+1)/count)
            level_text:setText("起点："..Core.levels[threshold+1])
            UIManager:setDirty(dialog,"ui")
        end,
    }
    slider.not_focusable = true
    toggle = CheckButton:new{
        text="开启提示，翻页自动更新",checked=enabled,parent=dialog,width=width,
        callback=function() enabled=toggle.checked end,
    }
    dialog:addWidget(toggle)
    dialog:addWidget(CenterContainer:new{dimen=Geom:new{w=width,h=level_text:getSize().h},
        not_focusable=true,level_text})
    dialog:addWidget(VerticalSpan:new{width=Screen:scaleBySize(16),not_focusable=true})
    dialog:addWidget(slider)
    dialog:addWidget(VerticalSpan:new{width=Screen:scaleBySize(16),not_focusable=true})
    local ticks = HorizontalGroup:new{not_focusable=true}
    for _, text in ipairs(Core.levels) do
        local tick=TextWidget:new{text=text,face=Font:getFace("cfont",12)}
        ticks[#ticks+1]=CenterContainer:new{dimen=Geom:new{w=math.floor(width/count),h=tick:getSize().h},tick}
    end
    dialog:addWidget(ticks)
    local close = dialog.onCloseWidget
    dialog.onCloseWidget = function(this)
        owner.controls = nil
        return close(this)
    end
    UIManager:show(dialog)
    return dialog
end
return Controls
