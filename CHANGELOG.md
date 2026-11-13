# GuildEventManager

## 0.5.0 (core and PvP module)

### New
- **Languages:** French, Spanish (also Mexican Spanish), Italian and Brazilian Portuguese for the core and the PvP module.
- **Mak'gora / duel of honor** (PvP): challenge a guild member with a stake (`/gem makgora <name> [stake]` or the new tab). The challenged one accepts, a guild member watches as witness and confirms the winner; the winner gets 10 honor. Once a week per pair. If the game's duel message is readable, the witness is asked directly.
- **Oaths** (PvP): swear a small, great or mighty oath (10 / 25 / 40 honor, `/gem oath`). Two witnesses confirm it was kept within 14 days.
- **Season results** (PvP): Season Podium (places 1–3 of guild honor), Champion of the Clan / Order (place 1, honor name "Champion" for the next season), Unstoppable (the guild reaches 5000 honor in a season – everyone who helped earns it). Shown in the new tab with the last three seasons and the progress towards the goal.
- New achievements: Mak'gora / Duel of Honor (bronze, silver, gold with honor name), Challenger, Unbeaten, Oathkeeper, Sword of the Clan / Order (meta achievement).
- All new values are in the honor rules and can be changed by event managers.
- Module API 2 / PvP API 2 (both still accept modules written for version 1): computed, repeatable and meta achievements (`compute`, `repeatable`, `progress`, `meta`, `honorPrio`); `PvP.Challenge`, `PvP.Swear`, `PvP.SeasonResults`, new callbacks `MAKGORA`, `MAKGORA_NEW`, `OATH_FULFILLED`; `debt.how` in `DEBT_PAID`. See docs/MODULES.md, section 6 (API changes), which also states the compatibility promise for 1.0.

### Fixed
- **The guild profile was sent again and again.** It held full copies of all achievements (about 5 KB), and the game drops addon messages once a client sends too fast, so parts never arrived. The profile now keeps only what event managers changed (about 0.5 KB), and all messages leave through a queue that keeps to the game's limit.

## PvP module 0.4.1

### New
- **Revenge in the guild chat** (guild setting, off by default): the avenger's client posts "[GEM] Revenge taken on X (zone) – blood debt settled!" so members without the addon see it too. Out of combat only, several revenges in one line, at most one post every 2 minutes per member (adjustable in the honor rules).
- Personal options in the PvP tab: don't post my own revenges; hide these lines of others in the guild chat.

## PvP module 0.4.0

### New
- **Revenge near you:** a debtor who dies near you (visible nameplate) while you fight settles the blood debt, as in your target.
- **Guild message:** every member sees when someone takes revenge ("Monaco Stenz took revenge on X · zone · +20 honor", "Served cold! ..."). Several revenges within seconds become one line. Personal choice in the PvP tab: chat, chat + banner, off.
- `/gem revenge` shows all blood-debt messages once with sample names.

## PvP module 0.3.2

### Fixed
- Blood debts are redeemed when the debtor dies in your target while you are fighting, also without an honorable kill (grey enemies, diminished honor). Before, a debt was only redeemed through a kill with a readable victim name, which the client never delivered.

## PvP module 0.3.1

### Fixed
- Kills now carry the victim's name when the client does not deliver a readable honor message: the dead enemy player in the target (or under the mouse) is used. Needed for the per-enemy daily limit and for redeeming blood debts.
- `/gem pvpcheck` shows the last honor message the client delivered.

## 0.4.2

### Fixed
- Demo data follows the addon language (Settings → Personal → Language), not the client language, so screenshots can be taken in English on a German client.
- Old achievement "H_ACH_BLADE" from 0.1 no longer shows up.
- Achievement settings show their labels only when an achievement is selected.
- Banner thresholds field and the rank column of PvP Kills are wide enough.

## 0.4.1

### Fixed
- `/gem demo` failed with "attempt to call a nil value": the WoW client has no `math.randomseed`; the demo uses its own generator now.

## 0.4.0 (PvP module 0.3.0)

### New
- **Module API v1** (`GuildEventManagerAPI`): register modules with event types, point pots, achievements, rules and strings; own and awarded points; events; callbacks (event started/ended/cancelled/updated, points added, achievement earned, activated, profile changed); guild messages with a module namespace; own tabs, widgets, commands.
- **PvP extension API** (`GuildEventManagerAPI.PvP`): PvP modules register deeds that give guild honor (with honor value and daily cap in the honor rules), extra rules, and react to kills, deaths, blood debts and war drums.
- Developer guide `docs/MODULES.md` and two example modules in `examples/`.
- The honor rules form shows the rules of PvP modules.

## 0.3.0 (PvP module 0.2.0)

### New
- **PvP Kills** tab: honorable kills of every member in the open world and in battlegrounds, this season and in total, plus the game's own statistics (lifetime honorable and dishonorable kills, today, this week, PvP rank with progress, highest rank). Sortable by every column. Each member sends only his own numbers.
- **Demo mode** for screenshots: `/gem demo` fills the window with sample data for the guild Neocortex and invented names. Nothing is sent or saved; `/gem demo off` or `/reload` ends it.

### Changed
- Several modules can now listen to the same guild message.

## 0.2.2

### Fixed
- No more "ADDON_ACTION_BLOCKED" messages in combat: the guild info (activation code) is read only out of combat, once per session, and kept per guild.

## 0.2.1

### Fixed
- The PvP module no longer registers for the combat log, which the Forever client (Midnight engine) closes to addons. Kills now come from the honorable-kill counter, blood debts from the enemy who last targeted you.
- Blocked or forbidden calls are written to the error log (`/gem errors`).

## 0.2.0

### New
- **PvP module** (GuildEventManager_PvP, separate folder): guild honor for open world kills, blood debts (Alliance: debts of honor), war drums (Alliance: storm bells) with waypoint and arrival honor, honor roll, honor rules, event types *Warband* and *Defense*, 12 PvP achievements.
- **Event goals** for every event type: tick them off on the event page, each reached goal gives points to all participants.
- Hidden and tiered (bronze/silver/gold) achievements; modules bring their own achievements and tabs.
- Own icon for the addon list, minimap button and addon compartment.

### Fixed
- Your own character is found in the guild roster (Forever returns first and last name separately).

## 0.1.0

- First version: events with run types, groups, sign-ups and reminders; event points and guild total; clan/order banner with member ranking; guild achievements with WotLK-style plaques; guild profile with event manager rank; sync over the guild addon channel after activation by the guild master; Horde and Alliance themes.
