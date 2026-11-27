local ADDON, P = ...
-- WANTED posters (0.9): the poster widget, the poster that slides in when a
-- bounty is set or collected, the offer after a death, the poster at login,
-- the event sounds and their settings ("Bounty posters", "Sounds").
--
-- Textures: Media\Wanted\poster_<horde|alliance>.tga (512x768 on 512x1024,
-- the portrait hole is transparent) and <race>_<male|female>.tga (256x128).
-- Built by art-src/wanted/build_textures.py.
local core = P.core
if not core then return end
local U, G, T, W, C = core.U, core.Guild, core.Theme, core.W, core.Comm
local L = P.L

local MEDIA = "Interface\\AddOns\\GuildEventManager_PvP\\Media\\Wanted\\"
local PW, PH = 300, 450          -- poster size at scale 1
local S = PW / 1024              -- template pixels -> poster pixels

-- positions in pixels of the 1024 x 1536 templates (art-src/wanted)
local LAYOUT = {
  horde = { hole = { 118, 300, 788, 394 }, guild = 122, name = 752, cols = { 237, 512, 787 }, lab = 828, val = 868,
    band = { 512, 922 }, row1 = 972, row2 = 1032, untilY = 1087, left = 128, reward = 1180,
    von = { 512, 1280 }, by = 1335, font = "Fonts\\MORPHEUS.TTF",
    ink = { 0.29, 0.06, 0.04 }, soft = { 0.48, 0.17, 0.13 }, band2 = { 0.98, 0.89, 0.69 } },
  alliance = { hole = { 118, 300, 788, 394 }, guild = 122, name = 752, cols = { 237, 512, 787 }, lab = 828, val = 868,
    band = { 512, 922 }, row1 = 972, row2 = 1032, untilY = 1087, left = 128, reward = 1180,
    von = { 512, 1280 }, by = 1335, font = "Fonts\\FRIZQT__.TTF",
    ink = { 0.07, 0.16, 0.42 }, soft = { 0.29, 0.35, 0.54 }, band2 = { 0.96, 0.82, 0.48 } },
}

local RACE_FILE = { Human = "human", Dwarf = "dwarf", NightElf = "nightelf", Gnome = "gnome", Orc = "orc",
  Scourge = "undead", Undead = "undead", Tauren = "tauren", Troll = "troll", Skyborne = "skyborne" }

function P.PortraitFile(i)
  local base = i and i.rf and RACE_FILE[i.rf]
  if not base then return MEDIA .. "unknown" end     -- race not known yet: hooded stranger
  return MEDIA .. base .. ((i.sx == 3) and "_female" or "_male")
end

---------------------------------------------------------------------------
-- Settings (per account)
---------------------------------------------------------------------------
local DEFAULTS = {
  newMode = "always",   -- poster for a new bounty: always | noinst | off (then text only)
  doneMode = "always",  -- poster for a collected bounty
  sndNew = "always",    -- sound: always | noinst | off
  sndDone = "always",
  sound = "drums",
  size = "m", dur = 12, chat = false, offer = true,
}
function P.WantedSettings()
  if not core.db then return DEFAULTS end
  core.db.wanted = core.db.wanted or {}
  local s = core.db.wanted
  for k, v in pairs(DEFAULTS) do if s[k] == nil then s[k] = v end end
  -- one sound per event (0.9); both start with the former common sound
  if s.soundNew == nil then s.soundNew = s.sound end
  if s.soundDone == nil then s.soundDone = s.sound end
  return s
end

local function inInstance()
  if not IsInInstance then return false end
  local ok, inst = pcall(IsInInstance)
  return ok and inst and true or false
end

local function allowed(mode)
  if mode == "off" then return false end
  if mode == "noinst" and inInstance() then return false end
  return true
end

---------------------------------------------------------------------------
-- Sounds (the "Sounds" settings page picks them; for now: war drums)
---------------------------------------------------------------------------
P.SOUNDS = {
  { id = "drums", labelKey = "SND_DRUMS", file = 567275 },   -- Sound\Event Sounds\Event_wardrum_ogre.ogg
  { id = "s567399", labelKey = "SND_567399", file = 567399 }, -- sound/interface/alarmclockwarning2.ogg (picked 23.11.)
  { id = "s567283", labelKey = "SND_567283", file = 567283 }, -- sound/event sounds/ogreeventcheerunique.ogg (picked 23.11.)
}
local function soundById(id)
  for _, s in ipairs(P.SOUNDS) do if s.id == id then return s end end
  return P.SOUNDS[1]
end

function P.PlaySound(id)
  local s = soundById(id)
  local ok, will
  if s.file then ok, will = pcall(PlaySoundFile, s.file, "Master") end
  if not (ok and will) and s.kit then ok, will = pcall(PlaySound, s.kit, "Master") end
  if not (ok and will) then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
