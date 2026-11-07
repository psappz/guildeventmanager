local ADDON, ns = ...
-- Module registry. Every event type comes from a module; the core brings three.
-- Separate addons (GuildEventManager_PvP, _PvE, _Holidays) register through
-- GuildEventManagerAPI.RegisterModule (see API.lua).
local M = {}
ns.Modules = M

M.modules = {}   -- id -> def
M.types = {}     -- event type id -> def
M.pots = {       -- point pots; modules may add more (the PvP module adds "honor")
  { id = "event", nameKey = "POT_EVENT" },
  { id = "ach", nameKey = "POT_ACH" },
}

-- def = { id, nameKey or name, version, eventTypes = { { id, nameKey, descKey, kind, group, gmin, gmax, icon } }, pots = { { id, nameKey } } }
function M.Register(def)
  if type(def) ~= "table" or not def.id then return false end
  if not M.modules[def.id] then M.order = M.order or {}; M.order[#M.order + 1] = def.id end
  M.modules[def.id] = def
  for _, t in ipairs(def.eventTypes or {}) do
    t.module = def.id
    M.types[t.id] = t
  end
  for _, p in ipairs(def.pots or {}) do
    local exists = false
    for _, q in ipairs(M.pots) do if q.id == p.id then exists = true end end
    if not exists then M.pots[#M.pots + 1] = p end
  end
  if ns.Achievements then ns.Achievements.Dirty() end
  if ns.UI and ns.UI.Refresh then ns.Schedule("gemModules", 0.2, ns.UI.Refresh) end
  return true
end

function M.Installed(moduleId) return M.modules[moduleId] ~= nil end

function M.Type(id) return M.types[id] end

function M.TypeName(id)
  local t = M.types[id]
  if not t then return id or "?" end
  return t.name or ns.L[t.nameKey] or t.id
end

-- Every known type, also those of modules this client does not have
-- (taken from the guild profile), sorted by module and name
function M.AllTypes()
  local list, have = {}, {}
  for id, t in pairs(M.types) do list[#list + 1] = t; have[id] = true end
  local p = ns.Profile and ns.Profile.Get()
  for id, info in pairs(p and p.typesKnown or {}) do
    if not have[id] then list[#list + 1] = { id = id, module = info.module, name = info.name, missing = true } end
  end
  table.sort(list, function(a, b)
    if a.module ~= b.module then return (a.module == "core") or (b.module ~= "core" and tostring(a.module) < tostring(b.module)) end
    return M.TypeName(a.id) < M.TypeName(b.id)
  end)
  return list
end

-- The core's own event types
M.Register({
  id = "core", nameKey = "MOD_CORE", version = 1,
  eventTypes = {
    { id = "rp", nameKey = "TYPE_RP", descKey = "TYPE_RP_DESC", kind = "short", group = "none", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { id = "meet", nameKey = "TYPE_MEET", descKey = "TYPE_MEET_DESC", kind = "short", group = "none", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    { id = "ritual", nameKey = "TYPE_RITUAL", descKey = "TYPE_RITUAL_DESC", kind = "short", group = "raid", icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing" },
  },
})
