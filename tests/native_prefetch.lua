-- Actual fork, pipe, error propagation and cancellation; no reader input trap.
require("setupkoenv")
local root=assert(arg[1])
package.path=root.."/wordwise.koplugin/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):open(os.getenv("KO_HOME").."/settings.reader.lua")
local UIManager=require("ui/uimanager")
local Prefetch=require("wordwise_prefetch")
local ffiutil=require("ffi/util")
local expected=string.rep("abc",100000)
local passed=0
local function failure(err) error(err) end
UIManager:show(require("ui/widget/container/widgetcontainer"):new{})
Prefetch.start(function() return {text=expected} end,function(result)
    assert(result.text==expected,"large pipe response truncated")
    passed=passed+1
    Prefetch.start(function() error("explicit-worker-failure") end,function() error("worker error accepted") end,function(err)
        assert(err:find("explicit-worker-failure",1,true))
        passed=passed+1
        local invoked=false
        local job=Prefetch.start(function() require("ffi").C.sleep(2);return true end,
            function() invoked=true end,function() invoked=true end)
        local started=require("ui/time").now()
        job:cancel()
        assert(require("ui/time").now()-started<require("ui/time").s(0.5),"cancellation blocked on the child's setup race")
        UIManager:scheduleIn(0.1,function()
            assert(not invoked,"cancelled worker delivered a result")
            passed=passed+1
            print(passed.." passed, 0 failed; actual fork transport, failure and cancellation")
            UIManager:quit()
        end)
    end)
end,failure)
UIManager:run()
