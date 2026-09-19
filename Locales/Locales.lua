local _, RP = ...

-- Localization. Keys are the English text; a missing translation falls back to the
-- key itself, so an untranslated string shows up in English instead of as nil.
-- Translations live in Locales/<locale>.lua and only fill in the strings they know.
-- Keep every format specifier (%s, %d) of a key in the same order in the translation.

RP.L = setmetatable({}, { __index = function(_, key) return key end })
local L = RP.L

-- Keys that are not English text themselves.
L["cat.hearth"] = "Hearthstone"
L["cat.dungeon"] = "Dungeon"
L["cat.class"] = "Class"
L["cat.zone"] = "Zone"
L["cat.profession"] = "Profession"
L["cat.other"] = "Other"
