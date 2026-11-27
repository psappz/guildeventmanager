local ADDON, ns = ...
-- Person instead of character (0.9): a member's main and twinks count as one
-- person for GP, rankings, achievements and guild achievements.
--
-- * Automatic: all characters of one WoW account share the SavedVariables, so
--   GEM knows them as soon as each has been logged in once. The player picks
--   the main and the visibility on the settings page.
-- * By hand: managers can link twinks of members without the addon
--   ("set by the leadership"). What a player sets for himself wins.
-- * Visibility per player: "guild" (default), "lead" (only managers see the
--   link; sent by whisper to managers, between managers over the officer
--   channel) or "off" (nothing is shared, only this client links).
--
-- Guild store: s.persons[main]  = { alts = { key = true }, vis, v, by }   (players themselves)
--              s.personsLead[main] = { alts = { key = true }, v, by }      (set by managers)
-- Account:     ns.db.account[storeKey] = { chars = { key = ts | false }, main, vis }
local U, G, C = ns.U, ns.Guild, ns.Comm
local P = {}
ns.Persons = P
P.VIS = { "guild", "lead", "off" }

local index           -- alt key -> main key (nil = not built)

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
local function guildStore()
  local s = ns.Store()
  if not s then return nil end
  s.persons = s.persons or {}
  s.personsLead = s.personsLead or {}
  return s
end

function P.Account()
  if not ns.db or ns.demo then return nil end
  local k = G.StoreKey()
  if not k then return nil end
  ns.db.account = ns.db.account or {}
  local a = ns.db.account[k]
  if not a then a = { chars = {}, vis = "guild" }; ns.db.account[k] = a end
  a.chars = a.chars or {}
  return a
end

function P.Dirty()
  index = nil
  if ns.Achievements and ns.Achievements.Dirty then ns.Achievements.Dirty() end
end

local function setOf(list)
  local t = {}
  for k, v in pairs(list or {}) do
    if type(k) == "string" and v == true then t[k] = true
    elseif type(v) == "string" then t[v] = true end
  end
  return t
end

