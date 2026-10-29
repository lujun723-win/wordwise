require("setupkoenv")
local root,input,output=assert(arg[1]),assert(arg[2]),assert(arg[3])
package.path=root.."/wordwise.koplugin/?.lua;"..package.path
local JSON=require("json")
local file=assert(io.open(input));local cases=JSON.decode(file:read("*a"));file:close()
local Names=require("wordwise_names")
local model=Names.load(root.."/wordwise.koplugin/models/pos")
local results={}
for _,words in ipairs(cases) do
    local occurrences={}
    for _,word in ipairs(words) do occurrences[#occurrences+1]={text=word} end
    local tokens=Names.tokens(occurrences)
    local filtered,count=model:filter(occurrences)
    results[#results+1]={tokens=tokens,tags=model:tag(tokens),kept=filtered,protected=count}
end
file=assert(io.open(output,"w"));file:write(JSON.encode(results));file:close()
