# Renaming RaidPrepared → PullReady

Working notes for the 1.5.0 rename. Delete this file once the rename is
published and the leftover toc entries (section 5) are gone.

## The approach

The addon is renamed; **the addon folder is not**. Everything the player sees
says PullReady, while the folder, the `.toc` filename and the CurseForge URL
stay `RaidPrepared`.

That is deliberate. WoW names the saved-variables file after the addon folder,
so a new folder would hand every existing user an empty settings file and leave
the old folder behind to load alongside the new one. Keeping the folder means
existing installs update in place and keep their settings, favourites and
loadout flags. The cost is a permanent mismatch between the display name and the
folder on disk, which is common enough in the addon ecosystem that nobody
notices.

The CurseForge project display name is independent of the packaged folder name -
the packager takes the folder name from `package-as` in `.pkgmeta`, not from the
project. That is what makes this possible.

## 1. Done in this repository

Renamed (player-visible):

| Change | Where |
| --- | --- |
| `## Title: PullReady` | `RaidPrepared.toc` |
| Slash commands `/pullready` and `/pr` (`/rp` removed) | `Core.lua` |
| `/rp …` → `/pr …` in every user-visible string | `Locales/*.lua` (keys **and** translations), `Core.lua`, `Dialog.lua` |
| `L["RaidPrepared travel - %s"]` → `L["PullReady travel - %s"]` | all 9 translated locales |
| Chat prefix `\|cff33ccffPullReady\|r:` | `Core.lua`, `Travel/Core.lua`, `Talents.lua`, `RaidCheck.lua` |
| Window title, tooltips, addon compartment label | `Dialog.lua`, `Minimap.lua`, `CharacterPanel.lua`, `Talents.lua` |
| Name and taglines | `README.md`, `CURSEFORGE.md` |

Renamed (internal, no effect on the player):

| Change | Where |
| --- | --- |
| Saved variable globals → `PullReadyDB` / `PullReadyCharDB` | `.toc` + all Lua, with the migration below |
| `RaidPrepared_OnAddonCompartment*` → `PullReady_OnAddonCompartment*` | `.toc` + `Minimap.lua` |
| Frame names (`PullReadyDialog`, `PullReadyMinimapButton`, `PullReadyTravel*`) | `Dialog.lua`, `Minimap.lua`, `Travel/` |
| Private namespace `RP` → `PR` | all Lua files |
| `## Version: 1.5.0` | `RaidPrepared.toc` |

Deliberately **not** renamed:

- `RaidPrepared.toc`, and the `RaidPrepared` folder it has to match - a `.toc`
  must be named after its folder, and the folder is what keeps settings alive.
- `package-as: RaidPrepared` in `.pkgmeta` - this is what sets the folder name
  inside the packaged zip. Changing it is exactly what would break upgrades.
- `RaidCheck.lua` and `PR.RaidCheck` - named after the raid-inspect feature, not
  after the addon.

## 2. The saved-variable migration

The `.toc` declares the old globals alongside the new ones:

```
## SavedVariables: PullReadyDB, RaidPreparedDB
## SavedVariablesPerCharacter: PullReadyCharDB, RaidPreparedCharDB
```

Declaring them is what makes WoW load the old tables out of the existing
`RaidPrepared.lua` at all. `AdoptRenamedVariables()` in `Core.lua` then hands
them over on the first `ADDON_LOADED` and clears the old names so they are not
written out again.

This works only because the folder did not change, so it is the same saved
variables file. Had the folder been renamed, there would be nothing to read.

## 3. Before publishing

- [ ] Copy the repo into `Interface\AddOns\RaidPrepared` (**not** `PullReady` -
      the folder has to match the `.toc` name).
- [ ] Delete the stale `dist\RaidPrepared-1.0.0.zip` build artifact.
- The GitHub repo can be renamed to `PullReady` if you like - it has no effect
  on the packaged folder, since `package-as` decides that. Update the remote if
  you do: `git remote set-url origin git@github.com:daniel-rabe/PullReady.git`

## 4. In-game smoke test

Test on a character that already has settings, so the migration is exercised.

- [ ] Addon loads with no Lua error and is listed as *PullReady*.
- [ ] `/pullready` and `/pr` both work; `/rp` is gone.
- [ ] `/pr help` output shows `/pr …` in your client language.
- [ ] **Existing settings survived**: quality rank, minimap position, indicator
      toggle, whisper language.
- [ ] **Existing per-character data survived**: talent loadout flags, shopping
      favourites, travel favourites and recents.
- [ ] `/reload`, then confirm the settings are still there - this is what proves
      the new globals are being written, not just read.
- [ ] Check `WTF\…\SavedVariables\RaidPrepared.lua` after logout: it should
      contain `PullReadyDB` and **no** `RaidPreparedDB`.

## 5. Retiring the migration

Once 1.5.0 has been out long enough that everyone has logged in with it (a
release or two), delete `AdoptRenamedVariables()` and its call from `Core.lua`
and shorten the two `.toc` lines back to the new names only. Anyone who skips
straight from 1.4.0 to that release loses their settings, which is the normal
cost of a stale-upgrade path.

## 6. CurseForge

Only the display name changes. **Do not request a slug change** - the packaged
folder name must match the slug, and the folder is staying `RaidPrepared`.
Changing the slug would mean changing `package-as` too, which is the upgrade
break this whole approach exists to avoid.

- [ ] Rename the project to **PullReady** in the author console
      (Projects → the project → Settings).
- [ ] Paste the updated `CURSEFORGE.md` into the project description.
- [ ] Upload 1.5.0.
- [ ] Mention the old name in the description for a release or two so searches
      for "RaidPrepared" still land.

The URL stays `…/wow/addons/raidprepared`. If that bothers you later, the slug
can be changed by CurseForge staff on request
([forum thread](https://authors.curseforge.com/forums/wow-sites/wow-sites-feedback/218755-changing-addon-url)),
but that is a separate decision with the folder-rename cost attached.

No logo work needed: `media/logo.png` is a wordmark-free icon (shield, gem,
potion, checkmark) and carries no old name, in the image or in its metadata.

### Suggested 1.5.0 changelog

> **RaidPrepared is now PullReady.**
>
> Same addon, new name. The update installs over your existing copy and your
> settings, favourites and talent loadout flags all carry over - there is
> nothing to clean up.
>
> The slash commands are now `/pr` and `/pullready`. `/rp` no longer works.
>
> The addon folder is still called `RaidPrepared` so that updates keep working
> in place; only the name shown in game and here has changed.

## 7. Elsewhere

- [ ] WoWInterface / Wago listings, if the addon is mirrored there.
- [ ] Any links in guild docs, Discord pins or the GitHub profile README.
