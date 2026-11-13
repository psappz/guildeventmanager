# GuildEventManager

**Guild events, guild honor and guild achievements for WoW Forever – for the whole guild, Horde and Alliance.**

GuildEventManager lets your guild plan and run its own events, rewards everyone who takes part, and adds it all up to one total score for the guild. Achievements appear as plaques in the style of the Wrath of the Lich King achievement toasts.

---

## How it works

- **The guild master switches it on.** He pastes an activation code into the guild info. Until then the addon sends nothing, even if members have it installed.
- **The guild master decides who runs events:** himself and a guild rank of his choice (optionally all higher ranks too).
- **Everyone follows the guild profile.** Points, rules, achievement thresholds, names and active event types are set once by the guild leadership and reach every member over the guild addon channel.
- **No server, no website.** Every client keeps the same ledger and adds up the same numbers.

---

## Features

| Area | What you get |
|---|---|
| **Events** | RP evening, guild meeting, ritual (core) plus module types. Short, multi-day, multi-week or whole-season events, group requirement, sign-ups, reminders 10 minutes before the start, goals to tick off |
| **Points** | Event points for taking part, organising and reaching goals. Pots are weighted and add up to one guild score |
| **Clan / order banner** | Four banner levels from the guild's points of the last four weeks, member ranking by week, season or all time |
| **Achievements** | Guild achievements with thresholds, points, honor names and their duration (season or forever) – all adjustable. Hidden and bronze/silver/gold achievements |
| **Languages** | English, Deutsch, Français, Español, Italiano, Português – the addon language can differ from the client language |
| **Faction look** | Horde: clan, Orgrimmar colours, war drum. Alliance: order, Stormwind colours, storm bell. Same mechanics for both |

## PvP module (included)

- **Guild honor** for honorable kills in the open world, with daily limits
- **Blood debt / debt of honor:** whoever kills you becomes your debt – take revenge within 7 days
- **War drums / storm bells:** call the guild to your position (help, rally, attack) with a map waypoint; whoever arrives in time gets honor
- **Warband and defense** event types with goals
- **Honor roll** of the guild; event managers can strike a deed
- **Duel of honor:** challenge a guild member with a stake; a witness confirms the winner, once a week per pair. A normal duel – nobody dies
- **Oaths:** swear a small, great or mighty oath – two witnesses confirm it was kept
- **Season results:** podium of guild honor, the season champion carries the honor name "Champion", and the whole guild earns *Unstoppable* when it reaches the season goal
- **PvP Kills tab:** honorable kills of every member (season and total, open world and battlegrounds), PvP rank and the game's own statistics

All values are defaults and can be changed in the settings.

---

## Commands

- `/gem` – main window
- `/gem drum help|rally|attack [text]` – war drum / storm bell
- `/gem duel <name> [stake]`, `/gem witness <winner>` – duel of honor
- `/gem oath [1|2|3] <text>` – swear an oath
- `/gem status`, `/gem minimap`, `/gem errors`

Part of the Manager family with ConfigManager, LegacyManager, RecipeManager and DungeonManager.
