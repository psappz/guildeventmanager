local ADDON, ns = ...
-- GuildEventManagerAPI: the public interface for modules.
-- Documentation with examples: docs/MODULES.md
-- Everything a module needs is here; anything else in the core may change
-- between versions. API.version rises only when something is added; existing
-- functions keep their behaviour.
local U, G, T = ns.U, ns.Guild, ns.Theme

local API = {}
GuildEventManagerAPI = API

API.version = 7   -- see docs/MODULES.md, section 6 (API changes)
API.coreVersion = ns.VERSION

local function moduleId(id)
  if type(id) ~= "string" or not id:match("^[%w_]+$") then error("GuildEventManagerAPI: module id must be letters, digits or _", 3) end
  return id
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
-- def = {
--   id = "pve", name = "PvE" | nameKey = "MOD_PVE", version = 1,
--   requires = { api = 1, pvp = 1 },          -- optional minimum versions
--   eventTypes = { { id, name|nameKey, desc|descKey, kind, group, icon, goalKeys|goals, color, open } },
--   pots = { { id, name|nameKey } },
--   achievements = { { id, name|nameKey, stat, why, flag, evtype, n, pts, scope, honor, honorScope, hidden, tier, icon, descKey } },
--   rules = { key = default, ... },           -- guild-wide settings, see GetRules
--   locales = { enUS = { KEY = "..." }, deDE = { ... } },
--   addon = "GuildEventManager_Fishing",      -- API 7: folder name, for the version check
--   about = { descKey, points = { keys }, get = "CurseForge: ..." },  -- API 7: info card for the guild
--   areas = { "pvp", "pve" },                 -- 0.9: event types with `area = "pvp"` stay locked until
--                                             -- the guild master unlocks the area (Settings > Modules)
-- }
-- Returns true, or false and a reason.
function API.RegisterModule(def)
  if type(def) ~= "table" then return false, "no definition" end
  moduleId(def.id)
  local req = def.requires or {}
  if (req.api or 1) > API.version then
    U.Print(ns.L.API_TOO_OLD:format(def.name or def.id, req.api, API.version))
    return false, "api"
  end
  if req.pvp and not (API.PvP and API.PvP.version >= req.pvp) then
    U.Print(ns.L.API_NEEDS_PVP:format(def.name or def.id))
    return false, "pvp"
  end
  for code, tbl in pairs(def.locales or {}) do ns.AddLocale(code, tbl) end
  return ns.Modules.Register(def)
end

function API.IsModuleLoaded(id) return ns.Modules.Installed(id) end

-- Strings: API.AddLocale("deDE", { MY_KEY = "..." }); API.L.MY_KEY
function API.AddLocale(code, tbl) ns.AddLocale(code, tbl) end
API.L = ns.L

---------------------------------------------------------------------------
-- Guild and player
---------------------------------------------------------------------------
function API.IsActivated() return G.IsActivated() end
function API.IsGuildMaster() return G.IsLeader() end   -- 0.9 ("view as rank" counts)
function API.IsManager(name) return G.IsManager(name and G.Resolve(name) or nil) end
function API.IsGuildMember(name) return G.Resolve(name) ~= nil end
function API.PlayerKey() return G.MyKey() end
function API.MemberKey(name) return G.Resolve(name) end      -- any spelling -> member key (nil if not in the guild)
function API.DisplayName(key) return G.Display(key) end
function API.GuildName() return G.Name() end
function API.Members() return G.Members() end
-- Person instead of character (API 7, 0.9): a member's main and twinks are one person.
-- Count per person with API.MainOf(key); API.Person(key) -> { main, chars = { main, twink, ... }, source = "self"|"lead"|nil }
function API.MainOf(key) return ns.Persons.MainOf(key) end
function API.Person(key)
  if not key then return nil end
  local main = ns.Persons.MainOf(key)
  return { main = main, chars = ns.Persons.Chars(main), source = ns.Persons.Source(main) }
end
function API.Faction() return T.Faction() end                 -- "horde" | "alliance"
function API.Word(key) return T.Word(key) end                 -- H_<key> or A_<key> from the locale
function API.Theme() return T.Current() end
function API.IsDemo() return ns.demo and true or false end
function API.SeasonStart() return ns.Points.SeasonStart() end
function API.SeasonEnd() return ns.Points.SeasonEnd() end

