local _, PR = ...
local L = PR.L
local Theme = PR.Theme

-- Talent loadout check: players flag their saved loadouts as "raid" and/or "dungeon".
-- Inside a raid or Mythic/Mythic+ dungeon a warning appears when the active loadout is not
-- flagged for that content - but only if at least one loadout of the spec is flagged for it.

local CHECK_DELAY = 3 -- seconds after zoning in (talent data is not ready immediately)
local DIFFICULTY_MYTHIC_DUNGEON = 23
local DIFFICULTY_MYTHIC_KEYSTONE = 8

local CONTENT_LABELS = {
    raid = L["raid"],
    dungeon = L["Mythic dungeon"],
}

local FRAME_WIDTH = 380 -- width of the hint text
local ROW_HEIGHT = 26

-- Applying a loadout is a cast the server has to confirm, so the row says so meanwhile.
local LOADING_TIMEOUT = 10 -- seconds before the marker gives up waiting for the client
local LOADING_DOT_PERIOD = 0.3 -- seconds per dot of the animated ellipsis

local Talents = {}
PR.Talents = Talents

local function Print(msg)
    print(("|cff33ccff%s|r: "):format(PR.Fun:Title()) .. msg)
end

local frame, scrollChild, headerText, emptyText
local rows = {}
local talentFrameWidgets
local lastCheckedInstanceID
local loadingConfigID, loadingTimer -- the loadout being applied right now
local loadingRow, loadingDots -- its row, and the ellipsis length drawn on it

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function GetSpecID()
    if PlayerUtil and PlayerUtil.GetCurrentSpecID then
        return PlayerUtil.GetCurrentSpecID()
    end
    local specIndex = PR.GetSpecIndex()
    return specIndex and (PR.GetSpecInfo(specIndex))
end

local function GetSpecNameAndIcon()
    local specIndex = PR.GetSpecIndex()
    if not specIndex then return nil, nil end
    local _, name, _, icon = PR.GetSpecInfo(specIndex)
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

-- Applying a loadout runs a cast the server confirms with TRAIT_CONFIG_UPDATED (or
-- CONFIG_COMMIT_FAILED), so the row that was clicked carries a marker until then. The
-- timer is only a failsafe: without it a swallowed event would leave the marker up.
function Talents:SetLoading(configID)
    if loadingTimer then
        loadingTimer:Cancel()
        loadingTimer = nil
    end
    loadingConfigID = configID
    if configID then
        loadingTimer = C_Timer.NewTimer(LOADING_TIMEOUT, function() Talents:SetLoading(nil) end)
    end
    self:RefreshWindow()
end

function Talents:IsLoading()
    return loadingConfigID ~= nil
end

-- Activates a saved loadout, the way clicking it in Blizzard's own load dropdown would.
-- LoadConfig applies the build; the "last selected" id is what the talent UI and
-- GetActiveLoadoutID above read back, so it has to follow along.
function Talents:LoadLoadout(configID)
    if not configID or configID == self:GetActiveLoadoutID() then return end
    if not (C_ClassTalents and C_ClassTalents.LoadConfig) then return end
    if self:IsLoading() then return end -- one at a time: the last one is still applying

    local info = C_Traits.GetConfigInfo(configID)
    local name = info and info.name or ("#" .. configID)

    -- Talents are locked in combat, and the client would refuse the call anyway.
    if InCombatLockdown() then
        Print(L["Talent loadouts cannot be changed in combat."])
        return
    end

    local specID = GetSpecID()
    local failed = Enum.LoadConfigResult and Enum.LoadConfigResult.Error or 0
    if C_ClassTalents.LoadConfig(configID, true) == failed then
        -- Refused by the client: an encounter in progress, a pending unspent point, ...
        Print(L["Could not activate the loadout '%s'."]:format(name))
        return
    end

    if specID and C_ClassTalents.UpdateLastSelectedSavedConfigID then
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
    end
    self:SetLoading(configID)
    self:NotifyChanged()
end

function Talents:GetFlag(configID, content)
    local flags = PullReadyCharDB.loadoutFlags[configID]
    return flags ~= nil and flags[content] == true
end

function Talents:SetFlag(configID, content, value)
    local all = PullReadyCharDB.loadoutFlags
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
        slotName = TALENTS or L["Talents"],
        icon = icon or 134400,
        kind = "talents",
        problem = "missing",
        detail = L["Loadout '%s' is not flagged for %s (use: %s)"]:format(
            activeName or (activeID and L["unsaved loadout"] or L["Starter Build"]),
            CONTENT_LABELS[content], table.concat(flagged, ", ")),
    }
end

function PR.RunTalentCheck()
    local issue = Talents:Check()
    if issue then
        print(("|cffff4040%s|r: "):format(PR.Fun:Title()) .. issue.detail)
        PR.Dialog:Show({ issue })
    end
end

---------------------------------------------------------------------------
-- Talents tab (main dialog)
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

-- Horizontal space a checkbox label needs (labels differ in length per language).
local function LabelSpace(check)
    return math.ceil(check.label:GetStringWidth()) + 12
end

local function NameOnClick(self)
    Talents:LoadLoadout(self:GetParent().configID)
end

