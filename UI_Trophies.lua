local ADDON, ns = ...
-- Trophies (0.9): a round trophy (icon of the guild achievement with a rim in
-- bronze, silver, gold or legendary orange, season trophies with a band) and
-- the trophy wall of the banner page with filter and paging. Not yet earned:
-- grey with the progress below. Tooltip: condition, when, next tier, the
-- three biggest contributions and the own one.
local U, G, T, W, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI
local L = ns.L
local TR = {}
ns.UITrophies = TR

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function masked(f, layer, sub, size)
  local t = f:CreateTexture(nil, layer, nil, sub)
  t:SetSize(size, size)
  local m = f:CreateMaskTexture()
  m:SetAllPoints(t)
  m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  t:AddMaskTexture(m)
  return t
end

-- a trophy button: :Set(x, tier, season) with x from GuildAch.All() (or nil def only)
function TR.Icon(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.rim = masked(b, "BACKGROUND", 0, size); b.rim:SetPoint("CENTER"); b.rim:SetTexture(WHITE)
  b.inner = masked(b, "BORDER", 0, size - 6); b.inner:SetPoint("CENTER"); b.inner:SetTexture(WHITE); b.inner:SetVertexColor(0.1, 0.07, 0.05)
  b.icon = masked(b, "ARTWORK", 0, size - 8); b.icon:SetPoint("CENTER")
  b.band = CreateFrame("Frame", nil, b, "BackdropTemplate")
  b.band:SetHeight(11); b.band:SetPoint("BOTTOMLEFT", 2, -4); b.band:SetPoint("BOTTOMRIGHT", -2, -4)
  W.Paint(b.band, { 0.35, 0.08, 0.06, 1 }, { 0.83, 0.69, 0.22, 1 })
  b.band.t = b.band:CreateFontString(nil, "OVERLAY"); b.band.t:SetFont("Fonts\\FRIZQT__.TTF", 7, ""); b.band.t:SetPoint("CENTER", 0, 0)
  b.band.t:SetTextColor(0.96, 0.89, 0.66)
  b:SetScript("OnEnter", function(self) if self.x then TR.Tooltip(self, self.x, self.tier, self.seasonLabel) end end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  function b:Set(x, tier, seasonLabel, seasonStart)
    self.x, self.tier, self.seasonLabel = x, tier, seasonLabel
    local c = tier and tier > 0 and ns.GuildAch.COLORS[tier]
    self.icon:SetTexture(x.def.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if c then
      self.rim:SetVertexColor(c[1], c[2], c[3], 1)
      self.icon:SetDesaturated(false); self.icon:SetAlpha(1)
    else
      self.rim:SetVertexColor(0.25, 0.2, 0.16, 1)
      self.icon:SetDesaturated(true); self.icon:SetAlpha(0.45)
    end
    self.band:SetShown(seasonLabel ~= nil)
    if seasonLabel then
      self.band.t:SetText(seasonStart and ns.GuildAch.SeasonShort(seasonStart) or seasonLabel)
      if c then self.band:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
    end
  end
  return b
end

function TR.Tooltip(owner, x, tier, seasonLabel)
  local GA = ns.GuildAch
  local a = x.def
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(GA.Name(a), 1, 0.82, 0)
  GameTooltip:AddLine(GA.Desc(a), 0.9, 0.9, 0.9, true)
  local parts = {}
  for i, n in ipairs(a.tiers) do parts[#parts + 1] = GA.TierName(i) .. " " .. n end
  GameTooltip:AddLine(table.concat(parts, " · ") .. (a.scope == "season" and ("  (" .. L.GA_PER_SEASON .. ")") or ""), 0.6, 0.6, 0.6, true)
  if tier and tier > 0 then
    local ts = (seasonLabel and x.seasons) and nil or x.tierTs[tier]
    for _, s in ipairs(x.seasons or {}) do if s.label == seasonLabel and s.tier == tier then ts = s.ts end end
    local c = GA.COLORS[tier]
    GameTooltip:AddLine(L.GA_EARNED_ON:format(GA.TierName(tier), ts and date("%d.%m.%Y", ts) or "?")
      .. (seasonLabel and (" · " .. seasonLabel) or ""), c[1], c[2], c[3])
  end
  -- progress (current season for season achievements)
  if x.next and not (seasonLabel and x.season and seasonLabel ~= GA.SeasonLabel(x.season)) then
    GameTooltip:AddLine(L.GA_NEXT:format(GA.TierName(x.tier + 1), x.have, x.next), 1, 1, 1)
  end
  if x.current and x.current ~= x.have then GameTooltip:AddLine(L.GA_CURRENT:format(x.current), 0.8, 0.8, 0.8) end
  if x.top and x.top[1] then
    GameTooltip:AddLine(L.GA_TOP, 0.6, 0.6, 0.6)
    for i, t in ipairs(x.top) do if t then GameTooltip:AddLine(i .. ". " .. G.Display(t.who) .. " · " .. t.n, 1, 1, 1) end end
  end
  GameTooltip:AddLine(L.GA_MINE:format(x.mine or 0), 0.5, 0.7, 1)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The wall: filter chips, a row of trophies, paging
---------------------------------------------------------------------------
local SIZE, GAP = 40, 10

-- items of the wall: earned trophies first (newest first), then the open ones
local function items(filter)
  local GA = ns.GuildAch
  local out = {}
  local cur
  for _, x in ipairs(GA.All()) do
    cur = x.season and GA.SeasonLabel(x.season) or cur
    local isSeason = x.def.scope == "season"
    local function add(tier, label, ts, st) out[#out + 1] = { x = x, tier = tier, label = label, ts = ts or 0, st = st } end
    if filter ~= "season" or isSeason then
      if x.tier > 0 then add(x.tier, isSeason and GA.SeasonLabel(x.season) or nil, x.tierTs[x.tier], isSeason and x.season or nil) end
    end
    if isSeason and filter == "allseasons" then
      for _, s in ipairs(x.seasons) do add(s.tier, s.label, s.ts, s.st) end
    end
    if x.tier == 0 and (filter ~= "season" or isSeason) and filter ~= "allseasons" then add(0, nil, -1) end
  end
  table.sort(out, function(a, b) if (a.tier > 0) ~= (b.tier > 0) then return a.tier > 0 end return a.ts > b.ts end)
  return out
end

function TR.Wall(parent)
  local w = CreateFrame("Frame", nil, parent)
  w:SetHeight(110)
  w.head = UI.Section(w, L.GA_WALL)
  w.head:SetPoint("TOPLEFT", 0, 0)
  w.filter = "all"
  w.chips = {}
  local prev
  for _, f in ipairs({ { "allseasons", L.GA_F_ALLSEASONS }, { "season", L.GA_F_SEASON }, { "all", L.GA_F_ALL } }) do
    local b = W.Button(w, f[2], false, 18)
    W.SetLabel(b, f[2])
    b.f = f[1]
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 2) end
    b:SetScript("OnClick", function(self) w.filter = self.f; w.page = 1; w:Refresh() end)
    w.chips[#w.chips + 1] = b
    prev = b
  end
  w.head.line:SetPoint("RIGHT", prev, "LEFT", -8, 0)
  w.prev = W.Button(w, "<", false, 18); w.prev:SetWidth(20); w.prev:SetPoint("TOPLEFT", 0, -30)
  w.next = W.Button(w, ">", false, 18); w.next:SetWidth(20); w.next:SetPoint("TOPRIGHT", 0, -30)
  w.prev:SetScript("OnClick", function() w.page = math.max(1, (w.page or 1) - 1); w:Refresh() end)
  w.next:SetScript("OnClick", function() w.page = (w.page or 1) + 1; w:Refresh() end)
  w.icons = {}
  w.labels = {}
  w.closest = W.Text(w, 10, "muted"); w.closest:SetPoint("BOTTOMLEFT", 0, 0); w.closest:SetPoint("RIGHT", w, "RIGHT", 0, 0)
  w.closest:SetJustifyH("LEFT"); w.closest:SetWordWrap(false)
  w.page = 1
  function w:Refresh()
    local GA = ns.GuildAch
    local th = T.Current()
    for _, b in ipairs(self.chips) do
      b:SetBackdropColor(unpack(b.f == self.filter and th.accent or th.panel2))
    end
    local list = items(self.filter)
    local width = (self:GetWidth() or 400) - 56
    local per = math.max(1, math.floor((width + GAP) / (SIZE + GAP)))
    local pages = math.max(1, math.ceil(#list / per))
    self.page = math.min(self.page or 1, pages)
    self.prev:SetShown(pages > 1); self.next:SetShown(pages > 1)
    self.prev:SetEnabled(self.page > 1); self.next:SetEnabled(self.page < pages)
    local first = (self.page - 1) * per
    for i = 1, per do
      local it = list[first + i]
      local b = self.icons[i]
      if it and not b then b = TR.Icon(self, SIZE); self.icons[i] = b end
      if b then
        if it then
          b:ClearAllPoints(); b:SetPoint("TOPLEFT", 28 + (i - 1) * (SIZE + GAP), -26)
          b:Set(it.x, it.tier, it.label, it.st)
          b:Show()
          local lb = self.labels[i]
          if not lb then lb = W.Text(self, 9, "muted"); lb:SetJustifyH("CENTER"); lb:SetWordWrap(false); self.labels[i] = lb end
          lb:ClearAllPoints(); lb:SetPoint("TOP", b, "BOTTOM", 0, it.label and -7 or -3); lb:SetWidth(SIZE + GAP - 2)
          lb:SetText(it.tier > 0 and GA.Name(it.x.def) or (it.x.have .. "/" .. (it.x.next or "?")))
          lb:SetTextColor(unpack(it.tier > 0 and th.text or th.muted))
          lb:Show()
        else
          b:Hide(); if self.labels[i] then self.labels[i]:Hide() end
        end
      end
    end
    for i = per + 1, #self.icons do self.icons[i]:Hide(); if self.labels[i] then self.labels[i]:Hide() end end
    local earned = 0
    for _, it in ipairs(list) do if it.tier > 0 then earned = earned + 1 end end
    self.head:SetText(L.GA_WALL .. " (" .. GA.Count() .. ")")
    local x, share = GA.Closest()
    if x then
      self.closest:SetText(L.GA_CLOSEST:format(GA.Name(x.def), GA.TierName(x.tier + 1), x.next - x.have))
    else self.closest:SetText("") end
  end
  return w
end
