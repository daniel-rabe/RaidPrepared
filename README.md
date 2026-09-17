<p align="center">
  <img src="media/logo.png" alt="RaidPrepared" width="200">
</p>

# RaidPrepared

A World of Warcraft (Retail – Midnight) addon that makes sure you and your raid show up prepared: it checks equipped gear for missing or low-quality **enchants** and **gems**, counts your **healing potions**, **mana potions** and **weapon buffs** (oils, stones), and can inspect the whole raid for missing enchants and gems.

## Features

### Personal check
- Runs automatically when you **join a raid group** (and on login/reload while already in a raid).
- Detects:
  - **Missing enchants** on head, shoulders, chest, legs, feet, both rings, main hand and off-hand weapons.
  - **Empty gem sockets**.
  - **Missing epic gem**: one Eversong Diamond (Indecipherable, Powerful, Stoic or Telluric) should be socketed in your gear.
  - **Low-quality** enchants and gems (below the highest crafting quality rank).
  - **Outdated** gems from previous expansions (and optionally enchants, see configuration).
- Counts consumables in your bags:
  - **Healing potions**: Silvermoon Health Potion, Concentrated Silvermoon Health Potion
  - **Mana potions**: Lightfused Mana Potion – required for healer specs only
  - **Weapon buffs**: Thalassian Phoenix Oil, Oil of Dawn, Smuggler's Enchanted Edge, Refulgent Whetstone, Refulgent Weightstone, Laced Zoomshots, Weighted Boomshots – including remaining time of the active buff. Death Knights, Rogues and Shamans are not warned.
  - Consumables are matched by item ID (all quality ranks), so the check works with every client language.
- Shows a dialog listing every problem, dismissable with a button. Nothing pops up when everything is fine.
- Never opens in combat – it waits until combat ends.
- Optional **indicators on the character panel** item slots: enchant icon and socket icon next to each slot – red = missing, orange = low quality/outdated; items with a missing enchant or gem get a red border. Hover for details, toggle in the **Options** tab of the addon window or with `/rp indicators`.

### Talent loadout check
- Flag your saved talent loadouts as **Raid** and/or **Dungeon** – in the addon window (`/rp talents`) or with the checkboxes above the loadout dropdown in the talent frame.
- When you enter a **raid** or a **Mythic / Mythic+ dungeon**, and on every **ready check** inside, you are warned if your active loadout is not flagged for that content.
- If no loadout of your current spec is flagged for the content, no warning appears.
- Flags are saved per character.

### Raid gear check
- Available to the **raid leader and assistants** only.
- Lists **all group members** with their enchant/gem status (including a missing epic gem).
- Shows **low or mid quality enchants** together with the item level of that gear slot.
- Inspects players one after another (throttled, pauses in combat, doesn't interfere with your own inspect window).
- Per-player **Refresh** button and a **Refresh All** button.
- Hover a player to see the full list of problems with item links.
- Shows players who are out of range or offline.

## Usage

| Action | Result |
| --- | --- |
| `/rp` or `/raidprepared` | Check your own gear and consumables |
| `/rp raid` | Open the raid gear check (lead/assist only) |
| `/rp talents` | Flag talent loadouts for raid / Mythic dungeons |
| `/rp options` | Open the Options tab of the addon window |
| `/rp indicators` | Toggle enchant/socket indicators on the character panel |
| `/rp minimap` | Show/hide the minimap button |
| `/rp quality <rank>` | Set the required enchant/gem quality rank (default 2, also in the Options tab) |
| `/rp debug` | Print raw item, socket and consumable data (for bug reports) |
| Minimap button – left-click | Check your own gear |
| Minimap button – right-click | Open the raid gear check (lead/assist only) |
| Minimap button – Shift-click | Open the talent loadout flags |
| Minimap button – drag | Move the button |

The same actions are available from the addon compartment menu on the minimap.

## Installation

1. Download the latest release (or clone this repository).
2. Copy the `RaidPrepared` folder to `World of Warcraft\_retail_\Interface\AddOns\`.
3. Restart the game or type `/reload`.

## Configuration

Patch-specific settings live in [`Data.lua`](Data.lua):

| Setting | Purpose |
| --- | --- |
| `ENCHANT_SLOTS` | Slots that must be enchanted |
| `DEFAULT_MAX_QUALITY_TIER` | Highest crafting quality rank (anything lower is "low quality") |
| `KNOWN_CURRENT_ENCHANTS` | Optional whitelist of enchant IDs; others are reported as outdated |
| `MIN_GEM_EXPANSION` | Older gems count as outdated |
| `EPIC_GEM_IDS` | Epic gem item IDs; warn if none is socketed (empty = no check) |
| `HEALING_POTION_IDS` / `MANA_POTION_IDS` / `WEAPON_BUFF_IDS` | Item IDs that are counted (one ID per quality rank) |
| `MIN_HEALING_POTIONS` / `MIN_MANA_POTIONS` / `MIN_WEAPON_BUFFS` | Warn below this amount |
| `MANA_POTION_ROLES` | Spec roles that need mana potions |
| `WEAPON_BUFF_EXEMPT_CLASSES` | Classes that use imbues/poisons/runes instead of oils |

## Limitations

- Consumable item IDs are season-specific and need to be updated in `Data.lua` for new seasons/expansions.
- The raid check can only inspect players who are nearby (visible). Use **Refresh** once they are in range.
- The raid check reports missing enchants and empty sockets only; potion counts of other players are not visible to addons.

## Files

| File | Purpose |
| --- | --- |
| `RaidPrepared.toc` | Addon manifest |
| `Data.lua` | Patch-specific configuration |
| `Scanner.lua` | Gear scanning (enchants, gems) for any unit |
| `Potions.lua` | Potion and weapon buff counting |
| `RaidCheck.lua` | Raid inspect queue and window |
| `Dialog.lua` | Personal check result dialog |
| `Minimap.lua` | Minimap button and addon compartment |
| `Talents.lua` | Talent loadout flags, instance/ready check warning, talent frame checkboxes |
| `CharacterPanel.lua` | Enchant/socket indicators on the character panel |
| `Core.lua` | Events, raid join detection, slash commands |
