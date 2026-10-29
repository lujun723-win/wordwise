-- SPDX-License-Identifier: AGPL-3.0-or-later AND MIT
-- Averaged perceptron inference ported from nltk/tag/perceptron.py.
-- Copyright 2013 Matthew Honnibal; NLTK modifications Copyright 2015 NLTK.
-- The bundled MIT model distinguishes proper nouns in context, not PERSON entities.
local JSON = require("json")
local Names = {}
Names.__index = Names

local function read(path)
    local file=assert(io.open(path,"rb"),"缺少离线专名模型，请安装完整插件包。")
    local data=file:read("*a");file:close()
    return JSON.decode(data)
end

function Names.load(path)
    local prefix=path.."/averaged_perceptron_tagger_eng."
    return setmetatable({weights=read(prefix.."weights.json"),classes=read(prefix.."classes.json"),
        tagdict=read(prefix.."tagdict.json")},Names)
end

local function normalize(word)
    if word:find("-",1,true) and word:sub(1,1)~="-" then return "!HYPHEN" end
    if word:match("^%d%d%d%d$") then return "!YEAR" end
    if word:match("^%d") then return "!DIGITS" end
    return word:lower()
end

function Names:tag(tokens)
    local context={"-START-","-START2-"}
    for _,word in ipairs(tokens) do context[#context+1]=normalize(word) end
    context[#context+1]="-END-";context[#context+1]="-END2-"
    local tags,prev,prev2={},"-START-","-START2-"
    for index,word in ipairs(tokens) do
        local tag=self.tagdict[word]
        if not tag then
            local i=index+2
            local features={"bias","i suffix "..word:sub(-3),"i pref1 "..word:sub(1,1),
                "i-1 tag "..prev,"i-2 tag "..prev2,"i tag+i-2 tag "..prev.." "..prev2,
                "i word "..context[i],"i-1 tag+i word "..prev.." "..context[i],
                "i-1 word "..context[i-1],"i-1 suffix "..context[i-1]:sub(-3),
                "i-2 word "..context[i-2],"i+1 word "..context[i+1],
                "i+1 suffix "..context[i+1]:sub(-3),"i+2 word "..context[i+2]}
            local scores={}
            for _,feature in ipairs(features) do
                for label,weight in pairs(self.weights[feature] or {}) do
                    scores[label]=(scores[label] or 0)+weight
                end
            end
            local best=-math.huge
            for _,label in ipairs(self.classes) do
                local score=scores[label] or 0
                if score>best or (score==best and (not tag or label>tag)) then best,tag=score,label end
            end
            assert(tag,"专名模型没有输出词性。")
        end
        tags[index]=tag;prev2,prev=prev,tag
    end
    return tags
end

-- Punctuation is tokenized without changing spelling. Possessive 's shares
-- its source occurrence with the base, so James's can be protected as a name.
function Names.tokens(words)
    local tokens,owners={},{}
    local function add(token,index) tokens[#tokens+1]=token;owners[#owners+1]=index end
    for index,occurrence in ipairs(words) do
        local raw=occurrence.text:gsub("’","'")
        local i=1
        while i<=#raw do
            local ch=raw:sub(i,i)
            if ch:match("[%a%d]") then
                local start=i;i=i+1
                while i<=#raw do
                    local c=raw:sub(i,i)
                    if c:match("[%a%d]") or ((c=="'" or c=="-") and raw:sub(i+1,i+1):match("%a")) then
                        i=i+1
                    else break end
                end
                local word=raw:sub(start,i-1)
                local base=word:match("^(.+)'[sS]$")
                if base then add(base,index);add(word:sub(-2),index) else add(word,index) end
            else
                if ch:match("%p") then add(ch,index) end
                i=i+1
            end
        end
    end
    return tokens,owners
end

function Names:filter(words)
    local tokens,owners=Names.tokens(words)
    local tags=self:tag(tokens)
    local proper={}
    for i,tag in ipairs(tags) do if tag=="NNP" or tag=="NNPS" then proper[owners[i]]=true end end
    local kept,count={},0
    for i,word in ipairs(words) do
        if proper[i] then count=count+1 else kept[#kept+1]=word end
    end
    return kept,count
end
return Names
