-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Uses only functions exported by KOReader 2026.07.1's libk2pdfopt.
local ffi = require("ffi")
local KOPTContext = require("ffi/koptcontext")
local OCR = {}

function OCR.recognize(gray, model_dir, dpi)
    local model = assert(io.open(model_dir .. "/eng.traineddata", "rb"),
        "缺少英文 OCR 模型，请安装完整插件包。")
    model:close()
    local kc = KOPTContext.new()
    local ok, result = xpcall(function()
        -- This module runs in a forked child. Reset any engine inherited from
        -- KOReader so an earlier lookup cannot silently select another model.
        kc:freeOCR()
        local width, height = gray:getWidth(), gray:getHeight()
        kc:setDeviceDPI(dpi)
        kc:setDeviceDim(width, height)
        kc:setLanguage("eng")
        kc:setBBox(0, 0, width, height)
        -- Native WILLUSBITMAP rows are top-down and packed; BlitBuffer may
        -- have an aligned stride. Copy row by row, never copy padding as pixels.
        kc.src.width, kc.src.height, kc.src.bpp = width, height, 8
        assert(KOPTContext.k2pdfopt.bmp_alloc(kc.src) == 1, "OCR 位图分配失败。")
        for i = 0, 255 do
            kc.src.red[i], kc.src.green[i], kc.src.blue[i] = i, i, i
        end
        for y = 0, height - 1 do
            ffi.copy(kc.src.data + y * width, gray.data + y * gray.stride, width)
        end
        local rows = kc:getNativeWordBoxes("src", 0, 0, width, height)
        assert(rows, "OCR 无法分割当前页文本。")
        local words, lines = {}, {}
        for line_id, row in ipairs(rows) do
            lines[#lines + 1] = { x0 = row.x0, y0 = row.y0, x1 = row.x1, y1 = row.y1 }
            for _, box in ipairs(row) do
                assert(box.x0 >= 0 and box.y0 >= 0 and box.x1 <= width
                    and box.y1 <= height and box.x1 > box.x0 and box.y1 > box.y0,
                    "OCR 词框越界。")
                local text = kc:getTOCRWord("src", box.x0, box.y0,
                    box.x1 - box.x0, box.y1 - box.y0, model_dir, "eng", 8, 0, 0, dpi)
                assert(text ~= nil, "英文 OCR 引擎初始化失败，请检查模型。")
                if text ~= "" then
                    words[#words + 1] = {
                        text = text, x0 = box.x0, y0 = box.y0, x1 = box.x1, y1 = box.y1,
                        line_id = line_id,
                    }
                end
            end
        end
        return { words = words, lines = lines }
    end, debug.traceback)
    kc:freeOCR()
    kc:free()
    if not ok then error(result) end
    return result
end

return OCR
