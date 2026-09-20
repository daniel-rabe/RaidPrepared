<p align="center">
  <img src="media/logo.png" alt="PullReady" width="200">
</p>

# PullReady

A World of Warcraft (Retail – Midnight) addon that makes sure you and your raid are ready before the pull: it checks equipped gear for missing or low-quality **enchants** and **gems**, counts your **healing potions**, **mana potions** and **weapon buffs** (oils, stones), can inspect the whole raid for missing enchants and gems, and searches every fast-travel option your character actually has.

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
- Shows a dialog listing every problem (close with the X button or ESC). Nothing pops up when everything is fine.
- Never opens in combat – it waits until combat ends.
- Optional **indicators on the character panel** item slots: enchant icon and socket icon next to each slot – red = missing, orange = low quality/outdated; items with a missing enchant or gem get a red border. Hover for details, toggle in the **Options** tab of the addon window or with `/pr indicators`.

### Talent loadout check
- Flag your saved talent loadouts as **Raid** and/or **Dungeon** – in the **Talents** tab of the addon window (`/pr talents`) or with the checkboxes above the loadout dropdown in the talent frame.
- When you enter a **raid** or a **Mythic / Mythic+ dungeon**, and on every **ready check** inside, you are warned if your active loadout is not flagged for that content.
- If no loadout of your current spec is flagged for the content, no warning appears.
- Flags are saved per character.

