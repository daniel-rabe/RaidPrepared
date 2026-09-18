-- RaidPrepared - Travel/Search.lua
-- Scores the collected travel options against what you typed.
--
-- Every whitespace-separated token in the query must match something (a word in
-- the name, a keyword, or the category label). Tokens score independently and
-- the total decides the order, so "mythic dawn" beats a row that only matches
-- "dawn".

local _, RP = ...
local T = RP.Travel

T.Search = T.Search or {}
local Search = T.Search

-- Score tiers, highest first.
local SCORE_EXACT     = 1000
local SCORE_PREFIX    = 800
local SCORE_WORD      = 600
local SCORE_SUBSTRING = 400
local SCORE_KEYWORD   = 350
local SCORE_DESC      = 300
local SCORE_CATEGORY  = 200
local SCORE_FUZZY     = 100

-- Ranking nudges applied once per option, not per token.
local BONUS_FAVORITE  = 5000
local BONUS_RECENT    = 2000

local ACCENTS = {
    ["\195\164"] = "a", ["\195\182"] = "o", ["\195\188"] = "u", ["\195\159"] = "ss",
    ["\195\132"] = "a", ["\195\150"] = "o", ["\195\156"] = "u",
    ["\195\169"] = "e", ["\195\168"] = "e", ["\195\170"] = "e",
    ["\195\161"] = "a", ["\195\160"] = "a", ["\195\162"] = "a",
    ["\195\173"] = "i", ["\195\179"] = "o", ["\195\186"] = "u",
    ["\195\167"] = "c", ["\195\177"] = "n",
}

---Lowercase and fold accented characters so "Dazar'alor" matches "dazaralor".
function Search.Normalize(s)
    if not s or s == "" then
        return ""
    end
    s = s:lower()
    for from, to in pairs(ACCENTS) do
        s = s:gsub(from, to)
    end
    -- Apostrophes and colons are noise in a search box.
    s = s:gsub("['\226\128\153:,%.]", "")
    return s
end

local Normalize = Search.Normalize

-- Fuzzy matching only earns its place for near-misses and typos. Without a
-- bound on how far the characters are spread, "garr" matches "Path of the
-- BesieGed HARboR" and buries the result you actually wanted.
local FUZZY_MIN_LENGTH = 4
local FUZZY_MAX_SPREAD = 2   -- matched span may be at most 2x the token length

---Size of the smallest window of haystack containing needle as a subsequence,
---or nil when the characters do not all appear in order.
---
---Every starting position is tried rather than just the first: matching
---left-to-right anchors "hearthstn" on the h in "greatfather" and spans the
---whole string, when the real match sits at the end.
local function SubsequenceSpan(needle, haystack)
    local firstChar = needle:sub(1, 1)
    local best
    local start = haystack:find(firstChar, 1, true)

    while start do
        local pos, matched = start, true
        for i = 2, #needle do
            pos = haystack:find(needle:sub(i, i), pos + 1, true)
            if not pos then
                matched = false
                break
            end
        end
        if not matched then
            -- A later start has strictly less to work with, so it fails too.
            break
        end

        local span = pos - start + 1
        if not best or span < best then
            best = span
        end
        start = haystack:find(firstChar, start + 1, true)
    end

    return best
end

---Best score for one query token against one option, or nil when it misses.
local function ScoreToken(token, name, keywords, catLabel, desc)
    if name == token then
        return SCORE_EXACT
    end
    if name:sub(1, #token) == token then
        return SCORE_PREFIX
    end
    -- Word-start match: "dawn" hitting "Teleport: Dawnbreaker".
    if name:find("%f[%w]" .. token:gsub("%W", "%%%0")) then
        return SCORE_WORD
    end
    if name:find(token, 1, true) then
        return SCORE_SUBSTRING
    end

    if keywords then
        for i = 1, #keywords do
            local kw = keywords[i]
            if kw:sub(1, #token) == token then
                return SCORE_KEYWORD
            end
        end
    end

    -- "Path of the Warding Candles" only becomes findable as "darkflame" via
    -- the description, so this tier matters more than its score suggests.
    if desc and desc:find("%f[%w]" .. token:gsub("%W", "%%%0")) then
        return SCORE_DESC
    end

    if catLabel and catLabel:sub(1, #token) == token then
        return SCORE_CATEGORY
    end

    if #token >= FUZZY_MIN_LENGTH then
        local span = SubsequenceSpan(token, name)
        if span and span <= #token * FUZZY_MAX_SPREAD then
            return SCORE_FUZZY
        end
    end

    return nil
end

---Split a query into normalized tokens.
local function Tokenize(query)
    local tokens = {}
    for word in Normalize(query):gmatch("%S+") do
        tokens[#tokens + 1] = word
    end
    return tokens
end

---Filter and rank the available options.
---An empty query returns everything, favourites and recents first.
---@param query string
---@return table results  array of option tables, best match first
function Search.Run(query)
    local options = T.Collector.Get()
    local tokens  = Tokenize(query)
    local db      = T.db
    local results = {}

    for i = 1, #options do
        local opt      = options[i]
        local name     = Normalize(opt.name)
        local catLabel = Normalize(T.L["cat." .. opt.cat])
        local score    = 0
        local matched  = true

        -- Normalizing the description is the expensive part, so cache it on the
        -- option; the collector discards the whole list when data changes.
        local desc = opt.descNorm
        if desc == nil and opt.desc then
            desc = Normalize(opt.desc)
            opt.descNorm = desc
        end

        for t = 1, #tokens do
            local s = ScoreToken(tokens[t], name, opt.keywords, catLabel, desc)
            if not s then
                matched = false
                break
            end
            score = score + s
        end

        if matched then
            if db and db.favorites[opt.key] then
                score = score + BONUS_FAVORITE
            end
            local rank = T:RecentRank(opt.key)
            if rank then
                score = score + BONUS_RECENT - rank
            end

            opt.score = score
            results[#results + 1] = opt
        end
    end

    table.sort(results, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.name < b.name
    end)

    return results
end
