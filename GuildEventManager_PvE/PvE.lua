local ADDON, R = ...
-- GuildEventManager PvE module: raids as events. Roles, dual spec, line-up in
-- groups with boss setups, buff overview, readiness, Discord export.
-- The line-up travels with the event (e.pve), the specs and the readiness of
-- every member travel in the module's own messages.
local core = R.core
if not core then return end
local API = GuildEventManagerAPI
API.pve = R
R.L = core.L
R.version = 1
local U, G, E = core.U, core.Guild, core.Events
local L = R.L

---------------------------------------------------------------------------
-- Storage per guild: specs, Discord names, readiness, bench counts
---------------------------------------------------------------------------
function R.Store()
  local s = core.Store()
  if not s then return { specs = {}, discord = {}, state = {}, bench = {}, need = {} } end
  s.pve = s.pve or {}
  local p = s.pve
  p.specs = p.specs or {}
  p.discord = p.discord or {}
  p.state = p.state or {}
  p.bench = p.bench or {}
  p.need = p.need or {}
  return p
end

---------------------------------------------------------------------------
-- Rights: the guild's event managers, plus every rank down to the raid rank
-- set in the settings (default: the rank below the guild master)
---------------------------------------------------------------------------
function R.RaidRank() return tonumber(core.Profile.Get().raidRank) or 1 end
function R.CanCreate(key)
  key = key or G.MyKey()
  if G.IsManager(key) then return true end
  local r = G.RankOf(key)
  return r ~= nil and r <= R.RaidRank()
end

---------------------------------------------------------------------------
-- Templates
---------------------------------------------------------------------------
function R.TemplateOf(e)
  local id = e and e.type and e.type:match("^raid_(.+)$")
  return id and R.TPL[id]
end
function R.IsRaid(e) return R.TemplateOf(e) ~= nil end
function R.TplName(t) return L[t.labelKey] end
function R.Need(t)
  local pr = core.Profile.Get()
  local n = pr.pve and pr.pve.need and pr.pve.need[t.id]
  return { tank = n and n.tank or t.need.tank, heal = n and n.heal or t.need.heal }
end
function R.Bosses(t) return t.bosses end

function R.RaidEvents(open)
  return E.List(function(e) return R.IsRaid(e) and (not open or E.IsOpen(e)) end)
end
function R.NextRaid()
  for _, e in ipairs(R.RaidEvents(true)) do return e end
end

---------------------------------------------------------------------------
-- Own talents: tree per talent group. Works with the classic talent API and
-- with the specialization API; whatever this client offers.
---------------------------------------------------------------------------
function R.MyClass() return select(2, UnitClass("player")) end

local function treeOfSpecIndex(class, idx, role)
  -- specialization API: druids have 4 (balance, feral, guardian, restoration)
  if class == "DRUID" then
    if idx == 3 then return 2, "mt" end
    if idx == 4 then return 3, "heal" end
  end
  return idx, nil
end

