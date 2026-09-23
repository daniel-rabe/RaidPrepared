local _, PR = ...
local L = PR.L

-- Durability of the equipped gear: how much of it is left overall, what every single
-- item still has, and a warning for each one that is broken or worn below
-- PR.MIN_DURABILITY. Only the player's own gear can be read (GetInventoryItemDurability
-- takes no unit), so this never runs for inspected group members.

local ICON = "Interface\\Icons\\Trade_BlackSmithing"

-- Rounded down, so an item just short of the minimum is not shown as the percentage
-- that would have been fine.
local function Display(percent)
    return math.floor(percent * 100)
end

local function NewItem(slot, current, maximum)
    local percent = current / maximum
    local item = {
        slot = slot,
        slotName = PR.SLOT_NAMES[slot] or tostring(slot),
        link = GetInventoryItemLink("player", slot),
        icon = GetInventoryItemTexture("player", slot),
        current = current,
        maximum = maximum,
        percent = percent,
        display = Display(percent),
        broken = current <= 0,
    }
    item.worn = not item.broken and percent < PR.MIN_DURABILITY
    return item
end

-- A broken item is the same class of problem as a missing enchant: it does nothing at
-- all until it is repaired. Everything else that is worn down is a warning.
local function BuildIssues(entry)
    local issues = {}
    for _, item in ipairs(entry.items) do
        if item.broken or item.worn then
            issues[#issues + 1] = {
                slot = item.slot,
                slotName = item.slotName,
                itemLink = item.link,
                kind = "durability",
                problem = item.broken and "missing" or "low",
                detail = item.broken and L["Broken - repair before the pull"]
                    or L["Durability %d%% (minimum %d%%)"]:format(item.display, entry.minimum),
            }
        end
    end
    return issues
end

-- Durability of the player's gear plus the issues of the personal check. Shaped like the
-- consumable entries of Potions.lua. Items that cannot break at all (rings, neck,
-- trinkets, cloak) have no durability and are left out entirely.
function PR.ScanDurability()
    local items, current, maximum = {}, 0, 0
    local broken, worn = 0, 0

    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local itemCurrent, itemMaximum = GetInventoryItemDurability(slot)
        if itemCurrent and itemMaximum and itemMaximum > 0 then
            local item = NewItem(slot, itemCurrent, itemMaximum)
            items[#items + 1] = item
            current, maximum = current + itemCurrent, maximum + itemMaximum
            if item.broken then
                broken = broken + 1
            elseif item.worn then
                worn = worn + 1
            end
        end
    end

    -- Worst first: that is the piece the warning is about and the one worth seeing first.
    table.sort(items, function(a, b)
        if a.percent ~= b.percent then return a.percent < b.percent end
        return a.slot < b.slot
    end)

    local percent = maximum > 0 and (current / maximum) or 1
    local entry = {
        kind = "durability",
        label = L["Durability"],
        items = items,
        lowest = items[1],
        current = current,
        maximum = maximum,
        percent = percent,
        display = Display(percent),
        broken = broken,
        worn = worn,
        minimum = Display(PR.MIN_DURABILITY),
        icon = ICON,
    }
    return entry, BuildIssues(entry)
end

-- /pr debug output for durability.
function PR.DebugDurability()
    local entry = PR.ScanDurability()
    print(("  durability: %d%% (%d/%d), %d broken, %d below %d%%"):format(
        entry.display, entry.current, entry.maximum, entry.broken, entry.worn, entry.minimum))
    for _, item in ipairs(entry.items) do
        print(("    %s: %d/%d (%d%%) %s"):format(item.slotName, item.current, item.maximum,
            item.display, item.link or "?"))
    end
end
