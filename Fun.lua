local _, PR = ...

-- Fun mode, switched on and off with "/pr ziegel".
--
-- It is a joke skin, not a feature: the window header becomes FUN_TITLE, every
-- warning the check produces is swapped for a ruder version of itself and the
-- window's warning sound is swapped too (see the bottom of this file). The checks,
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

    -- Durability
    ["Broken - repair before the pull"]        = "fun.broken",
    ["Durability %d%% (minimum %d%%)"]         = "fun.durability",

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

enUS["fun.broken"]     = "Broken. You are swinging a paperweight, champ."
enUS["fun.durability"] = "Durability %d%%, minimum is %d%%. Ever met an anvil?"

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

-- ---------------------------------------------------------------- warning sound
--
-- The check window's warning sound is swapped as well: fun mode answers a failed
-- check with Illidan's "You are not prepared!" instead of the ordinary UI alert.
-- The line is not shipped with the addon - every client already carries it as a
-- sound kit, which is also why the player hears it in their own language.
--
-- 11466 is A_BLCKTMPLE_Illidan_04, the closing line of the Black Temple gate
-- speech. If it ever turns out to be one of its neighbours (11463-11467 are the
-- same speech), this constant is the only thing that has to move.
local ILLIDAN_SOUND_KIT = 11466

-- The shout runs a good three seconds and the window can reopen right after a
-- check, so it is rationed. The ordinary alert is short enough to need none of this.
local ILLIDAN_COOLDOWN = 20
local lastShout = 0

-- True once the shout is actually on its way. It is not when the cooldown is still
-- running, and it is not on a streaming install that never pulled the Black Temple
-- audio down: the client has no file for the kit then and PlaySound says so rather
-- than playing anything.
local function Shout()
    local now = GetTime()
    if now - lastShout < ILLIDAN_COOLDOWN then return false end
    -- "Master", so the shout still lands with the dialog channel turned down. Fun
    -- mode has to be switched on by hand, so it is allowed to be loud.
    if not PlaySound(ILLIDAN_SOUND_KIT, "Master") then return false end
    lastShout = now
    return true
end

-- The sound the check window plays when it opens on problems. Falls back to the
-- ordinary alert whenever the shout does not happen, so a failed check is never silent.
function Fun:PlayWarningSound()
    if self:IsEnabled() and Shout() then return end
    PlaySound(SOUNDKIT.RAID_WARNING)
end
