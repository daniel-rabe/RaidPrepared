-- Loads PullReady against the stub client and drives the dialog, so that the
-- theme work is exercised outside the game. Not a substitute for testing in the
-- client - it proves the code runs, not that it looks right.

local stub = dofile(SMOKE_DIR .. "/stub.lua")
local newWidget = stub.newWidget

local frames = {}

function CreateFrame(kind, name, parent, template)
    local f = newWidget(kind or "Frame", name, parent)
    f._template = template
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end

UIParent = newWidget("Frame", "UIParent")

-- The character sheet the indicator code hangs off. Hidden, so the async scan
-- bails out the way it does when the sheet is closed.
PaperDollFrame = newWidget("Frame", "PaperDollFrame")
PaperDollFrame:Hide()
CharacterFrame = newWidget("Frame", "CharacterFrame")
CharacterFrame:Hide()
for _, slot in ipairs({
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot",
    "CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
}) do
    _G[slot] = newWidget("Button", slot, CharacterFrame)
end
UISpecialFrames = {}
SlashCmdList = {}

-- The client's Lua aliases. The game runs Lua 5.1, where unpack is a global; the
-- host runtime here may be newer, so put it back.
unpack = rawget(_G, "unpack") or table.unpack
loadstring = rawget(_G, "loadstring") or load
tinsert, tremove, tContains = table.insert, table.remove, nil
sort, wipe = table.sort, function(t) for k in pairs(t) do t[k] = nil end return t end
strjoin, strsplit = nil, nil
strtrim = function(v) return (tostring(v):gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, strupper = string.lower, string.upper
strfind, strmatch, strsub, strrep = string.find, string.match, string.sub, string.rep
format, gsub = string.format, string.gsub
max, min, abs, floor, ceil = math.max, math.min, math.abs, math.floor, math.ceil
date, time = os.date, os.time
GetTime = function() return 1000 end
LibStub = nil
Minimap = nil
Settings = nil
InterfaceOptions_AddCategory = nil

GameTooltip = newWidget("GameTooltip", "GameTooltip")
stub.methods.SetOwner = function() end
stub.methods.AddLine = function() end
stub.methods.AddDoubleLine = function() end
stub.methods.SetInventoryItem = function() end
stub.methods.SetHyperlink = function() end
stub.methods.ClearLines = function() end
stub.methods.NumLines = function() return 0 end
stub.methods.SetSpellByID = function() end
function GameTooltip_Hide() end
function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a,
             GetRGBA = function(self) return self.r, self.g, self.b, self.a end }
end

-- Sound kits stub as their own name and every played sound is recorded, so the
-- drive section below can tell the ordinary alert from Illidan.
SOUNDKIT = setmetatable({}, { __index = function(_, key) return key end })
local soundsPlayed = {}
function PlaySound(kit)
    soundsPlayed[#soundsPlayed + 1] = kit
    return true
end
function GetLocale() return "enUS" end
function InCombatLockdown() return false end
function IsInRaid() return false end
function IsInGroup() return false end
function GetInventoryItemTexture() return 134400 end
function GetInventoryItemLink() return nil end
function GetInventoryItemDurability() return nil end

OPTIONS, TALENTS = "Options", "Talents"
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
ITEM_QUALITY_COLORS = setmetatable({}, {
    __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end,
})

-- Talent loadouts: two saved configs on the current spec, the first one active.
-- LoadConfig records what the addon asked for, so the talents tab's click handler
-- can be driven and checked below.
local loadoutNames = { [11] = "Raid", [12] = "Mythic+" }
local selectedConfigID, loadedConfigID = 11, nil
C_ClassTalents = {
    GetConfigIDsBySpecID = function() return { 11, 12 } end,
    GetLastSelectedSavedConfigID = function() return selectedConfigID end,
    GetStarterBuildActive = function() return false end,
    LoadConfig = function(configID) loadedConfigID = configID; return 2 end, -- LoadInProgress
    UpdateLastSelectedSavedConfigID = function(_, configID) selectedConfigID = configID end,
}
C_Traits = { GetConfigInfo = function(configID) return { name = loadoutNames[configID] } end }
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 250, "Blood", "", 135770 end,
}
PlayerUtil = { GetCurrentSpecID = function() return 250 end }
Enum = { LoadConfigResult = { Error = 0, NoChangesNecessary = 1, LoadInProgress = 2 } }

