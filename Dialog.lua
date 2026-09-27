local addonName, PR = ...
local L = PR.L
local Theme = PR.Theme

local FRAME_WIDTH = 580
local FRAME_HEIGHT = 390
local ROW_HEIGHT = 34

-- Consumable summary: one icon per kind with its stack count, details in the tooltip.
-- The tier set and the gear durability follow the consumables as two more icons in the
-- same row.
-- Tab strip along the bottom inside the frame. Labels are dropped for icons alone
-- when the six translated labels do not fit - German and Russian do not.
local TAB_HEIGHT = 28
local TAB_GAP = 2
local TAB_MARGIN = 14
local TAB_ICON_SIZE = 18
local TAB_PAD = 9
local TAB_LABEL_GAP = 5
local TAB_BOTTOM = 14 -- clears the Blizzard backdrop's 11px bottom inset
local TAB_STRIP_HEIGHT = TAB_HEIGHT + TAB_BOTTOM + 6

-- One per tab, in tab order. Our own glyphs rather than the game's item icons:
-- those are busy little paintings and turn to mush at this size.
local TAB_ICONS = {
    Theme.ICONS.check,
    Theme.ICONS.group,
    Theme.ICONS.talents,
    Theme.ICONS.travel,
    Theme.ICONS.shopping,
    Theme.ICONS.options,
}

local ORNAMENT_SIZE = 84
local FLOURISH_WIDTH = 200
local FLOURISH_HEIGHT = 50
-- The title sits in the top left, as in the mockup, far enough in to clear the
-- corner filigree and stopping short of the crest in the middle of the top edge.
local TITLE_TOP = -22
local TITLE_INSET = 88

-- Every tab panel is inset this far from the top, so its own content clears the
-- title. Each panel keeps its internal spacing: they all anchor to their own top
-- edge, so insetting the panel shifts the whole tab down as one.
local HEADER_PAD = 16
local RING_SIZE = 66

-- How far the edge glow reaches in from the border, and how far the strips sit
-- inside it so they do not paint over the border art itself.
local GLOW_DEPTH = 10
local GLOW_INSET = 4

local POTION_ICON_SIZE = 34
local POTION_ICON_GAP = 26
local POTION_KINDS = { "flask", "heal", "mana", "power", "weapon" }
local TIER_ICON_INDEX = #POTION_KINDS + 1 -- the tier set follows the consumables
local DURABILITY_ICON_INDEX = TIER_ICON_INDEX + 1 -- durability closes the row
local TOOLTIP_ICON = "|T%s:16:16:0:0:64:64:5:59:5:59|t"

-- Quality option: the crafting quality icons the game itself uses, instead of a bare number.
-- The "-12-" set is one symbol per rank; the older set repeats the symbol (rank 2 = two of them).
local QUALITY_ATLASES = {
    "Professions-ChatIcon-Quality-12-Tier%d",
    "Professions-ChatIcon-Quality-Tier%d",
}
local QUALITY_BUTTON_SIZE = 32
local QUALITY_BUTTON_GAP = 6
local QUALITY_ICON_HEIGHT = 24

-- Which palette entry (see Theme.lua) a scan problem is drawn in.
local PROBLEM_STATUS = {
    missing  = "bad",
    low      = "warn",
    outdated = "warn",
}

local Dialog = {}
PR.Dialog = Dialog

Dialog.TAB_CHECK = 1
Dialog.TAB_INSPECT = 2
Dialog.TAB_TALENTS = 3
Dialog.TAB_TRAVEL = 4
Dialog.TAB_SHOPPING = 5
Dialog.TAB_OPTIONS = 6

local frame, scrollChild, titleText, summaryText, summaryBar, okBlock, okText, okSubText
local checkPanel, inspectPanel, talentsPanel, optionsPanel, travelPanel, shoppingPanel
local indicatorsCheck
local qualityButtons = {}
local whisperCheck, whisperDrop, themeDrop
local rows = {}
local pendingIssues, pendingPotions, pendingTierSet, pendingDurability -- waiting for combat to end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    Theme:Register(function(palette)
        row.highlight:SetColorTexture(unpack(palette.rowHighlight))
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 2, 0)

    row.slot = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.slot:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.slot:SetPoint("RIGHT", -4, 0)
    row.slot:SetJustifyH("LEFT")

    row.problem = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.problem:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
    row.problem:SetPoint("RIGHT", -4, 0)
    row.problem:SetJustifyH("LEFT")
    row.problem:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetInventoryItem("player", self.slotID)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    rows[index] = row
    return row
end

-- Red = none, orange = below the minimum, green = enough, grey = not required.
local function PotionStatusColor(entry)
    if not entry.required then
        return Theme:Status("inactive")
    elseif entry.count == 0 then
        return Theme:Status("bad")
    elseif entry.count < entry.minimum then
        return Theme:Status("warn")
    end
    return Theme:Status("ok")
end

