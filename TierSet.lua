local _, PR = ...
local L = PR.L

-- Tier ("class") set check: how many pieces of this season's set a unit wears, which set
-- bonus that gives, and - for the player, whose currency is readable - whether the catalyst
-- charges would still buy the pieces missing for a better bonus. Runs for the player and
-- for inspected group members (see RaidCheck.lua). Patch-specific parts live in Data.lua.

local ISSUE_SLOT = 110 -- sort position of the tier set warning (after the consumables)
local FALLBACK_ICON = "Interface\\Icons\\INV_Chest_Plate04"

-- The set line of an item tooltip: "%s (%d/%d)" -> "^(.+) %((%d+)/(%d+)%)$" (localized).
local SET_LINE_PATTERN
do
    local fmt = ITEM_SET_NAME or "%s (%d/%d)"
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    SET_LINE_PATTERN = "^" .. fmt:gsub("%%s", "(.+)"):gsub("%%d", "%%d+") .. "$"
end

-- The specs to ask about set bonuses. A unit's own spec is the answer wherever the client
-- knows it; otherwise every spec of its class will do, since each of them has a set bonus
-- for the same pieces and only the item's membership in the set is being read here.
local function GetSpecIDs(unit)
    local specID
    if UnitIsUnit(unit, "player") then
        local specIndex = PR.GetSpecIndex()
        specID = specIndex and PR.GetSpecInfo(specIndex)
    else
        specID = PR.GetInspectSpecID(unit)
    end
    if specID and specID > 0 then return { specID } end
    return PR.GetClassSpecIDs(select(3, UnitClass(unit)))
end

