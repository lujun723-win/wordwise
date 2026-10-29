-- SPDX-License-Identifier: AGPL-3.0-or-later
local Core = {}

Core.dictionary_name = "ReadAssist ECDICT Short"
Core.levels = { "小学", "初中", "高中", "四级", "六级", "未划分等级" }

function Core.normalize(raw)
    local word = raw:gsub("’", "'"):gsub("‘", "'"):gsub("“", '"'):gsub("”", '"')
        :gsub("^[%s%p]+", ""):gsub("[%s%p]+$", ""):lower()
    if #word >= 2 and #word <= 30 and word:match("^[a-z][a-z'-]+$") then
        return word
    end
end

function Core.readLevels(path)
    local file = assert(io.open(path, "r"), "缺少分级词表，请重新安装完整插件包。")
    local content=file:read("*a");file:close()
    local records = {}
    for line in content:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" and line ~= "" then
            local word, level, rank = line:match("^([^\t]+)\t(%d+)\t(%d+)$")
            assert(word and tonumber(level) < #Core.levels, "分级词表格式错误。")
            assert(not records[word], "分级词表有重复词条："..word)
            records[word] = { level = tonumber(level), rank = tonumber(rank) }
        end
    end
    return records
end

function Core.select(words, records, threshold, limit)
    local seen, selected = {}, {}
    for _, occurrence in ipairs(words) do
        local word = Core.normalize(occurrence.text)
        if word and not seen[word] then
            seen[word] = true
            -- Explicit user policy: words outside the 30k common index enter
            -- the unclassified group. Exact dictionary lookup below
            -- must still confirm a real entry; OCR noise is never translated.
            local record = records[word] or {level=5, rank=30001}
            if record.level >= threshold then
                selected[#selected + 1] = {
                    word = word, level = record.level, rank = record.rank,
                    x0 = occurrence.x0, y0 = occurrence.y0,
                    x1 = occurrence.x1, y1 = occurrence.y1,
                    line_id = assert(occurrence.line_id, "OCR 缺少所属行。"),
                }
            end
        end
    end
    return Core.limit(selected, limit)
end

function Core.prioritize(selected)
    table.sort(selected, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.y0 ~= b.y0 then return a.y0 < b.y0 end
        if a.x0 ~= b.x0 then return a.x0 < b.x0 end
        return a.word < b.word
    end)
    return selected
end

function Core.limit(selected, limit)
    Core.prioritize(selected)
    if limit then
        while #selected > limit do table.remove(selected) end
    end
    table.sort(selected, function(a, b)
        if a.y0 ~= b.y0 then return a.y0 < b.y0 end
        return a.x0 < b.x0
    end)
    return selected
end

-- The bundled StarDict contains only curated plain-text short definitions.
-- Reject a different dictionary schema instead of guessing how to strip HTML.
function Core.definitions(hints, results)
    assert(type(results) == "table" and #results == #hints,
        "StarDict 返回结果与查询数量不一致，请检查随包词典。")
    local output = {}
    for i, hint in ipairs(hints) do
        local entries = results[i]
        assert(type(entries) == "table" and #entries <= 1,
            "随包 StarDict 有重复词条：" .. hint.word)
        -- An out-of-common word may be absent from the dictionary. This is an
        -- exact lookup miss, not permission to guess a correction or meaning.
        if #entries == 1 then
            local entry = entries[1]
            assert(entry.dict == Core.dictionary_name and type(entry.definition) == "string",
                "StarDict 词典格式不匹配。")
            -- sdcv prefixes plaintext definitions with a newline.
            local gloss = entry.definition:gsub("^%s+", ""):gsub("%s+$", "")
            assert(gloss ~= "" and not gloss:find("[\r\n\t<>]"), "短释义格式错误：" .. hint.word)
            local item = {}
            for k, v in pairs(hint) do item[k] = v end
            item.gloss = gloss
            output[#output + 1] = item
        end
    end
    return output
end

function Core.intersects(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w
        and a.y < b.y + b.h and b.y < a.y + a.h
end

-- One defined position: centred above the source word. If this space is
-- occupied, omit that label; never move it onto another word or cover text.
function Core.place(hints, lines, width, height, measure, padding, gap, limit, brace_height, obstacles)
    brace_height = brace_height or 0
    local placed, omitted, limited = {}, 0, 0
    local reasons = { line_gap=0, text=0, labels=0, edge=0, controls=0 }
    for i, hint in ipairs(hints) do
        if limit and #placed >= limit then
            limited = #hints - i + 1
            break
        end
        local source = assert(lines[hint.line_id], "OCR 所属行不存在。")
        local previous_bottom = 0
        for _, line in ipairs(lines) do
            if line.y1 <= source.y0 and line.x0 < source.x1 and source.x0 < line.x1 then
                previous_bottom = math.max(previous_bottom, line.y1)
            end
        end
        local available = source.y0 - previous_bottom - gap - 2 * padding - brace_height
        local tw, th, payload = measure(hint.gloss, available)
        if tw then
            local rect = {
                x = math.floor((hint.x0 + hint.x1 - math.max(tw+2*padding,hint.x1-hint.x0)) / 2),
                y = source.y0 - th - 2 * padding - brace_height - gap,
                w = math.max(tw+2*padding,hint.x1-hint.x0), h = th + 2 * padding + brace_height, payload = payload,
                text_x = math.floor((hint.x0+hint.x1-tw)/2),
                text_h = th, brace_h = brace_height,
                brace_x0 = hint.x0, brace_x1 = hint.x1,
                tip_x = math.floor((hint.x0 + hint.x1) / 2),
            }
            local clear = rect.x >= 0 and rect.y >= 0
                and rect.x + rect.w <= width and rect.y + rect.h <= height
            local reason = not clear and "edge"
            if clear then
                for _, line in ipairs(lines) do
                    if Core.intersects(rect, {
                        x = line.x0, y = line.y0,
                        w = line.x1 - line.x0, h = line.y1 - line.y0,
                    }) then clear = false; reason = "text"; break end
                end
            end
            if clear then
                for _, obstacle in ipairs(obstacles or {}) do
                    if Core.intersects(rect, obstacle) then clear = false; reason = "controls"; break end
                end
            end
            if clear then
                for _, previous in ipairs(placed) do
                    if Core.intersects(rect, previous) then clear = false; reason = "labels"; break end
                end
            end
            if clear then
                rect.hint = hint
                placed[#placed + 1] = rect
            else
                omitted = omitted + 1
                reasons[reason] = reasons[reason] + 1
            end
        else
            omitted = omitted + 1
            reasons.line_gap = reasons.line_gap + 1
        end
    end
    return placed, omitted, limited, reasons
end

return Core
