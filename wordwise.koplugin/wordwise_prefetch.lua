-- SPDX-License-Identifier: AGPL-3.0-or-later
-- A fork owns its document cursor. No reader events, widgets or screen refreshes.
local JSON = require("json")
local ffi = require("ffi")
local ffiutil = require("ffi/util")
local UIManager = require("ui/uimanager")
local Core = require("wordwise_core")
local Prefetch = {}

function Prefetch.prepare(owner, pages)
    local BB = require("ffi/blitbuffer")
    local Text = require("wordwise_text")
    local util = require("util")
    local document, view = owner.ui.document, owner.view
    -- CRe's inherited progress callback can write directly to Screen on long
    -- chapter renders. Disable it in this child; the parent's callback stays.
    document:setCallback()
    local result = {}
    for _, page in ipairs(pages) do
        view.state.page = page
        local gray = BB.new(require("device").screen:getWidth(), require("device").screen:getHeight(), BB.TYPE_BB8)
        gray:paintRect(0,0,gray:getWidth(),gray:getHeight(),BB.COLOR_WHITE)
        local ok, data = xpcall(function()
            view:drawPageView(gray,0,0)
            local extracted = Text.extract(document,view,gray)
            if not extracted then
                extracted = require("wordwise_ocr").recognize(gray,owner.path.."/models",require("device").screen:getDPI())
                extracted.source = "截图 OCR"
            end
            local words, protected = owner.names:filter(extracted.words)
            local hints = Core.select(words,owner.records,owner.threshold,nil)
            if #hints>0 then
                local args={"./sdcv","--utf8-input","--utf8-output","--json-output","--non-interactive",
                    "--only-data-dir","--data-dir",owner.path.."/data/dict","--use-dict",Core.dictionary_name,
                    "--exact-search","--"}
                for _, hint in ipairs(hints) do args[#args+1]=hint.word end
                local pipe=assert(io.popen(util.shell_escape(args)),"无法启动离线词典。")
                local output=pipe:read("*a")
                assert(pipe:close(),"离线词典查询失败。")
                local definitions={}
                for line in output:gmatch("[^\r\n]+") do definitions[#definitions+1]=JSON.decode(line) end
                hints=Core.definitions(hints,definitions)
            end
            return {page=page,hints=hints,lines=extracted.lines,source=extracted.source,protected=protected}
        end,debug.traceback)
        gray:free()
        if not ok then error(data) end
        result[#result+1]=data
    end
    return result
end

function Prefetch.start(task, on_result, on_error)
    local job={}
    local pid, fd=ffiutil.runInSubProcess(function(_,write_fd)
        local ok, result=xpcall(task,debug.traceback)
        assert(ffiutil.writeToFD(write_fd,JSON.encode({ok=ok,result=result}),true),"预处理结果写入失败。")
    end,true)
    assert(pid and fd,"无法启动页内提示预处理。")
    function job:cancel()
        if not pid then return end
        UIManager:unschedule(self.poll)
        -- Signal both: cancellation can arrive before the forked child has
        -- created its process group. The unreaped PID cannot be reused yet.
        ffi.C.kill(-pid,9)
        ffi.C.kill(pid,9)
        ffiutil.isSubProcessDone(pid,true)
        ffi.C.close(fd)
        pid,fd=nil,nil
    end
    job.poll=function()
        local done=ffiutil.isSubProcessDone(pid)
        local available=assert(ffiutil.getNonBlockingReadSize(fd),"不支持后台预处理管道。")
        if done or available>0 then
            -- The worker writes only after all pages are ready, then exits.
            local data=ffiutil.readAllFromFD(fd)
            ffiutil.isSubProcessDone(pid,true)
            pid,fd=nil,nil
            local ok,result=pcall(JSON.decode,data)
            if not ok or type(result)~="table" then on_error("页内提示预处理未返回有效结果。")
            elseif not result.ok then on_error(result.result)
            else
                local accepted,err=xpcall(function() on_result(result.result) end,debug.traceback)
                if not accepted then on_error(err) end
            end
        else
            UIManager:scheduleIn(0.05,job.poll)
        end
    end
    UIManager:scheduleIn(0.05,job.poll)
    return job
end

return Prefetch
