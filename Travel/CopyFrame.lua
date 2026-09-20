-- PullReady - Travel/CopyFrame.lua
-- A scrollable text box for diagnostic output, because WoW chat cannot be
-- copied. Text arrives pre-selected so Ctrl+C works immediately.

local _, PR = ...
local T = PR.Travel
local L = PR.L

T.UI = T.UI or {}
local UI = T.UI

local copyFrame, copyBox, copyTitle

local FRAME_WIDTH  = 560
local FRAME_HEIGHT = 420

local function CreateCopyFrame()
    copyFrame = CreateFrame("Frame", "PullReadyTravelCopyFrame", UIParent, "BackdropTemplate")
    copyFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    copyFrame:SetPoint("CENTER")
    copyFrame:SetFrameStrata("DIALOG")
    copyFrame:SetClampedToScreen(true)
    copyFrame:SetMovable(true)
    copyFrame:EnableMouse(true)
    copyFrame:RegisterForDrag("LeftButton")
    copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
    copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
    copyFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    copyFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    copyFrame:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    copyFrame:Hide()

    tinsert(UISpecialFrames, "PullReadyTravelCopyFrame")

    copyTitle = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    copyTitle:SetPoint("TOPLEFT", 12, -10)

    local close = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScale(0.85)

    local hint = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 10)
    hint:SetText(L["Ctrl+C to copy, Esc to close"])

    local scroll = CreateFrame("ScrollFrame", "PullReadyTravelCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 28)

    copyBox = CreateFrame("EditBox", nil, scroll)
    copyBox:SetMultiLine(true)
    copyBox:SetAutoFocus(false)
    copyBox:SetFontObject("ChatFontNormal")
    copyBox:SetWidth(FRAME_WIDTH - 56)
    copyBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    scroll:SetScrollChild(copyBox)

    copyFrame:SetScript("OnHide", function() copyBox:SetText("") end)
end

---Show text in the copy window, pre-selected and ready for Ctrl+C.
---@param title string
---@param text string
function UI.ShowCopy(title, text)
    if not copyFrame then
        CreateCopyFrame()
    end
    copyTitle:SetText(L["PullReady travel - %s"]:format(title or L["Output"]))
    copyBox:SetText(text or "")
    copyFrame:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
    copyBox:SetCursorPosition(0)
end
