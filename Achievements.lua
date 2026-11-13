local ADDON, ns = ...
-- Guild achievements (clan / order achievements). Worked out from the point
-- ledger on every client, so they need no messages of their own. Thresholds,
-- names, points, honor names and their duration come from the guild profile.
local U, G, T = ns.U, ns.Guild, ns.Theme
local A = {}
ns.Achievements = A

-- stat: participate (events attended), lead (events led), types (different
-- event types attended), points (event + honor points),
-- why (entries with e.why == a.why, optionally e.flag == a.flag),
-- evtype (events of type a.evtype attended)
-- meta = { ids }: earned with all of these achievements (n = #meta)
-- compute = function(entries, events, a) -> { { who, ts, note } }: worked out by
--   the module (season results, streaks, ...); repeatable = true counts every award
-- honorPrio = n: this honor name wins over newer ones with a lower number (default 0)
-- hidden = true: shown only once earned. Modules add their own (def.achievements).
-- scope: "season" counts only this season, "forever" counts everything
-- faction = true: name / honor name come from H_ / A_ locale keys
A.DEFAULTS = {
  { id = "first", nameKey = "ACH_FIRST", stat = "participate", n = 1, pts = 10, scope = "forever", icon = "Interface\\Icons\\INV_Misc_Horn_01" },
  { id = "regular", nameKey = "ACH_REGULAR", stat = "participate", n = 10, pts = 25, scope = "season", icon = "Interface\\Icons\\INV_Misc_Note_02" },
  { id = "veteran", nameKey = "ACH_VETERAN", stat = "participate", n = 25, pts = 50, scope = "forever", faction = true,
    honorKey = "HONOR_VETERAN", honorScope = "forever", icon = "Interface\\Icons\\INV_Shield_05" },
  { id = "host", nameKey = "ACH_HOST", stat = "lead", n = 1, pts = 15, scope = "forever", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
  { id = "caller", nameKey = "ACH_CALLER", stat = "lead", n = 5, pts = 50, scope = "season", faction = true,
    honorKey = "HONOR_CALLER", honorScope = "season", icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
  { id = "versatile", nameKey = "ACH_VERSATILE", stat = "types", n = 3, pts = 25, scope = "season", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
  { id = "pillar", nameKey = "ACH_PILLAR", stat = "points", n = 1000, pts = 50, scope = "season", faction = true,
    honorKey = "HONOR_PILLAR", honorScope = "season", icon = "Interface\\Icons\\INV_BannerPVP_01" },
}

-- Defaults of the core plus every installed module
function A.AllDefaults()
  local list = {}
  for _, a in ipairs(A.DEFAULTS) do list[#list + 1] = a end
  for _, id in ipairs(ns.Modules.order or {}) do
    local m = ns.Modules.modules[id]
    for _, a in ipairs(m and m.achievements or {}) do a.module = id; list[#list + 1] = a end
  end
  return list
end

-- The guild profile keeps only what managers changed (p.achOv[id] = { n, pts, ... });
-- the definitions themselves come from the code. Keeps the profile small.
A.FIELDS = { "n", "pts", "name", "honor", "scope", "honorScope", "on" }

local function defaultsById()
  local map = {}
  for _, d in ipairs(A.AllDefaults()) do map[d.id] = d end
  return map
end

-- Differences of an edited achievement to its default
function A.Diff(a, d)
  local ov = {}
  for _, f in ipairs(A.FIELDS) do
    if a[f] ~= d[f] then ov[f] = a[f] end
  end
  if d.honorKey and not a.honorKey and not a.honor then ov.noHonor = true end
  return next(ov) and ov or nil
end

function A.List()
  local p = ns.Profile.Get()
  if p == ns.Profile.DEFAULTS then return A.AllDefaults() end
  local defs = defaultsById()
  -- older versions kept full copies in p.achs: turn them into overrides once
  if type(p.achs) == "table" then
    p.achOv = p.achOv or {}
    for _, a in ipairs(p.achs) do
      local d = defs[a.id]
      if d and not p.achOv[a.id] then p.achOv[a.id] = A.Diff(a, d) end
    end
    p.achs = nil
  end
  local list = {}
  for _, d in ipairs(A.AllDefaults()) do
    local a = U.Copy(d)
    local ov = p.achOv and p.achOv[d.id]
    if ov then
      for k, v in pairs(ov) do a[k] = v end
      if ov.noHonor then a.honorKey = nil; a.honor = nil end
    end
    list[#list + 1] = a
  end
  return list
end

-- Change one achievement (managers): fn(a) edits a copy, the difference is stored
function A.Edit(id, fn)
  return ns.Profile.Update(function(pr)
    local d = defaultsById()[id]
    if not d then return end
    local a
    for _, x in ipairs(A.List()) do if x.id == id then a = x end end
    fn(a)
    pr.achOv = pr.achOv or {}
    pr.achOv[id] = A.Diff(a, d)
  end)
end

function A.Name(a)
  if a.name and a.name ~= "" then return a.name end
  local n = a.faction and T.Word(a.nameKey) or ns.L[a.nameKey]
  if a.tier then n = n .. " (" .. ns.L["MEDAL_" .. a.tier] .. ")" end
  return n
end

function A.Honor(a)
  if a.honor and a.honor ~= "" then return a.honor end
  if a.honorKey then return T.Word(a.honorKey) end
  return nil
end

function A.Desc(a)
  local key = a.descKey or ("ACHSTAT_" .. a.stat)
  return ns.L[key]:format(a.n) .. ((a.scope == "season") and (" · " .. ns.L.ACH_SEASON) or "")
end

---------------------------------------------------------------------------
-- Working out who earned what
---------------------------------------------------------------------------
local cache, cacheAt

-- How much one ledger entry adds to an achievement (seen: per-member set for "types")
local function contrib(a, e, events, seen)
  if a.stat == "participate" then return e.why == "participate" and 1 or 0 end
  if a.stat == "lead" then return e.why == "lead" and 1 or 0 end
  if a.stat == "points" then return (e.pot == "event" or e.pot == "honor") and e.amt or 0 end
  if a.stat == "why" then
    if e.why ~= a.why or (a.flag and e.flag ~= a.flag) then return 0 end
    if a.evtype then
      local ev = e.ev and events[e.ev]
      if not ev or ev.type ~= a.evtype then return 0 end
    end
    return 1
  end
  if a.stat == "evtype" then
    local ev = e.why == "participate" and e.ev and events[e.ev]
    return (ev and ev.type == a.evtype) and 1 or 0
  end
  if a.stat == "types" and e.why == "participate" then
    local ev = e.ev and events[e.ev]
    if ev and ev.type and not seen[ev.type] then seen[ev.type] = true; return 1 end
  end
  return 0
end
A.Contrib = contrib

function A.Dirty() cache = nil end

local function compute()
  local s = ns.Store()
  if not s then return {} end
  local seasonStart = ns.Points.SeasonStart()
  local entries = {}
  for _, e in pairs(s.ledger) do
    if not e.reverted and e.why ~= "revert" and (e.amt or 0) > 0 then entries[#entries + 1] = e end
  end
  table.sort(entries, function(a, b) return (a.ts or 0) < (b.ts or 0) end)

  local res = {}
  local metas = {}
  local function award(who, a, ts, note)
    res[who] = res[who] or {}
    table.insert(res[who], { id = a.id, ts = ts or 0, pts = a.pts or 0, def = a, note = note })
  end
  for _, a in ipairs(A.List()) do
    if a.on ~= false and a.meta then
      metas[#metas + 1] = a
    elseif a.on ~= false and a.compute then
      -- computed by the module from all entries: { { who, ts, note } }
      local ok, awards = pcall(a.compute, entries, s.events, a)
      if ok and type(awards) == "table" then
        table.sort(awards, function(x, y) return (x.ts or 0) < (y.ts or 0) end)
        local got = {}
        for _, w in ipairs(awards) do
          if w.who and (a.repeatable or not got[w.who]) then got[w.who] = true; award(w.who, a, w.ts, w.note) end
        end
      elseif not ok and ns.LogError then ns.LogError("ach " .. tostring(a.id), awards) end
    elseif a.on ~= false then
      local count, typesSeen = {}, {}
      for _, e in ipairs(entries) do
        if a.scope ~= "season" or (e.ts or 0) >= seasonStart then
          local who = e.who
          typesSeen[who] = typesSeen[who] or {}
          local add = contrib(a, e, s.events, typesSeen[who])
          if add > 0 then
            local before = count[who] or 0
            count[who] = before + add
            if before < a.n and count[who] >= a.n then
              award(who, a, e.ts)
            end
          end
        end
      end
    end
  end
  -- meta achievements: earned with all achievements in a.meta (first time each)
  for _, a in ipairs(metas) do
    for who, list in pairs(res) do
      local first = {}
      for _, e in ipairs(list) do
        if not first[e.id] or e.ts < first[e.id] then first[e.id] = e.ts end
      end
      local ts, all = 0, true
      for _, id in ipairs(a.meta) do
        if not first[id] then all = false; break end
        if first[id] > ts then ts = first[id] end
      end
      if all then award(who, a, ts) end
    end
  end
  return res
end

-- { [key] = { { id, ts, pts, def } } }
function A.Earned()
  if not cache or (GetTime() - (cacheAt or 0)) > 30 then cache = compute(); cacheAt = GetTime() end
  return cache
end

function A.Count(key, id)
  local n = 0
  for _, e in ipairs(A.Earned()[key] or {}) do if e.id == id then n = n + 1 end end
  return n
end

function A.Has(key, id)
  for _, e in ipairs(A.Earned()[key] or {}) do if e.id == id then return e end end
end

-- Progress of a member towards an achievement (for the achievement tab)
function A.Progress(key, a)
  local s = ns.Store()
  if not s then return 0 end
  if a.meta then
    local n = 0
    for _, id in ipairs(a.meta) do if A.Has(key, id) then n = n + 1 end end
    return n
  end
  if a.compute then
    if a.progress then
      local ok, v = pcall(a.progress, key, a)
      if ok and tonumber(v) then return tonumber(v) end
    end
    return A.Has(key, a.id) and a.n or 0
  end
  local since = (a.scope == "season") and ns.Points.SeasonStart() or 0
  local n, seen = 0, {}
  for _, e in pairs(s.ledger) do
    if e.who == key and not e.reverted and e.why ~= "revert" and (e.ts or 0) >= since then
      n = n + contrib(a, e, s.events, seen)
    end
  end
  return n
end

-- Current honor name of a member: the newest earned one that is still valid
function A.HonorName(key)
  local best
  local seasonStart = ns.Points.SeasonStart()
  for _, e in ipairs(A.Earned()[key] or {}) do
    local h = A.Honor(e.def)
    if h and (e.def.honorScope ~= "season" or (e.ts or 0) >= seasonStart) then
      local prio = tonumber(e.def.honorPrio) or 0
      if not best or prio > best.prio or (prio == best.prio and e.ts > best.ts) then best = { name = h, ts = e.ts, prio = prio } end
    end
  end
  return best and best.name
end

---------------------------------------------------------------------------
-- Plaque for the player's own new achievements
---------------------------------------------------------------------------
function A.Check()
  cache = nil
  if ns.demo then return end
  ns.Schedule("gemAchCheck", 1, function()
    local sk = G.StoreKey()
    if not sk or not ns.char then return end
    ns.char.seenAch = ns.char.seenAch or {}
    local first = ns.char.seenAch[sk] == nil
    local seen = ns.char.seenAch[sk] or {}
    ns.char.seenAch[sk] = seen
    local fresh = {}
    for _, e in ipairs(A.Earned()[G.MyKey()] or {}) do
      local k = e.id .. ":" .. (e.def.repeatable and tostring(e.ts)
        or (e.def.scope == "season" and tostring(ns.Points.SeasonStart()) or "0"))
      if not seen[k] then
        seen[k] = true
        if not first then fresh[#fresh + 1] = e end
      end
    end
    for i, e in ipairs(fresh) do
      ns.Schedule("gemPlaque" .. i, (i - 1) * 7, function()
        ns.Plaque.Show(A.Name(e.def), A.Honor(e.def) and ns.L.HONOR_PREFIX:format(A.Honor(e.def)) or A.Desc(e.def), e.pts, e.def.icon)
        U.Print(ns.L.ACH_EARNED_CHAT:format(T.Word("ACH_KIND"), A.Name(e.def)))
        ns.Fire("ACHIEVEMENT_EARNED", e.def, e.ts)
      end)
    end
  end)
end
