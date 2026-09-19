local _, RP = ...
local L = RP.L

-- Inspects every group member (one at a time) and lists missing enchants / empty gem sockets.

local INSPECT_INTERVAL = 1.5  -- seconds between NotifyInspect calls (server throttles faster requests)
local INSPECT_TIMEOUT = 5     -- give up on a member after this many seconds
local LINK_RETRIES = 6        -- retries while item links of an inspected unit are still incomplete
local LINK_RETRY_DELAY = 0.3

local ROW_HEIGHT = 24
local NAME_WIDTH = 150

local STATUS_TEXT = {
    pending    = "|cffaaaaaa" .. L["Waiting..."] .. "|r",
    inspecting = "|cffffff00" .. L["Inspecting..."] .. "|r",
    ok         = "|cff40ff40" .. L["OK"] .. "|r",
    offline    = "|cffaaaaaa" .. L["Offline"] .. "|r",
    range      = "|cffaaaaaa" .. L["Out of range"] .. "|r",
    failed     = "|cffff9919" .. L["Inspect failed - try refresh"] .. "|r",
}

local RaidCheck = {}
RP.RaidCheck = RaidCheck

-- In a raid the inspect is only available to the leader and assistants; in a party to everyone.
function RaidCheck:IsAllowed()
    if IsInRaid() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end
    return IsInGroup()
end

function RaidCheck:GetTitle()
    return IsInRaid() and L["Raid Inspect"] or L["Party Inspect"]
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
    entry.whispered = nil
    self:Refresh()
end

