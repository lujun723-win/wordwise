-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Measure the actual rendered glyphs, not the UI font's line-height leading.
local Blitbuffer = require("ffi/blitbuffer")
local Text = require("wordwise_text")
local TextWidget = require("ui/widget/textwidget")
local Label = {}

function Label.new(gloss, face)
    local widget = TextWidget:new{text=gloss,face=face,padding=0}
    local size = widget:getSize()
    local margin = math.ceil(face.size)
    local bitmap = Blitbuffer.new(size.w+2*margin,size.h+2*margin,Blitbuffer.TYPE_BB8)
    bitmap:paintRect(0,0,bitmap:getWidth(),bitmap:getHeight(),Blitbuffer.COLOR_WHITE)
    local ok, ink = pcall(function()
        widget:paintTo(bitmap,margin,margin)
        return assert(Text.inkBounds(bitmap,{x=0,y=0,w=bitmap:getWidth(),h=bitmap:getHeight()}),
            "释义没有可显示的字迹。")
    end)
    widget:free()
    if not ok then bitmap:free();error(ink) end
    return setmetatable({face=face,bitmap=bitmap,ink=ink}, {__index=Label})
end

function Label:getSize() return {w=self.ink.x1-self.ink.x0,h=self.ink.y1-self.ink.y0} end
function Label:paintTo(bb,x,y)
    local size = self:getSize()
    bb:blitFrom(self.bitmap,x,y,self.ink.x0,self.ink.y0,size.w,size.h)
end
function Label:free() self.bitmap:free() end
return Label
