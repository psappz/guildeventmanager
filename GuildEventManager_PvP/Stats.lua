local ADDON, P = ...
-- PvP statistics per guild member: honorable kills in the open world and in
-- battlegrounds (this season and since the module counts), the game's own
-- lifetime numbers, dishonorable kills and the PvP rank. Every client sends
-- only its own numbers ("PVPSTAT"); all clients keep the latest of everyone.
local core = P.core
if not core then return end
local U, G, C = core.U, core.Guild, core.Comm
local L = P.L

local function secret(v) return issecretvalue and issecretvalue(v) or false end
local function num(v) if v == nil or secret(v) then return nil end return tonumber(v) end

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  table.remove(r, 1)
  return unpack(r)
end

---------------------------------------------------------------------------
-- Own counters (per character): open world / battleground, all and season
---------------------------------------------------------------------------
local function counters()
  local c = P.Char()
  c.hk = c.hk or { ow = 0, bg = 0, sow = 0, sbg = 0, season = 0 }
  local st = core.Points.SeasonStart()
  if c.hk.season ~= st then c.hk.season = st; c.hk.sow = 0; c.hk.sbg = 0 end
  return c.hk
end

-- The game's day (it ends at the daily reset, not at midnight); nil if unknown
local function gameDay()
  local f = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset
  local left = f and try(f)
  left = num(left)
  if not left then return nil end
  return math.floor((U.Now() + left) / 86400)
end

local function today(h)
  local d = gameDay()
  if not d then return nil end
  if h.day == nil then
    -- first day with this counter: what the game shows so far counts as counted
    h.day = d; h.todayCount = num(try(GetPVPSessionStats)) or 0
  elseif h.day ~= d then
    h.day = d; h.todayCount = 0
  end
  return d
end

-- The game counts every honorable kill of the day (GetPVPSessionStats). Kills the
-- module missed (old version, reconnect, crash before saving) show up there:
-- add the difference, so "Today" and the module's own counts fit together.
function P.ReconcileHK()
  if core.demo then return end
  local h = counters()
  if not today(h) then return end
  local game = num(try(GetPVPSessionStats))
  if not game then return end
  local missing = game - (h.todayCount or 0)
  if missing <= 0 then return end
  local _, kind = IsInInstance()
  if kind == "pvp" or kind == "arena" then h.bg = h.bg + missing; h.sbg = h.sbg + missing
  else h.ow = h.ow + missing; h.sow = h.sow + missing end
  h.todayCount = game
end

-- kind: instance type from IsInInstance ("none", "pvp", "arena", ...)
function P.RecordHK(kind)
  local h = counters()
  if today(h) then h.todayCount = (h.todayCount or 0) + 1 end
  if kind == "pvp" or kind == "arena" then
    h.bg = h.bg + 1; h.sbg = h.sbg + 1
  elseif kind == "none" or kind == nil then
    h.ow = h.ow + 1; h.sow = h.sow + 1
  else
    return
  end
  core.Schedule("gemPvpStatSend", 60, P.SendStats)
end

-- Everything the game tells about the own PvP record (each value may be nil)
function P.OwnStats()
  local h = counters()
  local s = { ow = h.ow, bg = h.bg, sow = h.sow, sbg = h.sbg }
  local hk, dk, highest = try(GetPVPLifetimeStats)
  s.life, s.dk = num(hk), num(dk)
  local today = try(GetPVPSessionStats)
  s.today = num(today)
  local yhk = try(GetPVPYesterdayStats)
  s.yday = num(yhk)
  local whk = try(GetPVPThisWeekStats)
  s.week = num(whk)
  local lhk, _, lrank = try(GetPVPLastWeekStats)
  s.lastweek = num(lhk)
  local rid = try(UnitPVPRank, "player")
  rid = num(rid)
  if rid and rid > 0 then
    s.rank = rid
    s.rankName = try(GetPVPRankInfo, rid)
  end
  highest = num(highest)
  if highest and highest > 0 then
    s.high = highest
    s.highName = try(GetPVPRankInfo, highest)
  end
  local prog = try(GetPVPRankProgress)
  s.prog = num(prog) and math.floor(num(prog) * 100) or nil
  return s
