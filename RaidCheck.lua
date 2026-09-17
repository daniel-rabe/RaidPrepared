local _, RP = ...

-- Inspects every group member (one at a time) and lists missing enchants / empty gem sockets.

local INSPECT_INTERVAL = 1.5  -- seconds between NotifyInspect calls (server throttles faster requests)
local INSPECT_TIMEOUT = 5     -- give up on a member after this many seconds
local LINK_RETRIES = 6        -- retries while item links of an inspected unit are still incomplete
local LINK_RETRY_DELAY = 0.3

local FRAME_WIDTH = 580
local FRAME_HEIGHT = 440
local ROW_HEIGHT = 24
local NAME_WIDTH = 150

local STATUS_TEXT = {
    pending    = "|cffaaaaaaWaiting...|r",
    inspecting = "|cffffff00Inspecting...|r",
    ok         = "|cff40ff40OK|r",
    offline    = "|cffaaaaaaOffline|r",
    range      = "|cffaaaaaaOut of range|r",
    failed     = "|cffff9919Inspect failed - try refresh|r",
}

local RaidCheck = {}
RP.RaidCheck = RaidCheck

-- The raid check is only available to the group leader and raid assistants.
function RaidCheck:IsAllowed()
    return IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
end

local members = {} -- guid -> { guid, name, classFile, status, issues }
local order = {}   -- guids sorted by name
local queue = {}   -- guids waiting to be inspected
local current      -- { guid, started, scanning } of the member being inspected
local lastRequest = 0

local frame, scrollChild, headerText
local rows = {}

---------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------

