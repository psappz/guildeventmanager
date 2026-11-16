local ADDON, ns = ...
-- The guild banner: layered art per faction and stage (Media/Banner), the
-- cloth tinted with the tabard's background colour, the hem with its border
-- colour, the guild emblem drawn by the game in the middle (stages 2-4).
-- Layers back to front: pole, cloth, border, sheen (4), emblem (2-4),
-- trim (3-4), tassels (3-4), finial (4).
local UI, T = ns.UI, ns.Theme
local GB = {}
ns.GuildBanner = GB

local PATH = "Interface\\AddOns\\GuildEventManager\\Media\\Banner\\"
-- canvas of the art: 1024 x 2048, emblem centre (560, 820), radius 210
local EMBLEM_X, EMBLEM_Y, EMBLEM_R = 560 / 1024, 820 / 2048, 210 / 1024

-- colours when the guild has no tabard (or the player no guild)
GB.DEFAULT = {
  horde = { bg = { 0.55, 0.08, 0.06 }, border = { 0.14, 0.11, 0.10 } },
  alliance = { bg = { 0.12, 0.25, 0.62 }, border = { 0.86, 0.72, 0.30 } },
}

local LAYERS = {
  { id = "pole", sub = -6 }, { id = "cloth", sub = -4 }, { id = "border", sub = -2 }, { id = "sheen", sub = 0 },
  { id = "trim", sub = 4 }, { id = "tassels", sub = 5 }, { id = "finial", sub = 6 },
}

-- sparkles on stage 4: positions on the canvas (x, y, size) and start delays
local SPARKLES = { { 262, 190, 70, 0 }, { 880, 520, 55, 0.7 }, { 262, 1180, 60, 1.5 }, { 870, 1520, 80, 2.1 }, { 150, 95, 90, 2.8 }, { 560, 1690, 50, 3.4 } }
-- the alliance cloth ends higher in the middle (swallow-tail): its lowest sparkle sits on the tip
local SPARKLE_FACTION = { alliance = { [6] = { 560, 1600 } } }
local GOLD = { 0.95, 0.72, 0.32 }

local function pulse(region, from, to, dur, delay)
  local ag = region:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur); a:SetSmoothing("IN_OUT")
  if delay and a.SetStartDelay then a:SetStartDelay(delay) end
  return ag
end