---------------------------------------------------------------------------
-- Rules: guild-wide settings of a module, kept in the guild profile.
-- Defaults come from def.rules; managers change them with SetRules.
---------------------------------------------------------------------------
function API.GetRules(id)
  local def = ns.Modules.modules[id]
  local defaults = def and def.rules or {}
  local pr = ns.Profile.Get()
  if pr == ns.Profile.DEFAULTS then return U.Copy(defaults) end
  pr.mods = pr.mods or {}
  pr.mods[id] = pr.mods[id] or {}
  local r = pr.mods[id]
  for k, v in pairs(defaults) do if r[k] == nil then r[k] = U.Copy(v) end end
  return r
end

-- fn(rules) changes the table; the profile is versioned and sent to the guild
function API.SetRules(id, fn)
  return ns.Profile.Update(function(pr)
    pr.mods = pr.mods or {}
    pr.mods[id] = pr.mods[id] or {}
    fn(pr.mods[id])
  end)
end

---------------------------------------------------------------------------
-- Points
---------------------------------------------------------------------------
-- Own deeds in a module pot (not "event" / "ach"): every member reports only
-- what he did himself. reason becomes entry.why (use it in achievements).
-- extra: { note = "shown in lists", zone = "...", flag = "for achievements" }
function API.ReportOwn(pot, amount, reason, extra) return ns.Points.AddSelf(pot, amount, reason, extra) end

-- Points for a member, any pot (event managers only)
function API.AwardPoints(name, pot, amount, reason, eventId)
  local key = G.Resolve(name) or name
  if not G.roster[key] then return nil end
  return ns.Points.Add(key, pot, amount, reason, eventId)
end

-- { [memberKey] = { total, pots = { pot = n } } }; period "week" | "month" | "season" | "all"
function API.GetTotals(period) return ns.Points.Totals(period) end
function API.GetEntries(filter) return ns.Points.Entries(filter) end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function API.GetEvents(filter) return ns.Events.List(filter) end
function API.GetEvent(id) return ns.Events.Get(id) end
function API.IsSigned(e, name) return ns.Events.IsSigned(e, name and G.Resolve(name) or nil) end

---------------------------------------------------------------------------
-- Callbacks: API.On(name, fn)
--   EVENT_STARTED (event, startedHere)   EVENT_ENDED (event, attended)
--   EVENT_CANCELLED (event)              EVENT_UPDATED (event, isNew)
--   POINTS_ADDED (entry)                 ACHIEVEMENT_EARNED (def, time)
--   ACTIVATED ()                         PROFILE_CHANGED ()
--   PERSONS_CHANGED ()                   (a main/twink link changed; API 7)
---------------------------------------------------------------------------
function API.On(name, fn) ns.On(name, fn) end

---------------------------------------------------------------------------
-- Guild messages of a module. Sent only in an activated guild, throttled,
-- split when long; received only from guild members. kind: letters/digits.
--   API.Send("pve", "CATCH", { fish = 6358 })
--   API.Listen("pve", "CATCH", function(data, senderKey) end)
---------------------------------------------------------------------------
function API.Send(id, kind, data) return ns.Comm.Send(moduleId(id) .. ":" .. kind, data or {}) end
-- only to the ranks that may read the officer chat (API 7)
function API.SendOfficer(id, kind, data) return ns.Comm.SendOfficer(moduleId(id) .. ":" .. kind, data or {}) end
function API.Listen(id, kind, fn) ns.Comm.On(moduleId(id) .. ":" .. kind, fn) end
function API.CanSend() return ns.Comm.CanSend() end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
-- Own tab in the main window (before Settings). def = { label = fn, build = fn(panel), refresh = fn(panel) }
function API.AddTab(id, def) ns.UI.AddTab(id, def) end
-- API 5: a side bar entry with sub tabs, settings pages, notices, honor book texts
function API.AddModule(id, def) return ns.UI.AddModule(id, def) end
function API.AddSettingsPage(id, def) ns.UI.AddSettingsPage(id, def) end
function API.AddHelp(id, fn) ns.UI.AddHelp(id, fn) end    -- help for a view or entry: fn() -> title, text
function API.AddNotice(n) ns.Notices.Add(n) end         -- { key, group, text, view | ev | open = fn }
function API.RemoveNotice(key) ns.Notices.Remove(key) end
function API.AddLedgerFormat(id, def) return ns.Ledger.AddFormat(id, def) end -- { label = fn, match = fn(e), text = fn(e) }
-- API 5: sign-ups with state, comment and the fields of the event type
function API.SignupStatus(e, name) return ns.Events.Status(e, name and G.Resolve(name) or nil) end
function API.GetSignups(e) return ns.Events.SignupList(e) end   -- { { key, st, c, f, t } }, by time
function API.SetSignup(e, opts) return ns.Events.SetSignup(e, opts) end -- { st = "in"|"tent"|"late"|"bench"|"out", c, f }
function API.InviteAll(e) return ns.Events.InviteAll(e) end
function API.CanCreate(typeId, name)
  if not name and not ns.Events.TypeOpen(typeId) then return false end   -- 0.9: area locked, holiday not open
  return ns.Events.CanCreate(typeId, name and G.Resolve(name) or nil)
