local ADDON, ns = ...
-- Guild events: announced, started and ended by guild event managers.
-- Run types: short (one evening), multiday, multiweek, season (whole season).
-- Group requirement: none, party, raid, teams.
local U, G, C, T = ns.U, ns.Guild, ns.Comm, ns.Theme
local E = {}
ns.Events = E

E.KINDS = { "short", "multiday", "multiweek", "season" }
E.GROUPS = { "none", "party", "raid", "teams" }
E.STATUS = { planned = 1, running = 2, done = 3, cancelled = 4 }

local function events()
  local s = ns.Store()
  return s and s.events or {}
end

function E.Get(id) return events()[id] end

-- Sorted: running, planned (soonest first), then done/cancelled (newest first)
function E.List(filter)
  local list = {}
  for _, e in pairs(events()) do
    if not filter or filter(e) then list[#list + 1] = e end
  end
  table.sort(list, function(a, b)
    local sa, sb = E.STATUS[a.status] or 9, E.STATUS[b.status] or 9
    if sa ~= sb then return sa < sb end
    if sa <= 2 then return (a.start or 0) < (b.start or 0) end
    return (a.start or 0) > (b.start or 0)
  end)
  return list
end

function E.IsOpen(e) return e.status == "planned" or e.status == "running" end

function E.Icon(e)
  local t = ns.Modules.Type(e.type)
  return (t and t.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function E.TypeMissing(e) return ns.Modules.Type(e.type) == nil end

---------------------------------------------------------------------------
-- Writing (managers)
---------------------------------------------------------------------------
local function send(e) C.Send("EVT", { e = e }) end

function E.Save(e)
  if not G.IsManager() then U.Print(ns.L.NO_RIGHTS); return nil end
  e.upd = math.max(U.Now(), (e.upd or 0) + 1)
  events()[e.id] = e
  send(e)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return e
end

-- fields: type, name, desc, kind, start, finish, group, gmin, gmax
function E.Create(fields)
  if not G.IsManager() then U.Print(ns.L.NO_RIGHTS); return nil end
  local t = ns.Modules.Type(fields.type)
  local e = {
    id = U.NewId(), type = fields.type,
    name = (fields.name and fields.name ~= "") and fields.name or ns.Modules.TypeName(fields.type),
    desc = fields.desc or "",
    leader = fields.leader or G.MyKey(),
    kind = fields.kind or (t and t.kind) or "short",
    start = fields.start or U.Now(),
    finish = fields.finish,
    group = fields.group or (t and t.group) or "none",
    gmin = fields.gmin, gmax = fields.gmax,
    pts = fields.pts,  -- own participation points, nil = profile default
    goals = fields.goals, -- { { text, done } }
    status = "planned", signups = {}, created = U.Now(), by = G.MyKey(),
  }
  if e.kind == "season" then
    e.start = ns.Points.SeasonStart(); e.finish = ns.Points.SeasonEnd()
  end
  E.Save(e)
  U.Print(ns.L.EVT_ANNOUNCED:format(e.name))
  return e
end

function E.Start(e)
  e.status = "running"; e.started = U.Now()
  E.Save(e)
  C.Send("EVTSTART", { ev = e.id })
end

function E.Cancel(e)
  e.status = "cancelled"
  E.Save(e)
end

-- attended: { key = true }; writes participation and organiser points
function E.End(e, attended)
  local p = ns.Profile.Get()
  local per = tonumber(e.pts) or p.pts.participate
  local n = 0
  e.attended = {}
  local done, total = E.GoalCount(e)
  local full = total > 0 and done == total
  for key, on in pairs(attended or {}) do
    if on then
      e.attended[key] = true
      n = n + 1
      if per > 0 then ns.Points.Add(key, "event", per, "participate", e.id, nil, full and { flag = "full" } or nil) end
      if done > 0 and (p.pts.goal or 0) > 0 then ns.Points.Add(key, "event", done * p.pts.goal, "goal", e.id) end
    end
  end
  if n >= (p.pts.leadMin or 5) and (p.pts.lead or 0) > 0 and e.leader then
    ns.Points.Add(e.leader, "event", p.pts.lead, "lead", e.id)
  end
  e.status = "done"; e.ended = U.Now()
  E.Save(e)
  U.Print(ns.L.EVT_ENDED:format(e.name, n))
end

function E.GoalCount(e)
  local done, total = 0, 0
  for _, g in ipairs(e.goals or {}) do
    total = total + 1
    if g.done then done = done + 1 end
  end
  return done, total
end

function E.ToggleGoal(e, i)
  local g = e.goals and e.goals[i]
  if not g or not G.IsManager() then return end
  g.done = not g.done
  E.Save(e)
end

-- Everyone who could have taken part: guild members in my group plus sign-ups
function E.Candidates(e)
  local list, have = {}, {}
  local function add(key, inGroup)
    if key and G.roster[key] and not have[key] then
      have[key] = true
      list[#list + 1] = { key = key, inGroup = inGroup, signed = E.IsSigned(e, key) }
    end
  end
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  if n > 0 then
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
      local unit = raid and ("raid" .. i) or (i == n and "player" or ("party" .. i))
      add(G.UnitKey(unit), true)
    end
  else
    add(G.MyKey(), true)
  end
  for key, s in pairs(e.signups or {}) do if s.on then add(key, false) end end
  table.sort(list, function(a, b) return G.Display(a.key) < G.Display(b.key) end)
  return list
end

---------------------------------------------------------------------------
-- Sign-ups (every member)
---------------------------------------------------------------------------
function E.IsSigned(e, key)
  local s = e.signups and e.signups[key or G.MyKey()]
  return s and s.on or false
end

function E.SignCount(e)
  local n = 0
  for _, s in pairs(e.signups or {}) do if s.on then n = n + 1 end end
  return n
end

function E.SignUp(e, on)
  if not C.CanSend() and not ns.demo then U.Print(ns.L.NOT_ACTIVE); return end
  e.signups = e.signups or {}
  e.signups[G.MyKey()] = { on = on and true or false, t = U.Now() }
  C.Send("SIGN", { ev = e.id, on = on and true or false })
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function mergeSignups(old, new)
  local out = {}
  for k, v in pairs(old or {}) do out[k] = v end
  for k, v in pairs(new or {}) do
    if type(v) == "table" and (not out[k] or (tonumber(v.t) or 0) >= (tonumber(out[k].t) or 0)) then out[k] = v end
  end
  return out
end

C.On("EVT", function(data, from)
  local e = data.e
  if type(e) ~= "table" or not e.id then return end
  if not G.IsManager(from) then return end
  local list = events()
  local old = list[e.id]
  if old and (tonumber(old.upd) or 0) >= (tonumber(e.upd) or 0) then
    old.signups = mergeSignups(old.signups, e.signups)
    return
  end
  e.signups = mergeSignups(old and old.signups, e.signups)
  list[e.id] = e
  if not old and E.IsOpen(e) and (U.Now() - (tonumber(e.created) or 0)) < 900 and ns.db.notify ~= false then
    U.Print(ns.L.EVT_NEW:format(T.Word("GUILD"), e.name, U.FormatTime(e.start)))
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  end
  ns.Achievements.Dirty()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

C.On("EVTSTART", function(data)
  local e = data.ev and E.Get(data.ev)
  if not e then return end
  local msg = ns.L.EVT_STARTS_NOW:format(e.name)
  U.Print(U.Color(U.GOLD, msg))
  if RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.8, b = 0 })
  end
end)

C.On("SIGN", function(data, from)
  local e = data.ev and E.Get(data.ev)
  if not e or not from then return end
  e.signups = e.signups or {}
  e.signups[from] = { on = data.on and true or false, t = U.Now() }
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

---------------------------------------------------------------------------
-- Reminders: 10 minutes before a planned event (for sign-ups and managers),
-- and a short summary after login
---------------------------------------------------------------------------
local reminded = {}
function E.Tick()
  ns.Schedule("gemEventTick", 30, E.Tick)
  if ns.demo or not G.IsActivated() then return end
  local now = U.Now()
  for _, e in pairs(events()) do
    if e.status == "planned" and e.kind == "short" and not reminded[e.id] then
      local left = (e.start or 0) - now
      if left > 0 and left <= 600 and (E.IsSigned(e) or G.IsManager()) then
        reminded[e.id] = true
        local msg = ns.L.EVT_REMINDER:format(e.name, math.ceil(left / 60))
        U.Print(U.Color(U.GOLD, msg))
        if RaidNotice_AddMessage and RaidWarningFrame then
          pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, { r = 1, g = 0.8, b = 0 })
        end
      end
    end
  end
end

function E.LoginNotice()
  if not G.IsActivated() then return end
  local planned, running = 0, 0
  for _, e in pairs(events()) do
    if e.status == "planned" then planned = planned + 1 elseif e.status == "running" then running = running + 1 end
  end
  if planned + running > 0 then U.Print(ns.L.LOGIN_EVENTS:format(running, planned)) end
end