local function NameOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(PR.Fun:Title())
    GameTooltip:AddLine(L["Click a loadout name to activate it."], 1, 1, 1, true)
    GameTooltip:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

    row.dungeon = CreateCheckbox(row, L["Dungeon"], function(_, checked)
        Talents:SetFlag(row.configID, "dungeon", checked)
    end)
    row.dungeon:SetPoint("RIGHT", -math.max(60, LabelSpace(row.dungeon)), 0)

    row.raid = CreateCheckbox(row, L["Raid"], function(_, checked)
        Talents:SetFlag(row.configID, "raid", checked)
    end)
    row.raid:SetPoint("RIGHT", row.dungeon, "LEFT", -math.max(40, LabelSpace(row.raid)), 0)

    -- The name doubles as the button that loads the loadout.
    row.load = CreateFrame("Button", nil, row)
    row.load:SetHeight(ROW_HEIGHT - 4)
    row.load:SetPoint("LEFT", 0, 0)
    row.load:SetPoint("RIGHT", row.raid, "LEFT", -8, 0)
    row.load:SetScript("OnClick", NameOnClick)
    row.load:SetScript("OnEnter", NameOnEnter)
    row.load:SetScript("OnLeave", GameTooltip_Hide)

    row.load.highlight = row.load:CreateTexture(nil, "HIGHLIGHT")
    row.load.highlight:SetAllPoints()
    Theme:Register(function(palette)
        row.load.highlight:SetColorTexture(unpack(palette.rowHighlight))
    end)

    row.name = row.load:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetPoint("RIGHT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    rows[index] = row
    return row
end

-- "Name (loading...)", with the ellipsis growing so the row reads as busy rather than
-- stuck. Called from OnUpdate, so it only touches the font string when a dot is due.
local function DrawLoadingRow(force)
    if not loadingRow then return end
    local dots = math.floor(GetTime() / LOADING_DOT_PERIOD) % 4
    if dots == loadingDots and not force then return end
    loadingDots = dots
    loadingRow.name:SetText(("%s |cffffd100%s|r"):format(
        loadingRow.loadoutName, L["(loading%s)"]:format(("."):rep(dots))))
end

-- Builds the loadout list into a parent frame (the "Talents" tab of the main dialog).
function Talents:CreatePanel(parent)
    frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()
    frame:SetScript("OnShow", function() Talents:RefreshWindow() end)

    headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerText:SetPoint("TOP", 0, -42)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", headerText, "BOTTOM", 0, -4)
    hint:SetWidth(FRAME_WIDTH)
    hint:SetText(L["Flag the loadouts you use for raids and Mythic dungeons."]
        .. "\n" .. L["Click a loadout name to activate it."])

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -96)
    scroll:SetPoint("BOTTOMRIGHT", -38, 52)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(parent:GetWidth() - 58, 1)
    scroll:SetScrollChild(scrollChild)

    emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", scroll, "CENTER")
    emptyText:SetText(L["No saved loadouts for this specialization."])
    return frame
end

function Talents:RefreshWindow()
    if not frame or not frame:IsVisible() then return end

    local specName = GetSpecNameAndIcon()
    headerText:SetText(specName or "")

    local loadouts = self:GetLoadouts()
    local activeID = self:GetActiveLoadoutID()
    loadingRow, loadingDots = nil, nil
    for i, loadout in ipairs(loadouts) do
        local row = rows[i] or CreateRow(i)
        row.configID = loadout.id
        row.loadoutName = loadout.name
        if loadout.id == loadingConfigID then
            loadingRow = row
        elseif loadout.id == activeID then
            row.name:SetText(loadout.name .. " |cff40ff40" .. L["(active)"] .. "|r")
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

    DrawLoadingRow(true)
    -- Nothing to animate once the loadout is applied, so the OnUpdate goes away with it.
    frame:SetScript("OnUpdate", loadingRow and DrawLoadingRow or nil)
end

function Talents:Open()
    PR.Dialog:OpenTab(PR.Dialog.TAB_TALENTS)
end

function Talents:Toggle()
    PR.Dialog:ToggleTab(PR.Dialog.TAB_TALENTS)
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

    local raid = CreateCheckbox(talentsFrame, L["Raid"], onClick("raid"))
    raid:SetPoint("BOTTOMLEFT", loadSystem, "TOPLEFT", 0, 2)
    local dungeon = CreateCheckbox(talentsFrame, L["Dungeon"], onClick("dungeon"))
    dungeon:SetPoint("LEFT", raid, "RIGHT", math.max(40, LabelSpace(raid)), 0)

    for _, check in ipairs({ raid, dungeon }) do
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(PR.Fun:Title())
            GameTooltip:AddLine(L["Flag the selected loadout for this content. You are warned when entering it with a loadout that is not flagged."], 1, 1, 1, true)
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
    "ACTIVE_COMBAT_CONFIG_CHANGED", "SELECTED_LOADOUT_CHANGED", "CONFIG_COMMIT_FAILED" }) do
    pcall(events.RegisterEvent, events, event)
end

-- The events that end a loadout swap: the build went live, or the client gave up on it.
local LOADING_DONE = {
    TRAIT_CONFIG_UPDATED = true,
    ACTIVE_COMBAT_CONFIG_CHANGED = true,
    CONFIG_COMMIT_FAILED = true,
    PLAYER_SPECIALIZATION_CHANGED = true,
}

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_PlayerSpells" and PullReadyCharDB then
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
                PR.RunTalentCheck()
            end
        end)
    elseif event == "READY_CHECK" then
        if Talents:GetContent() then
            PR.RunTalentCheck()
        end
    else
        if LOADING_DONE[event] then
            Talents:SetLoading(nil)
        end
        Talents:NotifyChanged()
    end
end)
