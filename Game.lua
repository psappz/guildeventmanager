local ADDON, ns = ...
-- Game watcher (0.9, API 7 §11): the core listens once to what happens in the
-- game and tells the modules that asked for it. Every value WoW Forever may
-- hide ("secret values") is checked first: a hidden value is left out (nil),
-- it never raises an error. The core adds zone, map and time, drops
-- duplicates and calls every listener protected.
--
--   API.OnGame(kind, fn) -> handle;  API.OffGame(handle)
--   kinds and what fn gets (x.at = server time):
--     fishloot  { item, qty, name, zone, sub, map, at }     one per item of a fishing loot
--     loot      { item, qty, name, fishing, pushed, zone, map, at } one per item the player receives
--               (from the own loot chat line "You receive loot: …" – the probe of 22.11.
--               showed that the loot window of fishing is not reliable on Forever;
--               pushed = "You receive item: …", e.g. quest rewards)
--     itemcount { item, count, prev, at }                   for items watched with API.WatchItem(id)
--     questdone { id, xp, money, at }
--     npcsay    { npc, text, chat = "yell"|"say"|"emote"|"boss", zone, map, at }
--     system    { text, at }
--     pvpkill   { victim, zone, map, at }                   honorable kill (victim nil if unreadable)
--     zone      { zone, sub, map, at }
--     spellcast { spell, target, zone, map, at }            own successful cast (0.9); target = the name
--               the cast was aimed at (nil if none or unreadable), e.g. a snowball at a guild member
--   API.ZoneIs(map or name), API.MapID(), API.ItemCount(id)
-- Events are registered only while somebody listens to the kind.
local U = ns.U
local GW = {}
ns.Game = GW

local f = CreateFrame("Frame")
local listeners = {}     -- kind -> { handle = fn }
local nextHandle = 0
local recent = {}        -- dedupe key -> time
local watched = {}       -- item id -> last count
local casts = {}         -- cast id -> { target, spell, t } (spellcast, 0.9)

local KINDS = {
  fishloot = { "CHAT_MSG_LOOT", "LOOT_OPENED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" },
  loot = { "CHAT_MSG_LOOT", "LOOT_OPENED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" },
  itemcount = { "BAG_UPDATE_DELAYED" },
  questdone = { "QUEST_TURNED_IN" },
  npcsay = { "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_RAID_BOSS_EMOTE" },
  system = { "CHAT_MSG_SYSTEM" },
  pvpkill = { "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_PVP_KILLS_CHANGED" },   -- the combat log is closed on Forever
  zone = { "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
  spellcast = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" },
}
GW.KINDS = KINDS

---------------------------------------------------------------------------
-- Safe values
---------------------------------------------------------------------------
local isSecret = U.IsSecret
-- a readable value or nil
local function val(v)
  if v == nil or isSecret(v) then return nil end
  return v
end
-- a readable string or nil
local function str(v)
  v = val(v)
  if v == nil then return nil end
  local ok, s = pcall(tostring, v)
  if not ok or isSecret(s) then return nil end
  return s
end
local function num(v) v = val(v); return v and tonumber(v) or nil end
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  for i = 2, #r do if isSecret(r[i]) then r[i] = nil end end
  return unpack(r, 2)
end
GW.Str, GW.Num, GW.Call = str, num, call

local lastHK, honorQ = nil, {}       -- honorable kills (see checkKills)
local function sessionHK() return num((call(GetPVPSessionStats))) end

local function now()
  local t = call(GetServerTime)
  return t or time()
end

function GW.MapID()
  local m = call(function() return C_Map.GetBestMapForUnit("player") end)
  return num(m)
end

local function where()
  return str(call(GetZoneText)), str(call(GetSubZoneText)), GW.MapID()
end

-- map id (number) or zone name (any language the client shows)
function GW.ZoneIs(x)
  if type(x) == "number" then return GW.MapID() == x end
  if type(x) ~= "string" then return false end
  local z, s = where()
  x = x:lower()
  return (z and z:lower() == x) or (s and s:lower() == x) or false
end

function GW.ItemCount(id)
  return num(call(GetItemCount, id)) or 0
end

local function itemId(link)
  local s = str(link)
  return s and tonumber(s:match("item:(%d+)")) or nil
end

-- same thing twice within a few seconds (loot window opened twice, a yell
-- heard from two NPCs …) counts once
local function dupe(key, secs)
  local t = GetTime and GetTime() or time()
  for k, at in pairs(recent) do if t - at > 30 then recent[k] = nil end end
  if recent[key] and t - recent[key] < (secs or 3) then return true end
  recent[key] = t
  return false
end

---------------------------------------------------------------------------
-- Dispatch
---------------------------------------------------------------------------
local function fire(kind, x)
  local l = listeners[kind]
  if not l then return end
  x.at = x.at or now()
  for h, fn in pairs(l) do
    ns.SafeCall("game:" .. kind .. ":" .. h.mod, fn, x)
  end
end
GW.Fire = fire

local function wantedEvents()
  local set = {}
  for kind, l in pairs(listeners) do
    if next(l) then for _, ev in ipairs(KINDS[kind]) do set[ev] = true end end
  end
  if next(watched) then set.BAG_UPDATE_DELAYED = true end
  return set
end

local registered = {}
local function sync()
  local want = wantedEvents()
  for ev in pairs(want) do
    if not registered[ev] then registered[ev] = pcall(f.RegisterEvent, f, ev) and true or nil end
  end
  for ev in pairs(registered) do
    if not want[ev] then pcall(f.UnregisterEvent, f, ev); registered[ev] = nil end
  end
end

function GW.On(kind, fn, mod)
  if not KINDS[kind] then error("GuildEventManagerAPI.OnGame: unknown kind " .. tostring(kind), 3) end
  if type(fn) ~= "function" then error("GuildEventManagerAPI.OnGame: fn must be a function", 3) end
  nextHandle = nextHandle + 1
  local h = { id = nextHandle, kind = kind, mod = mod or "?" }
  listeners[kind] = listeners[kind] or {}
  listeners[kind][h] = fn
  if kind == "pvpkill" and lastHK == nil then lastHK = sessionHK() end
  sync()
  return h
end

function GW.Off(h)
  if type(h) == "table" and h.kind and listeners[h.kind] then listeners[h.kind][h] = nil; sync() end
end

function GW.WatchItem(id, on)
  id = tonumber(id)
  if not id then return end
  if on == false then watched[id] = nil else watched[id] = GW.ItemCount(id) end
  sync()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local CHAT = { CHAT_MSG_MONSTER_YELL = "yell", CHAT_MSG_MONSTER_SAY = "say", CHAT_MSG_MONSTER_EMOTE = "emote", CHAT_MSG_RAID_BOSS_EMOTE = "boss" }

-- "%s dies, honorable kill Rank: %s (%d Honor Points)" -> pattern
local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
  p = p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)"):gsub("%%%d?%$?%.?%d*f", "([%%d%%.,]+)")
  -- the closing full stop is not always there (loot lines on Forever, probe 22.11.)
  if p:sub(-2) == "%." then p = p:sub(1, -3) .. "%.?" end
  return "^" .. p .. "$"