-- The set bonus spells of an item, sorted, or nil when it is not part of a set with
-- bonuses. Every piece of a set returns the same spell IDs, which is what makes them
-- usable as a fingerprint of the set.
local function GetSetBonusSpells(specIDs, itemID)
    if not (itemID and C_Item.GetSetBonusesForSpecializationByItemID) then return nil end

    for _, specID in ipairs(specIDs) do
        local spells = C_Item.GetSetBonusesForSpecializationByItemID(specID, itemID)
        if type(spells) == "table" then
            local ids = {}
            for _, spellID in pairs(spells) do
                if type(spellID) == "number" then
                    ids[#ids + 1] = spellID
                end
            end
            if #ids > 0 then
                table.sort(ids)
                return ids
            end
        end
    end
    return nil
end

-- Set pieces of an earlier expansion are not this season's tier set. An item whose info is
-- not cached yet has no expansion ID; it counts rather than being silently dropped.
local function IsCurrentExpansion(link)
    local expacID = select(15, C_Item.GetItemInfo(link))
    return not (expacID and PR.MIN_TIER_SET_EXPANSION) or expacID >= PR.MIN_TIER_SET_EXPANSION
end

local function NewPiece(unit, slot, link)
    return {
        slot = slot,
        slotName = PR.SLOT_NAMES[slot] or tostring(slot),
        link = link,
        icon = link and GetInventoryItemTexture(unit, slot) or nil,
    }
end

-- One entry per item set worn across the tier slots, in slot order. The bonus spells
-- identify the set wherever the API is there: an item set ID on its own also covers sets
-- that grant no bonus at all, such as the PvP sets. Grouping by set ID is the fallback for
-- a client (or a class) the bonus API has nothing to say about.
local function CollectSets(unit, specIDs)
    local sets, order = {}, {}
    local bySetID = not (#specIDs > 0 and C_Item.GetSetBonusesForSpecializationByItemID)
    for _, slot in ipairs(PR.TIER_SET_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link and IsCurrentExpansion(link) then
            local itemID = C_Item.GetItemInfoInstant(link)
            local spells = not bySetID and GetSetBonusSpells(specIDs, itemID) or nil
            local setID = select(16, C_Item.GetItemInfo(link))
            local key = bySetID and setID and ("set:" .. setID)
                or (spells and table.concat(spells, ":"))
            if key then
                local set = sets[key]
                if not set then
                    set = { setID = setID, spells = spells, hasBonus = spells ~= nil, pieces = {} }
                    sets[key] = set
                    order[#order + 1] = set
                end
                set.pieces[#set.pieces + 1] = NewPiece(unit, slot, link)
            end
        end
    end
    return order
end

-- The set that counts: one with bonuses beats one without, then the one with most pieces.
local function PickSet(sets)
    local best
    for _, set in ipairs(sets) do
        if not best or (set.hasBonus and not best.hasBonus)
            or (set.hasBonus == best.hasBonus and #set.pieces > #best.pieces) then
            best = set
        end
    end
    return best
end

-- The set name as the tooltip of an equipped piece spells it out, e.g. "Dawnlit Regalia"
-- out of "Dawnlit Regalia (2/5)". Localized by the client, so nothing to translate here.
local function GetSetNameFromTooltip(unit, slot)
    local data = C_TooltipInfo and C_TooltipInfo.GetInventoryItem(unit, slot)
    if not (data and data.lines) then return nil end

    for _, line in ipairs(data.lines) do
        local name = line.leftText and line.leftText:match(SET_LINE_PATTERN)
        if name then
            name = name:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            name = strtrim(name)
            if name ~= "" then return name end
        end
    end
    return nil
end

local function GetSetName(unit, set)
    if not set then return nil end
    local name = set.pieces[1] and GetSetNameFromTooltip(unit, set.pieces[1].slot)
    if name then return name end
    if set.setID and C_Item.GetItemSetInfo then
        name = C_Item.GetItemSetInfo(set.setID)
        if type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

-- The catalyst charges of this character. The currencies are listed newest season first in
-- Data.lua and the first one the character has already seen wins, so charges left over from
-- an older season are only reported while the current currency has not shown up yet.
local function GetCatalystCurrency()
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end

    local fallback
    for _, currencyID in ipairs(PR.CATALYST_CURRENCY_IDS) do
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info then
            local currency = {
                id = currencyID,
                name = info.name,
                icon = info.iconFileID,
                charges = info.quantity or 0,
            }
            if info.discovered then return currency end
            fallback = fallback or currency
        end
    end
    return fallback
end

-- State of every bonus threshold, the next one that is not active yet, and the best one the
-- charges on hand could still buy (one charge converts one piece).
local function BuildBonuses(count, charges)
    local bonuses, nextBonus, upgrade = {}, nil, nil
    for _, pieces in ipairs(PR.TIER_SET_BONUS_PIECES) do
        local bonus = { pieces = pieces, active = count >= pieces, needed = math.max(0, pieces - count) }
        bonuses[#bonuses + 1] = bonus
        if not bonus.active then
            nextBonus = nextBonus or bonus
            if bonus.needed <= charges then
                upgrade = bonus -- thresholds ascend, so the last affordable one wins
            end
        end
    end
    return bonuses, nextBonus, upgrade
end

-- Only a bonus that is actually within reach is a problem: with no charges to convert
-- anything there is nothing to do about it before the pull.
local function BuildIssues(entry)
    if not entry.upgrade then return {} end
    return { {
        slot = ISSUE_SLOT,
        slotName = entry.name or entry.label,
        icon = entry.icon,
        kind = "tierset",
        problem = "low",
        detail = L["%d piece(s) short of the %d-piece bonus - %d catalyst charge(s) ready"]
            :format(entry.upgrade.needed, entry.upgrade.pieces, entry.charges),
    } }
end

-- Tier set state of a unit ("player" or an inspected group member). Item data should be
-- cached (see PR.ScanUnitAsync); currency is the player's catalyst charges, or nil for a
-- unit whose charges cannot be read. Shaped like the consumable entries of Potions.lua.
function PR.ScanUnitTierSet(unit, currency)
    local set = PickSet(CollectSets(unit, GetSpecIDs(unit)))
    local pieces = set and set.pieces or {}
    local charges = currency and currency.charges or 0
    local bonuses, nextBonus, upgrade = BuildBonuses(#pieces, charges)

    local active -- highest bonus that is running, nil below the first threshold
    for _, bonus in ipairs(bonuses) do
        if bonus.active then active = bonus end
    end

    -- The tier slots holding something else: those are what the catalyst would convert.
    local wornSlots = {}
    for _, piece in ipairs(pieces) do
        wornSlots[piece.slot] = true
    end
    local convertible = {}
    for _, slot in ipairs(PR.TIER_SET_SLOTS) do
        local link = not wornSlots[slot] and GetInventoryItemLink(unit, slot)
        if link then
            convertible[#convertible + 1] = NewPiece(unit, slot, link)
        end
    end

    return {
        kind = "tier",
        label = L["Tier Set"],
        name = GetSetName(unit, set),
        count = #pieces,
        maxPieces = #PR.TIER_SET_SLOTS,
        pieces = pieces,
        convertible = convertible,
        bonuses = bonuses,
        active = active,
        nextBonus = nextBonus,
        upgrade = upgrade,
        currency = currency,
        charges = charges,
        icon = (pieces[1] and pieces[1].icon) or (currency and currency.icon) or FALLBACK_ICON,
    }
end

-- The player's tier set entry plus the issues of the personal check.
function PR.ScanTierSet()
    local entry = PR.ScanUnitTierSet("player", GetCatalystCurrency())
    return entry, BuildIssues(entry)
end

-- The set ID and expansion of an equipped item need the item cache. PR.ScanAsync has
-- usually warmed it already; this keeps the module usable on its own.
function PR.ScanTierSetAsync(callback)
    local items = ContinuableContainer:Create()
    for _, slot in ipairs(PR.TIER_SET_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            items:AddContinuable(Item:CreateFromItemID(itemID))
        end
    end
    items:ContinueOnLoad(function()
        callback(PR.ScanTierSet())
    end)
end

-- /pr debug output for the tier set.
function PR.DebugTierSet()
    local entry = PR.ScanTierSet()
    print(("  tier set: %s %d/%d (specs %s)"):format(entry.name or "?", entry.count, entry.maxPieces,
        table.concat(GetSpecIDs("player"), ",")))
    for _, piece in ipairs(entry.pieces) do
        print(("    %s: %s"):format(piece.slotName, piece.link or "?"))
    end
    for _, bonus in ipairs(entry.bonuses) do
        print(("    %d-piece: %s"):format(bonus.pieces, tostring(bonus.active)))
    end
    print(("    catalyst: %s (id %s) charges=%d, reachable bonus=%s"):format(
        entry.currency and entry.currency.name or "?",
        entry.currency and tostring(entry.currency.id) or "?",
        entry.charges, entry.upgrade and tostring(entry.upgrade.pieces) or "none"))
end
