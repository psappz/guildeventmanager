# Writing modules for GuildEventManager

GuildEventManager is built from a **core** and **modules**. The core brings the event framework, points, the clan/order banner, guild achievements, plaques, the guild profile and the sync over the guild addon channel. Modules add event types, point pots, achievements, tabs and their own logic.

- The **PvP module** (`GuildEventManager_PvP`) ships in the same package as the core. It is the base for all PvP features and can be extended by **PvP modules** of its own.
- **Every other module is a separate addon** with its own folder, its own repository and its own CurseForge project. Users install only what they want.

This guide shows how to write such a module. Two working examples are in [`examples/`](../examples):

| Example | Shows |
|---|---|
| [`GuildEventManager_Example`](../examples/GuildEventManager_Example) | Event module: event type with goals, own point pot, achievement, rule, slash command, guild messages, callback, own tab |
| [`GuildEventManager_PvPDuels`](../examples/GuildEventManager_PvPDuels) | PvP module: PvP event type, a deed that gives guild honor (with rule and daily cap in the honor rules), PvP achievement, PvP callback |

---

## 1. How a module is built

A module is a normal WoW addon:

```
GuildEventManager_MyModule/
  GuildEventManager_MyModule.toc
  MyModule.lua
```

```toc
## Interface: 16001
## Title: GuildEventManager MyModule
## Dependencies: GuildEventManager
## Version: 1.0.0
## X-License: MIT

MyModule.lua
```

A **PvP module** depends on both:

```toc
## Dependencies: GuildEventManager, GuildEventManager_PvP
```

Name the folder `GuildEventManager_<Name>` so it is sorted next to the core in the addon list.

### Quick start

1. Copy `examples/GuildEventManager_Example` (or `GuildEventManager_PvPDuels` for PvP).
2. Rename the folder, the `.toc` file and the module id (`local ID = "hunt"`).
3. Replace event type, strings and logic.
4. Copy the folder into `Interface/AddOns/` and **restart the game** (new files are not loaded by `/reload`).
5. `/gem demo` shows the window with sample data; `/gem errors` shows errors of all modules.

### Publishing

- Own GitHub repository with a `.pkgmeta` (`package-as: GuildEventManager_MyModule`).
- Own CurseForge project. Under *Relations* add **GuildEventManager** as *Required Dependency*, so the CurseForge app installs the core with it.
- Tell us about your module (issue in this repository) and we add it to the list at the end.

---

## 2. Rules every module must follow

**One guild, one profile.** What a member sees depends on the settings of the guild master and the event manager rank (the *guild profile*), not on the modules installed. If a member lacks a module, its event types still appear (marked "module not installed").

**Silent until activated.** Nothing is sent before the guild master has put the activation code into the guild info. `API.Send` and `API.ReportOwn` take care of this.

**Each client reports only its own deeds.** There is no server. A client writes points only for its own character (`API.ReportOwn`, `PvP.ReportDeed`); only event managers write points for others (`API.AwardPoints`). All clients add up the same ledger and get the same numbers. Managers can strike any entry.

**WoW Forever runs on the Midnight engine.** That means for addons:
- `COMBAT_LOG_EVENT_UNFILTERED` is closed. **Registering for it raises "ADDON_ACTION_FORBIDDEN"** and the user sees a blocked-addon dialog. Use unit events, system messages, `PLAYER_PVP_KILLS_CHANGED`, `PLAYER_DEAD`, nameplates, the PvP callbacks of this API.
- Some values are *secret* in combat (`issecretvalue(v)`); check before you compare or store them.
- Some functions are blocked in combat. Example: `GetGuildInfoText` – the core reads it out of combat only.
- An addon may create only 500 timer objects. Use `API.Schedule(name, delay, fn)`; a job with the same name replaces the pending one.

**Strings.** Every visible text comes from the locale (`locales` in `RegisterModule`, at least `enUS`). Faction words use `H_`/`A_` keys and `API.Word(key)`: the Horde says *clan*, the Alliance *order*. The core and the PvP module speak `enUS`, `deDE`, `frFR`, `esES` (also for `esMX`), `itIT` and `ptBR`; missing keys fall back to `enUS`. The player can choose the addon language in *Settings → Personal*, so do not compare against `GetLocale()` for texts.