end
function API.CanManage(e, name) return ns.Events.CanManage(e, name and G.Resolve(name) or nil) end
-- API 7: modules of the guild. A module is part of the guild once the guild
-- master or an event manager has it installed (catalogue in the guild profile).
function API.ModuleKnown(id) return ns.Catalog.Info(id) ~= nil or ns.Catalog.IsCore(id) end
function API.IsInterested(id) return ns.Catalog.IsInterested(id) end   -- player has not said "not interested"

-- API 7: contests. The event type declares `contest = { rank = "high"|"low",
-- ties = "shared"|"first", places = fn(e) -> { p1, p2, p3 }, target = n|fn(e),
-- window = fn(e) -> from, to, format = fn(value, e) -> text }`.
function API.ContestRunning(e) return ns.Contest.Running(e) and true or false end   -- 0.9: counting right now?
function API.ContestEnded(e) return ns.Contest.Ended(e) end                     -- 0.9: time counting ended, or nil
function API.SetScore(e, value) return ns.Contest.SetScore(e, value) end        -- own score
function API.AddScore(e, delta) return ns.Contest.AddScore(e, delta) end
function API.Standings(e) return ns.Contest.Standings(e) end                    -- { { key, value, at, place, bonus } }
function API.EndContest(e, reason) return ns.Contest.EndContest(e, reason) end  -- stop counting now (told to everyone)
function API.SuggestBonus(e, name, points, reasonKey) return ns.Contest.SuggestBonus(e, name, points, reasonKey) end
function API.ShowStandings(e) if ns.UIEvents then ns.UIEvents.ShowStandings(e) end end
-- big message in the middle of the screen (like a raid warning, but none)
function API.Alert(text, opts) return ns.Contest.Alert(text, opts) end
function API.AlertGuild(text, opts) return ns.Contest.AlertGuild(text, opts) end      -- everyone in the guild
function API.AlertEvent(e, text, opts) return ns.Contest.AlertEvent(e, text, opts) end -- those signed up

