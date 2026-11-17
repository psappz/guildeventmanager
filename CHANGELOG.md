# GuildEventManager

## 0.8.0 (in progress)

### Added
- **Invitation reminder:** every member who has not answered an event yet gets a notice under the bell and a line in the chat after login. In the week before the event a popup asks for an answer: "Open GuildEventManager" leads straight to the own sign-up (with a short glow around it), "Later" asks again after three hours. The popup never comes during combat or while the window is open; Escape counts as "Later". Answering yes, no or anything else ends the reminders.
- **Help:** a "?" next to the bell explains the page you are on. While the guild has not switched the addon on, it carries a red 1: members learn that the guild master has to do it, the guild master gets a step-by-step guide on the settings page (copy the code, paste it, check – with live status).
- **Preview for members:** while the guild master has not switched the addon on – or when you are not in a guild – the window shows the sample guild with a big hint on top instead of an empty page. "Tell the guild master" opens a whisper to him with a ready text (you send it yourself). Nothing is sent or saved; the preview ends by itself once the guild is switched on.
- **Switch off:** link "Switch off GuildEventManager" at the bottom right of the settings (guild master): a guide to remove the code again. Nobody has to uninstall the addon; points, events and settings are kept.
- **API:** `API.AddHelp(id, fn)` – help text for a module's views.
- **Level of an event:** the editor has a field "From level" (empty = all levels). Only characters of that level are reminded; the detail page shows the level. Raids use the highest player level by default. Event types can set `minLevel`.

### Changed
- Members who are online when the guild master pastes the activation code switch on by themselves within about two minutes (before: only after `/reload`).
- New guide for guild masters: `docs/GUILD_MASTER.md`.
- Overview: "still without an answer" counts only the events you are asked to answer (declined ones and events above your level no longer count).

### Fixed
- Opening an event from a notice right after login showed the event list instead of the event.
- Addon messages from players outside the guild are now ignored on every channel. Before, a stranger could whisper sign-ups or points to a member.

## 0.7.0 – 2026-11-16 (beta test)

### Added
- **New window layout:** a side bar with the guild's areas (Overview, Events, Honor book, My achievements, Banner) and the modules (Raids, PvP), each module with its sub tabs. The gear opens the settings – with the rule pages of the modules (PvP rules, target alarm, raids) as sub tabs –, the bell shows notices (new events, raid groups, sightings), the guild crest opens the banner. Core API 5: `API.AddModule(id, { label, icon, order, badge, tabs })`, `API.AddSettingsPage`, `API.AddNotice`; `API.AddTab` with `parent` puts a tab into a module entry.
- **Overview:** banner progress, the next event (a click opens its sign-up), your own sign-ups, the newest bookings of all modules and the notices.
- **Honor book:** every booking of every module in one list with the module as a tag and a filter chip per module; event managers strike entries with a right-click. Modules say how their entries read with `API.AddLedgerFormat`.
- **Sign-up per event:** a click on an event opens its page with "Your sign-up": Yes, Tentative, Late, Bench or No, a comment (60 characters) and the event's own questions. The list of sign-ups is grouped by state and shows the answers. The event list shows "you: Yes" and so on. Tentative and bench are not counted as taking part and are not invited.
- **Sign-up fields (API 5):** event types ask their own questions with `signupFields` (`auto` read from the game, `choice`, `multi`, `number`, `check`, `text`; required, default, check, hidden, lead-only). The answers travel with the sign-up; members without the module can still sign up.
- **Invite all** on every event (event page, raid night): invites everyone signed up with Yes or Late who is online, turns the party into a raid when needed. Needs group lead or assistant.
- **Raids – new module GuildEventManager_PvE, part of the package** (entry "Raids"):
  - Raid events for The Barrow Deeps (10, 2 groups, 8 bosses), Hyjal Summit (20, 4 groups, 13 bosses) and Onyxia's Lair (40, 8 groups, Drakefire Amulet). Raids are data, more can be added.
  - Who may create and lead raids: the event managers plus every rank down to the one set in the settings (default: the rank below the guild master). Raid leads below the event-manager rank plan, invite and sort; honor for a raid is booked by an event manager when closing it.
  - Sign-up with role (main tank, 2nd tank, melee, range, healer) and second role, only the roles the class can play (no range paladins, no tank priests). A sign-up without a role stays "role open" instead of being guessed; the raid lead sets roles per raid with a right-click in the line-up.
  - Specs ("My specs"): on WoW Forever every class has one talent tree with the classic trees side by side. The main spec is "Automatic" – the tree with the most points, following the talents – or chosen by hand; the second spec comes from the second talent group or is chosen by hand. The talent points are shown (e.g. Discipline 17 · Holy 0 · Shadow 15). Specs are sent to the guild; the raid lead may correct them.
  - Overview of the sign-ups by role with the wanted numbers per raid (settings), tentative and bench below.
  - Line-up: groups with drag & drop – into another group moves, onto a player of another group swaps, inside a group reorders; click and click the target works too. Tanks always stand on top of their group. Role icons (shield, healing, sword, bow) on every slot. "Fill groups" spreads tanks and healers.
  - Boss setups: per boss a member can play his second role (right-click); the boss list switches the line-up.
  - Buffs, debuffs and utility of the line-up, raid-wide and per group with hints ("melee without Windfury"); cure poison and cure disease are separate (priests remove disease, not poison). A click on an entry highlights everyone who brings it. Boss needs for Onyxia (fear protection, Tremor Totem in every group, fire resistance to be filled in after the first tries).
  - Raid night: invite all, sort the raid into the planned groups, readiness per member (online, addon, lockout of this week, Drakefire Amulet, bench count), text for Discord.
  - Raid-Helper import: paste the event JSON; Discord names are matched to characters once and remembered per Discord ID, the class comes from the spec name. A sign-up made in the addon always wins.
  - `/gem raid` opens the raids, `/gem raid an|vorläufig|spät|bank|ab` signs up for the next raid, `/gem raid import`.
