local _, RP = ...
local T = RP.Travel
local L = T.L

-- RaidPrepared - Travel/Panel.lua
-- The travel tab: one edit box, and a pool of secure action buttons underneath
-- it that get rebound to whatever the search currently matches.
--
-- Secure buttons cannot be created OR rebound while the player is in combat.
-- The dialog is built lazily on first open, which may happen mid-fight, so the
-- pool is built on demand and every build/rebind is gated on InCombatLockdown.
-- In combat the tab greys out and says so, then fills in on PLAYER_REGEN_ENABLED.

T.UI = T.UI or {}
local UI = T.UI

local MAX_ROWS    = 8
local ROW_HEIGHT  = 28
local ROW_SPACING = 2
local SIDE_INSET  = 20
local ROWS_TOP    = 76   -- below the dialog title and the search box
local CD_THROTTLE = 0.25

local panel, editBox, placeholder, emptyText, footerText, seasonButton
local rows          = {}
local results       = {}
local rowWidth      = 540
local poolBuilt     = false
local pendingUpdate = false
local seasonOnly    = false
local cdElapsed     = 0

-- ============================================================================
-- COOLDOWN (secret-safe)
-- ============================================================================

---Cooldown start/duration for an option, or nil when there is none to draw.
---Reads fail closed: a restricted or secret value yields nil, never an error.
local function GetCooldown(opt)
    if T.CooldownsRestricted() then
        return nil
    end

    local start, duration

    if opt.kind == "spell" then
        if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
        local ok, info = pcall(C_Spell.GetSpellCooldown, opt.id)
        if not ok or type(info) ~= "table" then return nil end
        start, duration = T.Plain(info.startTime), T.Plain(info.duration)
    else
        -- Toys are items, so both share the item cooldown API.
        if not (C_Item and C_Item.GetItemCooldown) then return nil end
        local ok, s, d = pcall(C_Item.GetItemCooldown, opt.id)
        if not ok then return nil end
        start, duration = T.Plain(s), T.Plain(d)
    end

    if not start or not duration or duration <= 0 then
        return nil
    end
    return start, duration
end

-- ============================================================================
-- ROW BINDING
-- ============================================================================

---Clear every action attribute so nothing stale survives a rebind.
local function ClearActionAttributes(row)
    row:SetAttribute("type", nil)
    row:SetAttribute("type1", nil)
    row:SetAttribute("type2", nil)
    row:SetAttribute("spell", nil)
    row:SetAttribute("item", nil)
    row:SetAttribute("toy", nil)
    row:SetAttribute("macrotext", nil)
    -- A stale unit silently retargets the next cast, so always write it.
    row:SetAttribute("unit", nil)
end

---Point a row at an option. Caller guarantees we are out of combat.
local function BindRow(row, opt)
    ClearActionAttributes(row)

    if opt.kind == "spell" then
        row:SetAttribute("type1", "spell")
        row:SetAttribute("spell", opt.id)
    elseif opt.kind == "toy" then
        row:SetAttribute("type1", "toy")
        row:SetAttribute("toy", opt.id)
    else
        row:SetAttribute("type1", "item")
        row:SetAttribute("item", "item:" .. opt.id)
    end

    -- Right-click toggles the favourite, so it must not cast. An unset type2
    -- falls back to type1, so the empty string is what actually disables it.
    row:SetAttribute("type2", "")

    row.opt = opt
    row.icon:SetTexture(opt.icon)
    row.label:SetText(opt.display or opt.name)
    row.category:SetText(L["cat." .. opt.cat])

    local isFav = T.db and T.db.favorites[opt.key]
    row.star:SetShown(isFav and true or false)

    row:Show()
end

local function HideRow(row)
    row.opt = nil
    row:Hide()
end

-- ============================================================================
-- CONSTRUCTION
-- ============================================================================