end

-- kind: "new" | "done"
function P.BountySound(kind)
  local s = P.WantedSettings()
  local mode = kind == "done" and s.sndDone or s.sndNew
  if allowed(mode) then P.PlaySound(kind == "done" and s.soundDone or s.soundNew) end
end

-- the old signal (blood debt paid, alarm ...): drums for everyone now. In WoW
-- Forever game sounds play only by FileDataID or SoundKitID, not by path.
function P.PlaySignal()
  if core.db and core.db.pvpMute then return end
  P.PlaySound(P.WantedSettings().soundNew)
end

---------------------------------------------------------------------------
-- The poster widget
---------------------------------------------------------------------------
local function fmtWhen(t)
  if not t then return "?" end
  local now = U.Now()
  if date("%Y-%m-%d", t) == date("%Y-%m-%d", now) then return L.WNT_TODAY:format(date("%H:%M", t)) end
  if date("%Y-%m-%d", t) == date("%Y-%m-%d", now - 86400) then return L.WNT_YESTERDAY:format(date("%H:%M", t)) end
  return date("%d.%m. %H:%M", t)
end
P.WantedWhen = fmtWhen

-- WoW fonts have no bold face: a shadow in the text's own colour, shifted by
-- a fraction of a pixel, thickens the strokes ("fake bold")
local function setText(fs, font, size, color, text, w)
  fs:SetFont(font, size, "")
  fs:SetTextColor(color[1], color[2], color[3], 1)
  fs:SetShadowColor(color[1], color[2], color[3], 0.9)
  fs:SetShadowOffset(0.7, -0.2)
  fs:SetText(text or "")
  if w then
    -- too long for its place: shrink step by step instead of cutting it off
    local sz = size
    while sz > size * 0.6 and fs:GetStringWidth() > w do
      sz = sz - 0.5
      fs:SetFont(font, sz, "")
    end
  end
end

local function pos(f, fs, x, y, align)
  fs:ClearAllPoints()
  local point = align == "left" and "LEFT" or (align == "right" and "RIGHT" or "CENTER")
  fs:SetPoint(point, f, "TOPLEFT", x * S, -y * S)
  fs:SetJustifyH(align == "left" and "LEFT" or (align == "right" and "RIGHT" or "CENTER"))
end

-- the unit token of a visible enemy with this name (target, mouseover, nameplates)
function P.FindUnitByName(name)
  local k = P.BountyKey(name)
  local function test(u)
    if U.UnitTrue(UnitExists, u) and U.UnitTrue(UnitIsPlayer, u) then
      local n = P.UnitNameOf and P.UnitNameOf(u)
      if n and P.BountyKey(n) == k then return true end
    end
  end
  for _, u in ipairs({ "target", "mouseover", "focus" }) do if test(u) then return u end end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for _, plate in ipairs(plates) do
        local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if u and test(u) then return u end
      end
    end
  end
end