-- Lists every item kind the scan found for this consumable, with its quantity.
local function ShowPotionTooltip(self)
    local entry = self.entry
    if not entry then return end
    local r, g, b = PotionStatusColor(entry)

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddDoubleLine(entry.label, tostring(entry.count), 1, 1, 1, r, g, b)
    GameTooltip:AddLine(" ")
    if entry.items and #entry.items > 0 then
        for _, item in ipairs(entry.items) do
            local icon = item.icon and TOOLTIP_ICON:format(item.icon) .. " " or ""
            GameTooltip:AddDoubleLine(icon .. (item.link or item.name or L["item %d"]:format(item.itemID)),
                tostring(item.count), 1, 1, 1, 1, 1, 1)
        end
    else
        GameTooltip:AddLine(L["None in your bags"], Theme:Status("bad"))
    end
    if entry.activeTime then
        GameTooltip:AddLine(L["(active %dm)"]:format(math.floor(entry.activeTime / 60)), Theme:Status("ok"))
    end
    if not entry.required then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Not required"], Theme:Status("inactive"))
    end
    GameTooltip:Show()
end

local function CreatePotionIcon(parent, index)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(POTION_ICON_SIZE, POTION_ICON_SIZE)
    button:SetPoint("LEFT", (index - 1) * (POTION_ICON_SIZE + POTION_ICON_GAP), 0)

    -- Slightly oversized colored texture behind the icon, so it reads as a status border.
    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetPoint("TOPLEFT", -2, 2)
    button.border:SetPoint("BOTTOMRIGHT", 2, -2)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", 2, -2)
    button.count:SetJustifyH("RIGHT")

    button:SetScript("OnEnter", ShowPotionTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

-- Icon, stack count and status color for one consumable kind.
local function UpdatePotionIcon(button, entry)
    button.entry = entry
    if not entry then
        button:Hide()
        return
    end
    local r, g, b = PotionStatusColor(entry)
    button.icon:SetTexture(entry.icon or 134400)
    button.icon:SetDesaturated(entry.count == 0)
    button.icon:SetAlpha(entry.required and 1 or 0.6)
    button.border:SetColorTexture(r, g, b, 0.9)
    button.count:SetText(tostring(entry.count))
    button.count:SetTextColor(r, g, b)
    button:Show()
end

-- Green = best set bonus active, orange = a lesser bonus, red = no bonus at all.
local function TierStatusColor(entry)
    local best = entry.bonuses[#entry.bonuses]
    if best and best.active then
        return Theme:Status("ok")
    elseif entry.active then
        return Theme:Status("warn")
    end
    return Theme:Status("bad")
end

-- Which set is worn, which bonus it grants and what the catalyst charges could still buy.
local function ShowTierTooltip(self)
    local entry = self.entry
    if not entry then return end
    local r, g, b = TierStatusColor(entry)
    local pieces = ("%d/%d"):format(entry.count, entry.maxPieces)

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddDoubleLine(entry.name or entry.label, pieces, 1, 1, 1, r, g, b)
    GameTooltip:AddLine(" ")
    for _, bonus in ipairs(entry.bonuses) do
        local state = bonus.active and L["active"] or L["not active"]
        local br, bg, bb = 0.65, 0.65, 0.65
        if bonus.active then br, bg, bb = 0.25, 1, 0.25 end
        GameTooltip:AddDoubleLine(L["%d-piece bonus"]:format(bonus.pieces), state, 1, 1, 1, br, bg, bb)
    end

    GameTooltip:AddLine(" ")
    if #entry.pieces > 0 then
        for _, piece in ipairs(entry.pieces) do
            local icon = piece.icon and TOOLTIP_ICON:format(piece.icon) .. " " or ""
            GameTooltip:AddDoubleLine(piece.slotName, icon .. (piece.link or ""), 1, 1, 1, 1, 1, 1)
        end
    else
        GameTooltip:AddLine(L["No set pieces equipped"], 1, 0.25, 0.25)
    end

    GameTooltip:AddLine(" ")
    local currency = entry.currency
    local currencyIcon = currency and currency.icon and TOOLTIP_ICON:format(currency.icon) .. " " or ""
    GameTooltip:AddDoubleLine(currencyIcon .. (currency and currency.name or L["Catalyst charges"]),
        tostring(entry.charges), 1, 1, 1, 1, 1, 1)
    if entry.upgrade then
        GameTooltip:AddLine(L["%d piece(s) short of the %d-piece bonus - %d catalyst charge(s) ready"]
            :format(entry.upgrade.needed, entry.upgrade.pieces, entry.charges), 1, 0.6, 0.1, true)
        if #entry.convertible > 0 then
            local slotNames = {}
            for _, piece in ipairs(entry.convertible) do
                slotNames[#slotNames + 1] = piece.slotName
            end
            GameTooltip:AddLine(L["The catalyst could convert: %s"]:format(table.concat(slotNames, ", ")),
                1, 0.82, 0, true)
        end
    elseif entry.nextBonus then
        GameTooltip:AddLine(L["%d piece(s) short of the %d-piece bonus"]
            :format(entry.nextBonus.needed, entry.nextBonus.pieces), 0.65, 0.65, 0.65, true)
    end
    GameTooltip:Show()
end

-- Pieces equipped in the icon's corner, the bonus they grant as a tag on top of it.
local function UpdateTierIcon(button, entry)
    button.entry = entry
    if not entry then
        button:Hide()
        return
    end
    local r, g, b = TierStatusColor(entry)
    button.icon:SetTexture(entry.icon or 134400)
    button.icon:SetDesaturated(entry.count == 0)
    button.border:SetColorTexture(r, g, b, 0.9)
    button.count:SetText(("%d/%d"):format(entry.count, entry.maxPieces))
    button.count:SetTextColor(r, g, b)
    button.bonus:SetText(entry.active and L["%dP"]:format(entry.active.pieces) or "")
    button.bonus:SetTextColor(r, g, b)
    button:Show()
end

-- Green = nothing to repair, orange = something is worn down, red = something is broken.
local function DurabilityStatusColor(entry)
    if #entry.items == 0 then
        return Theme:Status("inactive")
    elseif entry.broken > 0 then
        return Theme:Status("bad")
    elseif entry.worn > 0 then
        return Theme:Status("warn")
    end
    return Theme:Status("ok")
end

-- What every item that can break still has left, worst first.
local function ShowDurabilityTooltip(self)
    local entry = self.entry
    if not entry then return end
    local r, g, b = DurabilityStatusColor(entry)

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddDoubleLine(entry.label, ("%d%%"):format(entry.display), 1, 1, 1, r, g, b)
    GameTooltip:AddLine(" ")
    if #entry.items == 0 then
        GameTooltip:AddLine(L["Nothing equipped that can break"], 0.65, 0.65, 0.65)
        GameTooltip:Show()
        return
    end

    for _, item in ipairs(entry.items) do
        local icon = item.icon and TOOLTIP_ICON:format(item.icon) .. " " or ""
        local ir, ig, ib = 1, 1, 1
        if item.broken then
            ir, ig, ib = Theme:Status("bad")
        elseif item.worn then
            ir, ig, ib = Theme:Status("warn")
        end
        GameTooltip:AddDoubleLine(icon .. item.slotName,
            item.broken and L["Broken"] or ("%d%%"):format(item.display), 1, 1, 1, ir, ig, ib)
    end

    GameTooltip:AddLine(" ")
    if entry.broken > 0 then
        GameTooltip:AddLine(L["%d item(s) broken"]:format(entry.broken), Theme:Status("bad"))
    end
    if entry.worn > 0 then
        GameTooltip:AddLine(L["%d item(s) below %d%%"]:format(entry.worn, entry.minimum),
            Theme:Status("warn"))
    end
    if entry.broken == 0 and entry.worn == 0 then
        GameTooltip:AddLine(L["Nothing needs repairing"], Theme:Status("ok"))
    end
    GameTooltip:Show()
end

-- The durability of the whole gear on the icon, the pieces behind it in the tooltip.
local function UpdateDurabilityIcon(button, entry)
    button.entry = entry
    if not entry then
        button:Hide()
        return
    end
    local r, g, b = DurabilityStatusColor(entry)
    button.icon:SetTexture(entry.icon)
    button.icon:SetDesaturated(entry.broken > 0)
    button.border:SetColorTexture(r, g, b, 0.9)
    button.count:SetText(#entry.items > 0 and ("%d%%"):format(entry.display) or "-")
    button.count:SetTextColor(r, g, b)
    button:Show()
end

-- First atlas set the client actually knows, so an older client still shows an icon.
local function GetQualityAtlas(tier)
    local atlas
    for _, pattern in ipairs(QUALITY_ATLASES) do
        atlas = pattern:format(tier)
        local info = C_Texture.GetAtlasInfo(atlas)
        if info then return atlas, info end
    end
    return atlas, nil
end

-- Marks the selected quality; the others stay visible but dimmed.
local function UpdateQualityButtons()
    local selected = PR.GetMaxQualityTier()
    for _, button in ipairs(qualityButtons) do
        local isSelected = button.tier == selected
        if isSelected then
            local r, g, b = unpack(Theme:Current().title) -- frame on the chosen rank
            button.selection:SetColorTexture(r, g, b, 0.9)
        else
            button.selection:SetColorTexture(0.3, 0.3, 0.3, 0.8)
        end
        button.icon:SetAlpha(isSelected and 1 or 0.6) -- the rank 1 icon is grey, so do not dim it far
    end
end

local function CreateQualityButton(parent, tier)
    local button = CreateFrame("Button", nil, parent)
    button.tier = tier
    button:SetSize(QUALITY_BUTTON_SIZE, QUALITY_BUTTON_SIZE)
    button:SetPoint("LEFT", (tier - PR.MIN_QUALITY_RANK_OPTION) * (QUALITY_BUTTON_SIZE + QUALITY_BUTTON_GAP), 0)

    -- Frame around the button; UpdateQualityButtons colors it gold when selected.
    button.selection = button:CreateTexture(nil, "BACKGROUND")
    button.selection:SetAllPoints()

    button.background = button:CreateTexture(nil, "BORDER")
    button.background:SetPoint("TOPLEFT", 2, -2)
    button.background:SetPoint("BOTTOMRIGHT", -2, 2)
    button.background:SetColorTexture(0, 0, 0, 0.5)

    -- Scaled to the atlas aspect ratio, so the quality icon is not squashed.
    local atlas, info = GetQualityAtlas(tier)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("CENTER")
    button.icon:SetAtlas(atlas)
    local aspect = (info and info.height and info.height > 0) and (info.width / info.height) or 1
    button.icon:SetSize(QUALITY_ICON_HEIGHT * aspect, QUALITY_ICON_HEIGHT)

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.15)

    button:SetScript("OnClick", function(self)
        PR.SetMaxQualityTier(self.tier)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Quality rank %d"]:format(self.tier), 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

-- The corner filigree is one texture reused four times, mirrored through its tex
-- coords; the crest straddles the top edge above the title.
local CORNERS = {
    { point = "TOPLEFT",     x = -10, y = 10,  left = 0, right = 1, top = 0, bottom = 1 },
    { point = "TOPRIGHT",    x = 10,  y = 10,  left = 1, right = 0, top = 0, bottom = 1 },
    { point = "BOTTOMLEFT",  x = -10, y = -10, left = 0, right = 1, top = 1, bottom = 0 },
    { point = "BOTTOMRIGHT", x = 10,  y = -10, left = 1, right = 0, top = 1, bottom = 0 },
}

local CHECKMARK = "Interface\\RaidFrame\\ReadyCheck-Ready"

-- Warms the frame edge without touching the middle of the panel.
--
-- This used to be one texture stretched over the whole frame, which spread its
-- falloff in proportion to the frame and washed the centre out. Four strips of a
-- fixed depth, each fading inwards, keep the panel dark and the glow where it
-- belongs. SetGradient means no texture file is needed at all.
local function CreateEdgeGlow(parent)
    local strips = {}

    -- warmAtMin says which end of the gradient carries the colour: VERTICAL runs
    -- min at the bottom, HORIZONTAL min at the left.
    local function strip(orientation, warmAtMin, place)
        local texture = parent:CreateTexture(nil, "BORDER")
        texture:SetTexture("Interface\\Buttons\\WHITE8x8")
        texture:SetBlendMode("ADD")
        texture.orientation = orientation
        texture.warmAtMin = warmAtMin
        place(texture)
        strips[#strips + 1] = texture
    end

    strip("VERTICAL", false, function(t)
        t:SetPoint("TOPLEFT", GLOW_INSET, -GLOW_INSET)
        t:SetPoint("TOPRIGHT", -GLOW_INSET, -GLOW_INSET)
        t:SetHeight(GLOW_DEPTH)
    end)
    strip("VERTICAL", true, function(t)
        t:SetPoint("BOTTOMLEFT", GLOW_INSET, GLOW_INSET)
        t:SetPoint("BOTTOMRIGHT", -GLOW_INSET, GLOW_INSET)
        t:SetHeight(GLOW_DEPTH)
    end)
    strip("HORIZONTAL", true, function(t)
        t:SetPoint("TOPLEFT", GLOW_INSET, -GLOW_INSET)
        t:SetPoint("BOTTOMLEFT", GLOW_INSET, GLOW_INSET)
        t:SetWidth(GLOW_DEPTH)
    end)
    strip("HORIZONTAL", false, function(t)
        t:SetPoint("TOPRIGHT", -GLOW_INSET, -GLOW_INSET)
        t:SetPoint("BOTTOMRIGHT", -GLOW_INSET, GLOW_INSET)
        t:SetWidth(GLOW_DEPTH)
    end)

    return strips
end

-- Gold panel art. The default palette hides all of it and keeps the Blizzard
-- dialog border instead, so this is created once and simply shown or hidden.
local function CreateOrnaments(parent)
    local pieces = {}
    for _, corner in ipairs(CORNERS) do
        local texture = parent:CreateTexture(nil, "OVERLAY")
        texture:SetSize(ORNAMENT_SIZE, ORNAMENT_SIZE)
        texture:SetPoint(corner.point, corner.x, corner.y)
        texture:SetTexture(Theme.CORNER)
        texture:SetTexCoord(corner.left, corner.right, corner.top, corner.bottom)
        pieces[#pieces + 1] = texture
    end

    local crest = parent:CreateTexture(nil, "OVERLAY")
    crest:SetSize(FLOURISH_WIDTH, FLOURISH_HEIGHT)
    crest:SetPoint("TOP", 0, FLOURISH_HEIGHT / 2)
    crest:SetTexture(Theme.FLOURISH)
    pieces[#pieces + 1] = crest

    -- Warms up the frame edge. Below ARTWORK, so every panel still draws on top.
    local glow = CreateEdgeGlow(parent)

    Theme:Register(function(palette)
        for _, texture in ipairs(pieces) do
            texture:SetShown(palette.ornaments)
            if palette.ornaments then
                texture:SetVertexColor(unpack(palette.ornamentColor))
            end
        end
        for _, strip in ipairs(glow) do
            strip:SetShown(palette.ornaments)
            if palette.ornaments then
                local r, g, b, a = unpack(palette.glowColor)
                local warm, clear = CreateColor(r, g, b, a), CreateColor(r, g, b, 0)
                if strip.warmAtMin then
                    strip:SetGradient(strip.orientation, warm, clear)
                else
                    strip:SetGradient(strip.orientation, clear, warm)
                end
            end
        end
    end)
end

-- Only useful once the labels have been dropped; otherwise the tab says it already.
local function ShowTabTooltip(self)
    if self.label:IsShown() then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.text, 1, 1, 1)
    GameTooltip:Show()
end

local function CreateTabButton(parent, index, text)
    local tab = CreateFrame("Button", "PullReadyDialogTab" .. index, parent)
    tab:SetID(index)
    tab:SetHeight(TAB_HEIGHT)
    tab.text = text

    tab.background = tab:CreateTexture(nil, "BACKGROUND")
    tab.background:SetAllPoints()

    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
    tab.icon:SetTexture(TAB_ICONS[index])

    tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.label:SetPoint("LEFT", tab.icon, "RIGHT", TAB_LABEL_GAP, 0)
    tab.label:SetText(text)

    tab.highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    tab.highlight:SetAllPoints()
    tab.highlight:SetColorTexture(1, 1, 1, 0.07)

    tab:SetScript("OnClick", function(self)
        Dialog:SelectTab(self:GetID())
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    end)
    tab:SetScript("OnEnter", ShowTabTooltip)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    return tab
end

-- Selected tab gold, the rest dark, a disabled one dimmed out.
local function UpdateTabVisuals()
    local palette = Theme:Current()
    for index, tab in ipairs(frame.Tabs) do
        local selected = frame.selectedTab == index
        tab.background:SetTexture(selected and Theme.TAB_ON or Theme.TAB_OFF)
        tab.background:SetVertexColor(unpack(selected and palette.tabTintOn or palette.tabTint))
        local tint = palette.tabTextOff
        if not tab.isDisabled then
            tint = selected and palette.tabTextOn or palette.tabText
        end
        tab.background:SetAlpha(tab.isDisabled and 0.45 or 1)
        tab.label:SetTextColor(unpack(tint))
        tab.icon:SetVertexColor(unpack(tint))
        tab.icon:SetAlpha(tab.isDisabled and 0.5 or 1)
    end
end

-- Tab widths follow their labels and the strip is centered. Six translated labels
-- do not fit in every language, so when they do not, every tab drops to its icon
-- alone and the label moves into the tooltip.
local function LayoutTabs()
    local tabs = frame.Tabs
    local available = FRAME_WIDTH - 2 * TAB_MARGIN
    local widths, total = {}, TAB_GAP * (#tabs - 1)

    for index, tab in ipairs(tabs) do
        tab.label:SetText(tab.text)
        widths[index] = 2 * TAB_PAD + TAB_ICON_SIZE + TAB_LABEL_GAP
            + math.ceil(tab.label:GetStringWidth())
        total = total + widths[index]
    end

    local labelled = total <= available
    if not labelled then
        total = TAB_GAP * (#tabs - 1)
        for index in ipairs(tabs) do
            widths[index] = TAB_ICON_SIZE + 2 * TAB_PAD
            total = total + widths[index]
        end
    end

    local x = math.floor((FRAME_WIDTH - total) / 2)
    for index, tab in ipairs(tabs) do
        tab.label:SetShown(labelled)
        tab.icon:ClearAllPoints()
        if labelled then
            tab.icon:SetPoint("LEFT", TAB_PAD, 0)
        else
            tab.icon:SetPoint("CENTER")
        end
        tab:SetWidth(widths[index])
        tab:ClearAllPoints()
        tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, TAB_BOTTOM)
        x = x + widths[index] + TAB_GAP
    end
end

local function SetTabEnabled(index, enabled)
    local tab = frame.Tabs[index]
    tab.isDisabled = not enabled
    tab:SetEnabled(enabled)
end

local function CreateDialog()
    frame = CreateFrame("Frame", "PullReadyDialog", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    Theme:Register(function(palette)
        Theme:SkinBackdrop(frame, palette)
    end)
    CreateOrnaments(frame)
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName()) -- close with ESC

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", TITLE_INSET, TITLE_TOP)
    title:SetText(PR.Fun:Title())
    titleText = title
    Theme:Register(function(palette)
        title:SetTextColor(unpack(palette.title))
    end)

    -- Tab 1: check results
    checkPanel = CreateFrame("Frame", nil, frame)
    checkPanel:SetAllPoints()

    summaryText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    -- Anchored to the panel rather than to the title: the title is off in the
    -- corner now, and this line belongs over the icon row it summarises.
    summaryText:SetPoint("TOP", checkPanel, "TOP", 0, -30)

    summaryBar = CreateFrame("Frame", nil, checkPanel)
    summaryBar:SetSize(
        DURABILITY_ICON_INDEX * POTION_ICON_SIZE + (DURABILITY_ICON_INDEX - 1) * POTION_ICON_GAP,
        POTION_ICON_SIZE)
    summaryBar:SetPoint("TOP", summaryText, "BOTTOM", 0, -8)
    summaryBar.icons = {}
    for i, kind in ipairs(POTION_KINDS) do
        summaryBar.icons[kind] = CreatePotionIcon(summaryBar, i)
    end

    -- Same button as a consumable, with the tier set's own count, tag and tooltip.
    summaryBar.tier = CreatePotionIcon(summaryBar, TIER_ICON_INDEX)
    summaryBar.tier.bonus = summaryBar.tier:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    summaryBar.tier.bonus:SetPoint("TOPLEFT", -2, 2)
    summaryBar.tier.bonus:SetJustifyH("LEFT")
    summaryBar.tier:SetScript("OnEnter", ShowTierTooltip)

    -- And once more for the gear durability. "100%" needs the smaller font to stay on
    -- top of the icon.
    summaryBar.durability = CreatePotionIcon(summaryBar, DURABILITY_ICON_INDEX)
    summaryBar.durability.count:SetFontObject(NumberFontNormalSmall)
    summaryBar.durability:SetScript("OnEnter", ShowDurabilityTooltip)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)


    local scroll = CreateFrame("ScrollFrame", nil, checkPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -104)
    scroll:SetPoint("BOTTOMRIGHT", -38, 20)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(FRAME_WIDTH - 58, 1)
    scroll:SetScrollChild(scrollChild)

    -- The "all clear" state of the check tab: ring, checkmark, headline, subtitle.
    okBlock = CreateFrame("Frame", nil, checkPanel)
    okBlock:SetSize(360, RING_SIZE + 60)
    okBlock:SetPoint("CENTER", scroll, "CENTER")

    local okRing = okBlock:CreateTexture(nil, "ARTWORK")
    okRing:SetSize(RING_SIZE, RING_SIZE)
    okRing:SetPoint("TOP")
    okRing:SetTexture(Theme.RING)

    local okMark = okBlock:CreateTexture(nil, "OVERLAY")
    okMark:SetSize(RING_SIZE * 0.52, RING_SIZE * 0.52)
    okMark:SetPoint("CENTER", okRing, "CENTER")
    okMark:SetTexture(CHECKMARK)

    okText = okBlock:CreateFontString(nil, "OVERLAY", "GameFontGreenLarge")
    okText:SetPoint("TOP", okRing, "BOTTOM", 0, -10)
    okText:SetText(L["Everything looks good!"])

    okSubText = okBlock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    okSubText:SetPoint("TOP", okText, "BOTTOM", 0, -4)
    okSubText:SetText(L["You are ready for the pull."])

    Theme:Register(function(palette)
        okRing:SetVertexColor(unpack(palette.ring))
        okSubText:SetTextColor(unpack(palette.subtitle))
    end)

    -- Tab 2: raid / party inspect
    inspectPanel = PR.RaidCheck:CreatePanel(frame)

    -- Tab 3: talent loadouts
    talentsPanel = PR.Talents:CreatePanel(frame)

    -- Tab 6: options
    optionsPanel = CreateFrame("Frame", nil, frame)
    optionsPanel:SetAllPoints()
    optionsPanel:Hide()
    optionsPanel:SetScript("OnShow", function()
        indicatorsCheck:SetChecked(PullReadyDB.characterIndicators)
        UpdateQualityButtons()
        whisperCheck:SetChecked(PullReadyDB.localizedWhisper)
        Dialog:UpdateWhisperLocale()
        Dialog:UpdateThemeLabel()
    end)

    local optionsHeader = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    optionsHeader:SetPoint("TOPLEFT", 24, -56)
    optionsHeader:SetText(OPTIONS or L["Options"])

    indicatorsCheck = CreateFrame("CheckButton", nil, optionsPanel, "UICheckButtonTemplate")
    indicatorsCheck:SetSize(26, 26)
    indicatorsCheck:SetPoint("TOPLEFT", optionsHeader, "BOTTOMLEFT", -4, -10)
    indicatorsCheck:SetScript("OnClick", function(self)
        PR.CharacterPanel:SetEnabled(self:GetChecked())
    end)

    local indicatorsLabel = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    indicatorsLabel:SetPoint("LEFT", indicatorsCheck, "RIGHT", 2, 1)
    indicatorsLabel:SetText(L["Show enchant & socket indicators on the character panel"])

    local indicatorsHint = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    indicatorsHint:SetPoint("TOPLEFT", indicatorsLabel, "BOTTOMLEFT", 0, -4)
    indicatorsHint:SetPoint("RIGHT", optionsPanel, "RIGHT", -24, 0)
    indicatorsHint:SetJustifyH("LEFT")
    indicatorsHint:SetText(L["Icons next to item slots and a red border on items with a missing enchant or gem."])

    -- Label and buttons share a row frame, so the hint below clears the taller buttons.
    local qualityRow = CreateFrame("Frame", nil, optionsPanel)
    qualityRow:SetHeight(QUALITY_BUTTON_SIZE)
    qualityRow:SetPoint("TOPLEFT", indicatorsCheck, "BOTTOMLEFT", 4, -28)
    qualityRow:SetPoint("RIGHT", optionsPanel, "RIGHT", -24, 0)

    local qualityLabel = qualityRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qualityLabel:SetPoint("LEFT")
    qualityLabel:SetText(L["Required enchant & gem quality rank:"])

    local ranks = PR.MAX_QUALITY_RANK_OPTION - PR.MIN_QUALITY_RANK_OPTION + 1
    local qualityBar = CreateFrame("Frame", nil, qualityRow)
    qualityBar:SetSize(ranks * QUALITY_BUTTON_SIZE + (ranks - 1) * QUALITY_BUTTON_GAP, QUALITY_BUTTON_SIZE)
    qualityBar:SetPoint("LEFT", qualityLabel, "RIGHT", 10, 0)
    for tier = PR.MIN_QUALITY_RANK_OPTION, PR.MAX_QUALITY_RANK_OPTION do
        qualityButtons[#qualityButtons + 1] = CreateQualityButton(qualityBar, tier)
    end
    UpdateQualityButtons()

    local qualityHint = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    qualityHint:SetPoint("TOPLEFT", qualityRow, "BOTTOMLEFT", 0, -6)
    qualityHint:SetPoint("RIGHT", optionsPanel, "RIGHT", -24, 0)
    qualityHint:SetJustifyH("LEFT")
    qualityHint:SetText(L["Enchants and gems below this crafting quality rank are reported as low quality."])

    whisperCheck = CreateFrame("CheckButton", nil, optionsPanel, "UICheckButtonTemplate")
    whisperCheck:SetSize(26, 26)
    whisperCheck:SetPoint("TOPLEFT", qualityHint, "BOTTOMLEFT", -4, -24)
    whisperCheck:SetScript("OnClick", function(self)
        PullReadyDB.localizedWhisper = self:GetChecked() and true or false
        Dialog:UpdateWhisperLocale()
    end)

    local whisperLabel = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    whisperLabel:SetPoint("LEFT", whisperCheck, "RIGHT", 2, 1)
    whisperLabel:SetText(L["Send Raid Inspect whispers in my language"])

    local whisperHint = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    whisperHint:SetPoint("TOPLEFT", whisperLabel, "BOTTOMLEFT", 0, -4)
    whisperHint:SetPoint("RIGHT", optionsPanel, "RIGHT", -24, 0)
    whisperHint:SetJustifyH("LEFT")
    whisperHint:SetText(L["Off: whispers are sent in the language chosen below, since the other player's game language is unknown."])

    local whisperLangLabel = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    whisperLangLabel:SetPoint("TOPLEFT", whisperHint, "BOTTOMLEFT", 4, -12)
    whisperLangLabel:SetText(L["Whisper language:"])

    whisperDrop = CreateFrame("DropdownButton", nil, optionsPanel, "WowStyle1DropdownTemplate")
    whisperDrop:SetWidth(160)
    whisperDrop:SetPoint("LEFT", whisperLangLabel, "RIGHT", 10, 0)
    whisperDrop:SetupMenu(function(_, rootDescription)
        for _, entry in ipairs(PR.WHISPER_LOCALES) do
            rootDescription:CreateRadio(entry.name,
                function() return PullReadyDB.whisperLocale == entry.locale end,
                function()
                    PullReadyDB.whisperLocale = entry.locale
                    Dialog:UpdateWhisperLocale()
                end)
        end
    end)
    whisperDrop.label = whisperLangLabel

    local themeLabel = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    themeLabel:SetPoint("TOPLEFT", whisperLangLabel, "BOTTOMLEFT", 0, -22)
    themeLabel:SetText(L["Window theme:"])

    themeDrop = CreateFrame("DropdownButton", nil, optionsPanel, "WowStyle1DropdownTemplate")
    themeDrop:SetWidth(160)
    themeDrop:SetPoint("LEFT", themeLabel, "RIGHT", 10, 0)
    themeDrop:SetupMenu(function(_, rootDescription)
        for _, name in ipairs(Theme.ORDER) do
            rootDescription:CreateRadio(Theme:Label(name),
                function() return Theme:Name() == name end,
                function()
                    Theme:Set(name)
                    Dialog:UpdateThemeLabel()
                end)
        end
    end)
    Dialog:UpdateThemeLabel()

    -- Tab 4: fast-travel search
    travelPanel = PR.Travel:CreatePanel(frame)

    -- Tab 5: shopping list
    shoppingPanel = PR.Shopping:CreatePanel(frame)

    -- Tabs along the bottom, inside the frame. Every panel is inset above them.
    for _, panel in ipairs({ checkPanel, inspectPanel, talentsPanel, optionsPanel,
            travelPanel, shoppingPanel }) do
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", 0, -HEADER_PAD)
        panel:SetPoint("BOTTOMRIGHT", 0, TAB_STRIP_HEIGHT)
    end

    frame.Tabs = {}
    for i, label in ipairs({ L["Check"], L["Raid Inspect"], TALENTS or L["Talents"], L["Travel"], L["Shopping"],
            OPTIONS or L["Options"] }) do
        frame.Tabs[i] = CreateTabButton(frame, i, label)
    end
    LayoutTabs()
    Theme:Register(UpdateTabVisuals)
end

function Dialog:SelectTab(index)
    -- Never land on a disabled tab (inspect while not in a group).
    local tab = frame.Tabs[index]
    if tab and tab.isDisabled then
        index = Dialog.TAB_CHECK
    end
    frame.selectedTab = index
    UpdateTabVisuals()
    checkPanel:SetShown(index == Dialog.TAB_CHECK)
    inspectPanel:SetShown(index == Dialog.TAB_INSPECT)
    talentsPanel:SetShown(index == Dialog.TAB_TALENTS)
    optionsPanel:SetShown(index == Dialog.TAB_OPTIONS)
    travelPanel:SetShown(index == Dialog.TAB_TRAVEL)
    shoppingPanel:SetShown(index == Dialog.TAB_SHOPPING)
end

local function Populate(issues, potions, tierSet, durability)
    for i, issue in ipairs(issues) do
        local row = rows[i] or CreateRow(i)
        row.itemLink = issue.itemLink
        row.slotID = issue.slot
        row.icon:SetTexture(issue.icon or GetInventoryItemTexture("player", issue.slot) or 134400)
        if issue.itemLink then
            row.slot:SetText(("%s - %s"):format(issue.slotName, issue.itemLink))
        else
            row.slot:SetText(issue.slotName)
        end
        row.problem:SetText(issue.detail)
        row.problem:SetTextColor(Theme:Status(PROBLEM_STATUS[issue.problem] or "bad"))
        row:Show()
    end
    for i = #issues + 1, #rows do
        rows[i]:Hide()
    end
    scrollChild:SetHeight(math.max(1, #issues * ROW_HEIGHT))

    local missing = 0
    for _, issue in ipairs(issues) do
        if issue.problem == "missing" then missing = missing + 1 end
    end
    for _, kind in ipairs(POTION_KINDS) do
        UpdatePotionIcon(summaryBar.icons[kind], potions and potions[kind])
    end
    UpdateTierIcon(summaryBar.tier, tierSet)
    UpdateDurabilityIcon(summaryBar.durability, durability)

    if #issues == 0 then
        summaryText:SetText("")
        okBlock:Show()
    else
        summaryText:SetText(L["%d problem(s) found, %d missing"]:format(#issues, missing))
        okBlock:Hide()
    end
end

function Dialog:Show(issues, potions, tierSet, durability)
    if InCombatLockdown() then
        pendingIssues, pendingPotions, pendingTierSet, pendingDurability =
            issues, potions, tierSet, durability
        return
    end
    if not frame then CreateDialog() end
    Populate(issues, potions, tierSet, durability)
    self:UpdateInspectAccess()
    self:SelectTab(Dialog.TAB_CHECK)
    frame:Show()
    if #issues > 0 then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

-- Updates title and availability of the inspect tab and button (needs a party or raid).
function Dialog:UpdateInspectAccess()
    if not frame then return end
    local allowed = PR.RaidCheck:IsAllowed()
    local title = PR.RaidCheck:GetTitle()

    frame.Tabs[Dialog.TAB_INSPECT].text = title
    SetTabEnabled(Dialog.TAB_INSPECT, allowed)
    LayoutTabs()
    UpdateTabVisuals()
    if not allowed and frame.selectedTab == Dialog.TAB_INSPECT and checkPanel then
        self:SelectTab(Dialog.TAB_CHECK)
    end
end

function Dialog:OpenTab(index)
    if not frame then
        CreateDialog()
        Populate({}, nil, nil, nil)
        okBlock:Hide()
        summaryText:SetText(L["No check run yet - use /pr or the minimap button."])
    end
    self:UpdateInspectAccess()
    self:SelectTab(index)
    frame:Show()
end

function Dialog:ToggleTab(index)
    if frame and frame:IsShown() and frame.selectedTab == index then
        frame:Hide()
    else
        self:OpenTab(index)
    end
end

-- The whisper language only applies when whispers are not sent in the client's language.
function Dialog:UpdateWhisperLocale()
    if not whisperDrop then return end
    local selectable = not PullReadyDB.localizedWhisper
    local name = PR.CLIENT_LOCALE
    for _, entry in ipairs(PR.WHISPER_LOCALES) do
        if entry.locale == (selectable and PullReadyDB.whisperLocale or PR.CLIENT_LOCALE) then
            name = entry.name
        end
    end
    whisperDrop:SetDefaultText(name)
    whisperDrop:SetEnabled(selectable)
    whisperDrop.label:SetFontObject(selectable and "GameFontHighlight" or "GameFontDisable")
end

function Dialog:UpdateThemeLabel()
    if themeDrop then
        themeDrop:SetDefaultText(Theme:Label(Theme:Name()))
    end
end

-- Header and the strings set once at creation, after fun mode was toggled (/pr ziegel).
function Dialog:RefreshFunMode()
    if not frame then return end
    titleText:SetText(PR.Fun:Title())
    okText:SetText(L["Everything looks good!"])
    okSubText:SetText(L["You are ready for the pull."])
end

-- Keeps the quality buttons in sync when the rank changes elsewhere (/pr quality).
function Dialog:RefreshQuality()
    if #qualityButtons > 0 then UpdateQualityButtons() end
end

function Dialog:OpenOptions()
    self:OpenTab(Dialog.TAB_OPTIONS)
end

function Dialog:Hide()
    if frame then frame:Hide() end
end

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
    if pendingIssues then
        local issues, potions = pendingIssues, pendingPotions
        local tierSet, durability = pendingTierSet, pendingDurability
        pendingIssues, pendingPotions, pendingTierSet, pendingDurability = nil, nil, nil, nil
        Dialog:Show(issues, potions, tierSet, durability)
    end
end)
