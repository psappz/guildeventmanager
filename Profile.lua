local ADDON, ns = ...
-- Guild profile: what the guild master (or the guild event manager rank) has
-- set for the whole guild. Versioned and sent to every member. Members follow
-- the profile, not their installed modules.
local U, G, C = ns.U, ns.Guild, ns.Comm
local P = {}
ns.Profile = P

P.DEFAULTS = {
  v = 0,
  activeTypes = { rp = true, meet = true, ritual = true },
  weights = { event = 1, honor = 1, ach = 1 },
  managerRank = nil,        -- rank index with event rights (nil = only the guild master)
  managerRankName = nil,
  managerHigher = true,     -- higher ranks included
  season = "month",         -- "2weeks" | "month" | "quarter"
  pts = { participate = 10, goal = 5, lead = 15, leadMin = 5 },
  banner = { 1000, 3000, 6000 },  -- thresholds for banner levels 2, 3, 4 (honor + event points, last 28 days)
  typesKnown = {},
}

---------------------------------------------------------------------------
-- Per-guild storage
---------------------------------------------------------------------------
function ns.Store()
  if ns.demo then return ns.demoStore end
  local key = G.StoreKey()
  if not key or not ns.db then return nil end
  ns.db.guilds = ns.db.guilds or {}
  local s = ns.db.guilds[key]
  if not s then
    s = { profile = U.Copy(P.DEFAULTS), events = {}, ledger = {} }
    ns.db.guilds[key] = s
  end
  return s
end

function P.Get()
  local s = ns.Store()
  if not s then return P.DEFAULTS end
  -- fill keys added in later versions
  for k, v in pairs(P.DEFAULTS) do if s.profile[k] == nil then s.profile[k] = U.Copy(v) end end
  return s.profile
end

-- New types (e.g. from a module) are on until a manager switches them off
function P.IsTypeActive(id) return P.Get().activeTypes[id] ~= false end

function P.Weight(pot) return tonumber(P.Get().weights[pot]) or 1 end

---------------------------------------------------------------------------
-- Changing and sending (managers only; rank settings: guild master only)
---------------------------------------------------------------------------
local function remember(p)
  p.typesKnown = p.typesKnown or {}
  for id, t in pairs(ns.Modules.types) do
    p.typesKnown[id] = { module = t.module, name = ns.Modules.TypeName(id) }
  end
end

function P.Update(fn)
  if not G.IsManager() then U.Print(ns.L.NO_RIGHTS); return false end
  local p = P.Get()
  local oldRank, oldHigher = p.managerRank, p.managerHigher
  fn(p)
  if not G.IsLeader() and (p.managerRank ~= oldRank or p.managerHigher ~= oldHigher) then
    p.managerRank, p.managerHigher = oldRank, oldHigher
    U.Print(ns.L.ONLY_GM_RANK)
  end
  remember(p)
  p.v = (p.v or 0) + 1
  p.by = G.MyKey()
  p.at = U.Now()
  P.Broadcast()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return true
end

function P.Broadcast() C.Send("PROF", { p = P.Get() }) end

function P.ResetDefaults()
  P.Update(function(p)
    local keep = { managerRank = p.managerRank, managerRankName = p.managerRankName, managerHigher = p.managerHigher, v = p.v }
    for k in pairs(p) do p[k] = nil end
    for k, v in pairs(U.Copy(P.DEFAULTS)) do p[k] = v end
    for k, v in pairs(keep) do p[k] = v end
  end)
end

C.On("PROF", function(data, from)
  local new = data.p
  if type(new) ~= "table" then return end
  local s = ns.Store()
  if not s then return end
  local old = P.Get()
  if (tonumber(new.v) or 0) <= (old.v or 0) then return end
  if not G.IsManager(from) then return end
  -- only the guild master may change who holds event rights
  if G.RankOf(from) ~= 0 and (new.managerRank ~= old.managerRank or new.managerHigher ~= old.managerHigher) then return end
  s.profile = new
  P.Get()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

---------------------------------------------------------------------------
-- Sync: on login every client says what it has; managers answer with what
-- is newer (profile, events, point entries).
---------------------------------------------------------------------------
function P.Hello()
  local s = ns.Store()
  if not s then return end
  local evMax, lgMax = 0, 0
  for _, e in pairs(s.events) do evMax = math.max(evMax, e.upd or 0) end
  for _, e in pairs(s.ledger) do lgMax = math.max(lgMax, e.ts or 0) end
  C.Send("HELLO", { pv = P.Get().v or 0, ev = evMax, lg = lgMax })
end

C.On("HELLO", function(data, from)
  if not G.IsManager() then return end
  local s = ns.Store()
  if not s then return end
  local delay = 1 + math.random() * 4
  ns.Schedule("gemAnswer" .. tostring(from), delay, function()
    if (P.Get().v or 0) > (tonumber(data.pv) or 0) then P.Broadcast() end
    local since = tonumber(data.ev) or 0
    local old = U.Now() - 60 * 86400
    for _, e in pairs(s.events) do
      if (e.upd or 0) > since and ((e.start or 0) > old or e.status == "planned" or e.status == "running") then
        C.Send("EVT", { e = e })
      end
    end
    local lsince = tonumber(data.lg) or 0
    local batch = {}
    for id, e in pairs(s.ledger) do
      if (e.ts or 0) > lsince then
        batch[#batch + 1] = e
        if #batch >= 8 then C.Send("LEDG", { l = batch }); batch = {} end
      end
    end
    if #batch > 0 then C.Send("LEDG", { l = batch }) end
  end)
end)
