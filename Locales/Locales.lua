local _, RP = ...

-- Localization. Keys are the English text; a missing translation falls back to the
-- key itself, so an untranslated string shows up in English instead of as nil.
-- Translations live in Locales/<locale>.lua and only fill in the strings they know.
-- Keep every format specifier (%s, %d) of a key in the same order in the translation.
--
-- Every locale is loaded, not just the client's: whispers can be sent in a language
-- the sender does not play in (see the whisper language option).

RP.Locales = {}

-- Registers and returns the table a Locales/<locale>.lua file fills in.
function RP.NewLocale(locale)
    local t = {}
    RP.Locales[locale] = t
    return t
end

-- Locales that share a translation file.
local ALIASES = { esMX = "esES", enGB = "enUS" }

RP.CLIENT_LOCALE = ALIASES[GetLocale()] or GetLocale()

-- Languages offered for whispers, in menu order. enUS needs no table: its strings
-- are the keys themselves.
RP.WHISPER_LOCALES = {
    { locale = "enUS", name = "English" },
    { locale = "deDE", name = "Deutsch" },
    { locale = "esES", name = "Español" },
    { locale = "frFR", name = "Français" },
    { locale = "itIT", name = "Italiano" },
    { locale = "ptBR", name = "Português (BR)" },
    { locale = "ruRU", name = "Русский" },
    { locale = "koKR", name = "한국어" },
    { locale = "zhCN", name = "简体中文" },
    { locale = "zhTW", name = "繁體中文" },
}

-- Translates into any loaded locale; falls back to the key (English).
function RP.GetString(key, locale)
    local t = RP.Locales[ALIASES[locale] or locale]
    return t and t[key] or key
end

-- The client's language, for everything shown to the player.
RP.L = setmetatable({}, {
    __index = function(_, key) return RP.GetString(key, RP.CLIENT_LOCALE) end,
})

-- Keys that are not English text themselves.
local enUS = RP.NewLocale("enUS")
enUS["cat.hearth"] = "Hearthstone"
enUS["cat.dungeon"] = "Dungeon"
enUS["cat.class"] = "Class"
enUS["cat.zone"] = "Zone"
enUS["cat.profession"] = "Profession"
enUS["cat.other"] = "Other"
