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
-- Most GP per entry a manager may book alone; above it the guild master
-- confirms (request over the officer channel). 0 = no limit.
function Pts.Cap()
  local p = ns.Profile and ns.Profile.Get()
  local c = p and tonumber(p.managerCap)
  if c == nil then c = 100 end
  return math.max(0, math.floor(c))
end
function Pts.OverCap(amt, key)
  local cap = Pts.Cap()
  if cap == 0 then return false end
  local isGM
  if key == nil or key == G.MyKey() then isGM = G.IsLeader() or G.RankOf(G.MyKey()) == 0
  else isGM = G.RankOf(key) == 0 end
  return not isGM and math.abs(tonumber(amt) or 0) > cap
end

function Pts.Add(who, pot, amt, why, ev, note, extra)
  if not G.IsManager() then U.Print(ns.L.NO_RIGHTS); return nil end
  amt = tonumber(amt)
  if not who or not amt or amt == 0 then return nil end
  if Pts.OverCap(amt) then
    return nil, Pts.Request(who, pot, amt, why, ev, note, extra)
  end
  local e = { id = U.NewId(), who = who, pot = pot or "event", amt = amt, why = why or "manual",
    ev = ev, note = note, ts = U.Now(), by = G.MyKey() }
  for k, v in pairs(extra or {}) do if e[k] == nil then e[k] = v end end
  ledger()[e.id] = e
  ns.Fire("POINTS_ADDED", e)
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
-- why-codes for which a member may also book a minus for himself (he can only
-- harm himself): a bounty is paid in advance from the own honor (API 4)
Pts.SELF_NEG = { bounty = true }
-- why-codes of marker entries without points (0.9, Deeds.lua): they only carry
-- a fact for achievements (a character at 60, gold paid into the guild bank)
Pts.MARKERS = { alt60 = true, dblagent = true, gbank = true, death = true, ding60 = true }

local function selfAmtOk(amt, why)
  amt = tonumber(amt) or 0
  if amt == 0 then return Pts.MARKERS[why] == true end
  if amt > 0 then return amt <= Pts.SELF_MAX end
  return amt < 0 and Pts.SELF_NEG[why] and amt >= -Pts.SELF_MAX or false
end

function Pts.AddSelf(pot, amt, why, extra)
  amt = tonumber(amt)
  if not amt or Pts.CORE_POTS[pot] then return nil end
  if amt == 0 and not Pts.MARKERS[why] then return nil end
  if amt > 0 then amt = math.min(amt, Pts.SELF_MAX) end
  if not selfAmtOk(amt, why) then return nil end
  if not ns.Comm.CanSend() then return nil end
  local me = G.MyKey()
  local e = { id = U.NewId(), who = me, pot = pot, amt = amt, why = why, ts = U.Now(), by = me }
  for k, v in pairs(extra or {}) do if e[k] == nil then e[k] = v end end
  ledger()[e.id] = e
  ns.Fire("POINTS_ADDED", e)
  Pts.queue = Pts.queue or {}
  Pts.queue[#Pts.queue + 1] = e
  ns.Schedule("gemLedgerFlush", 0.5, Pts.Flush)
  ns.Achievements.Check()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return e
end

local function selfEntryOk(e, from)
  return e.who == from and e.by == from and not Pts.CORE_POTS[e.pot]
    and selfAmtOk(e.amt, e.why) and e.why ~= "revert"
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
    -- above the cap only the guild master's own client is believed (also when
    -- relaying: an officer cannot pass on large entries, the guild master can)
    if type(e) == "table" and e.id and e.who and tonumber(e.amt) and not l[e.id]
      and (selfEntryOk(e, from) or (manager and not Pts.OverCap(e.amt, from))) then
      e.amt = tonumber(e.amt); e.ts = tonumber(e.ts) or U.Now()
      l[e.id] = e
      ns.Fire("POINTS_ADDED", e)
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
    if (e.ts or 0) >= since then add(ns.Persons.MainOf(e.who), e.pot, e.amt) end
  end
  for who, list in pairs(ns.Achievements.Earned()) do
    for _, a in ipairs(list) do
      if (a.ts or 0) >= since then add(who, "ach", a.pts or 0) end
    end
  end
  return ns.Persons.ByPerson(res)
end

