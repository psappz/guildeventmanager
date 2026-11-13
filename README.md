# GuildEventManager

Plan and run guild events in WoW Forever: event points, guild honor, guild achievements with WotLK-style plaques and one total score for the whole guild. Works for Horde (clan, Orgrimmar look) and Alliance (order, Stormwind look).

The guild master activates it for the guild by pasting an activation code into the guild info. Until then the addon sends nothing. Event rights go to the guild master and a rank he chooses.

- Slash command: `/gem`
- Modules: `GuildEventManager_PvP` (guild honor, blood debts, war drums, warbands, duels of honor, oaths, season results) ships in the same package as its own folder
- Languages: English, Deutsch, Français, Español, Italiano, Português
- Changes: [CHANGELOG.md](CHANGELOG.md)
- License: [MIT](LICENSE)

## Modules

GuildEventManager is modular. The core and the PvP module ship together; every other module is a separate addon that depends on the core. PvP modules can extend the PvP module (own PvP event types, deeds that give guild honor, honor rules, reactions to kills, deaths and war drums).

**Write your own module:** [docs/MODULES.md](docs/MODULES.md) – API reference, rules for the Forever client, testing checklist. Working examples: [examples/GuildEventManager_Example](examples/GuildEventManager_Example) (event module) and [examples/GuildEventManager_PvPDuels](examples/GuildEventManager_PvPDuels) (PvP module).

## Repository layout

- Root: the core addon `GuildEventManager`
- `GuildEventManager_PvP/`: the PvP module, moved to its own addon folder when packaged (see `.pkgmeta`)
- `docs/`: module guide, logo and CurseForge texts, not packaged
- `examples/`: example modules, not packaged

## Releasing

CurseForge packages every push through the repository webhook (`.pkgmeta`). Tags become release files.