-- API 7: settings of the event leader (type's `settings`), defaults filled in
function API.EventSettings(e) return ns.Events.Settings(e) end
function API.CreateEvent(fields) return ns.Events.Create(fields) end
function API.SaveEvent(e) return ns.Events.Save(e) end
function API.Open(tab) ns.UI.Show(tab) end
-- 0.9: open an event's detail page (tab: "info" | "teams"), or the editor for a new
-- event of a type (only for members who may create it)
function API.OpenEvent(e, tab) if e and ns.EventsUI then ns.EventsUI.OpenDetail(e, tab) end end
function API.NewEvent(typeId, fields)       -- fields: preset, e.g. { start, finish, name }
  if not ns.EventsUI or (typeId and not ns.Events.CanCreate(typeId)) then return false end
  local preset = {}
  for k, v in pairs(fields or {}) do preset[k] = v end
  preset.type = typeId
  ns.EventsUI.OpenEditor(nil, nil, preset)
  return true
end
function API.Refresh() if ns.UI then ns.UI.Refresh() end end
-- Themed widgets: Box, Text, Button, Edit, Check, Dropdown, Scroll, Pool, Bar, Dialog, OpenMenu (see Widgets.lua)
API.Widgets = ns.W
function API.Section(parent, text) return ns.UI.Section(parent, text) end
function API.Pill(parent) return ns.UI.Pill(parent) end
function API.ShowPlaque(name, sub, points, icon) ns.Plaque.Show(name, sub, points, icon) end
function API.Print(msg) U.Print(msg) end
-- /gem <command> [args]
function API.AddCommand(cmd, fn) ns.SlashExt[cmd:lower()] = fn end
-- Own section in the support export (/gem export): fn(full) returns a list of text lines
function API.AddExport(id, fn) ns.Export.Add(id, fn) end
-- API 5: a check for /gem probe; fn() returns { { label, value }, ... }
function API.AddProbe(id, fn) ns.Probe.Add(id, fn) end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Timer without timer objects (Forever limits an addon to 500 timers); same name replaces
function API.Schedule(name, delay, fn) ns.Schedule(name, delay, fn) end
-- Errors go to the error log (/gem errors) instead of interrupting the game
function API.SafeCall(where, fn, ...) return ns.SafeCall(where, fn, ...) end
function API.Now() return U.Now() end

---------------------------------------------------------------------------
-- API 7: own saved data, small windows, time and level helpers
---------------------------------------------------------------------------
local function savedRoot()
  if not ns.db then          -- before the core's ADDON_LOADED ran: the saved table exists already
    GuildEventManagerDB = GuildEventManagerDB or {}
    return GuildEventManagerDB, nil
  end
  return ns.db, ns.char
end

-- A table of the module that the core saves: per account, or per character.
-- Call it when you need it (also fine in the module's main chunk).
function API.Storage(id)
  local db = savedRoot()
  db.mods = db.mods or {}
  db.mods[moduleId(id)] = db.mods[id] or {}
  return db.mods[id]
end

function API.CharStorage(id)
  local db, char = savedRoot()
  if not char then
    db.chars = db.chars or {}
    local k = U.CharKey()
    db.chars[k] = db.chars[k] or {}
    char = db.chars[k]
  end
  char.mods = char.mods or {}
  char.mods[moduleId(id)] = char.mods[id] or {}
  return char.mods[id]
end

-- Small movable window in the guild's colours; the same id gives the same window.
-- opts = { title, width, height, strata, point = { "CENTER", x, y }, onClose = fn(win), noClose, lockable }
-- win.content is the area to fill; win:Open(), win:Close(), win:SetTitle(t), win:Resize(w, h)
-- Teams (0.9): e.teams of events with group "teams"
--   API.Teams(e) -> { size, list = { { lead = key, m = { keys } } }, pub } or nil
--   API.TeamOf(e, name) -> index, team ; API.TeamStandings(e) -> { { team, lead, value, place, members } }
function API.Teams(e) return ns.Teams.Get(e) end
function API.TeamOf(e, name) local key = name and G.Resolve(name) or G.MyKey(); return ns.Teams.Of(e, key) end
function API.TeamStandings(e) return ns.Teams.Standings(e) end
function API.ShowTeams(e) if ns.UITeams then ns.UITeams.Show(e) end end

-- Shared goal (0.9)
function API.ContestTotal(e) return ns.Contest.Total(e) end
function API.ContestGroups(e) return ns.Contest.Groups(e) end
function API.GoalReached(e) return ns.Contest.GoalReached(e) end

-- Guild achievements and trophies (0.9)
--   API.GuildAchievements() -> { { def, have, tier, next, tierTs, top, mine, seasons } }
--   API.GuildProgress(id) -> the same for one; API.Trophies() -> { { def, tier, ts, season } }
--   Modules: def.guildAchievements = { { id, nameKey, descKey, icon, tiers, scope, stat, ... } }
function API.GuildAchievements() return ns.GuildAch.All() end
function API.GuildProgress(id) return ns.GuildAch.Progress(id) end
function API.Trophies() return ns.GuildAch.Trophies() end

-- Report end (0.9): a participant reports an end his client may have missed;
-- the event leader confirms (ConfirmEnd) or lets counting go on (ResumeContest)
function API.ReportEnd(e, reason) return ns.Contest.ReportEnd(e, reason) end
function API.EndPending(e) return ns.Contest.Pending(e) end
function API.ConfirmEnd(e) return ns.Contest.ConfirmEnd(e) end
function API.ResumeContest(e) return ns.Contest.Resume(e) end

-- Game watcher (0.9): API.OnGame(kind, fn) -> handle, API.OffGame(handle)
-- kinds: fishloot, loot, itemcount, questdone, npcsay, system, pvpkill, zone, spellcast (0.9: own successful cast with the target name)
function API.OnGame(kind, fn, modId) return ns.Game.On(kind, fn, modId and moduleId(modId) or nil) end
function API.OffGame(handle) ns.Game.Off(handle) end
function API.WatchItem(itemId, on) ns.Game.WatchItem(itemId, on) end
function API.ItemCount(itemId) return ns.Game.ItemCount(itemId) end
function API.ZoneIs(x) return ns.Game.ZoneIs(x) end
function API.MapID() return ns.Game.MapID() end

function API.FloatingWindow(id, opts) return ns.Float.Get(moduleId(id), opts) end

-- Level of a guild member (from the roster); the own level for the player.
function API.MemberLevel(name)
  local key
  if name then key = G.Resolve(name); if not key then return nil end else key = G.MyKey() end
  if key == G.MyKey() then return UnitLevel("player") end
  local r = key and G.roster[key]
  return r and r.level or nil
end

-- Server clock: weekday (1 = Sunday), hour, minute of the realm.
function API.ServerClock()
  if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
    local ok, d = pcall(C_DateAndTime.GetCurrentCalendarTime)
    if ok and d and d.weekday then return d.weekday, d.hour, d.minute end
  end
  local h, m
  if GetGameTime then h, m = GetGameTime() end
  return tonumber(date("%w")) + 1, h or tonumber(date("%H")), m or tonumber(date("%M"))
end

-- Next point in time (timestamp) at weekday (1 = Sunday … 7 = Saturday) and
-- "HH:MM" realm time. Today counts if the time is still ahead.
function API.NextServerTime(weekday, hhmm)
  local th, tm = tostring(hhmm or "0:00"):match("^(%d+):(%d+)$")
  th, tm = tonumber(th) or 0, tonumber(tm) or 0
  local wd, h, m = API.ServerClock()
  local now = U.Now()
  now = now - now % 60                          -- the realm clock has no seconds
  local days = ((weekday or wd) - wd) % 7
  local delta = days * 86400 + ((th * 60 + tm) - (h * 60 + m)) * 60
  if delta <= 0 then delta = delta + 7 * 86400 end
  return now + delta
end

-- Time in the player's language. style: "datetime" (default), "date", "time", "weekday"
function API.FormatTime(ts, style)
  if not ts then return "–" end
  style = style or "datetime"
  local wd = ns.L["WD_" .. (tonumber(date("%w", ts)) + 1)]
  if style == "date" then return date("%d.%m.%Y", ts)
  elseif style == "time" then return date("%H:%M", ts)
  elseif style == "weekday" then return wd .. " " .. date("%H:%M", ts)
  end
  return wd .. " " .. U.FormatTime(ts)
end

-- Blizzard addon compartment (stays here: the TOC refers to these names)
-- see UI_Minimap.lua

---------------------------------------------------------------------------
-- Areas and holidays (0.9)
---------------------------------------------------------------------------
-- Has the guild master unlocked this area of the module? (types without area: always)
function API.AreaUnlocked(moduleId, area) return ns.Catalog.AreaOn(moduleId, area) end
-- { { id, name } } of the module
function API.Areas(moduleId) return ns.Catalog.Areas(moduleId) end
-- only the guild master; the change goes to the guild with the profile
function API.SetAreaUnlocked(moduleId, area, on) return ns.Catalog.SetArea(moduleId, area, on) end
-- may an event of this type be created right now? (area unlocked, holiday open; rights: API.CanCreate)
function API.TypeOpen(typeId) return ns.Events.TypeOpen(typeId) end

-- def = { id, nameKey, from = { month, day }, to = { month, day }, lead = days, icon }
-- (realm time; `to` may lie in the next year). Event types with `holiday = id`
-- can be created from `lead` days (default 14) before the start until its end.
function API.AddHoliday(def) return ns.Holidays.Add(def) end
-- { id, name, start, finish, active, soon, days, moved } of the current or next occurrence
function API.Holiday(id) return ns.Holidays.Info(id) end
function API.HolidayActive(id) return ns.Holidays.Active(id) end
-- the guild leadership moves a holiday for its guild (managers); nil, nil = back to the module's dates
function API.SetHolidayDates(id, from, to) return ns.Holidays.SetDates(id, from, to) end
-- timestamp of a realm date and time
function API.RealmTime(y, m, d, h, mi) return ns.Holidays.RealmTime(y, m, d, h, mi) end

---------------------------------------------------------------------------
-- Members (0.9, for guild management modules)
---------------------------------------------------------------------------
-- { name, rank, rankIndex, level, class, online, offDays } of a member (nil if not in the guild)
function API.MemberInfo(name)
  local key = name and G.Resolve(name) or G.MyKey()
  local r = key and G.roster[key]
  if not r then return nil end
  return { key = key, name = r.name, rank = r.rankName, rankIndex = r.rankIndex, level = r.level, class = r.class, online = r.online and true or false, offDays = r.offDays }
end
-- rank index -> name (0 = guild master)
function API.RankNames() local out = {}; for i, n in pairs(G.rankNames or {}) do out[i] = n end; return out end
-- guild leadership: the guild master and the ranks of the function "lead"
function API.IsLeadership(name) return G.IsLead(name and G.Resolve(name) or nil) end
-- bank character of the guild (Settings > guild structure, or a rank of the function "bank")
function API.IsBankChar(name) local key = name and G.Resolve(name) or G.MyKey(); return ns.Ranks and ns.Ranks.IsBank(key) or false end
-- open Blizzard's guild window with the member selected (addons cannot set ranks on Forever)
function API.OpenInGuild(name) local key = name and G.Resolve(name); if key and ns.Ranks then return ns.Ranks.OpenInGuild(key) end end

-- first-party modules shipped with the core may use the namespace directly
API.core = ns
