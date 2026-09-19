# FCKAFD

**F**ull **C**haracter **K**it **A**udit **F**or **D**ungeons

**Show up to raid prepared – and make sure everyone else does too.**

FCKAFD checks your gear the moment you join a raid group. Missing enchants, empty gem sockets, low-quality gems or no potions in your bags? A short dialog tells you exactly what's missing, before the pull timer does.

---

## ✨ Features

### 💎 Enchants & Gems
- Detects **missing enchants** on head, shoulders, chest, legs, feet, rings and weapons
- Finds **empty gem sockets**
- Warns if no **Eversong Diamond** (Indecipherable, Powerful, Stoic or Telluric) is socketed
- Flags **low-quality** enchants and gems below the highest crafting rank
- Flags **outdated gems** from previous expansions
- Optional **indicators on your character panel** show exactly which items lack an enchant or gem

### 🧪 Consumables
- Counts your **Silvermoon Health Potions** and **Concentrated Silvermoon Health Potions**
- Counts your **Lightfused Mana Potions** (only required for healers)
- Counts **weapon buffs** (Thalassian Phoenix Oil, Oil of Dawn, Smuggler's Enchanted Edge, Refulgent Whetstone & Weightstone, hunter ammo) and shows the remaining time of your active weapon buff
- Warns you when you have none left
- Works with **every client language** (items are matched by ID, all quality ranks)

### 📜 Talent Loadouts
- Flag your loadouts as **Raid** or **Dungeon** (Talents tab of the addon window or checkboxes in the talent frame)
- Warns when you enter a raid or Mythic/Mythic+ dungeon – or on a ready check – with the wrong loadout
- No flags for a content type, no warning

### 🧭 Travel
- One search box for every **fast-travel option** this character can actually use
- **Mythic+ dungeon teleports**, hearthstone toys, class travel spells, engineering wormholes
- Dungeon ports are searchable by **destination** – "Path of the Warding Candles" is found by typing *Darkflame Cleft*
- **M+** filters to the current season's dungeon ports
- Favourites and recently used options sort to the top

### 🛡️ Raid / Party Inspect
- **Raid Inspect** for raid leaders and assistants, **Party Inspect** for everyone in a party
- Lists **every raid member** with their enchant and gem status
- Shows **low/mid quality enchants** with the item level of the slot
- Hover a player to see exactly which items are missing an enchant or gem
- **Refresh** button for each player, plus **Refresh All**
- **Whisper** button for each player: sends a short, friendly heads-up listing what's missing (hover it to preview the text)
- Inspects players one at a time, pauses in combat, never interrupts your own inspect window

### 🔔 Unobtrusive
- Runs automatically when you join a raid – stays silent if everything is fine
- Never opens in combat
- Close the window with the X button or ESC

### 🌍 Languages
- Available in English, Deutsch, Français, Español, Italiano, Português (BR), Русский, 한국어, 简体中文 and 繁體中文

---

## 🎮 How to use

| | |
|---|---|
| **Join a raid** | Automatic check |
| `/fck` | Check your own gear and consumables |
| `/fck inspect` | Raid/Party Inspect |
| `/fck talents` | Flag talent loadouts |
| `/fck travel` | Search your fast-travel options |
| `/fck travel season` | This season's M+ maps and their ports |
| `/fck options` | Open the options tab |
| `/fck indicators` | Toggle character panel indicators |
| `/fck minimap` | Show/hide the minimap button |
| `/fck quality <rank>` | Set the required quality rank |
| **Minimap left-click** | Check your gear |
| **Minimap right-click** | Raid/Party Inspect |
| **Minimap Shift-click** | Talent loadout flags |
| **Minimap Ctrl-click** | Travel search |

Also available in the minimap **addon compartment** menu.

---

## ⚙️ Configuration

Advanced settings (enchantable slots, consumable item IDs, minimum counts, classes exempt from weapon oils, ...) can be adjusted in `Data.lua`.

## ⚠️ Notes
- The raid check can only inspect players within inspect range – use **Refresh** when they're nearby.
- **Renamed from RaidPrepared in 1.5.0.** Log in once with both folders installed and your settings are carried over, then delete the old `RaidPrepared` folder. `/rp` and `/raidprepared` still work as aliases.

---

Found a bug or have a suggestion? Please open an issue and include the output of `/fck debug`.
