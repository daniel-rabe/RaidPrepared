local addonName, PR = ...
local L = PR.L

local RAID_JOIN_DELAY = 2

local DEFAULTS = {
    maxQualityTier = nil, -- nil = PR.DEFAULT_MAX_QUALITY_TIER
    minimap = { hide = false, angle = 225 },
    characterIndicators = true, -- enchant/socket indicators on the character panel
    localizedWhisper = false,   -- false = whisper in whisperLocale (recipient's language is unknown)
    funMode = false,            -- joke skin, toggled with /pr ziegel (see Fun.lua)
    -- Shopping tab: the scope (missing only / whole catalog), then the favourites
    -- filter applied on top of whichever scope is selected.
    shoppingShowAll = false,
    shoppingFavoritesOnly = false,
    whisperLocale = "enUS",     -- language of Raid Inspect whispers when localizedWhisper is off
    travel = {                  -- fast-travel tab
        closeOnUse = true,
        maxRecent  = 15,
        seasonOnly = false,     -- "M+" filter on the travel tab, kept across reloads
        recent     = {},        -- array of entry keys, most recently used first
        favorites  = {},        -- [entryKey] = true
    },
}

local function Print(msg)
    print(("|cff33ccff%s|r: "):format(PR.Fun:Title()) .. msg)
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

-- Clamped on read as well: a rank saved before the selectable range shrank must not
-- flag every enchant and gem as low quality.
function PR.GetMaxQualityTier()
    local tier = PullReadyDB.maxQualityTier or PR.DEFAULT_MAX_QUALITY_TIER
    return math.max(PR.MIN_QUALITY_RANK_OPTION, math.min(PR.MAX_QUALITY_RANK_OPTION, tier))
end

function PR.SetMaxQualityTier(tier)
    tier = math.max(PR.MIN_QUALITY_RANK_OPTION, math.min(PR.MAX_QUALITY_RANK_OPTION, math.floor(tier)))
    PullReadyDB.maxQualityTier = tier
    PR.CharacterPanel:RequestUpdate()
    PR.Dialog:RefreshQuality()
    return tier
end

-- manual = true: always show the dialog (also when everything is fine).
function PR.RunCheck(manual)
    PR.ScanAsync(function(issues)
        -- Durability belongs to the gear, so its warnings follow the enchant and gem ones.
        local durability, durabilityIssues = PR.ScanDurability()
        for _, issue in ipairs(durabilityIssues) do
            issues[#issues + 1] = issue
        end
        PR.ScanPotionsAsync(function(potions, potionIssues)
            for _, issue in ipairs(potionIssues) do
                issues[#issues + 1] = issue
            end
            PR.ScanTierSetAsync(function(tierSet, tierIssues)
                for _, issue in ipairs(tierIssues) do
                    issues[#issues + 1] = issue
                end
                local talentIssue = PR.Talents:Check()
                if talentIssue then
                    issues[#issues + 1] = talentIssue
                end

                if #issues > 0 then
                    local counts = {}
                    for _, entry in ipairs(potions) do
                        counts[#counts + 1] = FormatPotionCount(entry)
                    end
                    Print(L["%d problem(s) found. %s"]:format(#issues, table.concat(counts, ", ")))
                    PR.Dialog:Show(issues, potions, tierSet, durability)
                elseif manual then
                    PR.Dialog:Show(issues, potions, tierSet, durability)
                end
            end)
        end)
    end)
end

local wasInRaid = false

local function CheckRaidJoin()
    local inRaid = IsInRaid()
    if inRaid and not wasInRaid then
        C_Timer.After(RAID_JOIN_DELAY, function()
            if IsInRaid() then PR.RunCheck(false) end
        end)
    end
    wasInRaid = inRaid
end

-- The addon was called RaidPrepared until 1.5.0. The folder name did not change
-- with it, so the saved variables are still the same file and the old tables are
-- simply handed over. Declaring the old names in the toc is what makes WoW load
-- them at all; clearing them here stops them being written out again, so the toc
-- entries can go away a release or two from now.
local function AdoptRenamedVariables()
    if PullReadyDB == nil and RaidPreparedDB ~= nil then
        PullReadyDB = RaidPreparedDB
    end
    if PullReadyCharDB == nil and RaidPreparedCharDB ~= nil then
        PullReadyCharDB = RaidPreparedCharDB
    end
    RaidPreparedDB, RaidPreparedCharDB = nil, nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        AdoptRenamedVariables()
        PullReadyDB = PullReadyDB or {}
        ApplyDefaults(PullReadyDB, DEFAULTS)
        PR.Travel.db = PullReadyDB.travel
        PullReadyCharDB = PullReadyCharDB or {}
        PullReadyCharDB.loadoutFlags = PullReadyCharDB.loadoutFlags or {}
        PullReadyCharDB.shoppingFavorites = PullReadyCharDB.shoppingFavorites or {}
        PR.Minimap:Create()
        PR.Talents:Init()
        PR.CharacterPanel:Init()
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

SLASH_PULLREADY1 = "/pullready"
SLASH_PULLREADY2 = "/pr"
SlashCmdList.PULLREADY = function(input)
    local cmd, arg = strtrim(input or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "check" then
        PR.RunCheck(true)
    elseif cmd == "raid" or cmd == "party" or cmd == "inspect" then
        PR.RaidCheck:Open()
    elseif cmd == "talents" then
        PR.Talents:Open()
    elseif cmd == "shop" or cmd == "shopping" then
        PR.Shopping:Toggle()
    elseif cmd == "travel" then
        local sub, rest = arg:match("^(%S*)%s*(.-)$")
        local Travel = PR.Travel
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
            Print(L["Usage: /pr travel [audit | scan <text> | discover | season | copy]"])
        end
    elseif cmd == "debug" then
        PR.Debug()
        PR.DebugPotions()
        PR.DebugTierSet()
        PR.DebugDurability()
    elseif cmd == "options" then
        PR.Dialog:OpenOptions()
    elseif cmd == "indicators" then
        Print(PR.CharacterPanel:Toggle() and L["Character panel indicators enabled."]
            or L["Character panel indicators disabled."])
    elseif cmd == "ziegel" then
        Print(PR.Fun:Toggle() and L["fun.on"] or L["fun.off"])
    elseif cmd == "minimap" then
        Print(PR.Minimap:Toggle() and L["Minimap button shown."] or L["Minimap button hidden."])
    elseif cmd == "quality" then
        local tier = tonumber(arg)
        if tier then
            Print(L["Required quality rank set to %d."]:format(PR.SetMaxQualityTier(tier)))
        else
            Print(L["Required quality rank is %d. Usage: /pr quality <rank>"]:format(PR.GetMaxQualityTier()))
        end
    else
        Print(L["Commands:"])
        print("  /pr - " .. L["check enchants, gems, potions and weapon buffs"])
        print("  /pr inspect - " .. L["raid/party inspect of all group members (also /pr raid, /pr party)"])
        print("  /pr talents - " .. L["flag talent loadouts for raid / Mythic dungeons"])
        print("  /pr travel - " .. L["search your fast-travel options (also /pr travel season)"])
        print("  /pr shop - " .. L["list the enchants, gems and consumables you still need"])
        print("  /pr options - " .. L["open the options tab"])
        print("  /pr indicators - " .. L["toggle enchant/socket indicators on the character panel"])
        print("  /pr minimap - " .. L["toggle minimap button"])
        print("  /pr quality <rank> - " .. L["required enchant/gem quality rank"])
        print("  /pr debug - " .. L["print raw item/socket data"])
        -- An easter egg: only listed once it is on, so it can be found again to switch off.
        if PR.Fun:IsEnabled() then
            print("  /pr ziegel - " .. L["fun.help"])
        end
    end
end
