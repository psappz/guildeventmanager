local ADDON, ns = ...
-- Events tab: overview, detail page, editor, attendance at the end.
local U, G, T, W, E, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.Events, ns.UI
local V = {}
ns.EventsUI = V
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
-- may I create events at all (managers, or a type that allows me, e.g. raids)?
function V.AnyCreate()
  if G.IsManager() then return true end
  for _, t in ipairs(ns.Modules.AllTypes()) do
    if not t.missing and E.CanCreate(t.id) and E.TypeOpen(t.id) then return true end
  end
  return false
end

local function makeRow(parent)
  local th = T.Current()
  local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
  r:SetHeight(ROW_H - 4)
  W.Paint(r, th.panel2, th.line)
  r.icon = UI.DateTile(r, 42, 34)
  r.icon:SetPoint("LEFT", 4, 0)
  r.name = W.Text(r, 12, "text")
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -2)
  r.meta = W.Text(r, 10, "muted")
  r.meta:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 2)
  r.chev = W.IconTex(r, "chevron", 14, "muted")
  r.chev:SetPoint("RIGHT", -8, 0)
  r.count = W.Text(r, 10, "muted")
  r.count:SetPoint("RIGHT", r.chev, "LEFT", -8, 0)
  r.action = W.Button(r, "", true, 22)   -- kept for old code paths, not shown
  r.action:Hide()
  r.pill = UI.Pill(r)
  r.pill:SetPoint("RIGHT", r.count, "LEFT", -10, 0)
  r.tag = UI.Pill(r)
  r.tag:SetPoint("RIGHT", r.pill, "LEFT", -6, 0)
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
  -- events of modules the player is not interested in: folded away
  list.mutedBtn = W.Button(list.scroll.content, "", false, 20)
  list.mutedBtn:SetScript("OnClick", function() list.showMuted = not list.showMuted; UI.Refresh() end)
  list.empty = W.Text(list.scroll.content, 12, "muted")
  list.empty:SetPoint("TOPLEFT", 4, -8); list.empty:SetPoint("RIGHT", list.scroll.content, "RIGHT", -4, 0)
end

local function refreshList(p)
  local list = p.list
  local manager = V.AnyCreate()
  list.new:SetShown(manager)
  local groups = {
    { L.SEC_RUNNING, function(e) return e.status == "running" and e.kind ~= "season" end },
    { L.SEC_PLANNED, function(e) return e.status == "planned" and e.kind ~= "season" end },
    { L.SEC_SEASON, function(e) return E.IsOpen(e) and e.kind == "season" end },
    { L.SEC_PAST, function(e) return not E.IsOpen(e) and (U.Now() - (e.start or 0)) < 30 * 86400 end },
  }
  local y, nr, nh = 0, 0, 0
  local content = list.scroll.content
  local hidden = 0
  local function visible(e)
    if list.showMuted or not ns.Catalog.Muted(e) or E.Status(e) then return true end
    if E.IsOpen(e) then hidden = hidden + 1 end
    return false
  end
  for _, g in ipairs(groups) do
    local items = E.List(function(e) return g[2](e) and ns.Profile.IsTypeActive(e.type) and visible(e) end)
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
        r.icon:Set(e.start)
        r.name:SetText(e.name .. (E.TypeMissing(e) and ("  " .. U.Color(U.WARN, L.MODULE_MISSING)) or ""))
        r.meta:SetText(table.concat({ ns.Modules.TypeName(e.type), kindText(e.kind), groupText(e), whenText(e) }, " · ") .. (e.series and (" · " .. L.SERIES_TAG) or ""))
        r.count:SetText(L.SIGNED_N:format(E.SignCount(e)))
        local st = E.Status(e)
        if E.IsOpen(e) and e.status == "running" then
          r.pill:Set(statusText(e), true)
        elseif E.IsOpen(e) then
          local text, col = UI.StateTag(st); r.pill:Set(text, false, col)
        else
          r.pill:Set(statusText(e), false)
        end
        local tag, tcol = UI.ModuleTag(e.type)
        r.tag:Set(tag, false, tcol)
        r.tag:ClearAllPoints()
        if r.pill:IsShown() then r.tag:SetPoint("RIGHT", r.pill, "LEFT", -6, 0) else r.tag:SetPoint("RIGHT", r.count, "LEFT", -10, 0) end
        y = y + ROW_H
      end
      y = y + 6
    end
  end
  list.rows:HideFrom(nr + 1)
  list.heads:HideFrom(nh + 1)
  list.mutedBtn:SetShown(hidden > 0 or list.showMuted)
  if list.mutedBtn:IsShown() then
    W.SetLabel(list.mutedBtn, list.showMuted and L.MUTED_HIDE or L.MUTED_SHOW:format(hidden))
    list.mutedBtn:SetWidth(list.mutedBtn.label:GetStringWidth() + 24)
    list.mutedBtn:ClearAllPoints(); list.mutedBtn:SetPoint("TOPLEFT", 0, -(y + 2))
    y = y + 28
  end
  list.empty:SetShown(nr == 0 and not list.mutedBtn:IsShown())
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
  d.icon = UI.DateTile(d, 46, 42)
  d.icon:SetPoint("TOPLEFT", 0, 0)
  d.name = W.Text(d, 16, "title")
  d.name:SetFont("Fonts\\MORPHEUS.TTF", 19, "")
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
  -- "How it works": the type's rules (API 7) in a small window
  d.rulesBtn = W.Button(d.left, L.RULES_BTN, true, 20)
  d.rulesBtn:SetWidth(140); d.rulesBtn:SetPoint("TOPRIGHT", d.left, "TOPRIGHT", 0, 2)
  d.rulesBtn:SetFrameLevel(d.left:GetFrameLevel() + 5)
  d.rulesBtn:SetScript("OnClick", function() if d.ev then V.ShowRules(d.ev) end end)
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
  -- tabs "Sign-ups" / "Teams" (0.9, events with group "teams")
  d.tabs = {}
  for i, id in ipairs({ "info", "teams" }) do
    local b = W.Button(d, "", false, 22)
    b.tab = id
    b:SetScript("OnClick", function(self) d.tab = self.tab; V.RefreshDetail() end)
    if i == 1 then b:SetPoint("TOPLEFT", 0, -54) else b:SetPoint("LEFT", d.tabs[i - 1], "RIGHT", 4, 0) end
    d.tabs[i] = b
  end
  d.teams = CreateFrame("Frame", nil, d)
  d.teams:SetPoint("TOPLEFT", 0, -84); d.teams:SetPoint("BOTTOMRIGHT", 0, 34)
  d.teams:Hide()
  if ns.UITeams then ns.UITeams.Build(d.teams) end
  -- own sign-up: state, comment, the event's own fields
  d.myHead = UI.Section(d.right, L.MY_SIGNUP); d.myHead:SetPoint("TOPLEFT", 0, 0)
  d.my = W.Box(d.right, 10, 10, "panel2")
  d.my:SetPoint("TOPLEFT", 0, -22); d.my:SetPoint("RIGHT", 0, 0)
  d.stRow = UI.ChipRow(d.my, function()
    local o = {}
    for _, st in ipairs(E.SIGN) do o[#o + 1] = { st, L["ST_" .. st] } end
    return o
  end, function() return d.draft and d.draft.st end, function(v) d.draft.st = v; V.RefreshDetail() end)
  d.stRow:SetPoint("TOPLEFT", 8, -8); d.stRow:SetPoint("RIGHT", -8, 0)
  d.cLabel = W.Text(d.my, 10, "muted"); d.cLabel:SetText(L.SIGN_COMMENT)
  d.comment = W.Edit(d.my, 10, 22)
  d.comment:SetMaxLetters(E.COMMENT_MAX)
  d.comment:SetScript("OnTextChanged", function(self) if d.draft then d.draft.c = self:GetText() end end)
  d.fieldRows = W.Pool(d.my, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(42)
    r.label = W.Text(r, 10, "muted"); r.label:SetPoint("TOPLEFT", 0, 0)
    r.auto = W.Text(r, 13, "title"); r.auto:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -6)
    r.autoTag = UI.Pill(r); r.autoTag:SetPoint("LEFT", r.auto, "RIGHT", 8, 0)
    r.chips = UI.ChipRow(r, function() return r.opts or {} end, function() return r.get and r.get() end, function(v) if r.set then r.set(v) end end)
    r.chips:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -4); r.chips:SetPoint("RIGHT", 0, 0)
    r.edit = W.Edit(r, 120, 22); r.edit:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -4)
    r.edit:SetScript("OnTextChanged", function(self) if r.set and self:HasFocus() then r.set(self:GetText()) end end)
    r.check = W.Check(r, "", function(_, on) if r.set then r.set(on) end end)
    r.check:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -4)
    return r
  end)
  d.why = W.Text(d.my, 10, "text")
  d.why:SetSpacing(2)
  d.allDates = W.Check(d.my, L.SERIES_SIGN_ALL, function(_, on) d.signAll = on end)
  d.save = W.Button(d.my, L.SIGN_ON, true, 22)
  d.save:SetScript("OnClick", function()
    local e = d.ev
    if not e or not d.draft then return end
    local ok
    if e.series and d.signAll then ok = ns.Series.SignAll(e, d.draft) > 0
    else ok = E.SetSignup(e, d.draft) end
    if ok then d.saved = U.Now() end
    V.RefreshDetail()
  end)
  d.savedText = W.Text(d.my, 10, "muted")
  d.savedText:SetPoint("LEFT", d.save, "RIGHT", 8, 0); d.savedText:SetPoint("RIGHT", -8, 0)
  d.savedText:SetWordWrap(false)

  d.signHead = UI.Section(d.right, L.SIGNUPS)
  d.endB = V.EndButtons(d.right)
  d.signBox = W.Box(d.right, 10, 10, "panel2")
  d.signBox:SetPoint("TOPLEFT", d.signHead, "BOTTOMLEFT", 0, -8); d.signBox:SetPoint("BOTTOMRIGHT", 0, 0)
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
  d.bInvite = act("ACT_INVITE", function(e) E.InviteAll(e) end)
  d.bCancel = act("ACT_CANCEL", function(e)
    if e.series then
      W.Dialog({ text = L.CONFIRM_CANCEL:format(e.name) .. "\n\n" .. L.SERIES_CANCEL_Q, accept = L.SERIES_ONLY_THIS, alt = L.SERIES_ALL_LATER,
        onAccept = function() E.Cancel(e) end, onAlt = function() ns.Series.CancelFollowing(e) end })
    else
      W.Dialog({ text = L.CONFIRM_CANCEL:format(e.name), onAccept = function() E.Cancel(e) end })
    end
  end)
