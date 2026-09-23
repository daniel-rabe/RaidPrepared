local _, PR = ...
local L = PR.L

-- PullReady - Shopping.lua
-- The shopping tab: the enchants, leg armor, gems and consumables of the current
-- season as real item rows. Shift-clicking a row pastes the item link into whatever
-- edit box has focus - the auction house search bar when the auction house is open,
-- the chat edit box otherwise.
--
-- By default only what the player's own scan flagged is listed, so the tab answers
-- "what do I still have to buy" rather than "what exists". The "Show all" option
-- turns it into the full catalog.
--
-- Two independent toggles control what is listed: "Show everything" widens the scope
-- from "what I am missing" to the whole catalog, and "Only favourites" filters
-- whatever that scope produced down to the favourited items. Since the filter can hide
-- everything the wider scope just added, the line next to it always says how many items
-- are shown out of how many the scope holds - otherwise "Show everything" looks broken
-- while "Only favourites" is on.
--
-- Right-clicking a row favourites the item, which pins it to the top of its section.
-- Which ring enchant or gem a character wants is a property of that character, not
-- of the account, so favourites live in the per-character saved variables next to
-- the talent loadout flags.
--
-- What is on offer lives in Data.lua; this file only decides what to show and draws it.

local Shopping = {}
PR.Shopping = Shopping

local ROW_HEIGHT     = 26
local ICON_SIZE      = 22
local SIDE_INSET     = 20
local REFRESH_DELAY  = 0.2
local LOAD_TIMEOUT   = 2

-- Enchantable slots in the order the tab lists them. Legs are not in here: they take
-- a spellthread or an armor kit instead of an enchant and have their own section.
local ENCHANT_ORDER = {
    INVSLOT_HEAD, INVSLOT_SHOULDER, INVSLOT_CHEST, INVSLOT_FEET,
    INVSLOT_FINGER1, INVSLOT_MAINHAND,
}

-- Section headers for the enchant slots. PR.SLOT_NAMES is not usable here: it numbers
-- the paired slots ("Finger 1"), while one enchant list serves both of them.
local function EnchantHeader(slot)
    if slot == INVSLOT_FINGER1 then return FINGER0SLOT or L["Rings"] end
    if slot == INVSLOT_MAINHAND then return WEAPON or L["Weapons"] end
    return PR.SLOT_NAMES[slot] or tostring(slot)
end

-- The mineral name ("Lapis") is the gem family line of the item's own tooltip, so
-- taking it from the client keeps it localized instead of needing a translation per
-- locale. Falls back to the English name in the catalog.
local function GemGroupHeader(group)
    local itemID = group.flawless[1]
    local data = itemID and C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
    local line = data and data.lines and data.lines[2]
    local text = line and line.leftText
    if text and text ~= "" and text ~= C_Item.GetItemNameByID(itemID) then
        return text
    end
    return group.mineral
end

local CONSUMABLE_ORDER = { "flask", "heal", "mana", "power", "weapon" }
local CONSUMABLE_HEADERS = {
    flask  = L["Flasks"],
    heal   = L["Healing Potions"],
    mana   = L["Mana Potions"],
    power  = L["Power Potions"],
    weapon = L["Weapon Buffs"],
}

local panel, scrollChild, hintText, emptyText, countText, showAllCheck, favoritesCheck
local rows = {}
local refreshQueued = false
local refreshToken = 0 -- only the newest refresh draws; a callback of an older one is dropped
local lastNeeds -- the last scan result, so a favourite toggle need not rescan

local function ShowAll()
    return PullReadyDB and PullReadyDB.shoppingShowAll == true
end

-- ============================================================================
-- FAVOURITES
-- ============================================================================

local function FavoritesOnly()
    return PullReadyDB and PullReadyDB.shoppingFavoritesOnly == true
end

local function IsFavorite(itemID)
    local favorites = PullReadyCharDB and PullReadyCharDB.shoppingFavorites
    return (favorites and favorites[itemID]) == true
end

