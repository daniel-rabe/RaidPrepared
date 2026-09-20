local _, PR = ...
local L = PR.L

local ICON = "Interface\\Icons\\INV_Misc_Gem_Diamond_02"

local Minimap_ = {}
PR.Minimap = Minimap_

local button

local function UpdatePosition()
    local angle = math.rad(PullReadyDB.minimap.angle or 225)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    PullReadyDB.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("PullReady")
    GameTooltip:AddLine(L["Left-click: check enchants, gems & consumables"], 1, 1, 1)
    if PR.RaidCheck:IsAllowed() then
        GameTooltip:AddLine(L["Right-click: %s"]:format(PR.RaidCheck:GetTitle()), 1, 1, 1)
    end
    GameTooltip:AddLine(L["Shift-click: talent loadout flags"], 1, 1, 1)
    GameTooltip:AddLine(L["Ctrl-click: travel search"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move button"], 1, 1, 1)
    GameTooltip:Show()
end

function Minimap_:Create()
    if button then return end

    button = CreateFrame("Button", "PullReadyMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouseButton)
        if IsControlKeyDown() then
            PR.Travel:Toggle()
        elseif IsShiftKeyDown() then
            PR.Talents:Toggle()
        elseif mouseButton == "RightButton" then
            PR.RaidCheck:Toggle()
        else
            PR.RunCheck(true)
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)

    UpdatePosition()
    self:UpdateVisibility()
end

function Minimap_:UpdateVisibility()
    if not button then return end
    button:SetShown(not PullReadyDB.minimap.hide)
end

function Minimap_:Toggle()
    PullReadyDB.minimap.hide = not PullReadyDB.minimap.hide
    self:UpdateVisibility()
    return not PullReadyDB.minimap.hide
end

-- Addon compartment (retail minimap addon menu), referenced from the TOC.
function PullReady_OnAddonCompartmentClick(_, mouseButton)
    if IsControlKeyDown() then
        PR.Travel:Toggle()
    elseif IsShiftKeyDown() then
        PR.Talents:Toggle()
    elseif mouseButton == "RightButton" then
        PR.RaidCheck:Toggle()
    else
        PR.RunCheck(true)
    end
end

function PullReady_OnAddonCompartmentEnter(_, menuButtonFrame)
    ShowTooltip(menuButtonFrame)
end

function PullReady_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
