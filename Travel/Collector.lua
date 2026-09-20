-- PullReady - Travel/Collector.lua
-- Turns the candidate tables in Data/ into the list of travel options this
-- character actually owns, with resolved names and icons.

local _, PR = ...
local T = PR.Travel

T.Collector = T.Collector or {}
local Collector = T.Collector

local cache      = nil    -- array of resolved options
local cacheDirty = true
local discovered = {}     -- [spellID] = keywords, dungeon teleports found in the spellbook

---Unique, stable identity for an entry. Also the saved-variable key.
local function EntryKey(kind, id)
    return kind .. ":" .. id
end
Collector.EntryKey = EntryKey

-- ============================================================================
-- NAME / ICON RESOLUTION
-- ============================================================================

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and info.name then
            return info.name, info.iconID
        end
    end
    return nil
end

---The spell's tooltip text, or nil when it has not loaded yet.
---Dungeon teleports are named "Path of the Warding Candles" and never mention
---the dungeon, but the description does ("...entrance of Darkflame Cleft"), so
---this is what makes searching by dungeon name work.
local function SpellDescription(id)
    if not (C_Spell and C_Spell.GetSpellDescription) then
        return nil
    end
    local ok, desc = pcall(C_Spell.GetSpellDescription, id)
    if not ok or type(desc) ~= "string" or desc == "" then
        -- Not cached yet. Ask for it; SPELL_DATA_LOAD_RESULT brings us back.
        if C_Spell.RequestLoadSpellData then
            pcall(C_Spell.RequestLoadSpellData, id)
        end
        return nil
    end
    return desc
end
Collector.SpellDescription = SpellDescription

---The destination named in a teleport's description, or nil.
---Turns "Path of the Warding Candles" into "Darkflame Cleft" for display.
local function DestinationName(desc)
    if not desc then
        return nil
    end
    for _, pattern in ipairs(T.Data.destinationPatterns or {}) do
        local found = desc:match(pattern)
        if found then
            -- Strip a lowercase article ("the Temple of the Jade Serpent") but
            -- never a capitalised one - "The MOTHERLODE!!" starts with its name.
            found = found:gsub("^the ", ""):gsub("%s+$", "")
            if found ~= "" then
                return found
            end
        end
    end
    return nil
end
Collector.DestinationName = DestinationName

---Ask the server for item data we do not have cached yet. Toys live in the toy
---box rather than your bags, so their item data is almost never cached at load;
---the answer arrives later as GET_ITEM_INFO_RECEIVED.
local function RequestItemData(id)
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end
Collector.RequestItemData = RequestItemData

local function ItemName(id)
    local name, icon
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, id)
        if ok then name = n end
    end
    if C_Item and C_Item.GetItemIconByID then
        local ok, i = pcall(C_Item.GetItemIconByID, id)
        if ok then icon = i end
    end
    if not name then
        RequestItemData(id)
    end
    return name, icon
end

local function ToyName(id)
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local ok, _, name, icon = pcall(C_ToyBox.GetToyInfo, id)
        if ok and name then
            return name, icon
        end
    end
    -- Toys are items, so the item cache is a valid fallback.
    return ItemName(id)
end

---Resolve display name and icon for an entry, or nil when the ID is unknown.
---A nil result means a bad ID, or item data that is not cached yet.
function Collector.Resolve(kind, id)
    if kind == "spell" then
        return SpellName(id)
    elseif kind == "toy" then
        return ToyName(id)
    else
        return ItemName(id)
    end
end

-- ============================================================================
-- AVAILABILITY
-- ============================================================================

