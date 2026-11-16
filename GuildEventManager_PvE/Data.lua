local ADDON, R = ...
-- Raid data: templates, roles, specs per class, Raid-Helper spec names, and
-- who brings which buff, debuff or utility. All of it is data so it can be
-- adjusted when WoW Forever changes something (or new raids arrive in 2027).
local core = GuildEventManagerAPI and GuildEventManagerAPI.core
if not core then return end
R.core = core

local I = "Interface\\Icons\\"

-- Roles in display order. tank = main tank or 2nd tank.
R.ROLES = { "mt", "ot", "melee", "range", "heal" }
R.ROLE_KIND = { mt = "tank", ot = "tank", melee = "melee", range = "range", heal = "heal" }
R.ROLE_ICON = {   -- shield, healing cross, sword, bow (Media/Icons, coloured)
  tank = core.W.Icon("role_tank"),
  heal = core.W.Icon("role_heal"),
  melee = core.W.Icon("role_melee"),
  range = core.W.Icon("role_range"),
}

-- Raid templates. Boss names as published for WoW Forever (order may differ in
-- game; the guild can rename them in the raid settings).
R.TEMPLATES = {
  { id = "barrow", size = 10, groups = 2, icon = I .. "INV_Misc_Bone_HumanSkull_01", labelKey = "RAID_T_BARROW",
    need = { tank = 2, heal = 3 },
    bosses = { "Chillhowl", "Elder Tangleclaw", "Khalith the Dreadspinner", "Well of Sorrow", "Amethrax",
      "Del'lynar Songwood", "Ravus and Darlissa", "Sonya Darkhallow" } },
  { id = "hyjal", size = 20, groups = 4, icon = I .. "INV_Misc_Herb_Felblossom", labelKey = "RAID_T_HYJAL",
    need = { tank = 2, heal = 5 },
    bosses = { "Bandalar", "Ancient of Decay", "Time-Lost Battalion", "Sylvestris Dusksong", "Old Gloomlurker",
      "Gharalis the Abyssal", "Kathris the Haunted", "Anara Chillwind", "Elder Minderel", "Tracker Stillwind",
      "Council of Thorns", "Nythus the Dreambound", "The Wild King" } },
  { id = "ony", size = 40, groups = 8, icon = I .. "INV_Misc_Head_Dragon_01", labelKey = "RAID_T_ONY",
    need = { tank = 3, heal = 10 },
    bosses = { "Onyxia" },
    amulet = 16309,   -- Drakefire Amulet
    bossNeeds = { [1] = { "fearward", "tremor_all", "fireres" } } },
}
R.TPL = {}
for _, t in ipairs(R.TEMPLATES) do R.TPL[t.id] = t end

-- Talent trees per class: tree index -> spec label key and default role
R.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
R.SPECS = {
  WARRIOR = { { "Arms", "melee" }, { "Fury", "melee" }, { "Protection", "mt" } },
  PALADIN = { { "Holy", "heal" }, { "Protection", "mt" }, { "Retribution", "melee" } },
  HUNTER  = { { "BeastMastery", "range" }, { "Marksmanship", "range" }, { "Survival", "range" } },
  ROGUE   = { { "Assassination", "melee" }, { "Combat", "melee" }, { "Subtlety", "melee" } },
  PRIEST  = { { "Discipline", "heal" }, { "Holy", "heal" }, { "Shadow", "range" } },
  SHAMAN  = { { "Elemental", "range" }, { "Enhancement", "melee" }, { "Restoration", "heal" } },
  MAGE    = { { "Arcane", "range" }, { "Fire", "range" }, { "Frost", "range" } },
  WARLOCK = { { "Affliction", "range" }, { "Demonology", "range" }, { "Destruction", "range" } },
  DRUID   = { { "Balance", "range" }, { "Feral", "melee" }, { "Restoration", "heal" } },
}