-- the stage-4 effects: glow behind, stronger sheen, a band of light running over
-- the cloth (masked to the cloth), a glowing emblem, sparkles on trim and finial
local function buildEffects(f, height)
  local w = height / 2
  local fx = { anims = {} }
  f.fx = fx
  fx.glow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  fx.glow:SetTexture(PATH .. "glow"); fx.glow:SetBlendMode("ADD")
  fx.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
  fx.glow:SetPoint("CENTER", f, "CENTER", w * 0.05, height * 0.02); fx.glow:SetSize(w * 1.5, height * 1.15)
  fx.anims[#fx.anims + 1] = pulse(fx.glow, 0.35, 0.75, 1.6)
  fx.sheen = f:CreateTexture(nil, "ARTWORK", nil, 1)
  fx.sheen:SetTexture(PATH .. "sheen"); fx.sheen:SetBlendMode("ADD"); fx.sheen:SetAllPoints(); fx.sheen:SetAlpha(0.45)
  -- running band of light, only on the cloth
  fx.shine = f:CreateTexture(nil, "ARTWORK", nil, 1)
  fx.shine:SetTexture(PATH .. "shine"); fx.shine:SetBlendMode("ADD")
  fx.shine:SetVertexColor(1, 0.88, 0.62); fx.shine:SetAlpha(0.32)
  fx.shine:SetSize(w, w); fx.shine:SetPoint("TOP", f, "TOP", 0, w * 0.1)
  if f.CreateMaskTexture and fx.shine.AddMaskTexture then
    fx.mask = f:CreateMaskTexture()
    fx.mask:SetAllPoints()
    fx.shine:AddMaskTexture(fx.mask)
  end
  local ag = fx.shine:CreateAnimationGroup()
  ag:SetLooping("REPEAT")
  local mv = ag:CreateAnimation("Translation")
  mv:SetOffset(0, -height * 0.85); mv:SetDuration(2.6); mv:SetSmoothing("IN_OUT")
  local wait = ag:CreateAnimation("Alpha")
  wait:SetFromAlpha(0); wait:SetToAlpha(0); wait:SetDuration(2.4); wait:SetOrder(2)
  fx.anims[#fx.anims + 1] = ag
  -- glowing emblem (a second copy of the game's emblem, additive)
  fx.emblem = f:CreateTexture(nil, "ARTWORK", nil, 3)
  fx.emblem:SetBlendMode("ADD")
  fx.emblem:SetSize(f.emblem:GetWidth() * 1.12, f.emblem:GetHeight() * 1.12)
  fx.emblem:SetPoint("CENTER", f.emblem, "CENTER")
  fx.anims[#fx.anims + 1] = pulse(fx.emblem, 0.25, 0.7, 1.3)
  -- sparkles
  fx.sparkles = {}
  for i, sp in ipairs(SPARKLES) do
    local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetTexture(PATH .. "sparkle"); t:SetBlendMode("ADD"); t:SetVertexColor(1, 0.92, 0.7)
    local sz = sp[3] / 1024 * w * 1.1
    t:SetSize(sz, sz)
    t:SetPoint("CENTER", f, "TOPLEFT", sp[1] / 1024 * w, -sp[2] / 2048 * height)
    t:SetAlpha(0)
    local g = t:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    local on = g:CreateAnimation("Alpha"); on:SetFromAlpha(0); on:SetToAlpha(1); on:SetDuration(0.35); on:SetOrder(1)
    if on.SetStartDelay then on:SetStartDelay(sp[4]) end
    local off = g:CreateAnimation("Alpha"); off:SetFromAlpha(1); off:SetToAlpha(0); off:SetDuration(0.6); off:SetOrder(2)
    local rest = g:CreateAnimation("Alpha"); rest:SetFromAlpha(0); rest:SetToAlpha(0); rest:SetDuration(4.2 - sp[4] * 0.3); rest:SetOrder(3)
    fx.sparkles[i] = t
    fx.anims[#fx.anims + 1] = g
  end
  return fx
end

local function showEffects(f, on, faction, emblemShown)
  local fx = f.fx
  if not fx then return end
  for _, r in ipairs({ fx.glow, fx.sheen, fx.shine }) do r:SetShown(on) end
  for _, t in ipairs(fx.sparkles) do t:SetShown(on) end
  if fx.mask then fx.mask:SetTexture(PATH .. "cloth_" .. faction .. "_4", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
  local w, h = f:GetWidth(), f:GetHeight()
  for i, t in ipairs(fx.sparkles) do
    local pos = (SPARKLE_FACTION[faction] and SPARKLE_FACTION[faction][i]) or SPARKLES[i]
    t:ClearAllPoints(); t:SetPoint("CENTER", f, "TOPLEFT", pos[1] / 1024 * w, -pos[2] / 2048 * h)
  end
  fx.emblem:SetShown(on and emblemShown)
  if on and emblemShown and SetLargeGuildTabardTextures then
    pcall(SetLargeGuildTabardTextures, "player", fx.emblem, f.dummyBg, f.dummyBorder)
    fx.emblem:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
  end
  for _, ag in ipairs(fx.anims) do
    if on then if not ag:IsPlaying() then ag:Play() end else ag:Stop() end
  end
end

-- UI.GuildBanner(parent, height, effects): a frame of height x height/2 with
-- :Set(stage, faction); effects = the animated stage-4 shine (big banner only)
function UI.GuildBanner(parent, height, effects)
  height = height or 280
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(height / 2, height)
  f.tex = {}
  for _, l in ipairs(LAYERS) do
    local t = f:CreateTexture(nil, "ARTWORK", nil, l.sub)
    t:SetAllPoints()
    f.tex[l.id] = t
  end
  f.emblem = f:CreateTexture(nil, "ARTWORK", nil, 2)
  local size = 2 * EMBLEM_R * (height / 2) * 0.92
  f.emblem:SetSize(size, size)
  f.emblem:SetPoint("CENTER", f, "TOPLEFT", EMBLEM_X * (height / 2), -EMBLEM_Y * height)
  -- the game's helper also wants a background and a border texture: kept on a hidden frame
  f.hidden = CreateFrame("Frame", nil, f); f.hidden:Hide()
  f.dummyBg = f.hidden:CreateTexture(nil, "ARTWORK")
  f.dummyBorder = f.hidden:CreateTexture(nil, "ARTWORK")
  if effects then buildEffects(f, height) end

  function f:Set(stage, faction, tabard)
    stage = math.max(1, math.min(4, tonumber(stage) or 1))
    faction = (faction == "alliance") and "alliance" or "horde"
    tabard = tabard == nil and ns.Tabard and ns.Tabard.Read() or tabard
    local def = GB.DEFAULT[faction]
    local bg = (tabard and tabard.bg) or def.bg
    local border = (tabard and tabard.border) or def.border
    local t = self.tex
    t.pole:SetTexture(PATH .. "pole_" .. faction)
    t.cloth:SetTexture(PATH .. "cloth_" .. faction .. "_" .. stage)
    t.cloth:SetVertexColor(bg[1], bg[2], bg[3])
    t.border:SetTexture(PATH .. "border_" .. faction .. "_" .. stage)
    t.border:SetVertexColor(border[1], border[2], border[3])
    t.sheen:SetTexture(PATH .. "sheen"); t.sheen:SetShown(stage >= 4)
    t.trim:SetTexture(PATH .. "trim_" .. faction); t.trim:SetShown(stage >= 3)
    t.tassels:SetTexture(PATH .. "tassels_" .. faction); t.tassels:SetShown(stage >= 3)
    t.finial:SetTexture(PATH .. "finial_" .. faction); t.finial:SetShown(stage >= 4)
    -- the emblem exactly as the game draws it on the tabard
    local shown = false
    if stage >= 2 and tabard and SetLargeGuildTabardTextures then
      shown = pcall(SetLargeGuildTabardTextures, "player", self.emblem, self.dummyBg, self.dummyBorder)
    end
    self.emblem:SetShown(shown and true or false)
    showEffects(self, stage >= 4, faction, shown and true or false)
  end
  return f
end
