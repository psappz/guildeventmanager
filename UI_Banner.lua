local ADDON, ns = ...
-- Banner tab: clan banner (Horde) / order banner (Alliance), guild totals and
-- the member ranking. Managers can award or correct points from here.
local U, G, T, W, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI
local Pts = ns.Points
local L = ns.L
local V = { period = "season" }

local ROW_H = 22

local function cols()
  local c = { { id = "#", w = 30 }, { id = "name", w = 0 } }
  for _, pot in ipairs(ns.Modules.pots) do c[#c + 1] = { id = pot.id, w = 70, pot = pot } end
  c[#c + 1] = { id = "total", w = 80 }
  return c
end

local function awardDialog(key)
  W.Dialog({ text = L.AWARD_TEXT:format(G.Display(key)), edit = true, editText = "10", onAccept = function(txt)
    local amt, note = (txt or ""):match("^%s*(%-?%d+)%s*(.-)%s*$")
    amt = tonumber(amt)
    if not amt or amt == 0 then U.Print(L.AWARD_BAD); return end
    Pts.Add(key, "event", amt, "manual", nil, note ~= "" and note or nil)
    U.Print(L.AWARD_DONE:format(amt, G.Display(key)))
  end })
end

local function build(p)
  local th = T.Current()
  -- banner card
  local card = W.Box(p, 280, 10, "panel2")
  card:SetPoint("TOPLEFT", 0, 0); card:SetPoint("BOTTOMLEFT", 0, 0)
  p.card = card
  -- the banner itself grows with the level: 1 cloth, 2 sigil, 3 trophies, 4 flames
  -- painted card background (leather / parchment), cropped to the card's shape
  card.bgArt = card:CreateTexture(nil, "BACKGROUND", nil, 1)
  card.bgArt:SetPoint("TOPLEFT", 1, -1); card.bgArt:SetPoint("BOTTOMRIGHT", -1, 1)
  card.bgArt:SetTexCoord(0, 1, 0, 0.8)
  local scene = CreateFrame("Frame", nil, card)
  scene:SetSize(250, V.ART_SIZE); scene:SetPoint("TOP", 0, -2)
  card.scene = scene
  -- the guild banner from the tabard (UI_GuildBanner.lua)
  scene.gb = UI.GuildBanner(card, 282)
  scene.gb:SetPoint("TOP", card, "TOP", 0, -4)
  -- painted banner (Media\\banner_<faction>_<stage>.tga) where it exists for this faction
  scene.art = scene:CreateTexture(nil, "ARTWORK", nil, 2)
  scene.art:SetSize(V.ART_SIZE, V.ART_SIZE); scene.art:SetPoint("TOP", 0, 0)
  -- the faction crest in the empty ring of the painted cloth (stage 2 and up)
  scene.artSigil = scene:CreateTexture(nil, "ARTWORK", nil, 4)
  -- flickering glow on the painted braziers (stage 4): the flame sprite, additive
  scene.glow = CreateFrame("Frame", nil, scene)
  scene.glow:SetAllPoints()
  scene.glowL = scene.glow:CreateTexture(nil, "OVERLAY")
  scene.glowR = scene.glow:CreateTexture(nil, "OVERLAY")
  for _, g in ipairs({ scene.glowL, scene.glowR }) do
    g:SetTexture("Interface\\AddOns\\GuildEventManager\\Media\\flame"); g:SetBlendMode("ADD")
  end
  local gag = scene.glow:CreateAnimationGroup()
  gag:SetLooping("BOUNCE")
  local ga = gag:CreateAnimation("Alpha")
  ga:SetFromAlpha(0.15); ga:SetToAlpha(0.6); ga:SetDuration(0.45); ga:SetSmoothing("IN_OUT")
  scene.glowAnim = gag
  local gold = { 0.83, 0.66, 0.30 }
  local function tex(layer, sub)
    local t = scene:CreateTexture(nil, layer, nil, sub or 0)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    return t
  end
  scene.pole = tex("BACKGROUND", 1); scene.pole:SetSize(5, 170); scene.pole:SetPoint("TOP", 0, -10)
  scene.pole:SetVertexColor(0.42, 0.28, 0.16)
  scene.bar = tex("BORDER", 1); scene.bar:SetSize(108, 5); scene.bar:SetPoint("TOP", 0, -14)
  scene.bar:SetVertexColor(gold[1], gold[2], gold[3])
  scene.tip = tex("BORDER", 2); scene.tip:SetSize(10, 10); scene.tip:SetPoint("TOP", 0, -2)
  scene.tip:SetVertexColor(gold[1], gold[2], gold[3]); scene.tip:SetRotation(math.rad(45))
  -- cloth with gold edges and a swallowtail (a square in the card colour cuts the notch)
  scene.cloth = tex("ARTWORK", 0); scene.cloth:SetSize(88, 112); scene.cloth:SetPoint("TOP", scene.bar, "BOTTOM", 0, 0)
  scene.edgeL = tex("ARTWORK", 1); scene.edgeL:SetSize(3, 112); scene.edgeL:SetPoint("TOPLEFT", scene.cloth, "TOPLEFT")
  scene.edgeR = tex("ARTWORK", 1); scene.edgeR:SetSize(3, 112); scene.edgeR:SetPoint("TOPRIGHT", scene.cloth, "TOPRIGHT")
  for _, e in ipairs({ scene.edgeL, scene.edgeR }) do e:SetVertexColor(gold[1], gold[2], gold[3]) end
  scene.notch = tex("ARTWORK", 3); scene.notch:SetSize(34, 34); scene.notch:SetPoint("CENTER", scene.cloth, "BOTTOM", 0, 0)
  scene.notch:SetRotation(math.rad(45))
  -- 2: sigil (faction crest) on the cloth
  scene.sigil = scene:CreateTexture(nil, "ARTWORK", nil, 4)
  scene.sigil:SetSize(62, 62); scene.sigil:SetPoint("CENTER", scene.cloth, "CENTER", 0, 8)
  -- 3: trophies at the foot of the pole
  local function roundIcon(path, size, layer, parent)
    parent = parent or scene
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, 5)
    t:SetSize(size, size); t:SetTexture(path)
    local m = parent:CreateMaskTexture()
    m:SetAllPoints(t)
    m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    t:AddMaskTexture(m)
    return t
  end
  scene.trophyL = roundIcon("Interface\\Icons\\INV_Misc_Head_Dragon_01", 34)
  scene.trophyL:SetPoint("BOTTOMRIGHT", scene, "BOTTOM", -10, 4)
  scene.trophyR = roundIcon("Interface\\Icons\\INV_Misc_Head_Dragon_01", 34)
  scene.trophyR:SetPoint("BOTTOMLEFT", scene, "BOTTOM", 10, 4)
  scene.trophyR:SetTexCoord(1, 0, 0, 1)
  -- 4: flames left and right of the banner, flickering (own frame, so only they flicker)
  scene.flames = CreateFrame("Frame", nil, scene)
  scene.flames:SetAllPoints()
  scene.flameL = roundIcon("Interface\\Icons\\Spell_Fire_Fire", 40, "OVERLAY", scene.flames)
  scene.flameL:SetPoint("CENTER", scene, "TOPLEFT", 26, -100)
  scene.flameR = roundIcon("Interface\\Icons\\Spell_Fire_Fire", 40, "OVERLAY", scene.flames)
  scene.flameR:SetPoint("CENTER", scene, "TOPRIGHT", -26, -100)
  scene.flameR:SetTexCoord(1, 0, 0, 1)
  for _, fl in ipairs({ scene.flameL, scene.flameR }) do fl:SetBlendMode("ADD") end
  local ag = scene.flames:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local fade = ag:CreateAnimation("Alpha")
  fade:SetFromAlpha(1); fade:SetToAlpha(0.55); fade:SetDuration(0.7); fade:SetSmoothing("IN_OUT")
  scene.flicker = ag
  scene.preview = W.Text(card, 9, "muted")
  scene.preview:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -6)

  card.guild = W.Text(card, 16, "title")
  card.guild:SetPoint("TOP", scene, "BOTTOM", 0, -6)
  card.guild:SetJustifyH("CENTER")
  card.level = W.Text(card, 13, "title")
  card.level:SetPoint("TOP", card.guild, "BOTTOM", 0, -8)
  card.level:SetJustifyH("CENTER")
  -- the four stages; a click shows that stage on the banner (preview), a second click ends it
  card.tiers = {}
  local TIER_ICON = { nil, nil, "Interface\\Icons\\INV_Misc_Head_Dragon_01", "Interface\\Icons\\Spell_Fire_Fire" }
  for i = 1, 4 do
    local t = CreateFrame("Button", nil, card)
    t:SetSize(56, 62)
    t:SetPoint("TOPLEFT", card, "TOPLEFT", 14 + (i - 1) * 64, -292)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetPoint("TOP"); t.icon:SetSize(44, 44)
    t.fallback = TIER_ICON[i]
    t.ring = t:CreateTexture(nil, "OVERLAY")
    t.ring:SetPoint("CENTER", t.icon, "CENTER"); t.ring:SetSize(52, 52)
    t.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); t.ring:SetBlendMode("ADD")
    t.ring:Hide()
    t.name = W.Text(t, 9, "muted")
    t.name:SetPoint("TOP", t.icon, "BOTTOM", 0, -4)
    t.name:SetJustifyH("CENTER")
    t.level = i
    t:SetScript("OnClick", function(self)
      V.preview = (V.preview ~= self.level) and self.level or nil
      UI.Refresh()
    end)
    t:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L["TIER_" .. self.level], 1, 0.82, 0)
      GameTooltip:AddLine(L["TIER_" .. self.level .. "_DESC"], 1, 1, 1, true)
      GameTooltip:AddLine(L.BANNER_PREVIEW_TIP, 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card.tiers[i] = t
  end
  card.bar = W.Bar(card, 8)
  card.bar:SetPoint("TOPLEFT", 16, -364); card.bar:SetPoint("RIGHT", -16, 0)
  card.next = W.Text(card, 10, "muted")
  card.next:SetPoint("TOPLEFT", card.bar, "BOTTOMLEFT", 0, -6); card.next:SetPoint("RIGHT", card, "RIGHT", -16, 0)
  card.next:SetJustifyH("CENTER")
  card.next:SetSpacing(2)

  -- stats
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", card, "TOPRIGHT", 14, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
  p.stats = {}
  for i = 1, 3 do
    local s = W.Box(right, 10, 52, "panel2")
    s.label = W.Text(s, 10, "muted"); s.label:SetPoint("TOPLEFT", 10, -8)
    s.value = W.Text(s, 18, "title"); s.value:SetPoint("BOTTOMLEFT", 10, 8)
    p.stats[i] = s
  end
  p.stats[1]:SetPoint("TOPLEFT", 0, 0)
  p.stats[1]:SetPoint("RIGHT", right, "LEFT", 180, 0)
  p.stats[2]:SetPoint("TOPLEFT", p.stats[1], "TOPRIGHT", 8, 0); p.stats[2]:SetWidth(172)
  p.stats[3]:SetPoint("TOPLEFT", p.stats[2], "TOPRIGHT", 8, 0); p.stats[3]:SetPoint("RIGHT", right, "RIGHT", 0, 0)

  local head = UI.Section(right, L.RANKING)
  head:SetPoint("TOPLEFT", 0, -66)
  p.periods = {}
  local prev
  for _, per in ipairs({ "all", "season", "week" }) do
    local b = W.Button(right, L["PERIOD_" .. per], false, 20)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, -62) end
    b:SetScript("OnClick", function() V.period = per; UI.Refresh() end)
    b.per = per
    p.periods[#p.periods + 1] = b
    prev = b
  end
  head.line:SetPoint("RIGHT", prev, "LEFT", -8, 0)

  p.colHead = CreateFrame("Frame", nil, right)
  p.colHead:SetPoint("TOPLEFT", 0, -90); p.colHead:SetPoint("RIGHT", right, "RIGHT", 0, 0); p.colHead:SetHeight(16)
  p.colHead.cells = {}

  p.scroll = W.Scroll(right)
  p.scroll:SetPoint("TOPLEFT", 0, -108); p.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
  p.rows = W.Pool(p.scroll.content, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.cells = {}
    r:SetScript("OnClick", function(self, button)
      if button == "RightButton" and G.IsManager() then
        W.OpenMenu(self, function(_, root)
          root:CreateTitle(G.Display(self.key))
          root:CreateButton(L.AWARD, function() awardDialog(self.key) end)
        end)
      end
    end)
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(G.Display(self.key), 1, 0.82, 0)
      local h = ns.Achievements.HonorName(self.key)
      if h then GameTooltip:AddLine(L.HONOR_PREFIX:format(h), 1, 1, 1) end
      if G.IsManager() then GameTooltip:AddLine(L.RIGHTCLICK_AWARD, 0.7, 0.7, 0.7) end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
  end)
  p.empty = W.Text(p.scroll.content, 11, "muted")
  p.empty:SetPoint("TOPLEFT", 4, -6); p.empty:SetPoint("RIGHT", p.scroll.content, "RIGHT", -4, 0)
  p.empty:SetText(L.NO_POINTS)
end

local function layoutCells(owner, list, cells, size, color)
  local x = 0
  local width = owner:GetWidth()
  local fixed = 0
  for _, c in ipairs(list) do fixed = fixed + c.w end
  for i, c in ipairs(list) do
    local fs = cells[i]
    if not fs then fs = W.Text(owner, size, color); cells[i] = fs end
    local w = (c.w > 0) and c.w or math.max(60, width - fixed - 8)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", x + 4, 0)
    fs:SetWidth(w - 6)
    fs:SetWordWrap(false)
    fs:SetJustifyH((c.id == "name") and "LEFT" or (c.id == "#" and "LEFT" or "RIGHT"))
    fs:Show()
    x = x + w
  end
  for i = #list + 1, #cells do cells[i]:Hide() end
end

-- painted stages per faction (files in Media); missing stages use the highest
-- painted one plus the drawn trophies / flames, a faction without art the drawn banner
V.ART = {}   -- the old painted banners are replaced by the guild banner (UI_GuildBanner.lua)
V.ART_SIZE = 232
-- positions on the painted images (fractions of the image): ring of the sigil,
-- flames of the braziers; measured on the ChatGPT art
V.ART_POS = {
  horde = { emblem = true, ring = { 0.5, 0.339, 0.34 }, flames = { { 0.158, 0.575 }, { 0.845, 0.58 } } },
  alliance = { emblem = true, ring = { 0.5, 0.337, 0.34 }, flames = { { 0.148, 0.53 }, { 0.852, 0.53 } } },
}
local function artFor(level)
  local list = V.ART[T.Faction()]
  if not list then return nil end
  local best
  for _, n in ipairs(list) do if n <= level then best = n end end
  return best and ("Interface\\AddOns\\GuildEventManager\\Media\\banner_" .. T.Faction() .. "_" .. best), best
end

local function refresh(p)
  local th = T.Current()
  local b = Pts.Banner()
  p.card.guild:SetText(G.Name() or "")
  p.card.level:SetText(L.BANNER_LEVEL:format(T.Word("BANNER"), b.level, L["TIER_" .. b.level]))
  -- banner picture: the reached level, or the stage the manager clicked (preview)
  local lvl = V.preview or b.level
  local sc = p.card.scene
  local c = th.banner
  sc.cloth:SetVertexColor(c[1], c[2], c[3])
  if sc.cloth.SetGradient and CreateColor then
    sc.cloth:SetGradient("VERTICAL", CreateColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1), CreateColor(c[1], c[2], c[3], 1))
  end
  local bg = th.panel2
  sc.notch:SetVertexColor(bg[1], bg[2], bg[3])
  sc.sigil:SetTexture(th.crest)
  local show = { cloth = lvl >= 1, sigil = lvl >= 2, trophies = lvl >= 3, flames = lvl >= 4 }
  sc.gb:Set(lvl, T.Faction())
  local art, artStage = artFor(lvl)
  sc.art:SetShown(false)
  local drawn = false
  show.trophies, show.flames = false, false
  for _, x in ipairs({ sc.pole, sc.bar, sc.tip }) do x:SetShown(drawn) end
  for _, x in ipairs({ sc.cloth, sc.edgeL, sc.edgeR, sc.notch }) do x:SetShown(drawn and show.cloth) end
  sc.sigil:SetShown(drawn and show.sigil)
  local pos = V.ART_POS[T.Faction()]
  local S = V.ART_SIZE
  sc.artSigil:SetTexture(th.crest)
  if pos then
    sc.artSigil:SetSize(S * pos.ring[3], S * pos.ring[3])
    sc.artSigil:ClearAllPoints(); sc.artSigil:SetPoint("CENTER", sc.art, "TOPLEFT", S * pos.ring[1], -S * pos.ring[2])
  end
  -- the painted stages 2-4 carry their own emblem; the crest is only for stages without one
  sc.artSigil:SetShown(art ~= nil and show.sigil and artStage >= 2 and not (pos and pos.emblem))
  -- painted trophies / flames replace the drawn ones
  local paintedTrophies = art ~= nil and artStage >= 3
  local paintedFlames = art ~= nil and artStage >= 4
  show.trophies = show.trophies and not paintedTrophies
  local glow = paintedFlames and pos ~= nil
  sc.glow:SetShown(glow)
  if glow then
    for k, g in ipairs({ sc.glowL, sc.glowR }) do
      local f = pos.flames[k]
      g:SetSize(S * 0.09, S * 0.18)
      g:ClearAllPoints(); g:SetPoint("CENTER", sc.art, "TOPLEFT", S * f[1], -S * f[2])
    end
    if not sc.glowAnim:IsPlaying() then sc.glowAnim:Play() end
  else
    sc.glowAnim:Stop()
  end
  if paintedFlames then show.flames = false end
  local bgFile = "Interface\\AddOns\\GuildEventManager\\Media\\bg_" .. T.Faction()
  p.card.bgArt:SetTexture(bgFile)
  sc.trophyL:SetShown(show.trophies); sc.trophyR:SetShown(show.trophies)
  sc.flames:SetShown(show.flames)
  if show.flames then if not sc.flicker:IsPlaying() then sc.flicker:Play() end else sc.flicker:Stop() end
  sc.preview:SetText(V.preview and L.BANNER_PREVIEW:format(L["TIER_" .. V.preview]) or "")
  for i, t in ipairs(p.card.tiers) do
    t.name:SetText(L["TIER_" .. i])
    if not t.mini then
      t.mini = UI.GuildBanner(t, 54)
      t.mini:SetPoint("CENTER", t.icon, "CENTER", 0, 0)
    end
    t.mini:Set(i, T.Faction())
    t.icon:SetTexture(nil)
    local reached = i <= b.level
    t.mini:SetAlpha(reached and 1 or 0.4)
    W.Color(t.name, reached and "title" or "muted")
    t.ring:SetShown(V.preview == i)
  end
  if b.nextAt then
    p.card.bar:SetValue(math.min(1, (b.value - b.from) / math.max(1, b.nextAt - b.from)))
    p.card.next:SetText(L.BANNER_NEXT:format(b.nextAt - b.value, L["TIER_" .. (b.level + 1)]) .. "\n" .. L.BANNER_HOW)
  else
    p.card.bar:SetValue(1)
    p.card.next:SetText(L.BANNER_MAX .. "\n" .. L.BANNER_HOW)
  end

  p.stats[1].label:SetText(L.STAT_SEASON); p.stats[1].value:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(Pts.GuildTotal("season"))) or math.floor(Pts.GuildTotal("season")))
  p.stats[2].label:SetText(L.STAT_WEEK); p.stats[2].value:SetText("+" .. math.floor(Pts.GuildTotal("week")))
  local me = Pts.Totals("season")[G.MyKey()]
  p.stats[3].label:SetText(L.STAT_ME); p.stats[3].value:SetText(me and math.floor(me.total) or 0)

  for _, btn in ipairs(p.periods) do
    local active = btn.per == V.period
    btn:SetBackdropColor(unpack(active and th.accent or th.panel2))
    btn.label:SetTextColor(unpack(active and { 1, 0.95, 0.85 } or th.text))
  end

  local c = cols()
  layoutCells(p.colHead, c, p.colHead.cells, 10, "muted")
  for i, col in ipairs(c) do
    local t = col.id == "#" and "#" or col.id == "name" and L.COL_MEMBER or col.id == "total" and L.COL_TOTAL
      or (col.pot.name or L[col.pot.nameKey])
    p.colHead.cells[i]:SetText(t)
  end

  local list = Pts.Ranking(V.period)
  local my = G.MyKey()
  local n = 0
  for i, r in ipairs(list) do
    if math.abs(r.total) > 0 or next(r.pots) then
      n = n + 1
      local row = p.rows:Get(n)
      row.key = r.key
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -(n - 1) * ROW_H); row:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
      row:SetWidth(p.scroll.content:GetWidth())
      if r.key == my then row.hl:SetColorTexture(th.accent[1], th.accent[2], th.accent[3], 0.25)
      elseif n % 2 == 0 then row.hl:SetColorTexture(0, 0, 0, 0.12)
      else row.hl:SetColorTexture(0, 0, 0, 0) end
      layoutCells(row, c, row.cells, 11, "text")
      for j, col in ipairs(c) do
        local fs = row.cells[j]
        if col.id == "#" then fs:SetText(n .. "."); W.Color(fs, "title")
        elseif col.id == "name" then
          local h = ns.Achievements.HonorName(r.key)
          fs:SetText(G.Display(r.key) .. (h and U.Color(T.Hex(th.muted), " · " .. h) or ""))
          W.Color(fs, "text")
        elseif col.id == "total" then fs:SetText(math.floor(r.total)); W.Color(fs, "title")
        else fs:SetText(r.pots[col.id] and math.floor(r.pots[col.id]) or "–"); W.Color(fs, "text") end
      end
    end
  end
  p.rows:HideFrom(n + 1)
  p.empty:SetShown(n == 0)
  p.scroll:SetContentHeight(n * ROW_H)
end

UI.RegisterView("banner", {
  label = function() return T.Word("BANNER") end,
  build = build,
  refresh = refresh,
})
