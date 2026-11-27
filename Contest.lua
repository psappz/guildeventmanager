local ADDON, ns = ...
-- Contests (API 7): an event type with `contest` keeps one score per member
-- and event (value and the time it was reached). Scores travel throttled over
-- the guild channel; every client computes the same standings. Counting ends
-- at the end of the window, when someone reaches the target, or when a module
-- calls EndContest (e.g. the winners of the official tournament are announced).
-- The event leader then checks the results and sends the final points
-- (results screen, UI_Events.lua); until then the result is provisional.
local U, G, C = ns.U, ns.Guild, ns.Comm
local CT = {}
ns.Contest = CT

CT.SEND_DELAY = 3      -- seconds to collect own score changes before sending

function CT.Def(e)
  local t = e and ns.Modules.Type(e.type)
  return t and type(t.contest) == "table" and t.contest or nil
end

function CT.Is(e) return CT.Def(e) ~= nil end

local function call(v, e) if type(v) == "function" then local ok, r = pcall(v, e); return ok and r or nil end; return v end

-- counting window: type's window(e) or the event's start and end
function CT.Window(e)
  local d = CT.Def(e) or {}
  if type(d.window) == "function" then
    local ok, a, b = pcall(d.window, e)
    if ok and a then return a, b end
  end
  return e.start or 0, e.finish
end

function CT.Target(e) return tonumber(call((CT.Def(e) or {}).target, e)) end

function CT.Places(e)
  local p = call((CT.Def(e) or {}).places, e)
  local out = {}
  for i = 1, 3 do out[i] = tonumber(type(p) == "table" and p[i]) or 0 end
  return out
end

---------------------------------------------------------------------------
-- Shared goal (0.9, e.g. Anglergeddon): everyone counts towards one target.
-- contest.goal = { target = n|fn(e), reward = n|fn(e), groupBonus = n|fn(e) }
-- Reached: every participant gets `reward`; the members of the group with
-- the highest sum get `groupBonus` on top. Groups: the teams of the event if
-- there are any, otherwise the raids (by raid leader) when several raids take
-- part, otherwise the groups (1–8) of the one raid.
---------------------------------------------------------------------------
function CT.Goal(e)
  local d = CT.Def(e)
  local g = d and d.goal
  if type(g) ~= "table" then return nil end
  return { target = tonumber(call(g.target, e)), reward = tonumber(call(g.reward, e)) or 0, bonus = tonumber(call(g.groupBonus, e)) or 0 }
end

function CT.Total(e)
  local n = 0
  for _, s in pairs(e and e.scores or {}) do n = n + (tonumber(type(s) == "table" and s.v) or 0) end
  return n
end

function CT.GoalReached(e)
  local g = CT.Goal(e)
  return g and g.target and CT.Total(e) >= g.target or false
end

-- the own raid / group right now: { r = raid or party leader key, s = subgroup }
local myGroup
function CT.MyGroup()
  local GW = ns.Game
  local call_ = GW and GW.Call or function(fn, ...) local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end end
  local function name(n) n = GW and GW.Str(n) or n; return n and G.Key(n) or nil end
  if call_(IsInRaid) then
    local me = GW and GW.Str(call_(UnitName, "player"))
    local lead, sub
    for i = 1, 40 do
      local n, rank, s = call_(GetRaidRosterInfo, i)
      n = GW and GW.Str(n) or n
      if n then
        local self_ = me and (n == me or n:match("^([^%-]+)") == me)
        if rank == 2 then lead = self_ and G.MyKey() or name(n) end
        if self_ then sub = tonumber(s) end
      end
    end
    if lead then myGroup = { r = lead, s = sub } end
  elseif call_(IsInGroup) then
    local lead
    if call_(UnitIsGroupLeader, "player") then lead = G.MyKey() else
      for i = 1, 4 do if call_(UnitIsGroupLeader, "party" .. i) then lead = name(call_(UnitName, "party" .. i)) end end
    end
    if lead then myGroup = { r = lead, s = 1 } end
  else
    myGroup = nil
  end
  return myGroup
end

