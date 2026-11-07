local ADDON, ns = ...
-- Point ledger. Every point is one entry, written by a guild event manager and
-- sent to the guild. Totals are summed from the ledger on every client, so all
-- members see the same numbers. Pots: event, ach (core), honor (PvP module), ...
local U, G, C = ns.U, ns.Guild, ns.Comm
local Pts = {}
ns.Points = Pts

local DAY = 86400

local function ledger()
  local s = ns.Store()
  return s and s.ledger or {}
end

---------------------------------------------------------------------------
-- Periods
---------------------------------------------------------------------------
-- Start of the running season (from the profile: 2weeks, month, quarter)
function Pts.SeasonStart(now)
  now = now or U.Now()
  local p = ns.Profile.Get()
  local t = date("*t", now)
  if p.season == "2weeks" then
    -- fixed 14-day blocks, starting on a Monday (1970-01-05 was a Monday)
    local base = 4 * DAY
    return now - ((now - base) % (14 * DAY))
  elseif p.season == "quarter" then
    return time({ year = t.year, month = math.floor((t.month - 1) / 3) * 3 + 1, day = 1, hour = 0 })
  end
  return time({ year = t.year, month = t.month, day = 1, hour = 0 })
end

function Pts.SeasonEnd(now)
  now = now or U.Now()
  local p = ns.Profile.Get()
  local st = Pts.SeasonStart(now)
  if p.season == "2weeks" then return st + 14 * DAY end
  local t = date("*t", st)
  local months = (p.season == "quarter") and 3 or 1
  return time({ year = t.year, month = t.month + months, day = 1, hour = 0 })
end

function Pts.PeriodStart(period)
  local now = U.Now()
  if period == "week" then return now - 7 * DAY end
  if period == "month" then return now - 30 * DAY end
  if period == "season" then return Pts.SeasonStart(now) end
  if period == "banner" then return now - 28 * DAY end
  return 0
end

