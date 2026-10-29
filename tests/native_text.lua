-- Real CREngine extraction + native rendering + exact StarDict lookup.
require("setupkoenv")
local root,output=assert(arg[1]),assert(arg[2])
package.path=root.."/wordwise.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):open(os.getenv("KO_HOME").."/settings.reader.lua")
local Device=require("device")
require("document/canvascontext"):init(Device)
local BB,Geom=require("ffi/blitbuffer"),require("ui/geometry")
local Text,Core=require("wordwise_text"),require("wordwise_core")
local doc=require("document/documentregistry"):openDocument(root.."/tests/fixtures/text-source.html")
doc:setupDefaultView();doc:setFontSize(44);doc:setInterlineSpacePercent(160)
assert(doc:loadDocument());doc:render();doc:gotoPage(1)
local width,height=Device.screen:getWidth(),Device.screen:getHeight()
local gray=BB.new(width,height,BB.TYPE_BB8)
doc:drawCurrentView(gray,0,0,Geom:new{w=width,h=height})
local result=assert(Text.extract(doc,{},gray))
local seen={}
for _,word in ipairs(result.words) do seen[Core.normalize(word.text) or word.text]=true end
assert(seen.it and seen.was and seen.before and seen["what's"],"source word boundaries changed")
assert(not seen.itwa and not seen.itwas,"source words were merged")
local hints=Core.select(result.words,Core.readLevels(root.."/wordwise.koplugin/data/levels.tsv"),2,nil)
local util,JSON=require("util"),require("json")
local args={"./sdcv","--utf8-input","--utf8-output","--json-output","--non-interactive",
    "--only-data-dir","--data-dir",root.."/wordwise.koplugin/data/dict",
    "--use-dict",Core.dictionary_name,"--exact-search","--"}
for _,hint in ipairs(hints) do args[#args+1]=hint.word;assert(hint.word~="what's") end
local pipe=assert(io.popen(util.shell_escape(args)))
local definitions={}
for line in pipe:lines() do definitions[#definitions+1]=JSON.decode(line) end
assert(pipe:close());hints=Core.definitions(hints,definitions)
local WordWise=assert(loadfile(root.."/wordwise.koplugin/main.lua"))()
local o=setmetatable({font_size=8,limit=30,labels={},source="原文",
    ui={dialog=require("ui/widget/container/widgetcontainer"):new{}}},{__index=WordWise})
o:layoutHints(hints,result.lines)
assert(#o.labels>0,"source text labels could not fit")
local report={}
for _,label in ipairs(o.labels) do
    assert(label.widget.face.orig_size==8)
    assert(label.hint.word~="itwa" and label.hint.word~="itwas" and label.hint.word~="what's")
    for _,line in ipairs(result.lines) do
        assert(not Core.intersects(label,{x=line.x0,y=line.y0,w=line.x1-line.x0,h=line.y1-line.y0}))
    end
    report[#report+1]={word=label.hint.word,gloss=label.hint.gloss,x=label.x,y=label.y,w=label.w,h=label.h}
end
o:paintTo(gray,0,0);assert(gray:writePNG(output..".png"))
local file=assert(io.open(output..".json","w"))
file:write(JSON.encode({status=o.status,words=result.words,lines=result.lines,labels=report}));file:close()
o:releaseLabels();gray:free();doc:close()
print("1 passed, 0 failed; "..#report.." source text labels; "..output..".png")
