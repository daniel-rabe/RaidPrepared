-- PullReady - Travel/Portals.lua
-- Mythic+ / challenge-mode dungeon teleports.
--
-- These are learned spells that sit in your spellbook, and Blizzard adds a new
-- batch every season. Rather than hardcoding a list that rots, the Collector
-- DISCOVERS them: it walks the spellbook and treats any known spell whose name
-- matches one of the patterns below as a dungeon teleport.
--
-- Anything the patterns miss can be pinned by ID in `extra` below. Use
-- `/pr travel scan` to dump your spellbook and find the ID.

local _, PR = ...
local T = PR.Travel

T.Data = T.Data or {}

-- Lua patterns matched against the lowercased spell name, each carrying the
-- category its matches belong to.
--
-- The name is the reliable signal, confirmed against a live spellbook: every
-- Mythic+ dungeon teleport is "Path of the <X>" (even the old Mists and Draenor
-- ones, which Blizzard renamed), while city teleports are "Teleport: <City>".
-- Both live inside spellbook flyouts, so flyout membership tells them apart.
T.Data.teleportPatterns = {
    { pattern = "^path of ",       cat = "dungeon" },
    { pattern = "^pfad d",         cat = "dungeon" },  -- deDE "Pfad des/der ..."
    { pattern = "^teleport:",      cat = "class"   },
    { pattern = "^teleportation:", cat = "class"   },  -- deDE
}

-- Pull the destination out of a teleport's description, so a port named
-- "Path of the Warding Candles" can be shown and found as "Darkflame Cleft".
--
-- Confirmed enUS wording, all four variants seen on a live spellbook:
--   "Teleport to the entrance to Siege of Boralus."
--   "Teleport to the entrance of Manaforge Omega."
--   "Teleport to the entrance to the Temple of the Jade Serpent."
--   "Teleport to the entrance of the Liberation of Undermine."
-- Other locales need their own patterns here; extraction failing just falls
-- back to the spell name, so a missing locale is cosmetic, never broken.
T.Data.destinationPatterns = {
    "entrance to (.+)%.",
    "entrance of (.+)%.",
}

-- Spells the patterns would wrongly claim as dungeon teleports. These are
-- already listed in Data/Travel.lua under a better category.
T.Data.dungeonExclude = {
    [18960]  = true,  -- Teleport: Moonglade (druid)
    [3561]   = true, [3562] = true, [3563] = true, [3565] = true,
    [3566]   = true, [3567] = true, [32271] = true, [32272] = true,
    [33690]  = true, [35715] = true, [53140] = true,
    [88342]  = true, [88344] = true,
    [132621] = true, [132627] = true,
    [176242] = true, [176248] = true,
    [193759] = true, [224869] = true,
    [281403] = true, [281404] = true,
    [344587] = true, [395277] = true, [446540] = true,
}

-- Dungeon teleports the name patterns do not catch. Add as { spellID, keywords }.
T.Data.dungeonExtra = {
    -- { 123456, { "some", "dungeon" } },
}
