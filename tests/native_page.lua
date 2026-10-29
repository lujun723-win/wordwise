-- Native integration: actual KOReader OCR, sdcv, fonts and plugin drawing.
-- Run in an isolated KO_HOME with SDL's dummy video driver, not the user's UI.
require("setupkoenv")
local root, source, output = assert(arg[1]), assert(arg[2]), assert(arg[3])
package.path = root .. "/wordwise.koplugin/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(os.getenv("KO_HOME") .. "/settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
local BB, Pic = require("ffi/blitbuffer"), require("ffi/pic")
local Core, OCR = require("wordwise_core"), require("wordwise_ocr")
local JSON, util = require("json"), require("util")
local WordWise = assert(loadfile(root .. "/wordwise.koplugin/main.lua"))()
local doc = Pic.openPNGDocument(source)
assert(Device.screen:getWidth() == doc.width and Device.screen:getHeight() == doc.height - 56)
local gray = BB.new(doc.width, doc.height - 56, BB.TYPE_BB8)
gray:blitFrom(doc.image_bb, 0, 0, 0, 56, gray:getWidth(), gray:getHeight())
doc:close()
local recognized = OCR.recognize(gray, root .. "/wordwise.koplugin/models", Device.screen:getDPI())
local records = Core.readLevels(root .. "/wordwise.koplugin/data/levels.tsv")
local hints = Core.select(recognized.words, records, 0, nil)
local args = {"./sdcv", "--utf8-input", "--utf8-output", "--json-output", "--non-interactive",
    "--only-data-dir", "--data-dir", root .. "/wordwise.koplugin/data/dict",
    "--use-dict", Core.dictionary_name, "--exact-search", "--"}
for _, hint in ipairs(hints) do args[#args + 1] = hint.word end
local pipe = assert(io.popen(util.shell_escape(args)))
local results = {}
for line in pipe:lines() do results[#results + 1] = JSON.decode(line) end
assert(pipe:close())
hints = Core.definitions(hints, results)
local o = setmetatable({font_size=8, limit=30, labels={},
    ui={dialog=require("ui/widget/container/widgetcontainer"):new{}}}, {__index=WordWise})
-- First isolate the reported six words to test the actual omission bug.
-- The production page cap is a separate constraint; don't pretend every
-- eligible word must be selected when a page contains more than twenty.
local wanted = {inspired=true,accomplishes=true,established=true,
    nomenclature=true,significantly=true,intact=true}
local regression = {}
for _, hint in ipairs(hints) do
    if wanted[hint.word] then regression[#regression+1]=hint end
end
assert(#regression==6, "reported words missing before layout")
o:layoutHints(regression,recognized.lines)
assert(#o.labels==6, "reported words cannot fit their actual line gaps")
local production = {}
for _, hint in ipairs(hints) do
    if hint.level >= 2 then production[#production+1]=hint end
end
hints = production
o:layoutHints(hints, recognized.lines)
local shown, report = {}, {}
for _, label in ipairs(o.labels) do
    assert(label.widget.face.orig_size == 8, "inconsistent font size")
    assert(label.hint.word ~= "what's", "A1 contraction cannot enter B1 hints")
    assert(label.brace_h > 0 and label.brace_x0==label.hint.x0 and label.brace_x1==label.hint.x1)
    shown[label.hint.word] = true
    for _, line in ipairs(recognized.lines) do
        assert(not Core.intersects(label, {x=line.x0,y=line.y0,w=line.x1-line.x0,h=line.y1-line.y0}),
            "label overlaps text: " .. label.hint.word)
    end
    report[#report + 1] = {word=label.hint.word, level=label.hint.level,
        gloss=label.hint.gloss, x=label.x,y=label.y,w=label.w,h=label.h,
        font=label.widget.face.orig_size}
end
assert(#o.labels <= 30)
o:paintTo(gray,0,0)
assert(gray:writePNG(output .. ".png"))
gray:free()
local file = assert(io.open(output .. ".json", "w"))
file:write(JSON.encode({status=o.status, labels=report}));file:close()
o:releaseLabels()
print("1 passed, 0 failed; " .. #report .. " labels; " .. output .. ".png")