---The form this character actually owns an entry in ("spell", "toy", "item"),
---or nil when they do not have it.
---
---Blizzard converts items into toys over time - the Garrison and Dalaran
---hearthstones are toys now - and the two need different secure attributes to
---cast. So the declared kind in Data/ is only a hint: for anything that is not
---a spell we check the toy box first, then bags, and use whichever the player
---actually has.
function Collector.ResolveKind(kind, id)
    if kind == "spell" then
        return (IsPlayerSpell and IsPlayerSpell(id)) and "spell" or nil
    end

    if PlayerHasToy and PlayerHasToy(id) then
        -- IsToyUsable returns nil while toy data is still loading. Treat that as
        -- usable rather than hiding a toy the player demonstrably owns.
        local usable = true
        if C_ToyBox and C_ToyBox.IsToyUsable then
            local ok, u = pcall(C_ToyBox.IsToyUsable, id)
            if ok and u == false then
                usable = false
            end
        end
        if usable then
            return "toy"
        end
    end

    if C_Item and C_Item.GetItemCount then
        local ok, count = pcall(C_Item.GetItemCount, id)
        if ok and (T.Plain(count) or 0) > 0 then
            return "item"
        end
    end

    return nil
end

---Whether this character currently owns / knows the entry.
function Collector.IsAvailable(kind, id)
    return Collector.ResolveKind(kind, id) ~= nil
end

-- ============================================================================
-- SPELLBOOK WALK
-- ============================================================================

---Expand a spellbook flyout and report the spells inside it.
---Teleports live in flyouts ("Teleport", "Portal", dungeon teleports), so a walk
---that skips flyouts sees the container and misses every spell that matters.
local function ExpandFlyout(flyoutID, fn, lineName)
    -- These are globals, not C_SpellBook members. Resolved at call time so a
    -- future move into C_SpellBook keeps working.
    local flyoutInfo = GetFlyoutInfo or (C_SpellBook and C_SpellBook.GetFlyoutInfo)
    local slotInfo   = GetFlyoutSlotInfo or (C_SpellBook and C_SpellBook.GetFlyoutSlotInfo)
    if not (flyoutInfo and slotInfo) then
        return
    end

    -- GetFlyoutInfo(flyoutID) -> name, description, numSlots, isKnown
    local ok, flyoutName, _, numSlots = pcall(flyoutInfo, flyoutID)
    if not ok or not numSlots or numSlots == 0 then
        return
    end

    local source = (lineName or "?") .. "/" .. (flyoutName or "flyout")
    for slot = 1, numSlots do
        -- GetFlyoutSlotInfo(flyoutID, slot) -> spellID, overrideSpellID, isKnown, spellName
        local okSlot, spellID, _, isKnown, spellName = pcall(slotInfo, flyoutID, slot)
        if okSlot and spellID then
            -- Report unknown slots too: Build filters on IsPlayerSpell anyway,
            -- and seeing them in /pr travel scan is how teleport IDs get harvested.
            fn(spellID, spellName or tostring(spellID), isKnown and source or (source .. " [unknown]"))
        end
    end
end

---Call fn(spellID, name, skillLineName) for every spell in the player spellbook,
---including spells nested inside flyouts. Returns false when the API is
---unavailable.
local function ForEachSpellBookSpell(fn)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then
        return false
    end
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local FLYOUT_TYPE = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout

    local okLines, numLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not okLines or not numLines then
        return false
    end

    for i = 1, numLines do
        local okLine, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
        if okLine and type(line) == "table" and line.numSpellBookItems then
            for j = 1, line.numSpellBookItems do
                local index = (line.itemIndexOffset or 0) + j
                local okItem, info = pcall(C_SpellBook.GetSpellBookItemInfo, index, bank)
                if okItem and type(info) == "table" then
                    if FLYOUT_TYPE and info.itemType == FLYOUT_TYPE then
                        -- actionID is the flyout ID here, never a spell ID.
                        if info.actionID then
                            ExpandFlyout(info.actionID, fn, line.name)
                        end
                    elseif info.spellID and info.name then
                        fn(info.spellID, info.name, line.name)
                    end
                end
            end
        end
    end
    return true
end

local DUNGEON_KEYWORDS = { "dungeon", "mythic", "teleport", "portal" }
local CLASS_KEYWORDS   = { "teleport", "portal", "city" }

