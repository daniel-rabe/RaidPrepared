local _, PR = ...

-- Fun mode, switched on and off with "/pr ziegel".
--
-- It is a joke skin, not a feature: the window header becomes FUN_TITLE and every
-- warning the check produces is swapped for a ruder version of itself. The checks,
-- their colours and their ordering are untouched, and so is everything that leaves
-- this client - the whispers of the Raid Inspect tab (they go through PR.GetString,
-- not PR.L) and the addon channel keep their normal wording, so nobody else in the
-- group is insulted by proxy.
--
-- The swap happens in PR.L: a key listed in REPLACEMENTS is translated as its
-- "fun." twin instead, which means the joke texts are translatable like any other
-- string and silently fall back to English where a locale has none.

local FUN_TITLE = "RaidReadyMcRaidface"
local NORMAL_TITLE = "PullReady"

local Fun = {}
PR.Fun = Fun

-- Normal string key -> fun string key. Only warnings belong in here; every other
-- string keeps its ordinary translation.
local REPLACEMENTS = {
    -- Gear scan
    ["Missing enchant"]                        = "fun.missing_enchant",
    ["Low quality enchant (rank %d/%d)%s"]     = "fun.low_enchant",
    ["Outdated enchant%s"]                     = "fun.outdated_enchant",
    ["Empty gem socket"]                       = "fun.empty_socket",
    ["%d empty gem sockets"]                   = "fun.empty_sockets",
    ["Low quality gem (rank %d/%d): %s"]       = "fun.low_gem",
    ["Outdated gem: %s"]                       = "fun.outdated_gem",
    ["No Eversong Diamond socketed"]           = "fun.no_epic_gem",

    -- Consumables
    ["No flask in your bags!"]                 = "fun.no_flask",
    ["Only %d flasks (minimum %d)"]            = "fun.few_flasks",
    ["No healing potions in your bags!"]       = "fun.no_heal",
    ["Only %d healing potions (minimum %d)"]   = "fun.few_heals",
    ["No mana potions in your bags!"]          = "fun.no_mana",
    ["Only %d mana potions (minimum %d)"]      = "fun.few_manas",
    ["No power potions in your bags!"]         = "fun.no_power",
    ["Only %d power potions (minimum %d)"]     = "fun.few_powers",
    ["No weapon buffs in your bags!"]          = "fun.no_weapon",
    ["Only %d weapon buffs (minimum %d)"]      = "fun.few_weapons",

    -- Tier set and talents
    ["%d piece(s) short of the %d-piece bonus - %d catalyst charge(s) ready"] = "fun.tier_short",
    ["Loadout '%s' is not flagged for %s (use: %s)"]                          = "fun.talents",

    -- Summary lines of the check tab and the chat report
    ["%d problem(s) found, %d missing"]        = "fun.summary",
    ["%d problem(s) found. %s"]                = "fun.summary_chat",
    ["Everything looks good!"]                 = "fun.all_good",
    ["No check run yet - use /pr or the minimap button."] = "fun.no_check",
}

local enUS = PR.Locales.enUS

enUS["fun.missing_enchant"]  = "No enchant at all. Bold strategy."
enUS["fun.low_enchant"]      = "Bargain-bin enchant, rank %d/%d, you peasant.%s"
enUS["fun.outdated_enchant"] = "That enchant belongs in a museum%s"
enUS["fun.empty_socket"]     = "An empty socket. A hole where your item level should be."
enUS["fun.empty_sockets"]    = "%d empty sockets. Your gear has more holes than your logs."
enUS["fun.low_gem"]          = "Rank %d/%d gravel: %s"
enUS["fun.outdated_gem"]     = "Antique gem: %s. The expansion ended, buddy."
enUS["fun.no_epic_gem"]      = "No Eversong Diamond. Allergic to damage, are we?"

enUS["fun.no_flask"]     = "Zero flasks. Raiding on vibes tonight?"
enUS["fun.few_flasks"]   = "%d flasks, need %d. Rationing like a goblin."
enUS["fun.no_heal"]      = "No health potions. Bold of you to assume you will live."
enUS["fun.few_heals"]    = "%d health potions, need %d. That is one death's worth."
enUS["fun.no_mana"]      = "No mana potions. Enjoy the auto-attacks, then."
enUS["fun.few_manas"]    = "%d mana potions, need %d. Hope you like wanding."
enUS["fun.no_power"]     = "No combat potions. Your parse is already crying."
enUS["fun.few_powers"]   = "%d combat potions, need %d. Grey parse incoming."
enUS["fun.no_weapon"]    = "No weapon buff. Swinging a wet noodle, are we?"
enUS["fun.few_weapons"]  = "%d weapon buffs, need %d. Stop being cheap."

enUS["fun.tier_short"] = "%d piece(s) off the %d-piece bonus and %d catalyst charge(s) rotting in your bank. Wake up."
enUS["fun.talents"]    = "Loadout '%s' is not the one for %s, you muppet. Use: %s"

enUS["fun.summary"]      = "%d crime(s) against gearing, %d of them simply missing"
enUS["fun.summary_chat"] = "%d crime(s) against gearing. %s"
enUS["fun.all_good"]     = "Fine. You are ready. Do not let it go to your head."
enUS["fun.no_check"]     = "Nothing checked yet. Press something, hero - /pr or the minimap button."

enUS["fun.on"]  = "Fun mode on. Brace yourself."
enUS["fun.off"] = "Fun mode off. Back to being polite."
enUS["fun.help"] = "turn the fun off again"

function Fun:IsEnabled()
    return (PullReadyDB and PullReadyDB.funMode) == true
end

function Fun:SetEnabled(enabled)
    PullReadyDB.funMode = enabled and true or false
    PR.Dialog:RefreshFunMode()
    return PullReadyDB.funMode
end

function Fun:Toggle()
    return self:SetEnabled(not self:IsEnabled())
end

-- The addon name as shown in the UI: window header, tooltips and chat prefix.
function Fun:Title()
    return self:IsEnabled() and FUN_TITLE or NORMAL_TITLE
end

-- The fun twin of a string key while fun mode is on, or nil to translate as usual.
function Fun:Key(key)
    if not self:IsEnabled() then return nil end
    return REPLACEMENTS[key]
end