local function listOf(set)
  local t = {}
  for k in pairs(set or {}) do t[#t + 1] = k end
  table.sort(t)
  return t
end

---------------------------------------------------------------------------
-- Index: links set by managers first, the players' own links override them.
-- The own account is linked too when the player chose "off".
---------------------------------------------------------------------------
local function build()
  index = {}
  local s = guildStore()
  local function apply(main, alts)
    for alt in pairs(alts or {}) do if alt ~= main then index[alt] = main end end
  end
  if s then
    local lead = {}
    for m, p in pairs(s.personsLead) do lead[#lead + 1] = { m, p } end
    table.sort(lead, function(a, b) return (a[2].v or 0) < (b[2].v or 0) end)
    for _, x in ipairs(lead) do apply(x[1], x[2].alts) end
    local own = {}
    for m, p in pairs(s.persons) do own[#own + 1] = { m, p } end
    table.sort(own, function(a, b) return (a[2].v or 0) < (b[2].v or 0) end)
    for _, x in ipairs(own) do
      -- a player's own record also says: "my main is not anybody's twink"
      index[x[1]] = nil
      -- a twink counts for the others only after it confirmed the link itself
      -- (sent it once from that character), so nobody can claim strangers
      local okAlts = {}
      for alt in pairs(x[2].alts or {}) do if x[2].ok and x[2].ok[alt] then okAlts[alt] = true end end
      apply(x[1], okAlts)
    end
  end
  local a = P.Account()
  if a and a.main then
    index[a.main] = nil
    for k, v in pairs(a.chars) do if v and k ~= a.main then index[k] = a.main end end
  end
  -- no chains: one step is enough, loops are cut
  for alt, m in pairs(index) do
    local seen = { [alt] = true }
    while index[m] and not seen[m] do seen[m] = true; m = index[m] end
    index[alt] = (m ~= alt) and m or nil
  end
end

-- The person's key (the main) for any character key
function P.MainOf(key)
  if not key then return key end
  if not index then build() end
  return index[key] or key
end

-- All character keys of a person (main first)
function P.Chars(key)
  local main = P.MainOf(key)
  if not index then build() end
  local out = {}
  for alt, m in pairs(index) do if m == main then out[#out + 1] = alt end end
  table.sort(out)
  table.insert(out, 1, main)
  return out
end

function P.Alts(key)
  local t = P.Chars(key)
  table.remove(t, 1)
  return t
end

-- Where a link comes from: "self", "lead" or nil
function P.Source(key)
  local main = P.MainOf(key)
  local alts = P.Alts(main)
  if #alts == 0 then return nil end
  local a = P.Account()
  if a and a.main == main then return "self" end
  local s = guildStore()
  local own = s and s.persons[main]
  if own and own.alts then
    for _, alt in ipairs(alts) do if own.alts[alt] then return "self" end end
  end
  return "lead"
end

-- A table keyed by person that also answers for a twink's key
function P.ByPerson(t)
  return setmetatable(t, { __index = function(tt, k)
    if type(k) ~= "string" then return nil end
    local m = P.MainOf(k)
    if m ~= k then return rawget(tt, m) end
  end })
end

---------------------------------------------------------------------------
-- Own account
---------------------------------------------------------------------------
-- Characters of this account in this guild (in the roster), false = "do not link"
function P.MyChars()
  local a = P.Account()
  local out = {}
  if not a then return out end
  for k, v in pairs(a.chars) do
    if G.roster[k] or k == G.MyKey() then out[#out + 1] = { key = k, linked = v ~= false, main = a.main == k } end
  end
  table.sort(out, function(x, y) return x.key < y.key end)
  return out
end

local function myGroup()
  local a = P.Account()
  if not a or not a.main then return nil end
  local alts = {}
  for k, v in pairs(a.chars) do
    if v and k ~= a.main and (G.roster[k] or k == G.MyKey()) then alts[k] = true end
  end
  return a.main, alts
end

-- Sends the own link (main + twinks) according to the visibility
function P.Publish(target)
  local a = P.Account()
  if not a or not a.main then return end
  local main, alts = myGroup()
  a.v = a.v or U.Now()
  local data = { m = main, a = listOf(alts), v = a.v, vis = a.vis or "guild" }
  local s = guildStore()
  if a.vis == "off" then
    P.PublishExt()
    if s then s.persons[main] = nil end
    data.a, data.off = nil, 1
    if not target then C.Send("PERS", data) end
  elseif a.vis == "lead" then
    if s then s.persons[main] = { alts = alts, ok = U.Copy(alts), vis = "lead", v = a.v, by = G.MyKey() } end
    if target then C.Send("PERS", data, "WHISPER", target)
    else
      for key, r in pairs(G.roster) do
        if r.online and key ~= G.MyKey() and G.IsLead(key) then C.Send("PERS", data, "WHISPER", r.name) end
      end
    end
  else
    if s then s.persons[main] = { alts = alts, ok = U.Copy(alts), vis = "guild", v = a.v, by = G.MyKey() } end
    if not target then C.Send("PERS", data) end
  end
  P.Dirty()
end

local function changed()
  local a = P.Account()
  if a then a.v = U.Now() end
  P.Publish()
  P.PublishExt()
  ns.Fire("PERSONS_CHANGED")
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function P.SetMain(key)
  local a = P.Account()
  if not a or a.chars[key] == nil then return false end
  a.main = key
  a.chars[key] = a.chars[key] or U.Now()
  changed()
  return true
end

function P.SetLinked(key, on)
  local a = P.Account()
  if not a or a.chars[key] == nil or key == a.main then return false end
  a.chars[key] = on and U.Now() or false
  changed()
  return true
end

function P.SetVisibility(vis)
  local a = P.Account()
  if not a or (vis ~= "guild" and vis ~= "lead" and vis ~= "off") then return false end
  a.vis = vis
  changed()
  return true
end

function P.Visibility()
  local a = P.Account()
  return a and a.vis or "guild"
end

-- Called after the guild is known: notes the character, the first one is the main
function P.Login()
  local a = P.Account()
  local me = G.MyKey()
  if not a or not me then return end
  local new = a.chars[me] == nil
  if new then a.chars[me] = U.Now() end
  -- characters of this account that were logged in with GEM before (0.8 and
  -- older kept them in db.chars as "Name Second@SCOPE"); only those in this guild
  local scope = U.Scope and U.Scope()
  for ck in pairs(ns.db.chars or {}) do
    local n, sc = tostring(ck):match("^(.-)@(.+)$")
    if n and (not scope or sc == scope) then
      local k = G.Resolve(n)
      if k and G.roster[k] and a.chars[k] == nil then a.chars[k] = U.Now(); new = true end
    end
  end
  if not a.main or (a.chars[a.main] == nil) then a.main = me; new = true end
  if new then a.v = U.Now() end
  -- remember level and class of this character (for the leadership's view of
  -- twinks outside the guild)
  local ck = U.CharKey and U.CharKey()
  if ck and ns.db.chars then
    ns.db.chars[ck] = ns.db.chars[ck] or {}
    local _, cls = UnitClass("player")
    ns.db.chars[ck].info = { lv = UnitLevel and UnitLevel("player") or nil, cl = cls, ts = U.Now() }
  end
  P.Publish()
  P.PublishExt()
end

---------------------------------------------------------------------------
-- Twinks outside the guild (0.9): characters of this account that are not in
-- this guild (another guild or none). Only the guild leadership sees them, and
-- only if the player allows it (setting, default on; never with visibility "off").
-- Leaders keep them in s.personsExt[main] = { x = { { n, lv, cl } }, v, by }.
---------------------------------------------------------------------------
function P.External()
  local out = {}
  local scope = U.Scope and U.Scope()
  for ck, c in pairs(ns.db and ns.db.chars or {}) do
    local n, sc = tostring(ck):match("^(.-)@(.+)$")
    n = n or tostring(ck)
    -- only characters logged in since 0.9 (they carry level and class); older
    -- entries may be outdated spellings
    local info = type(c) == "table" and c.info
    if info and (not scope or not sc or sc == scope) and not G.Resolve(n) then
      out[#out + 1] = { n = n, lv = info.lv, cl = info.cl }
    end
  end
  table.sort(out, function(a, b) return a.n < b.n end)
  return out
end

-- shared with the visibility: "guild" and "lead" show the leadership the
-- characters outside the guild as well, "off" shares nothing
function P.ShareExternal()
  local a = P.Account()
  return a and a.vis ~= "off" or false
end

-- The person (main) a character outside the guild belongs to (leadership and own account)
function P.ExternalOwner(name)
  if not name then return nil end
  local want = tostring(name):lower()
  local a = P.Account()
  if a and a.main and P.ShareExternal() then
    for _, e in ipairs(P.External()) do if e.n:lower() == want then return a.main end end
  end
  local s = guildStore()
  for m, e in pairs(s and s.personsExt or {}) do
    for _, x in ipairs(e.x or {}) do if tostring(x.n):lower() == want then return m end end
  end
end

function P.SetShareExternal(on)
  local a = P.Account()
  if not a then return end
  a.ext = on and true or false
  P.PublishExt()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function P.PublishExt(target)
  local a = P.Account()
  if not a or not a.main then return end
  local data = { m = a.main, v = U.Now() }
  if P.ShareExternal() then data.x = P.External() else data.off = 1 end
  local s = guildStore()
  if s and G.IsLead() then
    s.personsExt = s.personsExt or {}
    s.personsExt[a.main] = (not data.off) and { x = data.x, v = data.v, by = G.MyKey() } or nil
  end
  if target then C.Send("PERSX", data, "WHISPER", target); return end
  for key, r in pairs(G.roster) do
    if r.online and key ~= G.MyKey() and G.IsLead(key) then C.Send("PERSX", data, "WHISPER", r.name) end
  end
end

function P.ExternalOf(key)
  local s = guildStore()
  local main = P.MainOf(key)
  local a = P.Account()
  if a and a.main == main then return P.ShareExternal() and P.External() or {} end
  local e = s and s.personsExt and s.personsExt[main]
  return e and e.x or {}
end

C.On("PERSX", function(data, from, dist)
  if not G.IsLead() or type(data.m) ~= "string" then return end
  if dist == "OFFICER" and type(data.f) == "string" and G.IsLead(from) then from = data.f end
  -- only the player himself (a character of his person)
  if from ~= data.m and P.MainOf(from) ~= data.m then return end
  local s = guildStore()
  if not s then return end
  s.personsExt = s.personsExt or {}
  local cur = s.personsExt[data.m]
  local v = tonumber(data.v) or 0
  if cur and (cur.v or 0) > v then return end
  if data.off then s.personsExt[data.m] = nil
  else
    local list = {}
    for _, x in ipairs(type(data.x) == "table" and data.x or {}) do
      if type(x) == "table" and type(x.n) == "string" then list[#list + 1] = { n = x.n, lv = tonumber(x.lv), cl = x.cl } end
    end
    s.personsExt[data.m] = { x = list, v = v, by = from }
  end
  if dist == "WHISPER" then
    C.SendOfficer("PERSX", { m = data.m, x = data.x, off = data.off, v = v, f = from })
  end
  ns.Fire("PERSONS_CHANGED")
end)

---------------------------------------------------------------------------
-- Links set by managers (members without the addon, corrections)
---------------------------------------------------------------------------
function P.Assign(alt, main)
  if not G.IsLead() or not alt or alt == main then return false end
  local s = guildStore()
  if not s then return false end
  -- take the twink out of every other manager link
  for m, p in pairs(s.personsLead) do
    if p.alts then p.alts[alt] = nil end
    if m ~= main and not next(p.alts or {}) then s.personsLead[m] = nil end
  end
  if main then
    local p = s.personsLead[main] or { alts = {} }
    p.alts[alt] = true
    p.v, p.by = U.Now(), G.MyKey()
    s.personsLead[main] = p
    C.Send("PERSL", { m = main, a = listOf(p.alts), v = p.v })
  end
  if not main then C.Send("PERSL", { u = alt, v = U.Now() }) end
  P.Dirty()
  ns.Fire("PERSONS_CHANGED")
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
C.On("PERS", function(data, from, dist)
  local s = guildStore()
  if not s or type(data.m) ~= "string" then return end
  local main, alts = data.m, setOf(data.a)
  -- a "lead" link passed on by a manager over the officer channel
  if dist == "OFFICER" and type(data.f) == "string" and G.IsLead(from) then from = data.f end
  -- only a player himself (one of his characters) may send his link
  if from ~= main and not alts[from] then return end
  local cur = s.persons[main]
  local v = tonumber(data.v) or 0
  if cur and (cur.v or 0) > v then return end
  -- a twink may only change a record that already knows him (the main's own
  -- client lists all characters of the account), so nobody can take over
  -- another player's link by naming himself in it
  if cur and from ~= main and cur.by ~= from and not (cur.alts and cur.alts[from]) then return end
  -- drop older own records of the same player (the main changed)
  for m, p in pairs(s.persons) do
    if m ~= main and (alts[m] or m == from or (p.alts and (p.alts[from] or p.alts[main]))) and (p.v or 0) <= v then
      s.persons[m] = nil
    end
  end
  if data.off then
    s.persons[main] = nil
  elseif data.vis == "lead" and not G.IsLead() then
    -- not for us: a member must not keep a link only the leadership may see
    return
  else
    -- confirmations: kept for twinks still listed, the sender confirms himself
    local ok = {}
    if cur and cur.ok then for alt in pairs(cur.ok) do if alts[alt] then ok[alt] = true end end end
    if dist == "OFFICER" then for alt in pairs(setOf(data.ok)) do if alts[alt] then ok[alt] = true end end end
    if from ~= main and alts[from] then ok[from] = true end
    s.persons[main] = { alts = alts, ok = ok, vis = data.vis == "lead" and "lead" or "guild", v = v, by = from }
    -- managers pass "lead" links on to the other managers
    if data.vis == "lead" and dist == "WHISPER" then C.SendOfficer("PERS", { m = main, a = data.a, ok = listOf(ok), v = v, vis = "lead", f = from }) end
  end
  P.Dirty()
  ns.Fire("PERSONS_CHANGED")
end)

C.On("PERSL", function(data, from)
  if not G.IsLead(from) then return end
  local s = guildStore()
  if not s then return end
  local v = tonumber(data.v) or 0
  if data.u then
    for m, p in pairs(s.personsLead) do
      if p.alts and p.alts[data.u] and (p.v or 0) <= v then p.alts[data.u] = nil end
      if not next(p.alts or {}) then s.personsLead[m] = nil end
    end
  elseif type(data.m) == "string" then
    local cur = s.personsLead[data.m]
    if cur and (cur.v or 0) > v then return end
    local alts = setOf(data.a)
    for m, p in pairs(s.personsLead) do
      if m ~= data.m and p.alts then for k in pairs(alts) do p.alts[k] = nil end end
      if m ~= data.m and not next(p.alts or {}) then s.personsLead[m] = nil end
    end
    s.personsLead[data.m] = { alts = alts, v = v, by = from }
  end
  P.Dirty()
  ns.Fire("PERSONS_CHANGED")
end)

-- Sync: HELLO carries the newest link a client knows (ps); managers answer
-- with what is newer. "lead" links go to managers only.
function P.MaxV()
  local s = guildStore()
  local m = 0
  if not s then return 0 end
  for _, p in pairs(s.persons) do m = math.max(m, p.v or 0) end
  for _, p in pairs(s.personsLead) do m = math.max(m, p.v or 0) end
  return m
end

C.On("HELLO", function(data, from)
  -- a manager came online: players with "lead" visibility tell him again
  if G.IsLead(from) then
    local r = G.roster[from]
    ns.Schedule("gemPersLead" .. from, 2 + math.random() * 6, function()
      if P.Visibility() == "lead" then P.Publish(r and r.name or from) end
      P.PublishExt(r and r.name or from)
    end)
  end
  if not G.IsLead() then return end
  local s = guildStore()
  if not s then return end
  local since = tonumber(data.ps) or 0
  ns.Schedule("gemPersAnswer" .. tostring(from), 3 + math.random() * 5, function()
    for m, p in pairs(s.personsLead) do
      if (p.v or 0) > since then C.Send("PERSL", { m = m, a = listOf(p.alts), v = p.v }) end
    end
    for m, p in pairs(s.persons) do
      if (p.v or 0) > since and p.vis ~= "lead" then
        -- forwarded as the player's own link: receivers accept it from the player only,
        -- so a manager re-sends it as a relay record
        C.Send("PERSR", { m = m, a = listOf(p.alts), ok = listOf(p.ok), v = p.v, by = p.by })
      end
    end
  end)
end)

-- Relay of a player's own link by a manager (sync for members who were offline)
C.On("PERSR", function(data, from)
  if not G.IsLead(from) or type(data.m) ~= "string" then return end
  local s = guildStore()
  if not s then return end
  local cur = s.persons[data.m]
  local v = tonumber(data.v) or 0
  if cur and (cur.v or 0) > v then return end
  local alts, ok = setOf(data.a), {}
  if cur and (cur.v or 0) == v and cur.ok then for alt in pairs(cur.ok) do if alts[alt] then ok[alt] = true end end end
  for alt in pairs(setOf(data.ok)) do if alts[alt] then ok[alt] = true end end
  s.persons[data.m] = { alts = alts, ok = ok, vis = "guild", v = v, by = data.by, relay = from }
  P.Dirty()
  ns.Fire("PERSONS_CHANGED")
end)

ns.On("ACTIVATED", function()
  ns.Schedule("gemPersLogin", 6 + math.random() * 6, P.Login)
end)
