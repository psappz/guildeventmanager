local ADDON, ns = ...
-- Overview: banner progress, the next event with the own sign-up, the newest
-- bookings of all modules and the notices.
local U, G, T, W, UI, Pts, E, Lg = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI, ns.Points, ns.Events, ns.Ledger
local L = ns.L

local function card(parent, w)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  W.Paint(b, T.Current().panel2, T.Current().line)
  b:SetHeight(76)
  b.label = W.Text(b, 10, "muted"); b.label:SetPoint("TOPLEFT", 10, -9)
  b.value = W.Text(b, 15, "title"); b.value:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -6); b.value:SetPoint("RIGHT", -10, 0)
  b.value:SetWordWrap(false)
  b.info = W.Text(b, 10, "muted"); b.info:SetPoint("TOPLEFT", b.value, "BOTTOMLEFT", 0, -6); b.info:SetPoint("RIGHT", -10, 0)
  b.info:SetWordWrap(false)
  local th = T.Current()
  b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1) end)
  b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(th.line[1], th.line[2], th.line[3], 1) end)
  return b
end

local function nextEvent()
  local best
  for _, e in ipairs(E.List(function(e) return E.IsOpen(e) and e.kind ~= "season" and ns.Profile.IsTypeActive(e.type) end)) do
    if not best then best = e end
  end
  return best
end

local function build(p)
  p.cards = {}
  for i = 1, 3 do
    local c = card(p)
    if i == 1 then c:SetPoint("TOPLEFT", 0, 0) else c:SetPoint("LEFT", p.cards[i - 1], "RIGHT", 10, 0) end
    p.cards[i] = c
  end
  p.cards[1]:SetScript("OnClick", function() UI.Show("banner") end)
  p.cards[2]:SetScript("OnClick", function(self) if self.ev then UI.Show("events"); ns.UIEvents.OpenDetail(self.ev) end end)
  p.cards[3]:SetScript("OnClick", function() UI.Show("events") end)

  local left = CreateFrame("Frame", nil, p)
  left:SetPoint("TOPLEFT", 0, -92); left:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -6, 0)
  p.ledHead = UI.Section(left, L.HOME_LEDGER)
  p.ledHead:SetPoint("TOPLEFT", 0, 0)
  p.ledAll = W.Button(left, L.HOME_ALL, false, 20)
  p.ledAll:SetPoint("TOPRIGHT", 0, 2)
  p.ledAll:SetScript("OnClick", function() UI.Show("ledger") end)
  p.ledHead.line:SetPoint("RIGHT", p.ledAll, "LEFT", -8, 0)
  p.ledBox = W.Box(left, 10, 10, "panel2")
  p.ledBox:SetPoint("TOPLEFT", 0, -26); p.ledBox:SetPoint("BOTTOMRIGHT", 0, 0)
  p.ledRows = W.Pool(p.ledBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(20)
    r.tag = UI.Pill(r); r.tag:SetPoint("LEFT", 6, 0)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 86, 0); r.text:SetPoint("RIGHT", -44, 0); r.text:SetWordWrap(false)
    r.pts = W.Text(r, 11, "title"); r.pts:SetPoint("RIGHT", -8, 0); r.pts:SetJustifyH("RIGHT")
    return r
  end)
  p.ledEmpty = W.Text(p.ledBox, 10, "muted"); p.ledEmpty:SetPoint("TOPLEFT", 8, -8); p.ledEmpty:SetText(L.LEDGER_EMPTY)

  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", p, "TOP", 6, -92); right:SetPoint("BOTTOMRIGHT", 0, 0)
  p.notHead = UI.Section(right, L.NOTICES)
  p.notHead:SetPoint("TOPLEFT", 0, 0)
  p.notBox = W.Box(right, 10, 10, "panel2")
  p.notBox:SetPoint("TOPLEFT", 0, -26); p.notBox:SetPoint("BOTTOMRIGHT", 0, 0)
  local th = T.Current()
  p.notRows = W.Pool(p.notBox, function(parent)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetHeight(38)
    W.Paint(r, th.panel, th.line)
    r.group = W.Text(r, 9, "title"); r.group:SetPoint("TOPLEFT", 8, -5)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("TOPLEFT", r.group, "BOTTOMLEFT", 0, -3); r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self) if self.n then ns.Notices.Open(self.n) end end)
    return r
  end)
  p.notEmpty = W.Text(p.notBox, 10, "muted"); p.notEmpty:SetPoint("TOPLEFT", 8, -8); p.notEmpty:SetText(L.NOTICES_NONE)
