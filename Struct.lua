local ADDON, ns = ...
-- Guild structure (0.9): how the guild sees itself, apart from the WoW ranks.
--
-- * Ranks in the addon (pr.struct.ranks, in order): { id, name, wow = rank index,
--   virt = true for virtual ranks, out = true outside the order (twinks, bank) }.
--   WoW ranks are only groups of rights; several addon ranks may share one.
-- * Functions (pr.struct.funcs): { id, name, col = "rrggbb", ranks = { wow index },
--   base = "lead"|"raid"|"cls"|"twink"|"otwink"|"bank"|"trial"|"inactive"|nil }.
--   Functions with a base drive GEM (leadership, twink ranks, bank, inactive);
--   name and colour are free. Own functions (no base) are labels.
-- * Addon rank of a member (pr.memberRank[mainKey] = rank id), set by the
--   leadership; default: the first addon rank in the order with his WoW rank.
-- * Org chart (pr.org = { nodes = { { id, kind, title, who, parent, cls = { CLASS } } } }).
-- All of it lives in the guild profile (synced, changed by the guild leadership).
local U, G = ns.U, ns.Guild
local S = {}
ns.Struct = S

S.BASES = { "lead", "raid", "cls", "twink", "otwink", "bank", "trial", "inactive" }
S.FIXED = { lead = true, raid = true, cls = true, twink = true, otwink = true, bank = true, inactive = true }   -- used by GEM: rename yes, delete no
-- functions without WoW ranks that posts can take on in the org chart (deletable)
S.PRESETS = { { "hr", "9fbdf0" }, { "fin", "a9d98a" }, { "rec", "f58cba" }, { "prof", "fff569" }, { "evt", "ff805c" }, { "pvp", "ff805c" } }
S.COLORS = { "e6ba5c", "c9a8ef", "8fd0e8", "8fe0c8", "a9d98a", "9fbdf0", "bdad9c", "ff805c", "f58cba", "fff569" }
local DEFCOL = { lead = "e6ba5c", raid = "c9a8ef", cls = "8fd0e8", twink = "8fe0c8", otwink = "8fe0c8", bank = "a9d98a", trial = "9fbdf0", inactive = "bdad9c" }

local function prof() return ns.Profile and ns.Profile.Get() or {} end

-- name heuristics for the first structure
local function guess(name)
  local n = tostring(name or ""):lower()
  if n:find("twink") then
    if n:find("offiz") or n:find("officer") then return "otwink" end
    return "twink"
  end
  if n:find("bank") or n:find("versorg") then return "bank" end
  if n:find("inakt") or n:find("inactiv") then return "inactive" end
  if n:find("initiand") or n:find("probe") or n:find("rekrut") or n:find("trial") or n:find("recruit") then return "trial" end
  if n:find("spie") or n:find("raidle") or n:find("raid lead") then return "raid" end
  return nil
end