### Raid / Party Inspect
- Tab **Raid Inspect** (in a raid, leader and assistants only) or **Party Inspect** (in a party, available to everyone).
- Lists **all group members** with their enchant/gem status (including a missing epic gem).
- Shows **low or mid quality enchants** together with the item level of that gear slot.
- Inspects players one after another (throttled, pauses in combat, doesn't interfere with your own inspect window).
- Per-player **Refresh** button and a **Refresh All** button.
- Per-player **Whisper** button: sends a short, friendly whisper listing the missing/low enchants and empty sockets (hover it to preview the text). Once per inspect result, so nobody gets spammed.
- Hover a player to see the full list of problems with item links.
- Shows players who are out of range or offline.

### Travel
- Tab **Travel** (`/pr travel`, or Ctrl-click the minimap button): one search box for every fast-travel option this character can actually use right now.
- Covers **Mythic+ dungeon teleports**, the Garrison and Dalaran hearthstones, every **hearthstone toy** you own, **class travel spells** and **engineering wormholes**.
- Dungeon ports are found by **destination**: a port named "Path of the Warding Candles" is listed and searchable as *Darkflame Cleft*, because the destination is read out of the spell description. That keeps working across seasons and locales.
- **M+** filters the list to dungeon ports for the current Mythic+ season.
- **Left-click** a row to travel, **right-click** to favourite it. Favourites and recently used options sort to the top.
- Travel abilities are unusable in combat anyway, so the tab greys out and says **Locked in combat**, then fills back in when combat ends.

### Shopping
- Tab **Shopping** (`/pr shop`): this season's enchants, leg armor, gems and consumables as real item rows.
- By default only the sections your own check flagged are listed, so the tab answers *what do I still have to buy* rather than *what exists*. **Show everything** turns it into the full catalog.
- **Shift-click** a row to paste the item into the auction house search bar (or into chat when the auction house is closed); **Ctrl-click** opens the dressing room.
- **Right-click** a row to favourite it. Favourites are pinned to the top of their section and are remembered **per character**, since which ring enchant or gem you want depends on the character.
- Two independent toggles: **Show everything** widens the list from what you are missing to the whole catalog, and **Only favourites** narrows whichever of those two you are looking at down to your favourites.
- Legs list spellthreads or armor kits depending on the armor type you actually wear.

### Languages
- The interface is translated into every WoW client language: English, German, French, Spanish (EU/MX), Italian, Brazilian Portuguese, Russian, Korean and Chinese (Simplified/Traditional).
- The **Whisper** message is sent in your own client language.
- Translations live in `Locales/<locale>.lua`; anything not translated falls back to English. Corrections from native speakers are welcome.

## Usage

| Action | Result |
| --- | --- |
| `/pr` or `/pullready` | Check your own gear and consumables |
| `/pr inspect` (or `/pr raid`, `/pr party`) | Open the Raid/Party Inspect tab (raid: lead/assist only) |
| `/pr talents` | Open the Talents tab (flag loadouts for raid / Mythic dungeons) |
| `/pr travel` | Open the Travel tab (search your fast-travel options) |
| `/pr shop` | Open the Shopping tab (enchants, gems and consumables you still need) |
| `/pr travel season` | List this season's Mythic+ maps and the ports that serve them |
| `/pr travel audit` | Report travel entries whose ID does not resolve |
| `/pr travel scan [text]` | Dump spellbook entries, used to harvest teleport IDs |
| `/pr travel discover` | Show which spells the teleport patterns match |
| `/pr travel copy` | Reopen the last diagnostic output for copying |
| `/pr options` | Open the Options tab of the addon window |
| `/pr indicators` | Toggle enchant/socket indicators on the character panel |
| `/pr minimap` | Show/hide the minimap button |
| `/pr quality <rank>` | Set the required enchant/gem quality rank (default 2, also in the Options tab) |
| `/pr debug` | Print raw item, socket and consumable data (for bug reports) |
| Minimap button – left-click | Check your own gear |
| Minimap button – right-click | Open the Raid/Party Inspect tab |
| Minimap button – Shift-click | Open the Talents tab |
| Minimap button – Ctrl-click | Open the Travel tab |
| Minimap button – drag | Move the button |

The same actions are available from the addon compartment menu on the minimap.

## Installation

1. Download the latest release (or clone this repository).
2. Copy the folder to `World of Warcraft\_retail_\Interface\AddOns\RaidPrepared`.
3. Restart the game or type `/reload`.

The addon folder is still called `RaidPrepared`: the addon was renamed in 1.5.0
but the folder was deliberately left alone, so existing installs update in place
and keep their settings. WoW names the saved-variables file after the folder, not
after the addon, which is the whole reason for that.

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
| `ENCHANT_ITEMS` / `LEG_ARMOR_ITEMS` | Enchants and leg armor the Shopping tab offers, per slot |
| `GEM_ITEMS` / `EPIC_GEM_SHOP_IDS` | Gems the Shopping tab offers, grouped by mineral |
| `CONSUMABLE_SHOP_IDS` | Ordered consumable IDs for the Shopping tab (the tables above are sets) |
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
| `RaidCheck.lua` | Raid/Party Inspect queue and tab |
| `Dialog.lua` | Main window with Check, Inspect, Talents, Travel, Shopping and Options tabs |
| `Minimap.lua` | Minimap button and addon compartment |
| `Talents.lua` | Talent loadout flags, instance/ready check warning, talent frame checkboxes |
| `CharacterPanel.lua` | Enchant/socket indicators on the character panel |
| `Shopping.lua` | Shopping tab: what to buy, filtered to what the check flagged |
| `Locales/Locales.lua` | Localization table (English keys, English fallback) |
| `Locales/<locale>.lua` | Translations per client language |
| `Core.lua` | Events, raid join detection, slash commands |
| `Travel/Core.lua` | Travel namespace, event dispatch, diagnostic output capture |
| `Travel/Data.lua` | Curated travel candidates: hearthstones, toys, class spells, professions |
| `Travel/Portals.lua` | Name patterns used to auto-discover Mythic+ teleports |
| `Travel/Collector.lua` | Filters candidates down to what you own; audit, scan and discovery |
| `Travel/Search.lua` | Tokenized scoring and ranking for the travel search |
| `Travel/Season.lua` | Maps dungeon ports to the current Mythic+ season |
| `Travel/CopyFrame.lua` | Copyable window for diagnostic output |
| `Travel/Panel.lua` | Travel tab: search box and secure action button pool |
