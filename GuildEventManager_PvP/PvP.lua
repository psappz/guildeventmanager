local ADDON, P = ...
-- GuildEventManager PvP module: registration, rules (from the guild profile),
-- shared helpers. Every client reports only its own deeds; the core ledger
-- keeps them and all clients add them up the same way.
local core = GuildEventManagerAPI and GuildEventManagerAPI.core
if not core then return end
P.core = core
GuildEventManagerAPI.pvp = P
P.L = core.L
local U, G, T = core.U, core.Guild, core.Theme

-- Rules: defaults, changed by guild event managers in the PvP tab
P.DEFAULTS = {
  kill = 3,          -- honor per enemy player killed in the open world
  perVictim = 2,     -- counts at most n times per day per enemy
  dailyCap = 100,    -- honor from kills per member and day
  debt = 20,         -- honor for a redeemed blood debt
  debtDays = 7,      -- a debt expires after n days
  coldMin = 5,       -- "served cold": redeemed within n minutes after the death
  drum = 5,          -- honor for following a war drum
  drumWindow = 10,   -- minutes to arrive
  drumRadius = 4,    -- arrival radius in % of the zone map
  revengeChat = 0,   -- 1 = a revenge is also posted in the guild chat (seen without the addon)
  revengeChatMin = 2, -- minutes between two such posts of one member
  makgora = 10,      -- honor for a won Mak'gora (formal duel with witness)
  makgoraWitnesses = 1, -- witnesses needed for a Mak'gora
  oath1 = 10, oath2 = 25, oath3 = 40, -- honor for a fulfilled oath: small, great, mighty
  oathDays = 14,     -- an oath must be fulfilled within n days
  oathWitnesses = 2, -- witnesses needed for a fulfilled oath
  seasonGoal = 5000, -- guild honor in one season for "Unstoppable"
}

function P.Rules()
  local pr = core.Profile.Get()
  if pr == core.Profile.DEFAULTS then return P.DEFAULTS end
  pr.pvp = pr.pvp or {}
  for k, v in pairs(P.DEFAULTS) do if pr.pvp[k] == nil then pr.pvp[k] = v end end
  return pr.pvp
end

