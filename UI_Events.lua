local ADDON, ns = ...
-- Events tab: overview, detail page, editor, attendance at the end.
local U, G, T, W, E, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.Events, ns.UI
local V = {}
local L = ns.L

local ROW_H = 44

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function kindText(k) return L["KIND_" .. (k or "short")] end
local function groupText(e)
  local g = L["GROUP_" .. (e.group or "none")]
  if e.gmin or e.gmax then g = g .. " (" .. (e.gmin or "?") .. "–" .. (e.gmax or "?") .. ")" end
  return g
end
local function statusText(e) return L["STATUS_" .. (e.status or "planned")] end

local function whenText(e)
  local now = U.Now()
  if e.status == "running" then
    if e.finish then return L.WHEN_LEFT:format(U.FormatSpan(e.finish - now)) end
    return L.WHEN_RUNNING
  end
  if e.status == "planned" then
    if (e.start or 0) > now then return U.FormatTime(e.start) .. " · " .. L.WHEN_IN:format(U.FormatSpan(e.start - now)) end
    return U.FormatTime(e.start)
  end
  return U.FormatTime(e.start)
end


---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
local function makeRow(parent)
  local th = T.Current()
  local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
  r:SetHeight(ROW_H - 4)
  W.Paint(r, th.panel2, th.line)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(30, 30); r.icon:SetPoint("LEFT", 6, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = W.Text(r, 12, "text")
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
  r.meta = W.Text(r, 10, "muted")
  r.meta:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
  r.action = W.Button(r, "", true, 22)
  r.action:SetPoint("RIGHT", -8, 0)
  r.pill = UI.Pill(r)
  r.pill:SetPoint("RIGHT", r.action, "LEFT", -8, 0)
  r:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1) end)
  r:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(th.line[1], th.line[2], th.line[3], 1) end)
  r:SetScript("OnClick", function(self) V.OpenDetail(self.ev) end)
  return r
end

