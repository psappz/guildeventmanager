# GuildEventManager

**Guild events, raids, guild honor and achievements for WoW Forever – for the whole guild, Horde and Alliance.**

GuildEventManager lets your guild plan and run its own events and raids, reminds everyone to sign up, rewards everyone who takes part, and adds it all up to one total score for the guild. The guild's own tabard becomes a banner that grows with the guild's honor.

---

## How it works

- **The guild master switches it on.** He pastes an activation code into the guild info. Until then the addon sends nothing, even if members have it installed.
- **The guild master decides who runs events:** himself and a guild rank of his choice (optionally all higher ranks too). Raids can be led by a rank of their own.
- **Everyone follows the guild profile.** Points, rules, achievement thresholds, names and active event types are set once by the guild leadership and reach every member over the guild addon channel.
- **No server, no website.** Every client keeps the same ledger and adds up the same numbers.

---

## Features

| Area | What you get |
|---|---|
| **Overview** | Banner progress, the next event, your own sign-ups, the newest bookings of all modules and your notices at a glance. A bell in the header collects notices (new events, open invitations, raid groups, sightings) |
| **Events** | RP evening, guild meeting, ritual (core) plus module types. Short, multi-day, multi-week or whole-season events, group size, lowest level, goals to tick off, reminder 10 minutes before the start |
| **Sign-ups** | Yes, Tentative, Late, Bench or No, with a comment and the event's own questions. The list of sign-ups is grouped by answer. **Invite all** puts everyone signed up into the group and turns it into a raid when needed |
| **Invitation reminder** | Members of the right level who have not answered yet get a notice and, in the week before the event, a popup: "Open GuildEventManager" leads straight to the sign-up, "Later" asks again in a few hours. Never in combat |
| **Honor book** | Every booking of every module in one list, filtered by module; event managers can strike an entry |
| **Guild banner** | Painted from the guild's own tabard – colours and emblem as in the game, pole and style per faction. Four levels from the guild's points of the last four weeks: Horde *Forged · Tempered · Feared · Legendary*, Alliance *Armed · Proven · Celebrated · Legendary*. Member ranking by week, season or all time |
| **My achievements** | Thresholds, points, honor names and their duration (season or forever) – all adjustable. Hidden and bronze/silver/gold achievements, shown as plaques in the style of the Wrath of the Lich King toasts |
| **Languages** | English, Deutsch, Français, Español, Italiano, Português – the addon language can differ from the client language |
| **Faction look** | Horde: clan, Orgrimmar colours, war drum. Alliance: order, Stormwind colours, storm bell. Same mechanics for both |

## Raids – PvE module (included)

- **Raid events** for The Barrow Deeps (10), Hyjal Summit (20) and Onyxia's Lair (40), with their bosses
- **Sign-up with role and second role** – only roles the class can play. The raid lead can change a member's role per raid
- **Specs read from the talents:** the tree with the most points is shown automatically, or each member picks his spec by hand. Dual spec is supported
- **Line-up with drag & drop:** groups, tanks on top, "Fill groups", boss setups for second roles
- **Buffs, debuffs and utility** of the line-up, raid-wide and per group, with hints for what is missing
- **Raid night:** invite all, sort the raid into the planned groups, readiness per member (online, addon, lockout, Drakefire Amulet), text for Discord
- **Raid-Helper import:** paste the event JSON, Discord names are matched to characters once and remembered

## PvP module (included)

- **Guild honor** for honorable kills in the open world, with daily limits
- **Blood debt / debt of honor:** whoever kills you becomes your debt – take revenge within 7 days
- **Bounties:** put honor on the head of an enemy player; whoever of the guild kills him first collects it
- **Target alarm:** an enemy with a bounty, your blood debt, an oath naming him or on your watch list comes into sight – target him with one click or call the guild with a map waypoint
- **War drums / storm bells:** call the guild to your position (help, rally, attack) with a map waypoint; whoever arrives in time gets honor
- **Warband and defense** event types with goals
- **Duel of honor:** challenge a guild member with a stake; a named witness confirms the winner. A normal duel – nobody dies
- **Oaths:** swear a small, great or mighty oath – witnesses confirm it was kept
- **Season results:** podium of guild honor, the season champion carries the honor name "Champion", and the whole guild earns *Unstoppable* when it reaches the season goal
- **PvP Kills:** honorable kills of every member (season and total, open world and battlegrounds), PvP rank and the game's own statistics

All values are defaults and can be changed in the settings.

---

## Commands

- `/gem` – main window
- `/gem raid` – raids · `/gem raid yes|tentative|late|bench|no` – answer for the next raid · `/gem raid import`
- `/gem drum help|rally|attack [text]` – war drum / storm bell
- `/gem bounty <enemy> <honor>` – put a bounty on an enemy · `/gem watch <name>` – watch list
- `/gem duel <opponent> <witness> [stake]`, `/gem witness` – duel of honor
- `/gem oath [1|2|3] <text>` – swear an oath
- `/gem status`, `/gem minimap`, `/gem probe`, `/gem errors`

**Write your own module:** the API is documented on GitHub (link "Source").

Part of the Manager family with ConfigManager, LegacyManager, RecipeManager and DungeonManager.
