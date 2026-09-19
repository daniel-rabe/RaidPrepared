-- FCKAFD - Travel/Season.lua
-- Which dungeon ports belong to the current Mythic+ season.
--
-- There is no API linking a teleport spell to a challenge map, so the link is
-- the dungeon name: C_ChallengeMode.GetMapTable gives this season's maps, and a
-- port already knows its destination (pulled from the spell description).
-- Matching is exact-or-containment on the alphanumeric-only form, which handles
-- split dungeons like "Operation: Mechagon - Workshop" against a single
-- "Operation: Mechagon" port.

local _, RP = ...
local T = RP.Travel

T.Season = T.Season or {}
local Season = T.Season

local cache = nil

-- Below this length, containment matching starts producing false positives.
local MIN_KEY_LENGTH = 6

---Reduce a name to lowercase alphanumerics: "Ara-Kara, City of Echoes" ->
---"arakaracityofechoes". Punctuation differs between the two data sources.
local function Key(s)
    if not s or s == "" then
        return ""
    end
    local out = {}
    for word in s:lower():gmatch("%w+") do
        out[#out + 1] = word
    end
    return table.concat(out)
end
Season.Key = Key

---This season's challenge maps as { id, name, key }.
function Season.CurrentMaps()
    if cache then
        return cache
    end

    local maps = {}
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapUIInfo) then
        return maps
    end

    local okTable, ids = pcall(C_ChallengeMode.GetMapTable)
    if not okTable or type(ids) ~= "table" then
        return maps
    end

    for _, id in ipairs(ids) do
        local okInfo, name = pcall(C_ChallengeMode.GetMapUIInfo, id)
        if okInfo and name and name ~= "" then
            maps[#maps + 1] = { id = id, name = name, key = Key(name) }
        end
    end

    -- Only cache a populated answer; an empty table usually means the client
    -- has not received map data yet.
    if #maps > 0 then
        cache = maps
    end
    return maps
end

function Season.Invalidate()
    cache = nil
end

---Whether a travel option is this season's port for the given map.
function Season.Matches(map, opt)
    local key = Key(opt.display or opt.name)
    if #key < MIN_KEY_LENGTH or #map.key < MIN_KEY_LENGTH then
        return false
    end
    return map.key == key
        or map.key:find(key, 1, true) ~= nil
        or key:find(map.key, 1, true) ~= nil
end

---Whether this option is a dungeon port in the current season.
function Season.IsCurrent(opt)
    if not opt or opt.cat ~= "dungeon" then
        return false
    end
    local maps = Season.CurrentMaps()
    for i = 1, #maps do
        if Season.Matches(maps[i], opt) then
            return true
        end
    end
    return false
end

---Report each current-season map and the port that serves it, so a name
---mismatch is visible rather than a silently missing button.
function Season.Report()
    local maps = Season.CurrentMaps()
    if #maps == 0 then
        T:Out("|cffff4040No current-season maps returned.|r C_ChallengeMode has no data yet - open the group finder once, then retry.")
        return
    end

    local options = T.Collector.Get()
    local have = 0

    for _, map in ipairs(maps) do
        local match
        for _, opt in ipairs(options) do
            if opt.cat == "dungeon" and Season.Matches(map, opt) then
                match = opt.display or opt.name
                break
            end
        end
        if match then
            have = have + 1
            T:Out("%s  ->  %s", map.name, match)
        else
            T:Out("%s  ->  |cffff4040no port available|r", map.name)
        end
    end

    T:Out("season: %d of %d current maps have a port you can use.", have, #maps)
end

-- Map data arrives asynchronously and changes when a season rolls over.
T:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", Season.Invalidate)
T:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    Season.Invalidate()
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then
        pcall(C_MythicPlus.RequestMapInfo)
    end
end)