---Find teleports in the spellbook by name pattern, taking the category from
---whichever pattern matched. Dungeon and city teleports both live in flyouts,
---so the name is the only thing that separates them.
local function DiscoverDungeonTeleports()
    wipe(discovered)
    local patterns = T.Data.teleportPatterns or {}
    local exclude  = T.Data.dungeonExclude or {}

    ForEachSpellBookSpell(function(spellID, name)
        if exclude[spellID] then
            return
        end
        local lower = name:lower()
        for p = 1, #patterns do
            local rule = patterns[p]
            if lower:find(rule.pattern) then
                discovered[spellID] = {
                    cat      = rule.cat,
                    keywords = rule.cat == "dungeon" and DUNGEON_KEYWORDS or CLASS_KEYWORDS,
                }
                return
            end
        end
    end)

    for _, pair in ipairs(T.Data.dungeonExtra or {}) do
        local id, keywords = pair[1], pair[2]
        if id and IsPlayerSpell and IsPlayerSpell(id) then
            discovered[id] = { cat = "dungeon", keywords = keywords or DUNGEON_KEYWORDS }
        end
    end
end

-- ============================================================================
-- BUILD
-- ============================================================================

local QUESTION_MARK_ICON = 134400

local function AddOption(list, seen, seenName, kind, id, cat, keywords)
    -- Use the form the player owns, not the one the data guessed at; the row's
    -- secure attributes depend on getting this right.
    kind = Collector.ResolveKind(kind, id)
    if not kind then
        return
    end

    local key = EntryKey(kind, id)
    if seen[key] then
        return
    end

    local name, icon = Collector.Resolve(kind, id)
    if not name then
        return
    end

    -- Blizzard ships several teleports under one name (faction or seasonal
    -- variants, e.g. two "Path of the Besieged Harbor"). Showing both would be
    -- two identical rows, so the first one to survive availability wins.
    if seenName[name] then
        return
    end

    local desc = (kind == "spell") and SpellDescription(id) or nil

    -- Dungeon ports are named after flavour ("Path of the Warding Candles"),
    -- so show where they actually go. City teleports already name their
    -- destination, so leave those alone.
    local display
    if cat == "dungeon" then
        display = DestinationName(desc)
    end

    seen[key] = true
    seenName[name] = true
    list[#list + 1] = {
        key      = key,
        kind     = kind,
        id       = id,
        cat      = cat or "other",
        name     = name,
        icon     = icon or QUESTION_MARK_ICON,
        keywords = keywords,
        -- Searchable tooltip text. Only spells have one worth indexing.
        desc     = desc,
        -- What the row shows; falls back to the spell name.
        display  = display or name,
    }
end

