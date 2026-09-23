local _, PR = ...

-- Localization. Keys are the English text; a missing translation falls back to the
-- key itself, so an untranslated string shows up in English instead of as nil.
-- Translations live in Locales/<locale>.lua and only fill in the strings they know.
-- Keep every format specifier (%s, %d) of a key in the same order in the translation.
--
-- Every locale is loaded, not just the client's: whispers can be sent in a language
-- the sender does not play in (see the whisper language option).

PR.Locales = {}

-- Registers and returns the table a Locales/<locale>.lua file fills in.
function PR.NewLocale(locale)
    local t = {}
    PR.Locales[locale] = t
    return t
end

-- Locales that share a translation file.
local ALIASES = { esMX = "esES", enGB = "enUS" }

PR.CLIENT_LOCALE = ALIASES[GetLocale()] or GetLocale()

-- Languages offered for whispers, in menu order. enUS needs no table: its strings
-- are the keys themselves.
PR.WHISPER_LOCALES = {
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
function PR.GetString(key, locale)
    local t = PR.Locales[ALIASES[locale] or locale]
    return t and t[key] or key
end

-- The client's language, for everything shown to the player. Fun mode (see Fun.lua)
-- swaps a warning for its joke key first, so the joke text is translated like any
-- other string; PR.GetString itself stays untouched and keeps whispers serious.
PR.L = setmetatable({}, {
    __index = function(_, key)
        return PR.GetString(PR.Fun and PR.Fun:Key(key) or key, PR.CLIENT_LOCALE)
    end,
})

-- The magic characters of a Lua pattern, escaped with "%%%0".
local PATTERN_MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

-- Turns a localized format global into a Lua pattern that matches a whole line, with every
-- %s captured and every %d matched as digits. Only the literal parts of the format may be
-- escaped: an escaped placeholder would survive into the pattern, and some locales spell
-- their arguments out with a position ("%1$s (%2$d/%3$d)"), whose "%1" Lua reads as a
-- capture reference and rejects on the first match. fallback (English) stands in when the
-- global is missing or its format cannot be turned into a usable pattern.
function PR.LineFormatPattern(fmt, fallback)
    local function Build(f)
        f = f:gsub("%%%d+%$", "%%") -- "%1$s" -> "%s"; the argument order does not matter here
        local parts, pos = {}, 1
        while true do
            local from, to, spec = f:find("%%(.)", pos)
            if not from then break end
            parts[#parts + 1] = (f:sub(pos, from - 1):gsub(PATTERN_MAGIC, "%%%0"))
            if spec == "s" then
                parts[#parts + 1] = "(.+)"
            elseif spec == "d" then
                parts[#parts + 1] = "%d+"
            else -- "%%", or anything unexpected: a literal percent and the character itself
                parts[#parts + 1] = "%%" .. (spec ~= "%" and spec:gsub(PATTERN_MAGIC, "%%%0") or "")
            end
            pos = to + 1
        end
        parts[#parts + 1] = (f:sub(pos):gsub(PATTERN_MAGIC, "%%%0"))
        return "^" .. table.concat(parts) .. "$"
    end

    local pattern = Build(fmt or fallback)
    -- A pattern this addon cannot use is worse than no match at all, so try it once.
    if not pcall(string.match, "", pattern) then
        pattern = Build(fallback)
    end
    return pattern
end

-- Keys that are not English text themselves.
local enUS = PR.NewLocale("enUS")
enUS["cat.hearth"] = "Hearthstone"
enUS["cat.dungeon"] = "Dungeon"
enUS["cat.class"] = "Class"
enUS["cat.zone"] = "Zone"
enUS["cat.profession"] = "Profession"
enUS["cat.other"] = "Other"
