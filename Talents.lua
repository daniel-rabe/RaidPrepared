local _, RP = ...

-- Talent loadout check: players flag their saved loadouts as "raid" and/or "dungeon".
-- Inside a raid or Mythic/Mythic+ dungeon a warning appears when the active loadout is not
-- flagged for that content - but only if at least one loadout of the spec is flagged for it.

local CHECK_DELAY = 3 -- seconds after zoning in (talent data is not ready immediately)
local DIFFICULTY_MYTHIC_DUNGEON = 23
local DIFFICULTY_MYTHIC_KEYSTONE = 8

local CONTENT_LABELS = {
    raid = "raid",
    dungeon = "Mythic dungeon",
}

local FRAME_WIDTH = 380
local ROW_HEIGHT = 26

local Talents = {}
RP.Talents = Talents

local frame, scrollChild, headerText, emptyText
local rows = {}
local talentFrameWidgets
local lastCheckedInstanceID

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function GetSpecID()
    if PlayerUtil and PlayerUtil.GetCurrentSpecID then
        return PlayerUtil.GetCurrentSpecID()
    end
    local specIndex = GetSpecialization()
    return specIndex and (GetSpecializationInfo(specIndex))
end

local function GetSpecNameAndIcon()
    local specIndex = GetSpecialization()
    if not specIndex then return nil, nil end
    local _, name, _, icon = GetSpecializationInfo(specIndex)
    return name, icon
end

