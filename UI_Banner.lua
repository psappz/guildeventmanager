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
  card.crest = card:CreateTexture(nil, "ARTWORK")
  card.crest:SetSize(96, 96); card.crest:SetPoint("TOP", 0, -14)
  card.crest:SetTexture(th.crest)
  card.guild = W.Text(card, 16, "title")
  card.guild:SetPoint("TOP", card.crest, "BOTTOM", 0, -4)
  card.guild:SetJustifyH("CENTER")
  card.level = W.Text(card, 13, "title")
  card.level:SetPoint("TOP", card.guild, "BOTTOM", 0, -14)
  card.level:SetJustifyH("CENTER")
  card.tiers = {}
  for i = 1, 4 do
    local t = CreateFrame("Frame", nil, card)
    t:SetSize(56, 70)
    t:SetPoint("TOPLEFT", card, "TOPLEFT", 14 + (i - 1) * 64, -196)
    t.flag = t:CreateTexture(nil, "ARTWORK")
    t.flag:SetPoint("TOP"); t.flag:SetSize(36, 50)
    t.flag:SetColorTexture(th.banner[1], th.banner[2], th.banner[3], 1)
    t.name = W.Text(t, 9, "muted")
    t.name:SetPoint("TOP", t.flag, "BOTTOM", 0, -4)
    t.name:SetJustifyH("CENTER")
    card.tiers[i] = t
  end
  card.bar = W.Bar(card, 8)
  card.bar:SetPoint("TOPLEFT", 16, -290); card.bar:SetPoint("RIGHT", -16, 0)
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

local function refresh(p)
  local th = T.Current()
  local b = Pts.Banner()
  p.card.guild:SetText(G.Name() or "")
  p.card.level:SetText(L.BANNER_LEVEL:format(T.Word("BANNER"), b.level, L["TIER_" .. b.level]))
  for i, t in ipairs(p.card.tiers) do
    t.name:SetText(L["TIER_" .. i])
    t.flag:SetAlpha(i <= b.level and 1 or 0.25)
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