-- Cleared entries are removed rather than set to false, so the saved table only
-- ever holds the items that are actually favourited.
local function ToggleFavorite(itemID)
    PullReadyCharDB.shoppingFavorites = PullReadyCharDB.shoppingFavorites or {}
    local favorites = PullReadyCharDB.shoppingFavorites
    favorites[itemID] = (not favorites[itemID]) or nil
end

-- ============================================================================
-- CATALOG
-- ============================================================================

-- The ranks of one item, best first: a favourited rank beats everything, then the higher
-- item level, then the higher crafting quality, then the higher item ID.
--
-- Item level alone is not enough. The crafting ranks of a consumable mostly share one, and
-- a cold cache reports 0 for every rank, so the first ID of the list used to win by default
-- and pinned the row to rank 1 - while Data.lua lists rank 2 (rank 1 is always ID - 1).
--
-- The favourite comes first because a star is saved for one exact item ID: swapping the row
-- to another rank of the same item would silently lose it, and drop the item out of the list
-- entirely under "Only favourites".
local function RankOf(itemID)
    local quality = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
        and C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
    return {
        itemID   = itemID,
        favorite = IsFavorite(itemID),
        ilvl     = C_Item.GetDetailedItemLevelInfo(itemID) or 0,
        quality  = quality or 0,
    }
end

local function IsBetterRank(a, b)
    if a.favorite ~= b.favorite then return a.favorite end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if a.quality ~= b.quality then return a.quality > b.quality end
    return a.itemID > b.itemID
end