-- groups with their sums: { { id, name, value, members = { keys }, best } }
function CT.Groups(e)
  local out = {}
  local tm = ns.Teams and ns.Teams.Get(e)
  if tm and tm.list and #tm.list > 0 then
    local st = ns.Teams.Standings(e)
    for _, s in ipairs(st) do out[#out + 1] = { id = "t" .. (s.id or s.team), name = s.name, value = s.value, members = s.members } end
  else
    local raids, byRaid, bySub = {}, {}, {}
    for key, s in pairs(e.scores or {}) do
      local g = type(s) == "table" and type(s.g) == "table" and s.g
      if g and g.r then raids[g.r] = true end
    end
    local multi = 0
    for _ in pairs(raids) do multi = multi + 1 end
    for key, s in pairs(e.scores or {}) do
      local g = type(s) == "table" and type(s.g) == "table" and s.g or nil
      local id, nm
      if not g or not g.r then id, nm = "x", ns.L.GOAL_NO_GROUP
      elseif multi > 1 then id, nm = "r" .. g.r, ns.L.GOAL_RAID_OF:format(G.Display(g.r))
      else id, nm = "s" .. (g.s or 0), ns.L.GOAL_GROUP_N:format(g.s or 0) end
      local x = byRaid[id]
      if not x then x = { id = id, name = nm, value = 0, members = {} }; byRaid[id] = x; out[#out + 1] = x end
      x.value = x.value + (tonumber(s.v) or 0)
      x.members[#x.members + 1] = key
    end
  end
  table.sort(out, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.name < b.name end)
  -- best: the highest sum (more than 0); a tie shares the bonus
  local top = out[1] and out[1].value or 0
  for _, x in ipairs(out) do x.best = top > 0 and x.value == top and x.id ~= "x" end
  return out
end

-- set of keys in a best group
function CT.BestMembers(e)
  local set = {}
  for _, g in ipairs(CT.Groups(e)) do if g.best then for _, k in ipairs(g.members) do set[k] = true end end end
  return set
end

-- end of counting (nil = still counting)
function CT.Ended(e)
  if not e then return nil end
  if e.cend then return e.cend end
  local _, to = CT.Window(e)
  if to and U.Now() >= to then return to end
  return nil
end

function CT.Running(e)
  local from = CT.Window(e)
  return CT.Is(e) and U.Now() >= (from or 0) and not CT.Ended(e) and e.status ~= "done" and e.status ~= "cancelled"
end

---------------------------------------------------------------------------
-- Standings: { { key, value, at, place, bonus }, ... } best first
---------------------------------------------------------------------------
function CT.Standings(e)
  local d = CT.Def(e)
  if not d then return {} end
  local low = d.rank == "low"
  local shared = d.ties ~= "first"
  local list = {}
  for key, s in pairs(e.scores or {}) do
    if type(s) == "table" and tonumber(s.v) then
      list[#list + 1] = { key = key, value = tonumber(s.v), at = tonumber(s.at) or 0, bonus = s.bo }
    end
  end
  table.sort(list, function(a, b)
    if a.value ~= b.value then if low then return a.value < b.value end; return a.value > b.value end
    if a.at ~= b.at then return a.at < b.at end
    return a.key < b.key
  end)
  for i, x in ipairs(list) do
    local prev = list[i - 1]
    if prev and prev.value == x.value and shared then x.place = prev.place
    else x.place = i end
  end
  return list
end

function CT.MyScore(e)
  local s = e and e.scores and e.scores[G.MyKey()]
  return s and tonumber(s.v) or nil
end

---------------------------------------------------------------------------
-- Writing scores (only the own; the leader may set bonus suggestions)
---------------------------------------------------------------------------
local function store(e, key, v, at, bo, g)
  e.scores = e.scores or {}
  local old = e.scores[key]
  if old and (tonumber(old.at) or 0) > at and old.v == v then return false end
  e.scores[key] = { v = v, at = at, bo = bo or (old and old.bo), g = g or (old and old.g) }
  return true
end

local function cleanGroup(g)
  if type(g) ~= "table" or type(g.r) ~= "string" then return nil end
  return { r = g.r:sub(1, 60), s = tonumber(g.s) and math.max(0, math.min(8, math.floor(tonumber(g.s)))) or nil }
end

-- the target reached: counting ends at that moment (the same on every client)
local function checkTarget(e, key, v, at)
  if e.cend then return end
  local goal = CT.Goal(e)
  if goal then
    if goal.target and CT.Total(e) >= goal.target then
      e.cend, e.cendWhy, e.cendBy = at, "goal", key
      ns.Fire("CONTEST_END", e, CT.Standings(e))
      ns.Schedule("gemAnnounce" .. e.id, 0.1, function() CT.Announce(e) end)
    end
    return
  end
  local target = CT.Target(e)
  if not target then return end
  local d = CT.Def(e)
  local reached = (d.rank == "low") and v <= target or v >= target
  if reached then
    e.cend, e.cendWhy, e.cendBy = at, "target", key
    ns.Fire("CONTEST_END", e, CT.Standings(e))
    ns.Schedule("gemAnnounce" .. e.id, 0.1, function() CT.Announce(e) end)
  end
end

local function sendLater(e)
  ns.Schedule("gemScore" .. e.id, CT.SEND_DELAY, function()
    local s = e.scores and e.scores[G.MyKey()]
    if s then C.Send("SCORE", { ev = e.id, v = s.v, at = s.at, bo = s.bo, g = s.g }) end
  end)
end

function CT.SetScore(e, v)
  v = tonumber(v)
  if not (e and v and CT.Is(e)) then return false end
  -- an end was reported and waits for the referee: keep counting here only
  if e.cendOpen then e.pend = v; return true end
  if not CT.Running(e) then return false end
  local at = U.Now()
  local me = G.MyKey()
  local old = e.scores and e.scores[me]
  if old and tonumber(old.v) == v then return true end
  store(e, me, v, at, nil, CT.Goal(e) and CT.MyGroup() or nil)
  checkTarget(e, me, v, at)
  ns.Fire("CONTEST_SCORE", e, me)
  sendLater(e)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return true
end

function CT.AddScore(e, d)
  local base = (e and e.cendOpen and e.pend) or CT.MyScore(e) or 0
  return CT.SetScore(e, base + (tonumber(d) or 0))
end

-- a suggested bonus (e.g. "official Master Angler"); the leader decides at the end
function CT.SuggestBonus(e, key, pts, reasonKey)
  if not (e and CT.Is(e)) then return false end
  key = key and G.Resolve(key) or G.MyKey()
  local bo = { p = tonumber(pts) or 0, r = type(reasonKey) == "string" and reasonKey:sub(1, 40) or nil }
  e.scores = e.scores or {}
  local s = e.scores[key] or { v = 0, at = U.Now() }
  s.bo = bo
  e.scores[key] = s
  if key == G.MyKey() then sendLater(e) end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return true
end

-- the module ends counting now (e.g. a chat announcement); told to everyone
function CT.EndContest(e, reason)
  if not (e and CT.Is(e)) then return false end
  if CT.Ended(e) and not e.cendOpen then return false end
  local at = e.cendOpen and e.cend or U.Now()
  e.cend, e.cendWhy = at, type(reason) == "string" and reason:sub(1, 30) or "signal"
  e.cendOpen, e.pend = nil, nil
  C.Send("CEND", { ev = e.id, at = at, why = e.cendWhy })
  ns.Fire("CONTEST_END", e, CT.Standings(e))
  CT.Announce(e)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return true
end

C.On("SCORE", function(data, from)
  local e = data and ns.Events.Get(data.ev)
  local key = from and (G.Resolve(from) or G.Key(from))
  if not (e and key and CT.Is(e)) then return end
  local v, at = tonumber(data.v), tonumber(data.at)
  if not v or not at or at > U.Now() + 300 then return end
  local from_, to = CT.Window(e)
  if at < (from_ or 0) - 60 then return end
  -- reached after counting ended (target, goal, module): does not count
  -- (0.9: places 2 and 3 stand as at the moment of the win)
  if e.cend and not e.cendOpen and at > e.cend then return end
  local bo = type(data.bo) == "table" and { p = tonumber(data.bo.p) or 0, r = type(data.bo.r) == "string" and data.bo.r:sub(1, 40) or nil } or nil
  if store(e, key, v, at, bo, cleanGroup(data.g)) then
    checkTarget(e, key, v, at)
    ns.Fire("CONTEST_SCORE", e, key)
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  end
end)

C.On("CEND", function(data)
  local e = data and ns.Events.Get(data.ev)
  local at = tonumber(data and data.at)
  if not (e and at and CT.Is(e)) then return end
  if e.cend and e.cend <= at and not e.cendOpen then return end
  e.cend, e.cendWhy = math.min(at, e.cend or at), type(data.why) == "string" and data.why:sub(1, 30) or "signal"
  e.cendOpen, e.pend = nil, nil
  ns.Fire("CONTEST_END", e, CT.Standings(e))
  CT.Announce(e)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

---------------------------------------------------------------------------
-- "Report end" (0.9): a participant reports an end his client may not have
-- seen itself ("the tournament is over"). The first report stops counting
-- for everyone for now; the event leader (referee) confirms it – counting
-- ended at the reported time – or lets counting go on. Values counted in the
-- meantime are kept locally and sent when counting goes on.
---------------------------------------------------------------------------
function CT.CanReport(e)
  if not (e and CT.Is(e)) or not CT.Running(e) then return false end
  local d = CT.Def(e)
  if d.reportEnd == false then return false end
  local me = G.MyKey()
  return ns.Events.IsSigned(e, me) or ns.Events.CanManage(e) or (e.scores and e.scores[me] ~= nil) or false
end

local function reported(e, at, why, by)
  e.cend, e.cendWhy, e.cendBy, e.cendOpen = at, why, by, true
  ns.Fire("CONTEST_REPORT", e, by)
  if ns.Events.CanManage(e) then
    local text = ns.L.END_REPORTED_LEAD:format(G.Display(by), e.name)
    if ns.Catalog.Muted(e) then U.Print(text) else CT.Alert(text) end
  else
    U.Print(ns.L.END_REPORTED:format(G.Display(by), e.name))
  end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function CT.ReportEnd(e, why)
  if not CT.CanReport(e) then return false end
  local at = U.Now()
  why = type(why) == "string" and why:sub(1, 30) or "report"
  reported(e, at, why, G.MyKey())
  C.Send("CREP", { ev = e.id, at = at, why = why })
  return true
end

function CT.Pending(e) return e and e.cendOpen and true or false end

-- the referee: the reported end stands
function CT.ConfirmEnd(e)
  if not (e and e.cendOpen and ns.Events.CanManage(e)) then return false end
  return CT.EndContest(e, e.cendWhy or "report")
end

-- the referee: counting goes on
function CT.Resume(e)
  if not (e and e.cendOpen and ns.Events.CanManage(e)) then return false end
  C.Send("CRES", { ev = e.id, at = e.cend })
  CT.Resumed(e)
  return true
end

function CT.Resumed(e)
  e.cend, e.cendWhy, e.cendBy, e.cendOpen = nil, nil, nil, nil
  local v = e.pend
  e.pend = nil
  if v then CT.SetScore(e, v) end
  ns.Fire("CONTEST_RESUME", e)
  U.Print(ns.L.END_RESUMED:format(e.name))
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

C.On("CREP", function(data, from)
  local e = data and ns.Events.Get(data.ev)
  local at = tonumber(data and data.at)
  local key = from and (G.Resolve(from) or G.Key(from))
  if not (e and at and key and CT.Is(e)) then return end
  if at > U.Now() + 300 then return end
  if e.cend then
    -- the earlier report counts
    if e.cendOpen and at < e.cend then e.cend, e.cendBy = at, key end
    return
  end
  reported(e, at, type(data.why) == "string" and data.why:sub(1, 30) or "report", key)
end)

C.On("CRES", function(data, from)
  local e = data and ns.Events.Get(data.ev)
  local key = from and (G.Resolve(from) or G.Key(from))
  if not (e and key and e.cendOpen) then return end
  if not ns.Events.CanManage(e, key) then return end
  CT.Resumed(e)
end)

-- merge scores and the end of counting when an event update arrives
function CT.Merge(old, new)
  if not old then return end
  local out = {}
  for k, s in pairs(old.scores or {}) do out[k] = s end
  for k, s in pairs(type(new.scores) == "table" and new.scores or {}) do
    if type(s) == "table" and (not out[k] or (tonumber(s.at) or 0) >= (tonumber(out[k].at) or 0)) then out[k] = s end
  end
  new.scores = next(out) and out or nil
  if old.cend and (not new.cend or old.cend < new.cend) then new.cend, new.cendWhy, new.cendBy, new.cendOpen = old.cend, old.cendWhy, old.cendBy, old.cendOpen end
  new.pend = old.pend   -- own, not from the sender
end

---------------------------------------------------------------------------
-- Big messages (API 7)
---------------------------------------------------------------------------
function CT.Alert(text, opts)
  if not text then return end
  opts = opts or {}
  if ns.db and ns.db.alertChat then U.Print(U.Color(U.GOLD, text)); return end
  local shown = false
  if RaidNotice_AddMessage and RaidWarningFrame then
    shown = pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = 1, g = 0.82, b = 0.2 }, opts.seconds or 6)
  end
  U.Print(U.Color(U.GOLD, text))
  if opts.sound ~= false then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
  return shown
end

-- to everyone in the guild with the addon (and here)
function CT.AlertGuild(text, opts)
  CT.Alert(text, opts)
  C.Send("ALERT", { t = tostring(text):sub(1, 160) })
end

-- to those signed up for an event (and here)
function CT.AlertEvent(e, text, opts)
  if not e then return end
  CT.Alert(text, opts)
  C.Send("ALERT", { t = tostring(text):sub(1, 160), ev = e.id })
end

local lastAlert = {}
C.On("ALERT", function(data, from)
  local text = type(data.t) == "string" and data.t or nil
  if not text then return end
  local key = from and (G.Resolve(from) or from) or "?"
  if lastAlert[key] and U.Now() - lastAlert[key] < 60 then return end   -- at most one a minute per sender
  lastAlert[key] = U.Now()
  local e = data.ev and ns.Events.Get(data.ev)
  if data.ev then
    if not e or not ns.Events.IsSigned(e) then return end
  end
  if e and ns.Catalog.Muted(e) then U.Print(text); return end
  CT.Alert(text)
end)

-- the end of a contest: every client tells it once (no message needed: each
-- client sees the end itself), muted modules only in the chat
local function told()
  if not ns.db then return {} end
  ns.db.contestTold = ns.db.contestTold or {}
  return ns.db.contestTold
end

function CT.Announce(e)
  if not e or told()[e.id] then return end
  told()[e.id] = U.Now()
  local list = CT.Standings(e)
  local text
  local goal = CT.Goal(e)
  if goal then
    local total = CT.Total(e)
    if CT.GoalReached(e) then
      local best = {}
      for _, g in ipairs(CT.Groups(e)) do if g.best then best[#best + 1] = g.name end end
      text = ns.L.GOAL_REACHED:format(e.name, total, goal.target or 0, goal.reward)
      if #best > 0 and goal.bonus > 0 then text = text .. " " .. ns.L.GOAL_BEST:format(table.concat(best, ", "), goal.bonus) end
    else
      text = ns.L.GOAL_MISSED:format(e.name, total, goal.target or 0)
    end
    if ns.Catalog.Muted(e) then U.Print(text) else CT.Alert(text) end
    return
  end
  if list[1] then
    text = ns.L.CONTEST_END_LEAD:format(e.name, G.Display(list[1].key), CT.Format(e, list[1].value))
  else
    text = ns.L.CONTEST_END_NONE:format(e.name)
  end
  if ns.Catalog.Muted(e) then U.Print(text) else CT.Alert(text) end
end

function CT.Format(e, v)
  local d = CT.Def(e)
  if d and type(d.format) == "function" then
    local ok, s = pcall(d.format, v, e)
    if ok and s then return tostring(s) end
  end
  return tostring(v)
end

-- the leader sent the final result: a second message with the places
function CT.AnnounceResult(e)
  local r = e and e.result
  if not r or type(r.rows) ~= "table" then return end
  local key = "r" .. e.id
  if told()[key] then return end
  told()[key] = U.Now()
  local parts = {}
  for _, x in ipairs(r.rows) do
    if x.pl and x.pl <= 3 then parts[#parts + 1] = x.pl .. ". " .. G.Display(x.k) end
  end
  if #parts == 0 then return end
  local text = ns.L.CONTEST_RESULT:format(e.name, table.concat(parts, " · "))
  if ns.Catalog.Muted(e) then U.Print(text) else CT.Alert(text) end
end

-- every 30 s with the event tick: contests whose window ended
function CT.Tick()
  for _, e in pairs((ns.Store() or {}).events or {}) do
    if CT.Is(e) and not told()[e.id] and not e.cendOpen and e.status ~= "cancelled" and CT.Ended(e) and U.Now() >= (e.start or 0) then
      if U.Now() - CT.Ended(e) < 3600 then CT.Announce(e) else told()[e.id] = U.Now() end
    end
  end
end
