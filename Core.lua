local addonName, RP = ...
local L = RP.L

local PREFIX = "|cff33ccffRaidPrepared|r: "
local RAID_JOIN_DELAY = 2

local DEFAULTS = {
    maxQualityTier = nil, -- nil = RP.DEFAULT_MAX_QUALITY_TIER
    minimap = { hide = false, angle = 225 },
    characterIndicators = true, -- enchant/socket indicators on the character panel
    localizedWhisper = false,   -- false = whisper in whisperLocale (recipient's language is unknown)
    whisperLocale = "enUS",     -- language of Raid Inspect whispers when localizedWhisper is off
    travel = {                  -- fast-travel tab
        closeOnUse = true,
        maxRecent  = 15,
        recent     = {},        -- array of entry keys, most recently used first
        favorites  = {},        -- [entryKey] = true
    },
}

local function Print(msg)
    print(PREFIX .. msg)
end

local function ApplyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(db[key]) ~= "table" then db[key] = {} end
            ApplyDefaults(db[key], value)
        elseif db[key] == nil then
            db[key] = value
        end
    end
end

local function FormatPotionCount(entry)
    local text = ("%s: %d"):format(entry.label, entry.count)
    if entry.activeTime then
        text = text .. " " .. L["(active %dm)"]:format(math.floor(entry.activeTime / 60))
    end
    return text
end

function RP.GetMaxQualityTier()
    return RaidPreparedDB.maxQualityTier or RP.DEFAULT_MAX_QUALITY_TIER
end

function RP.SetMaxQualityTier(tier)
    tier = math.max(RP.MIN_QUALITY_RANK_OPTION, math.min(RP.MAX_QUALITY_RANK_OPTION, math.floor(tier)))
    RaidPreparedDB.maxQualityTier = tier
    RP.CharacterPanel:RequestUpdate()
    return tier
end

-- manual = true: always show the dialog (also when everything is fine).
function RP.RunCheck(manual)
    RP.ScanAsync(function(issues)
        RP.ScanPotionsAsync(function(potions, potionIssues)
            for _, issue in ipairs(potionIssues) do
                issues[#issues + 1] = issue
            end
            local talentIssue = RP.Talents:Check()
            if talentIssue then
                issues[#issues + 1] = talentIssue
            end

            if #issues > 0 then
                Print(L["%d problem(s) found. %s, %s, %s"]:format(#issues,
                    FormatPotionCount(potions.heal), FormatPotionCount(potions.mana),
                    FormatPotionCount(potions.weapon)))
                RP.Dialog:Show(issues, potions)
            elseif manual then
                RP.Dialog:Show(issues, potions)
            end
        end)
    end)
end

local wasInRaid = false

local function CheckRaidJoin()
    local inRaid = IsInRaid()
    if inRaid and not wasInRaid then
        C_Timer.After(RAID_JOIN_DELAY, function()
            if IsInRaid() then RP.RunCheck(false) end
        end)
    end
    wasInRaid = inRaid
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        RaidPreparedDB = RaidPreparedDB or {}
        ApplyDefaults(RaidPreparedDB, DEFAULTS)
        RP.Travel.db = RaidPreparedDB.travel
        RaidPreparedCharDB = RaidPreparedCharDB or {}
        RaidPreparedCharDB.loadoutFlags = RaidPreparedCharDB.loadoutFlags or {}
        RP.Minimap:Create()
        RP.Talents:Init()
        RP.CharacterPanel:Init()
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = arg1, arg2
        if isInitialLogin or isReloadingUi then
            CheckRaidJoin() -- already in a raid on login/reload counts as joining
        else
            wasInRaid = IsInRaid()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        CheckRaidJoin()
    end
end)

SLASH_RAIDPREPARED1 = "/raidprepared"
SLASH_RAIDPREPARED2 = "/rp"
SlashCmdList.RAIDPREPARED = function(input)
    local cmd, arg = strtrim(input or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "check" then
        RP.RunCheck(true)
    elseif cmd == "raid" or cmd == "party" or cmd == "inspect" then
        RP.RaidCheck:Open()
    elseif cmd == "talents" then
        RP.Talents:Open()
    elseif cmd == "travel" then
        local sub, rest = arg:match("^(%S*)%s*(.-)$")
        local Travel = RP.Travel
        if sub == "" then
            Travel:Toggle()
        elseif sub == "audit" then
            Travel:RunCaptured("Audit", Travel.Collector.Audit)
        elseif sub == "scan" then
            Travel:RunCaptured("Spellbook scan", Travel.Collector.ScanSpellbook, rest)
        elseif sub == "discover" then
            Travel:RunCaptured("Discovery", Travel.Collector.ReportDiscovery)
        elseif sub == "season" then
            Travel:RunCaptured("Current season", Travel.Season.Report)
        elseif sub == "copy" then
            Travel:ShowLastOutput()
        else
            Print(L["Usage: /rp travel [audit | scan <text> | discover | season | copy]"])
        end
    elseif cmd == "debug" then
        RP.Debug()
        RP.DebugPotions()
    elseif cmd == "options" then
        RP.Dialog:OpenOptions()
    elseif cmd == "indicators" then
        Print(RP.CharacterPanel:Toggle() and L["Character panel indicators enabled."]
            or L["Character panel indicators disabled."])
    elseif cmd == "minimap" then
        Print(RP.Minimap:Toggle() and L["Minimap button shown."] or L["Minimap button hidden."])
    elseif cmd == "quality" then
        local tier = tonumber(arg)
        if tier then
            Print(L["Required quality rank set to %d."]:format(RP.SetMaxQualityTier(tier)))
        else
            Print(L["Required quality rank is %d. Usage: /rp quality <rank>"]:format(RP.GetMaxQualityTier()))
        end
    else
        Print(L["Commands:"])
        print("  /rp - " .. L["check enchants, gems, potions and weapon buffs"])
        print("  /rp inspect - " .. L["raid/party inspect of all group members (also /rp raid, /rp party)"])
        print("  /rp talents - " .. L["flag talent loadouts for raid / Mythic dungeons"])
        print("  /rp travel - " .. L["search your fast-travel options (also /rp travel season)"])
        print("  /rp options - " .. L["open the options tab"])
        print("  /rp indicators - " .. L["toggle enchant/socket indicators on the character panel"])
        print("  /rp minimap - " .. L["toggle minimap button"])
        print("  /rp quality <rank> - " .. L["required enchant/gem quality rank"])
        print("  /rp debug - " .. L["print raw item/socket data"])
    end
end
