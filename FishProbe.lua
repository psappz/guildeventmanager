local ADDON, ns = ...
-- /gem probe fish: a recorder for the Stranglethorn Fishing Extravaganza.
-- It notes what this client tells addons during the tournament (yells of the
-- event NPCs, system messages, fishing loot, quest turn-ins, honor kills,
-- whether enemies fish or wear a fishing pole) into the saved variables, so
-- the fishing plugin can be built on facts. Starts by hand, or by itself on
-- Sundays between 13:30 and 17:30 server time while in Stranglethorn Vale.
-- Stops after four hours. Test tool, not a feature.
local U = ns.U
-- (0.8.x has no U.UnitTrue / U.UnitVal yet: secret-safe unit queries here)
local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function uval(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or isSecret(v) then return nil end
  return v
end
local function utrue(fn, ...) local v = uval(fn, ...); return v and true or false end
U = setmetatable({ UnitTrue = U.UnitTrue or utrue, UnitVal = U.UnitVal or uval }, { __index = U })
local FP = {}
ns.FishProbe = FP

local MAX, TXT = 800, 220
local STV_MAPS = { [1434] = true, [1433] = true, [224] = true, [210] = true, [50] = true }
local TASTY = 19807
local f = CreateFrame("Frame")
local rec            -- the running log (ns.db.fishLog) or nil
local lastCount

local function serverNow()
  local ok, t = pcall(GetServerTime)
  return ok and t or time()
end

-- weekday (1 = Sunday) and hour:minute in server time
local function serverClock()
  if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
    local ok, d = pcall(C_DateAndTime.GetCurrentCalendarTime)
    if ok and d then return d.weekday, d.hour, d.minute end
  end
  local h, m
  if GetGameTime then h, m = GetGameTime() end
  return tonumber(date("%w")) + 1, h or tonumber(date("%H")), m or tonumber(date("%M"))
end

local function mapID()
  local ok, m = pcall(function() return C_Map.GetBestMapForUnit("player") end)
  return ok and m or nil
end

local function inSTV()
  local m = mapID()
  if m and STV_MAPS[m] then return true end
  local z = (GetZoneText and GetZoneText() or ""):lower()
  return z:find("stranglethorn", 1, true) or z:find("schlingendorn", 1, true) or z:find("tuercespina", 1, true)
      or z:find("strangleronce", 1, true) or z:find("rovotorto", 1, true) or z:find("espinhaç", 1, true)
end

local function cut(s) s = tostring(s or ""); return #s > TXT and s:sub(1, TXT) or s end

local function add(kind, a, b, c)
  if not rec then return end
  if #rec.e >= MAX then rec.full = true; return end
  local _, h, m = serverClock()
  rec.e[#rec.e + 1] = { t = serverNow(), st = string.format("%02d:%02d", h or 0, m or 0), k = kind, a = cut(a), b = b and cut(b) or nil, c = c and cut(c) or nil, map = mapID() }
end
FP.Add = add

local function weapon(unit)
  local id = GetInventoryItemID and GetInventoryItemID(unit, 16)
  local link = GetInventoryItemLink and GetInventoryItemLink(unit, 16)
  return tostring(id) .. " " .. tostring(link)
end

local function channel(unit)
  local name, _, _, _, _, _, _, spellID = (UnitChannelInfo or function() end)(unit)
  local cast = (UnitCastingInfo or function() end)(unit)
  return "channel=" .. tostring(name) .. "/" .. tostring(spellID) .. " cast=" .. tostring(cast)
end

-- an enemy player: does he fish, which weapon do we see (directly / after inspect)
local inspecting
local function lookAt(unit, why)
  if not U.UnitTrue(UnitExists, unit) or not U.UnitTrue(UnitIsPlayer, unit) or not U.UnitTrue(UnitIsEnemy, "player", unit) then return end
  add("enemy:" .. why, UnitName(unit), channel(unit), "weapon " .. weapon(unit) .. " canInspect=" .. tostring(CanInspect and CanInspect(unit)))
  if why == "target" and CanInspect and CanInspect(unit) and NotifyInspect and not inspecting then
    inspecting = UnitGUID(unit)
    pcall(NotifyInspect, unit)
  end
end

local EVENTS = {
  "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_RAID_BOSS_EMOTE",
  "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "LOOT_OPENED", "QUEST_TURNED_IN", "QUEST_COMPLETE",
  "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_PVP_KILLS_CHANGED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
  "UNIT_SPELLCAST_CHANNEL_START", "PLAYER_REGEN_DISABLED", "INSPECT_READY", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED",
}

local function onEvent(_, event, ...)
  if not rec then return end
  local a1, a2 = ...
  if event:find("^CHAT_MSG_MONSTER") or event == "CHAT_MSG_RAID_BOSS_EMOTE" then
    add(event:gsub("CHAT_MSG_", ""):lower(), a2, a1)          -- sender, text
  elseif event == "CHAT_MSG_SYSTEM" or event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
    add(event:gsub("CHAT_MSG_", ""):lower(), a1)
  elseif event == "LOOT_OPENED" then
    local fishing = IsFishingLoot and IsFishingLoot()
    local items = {}
    for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
      local link = GetLootSlotLink and GetLootSlotLink(i)
      local _, name, qty = GetLootSlotInfo(i)
      items[#items + 1] = (link and link:match("item:(%d+)") or "?") .. "x" .. tostring(qty) .. " " .. tostring(name)
    end
    add("loot", "fishing=" .. tostring(fishing), table.concat(items, " | "), GetSubZoneText and GetSubZoneText() or "")
  elseif event == "QUEST_TURNED_IN" then
    add("quest_done", tostring(a1), "xp=" .. tostring(a2) .. " money=" .. tostring(select(3, ...)))
  elseif event == "QUEST_COMPLETE" then
    add("quest_complete", GetTitleText and GetTitleText() or "?", GetQuestID and tostring(GetQuestID()) or "?")
  elseif event == "PLAYER_PVP_KILLS_CHANGED" then
    add("hk_counter", "lifetime HK " .. tostring(GetPVPLifetimeStats and (GetPVPLifetimeStats())), "session " .. tostring(GetPVPSessionStats and (GetPVPSessionStats())))
  elseif event == "PLAYER_TARGET_CHANGED" then
    lookAt("target", "target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    lookAt("mouseover", "mouseover")
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
    if a1 and (a1 == "target" or a1:find("^nameplate")) and U.UnitTrue(UnitIsPlayer, a1) and U.UnitTrue(UnitIsEnemy, "player", a1) then
      local name = GetSpellInfo and GetSpellInfo(select(3, ...)) or tostring(select(3, ...))
      add("enemy_channel", UnitName(a1), tostring(name) .. " (" .. tostring(select(3, ...)) .. ")", a1)
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    add("combat_start", "target=" .. tostring(U.UnitVal(UnitName, "target")), U.UnitTrue(UnitExists, "target") and channel("target") or "", U.UnitTrue(UnitExists, "target") and ("weapon " .. weapon("target")) or "")
  elseif event == "INSPECT_READY" then
    if inspecting and a1 == inspecting then
      local unit = (UnitGUID("target") == inspecting) and "target" or nil
      add("inspect", unit and UnitName(unit) or "?", unit and ("weapon " .. weapon(unit)) or "target gone")
      if ClearInspectPlayer then pcall(ClearInspectPlayer) end
    end
    inspecting = nil
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    add("zone", GetZoneText and GetZoneText() or "?", tostring(mapID()))
  elseif event == "BAG_UPDATE_DELAYED" then
    local n = GetItemCount and GetItemCount(TASTY) or 0
    if n ~= lastCount then add("tastyfish_in_bags", tostring(n)); lastCount = n end
  end
end

local function snapshot()
  local w, h, m = serverClock()
  local prof = {}
  if GetProfessions then
    local _, _, _, fishing = GetProfessions()
    if fishing and GetProfessionInfo then
      local name, _, rank, maxRank, _, _, _, mod = GetProfessionInfo(fishing)
      prof[#prof + 1] = tostring(name) .. " " .. tostring(rank) .. "/" .. tostring(maxRank) .. " +" .. tostring(mod)
    end
  end
  add("snapshot", "server weekday=" .. tostring(w) .. " " .. tostring(h) .. ":" .. tostring(m) .. " local=" .. date("%a %H:%M"),
    "fishing " .. table.concat(prof, ","), "own weapon " .. weapon("player") .. " level " .. tostring(UnitLevel("player")))
  add("snapshot2", "IsFishingLoot=" .. tostring(IsFishingLoot ~= nil) .. " UnitChannelInfo=" .. tostring(UnitChannelInfo ~= nil)
    .. " CanInspect=" .. tostring(CanInspect ~= nil) .. " QuestFlagged(8193)=" .. tostring(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(8193)),
    "zone " .. tostring(GetZoneText and GetZoneText()) .. " map " .. tostring(mapID()), "tastyfish " .. tostring(GetItemCount and GetItemCount(TASTY)))
end

function FP.Start(auto)
  if rec then return end
  ns.db.fishLog = { at = date("%Y-%m-%d %H:%M"), server = serverNow(), auto = auto or nil, e = {} }
  rec = ns.db.fishLog
  for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
  lastCount = nil
  snapshot()
  U.Print("Fishing recorder ON – notes the tournament for the plugin. Stops after 4 h · /gem probe fish off")
end

function FP.Stop(quiet)
  if not rec then return end
  add("stop", "entries " .. #rec.e)
  rec = nil
  f:UnregisterAllEvents()
  if not quiet then U.Print("Fishing recorder OFF – thank you! Saved for the developer (logout or /reload writes it).") end
end

function FP.Show()
  local log = ns.db and ns.db.fishLog
  if not log then U.Print("Fishing recorder: nothing recorded yet."); return end
  local by = {}
  for _, e in ipairs(log.e) do by[e.k] = (by[e.k] or 0) + 1 end
  local parts = {}
  for k, n in pairs(by) do parts[#parts + 1] = k .. " " .. n end
  table.sort(parts)
  U.Print("Fishing recorder (" .. log.at .. (rec and ", running" or "") .. "): " .. table.concat(parts, " · "))
end

f:SetScript("OnEvent", function(...) ns.SafeCall("fishprobe", onEvent, ...) end)

-- auto start: Sunday 13:30–17:30 server time in Stranglethorn Vale; auto stop after 4 h
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, dt)
  acc = acc + dt
  if acc < 30 then return end
  acc = 0
  if not ns.db then return end
  if rec then
    if serverNow() - (rec.server or 0) > 4 * 3600 then FP.Stop() end
    return
  end
  local w, h, m = serverClock()
  local mins = (h or 0) * 60 + (m or 0)
  local last = ns.db.fishLog and ns.db.fishLog.server or 0
  if w == 1 and mins >= 13 * 60 + 30 and mins <= 17 * 60 + 30 and inSTV() and serverNow() - last > 6 * 3600 then
    FP.Start(true)
  end
end)

-- /gem probe [fish [on|off|show]]
local plain = ns.SlashExt.probe
ns.SlashExt.probe = function(rest)
  local a, b = (rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
  if a ~= "fish" then return plain(rest) end
  if b == "off" then FP.Stop() elseif b == "show" then FP.Show()
  elseif b == "on" or b == "" then if rec and b == "" then FP.Show() else FP.Start() end end
end

ns.Export.Add("Fishing recorder", function()
  local log = ns.db and ns.db.fishLog
  if not log then return { "nothing recorded" } end
  local out = { "started " .. log.at .. (log.auto and " (auto)" or "") }
  for _, e in ipairs(log.e) do
    out[#out + 1] = e.st .. " " .. e.k .. ": " .. e.a .. (e.b and (" | " .. e.b) or "") .. (e.c and (" | " .. e.c) or "") .. " [" .. tostring(e.map) .. "]"
  end
  return out
end)