function RaidCheck:QueueAll()
    wipe(queue)
    for _, guid in ipairs(order) do
        if not (current and current.guid == guid) then
            queue[#queue + 1] = guid
            members[guid].status = "pending"
            members[guid].whispered = nil
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
        elseif frame and frame:IsVisible() then
            UpdateRoster()
            RaidCheck:Refresh()
        end
        RP.Dialog:UpdateInspectAccess()
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
    local color, text = "ffff4040"
    if issue.kind == "enchant" and issue.problem == "low" then
        color = "ffff9919"
        text = issue.tier == 1 and L["low quality enchant"] or L["mid quality enchant"]
        if issue.itemLevel then
            text = text .. " " .. L["(ilvl %d)"]:format(issue.itemLevel)
        end
    elseif issue.kind == "enchant" then
        text = L["no enchant"]
    elseif issue.kind == "epicgem" then
        text = L["missing"]
    elseif issue.kind == "gem" and issue.empty then
        text = issue.empty == 1 and L["empty gem socket"] or L["%d empty gem sockets"]:format(issue.empty)
    else
        text = issue.detail
    end
    return ("|c%s%s: %s|r"):format(color, issue.slotName, text)
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

---------------------------------------------------------------------------
-- Whisper
---------------------------------------------------------------------------

local WHISPER_MAX = 255 -- chat message length limit
local WHISPER_PREFIX = "[RaidPrepared] " .. L["Hi! Automated gear check found: "]
local WHISPER_SUFFIX = L[". Just a friendly heads-up, no stress :)"]

-- Issue groups in message order: label, count format (singular, plural) and matcher.
local WHISPER_GROUPS = {
    { label = L["missing enchant"], one = L["%d missing enchant"], many = L["%d missing enchants"],
      match = function(i) return i.kind == "enchant" and i.problem == "missing" end },
    { label = L["lower rank enchant"], one = L["%d lower rank enchant"], many = L["%d lower rank enchants"],
      match = function(i) return i.kind == "enchant" and i.problem == "low" end },
    { label = L["empty socket"], one = L["%d empty socket"], many = L["%d empty sockets"],
      match = function(i) return i.kind == "gem" and i.problem == "missing" end },
    { label = L["gem"], one = L["%d gem to check"], many = L["%d gems to check"],
      match = function(i) return i.kind == "gem" end },
    { label = L["enchant"], one = L["%d enchant to check"], many = L["%d enchants to check"],
      match = function(i) return i.kind == "enchant" end },
}

-- Cuts a string to at most maxBytes without splitting a UTF-8 character.
local function TruncateUTF8(text, maxBytes)
    if #text <= maxBytes then return text end
    local cut = maxBytes
    while cut > 0 do
        local byte = text:byte(cut + 1)
        if byte < 0x80 or byte >= 0xC0 then break end -- the next byte starts a character
        cut = cut - 1
    end
    return text:sub(1, cut)
end

local function BuildWhisper(entry)
    local slots = {}
    local epicGem = false
    for _, issue in ipairs(entry.issues) do
        if issue.kind == "epicgem" then
            epicGem = true
        else
            for g, group in ipairs(WHISPER_GROUPS) do
                if group.match(issue) then
                    slots[g] = slots[g] or {}
                    table.insert(slots[g], issue.slotName)
                    break
                end
            end
        end
    end

    local detailed, counted = {}, {}
    for g, group in ipairs(WHISPER_GROUPS) do
        local list = slots[g]
        if list then
            detailed[#detailed + 1] = group.label .. ": " .. table.concat(list, ", ")
            counted[#counted + 1] = (#list == 1 and group.one or group.many):format(#list)
        end
    end
    if epicGem then
        detailed[#detailed + 1] = L["no Eversong Diamond socketed"]
        counted[#counted + 1] = L["no Eversong Diamond"]
    end

    local body = table.concat(detailed, "; ")
    local candidates = {
        WHISPER_PREFIX .. body .. WHISPER_SUFFIX,
        WHISPER_PREFIX .. body,
        WHISPER_PREFIX .. table.concat(counted, ", ") .. WHISPER_SUFFIX,
    }
    for _, msg in ipairs(candidates) do
        if #msg <= WHISPER_MAX then
            return msg
        end
    end
    return TruncateUTF8(candidates[3], WHISPER_MAX)
end

local function CanWhisper(entry)
    if entry.status ~= "issues" or #entry.issues == 0 or entry.whispered then return false end
    if entry.guid == UnitGUID("player") or InCombatLockdown() then return false end
    local unit = FindUnit(entry.guid)
    return unit ~= nil and UnitIsConnected(unit)
end

function RaidCheck:Whisper(guid)
    local entry = members[guid]
    if not entry or not CanWhisper(entry) then return end
    local target = GetUnitName(FindUnit(guid), true)
    if not target or target == UNKNOWNOBJECT then return end

    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    send(BuildWhisper(entry), "WHISPER", nil, target)
    entry.whispered = true
    self:Refresh()
end

-- Widens a button so each of its (localized) labels fits; keeps the first label set.
local function FitButton(button, minWidth, ...)
    local labels = { ... }
    local width = minWidth
    for _, text in ipairs(labels) do
        button:SetText(text)
        width = math.max(width, math.ceil(button:GetFontString():GetStringWidth()) + 20)
    end
    button:SetText(labels[1])
    button:SetWidth(width)
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
    FitButton(row.refresh, 70, L["Refresh"])
    row.refresh:SetScript("OnClick", function()
        RaidCheck:Queue(row.guid)
    end)

    row.whisper = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.whisper:SetSize(70, 20)
    row.whisper:SetPoint("RIGHT", row.refresh, "LEFT", -4, 0)
    FitButton(row.whisper, 70, L["Whisper"], L["Sent"])
    row.whisper:SetMotionScriptsWhileDisabled(true)
    row.whisper:SetScript("OnClick", function()
        RaidCheck:Whisper(row.guid)
    end)
    row.whisper:SetScript("OnEnter", function(self)
        local entry = members[row.guid]
        if not entry or entry.status ~= "issues" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if entry.whispered then
            GameTooltip:AddLine(L["Already whispered. Refresh this member to whisper again."], 1, 1, 1, true)
        else
            GameTooltip:AddLine(L["Whisper %s:"]:format(ColoredName(entry)))
            GameTooltip:AddLine(BuildWhisper(entry), 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row.whisper:SetScript("OnLeave", GameTooltip_Hide)

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.status:SetPoint("RIGHT", row.whisper, "LEFT", -8, 0)
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
                detail = detail .. " " .. L["(ilvl %d)"]:format(issue.itemLevel)
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

-- Builds the inspect list into a parent frame (the "Raid/Party Inspect" tab of the main dialog).
function RaidCheck:CreatePanel(parent)
    frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()
    frame:SetScript("OnShow", function()
        UpdateRoster()
        RaidCheck:Refresh()
    end)

    headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerText:SetPoint("TOP", 0, -42)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -66)
    scroll:SetPoint("BOTTOMRIGHT", -38, 52)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(parent:GetWidth() - 58, 1)
    scroll:SetScrollChild(scrollChild)

    local refreshAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshAll:SetSize(110, 24)
    refreshAll:SetPoint("BOTTOMLEFT", 20, 18)
    FitButton(refreshAll, 110, L["Refresh All"])
    refreshAll:SetScript("OnClick", function() RaidCheck:QueueAll() end)
    return frame
end

function RaidCheck:Refresh()
    if not frame or not frame:IsVisible() then return end

    local done, withIssues = 0, 0
    for i, guid in ipairs(order) do
        local entry = members[guid]
        local row = rows[i] or CreateRow(i)
        row.guid = guid
        row.name:SetText(ColoredName(entry))
        row.status:SetText(StatusText(entry))
        row.refresh:SetEnabled(entry.status ~= "inspecting" and entry.status ~= "pending")
        row.whisper:SetText(entry.whispered and L["Sent"] or L["Whisper"])
        row.whisper:SetEnabled(CanWhisper(entry))
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

    local header = L["%d/%d inspected, %s%d with problems|r"]:format(
        done, #order, withIssues > 0 and "|cffff4040" or "|cff40ff40", withIssues)
    if InCombatLockdown() and (#queue > 0 or current) then
        header = header .. " |cffff9919" .. L["(paused in combat)"] .. "|r"
    end
    headerText:SetText(header)
end

-- Cancels pending inspects and leaves the tab (e.g. after losing lead/assist in a raid).
function RaidCheck:Stop()
    wipe(queue)
    if frame and frame:IsVisible() then
        RP.Dialog:SelectTab(RP.Dialog.TAB_CHECK)
    end
end

function RaidCheck:Open()
    if not self:IsAllowed() then
        print("|cff33ccffRaidPrepared|r: " .. L["Raid Inspect requires raid lead or assist; Party Inspect requires a party."])
        return
    end
    RP.Dialog:OpenTab(RP.Dialog.TAB_INSPECT)
end

function RaidCheck:Toggle()
    if not self:IsAllowed() then
        self:Open()
        return
    end
    RP.Dialog:ToggleTab(RP.Dialog.TAB_INSPECT)
end
