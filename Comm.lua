local addonName, PR = ...

-- Finds the other PullReady users in the group over the addon message channel, so the
-- inspect list can mark them. Everyone announces themselves after joining a group;
-- whoever hears an announcement answers with one of their own, which is how a player
-- who joins late learns about the users who were already there.

local PREFIX = "PullReady"
local ANNOUNCE_DELAY = 3    -- let the roster settle before announcing
local ANSWER_SPREAD = 5     -- random delay so a whole raid does not answer at once
local ANSWER_COOLDOWN = 15  -- at most one answer per this many seconds

local Comm = {}
PR.Comm = Comm

local users = {}    -- guid -> version string of every known PullReady user
local lastAnswer = 0
local announcing = false
local lastChannel

local function Version()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return (get and get(addonName, "Version")) or "?"
end

-- The addon channel the group is reachable on, or nil when not grouped.
local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function Send(kind)
    local channel = Channel()
    if not channel then return end
    local guid = UnitGUID("player")
    if not guid then return end
    C_ChatInfo.SendAddonMessage(PREFIX, ("%s:%s:%s"):format(kind, guid, Version()), channel)
end

-- HI asks everyone to answer, IAM is such an answer and asks for nothing.
local function Announce()
    if announcing or not Channel() then return end
    announcing = true
    C_Timer.After(ANNOUNCE_DELAY, function()
        announcing = false
        Send("HI")
    end)
end

local function Answer()
    local now = GetTime()
    if now - lastAnswer < ANSWER_COOLDOWN or not Channel() then return end
    lastAnswer = now
    C_Timer.After(math.random() * ANSWER_SPREAD, function() Send("IAM") end)
end

-- The version comes from another client and ends up in a tooltip, so anything that is
-- not a plain version number (UI escape sequences above all) is thrown away.
local function CleanVersion(version)
    return version:match("^[%w%.%-]+$") and version:sub(1, 16) or "?"
end

local function OnMessage(text)
    local kind, guid, version = text:match("^(%u+):([^:]+):(.*)$")
    if not guid or guid == UnitGUID("player") then return end

    if users[guid] == nil then
        users[guid] = CleanVersion(version)
        PR.RaidCheck:Refresh()
    end
    if kind == "HI" then
        Answer()
    end
end

-- Group members are the only ones who can still answer, so everyone else is dropped.
local function PruneUsers()
    local present = { [UnitGUID("player") or ""] = true }
    local prefix, count = IsInRaid() and "raid" or "party", GetNumGroupMembers()
    for i = 1, count do
        local guid = UnitGUID(prefix .. i)
        if guid then present[guid] = true end
    end
    for guid in pairs(users) do
        if not present[guid] then users[guid] = nil end
    end
end

-- Version of the PullReady the member runs, or nil when they are not known to run it.
function Comm:GetVersion(guid)
    if guid == UnitGUID("player") then return Version() end
    return users[guid]
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        lastChannel = Channel()
        Announce() -- covers logging in or reloading while already grouped
    elseif event == "GROUP_ROSTER_UPDATE" then
        PruneUsers()
        local channel = Channel()
        if channel and channel ~= lastChannel then
            Announce() -- joined a group, or the group turned into a raid / instance group
        end
        lastChannel = channel
    elseif arg1 == PREFIX then
        OnMessage(arg2)
    end
end)
