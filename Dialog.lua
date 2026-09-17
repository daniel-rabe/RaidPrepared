local addonName, RP = ...

local FRAME_WIDTH = 460
local FRAME_HEIGHT = 390
local ROW_HEIGHT = 34

local PROBLEM_COLORS = {
    missing  = { 1.0, 0.25, 0.25 },
    low      = { 1.0, 0.6, 0.1 },
    outdated = { 1.0, 0.6, 0.1 },
}

local Dialog = {}
RP.Dialog = Dialog

local frame, scrollChild, summaryText, potionText, weaponText, okText, raidCheckButton
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

    summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summaryText:SetPoint("TOP", title, "BOTTOM", 0, -6)

    potionText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    potionText:SetPoint("TOP", summaryText, "BOTTOM", 0, -6)

    weaponText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    weaponText:SetPoint("TOP", potionText, "BOTTOM", 0, -4)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -104)
    scroll:SetPoint("BOTTOMRIGHT", -38, 52)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(FRAME_WIDTH - 58, 1)
    scroll:SetScrollChild(scrollChild)

    okText = frame:CreateFontString(nil, "OVERLAY", "GameFontGreenLarge")
    okText:SetPoint("CENTER", scroll, "CENTER")
    okText:SetText("Everything looks good!")

    local dismiss = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dismiss:SetSize(120, 24)
    dismiss:SetPoint("BOTTOM", 0, 18)
    dismiss:SetText("Dismiss")
    dismiss:SetScript("OnClick", function() frame:Hide() end)

    raidCheckButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    raidCheckButton:SetSize(100, 24)
    raidCheckButton:SetPoint("BOTTOMLEFT", 20, 18)
    raidCheckButton:SetText("Raid Check")
    raidCheckButton:SetScript("OnClick", function() RP.RaidCheck:Open() end)
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
    self:UpdateRaidCheckButton()
    frame:Show()
    if #issues > 0 then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

function Dialog:UpdateRaidCheckButton()
    if raidCheckButton then
        raidCheckButton:SetShown(RP.RaidCheck:IsAllowed())
    end
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
