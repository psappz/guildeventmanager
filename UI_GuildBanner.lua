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

-- UI.GuildBanner(parent, height): a frame of height x height/2 with :Set(stage, faction)
function UI.GuildBanner(parent, height)
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
  end
  return f
end
