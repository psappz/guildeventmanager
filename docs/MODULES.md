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

`GuildEventManagerAPI` (short: `API`). `API.version` is `7`. New functions raise the version; existing functions keep their behaviour. Declare the lowest version that has everything you use (see [section 6](#6-api-changes)), e.g. `requires = { api = 1 }` keeps your module working with older cores.

### API 7 (GuildEventManager 0.9) – what is new for modules

Everything below needs `requires = { api = 7 }`. The working example for an outside module is **GuildEventManager_Fishing**: it uses only the public API (no `API.core`).

**Module definition – new fields**

```lua
API.RegisterModule({
  id = "mymod", nameKey = "MY_MOD", version = 1, requires = { api = 7 },
  addon = "GuildEventManager_MyModule",          -- folder name: version check and "newer version in the guild"
  about = { descKey, points = { keys }, get = "CurseForge: GuildEventManager MyModule" },  -- info card for the guild
  areas = { "pvp", "pve" },                       -- event types with `area` stay locked until the guild master unlocks them
  eventTypes = { ... },
  guildAchievements = { ... },                    -- see below
  rules = { ... },                                -- guild-wide defaults (API.GetRules / API.SetRules)
})
```

**Modules of the guild.** A module counts as part of the guild as soon as the guild master or an event manager has it installed: his client writes it into the guild profile with name, description and where to get it. Members without the module get one notice and may say "not interested". `API.ModuleKnown(id)`, `API.IsInterested(id)`.

**Event types – new fields**

| Field | |
|---|---|
| `settings = { { id, kind, labelKey, default, min, max, options, showIf = fn(values) } }` | Settings of the event leader per event (kinds `choice`, `multi`, `number`, `check`, `text`, `time`, `date`); `options` may be a function. Read them with `API.EventSettings(e)` (defaults filled in). |
| `canSignUp(e, key) -> ok, reason, hints` | Third return value: yellow hints instead of a block. |
| `rules = fn(e) -> { { icon, title, text } }` | "How it works" cards in the event and under "?". |
| `reminders = { { before = seconds, textKey, checklist = { keys } } }` | Own reminders with a checklist. |
| `repeatDefault = { every = "week" }` | Recurring events: the editor starts with this. |
| `contest = { rank, ties, places, target, window, format, goal }` | Contest with live standings (below). |
| `group = "teams"` | Teams tab in the event (below). |
| `area = "pvp" \| "pve"` | Locked until the guild master unlocks the area of the module (0.9). |
| `holiday = "id"` | Can be created only from `lead` days before the holiday until its end (0.9). |

**Contests.** `contest = { rank = "high"|"low", ties = "shared"|"first", places = { p1, p2, p3 } | fn(e), target = n | fn(e), window = fn(e) -> from, to, format = fn(v) }`. Every client writes only its own score: `API.SetScore(e, v)`, `API.AddScore(e, d)`; `API.Standings(e)` → `{ { key, value, at, place, bonus } }`. Counting ends at the end of the window, when someone reaches `target` (scores reached later are ignored), or with `API.EndContest(e, reason)`. The event leader sends the final result (referee); `API.SuggestBonus(e, name, points, reasonKey)` proposes extra GP. `API.ContestRunning(e)`, `API.ContestEnded(e)`, `API.ShowStandings(e)`.
- **Shared goal:** `contest.goal = { target, reward, groupBonus }` – everybody counts towards one target; reached: every participant gets `reward`, the best group (teams, else raids, else groups 1–8) `groupBonus`. `API.ContestTotal(e)`, `API.ContestGroups(e)`, `API.GoalReached(e)`.
- **Report end:** a participant reports an end his client may have missed (`API.ReportEnd(e, reason)`); counting stops for everyone until the leader confirms (`API.ConfirmEnd(e)`) or lets it go on (`API.ResumeContest(e)`). `API.EndPending(e)`.

**Teams.** `API.Teams(e)`, `API.TeamOf(e, name)`, `API.TeamStandings(e)` (sum of the members), `API.ShowTeams(e)`. Callback `TEAMS_CHANGED`.

**Game watcher.** `API.OnGame(kind, fn, moduleId) -> handle`, `API.OffGame(handle)`. The core registers game events only while somebody listens, drops duplicates and checks every value WoW Forever may hide (secret values arrive as `nil`, never as an error).

| Kind | `fn(x)` gets |
|---|---|
| `fishloot` | `{ item, qty, name, zone, sub, map, at }` one per item of a fishing loot |
| `loot` | `{ item, qty, name, fishing, pushed, zone, map, at }` (from the own loot chat line) |
| `itemcount` | `{ item, count, prev, at }` for items watched with `API.WatchItem(id)` |
| `questdone` | `{ id, xp, money, at }` |
| `npcsay` | `{ npc, text, chat = "yell"\|"say"\|"emote"\|"boss", zone, map, at }` |
| `system` | `{ text, at }` |
| `pvpkill` | `{ victim, zone, map, at }` honorable kill (victim nil if unreadable) |
| `zone` | `{ zone, sub, map, at }` |
| `spellcast` | `{ spell, target, zone, map, at }` own successful cast, `target` = the name it was aimed at (0.9) |

Helpers: `API.ItemCount(id)`, `API.ZoneIs(mapId or name)`, `API.MapID()`.

**Guild achievements.** `guildAchievements = { { id, nameKey, descKey, icon, tiers = { bronze, silver, gold [, legendary] }, stat = fn(ctx, def, from, to) -> { { ts, add, who } } } }`. `ctx.events` holds the finished events (`{ id, ts, type, att = { person = true }, n, leaders, ev }`). Every step earns a trophy. `API.GuildAchievements()`, `API.GuildProgress(id)`, `API.Trophies()`, callback `GUILD_ACHIEVEMENT_EARNED`.

**Person instead of character.** A member's main and twinks are one person: `API.MainOf(key)`, `API.Person(key)` → `{ main, chars, source }`, callback `PERSONS_CHANGED`. Count per person.

**Areas (0.9).** `areas = { "pvp", "pve" }` on the module, `area = "pvp"` on an event type. The guild master installs the whole module and unlocks the areas he wants (Settings → Modules); types without area are always open. `API.Areas(moduleId)`, `API.AreaUnlocked(moduleId, area)`, `API.SetAreaUnlocked(moduleId, area, on)` (guild master only), `API.TypeOpen(typeId)`. Only creating is checked – events that arrive from others stay valid.

**Holidays (0.9).** `API.AddHoliday({ id, nameKey, from = { month, day }, to = { month, day }, lead = 14, icon })` in realm time (`to` may lie in the next year). `API.Holiday(id)` → `{ id, name, start, finish, active, soon, days, moved }` of the current or next occurrence, `API.HolidayActive(id)`, `API.SetHolidayDates(id, from, to)` (managers; `nil, nil` = back to the module's dates), `API.RealmTime(y, m, d, h, mi)`.

**Members (0.9).** `API.MemberInfo(name)` → `{ key, name, rank, rankIndex, level, class, online, offDays }`, `API.RankNames()`, `API.IsGuildMaster()`, `API.IsLeadership(name)` (guild master plus the ranks of the function "lead"), `API.IsBankChar(name)`, `API.OpenInGuild(name)` (Blizzard's guild window with the member – addons cannot set ranks on Forever).

**More helpers.** `API.Storage(id)` / `API.CharStorage(id)` (saved per account / per character), `API.FloatingWindow(id, opts)`, `API.MemberLevel(name)`, `API.ServerClock()`, `API.NextServerTime(weekday, "HH:MM")`, `API.FormatTime(ts, style)`, `API.SendOfficer(id, kind, data)` (only ranks that may read the officer chat), `API.Alert(text, opts)`, `API.AlertGuild`, `API.AlertEvent`, `API.OpenEvent(e, tab)`, `API.NewEvent(typeId, fields)`, `API.EventSettings(e)`, `API.AddHelp(viewId, fn)`.


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
| `gmin`, `gmax` | optional default player numbers; the editor picks the matching group size (e.g. `group = "raid", gmax = 25` → "Raid (25)") |
| `remind` | `true`: the editor's checkbox "Remind members to sign up" starts ticked (the PvE raids do this). Members of the right level who have not answered get a notice and, in the week before the event, a popup. |
| `canSignUp` | optional `function(e, key) -> ok, reason`: may this character sign up (declining is always allowed)? The PvE raids use it for the early sign-up below the raid level. |
| `pointsFactor` | optional `function(e, key) -> number`: multiplies the points for taking part when the event ends (the PvE raids: early sign-ups × levels a day). Every sign-up carries `lv`, the lowest level the character signed up with. |
| `signupFields` per event | events can carry their own questions (`e.fields`, created in the event editor): `{ id = "q1", kind = "choice"|"number"|"text", label, options, required, yn }`. They are cleaned on receipt (`Events.CleanFields`). |
| `minLevel` | optional default for the event's lowest level (number or function); only members of that level are asked to sign up. The manager can change it in the editor. The PvE raids use the highest player level. |
| `icon` | texture path – shown on the type tile in the event editor, so choose a clear one |
| `goalKeys` | locale keys of goals suggested in the editor; each reached goal gives event points to all participants |

In the event editor every active type is a tile (icon + name, description as tooltip and below the tiles). Keep `name` short (two lines of about 18 characters) and write `desc` as one or two sentences that tell a manager when to pick this type. Picking a type also sets its default duration and group size for a new event.

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
| `API.GetEvents(filter)`, `API.GetEvent(id)` | event tables: `id, type, name, desc, leader, kind, start, finish, group, lvl (lowest level, nil = all), status ("planned"/"running"/"done"/"cancelled"), signups, attended, goals` |
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
| `WINDOW_OPENED` | the player opens the GuildEventManager window (not on tab changes). API 4 |

### Guild messages

```lua
API.Send("pve", "CATCH", { fish = 6358, size = 41 })
API.Listen("pve", "CATCH", function(data, senderKey) ... end)
```

Only in an activated guild, throttled, split when long, dropped from senders outside the guild. Values: strings, numbers, booleans, nested tables. `API.CanSend()` tells whether sending is possible.

### UI

| Function | |
|---|---|
| `API.AddModule(id, { label = fn, icon, order, badge = fn, tabs = { { id, label = fn, build = fn(panel), refresh = fn(panel) }, ... } })` | an entry in the side bar (group "Modules") with sub tabs. `build` runs once per tab, `refresh` on every update. `badge` returns a short text (a count) or nil. API 5 |
| `API.AddTab(id, { label = fn, build, refresh, parent = "entryId" })` | one more tab: with `parent` as a sub tab of a module entry, without it as an entry of its own (API 1 behaviour). |
| `API.AddSettingsPage(id, { label = fn, build, refresh })` | a page behind the gear (the module's rules or options). API 5 |
| `API.AddHelp(id, fn)` | help text for a view or a side bar entry, shown under the "?" in the header: `fn()` returns `title, text`. A view without its own text uses its entry's. 0.8.0 |
| `API.AddNotice({ key, group, text, view = "tabId" or ev = eventId or open = fn })`, `API.RemoveNotice(key)` | a notice behind the bell (one per `key`, kept 7 days). API 5 |
| `API.AddLedgerFormat(id, { label = fn, match = fn(entry), text = fn(entry) })` | how your entries read in the honor book and which module tag they get. API 5 |
| `API.AddProbe(id, fn)` | a check for `/gem probe`: `fn()` returns `{ { label, value }, ... }` – use it for client functions you are not sure about. API 5 |
| `API.Open(tab)`, `API.Refresh()` | |
| `API.Widgets` | themed widgets: `Box, Text, Button, Edit, Check, Dropdown, Scroll, Pool, Bar, Dialog, OpenMenu` (see `Widgets.lua`) |
| `API.Section(parent, text)`, `API.Pill(parent)` | heading with line, small label |
| `API.ShowPlaque(name, sub, points, icon)` | achievement plaque |
| `API.AddCommand(cmd, fn)` | `/gem <cmd> <args>` |
| `API.AddExport(id, fn)` | own section in the support export (`/gem export`): `fn(full)` returns a list of text lines. Players copy the export and send it to their guild master; list what helps to find a problem (your counters, settings, last errors), never anything private. API 3 |
| `API.Print(msg)` | chat line with the addon prefix |

### Helpers

`API.Schedule(name, delay, fn)`, `API.SafeCall(where, fn, ...)`, `API.Now()`.

---

## 4. PvP modules – `GuildEventManagerAPI.PvP`

Available when `GuildEventManager_PvP` is loaded (`API.PvP.version` is `4`). Declare `requires = { api = 1, pvp = 1 }`, `pvp = 2` if you use duels of honor, oaths or season results, `pvp = 3` for the new names `ActiveDuels`, `DuelRecord` and `HONORDUEL`.

| Function | |
|---|---|
| `PvP.RegisterDeed(id, def)` | A deed that gives **guild honor**. `def = { label = "won a duel against %s" \| labelKey, honor = 5, ruleLabelKey, dailyCap = 25, capLabelKey }`. The deed appears in the honor roll; its honor value (and daily cap) appear in the **honor rules** and can be changed by event managers. |
| `PvP.ReportDeed(id, extra)` | own deed: honor as set in the rules, respecting the daily cap. `extra = { note, zone, flag }`. Use `why = id` in achievements. |
| `PvP.AddRule(key, default, label, labelKey)` | an extra rule in the honor rules form |
| `PvP.GetRules()`, `PvP.SetRules(fn)` | all honor rules (built-in and from modules) |
| `PvP.On(name, fn)` | `KILL (victimName, instanceType)` – own honorable kill, `"none"` = open world, `"pvp"` = battleground · `DEATH (killerName)` · `DEBT_NEW (debt)` · `DEBT_PAID (debt, servedCold)` – `debt.how` is `"kill"`, `"target"` or `"near"` (nameplate) · `DRUM (drum)` · `DRUM_ARRIVED (drum, first)` · `HONORDUEL (duel, winnerKey, loserKey)` – own won duel of honor · `HONORDUEL_NEW (duel)` · `OATH_FULFILLED (oath)` |
| `PvP.Drum(level, text)` | war drum / storm bell at the own position: `"help"`, `"rally"`, `"attack"` |
| `PvP.Challenge(name, witness, stake)`, `PvP.Swear(level, text)` | start a duel of honor (the named witness alone confirms the winner; PvP API 4) / swear an oath (level 1–3), as the player would in the tab |
| `PvP.ActiveDuels()`, `PvP.OpenOaths()`, `PvP.DuelRecord(name)` | running challenges, open oaths, `wins, losses` of a member |
| `PvP.SeasonResults(n)`, `PvP.SeasonProgress()` | finished seasons of guild honor (`{ start, stop, total, top = { {key, honor} ×3 } }`, newest first); honor of the running season and the goal |
| `PvP.OpenDebts()`, `PvP.InOpenWorld()`, `PvP.PlaySignal()`, `PvP.Notice(msg)` | |

PvP event types and achievements are registered with `API.RegisterModule` like any other. Achievements on your deeds use `stat = "why", why = "<deed id>"`; achievements on guild honor use `stat = "points"`.

Built-in deeds (`entry.why`): `kill`, `debt` (flag `cold`), `drum` (flag `first`), `makgora` (`note` = loser, `ch` = challenger, `wit` = witnesses, `stake`), `oath` (`note` = the oath, flag `lvl1`–`lvl3`). Built-in PvP event types: `warband`, `defense`.

Built-in honor rules (`PvP.GetRules()`): `kill, perVictim, dailyCap, debt, debtDays, coldMin, drum, drumWindow, drumRadius, revengeChat, revengeChatMin, makgora, makgoraWitnesses, oath1, oath2, oath3, oathDays, oathWitnesses, seasonGoal`.

**Duels of honor** are normal duels – nobody dies. Never call them "Mak'gora" in your texts: in WoW Hardcore that word means a duel to the death.

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

## 6. API changes

Every change to `GuildEventManagerAPI` and `GuildEventManagerAPI.PvP`, newest first. Declare the version you need in `requires`; a core or PvP module that is too old refuses your module with a message to the player instead of an error.

**Compatibility promise.** From GuildEventManager 1.0 on:
- Within one API version nothing changes behaviour. New things raise the version (`api = 3`, `pvp = 3`, ...); nothing is removed or renamed in place.
- Something that has to go is marked **deprecated** here first and keeps working for at least one more minor release of the core (e.g. 1.1 → removed in 1.2 at the earliest).
- Ledger entries, achievement ids and message kinds of a released module are never reused with another meaning: old entries in the guild ledger stay readable.
- Before 1.0 (0.x betas) the same rules apply as far as possible; breaking changes, if unavoidable, are listed here with a migration note.

### API 7 · PvP API 4 – 0.9.0

- **Modules of the guild:** catalogue in the guild profile, info card, "not interested", version notices; module fields `addon`, `about`.
- **Event types:** `settings` (event leader settings, `API.EventSettings`), third return value of `canSignUp` (hints), `rules`, `reminders`, `repeatDefault`, `contest` (with `goal`), `group = "teams"`, `area`, `holiday`.
- **Contests, teams, report end, shared goal:** see *API 7* in section 3.
- **Game watcher:** `API.OnGame` with the kinds `fishloot`, `loot`, `itemcount`, `questdone`, `npcsay`, `system`, `pvpkill`, `zone`, `spellcast`; `API.WatchItem`, `API.ItemCount`, `API.ZoneIs`, `API.MapID`.
- **Guild achievements of modules** (`guildAchievements`) and trophies; `API.GuildAchievements`, `API.GuildProgress`, `API.Trophies`.
- **Person instead of character:** `API.MainOf`, `API.Person`, callback `PERSONS_CHANGED`. GP, rankings and achievements count per person.
- **Areas and holidays:** `areas`, `API.AreaUnlocked`, `API.SetAreaUnlocked`, `API.TypeOpen`; `API.AddHoliday`, `API.Holiday`, `API.HolidayActive`, `API.SetHolidayDates`, `API.RealmTime`.
- **Members:** `API.MemberInfo`, `API.RankNames`, `API.IsGuildMaster`, `API.IsLeadership`, `API.IsBankChar`, `API.OpenInGuild`.
- **Storage and helpers:** `API.Storage`, `API.CharStorage`, `API.FloatingWindow`, `API.MemberLevel`, `API.ServerClock`, `API.NextServerTime`, `API.FormatTime`, `API.SendOfficer`, `API.Alert*`, `API.OpenEvent`, `API.NewEvent`.
- **Contests:** a score reached after counting ended is ignored when it arrives (places 2 and 3 stand as at the moment of the win).
- **Profile:** the module areas (`areas`) are guild master only, like the ranks with event rights.

### API 6 · PvP API 4 – 0.8.0

- **Event types:** `minLevel` (default lowest level, number or function), `remind` (the editor's reminder checkbox starts ticked), `canSignUp(e, key) -> ok, reason` (may this character say yes; declining is always allowed), `pointsFactor(e, key) -> number` (multiplies the points for taking part). See *Event types* in section 3.
- **Events:** every event carries `lvl` (lowest level; only those characters are reminded) and `remind`. Members who have not answered get a notice and, in the week before, a popup. Events can carry their own questions (`e.fields`, made in the editor), cleaned on receipt.
- **Sign-ups:** every sign-up carries `lv`, the lowest level the character signed up with.
- **Help:** `API.AddHelp(id, fn)` – text for the "?" in the header.
- **Security:** guild messages from senders who are not in the guild roster are ignored on every channel.

### API 5 · PvP API 4 – 0.7.0

- **Window:** side bar with entries and sub tabs. `API.AddModule`, `API.AddSettingsPage`, `API.AddTab` with `parent`, `API.AddNotice` / `API.RemoveNotice`, `API.AddLedgerFormat`, `API.AddProbe` (see *UI*). Tabs registered with `API.AddTab` without `parent` keep working as own entries.
- **Sign-ups:** a sign-up now has a state – `"in"` (yes), `"tent"` (tentative), `"late"`, `"bench"`, `"out"` (no) –, a comment and answers. `API.SignupStatus(e, name)`, `API.GetSignups(e)` → `{ { key, st, c, f, t } }` by time, `API.SetSignup(e, { st, c, f })`, `API.InviteAll(e)`. `API.IsSigned` is true for yes and late. Callback `SIGNUP_CHANGED (e, key, signup)`.
- **Sign-up fields:** an event type asks its own questions with `signupFields = { { id, kind, label|labelKey, short, options, required, default (value or fn(e)), min, max, validate = fn(v) -> error text, get = fn(e) (kind "auto"), format = fn(v), hidden, leadOnly } }`. Kinds: `auto` (read from the game when signing up), `choice`, `multi`, `number`, `check`, `text` (60 characters). Options are `{ value, labelKey }` pairs or plain values.
- **Rights per event type:** `canCreate = function(key) return true/false end` in an event type lets more members than the event managers create and run events of that type (the PvE module uses it for the raid rank). `API.CanCreate(typeId, name)`, `API.CanManage(e, name)`. Points are still booked by event managers only.
- `API.CreateEvent(fields)`, `API.SaveEvent(e)`. Fields of a module on the event (for example `e.pve`) travel with the event.
- The guild roster has the class of every member (`class`, the English file name such as `"PRIEST"`).

### API 4 · PvP API 4 – 0.7.0 (development steps, released together with API 5)

Core (`api = 4`):
- Callback `WINDOW_OPENED` when the player opens the window.

PvP (`pvp = 4`):
- **Breaking:** `PvP.Challenge(name, witness, stake)` – a duel of honor needs a named witness, a guild member other than the two duelists. Only that witness can confirm the winner; votes of anyone else are ignored, and the system-chat prompt after the duel appears only for them. Migration: pass the witness as the second argument; the old call `PvP.Challenge(name, stake)` now treats the stake as the witness name and fails with a message to the player.
- Duel records (`PvP.ActiveDuels()`) carry `w`, the witness key. Duels sent by 0.6.0 clients have no `w`; for them the old rule (`makgoraWitnesses` votes from anyone) still applies, but newer clients offer no witness buttons for them.
- The `MAKG` message carries `w`.
- Bounties: `PvP.OpenBounties()`, `PvP.WonBounties()`, `PvP.BountyOn(name)` (honor sum, count), `PvP.PostBounty(name, honor)`; callbacks `PVP_BOUNTY_NEW(b)` and `PVP_BOUNTY_WON(b)`. A bounty is paid in advance: the poster books a minus for himself (ledger `why = "bounty"`, `flag = "set"`), the collector the plus (`flag = "won"`), back-bookings use `flag = "back" | "exp" | "dup" | "late"`.

Core (`api = 4`), ledger:
- `Pts.SELF_NEG`: why-codes for which a member may book a minus for himself (`bounty`). Clients before API 4 ignore such entries, so their totals miss the advance payment.

### API 3 · PvP API 3 – GuildEventManager 0.6.0

Core (`api = 3`):
- `API.AddExport(id, fn)`: own section in the support export `/gem export`.
- Event types: `gmin`/`gmax` defaults are used by the new event editor; `icon` and `descKey` appear on the type tiles.

PvP (`pvp = 3`):
- `PvP.ActiveDuels()`, `PvP.DuelRecord(name)`, callbacks `HONORDUEL`, `HONORDUEL_NEW` – new names for the Mak'gora ones, which are deprecated (see below).
- Duel challenges can be taken back (`MAKGDEL` message); a taken-back duel never fires `HONORDUEL`.

### API 2 · PvP API 2 – GuildEventManager 0.5.0 (2026-11-13)

Core (`api = 2`):
- Achievements can be worked out by the module: `compute = function(entries, events, a)`, with `repeatable`, `progress` (see the achievement table in section 3).
- Meta achievements: `meta = { ids }`, `n = #meta`.
- `honorPrio` decides between several honor names of one member.
- Locales `frFR`, `esES` (also used for `esMX`), `itIT`, `ptBR` in the core; `API.AddLocale` accepts them. `ptPT` falls back to `ptBR`, `enGB` to `enUS`.
- Behaviour, not interface: all guild messages leave through one throttled queue (8 at once, then one every 1.1 s). Modules that sent many messages at once now see them arrive with a delay instead of getting lost.
- Behaviour, not interface: the guild profile stores only changes of achievements (`achOv`). Modules never read the profile directly, so nothing changes for them; use `API.GetRules` / `API.SetRules` as before.

PvP (`pvp = 2`):
- `PvP.Challenge(name, stake)`, `PvP.Swear(level, text)`, `PvP.ActiveDuels()`, `PvP.OpenOaths()`, `PvP.DuelRecord(name)`.
- `PvP.SeasonResults(n)`, `PvP.SeasonProgress()`.
- Callbacks `HONORDUEL (duel, winnerKey, loserKey)`, `HONORDUEL_NEW (duel)`, `OATH_FULFILLED (oath)`.
- `DEBT_PAID`: the debt now carries `debt.how` (`"kill"`, `"target"`, `"near"`).
- New built-in deeds `makgora` and `oath`, new honor rules `makgora, makgoraWitnesses, oath1, oath2, oath3, oathDays, oathWitnesses, seasonGoal`.
- New built-in achievements (ids): `makgora1`–`makgora3`, `challenger`, `unbeaten`, `oath1`–`oath3`, `podium`, `champion`, `unstoppable`, `sword`.

### API 1 · PvP API 1 – GuildEventManager 0.4.0 (2026-11-07)

First public module interface.
- Core: `RegisterModule` (event types, pots, achievements, rules, locales, `requires`), guild and player functions, `GetRules`/`SetRules`, `ReportOwn`, `AwardPoints`, `GetTotals`, `GetEntries`, events, callbacks (`EVENT_*`, `POINTS_ADDED`, `ACHIEVEMENT_EARNED`, `ACTIVATED`, `PROFILE_CHANGED`), `Send`/`Listen`/`CanSend`, UI (`AddTab`, `Widgets`, `Section`, `Pill`, `ShowPlaque`, `AddCommand`), helpers.
- PvP: `RegisterDeed`, `ReportDeed`, `AddRule`, `GetRules`/`SetRules`, callbacks `KILL`, `DEATH`, `DEBT_NEW`, `DEBT_PAID`, `DRUM`, `DRUM_ARRIVED`, `Drum`, `OpenDebts`, `InOpenWorld`, `PlaySignal`, `Notice`.

### Deprecated

| Old name | Use instead | Since | Removed |
|---|---|---|---|
| callbacks `MAKGORA`, `MAKGORA_NEW` | `HONORDUEL`, `HONORDUEL_NEW` | 0.6.0 | 1.2 at the earliest |
| `PvP.ActiveMakgoras()`, `PvP.MakgoraRecord()` | `PvP.ActiveDuels()`, `PvP.DuelRecord()` | 0.6.0 | 1.2 at the earliest |

Why: "Mak'gora" means a duel to the death in WoW Hardcore. Our duel of honor is a normal duel, so the name is gone from everything players see. The internal ids (`why = "makgora"`, achievement ids `makgora1`–`3`, rules `makgora`, `makgoraWitnesses`) stay, so existing ledger entries keep working.

---

## Known modules


- **GuildEventManager_PvE** (in the package): raids. `GuildEventManagerAPI.pve` gives `Player(e, key, boss)`, `Lineup(e, boss)`, `Group(e, g, boss)`, `Coverage(e, boss)`, `Spec(key)`, `ExportText(e)` for modules that build on raids.

| Module | Author | |
|---|---|---|
| GuildEventManager_PvP | psappz | ships with the core |
| GuildEventManager_Fishing | psappz | fishing contests: guild scoring at the Stranglethorn tournament, own contest, PvP teams, Anglergeddon – the example of a module built only on the public API |
| GuildEventManager_Holidays | psappz | Winter Veil, Lunar Festival, Love is in the Air, with PvP/PvE areas |
| GuildEventManager_Management | psappz | member files, activity, promotion suggestions, voluntary details |
| GuildEventManager_Marketplace | psappz | book of professions, guild stock (guild bank, bank characters) |

*Your module here – open an issue.*
