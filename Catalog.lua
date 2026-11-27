local ADDON, ns = ...
-- Modules of the guild (API 7). A module counts as part of the guild as soon
-- as the guild master or an event manager has it installed: his client writes
-- it into the guild profile (the catalogue) with name, description and where
-- to get it, so members without the module know about it too.
-- Members get one notice per new module and may say "not interested" for
-- add-on modules (not for the core modules PvP and raids).
local U, G = ns.U, ns.Guild
local K = {}
ns.Catalog = K

-- bundled with the addon: always on, cannot be muted
K.CORE = { core = true, pvp = true, pve = true }

local function L() return ns.L end

function K.IsCore(id) return K.CORE[id] == true end

-- the guild's catalogue: id -> { name, desc, points, get, v, by, at }
function K.List()
  local p = ns.Profile.Get()
  return p.mods or {}
end

function K.Info(id) return K.List()[id] end

-- text of the own installed module (in the own language)
local function textOf(def, key) return key and ns.L[key] or nil end

local function entryOf(def)
  local a = type(def.about) == "table" and def.about or {}
  local points = {}
  for _, k in ipairs(type(a.points) == "table" and a.points or {}) do
    local t = textOf(def, k)
    if t and #points < 4 then points[#points + 1] = t:sub(1, 120) end
  end
  return {
    name = (def.name or (def.nameKey and ns.L[def.nameKey]) or def.id):sub(1, 40),
    desc = (textOf(def, a.descKey) or ""):sub(1, 300),
    points = #points > 0 and points or nil,
    get = type(a.get) == "string" and a.get:sub(1, 80) or nil,
    v = K.OwnVersion(def.id),
  }
end

