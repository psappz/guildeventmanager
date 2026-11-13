local ADDON, P = ...
-- Open world kills and blood debts.
-- The Forever client runs on the Midnight engine: the combat log
-- (COMBAT_LOG_EVENT_UNFILTERED) is closed to addons, and even registering
-- for it is blocked. So this module uses what addons may still read:
-- * kills: the honorable-kill counter (PLAYER_PVP_KILLS_CHANGED with
--   GetPVPSessionStats) plus the honor chat line for the victim's name
-- * own death: PLAYER_DEAD, and the enemy player who last targeted us
--   (nameplates) or whom we last had as target during the fight
local core = P.core
if not core then return end
local U, G, T, Pts = core.U, core.Guild, core.Theme, core.Points
local L = P.L

local lastEnemy           -- { name, level, t } enemy player seen during the fight
local lastDeath = 0
local lastHK = nil        -- session honorable kills at the last check
local honorLines = {}     -- victim names from the honor chat line { name, t }
local reminded = {}       -- debt id -> GetTime() of the last reminder

local function secret(v) return issecretvalue and issecretvalue(v) or false end

local function unitName(unit)
  local n, second = UnitName(unit)
  if not n or secret(n) then return nil end
  if second and second ~= "" and not secret(second) then return n .. " " .. second end
  return n
end

local function isEnemyPlayer(unit)
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
  local f = UnitFactionGroup(unit)
  if not f or secret(f) then return UnitIsEnemy and UnitIsEnemy("player", unit) or false end
  local mine = UnitFactionGroup("player")
  return f ~= mine and (f == "Horde" or f == "Alliance")
end

local function key(name) return name and tostring(name):lower():gsub("[%-%s]+", " ") or nil end

