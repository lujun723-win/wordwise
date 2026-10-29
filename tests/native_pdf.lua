-- Generate a self-owned PDF fixture, then use the real MuPDF text layer.
require("setupkoenv")
local root,output=assert(arg[1]),assert(arg[2])
package.path=root.."/wordwise.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):open(os.getenv("KO_HOME").."/settings.reader.lua")
local Device=require("device")
require("document/canvascontext"):init(Device)
local BB,Geom=require("ffi/blitbuffer"),require("ui/geometry")
local Text,Core=require("wordwise_text"),require("wordwise_core")
local stream="BT /F1 32 Tf 50 1450 Td (it was before. What's beyond Lean? inspired intact nomenclature.) Tj ET\n"
local objects={
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1200 1600] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Length "..#stream.." >>\nstream\n"..stream.."endstream",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1200 1600] /Resources << >> /Contents 7 0 R >>",
    "<< /Length 0 >>\nstream\nendstream",
}
local pdf,offsets="%PDF-1.4\n",{}
for i,object in ipairs(objects) do
    offsets[i]=#pdf
    pdf=pdf..i.." 0 obj\n"..object.."\nendobj\n"
end
local xref=#pdf
pdf=pdf.."xref\n0 "..(#objects+1).."\n0000000000 65535 f \n"
for _,offset in ipairs(offsets) do pdf=pdf..string.format("%010d 00000 n \n",offset) end
pdf=pdf.."trailer\n<< /Size "..(#objects+1).." /Root 1 0 R >>\nstartxref\n"..xref.."\n%%EOF\n"
local path=output.."-fixture.pdf"
local file=assert(io.open(path,"wb"));file:write(pdf);file:close()
local doc=require("document/documentregistry"):openDocument(path)
local View=require("apps/reader/modules/readerview")
local view=setmetatable({document=doc,ui={paging=true},page_scroll=false,
    state={page=1,zoom=1,rotation=0,offset=Geom:new{x=0,y=0}},
    visible_area=Geom:new{x=0,y=0,w=1200,h=1600}},{__index=View})
local gray=BB.new(1200,1600,BB.TYPE_BB8)
doc:drawPage(gray,0,0,view.visible_area,1,1,0,1,1)
local result=assert(Text.extract(doc,view,gray))
local seen={}
for _,word in ipairs(result.words) do seen[Core.normalize(word.text) or word.text]=true end
assert(seen.it and seen.was and seen.before and seen["what's"] and seen.nomenclature,
    require("json").encode({seen=seen,source=result.words,boxes=doc:getPageTextBoxes(1)}))
assert(not seen.itwa and not seen.itwas)
assert(#result.lines==1,"one-line PDF must still use its text layer")
assert(gray:writePNG(output..".png"))
view.state.page=2
assert(Text.extract(doc,view,gray)==nil,"blank PDF page must select OCR, not fake text")
gray:free();doc:close()
print("1 passed, 0 failed; native PDF text + blank-page classification")