end
local honorPats
local function honorVictim(text)
  if not honorPats then
    honorPats = {}
    for _, g in ipairs({ "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORGAIN_EXHAUSTION1" }) do
      local p = toPattern(_G[g])
      if p then honorPats[#honorPats + 1] = p end
    end
  end
  for _, p in ipairs(honorPats) do
    local v = text:match(p)
    if v then return v end
  end
end
GW.HonorVictim = honorVictim

-- Honorable kills: the session counter says that, the honor chat line says
-- whom. Both may be hidden; a kill is reported once either way.
local function checkKills()
  local hk = sessionHK()
  local z, _, m = where()
  local t = GetTime and GetTime() or 0
  if hk and lastHK and hk < lastHK then lastHK = 0 end
  local n
  if hk and lastHK then n = hk - lastHK else n = #honorQ end   -- counter hidden: one per honor line
  if hk then lastHK = hk end
  for _ = 1, math.max(0, n) do
    local line = table.remove(honorQ, 1)
    local v = line and (t - line.t < 10) and line.name or nil
    fire("pvpkill", { victim = v, zone = z, map = m })
  end
  -- old honor lines without a kill: drop
  for i = #honorQ, 1, -1 do if t - honorQ[i].t > 10 then table.remove(honorQ, i) end end
end
GW.CheckKills = checkKills

-- Is the player fishing? The loot window says so (if it opens), the own
-- channel of Fishing too; loot shortly after counts as fishing loot.
local fishingUntil, lootFishing = 0, 0
local FISHING = { [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true, [51294] = true, [131474] = true }
local fishingName
local function isFishingSpell(id)
  id = num(id)
  if id and FISHING[id] then return true end
  if not fishingName then fishingName = str(call(GetSpellInfo, 7620)) or "" end
  local n = id and str(call(GetSpellInfo, id))
  return n ~= nil and n ~= "" and n == fishingName
end

local function onLootOpened()
  if call(IsFishingLoot) then lootFishing = (GetTime and GetTime() or 0) + 3 end
end

-- "You receive loot: %s." / "%sx%d." – and the pushed variant
local lootPats
local function lootPatterns()
  if lootPats then return lootPats end
  lootPats = {}
  for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do
    local p = toPattern(_G[g]); if p then lootPats[#lootPats + 1] = { p = p, pushed = false } end
  end
  for _, g in ipairs({ "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF" }) do
    local p = toPattern(_G[g]); if p then lootPats[#lootPats + 1] = { p = p, pushed = true } end
  end
  return lootPats
end
GW.LootPatterns = lootPatterns

local function onLootChat(text)
  text = str(text)
  if not text then return end
  local link, qty, pushed
  for _, x in ipairs(lootPatterns()) do
    local a, b = text:match(x.p)
    if a then link, qty, pushed = a, tonumber(b) or 1, x.pushed; break end
  end
  if not link then return end   -- loot of others, money …
  local id = tonumber(link:match("item:(%d+)"))
  if not id then return end
  local now = GetTime and GetTime() or 0
  local fishing = not pushed and (now < lootFishing or now < fishingUntil)
  local z, s, m = where()
  local name = link:match("%[(.-)%]")
  fire("loot", { item = id, qty = qty, name = name, fishing = fishing, pushed = pushed or nil, zone = z, sub = s, map = m })
  if fishing then fire("fishloot", { item = id, qty = qty, name = name, zone = z, sub = s, map = m }) end
end
GW.OnLootChat = onLootChat

local function onBags()
  for id, prev in pairs(watched) do
    local n = GW.ItemCount(id)
    if n ~= prev then
      watched[id] = n
      fire("itemcount", { item = id, count = n, prev = prev })
    end
  end
end

local function onEvent(_, event, ...)
  local a1, a2 = ...
  if CHAT[event] then
    local text, npc = str(a1), str(a2)
    if not text or dupe("say:" .. (npc or "") .. ":" .. text, 5) then return end
    local z, _, m = where()
    fire("npcsay", { npc = npc, text = text, chat = CHAT[event], zone = z, map = m })
  elseif event == "CHAT_MSG_SYSTEM" then
    local text = str(a1)
    if text then fire("system", { text = text }) end
  elseif event == "LOOT_OPENED" then
    onLootOpened()
  elseif event == "CHAT_MSG_LOOT" then
    onLootChat(a1)
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    if str(a1) == "player" then
      local spell = select(3, ...)
      if isFishingSpell(spell) then
        -- while the line is out, and a few seconds after it ends (the catch)
        fishingUntil = (GetTime and GetTime() or 0) + (event == "UNIT_SPELLCAST_CHANNEL_START" and 35 or 4)
      end
    end
  elseif event == "BAG_UPDATE_DELAYED" then
    onBags()
  elseif event == "QUEST_TURNED_IN" then
    local id = num(a1)
    if id and not dupe("quest:" .. id, 5) then fire("questdone", { id = id, xp = num(a2), money = num((select(3, ...))) }) end
  elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
    local text = str(a1)
    local v = text and honorVictim(text)
    honorQ[#honorQ + 1] = { name = v, t = GetTime and GetTime() or 0 }
    ns.Schedule("gemGameHK", 0.5, function() ns.SafeCall("gameHK", checkKills) end)
  elseif event == "PLAYER_PVP_KILLS_CHANGED" then
    ns.Schedule("gemGameHK", 0.5, function() ns.SafeCall("gameHK", checkKills) end)
  elseif event == "UNIT_SPELLCAST_SENT" then
    -- unit, target name, cast id, spell id: remember the target until the cast succeeds
    if str(a1) == "player" then
      local target, cast, spell = str(a2), str((select(3, ...))), num((select(4, ...)))
      if cast then
        for k, x in pairs(casts) do if (GetTime and GetTime() or 0) - x.t > 30 then casts[k] = nil end end
        casts[cast] = { target = target and target ~= "" and target or nil, spell = spell, t = GetTime and GetTime() or 0 }
      end
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if str(a1) == "player" then
      local cast, spell = str(a2), num((select(3, ...)))
      local sent = cast and casts[cast]
      if cast then casts[cast] = nil end
      if spell and not dupe("cast:" .. (cast or tostring(spell)), 1) then
        local z, _, m = where()
        fire("spellcast", { spell = spell, target = sent and sent.target or nil, zone = z, map = m })
      end
    end
  elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
    local z, s, m = where()
    if not dupe("zone:" .. tostring(m) .. tostring(z), 2) then fire("zone", { zone = z, sub = s, map = m }) end
  end
end
f:SetScript("OnEvent", function(...) ns.SafeCall("gameWatcher", onEvent, ...) end)
GW.Handle = onEvent   -- tests