---------------------------------------------------------------------------
-- Debts (by name: GUIDs of enemies are not readable without the combat log)
---------------------------------------------------------------------------
function P.OpenDebts()
  local list, now = {}, U.Now()
  local maxAge = (P.Rules().debtDays or 7) * 86400
  for _, d in ipairs(P.Char().debts) do
    if d.state == "open" and now - d.t > maxAge then d.state = "expired" end
    if d.state == "open" then list[#list + 1] = d end
  end
  return list
end

local function addDebt(name)
  local c = P.Char()
  for _, d in ipairs(c.debts) do
    if d.state == "open" and key(d.name) == key(name) then
      d.t = U.Now(); d.zone = GetZoneText and GetZoneText() or d.zone
      return d
    end
  end
  local d = { id = U.NewId(), name = name, t = U.Now(), zone = GetZoneText and GetZoneText() or "", state = "open" }
  table.insert(c.debts, 1, d)
  while #c.debts > 50 do table.remove(c.debts) end
  return d
end

function P.OnDeath()
  if GetTime() - lastDeath < 5 then return end
  lastDeath = GetTime()
  if not P.OpenWorld() or not G.IsActivated() then return end
  local name
  if lastEnemy and GetTime() - lastEnemy.t < 20 then name = lastEnemy.name end
  if not name then core.Fire("PVP_DEATH", nil); return end
  local d = addDebt(name)
  U.Print(L.PVP_DEBT_NEW:format(T.Word("DEBT"), d.name, P.Rules().debtDays))
  core.Fire("PVP_DEATH", name)
  core.Fire("PVP_DEBT_NEW", d)
  lastEnemy = nil
  if core.UI then core.UI.Refresh() end
end

---------------------------------------------------------------------------
-- Kills
---------------------------------------------------------------------------
local function killsToday()
  local c = P.Char()
  local day = P.Today()
  if not c.kills or c.kills.day ~= day then c.kills = { day = day, honor = 0, victims = {} } end
  return c.kills
end
function P.KillsToday() return killsToday() end

-- Redeem an open debt against this enemy (from a kill or from his death in our target)
-- how: "kill" (honorable kill), "target" (died in our target), "near" (died near us, nameplate)
function P.RedeemDebt(name, how)
  if not name or not P.OpenWorld() or not G.IsActivated() then return false end
  local r = P.Rules()
  for _, d in ipairs(P.OpenDebts()) do
    if key(d.name) == key(name) then
      d.state = "paid"; d.paid = U.Now()
      local after = U.Now() - d.t
      local cold = after <= (r.coldMin or 5) * 60
      Pts.AddSelf("honor", r.debt, "debt", { flag = cold and "cold" or nil, note = d.name, how = how or "kill", after = after,
        zone = GetZoneText and GetZoneText() or "" })
      P.Notice(L.PVP_DEBT_PAID:format(T.Word("DEBT"), d.name, r.debt))
      core.Fire("PVP_DEBT_PAID", d, cold)
      P.PlaySignal()
      return true
    end
  end
  return false
end

-- name may be nil when the client gives no honor line
function P.OnKill(name, kind)
  if not G.IsActivated() then return end
  core.Fire("PVP_KILL", name, kind or "none")
  if not P.OpenWorld() then return end
  local r = P.Rules()
  local zone = GetZoneText and GetZoneText() or ""
  local victim = name or L.PVP_UNKNOWN

  if name then P.RedeemDebt(name, "kill") end

  local k = killsToday()
  if name then
    local n = (k.victims[key(name)] or 0) + 1
    k.victims[key(name)] = n
    if n > (r.perVictim or 2) then return end
  end
  if k.honor + r.kill > (r.dailyCap or 100) then
    if not k.capped then k.capped = true; U.Print(L.PVP_CAP:format(r.dailyCap)) end
    return
  end
  k.honor = k.honor + r.kill
  Pts.AddSelf("honor", r.kill, "kill", { note = victim, zone = zone })
  if not (core.db and core.db.pvpQuiet) then U.Print(L.PVP_KILL:format(r.kill, victim)) end
end

local function sessionHK()
  if core.demo then return nil end
  if not GetPVPSessionStats then return nil end
  local ok, hk = pcall(GetPVPSessionStats)
  if not ok or secret(hk) then return nil end
  return tonumber(hk)
end

-- "%s dies, honorable kill Rank: %s (%d Honor Points)" and variants -> victim name
local function victimFromHonorLine(msg)
  if not msg or secret(msg) then return nil end
  for _, gs in ipairs({ "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORGAIN_EXHAUSTION1" }) do
    local fmt = _G[gs]
    if type(fmt) == "string" then
      local first = fmt:find("%%s") or fmt:find("%%1%$s")
      if first then
        local prefix = fmt:sub(1, first - 1)
        local after = fmt:sub(first + 2):match("^([^%%]+)")
        if after then
          local pat = "^" .. prefix:gsub("%p", "%%%0") .. "(.-)" .. after:gsub("%p", "%%%0")
          local n = msg:match(pat)
          if n and n ~= "" then return n end
        end
      end
    end
  end
  return nil
end

-- name of an enemy player in this unit slot who is dead right now
local function deadEnemyName(unit)
  if not UnitExists(unit) or not isEnemyPlayer(unit) then return nil end
  local ok, dead = pcall(UnitIsDeadOrGhost, unit)
  if not ok or secret(dead) or not dead then return nil end
  return unitName(unit)
end

local function checkKills()
  local hk = sessionHK()
  if not hk then return end
  if lastHK and hk > lastHK then
    for i = 1, hk - lastHK do
      local line = table.remove(honorLines, 1)
      local name = line and (GetTime() - line.t < 10) and line.name or nil
      -- the honor line may not be readable on this client: then the dead enemy in the target
      if not name then name = deadEnemyName("target") or deadEnemyName("mouseover") end
      local _, kind = IsInInstance()
      if P.RecordHK then core.SafeCall("pvpStat", P.RecordHK, kind) end
      core.SafeCall("pvpKill", P.OnKill, name, kind)
    end
  end
  lastHK = hk
end

---------------------------------------------------------------------------
-- Units we see: remember the last enemy of the fight, remind of debts
---------------------------------------------------------------------------
local function seeUnit(unit)
  if not unit or not isEnemyPlayer(unit) then return end
  local name = unitName(unit)
  if not name then return end
  if (UnitAffectingCombat and UnitAffectingCombat("player")) or unit == "target" then
    lastEnemy = { name = name, t = GetTime() }
  end
  for _, d in ipairs(P.OpenDebts()) do
    if key(d.name) == key(name) and GetTime() - (reminded[d.id] or -999) > 300 then
      reminded[d.id] = GetTime()
      P.Notice(L.PVP_DEBTOR_SEEN:format(T.Word("DEBT"), d.name))
      P.PlaySignal()
    end
  end
end

-- Who is hitting us: enemy players among the nameplates that target the player
local function scanAttackers()
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  local ok, plates = pcall(C_NamePlate.GetNamePlates)
  if not ok or type(plates) ~= "table" then return end
  for _, plate in ipairs(plates) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit and isEnemyPlayer(unit) then
      local okT, isMe = pcall(UnitIsUnit, unit .. "target", "player")
      if okT and isMe == true then
        local name = unitName(unit)
        if name then lastEnemy = { name = name, t = GetTime() } end
      end
    end
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg1)
  if event == "PLAYER_LOGIN" then
    for _, e in ipairs({ "PLAYER_PVP_KILLS_CHANGED", "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_DEAD",
      "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_REGEN_ENABLED" }) do
      pcall(self.RegisterEvent, self, e)
    end
    -- all units: player (who hits us), target and nameplates (a debtor dying near us)
    pcall(self.RegisterEvent, self, "UNIT_HEALTH")
    lastHK = sessionHK()
  elseif event == "PLAYER_PVP_KILLS_CHANGED" then
    core.Schedule("gemPvpHK", 0.3, checkKills)
  elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
    -- diagnostics for /gem pvpcheck: what the client really delivers
    if core.db then
      core.db.pvpDiag = core.db.pvpDiag or {}
      core.db.pvpDiag.honorLine = secret(arg1) and "<secret>" or tostring(arg1)
      core.db.pvpDiag.honorLineAt = date("%Y-%m-%d %H:%M:%S")
    end
    local name = victimFromHonorLine(arg1)
    if name then honorLines[#honorLines + 1] = { name = name, t = GetTime() } end
    core.Schedule("gemPvpHK", 0.3, checkKills)
  elseif event == "PLAYER_REGEN_ENABLED" then
    P.lastCombat = GetTime()
  elseif event == "PLAYER_DEAD" then
    core.SafeCall("pvpDeath", P.OnDeath)
  elseif event == "PLAYER_TARGET_CHANGED" then
    core.SafeCall("pvpSee", seeUnit, "target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    core.SafeCall("pvpSee", seeUnit, "mouseover")
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    core.SafeCall("pvpSee", seeUnit, arg1)
  elseif event == "UNIT_HEALTH" and (arg1 == "target" or (type(arg1) == "string" and arg1:find("^nameplate"))) then
    -- a debtor dies in our target or near us (nameplate) while we fight: revenge taken
    local fighting = (UnitAffectingCombat and UnitAffectingCombat("player")) or (GetTime() - (P.lastCombat or 0) < 10)
    if fighting and #P.OpenDebts() > 0 then
      local name = deadEnemyName(arg1)
      if name then core.SafeCall("pvpDebtNear", P.RedeemDebt, name, arg1 == "target" and "target" or "near") end
    end
  elseif event == "UNIT_HEALTH" and arg1 == "player" then
    -- we take damage: note which enemy player is on us
    core.Schedule("gemPvpScan", 0.2, scanAttackers)
  end
end)

-- /gem pvpcheck: what this client lets the module read
core.SlashExt.pvpcheck = function()
  local ver, build = GetBuildInfo and GetBuildInfo()
  U.Print(("build=%s (%s)  secrets=%s  HK=%s  recap=%s  nameplates=%s"):format(tostring(ver), tostring(build),
    tostring(issecretvalue ~= nil), tostring(sessionHK()), tostring(C_DeathRecap ~= nil), tostring(C_NamePlate ~= nil)))
  U.Print(("honor line: %s"):format(tostring(_G.COMBATLOG_HONORGAIN)))
  local d = core.db and core.db.pvpDiag
  U.Print(("last honor message: %s (%s)"):format(tostring(d and d.honorLine), tostring(d and d.honorLineAt)))
end

---------------------------------------------------------------------------
-- Revenge of a guild member: message for everyone (chat / banner / off).
-- The debt entry reaches every client through the ledger anyway; several
-- revenges within a few seconds (warband) are shown as one line.
---------------------------------------------------------------------------
local revenges = {}

function P.RevengeText(e)
  local who, victim = G.Display(e.who), e.note or L.PVP_UNKNOWN
  if e.flag == "cold" and tonumber(e.after) then
    return L.PVP_REVENGE_COLD:format(who, math.max(1, math.floor(tonumber(e.after) / 60)), victim)
  end
  return L.PVP_REVENGE:format(who, victim, (e.zone and e.zone ~= "") and e.zone or "?", tonumber(e.amt) or 0)
end

local function flushRevenges()
  local list = revenges
  revenges = {}
  if #list == 0 then return end
  local mode = (core.db and core.db.pvpRevenge) or "chat"
  local text
  if #list == 1 then
    text = P.RevengeText(list[1])
  else
    local names = {}
    for _, e in ipairs(list) do names[#names + 1] = G.Display(e.who) end
    text = L.PVP_REVENGE_MANY:format(#list, T.Word("DEBTS"), table.concat(names, ", "))
  end
  U.Print(U.Color(T.Hex(T.Current().title), "[" .. T.Word("GUILD") .. "] ") .. text)
  if mode == "banner" then
    if RaidNotice_AddMessage and RaidWarningFrame then
      pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = 1, g = 0.75, b = 0.2 })
    end
    P.PlaySignal()
  end
end

core.On("POINTS_ADDED", function(e)
  if e.why ~= "debt" or (tonumber(e.amt) or 0) <= 0 then return end
  if core.demo or e.who == G.MyKey() then return end          -- own revenge: shown at once
  if U.Now() - (tonumber(e.ts) or 0) > 300 then return end    -- old entries from the login sync
  if ((core.db and core.db.pvpRevenge) or "chat") == "off" then return end
  revenges[#revenges + 1] = e
  core.Schedule("gemPvpRevenge", 3, flushRevenges)
end)

-- /gem revenge: shows every blood-debt message once with sample names (nothing is saved or sent)
core.SlashExt.revenge = function()
  local r = P.Rules()
  local word = T.Word("DEBT")
  U.Print(L.PVP_DEBT_NEW:format(word, "Daizon Morathir", r.debtDays))
  core.Schedule("gemRevengeDemo1", 2.5, function()
    P.Notice(L.PVP_DEBTOR_SEEN:format(word, "Daizon Morathir")); P.PlaySignal()
  end)
  core.Schedule("gemRevengeDemo2", 5.5, function()
    P.Notice(L.PVP_DEBT_PAID:format(word, "Daizon Morathir", r.debt)); P.PlaySignal()
  end)
  core.Schedule("gemRevengeDemo3", 9, function()
    local e = { who = G.MyKey(), note = "Shanghai Nights", zone = GetZoneText and GetZoneText() or "?", amt = r.debt }
    local text = P.RevengeText(e)
    U.Print(U.Color(T.Hex(T.Current().title), "[" .. T.Word("GUILD") .. "] ") .. text)
    if RaidNotice_AddMessage and RaidWarningFrame then pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = 1, g = 0.75, b = 0.2 }) end
    P.PlaySignal()
  end)
  core.Schedule("gemRevengeDemo4", 12.5, function()
    local e = { who = G.MyKey(), note = "Lazy Shiv", flag = "cold", after = 180, amt = r.debt }
    local text = P.RevengeText(e)
    U.Print(U.Color(T.Hex(T.Current().title), "[" .. T.Word("GUILD") .. "] ") .. text)
    if RaidNotice_AddMessage and RaidWarningFrame then pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = 1, g = 0.75, b = 0.2 }) end
    P.PlaySignal()
  end)
end