-- Raid-Helper spec names (template "wowforever"): class, tree, role.
-- Doubled names get a trailing 1 in Raid-Helper.
R.RH_SPECS = {
  Arms = { "WARRIOR", 1, "melee" }, Fury = { "WARRIOR", 2, "melee" }, Protection = { "WARRIOR", 3, "mt" },
  Holy1 = { "PALADIN", 1, "heal" }, Protection1 = { "PALADIN", 2, "mt" }, Retribution = { "PALADIN", 3, "melee" },
  Beastmastery = { "HUNTER", 1, "range" }, BeastMastery = { "HUNTER", 1, "range" }, Marksmanship = { "HUNTER", 2, "range" }, Survival = { "HUNTER", 3, "range" },
  Assassination = { "ROGUE", 1, "melee" }, Combat = { "ROGUE", 2, "melee" }, Subtlety = { "ROGUE", 3, "melee" },
  Discipline = { "PRIEST", 1, "heal" }, Holy = { "PRIEST", 2, "heal" }, Shadow = { "PRIEST", 3, "range" }, Smite = { "PRIEST", 2, "range" },
  Elemental = { "SHAMAN", 1, "range" }, Enhancement = { "SHAMAN", 2, "melee" }, Restoration1 = { "SHAMAN", 3, "heal" },
  Arcane = { "MAGE", 1, "range" }, Fire = { "MAGE", 2, "range" }, Frost = { "MAGE", 3, "range" },
  Affliction = { "WARLOCK", 1, "range" }, Demonology = { "WARLOCK", 2, "range" }, Destruction = { "WARLOCK", 3, "range" },
  Balance = { "DRUID", 1, "range" }, Feral = { "DRUID", 2, "melee" }, Guardian = { "DRUID", 2, "mt" }, Restoration = { "DRUID", 3, "heal" },
}
-- Raid-Helper status classes and roles
R.RH_STATUS = { Bench = "bench", Late = "late", Tentative = "tent", Absence = "out", Absent = "out" }
R.RH_ROLES = { Tanks = "mt", Tank = "mt", Melee = "melee", Ranged = "range", Range = "range", Healers = "heal", Healer = "heal" }

---------------------------------------------------------------------------
-- Buffs, debuffs, utility: who provides them.
-- p = { class, tree, role } of a player in the current boss setup
---------------------------------------------------------------------------
local function cls(...) local set = {}; for _, c in ipairs({ ... }) do set[c] = true end; return function(p) return set[p.class] end end
local function tree(c, t) return function(p) return p.class == c and p.tree == t end end
local function any(...) local f = { ... }; return function(p) for _, fn in ipairs(f) do if fn(p) then return true end end return false end end

R.BUFFS = {
  { id = "mark", scope = "raid", fn = cls("DRUID") },
  { id = "fort", scope = "raid", fn = cls("PRIEST") },
  { id = "ai", scope = "raid", fn = cls("MAGE") },
  { id = "shadowprot", scope = "raid", fn = cls("PRIEST") },
  { id = "bless", scope = "raid", fn = cls("PALADIN") },
  { id = "shout", scope = "group", fn = cls("WARRIOR") },
  { id = "lotp", scope = "group", fn = tree("DRUID", 2), wants = "melee" },
  { id = "moonkin", scope = "group", fn = tree("DRUID", 1), wants = "caster" },
  { id = "wf", scope = "group", fn = cls("SHAMAN"), wants = "melee" },
  { id = "tremor", scope = "group", fn = cls("SHAMAN") },
  { id = "manatide", scope = "group", fn = tree("SHAMAN", 3), wants = "caster" },
  { id = "aura", scope = "group", fn = cls("PALADIN") },
  { id = "pact", scope = "group", fn = cls("WARLOCK") },
  { id = "ts", scope = "group", fn = tree("HUNTER", 2) },
}
R.DEBUFFS = {
  { id = "sunder", fn = cls("WARRIOR") },
  { id = "ff", fn = cls("DRUID") },
  { id = "curse", fn = cls("WARLOCK") },
  { id = "weave", fn = tree("PRIEST", 3) },
  { id = "scorch", fn = tree("MAGE", 2) },
  { id = "demo", fn = cls("WARRIOR") },
  { id = "thunder", fn = cls("WARRIOR") },
}
-- Priests remove magic and disease, but no poison.
R.UTILITY = {
  { id = "decurse", fn = cls("MAGE", "DRUID") },
  { id = "dispel", fn = cls("PRIEST", "PALADIN") },
  { id = "poison", fn = cls("DRUID", "SHAMAN", "PALADIN") },
  { id = "disease", fn = cls("PRIEST", "PALADIN", "SHAMAN") },
  { id = "fearward", fn = any(cls("PRIEST"), cls("SHAMAN")) },
  { id = "kick", fn = cls("ROGUE", "SHAMAN", "MAGE", "WARRIOR") },
  { id = "bres", fn = cls("DRUID") },
  { id = "soulstone", fn = cls("WARLOCK") },
}
R.ALLPROV = {}
for _, list in ipairs({ R.BUFFS, R.DEBUFFS, R.UTILITY }) do for _, b in ipairs(list) do R.ALLPROV[b.id] = b end end
R.ALLPROV.tremor_all = { id = "tremor_all", fn = cls("SHAMAN") }
R.ALLPROV.fireres = { id = "fireres", fn = function() return false end, unknown = true }

R.CLASS_COLOR = {
  WARRIOR = "ffc69b6d", PALADIN = "fff48cba", HUNTER = "ffaad372", ROGUE = "fffff468", PRIEST = "ffffffff",
  SHAMAN = "ff0070dd", MAGE = "ff3fc7eb", WARLOCK = "ff8788ee", DRUID = "ffff7c0a",
}
