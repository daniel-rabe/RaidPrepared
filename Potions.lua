local _, RP = ...

-- Counts raid consumables in the bags: healing potions, mana potions and temporary
-- weapon buffs (oils, sharpening stones, weightstones, ...).

local HEALTH_WORD = (HEALTH or "Health"):lower()
local MANA_WORD = (MANA or "Mana"):lower()
local WEAPON_WORD = (WEAPON or "Weapon"):lower()
local USE_PREFIX = (ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower()

local CONSUMABLE_CLASS = Enum.ItemClass and Enum.ItemClass.Consumable or 0
local POTION_SUBCLASS = Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Potion or 1

local DEFAULT_ICONS = {
    heal = 134830,   -- INV_Potion_54
    mana = 134851,   -- INV_Potion_76
    weapon = 135255, -- INV_Stone_02
}

-- itemID -> { heal = bool, mana = bool, weapon = bool }
local typeCache = {}

local function IsCandidate(itemID)
    if RP.EXTRA_HEALING_ITEMS[itemID] or RP.EXTRA_MANA_ITEMS[itemID] or RP.EXTRA_WEAPON_BUFF_ITEMS[itemID] then
        return true
    end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == CONSUMABLE_CLASS
end

local function StripCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", ""):gsub("|T.-|t", ""))
end

-- Classifies a consumable by its "Use:" tooltip text (localized via HEALTH/MANA/WEAPON globals).
-- Health/mana only count for items in the Potion subclass (so food is ignored);
-- weapon buffs are non-potion consumables whose use text mentions the weapon.
local function GetConsumableType(bag, slot, itemID)
    local cached = typeCache[itemID]
    if cached then return cached end

    local result = {
        heal = RP.EXTRA_HEALING_ITEMS[itemID] == true,
        mana = RP.EXTRA_MANA_ITEMS[itemID] == true,
        weapon = RP.EXTRA_WEAPON_BUFF_ITEMS[itemID] == true,
    }
    local subclassID = select(7, C_Item.GetItemInfoInstant(itemID))
    local isPotion = subclassID == POTION_SUBCLASS

    local data = C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
    if data and data.lines then
        for _, line in ipairs(data.lines) do
            local text = line.leftText and StripCodes(line.leftText):lower()
            if text and text:find(USE_PREFIX, 1, true) == 1 then
                if isPotion then
                    if text:find(HEALTH_WORD, 1, true) and not next(RP.HEALING_POTION_NAMES) then
                        result.heal = true
                    end
                    if text:find(MANA_WORD, 1, true) and not next(RP.MANA_POTION_NAMES) then
                        result.mana = true
                    end
                elseif text:find(WEAPON_WORD, 1, true) then
                    result.weapon = true
                end
            end
        end
        typeCache[itemID] = result
    end

    local name = C_Item.GetItemNameByID(itemID)
    if name then
        if RP.HEALING_POTION_NAMES[name] then result.heal = true end
        if RP.MANA_POTION_NAMES[name] then result.mana = true end
    end
    return result
end

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

local function NewEntry(kind, label, minimum, required)
    return {
        kind = kind,
        label = label,
        minimum = minimum,
        required = required,
        count = 0,
        outdated = 0,
        icon = DEFAULT_ICONS[kind],
    }
end

local function AddToEntry(entry, itemID, stackCount)
    local expacID = select(15, C_Item.GetItemInfo(itemID))
    if expacID and RP.MIN_CONSUMABLE_EXPANSION and expacID < RP.MIN_CONSUMABLE_EXPANSION then
        entry.outdated = entry.outdated + stackCount
        return
    end
    entry.count = entry.count + stackCount
    entry.icon = C_Item.GetItemIconByID(itemID) or entry.icon
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
            if entry.outdated > 0 then
                detail = detail .. (" - %d outdated not counted"):format(entry.outdated)
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

local function GetBagRange()
    return BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
end

-- Synchronous count. Returns consumables ({heal, mana, weapon} entries, also as array) and issues.
function RP.ScanPotions()
    local heal = NewEntry("heal", "Healing Potions", RP.MIN_HEALING_POTIONS, true)
    local mana = NewEntry("mana", "Mana Potions", RP.MIN_MANA_POTIONS, IsManaPotionRequired())
    local weapon = NewEntry("weapon", "Weapon Buffs", RP.MIN_WEAPON_BUFFS, IsWeaponBuffRequired())
    weapon.activeTime = GetActiveWeaponBuffTime()

    local first, last = GetBagRange()
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and IsCandidate(info.itemID) then
                local itemType = GetConsumableType(bag, slot, info.itemID)
                local stackCount = info.stackCount or 1
                if itemType.heal then AddToEntry(heal, info.itemID, stackCount) end
                if itemType.mana then AddToEntry(mana, info.itemID, stackCount) end
                if itemType.weapon then AddToEntry(weapon, info.itemID, stackCount) end
            end
        end
    end

    local consumables = { heal, mana, weapon, heal = heal, mana = mana, weapon = weapon }
    return consumables, BuildIssues(consumables)
end

-- Loads consumable item data into the cache first, then counts.
function RP.ScanPotionsAsync(callback)
    local container = ContinuableContainer:Create()
    local first, last = GetBagRange()
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and IsCandidate(itemID) then
                container:AddContinuable(Item:CreateFromBagAndSlot(bag, slot))
            end
        end
    end
    container:ContinueOnLoad(function()
        callback(RP.ScanPotions())
    end)
end

-- /rp debug output for consumables.
function RP.DebugPotions()
    local first, last = GetBagRange()
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and IsCandidate(info.itemID) then
                local itemType = GetConsumableType(bag, slot, info.itemID)
                if itemType.heal or itemType.mana or itemType.weapon then
                    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(info.itemID)
                    print(("  consumable %s x%d id=%d class=%s/%s expac=%s heal=%s mana=%s weapon=%s"):format(
                        info.hyperlink or "?", info.stackCount or 1, info.itemID,
                        tostring(classID), tostring(subclassID),
                        tostring(select(15, C_Item.GetItemInfo(info.itemID))),
                        tostring(itemType.heal), tostring(itemType.mana), tostring(itemType.weapon)))
                end
            end
        end
    end
    print(("  mana potions required: %s, weapon buffs required: %s, active weapon buff: %s"):format(
        tostring(IsManaPotionRequired()), tostring(IsWeaponBuffRequired()),
        tostring(GetActiveWeaponBuffTime())))
end