end

local function refreshDetail(p)
  local d = p.detail
  local e = d.ev and E.Get(d.ev.id) or d.ev
  if not e then V.ShowList(); return end
  d.ev = e
  d.icon:Set(e.start)
  d.name:SetText(e.name)
  local t = ns.Modules.Type(e.type)
  local mod = t and ns.Modules.modules[t.module]
  local tag, tcol = UI.ModuleTag(e.type)
  local vals = {
    { ns.Modules.TypeName(e.type) },
    { tag or (mod and (mod.name or L[mod.nameKey])) or L.MODULE_MISSING, false, tcol },
    { groupText(e) },
    { L.LEADER:format((function() local t = {}; for _, k in ipairs(E.Leaders(e)) do t[#t + 1] = G.Display(k) end; return table.concat(t, ", ") end)()) },
    { statusText(e), e.status == "running" },
    { kindText(e.kind) },
  }
  for i, pl in ipairs(d.pills) do pl:Set(vals[i][1], vals[i][2], vals[i][3]) end
  d.desc:SetText((e.desc and e.desc ~= "") and e.desc or (t and t.descKey and L[t.descKey]) or "")
  d.rulesBtn:SetShown(E.Rules(e) ~= nil)
  -- tabs: only events with teams
  local hasTeams = e.group == "teams" and ns.UITeams ~= nil
  if not hasTeams then d.tab = "info" end
  local th = T.Current()
  local nSign = 0
  for _, s in ipairs(E.SignupList(e)) do if s.st == "in" or s.st == "late" then nSign = nSign + 1 end end
  local tm = ns.Teams and ns.Teams.Get(e)
  local labels = { info = L.TM_TAB_SIGN:format(nSign), teams = L.TM_TAB_TEAMS:format(tm and #tm.list or 0) }
  for _, b in ipairs(d.tabs) do
    b:SetShown(hasTeams)
    W.SetLabel(b, labels[b.tab])
    local on = (d.tab or "info") == b.tab
    b:SetBackdropColor(unpack(on and th.accent or th.panel2))
    b.label:SetTextColor(unpack(on and { 1, 0.95, 0.85 } or th.text))
  end
  local top = hasTeams and -84 or -54
  d.left:ClearAllPoints(); d.left:SetPoint("TOPLEFT", 0, top); d.left:SetPoint("BOTTOMLEFT", 0, 34); d.left:SetPoint("RIGHT", d, "CENTER", -8, 0)
  d.right:ClearAllPoints(); d.right:SetPoint("TOPLEFT", d, "TOP", 8, top); d.right:SetPoint("BOTTOMRIGHT", 0, 34)
  local teamsTab = hasTeams and d.tab == "teams"
  d.left:SetShown(not teamsTab); d.right:SetShown(not teamsTab); d.teams:SetShown(teamsTab)
  if teamsTab then ns.UITeams.Attach(d.teams, e) end
  local facts = {
    L.FACT_START:format(U.FormatTime(e.start)),
  }
  if e.finish then facts[#facts + 1] = L.FACT_END:format(U.FormatTime(e.finish)) end
  local pr = ns.Profile.Get().pts
  facts[#facts + 1] = L.FACT_POINTS:format(tonumber(e.pts) or pr.participate, pr.lead, pr.leadMin)
  if E.MinLevel(e) then facts[#facts + 1] = L.FACT_LEVEL:format(E.MinLevel(e)) end
  if e.rep then
    local id = (e.rep.every == "week" and e.rep.n == 2) and "week2" or e.rep.every
    facts[#facts + 1] = L.FACT_REPEAT:format(L["ED_REP_" .. id] or id) .. (e.rep.untilTs and (" · " .. L.FACT_UNTIL:format(date("%d.%m.%Y", e.rep.untilTs))) or "")
  end
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
  local manager = E.CanManage(e)
  for i, g in ipairs(e.goals or {}) do
    local c = d.goalChecks:Get(i)
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", d.goalHead, "BOTTOMLEFT", 2, -8 - (i - 1) * 20)
    c.text:SetText(g.text)
    c:SetChecked(g.done)
    c:SetEnabled(manager and E.IsOpen(e))
    c:SetScript("OnClick", function() E.ToggleGoal(e, i) end)
  end
  d.goalChecks:HideFrom(total + 1)

  -- own sign-up
  local open = E.IsOpen(e)
  local th = T.Current()
  local muted = T.Hex(th.muted)
  if d.draftFor ~= e.id then
    local cur = E.Signup(e)
    d.draftFor = e.id
    d.saved = nil
    d.draft = { st = E.Status(e) or "in", c = cur and cur.c or "", f = U.Copy(cur and cur.f or {}) }
    for _, fd in ipairs(E.Fields(e)) do
      if d.draft.f[fd.id] == nil and fd.default ~= nil and fd.kind ~= "auto" then d.draft.f[fd.id] = E.FieldDefault(fd, e) end
    end
    d.comment:SetText(d.draft.c or "")
  end
  d.myHead:SetShown(open); d.my:SetShown(open)
  local y = 0
  if open then
    d.stRow:Refresh()
    d.cLabel:ClearAllPoints(); d.cLabel:SetPoint("TOPLEFT", 8, -40)
    d.comment:ClearAllPoints(); d.comment:SetPoint("TOPLEFT", 8, -54); d.comment:SetPoint("RIGHT", -8, 0)
    y = -84
    local fields = {}
    for _, f in ipairs(E.Fields(e)) do if not f.hidden then fields[#fields + 1] = f end end
    for i, f in ipairs(fields) do
      local r = d.fieldRows:Get(i)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 8, y); r:SetPoint("RIGHT", d.my, "RIGHT", -8, 0)
      r.label:SetText(E.FieldLabel(f) .. (f.required and " *" or ""))
      local kind = f.kind or "text"
      r.auto:SetShown(kind == "auto"); r.autoTag:SetShown(kind == "auto")
      r.chips:SetShown(kind == "choice" or kind == "multi")
      r.edit:SetShown(kind == "number" or kind == "text")
      r.check:SetShown(kind == "check")
      r.get, r.set, r.opts = nil, nil, nil
      if kind == "auto" then
        local v = E.AutoValue(f, e)
        r.auto:SetText(v ~= nil and (f.format and f.format(v) or tostring(v)) or "–")
        r.autoTag:Set(L.FIELD_AUTO, false)
      elseif kind == "choice" or kind == "multi" then
        r.opts = {}
        for _, o in ipairs((type(f.options) == "function" and f.options(e)) or f.options or {}) do
          local val, lab = o, o
          if type(o) == "table" then val, lab = o[1], o[2] or o[1] end
          if type(lab) == "string" and ns.L[lab] then lab = ns.L[lab] end
          r.opts[#r.opts + 1] = { val, lab }
        end
        if kind == "choice" then
          r.get = function() return d.draft.f[f.id] end
          r.set = function(v) d.draft.f[f.id] = v; V.RefreshDetail() end
        else
          r.get = function() return nil end
          r.set = function(v)
            local list = d.draft.f[f.id] or {}
            local found
            for j = #list, 1, -1 do if list[j] == v then table.remove(list, j); found = true end end
            if not found then list[#list + 1] = v end
            d.draft.f[f.id] = list
            V.RefreshDetail()
          end
        end
        r.chips:Refresh()
        if kind == "multi" then
          local sel = {}
          for _, v in ipairs(d.draft.f[f.id] or {}) do sel[v] = true end
          for _, c in ipairs(r.chips.chips) do if c:IsShown() then c:SetSelected(sel[c.value] or false) end end
        end
      elseif kind == "check" then
        r.check.text:SetText(f.checkLabel or "")
        r.check:SetChecked(d.draft.f[f.id] and true or false)
        r.set = function(v) d.draft.f[f.id] = v end
      else
        if not r.edit:HasFocus() then r.edit:SetText(d.draft.f[f.id] ~= nil and tostring(d.draft.f[f.id]) or "") end
        r.edit:SetNumeric(kind == "number")
        r.set = function(v) d.draft.f[f.id] = v end
      end
      y = y - 46
    end
    d.fieldRows:HideFrom(#fields + 1)
    -- not allowed (e.g. level): say why; declining still works
    -- hints when allowed (yellow, API 7)
    local can, why, notes = E.CanSignUp(e)
    local warnText
    if not can then warnText = U.Color(U.WARN, why or L.SIGN_NOT_ALLOWED)
    elseif notes then
      local l = {}
      for _, n in ipairs(notes) do l[#l + 1] = U.Color("ffe6c34d", "! " .. n) end
      warnText = table.concat(l, "\n")
    end
    d.why:SetShown(warnText ~= nil)
    if warnText then
      d.why:ClearAllPoints(); d.why:SetPoint("TOPLEFT", 8, y - 2); d.why:SetPoint("RIGHT", d.my, "RIGHT", -8, 0)
      d.why:SetText(warnText)
      y = y - d.why:GetStringHeight() - 8
    end
    d.allDates:SetShown(e.series ~= nil)
    if e.series then
      local mine = e.signups and e.signups[G.MyKey()]
      if d.signAllFor ~= e.id then d.signAllFor = e.id; d.signAll = mine and mine.all or false end
      d.allDates:SetChecked(d.signAll)
      d.allDates:ClearAllPoints(); d.allDates:SetPoint("TOPLEFT", 10, y - 4)
      y = y - 22
    end
    d.save:ClearAllPoints(); d.save:SetPoint("TOPLEFT", 8, y - 4)
    W.SetLabel(d.save, E.Status(e) and L.SIGN_SAVE or L.SIGN_ON)
    local cur = E.Status(e)
    d.savedText:SetText(d.saved and L.SIGN_SAVED or (cur and L.YOU_ST:format(L["ST_" .. cur]) or ""))
    y = y - 34
    d.my:SetHeight(-y)
    d.signHead:ClearAllPoints(); d.signHead:SetPoint("TOPLEFT", d.my, "BOTTOMLEFT", 0, -12)
  else
    d.signHead:ClearAllPoints(); d.signHead:SetPoint("TOPLEFT", 0, 0)
  end

  -- all sign-ups, by state, with their answers
  local fields = E.Fields(e)
  local byState = {}
  for _, s in ipairs(E.SignupList(e)) do
    byState[s.st] = byState[s.st] or {}
    local bits = {}
    for _, f in ipairs(fields) do
      local v = s.f[f.id]
      if v ~= nil and v ~= "none" and f.hidden ~= true and (f.leadOnly ~= true or E.CanManage(e)) then
        if f.format then
          local ok, fv = pcall(f.format, v); if ok and fv then v = fv end
        elseif f.kind == "choice" or f.kind == "multi" then
          local lab = {}
          for _, o in ipairs((type(f.options) == "function" and f.options(e)) or f.options or {}) do
            if type(o) == "table" then lab[o[1]] = (o[2] and ns.L[o[2]]) or o[2] or o[1] end
          end
          if type(v) == "table" then
            local t = {}
            for _, x in ipairs(v) do t[#t + 1] = lab[x] or x end
            v = table.concat(t, ", ")
          else v = lab[v] or v end
        end
        if type(v) == "table" then v = table.concat(v, ", ") elseif type(v) == "boolean" then v = v and L.YES or L.NO end
        bits[#bits + 1] = (f.short or E.FieldLabel(f)) .. ": " .. tostring(v)
      end
    end
    if s.c then bits[#bits + 1] = "»" .. s.c .. "«" end
    byState[s.st][#byState[s.st] + 1] = G.Display(s.key) .. (#bits > 0 and U.Color(muted, "  · " .. table.concat(bits, " · ")) or "")
  end
  local lines = {}
  for _, st in ipairs(E.SIGN) do
    local l = byState[st]
    if l and #l > 0 then
      lines[#lines + 1] = U.Color(T.Hex(th.title), L["ST_" .. st] .. " (" .. #l .. ")")
      for _, x in ipairs(l) do lines[#lines + 1] = "  " .. x end
    end
  end
  -- contest (API 7): standings or the referee's result above the sign-ups
  local top = V.ContestLines(e)
  if top then
    if #lines > 0 then top[#top + 1] = "" end
    for _, l in ipairs(lines) do top[#top + 1] = l end
    lines = top
  end
  d.signHead:SetText(L.SIGNUPS .. " (" .. E.SignCount(e) .. ")")
  -- report end / confirm (contests)
  V.RefreshEndButtons(d.endB, e)
  d.endB.report:ClearAllPoints(); d.endB.report:SetPoint("BOTTOMRIGHT", d.signBox, "TOPRIGHT", 0, 4)
  d.endB.resume:ClearAllPoints(); d.endB.resume:SetPoint("BOTTOMRIGHT", d.signBox, "TOPRIGHT", 0, 4)
  d.endB.confirm:ClearAllPoints(); d.endB.confirm:SetPoint("RIGHT", d.endB.resume, "LEFT", -4, 0)
  d.signText:SetText(#lines > 0 and table.concat(lines, "\n") or L.NO_SIGNUPS)
  d.signScroll:SetContentHeight(d.signText:GetStringHeight() + 4)
  d.sign:Hide()

  local manager = E.CanManage(e)
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

-- the level a type asks for by default (number or function), nil = all levels
local function typeLevel(t)
  local v = t and t.minLevel
  if type(v) == "function" then local ok, r = pcall(v); v = ok and r or nil end
  v = tonumber(v)
  return (v and v > 1) and math.floor(v) or nil
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
  -- leadership (0.9): one or more leaders, raids need a raid lead
  ed.lLead = W.Text(col, 10, "muted")
  ed.leadRows = W.Pool(col, function(parent)
    local b = W.Button(parent, "", false, 20)
    b:SetScript("OnClick", function(self)
      local k = self.key
      local list = ed.f and ed.f.leaders or {}
      for i = #list, 1, -1 do if list[i] == k then table.remove(list, i) end end
      V.EditorRefresh()
    end)
    return b
  end)
  ed.leadEdit = W.Edit(col, 150, 20)
  ed.leadAdd = W.Button(col, L.ED_LEAD_ADD, false, 20); ed.leadAdd:SetWidth(90)
  local function addLeader(text)
    local k = G.Resolve(((text or ed.leadEdit:GetText()) or ""):match("^%s*(.-)%s*$"))
    if not k or not ed.f then return end
    k = ns.Persons and ns.Persons.MainOf(k) or k
    ed.f.leaders = ed.f.leaders or {}
    for _, x in ipairs(ed.f.leaders) do if x == k then return end end
    ed.f.leaders[#ed.f.leaders + 1] = k
    ed.leadEdit:SetText("")
    V.EditorRefresh()
  end
  ed.leadAdd:SetScript("OnClick", function() addLeader() end)
  ed.leadEdit:SetScript("OnEnterPressed", function(self) addLeader(); self:ClearFocus() end)
  W.NameComplete(ed.leadEdit, W.MemberNames, addLeader)
  ed.leadHint = W.Text(col, 10, "muted")

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
  -- repeat (API 7): the next four weeks are kept as events
  ed.lRep = W.Text(col, 10, "muted"); ed.lRep:SetText(L.ED_REPEAT)
  ed.rep = W.Dropdown(col, 170, function()
    local o = {}
    for _, id in ipairs({ "none", "day", "week", "week2", "month" }) do o[#o + 1] = { id, L["ED_REP_" .. id] } end
    return o
  end, function() return ed.repSel or "none" end, function(v) ed.repSel = v; V.EditorRefresh() end)
  ed.lUntil = W.Text(col, 10, "muted"); ed.lUntil:SetText(L.ED_REP_UNTIL)
  ed.until_ = W.Edit(col, 100, 22); ed.until_:SetMaxLetters(10)
  ed.untilHint = W.Text(col, 10, "muted"); ed.untilHint:SetText(L.ED_DATE_HINT)
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
  ed.lLvl = W.Text(col, 10, "muted"); ed.lLvl:SetText(L.ED_LEVEL)
  ed.lvl = W.Edit(col, 60, 22); ed.lvl:SetNumeric(true); ed.lvl:SetMaxLetters(3)
  ed.lvlHint = W.Text(col, 10, "muted"); ed.lvlHint:SetText(L.ED_LEVEL_HINT)
  ed.remind = W.Check(col, L.ED_REMIND)
  for _, e in ipairs({ ed.gmin, ed.gmax, ed.pts, ed.lvl }) do
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

  -- 1b · settings of the event type (API 7): one row per setting
  ed.sSet = UI.Section(col, L.ED_SETTINGS); ed.sSet:SetWidth(LEFT_W)
  ed.setRows = W.Pool(col, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(LEFT_W, 24)
    r.label = W.Text(r, 11, "text"); r.label:SetPoint("LEFT", 0, 0); r.label:SetWidth(200); r.label:SetWordWrap(false)
    r.hint = W.Text(r, 10, "muted")
    local function set(v) if ed.set and r.def then ed.set[r.def.id] = v; V.EditorRefresh() end end
    r.drop = W.Dropdown(r, 220, function() return r.def and E.SettingOptions(r.def, ed.f) or {} end,
      function() return ed.set and r.def and ed.set[r.def.id] end, set)
    r.drop:SetPoint("LEFT", 206, 0)
    r.edit = W.Edit(r, 90, 22); r.edit:SetPoint("LEFT", 206, 0)
    r.edit:SetScript("OnTextChanged", function(self, user)
      if not (user and ed.set and r.def) then return end
      local k = r.def.kind
      local txt = self:GetText()
      if k == "number" then ed.set[r.def.id] = tonumber(txt)
      elseif k == "date" then
        local d, m, y = txt:match("^(%d%d?)%.(%d%d?)%.(%d%d%d%d)$")
        ed.set[r.def.id] = d and string.format("%04d-%02d-%02d", y, m, d) or nil
      else ed.set[r.def.id] = txt end
    end)
    r.edit:SetScript("OnEditFocusLost", function() V.EditorRefresh() end)
    r.check = W.Check(r, "", function(_, on) if ed.set and r.def then ed.set[r.def.id] = on; V.EditorRefresh() end end)
    r.check:SetPoint("LEFT", 206, 0)
    r.multi = {}
    return r
  end)

  -- 5 · own questions for the sign-up
  local Q_KINDS = { "yesno", "choice", "number", "text" }
  ed.s5q = UI.Section(col, L.ED_QUESTIONS); ed.s5q:SetWidth(LEFT_W)
  ed.qHint = W.Text(col, 10, "muted"); ed.qHint:SetWidth(LEFT_W); ed.qHint:SetText(L.ED_Q_HINT)
  ed.qRows = W.Pool(col, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(LEFT_W, 50)
    r.edit = W.Edit(r, LEFT_W - 30 - 116, 22)
    r.edit:SetPoint("TOPLEFT", 0, 0)
    r.edit:SetMaxLetters(60)
    r.edit:SetScript("OnTextChanged", function(self, user)
      if user and ed.qs and ed.qs[r.index] then ed.qs[r.index].label = self:GetText() end
    end)
    r.kind = W.Dropdown(r, 110, function()
      local o = {}
      for _, k in ipairs(Q_KINDS) do o[#o + 1] = { k, L["ED_Q_KIND_" .. k] } end
      return o
    end, function() return ed.qs and ed.qs[r.index] and ed.qs[r.index].kind end, function(v)
      if ed.qs and ed.qs[r.index] then ed.qs[r.index].kind = v; V.EditorRefresh() end
    end)
    r.kind:SetPoint("LEFT", r.edit, "RIGHT", 6, 0)
    r.del = W.Button(r, "x", false, 22); r.del:SetWidth(24)
    r.del:SetPoint("LEFT", r.kind, "RIGHT", 6, 0)
    r.del:SetScript("OnClick", function() table.remove(ed.qs, r.index); V.EditorRefresh() end)
    r.req = W.Check(r, L.ED_Q_REQUIRED, function(_, on) if ed.qs and ed.qs[r.index] then ed.qs[r.index].required = on end end)
    r.req:SetPoint("TOPLEFT", r.edit, "BOTTOMLEFT", 2, -8)
    r.optsL = W.Text(r, 10, "muted"); r.optsL:SetText(L.ED_Q_OPTIONS)
    r.optsL:SetPoint("LEFT", r.req, "RIGHT", 70, 0)
    r.opts = W.Edit(r, 10, 22)
    r.opts:SetPoint("LEFT", r.optsL, "RIGHT", 6, 0); r.opts:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.opts:SetMaxLetters(130)
    r.opts:SetScript("OnTextChanged", function(self, user)
      if user and ed.qs and ed.qs[r.index] then ed.qs[r.index].opts = self:GetText() end
    end)
    return r
  end)
  ed.addQ = W.Button(col, L.ED_Q_ADD, false, 22)
  ed.addQ:SetScript("OnClick", function()
    if #ed.qs >= E.Q_MAX then return end
    ed.qs[#ed.qs + 1] = { kind = "yesno", label = "" }
    V.EditorRefresh()
    local r = ed.qRows.items[#ed.qs]
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
    if not t.missing and ns.Profile.IsTypeActive(t.id) and E.CanCreate(t.id) and E.TypeOpen(t.id) then types[#types + 1] = t end
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
  at(ed.name); y = y + 22 + 12
  -- leadership
  f.leaders = f.leaders or {}
  local raid = E.IsRaid(f.type)
  ed.lLead:SetText(raid and L.ED_LEAD_RAID or L.ED_LEAD)
  at(ed.lLead); y = y + 14
  local lx = 0
  for i, k in ipairs(f.leaders) do
    local b = ed.leadRows:Get(i)
    b.key = k
    local rl = raid and ns.Struct and ns.Struct.IsRaidLead(k)
    W.SetLabel(b, G.Display(k) .. (rl and (" |cffc9a8ef[" .. (L.ED_LEAD_RL or "RL") .. "]|r") or "") .. "  |cff9a8a7ax|r")
    b:SetWidth(b.label:GetStringWidth() + 18)
    if lx + b:GetWidth() > (col:GetWidth() or 500) - 260 and lx > 0 then lx = 0; y = y + 24 end
    at(b, lx); b:Show()
    lx = lx + b:GetWidth() + 4
  end
  ed.leadRows:HideFrom(#f.leaders + 1)
  at(ed.leadEdit, lx); ed.leadAdd:ClearAllPoints(); ed.leadAdd:SetPoint("LEFT", ed.leadEdit, "RIGHT", 4, 0)
  y = y + 24
  local lerr = E.CheckLeaders(f.type, f.leaders)
  ed.leadHint:SetText(lerr and ("|cffff805c" .. lerr .. "|r") or "")
  ed.leadHint:SetShown(lerr ~= nil)
  if lerr then at(ed.leadHint); y = y + 14 end
  y = y + 8

  -- 1b · settings of the type
  local defs = E.SettingDefs(f.type)
  ed.set = ed.set or {}
  local shown = 0
  if #defs > 0 then
    ed.sSet:SetText(L.ED_SETTINGS_OF:format(ns.Modules.TypeName(f.type)))
    at(ed.sSet); y = y + 24
    local values = E.Settings({ type = f.type, set = ed.set })
    for _, d in ipairs(defs) do
      local visible = true
      if type(d.showIf) == "function" then local ok, v = pcall(d.showIf, values); visible = ok and v and true or false end
      if visible and E.SET_KINDS[d.kind] then
        shown = shown + 1
        local r = ed.setRows:Get(shown)
        r.def = d
        r.label:SetText(E.FieldLabel(d))
        r.drop:Hide(); r.edit:Hide(); r.check:Hide(); r.hint:SetText("")
        for _, c in ipairs(r.multi) do c:Hide() end
        local v = values[d.id]
        local h = 24
        if d.kind == "choice" then
          r.drop:Show(); r.drop:Refresh()
        elseif d.kind == "check" then
          r.check:Show(); r.check:SetChecked(v)
        elseif d.kind == "multi" then
          local opts = E.SettingOptions(d, f)
          local on = {}
          for _, x in ipairs(type(v) == "table" and v or {}) do on[x] = true end
          for i, o in ipairs(opts) do
            local c = r.multi[i]
            if not c then
              c = W.Check(r, "", function(self, checked)
                local list = {}
                for j, cc in ipairs(r.multi) do if cc:IsShown() and cc:GetChecked() then list[#list + 1] = cc.value end end
                ed.set[r.def.id] = list
              end)
              r.multi[i] = c
            end
            c.value = o[1]; c.text:SetText(o[2]); c:SetChecked(on[o[1]])
            c:ClearAllPoints(); c:SetPoint("TOPLEFT", r, "TOPLEFT", 206 + ((i - 1) % 2) * 130, -4 - math.floor((i - 1) / 2) * 20)
            c:Show()
          end
          h = math.max(24, math.ceil(#opts / 2) * 20 + 6)
        else
          r.edit:Show()
          r.edit:SetNumeric(d.kind == "number")
          r.edit:SetWidth(d.kind == "text" and 220 or 90)
          if not r.edit:HasFocus() then
            local txt = v
            if d.kind == "date" and type(v) == "string" then local y4, m, dd = v:match("^(%d+)%-(%d+)%-(%d+)$"); txt = y4 and (dd .. "." .. m .. "." .. y4) or v end
            r.edit:SetText(txt ~= nil and tostring(txt) or "")
          end
          local hint = d.kind == "time" and "HH:MM" or d.kind == "date" and L.ED_DATE_HINT
            or (d.kind == "number" and (d.min or d.max)) and ((d.min or 0) .. "–" .. (d.max or "")) or ""
          r.hint:SetText(hint); r.hint:ClearAllPoints(); r.hint:SetPoint("LEFT", r.edit, "RIGHT", 8, 0)
        end
        r:SetHeight(h)
        at(r); y = y + h + 4
      end
    end
    y = y + 12
  end
  ed.sSet:SetShown(#defs > 0); ed.sSet.line:SetShown(#defs > 0)
  ed.setRows:HideFrom(shown + 1)

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
  local canRepeat = not season
  ed.lRep:SetShown(canRepeat); ed.rep:SetShown(canRepeat)
  local hasRep = canRepeat and (ed.repSel or "none") ~= "none"
  ed.lUntil:SetShown(hasRep); ed.until_:SetShown(hasRep); ed.untilHint:SetShown(hasRep)
  if canRepeat then
    at(ed.lRep); y = y + 14
    at(ed.rep); ed.rep:Refresh()
    if hasRep then
      ed.lUntil:ClearAllPoints(); ed.lUntil:SetPoint("LEFT", ed.rep, "RIGHT", 14, 0)
      ed.until_:ClearAllPoints(); ed.until_:SetPoint("LEFT", ed.lUntil, "RIGHT", 6, 0)
      ed.untilHint:ClearAllPoints(); ed.untilHint:SetPoint("LEFT", ed.until_, "RIGHT", 6, 0)
    end
    y = y + 30
  end
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
  y = y + 22 + 10
  at(ed.lLvl); y = y + 14
  at(ed.lvl)
  ed.lvlHint:ClearAllPoints(); ed.lvlHint:SetPoint("LEFT", ed.lvl, "RIGHT", 10, 0); ed.lvlHint:SetPoint("RIGHT", col, "LEFT", LEFT_W, 0)
  y = y + 22 + 10
  at(ed.remind)
  y = y + 14 + 16

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
  y = y + 16

  -- 5 · own questions
  at(ed.s5q); y = y + 24
  at(ed.qHint); y = y + ed.qHint:GetStringHeight() + 6
  for i, q in ipairs(ed.qs) do
    local r = ed.qRows:Get(i)
    r.index = i
    if not r.edit:HasFocus() and r.edit:GetText() ~= (q.label or "") then r.edit:SetText(q.label or "") end
    r.kind:Refresh()
    r.req:SetChecked(q.required)
    local choice = q.kind == "choice"
    r.optsL:SetShown(choice); r.opts:SetShown(choice)
    if choice and not r.opts:HasFocus() and r.opts:GetText() ~= (q.opts or "") then r.opts:SetText(q.opts or "") end
    at(r); y = y + 56
  end
  ed.qRows:HideFrom(#ed.qs + 1)
  ed.addQ:SetShown(#ed.qs < E.Q_MAX)
  if #ed.qs < E.Q_MAX then at(ed.addQ); y = y + 26 end
  ed.scroll:SetContentHeight(y + 8)
  V.EditorPreview()
end

function V.EditorPickType(id)
  local ed = V.panel.editor
  local f = ed.f
  local old = ns.Modules.TypeName(f.type)
  if f.type ~= id then ed.set = {} end
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
    local lv = typeLevel(t)
    ed.lvl:SetText(lv and tostring(lv) or "")
    ed.remind:SetChecked(t and t.remind)
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
  local lv = tonumber(ed.lvl:GetText())
  lines[#lines + 1] = (lv and lv > 1) and L.FACT_LEVEL:format(lv) or L.FACT_LEVEL_ALL
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
  local lerr = E.CheckLeaders(f.type, f.leaders)
  if lerr then ed.err:SetText(lerr); return end
  f.pts = tonumber(ed.pts:GetText())
  f.lvl = tonumber(ed.lvl:GetText())
  if f.lvl and f.lvl <= 1 then f.lvl = nil end
  f.remind = ed.remind:GetChecked() and true or false
  local old = {}
  for _, g in ipairs(f.goals or {}) do old[g.text] = g.done end
  local goals = {}
  for _, line in ipairs(ed.goals) do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and #goals < 8 then goals[#goals + 1] = { text = line, done = old[line] or false } end
  end
  f.goals = #goals > 0 and goals or nil
  -- own questions: keep the ids of existing ones, so answers stay with them
  local used, qs = {}, {}
  for _, q in ipairs(ed.qs) do if q.id then used[q.id] = true end end
  local nextId = 1
  for _, q in ipairs(ed.qs) do
    local label = (q.label or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if label ~= "" then
      if not q.id then
        while used["q" .. nextId] do nextId = nextId + 1 end
        q.id = "q" .. nextId; used[q.id] = true
      end
      local fq = { id = q.id, label = label, required = q.required and true or nil }
      if q.kind == "yesno" then
        fq.kind, fq.yn = "choice", true
      elseif q.kind == "choice" then
        fq.kind, fq.options = "choice", {}
        for part in (q.opts or ""):gmatch("[^,]+") do
          part = part:gsub("^%s+", ""):gsub("%s+$", "")
          if part ~= "" then fq.options[#fq.options + 1] = part end
        end
        if #fq.options < 2 then ed.err:SetText(L.ED_ERR_Q_OPTS:format(label)); return end
      else
        fq.kind = q.kind
      end
      qs[#qs + 1] = fq
    end
  end
  f.fields = E.CleanFields(qs)
  -- settings of the type: only valid values, then the type's own check
  local defs = E.SettingDefs(f.type)
  f.set = E.CleanSettings(f.type, ed.set, f)
  if #defs > 0 then
    for _, d in ipairs(defs) do
      local raw = ed.set and ed.set[d.id]
      if raw ~= nil and raw ~= "" and E.SettingValue(d, raw, f) == nil then
        ed.err:SetText(L.ED_ERR_SETTING:format(E.FieldLabel(d))); return
      end
    end
    local err = E.ValidateSettings(f.type, E.Settings({ type = f.type, set = f.set }))
    if err then ed.err:SetText(err); return end
  end
  -- repeat
  local sel = (f.kind ~= "season") and ed.repSel or "none"
  if sel and sel ~= "none" then
    local untilTs
    local txt = ed.until_:GetText():gsub("%s", "")
    if txt ~= "" then
      local dd, mm, yy = txt:match("^(%d%d?)%.(%d%d?)%.(%d%d%d%d)$")
      if not dd then ed.err:SetText(L.ED_ERR_SETTING:format(L.ED_REP_UNTIL)); return end
      untilTs = time({ year = tonumber(yy), month = tonumber(mm), day = tonumber(dd), hour = 23, min = 59 })
    end
    f.rep = { every = (sel == "week2") and "week" or sel, n = (sel == "week2") and 2 or 1, untilTs = untilTs }
  else
    f.rep = nil
  end
  local e
  if ed.ev then
    e = E.Get(ed.ev.id)
    if not e then V.ShowList(); return end
    for _, k in ipairs({ "type", "name", "desc", "kind", "start", "finish", "group", "gmin", "gmax", "lvl", "remind", "pts", "goals", "fields", "set", "rep", "leaders" }) do e[k] = f[k] end
    e.leader = f.leaders[1] or e.leader
    if e.kind == "season" then e.start = ns.Points.SeasonStart(); e.finish = ns.Points.SeasonEnd() end
    E.Save(e)
    -- a date of a series: only this one, or all later ones too
    local later = 0
    if e.series then
      for _, x in ipairs(ns.Series.Members(e.series)) do if (x.start or 0) > (e.start or 0) and x.status == "planned" then later = later + 1 end end
    end
    if later > 0 then
      local saved = e
      W.Dialog({ text = L.SERIES_EDIT_Q:format(later), accept = L.SERIES_ONLY_THIS, alt = L.SERIES_ALL_LATER,
        onAccept = function() end,
        onAlt = function() ns.Series.ApplyFollowing(saved); ns.Series.Fill() end })
    elseif e.rep then
      ns.Series.Fill()
    end
  else
    e = E.Create(f)
  end
  if e then V.OpenDetail(e) end
end

-- e: edit this event · template: copy of an event as a new one (same weekday and time, next date ahead)
-- preset: fields for a new event, e.g. { type = "raid_hyjal" }
function V.OpenEditor(e, template, preset)
  local p = V.panel
  -- opened before the events page was ever shown (help, a module button)
  if not p and ns.UI and ns.UI.Show then ns.UI.Show("events"); p = V.panel end
  if not p then return end
  if e and not E.CanManage(e) then return end
  if not e and not V.AnyCreate() then return end
  local ed = p.editor
  ed.ev = e
  local src = e or template
  ed.f = src and U.Copy(src) or { kind = "short", group = "none" }
  ed.f.leaders = src and U.Copy(E.Leaders(src)) or {}
  if #ed.f.leaders == 0 and G.MyKey() then ed.f.leaders = { ns.Persons and ns.Persons.MainOf(G.MyKey()) or G.MyKey() } end
  if preset and not src then
    for k, v in pairs(preset) do ed.f[k] = v end
    local t = ed.f.type and ns.Modules.Type(ed.f.type)
    if t then ed.f.kind = t.kind or ed.f.kind; ed.f.group = t.group or ed.f.group; ed.f.gmin, ed.f.gmax = t.gmin, t.gmax end
  end
  if template then
    for _, k in ipairs({ "id", "status", "signups", "attended", "leader", "by", "ts", "v", "started", "ended", "created" }) do ed.f[k] = nil end
    ed.f.leaders = U.Copy(E.Leaders(src))
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
      if not t.missing and ns.Profile.IsTypeActive(t.id) and E.CanCreate(t.id) and E.TypeOpen(t.id) then
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
  if not src and ed.f.lvl == nil then ed.f.lvl = typeLevel(ns.Modules.Type(ed.f.type)) end
  ed.lvl:SetText(ed.f.lvl and tostring(ed.f.lvl) or "")
  ed.remind:SetChecked(E.Remind(ed.f))
  ed.goals = {}
  for _, g in ipairs(ed.f.goals or {}) do ed.goals[#ed.goals + 1] = g.text end
  ed.goalsTouched = src ~= nil
  ed.qs = {}
  for _, q in ipairs(ed.f.fields or {}) do
    local opts = {}
    for _, o in ipairs(q.options or {}) do opts[#opts + 1] = type(o) == "table" and o[1] or o end
    ed.qs[#ed.qs + 1] = { id = q.id, label = q.label, required = q.required,
      kind = q.yn and "yesno" or q.kind, opts = (not q.yn) and table.concat(opts, ", ") or nil }
  end
  if #ed.goals == 0 and not src then
    local t = ns.Modules.Type(ed.f.type)
    for _, k in ipairs(t and t.goalKeys or {}) do ed.goals[#ed.goals + 1] = L[k] end
  end
  ed.set = U.Copy(type(src and src.set) == "table" and src.set or {})
  local r = src and src.rep
  ed.repSel = r and ((r.every == "week" and r.n == 2) and "week2" or r.every) or "none"
  ed.until_:SetText(r and r.untilTs and date("%d.%m.%Y", r.untilTs) or "")
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
  a.hint:SetSpacing(2)
  a.cancel = W.Button(a, CANCEL or "Cancel", false, 22)
  a.cancel:SetPoint("TOPRIGHT", 0, 0)
  a.cancel:SetScript("OnClick", function() V.OpenDetail(a.ev) end)
  a.ok = W.Button(a, L.END_AND_AWARD, true, 22)
  a.ok:SetPoint("RIGHT", a.cancel, "LEFT", -6, 0)
  a.ok:SetScript("OnClick", function()
    -- sending the result confirms a reported end
    if a.ev and ns.Contest.Pending(a.ev) then ns.Contest.ConfirmEnd(a.ev) end
    local sel, rows = {}, {}
    for _, r in ipairs(a.rows.items) do
      if r:IsShown() and r.key then
        if r.check:GetChecked() then sel[r.key] = true end
        local pp, bo = tonumber(r.pp:GetText()) or 0, tonumber(r.bo:GetText()) or 0
        if a.contest or pp ~= 0 or bo ~= 0 then
          rows[r.key] = { pp = pp, bo = bo, v = r.value, pl = r.place }
        end
      end
    end
    local note = a.note:GetText()
    E.End(a.ev, sel, { rows = rows, note = note ~= "" and note or nil })
    V.OpenDetail(a.ev)
  end)
  -- counting of a contest still runs: end it first
  a.stop = W.Button(a, L.CONTEST_STOP, false, 22)
  a.stop:SetPoint("RIGHT", a.ok, "LEFT", -6, 0)
  a.stop:SetScript("OnClick", function() ns.Contest.EndContest(a.ev, "leader"); V.RefreshAttendance() end)
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
  a.noteL = W.Text(a, 10, "muted"); a.noteL:SetText(L.RESULT_NOTE)
  a.noteL:SetPoint("LEFT", a.add, "RIGHT", 14, 0)
  a.note = W.Edit(a, 10, 22); a.note:SetMaxLetters(200)
  a.note:SetPoint("LEFT", a.noteL, "RIGHT", 6, 0); a.note:SetPoint("RIGHT", 0, 0)
  -- column heads
  local COLS = { name = 4, value = 300, place = 380, pp = 450, bo = 540 }
  a.COLS = COLS
  a.head = CreateFrame("Frame", nil, a)
  a.head:SetPoint("TOPLEFT", 0, -58); a.head:SetPoint("RIGHT", 0, 0); a.head:SetHeight(16)
  local function head(key, text)
    local fs = W.Text(a.head, 10, "muted"); fs:SetPoint("LEFT", COLS[key], 0); fs:SetText(text)
    a.head[key] = fs
  end
  head("name", L.RESULT_COL_NAME); head("value", L.RESULT_COL_VALUE); head("place", L.RESULT_COL_PLACE)
  head("pp", L.RESULT_COL_PLACEPTS); head("bo", L.RESULT_COL_BONUS)
  a.scroll = W.Scroll(a)
  a.scroll:SetPoint("TOPLEFT", 0, -78); a.scroll:SetPoint("BOTTOMRIGHT", 0, 30)
  a.rows = W.Pool(a.scroll.content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(24)
    r.check = W.Check(r, "", function(self, on) a.defaults[r.key] = on end)
    r.check:SetPoint("LEFT", COLS.name, 0)
    r.value = nil
    r.valueT = W.Text(r, 11, "text"); r.valueT:SetPoint("LEFT", COLS.value, 0)
    r.placeT = W.Text(r, 11, "title"); r.placeT:SetPoint("LEFT", COLS.place, 0)
    r.pp = W.Edit(r, 60, 20); r.pp:SetPoint("LEFT", COLS.pp, 0)
    r.bo = W.Edit(r, 60, 20); r.bo:SetPoint("LEFT", COLS.bo, 0)
    r.boWhy = W.Text(r, 9, "muted"); r.boWhy:SetPoint("LEFT", r.bo, "RIGHT", 6, 0); r.boWhy:SetPoint("RIGHT", 0, 0)
    r.boWhy:SetWordWrap(false)
    for _, ed in ipairs({ r.pp, r.bo }) do
      ed:SetScript("OnTextChanged", function(self, user)
        if not (user and r.key) then return end
        a.edits[r.key] = a.edits[r.key] or {}
        a.edits[r.key][self == r.pp and "pp" or "bo"] = self:GetText()
      end)
    end
    return r
  end)
end

function V.RefreshAttendance()
  local a = V.panel.att
  local e = a.ev
  local CT = ns.Contest
  a.contest = CT.Is(e)
  local cands = E.Candidates(e)
  local have = {}
  for _, c in ipairs(cands) do have[c.key] = true end
  -- everyone with a score of the contest
  local standings = a.contest and CT.Standings(e) or {}
  local byKey = {}
  for _, x in ipairs(standings) do
    byKey[x.key] = x
    if not have[x.key] then cands[#cands + 1] = { key = x.key, inGroup = false, signed = E.IsSigned(e, x.key), scored = true }; have[x.key] = true end
  end
  for key in pairs(a.extra) do
    if not have[key] then cands[#cands + 1] = { key = key, inGroup = false, signed = false, extra = true } end
  end
  -- contest: best first; otherwise by name
  if a.contest then
    table.sort(cands, function(x, y)
      local px, py = byKey[x.key] and byKey[x.key].place or 999, byKey[y.key] and byKey[y.key].place or 999
      if px ~= py then return px < py end
      return G.Display(x.key) < G.Display(y.key)
    end)
  end
  local per = tonumber(e.pts) or ns.Profile.Get().pts.participate
  local hint = L.ATTEND_HINT:format(per)
  local running = a.contest and not CT.Ended(e)
  if a.contest then hint = hint .. "\n" .. (running and U.Color(U.WARN, L.CONTEST_STILL_RUNS) or L.RESULT_HINT) end
  if a.contest and CT.Pending(e) then hint = hint .. "\n" .. U.Color(U.WARN, L.END_PENDING_RESULT:format(G.Display(e.cendBy or "?"), date("%H:%M", e.cend or 0))) end
  a.hint:SetText(hint)
  a.stop:SetShown(running)
  a.ok:SetEnabled(not running)
  for _, k in ipairs({ "value", "place", "pp" }) do a.head[k]:SetShown(a.contest) end
  local places = a.contest and CT.Places(e) or {}
  -- shared goal: reward for everyone when reached, bonus for the best group
  local goal = a.contest and CT.Goal(e)
  local reward = (goal and CT.GoalReached(e)) and goal.reward or 0
  local best = goal and CT.BestMembers(e) or {}
  if goal then
    local total = CT.Total(e)
    hint = hint .. "\n" .. (CT.GoalReached(e) and L.GOAL_HINT_OK:format(total, goal.target or 0, goal.reward, goal.bonus)
      or L.GOAL_HINT_MISSED:format(total, goal.target or 0))
    a.hint:SetText(hint)
  end
  for i, c in ipairs(cands) do
    local r = a.rows:Get(i)
    r.key = c.key
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 26); r:SetPoint("RIGHT", a.scroll.content, "RIGHT", 0, 0)
    local tag = c.inGroup and L.IN_GROUP or (c.signed and L.SIGNED or (c.scored and L.RESULT_SCORED or L.ADDED))
    r.check.text:SetText(G.Display(c.key) .. "  " .. U.Color(T.Hex(T.Current().muted), tag))
    if a.defaults[c.key] == nil then a.defaults[c.key] = c.inGroup or c.extra or c.scored or (byKey[c.key] ~= nil) or false end
    r.check:SetChecked(a.defaults[c.key])
    local x = byKey[c.key]
    r.value, r.place = x and x.value or nil, x and x.place or nil
    r.valueT:SetShown(a.contest); r.placeT:SetShown(a.contest); r.pp:SetShown(a.contest)
    r.valueT:SetText(x and CT.Format(e, x.value) or "–")
    r.placeT:SetText(x and (x.place .. ".") or "")
    local ed = a.edits[c.key] or {}
    local ppDef = ((x and x.place and places[x.place]) or 0) + reward
    local boDef = (x and x.bonus and tonumber(x.bonus.p) or 0) + ((goal and best[c.key] and reward > 0) and goal.bonus or 0)
    if not r.pp:HasFocus() then r.pp:SetText(ed.pp or tostring(ppDef)) end
    if not r.bo:HasFocus() then r.bo:SetText(ed.bo or tostring(boDef)) end
    r.boWhy:SetText(x and x.bonus and x.bonus.r and L[x.bonus.r] or "")
  end
  a.rows:HideFrom(#cands + 1)
  a.scroll:SetContentHeight(#cands * 26 + 8)
end
function V.OpenAttendance(e)
  local a = V.panel.att
  a.ev = e
  a.extra, a.defaults, a.edits = {}, {}, {}
  a.note:SetText("")
  a.title:SetText((ns.Contest.Is(e) and L.RESULT_TITLE or L.END_TITLE):format(e.name))
  V.RefreshAttendance()
  V.Mode("att")
end

---------------------------------------------------------------------------
-- "Report end" buttons (0.9): participants report, the referee confirms or
-- lets counting go on. Used in the detail page and the live window.
---------------------------------------------------------------------------
function V.EndButtons(parent)
  local b = {}
  b.report = W.Button(parent, L.END_REPORT, false, 20)
  b.confirm = W.Button(parent, L.END_CONFIRM, true, 20)
  b.resume = W.Button(parent, L.END_RESUME, false, 20)
  for _, x in ipairs({ b.report, b.confirm, b.resume }) do W.SetLabel(x, x.label:GetText()); x:Hide() end
  b.report:SetScript("OnClick", function()
    local e = b.ev
    if not e then return end
    W.Dialog({ text = L.END_REPORT_Q:format(e.name), accept = L.END_REPORT, onAccept = function() ns.Contest.ReportEnd(e, "report"); V.RefreshEndButtons(b) end })
  end)
  b.report:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.END_REPORT, 1, 0.82, 0)
    GameTooltip:AddLine(L.END_REPORT_TIP, 1, 1, 1, true); GameTooltip:Show()
  end)
  b.report:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b.confirm:SetScript("OnClick", function() if b.ev then ns.Contest.ConfirmEnd(b.ev); V.RefreshEndButtons(b) end end)
  b.resume:SetScript("OnClick", function() if b.ev then ns.Contest.Resume(b.ev); V.RefreshEndButtons(b) end end)
  return b
end

-- shows the fitting buttons; returns how many are shown
function V.RefreshEndButtons(b, e)
  e = e or b.ev
  b.ev = e
  local CT = ns.Contest
  local pending = e and CT.Pending(e)
  local lead = e and E.CanManage(e)
  b.report:SetShown(e and not pending and CT.CanReport(e) or false)
  b.confirm:SetShown(pending and lead or false)
  b.resume:SetShown(pending and lead or false)
  local n = 0
  for _, x in ipairs({ b.report, b.confirm, b.resume }) do if x:IsShown() then n = n + 1 end end
  return n
end

---------------------------------------------------------------------------
-- Contest standings / result as text lines (detail page, standings window)
---------------------------------------------------------------------------
function V.ContestLines(e, max)
  local CT = ns.Contest
  if not CT.Is(e) then return nil end
  local th = T.Current()
  local out = {}
  local me = G.MyKey()
  if e.result and e.result.rows then
    out[#out + 1] = U.Color(T.Hex(th.title), L.RESULT_FINAL)
    for _, r in ipairs(e.result.rows) do
      local pts = (r.pp or 0) + (r.bo or 0)
      local line = (r.pl and (r.pl .. ". ") or "   ") .. G.Display(r.k) .. (r.v and ("  " .. CT.Format(e, r.v)) or "") .. (pts ~= 0 and U.Color(T.Hex(th.muted), "  +" .. pts) or "")
      out[#out + 1] = "  " .. (r.k == me and U.Color(U.GOLD, line) or line)
    end
    if e.result.note then out[#out + 1] = U.Color(T.Hex(th.muted), "  »" .. e.result.note .. "« – " .. G.Display(e.result.by)) end
    return out
  end
  local list = CT.Standings(e)
  local ended = CT.Ended(e)
  local goal = CT.Goal(e)
  if CT.Pending(e) then
    out[#out + 1] = U.Color(U.WARN, L.END_PENDING:format(G.Display(e.cendBy or "?"), date("%H:%M", e.cend or 0)))
  end
  if goal then
    local total = CT.Total(e)
    local tgt = goal.target or 0
    local filled = tgt > 0 and math.min(20, math.floor(total / tgt * 20)) or 0
    local bar = U.Color(U.GOLD, string.rep("|", filled)) .. U.Color(T.Hex(th.muted), string.rep("|", 20 - filled))
    out[#out + 1] = U.Color(T.Hex(th.title), L.GOAL_HEAD) .. "  " .. total .. " / " .. tgt .. (CT.GoalReached(e) and ("  " .. U.Color(U.GOLD, L.GOAL_DONE)) or "")
    out[#out + 1] = "  " .. bar
    local groups = CT.Groups(e)
    if #groups > 1 or (groups[1] and groups[1].id ~= "x") then
      out[#out + 1] = U.Color(T.Hex(th.title), L.GOAL_GROUPS)
      local myKey = G.MyKey()
      for _, g in ipairs(groups) do
        local mine = false
        for _, k in ipairs(g.members or {}) do if k == myKey then mine = true end end
        local line = g.name .. "  " .. g.value .. (g.best and ("  " .. L.GOAL_BONUS_TAG:format(goal.bonus)) or "")
        out[#out + 1] = "  " .. (mine and U.Color(U.GOLD, line) or line)
      end
    end
  end
  local head = ended and L.STANDINGS_WAIT or (CT.Running(e) and L.STANDINGS_LIVE or L.STANDINGS)
  out[#out + 1] = U.Color(T.Hex(th.title), head)
  if #list == 0 then out[#out + 1] = "  " .. L.STANDINGS_NONE; return out end
  for i, x in ipairs(list) do
    -- the first ones, and the own line also further down
    if i <= (max or 10) or x.key == me then
      local line = x.place .. ". " .. G.Display(x.key) .. "  " .. CT.Format(e, x.value)
      if x.key == me then line = U.Color(U.GOLD, line) end
      out[#out + 1] = "  " .. line
    end
  end
  return out
end

-- a small live window with the standings (API.ShowStandings)
function V.ShowStandings(e)
  if not e then return end
  local win = ns.Float.Get("standings", { title = "", width = 240, height = 220, point = { "RIGHT", -60, 60 } })
  if not win.text then
    win.text = W.Text(win.content, 11, "text"); win.text:SetPoint("TOPLEFT", 0, 0); win.text:SetPoint("RIGHT", 0, 0)
    win.text:SetSpacing(2)
    ns.On("CONTEST_SCORE", function(ev) if win:IsShown() and win.ev and ev.id == win.ev.id then V.ShowStandings(win.ev) end end)
    ns.On("CONTEST_END", function(ev) if win:IsShown() and win.ev and ev.id == win.ev.id then V.ShowStandings(win.ev) end end)
  end
  if not win.endB then
    win.endB = V.EndButtons(win.content)
    win.endB.report:SetPoint("BOTTOMLEFT", 0, 0)
    win.endB.confirm:SetPoint("BOTTOMLEFT", 0, 0)
    win.endB.resume:SetPoint("LEFT", win.endB.confirm, "RIGHT", 4, 0)
    for _, ev in ipairs({ "CONTEST_REPORT", "CONTEST_RESUME" }) do
      ns.On(ev, function(x) if win:IsShown() and win.ev and x.id == win.ev.id then V.ShowStandings(win.ev) end end)
    end
  end
  win.ev = e
  win:SetTitle(e.name)
  local lines = V.ContestLines(e, 8) or {}
  win.text:SetText(table.concat(lines, "\n"))
  local nb = V.RefreshEndButtons(win.endB, e)
  win:Resize(240, math.max(80, 36 + win.text:GetStringHeight() + (nb > 0 and 28 or 0)))
  win:Open()
end

---------------------------------------------------------------------------
-- Rules of an event type (API 7): cards with symbol, title and text
---------------------------------------------------------------------------
V.RULE_ICONS = {
  fish = "Interface\\Icons\\INV_Misc_Fish_02", trophy = W.ICONS .. "ach", clock = W.ICONS .. "events",
  warning = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", map = "Interface\\Icons\\INV_Misc_Map_01",
  sword = W.ICONS .. "pvp", info = W.ICONS .. "help", check = W.ICONS .. "check", coin = "Interface\\Icons\\INV_Misc_Coin_01",
  group = W.ICONS .. "home", star = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
}

function V.RulesText(e)
  local list = E.Rules(e)
  if not list then return nil end
  local parts = {}
  for _, r in ipairs(list) do parts[#parts + 1] = (r.title ~= "" and (U.Color(T.Hex(T.Current().title), r.title) .. "\n") or "") .. r.text end
  return table.concat(parts, "\n\n")
end

function V.ShowRules(e)
  local list = E.Rules(e)
  if not list then return end
  local win = ns.Float.Get("rules", { title = "", width = 380, height = 420, strata = "DIALOG", point = { "CENTER", 0, 40 } })
  win:SetFrameStrata("DIALOG"); win:Raise()
  win:SetTitle(L.RULES_TITLE:format(e.name))
  if not win.scroll then
    win.scroll = W.Scroll(win.content)
    win.scroll:SetAllPoints()
    win.cards = W.Pool(win.scroll.content, function(parent)
      local c = W.Box(parent, 10, 10, "panel2")
      c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(26, 26); c.icon:SetPoint("TOPLEFT", 8, -8)
      c.title = W.Text(c, 12, "title"); c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, 0); c.title:SetPoint("RIGHT", -8, 0)
      c.text = W.Text(c, 11, "text"); c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4); c.text:SetPoint("RIGHT", -8, 0)
      c.text:SetSpacing(2)
      return c
    end)
  end
  local y, w = 0, win.content:GetWidth() - 18
  for i, r in ipairs(list) do
    local c = win.cards:Get(i)
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y); c:SetWidth(w)
    local tex = r.icon and (V.RULE_ICONS[r.icon] or (tostring(r.icon):find("\\") and r.icon)) or V.RULE_ICONS.info
    c.icon:SetTexture(tex)
    c.title:SetText(r.title); c.text:SetText(r.text)
    local h = math.max(42, 8 + c.title:GetStringHeight() + 4 + c.text:GetStringHeight() + 10)
    c:SetHeight(h)
    y = y + h + 6
  end
  win.cards:HideFrom(#list + 1)
  win.scroll:SetContentHeight(y)
  win:Open()
end

-- the "?" in the header shows the rules while an event of such a type is open
UI.HelpOverride = function(view)
  if view ~= "events" or not V.panel or not V.panel.detail or not V.panel.detail:IsShown() then return nil end
  local e = V.panel.detail.ev
  local text = e and V.RulesText(e)
  if text then return L.RULES_TITLE:format(e.name), text end
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
function V.RefreshDetail() if V.panel and V.panel.mode == "detail" then refreshDetail(V.panel) end end

function V.OpenDetail(e, tab)
  -- first opening: the page is built with the next refresh, show the event then
  if not V.panel then V.pending = e; V.pendingTab = tab; UI.Show("events"); return end
  if not e then return V.ShowList() end
  if UI.Frame() == nil or not UI.Frame():IsShown() or UI.Frame().current ~= "events" then UI.Show("events") end
  local d = V.panel.detail
  if tab or not (d.ev and d.ev.id == e.id) then d.tab = tab or "info" end
  d.ev = e
  V.Mode("detail")
end

-- Straight to the own sign-up of an event (from the invitation popup):
-- the detail page with a short glow around "Your sign-up"
function V.OpenSignup(e)
  if not e then return end
  local first = V.panel == nil
  UI.Show("events")
  V.OpenDetail(e)
  if first then ns.Schedule("gemSignupGlow", 0.2, function() V.GlowSignup() end) else V.GlowSignup() end
end

function V.GlowSignup()
  local d = V.panel and V.panel.detail
  if not d or not d.my or not d.my:IsShown() then return end
  if not d.glow then
    local g = d.my:CreateTexture(nil, "OVERLAY")
    g:SetPoint("TOPLEFT", -3, 3); g:SetPoint("BOTTOMRIGHT", 3, -3)
    local c = T.Current().title
    g:SetColorTexture(c[1], c[2], c[3], 0.22)
    g:SetBlendMode("ADD")
    g:SetAlpha(0)
    local ag = g:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.35); a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.6); a2:SetOrder(2)
    ag:SetLooping("NONE")
    local n = 0
    ag:SetScript("OnFinished", function() n = n + 1; if n < 3 then ag:Play() end end)
    d.glow, d.glowAnim = g, ag
    d.glowReset = function() n = 0 end
  end
  d.glowReset()
  d.glowAnim:Stop(); d.glowAnim:Play()
end

UI.RegisterView("events", {
  label = function() return L.TAB_EVENTS end,
  build = function(p)
    V.panel = p
    buildList(p); buildDetail(p); buildEditor(p); buildAttendance(p)
    p.mode = "list"
    if V.pending then p.detail.ev = V.pending; p.detail.tab = V.pendingTab or "info"; V.pendingTab = nil; p.mode = "detail"; p.list:Hide(); p.detail:Show(); p.editor:Hide(); p.att:Hide(); V.pending = nil end
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