- **PvP target alarm** (like RareScanner): an enemy player with a bounty, your blood debt, an oath naming him, or on your watch list comes into sight (nameplate, target, mouseover, target of a group member). A window shows why, with a protected button "Target and mark with skull" (prepared out of combat only) and "Call the guild", which sends the sighting with position; others get a notice with a waypoint. At most one alarm per enemy and minute, off in capitals, inns and battlegrounds (settings), closes after 30 s. `/gem watch <name>` keeps your own watch list.
- **`/gem probe`** checks what this client gives addons (talent groups, lockouts, amulet, invite and raid sorting, waypoints, protected buttons, size of the paste box) and adds the result to `/gem export`. Modules add checks with `API.AddProbe`.
- **Bounties** (new tab "Bounties", `/gem bounty <enemy> <honor>`): a member puts honor on the head of an enemy player – at least 5 more than a normal kill gives (8 with the default rules), at most 50. The bounty only pays when the addon is sure the kill was yours: the enemy died in your target (or the honor line names him); an enemy seen dying only by his nameplate may be somebody else's kill and gives a hint instead. The honor is taken from him right away; whoever of the guild kills that player first gets it. After 7 days, or when withdrawn, the poster gets it back. Rules for the guild master and event managers: smallest and largest bounty, run time, open bounties per member. The guild is told when a bounty is set and collected; an enemy with a bounty in the target frame gives a "Wanted" notice. Two members claiming at the same moment: the earlier one gets it, the other books it back. Core API 4: `Pts.SELF_NEG`, members may book a minus for themselves for bounties. PvP API 4: `PvP.OpenBounties`, `PvP.WonBounties`, `PvP.BountyOn`, `PvP.PostBounty`, callbacks `PVP_BOUNTY_NEW`, `PVP_BOUNTY_WON`.

