local _, PR = ...
local L = PR.L

local MAX_GEMS = 4

local QUALITY_ATLAS_PATTERN = "Professions%-ChatIcon%-Quality%-.-Tier(%d)"
local QUALITY_ICON_PATTERN  = "Professions%-Icon%-Quality%-.-Tier(%d)"

-- "Enchanted: %s" -> "^Enchanted: (.+)$" (localized)
local ENCHANT_LINE_PATTERN = PR.LineFormatPattern(ENCHANTED_TOOLTIP_LINE, "Enchanted: %s")

local function GetMaxQualityTier()
    return PR.GetMaxQualityTier()
end

local function GetEnchantID(link)
    local enchant = link:match("item:%-?%d+:(%-?%d*)")
    return tonumber(enchant) or 0
end

local function GetQualityTierFromText(text)
    if not text then return nil end
    local tier = text:match(QUALITY_ATLAS_PATTERN) or text:match(QUALITY_ICON_PATTERN)
    return tonumber(tier)
end

local function IsEnchantableSlot(slot, link)
    if not PR.ENCHANT_SLOTS[slot] then
        return false
    end
    if slot == INVSLOT_OFFHAND then
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
        return PR.ENCHANTABLE_OFFHAND[equipLoc] == true
    end
    return true
end

-- Returns the enchant tooltip line text (e.g. "Enchanted: Foo |A:...Tier2|a") or nil.
local function GetEnchantTooltipText(unit, slot)
    local data = C_TooltipInfo and C_TooltipInfo.GetInventoryItem(unit, slot)
    if not data or not data.lines then return nil end

    local enchantType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text and ((enchantType and line.type == enchantType) or text:match(ENCHANT_LINE_PATTERN)) then
            return text
        end
    end
    return nil
end

local function GetNumSockets(link)
    if C_Item.GetItemNumSockets then
        local num = C_Item.GetItemNumSockets(link)
        if num then return num end
    end

    local count = 0
    local stats = C_Item.GetItemStats(link)
    if stats then
        for key, value in pairs(stats) do
            if key:find("^EMPTY_SOCKET_") then
                count = count + value
            end
        end
    end
    return count
end

