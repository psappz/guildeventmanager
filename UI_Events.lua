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

-- "24.12. 20:00", "24.12.2026 20:00", "20:00" (today), "+30" (minutes from now)
function V.ParseTime(s)
  s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  local plus = s:match("^%+(%d+)$")
  if plus then return U.Now() + tonumber(plus) * 60 end
  local now = date("*t", U.Now())
  local d, m, y, h, mi = s:match("^(%d+)%.(%d+)%.(%d*)%s+(%d+):(%d+)$")
  if not d then
    h, mi = s:match("^(%d+):(%d+)$")
    if h then d, m, y = now.day, now.month, now.year end
  end
  if not d then
    d, m, y = s:match("^(%d+)%.(%d+)%.(%d*)$")
    h, mi = 20, 0
  end
  if not d then return nil end
  y = tonumber(y) or now.year
  if y < 100 then y = y + 2000 end
  return time({ year = y, month = tonumber(m), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
end

local function fmtInput(ts) return ts and date("%d.%m.%Y %H:%M", ts) or "" end

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
local function label(parent, text, anchor, x, y)
  local fs = W.Text(parent, 10, "muted")
  fs:SetText(text)
  fs:SetPoint("TOPLEFT", anchor or parent, anchor and "BOTTOMLEFT" or "TOPLEFT", x or 0, y or 0)
  return fs
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

  local col = CreateFrame("Frame", nil, ed)
  col:SetPoint("TOPLEFT", 0, -36); col:SetPoint("BOTTOMRIGHT", ed, "BOTTOM", -10, 0)
  local s = UI.Section(col, L.BASICS); s:SetPoint("TOPLEFT", 0, 0)

  local l1 = label(col, L.F_TYPE, nil, 0, -26)
  ed.type = W.Dropdown(col, 200, function()
    local o = {}
    for _, t in ipairs(ns.Modules.AllTypes()) do
      if not t.missing and ns.Profile.IsTypeActive(t.id) then o[#o + 1] = { t.id, ns.Modules.TypeName(t.id) } end
    end
    return o
  end, function() return ed.f and ed.f.type end, function(v)
    ed.f.type = v
    local t = ns.Modules.Type(v)
    if t then ed.f.kind = t.kind or ed.f.kind; ed.f.group = t.group or ed.f.group end
    ed.kind:Refresh(); ed.group:Refresh()
  end)
  ed.type:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 0, -3)

  local l2 = label(col, L.F_NAME, ed.type, 0, -8)
  ed.name = W.Edit(col, 10, 22)
  ed.name:SetPoint("TOPLEFT", l2, "BOTTOMLEFT", 0, -3); ed.name:SetPoint("RIGHT", col, "RIGHT", 0, 0)

  local l3 = label(col, L.F_KIND, ed.name, 0, -8)
  ed.kind = W.Dropdown(col, 160, function()
    local o = {}
    for _, k in ipairs(E.KINDS) do o[#o + 1] = { k, kindText(k) } end
    return o
  end, function() return ed.f and ed.f.kind end, function(v) ed.f.kind = v; V.EditorLayout() end)
  ed.kind:SetPoint("TOPLEFT", l3, "BOTTOMLEFT", 0, -3)
  local l4 = label(col, L.F_GROUP, ed.name, 176, -8)
  ed.group = W.Dropdown(col, 160, function()
    local o = {}
    for _, g in ipairs(E.GROUPS) do o[#o + 1] = { g, L["GROUP_" .. g] } end
    return o
  end, function() return ed.f and ed.f.group end, function(v) ed.f.group = v end)
  ed.group:SetPoint("TOPLEFT", l4, "BOTTOMLEFT", 0, -3)

  local l5 = label(col, L.F_START, ed.kind, 0, -8)
  ed.start = W.Edit(col, 160, 22)
  ed.start:SetPoint("TOPLEFT", l5, "BOTTOMLEFT", 0, -3)
  ed.lFinish = label(col, L.F_FINISH, ed.kind, 176, -8)
  ed.finish = W.Edit(col, 160, 22)
  ed.finish:SetPoint("TOPLEFT", ed.lFinish, "BOTTOMLEFT", 0, -3)
  ed.timeHint = W.Text(col, 10, "muted")
  ed.timeHint:SetPoint("TOPLEFT", ed.start, "BOTTOMLEFT", 0, -4)
  ed.timeHint:SetText(L.TIME_HINT)

  local l6 = label(col, L.F_GMIN, ed.timeHint, 0, -10)
  ed.gmin = W.Edit(col, 70, 22); ed.gmin:SetNumeric(true)
  ed.gmin:SetPoint("TOPLEFT", l6, "BOTTOMLEFT", 0, -3)
  local l7 = label(col, L.F_GMAX, ed.timeHint, 90, -10)
  ed.gmax = W.Edit(col, 70, 22); ed.gmax:SetNumeric(true)
  ed.gmax:SetPoint("TOPLEFT", l7, "BOTTOMLEFT", 0, -3)
  local l8 = label(col, L.F_POINTS, ed.timeHint, 176, -10)
  ed.pts = W.Edit(col, 70, 22); ed.pts:SetNumeric(true)
  ed.pts:SetPoint("TOPLEFT", l8, "BOTTOMLEFT", 0, -3)

  local col2 = CreateFrame("Frame", nil, ed)
  col2:SetPoint("TOPLEFT", ed, "TOP", 10, -36); col2:SetPoint("BOTTOMRIGHT", 0, 0)
  local s2 = UI.Section(col2, L.F_DESC); s2:SetPoint("TOPLEFT", 0, 0)
  local box = W.Box(col2, 10, 10, "panel2")
  box:SetPoint("TOPLEFT", 0, -24); box:SetPoint("RIGHT", 0, 0); box:SetHeight(150)
  ed.desc = W.Edit(box, 10, 140, true)
  ed.desc:SetPoint("TOPLEFT", 4, -4); ed.desc:SetPoint("BOTTOMRIGHT", -4, 4)
  ed.desc:SetMaxLetters(500)
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() ed.desc:SetFocus() end)
  ed.descHint = W.Text(col2, 10, "muted")
  ed.descHint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6); ed.descHint:SetPoint("RIGHT", 0, 0)
  ed.descHint:SetText(L.DESC_HINT)
  ed.goalsLabel = W.Text(col2, 10, "muted")
  ed.goalsLabel:SetPoint("TOPLEFT", ed.descHint, "BOTTOMLEFT", 0, -12)
  local gbox = W.Box(col2, 10, 10, "panel2")
  gbox:SetPoint("TOPLEFT", ed.goalsLabel, "BOTTOMLEFT", 0, -4); gbox:SetPoint("RIGHT", 0, 0); gbox:SetHeight(84)
  ed.goals = W.Edit(gbox, 10, 76, true)
  ed.goals:SetPoint("TOPLEFT", 4, -4); ed.goals:SetPoint("BOTTOMRIGHT", -4, 4)
  ed.goals:SetMaxLetters(400)
  gbox:EnableMouse(true)
  gbox:SetScript("OnMouseDown", function() ed.goals:SetFocus() end)

  ed.save:SetScript("OnClick", function() V.SaveEditor() end)
end

function V.EditorLayout()
  local ed = V.panel.editor
  local isShort = ed.f.kind == "short"
  local isSeason = ed.f.kind == "season"
  ed.start:SetEnabled(not isSeason); ed.start:SetAlpha(isSeason and 0.4 or 1)
  ed.finish:SetEnabled(not isSeason); ed.finish:SetAlpha(isSeason and 0.4 or 1)
  ed.lFinish:SetText(isShort and L.F_FINISH_OPT or L.F_FINISH)
end

function V.SaveEditor()
  local ed = V.panel.editor
  ed.err:SetText("")
  local f = ed.f
  if not f.type then ed.err:SetText(L.ERR_TYPE); return end
  f.name = ed.name:GetText()
  f.desc = ed.desc:GetText()
  if f.kind ~= "season" then
    f.start = V.ParseTime(ed.start:GetText())
    if not f.start then ed.err:SetText(L.ERR_START); return end
    f.finish = V.ParseTime(ed.finish:GetText())
    if f.kind ~= "short" and not f.finish then ed.err:SetText(L.ERR_FINISH); return end
    if f.finish and f.finish <= f.start then ed.err:SetText(L.ERR_ORDER); return end
  end
  f.gmin = tonumber(ed.gmin:GetText())
  f.gmax = tonumber(ed.gmax:GetText())
  f.pts = tonumber(ed.pts:GetText())
  local old = {}
  for _, g in ipairs(f.goals or {}) do old[g.text] = g.done end
  f.goals = {}
  for line in (ed.goals:GetText() or ""):gmatch("[^\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and #f.goals < 8 then f.goals[#f.goals + 1] = { text = line, done = old[line] or false } end
  end
  if #f.goals == 0 then f.goals = nil end
  local e
  if ed.ev then
    e = E.Get(ed.ev.id)
    if not e then V.ShowList(); return end
    for _, k in ipairs({ "type", "name", "desc", "kind", "start", "finish", "group", "gmin", "gmax", "pts", "goals" }) do e[k] = f[k] end
    if e.name == "" then e.name = ns.Modules.TypeName(e.type) end
    if e.kind == "season" then e.start = ns.Points.SeasonStart(); e.finish = ns.Points.SeasonEnd() end
    E.Save(e)
  else
    e = E.Create(f)
  end
  if e then V.OpenDetail(e) end
end

function V.OpenEditor(e)
  local p = V.panel
  if not G.IsManager() then return end
  local ed = p.editor
  ed.ev = e
  ed.f = e and U.Copy(e) or { kind = "short", group = "none", start = U.Now() + 3600 }
  if not ed.f.type then
    for _, t in ipairs(ns.Modules.AllTypes()) do
      if not t.missing and ns.Profile.IsTypeActive(t.id) then ed.f.type = t.id; ed.f.kind = t.kind; ed.f.group = t.group; break end
    end
  end
  ed.title:SetText(e and L.EDIT_EVENT or L.NEW_EVENT_TITLE)
  W.SetLabel(ed.save, e and L.SAVE or L.ANNOUNCE)
  ed.name:SetText(e and e.name or "")
  ed.desc:SetText(e and e.desc or "")
  ed.start:SetText(fmtInput(ed.f.start))
  ed.finish:SetText(fmtInput(ed.f.finish))
  ed.gmin:SetText(ed.f.gmin and tostring(ed.f.gmin) or "")
  ed.gmax:SetText(ed.f.gmax and tostring(ed.f.gmax) or "")
  ed.pts:SetText(ed.f.pts and tostring(ed.f.pts) or "")
  ed.goalsLabel:SetText(L.F_GOALS:format(ns.Profile.Get().pts.goal or 5))
  local gl = {}
  for _, g in ipairs(ed.f.goals or {}) do gl[#gl + 1] = g.text end
  if #gl == 0 then
    local t = ns.Modules.Type(ed.f.type)
    for _, k in ipairs(t and t.goalKeys or {}) do gl[#gl + 1] = L[k] end
  end
  ed.goals:SetText(table.concat(gl, "\n"))
  ed.err:SetText("")
  ed.type:Refresh(); ed.kind:Refresh(); ed.group:Refresh()
  V.EditorLayout()
  V.Mode("editor")
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
