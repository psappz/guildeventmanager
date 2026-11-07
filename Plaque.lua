local ADDON, ns = ...
-- Achievement plaque in the WotLK style, tinted for the faction.
-- Layout measured on the client: header band 56-67, brown field 38-54,
-- gold band 27-37 (units from the bottom of the 300x88 frame).
local T = ns.Theme
local PL = {}
ns.Plaque = PL

local FONT = "Fonts\\FRIZQT__.TTF"
local frame

local function build()
  local f = CreateFrame("Frame", "GuildEventManagerPlaque", UIParent)
  f:SetSize(300, 88); f:SetScale(1.4)
  f:SetPoint("TOP", UIParent, "TOP", 0, -110)
  f:SetFrameStrata("HIGH"); f:Hide(); f:EnableMouse(true)

  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Background")
  f.bg:SetTexCoord(0, 0.605, 0, 0.703); f.bg:SetAllPoints()

  f.crest = f:CreateTexture(nil, "BORDER")
  f.crest:SetSize(70, 70); f.crest:SetPoint("CENTER", f, "CENTER", 30, 0); f.crest:SetAlpha(0.18)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(50, 50); f.icon:SetPoint("LEFT", 6, -1)
  f.iconFrame = f:CreateTexture(nil, "OVERLAY")
  f.iconFrame:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
  f.iconFrame:SetTexCoord(0, 0.5625, 0, 0.5625)
  f.iconFrame:SetSize(72, 72); f.iconFrame:SetPoint("CENTER", f.icon, "CENTER", -1, 2)

  f.unlocked = f:CreateFontString(nil, "OVERLAY")
  f.unlocked:SetFont(FONT, 8, ""); f.unlocked:SetTextColor(0.16, 0.11, 0.06)
  f.unlocked:SetPoint("CENTER", f, "BOTTOM", 7, 61)
  f.name = f:CreateFontString(nil, "OVERLAY")
  f.name:SetFont(FONT, 12, "OUTLINE"); f.name:SetTextColor(1, 0.95, 0.82)
  f.name:SetPoint("CENTER", f, "BOTTOM", 6, 46)
  f.name:SetWidth(166); f.name:SetWordWrap(false)
  f.sub = f:CreateFontString(nil, "OVERLAY")
  f.sub:SetFont(FONT, 9, ""); f.sub:SetTextColor(1, 0.82, 0.25)
  f.sub:SetPoint("CENTER", f, "BOTTOM", 6, 32)
  f.sub:SetWidth(166); f.sub:SetWordWrap(false)

  f.shield = f:CreateTexture(nil, "ARTWORK")
  f.shield:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Shields")
  f.shield:SetTexCoord(0, 0.5, 0, 0.45)
  f.shield:SetSize(64, 64); f.shield:SetPoint("TOPRIGHT", -10, -13)
  f.points = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.points:SetPoint("CENTER", f.shield, "CENTER", 0, 1)

  f.glow = f:CreateTexture(nil, "OVERLAY")
  f.glow:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Glow")
  f.glow:SetTexCoord(0, 0.78125, 0, 0.66796875)
  f.glow:SetBlendMode("ADD"); f.glow:SetSize(400, 171); f.glow:SetPoint("CENTER"); f.glow:SetAlpha(0)

  local ag = f:CreateAnimationGroup()
  local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.25); a:SetOrder(1)
  local h = ag:CreateAnimation("Alpha"); h:SetFromAlpha(1); h:SetToAlpha(1); h:SetDuration(5); h:SetOrder(2)
  local o = ag:CreateAnimation("Alpha"); o:SetFromAlpha(1); o:SetToAlpha(0); o:SetDuration(0.8); o:SetOrder(3)
  ag:SetScript("OnFinished", function() f:Hide() end)
  f.anim = ag
  local gl = f.glow:CreateAnimationGroup()
  local g1 = gl:CreateAnimation("Alpha"); g1:SetFromAlpha(0); g1:SetToAlpha(1); g1:SetDuration(0.2); g1:SetOrder(1)
  local g2 = gl:CreateAnimation("Alpha"); g2:SetFromAlpha(1); g2:SetToAlpha(0); g2:SetDuration(0.6); g2:SetOrder(2)
  f.glowAnim = gl
  f:SetScript("OnMouseUp", function() ag:Stop(); f:Hide() end)
  return f
end

-- name: achievement name, sub: honor name or description, pts: points, icon: texture
function PL.Show(name, sub, pts, icon, faction)
  frame = frame or build()
  local th = T.THEMES[faction or T.Faction()]
  frame.bg:SetVertexColor(unpack(th.tint))
  frame.glow:SetVertexColor(unpack(th.glow))
  frame.crest:SetTexture(th.crest)
  frame.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  frame.unlocked:SetText((T.THEMES[faction or T.Faction()].key == "alliance" and ns.L.A_ACH_KIND or ns.L.H_ACH_KIND):upper())
  frame.name:SetText(name or "")
  frame.sub:SetText(sub or "")
  frame.points:SetText(tostring(pts or 0))
  frame.anim:Stop(); frame.glowAnim:Stop()
  frame:SetAlpha(1); frame:Show()
  frame.anim:Play(); frame.glowAnim:Play()
  pcall(PlaySound, SOUNDKIT and SOUNDKIT.UI_PERSONAL_LOOT_BANNER or 888)
end

function PL.Test(faction)
  local a = ns.Achievements.DEFAULTS[7]
  for _, d in ipairs(ns.Achievements.AllDefaults()) do if d.id == "blade3" then a = d end end
  local f = faction or T.Faction()
  local L = ns.L
  local name = (f == "alliance") and L["A_" .. a.nameKey] or L["H_" .. a.nameKey]
  local honor = (f == "alliance") and L["A_" .. a.honorKey] or L["H_" .. a.honorKey]
  PL.Show(name, L.HONOR_PREFIX:format(honor), a.pts, a.icon, f)
end
