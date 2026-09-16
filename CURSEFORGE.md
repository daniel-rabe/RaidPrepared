# RaidPrepared

**Show up to raid prepared – and make sure everyone else does too.**

RaidPrepared checks your gear the moment you join a raid group. Missing enchants, empty gem sockets, low-quality gems or no potions in your bags? A short dialog tells you exactly what's missing, before the pull timer does.

---

## ✨ Features

### 💎 Enchants & Gems
- Detects **missing enchants** on head, shoulders, chest, legs, feet, rings and weapons
- Finds **empty gem sockets**
- Flags **low-quality** enchants and gems below the highest crafting rank
- Flags **outdated gems** from previous expansions

### 🧪 Consumables
- Counts your **Silvermoon Health Potions** and **Concentrated Silvermoon Health Potions**
- Counts your **Lightfused Mana Potions** (only required for healers)
- Counts **weapon oils and stones** and shows the remaining time of your active weapon buff
- Warns you when you have none left

### 🛡️ Raid Gear Check
- For **raid leaders and assistants**
- Lists **every raid member** with their enchant and gem status
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
| `/rp minimap` | Show/hide the minimap button |
| `/rp quality <rank>` | Set the required quality rank |
| **Minimap left-click** | Check your gear |
| **Minimap right-click** | Raid gear check (lead/assist) |

Also available in the minimap **addon compartment** menu.

---

## ⚙️ Configuration

Advanced settings (enchantable slots, potion names, minimum counts, classes exempt from weapon oils, ...) can be adjusted in `Data.lua`.

## ⚠️ Notes
- Potion names are matched in English. Other client languages: add the localized names in `Data.lua`.
- The raid check can only inspect players within inspect range – use **Refresh** when they're nearby.

---

Found a bug or have a suggestion? Please open an issue and include the output of `/rp debug`.
