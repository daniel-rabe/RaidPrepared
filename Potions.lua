local _, PR = ...
local L = PR.L

-- Counts raid consumables in the bags by item ID (see Data.lua): flasks, healing potions,
-- mana potions, power potions and temporary weapon buffs (oils, stones, hunter ammo).

local DEFAULT_ICONS = {
    heal = 134830,   -- INV_Potion_54
    mana = 134851,   -- INV_Potion_76
    weapon = 135255, -- INV_Stone_02
    power = 7548911, -- inv_12_profession_alchemy_lightpotion_yellow
}

-- The icon a kind shows while nothing of it is in the bags. Flasks have no entry above:
-- theirs is taken from the flask item itself, which keeps it right across seasons.
local function DefaultIcon(kind)
    if kind == "flask" then
        return C_Item.GetItemIconByID(PR.FLASK_ICON_ID)
    end
    return DEFAULT_ICONS[kind]
end

-- Label and problem texts per consumable kind (full sentences, so they translate cleanly).
local TEXTS = {
    flask = {
        label = L["Flasks"],
        none = L["No flask in your bags!"],
        few = L["Only %d flasks (minimum %d)"],
    },
    heal = {
        label = L["Healing Potions"],
        none = L["No healing potions in your bags!"],
        few = L["Only %d healing potions (minimum %d)"],
    },
    mana = {
        label = L["Mana Potions"],
        none = L["No mana potions in your bags!"],
        few = L["Only %d mana potions (minimum %d)"],
    },
    power = {
        label = L["Power Potions"],
        none = L["No power potions in your bags!"],
        few = L["Only %d power potions (minimum %d)"],
    },
    weapon = {
        label = L["Weapon Buffs"],
        none = L["No weapon buffs in your bags!"],
        few = L["Only %d weapon buffs (minimum %d)"],
    },
}

local function IsManaPotionRequired()
    local specIndex = PR.GetSpecIndex()
    local role = specIndex and GetSpecializationRole(specIndex)
    return role ~= nil and PR.MANA_POTION_ROLES[role] == true
end

local function IsWeaponBuffRequired()
    local _, classFile = UnitClass("player")
    return not PR.WEAPON_BUFF_EXEMPT_CLASSES[classFile]
end

-- Remaining time of the flask buff that is already running in seconds, or nil.
local function GetActiveFlaskTime()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    for _, spellID in ipairs(PR.FLASK_AURA_IDS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if aura and aura.expirationTime and aura.expirationTime > 0 then
            return aura.expirationTime - GetTime()
        end
    end
    return nil
end

-- Remaining time of the currently applied main-hand temporary enchant in seconds, or nil.
local function GetActiveWeaponBuffTime()
    local hasMainHand, mainHandExpiration = GetWeaponEnchantInfo()
    if hasMainHand and mainHandExpiration then
        return mainHandExpiration / 1000
    end
    return nil
end

local function NewEntry(kind, ids, minimum, required)
    return {
        kind = kind,
        label = TEXTS[kind].label,
        ids = ids,
        minimum = minimum,
        required = required,
        count = 0,
        icon = DefaultIcon(kind),
        items = {},     -- one entry per item ID found, most numerous first
        itemsByID = {}, -- [itemID] = entry in items
    }
end

-- Adds one bag stack to the entry and to its per-item breakdown.
local function AddStack(entry, info)
    local count = info.stackCount or 1
    entry.count = entry.count + count

    local item = entry.itemsByID[info.itemID]
    if not item then
        item = {
            itemID = info.itemID,
            icon = info.iconFileID or C_Item.GetItemIconByID(info.itemID) or entry.icon,
            link = info.hyperlink,
            name = C_Item.GetItemNameByID(info.itemID),
            count = 0,
        }
        entry.itemsByID[info.itemID] = item
        entry.items[#entry.items + 1] = item
    end
    item.count = item.count + count
end

-- Most numerous item first (item ID as tie-breaker, so the order stays stable);
-- that item also gives the entry its icon.
local function SortItems(entry)
    table.sort(entry.items, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.itemID < b.itemID
    end)
    if entry.items[1] then
        entry.icon = entry.items[1].icon
    end
end

local function BuildIssues(consumables)
    local issues = {}
    for i, entry in ipairs(consumables) do
        if entry.required and entry.count < entry.minimum then
            local texts = TEXTS[entry.kind]
            local detail
            if entry.count == 0 then
                detail = texts.none
            else
                detail = texts.few:format(entry.count, entry.minimum)
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

-- Returns consumables ({flask, heal, mana, power, weapon} entries, also as array) and issues.
function PR.ScanPotions()
    local flask = NewEntry("flask", PR.FLASK_IDS, PR.MIN_FLASKS, true)
    flask.activeTime = GetActiveFlaskTime()
    local heal = NewEntry("heal", PR.HEALING_POTION_IDS, PR.MIN_HEALING_POTIONS, true)
    local mana = NewEntry("mana", PR.MANA_POTION_IDS, PR.MIN_MANA_POTIONS, IsManaPotionRequired())
    local power = NewEntry("power", PR.POWER_POTION_IDS, PR.MIN_POWER_POTIONS, true)
    local weapon = NewEntry("weapon", PR.WEAPON_BUFF_IDS, PR.MIN_WEAPON_BUFFS, IsWeaponBuffRequired())
    weapon.activeTime = GetActiveWeaponBuffTime()

    local consumables = {
        flask, heal, mana, power, weapon,
        flask = flask, heal = heal, mana = mana, power = power, weapon = weapon,
    }

    ForEachBagItem(function(_, _, info)
        for _, entry in ipairs(consumables) do
            if entry.ids[info.itemID] then
                AddStack(entry, info)
            end
        end
    end)

    for _, entry in ipairs(consumables) do
        SortItems(entry)
    end

    return consumables, BuildIssues(consumables)
end

-- Item IDs need no item cache, so this completes immediately; kept async for the caller.
function PR.ScanPotionsAsync(callback)
    callback(PR.ScanPotions())
end

-- /pr debug output for consumables.
function PR.DebugPotions()
    local consumables = PR.ScanPotions()
    ForEachBagItem(function(_, _, info)
        for _, entry in ipairs(consumables) do
            if entry.ids[info.itemID] then
                print(("  %s: %s x%d id=%d"):format(entry.label, info.hyperlink or "?",
                    info.stackCount or 1, info.itemID))
            end
        end
    end)
    print(("  mana potions required: %s, weapon buffs required: %s, active weapon buff: %s, active flask: %s"):format(
        tostring(IsManaPotionRequired()), tostring(IsWeaponBuffRequired()),
        tostring(GetActiveWeaponBuffTime()), tostring(GetActiveFlaskTime())))
end