end

local function store()
  local st = core.Store()
  if not st then return {} end
  st.pvpstats = st.pvpstats or {}
  return st.pvpstats
end
P.StatsStore = store

function P.SendStats()
  if core.demo or not C.CanSend() then return end
  core.SafeCall("pvpReconcile", P.ReconcileHK)
  local s = P.OwnStats()
  s.season = counters().season
  s.ts = U.Now()
  store()[G.MyKey()] = s
  C.Send("PVPSTAT", { s = s })
  if core.UI then core.UI.Refresh() end
end

local COUNT = { "ow", "bg", "sow", "sbg" }

C.On("PVPSTAT", function(data, from)
  if type(data.s) ~= "table" or not from then return end
  local s = data.s
  -- numbers from an older season do not count for this season
  if tonumber(s.season) ~= core.Points.SeasonStart() then s.sow, s.sbg = 0, 0 end
  -- the module's own counters only grow: a member whose game crashed or lost
  -- the connection lost the counts of that session (the game saves addon data
  -- only on logout); keep the higher numbers we already know
  local old = store()[from]
  if old and tonumber(old.season) == tonumber(s.season) then
    for _, k in ipairs(COUNT) do
      if (tonumber(old[k]) or 0) > (tonumber(s[k]) or 0) then s[k] = old[k] end
    end
  elseif old then
    for _, k in ipairs({ "ow", "bg" }) do
      if (tonumber(old[k]) or 0) > (tonumber(s[k]) or 0) then s[k] = old[k] end
    end
  end
  s.ts = U.Now()
  store()[from] = s
  if core.UI then core.UI.Refresh() end
end)

-- Somebody logged in: everyone answers with his own numbers (spread out),
-- and one member gives him back what the guild knows of him, so counts lost
-- by a crash or a disconnect come back.
C.On("HELLO", function(_, from)
  core.Schedule("gemPvpStatSend", 3 + math.random() * 12, P.SendStats)
  local known = from and store()[from]
  if known and from ~= G.MyKey() then
    core.Schedule("gemPvpBack" .. from, 1 + math.random() * 6, function()
      C.Send("PVPSTATBACK", { to = from, s = { ow = known.ow, bg = known.bg, sow = known.sow, sbg = known.sbg, season = known.season } })
    end)
  end
end)

C.On("PVPSTATBACK", function(data, from)
  local to = data.to
  if not to then return end
  -- somebody else already answered: no need for a second answer
  if to ~= G.MyKey() then core.Unschedule("gemPvpBack" .. to); return end
  local s = data.s
  if type(s) ~= "table" then return end
  local h = counters()
  local changed = false
  local same = tonumber(s.season) == h.season
  for _, k in ipairs(same and COUNT or { "ow", "bg" }) do
    local v = tonumber(s[k]) or 0
    if v > (h[k] or 0) then h[k] = v; changed = true end
  end
  if changed then core.Schedule("gemPvpStatSend", 3, P.SendStats) end
end)

-- Rows for the table: one per member with numbers
function P.StatRows()
  local rows = {}
  local season = core.Points.SeasonStart()
  for key, s in pairs(store()) do
    if G.roster[key] or core.demo then
      local sow, sbg = s.sow or 0, s.sbg or 0
      if tonumber(s.season) and tonumber(s.season) ~= season then sow, sbg = 0, 0 end
      rows[#rows + 1] = { key = key, s = s, sow = sow, sbg = sbg, stot = sow + sbg, tot = (s.ow or 0) + (s.bg or 0) }
    end
  end
  return rows
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    pcall(self.RegisterEvent, self, "PLAYER_PVP_RANK_CHANGED")
    core.Schedule("gemPvpStatSend", 20, P.SendStats)
  else
    core.Schedule("gemPvpStatSend", 10, P.SendStats)
  end
end)
