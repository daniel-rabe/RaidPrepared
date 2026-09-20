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

-- ============================================================================
-- SHOPPING TAB CATALOG
-- ============================================================================
-- What the Shopping tab offers to buy. Item IDs only: name, icon, link and quality
-- colour all come from C_Item at runtime, so the list is localized for free.
--
-- Enchants, leg armor and gems list the rank 2 (higher crafting quality) item; rank 1
-- is always ID - 1. Rank 2 is what the default required quality asks for, and an
-- auction house name search returns both ranks anyway.
--
-- Not listed on purpose: "Enchant Tool - ..." (profession tools, not gear) and the
-- Heliotrope gems (PvP items sharing the Thalassian Diamond unique-equipped family).

-- Enchants keyed by the inventory slot they apply to. FINGER2 reuses the FINGER1 list
-- and OFFHAND reuses the MAINHAND list (see RP.GetEnchantShopSlot).
RP.ENCHANT_ITEMS = {
    [INVSLOT_HEAD] = {
        243979, -- Enchant Helm - Blessing of Speed
        243981, -- Enchant Helm - Empowered Blessing of Speed
        243949, -- Enchant Helm - Hex of Leeching
        243951, -- Enchant Helm - Empowered Hex of Leeching
        244005, -- Enchant Helm - Rune of Avoidance
        244007, -- Enchant Helm - Empowered Rune of Avoidance
    },
    [INVSLOT_SHOULDER] = {
        243963, -- Enchant Shoulders - Akil'zon's Swiftness
        243991, -- Enchant Shoulders - Amirdrassil's Grace
        243961, -- Enchant Shoulders - Flight of the Eagle
        243989, -- Enchant Shoulders - Nature's Grace
        244021, -- Enchant Shoulders - Silvermoon's Mending
        244019, -- Enchant Shoulders - Thalassian Recovery
    },
    [INVSLOT_CHEST] = {
        243947, -- Enchant Chest - Mark of Nalorakk
        244003, -- Enchant Chest - Mark of the Magister
        243975, -- Enchant Chest - Mark of the Rootwarden
        243977, -- Enchant Chest - Mark of the Worldsoul
    },
    [INVSLOT_FEET] = {
        244009, -- Enchant Boots - Farstrider's Hunt
        243953, -- Enchant Boots - Lynx's Dexterity
        243983, -- Enchant Boots - Shaladrassil's Roots
    },
    [INVSLOT_FINGER1] = {
        243955, -- Enchant Ring - Amani Mastery
        243957, -- Enchant Ring - Eyes of the Eagle
        243987, -- Enchant Ring - Nature's Fury
        243985, -- Enchant Ring - Nature's Wrath
        244015, -- Enchant Ring - Silvermoon's Alacrity
        244017, -- Enchant Ring - Silvermoon's Tenacity
        244011, -- Enchant Ring - Thalassian Haste
        244013, -- Enchant Ring - Thalassian Versatility
        243959, -- Enchant Ring - Zul'jin's Mastery
    },
    [INVSLOT_MAINHAND] = {
        244029, -- Enchant Weapon - Acuity of the Ren'dorei
        244031, -- Enchant Weapon - Arcane Mastery
        243973, -- Enchant Weapon - Berserker's Rage
        244027, -- Enchant Weapon - Flames of the Sin'dorei
        243971, -- Enchant Weapon - Jan'alai's Precision
        273072, -- Enchant Weapon - Rite of the Hash'ey
        243969, -- Enchant Weapon - Strength of Halazzi
        243999, -- Enchant Weapon - Worldsoul Aegis
        243997, -- Enchant Weapon - Worldsoul Cradle
        244001, -- Enchant Weapon - Worldsoul Tenacity
    },
}

-- Legs take a spellthread (cloth) or an armor kit (leather/mail/plate), not an enchant.
RP.LEG_ARMOR_ITEMS = {
    cloth = {
        240157, -- Bright Linen Spellthread
        240133, -- Sunfire Silk Spellthread
        240155, -- Arcanoweave Spellthread
    },
    physical = {
        244641, -- Forest Hunter's Armor Kit
        244643, -- Blood Knight's Armor Kit
        244645, -- Thalassian Scout Armor Kit
    },
}

-- Gems grouped by mineral. The mineral sets the primary stat, the cut adjective the
-- secondary one. "Flawless" is a strictly better tier of the same gem (+17 versus +13
-- Versatility at the same item level), so the plain line is only shown under "Show all".
RP.GEM_ITEMS = {
    { mineral = "Lapis",    flawless = { 240912, 240916, 240914, 240918 }, plain = { 240880, 240884, 240882, 240886 } },
    { mineral = "Peridot",  flawless = { 240888, 240894, 240890, 240892 }, plain = { 240856, 240862, 240858, 240860 } },
    { mineral = "Garnet",   flawless = { 240904, 240910, 240906, 240908 }, plain = { 240872, 240878, 240874, 240876 } },
    { mineral = "Amethyst", flawless = { 240896, 240902, 240900, 240898 }, plain = { 240864, 240870, 240868, 240866 } },
}

-- The unique epic diamonds, one row each (rank 2 of every pair in RP.EPIC_GEM_IDS).
RP.EPIC_GEM_SHOP_IDS = {
    240983, -- Indecipherable Eversong Diamond
    240967, -- Powerful Eversong Diamond
    240971, -- Stoic Eversong Diamond
    240969, -- Telluric Eversong Diamond
}

-- The consumable tables above are sets, and pairs() order is not stable, so the shopping
-- list needs its own ordered copy. Both crafting ranks are listed; the tab keeps one row
-- per item name and drops the lower-item-level rank (see RP.BuildShopItems).
RP.CONSUMABLE_SHOP_IDS = {
    heal   = { 241304, 241305, 271883, 271884 },
    mana   = { 241300, 241301 },
    power  = { 241308, 241309, 245897, 245898, 241292, 241293, 241288, 241289, 245902, 245903,
               241296, 241297, 245900, 245901, 271886, 271887, 274763, 274764, 271889, 271890,
               274765, 274766 },
    weapon = { 243733, 243734, 243735, 243736, 243737, 243738, 237370, 237371, 237367, 237369,
               257749, 257750, 257751, 257752 },
}

-- The enchant list a slot shops from: the two ring slots share one list, as do the two
-- weapon slots. Legs are handled separately (spellthread / armor kit).
function RP.GetEnchantShopSlot(slot)
    if slot == INVSLOT_FINGER2 then return INVSLOT_FINGER1 end
    if slot == INVSLOT_OFFHAND then return INVSLOT_MAINHAND end
    return slot
end

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