### Changed
- **Guild banner from the guild tabard:** the banner is painted per faction (Horde: dark wood, leather, iron and tusks; Alliance: pale wood, steel and gold) and grows with the level – 1 pennant, 2 full banner with the guild emblem, 3 trim and tassels, 4 finial and sheen. The levels have names per faction: Horde Forged · Tempered · Feared · Legendary, Alliance Armed · Proven · Celebrated · Legendary. The cloth takes the tabard's background colour, the hem its border colour, and the emblem is drawn by the game exactly as on the tabard. `/gem tabard` shows a test drawing, `/gem probe` the tabard data.
- **Guild emblem in the window header:** the guild's own emblem on a shield in the tabard colour (the faction crest when the guild has no tabard). Choice buttons are capsules like in the mockup.
- **New look:** own icons for the side bar, bell (with a red count), gear and close; the guild crest per faction and the guild name as the window title; coloured tags for modules (PvP red, Raids gold) and sign-up states; date tiles in the event list and on the event page; check and cross as icons; role symbols (shield, cross, sword, bow) and two-line slots with spec and second role in the raid line-up; buffs per group as coloured capsules.
- **Achievements are now "My achievements":** they are earned by you alone and bring honor to you. Guild achievements, won together for the banner, and trophies follow in 0.9.0.
- The PvP tabs are sub tabs of "PvP" (Overview, Kills, Duels & Oaths, Bounties); the PvP rules moved to the settings.
- The guild roster now remembers the class of every member (for raids).
- **Names in the PvP kill log:** a kill whose name the addon could not see no longer says "defeated an enemy". It takes the enemy you last had in your target during the fight (within 2 minutes); only if there is none it says "(name unknown)". Older entries with "an enemy" are shown the same way.
- **Feign Death:** a hunter playing dead looks dead and drops out of the target. An enemy that "dies" in your target but is gone from it half a second later is treated as feigning: his name is never used for a kill, a bounty or a blood debt. An enemy seen dead and then alive again is taken off the list. `/gem pvpcheck` shows how many feigns were caught.
- **Duels of honor need a named witness.** The challenger names the opponent, a witness (a guild member who does not fight) and an optional stake – three labelled fields in the tab, or `/gem duel <opponent> <witness> [stake]`. Only that witness can confirm the winner, after a confirmation dialog; buttons, the prompt after the duel and votes of anyone else are gone or ignored. The witness is told when they are named and when the duel starts. Duels sent by 0.6.0 clients have no named witness and can no longer be confirmed from this version – take them back and challenge again. The rule "Witnesses (duel)" is no longer shown. PvP API 4: `PvP.Challenge(name, witness, stake)`.
- **Challenge, answer and duel can be days apart.** The opponent has a day to answer (was 30 minutes); after that the duelists meet the witness whenever it suits them, within the new rule "Days to fight an accepted duel of honor" (default 3, was 2 hours). The witness keeps the duel over relogs and takes over an acceptance they missed while offline. When the witness opens the addon window, it asks who won (winner A / winner B / Later), then asks to confirm; `/gem witness` without a name asks as well. Core API 4: callback `WINDOW_OPENED`.
- **Minimum rank for duel witnesses:** new rule "Witness: minimum rank" (a dropdown with the guild's ranks, default every rank). A challenge with a witness below that rank is refused with a message; the tab shows the required rank.
- **Daily limits for duels of honor,** so duels cannot make up for missing world PvP: new rules "Duels of honor per day" for the whole guild (default 5) and "per member and day" (default 1, 0 = no limit), set by the guild master and event managers like the honor per duel. A day ends at the game's daily reset. Open, fought and booked duels count; declined and taken-back ones don't. The tab shows today's count.
- **Painted clan / order banner:** hand-painted art for all four stages of both factions (cloth, sigil with an own emblem per faction, trophies, braziers with flickering flames), a leather (Horde) or parchment (Alliance) card background, and the stages as small pictures below the banner.

### Fixed
- **Victim names missing although the enemy was in the target.** During a fight the game's kill counter is often unreadable, so the kill is counted after the fight – when the target is long gone. The PvP module now remembers every enemy player it sees die (target and nameplates, also when the name was only readable before the fight) and gives those names to the kills counted later. `/gem pvpcheck` and `/gem export` show what was seen at the last kills.

## 0.6.0 (beta)

### Changed
- **"Mak'gora" is now "Duel of Honor" everywhere** (both factions, all languages). In WoW Hardcore, Mak'gora means a duel to the death; ours is a normal duel. The challenge dialog and the tab now say so: nobody dies, no character is lost. The command is `/gem duel` (German `/gem duell`); `/gem makgora` is gone. The tab is called "Duels & Oaths". Existing duels and achievements are kept.
- **New event editor** in four steps on one page:
  - *What?* – event types as tiles with icon and description.
  - *When?* – today, tomorrow and the next weekdays as buttons (or any date), time from lists in 15-minute steps, duration as buttons (1 h, 2 h, 3 h, open end, days, weeks, season). Start and end are worked out from that – no date format to learn.
  - *Who?* – group size as buttons (everyone, group, raid 10/25/40, teams) that fill in min./max. players; the points field shows the default.
  - *Goals* – a list with "+ Add goal" and a delete button per goal; the defaults of the event type are filled in.
  - A live preview shows the event as members will see it. Errors (date in the past, min. above max.) appear before anything is sent.
- **Take back a challenge:** a duel of honor that was sent or accepted can be taken back by either duelist (button in the tab, `/gem duel cancel`) as long as no winner is booked.
- **The clan / order banner now grows with its level:** cloth in the guild colours (1), the faction sigil on it (2), trophies at its foot (3), flickering flames beside it (4). Click a stage below the banner to preview it.
- **Data export for support:** `/gem export` shows everything the addon knows on this client – character, guild state, own points and the last entries, PvP counts, game statistics, last death recap and error messages – as text to copy and send (`/gem export full` with all entries). No passwords or account data.
- **"Use as template"** on every event: copies it as a new event on the same weekday and time, the next date ahead.

### Fixed
- **Guild looked "not activated" for a while after a reconnect.** Right after login or a reconnect the game returns an empty guild info text; the addon took that as "activation code removed". It now keeps the known state, reads again later and rides out a short "no guild" during loading screens.
- **Kills were lost** while the guild state was unknown: they are now kept for 15 minutes and booked as soon as the guild is active again. The kill counter is also checked after every fight and every 20 seconds, in case the game's counter could not be read during the fight or the session counter restarted after a disconnect.
- **"Today" higher than the season count in PvP Kills.** "Today" comes from the game, the other columns are the module's own counts, and kills the module missed (older versions, reconnects, crashes) never reached them. The module now compares its count of the day with the game's and adds what it missed.
- **PvP Kills counters dropped after a crash or disconnect.** The game saves addon data only on logout or /reload, so a disconnect loses the counts of that session. Other members now give a member back what the guild knew of him when he logs in, and their copies never go down.

### Module API
- API 3 / PvP API 3: `API.AddExport(id, fn)` for an own section in the export.
- Deprecated: callbacks `MAKGORA`, `MAKGORA_NEW` → `HONORDUEL`, `HONORDUEL_NEW`; `PvP.ActiveMakgoras()`, `PvP.MakgoraRecord()` → `PvP.ActiveDuels()`, `PvP.DuelRecord()`. The old names still work (removed in 1.2 at the earliest).
- Event types: `gmin`/`gmax` defaults are used by the editor; `icon` and `descKey` are shown on the type tiles.

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