end

local function refresh(p)
  local th = T.Current()
  local w = (p:GetWidth() > 0 and p:GetWidth() or 840)
  for _, c in ipairs(p.cards) do c:SetWidth((w - 20) / 3) end

  local b = Pts.Banner()
  local c1 = p.cards[1]
  c1.label:SetText(L.HOME_BANNER)
  c1.value:SetText(L.HOME_BANNER_VAL:format(b.level, b.value))
  c1.info:SetText(b.nextAt and L.HOME_BANNER_NEXT:format(b.nextAt - b.value, b.level + 1) or L.HOME_BANNER_MAX)

  local e = nextEvent()
  local c2 = p.cards[2]
  c2.ev = e
  c2.label:SetText(L.HOME_NEXT)
  if e then
    c2.value:SetText(e.name)
    local st = E.Status(e)
    c2.info:SetText(U.FormatTime(e.start) .. " · " .. L.SIGNED_N:format(E.SignCount(e)) .. " · " .. (st and L["ST_" .. st] or L.HOME_NOT_SIGNED))
  else
    c2.value:SetText(L.HOME_NONE)
    c2.info:SetText("")
  end

  local open, signed = 0, 0
  for _, ev in ipairs(E.List(function(x) return E.IsOpen(x) and ns.Profile.IsTypeActive(x.type) end)) do
    open = open + 1
    local st = E.Status(ev)
    if st and st ~= "out" then signed = signed + 1 end
  end
  local c3 = p.cards[3]
  c3.label:SetText(L.HOME_MINE)
  c3.value:SetText(L.HOME_MINE_VAL:format(signed, open))
  c3.info:SetText(open > signed and L.HOME_MINE_OPEN:format(open - signed) or "")

  local list = Pts.Entries()
  local n = 0
  for _, x in ipairs(list) do
    n = n + 1
    if n > 10 then break end
    local r = p.ledRows:Get(n)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -6 - (n - 1) * 22); r:SetPoint("RIGHT", p.ledBox, "RIGHT", 0, 0)
    local _, tag, tcol = Lg.Tag(x)
    r.tag:Set(tag, false, tcol)
    r.text:SetText(G.Display(x.who) .. U.Color(T.Hex(th.muted), " · " .. Lg.Text(x)))
    r.pts:SetText((x.amt > 0 and "+" or "") .. x.amt)
  end
  p.ledRows:HideFrom(math.min(n, 10) + 1)
  p.ledEmpty:SetShown(n == 0)

  local notes = ns.Notices.List()
  for i, nn in ipairs(notes) do
    if i > 8 then break end
    local r = p.notRows:Get(i)
    r.n = nn
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 42); r:SetPoint("RIGHT", p.notBox, "RIGHT", -6, 0)
    r.group:SetText((nn.group or "") .. "  " .. U.Color(T.Hex(th.muted), date("%d.%m. %H:%M", nn.at or U.Now())))
    r.text:SetText(nn.text or "")
  end
  p.notRows:HideFrom(math.min(#notes, 8) + 1)
  p.notEmpty:SetShown(#notes == 0)
end

UI.RegisterView("home", {
  label = function() return L.TAB_HOME end,
  build = build,
  refresh = refresh,
})