local function CreateRow(index)
    local row = CreateFrame("Button", "RaidPreparedTravelRow" .. index, panel, "SecureActionButtonTemplate")
    row:SetSize(rowWidth, ROW_HEIGHT)
    -- Both edges: with "action button use key down" enabled (the retail
    -- default) the secure handler fires on the down edge, so a button
    -- registered only for "AnyUp" never casts at all.
    row:RegisterForClicks("AnyDown", "AnyUp")

    if index == 1 then
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE_INSET, -ROWS_TOP)
    else
        row:SetPoint("TOPLEFT", rows[index - 1], "BOTTOMLEFT", 0, -ROW_SPACING)
    end

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.05)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
    row.icon:SetPoint("LEFT", 3, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.cooldown = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cooldown:SetAllPoints(row.icon)
    row.cooldown:SetDrawBling(false)

    row.category = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.category:SetPoint("RIGHT", -6, 0)
    row.category:SetJustifyH("RIGHT")

    row.star = row:CreateTexture(nil, "OVERLAY")
    row.star:SetSize(12, 12)
    row.star:SetPoint("RIGHT", row.category, "LEFT", -4, 0)
    row.star:SetAtlas("PetJournal-FavoritesIcon")
    row.star:Hide()

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row.star, "LEFT", -4, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.15)
        if not self.opt then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.opt.kind == "spell" then
            GameTooltip:SetSpellByID(self.opt.id)
        else
            GameTooltip:SetItemByID(self.opt.id)
        end
        -- The row shows the destination, so name the spell it actually casts.
        if self.opt.display and self.opt.display ~= self.opt.name then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.opt.name, 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Right-click to favourite"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.05)
        GameTooltip:Hide()
    end)

    row:SetScript("PostClick", function(self, button, down)
        -- Registered for both edges so the secure cast fires; our own
        -- bookkeeping must still happen exactly once, on release.
        if down then return end
        if not self.opt then return end

        if button == "RightButton" then
            -- Right-click never casts: type2 is left unset, so this is ours.
            local favorites = T.db.favorites
            local key = self.opt.key
            favorites[key] = (not favorites[key]) or nil
            UI.Refresh()
            return
        end

        T:RememberUse(self.opt.key)
        if T.db.closeOnUse then
            RP.Dialog:Hide()
        end
    end)

    rows[index] = row
    return row
end

---Build the secure button pool. Returns false when combat blocks it.
local function EnsurePool()
    if poolBuilt then return true end
    if InCombatLockdown() then return false end
    for i = 1, MAX_ROWS do
        CreateRow(i)
    end
    poolBuilt = true
    return true
end

-- ============================================================================
-- REFRESH
-- ============================================================================