-- Sorted ranking: { { key, total, pots } }
function Pts.Ranking(period)
  local list = {}
  for who, r in pairs(Pts.Totals(period)) do
    list[#list + 1] = { key = who, total = r.total, pots = r.pots, alts = ns.Persons.Alts(who) }
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

---------------------------------------------------------------------------
-- Requests to the guild master (entries above the cap). They travel over the
-- officer channel only; an officer re-sends his open ones when the guild master
-- comes online (HELLO). Kept 14 days.
---------------------------------------------------------------------------
local REQ_DAYS = 14
local function requests()
  local s = ns.Store()
  if not s then return {} end
  s.requests = s.requests or {}
  local now = U.Now()
  for id, r in pairs(s.requests) do
    if type(r) ~= "table" or now - (tonumber(r.ts) or 0) > REQ_DAYS * DAY then s.requests[id] = nil end
  end
  return s.requests
end
Pts.Requests = requests

function Pts.Request(who, pot, amt, why, ev, note, extra)
  local r = { id = U.NewId(), who = who, pot = pot or "event", amt = amt, why = why or "manual", ev = ev,
    note = note, ts = U.Now(), by = G.MyKey(), state = "open" }
  if type(extra) == "table" and extra.flag then r.flag = extra.flag end
  requests()[r.id] = r
  C.SendOfficer("LEDGREQ", { r = r })
  U.Print(ns.L.AW_REQ_SENT:format(amt, G.Display(who), Pts.Cap()))
  ns.Fire("POINTS_REQUEST", r)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return r
end

function Pts.OpenRequests()
  local out = {}
  for _, r in pairs(requests()) do if r.state == "open" then out[#out + 1] = r end end
  table.sort(out, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
  return out
end

local function isGM() return G.IsLeader() or G.RankOf(G.MyKey()) == 0 end
Pts.IsGM = isGM

-- the guild master decides: ok = true books the entry in his name
function Pts.Decide(id, ok)
  if not isGM() then U.Print(ns.L.NO_RIGHTS); return end
  local r = requests()[id]
  if not r or r.state ~= "open" then return end
  if ok then
    local extra = { ask = r.by, req = r.id }
    if r.flag then extra.flag = r.flag end
    local note = r.note
    Pts.Add(r.who, r.pot, r.amt, r.why, r.ev, note, extra)
  end
  r.state = ok and "ok" or "no"
  r.done = U.Now()
  C.SendOfficer("LEDGREQDONE", { id = r.id, ok = ok and 1 or 0 })
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

C.On("LEDGREQ", function(data, from, dist)
  local r = data.r
  if dist ~= "OFFICER" or type(r) ~= "table" or type(r.id) ~= "string" then return end
  if r.by ~= from or not G.IsManager(from) or not tonumber(r.amt) or not r.who then return end
  local list = requests()
  if list[r.id] then return end
  list[r.id] = { id = r.id, who = r.who, pot = r.pot, amt = tonumber(r.amt), why = r.why, ev = r.ev,
    note = type(r.note) == "string" and r.note:sub(1, 120) or nil, ts = tonumber(r.ts) or U.Now(), by = from,
    state = "open", flag = r.flag }
  if isGM() then
    U.Print(ns.L.AW_REQ_IN:format(G.Display(from), list[r.id].amt, G.Display(r.who)))
    if ns.Notices then
      ns.Notices.Add({ key = "req:" .. r.id, group = ns.L.TAB_LEDGER,
        text = ns.L.AW_REQ_IN:format(G.Display(from), list[r.id].amt, G.Display(r.who)), view = "ledgeraward" })
    end
  end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

C.On("LEDGREQDONE", function(data, from, dist)
  if dist ~= "OFFICER" or G.RankOf(from) ~= 0 then return end
  local r = requests()[data.id]
  if not r or r.state ~= "open" then return end
  r.state = (tonumber(data.ok) == 1) and "ok" or "no"
  r.done = U.Now()
  if r.by == G.MyKey() then
    U.Print((r.state == "ok" and ns.L.AW_REQ_OK or ns.L.AW_REQ_NO):format(r.amt, G.Display(r.who)))
  end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

-- the guild master came online: send him the open requests again
C.On("HELLO", function(data, from)
  if G.RankOf(from) ~= 0 or not G.IsManager() then return end
  local me = G.MyKey()
  ns.Schedule("gemReqResend", 3 + math.random() * 5, function()
    for _, r in pairs(requests()) do
      if r.state == "open" and r.by == me then C.SendOfficer("LEDGREQ", { r = r }) end
    end
  end)
end)