-- Builds a structure from the WoW ranks (and the 0.9 rank settings) when there is none
function S.Default()
  local pr = prof()
  local ranks, funcs = {}, {}
  local by = {}
  local lead = { 0 }
  for _, r in ipairs(pr.leadRanks or { 1 }) do lead[#lead + 1] = r end
  local L = ns.L
  for i = 0, 20 do
    local n = G.rankNames[i]
    if n then
      local g = guess(n)
      if n == pr.twinkRank then g = "twink" elseif n == pr.officerTwinkRank then g = "otwink"
      elseif n == pr.inactiveRank then g = "inactive" end
      if g then by[g] = by[g] or {}; table.insert(by[g], i) end
      ranks[#ranks + 1] = { id = "w" .. i, name = n, wow = i, out = (g == "twink" or g == "otwink" or g == "bank") or nil }
    end
  end
  by.lead = lead
  for _, b in ipairs(S.BASES) do
    funcs[#funcs + 1] = { id = b, base = b, name = L["ST_F_" .. b] or b, col = DEFCOL[b], ranks = by[b] or {} }
  end
  return { ranks = ranks, funcs = funcs }
end

-- preset functions that are missing (and were not deleted) are added to a copy
local function withPresets(st)
  local have, missing = {}, false
  for _, f in ipairs(st.funcs or {}) do have[f.id] = true end
  for _, p in ipairs(S.PRESETS) do if not have[p[1]] and not (st.deleted and st.deleted[p[1]]) then missing = true end end
  if not missing then return st end
  local c = U.Copy(st)
  c.funcs = c.funcs or {}
  for _, p in ipairs(S.PRESETS) do
    if not have[p[1]] and not (st.deleted and st.deleted[p[1]]) then
      c.funcs[#c.funcs + 1] = { id = p[1], name = ns.L["ORG_D_" .. p[1]] or p[1], col = p[2], ranks = {} }
    end
  end
  return c
end

function S.Get()
  local pr = prof()
  if type(pr.struct) ~= "table" or type(pr.struct.ranks) ~= "table" or #pr.struct.ranks == 0 then
    return withPresets(S.Default()), true
  end
  return withPresets(pr.struct)
end

-- Saves a changed structure (leadership only)
function S.Save(st)
  if not S.CanEdit() then return false end
  ns.Profile.Update(function(pr) pr.struct = st end)
  if ns.Persons then ns.Persons.Dirty() end
  return true
end

-- Edits a copy and saves it: S.Edit(function(st) ... end)
function S.Edit(fn)
  local st = U.Copy(S.Get())
  fn(st)
  return S.Save(st)
end

function S.CanEdit() return G.IsLead() and not ns.demo end

function S.Func(base)
  for _, f in ipairs(S.Get().funcs or {}) do if f.base == base then return f end end
end

function S.FuncById(id)
  for _, f in ipairs(S.Get().funcs or {}) do if f.id == id then return f end end
end

-- WoW rank indexes of a function (base)
function S.Ranks(base)
  local f = S.Func(base)
  return f and f.ranks or {}
end

function S.HasRank(base, wow)
  if wow == nil then return false end
  for _, r in ipairs(S.Ranks(base)) do if r == wow then return true end end
  return false
end

-- Functions carrying a WoW rank (for tags)
function S.FuncsOfRank(wow)
  local out = {}
  for _, f in ipairs(S.Get().funcs or {}) do
    for _, r in ipairs(f.ranks or {}) do if r == wow then out[#out + 1] = f; break end end
  end
  return out
end

function S.Tag(f)
  local c = f.col or "bdad9c"
  return "|cff" .. c .. "[" .. (f.name or "?") .. "]|r"
end

---------------------------------------------------------------------------
-- Addon ranks
---------------------------------------------------------------------------
function S.Rank(id)
  for i, r in ipairs(S.Get().ranks) do if r.id == id then return r, i end end
end

-- The addon rank of a member (person): set one, else the first with his WoW rank
function S.MemberRank(key)
  local main = ns.Persons and ns.Persons.MainOf(key) or key
  local r = G.roster[key]
  local wow = r and r.rankIndex
  local set = prof().memberRank
  local id = type(set) == "table" and set[main]
  local st = S.Get()
  if id then
    for i, x in ipairs(st.ranks) do if x.id == id and x.wow == wow then return x, i end end
  end
  for i, x in ipairs(st.ranks) do if x.wow == wow and not x.out then return x, i end end
  for i, x in ipairs(st.ranks) do if x.wow == wow then return x, i end end
end

-- Colour of an addon rank (Guild structure); default: the colour of the
-- leadership function for leadership ranks, otherwise a quiet grey
function S.RankCol(x)
  if x and x.col then return x.col end
  if x and G.IsLeadRank(x.wow) then local f = S.Func("lead"); return f and f.col or "e6ba5c" end
  return "bdad9c"
end

-- Badges of a character: its addon rank (round) and its functions (square):
-- functions of the WoW rank, posts and duties in the org chart
function S.Badges(key, withPosts)
  local out = {}
  local r = G.roster[key]
  local x = S.MemberRank(key)
  if x or r then
    local t = x and x.name or (G.rankNames[r.rankIndex] or "")
    if x and x.virt and r then t = t .. " (" .. (G.rankNames[r.rankIndex] or "") .. ")" end
    out[#out + 1] = { text = t, col = S.RankCol(x), round = true }
  end
  if r then for _, f in ipairs(S.FuncsOfRank(r.rankIndex)) do out[#out + 1] = { text = f.name, col = f.col } end end
  if withPosts then
    local function classes(n)
      local cs = {}
      for _, c in ipairs(n.cls or {}) do cs[#cs + 1] = S.ClassName(c) end
      return #cs > 0 and (": " .. table.concat(cs, ", ")) or ""
    end
    for _, n in ipairs(S.PostsOf(key)) do
      if n.kind ~= "gm" and n.kind ~= "off" and n.kind ~= "member" then
        out[#out + 1] = { text = S.KindName(n) .. (n.kind == "cls" and classes(n) or ""), col = S.KindCol(n) }
      end
      for _, d in ipairs(n.duties or {}) do
        local lb = S.DutyLabel(d)
        if lb then out[#out + 1] = { text = lb .. (d == "cls" and classes(n) or ""), col = S.DutyCol(d) } end
      end
    end
  end
  return out
end

-- Order of a member in the addon (lower = higher); outside the order last
function S.Order(key)
  local x, i = S.MemberRank(key)
  if not x then return 999 end
  if x.out then return 500 + i end
  return i
end

function S.SetMemberRank(key, id)
  if not S.CanEdit() then return false end
  local main = ns.Persons and ns.Persons.MainOf(key) or key
  ns.Profile.Update(function(pr)
    pr.memberRank = pr.memberRank or {}
    pr.memberRank[main] = id
  end)
  return true
end

-- Addon ranks a member may get without a WoW rank change (same WoW rank)
function S.RanksFor(key)
  local r = G.roster[key]
  local out = {}
  for _, x in ipairs(S.Get().ranks) do if r and x.wow == r.rankIndex then out[#out + 1] = x end end
  return out
end

function S.NewId() return "r" .. tostring(U.Now()) .. tostring(math.random(100, 999)) end

---------------------------------------------------------------------------
-- Org chart
---------------------------------------------------------------------------
S.KINDS = { "council", "gm", "off", "raid", "cls", "own" }

function S.Org()
  local o = prof().org
  if type(o) ~= "table" or type(o.nodes) ~= "table" or #o.nodes == 0 then
    return S.TemplateOrg("classic"), true
  end
  return o
end

function S.EditOrg(fn)
  if not S.CanEdit() then return false end
  local o = U.Copy(S.Org())
  fn(o)
  ns.Profile.Update(function(pr) pr.org = o end)
  return true
end

-- Persons of the guild leadership (mains), for councils with auto = true
function S.LeadPersons()
  local out, seen = {}, {}
  for k, r in pairs(G.roster) do
    local m = ns.Persons and ns.Persons.MainOf(k) or k
    local mr = G.roster[m]
    if mr and not seen[m] and G.IsLeadRank(mr.rankIndex) then seen[m] = true; out[#out + 1] = m end
  end
  table.sort(out, function(a, b)
    local ra, rb = G.roster[a].rankIndex or 99, G.roster[b].rankIndex or 99
    if ra ~= rb then return ra < rb end
    return G.Display(a) < G.Display(b)
  end)
  return out
end

-- A council with auto = true shows every person of the guild leadership as a
-- member on one level (virtual nodes "lead:<key>"; posts may hang below them)
local function virtualMember(key, parent)
  local info = (S.Org().memberInfo or {})[key] or {}
  return { id = "lead:" .. key, kind = "member", who = key, parent = parent, virtual = true,
    duties = info.duties, cls = info.cls }
end

-- Duties of a post (0.9): posts take on functions of the guild structure
-- (class lead, raid lead, human resources, finance, own ones) – no extra level
-- needed. node.duties holds function ids; names and colours come from the
-- structure (Settings » Guild structure). Old builds stored "txt:<text>".
function S.DutyFuncs()
  local out = {}
  for _, f in ipairs(S.Get().funcs or {}) do
    if f.base == nil or f.base == "raid" or f.base == "cls" then out[#out + 1] = f end
  end
  return out
end

function S.DutyLabel(d)
  if type(d) ~= "string" then return nil end
  if d:sub(1, 4) == "txt:" then return d:sub(5) end
  local f = S.FuncById(d)
  return f and f.name or nil
end

function S.DutyCol(d)
  local f = type(d) == "string" and S.FuncById(d)
  return f and f.col or "e6ba5c"
end

-- colour of the top line of a post: the function of its kind (Guild structure)
function S.KindCol(n)
  if not n then return "6b5445" end
  local f
  if n.kind == "gm" or n.kind == "off" or n.kind == "council" or n.kind == "member" then f = S.Func("lead")
  elseif n.kind == "raid" then f = S.Func("raid")
  elseif n.kind == "cls" then f = S.Func("cls")
  elseif n.duties and n.duties[1] then f = S.FuncById(n.duties[1]) end
  return f and f.col or "ff805c"
end

-- Turns the "txt:" duties of older builds into functions of the structure
function S.MigrateDuties()
  if not S.CanEdit() then return end
  local o = S.Org()
  local texts = {}
  local function scan(list) for _, d in ipairs(list or {}) do if type(d) == "string" and d:sub(1, 4) == "txt:" then texts[d:sub(5)] = true end end end
  for _, n in ipairs(o.nodes or {}) do scan(n.duties) end
  for _, info in pairs(o.memberInfo or {}) do scan(info.duties) end
  if not next(texts) then return end
  local st = U.Copy(S.Get())
  local idOf = {}
  for t in pairs(texts) do
    for _, f in ipairs(st.funcs) do if f.name and f.name:lower() == t:lower() then idOf[t] = f.id end end
    if not idOf[t] then
      local id = S.NewId() .. tostring(#st.funcs)
      st.funcs[#st.funcs + 1] = { id = id, name = t, col = "ff805c", ranks = {} }
      idOf[t] = id
    end
  end
  local org = U.Copy(o)
  local function fix(list)
    for i, d in ipairs(list or {}) do if type(d) == "string" and d:sub(1, 4) == "txt:" then list[i] = idOf[d:sub(5)] end end
  end
  for _, n in ipairs(org.nodes or {}) do fix(n.duties) end
  for _, info in pairs(org.memberInfo or {}) do fix(info.duties) end
  ns.Profile.Update(function(pr) pr.struct = st; pr.org = org end)
end

function S.HasDuty(n, d)
  for _, x in ipairs(n and n.duties or {}) do if x == d then return true end end
  return false
end

-- leads classes: class lead posts and posts with the duty "class lead"
function S.LeadsClasses(n)
  return n and (n.kind == "cls" or S.HasDuty(n, "cls")) or false
end

-- Changes one node; virtual members of a council keep their data in org.memberInfo
function S.EditNode(id, fn)
  return S.EditOrg(function(o)
    if type(id) == "string" and id:sub(1, 5) == "lead:" then
      local key = id:sub(6)
      o.memberInfo = o.memberInfo or {}
      local info = o.memberInfo[key] or {}
      fn(info, o)
      o.memberInfo[key] = info
      return
    end
    for _, n in ipairs(o.nodes) do if n.id == id then fn(n, o) end end
  end)
end

-- Gives or takes a class; a class has exactly one class lead
function S.ToggleClass(id, cls)
  return S.EditOrg(function(o)
    local function strip(t) if t and t.cls then for k = #t.cls, 1, -1 do if t.cls[k] == cls then table.remove(t.cls, k) end end end end
    local target
    if type(id) == "string" and id:sub(1, 5) == "lead:" then
      o.memberInfo = o.memberInfo or {}
      local key = id:sub(6)
      o.memberInfo[key] = o.memberInfo[key] or {}
      target = o.memberInfo[key]
    else
      for _, n in ipairs(o.nodes) do if n.id == id then target = n end end
    end
    if not target then return end
    local had = false
    for _, c in ipairs(target.cls or {}) do if c == cls then had = true end end
    for _, n in ipairs(o.nodes) do strip(n) end
    for _, info in pairs(o.memberInfo or {}) do strip(info) end
    if not had then target.cls = target.cls or {}; target.cls[#target.cls + 1] = cls end
  end)
end

-- All nodes including the virtual council members
function S.AllNodes()
  local out = {}
  for _, n in ipairs(S.Org().nodes) do
    out[#out + 1] = n
    if n.kind == "council" and n.auto then
      for _, k in ipairs(S.LeadPersons()) do out[#out + 1] = virtualMember(k, n.id) end
    end
  end
  return out
end

function S.Node(id)
  if type(id) == "string" and id:sub(1, 5) == "lead:" then
    local key = id:sub(6)
    for _, n in ipairs(S.Org().nodes) do
      if n.kind == "council" and n.auto then return virtualMember(key, n.id) end
    end
    return nil
  end
  for _, n in ipairs(S.Org().nodes) do if n.id == id then return n end end
end

function S.Children(id)
  local out = {}
  local me = S.Node(id)
  if me and me.kind == "council" and me.auto then
    for _, k in ipairs(S.LeadPersons()) do out[#out + 1] = virtualMember(k, id) end
  end
  for _, n in ipairs(S.Org().nodes) do if n.parent == id then out[#out + 1] = n end end
  return out
end

function S.KindName(n)
  if n.kind == "own" or n.kind == "council" then
    return (n.title and n.title ~= "") and n.title or ns.L["ST_K_" .. n.kind]
  end
  if n.kind == "member" then
    local x = S.MemberRank(n.who)
    return x and x.name or ns.L.ST_K_member
  end
  return ns.L["ST_K_" .. n.kind] or n.kind
end

-- Templates for the org chart
S.ORG_TEMPLATES = { "classic", "council", "raid", "empty" }

function S.TemplateOrg(name)
  local nodes, id = {}, 0
  local function add(n) id = id + 1; n.id = id; nodes[#nodes + 1] = n; return id end
  local gm
  for k, r in pairs(G.roster) do if r.rankIndex == 0 then gm = k end end
  local leads = {}
  for _, k in ipairs(S.LeadPersons()) do if k ~= gm then leads[#leads + 1] = k end end
  if name == "council" then
    add({ kind = "council", title = ns.L.ST_K_council, auto = true })
  elseif name == "empty" then
    add({ kind = "gm", who = gm })
  else
    local root = add({ kind = "gm", who = gm })
    local first = root
    for i, k in ipairs(leads) do local x = add({ kind = "off", who = k, parent = root }); if i == 1 then first = x end end
    if name == "raid" then
      local rl = add({ kind = "raid", parent = first })
      add({ kind = "cls", parent = rl, cls = { "WARRIOR", "PALADIN", "ROGUE" } })
      add({ kind = "cls", parent = rl, cls = { "PRIEST", "SHAMAN", "DRUID" } })
      add({ kind = "cls", parent = rl, cls = { "MAGE", "WARLOCK", "HUNTER" } })
    end
  end
  return { nodes = nodes, next = id + 1, template = name }
end

function S.ApplyTemplate(name)
  if not S.CanEdit() then return false end
  local o = S.TemplateOrg(name)
  ns.Profile.Update(function(pr) pr.org = o end)
  return true
end

-- Class leader of a class (class file token, e.g. "MAGE")
function S.ClassLeader(cls)
  for _, n in ipairs(S.AllNodes()) do
    if S.LeadsClasses(n) then for _, c in ipairs(n.cls or {}) do if c == cls then return n end end end
  end
end

-- Posts of a person: { node }
function S.PostsOf(key)
  local main = ns.Persons and ns.Persons.MainOf(key) or key
  local out = {}
  for _, n in ipairs(S.AllNodes()) do
    if n.who and (ns.Persons and ns.Persons.MainOf(n.who) or n.who) == main and n.kind ~= "council"
      and ((n.kind ~= "gm" and n.kind ~= "off" and n.kind ~= "member") or (n.duties and #n.duties > 0)) then out[#out + 1] = n end
  end
  return out
end

-- Raid lead: the person's rank has the function "raid lead", or he holds a raid
-- lead post or the duty "raid lead" in the org chart
function S.IsRaidLead(key)
  local main = ns.Persons and ns.Persons.MainOf(key) or key
  for _, k in ipairs(ns.Persons and ns.Persons.Chars(main) or { main }) do
    local r = G.roster[k]
    if r and S.HasRank("raid", r.rankIndex) then return true end
  end
  for _, n in ipairs(S.AllNodes()) do
    if n.who and (ns.Persons and ns.Persons.MainOf(n.who) or n.who) == main and (n.kind == "raid" or S.HasDuty(n, "raid")) then return true end
  end
  return false
end

-- Classes the person leads (for the "my classes" filter)
function S.MyClasses(key)
  local set = {}
  for _, n in ipairs(S.PostsOf(key or G.MyKey())) do
    if S.LeadsClasses(n) then for _, c in ipairs(n.cls or {}) do set[c] = true end end
  end
  return set
end

-- Classes of the guild (class files of the mains) with persons: { CLASS = { mainKey, ... } }
function S.ClassMembers()
  local out = {}
  for k, r in pairs(G.roster) do
    local main = ns.Persons and ns.Persons.MainOf(k) or k
    if main == k and r.class then
      out[r.class] = out[r.class] or {}
      table.insert(out[r.class], k)
    end
  end
  for _, list in pairs(out) do table.sort(list, function(a, b) return G.Display(a) < G.Display(b) end) end
  return out
end

function S.ClassName(cls)
  local t = LOCALIZED_CLASS_NAMES_MALE
  return (t and t[cls]) or (cls and (cls:sub(1, 1) .. cls:sub(2):lower())) or "?"
end

function S.ClassHex(cls)
  local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
  if not c then return "ede3d4" end
  return string.format("%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end
