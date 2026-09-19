local addonName, RP = ...

local FRAME_WIDTH = 580
local FRAME_HEIGHT = 390
local ROW_HEIGHT = 34

local PROBLEM_COLORS = {
    missing  = { 1.0, 0.25, 0.25 },
    low      = { 1.0, 0.6, 0.1 },
    outdated = { 1.0, 0.6, 0.1 },
}

local Dialog = {}
RP.Dialog = Dialog

Dialog.TAB_CHECK = 1
Dialog.TAB_INSPECT = 2
Dialog.TAB_TALENTS = 3
Dialog.TAB_OPTIONS = 4
Dialog.TAB_TRAVEL = 5

local frame, scrollChild, summaryText, potionText, weaponText, okText
local checkPanel, inspectPanel, talentsPanel, optionsPanel, travelPanel, indicatorsCheck, qualityValue
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

local function CreateDialog()
    frame = CreateFrame("Frame", "RaidPreparedDialog", UIParent, "BackdropTemplate")
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
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName()) -- close with ESC

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("RaidPrepared")

    -- Tab 1: check results
    checkPanel = CreateFrame("Frame", nil, frame)
    checkPanel:SetAllPoints()

    summaryText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summaryText:SetPoint("TOP", title, "BOTTOM", 0, -6)

    potionText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    potionText:SetPoint("TOP", summaryText, "BOTTOM", 0, -6)

    weaponText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    weaponText:SetPoint("TOP", potionText, "BOTTOM", 0, -4)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", nil, checkPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -104)
    scroll:SetPoint("BOTTOMRIGHT", -38, 52)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(FRAME_WIDTH - 58, 1)
    scroll:SetScrollChild(scrollChild)

    okText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontGreenLarge")
    okText:SetPoint("CENTER", scroll, "CENTER")
    okText:SetText("Everything looks good!")

    local dismiss = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dismiss:SetSize(120, 24)
    dismiss:SetPoint("BOTTOM", 0, 18)
    dismiss:SetText("Dismiss")
    dismiss:SetScript("OnClick", function() frame:Hide() end)

    -- Tab 2: raid / party inspect
    inspectPanel = RP.RaidCheck:CreatePanel(frame)

    -- Tab 3: talent loadouts
    talentsPanel = RP.Talents:CreatePanel(frame)

    -- Tab 4: options
    optionsPanel = CreateFrame("Frame", nil, frame)
    optionsPanel:SetAllPoints()
    optionsPanel:Hide()
    optionsPanel:SetScript("OnShow", function()
        indicatorsCheck:SetChecked(RaidPreparedDB.characterIndicators)
        qualityValue:SetText(RP.GetMaxQualityTier())
    end)

    local optionsHeader = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    optionsHeader:SetPoint("TOPLEFT", 24, -56)
    optionsHeader:SetText(OPTIONS or "Options")

    indicatorsCheck = CreateFrame("CheckButton", nil, optionsPanel, "UICheckButtonTemplate")
    indicatorsCheck:SetSize(26, 26)
    indicatorsCheck:SetPoint("TOPLEFT", optionsHeader, "BOTTOMLEFT", -4, -10)
    indicatorsCheck:SetScript("OnClick", function(self)
        RP.CharacterPanel:SetEnabled(self:GetChecked())
    end)

    local indicatorsLabel = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    indicatorsLabel:SetPoint("LEFT", indicatorsCheck, "RIGHT", 2, 1)
    indicatorsLabel:SetText("Show enchant & socket indicators on the character panel")

    local indicatorsHint = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    indicatorsHint:SetPoint("TOPLEFT", indicatorsLabel, "BOTTOMLEFT", 0, -4)
    indicatorsHint:SetPoint("RIGHT", optionsPanel, "RIGHT", -24, 0)
    indicatorsHint:SetJustifyH("LEFT")
    indicatorsHint:SetText("Icons next to item slots and a red border on items with a missing enchant or gem.")

    local qualityLabel = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qualityLabel:SetPoint("TOPLEFT", indicatorsCheck, "BOTTOMLEFT", 4, -34)
    qualityLabel:SetText("Required enchant & gem quality rank:")

    local function Step(delta)
        qualityValue:SetText(RP.SetMaxQualityTier(RP.GetMaxQualityTier() + delta))
    end

    local minus = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("LEFT", qualityLabel, "RIGHT", 10, 0)
    minus:SetText("-")
    minus:SetScript("OnClick", function() Step(-1) end)

    qualityValue = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    qualityValue:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    qualityValue:SetWidth(20)

    local plus = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
    plus:SetSize(24, 22)
    plus:SetPoint("LEFT", qualityValue, "RIGHT", 6, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function() Step(1) end)

    local qualityHint = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    qualityHint:SetPoint("TOPLEFT", qualityLabel, "BOTTOMLEFT", 0, -6)
    qualityHint:SetPoint("RIGHT", optionsPanel, "RIGHT", -24, 0)
    qualityHint:SetJustifyH("LEFT")
    qualityHint:SetText("Enchants and gems below this crafting quality rank are reported as low quality.")

    -- Tab 5: fast-travel search
    travelPanel = RP.Travel:CreatePanel(frame)

    -- Tabs below the frame
    frame.Tabs = {}
    for i, label in ipairs({ "Check", "Raid Inspect", TALENTS or "Talents", OPTIONS or "Options", "Travel" }) do
        local tab = CreateFrame("Button", "RaidPreparedDialogTab" .. i, frame, "PanelTabButtonTemplate")
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
end

local function ColorPotionCount(entry)
    local color
    if not entry.required then
        color = "ffaaaaaa"
    elseif entry.count == 0 then
        color = "ffff4040"
    elseif entry.count < entry.minimum then
        color = "ffff9919"
    else
        color = "ff40ff40"
    end
    local text = ("%s: |c%s%d|r"):format(entry.label, color, entry.count)
    if entry.activeTime then
        text = text .. (" |cff40ff40(active %dm)|r"):format(math.floor(entry.activeTime / 60))
    end
    return text
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
    if potions then
        potionText:SetText(ColorPotionCount(potions.heal) .. "    " .. ColorPotionCount(potions.mana))
        weaponText:SetText(ColorPotionCount(potions.weapon))
    else
        potionText:SetText("")
        weaponText:SetText("")
    end

    if #issues == 0 then
        summaryText:SetText("")
        okText:Show()
    else
        summaryText:SetText(("%d problem(s) found, %d missing"):format(#issues, missing))
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
    local allowed = RP.RaidCheck:IsAllowed()
    local title = RP.RaidCheck:GetTitle()

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
        summaryText:SetText("No check run yet - use /rp or the minimap button.")
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
