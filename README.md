# GuildEventManager

Plan and run guild events in WoW Forever: event points, guild honor, guild achievements with WotLK-style plaques and one total score for the whole guild. Works for Horde (clan, Orgrimmar look) and Alliance (order, Stormwind look).

The guild master activates it for the guild by pasting an activation code into the guild info. Until then the addon sends nothing. Event rights go to the guild master and a rank he chooses.

- Slash command: `/gem`
- Modules: `GuildEventManager_PvP` (guild honor, blood debts, war drums, warbands) ships in the same package as its own folder
- Changes: [CHANGELOG.md](CHANGELOG.md)
- License: [MIT](LICENSE)

## Repository layout

- Root: the core addon `GuildEventManager`
- `GuildEventManager_PvP/`: the PvP module, moved to its own addon folder when packaged (see `.pkgmeta`)
- `docs/`: logo and CurseForge texts, not packaged

## Releasing

CurseForge packages every push through the repository webhook (`.pkgmeta`). Tags become release files.
