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
-- whatever that scope produced down to the favourited items.
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

-- Cloth wearers get spellthreads, everyone else armor kits. Used only when no leg
-- item is equipped; otherwise the equipped item's own armor subclass decides.
local CLOTH_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true }

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

local panel, scrollChild, hintText, emptyText, showAllCheck, favoritesCheck
local rows = {}
local refreshQueued = false
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

-- One row per item name. The consumable tables list every crafting rank, and two rows
-- for the same potion are just noise, so the lower item level is dropped. Needs the
-- item cache to be warm; ids that are still unknown fall back to one row each.
function PR.BuildShopItems(ids)
    local best, order = {}, {}
    for _, itemID in ipairs(ids) do
        local key = C_Item.GetItemNameByID(itemID) or itemID
        local ilvl = C_Item.GetDetailedItemLevelInfo(itemID) or 0
        local current = best[key]
        if not current then
            order[#order + 1] = key
            best[key] = { itemID = itemID, ilvl = ilvl }
        elseif ilvl > current.ilvl then
            current.itemID, current.ilvl = itemID, ilvl
        end
    end

    local items = {}
    for _, key in ipairs(order) do
        items[#items + 1] = best[key].itemID
    end
    return items
end

-- Spellthreads for cloth legs, armor kits for everything else.
local function LegArmorIDs()
    local link = GetInventoryItemLink("player", INVSLOT_LEGS)
    if link then
        local subclassID = select(7, C_Item.GetItemInfoInstant(link))
        local cloth = Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cloth or 1
        return subclassID == cloth and PR.LEG_ARMOR_ITEMS.cloth or PR.LEG_ARMOR_ITEMS.physical
    end

    local _, classFile = UnitClass("player")
    return CLOTH_CLASSES[classFile] and PR.LEG_ARMOR_ITEMS.cloth or PR.LEG_ARMOR_ITEMS.physical
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
    if showAll or needs.legs then add(LegArmorIDs()) end
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

-- The flat display list: { kind = "header"|"item", label | itemID }.
local function BuildEntries(needs)
    local showAll = ShowAll()
    local entries = {}

    local favoritesOnly = FavoritesOnly()

    -- Favourites are pinned to the top of their own section; catalog order is kept
    -- inside both blocks, so the list never reshuffles for any other reason. Under
    -- "Only favourites" a section with no favourite is dropped header and all,
    -- rather than left as a bare heading.
    local function section(label, ids)
        local favorites, rest = {}, {}
        for _, itemID in ipairs(ids) do
            local block = IsFavorite(itemID) and favorites or rest
            block[#block + 1] = itemID
        end
        if favoritesOnly then rest = {} end
        if #favorites + #rest == 0 then return end

        entries[#entries + 1] = { kind = "header", label = label }
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
        section(L["Leg Armor"], LegArmorIDs())
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

    return entries
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

local function Populate(entries)
    for i, entry in ipairs(entries) do
        local row = rows[i] or CreateRow(i)
        if entry.kind == "header" then
            SetHeaderRow(row, entry.label)
        else
            SetItemRow(row, entry.itemID)
        end
        row:Show()
    end
    for i = #entries + 1, #rows do
        rows[i]:Hide()
    end

    scrollChild:SetHeight(math.max(1, #entries * ROW_HEIGHT))
    hintText:SetShown(#entries > 0)

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

    PR.ScanUnitAsync("player", true, function(issues)
        -- The scan is async: the tab may have been closed meanwhile.
        if not Visible() then return end

        local consumables = PR.ScanPotions()
        local needs = BuildNeeds(issues, consumables)
        lastNeeds = needs

        -- Names and links are compared while building the list, so warm the cache first.
        local items = ContinuableContainer:Create()
        for _, itemID in ipairs(CollectIDs(needs)) do
            items:AddContinuable(Item:CreateFromItemID(itemID))
        end
        items:ContinueOnLoad(function()
            if not Visible() then return end
            Populate(BuildEntries(needs))
        end)
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

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", SIDE_INSET, -130)
    scroll:SetPoint("BOTTOMRIGHT", -38, 20)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(parent:GetWidth() - 58, 1)
    scroll:SetScrollChild(scrollChild)

    emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    emptyText:SetPoint("CENTER", scroll, "CENTER")
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
