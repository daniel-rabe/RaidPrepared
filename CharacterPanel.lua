local _, PR = ...

-- Optional indicators on the character panel item slots: missing/low-quality enchant and
-- empty/low-quality gem sockets. Toggle with /pr indicators.

local ICON_SIZE = 14
local ICON_GAP = 2
local BORDER_SIZE = 2
local UPDATE_DELAY = 0.2

-- Slots in the right column (and the main hand at the bottom) get their icons on the left side.
local RIGHT_SIDE_SLOTS = {
    [INVSLOT_HAND] = true,
    [INVSLOT_WAIST] = true,
    [INVSLOT_LEGS] = true,
    [INVSLOT_FEET] = true,
    [INVSLOT_FINGER1] = true,
    [INVSLOT_FINGER2] = true,
    [INVSLOT_TRINKET1] = true,
    [INVSLOT_TRINKET2] = true,
    [INVSLOT_MAINHAND] = true,
}

local ENCHANT_ICON = 136244 -- Trade_Engraving
local SOCKET_ICON = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"

local COLORS = {
    missing = { 1.0, 0.15, 0.15 },
    low = { 1.0, 0.6, 0.1 },
    outdated = { 1.0, 0.6, 0.1 },
}

local SLOT_BUTTONS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot",
    "CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
}

local CharacterPanel = {}
PR.CharacterPanel = CharacterPanel

local indicators = {} -- slotID -> { enchant = frame, gem = frame }
local updatePending = false

local function CreateIndicator(button, icon, texCoordInset)
    local indicator = CreateFrame("Frame", nil, button)
    indicator:SetSize(ICON_SIZE, ICON_SIZE)
    indicator:SetFrameLevel(button:GetFrameLevel() + 5)

    indicator.border = indicator:CreateTexture(nil, "BACKGROUND")
    indicator.border:SetAllPoints()

    indicator.icon = indicator:CreateTexture(nil, "ARTWORK")
    indicator.icon:SetPoint("TOPLEFT", 1, -1)
    indicator.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    indicator.icon:SetTexture(icon)
    if texCoordInset then
        indicator.icon:SetTexCoord(texCoordInset, 1 - texCoordInset, texCoordInset, 1 - texCoordInset)
    end

    indicator:EnableMouse(true)
    indicator:SetScript("OnEnter", function(self)
        if not self.text then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(PR.Fun:Title())
        GameTooltip:AddLine(self.text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    indicator:SetScript("OnLeave", GameTooltip_Hide)
    indicator:Hide()
    return indicator
end

-- Red frame drawn around the slot button when an enchant or gem is missing.
local function CreateBorder(button)
    local border = CreateFrame("Frame", nil, button)
    border:SetPoint("TOPLEFT", -BORDER_SIZE, BORDER_SIZE)
    border:SetPoint("BOTTOMRIGHT", BORDER_SIZE, -BORDER_SIZE)
    border:SetFrameLevel(button:GetFrameLevel() + 4)

    local r, g, b = unpack(COLORS.missing)
    local function Edge(point1, point2, width, height)
        local edge = border:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(r, g, b, 1)
        edge:SetPoint(point1)
        edge:SetPoint(point2)
        if width then edge:SetWidth(width) end
        if height then edge:SetHeight(height) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, BORDER_SIZE)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, BORDER_SIZE)
    Edge("TOPLEFT", "BOTTOMLEFT", BORDER_SIZE, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", BORDER_SIZE, nil)

    border:Hide()
    return border
end

local function GetIndicators(button)
    local slot = button:GetID()
    if not indicators[slot] then
        local enchant = CreateIndicator(button, ENCHANT_ICON, 0.08)
        local gem = CreateIndicator(button, SOCKET_ICON)
        -- Place the icons beside the button, towards the character model.
        local side = RIGHT_SIDE_SLOTS[slot] and "LEFT" or "RIGHT"
        local opposite = side == "LEFT" and "RIGHT" or "LEFT"
        local offset = side == "LEFT" and -ICON_GAP or ICON_GAP
        enchant:SetPoint("TOP" .. opposite, button, "TOP" .. side, offset, -2)
        gem:SetPoint("BOTTOM" .. opposite, button, "BOTTOM" .. side, offset, 2)
        indicators[slot] = { enchant = enchant, gem = gem, border = CreateBorder(button) }
    end
    return indicators[slot]
end

local function ShowIndicator(indicator, issue)
    if not issue then
        indicator:Hide()
        return
    end
    local r, g, b = unpack(COLORS[issue.problem] or COLORS.missing)
    indicator.border:SetColorTexture(r, g, b, 1)
    indicator.text = issue.detail
    indicator:Show()
end

local function HideAll()
    for _, slotIndicators in pairs(indicators) do
        slotIndicators.enchant:Hide()
        slotIndicators.gem:Hide()
        slotIndicators.border:Hide()
    end
end

local function Update()
    updatePending = false
    if not PullReadyDB.characterIndicators then
        HideAll()
        return
    end
    if not (PaperDollFrame and PaperDollFrame:IsVisible()) then return end

    PR.ScanUnitAsync("player", true, function(issues)
        -- The scan is async: the option may have been turned off or the panel closed meanwhile.
        if not PullReadyDB.characterIndicators then
            HideAll()
            return
        end
        if not (PaperDollFrame and PaperDollFrame:IsVisible()) then return end

        -- Worst issue per slot and kind ("missing" wins over "low"/"outdated").
        local bySlot = {}
        for _, issue in ipairs(issues) do
            if issue.kind == "enchant" or issue.kind == "gem" then
                bySlot[issue.slot] = bySlot[issue.slot] or {}
                local current = bySlot[issue.slot][issue.kind]
                if not current or issue.problem == "missing" then
                    bySlot[issue.slot][issue.kind] = issue
                end
            end
        end

        for _, name in ipairs(SLOT_BUTTONS) do
            local button = _G[name]
            if button then
                local slotIndicators = GetIndicators(button)
                local slotIssues = bySlot[button:GetID()] or {}
                ShowIndicator(slotIndicators.enchant, slotIssues.enchant)
                ShowIndicator(slotIndicators.gem, slotIssues.gem)
                local missing = (slotIssues.enchant and slotIssues.enchant.problem == "missing")
                    or (slotIssues.gem and slotIssues.gem.problem == "missing")
                slotIndicators.border:SetShown(missing and true or false)
            end
        end
    end)
end

function CharacterPanel:RequestUpdate()
    if updatePending then return end
    updatePending = true
    C_Timer.After(UPDATE_DELAY, Update)
end

function CharacterPanel:SetEnabled(enabled)
    PullReadyDB.characterIndicators = enabled and true or false
    self:RequestUpdate()
end

function CharacterPanel:Toggle()
    self:SetEnabled(not PullReadyDB.characterIndicators)
    return PullReadyDB.characterIndicators
end

function CharacterPanel:Init()
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function() CharacterPanel:RequestUpdate() end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("SOCKET_INFO_UPDATE")
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
events:SetScript("OnEvent", function()
    if PullReadyDB and PaperDollFrame and PaperDollFrame:IsVisible() then
        CharacterPanel:RequestUpdate()
    end
end)
