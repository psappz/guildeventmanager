local ADDON, ns = ...
-- Teams (0.9, API 7): events with group "teams" split the sign-ups into
-- teams with a leader each. The event leaders draw them (random, balanced or
-- by hand), adjust them and publish them; every member sees his team.
--
-- e.teams = { size = n, list = { { lead = key, m = { key, ... } } }, pub = ts, by = key }
-- Rest rule (decided 20.11.): a small rest is spread over the teams; a rest of
-- half a team or more – or more than one extra player per team – becomes an
-- own, smaller team; no team above 40.
-- Default leader of a team/group: the highest guild rank among its healers,
-- then alphabetical; without healers the highest rank of the team.
local U, G = ns.U, ns.Guild
local T = {}
ns.Teams = T
T.MAX = 40
T.NAME_MAX = 24

-- players who take part: sign-ups "in" (and "late"), as persons' characters
function T.Players(e, noLeaders)
  local out = {}
  for _, s in ipairs(ns.Events.SignupList(e)) do
    if (s.st == "in" or s.st == "late") and not (noLeaders and ns.Events.IsLeader(e, s.key)) then out[#out + 1] = s.key end
  end
  return out
end

-- Event leaders: drawn into the teams only with "include leadership";
-- otherwise they stay on the bench as event managers (0.9)
function T.IsEventLead(e, key) return ns.Events.IsLeader(e, key) end
function T.WithLead(e, t)
  t = t or T.Get(e)
  if t and t.withLead ~= nil then return t.withLead end
  return ns.db and ns.db.teamsWithLead or false
end
-- players that are drawn
function T.DrawPlayers(e, withLead) return T.Players(e, not withLead) end

-- team sizes for n players: { size, count, rest } – the result of the rest rule
function T.Split(n, size)
  size = math.max(1, math.min(T.MAX, math.floor(size or 5)))
  if n <= 0 then return {} end
  local k = math.floor(n / size)
  local r = n - k * size
  local sizes = {}
  for i = 1, k do sizes[i] = size end
  if r > 0 then
    if k == 0 or r >= size / 2 or r > k or size + 1 > T.MAX then
      sizes[#sizes + 1] = r                     -- own, smaller team
    else
      for i = 1, r do sizes[i] = sizes[i] + 1 end   -- spread
    end
  end
  return sizes
end

-- suggestions by the number of sign-ups: up to three even splits ("5 teams of 2")
function T.Suggest(n)
  local out = {}
  if n < 2 then return out end
  local seen = {}
  local prefer = { 5, 2, 3, 4, 10, 20, 40, 6, 8 }
  for _, s in ipairs(prefer) do
    if s <= n and s <= T.MAX and n % s == 0 and n / s >= 2 and not seen[s] then
      seen[s] = true
      out[#out + 1] = { size = s, count = n / s }
    end
    if #out >= 3 then break end
  end
  if #out == 0 then
    local s = math.min(5, n)
    local sz = T.Split(n, s)
    out[1] = { size = s, count = #sz, uneven = true }
  end
  return out
end

-- healer? (sign-up role, then class)
local HEAL_CLASS = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }
local function isHealer(e, key)
  local s = e.signups and e.signups[key]
  local f = s and s.f
  if type(f) == "table" then
    for _, v in pairs(f) do if v == "heal" or v == "healer" then return true end end
    for _, v in pairs(f) do if v == "tank" or v == "dps" or v == "melee" or v == "ranged" then return false end end
  end
  return false
end
T.IsHealer = function(e, key)
  if isHealer(e, key) then return true end
  local pve = ns.API and ns.API.pve
  local s = pve and pve.Spec and pve.Spec(key)
  return s and s.m and s.m[2] == "heal" or false
end

-- Tank (0.9): set by the leaders by hand (icon on/off), else the sign-up role
-- (tank, mt, ot) or a tank spec in the raid profile (main or second spec)
local TANK = { tank = true, mt = true, ot = true }
function T.SpecTank(e, key)
  local s = e and e.signups and e.signups[key]
  if s and type(s.f) == "table" then for _, v in pairs(s.f) do if TANK[v] then return true end end end
  local pve = ns.API and ns.API.pve
  local sp = pve and pve.Spec and pve.Spec(key)
  if sp and ((sp.m and TANK[sp.m[2]]) or (sp.o and TANK[sp.o[2]])) then return true end
  return false
end
function T.IsTank(e, key)
  local t = T.Get(e)
  if t and t.tank and t.tank[key] ~= nil then return t.tank[key] end
  return T.SpecTank(e, key)
end
function T.SetTank(e, key, on)
  if not T.CanEdit(e) then return false end
  local t = U.Copy(T.Get(e) or { size = 5, list = {} })
  t.tank = t.tank or {}
  if (on and true or false) == T.SpecTank(e, key) then t.tank[key] = nil else t.tank[key] = on and true or false end
  T.Set(e, t)
  return true
end
-- the event needs tanks: one tank per team when drawing, warning without
function T.NeedTank(e, t)
  t = t or T.Get(e)
  if t and t.needTank ~= nil then return t.needTank end
  return false
end

local function rankOf(key) return G.RankOf(key) or 99 end

-- default leader of a list of keys
function T.DefaultLeader(e, keys)
  local best
  local function better(a, b)
    if not b then return true end
    local ha, hb = T.IsHealer(e, a), T.IsHealer(e, b)
    if ha ~= hb then return ha end
    local ra, rb = rankOf(a), rankOf(b)
    if ra ~= rb then return ra < rb end
    return G.Display(a) < G.Display(b)
  end
  for _, k in ipairs(keys or {}) do if better(k, best) then best = k end end
  return best
end

-- deterministic random numbers from the event id (all clients draw the same)
local function rng(seed)
  local h = 0
  for i = 1, #seed do h = (h * 31 + seed:byte(i)) % 2147483647 end
  if h == 0 then h = 1 end
  return function(n)
    h = (h * 48271) % 2147483647
    return (h % n) + 1
  end
end

-- Draws teams: mode "random" | "balanced" | "manual" (all unassigned)
function T.Draw(e, size, mode, withLead, needTank)
  if withLead == nil then withLead = T.WithLead(e) end
  if needTank == nil then needTank = T.NeedTank(e) end
  local players = T.DrawPlayers(e, withLead)
  table.sort(players)
  local sizes = T.Split(#players, size)
  local list = {}
  for i = 1, #sizes do list[i] = { m = {} } end
  -- tanks first: one per team (random order for "random")
  if needTank and mode ~= "manual" then
    local tanks, rest = {}, {}
    for _, k in ipairs(players) do if T.IsTank(e, k) then tanks[#tanks + 1] = k else rest[#rest + 1] = k end end
    if mode == "random" then
      local r = rng(tostring(e.id) .. ":t:" .. tostring(size))
      for i = #tanks, 2, -1 do local j = r(i); tanks[i], tanks[j] = tanks[j], tanks[i] end
    end
    local n = math.min(#tanks, #sizes)
    for i = 1, n do list[i].m[1] = tanks[i] end
    for i = n + 1, #tanks do rest[#rest + 1] = tanks[i] end
    players = rest
    if mode ~= "random" then table.sort(players) end
  end
  if mode == "random" then
    local r = rng(tostring(e.id) .. ":" .. tostring(size))
    for i = #players, 2, -1 do local j = r(i); players[i], players[j] = players[j], players[i] end
    local p = 1
    for i, n in ipairs(sizes) do while #list[i].m < n and players[p] do list[i].m[#list[i].m + 1] = players[p]; p = p + 1 end end
  elseif mode == "balanced" then
    -- healers first, spread; then by level, snake order
    table.sort(players, function(a, b)
      local ha, hb = T.IsHealer(e, a), T.IsHealer(e, b)
      if ha ~= hb then return ha end
      local la = (G.roster[a] and G.roster[a].level) or 0
      local lb = (G.roster[b] and G.roster[b].level) or 0
      if la ~= lb then return la > lb end
      return a < b
    end)
    local i, d = 1, 1
    for _, k in ipairs(players) do
      local guard = 0
      while #list[i].m >= sizes[i] and guard < #sizes * 2 do
        i = i + d
        if i > #sizes then i, d = #sizes, -1 elseif i < 1 then i, d = 1, 1 end
        guard = guard + 1
      end
      list[i].m[#list[i].m + 1] = k
      i = i + d
      if i > #sizes then i, d = #sizes, -1 elseif i < 1 then i, d = 1, 1 end
    end
  end
  for i, t in ipairs(list) do t.lead = T.DefaultLeader(e, t.m); t.id = i end
  local old = T.Get(e)
  return { size = size, list = list, withLead = withLead and true or false, needTank = needTank and true or false,
    tank = old and old.tank and U.Copy(old.tank) or nil }
end

-- keeps only what a team list may hold (received data)
function T.Clean(t)
  if type(t) ~= "table" or type(t.list) ~= "table" then return nil end
  local out = { size = math.max(1, math.min(T.MAX, tonumber(t.size) or 5)), list = {},
    pub = tonumber(t.pub), by = type(t.by) == "string" and t.by or nil, v = tonumber(t.v),
    withLead = t.withLead == true, needTank = t.needTank == true }
  if type(t.tank) == "table" then
    out.tank = {}
    local n = 0
    for k, v in pairs(t.tank) do
      if type(k) == "string" and type(v) == "boolean" and n < 200 then out.tank[k] = v; n = n + 1 end
    end
  end
  for i, team in ipairs(t.list) do
    if i > 100 then break end
    local m = {}
    if type(team) == "table" and type(team.m) == "table" then
      for j, k in ipairs(team.m) do if j <= T.MAX and type(k) == "string" then m[#m + 1] = k end end
    end
    local nm = type(team) == "table" and type(team.name) == "string" and team.name:gsub("[|\n]", ""):sub(1, T.NAME_MAX) or nil
    out.list[#out.list + 1] = { m = m, lead = type(team) == "table" and type(team.lead) == "string" and team.lead or nil,
      id = type(team) == "table" and tonumber(team.id) or nil, name = (nm and nm ~= "") and nm or nil }
  end
  T.Ids(out)
  return out
end

-- every team has a fixed id (1, 2, 3 …) – its unique identifier; the name
-- can be changed, without one the team is called "Team <id>"
function T.Ids(t)
  local used, top = {}, 0
  for _, team in ipairs(t.list) do
    if team.id and not used[team.id] then used[team.id] = true; top = math.max(top, team.id) else team.id = nil end
  end
  for _, team in ipairs(t.list) do if not team.id then top = top + 1; team.id = top end end
  return t
end

function T.Name(team, i)
  if type(team) ~= "table" then return "" end
  return team.name or ns.L.TM_TEAM_N:format(team.id or i or 0)
end

function T.Get(e) return type(e) == "table" and type(e.teams) == "table" and e.teams or nil end

-- team index and team of a member
function T.Of(e, key)
  local t = T.Get(e)
  if not t then return nil end
  for i, team in ipairs(t.list or {}) do
    for _, k in ipairs(team.m or {}) do if k == key then return i, team end end
  end
end

-- signed-up players not in a team
function T.Unassigned(e)
  local out, seen = {}, {}
  for _, k in ipairs(T.Players(e)) do if not T.Of(e, k) then out[#out + 1] = k; seen[k] = true end end
  for _, k in ipairs(ns.Events.Leaders(e)) do if not seen[k] and not T.Of(e, k) then out[#out + 1] = k end end
  table.sort(out, function(a, b)
    local la, lb = T.IsEventLead(e, a), T.IsEventLead(e, b)
    if la ~= lb then return la end
    return G.Display(a) < G.Display(b)
  end)
  return out
end

-- changes (event leaders / managers): saved with the event
local function save(e, t)
  e.teams = t
  t.by, t.v = G.MyKey(), U.Now()
  ns.Events.Save(e)
  ns.Fire("TEAMS_CHANGED", e)
end

function T.CanEdit(e) return ns.Events.CanManage(e) end

function T.Set(e, t) if T.CanEdit(e) then save(e, t) return true end return false end

-- moves a player into team i (0 = unassigned); keeps the team leader valid
function T.Move(e, key, i)
  if not T.CanEdit(e) then return false end
  local t = U.Copy(T.Get(e) or { size = 5, list = {} })
  for _, team in ipairs(t.list) do
    for k = #team.m, 1, -1 do if team.m[k] == key then table.remove(team.m, k) end end
    if team.lead == key then team.lead = nil end
  end
  if i and i > 0 then
    while #t.list < i do t.list[#t.list + 1] = { m = {} } end
    local team = t.list[i]
    if #team.m < T.MAX then team.m[#team.m + 1] = key end
  end
  for _, team in ipairs(t.list) do if not team.lead then team.lead = T.DefaultLeader(e, team.m) end end
  save(e, t)
  return true
end

-- swaps two players (drag onto a name)
function T.Swap(e, a, b)
  if not T.CanEdit(e) or a == b then return false end
  local t = U.Copy(T.Get(e) or { size = 5, list = {} })
  local function where(key)
    for i, team in ipairs(t.list) do for k, x in ipairs(team.m) do if x == key then return i, k end end end
  end
  local ia, ka = where(a)
  local ib, kb = where(b)
  if ia and ib then t.list[ia].m[ka], t.list[ib].m[kb] = b, a
  elseif ia then t.list[ia].m[ka] = b
  elseif ib then t.list[ib].m[kb] = a end
  for _, team in ipairs(t.list) do
    local ok = false
    for _, k in ipairs(team.m) do if k == team.lead then ok = true end end
    if not ok then team.lead = T.DefaultLeader(e, team.m) end
  end
  save(e, t)
  return true
end

function T.SetLeader(e, key)
  if not T.CanEdit(e) then return false end
  local i = T.Of(e, key)
  if not i then return false end
  local t = U.Copy(T.Get(e))
  t.list[i].lead = key
  save(e, t)
  return true
end

function T.AddTeam(e)
  if not T.CanEdit(e) then return false end
  local t = U.Copy(T.Get(e) or { size = 5, list = {} })
  t.list[#t.list + 1] = { m = {} }
  T.Ids(t)
  save(e, t)
  return true
end

function T.RemoveEmpty(e)
  if not T.CanEdit(e) then return false end
  local t = U.Copy(T.Get(e) or { size = 5, list = {} })
  for i = #t.list, 1, -1 do if #t.list[i].m == 0 then table.remove(t.list, i) end end
  save(e, t)
  return true
end

-- renames team i ("" = back to "Team <id>")
function T.Rename(e, i, name)
  if not T.CanEdit(e) or not T.Get(e) then return false end
  local t = U.Copy(T.Get(e))
  if not t.list[i] then return false end
  name = tostring(name or ""):gsub("[|\n]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, T.NAME_MAX)
  t.list[i].name = name ~= "" and name or nil
  save(e, t)
  return true
end

-- deletes team i; its members are "not assigned" again
function T.Delete(e, i)
  if not T.CanEdit(e) or not T.Get(e) then return false end
  local t = U.Copy(T.Get(e))
  if not t.list[i] then return false end
  table.remove(t.list, i)
  save(e, t)
  return true
end

-- publish: every member sees the teams (and a chat line); team leaders invite
function T.Publish(e)
  if not T.CanEdit(e) or not T.Get(e) then return false end
  local t = U.Copy(T.Get(e))
  t.pub = U.Now()
  save(e, t)
  if ns.Contest and ns.Contest.AlertEvent then
    pcall(ns.Contest.AlertEvent, e, ns.L.TM_PUBLISHED:format(e.name or "", #t.list))
  end
  return true
end

-- team standings in a contest: sum of the members' values
function T.Standings(e)
  local t = T.Get(e)
  if not t or not ns.Contest then return {} end
  local val = {}
  for _, s in ipairs(ns.Contest.Standings(e) or {}) do val[s.key] = (val[s.key] or 0) + (s.value or 0) end
  local out = {}
  for i, team in ipairs(t.list) do
    local sum = 0
    for _, k in ipairs(team.m) do sum = sum + (val[k] or 0) end
    out[#out + 1] = { team = i, id = team.id, name = T.Name(team, i), lead = team.lead, value = sum, members = team.m }
  end
  table.sort(out, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.team < b.team end)
  local place, last = 0, nil
  for i, x in ipairs(out) do
    if x.value ~= last then place = i; last = x.value end
    x.place = place
  end
  return out
end

---------------------------------------------------------------------------
-- Test event (/gem testteams [n] | off): a local "teams" event with n sign-ups
-- from the guild roster (invented names if the guild is smaller). It is never
-- sent (Comm drops test events) and /gem testteams off removes it.
---------------------------------------------------------------------------
local FAKE = { "Durgash", "Krazja", "Morvok", "Telanis", "Zulkara", "Brakkar", "Ishara", "Gorrum", "Velith",
  "Nazgrul", "Shaari", "Torvak", "Mirela", "Ruktar", "Fenlira", "Ogrash", "Senjin", "Kaelris", "Grimtok", "Yasha" }

function T.RemoveTest()
  local s = ns.Store()
  local n = 0
  for id, e in pairs(s and s.events or {}) do if e.test then s.events[id] = nil; n = n + 1 end end
  return n
end

function T.CreateTest(n)
  n = math.max(2, math.min(80, tonumber(n) or 23))
  local s = ns.Store()
  if not s then return nil end
  s.events = s.events or {}
  T.RemoveTest()
  local keys = {}
  for k in pairs(G.roster) do keys[#keys + 1] = k end
  table.sort(keys)
  local realm = (G.MyKey() or "x@EU"):match("@(.+)$") or "EU"
  local i = 1
  while #keys < n do keys[#keys + 1] = (FAKE[(i - 1) % #FAKE + 1] .. (i > #FAKE and tostring(math.floor((i - 1) / #FAKE) + 1) or "")) .. "@" .. realm; i = i + 1 end
  local e = {
    id = "test-" .. U.NewId(), type = "meet", test = true,
    name = ns.L.TM_TEST_NAME, desc = ns.L.TM_TEST_DESC,
    leader = G.MyKey(), leaders = { G.MyKey() }, kind = "short",
    start = U.Now() + 3600, group = "teams", status = "planned",
    signups = {}, created = U.Now(), by = G.MyKey(), upd = U.Now(),
  }
  local roles = { "heal", "tank", "dps", "dps", "dps" }
  for j = 1, n do
    e.signups[keys[j]] = { st = "in", on = true, t = U.Now() - n + j, f = { role = roles[(j - 1) % #roles + 1] } }
  end
  s.events[e.id] = e
  ns.Fire("EVENT_UPDATED", e, true)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return e
end

ns.SlashExt = ns.SlashExt or {}
ns.SlashExt.testteams = function(rest)
  local L = ns.L
  if (rest or ""):lower() == "off" then U.Print(L.TM_TEST_OFF:format(T.RemoveTest())); if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end return end
  local e = T.CreateTest(tonumber(rest))
  if not e then return end
  U.Print(L.TM_TEST_ON:format(#T.Players(e)))
  if ns.UI and ns.UI.Show then ns.UI.Show("events") end
  if ns.UITeams then ns.UITeams.Show(e) end
end
