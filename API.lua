local ADDON, ns = ...
-- Public API for modules (GuildEventManager_PvP, _PvE, _Holidays, ...).
--
--   GuildEventManagerAPI.RegisterModule({
--     id = "pvp", name = "PvP", version = 1,
--     eventTypes = { { id = "warband", name = "Warband", kind = "short", group = "raid", icon = "Interface\\Icons\\..." } },
--     pots = { { id = "honor", name = "Guild honor" } },
--   })
--   GuildEventManagerAPI.AddPoints(memberName, pot, amount, reason, eventId)   -- managers only
--   GuildEventManagerAPI.IsManager(), .IsActivated(), .Faction(), .Word(key)
GuildEventManagerAPI = {
  version = 1,
  RegisterModule = function(def) return ns.Modules.Register(def) end,
  AddPoints = function(name, pot, amt, why, ev)
    local key = ns.Guild.Resolve(name)
    if not key then return nil end
    return ns.Points.Add(key, pot, amt, why, ev)
  end,
  IsManager = function() return ns.Guild.IsManager() end,
  IsActivated = function() return ns.Guild.IsActivated() end,
  Faction = function() return ns.Theme.Faction() end,
  Word = function(key) return ns.Theme.Word(key) end,
  Open = function(tab) ns.UI.Show(tab) end,
  -- first-party modules (GuildEventManager_PvP, ...) get the core namespace
  core = ns,
}
