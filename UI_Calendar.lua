local ADDON, ns = ...
-- Calendar at the bottom of the side bar: always visible, one calendar for all
-- events of the guild (core and modules). Month view: up to three dots per day
-- in the colour of the event type; week view: one line per event.
-- Mouse over a day or event shows details, a click opens the event where it
-- belongs (an event type may bring its own `open(e)` and `color`).
local U, G, T, W, UI, E = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI, ns.Events
local C = {}
ns.Calendar = C

local DOT = "Interface\\AddOns\\GuildEventManager\\Media\\cal_dot"
local CELL_H, HEAD_H, TITLE_H, BTN_H = 22, 12, 16, 18
local GRID_H = HEAD_H + 6 * CELL_H            -- the week view uses the same height
local LINE_H = 12
local HEIGHT = 6 + TITLE_H + GRID_H + 6 + BTN_H + 4

-- colours of the event types; a type may set its own `color = { r, g, b }`
local COLORS = {
  meet = { 0.56, 0.71, 0.42 },                 -- guild meeting: green
  rp = { 0.60, 0.53, 0.81 }, ritual = { 0.60, 0.53, 0.81 },   -- RP and ritual: violet
}
local MODULE_COLORS = {
  pve = { 0.85, 0.47, 0.31 },                  -- raids: orange
  pvp = { 0.79, 0.29, 0.27 },                  -- PvP: red
}
local FALLBACK = { 0.90, 0.73, 0.36 }

function C.Color(e)
  local t = ns.Modules.Type(e.type)
  if t and type(t.color) == "table" then return t.color end
  return COLORS[e.type] or (t and MODULE_COLORS[t.module]) or FALLBACK
end

-- open the event where it belongs
function C.Open(e)
  if not e then return end
  local t = ns.Modules.Type(e.type)
  if t and type(t.open) == "function" then
    local ok = pcall(t.open, e)
    if ok then return end
  end
  UI.Show("events")
  if ns.UIEvents and ns.UIEvents.OpenDetail then ns.UIEvents.OpenDetail(e) end
end

---------------------------------------------------------------------------
-- Dates (noon of a day, so summer time never shifts a day)
---------------------------------------------------------------------------
local function noon(y, m, d) return time({ year = y, month = m, day = d, hour = 12 }) end
local function dayKey(ts) return date("%Y-%m-%d", ts) end
local function weekday(ts) return (tonumber(date("%w", ts)) + 6) % 7 end   -- Monday = 0
local function addDays(ts, n)
  local t = date("*t", ts)
  return noon(t.year, t.month, t.day + n)