---Rebuild the available-options list. Cheap enough to run on events, but never
---call it per keystroke - the search filters the cached result instead.
function Collector.Build()
    local list, seen, seenName = {}, {}, {}

    -- Curated entries first: they carry better categories and search keywords,
    -- and AddOption skips anything already seen.
    for _, e in ipairs(T.Data.entries) do
        AddOption(list, seen, seenName, e.kind, e.id, e.cat, e.keywords)
    end

    DiscoverDungeonTeleports()

    -- Sort discovered IDs so name-deduplication picks the same winner every
    -- rebuild; pairs() order is not stable.
    local ids = {}
    for spellID in pairs(discovered) do
        ids[#ids + 1] = spellID
    end
    table.sort(ids)

    for i = 1, #ids do
        local info = discovered[ids[i]]
        AddOption(list, seen, seenName, "spell", ids[i], info.cat, info.keywords)
    end

    table.sort(list, function(a, b) return a.name < b.name end)

    cache, cacheDirty = list, false
    return list
end

---The available-options list, rebuilt only when something invalidated it.
function Collector.Get()
    if cacheDirty or not cache then
        return Collector.Build()
    end
    return cache
end

function Collector.Invalidate()
    cacheDirty = true
end

-- ============================================================================
-- DIAGNOSTICS
-- ============================================================================

local AUDIT_LIST_LIMIT = 8

---Report every curated entry whose name will not resolve, i.e. a wrong ID.
---Uncached item data resolves itself: the first run requests it, so re-running
---a few seconds later shows only genuinely bad IDs.
function Collector.Audit()
    local bad, total, listed = 0, 0, 0

    for _, e in ipairs(T.Data.entries) do
        total = total + 1
        if not Collector.Resolve(e.kind, e.id) then
            bad = bad + 1
            if listed < AUDIT_LIST_LIMIT then
                listed = listed + 1
                T:Out("|cffff4040unresolved|r %s %d (%s)", e.kind, e.id, e.cat)
            end
        end
    end
    if bad > listed then
        T:Out("|cffff4040...and %d more|r", bad - listed)
    end

    if bad == 0 then
        T:Out("audit: all %d entries resolve.", total)
    else
        T:Out("audit: %d of %d did not resolve. Item data is fetched from the server on demand - wait a few seconds and run |cffffff00/pr travel audit|r again; whatever still fails is a bad ID.", bad, total)
    end
    T:Out("audit: %d option(s) available on this character.", #Collector.Build())
end

---Report exactly what the discovery pass finds, using the real patterns rather
---than a substring. This is the command that answers "why is my dungeon port
---missing" - it shows whether the spell was seen, matched, and is castable.
function Collector.ReportDiscovery()
    DiscoverDungeonTeleports()

    local count = 0
    for spellID, info in pairs(discovered) do
        count = count + 1
        local name = Collector.Resolve("spell", spellID) or "?"
        local known = (IsPlayerSpell and IsPlayerSpell(spellID)) and "" or " [not known]"

        -- The description is what makes a dungeon name searchable, so show it:
        -- an empty one here means that port cannot be found by dungeon name.
        local desc = SpellDescription(spellID)
        desc = desc and desc:gsub("[\r\n]+", " ") or "|cffff4040<no description>|r"

        T:Out("%d  |cffffff00%s|r  cat=%s%s\n        %s", spellID, name, info.cat, known, desc)
    end

    T:Out("discover: %d spell(s) matched the teleport patterns.", count)
    if count == 0 then
        local shown = {}
        for _, rule in ipairs(T.Data.teleportPatterns or {}) do
            shown[#shown + 1] = rule.pattern
        end
        T:Out("Patterns tried: %s", table.concat(shown, ", "))
        T:Out("Run |cffffff00/pr travel scan <part of the port name>|r to find what it is actually called.")
    end
end

---Dump spellbook entries, optionally filtered by a name substring.
function Collector.ScanSpellbook(filter)
    filter = (filter and filter ~= "") and filter:lower() or nil

    local shown, walked = 0, 0
    local ok = ForEachSpellBookSpell(function(spellID, name, lineName)
        walked = walked + 1
        if filter and not name:lower():find(filter, 1, true) then
            return
        end
        shown = shown + 1
        T:Out("%d  |cffffff00%s|r  (%s)", spellID, name, tostring(lineName))
    end)

    if not ok then
        T:Out("|cffff4040scan failed:|r C_SpellBook API unavailable or returned nothing.")
        return
    end

    local lines = select(2, pcall(C_SpellBook.GetNumSpellBookSkillLines)) or "?"
    T:Out("scan: %d shown of %d spell(s) across %s skill line(s)%s.",
        shown, walked, tostring(lines), filter and (" - filter: " .. filter) or "")

    if walked == 0 then
        T:Out("|cffff4040The spellbook walk found no spells at all|r - dungeon teleport discovery cannot work. Please report this.")
    end
end

-- ============================================================================
-- INVALIDATION
-- ============================================================================

---Warm the item cache for every item and toy candidate, so names are ready by
---the time the window is first opened.
function Collector.Prefetch()
    for _, e in ipairs(T.Data.entries) do
        if e.kind ~= "spell" then
            RequestItemData(e.id)
        end
    end
end

local INVALIDATING_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "SPELLS_CHANGED",
    "TOYS_UPDATED",
    "BAG_UPDATE_DELAYED",
    -- Fires once per item as the server answers a RequestLoadItemDataByID.
    "GET_ITEM_INFO_RECEIVED",
    -- Same, for RequestLoadSpellData: descriptions arrive after the first pass.
    "SPELL_DATA_LOAD_RESULT",
}

for _, event in ipairs(INVALIDATING_EVENTS) do
    T:RegisterEvent(event, Collector.Invalidate)
end

T:RegisterEvent("PLAYER_ENTERING_WORLD", Collector.Prefetch)
