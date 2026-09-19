-- RaidPrepared - Travel/Data.lua
-- Curated travel options. Every entry is a CANDIDATE: Modules/Collector.lua
-- filters this list down to what your character actually owns and knows, so an
-- entry you do not have simply never appears.
--
-- Verify the list on your own account with:
--   /rp travel audit   - reports entries whose name will not resolve (bad ID)
--   /rp travel scan    - dumps your spellbook so real IDs can be harvested
--
-- kind: "spell" | "toy" | "item"
--   For anything that is not a spell this is only a HINT. Blizzard converts
--   items into toys over time (the Garrison and Dalaran hearthstones are toys
--   now), so Collector.ResolveKind checks the toy box and then bags, and uses
--   whichever form you actually own.
-- cat : "hearth" | "dungeon" | "class" | "zone" | "profession" | "other"
-- keywords: extra English search terms, always lowercase

local _, RP = ...
local T = RP.Travel

T.Data = T.Data or {}
local entries = {}
T.Data.entries = entries

---Append a travel candidate.
local function add(kind, id, cat, keywords)
    entries[#entries + 1] = {
        kind = kind,
        id = id,
        cat = cat or "other",
        keywords = keywords,
    }
end
T.Data.Add = add

-- ---------------------------------------------------------------------------
-- Hearthstones (bag items)
-- ---------------------------------------------------------------------------
add("item", 6948,   "hearth", { "hearthstone", "hs", "home", "inn" })
add("item", 110560, "hearth", { "garrison", "hearthstone", "ghs", "draenor" })
add("item", 140192, "hearth", { "dalaran", "hearthstone", "dhs", "legion" })
add("item", 141605, "other",  { "flight", "master", "whistle", "fmw" })

-- ---------------------------------------------------------------------------
-- Hearthstone toys
-- ---------------------------------------------------------------------------
add("toy", 64488,  "hearth", { "innkeeper", "daughter", "hearthstone" })
add("toy", 54452,  "hearth", { "ethereal", "portal" })
add("toy", 162973, "hearth", { "greatfather", "winter", "hearthstone", "winterveil" })
add("toy", 163045, "hearth", { "headless", "horseman", "hearthstone", "hallow" })
add("toy", 165669, "hearth", { "lunar", "elder", "hearthstone", "festival" })
add("toy", 165670, "hearth", { "peddlefeet", "lovely", "hearthstone", "love" })
add("toy", 165802, "hearth", { "noble", "gardener", "hearthstone", "noblegarden" })
add("toy", 166746, "hearth", { "fire", "eater", "hearthstone", "midsummer" })
add("toy", 166747, "hearth", { "brewfest", "reveler", "hearthstone" })
add("toy", 168907, "hearth", { "holographic", "digitalization", "hearthstone" })
add("toy", 172179, "hearth", { "eternal", "traveler", "hearthstone" })
add("toy", 180290, "hearth", { "night", "fae", "hearthstone", "covenant" })
add("toy", 182773, "hearth", { "necrolord", "hearthstone", "covenant" })
add("toy", 183716, "hearth", { "venthyr", "sinstone", "hearthstone", "covenant" })
add("toy", 184353, "hearth", { "kyrian", "hearthstone", "covenant" })
add("toy", 188952, "hearth", { "dominated", "hearthstone" })
add("toy", 190237, "hearth", { "broker", "translocation", "matrix" })
add("toy", 193588, "hearth", { "timewalker", "hearthstone" })
add("toy", 200630, "hearth", { "ohnir", "windsage", "hearthstone" })
add("toy", 206195, "hearth", { "path", "naaru", "hearthstone" })
add("toy", 209035, "hearth", { "hearthstone", "flame" })
add("toy", 212337, "hearth", { "stone", "hearth", "hearthstone" })

-- ---------------------------------------------------------------------------
-- Class travel spells
-- ---------------------------------------------------------------------------
add("spell", 556,    "class", { "astral", "recall", "shaman" })
add("spell", 50977,  "class", { "death", "gate", "acherus", "dk" })
add("spell", 18960,  "class", { "teleport", "moonglade", "druid" })
add("spell", 193753, "class", { "dreamwalk", "druid", "dreamgrove" })
add("spell", 126892, "class", { "zen", "pilgrimage", "monk" })

-- Mage teleports (self). Portals are group-facing and intentionally excluded.
add("spell", 3561,   "class", { "teleport", "stormwind", "mage", "alliance" })
add("spell", 3562,   "class", { "teleport", "ironforge", "mage", "alliance" })
add("spell", 3565,   "class", { "teleport", "darnassus", "mage", "alliance" })
add("spell", 32271,  "class", { "teleport", "exodar", "mage", "alliance" })
add("spell", 3567,   "class", { "teleport", "orgrimmar", "mage", "horde" })
add("spell", 3563,   "class", { "teleport", "undercity", "mage", "horde" })
add("spell", 3566,   "class", { "teleport", "thunder", "bluff", "mage", "horde" })
add("spell", 32272,  "class", { "teleport", "silvermoon", "mage", "horde" })
add("spell", 49359,  "class", { "teleport", "theramore", "mage", "alliance" })
add("spell", 120145, "class", { "ancient", "teleport", "dalaran", "mage" })
add("spell", 1259190, "class", { "teleport", "silvermoon", "city", "mage" })
add("spell", 33690,  "class", { "teleport", "shattrath", "mage", "alliance" })
add("spell", 35715,  "class", { "teleport", "shattrath", "mage", "horde" })
add("spell", 53140,  "class", { "teleport", "dalaran", "northrend", "mage" })
add("spell", 88342,  "class", { "teleport", "tol", "barad", "mage", "alliance" })
add("spell", 88344,  "class", { "teleport", "tol", "barad", "mage", "horde" })
add("spell", 132621, "class", { "teleport", "vale", "eternal", "blossoms", "mage", "alliance" })
add("spell", 132627, "class", { "teleport", "vale", "eternal", "blossoms", "mage", "horde" })
add("spell", 176248, "class", { "teleport", "stormshield", "mage", "alliance" })
add("spell", 176242, "class", { "teleport", "warspear", "mage", "horde" })
add("spell", 193759, "class", { "teleport", "hall", "guardian", "mage" })
add("spell", 224869, "class", { "teleport", "dalaran", "broken", "isles", "mage" })
add("spell", 281403, "class", { "teleport", "boralus", "mage", "alliance" })
add("spell", 281404, "class", { "teleport", "dazaralor", "mage", "horde" })
add("spell", 344587, "class", { "teleport", "oribos", "mage", "shadowlands" })
add("spell", 395277, "class", { "teleport", "valdrakken", "mage", "dragonflight" })
add("spell", 446540, "class", { "teleport", "dornogal", "mage", "war", "within" })

-- ---------------------------------------------------------------------------
-- Profession / engineering
-- ---------------------------------------------------------------------------
add("toy", 168807, "profession", { "wormhole", "generator", "zandalar", "engineering" })
add("toy", 168808, "profession", { "wormhole", "generator", "kul", "tiras", "engineering" })
add("toy", 172924, "profession", { "wormhole", "generator", "shadowlands", "engineering" })
add("toy", 198156, "profession", { "wyrmhole", "generator", "dragon", "isles", "engineering" })
