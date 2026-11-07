local ADDON, ns = ...
local U, G, C, P, E = ns.U, ns.Guild, ns.Comm, ns.Profile, ns.Events

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
  or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "0.1.0"

local function initDB()
  GuildEventManagerDB = GuildEventManagerDB or {}
  local db = GuildEventManagerDB
  db.guilds = db.guilds or {}
  db.minimap = db.minimap or {}
  db.chars = db.chars or {}
  db.chars[U.CharKey()] = db.chars[U.CharKey()] or {}
  ns.db = db
  ns.char = db.chars[U.CharKey()]
end

-- Activation follows the marker in the guild info. Until it is there the
-- addon sends nothing and ignores nothing-but-reads.
function ns.CheckActivation()
  local active = G.IsActivated()
  if active and not ns.wasActive then
    ns.wasActive = true
    ns.Fire("ACTIVATED")
    if not ns.helloSent then
      ns.helloSent = true
      ns.Schedule("gemHello", 4 + math.random() * 6, function()
        P.Hello()
        E.LoginNotice()
        ns.Achievements.Check()
      end)
    end
  elseif not active and ns.wasActive then
    ns.wasActive = false
  end
  if ns.UI then ns.UI.Refresh() end
end

local function showErrors()
  local errs = ns.db.errors or {}
  if #errs == 0 then U.Print(ns.L.ERRORS_NONE); return end
  U.Print(ns.L.ERRORS_TITLE .. " (" .. #errs .. ")")
  for i = math.min(#errs, 5), 1, -1 do
    local e = errs[i]
    print(("  %s  [%s]  %s"):format(e.t or "?", e.where or "?", e.msg or "?"))
  end
  ns.db.unseenErrors = false
end

local function showDebug()
  ns.debug = not ns.debug
  U.Print(ns.debug and ns.L.DEBUG_ON or ns.L.DEBUG_OFF)
  U.Print(("guild=%s marker=%s activated=%s manager=%s leader=%s rank=%s roster=%d"):format(
    tostring(G.Name()), tostring(G.Marker()), tostring(G.IsActivated()), tostring(G.IsManager()),
    tostring(G.IsLeader()), tostring(G.RankOf(G.MyKey())), (function() local n = 0 for _ in pairs(G.roster) do n = n + 1 end return n end)()))
  local raw = {}
  for i = 1, math.min(3, GetNumGuildMembers and GetNumGuildMembers() or 0) do raw[#raw + 1] = tostring((GetGuildRosterInfo(i))) end
  local ver, build = GetBuildInfo and GetBuildInfo()
  U.Print(("client=%s (%s)"):format(tostring(ver), tostring(build)))
  U.Print(("me=%s / %s  key=%s  realm=%s  roster: %s"):format(tostring(UnitName("player")), tostring(select(2, UnitName("player"))),
    tostring(G.MyKey()), tostring(GetRealmName and GetRealmName()), table.concat(raw, ", ")))
  local log = ns.db.commLog or {}
  for i = math.min(#log, 10), 1, -1 do
    local l = log[i]
    if l then print("  " .. tostring(l.t or "") .. " " .. tostring(l.dir or "") .. " " .. tostring(l.kind or "") .. " " .. tostring(l.who or "") .. " " .. tostring(l.size or "")) end
  end
end

ns.SlashExt = ns.SlashExt or {}   -- modules add commands: ns.SlashExt.drum = function(rest) end

SLASH_GUILDEVENTMANAGER1, SLASH_GUILDEVENTMANAGER2 = "/guildeventmanager", "/gem"
SlashCmdList.GUILDEVENTMANAGER = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then ns.SafeCall("open", ns.UI.Toggle)
  elseif cmd == "events" or cmd == "banner" or cmd == "settings" then ns.SafeCall("open", ns.UI.Show, cmd)
  elseif cmd == "ach" or cmd == "achievements" or cmd == "erfolge" then ns.SafeCall("open", ns.UI.Show, "ach")
  elseif cmd == "plaque" or cmd == "plakette" then
    local f = rest:lower()
    ns.SafeCall("plaque", ns.Plaque.Test, f:find("^al") and "alliance" or f:find("^ho") and "horde" or nil)
  elseif cmd == "status" then
    for _, l in ipairs(ns.Minimap.StatusLines()) do U.Print(l[1]) end
    U.Print(ns.Family.Line(ns.L.FAMILY))
  elseif cmd == "minimap" then ns.Minimap.ToggleShown()
  elseif cmd == "debug" then showDebug()
  elseif cmd == "sync" then ns.helloSent = false; ns.wasActive = false; ns.CheckActivation()
  elseif cmd == "errors" then showErrors()
  elseif cmd == "clearerrors" then ns.db.errors = {}; ns.db.unseenErrors = false; U.Print(ns.L.ERRORS_CLEARED)
  elseif ns.SlashExt[cmd] then ns.SafeCall("slash:" .. cmd, ns.SlashExt[cmd], rest)
  else U.Print(ns.L.HELP .. (ns.HelpExt or "")) end
end

local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= ADDON then return end
  initDB()
  ns.ApplyLocale(ns.db.language)
end

function handlers.PLAYER_LOGIN(frame)
  C.Init()
  for _, ev in ipairs({ "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT" }) do
    frame:RegisterEvent(ev)
  end
  G.RequestRoster()
  ns.Schedule("gemEventTick", 30, E.Tick)
  if ns.db.unseenErrors then U.Print(ns.L.ERRORS_PENDING) end
end

function handlers.PLAYER_ENTERING_WORLD()
  -- created late on purpose (as in the other Manager addons): minimap skins
  -- rescan shortly after login and would hide a button that already exists
  if not ns.minimapPlanned then
    ns.minimapPlanned = true
    ns.Schedule("gemMinimap", 3, function() ns.Minimap.Create() end)
  end
  ns.Schedule("gemRoster", 2, G.RequestRoster)
end

function handlers.GUILD_ROSTER_UPDATE()
  ns.Schedule("gemRosterRead", 0.5, function()
    G.ReadRoster()
    ns.CheckActivation()
  end)
end

function handlers.PLAYER_GUILD_UPDATE()
  ns.helloSent = false
  G.markerRead = nil
  G.RequestRoster()
end

function handlers.CHAT_MSG_ADDON(prefix, text, dist, sender)
  C.OnMessage(prefix, text, dist, sender)
end

function handlers.PLAYER_LOGOUT() ns.leaving = true end

-- Blocked / forbidden calls: keep addon and function in the error log
local function blocked(kind, addon, fn)
  if addon == ADDON or tostring(addon):find("^GuildEventManager") then
    ns.LogError(kind, tostring(addon) .. " -> " .. tostring(fn))
  end
end
function handlers.ADDON_ACTION_BLOCKED(addon, fn) blocked("ADDON_ACTION_BLOCKED", addon, fn) end
function handlers.ADDON_ACTION_FORBIDDEN(addon, fn) blocked("ADDON_ACTION_FORBIDDEN", addon, fn) end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_ACTION_BLOCKED")
f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
f:SetScript("OnEvent", function(self, event, ...)
  local h = handlers[event]
  if not h then return end
  if event == "PLAYER_LOGIN" then ns.SafeCall(event, h, self) else ns.SafeCall(event, h, ...) end
end)
