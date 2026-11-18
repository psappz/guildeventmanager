local ADDON, P = ...
-- Target alarm (like RareScanner): an enemy player with a bounty, a blood
-- debt, an oath naming him, or on the own watch list comes into sight
-- (nameplate, target, mouseover, target of a group member). A small window
-- shows why, with a protected button to target and mark him, and a button
-- to call the guild. Sightings of other members arrive as notices with a
-- waypoint. No combat log needed.
local core = P.core
if not core then return end
local U, G, T, W, C = core.U, core.Guild, core.Theme, core.W, core.Comm
local L = P.L

local DEFAULTS = { bounty = true, debt = true, oath = true, watch = true, sound = true, city = false, bg = false, throttle = 60 }
function P.AlarmSettings()
  if not core.db then return DEFAULTS end
  core.db.pvpAlarm = core.db.pvpAlarm or {}
  local a = core.db.pvpAlarm
  for k, v in pairs(DEFAULTS) do if a[k] == nil then a[k] = v end end
  return a
end

---------------------------------------------------------------------------
-- Watch list (per character)
---------------------------------------------------------------------------
function P.WatchList()
  if not core.db then return {} end
  core.db.pvpWatch = core.db.pvpWatch or {}
  return core.db.pvpWatch
end

function P.ToggleWatch(name)
  name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if name == "" then
    local names = {}
    for _, n in pairs(P.WatchList()) do names[#names + 1] = n end
    table.sort(names)
    U.Print(#names > 0 and L.PVP_WATCH_LIST:format(table.concat(names, ", ")) or L.PVP_WATCH_EMPTY)
    return
  end
  local k = P.NameKey(name)
  local list = P.WatchList()
  if list[k] then list[k] = nil; U.Print(L.PVP_WATCH_OFF:format(name))
  else list[k] = name; U.Print(L.PVP_WATCH_ON:format(name)) end
end
core.SlashExt.watch = function(rest) P.ToggleWatch(rest) end

---------------------------------------------------------------------------
-- Why is someone wanted? { { kind, text } }
---------------------------------------------------------------------------
function P.WantedReasons(name)
  local a = P.AlarmSettings()
  local k = P.NameKey(name)
  local out = {}
  if a.bounty then
    local sum, n = P.BountyOn(name)
    if n > 0 then out[#out + 1] = { kind = "bounty", text = L.PVP_AL_BOUNTY:format(sum, n) } end
  end
  if a.debt then
    for _, d in ipairs(P.OpenDebts()) do
      if P.NameKey(d.name) == k then out[#out + 1] = { kind = "debt", text = L.PVP_AL_DEBT:format(T.Word("DEBT")) }; break end
    end
  end
  if a.oath then
    for _, o in ipairs(P.OpenOaths()) do
      local text = (o.text or ""):lower()
      local plain = name:lower():gsub("%-.*$", "")
      if #plain >= 3 and text:find(plain, 1, true) then
        out[#out + 1] = { kind = "oath", text = L.PVP_AL_OATH:format(G.Display(o.by), o.text) }
      end
    end
  end
  if a.watch and P.WatchList()[k] then out[#out + 1] = { kind = "watch", text = L.PVP_AL_WATCH } end
  return out
end

local function quietHere()
  local a = P.AlarmSettings()
  if not a.bg and IsInInstance then
    local ok, inst, kind = pcall(IsInInstance)
    if ok and inst and (kind == "pvp" or kind == "arena") then return true end
  end
  if not a.city and IsResting then
    local ok, rest = pcall(IsResting)
    if ok and rest then return true end
  end
  return false
end

local lastAlarm = {}
local SOURCE = { target = "PVP_AL_SRC_TARGET", mouseover = "PVP_AL_SRC_MOUSE" }
function P.CheckWanted(unit, name)
  if not name or quietHere() then return end
  local reasons = P.WantedReasons(name)
  if #reasons == 0 then return end
  local k = P.NameKey(name)
  local throttle = tonumber(P.AlarmSettings().throttle) or 60
  if GetTime() - (lastAlarm[k] or -9999) < throttle then return end
  lastAlarm[k] = GetTime()
  local info = { name = name, reasons = reasons }
  if unit then
    local okL, lvl = pcall(UnitLevel, unit)
    local okC, cname, class = pcall(UnitClass, unit)
    info.level = okL and tonumber(lvl) or nil
    info.className = okC and type(cname) == "string" and cname or nil
    info.class = okC and type(class) == "string" and class or nil
    local src = SOURCE[unit] or (unit:find("^nameplate") and "PVP_AL_SRC_PLATE") or "PVP_AL_SRC_GROUP"
    info.source = L[src]
  end
  info.zone = GetZoneText and GetZoneText() or ""
  P.ShowAlarm(info)
end

---------------------------------------------------------------------------
-- Window
-- The window itself is a plain frame, so it can appear and close at any time,
-- also in combat. The protected target button is NOT part of it: it sits on
-- top of a placeholder, parented to UIParent, and is placed, shown and hidden
-- only out of combat (the game blocks that in combat). In combat the
-- placeholder says how to target by hand; after the fight the button follows.
---------------------------------------------------------------------------
local win, secure
local pendingSync = false

local function syncTarget()
  if not secure then return end
  if InCombatLockdown and InCombatLockdown() then pendingSync = true; return end
  pendingSync = false
  if win and win:IsShown() and win.info and win.slot:GetLeft() then
    local s = win.slot
    secure:ClearAllPoints()
    -- absolute position (anchoring to the window would make the window protected)
    secure:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s:GetLeft(), s:GetBottom())
    secure:SetSize(s:GetWidth(), s:GetHeight())
    secure:SetFrameLevel(win:GetFrameLevel() + 10)
    secure:SetAttribute("macrotext", "/targetexact " .. win.info.name .. "\n/run if UnitExists('target') then SetRaidTarget('target', 8) end")
    secure:Show()
    win.slot.label:SetText("")
  else
    secure:Hide()
  end
end

local function build()
  local th = T.Current()
  local w = CreateFrame("Frame", "GuildEventManagerAlarm", UIParent, "BackdropTemplate")
  w:SetSize(320, 150)
  w:SetFrameStrata("HIGH")
  W.Paint(w, th.bg, th.title)
  w:EnableMouse(true); w:SetMovable(true); w:RegisterForDrag("LeftButton")
  w:SetClampedToScreen(true)
  w:SetScript("OnDragStart", w.StartMoving)
  w:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if core.db then core.db.pvpAlarmPos = { p, rp, x, y } end
    syncTarget()
  end)
  local pos = core.db and core.db.pvpAlarmPos
  if pos then w:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else w:SetPoint("TOP", UIParent, "TOP", 0, -140) end
  w.icon = w:CreateTexture(nil, "ARTWORK"); w.icon:SetSize(36, 36); w.icon:SetPoint("TOPLEFT", 10, -10)
  w.icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")
  w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  w.title = W.Text(w, 14, "title"); w.title:SetPoint("TOPLEFT", w.icon, "TOPRIGHT", 8, 0); w.title:SetPoint("RIGHT", -28, 0)
  w.title:SetWordWrap(false)
  w.sub = W.Text(w, 10, "muted"); w.sub:SetPoint("TOPLEFT", w.title, "BOTTOMLEFT", 0, -3); w.sub:SetPoint("RIGHT", -10, 0)
  w.sub:SetWordWrap(false)
  w.close = W.Close(w, function() w:Hide() end)
  w.close:SetPoint("TOPRIGHT", -6, -6)
  w.reasons = W.Text(w, 11, "text"); w.reasons:SetPoint("TOPLEFT", 10, -54); w.reasons:SetPoint("RIGHT", -10, 0)
  w.reasons:SetJustifyH("LEFT"); w.reasons:SetSpacing(2)
  -- placeholder in the window; the protected button lies on top of it
  local slot = CreateFrame("Frame", nil, w, "BackdropTemplate")
  slot:SetSize(180, 24)
  slot:SetPoint("BOTTOMLEFT", 10, 10)
  W.Paint(slot, th.panel2, th.line)
  slot.label = W.Text(slot, 10, "muted"); slot.label:SetPoint("CENTER")
  w.slot = slot
  -- protected button: targets the enemy and puts a skull on him (out of combat only)
  local sb = CreateFrame("Button", "GuildEventManagerAlarmTarget", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
  sb:SetSize(180, 24)
  sb:SetFrameStrata("HIGH")
  W.Paint(sb, th.accent, th.title)
  sb.label = W.Text(sb, 11, "text"); sb.label:SetPoint("CENTER")
  sb.label:SetText(L.PVP_AL_TARGET)
  sb:RegisterForClicks("AnyUp", "AnyDown")
  sb:SetAttribute("type", "macro")
  sb:Hide()
  secure = sb
  w.target = sb
  w:HookScript("OnShow", syncTarget)
  w:HookScript("OnHide", syncTarget)
  w.call = W.Button(w, L.PVP_AL_CALL, false, 24)
  w.call:SetPoint("LEFT", slot, "RIGHT", 6, 0); w.call:SetPoint("RIGHT", -10, 0)
  w.call:SetScript("OnClick", function() if w.info then P.CallGuild(w.info) end end)
  w.hint = W.Text(w, 9, "muted"); w.hint:SetPoint("BOTTOMLEFT", slot, "TOPLEFT", 0, 4); w.hint:SetPoint("RIGHT", -10, 0)
  w.hint:SetWordWrap(false)
  w:Hide()
  return w
end

function P.ShowAlarm(info)
  win = win or build()
  win.info = info
  local th = T.Current()
  local col = info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class]
  local nm = col and U.Color(string.format("ff%02x%02x%02x", col.r * 255, col.g * 255, col.b * 255), info.name) or info.name
  win.title:SetText(L.PVP_AL_TITLE:format(nm))
  local bits = {}
  if info.level and info.level > 0 then bits[#bits + 1] = L.PVP_AL_LEVEL:format(info.level) end
  if info.className then bits[#bits + 1] = info.className end
  if info.source then bits[#bits + 1] = info.source end
  if info.zone ~= "" then bits[#bits + 1] = info.zone end
  win.sub:SetText(table.concat(bits, " · "))
  local lines = {}
  for _, r in ipairs(info.reasons) do lines[#lines + 1] = "• " .. r.text end
  win.reasons:SetText(table.concat(lines, "\n"))
  local hasBounty = false
  for _, r in ipairs(info.reasons) do if r.kind == "bounty" then hasBounty = true end end
  win:SetHeight(110 + #lines * 14)
  if InCombatLockdown and InCombatLockdown() then
    win.slot.label:SetText(L.PVP_AL_TARGET_COMBAT)
    win.hint:SetText(L.PVP_AL_HINT_COMBAT)
  else
    win.hint:SetText(hasBounty and L.PVP_AL_HINT_BOUNTY or "")
  end
  win:Show()
  syncTarget()
  if P.AlarmSettings().sound then P.PlaySignal() end
  if FlashClientIcon then pcall(FlashClientIcon) end
  core.Schedule("gemPvpAlarmHide", 30, function() if win then win:Hide() end end)
end

---------------------------------------------------------------------------
-- Calling the guild: sightings with position
---------------------------------------------------------------------------
function P.CallGuild(info)
  if not C.CanSend() then U.Print(core.L.NOT_ACTIVE); return end
  local map, x, y = P.Position()
  local kinds = {}
  for _, r in ipairs(info.reasons) do kinds[#kinds + 1] = r.kind end
  C.Send("SIGHT", { n = info.name, z = info.zone, map = map, x = x and math.floor(x * 1000) / 1000, y = y and math.floor(y * 1000) / 1000, k = table.concat(kinds, ","), t = U.Now() })
  U.Print(L.PVP_AL_CALLED:format(info.name))
end

C.On("SIGHT", function(data, from)
  if type(data) ~= "table" or type(data.n) ~= "string" or from == G.MyKey() then return end
  local name = data.n:sub(1, 40)
  local where = tostring(data.z or ""):sub(1, 40)
  local pos = (tonumber(data.x) and tonumber(data.y)) and string.format(" %d,%d", data.x * 100, data.y * 100) or ""
  local text = L.PVP_AL_SEEN:format(G.Display(from), name, where .. pos)
  P.Notice(text)
  local d = tonumber(data.map) and { map = tonumber(data.map), x = tonumber(data.x), y = tonumber(data.y) }
  if core.Notices then
    core.Notices.Add({ key = "sight:" .. P.NameKey(name), group = L.TAB_PVP, text = text,
      open = d and function() if P.SetWaypoint(d) then U.Print(L.PVP_AL_WAYPOINT) end end or nil, view = "pvp" })
  end
end)

---------------------------------------------------------------------------
-- Targets of group members (the nameplates, target and mouseover come from Detect.lua)
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(self, event, unit)
  if event == "PLAYER_LOGIN" then pcall(self.RegisterEvent, self, "UNIT_TARGET"); return end
  -- after the fight: place or remove the target button as the window needs it
  if event == "PLAYER_REGEN_ENABLED" then
    if pendingSync then core.SafeCall("pvpAlarmSync", syncTarget) end
    return
  end
  if event == "UNIT_TARGET" and type(unit) == "string" and (unit:find("^party%d") or unit:find("^raid%d")) then
    local t = unit .. "target"
    core.SafeCall("pvpAlarmGroup", function()
      if P.IsEnemyPlayer(t) then
        local name = P.UnitNameOf(t)
        if name then P.CheckWanted(t, name) end
      end
    end)
  end
end)

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------
local OPTS = { "bounty", "debt", "oath", "watch", "sound", "city", "bg" }
core.UI.AddSettingsPage("pvpalarm", {
  label = function() return L.PVP_AL_SETTINGS end,
  build = function(p)
    p.head = core.UI.Section(p, L.PVP_AL_SETTINGS); p.head:SetPoint("TOPLEFT", 0, 0)
    p.checks = {}
    for i, k in ipairs(OPTS) do
      local c = W.Check(p, L["PVP_AL_OPT_" .. k], function(_, on) P.AlarmSettings()[k] = on end)
      c:SetPoint("TOPLEFT", 0, -30 - (i - 1) * 24)
      p.checks[k] = c
    end
    p.thrLabel = W.Text(p, 11, "text"); p.thrLabel:SetPoint("TOPLEFT", 0, -30 - #OPTS * 24 - 6); p.thrLabel:SetText(L.PVP_AL_OPT_throttle)
    p.thr = W.Edit(p, 60, 22); p.thr:SetPoint("LEFT", p.thrLabel, "RIGHT", 10, 0); p.thr:SetNumeric(true)
    p.thr:SetScript("OnTextChanged", function(self, user) if user then P.AlarmSettings().throttle = math.max(10, tonumber(self:GetText()) or 60) end end)
    p.test = W.Button(p, L.PVP_AL_TEST, false, 22); p.test:SetPoint("TOPLEFT", p.thrLabel, "BOTTOMLEFT", 0, -16)
    p.test:SetScript("OnClick", function()
      P.ShowAlarm({ name = "Grimtusk", level = 60, className = "Warrior", class = "WARRIOR", zone = GetZoneText and GetZoneText() or "",
        source = L.PVP_AL_SRC_PLATE, reasons = { { kind = "bounty", text = L.PVP_AL_BOUNTY:format(50, 2) }, { kind = "watch", text = L.PVP_AL_WATCH } } })
    end)
    p.watchHead = core.UI.Section(p, L.PVP_AL_WATCHLIST); p.watchHead:SetPoint("TOPLEFT", p.test, "BOTTOMLEFT", 0, -20)
    p.watchText = W.Text(p, 11, "text"); p.watchText:SetPoint("TOPLEFT", p.watchHead, "BOTTOMLEFT", 0, -8); p.watchText:SetPoint("RIGHT", 0, 0)
    p.watchText:SetSpacing(2)
  end,
  refresh = function(p)
    local a = P.AlarmSettings()
    for k, c in pairs(p.checks) do c:SetChecked(a[k] and true or false) end
    if not p.thr:HasFocus() then p.thr:SetText(tostring(a.throttle)) end
    local names = {}
    for _, n in pairs(P.WatchList()) do names[#names + 1] = n end
    table.sort(names)
    p.watchText:SetText((#names > 0 and table.concat(names, ", ") or L.PVP_WATCH_EMPTY) .. "\n" .. U.Color("ff8a8078", L.PVP_AL_WATCH_HINT))
  end,
})
