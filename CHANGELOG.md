# GuildEventManager

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
