local ADDON, ns = ...
-- Recurring events (API 7). An event with e.rep = { every = "day"|"week"|"month",
-- n = 1|2, untilTs } belongs to a series (e.series). The clients of event
-- managers keep the next four weeks of a series as real events; their ids come
-- from the series and the date, so two managers never create the same date
-- twice. Members can say yes "for the whole series": future dates take over
-- that answer. A date that was cancelled stays cancelled.
local U, G = ns.U, ns.Guild
local E = ns.Events
local S = {}
ns.Series = S

S.AHEAD = 28 * 86400
S.EVERY = { day = true, week = true, month = true }

local function events()
  local s = ns.Store()
  return s and s.events or {}
end

-- cleaned repeat rule or nil
function S.Clean(rep)
  if type(rep) ~= "table" or not S.EVERY[rep.every] then return nil end
  local n = math.floor(tonumber(rep.n) or 1)
  if n < 1 or n > 4 then n = 1 end
  local untilTs = tonumber(rep.untilTs)
  return { every = rep.every, n = n, untilTs = untilTs }
end

-- the next start after ts (same time of day; months: same day of the month)
function S.Next(rep, ts)
  if rep.every == "day" then return ts + rep.n * 86400 end
  if rep.every == "week" then return ts + rep.n * 7 * 86400 end
  local d = date("*t", ts)
  d.month = d.month + rep.n
  while d.month > 12 do d.month = d.month - 12; d.year = d.year + 1 end
  local day = d.day
  -- e.g. the 31st in a short month: the last day of that month
  for dd = day, 28, -1 do
    d.day = dd
    local t = time(d)
    if tonumber(date("%d", t)) == dd then return t end
  end
  return time(d)
end

function S.IdFor(series, ts) return tostring(series):sub(1, 16) .. "_" .. date("%Y%m%d", ts) end

-- all events of a series, by start
function S.Members(series)
  local list = {}
  for _, e in pairs(events()) do if e.series == series then list[#list + 1] = e end end
  table.sort(list, function(a, b) return (a.start or 0) < (b.start or 0) end)
  return list
end

-- fields a new date takes over from the latest date of the series
S.COPY = { "type", "name", "desc", "kind", "group", "gmin", "gmax", "lvl", "remind", "pts", "fields", "set", "rep", "series", "leader" }

local function newDate(tpl, start)
  local e = {}
  for _, k in ipairs(S.COPY) do e[k] = ns.U.Copy(tpl[k]) end
  e.id = S.IdFor(tpl.series, start)
  e.start = start
  if tpl.finish then e.finish = start + (tpl.finish - tpl.start) end
  if tpl.goals then
    e.goals = {}
    for _, g in ipairs(tpl.goals) do e.goals[#e.goals + 1] = { text = g.text, done = false } end
  end
  e.status, e.signups, e.created, e.by = "planned", {}, U.Now(), G.MyKey()
  -- answers "for the whole series" go along
  for key, s in pairs(tpl.signups or {}) do
    if type(s) == "table" and s.all then e.signups[key] = { on = s.on, st = s.st, c = s.c, f = s.f, t = U.Now(), lv = s.lv, all = true } end
  end
  return e
end

-- the clients of managers fill every series up to four weeks ahead
function S.Fill()
  if ns.demo or not G.IsActivated() or not G.IsManager() then return 0 end
  local now, made = U.Now(), 0
  local seen = {}
  for _, e in pairs(events()) do
    if e.series and not seen[e.series] and S.Clean(e.rep) then
      seen[e.series] = true
      local list = S.Members(e.series)
      local tpl
      for i = #list, 1, -1 do if S.Clean(list[i].rep) then tpl = list[i]; break end end
      if tpl and E.CanManage(tpl) then
        local rep = S.Clean(tpl.rep)
        local start = tpl.start
        local guard = 0
        while guard < 40 do
          guard = guard + 1
          start = S.Next(rep, start)
          if start > now + S.AHEAD then break end
          if rep.untilTs and start > rep.untilTs then break end
          local id = S.IdFor(tpl.series, start)
          if not events()[id] and start > now then
            local ne = newDate(tpl, start)
            E.Save(ne)
            made = made + 1
          end
        end
      end
    end
  end
  return made
end

---------------------------------------------------------------------------
-- Changes for the rest of the series
---------------------------------------------------------------------------
S.EDIT_KEYS = { "type", "name", "desc", "kind", "group", "gmin", "gmax", "lvl", "remind", "pts", "goals", "fields", "set", "rep" }

-- apply the fields of e to every planned later date of its series (time of day and length too)
function S.ApplyFollowing(e)
  if not e.series then return 0 end
  local n = 0
  for _, x in ipairs(S.Members(e.series)) do
    if x.id ~= e.id and (x.start or 0) > (e.start or 0) and x.status == "planned" then
      for _, k in ipairs(S.EDIT_KEYS) do x[k] = U.Copy(e[k]) end
      -- same date, the new time of day
      local d = date("*t", x.start)
      local ed = date("*t", e.start)
      d.hour, d.min, d.sec = ed.hour, ed.min, ed.sec
      local len = e.finish and (e.finish - e.start) or nil
      x.start = time(d)
      x.finish = len and (x.start + len) or nil
      if x.goals then for _, g in ipairs(x.goals) do g.done = false end end
      E.Save(x)
      n = n + 1
    end
  end
  return n
end

-- cancel this date and all later planned dates; the series stops here
function S.CancelFollowing(e)
  if not e.series then E.Cancel(e); return 1 end
  local n = 0
  for _, x in ipairs(S.Members(e.series)) do
    if (x.start or 0) >= (e.start or 0) and x.status == "planned" then
      if x.rep then x.rep = S.Clean(x.rep); x.rep.untilTs = (e.start or 0) - 1 end
      E.Cancel(x)
      n = n + 1
    end
  end
  -- earlier dates must not create new ones either
  for _, x in ipairs(S.Members(e.series)) do
    if (x.start or 0) < (e.start or 0) and x.rep and E.CanManage(x) then
      x.rep = S.Clean(x.rep); x.rep.untilTs = (e.start or 0) - 1
      E.Save(x)
    end
  end
  return n
end

---------------------------------------------------------------------------
-- Sign-up for the whole series (member)
---------------------------------------------------------------------------
function S.SignAll(e, opts)
  local n = 0
  for _, x in ipairs(S.Members(e.series)) do
    if x.status == "planned" and (x.start or 0) >= (e.start or 0) then
      local o = U.Copy(opts); o.all = true
      if E.SetSignup(x, o) then n = n + 1 end
    end
  end
  return n
end

-- managers fill the series after login and every ten minutes
ns.On("ACTIVATED", function() ns.Schedule("gemSeries", 10, function() ns.SafeCall("series", S.Fill) end) end)
function S.Tick()
  S.last = S.last or 0
  if U.Now() - S.last < 600 then return end
  S.last = U.Now()
  S.Fill()
end