-- All specializations of the own class: { index, id, name, tree, role, configured }
-- configured = the player saved a talent loadout for it (his "dual spec")
local ROLE_OF = { TANK = "mt", HEALER = "heal" }
function R.MySpecs()
  local SI = C_SpecializationInfo
  local class = R.MyClass()
  local classID = select(3, UnitClass("player"))
  local num = GetNumSpecializations or (SI and SI.GetNumSpecializations)
  local n
  if num then local ok, v = pcall(num); n = ok and tonumber(v) end
  if not n and SI and SI.GetNumSpecializationsForClassID and classID then
    local ok, v = pcall(SI.GetNumSpecializationsForClassID, classID); n = ok and tonumber(v)
  end
  n = n or (class == "DRUID" and 4 or 3)
  local info = GetSpecializationInfo or (SI and SI.GetSpecializationInfo)
  local CT = C_ClassTalents
  local out = {}
  for i = 1, math.min(n, 4) do
    local id, name, role
    if info then
      local r = { pcall(info, i) }
      if r[1] then id, name, role = r[2], r[3], r[6] end
    end
    local tree, fixed = treeOfSpecIndex(class, i)
    local our = fixed or ROLE_OF[role] or R.DefaultRole(class, tree)
    local configured = false
    if CT and id then
      if CT.GetConfigIDsBySpecID then
        local ok, ids = pcall(CT.GetConfigIDsBySpecID, id)
        if ok and type(ids) == "table" and #ids > 0 then configured = true end
      end
      if not configured and CT.GetLastSelectedSavedConfigID then
        local ok, cid = pcall(CT.GetLastSelectedSavedConfigID, id)
        if ok and cid then configured = true end
      end
    end
    out[#out + 1] = { index = i, id = id, name = name, tree = tree, role = our, configured = configured }
  end
  -- a character that has not chosen a specialization yet has one "spec"
  -- named like the class: no spec at all for us
  local className = UnitClass("player")
  if #out == 1 or (out[1] and out[1].name and out[1].name == className) then
    for _, x in ipairs(out) do x.initial = true end
  end
  return out
end

-- Points per third of the class talent tree for one talent config:
-- returns tree (1-3) or nil, { pts1, pts2, pts3 }, info
local function configThirds(configID)
  local TR = C_Traits
  if not TR or not configID then return nil, nil, "no C_Traits" end
  local ok, ci = pcall(TR.GetConfigInfo, configID)
  if not ok or type(ci) ~= "table" or type(ci.treeIDs) ~= "table" or not ci.treeIDs[1] then return nil, nil, "no tree" end
  local ok2, nodes = pcall(TR.GetTreeNodes, ci.treeIDs[1])
  if not ok2 or type(nodes) ~= "table" then return nil, nil, "no nodes" end
  local list, minX, maxX = {}, math.huge, -math.huge
  for _, nodeID in ipairs(nodes) do
    local ok3, ni = pcall(TR.GetNodeInfo, configID, nodeID)
    if ok3 and type(ni) == "table" and ni.posX then
      list[#list + 1] = { x = ni.posX, r = tonumber(ni.ranksPurchased) or tonumber(ni.currentRank) or 0, sub = ni.subTreeID }
      if ni.posX < minX then minX = ni.posX end
      if ni.posX > maxX then maxX = ni.posX end
    end
  end
  if #list == 0 or maxX <= minX then return nil, nil, "nodes " .. #list end
  local pts = { 0, 0, 0 }
  local w = (maxX - minX) / 3
  for _, n in ipairs(list) do
    local third = math.min(3, math.floor((n.x - minX) / w) + 1)
    pts[third] = pts[third] + n.r
  end
  local best, bp = nil, 0
  for i = 1, 3 do if pts[i] > bp then best, bp = i, pts[i] end end
  return best, pts, "nodes " .. #list .. " · x " .. math.floor(minX) .. "–" .. math.floor(maxX) .. " · name " .. tostring(ci.name)
end
R.ConfigThirds = configThirds

-- the active talent config and the saved loadouts:
-- { { id, name, active, tree, pts, info } }
function R.Loadouts()
  local CT = C_ClassTalents
  local out = {}
  if not CT then return out end
  local active
  if CT.GetActiveConfigID then local ok, v = pcall(CT.GetActiveConfigID); active = ok and v or nil end
  local seen = {}
  local function add(id, isActive)
    if not id or seen[id] then return end
    seen[id] = true
    local tree, pts, info = configThirds(id)
    local name
    if C_Traits and C_Traits.GetConfigInfo then
      local ok, ci = pcall(C_Traits.GetConfigInfo, id); name = ok and type(ci) == "table" and ci.name or nil
    end
    out[#out + 1] = { id = id, name = name, active = isActive, tree = tree, pts = pts, info = info }
  end
  add(active, true)
  local specs = R.MySpecs()
  for _, sp in ipairs(specs) do
    if sp.id and CT.GetConfigIDsBySpecID then
      local ok, ids = pcall(CT.GetConfigIDsBySpecID, sp.id)
      if ok and type(ids) == "table" then for _, id in ipairs(ids) do add(id, false) end end
    end
  end
  -- the saved loadout that is currently selected counts as the active one
  if CT.GetLastSelectedSavedConfigID and specs[1] and specs[1].id then
    local ok, last = pcall(CT.GetLastSelectedSavedConfigID, specs[1].id)
    if ok and last then for _, l in ipairs(out) do if l.id == last and not l.active then l.selected = true end end end
  end
  return out
end

-- Talent points of the active talent group per tree, as text
-- ("Disziplin 17 · Heilig 0 · Schatten 15"), or nil
function R.TalentPoints()
  local class = R.MyClass()
  for _, l in ipairs(R.Loadouts()) do
    if l.active and l.pts then
      local t = {}
      for i = 1, 3 do t[#t + 1] = R.SpecName(class, i) .. " " .. l.pts[i] end
      return table.concat(t, " · ")
    end
  end
end

-- returns { [group] = tree }, active group, source
function R.ReadTalents()
  local class = R.MyClass()
  local out, active = {}, 1
  local SI = C_SpecializationInfo
  local getSpec = GetSpecialization or (SI and SI.GetSpecialization)
  if getSpec then
    local ok, idx = pcall(getSpec)
    if ok and tonumber(idx) then
      -- WoW Forever: specializations with saved talent loadouts. The active
      -- spec is group 1; another spec the player has a loadout for is group 2.
      local specs = R.MySpecs()
      if specs[1] and specs[1].initial then
        -- one talent tree for the whole class (WoW Forever): the classic
        -- trees side by side; the third with the most points is the spec
        local loads = R.Loadouts()
        for _, l in ipairs(loads) do
          if l.active and l.tree then out[1] = { l.tree, R.DefaultRole(class, l.tree) } end
        end
        for _, l in ipairs(loads) do
          if not l.active and l.tree and not out[2] and (not out[1] or l.tree ~= out[1][1]) then out[2] = { l.tree, R.DefaultRole(class, l.tree) } end
        end
        return out, 1, out[1] and "loadouts" or "initial"
      end
      for _, x in ipairs(specs) do
        if x.index == idx then out[1] = { x.tree, x.role } end
      end
      if not out[1] then local t, role = treeOfSpecIndex(class, idx); out[1] = { t, role } end
      for _, x in ipairs(R.MySpecs()) do
        if x.index ~= idx and x.configured and not out[2] then out[2] = { x.tree, x.role } end
      end
      return out, 1, "spec"
    end
  end
  local tabInfo = GetTalentTabInfo or (SI and SI.GetTalentTabInfo)
  if not tabInfo then return out, active, nil end
  local numGroups = GetNumTalentGroups or (SI and (SI.GetNumSpecGroups or SI.GetNumTalentGroups))
  local groups = (numGroups and select(2, pcall(numGroups))) or 1
  if type(groups) ~= "number" then groups = 1 end
  local activeFn = GetActiveTalentGroup or (SI and (SI.GetActiveSpecGroup or SI.GetActiveTalentGroup))
  if activeFn then
    local ok, a = pcall(activeFn); if ok and tonumber(a) then active = a end
  end
  for g = 1, math.min(groups, 2) do
    local best, bestPts = nil, 0
    for t = 1, 3 do
      local r = { pcall(tabInfo, t, false, false, g) }
      -- a table as answer (new API): { pointsSpent = n }
      if r[1] and type(r[2]) == "table" then r = { true, nil, nil, nil, nil, tonumber(r[2].pointsSpent) } end
      if r[1] then
        local pts = (type(r[6]) == "number" and r[6]) or (type(r[4]) == "number" and r[4]) or 0
        if pts > bestPts then best, bestPts = t, pts end
      end
    end
    if best then out[g] = { best } end
  end
  return out, active, "talents"
end

function R.DefaultRole(class, tree)
  local s = class and R.SPECS[class] and R.SPECS[class][tree]
  return s and s[2] or nil
end
function R.SpecName(class, tree)
  local s = class and R.SPECS[class] and R.SPECS[class][tree]
  return s and (L["RAID_SPEC_" .. s[1]] or s[1]) or "?"
end
function R.RoleName(role) return role and L["RAID_ROLE_" .. role] or "–" end

-- Spec record of a member: { class, m = { tree, role }, o = { tree, role }, t, src }
function R.Spec(key) return R.Store().specs[key or G.MyKey()] end

function R.SaveSpec(key, rec, quiet)
  key = key or G.MyKey()
  local mine = key == G.MyKey()
  if not mine and not R.CanCreate() then U.Print(L.NO_RIGHTS); return false end
  local s = R.Store()
  rec.t = U.Now()
  rec.src = rec.src or (mine and "self" or "lead")
  s.specs[key] = rec
  API.Send("pve", "SPEC", { k = key, s = rec })
  if not quiet then U.Print(L.RAID_SPEC_SAVED:format(G.Display(key))) end
  API.Refresh()
  return true
end

-- Read the talents and fill gaps of the own record (never overwrites a role
-- the member picked)
-- Take the specs from the talents. A choice the member (or the raid lead) made
-- by hand always stays; only force (button "Read talents") replaces it.
function R.UpdateOwnSpec(force)
  local class = R.MyClass()
  if not class then return end
  local cur = R.Spec() or {}
  if not force and (cur.src == "self" or cur.src == "lead") and cur.class == class then return end
  local got, active = R.ReadTalents()
  if force then cur = { class = class, src = "auto" } end
  local rec = { class = class, m = cur.m and U.Copy(cur.m) or nil, o = cur.o and U.Copy(cur.o) or nil, src = cur.src }
  local changed = cur.class ~= class
  local function fill(slot, g)
    local x = got[g]
    if not x then return end
    local tree, role = x[1], x[2]
    rec[slot] = rec[slot] or {}
    if rec[slot][1] ~= tree then rec[slot][1] = tree; changed = true end
    if not rec[slot][2] or (cur.src == "auto") then
      local r = role or R.DefaultRole(class, tree)
      if rec[slot][2] ~= r then rec[slot][2] = r; changed = true end
    end
  end
  local src = select(3, R.ReadTalents())
  if src == "spec" and got[2] and cur.m and cur.m[1] == got[2][1] and cur.m[2] == got[2][2] then
    got[1], got[2] = got[2], got[1]   -- playing the second spec right now
  elseif src == "spec" and not got[2] and cur.m and got[1] and cur.m[1] ~= got[1][1] and cur.o == nil then
    got[2] = got[1]; got[1] = cur.m
  end
  if got[2] then fill("m", 1); fill("o", 2)
  elseif got[1] then
    -- one group readable: it is the active one; the other stays as saved
    fill((active == 2) and "o" or "m", 1)
  end
  if changed or force then
    rec.src = "auto"
    R.SaveSpec(nil, rec, not force)
  end
end

API.Listen("pve", "SPEC", function(data, from)
  local key, rec = data.k, data.s
  if type(key) ~= "string" or type(rec) ~= "table" then return end
  if key ~= from and not R.CanCreate(from) then return end
  local s = R.Store()
  local old = s.specs[key]
  -- a member's own entry wins over an older correction
  if old and (tonumber(old.t) or 0) > (tonumber(rec.t) or 0) then return end
  local clean = { class = R.SPECS[rec.class] and rec.class or (old and old.class), t = tonumber(rec.t) or U.Now(), src = rec.src == "lead" and "lead" or (rec.src == "auto" and "auto" or "self") }
  for _, slot in ipairs({ "m", "o" }) do
    local x = rec[slot]
    if type(x) == "table" then
      local tree = tonumber(x[1])
      local role = R.ROLE_KIND[x[2]] and x[2] or nil
      if tree and tree >= 1 and tree <= 3 then clean[slot] = { tree, role } end
    end
  end
  s.specs[key] = clean
  API.Refresh()
end)

---------------------------------------------------------------------------
-- Readiness: every client tells lockouts, the Drakefire Amulet and that it has
-- the module (on login, after a lockout change, on request)
---------------------------------------------------------------------------
function R.MyLockouts()
  local out = {}
  if not GetNumSavedInstances or not GetSavedInstanceInfo then return out end
  local ok, n = pcall(GetNumSavedInstances)
  if not ok then return out end
  for i = 1, (n or 0) do
    local r = { pcall(GetSavedInstanceInfo, i) }
    if r[1] then
      local name, reset, locked, isRaid, maxPlayers, numEnc, prog = r[2], r[4], r[6], r[9], r[10], r[12], r[13]
      if locked and isRaid and tonumber(maxPlayers) then
        out[tostring(maxPlayers)] = { n = name, r = U.Now() + (tonumber(reset) or 0), p = (prog and numEnc) and (prog .. "/" .. numEnc) or nil }
      end
    end
  end
  return out
end

local AMULET = 16309
-- true / false, or nil when the client gives no way to look
function R.HasAmulet()
  local how = nil
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  if count then
    local ok, n = pcall(count, AMULET, false)
    if ok and type(n) == "number" then
      if n > 0 then return true, "count" end
      how = "count"
    end
  end
  -- worn around the neck
  local inv = GetInventoryItemID or (C_Item and C_Item.GetInventoryItemID)
  if inv then
    local ok, id = pcall(inv, "player", 2)
    if ok then
      if id == AMULET then return true, "neck" end
      how = how or "neck"
    end
  end
  -- in the bags
  local C = C_Container
  local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
  local itemId = (C and C.GetContainerItemID) or GetContainerItemID
  if slots and itemId then
    for bag = 0, 4 do
      local ok, n = pcall(slots, bag)
      for slot = 1, (ok and tonumber(n) or 0) do
        local ok2, id = pcall(itemId, bag, slot)
        if ok2 and id == AMULET then return true, "bags" end
      end
    end
    how = how or "bags"
  end
  if how then return false, how end
  return nil, "no API"
end

function R.SendState()
  if not API.CanSend() then return end
  local st = { v = R.version, lock = R.MyLockouts(), amu = R.HasAmulet() }
  local s = R.Store()
  st.t = U.Now()
  s.state[G.MyKey()] = st
  API.Send("pve", "STATE", st)
end

API.Listen("pve", "STATE", function(data, from)
  if type(data) ~= "table" then return end
  local lock = {}
  for size, x in pairs(type(data.lock) == "table" and data.lock or {}) do
    if type(x) == "table" then lock[tostring(size)] = { n = tostring(x.n or ""):sub(1, 40), r = tonumber(x.r), p = x.p and tostring(x.p):sub(1, 8) } end
  end
  R.Store().state[from] = { v = tonumber(data.v), lock = lock, amu = data.amu, t = U.Now() }
  API.Refresh()
end)

API.Listen("pve", "ASK", function(_, from)
  core.Schedule("pveAnswer", 1 + math.random() * 3, R.SendState)
end)

function R.AskState()
  API.Send("pve", "ASK", {})
  R.SendState()
end

-- readiness of a member for a raid: { online, addon, locked = info|nil, amulet = true|false|nil }
function R.Ready(e, key)
  local t = R.TemplateOf(e)
  local r = G.roster[key]
  local st = R.Store().state[key]
  local fresh = st and (U.Now() - (st.t or 0)) < 3 * 86400
  local out = { online = r and r.online or false, addon = fresh and true or false }
  if fresh and t then
    local l = st.lock and st.lock[tostring(t.size)]
    if l and (l.r or 0) > U.Now() then out.locked = l end
    if t.amulet then out.amulet = st.amu end
  end
  if t and t.amulet and out.amulet == nil then
    local su = E.Signup(e, key)
    local a = su and su.f and su.f.amulet
    if a ~= nil then out.amulet = (a == "yes") end
  end
  return out
end

---------------------------------------------------------------------------
-- Players of a raid (with the role of the current boss setup)
---------------------------------------------------------------------------
function R.Plan(e)
  e.pve = e.pve or {}
  local p = e.pve
  p.g = p.g or {}    -- key -> group
  p.o = p.o or {}    -- order (keys), tanks are always put on top
  p.sw = p.sw or {}  -- [boss] = { key = true }: plays the second role at this boss
  p.b = tonumber(p.b) or 0  -- current boss setup (0 = standard)
  return p
end

-- may this class play the role? (unknown class: yes)
function R.RoleOk(class, role)
  if not role or not R.ROLE_KIND[role] then return false end
  local set = class and R.CLASS_ROLES[class]
  return not set or set[role] == true
end

-- the only role a class can play (rogue, hunter, mage, warlock), else nil
function R.OnlyRole(class)
  local set = class and R.CLASS_ROLES[class]
  if not set then return nil end
  local one
  for r in pairs(set) do if one then return nil end one = r end
  return one
end

function R.RolesOf(class)
  local out = {}
  for _, r in ipairs(R.ROLES) do if R.RoleOk(class, r) then out[#out + 1] = r end end
  return out
end

-- the raid lead sets a member's role for this raid (nil: back to the sign-up)
function R.SetRole(e, key, role)
  if not R.CanEdit(e) then return false end
  local p = R.Plan(e)
  p.r = p.r or {}
  p.r[key] = role
  R.Changed(e)
  return true
end

function R.Player(e, key, boss)
  local su = E.Signup(e, key)
  local f = su and su.f or {}
  local sp = R.Spec(key) or {}
  local r = G.roster[key]
  local class = (r and r.class) or f.class or sp.class
  local pl = R.Plan(e)
  local lead = pl.r and pl.r[key]
  local role
  for _, cand in ipairs({ lead or false, f.role or false, (sp.m and sp.m[2]) or false, R.DefaultRole(class, sp.m and sp.m[1]) or false, R.OnlyRole(class) or false }) do
    if cand and R.RoleOk(class, cand) then role = cand; break end
  end
  local byLead = lead ~= nil and role == lead
  local tree = tonumber(f.tree) or (sp.m and sp.m[1])
  local off = (f.off and f.off ~= "none" and f.off) or (sp.o and sp.o[2])
  local offTree = sp.o and sp.o[1]
  if off == role or not R.RoleOk(class, off) then off = nil end
  local p = R.Plan(e)
  boss = boss or p.b
  local swapped = boss and boss > 0 and p.sw[boss] and p.sw[boss][key] and off and true or false
  local main = role
  if swapped then role = off; tree = offTree or tree end
  return { key = key, class = class, tree = tree, role = role, kind = role and R.ROLE_KIND[role] or nil, main = main, off = off,
    swapped = swapped, byLead = byLead, st = E.Status(e, key), c = su and su.c, src = su and su.src }
end

local function inRaid(st) return st == "in" or st == "late" end

local function orderIndex(p)
  local idx = {}
  for i, k in ipairs(p.o) do idx[k] = i end
  return idx
end

-- members of group g, tanks first, then in the order the raid lead chose
function R.Group(e, g, boss)
  local p = R.Plan(e)
  local idx = orderIndex(p)
  local list = {}
  for key, grp in pairs(p.g) do
    if grp == g and inRaid(E.Status(e, key)) then list[#list + 1] = R.Player(e, key, boss) end
  end
  table.sort(list, function(a, b)
    local ta, tb = a.kind == "tank" and 0 or 1, b.kind == "tank" and 0 or 1
    if ta ~= tb then return ta < tb end
    local ia, ib = idx[a.key] or 999, idx[b.key] or 999
    if ia ~= ib then return ia < ib end
    return a.key < b.key
  end)
  return list
end

-- signed up with yes/late but in no group
function R.Pool(e, boss)
  local p = R.Plan(e)
  local t = R.TemplateOf(e)
  local list = {}
  for _, s in ipairs(E.SignupList(e)) do
    local g = p.g[s.key]
    if inRaid(s.st) and (not g or g > t.groups) then list[#list + 1] = R.Player(e, s.key, boss) end
  end
  return list
end

function R.ByState(e, st, boss)
  local list = {}
  for _, s in ipairs(E.SignupList(e)) do
    if s.st == st then list[#list + 1] = R.Player(e, s.key, boss) end
  end
  return list
end

-- everyone in the groups
function R.Lineup(e, boss)
  local t = R.TemplateOf(e)
  local out = {}
  for g = 1, t.groups do for _, x in ipairs(R.Group(e, g, boss)) do x.group = g; out[#out + 1] = x end end
  return out
end

function R.RoleCounts(list)
  local n = { tank = 0, heal = 0, melee = 0, range = 0, unknown = 0, total = #list }
  for _, x in ipairs(list) do local k = x.kind or "unknown"; n[k] = n[k] + 1 end
  return n
end

---------------------------------------------------------------------------
-- Changing the line-up (raid lead): saved and sent a moment after the last change
---------------------------------------------------------------------------
function R.CanEdit(e) return E.CanManage(e) end

local function changed(e)
  e.pve.upd = U.Now()
  core.Schedule("pveSave" .. e.id, 2, function() if E.Get(e.id) then E.Save(e) end end)
  API.Refresh()
end
R.Changed = changed

function R.GroupSize(e, g)
  local n = 0
  for key, grp in pairs(R.Plan(e).g) do if grp == g and inRaid(E.Status(e, key)) then n = n + 1 end end
  return n
end

function R.Move(e, key, g)
  if not R.CanEdit(e) then return false end
  local p = R.Plan(e)
  if g and p.g[key] ~= g and R.GroupSize(e, g) >= 5 then return false end
  p.g[key] = g
  changed(e)
  return true
end

function R.Swap(e, a, b)
  if not R.CanEdit(e) or a == b then return false end
  local p = R.Plan(e)
  p.g[a], p.g[b] = p.g[b], p.g[a]
  local idx = orderIndex(p)
  local ia, ib = idx[a], idx[b]
  if ia and ib then p.o[ia], p.o[ib] = b, a end
  changed(e)
  return true
end

-- put key right before other (inside a group)
function R.Reorder(e, key, before)
  if not R.CanEdit(e) or key == before then return false end
  local p = R.Plan(e)
  -- make sure every member of the raid has a place in the order
  local idx = orderIndex(p)
  for _, s in ipairs(E.SignupList(e)) do if not idx[s.key] then p.o[#p.o + 1] = s.key; idx[s.key] = #p.o end end
  for i = #p.o, 1, -1 do if p.o[i] == key then table.remove(p.o, i) end end
  local pos = #p.o + 1
  for i, k in ipairs(p.o) do if k == before then pos = i; break end end
  table.insert(p.o, pos, key)
  changed(e)
  return true
end

-- drop of a dragged player on a target: a group slot (empty) or another player
function R.Drop(e, key, target)
  if not key or not target then return false end
  local p = R.Plan(e)
  if target.key then
    if target.key == key then return false end
    local ga, gb = p.g[key], p.g[target.key]
    if ga and ga == gb then return R.Reorder(e, key, target.key) end
    return R.Swap(e, key, target.key)
  end
  return R.Move(e, key, target.group or nil)
end

function R.ToggleSwap(e, boss, key)
  if not R.CanEdit(e) or not boss or boss < 1 then return false end
  local p = R.Plan(e)
  p.sw[boss] = p.sw[boss] or {}
  p.sw[boss][key] = (not p.sw[boss][key]) or nil
  changed(e)
  return true
end

function R.SetBoss(e, boss)
  if not R.CanEdit(e) then return false end
  R.Plan(e).b = boss or 0
  changed(e)
  return true
end

-- fill the groups: tanks and healers spread over all groups, melee from the
-- front, range from the back; members already placed stay where they are
function R.AutoFill(e)
  if not R.CanEdit(e) then return false end
  local t = R.TemplateOf(e)
  local p = R.Plan(e)
  local free = {}
  for g = 1, t.groups do free[g] = 5 - R.GroupSize(e, g) end
  local pool = R.Pool(e, 0)
  local by = { tank = {}, heal = {}, melee = {}, range = {}, other = {} }
  for _, x in ipairs(pool) do local k = by[x.kind] and x.kind or "other"; by[k][#by[k] + 1] = x end
  local function place(x, g) p.g[x.key] = g; free[g] = free[g] - 1 end
  local function spread(list)
    local g = 1
    for _, x in ipairs(list) do
      for _ = 1, t.groups do
        if free[g] > 0 then place(x, g); g = g % t.groups + 1; break end
        g = g % t.groups + 1
      end
    end
  end
  local function fill(list, from, to, step)
    for _, x in ipairs(list) do
      for g = from, to, step do if free[g] > 0 then place(x, g); break end end
    end
  end
  spread(by.tank); spread(by.heal)
  fill(by.melee, 1, t.groups, 1)
  fill(by.range, t.groups, 1, -1)
  fill(by.other, 1, t.groups, 1)
  changed(e)
  return true
end

function R.ClearPlan(e)
  if not R.CanEdit(e) then return false end
  local p = R.Plan(e)
  p.g, p.o = {}, {}
  changed(e)
  return true
end

---------------------------------------------------------------------------
-- Buffs, debuffs, utility of the current line-up
---------------------------------------------------------------------------
function R.Provides(id, x)
  local b = R.ALLPROV[id]
  if not b or not x.class then return false end
  return b.fn(x) and true or false
end

-- { [id] = { n, keys = { key = true } } } over the whole line-up
function R.Coverage(e, boss)
  local list = R.Lineup(e, boss)
  local out = {}
  for id in pairs(R.ALLPROV) do out[id] = { n = 0, keys = {} } end
  for _, x in ipairs(list) do
    for id in pairs(R.ALLPROV) do
      if R.Provides(id, x) then out[id].n = out[id].n + 1; out[id].keys[x.key] = true end
    end
  end
  return out, list
end

-- per group: buffs present and hints for what is missing
function R.GroupBuffs(e, g, boss)
  local list = R.Group(e, g, boss)
  local have, miss = {}, {}
  local melee, casters = 0, 0
  for _, x in ipairs(list) do
    if x.kind == "melee" or x.kind == "tank" then melee = melee + 1 end
    if (x.kind == "range" and x.class ~= "HUNTER") or x.kind == "heal" then casters = casters + 1 end
  end
  for _, b in ipairs(R.BUFFS) do
    if b.scope == "group" then
      for _, x in ipairs(list) do if R.Provides(b.id, x) then have[#have + 1] = b.id; break end end
    end
  end
  local got = {}
  for _, id in ipairs(have) do got[id] = true end
  if melee >= 2 and not got.wf then miss[#miss + 1] = "RAID_MISS_WF" end
  if melee >= 2 and not got.lotp then miss[#miss + 1] = "RAID_MISS_LOTP" end
  if casters >= 3 and not got.moonkin then miss[#miss + 1] = "RAID_MISS_MOON" end
  return have, miss, list
end

-- what a boss needs, and whether the line-up covers it
function R.BossNeeds(e, boss)
  local t = R.TemplateOf(e)
  local needs = t and t.bossNeeds and t.bossNeeds[boss]
  if not needs then return {} end
  local cov = R.Coverage(e, boss)
  local out = {}
  for _, id in ipairs(needs) do
    local ok
    if id == "tremor_all" then
      local groups, with = 0, 0
      for g = 1, t.groups do
        local m = R.Group(e, g, boss)
        if #m > 0 then
          groups = groups + 1
          for _, x in ipairs(m) do if x.class == "SHAMAN" then with = with + 1; break end end
        end
      end
      out[#out + 1] = { id = id, ok = groups > 0 and with >= groups, info = with .. "/" .. groups }
    elseif R.ALLPROV[id] and R.ALLPROV[id].unknown then
      out[#out + 1] = { id = id, unknown = true }
    else
      ok = cov[id] and cov[id].n > 0
      out[#out + 1] = { id = id, ok = ok, info = cov[id] and tostring(cov[id].n) }
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Raid night: sort the raid into the planned groups
---------------------------------------------------------------------------
local sortTries = 0
function R.SortStep(e)
  if not IsInRaid or not IsInRaid() then U.Print(L.RAID_SORT_NORAID); return end
  if InCombatLockdown and InCombatLockdown() then U.Print(L.RAID_SORT_COMBAT); return end
  local p = R.Plan(e)
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local where, count = {}, {}
  for g = 1, 8 do count[g] = 0 end
  for i = 1, n do
    local _, _, sub = GetRaidRosterInfo(i)
    local key = G.UnitKey("raid" .. i)
    where[i] = { key = key, sub = sub }
    if sub then count[sub] = (count[sub] or 0) + 1 end
  end
  local moved = 0
  for i, w in ipairs(where) do
    local want = w.key and p.g[w.key]
    if want and w.sub ~= want then
      if (count[want] or 0) < 5 then
        pcall(SetRaidSubgroup, i, want)
        count[w.sub] = count[w.sub] - 1; count[want] = count[want] + 1
        moved = moved + 1
      else
        -- swap with someone in the target group who does not belong there
        for j, o in ipairs(where) do
          if o.sub == want and (not o.key or p.g[o.key] ~= want) then
            pcall(SwapRaidSubgroup, i, j)
            o.sub, w.sub = w.sub, want
            moved = moved + 1
            break
          end
        end
      end
      if moved >= 4 then break end
    end
  end
  sortTries = sortTries + 1
  if moved > 0 and sortTries < 20 then
    core.Schedule("pveSort", 0.6, function() R.SortStep(e) end)
  else
    sortTries = 0
    U.Print(L.RAID_SORT_DONE)
  end
end

function R.SortRaid(e)
  sortTries = 0
  if UnitIsGroupLeader and not UnitIsGroupLeader("player") and not (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) then
    U.Print(L.INVITE_NO_LEAD); return
  end
  R.SortStep(e)
end

---------------------------------------------------------------------------
-- Text for Discord
---------------------------------------------------------------------------
function R.ExportText(e, boss)
  local t = R.TemplateOf(e)
  boss = boss or R.Plan(e).b
  local lines = {}
  local bossName = (boss and boss > 0) and t.bosses[boss] or L.RAID_SETUP_STD
  lines[#lines + 1] = "**" .. e.name .. "** · " .. U.FormatTime(e.start) .. " · " .. bossName
  local n = R.RoleCounts(R.Lineup(e, boss))
  lines[#lines + 1] = L.RAID_EXPORT_COUNTS:format(n.tank, n.heal, n.melee, n.range)
  for g = 1, t.groups do
    local names = {}
    for _, x in ipairs(R.Group(e, g, boss)) do names[#names + 1] = G.Display(x.key) .. " (" .. (x.role and R.RoleName(x.role) or L.RAID_KIND_unknown) .. ")" end
    lines[#lines + 1] = L.RAID_GROUP_N:format(g) .. ": " .. (#names > 0 and table.concat(names, ", ") or "–")
  end
  for _, st in ipairs({ "tent", "late", "bench" }) do
    local names = {}
    for _, x in ipairs(R.ByState(e, st, boss)) do
      if st ~= "late" or not R.Plan(e).g[x.key] then names[#names + 1] = G.Display(x.key) end
    end
    if #names > 0 then lines[#lines + 1] = L["ST_" .. st] .. ": " .. table.concat(names, ", ") end
  end
  local pool = {}
  for _, x in ipairs(R.Pool(e, boss)) do pool[#pool + 1] = G.Display(x.key) end
  if #pool > 0 then lines[#lines + 1] = L.RAID_POOL .. ": " .. table.concat(pool, ", ") end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Event types and registration
---------------------------------------------------------------------------
local function roleOptions(withNone, class)
  local o = {}
  if withNone then o[#o + 1] = { "none", "RAID_ROLE_none" } end
  for _, r in ipairs(R.ROLES) do if R.RoleOk(class, r) then o[#o + 1] = { r, "RAID_ROLE_" .. r } end end
  return o
end

local function fieldsFor(t)
  local f = {
    { id = "role", kind = "choice", labelKey = "RAID_F_ROLE", short = L.RAID_F_ROLE_S, options = function() return roleOptions(false, R.MyClass()) end, required = true,
      default = function()
        local s = R.Spec()
        local r = s and s.m and s.m[2] or R.DefaultRole(R.MyClass(), s and s.m and s.m[1]) or R.OnlyRole(R.MyClass())
        return R.RoleOk(R.MyClass(), r) and r or nil
      end,
      validate = function(v) if v and not R.RoleOk(R.MyClass(), v) then return L.RAID_ROLE_NOT_CLASS end end,
      format = function(v) return R.RoleName(v) end },
    { id = "off", kind = "choice", labelKey = "RAID_F_OFF", short = L.RAID_F_OFF_S, options = function() return roleOptions(true, R.MyClass()) end,
      default = function() local s = R.Spec(); return s and s.o and s.o[2] or "none" end },
    { id = "class", kind = "auto", hidden = true, get = function() return R.MyClass() end },
    { id = "tree", kind = "auto", hidden = true, get = function() local s = R.Spec(); return s and s.m and s.m[1] end },
  }
  if t.amulet then
    f[#f + 1] = { id = "amulet", kind = "auto", labelKey = "RAID_F_AMULET", short = L.RAID_F_AMULET_S,
      get = function() local a = R.HasAmulet(); if a == nil then return nil end return a and "yes" or "no" end,
      format = function(v) return v == "yes" and L.YES or L.NO end }
  end
  return f
end

local types = {}
for _, t in ipairs(R.TEMPLATES) do
  types[#types + 1] = {
    id = "raid_" .. t.id, nameKey = t.labelKey, descKey = "RAID_DESC_" .. t.id, kind = "short", group = "raid",
    gmax = t.size, icon = t.icon, raid = t.id,
    minLevel = function() return (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60 end,
    canCreate = function(key) return R.CanCreate(key) end,
    signupFields = fieldsFor(t),
  }
end

API.RegisterModule({
  id = "pve", nameKey = "MOD_PVE", version = R.version,
  tag = { key = "TAB_RAIDS" },
  requires = { api = 5 },
  eventTypes = types,
})

-- bench counts, own spec, readiness
core.On("EVENT_ENDED", function(e)
  if not R.IsRaid(e) then return end
  local s = R.Store()
  for _, x in ipairs(E.SignupList(e)) do
    if x.st == "bench" then s.bench[x.key] = (s.bench[x.key] or 0) + 1 end
    if e.attended and e.attended[x.key] then s.bench[x.key] = 0 end
  end
end)

-- a notice when the raid lead puts me into a group
local lastGroup = {}
core.On("EVENT_UPDATED", function(e)
  if not R.IsRaid(e) or not E.IsOpen(e) then return end
  local g = e.pve and e.pve.g and e.pve.g[G.MyKey()]
  if g and lastGroup[e.id] ~= g then
    API.AddNotice({ key = "raidgrp:" .. e.id, group = L.TAB_RAIDS, text = L.RAID_NOTICE_GROUP:format(e.name, g), view = "raidplan" })
  end
  lastGroup[e.id] = g
end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UPDATE_INSTANCE_INFO")
pcall(f.RegisterEvent, f, "PLAYER_TALENT_UPDATE")
pcall(f.RegisterEvent, f, "ACTIVE_TALENT_GROUP_CHANGED")
f:SetScript("OnEvent", function(_, ev)
  if ev == "PLAYER_ENTERING_WORLD" then
    if RequestRaidInfo then pcall(RequestRaidInfo) end
    core.Schedule("pveLogin", 12, function() R.UpdateOwnSpec(); R.SendState() end)
  elseif ev == "UPDATE_INSTANCE_INFO" then
    core.Schedule("pveState", 5, R.SendState)
  else
    core.Schedule("pveSpec", 3, R.UpdateOwnSpec)
  end
end)

---------------------------------------------------------------------------
-- /gem raid [an|vorläufig|spät|bank|ab|import]
---------------------------------------------------------------------------
local WORDS = { an = "in", ja = "in", yes = "in", ["in"] = "in", ["vorläufig"] = "tent", tent = "tent", tentative = "tent",
  ["spät"] = "late", late = "late", bank = "bench", bench = "bench", ab = "out", nein = "out", no = "out", out = "out" }
API.AddCommand("raid", function(arg)
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "import" then API.Open("raidimport"); return end
  local st = WORDS[arg]
  if st then
    local e = R.NextRaid()
    if not e then U.Print(L.RAID_NONE); return end
    local cur = E.Signup(e)
    E.SetSignup(e, { st = st, c = cur and cur.c, f = cur and cur.f })
    U.Print(L.RAID_SIGNED:format(e.name, L["ST_" .. st]))
    return
  end
  API.Open("raids")
end)

---------------------------------------------------------------------------
-- /gem probe: dual spec, lockouts, amulet on this client
---------------------------------------------------------------------------
API.AddProbe("pve", function()
  local P = core.Probe
  local got, active, src = R.ReadTalents()
  local t = {}
  for g, x in pairs(got) do t[#t + 1] = "group " .. g .. ": tree " .. tostring(x[1]) .. (x[2] and (" (" .. x[2] .. ")") or "") end
  return {
    { "talent API", "GetTalentTabInfo " .. P.Has(GetTalentTabInfo) .. " · GetNumTalentGroups " .. P.Has(GetNumTalentGroups) .. " · GetSpecialization " .. P.Has(GetSpecialization) },
    { "specs (loadout saved = *)", (function()
      local t = {}
      local specs = R.MySpecs()
      if specs[1] and specs[1].initial then return "one spec for the whole class (" .. tostring(specs[1].name) .. ")" end
      for _, x in ipairs(specs) do t[#t + 1] = x.index .. " " .. tostring(x.name) .. " → " .. tostring(x.role) .. (x.configured and " *" or "") end
      return table.concat(t, " · ")
    end)() },
    { "loadouts (third with most points = tree)", (function()
      local t = {}
      for _, l in ipairs(R.Loadouts()) do
        t[#t + 1] = (l.active and "ACTIVE " or "") .. (l.selected and "SELECTED " or "") .. tostring(l.name) .. " #" .. tostring(l.id) ..
          ": " .. (l.pts and table.concat(l.pts, "/") or "-") .. " → " .. (l.tree and R.SpecName(R.MyClass(), l.tree) or "?") .. " (" .. tostring(l.info) .. ")"
      end
      return #t > 0 and table.concat(t, " · ") or "none (C_ClassTalents " .. P.Has(C_ClassTalents) .. ", C_Traits " .. P.Has(C_Traits) .. ")"
    end)() },
    { "talents read", (#t > 0 and table.concat(t, "; ") or "nothing") .. " · active " .. tostring(active) .. " · via " .. tostring(src) },
    { "lockouts (GetNumSavedInstances)", GetNumSavedInstances and P.Try(GetNumSavedInstances) or "no" },
    { "first lockout", (GetSavedInstanceInfo and GetNumSavedInstances and (select(2, pcall(GetNumSavedInstances)) or 0) > 0) and P.Try(GetSavedInstanceInfo, 1) or "none" },
    { "Drakefire Amulet", (function() local a, how = R.HasAmulet(); return tostring(a) .. " (" .. tostring(how) .. ")" end)() },
    { "C_Item.GetItemCount / GetItemCount", P.Has(C_Item and C_Item.GetItemCount) .. " / " .. P.Has(GetItemCount) .. " · test (Hearthstone 6948): " .. (((C_Item and C_Item.GetItemCount) or GetItemCount) and P.Try((C_Item and C_Item.GetItemCount) or GetItemCount, 6948) or "–") },
  }
end)
-- Raid spells for the assignments (0.8.0): which classic spells this client
-- still knows (by spell ID, shows the name in the client language) and every
-- spell in the own spell book.
local PROBE_SPELLS = {
  { "paladin", { 19740, 19742, 20217, 20911, 19977, 1038, 25895, 1912, 25782, 25894, 25898, 25899, 25890, 465, 7294, 19746, 19876, 19888, 19891 } },
  { "warlock", { 1490, 17862, 704, 1714, 702, 980, 603, 18223 } },
  { "shaman", { 8512, 8075, 8835, 5675, 5394, 8227, 8190, 8143, 8170, 8166, 8184, 10595, 8177, 25908, 3738 } },
  { "priest", { 6346, 1243, 14752, 976, 21562 } },
  { "druid/mage/hunter/warrior", { 1126, 21849, 1459, 23028, 604, 1008, 13159, 20043, 6673, 469, 7386, 770, 11198 } },
}
local function spellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, i = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(i) == "table" then return i.name end
  end
  if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok then return n end end
end
local function spellBook()
  local out = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local li = C_SpellBook.GetSpellBookSkillLineInfo(i)
      if li then
        for j = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
          local ok, n = pcall(C_SpellBook.GetSpellBookItemName, j, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0)
          if ok and n then out[#out + 1] = n end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
    for t = 1, GetNumSpellTabs() do
      local _, _, off, num = GetSpellTabInfo(t)
      for j = off + 1, off + num do
        local ok, n = pcall(GetSpellBookItemName, j, BOOKTYPE_SPELL or "spell")
        if ok and n then out[#out + 1] = n end
      end
    end
  end
  local seen, uniq = {}, {}
  for _, n in ipairs(out) do if not seen[n] then seen[n] = true; uniq[#uniq + 1] = n end end
  return uniq
end
API.AddProbe("raidspells", function()
  local rows = {}
  for _, g in ipairs(PROBE_SPELLS) do
    local t = {}
    for _, id in ipairs(g[2]) do t[#t + 1] = id .. "=" .. (spellName(id) or "–") end
    rows[#rows + 1] = { "spells " .. g[1], table.concat(t, " · ") }
  end
  local book = spellBook()
  rows[#rows + 1] = { "own spell book (" .. #book .. ")", #book > 0 and table.concat(book, " · ") or "not readable" }
  return rows
end)

core.HelpExt = (core.HelpExt or "") .. " · /gem raid [an|vorläufig|spät|bank|ab|import]"
