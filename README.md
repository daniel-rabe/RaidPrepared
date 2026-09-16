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
  - **Low-quality** enchants and gems (below the highest crafting quality rank).
  - **Outdated** gems from previous expansions (and optionally enchants, see configuration).
- Counts consumables in your bags:
  - **Healing potions** (Silvermoon Health Potion, Concentrated Silvermoon Health Potion)
  - **Mana potions** (Lightfused Mana Potion) – required for healer specs only
  - **Weapon buffs** (oils, sharpening stones, weightstones) – including remaining time of the active buff. Death Knights, Rogues and Shamans are not warned.
- Shows a dialog listing every problem, dismissable with a button. Nothing pops up when everything is fine.
- Never opens in combat – it waits until combat ends.

### Raid gear check
- Lists **all group members** with their enchant/gem status.
- Inspects players one after another (throttled, pauses in combat, doesn't interfere with your own inspect window).
- Per-player **Refresh** button and a **Refresh All** button.
- Hover a player to see the full list of problems with item links.
- Shows players who are out of range or offline.

## Usage

| Action | Result |
| --- | --- |
| `/rp` or `/raidprepared` | Check your own gear and consumables |
| `/rp raid` | Open the raid gear check |
| `/rp minimap` | Show/hide the minimap button |
| `/rp quality <rank>` | Set the required enchant/gem quality rank (default 2) |
| `/rp debug` | Print raw item, socket and consumable data (for bug reports) |
| Minimap button – left-click | Check your own gear |
| Minimap button – right-click | Open the raid gear check |
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
| `MIN_GEM_EXPANSION` / `MIN_CONSUMABLE_EXPANSION` | Older gems/consumables count as outdated |
| `HEALING_POTION_NAMES` / `MANA_POTION_NAMES` | Potions that are counted (empty = detect automatically) |
| `MIN_HEALING_POTIONS` / `MIN_MANA_POTIONS` / `MIN_WEAPON_BUFFS` | Warn below this amount |
| `MANA_POTION_ROLES` | Spec roles that need mana potions |
| `WEAPON_BUFF_EXEMPT_CLASSES` | Classes that use imbues/poisons/runes instead of oils |
| `EXTRA_HEALING_ITEMS` / `EXTRA_MANA_ITEMS` / `EXTRA_WEAPON_BUFF_ITEMS` | Additional item IDs to count |

## Limitations

- Potion names are matched in English; on other client languages add the localized names to `Data.lua`.
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
| `Core.lua` | Events, raid join detection, slash commands |