---------------------------------------------------------------------------
-- Registration with the core: pot, event type, achievements
---------------------------------------------------------------------------
local I = "Interface\\Icons\\"
local function tiers(base, list)
  local out = {}
  for i, t in ipairs(list) do
    local a = {}
    for k, v in pairs(base) do a[k] = v end
    for k, v in pairs(t) do a[k] = v end
    a.id = base.id .. i
    out[#out + 1] = a
  end
  return out
end

local achs = {
  { id = "firstblood", nameKey = "PVP_ACH_FIRSTBLOOD", stat = "why", why = "kill", n = 1, pts = 10, scope = "forever",
    descKey = "PVP_STAT_KILL", icon = I .. "Ability_Rogue_Eviscerate" },
}
for _, a in ipairs(tiers({ id = "blade", nameKey = "PVP_ACH_BLADE", faction = true, stat = "why", why = "kill", scope = "forever",
  descKey = "PVP_STAT_KILL", icon = I .. "INV_Sword_04" }, {
  { n = 50, pts = 10, tier = "BRONZE" }, { n = 250, pts = 25, tier = "SILVER" },
  { n = 1000, pts = 50, tier = "GOLD", honorKey = "HONOR_BLADE", honorScope = "forever" } })) do achs[#achs + 1] = a end
for _, a in ipairs(tiers({ id = "debt", nameKey = "PVP_ACH_DEBT", stat = "why", why = "debt", scope = "forever",
  descKey = "PVP_STAT_DEBT", icon = I .. "Ability_Warrior_Revenge" }, {
  { n = 1, pts = 10, tier = "BRONZE" }, { n = 10, pts = 25, tier = "SILVER" },
  { n = 50, pts = 50, tier = "GOLD", honorKey = "HONOR_AVENGER", honorScope = "forever" } })) do achs[#achs + 1] = a end
achs[#achs + 1] = { id = "cold", nameKey = "PVP_ACH_COLD", stat = "why", why = "debt", flag = "cold", n = 1, pts = 25,
  scope = "forever", hidden = true, descKey = "PVP_STAT_COLD", icon = I .. "Spell_Frost_FrostShock" }
for _, a in ipairs(tiers({ id = "drum", nameKey = "PVP_ACH_DRUM", stat = "why", why = "drum", scope = "forever",
  descKey = "PVP_STAT_DRUM", icon = I .. "Ability_Warrior_RallyingCry" }, {
  { n = 1, pts = 10, tier = "BRONZE" }, { n = 25, pts = 25, tier = "SILVER" }, { n = 100, pts = 50, tier = "GOLD" } })) do achs[#achs + 1] = a end
achs[#achs + 1] = { id = "firstthere", nameKey = "PVP_ACH_FIRSTTHERE", stat = "why", why = "drum", flag = "first", n = 10, pts = 25,
  scope = "forever", descKey = "PVP_STAT_FIRSTTHERE", icon = I .. "Ability_Rogue_Sprint" }
for _, a in ipairs(tiers({ id = "war", nameKey = "PVP_ACH_WAR", stat = "evtype", evtype = "warband", scope = "forever",
  descKey = "PVP_STAT_WAR", icon = I .. "INV_BannerPVP_01" }, {
  { n = 1, pts = 10, tier = "BRONZE" }, { n = 10, pts = 25, tier = "SILVER" }, { n = 25, pts = 50, tier = "GOLD" } })) do achs[#achs + 1] = a end
achs[#achs + 1] = { id = "fullwar", nameKey = "PVP_ACH_FULLWAR", stat = "why", why = "participate", flag = "full", evtype = "warband",
  n = 1, pts = 25, scope = "forever", descKey = "PVP_STAT_FULLWAR", icon = I .. "INV_Misc_Note_06" }

-- Mak'gora, oaths and season results (Honor.lua, Season.lua)
for _, a in ipairs(tiers({ id = "makgora", nameKey = "PVP_ACH_MAKGORA", faction = true, stat = "why", why = "makgora", scope = "forever",
  descKey = "PVP_STAT_MAKGORA", icon = I .. "Ability_Warrior_Challange" }, {
  { n = 1, pts = 10, tier = "BRONZE" }, { n = 10, pts = 25, tier = "SILVER" },
  { n = 25, pts = 50, tier = "GOLD", honorKey = "HONOR_MAKGORA", honorScope = "forever" } })) do achs[#achs + 1] = a end
achs[#achs + 1] = { id = "challenger", nameKey = "PVP_ACH_CHALLENGER", n = 5, pts = 25, scope = "forever",
  descKey = "PVP_STAT_CHALLENGER", icon = I .. "Ability_Warrior_BattleShout",
  compute = function(...) return P.AchChallenger(...) end, progress = function(...) return P.ProgChallenger(...) end }
achs[#achs + 1] = { id = "unbeaten", nameKey = "PVP_ACH_UNBEATEN", n = 5, pts = 50, scope = "forever",
  descKey = "PVP_STAT_UNBEATEN", icon = I .. "Ability_Warrior_DefensiveStance",
  compute = function(...) return P.AchUnbeaten(...) end, progress = function(...) return P.ProgUnbeaten(...) end }
for _, a in ipairs(tiers({ id = "oath", nameKey = "PVP_ACH_OATH", stat = "why", why = "oath", scope = "forever",
  descKey = "PVP_STAT_OATH", icon = I .. "INV_Misc_Book_09" }, {
  { n = 1, pts = 10, tier = "BRONZE" }, { n = 5, pts = 25, tier = "SILVER" },
  { n = 15, pts = 50, tier = "GOLD", honorKey = "HONOR_OATH", honorScope = "forever" } })) do achs[#achs + 1] = a end
achs[#achs + 1] = { id = "podium", nameKey = "PVP_ACH_PODIUM", n = 1, pts = 25, scope = "forever", repeatable = true,
  descKey = "PVP_STAT_PODIUM", icon = I .. "INV_Misc_Trophy_Argent", compute = function(...) return P.AchPodium(...) end }
achs[#achs + 1] = { id = "champion", nameKey = "PVP_ACH_CHAMPION", faction = true, n = 1, pts = 50, scope = "forever", repeatable = true,
  honorKey = "HONOR_CHAMPION", honorScope = "season", honorPrio = 10,
  descKey = "PVP_STAT_CHAMPION", icon = I .. "INV_Crown_01", compute = function(...) return P.AchChampion(...) end }
achs[#achs + 1] = { id = "unstoppable", nameKey = "PVP_ACH_UNSTOPPABLE", n = 1, pts = 50, scope = "forever", repeatable = true,
  descKey = "PVP_STAT_UNSTOPPABLE", icon = I .. "Spell_Nature_BloodLust", compute = function(...) return P.AchUnstoppable(...) end }
P.SWORD_META = { "firstblood", "debt1", "drum1", "war1", "makgora1", "oath1", "podium" }
achs[#achs + 1] = { id = "sword", nameKey = "PVP_ACH_SWORD", faction = true, meta = P.SWORD_META, n = #P.SWORD_META, pts = 50,
  scope = "forever", descKey = "PVP_STAT_SWORD", icon = I .. "INV_Sword_39" }

GuildEventManagerAPI.RegisterModule({
  id = "pvp", nameKey = "MOD_PVP", version = 1,
  pots = { { id = "honor", nameKey = "POT_HONOR" } },
  eventTypes = {
    { id = "warband", nameKey = "TYPE_WARBAND", descKey = "TYPE_WARBAND_DESC", kind = "short", group = "raid",
      icon = I .. "INV_BannerPVP_01", goalKeys = { "GOAL_WAR_1", "GOAL_WAR_2", "GOAL_WAR_3" } },
    { id = "defense", nameKey = "TYPE_DEFENSE", descKey = "TYPE_DEFENSE_DESC", kind = "short", group = "raid",
      icon = I .. "INV_Shield_06", goalKeys = { "GOAL_DEF_1", "GOAL_DEF_2" } },
  },
  achievements = achs,
})

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local HORDE = { Orc = 1, Scourge = 1, Undead = 1, Tauren = 1, Troll = 1, BloodElf = 1, Goblin = 1, Nightborne = 1,
  HighmountainTauren = 1, MagharOrc = 1, ZandalariTroll = 1, Vulpera = 1 }
local ALLIANCE = { Human = 1, Dwarf = 1, NightElf = 1, Gnome = 1, Draenei = 1, Worgen = 1, VoidElf = 1,
  LightforgedDraenei = 1, DarkIronDwarf = 1, KulTiran = 1, Mechagnome = 1 }

-- Faction of a player GUID from its race ("horde", "alliance" or nil)
function P.FactionOf(guid)
  if not guid or not GetPlayerInfoByGUID then return nil end
  local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, guid)
  if not ok or not race then return nil end
  if HORDE[race] then return "horde" end
  if ALLIANCE[race] then return "alliance" end
  return nil
end

function P.OpenWorld()
  local inInstance = IsInInstance and IsInInstance()
  return not inInstance
end

-- Grey level (gives no honor) as in the classic client
function P.GreyLevel(level)
  level = level or UnitLevel("player") or 1
  if level <= 5 then return 0 end
  if level <= 39 then return level - 5 - math.floor(level / 10) end
  if level <= 59 then return level - 1 - math.floor(level / 5) end
  return level - 9
end

function P.Today() return date("%Y-%m-%d", U.Now()) end

function P.Char()
  if core.demo then return core.demoChar end
  local c = core.char
  if not c then return {} end
  c.pvp = c.pvp or { debts = {}, kills = {} }
  return c.pvp
end

-- Drum / bell sound per faction; falls back to the raid warning sound
function P.PlaySignal()
  if core.db and core.db.pvpMute then return end
  local file = (T.Faction() == "alliance") and "Sound\\Doodad\\BellTollAlliance.ogg" or "Sound\\Event Sounds\\Event_wardrum_ogre.ogg"
  local ok, willPlay = pcall(PlaySoundFile, file, "Master")
  if not (ok and willPlay) then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
end

function P.Notice(msg)
  U.Print(U.Color(U.GOLD, msg))
  if RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, { r = 1, g = 0.75, b = 0.2 })
  end
end

core.HelpExt = (core.HelpExt or "") .. " · /gem pvp · /gem drum help|rally|attack [text] · /gem makgora <name> [stake] · /gem oath [1-3] <text>"
core.SlashExt.pvp = function() core.UI.Show("pvp") end