-- One row per item name. The consumable tables list every crafting rank, and two rows
-- for the same potion are just noise, so only the best rank is kept. Needs the item cache
-- to be warm; ids that are still unknown fall back to one row each.
function PR.BuildShopItems(ids)
    local best, order = {}, {}
    for _, itemID in ipairs(ids) do
        local key = C_Item.GetItemNameByID(itemID) or itemID
        local rank = RankOf(itemID)
        if not best[key] then
            order[#order + 1] = key
            best[key] = rank
        elseif IsBetterRank(rank, best[key]) then
            best[key] = rank
        end
    end

    local items = {}
    for _, key in ipairs(order) do
        items[#items + 1] = best[key].itemID
    end
    return items
end

-- Spellthreads grant Intellect, armor kits Agility or Strength, and neither is
-- restricted by armor type - so the spec's primary stat decides, not what the legs
-- are made of. Without a usable spec (no specialization yet, or the API not
-- answering) both lists are offered rather than guessing wrong.
local INTELLECT = LE_UNIT_STAT_INTELLECT or 4

local function LegArmorIDs(showAll)
    local both = {}
    local function append(list)
        for _, itemID in ipairs(list) do both[#both + 1] = itemID end
    end

    if not showAll then
        local specIndex = PR.GetSpecIndex()
        local primaryStat = specIndex and select(6, PR.GetSpecInfo(specIndex))
        if primaryStat == INTELLECT then
            return PR.LEG_ARMOR_ITEMS.intellect
        elseif primaryStat then
            return PR.LEG_ARMOR_ITEMS.physical
        end
    end

    append(PR.LEG_ARMOR_ITEMS.intellect)
    append(PR.LEG_ARMOR_ITEMS.physical)
    return both
end

-- What the scan says is still missing, reduced to the sections the tab can offer.
local function BuildNeeds(issues, consumables)
    local needs = { enchant = {}, legs = false, gems = false, epicGem = false, consumable = {} }

    for _, issue in ipairs(issues) do
        if issue.kind == "enchant" then
            if issue.slot == INVSLOT_LEGS then
                needs.legs = true
            else
                needs.enchant[PR.GetEnchantShopSlot(issue.slot)] = true
            end
        elseif issue.kind == "gem" then
            needs.gems = true
        elseif issue.kind == "epicgem" then
            needs.epicGem = true
        end
    end

    for _, entry in ipairs(consumables) do
        if entry.required and entry.count < entry.minimum then
            needs.consumable[entry.kind] = true
        end
    end
    return needs
end

-- Every item ID the current selection could show, including the ranks BuildShopItems
-- drops again later - the cache has to be warm before a name can be compared.
local function CollectIDs(needs)
    local showAll = ShowAll()
    local ids = {}

    local function add(list)
        for _, itemID in ipairs(list) do
            ids[#ids + 1] = itemID
        end
    end

    for _, slot in ipairs(ENCHANT_ORDER) do
        if showAll or needs.enchant[slot] then add(PR.ENCHANT_ITEMS[slot]) end
    end
    if showAll or needs.legs then add(LegArmorIDs(showAll)) end
    if showAll or needs.gems then
        for _, group in ipairs(PR.GEM_ITEMS) do
            add(group.flawless)
            if showAll then add(group.plain) end
        end
    end
    if showAll or needs.epicGem then add(PR.EPIC_GEM_SHOP_IDS) end
    for _, kind in ipairs(CONSUMABLE_ORDER) do
        if showAll or needs.consumable[kind] then add(PR.CONSUMABLE_SHOP_IDS[kind]) end
    end
    return ids
end

-- The flat display list: { kind = "header"|"item", label | itemID }, and how many items
-- the current scope holds before the favourites filter is applied to it.
local function BuildEntries(needs)
    local showAll = ShowAll()
    local entries = {}
    local total = 0

    local favoritesOnly = FavoritesOnly()

    -- Favourites are pinned to the top of their own section; catalog order is kept
    -- inside both blocks, so the list never reshuffles for any other reason. Under
    -- "Only favourites" a section with no favourite is dropped header and all, and
    -- the remaining sections drop their heading too: what is left is a handful of
    -- hand-picked items, and a heading per item is noise rather than structure.
    local function section(label, ids)
        local favorites, rest = {}, {}
        for _, itemID in ipairs(ids) do
            local block = IsFavorite(itemID) and favorites or rest
            block[#block + 1] = itemID
        end
        total = total + #favorites + #rest
        if favoritesOnly then rest = {} end
        if #favorites + #rest == 0 then return end

        if not favoritesOnly then
            entries[#entries + 1] = { kind = "header", label = label }
        end
        for _, itemID in ipairs(favorites) do
            entries[#entries + 1] = { kind = "item", itemID = itemID }
        end
        for _, itemID in ipairs(rest) do
            entries[#entries + 1] = { kind = "item", itemID = itemID }
        end
    end

    for _, slot in ipairs(ENCHANT_ORDER) do
        if showAll or needs.enchant[slot] then
            section(EnchantHeader(slot), PR.ENCHANT_ITEMS[slot])
        end
    end
    if showAll or needs.legs then
        section(L["Leg Armor"], LegArmorIDs(showAll))
    end
    if showAll or needs.gems then
        for _, group in ipairs(PR.GEM_ITEMS) do
            local ids = {}
            for _, itemID in ipairs(group.flawless) do ids[#ids + 1] = itemID end
            if showAll then
                for _, itemID in ipairs(group.plain) do ids[#ids + 1] = itemID end
            end
            section(GemGroupHeader(group), ids)
        end
    end
    if showAll or needs.epicGem then
        section(L["Epic Gem"], PR.EPIC_GEM_SHOP_IDS)
    end
    for _, kind in ipairs(CONSUMABLE_ORDER) do
        if showAll or needs.consumable[kind] then
            section(CONSUMABLE_HEADERS[kind], PR.BuildShopItems(PR.CONSUMABLE_SHOP_IDS[kind]))
        end
    end

    return entries, total
end

-- ============================================================================
-- ROWS
-- ============================================================================

local function RowOnClick(self, button)
    if not self.itemID then return end

    if button == "RightButton" then
        ToggleFavorite(self.itemID)
        Shopping:Reorder()
        return
    end

    if self.itemLink then
        -- Blizzard's own modified-click dispatcher, the same one the bag and character
        -- sheet buttons use: shift inserts the link into the focused edit box (the
        -- auction house search bar when it is open), ctrl opens the dressing room.
        HandleModifiedItemClick(self.itemLink)
    end
end

local function RowOnEnter(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Right-click to favourite"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:RegisterForClicks("AnyUp")

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.star = row:CreateTexture(nil, "OVERLAY")
    row.star:SetSize(12, 12)
    row.star:SetPoint("RIGHT", -6, 0)
    row.star:SetAtlas("PetJournal-FavoritesIcon")
    row.star:Hide()

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.label:SetPoint("RIGHT", row.star, "LEFT", -4, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row:SetScript("OnClick", RowOnClick)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)

    rows[index] = row
    return row
end

-- A header row carries no item, so it neither highlights nor reacts to a click.
local function SetHeaderRow(row, label)
    row.itemID, row.itemLink = nil, nil
    row.icon:Hide()
    row.star:Hide()
    row.highlight:SetAlpha(0)
    row:EnableMouse(false)
    row.label:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.label:SetFontObject("GameFontNormal")
    -- SetTextColor survives SetFontObject, so a row that showed an epic item before
    -- would keep its purple text as a header.
    row.label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    row.label:SetText(label)
end

local function SetItemRow(row, itemID)
    local name, link, quality = C_Item.GetItemInfo(itemID)
    row.itemID = itemID
    row.itemLink = link
    row.icon:SetTexture(C_Item.GetItemIconByID(itemID) or 134400)
    row.icon:Show()
    row.star:SetShown(IsFavorite(itemID))
    row.highlight:SetAlpha(1)
    row:EnableMouse(true)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.label:SetFontObject("GameFontHighlight")
    row.label:SetText(name or L["item %d"]:format(itemID))

    -- ITEM_QUALITY_COLORS rather than C_Item.GetItemQualityColor: the latter returns
    -- four loose values, not a table, so indexing its result would error.
    local color = quality and ITEM_QUALITY_COLORS[quality]
    if color then
        row.label:SetTextColor(color.r, color.g, color.b)
    else
        row.label:SetTextColor(1, 1, 1)
    end
end

local function Populate(entries, total)
    local shown = 0
    for i, entry in ipairs(entries) do
        local row = rows[i] or CreateRow(i)
        if entry.kind == "header" then
            SetHeaderRow(row, entry.label)
        else
            SetItemRow(row, entry.itemID)
            shown = shown + 1
        end
        row:Show()
    end
    for i = #entries + 1, #rows do
        rows[i]:Hide()
    end

    scrollChild:SetHeight(math.max(1, #entries * ROW_HEIGHT))
    hintText:SetShown(#entries > 0)

    -- What the two toggles actually produced. Without it "Show everything" looks like it
    -- does nothing while "Only favourites" is on: the scope widens to the whole catalog
    -- and the filter cuts it straight back to the same handful of rows, so the total is
    -- the only thing that visibly moves.
    total = total or shown
    countText:SetText(shown < total and L["Showing %d of %d items"]:format(shown, total)
        or L["%d items"]:format(total))
    countText:SetShown(total > 0)

    -- An empty list under "Only favourites" usually means no favourites have been
    -- set yet, which is worth saying instead of claiming everything is bought.
    if #entries > 0 then
        emptyText:Hide()
    elseif FavoritesOnly() then
        emptyText:SetText(L["No favourites yet - right-click an item to add one."])
        emptyText:SetTextColor(0.65, 0.65, 0.65)
        emptyText:Show()
    else
        emptyText:SetText(L["Nothing to buy!"])
        emptyText:SetTextColor(0.1, 1.0, 0.1)
        emptyText:Show()
    end
end

-- ============================================================================
-- REFRESH
-- ============================================================================

local function Visible()
    return panel and panel:IsVisible()
end

-- Redraws from the last scan. Favouriting only reorders or filters the list, so it
-- does not need the gear and bags read again.
function Shopping:Reorder()
    if not Visible() or not lastNeeds then return end
    Populate(BuildEntries(lastNeeds))
end

function Shopping:Refresh()
    if not Visible() then return end

    refreshToken = refreshToken + 1
    local token = refreshToken

    PR.ScanUnitAsync("player", true, function(issues)
        -- The scan is async: the tab may have been closed, or a newer refresh started.
        if token ~= refreshToken or not Visible() then return end

        local consumables = PR.ScanPotions()
        local needs = BuildNeeds(issues, consumables)
        lastNeeds = needs

        local function Draw()
            if token ~= refreshToken or not Visible() then return end
            Populate(BuildEntries(needs))
        end

        -- Names and links are compared while building the list, so warm the cache first.
        local items = ContinuableContainer:Create()
        for _, itemID in ipairs(CollectIDs(needs)) do
            items:AddContinuable(Item:CreateFromItemID(itemID))
        end
        items:ContinueOnLoad(Draw)

        -- ContinueOnLoad only fires once every single item has loaded, and an item ID the
        -- client cannot resolve never loads at all - one stale ID in the catalog would
        -- leave the tab sitting on its old contents for good, which "Show everything" runs
        -- into first since it asks for the whole catalog. So draw what is cached once the
        -- wait is up; the rows that missed out show the item ID and fill themselves in on
        -- the next refresh, and a Draw arriving late from ContinueOnLoad is just a redraw.
        C_Timer.After(LOAD_TIMEOUT, Draw)
    end)
end

-- Bag and equipment changes arrive in bursts, so debounce instead of rebuilding
-- the list once per event.
local function QueueRefresh()
    if refreshQueued or not Visible() then return end
    refreshQueued = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshQueued = false
        Shopping:Refresh()
    end)
end

-- ============================================================================
-- PANEL
-- ============================================================================

function Shopping:CreatePanel(parent)
    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()

    hintText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetPoint("TOPLEFT", SIDE_INSET + 4, -48)
    hintText:SetPoint("RIGHT", panel, "RIGHT", -SIDE_INSET - 4, 0)
    hintText:SetJustifyH("LEFT")
    hintText:SetText(L["Shift-click an item to paste it into the auction house search."])

    showAllCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    showAllCheck:SetSize(24, 24)
    showAllCheck:SetPoint("TOPLEFT", hintText, "BOTTOMLEFT", -4, -6)
    showAllCheck:SetScript("OnClick", function(self)
        PullReadyDB.shoppingShowAll = self:GetChecked() and true or false
        Shopping:Refresh()
    end)

    local showAllLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    showAllLabel:SetPoint("LEFT", showAllCheck, "RIGHT", 2, 1)
    showAllLabel:SetText(L["Show everything, not just what I am missing"])

    -- Stacked rather than side by side: the labels are long enough in German and
    -- Russian that two of them on one row would run off the frame.
    favoritesCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    favoritesCheck:SetSize(24, 24)
    favoritesCheck:SetPoint("TOPLEFT", showAllCheck, "BOTTOMLEFT", 0, -2)
    favoritesCheck:SetScript("OnClick", function(self)
        PullReadyDB.shoppingFavoritesOnly = self:GetChecked() and true or false
        Shopping:Reorder()
    end)

    local favoritesLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    favoritesLabel:SetPoint("LEFT", favoritesCheck, "RIGHT", 2, 1)
    favoritesLabel:SetText(L["Only favourites"])

    -- Next to the filter it explains, not under it: "Only favourites" is the short label
    -- of the two, so the rest of that row is free in every locale.
    countText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countText:SetPoint("LEFT", favoritesLabel, "RIGHT", 12, 0)
    countText:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", SIDE_INSET, -130)
    scroll:SetPoint("BOTTOMRIGHT", -38, 20)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(parent:GetWidth() - 58, 1)
    scroll:SetScrollChild(scrollChild)

    -- LEFT and RIGHT alone: both carry the vertical centre of the scroll frame, so a CENTER
    -- point on top of them would only be a second, conflicting answer for the same x.
    emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    emptyText:SetPoint("LEFT", scroll, "LEFT", 8, 0)
    emptyText:SetPoint("RIGHT", scroll, "RIGHT", -8, 0)
    emptyText:Hide()

    panel:SetScript("OnShow", function()
        showAllCheck:SetChecked(ShowAll())
        favoritesCheck:SetChecked(FavoritesOnly())
        Shopping:Refresh()
    end)
    panel:SetScript("OnHide", GameTooltip_Hide)

    return panel
end

function Shopping:Open()
    PR.Dialog:OpenTab(PR.Dialog.TAB_SHOPPING)
end

function Shopping:Toggle()
    PR.Dialog:ToggleTab(PR.Dialog.TAB_SHOPPING)
end

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("SOCKET_INFO_UPDATE")
events:SetScript("OnEvent", QueueRefresh)