**Message budget.** The game drops addon messages silently once a client sends faster than about 10 at once and 1 per second after that. The core sends through one queue (8 at once, then one every 1.1 s) shared by all modules. Keep messages small, send on change rather than on a timer, and spread answers to `HELLO` with a random delay (`API.Schedule(name, 3 + math.random() * 10, fn)`).

**Deeds the addon cannot see** (a duel, an oath, something that happened outside the game's events): let other guild members confirm them as witnesses, as the duel of honor and the oaths of the PvP module do. The witness sends a confirmation; the doer's client books its own entry once enough confirmations arrived. Keep the confirmations and send them again when the doer comes online.

**Errors.** Wrap event handlers in `API.SafeCall("where", fn, ...)`: errors go to `/gem errors` instead of interrupting the game.

---

## 3. API reference

`GuildEventManagerAPI` (short: `API`). `API.version` is `1`. New functions raise the version; existing functions keep their behaviour. Check it with `requires = { api = 1 }`.

### Modules

| Function | |
|---|---|
| `API.RegisterModule(def)` | Registers a module. Returns `true`, or `false, reason` (API too old, PvP module missing). Call it once when your file loads. |
| `API.IsModuleLoaded(id)` | Is a module registered? |
| `API.AddLocale(code, table)` | Adds strings; `API.L.KEY` reads them in the user's language (fallback enUS). |

**Module definition**

```lua
API.RegisterModule({
  id = "pve",                    -- letters, digits, _ ; unique
  name = "PvE" | nameKey = "MOD_PVE",
  version = 1,                   -- your module's version
  requires = { api = 1, pvp = 1 },   -- optional minimum versions
  locales = { enUS = { ... }, deDE = { ... } },
  eventTypes = { ... },          -- see below
  pots = { { id = "fishing", nameKey = "POT_FISHING" } },   -- own point pots (column in the ranking)
  achievements = { ... },        -- see below
  rules = { pointsPerFish = 2 }, -- guild-wide settings with defaults, see API.GetRules
})
```

**Event type**

| Field | |
|---|---|
| `id` | unique id, e.g. `"fishing_contest"` |
| `name` / `nameKey`, `desc` / `descKey` | name and description (description is shown on the event page if the event has none) |
| `kind` | default run type: `"short"`, `"multiday"`, `"multiweek"`, `"season"` |
| `group` | default group requirement: `"none"`, `"party"`, `"raid"`, `"teams"` |
| `icon` | texture path |
| `goalKeys` | locale keys of goals suggested in the editor; each reached goal gives event points to all participants |

**Achievement** – counted from the point ledger on every client, no messages needed.

| Field | |
|---|---|
| `id`, `name`/`nameKey`, `descKey` (format with `%d` = threshold), `icon` | |
| `stat` | `"why"`: entries with `entry.why == why` (and `entry.flag == flag` if set, events of type `evtype` if set) · `"participate"` · `"lead"` · `"types"` (different event types) · `"points"` (event + honor points) · `"evtype"` (events of type `evtype` attended) |
| `n`, `pts` | threshold and achievement points |
| `scope` | `"season"` or `"forever"` |
| `honor` / `honorKey`, `honorScope` | honor name earned with it, and how long it lasts |
| `tier` | `"BRONZE"`, `"SILVER"`, `"GOLD"` (added to the name) |
| `hidden` | shown only once earned |
| `faction` | `nameKey` / `honorKey` are faction words (`H_`/`A_`) |
| `honorPrio` | this honor name wins over newer ones with a lower number (default 0; the season champion uses 10) |
| `compute` | `function(entries, events, a) return { { who = key, ts = time, note = ... } } end` – worked out by your module from all ledger entries (sorted by time, struck ones removed). For season results, streaks, anything `stat` cannot express. `a.n` is the (editable) threshold. |
| `repeatable` | with `compute`: every award counts (points each time, `×n` in the list), e.g. once per season |
| `progress` | with `compute`: `function(memberKey, a) return number end` for the progress bar |
| `meta` | `{ "achId", ... }`: earned with all of these; set `n = #meta` |

Guild event managers can change threshold, points, name, honor name and duration of every achievement in the window.

### Guild and player

| Function | Returns |
|---|---|
| `API.IsActivated()` | guild master has activated the addon |
| `API.IsManager([name])` | the player (or `name`) has event rights |
| `API.IsGuildMember(name)`, `API.MemberKey(name)` | any spelling → member key (lowercase, `nil` if not in the guild) |
| `API.PlayerKey()`, `API.DisplayName(key)`, `API.Members()` | |
| `API.GuildName()`, `API.Faction()` (`"horde"`/`"alliance"`), `API.Word(key)`, `API.Theme()` | |
| `API.SeasonStart()`, `API.SeasonEnd()`, `API.Now()` | server time |
| `API.IsDemo()` | demo mode is running (`/gem demo`) |

### Rules (guild-wide settings)

| Function | |
|---|---|
| `API.GetRules(id)` | table of your module's rules: defaults from `def.rules`, values from the guild profile |
| `API.SetRules(id, function(rules) ... end)` | event managers only; the profile gets a new version and reaches every member |

### Points

| Function | |
|---|---|
| `API.ReportOwn(pot, amount, reason, extra)` | own deed in a module pot (not `"event"`/`"ach"`). `reason` becomes `entry.why`; `extra = { note, zone, flag, ev }`. Max 100 per entry. |
| `API.AwardPoints(name, pot, amount, reason, eventId)` | event managers only, any pot, negative corrects |
| `API.GetTotals(period)` | `{ [key] = { total, pots = { pot = n } } }`, period `"week"`, `"month"`, `"season"`, `"all"` |
| `API.GetEntries(filter)` | ledger entries, newest first |

### Events

| Function | |
|---|---|
| `API.GetEvents(filter)`, `API.GetEvent(id)` | event tables: `id, type, name, desc, leader, kind, start, finish, group, status ("planned"/"running"/"done"/"cancelled"), signups, attended, goals` |
| `API.IsSigned(event, [name])` | |

### Callbacks – `API.On(name, fn)`

| Name | Arguments |
|---|---|
| `EVENT_STARTED` | `event, startedHere` |
| `EVENT_ENDED` | `event, attended` (only on the client that ended it) |
| `EVENT_CANCELLED` | `event` |
| `EVENT_UPDATED` | `event, isNew` (from the guild) |
| `POINTS_ADDED` | `entry` (own and received) |
| `ACHIEVEMENT_EARNED` | `def, time` (own character) |
| `ACTIVATED`, `PROFILE_CHANGED` | |

### Guild messages

```lua
API.Send("pve", "CATCH", { fish = 6358, size = 41 })
API.Listen("pve", "CATCH", function(data, senderKey) ... end)
```

Only in an activated guild, throttled, split when long, dropped from senders outside the guild. Values: strings, numbers, booleans, nested tables. `API.CanSend()` tells whether sending is possible.

### UI

| Function | |
|---|---|
| `API.AddTab(id, { label = fn, build = fn(panel), refresh = fn(panel) })` | own tab before *Settings*. `build` runs once, `refresh` on every update. Register when your file loads. |
| `API.Open(tab)`, `API.Refresh()` | |
| `API.Widgets` | themed widgets: `Box, Text, Button, Edit, Check, Dropdown, Scroll, Pool, Bar, Dialog, OpenMenu` (see `Widgets.lua`) |
| `API.Section(parent, text)`, `API.Pill(parent)` | heading with line, small label |
| `API.ShowPlaque(name, sub, points, icon)` | achievement plaque |
| `API.AddCommand(cmd, fn)` | `/gem <cmd> <args>` |
| `API.Print(msg)` | chat line with the addon prefix |

### Helpers

`API.Schedule(name, delay, fn)`, `API.SafeCall(where, fn, ...)`, `API.Now()`.

---

## 4. PvP modules – `GuildEventManagerAPI.PvP`

Available when `GuildEventManager_PvP` is loaded (`API.PvP.version` is `1`). Declare `requires = { api = 1, pvp = 1 }`.

| Function | |
|---|---|
| `PvP.RegisterDeed(id, def)` | A deed that gives **guild honor**. `def = { label = "won a duel against %s" \| labelKey, honor = 5, ruleLabelKey, dailyCap = 25, capLabelKey }`. The deed appears in the honor roll; its honor value (and daily cap) appear in the **honor rules** and can be changed by event managers. |
| `PvP.ReportDeed(id, extra)` | own deed: honor as set in the rules, respecting the daily cap. `extra = { note, zone, flag }`. Use `why = id` in achievements. |
| `PvP.AddRule(key, default, label, labelKey)` | an extra rule in the honor rules form |
| `PvP.GetRules()`, `PvP.SetRules(fn)` | all honor rules (built-in and from modules) |
| `PvP.On(name, fn)` | `KILL (victimName, instanceType)` – own honorable kill, `"none"` = open world, `"pvp"` = battleground · `DEATH (killerName)` · `DEBT_NEW (debt)` · `DEBT_PAID (debt, servedCold)` – `debt.how` is `"kill"`, `"target"` or `"near"` (nameplate) · `DRUM (drum)` · `DRUM_ARRIVED (drum, first)` · `MAKGORA (duel, winnerKey, loserKey)` – own won duel of honor · `MAKGORA_NEW (duel)` · `OATH_FULFILLED (oath)` |
| `PvP.Drum(level, text)` | war drum / storm bell at the own position: `"help"`, `"rally"`, `"attack"` |
| `PvP.Challenge(name, stake)`, `PvP.Swear(level, text)` | start a duel of honor (Mak'gora) / swear an oath (level 1–3), as the player would in the tab |
| `PvP.ActiveMakgoras()`, `PvP.OpenOaths()`, `PvP.MakgoraRecord(name)` | running challenges, open oaths, `wins, losses` of a member |
| `PvP.SeasonResults(n)`, `PvP.SeasonProgress()` | finished seasons of guild honor (`{ start, stop, total, top = { {key, honor} ×3 } }`, newest first); honor of the running season and the goal |
| `PvP.OpenDebts()`, `PvP.InOpenWorld()`, `PvP.PlaySignal()`, `PvP.Notice(msg)` | |

PvP event types and achievements are registered with `API.RegisterModule` like any other. Achievements on your deeds use `stat = "why", why = "<deed id>"`; achievements on guild honor use `stat = "points"`.

Built-in deeds (`entry.why`): `kill`, `debt` (flag `cold`), `drum` (flag `first`), `makgora` (`note` = loser, `ch` = challenger, `wit` = witnesses, `stake`), `oath` (`note` = the oath, flag `lvl1`–`lvl3`). Built-in PvP event types: `warband`, `defense`.

Built-in honor rules (`PvP.GetRules()`): `kill, perVictim, dailyCap, debt, debtDays, coldMin, drum, drumWindow, drumRadius, revengeChat, revengeChatMin, makgora, makgoraWitnesses, oath1, oath2, oath3, oathDays, oathWitnesses, seasonGoal`.

**Season results** come from the ledger, no messages: places 1–3 of guild honor in a finished season earn *Season Podium*, place 1 *Champion of the Clan/Order* with the honor name "Champion" for the next season, and when the guild reaches `seasonGoal` honor in a season everyone who added honor earns *Unstoppable*. These use `compute` + `repeatable` (see achievements); copy the pattern from `GuildEventManager_PvP/Season.lua` for your own rankings.

---

## 5. Testing checklist

- Load without errors with and without the PvP module (`/gem errors`).
- Members without your module: the guild still works, your event types show "module not installed".
- Not activated guild: nothing is sent (`/gem debug` shows the message log).
- Combat, battlegrounds, dungeons: no blocked-addon dialogs.
- Both factions: `/reload`, then `/gem demo alliance` before opening the window.
- `enUS` and your own language (switch the addon language in Settings → Personal, then `/reload`).
- Many messages at once (e.g. 20 members logging in): nothing gets lost (`/gem debug`).

---

## Known modules

| Module | Author | |
|---|---|---|
| GuildEventManager_PvP | psappz | ships with the core |

*Your module here – open an issue.*