end
local function mondayOf(ts) return addDays(ts, -weekday(ts)) end
local function today() local t = date("*t"); return noon(t.year, t.month, t.day) end
local function split(s) local out = {}; for w in tostring(s or ""):gmatch("[^,]+") do out[#out + 1] = w end; return out end

local V = { mode = "month", cur = nil }

-- events of the days from..to (keys), sorted by time
local function eventsByDay(from, to)
  local map = {}
  local lo, hi = addDays(from, -1) - 12 * 3600, addDays(to, 1) + 12 * 3600
  for _, e in ipairs(E.List(function(x) return x.status ~= "cancelled" and x.kind ~= "season" and x.start end)) do
    if e.start >= lo and e.start < hi then
      local k = dayKey(e.start)
      map[k] = map[k] or {}
      table.insert(map[k], e)
    end
  end
  for _, list in pairs(map) do table.sort(list, function(a, b) return a.start < b.start end) end
  return map
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function addEvent(tt, e, first)
  local L, th = ns.L, T.Current()
  if not first then tt:AddLine(" ") end
  local c = C.Color(e)
  tt:AddLine(e.name or "?", c[1], c[2], c[3])
  tt:AddLine(ns.Modules.TypeName(e.type) .. " · " .. date("%H:%M", e.start), 1, 1, 1)
  if e.leader then tt:AddLine(L.CAL_LEAD:format(G.Display(e.leader)), th.muted[1], th.muted[2], th.muted[3]) end
  local n = E.SignCount(e)
  if e.gmax then tt:AddLine(L.CAL_SIGNED:format(n, e.gmax), 1, 1, 1)
  else tt:AddLine(L.SIGNED_N:format(n), 1, 1, 1) end
  local st = E.Status(e)
  if st and L["ST_" .. st] then tt:AddLine(L.CAL_YOU:format(L["ST_" .. st]), 0.6, 0.9, 0.6) end
end

local function showTip(owner, list, hint)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  for i, e in ipairs(list) do addEvent(GameTooltip, e, i == 1) end
  if hint then GameTooltip:AddLine(" "); GameTooltip:AddLine(hint, 0.6, 0.6, 0.6, true) end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function build(side)
  local th = T.Current()
  local f = CreateFrame("Frame", nil, side)
  f:SetPoint("BOTTOMLEFT", 6, 8); f:SetPoint("BOTTOMRIGHT", -6, 8)
  f:SetHeight(HEIGHT)
  f.line = f:CreateTexture(nil, "ARTWORK")
  f.line:SetHeight(1); f.line:SetPoint("TOPLEFT"); f.line:SetPoint("TOPRIGHT")
  f.title = W.Text(f, 11, "title")
  f.title:SetPoint("TOPLEFT", 2, -6); f.title:SetPoint("RIGHT", -2, 0)
  f.title:SetWordWrap(false)

  -- month view
  f.month = CreateFrame("Frame", nil, f)
  f.month:SetPoint("TOPLEFT", 0, -6 - TITLE_H); f.month:SetPoint("RIGHT"); f.month:SetHeight(GRID_H)
  f.heads, f.cells = {}, {}
  for i = 1, 7 do
    local h = W.Text(f.month, 9, "muted")
    h:SetJustifyH("CENTER")
    f.heads[i] = h
  end
  for i = 1, 42 do
    local c = CreateFrame("Button", nil, f.month, "BackdropTemplate")
    W.Paint(c, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    c.num = W.Text(c, 9, "text"); c.num:SetPoint("TOP", 0, -2); c.num:SetJustifyH("CENTER")
    c.dots = {}
    for d = 1, 3 do
      local t = c:CreateTexture(nil, "ARTWORK")
      t:SetTexture(DOT); t:SetSize(5, 5)
      c.dots[d] = t
    end
    c.plus = W.Text(c, 8, "title"); c.plus:SetText("+")
    c:SetScript("OnEnter", function(self)
      if not self.list or #self.list == 0 then return end
      local th2 = T.Current()
      self:SetBackdropColor(th2.panel2[1], th2.panel2[2], th2.panel2[3], 0.9)
      showTip(self, self.list, #self.list == 1 and ns.L.CAL_CLICK or ns.L.CAL_CLICK_DAY)
    end)
    c:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0); GameTooltip:Hide() end)
    c:SetScript("OnClick", function(self)
      if not self.list or #self.list == 0 then return end
      GameTooltip:Hide()
      if #self.list == 1 then C.Open(self.list[1])
      else V.mode, V.cur = "week", self.day; C.Refresh() end
    end)
    f.cells[i] = c
  end

  -- week view
  f.week = CreateFrame("Frame", nil, f)
  f.week:SetPoint("TOPLEFT", 0, -6 - TITLE_H); f.week:SetPoint("RIGHT"); f.week:SetHeight(GRID_H)
  f.days, f.lines = {}, {}
  for i = 1, 7 do f.days[i] = W.Text(f.week, 9, "text") end
  for i = 1, math.floor(GRID_H / LINE_H) do
    local l = CreateFrame("Button", nil, f.week)
    l:SetHeight(LINE_H)
    l.bar = l:CreateTexture(nil, "ARTWORK"); l.bar:SetWidth(3); l.bar:SetPoint("TOPLEFT", 0, -1); l.bar:SetPoint("BOTTOMLEFT", 0, 1)
    l.bar:SetColorTexture(1, 1, 1, 1)
    l.hl = l:CreateTexture(nil, "BACKGROUND"); l.hl:SetAllPoints(); l.hl:SetColorTexture(1, 1, 1, 0.08); l.hl:Hide()
    l.text = W.Text(l, 9, "text"); l.text:SetPoint("LEFT", 6, 0); l.text:SetPoint("RIGHT", -1, 0); l.text:SetWordWrap(false)
    l:SetScript("OnEnter", function(self)
      if not self.ev then return end
      self.hl:Show(); showTip(self, { self.ev }, ns.L.CAL_CLICK)
    end)
    l:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    l:SetScript("OnClick", function(self)
      GameTooltip:Hide()
      if self.ev then C.Open(self.ev)
      elseif self.day then V.mode, V.cur = "week", self.day; C.Refresh() end
    end)
    f.lines[i] = l
  end

  -- buttons: < Heute >   …   Woche/Monat (widths from the text, so all fit)
  local function small(label)
    local b = W.Button(f, label, false, BTN_H)
    return b
  end
  f.prev = small("<"); f.prev:SetWidth(20); f.prev.tip = { ns.L.CAL_PREV }
  f.prev:SetPoint("BOTTOMLEFT", 0, 0)
  f.today = small(ns.L.CAL_TODAY)
  f.today:SetPoint("LEFT", f.prev, "RIGHT", 3, 0)
  f.next = small(">"); f.next:SetWidth(20); f.next.tip = { ns.L.CAL_NEXT }
  f.next:SetPoint("LEFT", f.today, "RIGHT", 3, 0)
  f.toggle = W.Button(f, ns.L.CAL_WEEK, true, BTN_H)
  f.toggle:SetPoint("BOTTOMRIGHT", 0, 0)
  f.prev:SetScript("OnClick", function() C.Step(-1) end)
  f.next:SetScript("OnClick", function() C.Step(1) end)
  f.today:SetScript("OnClick", function() V.cur = today(); C.Refresh() end)
  f.toggle:SetScript("OnClick", function() V.mode = (V.mode == "month") and "week" or "month"; C.Refresh() end)
  f.line:SetColorTexture(th.line[1], th.line[2], th.line[3], 1)
  return f
end

function C.Step(dir)
  V.cur = V.cur or today()
  if V.mode == "month" then
    local t = date("*t", V.cur)
    V.cur = noon(t.year, t.month + dir, 1)
  else
    V.cur = addDays(V.cur, 7 * dir)
  end
  C.Refresh()
end

-- button labels can be long in some languages: fit them into the width
local function fitButtons(f)
  local L = ns.L
  W.SetLabel(f.today, L.CAL_TODAY)
  W.SetLabel(f.toggle, V.mode == "month" and L.CAL_WEEK or L.CAL_MONTH)
  local avail = f:GetWidth()
  if not avail or avail < 50 then avail = 172 end
  for _, b in ipairs({ f.today, f.toggle }) do
    b.label:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    b:SetWidth(math.floor(b.label:GetStringWidth() + 12))
  end
  local used = 20 + 3 + f.today:GetWidth() + 3 + 20 + 6 + f.toggle:GetWidth()
  if used > avail then
    local over = used - avail
    f.toggle:SetWidth(math.max(30, f.toggle:GetWidth() - math.ceil(over / 2)))
    f.today:SetWidth(math.max(30, f.today:GetWidth() - math.ceil(over / 2)))
  end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function refreshMonth(f)
  local L, th = ns.L, T.Current()
  local t = date("*t", V.cur)
  local months = split(L.CAL_MONTHS)
  f.title:SetText((months[t.month] or t.month) .. " " .. t.year)
  local w = f:GetWidth()
  if not w or w < 50 then w = 172 end
  local cw = math.floor(w / 7)
  local x0 = math.floor((w - 7 * cw) / 2)
  local d1 = split(L.CAL_DAYS1)
  for i, h in ipairs(f.heads) do
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", x0 + (i - 1) * cw, 0); h:SetWidth(cw)
    h:SetText(d1[i] or "")
  end
  local first = noon(t.year, t.month, 1)
  local start = mondayOf(first)
  local map = eventsByDay(start, addDays(start, 41))
  local tk = dayKey(today())
  for i, c in ipairs(f.cells) do
    local day = addDays(start, i - 1)
    local dt = date("*t", day)
    c.day = day
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", x0 + ((i - 1) % 7) * cw, -HEAD_H - math.floor((i - 1) / 7) * CELL_H)
    c:SetSize(cw, CELL_H)
    c.num:SetText(dt.day)
    local inMonth = dt.month == t.month
    local isToday = dayKey(day) == tk
    W.Color(c.num, isToday and "title" or (inMonth and "text" or "muted"))
    c.num:SetAlpha(inMonth and 1 or 0.55)
    c:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], isToday and 1 or 0)
    local list = map[dayKey(day)] or {}
    c.list = list
    local n = math.min(#list, 3)
    local total = n * 5 + (n - 1) * 2 + (#list > 3 and 6 or 0)
    local x = -total / 2
    for d = 1, 3 do
      local dot = c.dots[d]
      if d <= n then
        local col = C.Color(list[d])
        dot:SetVertexColor(col[1], col[2], col[3], inMonth and 1 or 0.6)
        dot:ClearAllPoints(); dot:SetPoint("BOTTOMLEFT", c, "BOTTOM", x, 3)
        dot:Show()
        x = x + 7
      else
        dot:Hide()
      end
    end
    c.plus:ClearAllPoints(); c.plus:SetPoint("BOTTOMLEFT", c, "BOTTOM", x - 1, 1)
    c.plus:SetShown(#list > 3)
  end
end

local function refreshWeek(f)
  local L = ns.L
  local mon = mondayOf(V.cur)
  local sun = addDays(mon, 6)
  f.title:SetText(date("%d.%m.", mon) .. " – " .. date("%d.%m.", sun))
  local map = eventsByDay(mon, sun)
  local d2 = split(L.CAL_DAYS2)
  local cap = #f.lines
  -- every day gets one line; the rest goes to the days with more events
  local want, alloc = {}, {}
  for i = 1, 7 do
    want[i] = #(map[dayKey(addDays(mon, i - 1))] or {})
    alloc[i] = 1
  end
  local left = cap - 7
  local changed = true
  while left > 0 and changed do
    changed = false
    for i = 1, 7 do
      if left > 0 and alloc[i] < want[i] then alloc[i] = alloc[i] + 1; left = left - 1; changed = true end
    end
  end
  local tk = dayKey(today())
  local y, li = 0, 0
  for i = 1, 7 do
    local day = addDays(mon, i - 1)
    local list = map[dayKey(day)] or {}
    local lab = f.days[i]
    lab:ClearAllPoints(); lab:SetPoint("TOPLEFT", 2, -y - 2)
    lab:SetText((d2[i] or "") .. " " .. date("%d.", day))
    W.Color(lab, dayKey(day) == tk and "title" or "muted")
    for j = 1, alloc[i] do
      li = li + 1
      local l = f.lines[li]
      if not l then break end
      l:ClearAllPoints(); l:SetPoint("TOPLEFT", 40, -y); l:SetPoint("RIGHT", f.week, "RIGHT", 0, 0)
      l.ev, l.day = nil, nil
      if #list == 0 then
        l.bar:Hide(); l.text:SetText("–"); W.Color(l.text, "muted")
      elseif j == alloc[i] and #list > alloc[i] then
        l.bar:Hide(); l.text:SetText(L.CAL_MORE:format(#list - alloc[i] + 1)); W.Color(l.text, "title")
        l.day = day
      else
        local e = list[j]
        local col = C.Color(e)
        l.bar:SetVertexColor(col[1], col[2], col[3], 1); l.bar:Show()
        l.text:SetText(date("%H:%M", e.start) .. " " .. (e.name or "?")); W.Color(l.text, "text")
        l.ev = e
      end
      l:Show()
      y = y + LINE_H
    end
  end
  for k = li + 1, #f.lines do f.lines[k]:Hide() end
end

-- show (or hide) the calendar in the side bar; navBottom = lowest y of the navigation
function C.Refresh()
  local win = UI.Frame()
  if not win or not win.side then return end
  local f = win.calendar
  local blocked = not ns.preview and (not G.InGuild() or not G.IsActivated())
  if UI.entryOf[win.current] == "settings" then blocked = true end   -- the side bar shows the settings menu
  local room = (win.side:GetHeight() or 0) + (win.navBottom or -300) - 8
  if blocked or room < HEIGHT then
    if f then f:Hide() end
    return
  end
  if not f then f = build(win.side); win.calendar = f end
  local th = T.Current()
  f.line:SetColorTexture(th.line[1], th.line[2], th.line[3], 1)
  V.cur = V.cur or today()
  fitButtons(f)
  f.month:SetShown(V.mode == "month")
  f.week:SetShown(V.mode == "week")
  if V.mode == "month" then refreshMonth(f) else refreshWeek(f) end
  f:Show()
end

C.HEIGHT = HEIGHT
C.V = V