function P.NewPoster(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(PW, PH)
  f.portrait = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.hole = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  f.hole:SetColorTexture(0.08, 0.05, 0.035, 1)
  f.art = f:CreateTexture(nil, "ARTWORK")
  f.art:SetAllPoints()
  f.art:SetTexCoord(0, 1, 0, 0.75)
  f.unknown = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  f.unknown:SetText("?")
  f.unknown:SetTextColor(0.75, 0.68, 0.6, 1)
  local function fs() return f:CreateFontString(nil, "OVERLAY") end
  f.guild, f.name = fs(), fs()
  f.l1, f.l2, f.l3, f.v1, f.v2, f.v3 = fs(), fs(), fs(), fs(), fs(), fs()
  f.band = fs()
  f.whenL, f.when, f.zoneL, f.zone, f.layerL, f.layer, f.untilL, f.untilV = fs(), fs(), fs(), fs(), fs(), fs(), fs(), fs()
  f.rewardL, f.reward, f.von, f.by = fs(), fs(), fs(), fs()
  f.stamp = f:CreateFontString(nil, "OVERLAY", nil, 7)
  f.stamp2 = f:CreateFontString(nil, "OVERLAY", nil, 7)
  -- the live model sits on top of the hole while the enemy is in sight
  f.model = CreateFrame("PlayerModel", nil, f)
  f.model:Hide()
  f.liveTag = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall", 7)
  f.liveTag:SetText(L.WNT_LIVE)
  f.liveTag:SetTextColor(1, 0.3, 0.25, 1)
  f.liveTag:Hide()

  function f:Layout(faction)
    local Lay = LAYOUT[faction] or LAYOUT.horde
    self.lay = Lay
    self.faction = faction
    self.art:SetTexture(MEDIA .. "poster_" .. (faction == "alliance" and "alliance" or "horde"))
    local h = Lay.hole
    for _, t in ipairs({ self.portrait, self.hole }) do
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self, "TOPLEFT", h[1] * S - 1, -h[2] * S + 1)
      t:SetSize(h[3] * S + 2, h[4] * S + 2)
    end
    self.model:ClearAllPoints()
    self.model:SetPoint("TOPLEFT", self, "TOPLEFT", h[1] * S + 2, -h[2] * S - 2)
    self.model:SetSize(h[3] * S - 4, h[4] * S - 4)
    self.unknown:ClearAllPoints()
    self.unknown:SetPoint("CENTER", self, "TOPLEFT", (h[1] + h[3] / 2) * S, -(h[2] + h[4] / 2) * S)
    self.liveTag:ClearAllPoints()
    self.liveTag:SetPoint("TOPLEFT", self, "TOPLEFT", h[1] * S + 6, -h[2] * S - 5)
    local font, ink, soft = Lay.font, Lay.ink, Lay.soft
    setText(self.l1, font, 9.5, soft, L.WNT_RACE); pos(self, self.l1, Lay.cols[1], Lay.lab)
    setText(self.l2, font, 9.5, soft, L.WNT_CLASS); pos(self, self.l2, Lay.cols[2], Lay.lab)
    setText(self.l3, font, 9.5, soft, L.WNT_LEVEL); pos(self, self.l3, Lay.cols[3], Lay.lab)
    setText(self.band, font, 10, Lay.band2, L.WNT_LASTSEEN, 58); pos(self, self.band, Lay.band[1], Lay.band[2])
    setText(self.whenL, font, 9.5, soft, L.WNT_WHEN); pos(self, self.whenL, Lay.left, Lay.row1, "left")
    setText(self.zoneL, font, 9.5, soft, L.WNT_REGION); pos(self, self.zoneL, Lay.left, Lay.row2, "left")
    setText(self.untilL, font, 9.5, soft, L.WNT_UNTIL); pos(self, self.untilL, Lay.left, Lay.untilY, "left")
    setText(self.rewardL, font, 15, Lay.band2, L.WNT_REWARD); pos(self, self.rewardL, Lay.left + 20, Lay.reward, "left")
    setText(self.von, font, 11, soft, L.WNT_FROM); pos(self, self.von, Lay.von[1], Lay.von[2])
    -- values: next to their labels
    pos(self, self.guild, 512, Lay.guild); pos(self, self.name, 512, Lay.name)
    pos(self, self.v1, Lay.cols[1], Lay.val); pos(self, self.v2, Lay.cols[2], Lay.val); pos(self, self.v3, Lay.cols[3], Lay.val)
    pos(self, self.reward, 1024 - Lay.left - 20, Lay.reward, "right")
    pos(self, self.by, 512, Lay.by)
    self.v1:SetWidth(80); self.v2:SetWidth(80); self.v3:SetWidth(60)
    self.name:SetWidth(270); self.by:SetWidth(260); self.guild:SetWidth(270)
    for _, x in ipairs({ self.v1, self.v2, self.v3, self.name, self.by, self.guild }) do x:SetWordWrap(false) end
  end

  local function after(label, value, gap)
    value:ClearAllPoints()
    value:SetPoint("LEFT", label, "RIGHT", gap or 5, 0)
    value:SetJustifyH("LEFT")
    value:SetWordWrap(false)
  end

  -- b: a bounty (P.bounties) or a preview table with the same fields
  function f:SetBounty(b, faction)
    faction = faction or T.Faction()
    if self.faction ~= faction then self:Layout(faction) end
    local Lay, font, ink = self.lay, self.lay.font, self.lay.ink
    self.b = b
    local i = b.i or {}
    setText(self.guild, font, 24, ink, (G.guildName or (GetGuildInfo and GetGuildInfo("player")) or ""):upper(), 250)
    setText(self.name, font, 23, ink, b.target, 260)
    setText(self.v1, font, 14, ink, i.r or "?", 78)
    setText(self.v2, font, 14, ink, i.cl or "?", 78)
    local lv = tonumber(i.lv)
    setText(self.v3, font, 18, ink, (lv and lv > 0) and tostring(lv) or ((lv and lv < 0) and "??" or "?"))
    setText(self.when, font, 13, ink, i.st and fmtWhen(i.st) or "?"); after(self.whenL, self.when)
    local zone = i.z or "?"
    if i.sz and i.sz ~= "" and i.sz ~= i.z then zone = i.sz .. ", " .. zone end
    setText(self.zone, font, 13, ink, zone, 190); after(self.zoneL, self.zone); self.zone:SetWidth(190)
    setText(self.untilV, font, 13, ink, date("%d.%m. %H:%M", P.BountyEnds(b))); after(self.untilL, self.untilV)
    setText(self.reward, font, 26, Lay.band2, tostring(P.BountyTotal(b)) .. " " .. P.GPTag(true))
    local by = G.Display(b.by)
    if b.gb then by = L.WNT_CHEST:format(by) end
    local more = 0
    for k, a in pairs(b.adds or {}) do if k ~= b.by and (a or 0) > 0 then more = more + 1 end end
    if more > 0 then by = by .. " " .. L.WNT_MORE:format(more) end
    setText(self.by, font, 14, ink, by, 250)
    -- portrait
    local file = P.PortraitFile(i)
    if file then self.portrait:SetTexture(file); self.portrait:Show(); self.unknown:Hide()
    else self.portrait:Hide(); self.unknown:Show() end
    -- stamp
    local st = P.BountyState(b)
    local stamp, sub
    if st == "done" then
      stamp = L.WNT_DONE
      local names = {}
      for _, k in ipairs(b.ws or { b.w }) do names[#names + 1] = G.Display(k) end
      sub = L.WNT_DONE_BY:format(table.concat(names, ", "))
      if b.tri then sub = sub .. "  ·  " .. L.WNT_TRIPLE end
    elseif st == "expired" or (st == "off" and b.expired) then stamp = L.WNT_EXPIRED
    elseif st == "off" then stamp = L.WNT_OFF end
    if stamp then
      local red = (st == "done") and { 0.7, 0.1, 0.08 } or { 0.35, 0.33, 0.32 }
      self.stamp:SetFont("Fonts\\FRIZQT__.TTF", 30, "THICKOUTLINE")
      self.stamp:SetTextColor(red[1], red[2], red[3], 0.92)
      self.stamp:SetText(stamp)
      self.stamp:ClearAllPoints(); self.stamp:SetPoint("CENTER", self, "TOPLEFT", PW / 2, -PH * 0.47)
      self.stamp2:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
      self.stamp2:SetTextColor(red[1], red[2], red[3], 0.95)
      self.stamp2:SetText(sub or "")
      self.stamp2:ClearAllPoints(); self.stamp2:SetPoint("TOP", self.stamp, "BOTTOM", 0, -2)
      self.stamp2:SetWidth(PW - 30)
      if self.stamp.SetRotation then pcall(self.stamp.SetRotation, self.stamp, math.rad(12)) end
      self.stamp:Show(); self.stamp2:SetShown(sub ~= nil)
    else
      self.stamp:Hide(); self.stamp2:Hide()
    end
    self:UpdateLive()
  end

  -- the real enemy as a living model while he is in sight
  function f:UpdateLive()
    local b = self.b
    local unit = self.forceUnit and self.forceUnit()
    unit = unit or (b and P.BountyState(b) == "open" and not self.noLive and P.FindUnitByName(b.target))
    if unit then
      local ok = pcall(self.model.SetUnit, self.model, unit)
      if ok then
        -- a bit less zoom and the model a little lower, so the head is in the frame
        -- (tune: /gem wanted live <zoom> <down>)
        local ws = P.WantedSettings()
        if self.model.SetPortraitZoom then pcall(self.model.SetPortraitZoom, self.model, ws.liveZoom or 0.9) end
        if self.model.SetPosition then pcall(self.model.SetPosition, self.model, 0, 0, -(ws.liveDown or 0.05)) end
        self.model:Show(); self.liveTag:Show(); self.portrait:Hide(); self.unknown:Hide()
        self.liveUnit = unit
        return
      end
    end
    if self.liveUnit then
      self.liveUnit = nil
      self.model:Hide(); self.liveTag:Hide()
      if b then
        local file = P.PortraitFile(b.i)
        self.portrait:SetShown(file ~= nil); self.unknown:SetShown(file == nil)
      end
    end
  end
  local acc = 0
  f:SetScript("OnUpdate", function(self, dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    core.SafeCall("wantedLive", self.UpdateLive, self)
  end)

  f:Layout(T.Faction())
  return f
end

---------------------------------------------------------------------------
-- The poster that slides in (top right, movable)
---------------------------------------------------------------------------
local SCALE = { s = 0.75, m = 0.9, l = 1.05 }
local toast, queue, showing = nil, {}, false

local function savedPos()
  local s = P.WantedSettings()
  return s.pos
end

local function buildToast()
  local t = CreateFrame("Button", "GuildEventManagerWanted", UIParent)
  t:SetSize(PW, PH)
  t:SetFrameStrata("HIGH")
  t:SetClampedToScreen(true)
  t:SetMovable(true)
  t:EnableMouse(true)
  t:RegisterForDrag("LeftButton")
  t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  t.poster = P.NewPoster(t)
  t.poster:SetPoint("TOPLEFT")
  t.extra = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  t.extra:SetPoint("TOP", t, "BOTTOM", 0, -4)
  t.extra:SetTextColor(1, 0.85, 0.3, 1)
  t:SetScript("OnDragStart", function(self) self.dragging = true; self:StartMoving() end)
  t:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.dragging = nil
    local p1, _, p2, x, y = self:GetPoint(1)
    P.WantedSettings().pos = { p1, p2, x, y }
  end)
  t:SetScript("OnClick", function(self, btn)
    local b = self.poster.b
    GameTooltip:Hide()
    P.HideWanted()
    if btn == "LeftButton" and b and P.OpenBountyDetail then P.OpenBountyDetail(b.id) end
  end)
  -- tooltip: target, the poster's note, what a click does
  t:SetScript("OnEnter", function(self)
    local b = self.poster.b
    if not b then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(b.target or "", 1, 0.82, 0)
    if b.note then
      GameTooltip:AddLine(L.WNT_TIP_NOTE:format(G.Display(b.by)), 0.75, 0.75, 0.75)
      GameTooltip:AddLine(b.note, 1, 1, 1, true)
    end
    GameTooltip:AddLine(L.WNT_TIP_CLICK, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  t:SetScript("OnLeave", function() GameTooltip:Hide() end)
  t.ag = t:CreateAnimationGroup()
  local a = t.ag:CreateAnimation("Alpha")
  a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.35)
  t:Hide()
  return t
end

function P.ResetWantedPosition()
  P.WantedSettings().pos = nil
  if toast then toast:ClearAllPoints(); toast:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -140) end
end

function P.HideWanted()
  if toast then toast:Hide() end
  showing = false
  core.Schedule("gemWantedNext", 0.5, P.NextWanted)
end

local function canShowNow()
  if InCombatLockdown and InCombatLockdown() then return false end
  if UnitAffectingCombat and UnitAffectingCombat("player") then return false end
  return true
end

function P.NextWanted()
  if showing or #queue == 0 then return end
  if not canShowNow() then return end   -- PLAYER_REGEN_ENABLED tries again
  local item = table.remove(queue, 1)
  if U.Now() - item.at > 600 then return P.NextWanted() end   -- too old: skip
  toast = toast or buildToast()
  local s = P.WantedSettings()
  toast:ClearAllPoints()
  local p = savedPos()
  if p then toast:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else toast:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -140) end
  local scale = (SCALE[s.size] or 0.9) * (item.big and 1.2 or 1)
  toast:SetScale(scale)
  toast.poster:SetBounty(item.b)
  toast.extra:SetText(item.extra or "")
  toast:Show()
  toast.ag:Play()
  showing = true
  if item.sound then P.BountySound(item.kind) end
  local dur = tonumber(s.dur) or 12
  if item.kind == "done" and not item.big then dur = math.min(dur, 6) end
  if item.big then dur = dur + 4 end
  core.Schedule("gemWantedHide", dur, function() if toast and not toast.dragging and toast:IsMouseOver() then
    core.Schedule("gemWantedHide", 3, P.HideWanted) else P.HideWanted() end end)
