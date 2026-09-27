local addonName, PR = ...
local L = PR.L

-- Look of the main window, switchable in the options tab.
--
-- Two palettes: "default" keeps the Blizzard dialog art the addon has always used,
-- "darkgold" is the dark panel with gold filigree from the design mockup. Only the
-- colours and the textures differ - the layout is the same either way, so there is
-- one window to maintain rather than two.
--
-- Widgets do not read the palette directly. They hand a skin function to
-- Theme:Register at creation, which applies it once immediately and again whenever
-- the palette changes, so switching themes takes effect without a /reload. This is
-- the same shape as fun mode in Fun.lua, which re-applies itself the same way.

local Theme = {}
PR.Theme = Theme

-- Built from the folder name so a renamed addon folder still finds its art.
local TEXTURES = ("Interface\\AddOns\\%s\\Textures\\"):format(addonName)

Theme.CORNER    = TEXTURES .. "corner-ornament"
Theme.FLOURISH  = TEXTURES .. "header-flourish"
Theme.RING      = TEXTURES .. "check-ring"
Theme.TAB_ON    = TEXTURES .. "tab-active"
Theme.TAB_OFF   = TEXTURES .. "tab-inactive"

-- Tab glyphs. White silhouettes, tinted per palette where they are drawn, so one
-- set covers both themes.
Theme.ICONS = {
    check    = TEXTURES .. "icon-check",
    group    = TEXTURES .. "icon-group",
    talents  = TEXTURES .. "icon-talents",
    travel   = TEXTURES .. "icon-travel",
    shopping = TEXTURES .. "icon-shopping",
    options  = TEXTURES .. "icon-options",
}

local BLIZZARD_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 8, top = 12, bottom = 11 },
}

local FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Order of the dropdown in the options tab.
Theme.ORDER = { "default", "darkgold" }

Theme.PALETTES = {
    -- What the window looked like before the theme option existed.
    default = {
        label = "Default",
        backdrop = BLIZZARD_BACKDROP,
        backdropColor = nil, -- nil = leave the Blizzard art at its own tint
        borderColor = nil,
        ornaments = false,   -- no filigree, no vignette
        title       = { 1.00, 0.82, 0.00 },
        subtitle    = { 0.75, 0.75, 0.75 },
        tabTint     = { 0.62, 0.62, 0.66 },
        tabTintOn   = { 0.95, 0.95, 0.98 },
        tabText     = { 0.75, 0.75, 0.75 },
        tabTextOn   = { 0.14, 0.11, 0.07 }, -- dark: it sits on the lit plate
        tabTextOff  = { 0.45, 0.45, 0.45 },
        ring        = { 0.55, 0.57, 0.62 },
        rowHighlight = { 1, 1, 1, 0.08 },
        status = {
            ok       = { 0.25, 1.00, 0.25 },
            warn     = { 1.00, 0.60, 0.10 },
            bad      = { 1.00, 0.25, 0.25 },
            inactive = { 0.65, 0.65, 0.65 },
        },
    },

    -- Mockup variant 2: near-black panel, warm gold everywhere else.
    darkgold = {
        label = "Dark & Gold",
        backdrop = FLAT_BACKDROP,
        backdropColor = { 0.04, 0.035, 0.03, 0.96 },
        borderColor   = { 0.72, 0.56, 0.24, 1.00 },
        ornaments = true,
        ornamentColor = { 1.00, 0.86, 0.55, 0.85 },
        glowColor     = { 0.85, 0.64, 0.26, 0.12 },
        title       = { 1.00, 0.84, 0.42 },
        subtitle    = { 0.78, 0.70, 0.55 },
        tabTint     = { 1.00, 1.00, 1.00 },
        tabTintOn   = { 1.00, 1.00, 1.00 },
        tabText     = { 0.80, 0.72, 0.56 },
        tabTextOn   = { 0.16, 0.10, 0.02 }, -- dark: it sits on the gold plate
        tabTextOff  = { 0.42, 0.38, 0.32 },
        ring        = { 1.00, 0.86, 0.55 },
        rowHighlight = { 1.00, 0.82, 0.40, 0.10 },
        -- Warmed towards the gold so the status ramp sits inside the scheme
        -- instead of fighting it, while staying red/amber/green at a glance.
        status = {
            ok       = { 0.45, 0.95, 0.50 },
            warn     = { 1.00, 0.72, 0.22 },
            bad      = { 1.00, 0.34, 0.30 },
            inactive = { 0.56, 0.51, 0.43 },
        },
    },
}

local registry = {}

function Theme:Name()
    local name = PullReadyDB and PullReadyDB.theme
    return self.PALETTES[name] and name or "default"
end

function Theme:Current()
    return self.PALETTES[self:Name()]
end

-- The palette entry for a status, as r, g, b. Every check in the addon colours
-- itself through here, so a palette only has to name four colours.
function Theme:Status(key)
    return unpack(self:Current().status[key] or self:Current().status.inactive)
end

-- Registers a skin function and runs it once. The function is called again with
-- the new palette every time the theme changes.
function Theme:Register(skin)
    registry[#registry + 1] = skin
    skin(self:Current())
end

function Theme:Apply()
    local palette = self:Current()
    for _, skin in ipairs(registry) do
        skin(palette)
    end
end

function Theme:Set(name)
    if not self.PALETTES[name] then return end
    PullReadyDB.theme = name
    self:Apply()
    PR.CharacterPanel:RequestUpdate()
end

-- Localized name for the dropdown. The English label is the translation key, as
-- everywhere else in the addon.
function Theme:Label(name)
    local palette = self.PALETTES[name]
    return palette and L[palette.label] or name
end

-- Applies a palette's panel art to the main window. A palette that names no
-- colours leaves the Blizzard art at its own tint, which is what "default" wants.
function Theme:SkinBackdrop(frame, palette)
    frame:SetBackdrop(palette.backdrop)
    if palette.backdropColor then
        frame:SetBackdropColor(unpack(palette.backdropColor))
    else
        frame:SetBackdropColor(1, 1, 1, 1)
    end
    if palette.borderColor then
        frame:SetBackdropBorderColor(unpack(palette.borderColor))
    else
        frame:SetBackdropBorderColor(1, 1, 1, 1)
    end
end
