local addonName, RP = ...

local PREFIX = "|cff33ccffRaidPrepared|r: "
local RAID_JOIN_DELAY = 2

local DEFAULTS = {
    maxQualityTier = nil, -- nil = RP.DEFAULT_MAX_QUALITY_TIER
    minimap = { hide = false, angle = 225 },
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
    if entry.outdated > 0 then
        text = text .. (" (+%d outdated)"):format(entry.outdated)
    end
    if entry.activeTime then
        text = text .. (" (active %dm)"):format(math.floor(entry.activeTime / 60))
    end
    return text
end

-- manual = true: always show the dialog (also when everything is fine).
function RP.RunCheck(manual)
    RP.ScanAsync(function(issues)
        RP.ScanPotionsAsync(function(potions, potionIssues)
            for _, issue in ipairs(potionIssues) do
                issues[#issues + 1] = issue
            end

            if #issues > 0 then
                Print(("%d problem(s) found. %s, %s, %s"):format(#issues,
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
        RP.Minimap:Create()
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
    elseif cmd == "raid" then
        RP.RaidCheck:Open()
    elseif cmd == "debug" then
        RP.Debug()
        RP.DebugPotions()
    elseif cmd == "minimap" then
        Print("Minimap button " .. (RP.Minimap:Toggle() and "shown." or "hidden."))
    elseif cmd == "quality" then
        local tier = tonumber(arg)
        if tier and tier >= 1 then
            RaidPreparedDB.maxQualityTier = math.floor(tier)
            Print("Required quality rank set to " .. RaidPreparedDB.maxQualityTier .. ".")
        else
            local current = RaidPreparedDB.maxQualityTier or RP.DEFAULT_MAX_QUALITY_TIER
            Print("Required quality rank is " .. current .. ". Usage: /rp quality <rank>")
        end
    else
        Print("Commands:")
        print("  /rp - check enchants, gems, potions and weapon buffs")
        print("  /rp raid - check enchants and gems of all group members")
        print("  /rp minimap - toggle minimap button")
        print("  /rp quality <rank> - required enchant/gem quality rank")
        print("  /rp debug - print raw item/socket data")
    end
end