end

-- kind: "new" | "done"; opts: { big, extra, sound, text }
function P.ShowWanted(b, kind, opts)
  opts = opts or {}
  local s = P.WantedSettings()
  local mode = kind == "done" and s.doneMode or s.newMode
  if not allowed(mode) then
    if opts.text then U.Print(U.Color(U.GOLD, opts.text)) end
    -- the sound has its own setting
    if opts.sound ~= false then P.BountySound(kind) end
    return false
  end
  if s.chat and opts.text then U.Print(U.Color(U.GOLD, opts.text)) end
  -- the same bounty is not queued twice
  for _, q in ipairs(queue) do if q.b == b and q.kind == kind then return true end end
  queue[#queue + 1] = { b = b, kind = kind, big = opts.big, extra = opts.extra, sound = opts.sound ~= false, at = U.Now() }
  P.NextWanted()
  return true
end

---------------------------------------------------------------------------
-- Reacting to bounties
---------------------------------------------------------------------------
local function seenStore()
  local c = core.char
  if not c then return {} end
  c.wantedSeen = c.wantedSeen or {}
  return c.wantedSeen
end
local loginDone = false

core.On("PVP_BOUNTY_NEW", function(b, mine, fresh)
  if not b then return end
  if not mine and not fresh then return end
  if not loginDone and not mine then return end      -- the login poster collects them
  seenStore()[b.id] = true
  local text = L.PVP_BNT_ANNOUNCE:format(G.Display(b.by), P.BountyTotal(b), b.target)
  if core.Notices and not mine then
    core.Notices.Add({ key = "bnty:" .. b.id, group = L.TAB_PVP, text = text, view = "pvpbounty",
      open = function() if P.OpenBountyDetail then P.OpenBountyDetail(b.id) end end })
  end
  P.ShowWanted(b, "new", { text = text, sound = not mine })
end)

core.On("PVP_BOUNTY_WON", function(b, mine)
  if not b then return end
  local names = {}
  for _, k in ipairs(b.ws or { b.w }) do names[#names + 1] = G.Display(k) end
  if mine then
    P.ShowWanted(b, "done", { big = true, extra = L.WNT_PLUS:format(b.myShare or 0, P.GPTag()), text = L.PVP_BNT_WON:format(b.myShare or 0, b.target, G.Display(b.by)) })
  else
    local text = L.PVP_BNT_COLLECTED:format(table.concat(names, ", "), P.BountyTotal(b), b.target)
    P.ShowWanted(b, "done", { text = text })
  end
end)

core.On("PVP_BOUNTY_ADD", function(b, who, amt)
  if not b or who == G.MyKey() then return end
  local me = G.MyKey()
  if (b.by == me or (b.adds and b.adds[me])) and core.Notices then
    core.Notices.Add({ key = "bntyadd:" .. b.id, group = L.TAB_PVP, view = "pvpbounty",
      text = L.PVP_BNT_ADD_NOTICE:format(G.Display(who), amt, b.target, P.BountyTotal(b)) })
  end
end)

-- after the fight: the queued posters
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_REGEN_ENABLED" then core.Schedule("gemWantedNext", 1.5, P.NextWanted)
  elseif e == "PLAYER_LOGIN" then
    -- at login: one poster for everything new (the highest), "+ n more"
    core.Schedule("gemWantedLogin", 30, function()
      loginDone = true
      local seen, fresh = seenStore(), {}
      for _, b in ipairs(P.OpenBounties()) do
        if not seen[b.id] and b.by ~= G.MyKey() then fresh[#fresh + 1] = b end
      end
      for _, b in ipairs(P.OpenBounties()) do seen[b.id] = true end
      if #fresh == 0 then return end
      local extra = #fresh > 1 and L.WNT_MORE_NEW:format(#fresh - 1) or nil
      P.ShowWanted(fresh[1], "new", { extra = extra, text = L.PVP_BNT_LOGIN:format(#fresh) })
    end)
  end
end)

---------------------------------------------------------------------------
-- After a death: put a bounty on the killer with one click
---------------------------------------------------------------------------
local offer
local function buildOffer()
  local th = T.Current()
  local o = W.Box(UIParent, 300, 92, "bg")
  o:SetFrameStrata("HIGH")
  o:SetPoint("TOP", UIParent, "TOP", 0, -170)
  o:EnableMouse(true)
  o.title = W.Text(o, 12, "title"); o.title:SetPoint("TOPLEFT", 10, -9); o.title:SetPoint("RIGHT", -28, 0)
  o.close = W.Close(o, function() o:Hide() end); o.close:SetPoint("TOPRIGHT", -5, -5)
  o.sub = W.Text(o, 10, "muted"); o.sub:SetPoint("TOPLEFT", o.title, "BOTTOMLEFT", 0, -3); o.sub:SetPoint("RIGHT", -10, 0)
  o.btns = {}
  for i = 1, 3 do
    local b = W.Button(o, "", i == 3, 24)
    b:SetWidth(84)
    b:SetPoint("BOTTOMLEFT", 10 + (i - 1) * 94, 10)
    o.btns[i] = b
  end
  o:Hide()
  return o
end

function P.ShowDeathOffer(d)
  if not P.WantedSettings().offer or not d or not d.name then return end
  local min, max = P.BountyLimits()
  local amounts = { min, math.floor((min + max) / 2), max }
  if not P.CanPostOn(d.name, amounts[1]) then return end
  offer = offer or buildOffer()
  offer.title:SetText(L.WNT_OFFER_T:format(d.name))
  local i = P.SeenInfo(d.name) or {}
  local bits = {}
  if i.lv and i.lv > 0 then bits[#bits + 1] = L.PVP_AL_LEVEL:format(i.lv) end
  if i.r then bits[#bits + 1] = i.r end
  if i.cl then bits[#bits + 1] = i.cl end
  bits[#bits + 1] = L.WNT_OFFER_Q
  offer.sub:SetText(table.concat(bits, " · "))
  for n, btn in ipairs(offer.btns) do
    local amt = amounts[n]
    W.SetLabel(btn, amt .. " " .. P.GPTag())
    btn:SetEnabled(P.MyGP() >= amt)
    btn:SetScript("OnClick", function()
      offer:Hide()
      P.PostBounty(d.name, amt)
    end)
  end
  offer:Show()
  core.Schedule("gemWantedOffer", 45, function() if offer then offer:Hide() end end)
end

---------------------------------------------------------------------------
-- Settings pages: bounty posters, sounds
---------------------------------------------------------------------------
local MODES = function() return { { "always", L.WNT_M_ALWAYS }, { "noinst", L.WNT_M_NOINST }, { "off", L.WNT_M_OFF } } end

local function dropdownRow(p, y, label, key, opts)
  local l = W.Text(p, 11, "text"); l:SetPoint("TOPLEFT", 0, y); l:SetWidth(220); l:SetJustifyH("LEFT"); l:SetText(label)
  local dd = W.Dropdown(p, 200, opts, function() return P.WantedSettings()[key] end, function(v) P.WantedSettings()[key] = v end)
  dd:SetPoint("LEFT", l, "RIGHT", 10, 0)
  return dd
end

local function previewBounty()
  local open = P.OpenBounties()
  if open[1] then return open[1] end
  return { id = "preview", by = G.MyKey(), target = "Grimtusk Bloodfang", amt = 25, ts = U.Now(), state = "open", adds = {},
    i = { r = UnitRace and (UnitRace("player")) or "Orc", rf = select(2, UnitRace("player")), sx = 2, cl = UnitClass and (UnitClass("player")) or "?",
      lv = UnitLevel and UnitLevel("player") or 60, z = GetZoneText and GetZoneText() or "", st = U.Now() } }
end

core.UI.AddSettingsPage("pvpwanted", {
  group = "pvp",
  label = function() return L.WNT_SETTINGS end,
  build = function(p)
    p.head = core.UI.Section(p, L.WNT_SETTINGS); p.head:SetPoint("TOPLEFT", 0, 0)
    p.dd = {}
    p.dd[1] = dropdownRow(p, -36, L.WNT_S_NEW, "newMode", MODES)
    p.dd[2] = dropdownRow(p, -64, L.WNT_S_DONE, "doneMode", MODES)
    p.dd[3] = dropdownRow(p, -92, L.WNT_S_SIZE, "size", function() return { { "s", L.WNT_SZ_S }, { "m", L.WNT_SZ_M }, { "l", L.WNT_SZ_L } } end)
    p.dd[4] = dropdownRow(p, -120, L.WNT_S_DUR, "dur", function() return { { 8, "8 s" }, { 12, "12 s" }, { 20, "20 s" } } end)
    p.chat = W.Check(p, L.WNT_S_CHAT, function(_, on) P.WantedSettings().chat = on end); p.chat:SetPoint("TOPLEFT", 0, -150)
    p.offer = W.Check(p, L.WNT_S_OFFER, function(_, on) P.WantedSettings().offer = on end); p.offer:SetPoint("TOPLEFT", 0, -174)
    p.hint = W.Text(p, 10, "muted"); p.hint:SetPoint("TOPLEFT", 0, -206); p.hint:SetPoint("RIGHT", -10, 0); p.hint:SetSpacing(2)
    p.hint:SetText(L.WNT_S_HINT)
    p.test = W.Button(p, L.WNT_S_TEST, true, 22); p.test:SetPoint("TOPLEFT", p.hint, "BOTTOMLEFT", 0, -12)
    p.test:SetScript("OnClick", function() P.ShowWanted(previewBounty(), "new", { sound = true }) end)
    p.reset = W.Button(p, L.WNT_S_RESET, false, 22); p.reset:SetPoint("LEFT", p.test, "RIGHT", 8, 0)
    p.reset:SetScript("OnClick", P.ResetWantedPosition)
  end,
  refresh = function(p)
    local s = P.WantedSettings()
    for _, d in ipairs(p.dd) do d:Refresh() end
    p.chat:SetChecked(s.chat and true or false)
    p.offer:SetChecked(s.offer and true or false)
  end,
})

core.UI.AddSettingsPage("sounds", {
  group = "pvp",
  label = function() return L.SND_SETTINGS end,
  build = function(p)
    p.head = core.UI.Section(p, L.SND_SETTINGS); p.head:SetPoint("TOPLEFT", 0, 0)
    p.rows = {}
    local events = { { key = "sndNew", snd = "soundNew", label = L.SND_EV_NEW, kind = "new" }, { key = "sndDone", snd = "soundDone", label = L.SND_EV_DONE, kind = "done" } }
    for n, e in ipairs(events) do
      local y = -36 - (n - 1) * 34
      local l = W.Text(p, 11, "text"); l:SetPoint("TOPLEFT", 0, y); l:SetWidth(180); l:SetJustifyH("LEFT"); l:SetText(e.label)
      local snd = W.Dropdown(p, 150, function()
        local o = {}
        for _, s in ipairs(P.SOUNDS) do o[#o + 1] = { s.id, L[s.labelKey] or s.id } end
        return o
      end, function() return P.WantedSettings()[e.snd] end, function(v) P.WantedSettings()[e.snd] = v end)
      snd:SetPoint("LEFT", l, "RIGHT", 8, 0)
      local mode = W.Dropdown(p, 180, MODES, function() return P.WantedSettings()[e.key] end, function(v) P.WantedSettings()[e.key] = v end)
      mode:SetPoint("LEFT", snd, "RIGHT", 8, 0)
      local test = W.Button(p, L.SND_TEST, false, 22); test:SetPoint("LEFT", mode, "RIGHT", 8, 0)
      test:SetScript("OnClick", function() P.PlaySound(P.WantedSettings()[e.snd]) end)
      p.rows[n] = { snd, mode }
    end
    p.hint = W.Text(p, 10, "muted"); p.hint:SetPoint("TOPLEFT", 0, -36 - #events * 34 - 10); p.hint:SetPoint("RIGHT", -10, 0)
    p.hint:SetSpacing(2)
    p.hint:SetText(L.SND_HINT)
  end,
  refresh = function(p)
    for _, r in ipairs(p.rows) do r[1]:Refresh(); r[2]:Refresh() end
  end,
})

-- Live model tuner: a poster with the living model of your target (or yourself
-- without a target) and buttons for zoom and height; changes show at once.
local tuner
local function openTuner()
  if not tuner then
    local d = W.Box(UIParent, 300 + 24, 450 + 96, "bg")
    d:SetFrameStrata("DIALOG"); d:SetToplevel(true); d:SetPoint("CENTER", -200, 0)
    d:EnableMouse(true); d:SetMovable(true); d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving); d:SetScript("OnDragStop", d.StopMovingOrSizing)
    _G.GuildEventManagerLiveTuner = d
    tinsert(UISpecialFrames, "GuildEventManagerLiveTuner")
    d.close = W.Close(d, function() d:Hide() end); d.close:SetPoint("TOPRIGHT", -4, -4)
    d.poster = P.NewPoster(d); d.poster:SetPoint("TOPLEFT", 12, -12)
    d.poster.forceUnit = function()
      if U.UnitTrue(UnitExists, "target") then return "target" end
      return "player"
    end
    d.val = W.Text(d, 11, "text"); d.val:SetPoint("TOP", d.poster, "BOTTOM", 0, -8)
    local function apply()
      local ws = P.WantedSettings()
      ws.liveZoom = math.floor((ws.liveZoom or 0.9) * 100 + 0.5) / 100
      ws.liveDown = math.floor((ws.liveDown or 0.05) * 100 + 0.5) / 100
      d.val:SetText(("Zoom %.2f   ·   runter %.2f"):format(ws.liveZoom, ws.liveDown))
      d.poster:UpdateLive()
    end
    local function btn(label, x, y, fn)
      local b = W.Button(d, label, false, 22); b:SetWidth(70)
      b:SetPoint("TOP", d.poster, "BOTTOM", x, y)
      b:SetScript("OnClick", function() fn(P.WantedSettings()); apply() end)
      return b
    end
    btn("Zoom –", -114, -30, function(ws) ws.liveZoom = math.max(0, (ws.liveZoom or 0.9) - 0.05) end)
    btn("Zoom +", -38, -30, function(ws) ws.liveZoom = math.min(1, (ws.liveZoom or 0.9) + 0.05) end)
    btn("Hoch", 38, -30, function(ws) ws.liveDown = (ws.liveDown or 0.05) - 0.05 end)
    btn("Runter", 114, -30, function(ws) ws.liveDown = (ws.liveDown or 0.05) + 0.05 end)
    btn("Standard", 0, -58, function(ws) ws.liveZoom, ws.liveDown = nil, nil end)
    d.apply = apply
    d:RegisterEvent("PLAYER_TARGET_CHANGED")
    d:SetScript("OnEvent", function() d.poster:UpdateLive() end)
    tuner = d
  end
  local b = previewBounty()
  tuner.poster:SetBounty(b, T.Faction())
  tuner:Show()
  tuner.apply()
end

-- /gem wanted live: the tuner; /gem wanted live <zoom> <down>: set the values directly
-- /gem wanted: show a test poster
core.SlashExt.wanted = function(rest)
  local a, b, c = tostring(rest or ""):match("^%s*(%S*)%s*(%S*)%s*(%S*)")
  local ws = P.WantedSettings()
  if a == "live" then
    if tonumber(b) then ws.liveZoom = tonumber(b) end
    if tonumber(c) then ws.liveDown = tonumber(c) end
    openTuner()
    U.Print(("Live model: zoom %.2f, down %.2f"):format(ws.liveZoom or 0.9, ws.liveDown or 0.05))
  else
    P.ShowWanted(previewBounty(), "new", { sound = false })
  end
end