-- Numeric fields of the item string: itemID:enchantID:gem1:gem2:gem3:gem4:...
local function GetLinkFields(link)
    local itemString = link:match("item:([%-%d:]*)")
    local fields = {}
    if itemString then
        for field in (itemString .. ":"):gmatch("([^:]*):") do
            fields[#fields + 1] = tonumber(field) or 0
        end
    end
    return fields
end

-- Gem item IDs socketed into the item, read directly from the link (works without gem cache).
local function GetGemIDs(link)
    local fields = GetLinkFields(link)
    local gems = {}
    for i = 3, 2 + MAX_GEMS do
        local gemID = fields[i]
        if gemID and gemID > 0 then
            gems[#gems + 1] = gemID
        end
    end
    return gems
end

-- Socket info from tooltip data: total socket lines and how many hold a gem.
local function GetTooltipSocketInfo(unit, slot)
    local lineType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.GemSocket
    local data = lineType and C_TooltipInfo and C_TooltipInfo.GetInventoryItem(unit, slot)
    if not data or not data.lines then return 0, 0 end

    local sockets, filled = 0, 0
    for _, line in ipairs(data.lines) do
        if line.type == lineType then
            sockets = sockets + 1
            if line.gemIcon or line.gemID then
                filled = filled + 1
            end
        end
    end
    return sockets, filled
end

local function AddIssue(issues, slot, link, kind, problem, detail)
    issues[#issues + 1] = {
        slot = slot,
        slotName = PR.SLOT_NAMES[slot] or tostring(slot),
        itemLink = link,
        kind = kind,          -- "enchant" | "gem"
        problem = problem,    -- "missing" | "low" | "outdated"
        detail = detail,
    }
end

local function CheckEnchant(issues, unit, slot, link, checkQuality)
    if not IsEnchantableSlot(slot, link) then return end

    local enchantID = GetEnchantID(link)
    if enchantID == 0 then
        AddIssue(issues, slot, link, "enchant", "missing", L["Missing enchant"])
        return
    end
    if not checkQuality then return end

    local maxTier = GetMaxQualityTier()
    local text = GetEnchantTooltipText(unit, slot)
    local tier = GetQualityTierFromText(text)
    local name = text and text:match(ENCHANT_LINE_PATTERN)
    if name then
        name = name:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        name = strtrim(name)
    end

    if tier and tier < maxTier then
        AddIssue(issues, slot, link, "enchant", "low",
            L["Low quality enchant (rank %d/%d)%s"]:format(tier, maxTier, name and (": " .. name) or ""))
        local issue = issues[#issues]
        issue.tier, issue.maxTier = tier, maxTier
        issue.itemLevel = C_Item.GetDetailedItemLevelInfo(link)
    end

    if checkQuality ~= true then return end -- "enchant": enchant quality only

    if next(PR.KNOWN_CURRENT_ENCHANTS) and not PR.KNOWN_CURRENT_ENCHANTS[enchantID] then
        AddIssue(issues, slot, link, "enchant", "outdated",
            L["Outdated enchant%s"]:format(name and (": " .. name) or (" (ID " .. enchantID .. ")")))
    end
end

local function GetGemDisplay(gemID)
    local _, gemLink = C_Item.GetItemInfo(gemID)
    return gemLink or L["item %d"]:format(gemID)
end

local function CheckGems(issues, unit, slot, link, checkQuality)
    local gems = GetGemIDs(link)
    local tooltipSockets, tooltipFilled = GetTooltipSocketInfo(unit, slot)
    local numSockets = math.max(GetNumSockets(link), tooltipSockets)
    local filled = math.max(#gems, tooltipFilled)

    local empty = numSockets - filled
    if empty > 0 then
        AddIssue(issues, slot, link, "gem", "missing",
            empty == 1 and L["Empty gem socket"] or L["%d empty gem sockets"]:format(empty))
        issues[#issues].empty = empty
    end

    if checkQuality ~= true then return end

    local maxTier = GetMaxQualityTier()
    for _, gemID in ipairs(gems) do
        local tier
        if C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
            tier = C_TradeSkillUI.GetItemReagentQualityByItemInfo(gemID)
        end
        if tier and tier > 0 and tier < maxTier then
            AddIssue(issues, slot, link, "gem", "low",
                L["Low quality gem (rank %d/%d): %s"]:format(tier, maxTier, GetGemDisplay(gemID)))
        end

        local expacID = select(15, C_Item.GetItemInfo(gemID))
        if expacID and PR.MIN_GEM_EXPANSION and expacID < PR.MIN_GEM_EXPANSION then
            AddIssue(issues, slot, link, "gem", "outdated", L["Outdated gem: %s"]:format(GetGemDisplay(gemID)))
        end
    end
end

local EPIC_GEM_SLOT = 99 -- sort position of the epic gem issue (after gear slots)

-- Reports a missing epic gem when the unit has sockets but none holds one of PR.EPIC_GEM_IDS.
local function CheckEpicGem(issues, unit)
    if not next(PR.EPIC_GEM_IDS) then return end

    local sockets = 0
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            for _, gemID in ipairs(GetGemIDs(link)) do
                if PR.EPIC_GEM_IDS[gemID] then return end
            end
            sockets = sockets + math.max(GetNumSockets(link), (GetTooltipSocketInfo(unit, slot)))
        end
    end
    if sockets == 0 then return end

    issues[#issues + 1] = {
        slot = EPIC_GEM_SLOT,
        slotName = L["Epic Gem"],
        icon = C_Item.GetItemIconByID(PR.EPIC_GEM_ICON_ID),
        kind = "epicgem",
        problem = "missing",
        detail = L["No Eversong Diamond socketed"],
    }
end

-- Synchronous scan of a unit ("player" or an inspected unit). Item data should be cached
-- (see PR.ScanUnitAsync). checkQuality: true = also report low-quality/outdated enchants and gems,
-- "enchant" = also report low-quality enchants only, false = missing enchants/gems only.
function PR.ScanUnit(unit, checkQuality)
    local issues = {}
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        if slot ~= INVSLOT_BODY and slot ~= INVSLOT_TABARD then
            local link = GetInventoryItemLink(unit, slot)
            if link then
                CheckEnchant(issues, unit, slot, link, checkQuality)
                CheckGems(issues, unit, slot, link, checkQuality)
            end
        end
    end
    CheckEpicGem(issues, unit)
    table.sort(issues, function(a, b)
        if a.slot ~= b.slot then return a.slot < b.slot end
        return a.kind < b.kind
    end)
    return issues
end

function PR.Scan()
    return PR.ScanUnit("player", true)
end

-- Returns true if every equipped item of the unit has a link (inspect data complete).
function PR.HasAllItemLinks(unit)
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        if GetInventoryItemID(unit, slot) and not GetInventoryItemLink(unit, slot) then
            return false
        end
    end
    return true
end

-- Loads all equipped items of the unit and their gems into the cache, then scans.
function PR.ScanUnitAsync(unit, checkQuality, callback)
    local items = ContinuableContainer:Create()
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local itemID = GetInventoryItemID(unit, slot)
        if itemID then
            items:AddContinuable(Item:CreateFromItemID(itemID))
        end
    end

    items:ContinueOnLoad(function()
        local gems = ContinuableContainer:Create()
        for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
            local link = GetInventoryItemLink(unit, slot)
            if link then
                for _, gemID in ipairs(GetGemIDs(link)) do
                    gems:AddContinuable(Item:CreateFromItemID(gemID))
                end
            end
        end
        gems:ContinueOnLoad(function()
            callback(PR.ScanUnit(unit, checkQuality))
        end)
    end)
end

function PR.ScanAsync(callback)
    PR.ScanUnitAsync("player", true, callback)
end

-- /pr debug: dump what the scanner sees for every equipped item.
function PR.Debug()
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local tooltipSockets, tooltipFilled = GetTooltipSocketInfo("player", slot)
            print(("[%d] %s %s"):format(slot, link, link:gsub("|", "||")))
            print(("    enchant=%d gems={%s} numSockets=%d tooltipSockets=%d tooltipFilled=%d"):format(
                GetEnchantID(link), table.concat(GetGemIDs(link), ","),
                GetNumSockets(link), tooltipSockets, tooltipFilled))
        end
    end
end