---------------------------------------------------------------------------
-- Writing (managers only)
---------------------------------------------------------------------------
-- why: "participate" | "lead" | "goal" | "manual" | module specific
function Pts.Add(who, pot, amt, why, ev, note, extra)
  if not G.IsManager() then U.Print(ns.L.NO_RIGHTS); return nil end
  amt = tonumber(amt)
  if not who or not amt or amt == 0 then return nil end
  local e = { id = U.NewId(), who = who, pot = pot or "event", amt = amt, why = why or "manual",
    ev = ev, note = note, ts = U.Now(), by = G.MyKey() }
  for k, v in pairs(extra or {}) do if e[k] == nil then e[k] = v end end
  ledger()[e.id] = e
  Pts.queue = Pts.queue or {}
  Pts.queue[#Pts.queue + 1] = e
  -- send in batches (an event end writes many entries at once)
  ns.Schedule("gemLedgerFlush", 0.5, Pts.Flush)
  ns.Achievements.Check()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return e
end

-- Own deeds (PvP module and others): every member reports only what he did
-- himself, in pots other than the core ones. Managers can revert them.
Pts.CORE_POTS = { event = true, ach = true }
Pts.SELF_MAX = 100

function Pts.AddSelf(pot, amt, why, extra)
  amt = tonumber(amt)
  if not amt or amt <= 0 or Pts.CORE_POTS[pot] then return nil end
  if not ns.Comm.CanSend() then return nil end
  local me = G.MyKey()
  local e = { id = U.NewId(), who = me, pot = pot, amt = math.min(amt, Pts.SELF_MAX), why = why, ts = U.Now(), by = me }
  for k, v in pairs(extra or {}) do if e[k] == nil then e[k] = v end end
  ledger()[e.id] = e
  Pts.queue = Pts.queue or {}
  Pts.queue[#Pts.queue + 1] = e
  ns.Schedule("gemLedgerFlush", 0.5, Pts.Flush)
  ns.Achievements.Check()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return e
end

local function selfEntryOk(e, from)
  return e.who == from and e.by == from and not Pts.CORE_POTS[e.pot]
    and (tonumber(e.amt) or 0) > 0 and tonumber(e.amt) <= Pts.SELF_MAX and e.why ~= "revert"
end

function Pts.Flush()
  local q = Pts.queue or {}
  Pts.queue = {}
  local batch = {}
  for _, e in ipairs(q) do
    batch[#batch + 1] = e
    if #batch >= 8 then C.Send("LEDG", { l = batch }); batch = {} end
  end
  if #batch > 0 then C.Send("LEDG", { l = batch }) end
end

-- A correction is a new entry with the opposite amount (the ledger never forgets)
function Pts.Revert(id)
  local e = ledger()[id]
  if not e or e.reverted then return end
  local r = Pts.Add(e.who, e.pot, -e.amt, "revert", e.ev, id)
  if r then e.reverted = r.id end
end

C.On("LEDG", function(data, from)
  if type(data.l) ~= "table" then return end
  local manager = G.IsManager(from)
  local l = ledger()
  local changed = false
  for _, e in ipairs(data.l) do
    if type(e) == "table" and e.id and e.who and tonumber(e.amt) and not l[e.id]
      and (manager or selfEntryOk(e, from)) then
      e.amt = tonumber(e.amt); e.ts = tonumber(e.ts) or U.Now()
      l[e.id] = e
      if e.why == "revert" and e.note and l[e.note] then l[e.note].reverted = e.id end
      changed = true
    end
  end
  if changed then
    ns.Achievements.Check()
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  end
end)

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
function Pts.Entries(filter)
  local out = {}
  for _, e in pairs(ledger()) do
    if not filter or filter(e) then out[#out + 1] = e end
  end
  table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
  return out
end

-- Totals per member for a period: { [key] = { total, pots = { pot = n } } }
-- The ach pot is not in the ledger: achievements are worked out from it.
function Pts.Totals(period)
  local since = Pts.PeriodStart(period)
  local res = {}
  local function add(who, pot, amt)
    local r = res[who]
    if not r then r = { total = 0, pots = {} }; res[who] = r end
    r.pots[pot] = (r.pots[pot] or 0) + amt
    r.total = r.total + amt * ns.Profile.Weight(pot)
  end
  for _, e in pairs(ledger()) do
    if (e.ts or 0) >= since then add(e.who, e.pot, e.amt) end
  end
  for who, list in pairs(ns.Achievements.Earned()) do
    for _, a in ipairs(list) do
      if (a.ts or 0) >= since then add(who, "ach", a.pts or 0) end
    end
  end
  return res
end

-- Sorted ranking: { { key, total, pots } }
function Pts.Ranking(period)
  local list = {}
  for who, r in pairs(Pts.Totals(period)) do
    list[#list + 1] = { key = who, total = r.total, pots = r.pots }
  end
  table.sort(list, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return G.Display(a.key) < G.Display(b.key)
  end)
  return list
end

function Pts.GuildTotal(period)
  local sum = 0
  for _, r in pairs(Pts.Totals(period)) do sum = sum + r.total end
  return sum
end

---------------------------------------------------------------------------
-- Clan banner (Horde) / order banner (Alliance): honor + event points of the
-- whole guild in the last 28 days. Level 1..4, thresholds from the profile.
---------------------------------------------------------------------------
function Pts.Banner()
  local since = Pts.PeriodStart("banner")
  local value = 0
  for _, e in pairs(ledger()) do
    if (e.ts or 0) >= since and (e.pot == "event" or e.pot == "honor") then value = value + e.amt end
  end
  local th = ns.Profile.Get().banner or { 1000, 3000, 6000 }
  local level = 1
  for i, v in ipairs(th) do if value >= v then level = i + 1 end end
  local nextAt = th[level]
  local from = (level > 1) and th[level - 1] or 0
  return { level = level, value = value, nextAt = nextAt, from = from }
end
