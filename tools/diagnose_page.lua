-- Run from the official KOReader bundle with its own LuaJIT and native libs.
require("setupkoenv")
local root, image = assert(arg[1]), assert(arg[2])
package.path = root .. "/wordwise.koplugin/?.lua;" .. package.path
local BB = require("ffi/blitbuffer")
local Pic = require("ffi/pic")
local Core = require("wordwise_core")
local OCR = require("wordwise_ocr")
local doc = Pic.openPNGDocument(image)
-- The supplied macOS screenshot has a 56-pixel title bar.
local gray = BB.new(doc.width, doc.height - 56, BB.TYPE_BB8)
gray:blitFrom(doc.image_bb, 0, 0, 0, 56, gray:getWidth(), gray:getHeight())
local result = OCR.recognize(gray, root .. "/wordwise.koplugin/models", 160)
gray:free()
doc:close()
local records = Core.readLevels(root .. "/wordwise.koplugin/data/levels.tsv")
print("OCR words: " .. #result.words .. ", rows: " .. #result.lines)
for _, word in ipairs(result.words) do
    local key = Core.normalize(word.text)
    local record = key and records[key]
    print(string.format("%s\t%s\t%d,%d,%d,%d", word.text,
        record and (Core.levels[record.level + 1] or "未分级") or "非常用词",
        word.x0, word.y0, word.x1, word.y1))
end
print("Selected at senior high threshold:")
for _, hint in ipairs(Core.select(result.words, records, 2, nil, true)) do
    print(hint.word .. "\t" .. (Core.levels[hint.level + 1] or "未分级"))
end