local function buildList(p)
  local list = CreateFrame("Frame", nil, p)
  list:SetAllPoints()
  p.list = list
  list.head = UI.Section(list, L.EVENTS)
  list.head:SetPoint("TOPLEFT", 0, 0)
  list.new = W.Button(list, L.NEW_EVENT, true, 22)
  list.new:SetPoint("TOPRIGHT", 0, 4)
  list.new:SetScript("OnClick", function() V.OpenEditor(nil) end)
  list.head.line:SetPoint("RIGHT", list.new, "LEFT", -8, 0)
  list.scroll = W.Scroll(list)
  list.scroll:SetPoint("TOPLEFT", 0, -26); list.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
  list.rows = W.Pool(list.scroll.content, makeRow)
  list.heads = W.Pool(list.scroll.content, function(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(22)
    h.text = UI.Section(h, "")
    h.text:SetPoint("LEFT", 0, -2)
    return h
  end)
  list.empty = W.Text(list.scroll.content, 12, "muted")
  list.empty:SetPoint("TOPLEFT", 4, -8); list.empty:SetPoint("RIGHT", list.scroll.content, "RIGHT", -4, 0)
end

local function refreshList(p)
  local list = p.list
  local manager = G.IsManager()
  list.new:SetShown(manager)
  local groups = {
    { L.SEC_RUNNING, function(e) return e.status == "running" and e.kind ~= "season" end },
    { L.SEC_PLANNED, function(e) return e.status == "planned" and e.kind ~= "season" end },
    { L.SEC_SEASON, function(e) return E.IsOpen(e) and e.kind == "season" end },
    { L.SEC_PAST, function(e) return not E.IsOpen(e) and (U.Now() - (e.start or 0)) < 30 * 86400 end },
  }
  local y, nr, nh = 0, 0, 0
  local content = list.scroll.content
  for _, g in ipairs(groups) do
    local items = E.List(function(e) return g[2](e) and ns.Profile.IsTypeActive(e.type) end)
    if #items > 0 then
      nh = nh + 1
      local h = list.heads:Get(nh)
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetPoint("RIGHT", content, "RIGHT", 0, 0)
      h.text:SetText(g[1])
      y = y + 24
      for i, e in ipairs(items) do
        if g[1] == L.SEC_PAST and i > 10 then break end
        nr = nr + 1
        local r = list.rows:Get(nr)
        r.ev = e
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", content, "RIGHT", -2, 0)
        r.icon:SetTexture(E.Icon(e))
        r.name:SetText(e.name .. (E.TypeMissing(e) and ("  " .. U.Color(U.WARN, L.MODULE_MISSING)) or ""))
        r.meta:SetText(table.concat({ ns.Modules.TypeName(e.type), kindText(e.kind), groupText(e), whenText(e),
          L.SIGNED_N:format(E.SignCount(e)) }, " · "))
        local signed = E.IsSigned(e)
        if E.IsOpen(e) then
          r.pill:Set(signed and L.SIGNED or (e.status == "running" and statusText(e) or nil), e.status == "running")
          W.SetLabel(r.action, signed and L.SIGN_OFF or L.SIGN_ON)
          r.action:Show()
          r.action:SetScript("OnClick", function() E.SignUp(e, not E.IsSigned(e)) end)
        else
          r.pill:Set(statusText(e), false)
          r.action:Hide()
        end
        r.pill:ClearAllPoints()
        if r.action:IsShown() then r.pill:SetPoint("RIGHT", r.action, "LEFT", -8, 0) else r.pill:SetPoint("RIGHT", -8, 0) end
        y = y + ROW_H
      end
      y = y + 6
    end
  end
  list.rows:HideFrom(nr + 1)
  list.heads:HideFrom(nh + 1)
  list.empty:SetShown(nr == 0)
  list.empty:SetText(manager and L.NO_EVENTS_MANAGER or L.NO_EVENTS)
  list.scroll:SetContentHeight(y)
end

---------------------------------------------------------------------------
-- Detail
---------------------------------------------------------------------------
local function buildDetail(p)
  local d = CreateFrame("Frame", nil, p)
  d:SetAllPoints()
  d:Hide()
  p.detail = d
  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(40, 40); d.icon:SetPoint("TOPLEFT", 0, 0)
  d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  d.name = W.Text(d, 16, "title")
  d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -2)
  d.pills = {}
  for i = 1, 6 do
    d.pills[i] = UI.Pill(d)
    if i == 1 then d.pills[i]:SetPoint("BOTTOMLEFT", d.icon, "BOTTOMRIGHT", 10, 0)
    else d.pills[i]:SetPoint("LEFT", d.pills[i - 1], "RIGHT", 4, 0) end
  end
  d.back = W.Button(d, L.BACK, false, 22)
  d.back:SetPoint("TOPRIGHT", 0, 0)
  d.back:SetScript("OnClick", function() V.ShowList() end)
  d.sign = W.Button(d, L.SIGN_ON, true, 22)
  d.sign:SetPoint("RIGHT", d.back, "LEFT", -6, 0)

  d.left = CreateFrame("Frame", nil, d)
  d.left:SetPoint("TOPLEFT", 0, -54); d.left:SetPoint("BOTTOMLEFT", 0, 34)
  d.left:SetPoint("RIGHT", d, "CENTER", -8, 0)
  local s1 = UI.Section(d.left, L.ABOUT); s1:SetPoint("TOPLEFT", 0, 0)
  d.desc = W.Text(d.left, 11, "text")
  d.desc:SetPoint("TOPLEFT", 0, -22); d.desc:SetPoint("RIGHT", 0, 0)
  d.desc:SetSpacing(3)
  d.facts = W.Text(d.left, 11, "muted")
  d.facts:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -12); d.facts:SetPoint("RIGHT", 0, 0)
  d.facts:SetSpacing(4)
  d.goalHead = UI.Section(d.left, L.GOALS)
  d.goalHead:SetPoint("TOPLEFT", d.facts, "BOTTOMLEFT", 0, -14)
  d.goalChecks = W.Pool(d.left, function(parent) return W.Check(parent, "") end)

  d.right = CreateFrame("Frame", nil, d)
  d.right:SetPoint("TOPLEFT", d, "TOP", 8, -54); d.right:SetPoint("BOTTOMRIGHT", 0, 34)
  d.signHead = UI.Section(d.right, L.SIGNUPS); d.signHead:SetPoint("TOPLEFT", 0, 0)
  d.signBox = W.Box(d.right, 10, 10, "panel2")
  d.signBox:SetPoint("TOPLEFT", 0, -22); d.signBox:SetPoint("BOTTOMRIGHT", 0, 0)
  d.signScroll = W.Scroll(d.signBox)
  d.signScroll:SetPoint("TOPLEFT", 6, -6); d.signScroll:SetPoint("BOTTOMRIGHT", -6, 6)
  d.signText = W.Text(d.signScroll.content, 11, "text")
  d.signText:SetPoint("TOPLEFT", 0, 0); d.signText:SetPoint("RIGHT", 0, 0)
  d.signText:SetSpacing(3)

  -- manager actions
  d.mgr = {}
  local function act(key, fn)
    local b = W.Button(d, L[key], key == "ACT_START" or key == "ACT_END", 22)
    b:SetScript("OnClick", function() if d.ev then fn(d.ev) end end)
    d.mgr[#d.mgr + 1] = b
    return b
  end
  d.bStart = act("ACT_START", function(e) E.Start(e) end)
  d.bEnd = act("ACT_END", function(e) V.OpenAttendance(e) end)
  d.bEdit = act("ACT_EDIT", function(e) V.OpenEditor(e) end)
  d.bCopy = act("ACT_COPY", function(e) V.OpenEditor(nil, e) end)
  d.bCancel = act("ACT_CANCEL", function(e)
    W.Dialog({ text = L.CONFIRM_CANCEL:format(e.name), onAccept = function() E.Cancel(e) end })
  end)
end

local function refreshDetail(p)
  local d = p.detail
  local e = d.ev and E.Get(d.ev.id) or d.ev
  if not e then V.ShowList(); return end
  d.ev = e
  d.icon:SetTexture(E.Icon(e))
  d.name:SetText(e.name)
  local t = ns.Modules.Type(e.type)
  local mod = t and ns.Modules.modules[t.module]
  local vals = {
    { ns.Modules.TypeName(e.type) },
    { mod and (mod.name or L[mod.nameKey]) or L.MODULE_MISSING },
    { groupText(e) },
    { L.LEADER:format(G.Display(e.leader)) },
    { statusText(e), e.status == "running" },
    { kindText(e.kind) },
  }
  for i, pl in ipairs(d.pills) do pl:Set(vals[i][1], vals[i][2]) end
  d.desc:SetText((e.desc and e.desc ~= "") and e.desc or (t and t.descKey and L[t.descKey]) or "")
  local facts = {
    L.FACT_START:format(U.FormatTime(e.start)),
  }
  if e.finish then facts[#facts + 1] = L.FACT_END:format(U.FormatTime(e.finish)) end
  local pr = ns.Profile.Get().pts
  facts[#facts + 1] = L.FACT_POINTS:format(tonumber(e.pts) or pr.participate, pr.lead, pr.leadMin)
  if e.status == "done" then
    local n = 0
    for _ in pairs(e.attended or {}) do n = n + 1 end
    facts[#facts + 1] = L.FACT_ATTENDED:format(n)
  end
  local done, total = E.GoalCount(e)
  if total > 0 then facts[#facts + 1] = L.FACT_GOALS:format(pr.goal or 5) end
  d.facts:SetText(table.concat(facts, "\n"))
  d.goalHead:SetShown(total > 0)
  d.goalHead:SetText(L.GOALS .. "  " .. L.GOALS_DONE:format(done, total))
  local manager = G.IsManager()
  for i, g in ipairs(e.goals or {}) do
    local c = d.goalChecks:Get(i)
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", d.goalHead, "BOTTOMLEFT", 2, -8 - (i - 1) * 20)
    c.text:SetText(g.text)
    c:SetChecked(g.done)
    c:SetEnabled(manager and E.IsOpen(e))
    c:SetScript("OnClick", function() E.ToggleGoal(e, i) end)
  end
  d.goalChecks:HideFrom(total + 1)

  local names = {}
  for key, s in pairs(e.signups or {}) do if s.on then names[#names + 1] = G.Display(key) end end
  table.sort(names)
  d.signHead:SetText(L.SIGNUPS .. " (" .. #names .. ")")
  d.signText:SetText(#names > 0 and table.concat(names, "\n") or L.NO_SIGNUPS)
  d.signScroll:SetContentHeight(d.signText:GetStringHeight() + 4)

  local open = E.IsOpen(e)
  d.sign:SetShown(open)
  W.SetLabel(d.sign, E.IsSigned(e) and L.SIGN_OFF or L.SIGN_ON)
  d.sign:SetScript("OnClick", function() E.SignUp(e, not E.IsSigned(e)) end)

  local manager = G.IsManager()
  local x = 0
  for _, b in ipairs(d.mgr) do
    local show = manager and open
    if b == d.bStart then show = show and e.status == "planned" end
    if b == d.bCopy then show = manager and e.kind ~= "season" end
    b:SetShown(show)
    if show then
      b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", x, 0)
      x = x + b:GetWidth() + 6
    end
  end
end

---------------------------------------------------------------------------
-- Editor
---------------------------------------------------------------------------
-- The editor has three steps on one page: what (type tiles, name), when (day
-- chips, time, duration chips) and who (group size chips, points), plus goals
-- as a list. The right column holds the description and a live preview of the
-- event as members will see it. Start, end and kind are derived from the chips,
-- so nobody has to know a date format.
local function label(parent, text, anchor, x, y)
  local fs = W.Text(parent, 10, "muted")
  fs:SetText(text)
  fs:SetPoint("TOPLEFT", anchor or parent, anchor and "BOTTOMLEFT" or "TOPLEFT", x or 0, y or 0)
  return fs
end

local DAY = 86400
local TILE_W, TILE_H, TILE_GAP = 124, 44, 6
local DURS = { "1h", "2h", "3h", "open", "days", "weeks", "season" }
local SIZES = {
  { id = "all", group = "none" },
  { id = "party", group = "party", gmin = 2, gmax = 5 },
  { id = "raid10", group = "raid", gmin = 6, gmax = 10 },
  { id = "raid25", group = "raid", gmin = 10, gmax = 25 },
  { id = "raid40", group = "raid", gmin = 10, gmax = 40 },
  { id = "teams", group = "teams" },
}

local function midnight(ts)
  local t = date("*t", ts)
  return time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end
local function addDays(day, n)
  local t = date("*t", day)
  return time({ year = t.year, month = t.month, day = t.day + n, hour = 0, min = 0, sec = 0 })
end

-- editor state <-> event fields
local function stateFromEvent(f)
  local st = { hour = 20, min = 0, dur = "2h", n = 3, size = "all" }
  local start = f.start or (U.Now() + 3600)
  local t = date("*t", start)
  st.day, st.hour, st.min = midnight(start), t.hour, t.min
  if f.kind == "season" then st.dur = "season"
  elseif f.kind == "multiweek" then st.dur = "weeks"; st.n = math.max(2, math.floor(((f.finish or start) - start) / (7 * DAY) + 0.5))
  elseif f.kind == "multiday" then st.dur = "days"; st.n = math.max(2, math.floor(((f.finish or start) - start) / DAY + 0.5))
  elseif not f.finish then st.dur = "open"
  else
    local h = (f.finish - start) / 3600
    if h == 1 or h == 2 or h == 3 then st.dur = h .. "h" else st.dur = "custom"; st.secs = f.finish - start end
  end
  for _, sz in ipairs(SIZES) do
    if sz.group == (f.group or "none") and sz.gmin == f.gmin and sz.gmax == f.gmax then st.size = sz.id end
  end
  if st.size == "all" and (f.group ~= "none" or f.gmin or f.gmax) then st.size = "custom" end
  return st
end

local function applyState(f, st)
  local d = date("*t", st.day)
  f.start = time({ year = d.year, month = d.month, day = d.day, hour = st.hour, min = st.min, sec = 0 })
  local dur = st.dur
  if dur == "season" then f.kind = "season"; f.finish = nil
  elseif dur == "weeks" then f.kind = "multiweek"; f.finish = f.start + st.n * 7 * DAY
  elseif dur == "days" then f.kind = "multiday"; f.finish = f.start + st.n * DAY
  elseif dur == "open" then f.kind = "short"; f.finish = nil
  elseif dur == "custom" then f.kind = "short"; f.finish = f.start + (st.secs or 7200)
  else f.kind = "short"; f.finish = f.start + tonumber(dur:sub(1, 1)) * 3600 end
end

local function dayLabel(day, i)
  if i == 0 then return L.ED_TODAY end
  if i == 1 then return L.ED_TOMORROW end
  local t = date("*t", day)
  return L["WD_" .. t.wday] .. " " .. t.day .. "."
end

local function buildEditor(p)
  local ed = CreateFrame("Frame", nil, p)
  ed:SetAllPoints()
  ed:Hide()
  p.editor = ed
  ed.title = W.Text(ed, 16, "title")
  ed.title:SetPoint("TOPLEFT", 0, 0)
  ed.cancel = W.Button(ed, CANCEL or "Cancel", false, 22)
  ed.cancel:SetPoint("TOPRIGHT", 0, 0)
  ed.cancel:SetScript("OnClick", function() if ed.ev then V.OpenDetail(ed.ev) else V.ShowList() end end)
  ed.save = W.Button(ed, L.ANNOUNCE, true, 22)
  ed.save:SetPoint("RIGHT", ed.cancel, "LEFT", -6, 0)
  ed.err = W.Text(ed, 11, { 1, 0.45, 0.35 })
  ed.err:SetPoint("RIGHT", ed.save, "LEFT", -10, 0)

  -- left: scrolling form
  local LEFT_W = 4 * TILE_W + 3 * TILE_GAP + 4
  local scroll = W.Scroll(ed)
  scroll:SetPoint("TOPLEFT", 0, -32); scroll:SetPoint("BOTTOMLEFT", 0, 0); scroll:SetWidth(LEFT_W + 8)
  ed.scroll = scroll
  local col = scroll.content
  col:SetWidth(LEFT_W + 8)
  ed.col = col

  -- 1 · what
  ed.s1 = UI.Section(col, L.ED_WHAT); ed.s1:SetPoint("TOPLEFT", 0, 0); ed.s1:SetWidth(LEFT_W)
  ed.tiles = W.Pool(col, function(parent)
    local th = T.Current()
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(TILE_W, TILE_H)
    W.Paint(b, th.panel2, th.line)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(28, 28); b.icon:SetPoint("LEFT", 7, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.name = W.Text(b, 10, "text")
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0); b.name:SetPoint("RIGHT", -5, 0)
    b.name:SetMaxLines(2); b.name:SetSpacing(1)
    function b:SetSelected(on)
      self.selected = on
      local bd = on and th.title or th.line
      self:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
      local bg = on and th.panel or th.panel2
      self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
      W.Color(self.name, on and "title" or "text")
    end
    b:SetScript("OnEnter", function(self)
      self:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1)
      if self.tipTitle then
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.tipTitle, 1, 0.82, 0)
        if self.tipText then GameTooltip:AddLine(self.tipText, 1, 1, 1, true) end
        GameTooltip:Show()
      end
    end)
    b:SetScript("OnLeave", function(self) self:SetSelected(self.selected); GameTooltip:Hide() end)
    return b
  end)
  ed.typeDesc = W.Text(col, 10, "muted")
  ed.typeDesc:SetWidth(LEFT_W); ed.typeDesc:SetSpacing(2)
  ed.lName = W.Text(col, 10, "muted")
  ed.name = W.Edit(col, LEFT_W, 22)
  ed.name:SetMaxLetters(60)
  ed.name:SetScript("OnTextChanged", function() if ed.f then V.EditorPreview() end end)

  -- 2 · when
  ed.s2 = UI.Section(col, L.ED_WHEN); ed.s2:SetWidth(LEFT_W)
  ed.lDay = W.Text(col, 10, "muted"); ed.lDay:SetText(L.ED_DAY)
  ed.days = {}
  local cw = math.floor((LEFT_W - 7 * 4) / 8)
  for i = 0, 7 do
    local c = W.Chip(col, "", cw, 22)
    c.index = i
    c:SetScript("OnClick", function(self)
      if self.index == 7 then
        ed.st.custom = true
        ed.dateEdit:Show(); ed.dateEdit:SetFocus()
      else
        ed.st.custom = false
        ed.st.day = addDays(midnight(U.Now()), self.index)
        ed.dateEdit:Hide()
      end
      V.EditorRefresh()
    end)
    ed.days[i] = c
  end
  ed.days[7].label:SetText(L.ED_OTHER_DATE)
  ed.dateEdit = W.Edit(col, 110, 22)
  ed.dateEdit:SetMaxLetters(10)
  ed.dateEdit:Hide()
  ed.dateHint = W.Text(col, 10, "muted"); ed.dateHint:SetText(L.ED_DATE_HINT)
  ed.dateEdit:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local d, m, y = self:GetText():match("^(%d+)%.(%d+)%.?(%d*)$")
    if d then
      local now = date("*t", U.Now())
      y = tonumber(y) or now.year
      if y < 100 then y = y + 2000 end
      local ts = time({ year = y, month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 })
      local back = date("*t", ts)
      if back.day == tonumber(d) and back.month == tonumber(m) then ed.st.day = ts; ed.st.badDate = false
      else ed.st.badDate = true end
    else
      ed.st.badDate = self:GetText() ~= ""
    end
    V.EditorRefresh()
  end)
  ed.lTime = W.Text(col, 10, "muted"); ed.lTime:SetText(L.ED_TIME)
  ed.hour = W.Dropdown(col, 64, function()
    local o = {}
    for h = 0, 23 do o[#o + 1] = { h, ("%02d"):format(h) } end
    return o
  end, function() return ed.st and ed.st.hour end, function(v) ed.st.hour = v; V.EditorRefresh() end)
  ed.colon = W.Text(col, 12, "text"); ed.colon:SetText(":")
  ed.minute = W.Dropdown(col, 64, function()
    local o, seen = {}, {}
    for _, m in ipairs({ 0, 15, 30, 45 }) do o[#o + 1] = { m, ("%02d"):format(m) }; seen[m] = true end
    if ed.st and not seen[ed.st.min] then table.insert(o, { ed.st.min, ("%02d"):format(ed.st.min) }) end
    return o
  end, function() return ed.st and ed.st.min end, function(v) ed.st.min = v; V.EditorRefresh() end)
  ed.lDur = W.Text(col, 10, "muted"); ed.lDur:SetText(L.ED_DURATION)
  ed.durs = {}
  local dw = math.floor((LEFT_W - 6 * 4) / 7)
  for i, id in ipairs(DURS) do
    local c = W.Chip(col, L["ED_DUR_" .. id], dw, 22)
    c.tip = { L["ED_DUR_" .. id], L["ED_DUR_" .. id .. "_TIP"] }
    c:SetScript("OnClick", function()
      ed.st.dur = id
      if id == "days" and (ed.st.n < 2 or ed.st.n > 14) then ed.st.n = 3 end
      if id == "weeks" and (ed.st.n < 2 or ed.st.n > 8) then ed.st.n = 2 end
      V.EditorRefresh()
    end)
    ed.durs[i] = c
  end
  ed.count = W.Dropdown(col, 120, function()
    local o = {}
    if ed.st and ed.st.dur == "weeks" then
      for n = 2, 8 do o[#o + 1] = { n, L.ED_N_WEEKS:format(n) } end
    else
      for n = 2, 14 do o[#o + 1] = { n, L.ED_N_DAYS:format(n) } end
    end
    return o
  end, function() return ed.st and ed.st.n end, function(v) ed.st.n = v; V.EditorRefresh() end)
  ed.whenLine = W.Text(col, 11, "title")
  ed.whenLine:SetWidth(LEFT_W)

  -- 3 · who
  ed.s3 = UI.Section(col, L.ED_WHO); ed.s3:SetWidth(LEFT_W)
  ed.sizes = {}
  local sw = math.floor((LEFT_W - 5 * 4) / 6)
  for i, sz in ipairs(SIZES) do
    local c = W.Chip(col, L["ED_SIZE_" .. sz.id], sw, 22)
    c:SetScript("OnClick", function()
      ed.st.size = sz.id
      ed.f.group, ed.f.gmin, ed.f.gmax = sz.group, sz.gmin, sz.gmax
      ed.gmin:SetText(sz.gmin and tostring(sz.gmin) or "")
      ed.gmax:SetText(sz.gmax and tostring(sz.gmax) or "")
      V.EditorRefresh()
    end)
    ed.sizes[i] = c
  end
  ed.lMin = W.Text(col, 10, "muted"); ed.lMin:SetText(L.F_GMIN)
  ed.gmin = W.Edit(col, 60, 22); ed.gmin:SetNumeric(true); ed.gmin:SetMaxLetters(2)
  ed.lMax = W.Text(col, 10, "muted"); ed.lMax:SetText(L.F_GMAX)
  ed.gmax = W.Edit(col, 60, 22); ed.gmax:SetNumeric(true); ed.gmax:SetMaxLetters(2)
  ed.lPts = W.Text(col, 10, "muted")
  ed.pts = W.Edit(col, 60, 22); ed.pts:SetNumeric(true); ed.pts:SetMaxLetters(3)
  for _, e in ipairs({ ed.gmin, ed.gmax, ed.pts }) do
    e:SetScript("OnTextChanged", function(_, user) if user and ed.f then V.EditorPreview() end end)
  end

  -- 4 · goals
  ed.s4 = UI.Section(col, L.ED_GOALS); ed.s4:SetWidth(LEFT_W)
  ed.goalHint = W.Text(col, 10, "muted"); ed.goalHint:SetWidth(LEFT_W)
  ed.goalRows = W.Pool(col, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(LEFT_W, 24)
    r.edit = W.Edit(r, LEFT_W - 30, 22)
    r.edit:SetPoint("LEFT", 0, 0)
    r.edit:SetMaxLetters(60)
    r.del = W.Button(r, "x", false, 22); r.del:SetWidth(24)
    r.del:SetPoint("LEFT", r.edit, "RIGHT", 6, 0)
    r.edit:SetScript("OnTextChanged", function(self, user)
      if user and ed.goals then ed.goals[r.index] = self:GetText(); ed.goalsTouched = true; V.EditorPreview() end
    end)
    r.del:SetScript("OnClick", function()
      table.remove(ed.goals, r.index); ed.goalsTouched = true; V.EditorRefresh()
    end)
    return r
  end)
  ed.addGoal = W.Button(col, L.ED_ADD_GOAL, false, 22)
  ed.addGoal:SetScript("OnClick", function()
    if #ed.goals >= 8 then return end
    ed.goals[#ed.goals + 1] = ""; ed.goalsTouched = true
    V.EditorRefresh()
    local r = ed.goalRows.items[#ed.goals]
    if r then r.edit:SetFocus() end
  end)

  -- right: description and preview
  local right = CreateFrame("Frame", nil, ed)
  right:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 14, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
  local s5 = UI.Section(right, L.F_DESC); s5:SetPoint("TOPLEFT", 0, 0)
  local box = W.Box(right, 10, 10, "panel2")
  box:SetPoint("TOPLEFT", 0, -24); box:SetPoint("RIGHT", 0, 0); box:SetHeight(120)
  ed.desc = W.Edit(box, 10, 110, true)
  ed.desc:SetPoint("TOPLEFT", 4, -4); ed.desc:SetPoint("BOTTOMRIGHT", -4, 4)
  ed.desc:SetMaxLetters(500)
  ed.desc:SetScript("OnTextChanged", function(_, user) if user and ed.f then V.EditorPreview() end end)
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() ed.desc:SetFocus() end)
  ed.descHint = W.Text(right, 10, "muted")
  ed.descHint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -5); ed.descHint:SetPoint("RIGHT", 0, 0)
  ed.descHint:SetText(L.DESC_HINT)
  local s6 = UI.Section(right, L.ED_PREVIEW)
  s6:SetPoint("TOPLEFT", ed.descHint, "BOTTOMLEFT", 0, -14)
  ed.card = makeRow(right)
  ed.card:SetPoint("TOPLEFT", s6, "BOTTOMLEFT", 0, -8); ed.card:SetPoint("RIGHT", right, "RIGHT", 0, 0)
  ed.card:EnableMouse(false)
  ed.card.action:EnableMouse(false)
  ed.card.meta:SetPoint("RIGHT", ed.card.action, "LEFT", -6, 0)
  ed.card.meta:SetWordWrap(false)
  ed.card.name:SetPoint("RIGHT", ed.card.action, "LEFT", -6, 0)
  ed.card.name:SetWordWrap(false)
  ed.previewText = W.Text(right, 10, "muted")
  ed.previewText:SetPoint("TOPLEFT", ed.card, "BOTTOMLEFT", 2, -8); ed.previewText:SetPoint("RIGHT", 0, 0)
  ed.previewText:SetSpacing(3)
  ed.previewText:SetMaxLines(8)

  ed.save:SetScript("OnClick", function() V.SaveEditor() end)
end

-- Places all form parts below each other; parts that are not needed stay hidden.
function V.EditorRefresh()
  local ed = V.panel.editor
  local col, f, st = ed.col, ed.f, ed.st
  local y = 0
  local function at(fr, x, dy) fr:ClearAllPoints(); fr:SetPoint("TOPLEFT", col, "TOPLEFT", x or 0, -(y + (dy or 0))) end

  -- 1 · what
  at(ed.s1); y = y + 24
  local types = {}
  for _, t in ipairs(ns.Modules.AllTypes()) do
    if not t.missing and ns.Profile.IsTypeActive(t.id) then types[#types + 1] = t end
  end
  for i, t in ipairs(types) do
    local b = ed.tiles:Get(i)
    local cx, cy = (i - 1) % 4, math.floor((i - 1) / 4)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", col, "TOPLEFT", cx * (TILE_W + TILE_GAP), -(y + cy * (TILE_H + TILE_GAP)))
    b.icon:SetTexture(t.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.name:SetText(ns.Modules.TypeName(t.id))
    b.tipTitle, b.tipText = ns.Modules.TypeName(t.id), t.descKey and L[t.descKey] or nil
    b:SetSelected(f.type == t.id)
    b:SetScript("OnClick", function() V.EditorPickType(t.id) end)
  end
  ed.tiles:HideFrom(#types + 1)
  y = y + math.ceil(#types / 4) * (TILE_H + TILE_GAP) + 2
  local t = ns.Modules.Type(f.type)
  ed.typeDesc:SetText(t and t.descKey and L[t.descKey] or "")
  at(ed.typeDesc); y = y + ed.typeDesc:GetStringHeight() + 10
  ed.lName:SetText(L.ED_NAME:format(ns.Modules.TypeName(f.type)))
  at(ed.lName); y = y + 14
  at(ed.name); y = y + 22 + 16

  -- 2 · when
  at(ed.s2); y = y + 24
  local season = st.dur == "season"
  for _, c in pairs(ed.days) do c:SetEnabled(not season) end
  ed.hour:SetEnabled(not season); ed.minute:SetEnabled(not season)
  if not season then
    at(ed.lDay); y = y + 14
    local today = midnight(U.Now())
    local cw = ed.days[0]:GetWidth()
    for i = 0, 7 do
      local c = ed.days[i]
      at(c, i * (cw + 4))
      if i < 7 then
        local d = addDays(today, i)
        c.label:SetText(dayLabel(d, i))
        c:SetSelected(not st.custom and st.day == d)
      else
        c:SetSelected(st.custom and true or false)
      end
      c:Show()
    end
    y = y + 26
    ed.dateEdit:SetShown(st.custom and true or false)
    ed.dateHint:SetShown(st.custom and true or false)
    if st.custom then
      at(ed.dateEdit); ed.dateHint:ClearAllPoints(); ed.dateHint:SetPoint("LEFT", ed.dateEdit, "RIGHT", 8, 0)
      W.Color(ed.dateEdit, st.badDate and { 1, 0.45, 0.35 } or "text")
      y = y + 26
    end
    at(ed.lTime, 0, 4); y = y + 18
    at(ed.hour); ed.colon:ClearAllPoints(); ed.colon:SetPoint("LEFT", ed.hour, "RIGHT", 6, 0)
    ed.minute:ClearAllPoints(); ed.minute:SetPoint("LEFT", ed.colon, "RIGHT", 6, 0)
    ed.hour:Show(); ed.minute:Show(); ed.colon:Show()
    ed.hour:Refresh(); ed.minute:Refresh()
    y = y + 30
  else
    for _, c in pairs(ed.days) do c:Hide() end
    ed.lDay:Hide(); ed.lTime:Hide(); ed.dateEdit:Hide(); ed.dateHint:Hide()
    ed.hour:Hide(); ed.minute:Hide(); ed.colon:Hide()
  end
  if not season then ed.lDay:Show(); ed.lTime:Show() end
  at(ed.lDur); y = y + 14
  local dw = ed.durs[1]:GetWidth()
  for i, id in ipairs(DURS) do
    at(ed.durs[i], (i - 1) * (dw + 4))
    ed.durs[i]:SetSelected(st.dur == id)
  end
  y = y + 26
  local multi = st.dur == "days" or st.dur == "weeks"
  ed.count:SetShown(multi)
  if multi then at(ed.count); ed.count:Refresh(); y = y + 28 end
  applyState(f, st)
  local when
  if season then
    when = L.ED_WHEN_SEASON:format(U.FormatTime(ns.Points.SeasonStart()), U.FormatTime(ns.Points.SeasonEnd()))
  elseif f.finish then
    when = U.FormatTime(f.start) .. " – " .. U.FormatTime(f.finish)
  else
    when = U.FormatTime(f.start) .. " · " .. L.ED_DUR_open
  end
  if st.badDate then when = L.ED_BAD_DATE end
  ed.whenLine:SetText(when)
  at(ed.whenLine, 0, 2); y = y + ed.whenLine:GetStringHeight() + 18

  -- 3 · who
  at(ed.s3); y = y + 24
  local sw = ed.sizes[1]:GetWidth()
  for i, sz in ipairs(SIZES) do
    at(ed.sizes[i], (i - 1) * (sw + 4))
    ed.sizes[i]:SetSelected(st.size == sz.id)
  end
  y = y + 30
  at(ed.lMin); ed.lMax:ClearAllPoints(); ed.lMax:SetPoint("TOPLEFT", ed.lMin, "TOPLEFT", 80, 0)
  ed.lPts:ClearAllPoints(); ed.lPts:SetPoint("TOPLEFT", ed.lMin, "TOPLEFT", 170, 0)
  local pr = ns.Profile.Get().pts
  ed.lPts:SetText(L.ED_POINTS:format(pr.participate or 10))
  y = y + 14
  at(ed.gmin); at(ed.gmax, 80); at(ed.pts, 170)
  y = y + 22 + 16

  -- 4 · goals
  at(ed.s4); y = y + 24
  ed.goalHint:SetText(L.ED_GOALS_HINT:format(pr.goal or 5))
  at(ed.goalHint); y = y + ed.goalHint:GetStringHeight() + 6
  for i, g in ipairs(ed.goals) do
    local r = ed.goalRows:Get(i)
    r.index = i
    if r.edit:GetText() ~= g then r.edit:SetText(g) end
    at(r); y = y + 26
  end
  ed.goalRows:HideFrom(#ed.goals + 1)
  ed.addGoal:SetShown(#ed.goals < 8)
  if #ed.goals < 8 then at(ed.addGoal); y = y + 26 end
  ed.scroll:SetContentHeight(y + 8)
  V.EditorPreview()
end

function V.EditorPickType(id)
  local ed = V.panel.editor
  local f = ed.f
  local old = ns.Modules.TypeName(f.type)
  f.type = id
  local t = ns.Modules.Type(id)
  if t and not ed.ev then
    -- suggest the type's own group size and duration for a new event
    if t.kind == "season" then ed.st.dur = "season"
    elseif t.kind == "multiday" and ed.st.dur ~= "days" then ed.st.dur = "days"; ed.st.n = 3
    elseif t.kind == "multiweek" and ed.st.dur ~= "weeks" then ed.st.dur = "weeks"; ed.st.n = 2
    elseif t.kind == "short" and (ed.st.dur == "days" or ed.st.dur == "weeks" or ed.st.dur == "season") then ed.st.dur = "2h" end
    for _, sz in ipairs(SIZES) do
      if sz.group == (t.group or "none") and (t.gmin == nil or sz.gmin == t.gmin) then
        ed.st.size = sz.id; f.group, f.gmin, f.gmax = sz.group, t.gmin or sz.gmin, t.gmax or sz.gmax; break
      end
    end
    ed.gmin:SetText(f.gmin and tostring(f.gmin) or ""); ed.gmax:SetText(f.gmax and tostring(f.gmax) or "")
  end
  if not ed.goalsTouched then
    ed.goals = {}
    for _, k in ipairs(t and t.goalKeys or {}) do ed.goals[#ed.goals + 1] = L[k] end
  end
  local cur = ed.name:GetText()
  if cur == "" or cur == old then ed.name:SetText("") end
  V.EditorRefresh()
end

-- Card and text as members will see the event
function V.EditorPreview()
  local ed = V.panel.editor
  local f = ed.f
  local name = ed.name:GetText()
  if name == "" then name = ns.Modules.TypeName(f.type) end
  local pv = {
    type = f.type, kind = f.kind, group = f.group,
    gmin = tonumber(ed.gmin:GetText()), gmax = tonumber(ed.gmax:GetText()),
    start = f.kind == "season" and ns.Points.SeasonStart() or f.start, finish = f.finish, status = "planned",
  }
  local c = ed.card
  c.icon:SetTexture(E.Icon(pv))
  c.name:SetText(name)
  c.meta:SetText(table.concat({ ns.Modules.TypeName(pv.type), kindText(pv.kind), groupText(pv), whenText(pv) }, " · "))
  W.SetLabel(c.action, L.SIGN_ON)
  c.pill:Set(nil)
  local pr = ns.Profile.Get().pts
  local lines = {}
  local desc = ed.desc:GetText()
  if desc == "" then local t = ns.Modules.Type(f.type); desc = t and t.descKey and L[t.descKey] or "" end
  if desc ~= "" then lines[#lines + 1] = U.Color("ffffffff", desc) end
  lines[#lines + 1] = L.FACT_POINTS:format(tonumber(ed.pts:GetText()) or pr.participate, pr.lead, pr.leadMin)
  local n = 0
  for _, g in ipairs(ed.goals or {}) do if g:gsub("%s", "") ~= "" then n = n + 1 end end
  if n > 0 then lines[#lines + 1] = L.ED_PREVIEW_GOALS:format(n, pr.goal or 5) end
  ed.previewText:SetText(table.concat(lines, "\n"))
end

function V.SaveEditor()
  local ed = V.panel.editor
  ed.err:SetText("")
  local f, st = ed.f, ed.st
  if not f.type then ed.err:SetText(L.ERR_TYPE); return end
  if st.badDate then ed.err:SetText(L.ED_BAD_DATE); return end
  applyState(f, st)
  if f.kind ~= "season" and not ed.ev and f.start < U.Now() - 300 then ed.err:SetText(L.ED_ERR_PAST); return end
  f.name = ed.name:GetText()
  if f.name == "" then f.name = ns.Modules.TypeName(f.type) end
  f.desc = ed.desc:GetText()
  f.gmin = tonumber(ed.gmin:GetText())
  f.gmax = tonumber(ed.gmax:GetText())
  if f.gmin and f.gmax and f.gmin > f.gmax then ed.err:SetText(L.ED_ERR_SIZE); return end
  f.pts = tonumber(ed.pts:GetText())
  local old = {}
  for _, g in ipairs(f.goals or {}) do old[g.text] = g.done end
  local goals = {}
  for _, line in ipairs(ed.goals) do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and #goals < 8 then goals[#goals + 1] = { text = line, done = old[line] or false } end
  end
  f.goals = #goals > 0 and goals or nil
  local e
  if ed.ev then
    e = E.Get(ed.ev.id)
    if not e then V.ShowList(); return end
    for _, k in ipairs({ "type", "name", "desc", "kind", "start", "finish", "group", "gmin", "gmax", "pts", "goals" }) do e[k] = f[k] end
    if e.kind == "season" then e.start = ns.Points.SeasonStart(); e.finish = ns.Points.SeasonEnd() end
    E.Save(e)
  else
    e = E.Create(f)
  end
  if e then V.OpenDetail(e) end
end

-- e: edit this event · template: copy of an event as a new one (same weekday and time, next date ahead)
function V.OpenEditor(e, template)
  local p = V.panel
  if not G.IsManager() then return end
  local ed = p.editor
  ed.ev = e
  local src = e or template
  ed.f = src and U.Copy(src) or { kind = "short", group = "none" }
  if template then
    for _, k in ipairs({ "id", "status", "signups", "attended", "leader", "by", "ts", "v", "started", "ended", "created" }) do ed.f[k] = nil end
    for _, g in ipairs(ed.f.goals or {}) do g.done = false end
    local start = ed.f.start or U.Now()
    while start < U.Now() + 600 do start = start + 7 * DAY end
    local len = ed.f.finish and (ed.f.finish - (template.start or 0)) or nil
    ed.f.start = start
    ed.f.finish = len and (start + len) or nil
  end
  if not ed.f.start then
    -- new event: today at the next full hour (from 18:00 on: 20:00 if it is still ahead)
    local now = date("*t", U.Now())
    local h = now.hour + 1
    if h < 20 then h = 20 end
    if h > 23 then ed.f.start = addDays(midnight(U.Now()), 1) + 20 * 3600
    else ed.f.start = midnight(U.Now()) + h * 3600 end
    ed.f.finish = ed.f.start + 2 * 3600
  end
  if not ed.f.type then
    for _, t in ipairs(ns.Modules.AllTypes()) do
      if not t.missing and ns.Profile.IsTypeActive(t.id) then
        ed.f.type = t.id; ed.f.kind = t.kind or ed.f.kind; ed.f.group = t.group or ed.f.group
        ed.f.gmin, ed.f.gmax = t.gmin, t.gmax
        break
      end
    end
  end
  ed.st = stateFromEvent(ed.f)
  local today = midnight(U.Now())
  ed.st.custom = not (ed.st.day >= today and ed.st.day <= addDays(today, 6))
  ed.dateEdit:SetText(ed.st.custom and date("%d.%m.%Y", ed.st.day) or "")
  ed.title:SetText(e and L.EDIT_EVENT or (template and L.ED_TITLE_COPY or L.NEW_EVENT_TITLE))
  W.SetLabel(ed.save, e and L.SAVE or L.ANNOUNCE)
  ed.name:SetText((src and src.name ~= ns.Modules.TypeName(src.type)) and src.name or "")
  ed.desc:SetText(src and src.desc or "")
  ed.gmin:SetText(ed.f.gmin and tostring(ed.f.gmin) or "")
  ed.gmax:SetText(ed.f.gmax and tostring(ed.f.gmax) or "")
  ed.pts:SetText(ed.f.pts and tostring(ed.f.pts) or "")
  ed.goals = {}
  for _, g in ipairs(ed.f.goals or {}) do ed.goals[#ed.goals + 1] = g.text end
  ed.goalsTouched = src ~= nil
  if #ed.goals == 0 and not src then
    local t = ns.Modules.Type(ed.f.type)
    for _, k in ipairs(t and t.goalKeys or {}) do ed.goals[#ed.goals + 1] = L[k] end
  end
  ed.err:SetText("")
  ed.scroll:SetVerticalScroll(0)
  V.Mode("editor")
  V.EditorRefresh()
end

---------------------------------------------------------------------------
-- Attendance (end of an event): tick who took part, then points are written
---------------------------------------------------------------------------
local function buildAttendance(p)
  local a = CreateFrame("Frame", nil, p)
  a:SetAllPoints()
  a:Hide()
  p.att = a
  a.title = W.Text(a, 16, "title")
  a.title:SetPoint("TOPLEFT", 0, 0)
  a.hint = W.Text(a, 11, "muted")
  a.hint:SetPoint("TOPLEFT", a.title, "BOTTOMLEFT", 0, -6); a.hint:SetPoint("RIGHT", 0, 0)
  a.cancel = W.Button(a, CANCEL or "Cancel", false, 22)
  a.cancel:SetPoint("TOPRIGHT", 0, 0)
  a.cancel:SetScript("OnClick", function() V.OpenDetail(a.ev) end)
  a.ok = W.Button(a, L.END_AND_AWARD, true, 22)
  a.ok:SetPoint("RIGHT", a.cancel, "LEFT", -6, 0)
  a.ok:SetScript("OnClick", function()
    local sel = {}
    for _, c in ipairs(a.checks.items) do if c:IsShown() and c:GetChecked() then sel[c.key] = true end end
    E.End(a.ev, sel)
    V.OpenDetail(a.ev)
  end)
  a.add = W.Button(a, L.ADD_MEMBER, false, 22)
  a.add:SetPoint("BOTTOMLEFT", 0, 0)
  a.add:SetScript("OnClick", function()
    W.Dialog({ text = L.ADD_MEMBER_TEXT, edit = true, onAccept = function(txt)
      local key = G.Resolve(txt)
      if not key then U.Print(L.NOT_IN_GUILD:format(txt or "")); return end
      a.extra[key] = true
      V.RefreshAttendance()
    end })
  end)
  a.scroll = W.Scroll(a)
  a.scroll:SetPoint("TOPLEFT", 0, -50); a.scroll:SetPoint("BOTTOMRIGHT", 0, 30)
  a.checks = W.Pool(a.scroll.content, function(parent) return W.Check(parent, "") end)
end

function V.RefreshAttendance()
  local a = V.panel.att
  local cands = E.Candidates(a.ev)
  local have = {}
  for _, c in ipairs(cands) do have[c.key] = true end
  for key in pairs(a.extra) do
    if not have[key] then cands[#cands + 1] = { key = key, inGroup = false, signed = false, extra = true } end
  end
  local per = tonumber(a.ev.pts) or ns.Profile.Get().pts.participate
  a.hint:SetText(L.ATTEND_HINT:format(per))
  for i, c in ipairs(cands) do
    local cb = a.checks:Get(i)
    cb.key = c.key
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", 4 + col * 270, -4 - row * 22)
    local tag = c.inGroup and L.IN_GROUP or (c.signed and L.SIGNED or L.ADDED)
    cb.text:SetText(G.Display(c.key) .. "  " .. U.Color(T.Hex(T.Current().muted), tag))
    if a.defaults[c.key] == nil then a.defaults[c.key] = c.inGroup or c.extra or false end
    cb:SetChecked(a.defaults[c.key])
    cb:SetScript("OnClick", function(self) self:SetChecked(not self.checked); a.defaults[self.key] = self.checked end)
  end
  a.checks:HideFrom(#cands + 1)
  a.scroll:SetContentHeight(math.ceil(#cands / 3) * 22 + 8)
end

function V.OpenAttendance(e)
  local a = V.panel.att
  a.ev = e
  a.extra, a.defaults = {}, {}
  a.title:SetText(L.END_TITLE:format(e.name))
  V.RefreshAttendance()
  V.Mode("att")
end

---------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------
function V.Mode(m)
  local p = V.panel
  p.mode = m
  p.list:SetShown(m == "list")
  p.detail:SetShown(m == "detail")
  p.editor:SetShown(m == "editor")
  p.att:SetShown(m == "att")
  if m == "list" then refreshList(p) elseif m == "detail" then refreshDetail(p) end
end

function V.ShowList() V.Mode("list") end

function V.OpenDetail(e)
  if not V.panel then UI.Show("events"); return end
  if not e then return V.ShowList() end
  if UI.Frame() == nil or not UI.Frame():IsShown() or UI.Frame().current ~= "events" then UI.Show("events") end
  V.panel.detail.ev = e
  V.Mode("detail")
end

UI.RegisterView("events", {
  label = function() return L.TAB_EVENTS end,
  build = function(p)
    V.panel = p
    buildList(p); buildDetail(p); buildEditor(p); buildAttendance(p)
    p.mode = "list"
  end,
  refresh = function(p)
    if p.mode == "list" then refreshList(p)
    elseif p.mode == "detail" then refreshDetail(p)
    else
      p.list:SetShown(false); p.detail:SetShown(false)
      p.editor:SetShown(p.mode == "editor"); p.att:SetShown(p.mode == "att")
    end
  end,
})

ns.UIEvents = V
