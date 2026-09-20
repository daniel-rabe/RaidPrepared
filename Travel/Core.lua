local _, PR = ...

-- Fast-travel search, merged from the standalone GetAway addon.
-- Namespace, strings, event dispatch, diagnostic output capture, recent list.
--
-- The ported modules keep their original shape and refer to this table as `T`,
-- so they stay easy to diff against upstream GetAway.

local T = {}
PR.Travel = T

local PREFIX = "|cff33ccffPullReady|r: "

-- Set at ADDON_LOADED; every module reads travel settings through this.
T.db = nil

---Chat output. Extra args are treated as string.format arguments.
function T:Print(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, fmt, ...)
        msg = ok and formatted or fmt
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

-- Strings come from the addon-wide locale table (Locales/).
local L = PR.L
T.L = L

-- ============================================================================
-- CAPTURED OUTPUT
-- ============================================================================
-- Diagnostics use T:Out instead of T:Print. Normally it goes to chat, but while
-- a capture is open the lines are buffered and handed to the copy window
-- instead - WoW chat cannot be copied, and scan output is meant to be pasted.

local capture = nil
local lastOutput = ""

---Strip colour escapes so pasted text is clean.
local function StripColors(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
end

---Diagnostic output line. Buffered while capturing, else printed to chat.
function T:Out(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, fmt, ...)
        msg = ok and formatted or fmt
    end
    msg = tostring(msg)

    if capture then
        capture[#capture + 1] = StripColors(msg)
    else
        self:Print(msg)
    end
end

function T:BeginCapture()
    capture = {}
end

---Close the capture and show the collected lines in the copy window.
function T:EndCapture(title)
    local lines = capture or {}
    capture = nil
    lastOutput = table.concat(lines, "\n")

    if lastOutput == "" then
        T:Print(L["no output."])
        return
    end
    T.UI.ShowCopy(title, lastOutput)
end

---Run fn with output captured into the copy window.
function T:RunCaptured(title, fn, ...)
    T:BeginCapture()
    local ok, err = pcall(fn, ...)
    T:EndCapture(title)
    if not ok then
        T:Print("|cffff4040error:|r %s", tostring(err))
    end
end

function T:ShowLastOutput()
    if lastOutput == "" then
        T:Print(L["nothing captured yet - run audit, scan or discover first."])
        return
    end
    T.UI.ShowCopy(L["Last output"], lastOutput)
end

-- ============================================================================
-- SECRET-SAFE READS
-- ============================================================================
-- WoW 12.x tags some combat data as "secret": the value is truthy but throws on
-- compare / arithmetic. These helpers turn "would throw" into "reads as nil" so
-- a restricted context degrades to a missing cooldown swipe instead of an error.

local issecretvalue = issecretvalue

---Return v when it is a plain (non-secret) value, otherwise nil.
function T.Plain(v)
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    return v
end

---Whether cooldown queries currently yield secret values. Fails closed:
---an unreadable answer counts as restricted.
function T.CooldownsRestricted()
    if not (C_Secrets and C_Secrets.ShouldCooldownsBeSecret) then
        return false
    end
    local ok, v = pcall(C_Secrets.ShouldCooldownsBeSecret)
    if not ok then
        return true
    end
    if issecretvalue and issecretvalue(v) then
        return true
    end
    return v and true or false
end

-- ============================================================================
-- EVENT DISPATCH
-- ============================================================================
-- The ported modules register many handlers for the same events, which the
-- one-handler-per-frame style used elsewhere in this addon does not cover.

local handlers = {}
local eventFrame = CreateFrame("Frame", "PullReadyTravelEvents")

---Register a callback for a game event. Multiple callbacks per event are fine.
function T:RegisterEvent(event, fn)
    if not handlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            T:Print("|cffff4040error in %s handler:|r %s", event, tostring(err))
        end
    end
end)

-- ============================================================================
-- RECENTLY USED
-- ============================================================================

---Move an entry key to the front of the recent list.
function T:RememberUse(key)
    local db = T.db
    if not (db and key) then return end
    local recent = db.recent
    for i = #recent, 1, -1 do
        if recent[i] == key then
            table.remove(recent, i)
        end
    end
    table.insert(recent, 1, key)
    for i = #recent, db.maxRecent + 1, -1 do
        table.remove(recent, i)
    end
end

---Rank of a key in the recent list (1 = most recent), or nil when never used.
function T:RecentRank(key)
    local db = T.db
    if not db then return nil end
    for i = 1, #db.recent do
        if db.recent[i] == key then
            return i
        end
    end
    return nil
end
