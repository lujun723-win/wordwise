require("setupkoenv")
local root=assert(arg[1])
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):open(os.getenv("KO_HOME").."/settings.reader.lua")
local Device=require("device")
require("document/canvascontext"):init(Device)
local d=require("document/documentregistry"):openDocument(root.."/tests/fixtures/text-source.html")
d:setupDefaultView();d:setFontSize(44);d:setInterlineSpacePercent(160)
assert(d:loadDocument());d:render();d:gotoPage(1)
local JSON=require("json")
local range=assert(d:getTextFromPositions({x=0,y=0},{x=1199,y=1599},true))
print("RANGE",JSON.encode(range))
local start=range.pos0
for i=1,100 do
    local cmp=d:compareXPointers(start,range.pos1)
    if not cmp or cmp<=0 then break end
    local ending=assert(d:getNextVisibleWordEnd(start))
    local text=d:getTextFromXPointers(start,ending)
    local boxes=d:getScreenBoxesFromPositions(start,ending,true)
    print(i,text,start,ending,JSON.encode(boxes))
    local nextword=d:getNextVisibleWordStart(ending)
    if not nextword then break end
    assert(d:compareXPointers(start,nextword)==1)
    start=nextword
end
d:close()