---Re-run the search and rebind the button pool.
function UI.Refresh()
    if not panel then return end

    if InCombatLockdown() then
        -- Attributes are frozen, and the pool cannot be built. Show why, and
        -- pick this up on regen.
        pendingUpdate = true
        footerText:SetText("|cffff8040" .. L["Locked in combat"] .. "|r")
        footerText:Show()
        emptyText:Hide()
        for i = 1, #rows do
            rows[i]:SetAlpha(0.4)
        end
        return
    end

    if not EnsurePool() then return end

    pendingUpdate = false
    results = T.Search.Run(editBox:GetText() or "")

    if seasonOnly then
        local filtered = {}
        for i = 1, #results do
            if T.Season.IsCurrent(results[i]) then
                filtered[#filtered + 1] = results[i]
            end
        end
        results = filtered
    end

    local shown = math.min(#results, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local row = rows[i]
        row:SetAlpha(1)
        if i <= shown then
            BindRow(row, results[i])
        else
            HideRow(row)
        end
    end

    if #results == 0 then
        local message
        if seasonOnly then
            message = L["No current-season ports available."]
        elseif #T.Collector.Get() > 0 then
            message = L["No matching travel options."]
        else
            message = L["Nothing available yet."]
        end
        emptyText:SetText(message)
        emptyText:Show()
    else
        emptyText:Hide()
    end

    if #results > MAX_ROWS then
        footerText:SetText("|cff808080" .. L["+%d more - keep typing to narrow"]
            :format(#results - MAX_ROWS) .. "|r")
        footerText:Show()
    else
        footerText:Hide()
    end

    cdElapsed = CD_THROTTLE  -- force a cooldown pass on the next frame
end

---Repaint cooldown swipes on the visible rows.
local function UpdateCooldowns()
    for i = 1, #rows do
        local row = rows[i]
        if row:IsShown() and row.opt then
            local start, duration = GetCooldown(row.opt)
            if start then
                row.cooldown:SetCooldown(start, duration)
                row.icon:SetDesaturated(true)
            else
                row.cooldown:Clear()
                row.icon:SetDesaturated(false)
            end
        end
    end
end

-- ============================================================================
-- PANEL
-- ============================================================================

---Turn the current-season dungeon filter on or off.
function UI.SetSeasonOnly(on)
    seasonOnly = on and true or false
    if seasonButton then
        -- Locked "pushed" look so the active filter is obvious.
        seasonButton:SetButtonState(seasonOnly and "PUSHED" or "NORMAL", seasonOnly)
    end
    UI.Refresh()
end

-- Builds the travel search into a parent frame (the "Travel" tab of the main dialog).
function T:CreatePanel(parent)
    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()

    rowWidth = parent:GetWidth() - 2 * SIDE_INSET

    seasonButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    seasonButton:SetSize(34, 20)
    seasonButton:SetPoint("TOPRIGHT", -SIDE_INSET, -44)
    seasonButton:SetText("M+")
    seasonButton:SetNormalFontObject("GameFontNormalSmall")
    seasonButton:SetHighlightFontObject("GameFontHighlightSmall")
    seasonButton:SetScript("OnClick", function()
        UI.SetSeasonOnly(not seasonOnly)
    end)
    seasonButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Current season Mythic+"])
        GameTooltip:AddLine(L["Show only dungeon ports for this season's keys."], 0.8, 0.8, 0.8, true)
        if #T.Season.CurrentMaps() == 0 then
            GameTooltip:AddLine(L["Season data not loaded yet."], 1, 0.5, 0.25, true)
        end
        GameTooltip:Show()
    end)
    seasonButton:SetScript("OnLeave", GameTooltip_Hide)

    editBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", SIDE_INSET + 6, -44)
    editBox:SetPoint("TOPRIGHT", seasonButton, "TOPLEFT", -10, 0)
    editBox:SetHeight(20)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        UI.Refresh()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        RP.Dialog:Hide()
    end)
    -- Enter cannot activate a secure button from insecure code, so it just
    -- releases focus. Click a row to travel.
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    placeholder = editBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 4, 0)
    placeholder:SetText(L["Search travel options..."])

    -- Anchored to the panel, not to rows[1]: the pool may not exist yet.
    emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", SIDE_INSET + 4, -(ROWS_TOP + 6))
    emptyText:Hide()

    footerText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerText:SetPoint("BOTTOMLEFT", SIDE_INSET, 30)
    footerText:SetPoint("BOTTOMRIGHT", -SIDE_INSET, 30)
    footerText:SetJustifyH("LEFT")
    footerText:Hide()

    panel:SetScript("OnShow", function()
        editBox:SetText("")
        editBox:SetFocus()
        T.Collector.Invalidate()
        UI.Refresh()
    end)

    panel:SetScript("OnHide", function()
        editBox:ClearFocus()
        GameTooltip:Hide()
    end)

    panel:SetScript("OnUpdate", function(_, elapsed)
        cdElapsed = cdElapsed + elapsed
        if cdElapsed >= CD_THROTTLE then
            cdElapsed = 0
            UpdateCooldowns()
        end
    end)

    -- Hiding the dialog does not fire the panel's own OnHide, and an edit box
    -- that keeps focus swallows every keypress - including chat.
    parent:HookScript("OnHide", function()
        if editBox then editBox:ClearFocus() end
    end)

    return panel
end

function T:Open()
    RP.Dialog:OpenTab(RP.Dialog.TAB_TRAVEL)
end

function T:Toggle()
    RP.Dialog:ToggleTab(RP.Dialog.TAB_TRAVEL)
end

-- ============================================================================
-- EVENTS
-- ============================================================================

local function PanelVisible()
    return panel and panel:IsVisible()
end

T:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if PanelVisible() then UI.Refresh() end
end)

T:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingUpdate and PanelVisible() then UI.Refresh() end
end)

-- Item data trickles in one event per item, so debounce rather than rebuilding
-- the list dozens of times in a row.
local refreshQueued = false
local function QueueRefresh()
    if refreshQueued or not PanelVisible() then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        if PanelVisible() then UI.Refresh() end
    end)
end

T:RegisterEvent("GET_ITEM_INFO_RECEIVED", QueueRefresh)
T:RegisterEvent("SPELL_DATA_LOAD_RESULT", QueueRefresh)