C_Texture = { GetAtlasInfo = function(atlas) return { width = 24, height = 24 } end }
-- After runs the callback straight away, so deferred work is exercised in this pass.
-- NewTimer does not: its only caller is a failsafe that is meant to be cancelled long
-- before it fires, and firing it here would undo the state the test is checking.
local timers = {}
C_Timer = {
    After = function(_, fn) fn() end,
    NewTimer = function(_, fn)
        local timer = { fire = fn, Cancel = function(self) self.cancelled = true end }
        timers[#timers + 1] = timer
        return timer
    end,
}

-- Anything else the addon reaches for becomes a harmless function. Constants that
-- matter are defined above; this only keeps unrelated modules from exploding while
-- the dialog is being exercised.
local realG = _G

-- Unknown client globals become a plain string of their own name. Most of the
-- ones this addon touches are localized format strings or constants, and a string
-- supports the :gsub/:format calls and the concatenation they get used in.
-- Globals that really are functions are defined above; anything missed shows up
-- immediately as "attempt to call a string value".
setmetatable(_G, {
    __index = function(_, key)
        local stubbed = "<" .. key .. " %s %d>"
        rawset(realG, key, stubbed)
        return stubbed
    end,
})

-- ------------------------------------------------------------------ load
local PR = {}
local toc = io.open(TOC, "r"):read("*a")
local loaded = {}
for line in toc:gmatch("[^\r\n]+") do
    local rel = line:match("^%s*(.-%.lua)%s*$")
    if rel then
        rel = rel:gsub("\\", "/")
        local chunk, err = loadfile(ROOT .. "/" .. rel)
        assert(chunk, err)
        chunk("PullReady", PR)
        loaded[#loaded + 1] = rel
    end
end
print(("loaded %d files"):format(#loaded))

-- ------------------------------------------------------------------ saved vars
PullReadyDB = {}
PullReadyCharDB = { loadoutFlags = {} }
RaidPreparedDB = nil
RaidPreparedCharDB = nil

-- Same defaults the addon applies on ADDON_LOADED.
local function applyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(db[key]) ~= "table" then db[key] = {} end
            applyDefaults(db[key], value)
        elseif db[key] == nil then
            db[key] = value
        end
    end
end
applyDefaults(PullReadyDB, {
    minimap = { hide = false, angle = 225 }, characterIndicators = true,
    localizedWhisper = false, funMode = false, theme = "default",
    shoppingShowAll = false, shoppingFavoritesOnly = false, whisperLocale = "enUS",
    travel = { closeOnUse = true, maxRecent = 15, seasonOnly = false, recent = {}, favorites = {} },
})

-- ------------------------------------------------------------------ drive it
assert(PR.Theme, "PR.Theme missing")
assert(PR.Theme:Name() == "default", "unexpected starting theme")

PR.Dialog:OpenTab(PR.Dialog.TAB_CHECK)
print("dialog created, tabs: " .. #PullReadyDialog.Tabs)

for index = 1, 6 do
    PR.Dialog:SelectTab(index)
end
print("selected every tab")

-- The inspect tab must be unusable while solo, and selecting it must fall back.
PR.Dialog:UpdateInspectAccess()
local inspect = PullReadyDialog.Tabs[PR.Dialog.TAB_INSPECT]
assert(inspect.isDisabled, "inspect tab should be disabled while solo")
PR.Dialog:SelectTab(PR.Dialog.TAB_INSPECT)
assert(PullReadyDialog.selectedTab == PR.Dialog.TAB_CHECK,
    "selecting the disabled inspect tab must fall back to the check tab")
print("disabled-tab fallback ok")

-- Short labels keep their text; labels too wide for the frame collapse the whole
-- strip to icons, with the label moving into the tooltip.
assert(PullReadyDialog.Tabs[1].label:IsShown(), "English labels should fit")
local original = {}
for index, tab in ipairs(PullReadyDialog.Tabs) do
    original[index] = tab.text
    tab.text = "Ein sehr langer Reiterbeschriftungstext"
end
PR.Dialog:UpdateInspectAccess()
assert(not PullReadyDialog.Tabs[1].label:IsShown(),
    "oversized labels must collapse the tab strip to icons")
for index, tab in ipairs(PullReadyDialog.Tabs) do tab.text = original[index] end
PR.Dialog:UpdateInspectAccess()
assert(PullReadyDialog.Tabs[1].label:IsShown(), "labels should come back")
print("tab label fallback ok")

-- Talents tab: a row per saved loadout, and the name is a button that loads it.
PR.Dialog:SelectTab(PR.Dialog.TAB_TALENTS)
PR.Talents:RefreshWindow()

local function loadoutButtons()
    local found = {}
    for _, f in ipairs(frames) do
        local parent = f._parent
        if f._kind == "Button" and parent and parent.configID and f:GetScript("OnClick") then
            found[#found + 1] = f
        end
    end
    return found
end

local buttons = loadoutButtons()
assert(#buttons == 2, "expected one clickable name per saved loadout, got " .. #buttons)

-- Talents.lua's own event frame, the one listening for the trait config events.
local talentEvents
for _, f in ipairs(frames) do
    if f._events and f._events.TRAIT_CONFIG_UPDATED then talentEvents = f end
end
assert(talentEvents, "the talent event frame was not found")

-- The second row is not the active loadout, so clicking it loads it.
buttons[2]:GetScript("OnEnter")(buttons[2])
buttons[2]:GetScript("OnClick")(buttons[2])
assert(loadedConfigID == 12, "clicking a loadout name should load that loadout")
assert(selectedConfigID == 12, "the loaded loadout should become the selected one")

-- While the server applies the build the row says so instead of calling itself active,
-- and a second click is ignored until it is done.
assert(PR.Talents:IsLoading(), "the loadout being applied should be marked as loading")
assert(buttons[2]._parent.name._text:find("loading"),
    "the row should say it is loading, got: " .. tostring(buttons[2]._parent.name._text))
loadedConfigID = nil
buttons[1]:GetScript("OnClick")(buttons[1])
assert(loadedConfigID == nil, "a second loadout must not be queued while one is applying")

-- TRAIT_CONFIG_UPDATED is the client confirming the swap: the marker gives way to "active".
talentEvents:GetScript("OnEvent")(talentEvents, "TRAIT_CONFIG_UPDATED")
assert(not PR.Talents:IsLoading(), "the marker should clear once the config is confirmed")
assert(buttons[2]._parent.name._text:find("active"),
    "the applied loadout should read as active, got: " .. tostring(buttons[2]._parent.name._text))

-- Clicking the one that is already active does nothing.
loadedConfigID = nil
buttons[2]:GetScript("OnClick")(buttons[2])
assert(loadedConfigID == nil, "the active loadout must not be reloaded")

-- And talents are locked in combat.
InCombatLockdown = function() return true end
buttons[1]:GetScript("OnClick")(buttons[1])
assert(loadedConfigID == nil, "no loadout may be loaded in combat")
InCombatLockdown = function() return false end
print("talent loadout switching ok")

-- Switch themes both ways.
PR.Theme:Set("darkgold")
assert(PR.Theme:Name() == "darkgold", "theme did not change")
assert(PullReadyDB.theme == "darkgold", "theme not saved")
PR.Theme:Set("default")
PR.Theme:Set("darkgold")
print("theme switching ok")

-- Fun mode still swaps the header and the status strings.
PR.Fun:SetEnabled(true)
assert(PR.Fun:Title() == "RaidReadyMcRaidface", "fun title missing")
PR.Fun:SetEnabled(false)
print("fun mode ok")

-- A populated check run, then an empty one.
PR.Dialog:Show({
    { slot = 1, slotName = "Head", problem = "missing", detail = "Missing enchant" },
    { slot = 5, slotName = "Chest", problem = "low", detail = "Low quality gem" },
}, nil, nil, nil)
PR.Dialog:Show({}, nil, nil, nil)
print("populate ok")

-- Fun mode swaps the warning sound too. GetTime is frozen in this stub, so the
-- second window falls straight into the shout's cooldown and back onto the alert.
local issues = { { slot = 1, slotName = "Head", problem = "missing", detail = "Missing enchant" } }
local function lastSound() return soundsPlayed[#soundsPlayed] end

PR.Fun:SetEnabled(true)
PR.Dialog:Show(issues, nil, nil, nil)
assert(lastSound() == 11466, "fun mode should answer a failed check with Illidan")
PR.Dialog:Show(issues, nil, nil, nil)
assert(lastSound() == "RAID_WARNING", "a shout on cooldown falls back to the alert")

PR.Fun:SetEnabled(false)
PR.Dialog:Show(issues, nil, nil, nil)
assert(lastSound() == "RAID_WARNING", "without fun mode the alert is unchanged")
local before = #soundsPlayed
PR.Dialog:Show({}, nil, nil, nil)
assert(#soundsPlayed == before, "a clean check must not play a warning at all")
print("warning sound ok")

print("SMOKE OK")