-- Saved loadouts of the current spec: array of { id, name }.
function Talents:GetLoadouts()
    local loadouts = {}
    local specID = GetSpecID()
    if not specID then return loadouts end

    for _, configID in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
        local info = C_Traits.GetConfigInfo(configID)
        loadouts[#loadouts + 1] = { id = configID, name = info and info.name or ("#" .. configID) }
    end
    return loadouts
end

-- configID of the selected saved loadout, or nil (starter build / nothing saved).
function Talents:GetActiveLoadoutID()
    local specID = GetSpecID()
    if not specID then return nil end
    if C_ClassTalents.GetStarterBuildActive and C_ClassTalents.GetStarterBuildActive() then
        return nil
    end
    return C_ClassTalents.GetLastSelectedSavedConfigID(specID)
end

function Talents:GetFlag(configID, content)
    local flags = RaidPreparedCharDB.loadoutFlags[configID]
    return flags ~= nil and flags[content] == true
end

function Talents:SetFlag(configID, content, value)
    local all = RaidPreparedCharDB.loadoutFlags
    all[configID] = all[configID] or {}
    all[configID][content] = value and true or nil
    if not next(all[configID]) then
        all[configID] = nil
    end
    self:NotifyChanged()
end

-- "raid", "dungeon" or nil for the instance the player is currently in.
function Talents:GetContent()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "raid" then
        return "raid"
    end
    if instanceType == "party"
        and (difficultyID == DIFFICULTY_MYTHIC_DUNGEON or difficultyID == DIFFICULTY_MYTHIC_KEYSTONE) then
        return "dungeon"
    end
    return nil
end

-- Returns an issue table (same shape as gear issues) or nil.
function Talents:Check()
    local content = self:GetContent()
    if not content then return nil end

    local flagged = {}
    local activeID = self:GetActiveLoadoutID()
    local activeName
    for _, loadout in ipairs(self:GetLoadouts()) do
        if self:GetFlag(loadout.id, content) then
            flagged[#flagged + 1] = loadout.name
        end
        if loadout.id == activeID then
            activeName = loadout.name
        end
    end

    if #flagged == 0 then return nil end
    if activeID and self:GetFlag(activeID, content) then return nil end

    local _, icon = GetSpecNameAndIcon()
    return {
        slot = 98,
        slotName = "Talents",
        icon = icon or 134400,
        kind = "talents",
        problem = "missing",
        detail = ("Loadout '%s' is not flagged for %s (use: %s)"):format(
            activeName or (activeID and "unsaved loadout" or "Starter Build"),
            CONTENT_LABELS[content], table.concat(flagged, ", ")),
    }
end

function RP.RunTalentCheck()
    local issue = Talents:Check()
    if issue then
        print("|cffff4040RaidPrepared|r: " .. issue.detail)
        RP.Dialog:Show({ issue })
    end
end

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------

local function CreateCheckbox(parent, label, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    check.label:SetPoint("LEFT", check, "RIGHT", 0, 1)
    check.label:SetText(label)
    check:SetScript("OnClick", function(self)
        onClick(self, self:GetChecked())
    end)
    return check
end

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

    row.dungeon = CreateCheckbox(row, "Dungeon", function(_, checked)
        Talents:SetFlag(row.configID, "dungeon", checked)
    end)
    row.dungeon:SetPoint("RIGHT", -60, 0)

    row.raid = CreateCheckbox(row, "Raid", function(_, checked)
        Talents:SetFlag(row.configID, "raid", checked)
    end)
    row.raid:SetPoint("RIGHT", row.dungeon, "LEFT", -40, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row.raid, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    rows[index] = row
    return row
end

local function CreateWindow()
    frame = CreateFrame("Frame", "RaidPreparedTalents", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, 300)
    frame:SetPoint("CENTER", -40, 40)
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
    tinsert(UISpecialFrames, frame:GetName())
    frame:SetScript("OnShow", function() Talents:RefreshWindow() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("RaidPrepared - Talent Loadouts")

    headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerText:SetPoint("TOP", title, "BOTTOM", 0, -6)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", headerText, "BOTTOM", 0, -4)
    hint:SetWidth(FRAME_WIDTH - 50)
    hint:SetText("Flag the loadouts you use for raids and Mythic dungeons.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -80)
    scroll:SetPoint("BOTTOMRIGHT", -38, 52)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(FRAME_WIDTH - 58, 1)
    scroll:SetScrollChild(scrollChild)

    emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", scroll, "CENTER")
    emptyText:SetText("No saved loadouts for this specialization.")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(120, 24)
    closeButton:SetPoint("BOTTOM", 0, 18)
    closeButton:SetText(CLOSE or "Close")
    closeButton:SetScript("OnClick", function() frame:Hide() end)
end

function Talents:RefreshWindow()
    if not frame or not frame:IsShown() then return end

    local specName = GetSpecNameAndIcon()
    headerText:SetText(specName or "")

    local loadouts = self:GetLoadouts()
    local activeID = self:GetActiveLoadoutID()
    for i, loadout in ipairs(loadouts) do
        local row = rows[i] or CreateRow(i)
        row.configID = loadout.id
        if loadout.id == activeID then
            row.name:SetText(loadout.name .. " |cff40ff40(active)|r")
        else
            row.name:SetText(loadout.name)
        end
        row.raid:SetChecked(self:GetFlag(loadout.id, "raid"))
        row.dungeon:SetChecked(self:GetFlag(loadout.id, "dungeon"))
        row:Show()
    end
    for i = #loadouts + 1, #rows do
        rows[i]:Hide()
    end
    scrollChild:SetHeight(math.max(1, #loadouts * ROW_HEIGHT))
    emptyText:SetShown(#loadouts == 0)
end

function Talents:Open()
    if not frame then CreateWindow() end
    frame:Show()
end

function Talents:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:Open()
    end
end

---------------------------------------------------------------------------
-- Blizzard talent frame checkboxes
---------------------------------------------------------------------------

local function RefreshTalentFrameWidgets()
    if not talentFrameWidgets then return end
    local activeID = Talents:GetActiveLoadoutID()
    for content, check in pairs(talentFrameWidgets) do
        check:SetEnabled(activeID ~= nil)
        check:SetChecked(activeID ~= nil and Talents:GetFlag(activeID, content))
        check.label:SetFontObject(activeID and "GameFontHighlightSmall" or "GameFontDisableSmall")
    end
end

local function HookTalentFrame()
    if talentFrameWidgets then return end
    local talentsFrame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    local loadSystem = talentsFrame and talentsFrame.LoadSystem
    if not loadSystem then return end -- Blizzard UI changed; the settings window still works

    local function onClick(content)
        return function(_, checked)
            local activeID = Talents:GetActiveLoadoutID()
            if activeID then
                Talents:SetFlag(activeID, content, checked)
            end
        end
    end

    local raid = CreateCheckbox(talentsFrame, "Raid", onClick("raid"))
    raid:SetPoint("BOTTOMLEFT", loadSystem, "TOPLEFT", 0, 2)
    local dungeon = CreateCheckbox(talentsFrame, "Dungeon", onClick("dungeon"))
    dungeon:SetPoint("LEFT", raid, "RIGHT", 40, 0)

    for _, check in ipairs({ raid, dungeon }) do
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("RaidPrepared")
            GameTooltip:AddLine("Flag the selected loadout for this content. You are warned when "
                .. "entering it with a loadout that is not flagged.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", GameTooltip_Hide)
    end

    talentFrameWidgets = { raid = raid, dungeon = dungeon }
    talentsFrame:HookScript("OnShow", RefreshTalentFrameWidgets)
    RefreshTalentFrameWidgets()
end

function Talents:NotifyChanged()
    self:RefreshWindow()
    RefreshTalentFrameWidgets()
end

function Talents:Init()
    HookTalentFrame()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("READY_CHECK")
for _, event in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_CONFIG_UPDATED",
    "ACTIVE_COMBAT_CONFIG_CHANGED", "SELECTED_LOADOUT_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_PlayerSpells" and RaidPreparedCharDB then
            HookTalentFrame()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(CHECK_DELAY, function()
            if not Talents:GetContent() then
                lastCheckedInstanceID = nil
                return
            end
            local instanceID = select(8, GetInstanceInfo())
            if instanceID ~= lastCheckedInstanceID then
                lastCheckedInstanceID = instanceID
                RP.RunTalentCheck()
            end
        end)
    elseif event == "READY_CHECK" then
        if Talents:GetContent() then
            RP.RunTalentCheck()
        end
    else
        Talents:NotifyChanged()
    end
end)
