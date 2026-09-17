local _, RP = ...

-- Counts raid consumables in the bags by item ID (see Data.lua): healing potions,
-- mana potions and temporary weapon buffs (oils, stones, hunter ammo).

local DEFAULT_ICONS = {
    heal = 134830,   -- INV_Potion_54
    mana = 134851,   -- INV_Potion_76
    weapon = 135255, -- INV_Stone_02
}

local function IsManaPotionRequired()
    local specIndex = GetSpecialization and GetSpecialization()
    local role = specIndex and GetSpecializationRole(specIndex)
    return role ~= nil and RP.MANA_POTION_ROLES[role] == true
end

local function IsWeaponBuffRequired()
    local _, classFile = UnitClass("player")
    return not RP.WEAPON_BUFF_EXEMPT_CLASSES[classFile]
end

-- Remaining time of the currently applied main-hand temporary enchant in seconds, or nil.
local function GetActiveWeaponBuffTime()
    local hasMainHand, mainHandExpiration = GetWeaponEnchantInfo()
    if hasMainHand and mainHandExpiration then
        return mainHandExpiration / 1000
    end
    return nil
end

local function NewEntry(kind, label, ids, minimum, required)
    return {
        kind = kind,
        label = label,
        ids = ids,
        minimum = minimum,
        required = required,
        count = 0,
        icon = DEFAULT_ICONS[kind],
    }
end

local function BuildIssues(consumables)
    local issues = {}
    for i, entry in ipairs(consumables) do
        if entry.required and entry.count < entry.minimum then
            local detail
            if entry.count == 0 then
                detail = ("No %s in your bags!"):format(entry.label:lower())
            else
                detail = ("Only %d %s (minimum %d)"):format(entry.count, entry.label:lower(), entry.minimum)
            end
            issues[#issues + 1] = {
                slot = 100 + i,
                slotName = entry.label,
                icon = entry.icon,
                kind = "consumable",
                problem = entry.count == 0 and "missing" or "low",
                detail = detail,
            }
        end
    end
    return issues
end

-- Calls func(bag, slot, info) for every item in the backpack and equipped bags.
local function ForEachBagItem(func)
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                func(bag, slot, info)
            end
        end
    end
end

-- Returns consumables ({heal, mana, weapon} entries, also as array) and issues.
function RP.ScanPotions()
    local heal = NewEntry("heal", "Healing Potions", RP.HEALING_POTION_IDS, RP.MIN_HEALING_POTIONS, true)
    local mana = NewEntry("mana", "Mana Potions", RP.MANA_POTION_IDS, RP.MIN_MANA_POTIONS, IsManaPotionRequired())
    local weapon = NewEntry("weapon", "Weapon Buffs", RP.WEAPON_BUFF_IDS, RP.MIN_WEAPON_BUFFS, IsWeaponBuffRequired())
    weapon.activeTime = GetActiveWeaponBuffTime()

    local consumables = { heal, mana, weapon, heal = heal, mana = mana, weapon = weapon }

    ForEachBagItem(function(_, _, info)
        for _, entry in ipairs(consumables) do
            if entry.ids[info.itemID] then
                entry.count = entry.count + (info.stackCount or 1)
                entry.icon = info.iconFileID or C_Item.GetItemIconByID(info.itemID) or entry.icon
            end
        end
    end)

    return consumables, BuildIssues(consumables)
end

-- Item IDs need no item cache, so this completes immediately; kept async for the caller.
function RP.ScanPotionsAsync(callback)
    callback(RP.ScanPotions())
end

-- /rp debug output for consumables.
function RP.DebugPotions()
    local consumables = RP.ScanPotions()
    ForEachBagItem(function(_, _, info)
        for _, entry in ipairs(consumables) do
            if entry.ids[info.itemID] then
                print(("  %s: %s x%d id=%d"):format(entry.label, info.hyperlink or "?",
                    info.stackCount or 1, info.itemID))
            end
        end
    end)
    print(("  mana potions required: %s, weapon buffs required: %s, active weapon buff: %s"):format(
        tostring(IsManaPotionRequired()), tostring(IsWeaponBuffRequired()),
        tostring(GetActiveWeaponBuffTime())))
end
