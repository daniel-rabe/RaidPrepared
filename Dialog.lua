local addonName, PR = ...
local L = PR.L

local FRAME_WIDTH = 580
local FRAME_HEIGHT = 390
local ROW_HEIGHT = 34

-- Consumable summary: one icon per kind with its stack count, details in the tooltip.
local POTION_ICON_SIZE = 34
local POTION_ICON_GAP = 26
local POTION_KINDS = { "flask", "heal", "mana", "power", "weapon" }
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

local PROBLEM_COLORS = {
    missing  = { 1.0, 0.25, 0.25 },
    low      = { 1.0, 0.6, 0.1 },
    outdated = { 1.0, 0.6, 0.1 },
}

local Dialog = {}
PR.Dialog = Dialog

Dialog.TAB_CHECK = 1
Dialog.TAB_INSPECT = 2
Dialog.TAB_TALENTS = 3
Dialog.TAB_TRAVEL = 4
Dialog.TAB_SHOPPING = 5
Dialog.TAB_OPTIONS = 6

local frame, scrollChild, summaryText, potionBar, okText
local checkPanel, inspectPanel, talentsPanel, optionsPanel, travelPanel, shoppingPanel
local indicatorsCheck
local qualityButtons = {}
local whisperCheck, whisperDrop
local rows = {}
local pendingIssues, pendingPotions -- waiting for combat to end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)

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
        return 0.65, 0.65, 0.65
    elseif entry.count == 0 then
        return 1.0, 0.25, 0.25
    elseif entry.count < entry.minimum then
        return 1.0, 0.6, 0.1
    end
    return 0.25, 1.0, 0.25
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
        GameTooltip:AddLine(L["None in your bags"], 1, 0.25, 0.25)
    end
    if entry.activeTime then
        GameTooltip:AddLine(L["(active %dm)"]:format(math.floor(entry.activeTime / 60)), 0.25, 1, 0.25)
    end
    if not entry.required then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Not required"], 0.65, 0.65, 0.65)
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
            button.selection:SetColorTexture(1, 0.82, 0, 0.9) -- gold frame on the chosen rank
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
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 8, top = 12, bottom = 11 },
    })
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName()) -- close with ESC

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("PullReady")

    -- Tab 1: check results
    checkPanel = CreateFrame("Frame", nil, frame)
    checkPanel:SetAllPoints()

    summaryText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summaryText:SetPoint("TOP", title, "BOTTOM", 0, -6)

    potionBar = CreateFrame("Frame", nil, checkPanel)
    potionBar:SetSize(#POTION_KINDS * POTION_ICON_SIZE + (#POTION_KINDS - 1) * POTION_ICON_GAP,
        POTION_ICON_SIZE)
    potionBar:SetPoint("TOP", summaryText, "BOTTOM", 0, -8)
    potionBar.icons = {}
    for i, kind in ipairs(POTION_KINDS) do
        potionBar.icons[kind] = CreatePotionIcon(potionBar, i)
    end

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", nil, checkPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -104)
    scroll:SetPoint("BOTTOMRIGHT", -38, 20)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(FRAME_WIDTH - 58, 1)
    scroll:SetScrollChild(scrollChild)

    okText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontGreenLarge")
    okText:SetPoint("CENTER", scroll, "CENTER")
    okText:SetText(L["Everything looks good!"])

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

    -- Tab 4: fast-travel search
    travelPanel = PR.Travel:CreatePanel(frame)

    -- Tab 5: shopping list
    shoppingPanel = PR.Shopping:CreatePanel(frame)

    -- Tabs below the frame
    frame.Tabs = {}
    for i, label in ipairs({ L["Check"], L["Raid Inspect"], TALENTS or L["Talents"], L["Travel"], L["Shopping"],
            OPTIONS or L["Options"] }) do
        local tab = CreateFrame("Button", "PullReadyDialogTab" .. i, frame, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(label)
        PanelTemplates_TabResize(tab, 0)
        if i == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 6)
        else
            tab:SetPoint("TOPLEFT", frame.Tabs[i - 1], "TOPRIGHT", 3, 0)
        end
        tab:SetScript("OnClick", function(self)
            Dialog:SelectTab(self:GetID())
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        end)
        frame.Tabs[i] = tab
    end
    PanelTemplates_SetNumTabs(frame, #frame.Tabs)
end

function Dialog:SelectTab(index)
    -- Never land on a disabled tab (inspect without raid lead/assist).
    local tab = frame.Tabs[index]
    if tab and tab.isDisabled then
        index = Dialog.TAB_CHECK
    end
    PanelTemplates_SetTab(frame, index)
    checkPanel:SetShown(index == Dialog.TAB_CHECK)
    inspectPanel:SetShown(index == Dialog.TAB_INSPECT)
    talentsPanel:SetShown(index == Dialog.TAB_TALENTS)
    optionsPanel:SetShown(index == Dialog.TAB_OPTIONS)
    travelPanel:SetShown(index == Dialog.TAB_TRAVEL)
    shoppingPanel:SetShown(index == Dialog.TAB_SHOPPING)
end

local function Populate(issues, potions)
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
        row.problem:SetTextColor(unpack(PROBLEM_COLORS[issue.problem] or PROBLEM_COLORS.missing))
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
        UpdatePotionIcon(potionBar.icons[kind], potions and potions[kind])
    end

    if #issues == 0 then
        summaryText:SetText("")
        okText:Show()
    else
        summaryText:SetText(L["%d problem(s) found, %d missing"]:format(#issues, missing))
        okText:Hide()
    end
end

function Dialog:Show(issues, potions)
    if InCombatLockdown() then
        pendingIssues, pendingPotions = issues, potions
        return
    end
    if not frame then CreateDialog() end
    Populate(issues, potions)
    self:UpdateInspectAccess()
    self:SelectTab(Dialog.TAB_CHECK)
    frame:Show()
    if #issues > 0 then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

-- Updates title and availability of the inspect tab and button (raid lead/assist or party).
function Dialog:UpdateInspectAccess()
    if not frame then return end
    local allowed = PR.RaidCheck:IsAllowed()
    local title = PR.RaidCheck:GetTitle()

    local tab = frame.Tabs[Dialog.TAB_INSPECT]
    tab:SetText(title)
    PanelTemplates_TabResize(tab, 0)
    if allowed then
        PanelTemplates_EnableTab(frame, Dialog.TAB_INSPECT)
    else
        PanelTemplates_DisableTab(frame, Dialog.TAB_INSPECT)
        if frame.selectedTab == Dialog.TAB_INSPECT and checkPanel then
            self:SelectTab(Dialog.TAB_CHECK)
        end
    end
end

function Dialog:OpenTab(index)
    if not frame then
        CreateDialog()
        Populate({}, nil)
        okText:Hide()
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
        pendingIssues, pendingPotions = nil, nil
        Dialog:Show(issues, potions)
    end
end)
