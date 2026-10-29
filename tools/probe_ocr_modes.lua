-- Native diagnostic only. Compare recognition modes on identical source boxes.
require("setupkoenv")
local root, source = assert(arg[1]), assert(arg[2])
local ffi, BB, Pic = require("ffi"), require("ffi/blitbuffer"), require("ffi/pic")
local KOPT = require("ffi/koptcontext")
local doc = Pic.openPNGDocument(source)
local gray = BB.new(doc.width, doc.height - 56, BB.TYPE_BB8)
gray:blitFrom(doc.image_bb,0,0,0,56,gray:getWidth(),gray:getHeight())
doc:close()
local kc = KOPT.new()
kc:freeOCR()
local w,h=gray:getWidth(),gray:getHeight()
kc:setDeviceDPI(160);kc:setDeviceDim(w,h);kc:setLanguage("eng");kc:setBBox(0,0,w,h)
kc.src.width,kc.src.height,kc.src.bpp=w,h,8
assert(KOPT.k2pdfopt.bmp_alloc(kc.src)==1)
for i=0,255 do kc.src.red[i],kc.src.green[i],kc.src.blue[i]=i,i,i end
for y=0,h-1 do ffi.copy(kc.src.data+y*w,gray.data+y*gray.stride,w) end
assert(kc:getTOCRWord("src",50,481,125,33,root.."/wordwise.koplugin/models","eng",8,0,0,160))
kc:setCJKChar(1)
for _,row in ipairs(kc:getNativeWordBoxes("src",0,0,w,h)) do
    for _,box in ipairs(row) do
        local values={}
        for _,mode in ipairs({8}) do
            for _,spaces in ipairs({0}) do
                local text=kc:getTOCRWord("src",box.x0,box.y0,box.x1-box.x0,box.y1-box.y0,
                    root.."/wordwise.koplugin/models","eng",mode,spaces,0,160)
                values[#values+1]=mode.."/"..spaces..":"..tostring(text)
            end
        end
        print(string.format("%d,%d,%d,%d\t%s",box.x0,box.y0,box.x1,box.y1,table.concat(values,"\t")))
    end
end
kc:freeOCR();kc:free();gray:free()
