local _, RP = ...

-- Everything in this file is patch-specific. Review it when a new patch/season launches.

-- Specialization API compat. The GetSpecialization / GetSpecializationInfo globals only exist
-- while the "loadDeprecationFallbacks" CVar is on and Blizzard drops them next expansion;
-- C_SpecializationInfo is the current home. Always go through these helpers.
function RP.GetSpecIndex()
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        return C_SpecializationInfo.GetSpecialization()
    end
    if GetSpecialization then
        return GetSpecialization()
    end
end

function RP.GetSpecInfo(specIndex)
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        return C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end
    if GetSpecializationInfo then
        return GetSpecializationInfo(specIndex)
    end
end

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
RP.MIN_QUALITY_RANK_OPTION = 1 -- range selectable in the options tab / slash command
RP.MAX_QUALITY_RANK_OPTION = 2 -- enchants and gems are crafted in two quality ranks this season

-- Optional whitelist of current-season enchant IDs (the second field of an item link).
-- When non-empty, any enchant not listed here is reported as "outdated".
-- Leave empty to skip the check. Example: [7985] = true,
RP.KNOWN_CURRENT_ENCHANTS = {
}

-- Gems whose expansion ID is lower than this are reported as "outdated".
RP.MIN_GEM_EXPANSION = LE_EXPANSION_LEVEL_CURRENT

-- Unique epic gems; one of them should be socketed somewhere in the gear.
-- Matched by item ID (one ID per quality rank). Leave empty to skip the check.
RP.EPIC_GEM_IDS = {
    [240982] = true, [240983] = true, -- Indecipherable Eversong Diamond
    [240966] = true, [240967] = true, -- Powerful Eversong Diamond
    [240970] = true, [240971] = true, -- Stoic Eversong Diamond
    [240968] = true, [240969] = true, -- Telluric Eversong Diamond
}
RP.EPIC_GEM_ICON_ID = 240967 -- icon shown for the missing epic gem warning

-- Consumable check. Items are matched by item ID, so it works with every client language.
-- Each crafting quality rank is a separate item ID - list all of them. Update each season.
-- Warn when fewer than the minimum are in the bags.
RP.MIN_HEALING_POTIONS = 1
RP.MIN_MANA_POTIONS = 1
RP.MIN_WEAPON_BUFFS = 1
RP.MIN_POWER_POTIONS = 1

RP.HEALING_POTION_IDS = {
    [241304] = true, [241305] = true, -- Silvermoon Health Potion
    [271883] = true, [271884] = true, -- Concentrated Silvermoon Health Potion
}

RP.MANA_POTION_IDS = {
    [241300] = true, [241301] = true, -- Lightfused Mana Potion
}

-- Combat potions that grant a temporary burst of power ("Light's Potential" and friends).
-- The "Fleeting" versions are the soulbound crafts of the same potion.
RP.POWER_POTION_IDS = {
    [241308] = true, [241309] = true, -- Light's Potential
    [245897] = true, [245898] = true, -- Fleeting Light's Potential
    [241292] = true, [241293] = true, -- Draught of Rampant Abandon
    [241288] = true, [241289] = true, -- Potion of Recklessness
    [245902] = true, [245903] = true, -- Fleeting Potion of Recklessness
    [241296] = true, [241297] = true, -- Potion of Zealotry
    [245900] = true, [245901] = true, -- Fleeting Potion of Zealotry
    [271886] = true, [271887] = true, -- Liquid Luster
    [274763] = true, [274764] = true, -- Fleeting Liquid Luster
    [271889] = true, [271890] = true, -- Alluring Nostrum
    [274765] = true, [274766] = true, -- Fleeting Alluring Nostrum
}

-- Temporary weapon buffs: oils, sharpening stones, weightstones and hunter ammo.
RP.WEAPON_BUFF_IDS = {
    [243733] = true, [243734] = true, -- Thalassian Phoenix Oil
    [243735] = true, [243736] = true, -- Oil of Dawn
    [243737] = true, [243738] = true, -- Smuggler's Enchanted Edge
    [237370] = true, [237371] = true, -- Refulgent Whetstone
    [237367] = true, [237369] = true, -- Refulgent Weightstone
    [257749] = true, [257750] = true, -- Laced Zoomshots
    [257751] = true, [257752] = true, -- Weighted Boomshots
}

-- Specialization roles that need mana potions ("HEALER", "DAMAGER", "TANK").
-- Mana potion counts are still shown for other roles, but never reported as a problem.
RP.MANA_POTION_ROLES = {
    HEALER = true,
}

-- Classes that use their own weapon imbues/poisons/runes instead of oils or stones.
-- Their weapon buff count is still shown, but never reported as a problem.
RP.WEAPON_BUFF_EXEMPT_CLASSES = {
    DEATHKNIGHT = true,
    ROGUE = true,
    SHAMAN = true,
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

-- English slot names for whispers: the recipient's client language is unknown.
RP.SLOT_NAMES_EN = {
    [INVSLOT_HEAD]      = "Head",
    [INVSLOT_NECK]      = "Neck",
    [INVSLOT_SHOULDER]  = "Shoulder",
    [INVSLOT_BODY]      = "Shirt",
    [INVSLOT_CHEST]     = "Chest",
    [INVSLOT_WAIST]     = "Waist",
    [INVSLOT_LEGS]      = "Legs",
    [INVSLOT_FEET]      = "Feet",
    [INVSLOT_WRIST]     = "Wrist",
    [INVSLOT_HAND]      = "Hands",
    [INVSLOT_FINGER1]   = "Finger 1",
    [INVSLOT_FINGER2]   = "Finger 2",
    [INVSLOT_TRINKET1]  = "Trinket 1",
    [INVSLOT_TRINKET2]  = "Trinket 2",
    [INVSLOT_BACK]      = "Back",
    [INVSLOT_MAINHAND]  = "Main Hand",
    [INVSLOT_OFFHAND]   = "Off Hand",
}
