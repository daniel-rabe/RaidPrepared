# RaidPrepared

**Show up to raid prepared – and make sure everyone else does too.**

RaidPrepared checks your gear the moment you join a raid group. Missing enchants, empty gem sockets, low-quality gems or no potions in your bags? A short dialog tells you exactly what's missing, before the pull timer does.

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

### 🛡️ Raid Gear Check
- For **raid leaders and assistants**
- Lists **every raid member** with their enchant and gem status
- Shows **low/mid quality enchants** with the item level of the slot
- Hover a player to see exactly which items are missing an enchant or gem
- **Refresh** button for each player, plus **Refresh All**
- Inspects players one at a time, pauses in combat, never interrupts your own inspect window

### 🔔 Unobtrusive
- Runs automatically when you join a raid – stays silent if everything is fine
- Never opens in combat
- Dismiss the dialog with one click (or ESC)

---

## 🎮 How to use

| | |
|---|---|
| **Join a raid** | Automatic check |
| `/rp` | Check your own gear and consumables |
| `/rp raid` | Open the raid gear check (lead/assist) |
| `/rp talents` | Flag talent loadouts |
| `/rp options` | Open the options tab |
| `/rp indicators` | Toggle character panel indicators |
| `/rp minimap` | Show/hide the minimap button |
| `/rp quality <rank>` | Set the required quality rank |
| **Minimap left-click** | Check your gear |
| **Minimap right-click** | Raid gear check (lead/assist) |
| **Minimap Shift-click** | Talent loadout flags |

Also available in the minimap **addon compartment** menu.

---

## ⚙️ Configuration

Advanced settings (enchantable slots, consumable item IDs, minimum counts, classes exempt from weapon oils, ...) can be adjusted in `Data.lua`.

## ⚠️ Notes
- The raid check can only inspect players within inspect range – use **Refresh** when they're nearby.

---

Found a bug or have a suggestion? Please open an issue and include the output of `/rp debug`.
