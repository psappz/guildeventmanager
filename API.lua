local ADDON, ns = ...
-- GuildEventManagerAPI: the public interface for modules.
-- Documentation with examples: docs/MODULES.md
-- Everything a module needs is here; anything else in the core may change
-- between versions. API.version rises only when something is added; existing
-- functions keep their behaviour.
local U, G, T = ns.U, ns.Guild, ns.Theme

local API = {}
GuildEventManagerAPI = API

API.version = 3   -- see docs/MODULES.md, section 6 (API changes)
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
--   eventTypes = { { id, name|nameKey, desc|descKey, kind, group, icon, goalKeys|goals } },
--   pots = { { id, name|nameKey } },
--   achievements = { { id, name|nameKey, stat, why, flag, evtype, n, pts, scope, honor, honorScope, hidden, tier, icon, descKey } },
--   rules = { key = default, ... },           -- guild-wide settings, see GetRules
--   locales = { enUS = { KEY = "..." }, deDE = { ... } },
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
function API.IsManager(name) return G.IsManager(name and G.Resolve(name) or nil) end
function API.IsGuildMember(name) return G.Resolve(name) ~= nil end
function API.PlayerKey() return G.MyKey() end
function API.MemberKey(name) return G.Resolve(name) end      -- any spelling -> member key (nil if not in the guild)
function API.DisplayName(key) return G.Display(key) end
function API.GuildName() return G.Name() end
function API.Members() return G.Members() end
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
---------------------------------------------------------------------------
function API.On(name, fn) ns.On(name, fn) end

---------------------------------------------------------------------------
-- Guild messages of a module. Sent only in an activated guild, throttled,
-- split when long; received only from guild members. kind: letters/digits.
--   API.Send("pve", "CATCH", { fish = 6358 })
--   API.Listen("pve", "CATCH", function(data, senderKey) end)
---------------------------------------------------------------------------
function API.Send(id, kind, data) return ns.Comm.Send(moduleId(id) .. ":" .. kind, data or {}) end
function API.Listen(id, kind, fn) ns.Comm.On(moduleId(id) .. ":" .. kind, fn) end
function API.CanSend() return ns.Comm.CanSend() end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
-- Own tab in the main window (before Settings). def = { label = fn, build = fn(panel), refresh = fn(panel) }
function API.AddTab(id, def) ns.UI.AddTab(id, def) end
function API.Open(tab) ns.UI.Show(tab) end
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

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Timer without timer objects (Forever limits an addon to 500 timers); same name replaces
function API.Schedule(name, delay, fn) ns.Schedule(name, delay, fn) end
-- Errors go to the error log (/gem errors) instead of interrupting the game
function API.SafeCall(where, fn, ...) return ns.SafeCall(where, fn, ...) end
function API.Now() return U.Now() end

-- Blizzard addon compartment (stays here: the TOC refers to these names)
-- see UI_Minimap.lua

-- first-party modules shipped with the core may use the namespace directly
API.core = ns