local function GetGroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
    else
        units[1] = "player"
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do
                units[#units + 1] = "party" .. i
            end
        end
    end
    return units
end

local function FindUnit(guid)
    if guid == UnitGUID("player") then
        return "player"
    end
    for _, unit in ipairs(GetGroupUnits()) do
        if UnitGUID(unit) == guid then
            return unit
        end
    end
    return nil
end

local function RemoveFromQueue(guid)
    for i = #queue, 1, -1 do
        if queue[i] == guid then
            table.remove(queue, i)
        end
    end
end

local function UpdateRoster()
    local seen = {}
    for _, unit in ipairs(GetGroupUnits()) do
        local guid = UnitGUID(unit)
        if guid then
            seen[guid] = true
            local entry = members[guid]
            if not entry then
                entry = { guid = guid, status = "pending", issues = {} }
                members[guid] = entry
                queue[#queue + 1] = guid
            end
            local name = GetUnitName(unit, true)
            if name and name ~= UNKNOWNOBJECT then
                entry.name = name
            end
            entry.name = entry.name or UNKNOWNOBJECT
            entry.classFile = select(2, UnitClass(unit)) or entry.classFile
        end
    end

    for guid in pairs(members) do
        if not seen[guid] then
            members[guid] = nil
            RemoveFromQueue(guid)
        end
    end
    if current and not seen[current.guid] then
        current = nil
    end

    wipe(order)
    for guid in pairs(members) do
        order[#order + 1] = guid
    end
    table.sort(order, function(a, b)
        return members[a].name < members[b].name
    end)
end

---------------------------------------------------------------------------
-- Inspect queue
---------------------------------------------------------------------------

local function Finish(guid, status, issues)
    local entry = members[guid]
    if entry then
        entry.status = status
        entry.issues = issues or {}
    end
    if current and current.guid == guid then
        local notified = current.notified
        current = nil
        if notified and not (InspectFrame and InspectFrame:IsShown()) then
            ClearInspectPlayer()
        end
    end
    RaidCheck:Refresh()
end

local function CountEquippedItems(unit)
    local count = 0
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        if GetInventoryItemID(unit, slot) then
            count = count + 1
        end
    end
    return count
end

local function ScanMember(guid, unit)
    RP.ScanUnitAsync(unit, "enchant", function(issues)
        if current and current.guid == guid then
            Finish(guid, #issues > 0 and "issues" or "ok", issues)
        end
    end)
end

local function OnInspectReady(guid)
    if not current or current.guid ~= guid or current.scanning then return end

    local unit = FindUnit(guid)
    if not unit then
        Finish(guid, "failed")
        return
    end

    current.scanning = true
    current.started = GetTime()
    local tries = 0

    local function TryScan()
        if not current or current.guid ~= guid then return end
        if (CountEquippedItems(unit) == 0 or not RP.HasAllItemLinks(unit)) and tries < LINK_RETRIES then
            tries = tries + 1
            C_Timer.After(LINK_RETRY_DELAY, TryScan)
            return
        end
        if CountEquippedItems(unit) == 0 then
            Finish(guid, "failed")
            return
        end
        ScanMember(guid, unit)
    end
    TryScan()
end

local function ProcessQueue()
    if current then
        if GetTime() - current.started > INSPECT_TIMEOUT then
            Finish(current.guid, "failed")
        end
        return
    end
    if #queue == 0 or InCombatLockdown() then return end
    if GetTime() - lastRequest < INSPECT_INTERVAL then return end
    if InspectFrame and InspectFrame:IsShown() then return end -- don't disturb a manual inspect

    local guid = table.remove(queue, 1)
    local entry = members[guid]
    local unit = FindUnit(guid)
    if not entry or not unit then return end

    if unit == "player" then
        current = { guid = guid, started = GetTime(), scanning = true }
        entry.status = "inspecting"
        ScanMember(guid, "player")
        return
    end

    if not UnitIsConnected(unit) then
        Finish(guid, "offline")
        return
    end
    if not UnitIsVisible(unit) or not CanInspect(unit) then
        Finish(guid, "range")
        return
    end

    current = { guid = guid, started = GetTime(), notified = true }
    entry.status = "inspecting"
    lastRequest = GetTime()
    NotifyInspect(unit)
    RaidCheck:Refresh()
end

function RaidCheck:Queue(guid)
    local entry = members[guid]
    if not entry or (current and current.guid == guid) then return end
    RemoveFromQueue(guid)
    table.insert(queue, 1, guid)
    entry.status = "pending"
    self:Refresh()
end

function RaidCheck:QueueAll()
    wipe(queue)
    for _, guid in ipairs(order) do
        if not (current and current.guid == guid) then
            queue[#queue + 1] = guid
            members[guid].status = "pending"
        end
    end
    self:Refresh()
end

local ticker = CreateFrame("Frame")
local elapsedSince = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.2 then return end
    elapsedSince = 0
    if current or #queue > 0 then
        ProcessQueue()
    end
end)

ticker:RegisterEvent("INSPECT_READY")
ticker:RegisterEvent("GROUP_ROSTER_UPDATE")
ticker:RegisterEvent("PARTY_LEADER_CHANGED")
ticker:RegisterEvent("PLAYER_REGEN_ENABLED")
ticker:RegisterEvent("PLAYER_REGEN_DISABLED")
ticker:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" then
        OnInspectReady(arg1)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        if not RaidCheck:IsAllowed() then
            RaidCheck:Stop()
        elseif frame and frame:IsShown() then
            UpdateRoster()
            RaidCheck:Refresh()
        end
        RP.Dialog:UpdateRaidCheckButton()
    else
        RaidCheck:Refresh()
    end
end)

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function ColoredName(entry)
    local color = entry.classFile and C_ClassColor and C_ClassColor.GetClassColor(entry.classFile)
    return color and color:WrapTextInColorCode(entry.name) or entry.name
end

local function ShortIssue(issue)
    if issue.kind == "enchant" and issue.problem == "low" then
        local quality = issue.tier == 1 and "low" or "mid"
        local ilvl = issue.itemLevel and (" (ilvl %d)"):format(issue.itemLevel) or ""
        return ("|cffff9919%s: %s quality enchant%s|r"):format(issue.slotName, quality, ilvl)
    elseif issue.kind == "enchant" then
        return "|cffff4040" .. issue.slotName .. ": no enchant|r"
    elseif issue.kind == "epicgem" then
        return "|cffff4040" .. issue.slotName .. ": missing|r"
    end
    return "|cffff4040" .. issue.slotName .. ": " .. issue.detail:lower() .. "|r"
end

local function StatusText(entry)
    if entry.status == "issues" then
        local parts = {}
        for _, issue in ipairs(entry.issues) do
            parts[#parts + 1] = ShortIssue(issue)
        end
        return table.concat(parts, ", ")
    end
    return STATUS_TEXT[entry.status] or entry.status
end

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:EnableMouse(true)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.refresh = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.refresh:SetSize(70, 20)
    row.refresh:SetPoint("RIGHT", -2, 0)
    row.refresh:SetText("Refresh")
    row.refresh:SetScript("OnClick", function()
        RaidCheck:Queue(row.guid)
    end)

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.status:SetPoint("RIGHT", row.refresh, "LEFT", -8, 0)
    row.status:SetJustifyH("LEFT")
    row.status:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        local entry = members[self.guid]
        if not entry or #entry.issues == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ColoredName(entry))
        for _, issue in ipairs(entry.issues) do
            local detail = issue.detail
            if issue.itemLevel then
                detail = ("%s (ilvl %d)"):format(detail, issue.itemLevel)
            end
            local g = issue.problem == "missing" and 0.25 or 0.6
            GameTooltip:AddDoubleLine(issue.itemLink or issue.slotName, detail, 1, 1, 1, 1, g, 0.1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    rows[index] = row
    return row
end

local function CreateWindow()
    frame = CreateFrame("Frame", "RaidPreparedRaidCheck", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", 40, -40)
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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("RaidPrepared - Raid Gear Check")

    headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerText:SetPoint("TOP", title, "BOTTOM", 0, -6)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -62)
    scroll:SetPoint("BOTTOMRIGHT", -38, 52)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(FRAME_WIDTH - 58, 1)
    scroll:SetScrollChild(scrollChild)

    local refreshAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshAll:SetSize(120, 24)
    refreshAll:SetPoint("BOTTOMLEFT", 20, 18)
    refreshAll:SetText("Refresh All")
    refreshAll:SetScript("OnClick", function() RaidCheck:QueueAll() end)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(120, 24)
    closeButton:SetPoint("BOTTOMRIGHT", -20, 18)
    closeButton:SetText(CLOSE or "Close")
    closeButton:SetScript("OnClick", function() frame:Hide() end)
end

function RaidCheck:Refresh()
    if not frame or not frame:IsShown() then return end

    local done, withIssues = 0, 0
    for i, guid in ipairs(order) do
        local entry = members[guid]
        local row = rows[i] or CreateRow(i)
        row.guid = guid
        row.name:SetText(ColoredName(entry))
        row.status:SetText(StatusText(entry))
        row.refresh:SetEnabled(entry.status ~= "inspecting" and entry.status ~= "pending")
        row:Show()

        if entry.status == "ok" or entry.status == "issues" then
            done = done + 1
        end
        if entry.status == "issues" then
            withIssues = withIssues + 1
        end
    end
    for i = #order + 1, #rows do
        rows[i]:Hide()
    end
    scrollChild:SetHeight(math.max(1, #order * ROW_HEIGHT))

    local header = ("%d/%d inspected, %s%d with problems|r"):format(
        done, #order, withIssues > 0 and "|cffff4040" or "|cff40ff40", withIssues)
    if InCombatLockdown() and (#queue > 0 or current) then
        header = header .. " |cffff9919(paused in combat)|r"
    end
    headerText:SetText(header)
end

-- Closes the window and cancels pending inspects (e.g. after losing lead/assist).
function RaidCheck:Stop()
    wipe(queue)
    if frame and frame:IsShown() then
        frame:Hide()
    end
end

function RaidCheck:Open()
    if not self:IsAllowed() then
        print("|cff33ccffRaidPrepared|r: The raid check requires raid lead or assist.")
        return
    end
    if not frame then CreateWindow() end
    UpdateRoster()
    frame:Show()
    self:Refresh()
end

function RaidCheck:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:Open()
    end
end
