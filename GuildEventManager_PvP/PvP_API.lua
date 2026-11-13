local ADDON, P = ...
-- GuildEventManagerAPI.PvP: interface for PvP extension modules.
-- A PvP module depends on GuildEventManager and GuildEventManager_PvP and can
-- * bring its own PvP event types and achievements (GuildEventManagerAPI.RegisterModule)
-- * define deeds that give guild honor, each with an adjustable honor value
-- * add rules to the honor rules of the PvP tab
-- * react to kills, deaths, blood debts and war drums
-- Documentation: docs/MODULES.md
local core = P.core
if not core then return end
local U, Pts = core.U, core.Points
local L = P.L

local PvP = {}
GuildEventManagerAPI.PvP = PvP
PvP.version = 3   -- see docs/MODULES.md, section 6 (API changes)

P.deeds = {}       -- id -> { label, labelKey, honor, dailyCap, module }
P.extraRules = {}  -- { { key, label, labelKey } } shown after the built-in rules

local function deedRule(id) return "deed_" .. id end

-- Rule for the honor rules form (guild-wide, changed by event managers)
-- key: unique, e.g. "duels_perDay"; default: number
function PvP.AddRule(key, default, label, labelKey)
  if P.DEFAULTS[key] ~= nil then return end
  P.DEFAULTS[key] = default
  P.extraRules[#P.extraRules + 1] = { key = key, label = label, labelKey = labelKey }
end

-- A deed that gives guild honor.
-- def = { label = "won a duel against %s" | labelKey = "...", honor = 5, dailyCap = 50 (optional, honor per day) }
-- The label may contain %s for entry.note (e.g. the opponent).
function PvP.RegisterDeed(id, def)
  if type(id) ~= "string" or not id:match("^[%w_]+$") then error("RegisterDeed: id must be letters, digits or _", 2) end
  def = def or {}
  P.deeds[id] = def
  PvP.AddRule(deedRule(id), def.honor or 5, def.ruleLabel or (def.label and (def.label:gsub("%%s", "…"))), def.ruleLabelKey)
  if def.dailyCap then PvP.AddRule(deedRule(id) .. "_cap", def.dailyCap, def.capLabel, def.capLabelKey) end
end

-- Report a deed of the own character: honor as set in the rules.
-- extra = { note = "opponent", zone = "...", flag = "for achievements" }
-- Returns the ledger entry, or nil (not activated, daily cap reached, ...).
function PvP.ReportDeed(id, extra)
  local def = P.deeds[id]
  if not def then return nil end
  local r = P.Rules()
  local honor = tonumber(r[deedRule(id)]) or def.honor or 0
  if honor <= 0 then return nil end
  local cap = tonumber(r[deedRule(id) .. "_cap"])
  if cap then
    local c = P.Char()
    local day = P.Today()
    c.deeds = c.deeds or {}
    local d = c.deeds[id]
    if not d or d.day ~= day then d = { day = day, honor = 0 }; c.deeds[id] = d end
    if d.honor + honor > cap then return nil end
    d.honor = d.honor + honor
  end
  extra = extra or {}
  extra.zone = extra.zone or (GetZoneText and GetZoneText()) or nil
  return Pts.AddSelf("honor", honor, id, extra)
end

-- Guild honor rules (built-in and from modules): read only, change with SetRules
function PvP.GetRules() return P.Rules() end
function PvP.SetRules(fn)
  return core.Profile.Update(function(pr) pr.pvp = pr.pvp or {}; fn(pr.pvp) end)
end

-- Callbacks: PvP.On(name, fn)
--   KILL (victimName or nil, instanceType)   honorable kill of the own character; instanceType "none" = open world, "pvp" = battleground
--   DEATH (killerName or nil)                own death in the open world
--   DEBT_NEW (debt)  DEBT_PAID (debt, servedCold)
--   DRUM (drum)      DRUM_ARRIVED (drum, first)
--   HONORDUEL (duel, winnerKey, loserKey) own won duel of honor, booked
--   HONORDUEL_NEW (duel)                  a challenge arrived from the guild
--   MAKGORA / MAKGORA_NEW                 deprecated old names of the two above
--   OATH_FULFILLED (oath)                 own oath confirmed by the witnesses
function PvP.On(name, fn) core.On("PVP_" .. name, fn) end

-- War drum / storm bell at the own position: level "help" | "rally" | "attack"
function PvP.Drum(level, text) P.Drum(level, text) end
function PvP.OpenDebts() return P.OpenDebts() end

-- Duels of honor and oaths, both confirmed by witnesses
function PvP.Challenge(name, stake) P.Challenge(name, stake) end
function PvP.Swear(level, text) P.Swear(level, text) end                 -- level 1..3
function PvP.ActiveDuels() return P.ActiveMakgoras() end
function PvP.ActiveMakgoras() return P.ActiveMakgoras() end   -- deprecated name
function PvP.OpenOaths() return P.OpenOaths() end
function PvP.DuelRecord(name) return PvP.MakgoraRecord(name) end
function PvP.MakgoraRecord(name) return P.MakgoraRecord(name and core.Guild.Resolve(name) or core.Guild.MyKey()) end  -- wins, losses (deprecated name)

-- Season results of guild honor: { { start, stop, total, top = { { key, honor } x3 } } }, newest first
function PvP.SeasonResults(n) return P.SeasonResults(n) end
function PvP.SeasonProgress() return P.SeasonProgress() end              -- honor this season, goal
function PvP.InOpenWorld() return P.OpenWorld() end
function PvP.PlaySignal() P.PlaySignal() end
function PvP.Notice(msg) P.Notice(msg) end

-- Label of an honor-roll entry (built-in deeds and module deeds)
function P.DeedLabel(e)
  local def = P.deeds[e.why]
  if not def then return nil end
  local text = def.label or (def.labelKey and L[def.labelKey]) or e.why
  if text:find("%%s") then text = text:format(e.note or "?") end
  return text
end

---------------------------------------------------------------------------
-- Section of the support export (/gem export)
---------------------------------------------------------------------------
GuildEventManagerAPI.AddExport("PvP", function(full)
  local X = core.Export
  local out = {}
  local function add(k, v) out[#out + 1] = k .. ": " .. X.Val(v) end
  local c = P.Char()
  add("module version", PvP.version)
  add("counters (mine)", c.hk)
  local last, now = P.KillCounterState()
  add("kill counter (last seen / game now)", { last = last, now = now })
  add("kills today", P.KillsToday())
  add("pending kills", #(P.pendingKills or {}))
  add("game stats", P.OwnStats())
  local stored = P.StatsStore()[core.Guild.MyKey()]
  add("stats the guild has of me", stored)
  add("open world now", P.OpenWorld())
  add("rules", P.Rules())
  local debts = P.OpenDebts()
  add("open debts", #debts)
  for i = 1, math.min(#debts, full and #debts or 10) do
    local d = debts[i]
    out[#out + 1] = ("  debt %s since %s"):format(X.Val(d.name), d.ts and date("%Y-%m-%d %H:%M", d.ts) or "-")
  end
  add("active duels", #P.ActiveMakgoras())
  add("open oaths", #P.OpenOaths())
  local diag = core.db and core.db.pvpDiag or {}
  add("last honor line", { text = diag.honorLine, at = diag.honorLineAt })
  local r = diag.recap and diag.recap[1]
  if r then
    add("last death recap", { at = r.at, reason = r.reason, killer = r.killer })
    for _, l in ipairs(r.lines or {}) do out[#out + 1] = "  " .. X.Val(l) end
  else
    add("last death recap", "-")
  end
  return out
end)
