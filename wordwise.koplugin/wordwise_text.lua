-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Read source text before OCR. Pixel bounds measure ink only, never spelling.
local ffi = require("ffi")
local Text = {}

local function inside(rect, width, height)
    return rect.x >= 0 and rect.y >= 0 and rect.w > 0 and rect.h > 0
        and rect.x + rect.w <= width and rect.y + rect.h <= height
end

function Text.inkBounds(gray, rect)
    local left, top = math.max(0, math.floor(rect.x)), math.max(0, math.floor(rect.y))
    local right = math.min(gray:getWidth(), math.ceil(rect.x + rect.w))
    local bottom = math.min(gray:getHeight(), math.ceil(rect.y + rect.h))
    local x0, y0, x1, y1 = right, bottom, left, top
    local data = ffi.cast("uint8_t*", gray.data)
    -- The canonical BB8 is before screen inversion. Non-white backgrounds are
    -- deliberately treated as occupied, never guessed away to make labels fit.
    for y = top, bottom - 1 do
        local row = data + y * gray.stride
        for x = left, right - 1 do
            if row[x] < 255 then
                x0, y0 = math.min(x0, x), math.min(y0, y)
                x1, y1 = math.max(x1, x + 1), math.max(y1, y + 1)
            end
        end
    end
    if x1 > x0 and y1 > y0 then return {x0=x0,y0=y0,x1=x1,y1=y1} end
end

local function rolling(document, gray)
    local width, height = gray:getWidth(), gray:getHeight()
    local range = document:getTextFromPositions({x=0,y=0}, {x=width-1,y=height-1}, true)
    if not range or not range.text or not range.text:find("%S") then return nil end
    assert(range.pos0 and range.pos1 and range.sboxes, "原文缺少页面范围。")
    local lines, line_ids = {}, {}
    for i, rect in ipairs(range.sboxes) do
        local ink = Text.inkBounds(gray, rect)
        if ink then lines[#lines+1]=ink;line_ids[i]=#lines end
    end
    local tokens, start = {}, range.pos0
    while start and document:compareXPointers(start, range.pos1) == 1 do
        local ending = document:getNextVisibleWordEnd(start)
        if not ending then break end
        assert(document:compareXPointers(start, ending) == 1, "原文词边界未前进。")
        if document:compareXPointers(ending, range.pos1) == -1 then break end
        local previous = tokens[#tokens]
        local separator = previous and document:getTextFromXPointers(previous.ending, start)
        -- Native visible-word boundaries split apostrophes and hyphens. Join
        -- only these literal separators read from the original document.
        if separator == "'" or separator == "’" or separator == "-" then
            previous.ending = ending
        else
            tokens[#tokens+1] = {start=start,ending=ending}
        end
        local next_start = document:getNextVisibleWordStart(ending)
        assert(not next_start or document:compareXPointers(start, next_start) == 1,
            "原文词边界循环。")
        start = next_start
    end
    local words = {}
    for _, token in ipairs(tokens) do
        local text = document:getTextFromXPointers(token.start, token.ending)
        local boxes = document:getScreenBoxesFromPositions(token.start, token.ending, true)
        for _, rect in ipairs(boxes) do
            if inside(rect, width, height) then
                local ink = Text.inkBounds(gray, rect)
                if ink then
                    local cx, cy = rect.x + rect.w/2, rect.y + rect.h/2
                    local line_id
                    for i, line in ipairs(range.sboxes) do
                        if cx >= line.x and cx < line.x+line.w
                            and cy >= line.y and cy < line.y+line.h then
                            assert(not line_id, "原文屏幕行范围重叠。")
                            line_id = line_ids[i]
                        end
                    end
                    assert(line_id, "原文词不属于当前页面行。")
                    ink.text, ink.line_id = text, line_id
                    words[#words+1] = ink
                    break -- A hyphenated source word is hinted once, at its first visible fragment.
                end
            end
        end
    end
    return {words=words,lines=lines,source="原文"}
end

local function paged(document, view, gray)
    if not document.getPageTextBoxes then return nil end -- Image-only document provider.
    local width, height = gray:getWidth(), gray:getHeight()
    local words, lines, has_text = {}, {}, false
    for _, page in ipairs(view:getCurrentPageList()) do
        -- Do NOT use getTextBoxes: that interface can run its own OCR.
        for _, line in ipairs(document:getPageTextBoxes(page) or {}) do
            local tokens = {}
            for _, box in ipairs(line) do
                local previous = tokens[#tokens]
                local ends_separator = previous and (previous.word:sub(-1) == "'"
                    or previous.word:sub(-3) == "’" or previous.word:sub(-1) == "-")
                local is_separator = box.word == "'" or box.word == "’" or box.word == "-"
                -- MuPDF can split an apostrophe and its suffix into adjacent
                -- spans. Join only exact touching source boxes and punctuation;
                -- a real geometric space is never erased.
                if previous and previous.x1 == box.x0 and previous.y0 == box.y0
                    and previous.y1 == box.y1 and (ends_separator or is_separator) then
                    previous.word = previous.word .. box.word
                    previous.x1 = box.x1
                else
                    tokens[#tokens+1] = {word=box.word,x0=box.x0,y0=box.y0,x1=box.x1,y1=box.y1}
                end
            end
            local line_words, bounds = {}, nil
            for _, box in ipairs(tokens) do
                if box.word and box.word:find("%S") then
                    has_text = true
                    local rect = document:nativeToPageRectTransform(page, {
                        x=box.x0,y=box.y0,w=box.x1-box.x0,h=box.y1-box.y0})
                    rect = rect and view:pageToScreenTransform(page, rect)
                    if rect then
                        local ink = Text.inkBounds(gray, rect)
                        if ink then
                            if not bounds then
                                bounds = {x0=ink.x0,y0=ink.y0,x1=ink.x1,y1=ink.y1}
                            else
                                bounds.x0, bounds.y0 = math.min(bounds.x0,ink.x0), math.min(bounds.y0,ink.y0)
                                bounds.x1, bounds.y1 = math.max(bounds.x1,ink.x1), math.max(bounds.y1,ink.y1)
                            end
                            if inside(rect,width,height) then
                                ink.text = box.word;line_words[#line_words+1]=ink
                            end
                        end
                    end
                end
            end
            if bounds then
                lines[#lines+1]=bounds
                for _, word in ipairs(line_words) do
                    word.line_id=#lines;words[#words+1]=word
                end
            end
        end
    end
    if has_text then return {words=words,lines=lines,source="原文"} end
    return nil -- No text layer on these visible pages: use the declared scan/OCR path.
end

function Text.extract(document, view, gray)
    assert(document and document.info, "阅读器缺少当前文档。")
    if document.info.has_pages then return paged(document,view,gray) end
    return rolling(document,gray)
end

return Text
