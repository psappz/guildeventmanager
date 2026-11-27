local ADDON, ns = ...
-- Guild achievements and trophies (0.9). Only the whole guild earns them;
-- the reward is a trophy in bronze, silver or gold (some have a fourth,
-- "legendary" tier). Trophies do not count for the banner. Worked out from
-- the point ledger and the finished events on every client – no messages of
-- their own – counted per person (main and twinks together).
--
-- def = { id, nameKey, descKey, icon, tiers = { n1, n2, n3 [, n4] },
--         scope = "forever" | "season", stat = name or function(ctx, def, from, to), ... }
-- A stat returns, in time order, { ts, add, who } (counting up) or
-- { ts, total } (a running value such as a streak). Modules add their own
-- with `guild = true` in def.achievements (or def.guildAchievements).
-- Managers switch them off and change thresholds (profile p.gachOv[id]).
local U, G, T = ns.U, ns.Guild, ns.Theme
local GA = {}
ns.GuildAch = GA

local DAY, WEEK = 86400, 7 * 86400
local TIERS = { "BRONZE", "SILVER", "GOLD", "LEGEND" }
GA.TIERS = TIERS
GA.COLORS = { { 0.72, 0.45, 0.20 }, { 0.79, 0.79, 0.79 }, { 0.83, 0.69, 0.22 }, { 1, 0.5, 0 } }

local I = "Interface\\Icons\\"
GA.DEFAULTS = {
  { id = "g_first", nameKey = "GA_FIRST", descKey = "GA_D_FIRST", stat = "events", tiers = { 1, 25, 100 }, icon = I .. "INV_Misc_Horn_01" },
  { id = "g_fullhouse", nameKey = "GA_FULLHOUSE", descKey = "GA_D_FULLHOUSE", stat = "eventsize", size = 15, tiers = { 1, 5, 10 }, icon = I .. "INV_Misc_GroupNeedMore" },
  { id = "g_together", nameKey = "GA_TOGETHER", descKey = "GA_D_TOGETHER", stat = "participate", tiers = { 50, 250, 1000 }, icon = I .. "Spell_Holy_PrayerOfHealing" },
  { id = "g_hands", nameKey = "GA_HANDS", descKey = "GA_D_HANDS", stat = "leaders", tiers = { 3, 6, 12 }, icon = I .. "INV_Misc_Note_02" },
  { id = "g_weeks", nameKey = "GA_WEEKS", descKey = "GA_D_WEEKS", stat = "weekstreak", tiers = { 4, 8, 12 }, icon = I .. "INV_Misc_PocketWatch_01" },
  { id = "g_colorful", nameKey = "GA_COLORFUL", descKey = "GA_D_COLORFUL", stat = "seasonsWhere", where = "alltypes", tiers = { 1, 3, 6 }, icon = I .. "INV_Misc_Gem_Variety_01" },
  { id = "g_legend", nameKey = "GA_LEGEND", descKey = "GA_D_LEGEND", stat = "seasonsWhere", where = "banner4", tiers = { 1, 3, 6 }, icon = I .. "INV_BannerPVP_01" },
  { id = "g_legendary", nameKey = "GA_LEGENDARY", descKey = "GA_D_LEGENDARY", stat = "bannerstreak", tiers = { 3, 6, 9, 12 }, icon = I .. "INV_Misc_Ribbon_01" },
  { id = "g_busy", nameKey = "GA_BUSY", descKey = "GA_D_BUSY", stat = "points", scope = "season", tiers = { 1000, 2500, 5000 }, icon = I .. "INV_Misc_Coin_02" },
  { id = "g_tireless", nameKey = "GA_TIRELESS", descKey = "GA_D_TIRELESS", stat = "points", tiers = { 10000, 25000, 100000 }, icon = I .. "INV_Misc_Coin_01" },
  { id = "g_faces", nameKey = "GA_FACES", descKey = "GA_D_FACES", stat = "members", scope = "season", tiers = { 5, 10, 20 }, icon = I .. "INV_Misc_Head_Human_01" },
  { id = "g_doors", nameKey = "GA_DOORS", descKey = "GA_D_DOORS", stat = "members", tiers = { 20, 50, 100 }, icon = I .. "INV_Misc_Key_03" },
  { id = "g_goals", nameKey = "GA_GOALS", descKey = "GA_D_GOALS", stat = "goals", tiers = { 1, 5, 15 }, icon = I .. "INV_Misc_Flag_01" },
  { id = "g_faithful", nameKey = "GA_FAITHFUL", descKey = "GA_D_FAITHFUL", stat = "faithful", scope = "season", tiers = { 5, 10, 20 }, icon = I .. "Spell_Holy_SealOfDevotion" },
  { id = "g_family", nameKey = "GA_FAMILY", descKey = "GA_D_FAMILY", stat = "gem", tiers = { 10, 25, 50 }, icon = I .. "INV_Misc_Tabard_01" },
}

