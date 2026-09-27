-- A small stub of the WoW client API, enough to load PullReady and drive the
-- dialog. Unknown METHODS deliberately blow up rather than returning a dummy, so
-- a real mistake is not silently swallowed; unknown FIELDS read as nil, as they
-- would in the client.

local M = {}

local function noop() end
local function ret(v) return function() return v end end

-- Frame / texture / fontstring methods. Anything the addon calls has to be here.
local methods = {}

local function each(list, fn)
    for _, name in ipairs(list) do methods[name] = fn end
end

-- Setters and other things whose return value nobody uses.
each({
    "SetPoint", "SetAllPoints", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight",
    "SetText", "SetTextColor", "SetJustifyH", "SetWordWrap", "SetFontObject",
    "SetTexture", "SetTexCoord", "SetColorTexture", "SetVertexColor", "SetDesaturated",
    "SetAlpha", "SetBlendMode", "SetAtlas", "SetDrawLayer",
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
    "SetFrameStrata", "SetFrameLevel", "SetToplevel", "SetClampedToScreen",
    "EnableMouse", "SetMovable", "RegisterForDrag", "RegisterForClicks",
    "StartMoving", "StopMovingOrSizing", "SetScrollChild", "SetScript",
    "RegisterEvent", "UnregisterEvent", "SetChecked", "SetEnabled", "Enable", "Disable",
    "SetupMenu", "SetDefaultText", "SetID", "SetScale", "SetHitRectInsets",
    "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetDisabledTexture",
    "SetAttribute", "SetMinMaxValues", "SetValue", "SetObeyStepOnDrag",
    "SetAutoFocus", "SetMaxLetters", "SetMultiLine", "HighlightText", "SetFocus",
    "ClearFocus", "SetCursorPosition", "Raise", "SetPropagateKeyboardInput",
    "SetResizeBounds", "SetUserPlaced", "SetDontSavePosition", "SetClipsChildren",
    "RegisterUnitEvent", "UnregisterAllEvents", "RegisterAllEvents",
    "SetPoint2", "SetFont", "SetShadowOffset", "SetShadowColor", "SetSpacing",
    "SetTextInsets", "SetNumeric", "SetPasswordMode", "Insert", "SetIndentedWordWrap",
    "SetHorizontalScroll", "SetVerticalScroll", "UpdateScrollChildRect",
    "SetMotionScriptsWhileDisabled", "SetFrameRef", "SetPassThroughButtons",
    "SetDrawEdge", "SetReverseFill", "SetStatusBarTexture", "SetStatusBarColor",
    "SetCheckedTexture", "SetDisabledCheckedTexture", "SetButtonState",
    "SetSelectionTranslator", "SetIsDefaultCallback", "SetDefaultCallback",
    "GenerateMenu", "SetMenuAnchor", "SetTooltip", "SetDesaturation",
    "SetParent", "SetToplevel2", "SetIgnoreParentScale", "SetIgnoreParentAlpha",
    "SetRotation", "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetMouseMotionEnabled",
    "SetMouseClickEnabled", "SetGradient", "SetNonBlocking", "SetSequence",
    "SetGradient", "SetGradientAlpha",
    "SetNormalFontObject", "SetHighlightFontObject", "SetDisabledFontObject",
    "SetFontString", "SetFormattedText", "SetJustifyV", "SetMaxLines",
    "SetTextToFit", "SetWrap", "SetAlphaGradient", "SetBackdropOption",
}, noop)

methods.Show = function(self) self._shown = true end
methods.Hide = function(self) self._shown = false end
methods.SetShown = function(self, shown) self._shown = shown and true or false end
methods.IsShown = function(self) return self._shown ~= false end
methods.IsVisible = methods.IsShown
methods.GetID = function(self) return self._id or 0 end
methods.GetName = function(self) return self._frameName end
methods.GetWidth = function(self) return self._width or 580 end
methods.GetHeight = function(self) return self._height or 390 end
methods.GetStringWidth = function(self) return #tostring(self._text or "") * 6 end
methods.GetChecked = ret(false)
methods.GetText = function(self) return self._text end
methods.GetParent = function(self) return self._parent end
methods.GetObjectType = ret("Frame")
methods.GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end
methods.GetNumPoints = ret(0)
methods.IsEnabled = ret(true)
methods.IsMouseOver = ret(false)
methods.GetScrollChild = function(self) return self._scrollChild end
methods.GetValue = ret(0)
methods.GetNumber = ret(0)
methods.GetFontObject = ret(nil)
methods.GetFont = function() return "Fonts/FRIZQT__.TTF", 12, "" end
methods.GetRegions = function() return end
methods.GetChildren = function() return end
methods.GetTop = ret(100)
methods.GetBottom = ret(0)
methods.GetLeft = ret(0)
methods.GetRight = ret(100)
methods.GetCenter = function() return 50, 50 end
methods.GetEffectiveScale = ret(1)

-- The few that have to remember what they were given.
methods.HookScript = function(self, name, fn)
    self._scripts = self._scripts or {}
    local previous = self._scripts[name]
    self._scripts[name] = function(...)
        if previous then previous(...) end
        return fn(...)
    end
end
methods.GetScript = function(self, name)
    return self._scripts and self._scripts[name]
end

local recording = {
    SetText = function(self, text) self._text = text end,
    SetWidth = function(self, w) self._width = w end,
    SetHeight = function(self, h) self._height = h end,
    SetSize = function(self, w, h) self._width, self._height = w, h end,
    SetID = function(self, id) self._id = id end,
    SetScript = function(self, name, fn) self._scripts = self._scripts or {}; self._scripts[name] = fn end,
}
for name, fn in pairs(recording) do methods[name] = fn end

local widgetMeta
local function newWidget(kind, frameName, parent)
    local w = {
        _kind = kind, _frameName = frameName, _parent = parent,
        _shown = kind ~= "Texture" and kind ~= "FontString",
    }
    return setmetatable(w, widgetMeta)
end

methods.GetFontString = function(self)
    self._fontString = self._fontString or newWidget("FontString", nil, self)
    return self._fontString
end
methods.GetNormalTexture = function(self)
    self._normalTexture = self._normalTexture or newWidget("Texture", nil, self)
    return self._normalTexture
end
methods.GetHighlightTexture = methods.GetNormalTexture
methods.GetPushedTexture = methods.GetNormalTexture
methods.GetCheckedTexture = methods.GetNormalTexture

methods.CreateTexture = function(self) return newWidget("Texture", nil, self) end
methods.CreateFontString = function(self) return newWidget("FontString", nil, self) end
methods.CreateLine = function(self) return newWidget("Line", nil, self) end

widgetMeta = {
    __index = function(t, key)
        local method = methods[key]
        if method then return method end
        -- Not a known method: treat it as an ordinary (absent) field, which is
        -- what the addon's own `tab.isDisabled` style lookups expect.
        return nil
    end,
}

M.methods = methods
M.newWidget = newWidget
return M
