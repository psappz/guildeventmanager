local ADDON, ns = ...
-- Deeds (0.9): achievements in the spirit of WoW Forever's Legacy points.
--   * Characters at level 60 with both main professions at 300: 2, 3, 4, 5 of them
--     (per person: main and twinks)
--   * Double agent: a level 60 character on each faction on the same realm
--     (possible on PvE realms only)
--   * Gold paid into the guild bank (net, withdrawals count against it):
--     10, 100, 500, 1000, 2500 gold – 1 gold = 1 GP
-- Every client reports only its own characters and its own deposits, as marker
-- entries without points (why alt60 / dblagent / gbank); the achievements give the GP.
local U, G = ns.U, ns.Guild
local D = {}
ns.Deeds = D

local MAXLVL = 60
local PROFMAX = 300

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return unpack(r, 2)
end

---------------------------------------------------------------------------
-- What every character of the account is (kept per account, also on
-- characters outside the guild, e.g. one of the other faction)
---------------------------------------------------------------------------
local function store()
  if not ns.db then return nil end
  ns.db.deedChars = ns.db.deedChars or {}
  return ns.db.deedChars
end

-- the two main professions: { { name, rank, max } }
function D.MainProfessions()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    local p1, p2 = call(GetProfessions)
    for _, idx in ipairs({ p1, p2 }) do
      if idx then
        local name, _, rank, max = call(GetProfessionInfo, idx)
        if name then out[#out + 1] = { name = name, rank = tonumber(rank) or 0, max = tonumber(max) or 0 } end
      end
    end
  end
  return out
end

function D.Record()
  local s = store()
  if not s then return nil end
  local name = call(UnitName, "player")
  local realm = call(GetRealmName)
  if type(name) ~= "string" or type(realm) ~= "string" then return nil end
  local _, fac = call(UnitFactionGroup, "player")
  local rec = { name = name, realm = realm, fac = fac, lvl = tonumber(call(UnitLevel, "player")) or 0, profs = D.MainProfessions(), ts = U.Now() }
  s[name .. "-" .. realm] = rec
  return rec
end

-- level 60 and both main professions at 300
function D.Qualifies(rec)
  if not rec or (rec.lvl or 0) < MAXLVL then return false end
  local n = 0
  for _, p in ipairs(rec.profs or {}) do if (p.rank or 0) >= PROFMAX then n = n + 1 end end
  return n >= 2
end

-- a level 60 character of the other faction on the same realm in this account
function D.OtherFaction(rec)
  if not rec or (rec.lvl or 0) < MAXLVL or not rec.fac then return nil end
  for _, r in pairs(store() or {}) do
    if r.realm == rec.realm and r.fac and r.fac ~= rec.fac and (r.lvl or 0) >= MAXLVL then return r end
  end
  return nil
end

---------------------------------------------------------------------------
-- Reports (only in an activated guild; once per character)
---------------------------------------------------------------------------
local function charFlags()
  ns.char = ns.char or {}
  ns.char.deeds = ns.char.deeds or {}
  return ns.char.deeds
end

function D.Check()
  local rec = D.Record()
  if not rec or not ns.Comm.CanSend() then return end
  local f = charFlags()
  if not f.alt60 and D.Qualifies(rec) then
    if ns.Points.AddSelf("deed", 0, "alt60", { flag = "q" }) then f.alt60 = U.Now() end
  end
  if not f.dblagent and D.OtherFaction(rec) then
    if ns.Points.AddSelf("deed", 0, "dblagent", { flag = rec.fac }) then f.dblagent = U.Now() end
  end
end

-- gold paid in or taken out of the guild bank (copper; sent in whole gold)
local function money(copper)
  copper = tonumber(copper) or 0
  if copper == 0 then return end
  local f = charFlags()
  f.gbankCopper = (f.gbankCopper or 0) + copper
  local gold = (f.gbankCopper >= 0) and math.floor(f.gbankCopper / 10000) or -math.floor(-f.gbankCopper / 10000)
  if gold ~= 0 and ns.Comm.CanSend() then
    if ns.Points.AddSelf("deed", 0, "gbank", { n = gold }) then f.gbankCopper = f.gbankCopper - gold * 10000 end
  end
end
D.Money = money
if hooksecurefunc then
  pcall(hooksecurefunc, "DepositGuildBankMoney", function(copper) ns.SafeCall("deedDeposit", money, tonumber(copper) or 0) end)
  pcall(hooksecurefunc, "WithdrawGuildBankMoney", function(copper) ns.SafeCall("deedWithdraw", money, -(tonumber(copper) or 0)) end)
end

-- "Softcore" (27.11.): the first death of a person. -1 GP, and the whole guild hears it.
local C = ns.Comm
function D.Died()
  local fl = charFlags()
  if fl.death or not C.CanSend() then return end
  if not ns.Points.AddSelf("deed", 0, "death", {}) then return end
  fl.death = U.Now()
  -- only the person's first death is announced (twinks dying later stay quiet)
  local me = ns.Persons and ns.Persons.MainOf(G.MyKey()) or G.MyKey()
  local before = 0
  for _, e in pairs(ns.Store() and ns.Store().ledger or {}) do
    if e.why == "death" and e.who and (ns.Persons and ns.Persons.MainOf(e.who) or e.who) == me then before = before + 1 end
  end
  if before > 1 then return end
  C.Send("SOFTCORE", {})
  ns.Contest.Alert(ns.L.DEED_SOFT_ME)
end

-- deaths before this version: the game's statistic "Total deaths" (id 60).
-- Found on login: the achievement is booked quietly, without the guild message.
D.DEATH_STAT = 60
function D.StatDeaths()
  if not GetStatistic then return nil end
  local v = call(GetStatistic, D.DEATH_STAT)
  if type(v) ~= "string" and type(v) ~= "number" then return nil end
  local n = tonumber((tostring(v):gsub("[^%d]", "")))
  return n
end

function D.CheckPastDeaths()
  local fl = charFlags()
  if fl.death or not C.CanSend() then return end
  local n = D.StatDeaths()
  if n and n > 0 and ns.Points.AddSelf("deed", 0, "death", { flag = "stat" }) then fl.death = U.Now() end
end

C.On("SOFTCORE", function(_, from)
  if not from or from == G.MyKey() then return end
  ns.Contest.Alert(ns.L.DEED_SOFT_ALERT:format(G.Display(from)))
end)

-- First of a class at level 60 (27.11.): only who levels from 59 to 60 while
-- in the guild counts. The first one of every class gets the achievement; the
-- guild hears it.
D.CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN", "DRUID" }
function D.Dinged(level)
  if tonumber(level) ~= MAXLVL or not C.CanSend() then return end
  local _, cls = call(UnitClass, "player")
  if type(cls) ~= "string" then return end
  local first = true
  for _, e in pairs(ns.Store() and ns.Store().ledger or {}) do
    if e.why == "ding60" and e.flag == cls then first = false; break end
  end
  if not ns.Points.AddSelf("deed", 0, "ding60", { flag = cls }) then return end
  if first then
    C.Send("FIRST60", { c = cls })
    ns.Contest.Alert(ns.L.DEED_FIRST_ME:format(ns.L["DEED_FIRST_" .. cls] or cls))
  end
end

C.On("FIRST60", function(data, from)
  if not from or from == G.MyKey() or type(data) ~= "table" or type(data.c) ~= "string" then return end
  local name = ns.L["DEED_FIRST_" .. data.c]
  if name then ns.Contest.Alert(ns.L.DEED_FIRST_ALERT:format(G.Display(from), name)) end
end)

local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "PLAYER_DEAD" }) do pcall(f.RegisterEvent, f, ev) end
f:SetScript("OnEvent", function(_, ev, a1)
  if ev == "PLAYER_DEAD" then ns.SafeCall("deedDeath", D.Died); return end
  if ev == "PLAYER_LEVEL_UP" then ns.SafeCall("deedDing", D.Dinged, a1) end
  ns.Schedule("gemDeeds", ev == "PLAYER_LOGIN" and 30 or 5, function()
    ns.SafeCall("deeds", D.Check)
    ns.SafeCall("deedPastDeaths", D.CheckPastDeaths)
  end)
end)

