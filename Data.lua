local _, RP = ...

-- Everything in this file is patch-specific. Review it when a new patch/season launches.

-- Slots that are expected to carry an enchant (Midnight).
RP.ENCHANT_SLOTS = {
    [INVSLOT_HEAD]      = true,
    [INVSLOT_SHOULDER]  = true,
    [INVSLOT_CHEST]     = true,
    [INVSLOT_LEGS]      = true,
    [INVSLOT_FEET]      = true,
    [INVSLOT_FINGER1]   = true,
    [INVSLOT_FINGER2]   = true,
    [INVSLOT_MAINHAND]  = true,
    [INVSLOT_OFFHAND]   = true, -- only checked when the off-hand item is a weapon
}

-- Off-hand equip locations that can be enchanted (shields / held-in-off-hand items cannot).
RP.ENCHANTABLE_OFFHAND = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONOFFHAND = true,
}

-- Highest crafted quality tier for enchants and gems. Anything below is reported as "low quality".
-- Can be changed in-game with /rp quality <n> (stored in SavedVariables).
RP.DEFAULT_MAX_QUALITY_TIER = 2

-- Optional whitelist of current-season enchant IDs (the second field of an item link).
-- When non-empty, any enchant not listed here is reported as "outdated".
-- Leave empty to skip the check. Example: [7985] = true,
RP.KNOWN_CURRENT_ENCHANTS = {
}

-- Gems whose expansion ID is lower than this are reported as "outdated".
RP.MIN_GEM_EXPANSION = LE_EXPANSION_LEVEL_CURRENT

-- Potion check. Potions are detected by item class (Consumable > Potion) and classified as
-- healing/mana by their "Use:" tooltip text. Warn when fewer than the minimum are in the bags.
RP.MIN_HEALING_POTIONS = 1
RP.MIN_MANA_POTIONS = 1

-- When non-empty, only potions with one of these names count as healing potions
-- (item names as shown in game, all quality ranks share the name).
-- Leave empty to count every potion whose tooltip restores health.
RP.HEALING_POTION_NAMES = {
    ["Concentrated Silvermoon Health Potion"] = true,
    ["Silvermoon Health Potion"] = true,
}

-- Same for mana potions: when non-empty, only these names count as mana potions.
RP.MANA_POTION_NAMES = {
    ["Silvermoon Mana Potion"] = true,
}

-- Specialization roles that need mana potions ("HEALER", "DAMAGER", "TANK").
-- Mana potion counts are still shown for other roles, but never reported as a problem.
RP.MANA_POTION_ROLES = {
    HEALER = true,
}

-- Temporary weapon buffs (oils, sharpening stones, weightstones). Detected as consumables
-- whose "Use:" tooltip text mentions the weapon.
RP.MIN_WEAPON_BUFFS = 1

-- Classes that use their own weapon imbues/poisons/runes instead of oils or stones.
-- Their weapon buff count is still shown, but never reported as a problem.
RP.WEAPON_BUFF_EXEMPT_CLASSES = {
    DEATHKNIGHT = true,
    ROGUE = true,
    SHAMAN = true,
}

-- Potions and weapon buffs from older expansions are shown as "outdated" and not counted.
RP.MIN_CONSUMABLE_EXPANSION = LE_EXPANSION_LEVEL_CURRENT

-- Extra item IDs that should count as healing/mana potions or weapon buffs even if not detected automatically.
-- Example: [5512] = true, -- Healthstone
RP.EXTRA_HEALING_ITEMS = {
}
RP.EXTRA_MANA_ITEMS = {
}
RP.EXTRA_WEAPON_BUFF_ITEMS = {
}

RP.SLOT_NAMES = {
    [INVSLOT_HEAD]      = HEADSLOT,
    [INVSLOT_NECK]      = NECKSLOT,
    [INVSLOT_SHOULDER]  = SHOULDERSLOT,
    [INVSLOT_BODY]      = SHIRTSLOT,
    [INVSLOT_CHEST]     = CHESTSLOT,
    [INVSLOT_WAIST]     = WAISTSLOT,
    [INVSLOT_LEGS]      = LEGSSLOT,
    [INVSLOT_FEET]      = FEETSLOT,
    [INVSLOT_WRIST]     = WRISTSLOT,
    [INVSLOT_HAND]      = HANDSSLOT,
    [INVSLOT_FINGER1]   = FINGER0SLOT .. " 1",
    [INVSLOT_FINGER2]   = FINGER1SLOT .. " 2",
    [INVSLOT_TRINKET1]  = TRINKET0SLOT .. " 1",
    [INVSLOT_TRINKET2]  = TRINKET1SLOT .. " 2",
    [INVSLOT_BACK]      = BACKSLOT,
    [INVSLOT_MAINHAND]  = MAINHANDSLOT,
    [INVSLOT_OFFHAND]   = SECONDARYHANDSLOT,
}