-- version string of an installed module (TOC "Version" of its addon, else the def's number)
function K.OwnVersion(id)
  if id == "core" then return ns.VERSION end
  local def = ns.Modules.modules[id]
  if not def then return nil end
  if def.addon then
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = pcall(get, def.addon, "Version")
    if ok and v then return v end
  end
  return def.version and tostring(def.version) or nil
end

-- A manager's client adds his installed add-on modules that the guild does not know yet.
function K.Sync()
  if ns.demo or not G.IsActivated() or not G.IsManager() then return end
  local known = K.List()
  local add = {}
  for id, def in pairs(ns.Modules.modules) do
    if not K.IsCore(id) and not known[id] then add[id] = entryOf(def) end
  end
  if not next(add) then return end
  ns.Profile.Update(function(p)
    p.mods = p.mods or {}
    for id, x in pairs(add) do
      x.by, x.at = G.MyKey(), U.Now()
      p.mods[id] = x
    end
  end)
end

-- the guild drops a module from its catalogue (managers, settings page)
function K.Remove(id)
  if not G.IsManager() then return end
  ns.Profile.Update(function(p) if p.mods then p.mods[id] = nil end end)
end

---------------------------------------------------------------------------
-- Interest (per player and guild)
---------------------------------------------------------------------------
local function muteStore()
  local s = ns.Store()
  if not s then return {} end
  s.mute = s.mute or {}
  return s.mute
end

function K.IsInterested(id)
  if not id or K.IsCore(id) then return true end
  return not muteStore()[id]
end

function K.SetInterest(id, on)
  if not id or K.IsCore(id) then return end
  muteStore()[id] = (not on) and true or nil
  ns.Notices.Remove("mod:" .. id)
  ns.Fire("INTEREST_CHANGED", id, on and true or false)
  if ns.Events.CheckInvites then ns.Events.CheckInvites() end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- module of an event (also for types this client does not have)
function K.ModuleOf(e)
  local typeId = type(e) == "table" and e.type or e
  local t = typeId and ns.Modules.Type(typeId)
  if t then return t.module end
  local k = ns.Profile.Get().typesKnown or {}
  return k[typeId] and k[typeId].module or nil
end

function K.Muted(e)
  local id = K.ModuleOf(e)
  return id ~= nil and not K.IsInterested(id)
end

-- Taking part needs the module installed (add-on modules). nil = fine, else the reason.
function K.MissingFor(e)
  local typeId = e and e.type
  if not typeId or ns.Modules.Type(typeId) then return nil end
  local id = K.ModuleOf(e)
  if id and K.IsCore(id) then return nil end      -- core modules: as before, sign-up without data
  local info = id and K.Info(id)
  local name = info and info.name or (id or ns.Modules.TypeName(typeId))
  if info and info.get then return L().MOD_NEEDED_GET:format(name, info.get) end
  return L().MOD_NEEDED:format(name)
end

---------------------------------------------------------------------------
-- Notices: one per new module of the guild
---------------------------------------------------------------------------
local function seenStore()
  local s = ns.Store()
  if not s then return nil end
  s.modSeen = s.modSeen or {}
  return s.modSeen
end

function K.CheckNew()
  local seen = seenStore()
  if not seen or ns.demo then return end
  for id, info in pairs(K.List()) do
    if not seen[id] then
      seen[id] = true
      local installed = ns.Modules.Installed(id)
      local by = info.by and G.Display(info.by) or "?"
      ns.Notices.Add({
        key = "mod:" .. id, group = "module", mod = id,
        text = L().MOD_NEW_NOTICE:format(info.name or id, by) .. (installed and "" or ("  " .. U.Color(U.WARN, L().MOD_NOT_INSTALLED))),
      })
      ns.Fire("MODULE_NEW", id)
    end
  end
  seen._init = true
end

ns.On("PROFILE_CHANGED", function() ns.SafeCall("catalog", K.CheckNew) end)
ns.On("ACTIVATED", function()
  ns.Schedule("gemCatalog", 6, function()
    ns.SafeCall("catalogSync", K.Sync)
    ns.SafeCall("catalog", K.CheckNew)
  end)
end)

---------------------------------------------------------------------------
-- Versions: every client tells its versions in the HELLO when it logs in.
-- Seeing a higher version of the core or of an add-on module one has gives
-- one notice per version ("please update via CurseForge"). Builds with a
-- suffix (e.g. 0.9.0-dev, the developer's test builds) are never compared.
---------------------------------------------------------------------------
local function parse(v)
  if type(v) ~= "string" or v:find("%-") or v:find("[^%d%.]") then return nil end
  local out = {}
  for n in v:gmatch("%d+") do out[#out + 1] = tonumber(n) end
  return #out > 0 and out or nil
end

-- true when a is newer than b (both plain release versions)
function K.Newer(a, b)
  local x, y = parse(a), parse(b)
  if not x or not y then return false end
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p > q end
  end
  return false
end

-- own versions: the core package (PvP and raids come with it) and the add-on modules
function K.Versions()
  local out = { core = ns.VERSION }
  for id in pairs(ns.Modules.modules) do
    if not K.IsCore(id) then out[id] = K.OwnVersion(id) end
  end
  return out
end

local function seenVersions()
  if not ns.db then return {} end
  ns.db.versions = ns.db.versions or { best = {}, told = {} }
  return ns.db.versions
end

function K.Highest(id) return seenVersions().best[id] end

-- versions of another member (from HELLO or VER); returns true if he is behind us
function K.SeeVersions(vs, from)
  if type(vs) ~= "table" then return false end
  local store, own, behind = seenVersions(), K.Versions(), false
  for id, v in pairs(vs) do
    if type(id) == "string" and type(v) == "string" and #v <= 20 and parse(v) then
      if not store.best[id] or K.Newer(v, store.best[id]) then store.best[id] = v end
      local mine = own[id]
      if mine and parse(mine) then          -- a developer build (suffix) is never told to update
        if K.Newer(v, mine) and store.told[id] ~= v then
          store.told[id] = v
          local name = id == "core" and "GuildEventManager" or ((ns.Modules.modules[id] and (ns.Modules.modules[id].name or ns.L[ns.Modules.modules[id].nameKey])) or id)
          ns.Notices.Add({ key = "ver:" .. id, group = "update", text = L().VERSION_NEWER:format(name, v, mine), view = "settings" })
          ns.Fire("NEWER_VERSION", id, v)
        elseif K.Newer(mine, v) then behind = true end
      end
    end
  end
  return behind
end

-- someone with an older version says hello: tell him ours (at most every 10 minutes)
local lastTold = 0
function K.MaybeTell(vs)
  if U.Now() - lastTold < 600 then return end
  lastTold = U.Now()
  ns.Schedule("gemVersion", 2 + math.random() * 8, function() ns.Comm.Send("VER", { vs = K.Versions() }) end)
end

ns.Comm.On("VER", function(data, from) K.SeeVersions(data.vs, from) end)

---------------------------------------------------------------------------
-- Areas of a module (0.9): a module may split its event types into areas
-- (`area = "pvp"` / `"pve"` on the type, `areas = { "pvp", "pve" }` on the
-- module). The guild master installs the whole module and decides which
-- areas he unlocks for his guild; types without area are always open.
-- Locked by default. Kept in the guild profile: profile.areas[module][area] = true
---------------------------------------------------------------------------
function K.Areas(id)
  local def = ns.Modules.modules[id]
  local out = {}
  for _, a in ipairs(def and type(def.areas) == "table" and def.areas or {}) do
    local aid = type(a) == "table" and a.id or a
    if type(aid) == "string" then
      out[#out + 1] = { id = aid, name = (type(a) == "table" and a.nameKey and ns.L[a.nameKey]) or ns.L["AREA_" .. aid:upper()] or aid }
    end
  end
  return out
end

function K.AreaOn(id, area)
  if not area then return true end
  local p = ns.Profile.Get()
  local a = type(p.areas) == "table" and p.areas[id]
  return type(a) == "table" and a[area] == true or false
end

-- only the guild master
function K.SetArea(id, area, on)
  if not G.IsLeader() then U.Print(ns.L.AREA_ONLY_GM); return false end
  return ns.Profile.Update(function(p)
    p.areas = type(p.areas) == "table" and p.areas or {}
    p.areas[id] = type(p.areas[id]) == "table" and p.areas[id] or {}
    p.areas[id][area] = on and true or nil
  end)
end

-- is the event type unlocked in this guild? (module area)
function K.TypeOpen(t)
  if not (t and t.area) then return true end
  return K.AreaOn(t.module, t.area)
end

-- the same area settings in two profiles?
function K.SameAreas(a, b)
  a, b = type(a) == "table" and a or {}, type(b) == "table" and b or {}
  for _, x in ipairs({ { a, b }, { b, a } }) do
    for mod, set in pairs(x[1]) do
      local other = type(x[2][mod]) == "table" and x[2][mod] or {}
      for area, v in pairs(type(set) == "table" and set or {}) do
        if (v == true) ~= (other[area] == true) then return false end
      end
    end
  end
  return true
end
