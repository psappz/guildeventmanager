local ADDON, ns = ...
-- The guild's tabard (background colour, border, emblem and emblem colour),
-- read from the game. Every member reads his own guild's tabard, nothing is
-- sent. Base for the guild banner. /gem tabard shows a test drawing.
local U = ns.U
local Tb = {}
ns.Tabard = Tb

local function rgb(c)
  if type(c) == "table" then
    if c.GetRGB then return { c:GetRGB() } end
    if c.r then return { c.r, c.g, c.b } end
  end
end

-- { bg = {r,g,b}, border = {r,g,b}, emblem = {r,g,b}, emblemFile, emblemStyle, borderStyle, files = {...}, via }
function Tb.Read()
  -- modern client
  if C_GuildInfo and C_GuildInfo.GetGuildTabardInfo then
    local ok, t = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
    if ok and type(t) == "table" then
      return { bg = rgb(t.backgroundColor), border = rgb(t.borderColor), emblem = rgb(t.emblemColor),
        emblemFile = t.emblemFileID, emblemStyle = t.emblemStyle, via = "C_GuildInfo" }
    end
  end
  -- classic client
  if GetGuildLogoInfo then
    local r = { pcall(GetGuildLogoInfo) }
    if r[1] and r[2] then
      local out = { bg = { r[2], r[3], r[4] }, border = { r[5], r[6], r[7] }, emblem = { r[8], r[9], r[10] },
        emblemFile = r[11], emblemStyle = r[12], via = "GetGuildLogoInfo" }
      if GetGuildTabardFiles then
        local f = { pcall(GetGuildTabardFiles) }
        if f[1] then out.files = { bgU = f[2], bgL = f[3], emU = f[4], emL = f[5], boU = f[6], boL = f[7] } end
      end
      return out
    end
  end
  return nil
end

local function c3(c) return c and string.format("%.2f/%.2f/%.2f", c[1] or 0, c[2] or 0, c[3] or 0) or "?" end

ns.Probe.Add("tabard", function()
  local P = ns.Probe
  local t = Tb.Read()
  local out = {
    { "API", "C_GuildInfo.GetGuildTabardInfo " .. P.Has(C_GuildInfo and C_GuildInfo.GetGuildTabardInfo) ..
      " · GetGuildLogoInfo " .. P.Has(GetGuildLogoInfo) .. " · GetGuildTabardFiles " .. P.Has(GetGuildTabardFiles) ..
      " · SetLargeGuildTabardTextures " .. P.Has(SetLargeGuildTabardTextures) },
  }
  if t then
    out[#out + 1] = { "tabard (" .. t.via .. ")", "background " .. c3(t.bg) .. " · border " .. c3(t.border) ..
      " · emblem " .. c3(t.emblem) .. " · emblem file " .. tostring(t.emblemFile) .. " · style " .. tostring(t.emblemStyle) }
    if t.files then
      out[#out + 1] = { "tabard files", string.format("bg %s / %s · emblem %s / %s · border %s / %s",
        tostring(t.files.bgU), tostring(t.files.bgL), tostring(t.files.emU), tostring(t.files.emL), tostring(t.files.boU), tostring(t.files.boL)) }
    end
  else
    out[#out + 1] = { "tabard", "nothing (not in a guild, or no tabard yet)" }
  end
  return out
end)

---------------------------------------------------------------------------
-- Test drawing: the tabard as the game draws it (if the client has the
-- helper), and the same built from the single parts.
---------------------------------------------------------------------------
local win
function Tb.ShowTest()
  local t = Tb.Read()
  if not t then U.Print(ns.L.TABARD_NONE); return end
  if not win then
    local th = ns.Theme.Current()
    win = CreateFrame("Frame", "GuildEventManagerTabardTest", UIParent, "BackdropTemplate")
    win:SetSize(360, 250); win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    ns.W.Paint(win, th.bg, th.border)
    win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildEventManagerTabardTest")
    ns.W.Close(win)
    win.title = ns.W.Text(win, 13, "title"); win.title:SetPoint("TOPLEFT", 12, -10); win.title:SetText(ns.L.TABARD_TEST)
    -- left: from the single parts
    local function slot(x, label)
      local f = CreateFrame("Frame", nil, win)
      f:SetSize(150, 170); f:SetPoint("TOPLEFT", x, -34)
      f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetPoint("TOPLEFT", 10, -10); f.bg:SetPoint("BOTTOMRIGHT", -10, 24)
      f.border = f:CreateTexture(nil, "BORDER"); f.border:SetAllPoints(f.bg)
      f.emblem = f:CreateTexture(nil, "ARTWORK"); f.emblem:SetSize(90, 90); f.emblem:SetPoint("CENTER", f.bg, "CENTER")
      f.label = ns.W.Text(f, 10, "muted"); f.label:SetPoint("BOTTOM", 0, 4); f.label:SetText(label)
      return f
    end
    win.parts = slot(14, ns.L.TABARD_PARTS)
    win.game = slot(190, ns.L.TABARD_GAME)
    win.info = ns.W.Text(win, 9, "muted"); win.info:SetPoint("BOTTOMLEFT", 12, 8); win.info:SetPoint("RIGHT", -12, 0)
    win.info:SetWordWrap(true); win.info:SetJustifyH("LEFT")
  end
  -- built from the parts: colour fill, emblem texture tinted
  local p = win.parts
  p.bg:SetColorTexture(t.bg and t.bg[1] or 0, t.bg and t.bg[2] or 0, t.bg and t.bg[3] or 0, 1)
  p.border:SetTexture(nil)
  if t.files and t.files.boU then p.border:SetTexture(t.files.boU) end
  if t.border then p.border:SetVertexColor(t.border[1], t.border[2], t.border[3]) end
  local em = t.emblemFile or (t.files and t.files.emU)
  if em then p.emblem:SetTexture(em) else p.emblem:SetTexture(nil) end
  if t.emblem then p.emblem:SetVertexColor(t.emblem[1], t.emblem[2], t.emblem[3]) end
  -- as the game draws it
  local g = win.game
  if SetLargeGuildTabardTextures then
    local ok, err = pcall(SetLargeGuildTabardTextures, "player", g.emblem, g.bg, g.border)
    g.label:SetText(ok and ns.L.TABARD_GAME or ("error: " .. tostring(err):sub(1, 30)))
  else
    g.bg:SetColorTexture(0, 0, 0, 0); g.emblem:SetTexture(nil); g.border:SetTexture(nil)
    g.label:SetText(ns.L.TABARD_GAME_NONE)
  end
  win.info:SetText("via " .. t.via .. " · emblem " .. tostring(em) .. " · style " .. tostring(t.emblemStyle))
  win:Show()
end

ns.SlashExt.tabard = function() Tb.ShowTest() end