---------------------------------------------------------------------------
-- Achievements (worked out from the marker entries of all members)
---------------------------------------------------------------------------
-- characters of a person that qualify: distinct characters with an alt60 entry
local function altAwards(n)
  return function(entries)
    local per, out = {}, {}
    for _, e in ipairs(entries) do
      if e.why == "alt60" and e.who then
        local p = ns.Persons.MainOf(e.who) or e.who
        per[p] = per[p] or { set = {}, n = 0 }
        local x = per[p]
        if not x.set[e.who] then
          x.set[e.who] = true; x.n = x.n + 1
          if x.n == n then out[#out + 1] = { who = e.who, ts = e.ts } end
        end
      end
    end
    return out
  end
end

-- gold paid in, net per person (each entry at most 100,000 gold either way)
local function goldAwards(n)
  return function(entries)
    local per, out, done = {}, {}, {}
    for _, e in ipairs(entries) do
      if e.why == "gbank" and e.who then
        local p = ns.Persons.MainOf(e.who) or e.who
        local g = math.max(-100000, math.min(100000, math.floor(tonumber(e.n) or 0)))
        per[p] = (per[p] or 0) + g
        if not done[p] and per[p] >= n then done[p] = true; out[#out + 1] = { who = e.who, ts = e.ts } end
      end
    end
    return out
  end
end
D.AltAwards, D.GoldAwards = altAwards, goldAwards

local ICON_ALT = "Interface\\Icons\\INV_Misc_Book_09"
local ICON_GOLD = "Interface\\Icons\\INV_Misc_Coin_02"
local list = {
  { id = "alts2", nameKey = "DEED_ALTS2", descKey = "DEED_ALTS_D", n = 2, pts = 50, scope = "forever", compute = altAwards(2), icon = ICON_ALT },
  { id = "alts3", nameKey = "DEED_ALTS3", descKey = "DEED_ALTS_D", n = 3, pts = 100, scope = "forever", compute = altAwards(3), icon = ICON_ALT },
  { id = "alts4", nameKey = "DEED_ALTS4", descKey = "DEED_ALTS_D", n = 4, pts = 150, scope = "forever", compute = altAwards(4), icon = ICON_ALT },
  { id = "alts5", nameKey = "DEED_ALTS5", descKey = "DEED_ALTS_D", n = 5, pts = 250, scope = "forever", compute = altAwards(5), icon = ICON_ALT },
  { id = "dblagent", nameKey = "DEED_DBL", descKey = "DEED_DBL_D", stat = "why", why = "dblagent", n = 1, pts = 100, scope = "forever", hidden = true,
    icon = "Interface\\Icons\\INV_Misc_Bandana_03" },
  -- the first death: -1 GP, shown to the whole guild
  { id = "softcore", nameKey = "DEED_SOFT", descKey = "DEED_SOFT_D", stat = "why", why = "death", n = 1, pts = -1, scope = "forever",
    icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" },
  -- 1 gold = 1 GP: every step gives the gold of that step
  { id = "gold10", nameKey = "DEED_GOLD10", descKey = "DEED_GOLD_D", n = 10, pts = 10, scope = "forever", compute = goldAwards(10), icon = ICON_GOLD },
  { id = "gold100", nameKey = "DEED_GOLD100", descKey = "DEED_GOLD_D", n = 100, pts = 90, scope = "forever", compute = goldAwards(100), icon = ICON_GOLD },
  { id = "gold500", nameKey = "DEED_GOLD500", descKey = "DEED_GOLD_D", n = 500, pts = 400, scope = "forever", compute = goldAwards(500), icon = ICON_GOLD },
  { id = "gold1000", nameKey = "DEED_GOLD1000", descKey = "DEED_GOLD_D", n = 1000, pts = 500, scope = "forever", compute = goldAwards(1000), icon = ICON_GOLD },
  { id = "gold2500", nameKey = "DEED_GOLD2500", descKey = "DEED_GOLD_D", n = 2500, pts = 1500, scope = "forever", compute = goldAwards(2500), icon = ICON_GOLD },
}
-- the first of every class: the earliest entry of the guild wins
-- rank 1 = first, rank 2 = second of the class (by time, tie: lower id)
local function placeOf(cls, rank)
  return function(entries)
    local l = {}
    for _, e in ipairs(entries) do
      if e.why == "ding60" and e.flag == cls and e.who then l[#l + 1] = e end
    end
    table.sort(l, function(a, b)
      if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) < (b.ts or 0) end
      return tostring(a.id) < tostring(b.id)
    end)
    local e = l[rank]
    return e and { { who = e.who, ts = e.ts } } or {}
  end
end
local CLASS_ICON = { WARRIOR = "INV_Sword_27", ROGUE = "INV_ThrowingKnife_04", HUNTER = "INV_Weapon_Bow_07", MAGE = "INV_Staff_13", PRIEST = "INV_Staff_30",
  WARLOCK = "Spell_Nature_FaerieFire", PALADIN = "Spell_Holy_HolyBolt", SHAMAN = "Spell_Nature_BloodLust", DRUID = "Ability_Druid_Maul" }
for _, cls in ipairs(D.CLASSES) do
  list[#list + 1] = { id = "first60_" .. cls:lower(), nameKey = "DEED_FIRST_" .. cls, descKey = "DEED_FIRST_D", n = 1, pts = 50, scope = "forever",
    compute = placeOf(cls, 1), icon = "Interface\\Icons\\" .. CLASS_ICON[cls] }
  list[#list + 1] = { id = "second60_" .. cls:lower(), nameKey = "DEED_SECOND_" .. cls, descKey = "DEED_SECOND_D", n = 1, pts = 1, scope = "forever",
    compute = placeOf(cls, 2), icon = "Interface\\Icons\\" .. CLASS_ICON[cls] }
end
for _, a in ipairs(list) do table.insert(ns.Achievements.DEFAULTS, a) end
ns.Modules.pots[#ns.Modules.pots + 1] = { id = "deed", nameKey = "POT_DEED" }

-- how the marker entries read in the honor book
ns.Ledger.AddFormat("deeds", {
  label = function() return ns.L.POT_DEED end,
  match = function(e) return e.pot == "deed" end,
  text = function(e)
    if e.why == "gbank" then
      local g = tonumber(e.n) or 0
      return (g >= 0 and ns.L.DEED_L_IN or ns.L.DEED_L_OUT):format(math.abs(g))
    elseif e.why == "alt60" then return ns.L.DEED_L_ALT
    elseif e.why == "dblagent" then return ns.L.DEED_L_DBL
    elseif e.why == "death" then return ns.L.DEED_L_DEATH
    elseif e.why == "ding60" then return ns.L.DEED_L_DING:format(ns.L["CLASS_" .. tostring(e.flag)] or ns.L["DEED_FIRST_" .. tostring(e.flag)] or tostring(e.flag)) end
    return e.why
  end,
})

-- /gem probe: does the client give the death statistic? (Probe.lua loads later)
ns.Schedule("gemDeedProbe", 1, function()
  if not ns.Probe then return end
  ns.Probe.Add("deeds", function()
    return { { "statistic total deaths (60)", tostring(D.StatDeaths()) }, { "main professions", (function()
      local t = {}
      for _, p in ipairs(D.MainProfessions()) do t[#t + 1] = p.name .. " " .. p.rank .. "/" .. p.max end
      return #t > 0 and table.concat(t, ", ") or "(none)"
    end)() } }
  end)
end)