---------------------------------------------------------------------------
-- Definitions and overrides
---------------------------------------------------------------------------
function GA.AllDefaults()
  local list = {}
  for _, d in ipairs(GA.DEFAULTS) do d.module = d.module or "core"; list[#list + 1] = d end
  for _, id in ipairs(ns.Modules.order or {}) do
    local m = ns.Modules.modules[id]
    for _, a in ipairs(m and m.guildAchievements or {}) do a.module = id; a.guild = true; list[#list + 1] = a end
    for _, a in ipairs(m and m.achievements or {}) do if a.guild then a.module = id; list[#list + 1] = a end end
  end
  return list
end

-- the profile keeps only changes: p.gachOv[id] = { on = false, tiers = { ... } }
function GA.List()
  local p = ns.Profile.Get()
  local list = {}
  for _, d in ipairs(GA.AllDefaults()) do
    local a = U.Copy(d)
    a.stat, a.where, a.filter = d.stat, d.where, d.filter   -- functions stay shared
    local ov = p and p.gachOv and p.gachOv[d.id]
    if type(ov) == "table" then
      if ov.on == false then a.on = false end
      if type(ov.tiers) == "table" and #ov.tiers == #d.tiers then a.tiers = U.Copy(ov.tiers) end
    end
    list[#list + 1] = a
  end
  return list
end

function GA.Def(id)
  for _, a in ipairs(GA.List()) do if a.id == id then return a end end
end

-- managers: switch on/off, change thresholds (ascending, positive)
function GA.Edit(id, on, tiers)
  if not (ns.Guild.IsManager() or ns.Guild.IsLead()) then return false end
  local d
  for _, x in ipairs(GA.AllDefaults()) do if x.id == id then d = x end end
  if not d then return false end
  return ns.Profile.Update(function(pr)
    pr.gachOv = pr.gachOv or {}
    local ov = {}
    if on == false then ov.on = false end
    if type(tiers) == "table" and #tiers == #d.tiers then
      local ok, last, same = true, 0, true
      for i, n in ipairs(tiers) do
        n = math.floor(tonumber(n) or 0)
        if n <= last then ok = false end
        last = n
        if n ~= d.tiers[i] then same = false end
        tiers[i] = n
      end
      if ok and not same then ov.tiers = tiers end
    end
    pr.gachOv[id] = next(ov) and ov or nil
  end)
end

function GA.Name(a) return a.name or ns.L[a.nameKey] or a.id end
function GA.Desc(a) return a.desc or ns.L[a.descKey] or "" end
function GA.TierName(i) return ns.L["GA_TIER_" .. (TIERS[i] or "GOLD")] end

-- short name for the band of a trophy: "11/26", "Q4/26", "02.11."
function GA.SeasonShort(st)
  local p = ns.Profile.Get()
  local t = date("*t", st)
  if p.season == "2weeks" then return date("%d.%m.", st) end
  if p.season == "quarter" then return "Q" .. (math.floor((t.month - 1) / 3) + 1) .. "/" .. date("%y", st) end
  return date("%m/%y", st)
end

-- name of a season: "November 2026", "Q4 2026", "02.11.–15.11."
function GA.SeasonLabel(st)
  local p = ns.Profile.Get()
  local t = date("*t", st)
  if p.season == "2weeks" then return date("%d.%m.", st) .. "–" .. date("%d.%m.", st + 13 * DAY) end
  if p.season == "quarter" then return "Q" .. (math.floor((t.month - 1) / 3) + 1) .. " " .. t.year end
  local names = _G.CALENDAR_FULLDATE_MONTH_NAMES
  local m = (type(names) == "table" and names[t.month]) or date("%B", st)
  return m .. " " .. t.year
end

---------------------------------------------------------------------------
-- Context: ledger entries and finished events, once per computation
---------------------------------------------------------------------------
local pcache = {}
local function person(k)
  if not k then return nil end
  local p = pcache[k]
  if p == nil then p = ns.Persons.MainOf(k) or k; pcache[k] = p end
  return p
end

-- first index of a sorted list with ts >= from (binary search)
local function firstAt(list, from)
  local lo, hi = 1, #list
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if list[mid].ts < from then lo = mid + 1 else hi = mid - 1 end
  end
  return lo
end
GA.FirstAt = firstAt

-- entries with from <= ts < to, in time order (for modules too: GA.Range(ctx.entries, from, to))
local function range(list, from, to)
  local i = firstAt(list, from) - 1
  return function()
    i = i + 1
    local e = list[i]
    if e and e.ts < to then return e end
  end
end
GA.Range = range

local function weekOf(ts) return math.floor(((ts or 0) - 4 * DAY) / WEEK) end   -- weeks start on Monday

local function buildCtx()
  pcache = {}
  local s = ns.Store()
  if not s then return nil end
  local ctx = { entries = {}, events = {}, now = U.Now(), first = U.Now() }
  for _, e in pairs(s.ledger or {}) do
    if not e.reverted and e.why ~= "revert" and (e.amt or 0) > 0 and e.ts then
      ctx.entries[#ctx.entries + 1] = e
      if e.ts < ctx.first then ctx.first = e.ts end
    end
  end
  table.sort(ctx.entries, function(a, b) return a.ts < b.ts end)
  -- the same entries by reason and the GP entries, each in time order
  ctx.byWhy, ctx.gp = {}, {}
  for _, e in ipairs(ctx.entries) do
    local w = e.why or "?"
    local l = ctx.byWhy[w]
    if not l then l = {}; ctx.byWhy[w] = l end
    l[#l + 1] = e
    if e.pot == "event" or e.pot == "honor" then ctx.gp[#ctx.gp + 1] = e end
  end
  for id, e in pairs(s.events or {}) do
    if e.status == "done" and not e.test then
      local ts = tonumber(e.ended) or tonumber(e.finish) or tonumber(e.start) or 0
      local att, n = {}, 0
      for k, v in pairs(e.attended or {}) do
        if v then
          local p = person(k)
          if not att[p] then att[p] = true; n = n + 1 end
        end
      end
      local leaders = {}
      for _, k in ipairs(ns.Events.Leaders(e) or {}) do leaders[#leaders + 1] = person(k) end
      ctx.events[#ctx.events + 1] = { id = id, ts = ts, type = e.type, att = att, n = n, leaders = leaders, ev = e }
      if ts > 0 and ts < ctx.first then ctx.first = ts end
    end
  end
  table.sort(ctx.events, function(a, b) return a.ts < b.ts end)
  ctx.gem = s.gemSeen or {}
  return ctx
end
GA.BuildCtx = buildCtx

local function inWin(ts, from, to) return ts and ts >= from and ts < to end
local function evOk(def, x) return not def.filter or def.filter(x) end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------
local STATS = {}
GA.STATS = STATS

-- finished events
function STATS.events(ctx, def, from, to)
  local out = {}
  for _, x in ipairs(ctx.events) do
    if inWin(x.ts, from, to) and evOk(def, x) then out[#out + 1] = { ts = x.ts, add = 1, who = x.leaders[1] } end
  end
  return out
end

-- finished events with at least def.size participants
function STATS.eventsize(ctx, def, from, to)
  local out = {}
  for _, x in ipairs(ctx.events) do
    if inWin(x.ts, from, to) and x.n >= (def.size or 15) and evOk(def, x) then out[#out + 1] = { ts = x.ts, add = 1, who = x.leaders[1] } end
  end
  return out
end

-- participations of all members
function STATS.participate(ctx, def, from, to)
  local out = {}
  for e in range(ctx.byWhy.participate or {}, from, to) do
    out[#out + 1] = { ts = e.ts, add = 1, who = person(e.who) }
  end
  return out
end

-- different leaders of finished events
function STATS.leaders(ctx, def, from, to)
  local out, seen = {}, {}
  for _, x in ipairs(ctx.events) do
    if inWin(x.ts, from, to) and evOk(def, x) then
      for _, k in ipairs(x.leaders) do
        if not seen[k] then seen[k] = true; out[#out + 1] = { ts = x.ts, add = 1, who = k } end
      end
    end
  end
  return out
end

-- weeks in a row with a finished event (def.sameType: of the same type);
-- the value is the longest run so far
function STATS.weekstreak(ctx, def, from, to)
  local out, best = {}, 0
  local last, run = {}, {}
  for _, x in ipairs(ctx.events) do
    if inWin(x.ts, from, to) and evOk(def, x) then
      local key = def.sameType and x.type or "*"
      local w = weekOf(x.ts)
      if last[key] ~= w then
        run[key] = (last[key] == w - 1) and (run[key] or 0) + 1 or 1
        last[key] = w
        if run[key] > best then best = run[key]; out[#out + 1] = { ts = x.ts, total = best } end
      end
    end
  end
  return out
end

-- weeks in which every type of def.types was finished
function STATS.weeksall(ctx, def, from, to)
  local out, byWeek = {}, {}
  for _, x in ipairs(ctx.events) do
    if inWin(x.ts, from, to) then
      local w = weekOf(x.ts)
      local b = byWeek[w] or { have = {}, n = 0 }
      byWeek[w] = b
      for _, t in ipairs(def.types or {}) do
        if x.type == t and not b.have[t] then
          b.have[t] = true; b.n = b.n + 1
          if b.n == #def.types then out[#out + 1] = { ts = x.ts, add = 1 } end
        end
      end
    end
  end
  return out
end

-- GP of the guild (event and honor pots)
function STATS.points(ctx, def, from, to)
  local out = {}
  for e in range(ctx.gp, from, to) do
    out[#out + 1] = { ts = e.ts, add = e.amt, who = person(e.who) }
  end
  return out
end

-- different members with an entry
function STATS.members(ctx, def, from, to)
  local out, seen = {}, {}
  for e in range(ctx.entries, from, to) do
    local p = person(e.who)
    if p and not seen[p] then seen[p] = true; out[#out + 1] = { ts = e.ts, add = 1, who = p } end
  end
  return out
end

-- ledger entries with e.why == def.why (def.flag, def.test(e)); def.sum adds the GP, def.distinct counts e[distinct] once
function STATS.why(ctx, def, from, to)
  local out, seen = {}, {}
  for e in range(ctx.byWhy[def.why] or {}, from, to) do
    if (not def.flag or e.flag == def.flag or (def.flagPrefix and type(e.flag) == "string" and e.flag:sub(1, #def.flag) == def.flag))
      and (not def.test or def.test(e)) then
      local d = def.distinct and e[def.distinct]
      if not d or not seen[d] then
        if d then seen[d] = true end
        out[#out + 1] = { ts = e.ts, add = def.sum and e.amt or 1, who = person(e.who) }
      end
    end
  end
  return out
end

-- shared goals reached (contests with a goal)
function STATS.goals(ctx, def, from, to)
  local out = {}
  for _, x in ipairs(ctx.events) do
    local e = x.ev
    local ts = tonumber(e.cend) or x.ts
    if e.cendWhy == "goal" and inWin(ts, from, to) then out[#out + 1] = { ts = ts, add = 1, who = x.leaders[1] } end
  end
  return out
end

-- members with GEM (seen in a HELLO), still in the guild
function STATS.gem(ctx, def, from, to)
  local out, seen = {}, {}
  local list = {}
  for k, ts in pairs(ctx.gem) do list[#list + 1] = { k = k, ts = tonumber(ts) or 0 } end
  local me = G.MyKey and G.MyKey()
  if me and not ctx.gem[me] then list[#list + 1] = { k = me, ts = ctx.now } end
  table.sort(list, function(a, b) return a.ts < b.ts end)
  for _, x in ipairs(list) do
    local p = person(x.k)
    if p and not seen[p] and (G.roster[x.k] or x.k == me) then seen[p] = true; out[#out + 1] = { ts = x.ts, add = 1, who = p } end
  end
  return out
end

-- seasons: start of the season of a time and its end
local function seasonOf(ts) return ns.Points.SeasonStart(ts) end
local function seasonEnd(st) return ns.Points.SeasonEnd(st) end
GA.SeasonOf, GA.SeasonEnd = seasonOf, seasonEnd

-- all seasons from the first entry to now: { { st, en } }
function GA.Seasons(ctx)
  local out = {}
  local st = seasonOf(ctx.first)
  local guard = 0
  while st <= ctx.now and guard < 400 do
    local en = seasonEnd(st)
    out[#out + 1] = { st = st, en = en }
    st = en
    guard = guard + 1
  end
  return out
end

-- banner value (GP of the 28 days before ts) from a sorted list with prefix sums
local function bannerValues(ctx)
  if ctx.banner then return ctx.banner end
  local ts, sum, acc = {}, {}, 0
  for _, e in ipairs(ctx.gp) do acc = acc + e.amt; ts[#ts + 1] = e.ts; sum[#sum + 1] = acc end
  local function upto(t)   -- sum of all entries with ts < t
    local lo, hi = 1, #ts
    local r = 0
    while lo <= hi do
      local mid = math.floor((lo + hi) / 2)
      if ts[mid] < t then r = sum[mid]; lo = mid + 1 else hi = mid - 1 end
    end
    return r
  end
  ctx.banner = function(t) return upto(t) - upto(t - 28 * DAY) end
  return ctx.banner
end
GA.BannerValue = function(ctx, t) return bannerValues(ctx)(t) end

local function topLevel()
  local th = ns.Profile.Get().banner or { 1000, 3000, 6000 }
  return th[#th] or 6000
end

-- conditions for whole seasons; return the time it became true or nil
local WHERE = {}
GA.WHERE = WHERE
-- events of every core event type in the season
function WHERE.alltypes(ctx, st, en)
  local need, n, last = {}, 0, nil
  for _, t in ipairs(ns.Modules.AllTypes()) do
    if t.module == "core" and not t.missing then need[t.id] = true; n = n + 1 end
  end
  if n == 0 then return nil end
  for _, x in ipairs(ctx.events) do
    if x.ts >= st and x.ts < en and need[x.type] then need[x.type] = nil; n = n - 1; last = x.ts; if n == 0 then return last end end
  end
end
-- the season ended with banner level 4
function WHERE.banner4(ctx, st, en)
  if en > ctx.now then return nil end
  return bannerValues(ctx)(en) >= topLevel() and en or nil
end

function STATS.seasonsWhere(ctx, def, from, to)
  local out = {}
  local fn = type(def.where) == "function" and def.where or WHERE[def.where]
  if not fn then return out end
  for _, s in ipairs(GA.Seasons(ctx)) do
    if s.st >= from and s.st < to then
      local ok, ts = pcall(fn, ctx, s.st, s.en)
      if ok and ts then out[#out + 1] = { ts = ts, add = 1, season = s.st } end
    end
  end
  return out
end

-- months in a row with banner level 4 (checked day by day); longest run so far
function STATS.bannerstreak(ctx, def, from, to)
  local out = {}
  local val, top = bannerValues(ctx), topLevel()
  local day = math.floor(math.max(from, ctx.first) / DAY) * DAY + DAY
  local stop = math.min(to, ctx.now)
  local run, best = 0, 0
  local guard = 0
  while day <= stop and guard < 4000 do
    if val(day) >= top then
      run = run + 1
      local months = math.floor(run / 30.44)
      if months > best then best = months; out[#out + 1] = { ts = day, total = best } end
    else run = 0 end
    day = day + DAY
    guard = guard + 1
  end
  ctx.bannerRun = math.floor(run / 30.44)
  return out
end

-- members with an entry this season and in each of the two seasons before
function STATS.faithful(ctx, def, from, to)
  local out = {}
  local prev1 = seasonOf(from - 1)
  local prev2 = seasonOf(prev1 - 1)
  local had1, had2 = {}, {}
  for e in range(ctx.entries, prev2, prev1) do had2[person(e.who) or "?"] = true end
  for e in range(ctx.entries, prev1, from) do had1[person(e.who) or "?"] = true end
  local seen = {}
  for e in range(ctx.entries, from, to) do
    local p = person(e.who)
    if p and not seen[p] and had1[p] and had2[p] then seen[p] = true; out[#out + 1] = { ts = e.ts, add = 1, who = p } end
  end
  return out
end

---------------------------------------------------------------------------
-- Evaluation
---------------------------------------------------------------------------
-- { have, tier, tierTs = { ts per tier }, contrib = { [person] = n } }
local function eval(ctx, a, from, to)
  local fn = type(a.stat) == "function" and a.stat or STATS[a.stat]
  local r = { have = 0, tier = 0, tierTs = {}, contrib = {} }
  if not fn then return r end
  local ok, list = pcall(fn, ctx, a, from, to)
  if not ok then
    if ns.LogError then ns.LogError("gach " .. tostring(a.id), list) end
    return r
  end
  for _, x in ipairs(list or {}) do
    if x.total then r.have = math.max(r.have, x.total) else r.have = r.have + (x.add or 0) end
    if x.who and x.add then r.contrib[x.who] = (r.contrib[x.who] or 0) + x.add end
    while a.tiers[r.tier + 1] and r.have >= a.tiers[r.tier + 1] do
      r.tier = r.tier + 1
      r.tierTs[r.tier] = x.ts
    end
  end
  if a.stat == "bannerstreak" then r.current = ctx.bannerRun end
  return r
end
GA.Eval = eval

local cache, cacheAt
function GA.Dirty() cache = nil end

-- every guild achievement with its state:
-- { def, have, tier, next, tierTs, contrib, top = { {who, n} }, mine,
--   seasons = { { st, label, tier, ts } } (season scope: earlier seasons) }
local function compute()
  local ctx = buildCtx()
  if not ctx then return {} end
  local out = {}
  local cur = seasonOf(ctx.now)
  local me = person(G.MyKey())
  for _, a in ipairs(GA.List()) do
    if a.on ~= false then
      local r
      local x = { def = a, seasons = {} }
      if a.scope == "season" then
        for _, s in ipairs(GA.Seasons(ctx)) do
          if s.st < cur then
            local pr = eval(ctx, a, s.st, s.en)
            if pr.tier > 0 then x.seasons[#x.seasons + 1] = { st = s.st, label = GA.SeasonLabel(s.st), tier = pr.tier, ts = pr.tierTs[pr.tier] } end
          end
        end
        r = eval(ctx, a, cur, seasonEnd(cur))
        x.season = cur
      else
        r = eval(ctx, a, 0, ctx.now + 1)
      end
      x.have, x.tier, x.tierTs, x.contrib, x.current = r.have, r.tier, r.tierTs, r.contrib, r.current
      x.next = a.tiers[r.tier + 1]
      local top = {}
      for who, n in pairs(r.contrib) do top[#top + 1] = { who = who, n = n } end
      table.sort(top, function(p, q) if p.n ~= q.n then return p.n > q.n end return p.who < q.who end)
      x.top = { top[1], top[2], top[3] }
      x.mine = me and r.contrib[me] or 0
      out[#out + 1] = x
    end
  end
  return out
end

function GA.All()
  if not cache or (GetTime() - (cacheAt or 0)) > 30 then cache = compute(); cacheAt = GetTime() end
  return cache
end

function GA.Progress(id)
  for _, x in ipairs(GA.All()) do if x.def.id == id then return x end end
end

-- trophies: one per reached tier of a "forever" achievement (the highest),
-- one per season and season achievement
-- { { def, tier, ts, season = label or nil } }, newest first
function GA.Trophies()
  local out = {}
  for _, x in ipairs(GA.All()) do
    if x.tier > 0 then out[#out + 1] = { def = x.def, tier = x.tier, ts = x.tierTs[x.tier], season = x.season and GA.SeasonLabel(x.season) } end
    for _, s in ipairs(x.seasons) do out[#out + 1] = { def = x.def, tier = s.tier, ts = s.ts, season = s.label } end
  end
  table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
  return out
end

function GA.Count() return #GA.Trophies() end

-- the guild achievement closest to its next tier (share of the way)
function GA.Closest()
  local best, bestShare
  for _, x in ipairs(GA.All()) do
    if x.next then
      local from = x.tier > 0 and x.def.tiers[x.tier] or 0
      local share = (x.have - from) / math.max(1, x.next - from)
      if share < 1 and (not bestShare or share > bestShare) then best, bestShare = x, share end
    end
  end
  return best, bestShare
end

---------------------------------------------------------------------------
-- New trophies: plaque for everyone online, chat line, notice
---------------------------------------------------------------------------
local lastCheck = 0
function GA.Check()
  cache = nil
  if ns.demo then return end
  -- at most every 30 seconds (a PvP evening books an entry every few seconds)
  local wait = math.max(2, 30 - (GetTime() - lastCheck))
  if ns.Pending and ns.Pending("gemGachCheck") then return end
  ns.Schedule("gemGachCheck", wait, function()
    lastCheck = GetTime()
    local sk = G.StoreKey()
    if not sk or not ns.char then return end
    ns.char.seenGach = ns.char.seenGach or {}
    local first = ns.char.seenGach[sk] == nil
    local seen = ns.char.seenGach[sk] or {}
    ns.char.seenGach[sk] = seen
    local fresh = {}
    for _, x in ipairs(GA.All()) do
      for i = 1, x.tier do
        local k = x.def.id .. ":" .. tostring(x.season or 0) .. ":" .. i
        if not seen[k] then
          seen[k] = true
          -- a tier reached long ago (e.g. a lower one while catching up) gets no plaque
          -- (also a tier reached days ago, e.g. when old entries arrive by sync)
          local ts = x.tierTs[i]
          if not first and i == x.tier and (not ts or U.Now() - ts < 3 * DAY) then fresh[#fresh + 1] = { x = x, tier = i } end
        end
      end
    end
    for n, f in ipairs(fresh) do
      ns.Schedule("gemGachPlaque" .. n, 3 + (n - 1) * 7, function()
        local name = GA.Name(f.x.def) .. " · " .. GA.TierName(f.tier)
        ns.Plaque.Show(name, GA.Desc(f.x.def), nil, f.x.def.icon, nil, { guild = true, tier = f.tier })
        U.Print(ns.L.GA_EARNED_CHAT:format(name))
        if ns.Notices and ns.Notices.Add then
          ns.Notices.Add({ key = "gach:" .. f.x.def.id .. ":" .. f.tier .. ":" .. tostring(f.x.season or 0), group = "ach",
            text = ns.L.GA_EARNED_CHAT:format(name), view = "achievements" })
        end
        ns.Fire("GUILD_ACHIEVEMENT_EARNED", f.x.def, f.tier, f.x.tierTs[f.tier])
      end)
    end
  end)
end

-- members with GEM: every HELLO is noted (for "Extended Family")
ns.Comm.On("HELLO", function(data, from)
  local s = ns.Store()
  local key = from and (G.Resolve and G.Resolve(from) or G.Key(from))
  if not s or not key then return end
  s.gemSeen = s.gemSeen or {}
  if not s.gemSeen[key] then s.gemSeen[key] = U.Now(); cache = nil end
end)
