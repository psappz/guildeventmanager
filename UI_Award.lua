local ADDON, ns = ...
-- Honor book, two more tabs:
--  * "Add GP" (managers only): book GP for one or many members by hand, with a
--    reason. Above the guild master's limit per entry the entry becomes a
--    request; the guild master confirms or declines it here.
--  * "Audit" (everybody): entries by hand and corrections per booker, so that
--    nothing unusual goes unseen.
local U, G, T, W, UI, Pts, E = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI, ns.Points, ns.Events
local L = ns.L
local A = { sel = {}, filter = "", pot = "event", ev = nil }
local AUD = { period = "week" }

local ROW_H = 18

local function potOptions()
  local o = {}
  for _, p in ipairs(ns.Modules.pots) do
    if p.id ~= "ach" then o[#o + 1] = { p.id, p.name or L[p.nameKey] or p.id } end
  end
  return o
end

local function eventOptions()
  local o = { { "none", L.AW_NOEVENT } }
  local now = U.Now()
  local list = E.List(function(e) return e.start and math.abs(now - e.start) < 30 * 86400 and e.status ~= "cancelled" end)
  table.sort(list, function(a, b) return a.start > b.start end)
  for i = 1, math.min(#list, 25) do
    local e = list[i]
    o[#o + 1] = { e.id, date("%d.%m. ", e.start) .. (e.name or "?") }
  end
  return o
end

local function members()
  local out = {}
  local f = A.filter:lower()
  for key, r in pairs(G.roster) do
    if f == "" or tostring(r.name):lower():find(f, 1, true) then out[#out + 1] = key end
  end
  table.sort(out, function(a, b)
    local ra, rb = G.roster[a], G.roster[b]
    if (ra.online and 1 or 0) ~= (rb.online and 1 or 0) then return ra.online and true or false end
    return tostring(ra.name) < tostring(rb.name)
  end)
  return out
end

local function selectedCount()
  local n = 0
  for k, on in pairs(A.sel) do if on and G.roster[k] then n = n + 1 end end
  return n
end

---------------------------------------------------------------------------
-- Add GP
---------------------------------------------------------------------------
local function buildAward(p)
  local th = T.Current()
  -- members (left)
  local left = W.Box(p, 270, 10, "panel2")
  left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", 0, 0)
  p.mHead = W.Text(left, 11, "title"); p.mHead:SetPoint("TOPLEFT", 10, -8)
  p.search = W.Edit(left, 150, 20); p.search:SetPoint("TOPLEFT", 10, -26)
  p.search:SetScript("OnTextChanged", function(self) A.filter = self:GetText() or ""; UI.Refresh() end)
  p.searchHint = W.Text(p.search, 10, "muted"); p.searchHint:SetPoint("LEFT", 6, 0); p.searchHint:SetText(L.AW_SEARCH)
  p.bAll = W.Button(left, L.AW_ALL, false, 20); p.bAll:SetPoint("LEFT", p.search, "RIGHT", 4, 0)
  p.bAll:SetScript("OnClick", function() for _, k in ipairs(members()) do A.sel[k] = true end; UI.Refresh() end)
  p.bNone = W.Button(left, L.AW_NONE, false, 20); p.bNone:SetPoint("LEFT", p.bAll, "RIGHT", 4, 0)
  p.bNone:SetScript("OnClick", function() wipe(A.sel); UI.Refresh() end)
  p.bOnline = W.Button(left, L.AW_ONLINE, false, 20); p.bOnline:SetPoint("TOPLEFT", p.search, "BOTTOMLEFT", 0, -4)
  p.bOnline:SetScript("OnClick", function()
    for k, r in pairs(G.roster) do if r.online then A.sel[k] = true end end
    UI.Refresh()
  end)
  p.count = W.Text(left, 10, "muted"); p.count:SetPoint("LEFT", p.bOnline, "RIGHT", 8, 0)
  p.list = W.Scroll(left)
  p.list:SetPoint("TOPLEFT", 8, -76); p.list:SetPoint("BOTTOMRIGHT", -8, 8)
  p.rows = W.Pool(p.list.content, function(parent)
    local r = W.Check(parent, "", function(self, on) A.sel[self.key] = on or nil; UI.Refresh() end)
    r.rank = W.Text(r, 10, "muted"); r.rank:SetPoint("LEFT", r.text, "RIGHT", 6, 0)
    return r
  end)

  -- form (right)
  local x = 290
  local function label(text, y)
    local l = W.Text(p, 10, "muted"); l:SetPoint("TOPLEFT", x, y); l:SetText(text)
    return l
  end
  p.fHead = UI.Section(p, L.AW_TAB); p.fHead:SetPoint("TOPLEFT", x, 0); p.fHead:SetPoint("RIGHT", 0, 0)
  local lp = label(L.AW_POT, -26)
  p.pot = W.Dropdown(p, 150, potOptions, function() return A.pot end, function(v) A.pot = v end)
  p.pot:SetPoint("TOPLEFT", lp, "BOTTOMLEFT", 0, -3)
  local la = W.Text(p, 10, "muted"); la:SetPoint("TOPLEFT", lp, "TOPLEFT", 166, 0); la:SetText(L.AW_AMOUNT)
  p.amt = W.Edit(p, 90, 22); p.amt:SetPoint("TOPLEFT", la, "BOTTOMLEFT", 0, -3); p.amt:SetText("10")
  local lr = label(L.AW_REASON, -74)
  p.reason = W.Edit(p, 360, 22); p.reason:SetPoint("TOPLEFT", lr, "BOTTOMLEFT", 0, -3)
  p.reason:SetMaxLetters(80)
  local le = label(L.AW_EVENT, -122)
  p.ev = W.Dropdown(p, 360, eventOptions, function() return A.ev or "none" end, function(v) A.ev = (v ~= "none") and v or nil end)
  p.ev:SetPoint("TOPLEFT", le, "BOTTOMLEFT", 0, -3)
  p.capHint = W.Text(p, 10, "muted"); p.capHint:SetPoint("TOPLEFT", p.ev, "BOTTOMLEFT", 0, -8); p.capHint:SetWidth(420)
  p.book = W.Button(p, L.AW_BOOK, true, 24); p.book:SetPoint("TOPLEFT", p.capHint, "BOTTOMLEFT", 0, -8)
  p.msg = W.Text(p, 10, "text"); p.msg:SetPoint("LEFT", p.book, "RIGHT", 10, 0); p.msg:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  p.book:SetScript("OnClick", function()
    local who = {}
    for k, on in pairs(A.sel) do if on and G.roster[k] then who[#who + 1] = k end end
    local amt = tonumber((p.amt:GetText() or ""):match("^%s*(%-?%d+)%s*$"))
    local why = (p.reason:GetText() or ""):match("^%s*(.-)%s*$")
    if #who == 0 then p.msg:SetText(U.Color(U.WARN, L.AW_ERR_WHO)); return end
    if not amt or amt == 0 then p.msg:SetText(U.Color(U.WARN, L.AW_ERR_AMT)); return end
    if why == "" then p.msg:SetText(U.Color(U.WARN, L.AW_ERR_WHY)); return end
    local done, asked = 0, 0
    table.sort(who)
    for _, k in ipairs(who) do
      local e, req = Pts.Add(k, A.pot, amt, "manual", A.ev, why)
      if e then done = done + 1 elseif req then asked = asked + 1 end
    end
    p.msg:SetText(L.AW_DONE:format(done, asked))
    if done > 0 then wipe(A.sel); p.reason:SetText("") end
    UI.Refresh()
  end)

  -- limit (guild master)
  p.capL = label(L.AW_CAP_LABEL, -250)
  p.cap = W.Edit(p, 70, 22); p.cap:SetPoint("TOPLEFT", p.capL, "BOTTOMLEFT", 0, -3)
  p.capSave = W.Button(p, L.SAVE, false, 22); p.capSave:SetPoint("LEFT", p.cap, "RIGHT", 6, 0)
  p.capSave:SetScript("OnClick", function()
    local v = tonumber((p.cap:GetText() or ""):match("%d+"))
    if not v then return end
    ns.Profile.Update(function(pr) pr.managerCap = math.max(0, math.floor(v)) end)
    U.Print(L.SAVED)
  end)
  p.capNote = W.Text(p, 10, "muted"); p.capNote:SetPoint("LEFT", p.capSave, "RIGHT", 8, 0); p.capNote:SetPoint("RIGHT", p, "RIGHT", 0, 0)

  -- requests to the guild master
  p.rHead = UI.Section(p, L.AW_REQS); p.rHead:SetPoint("TOPLEFT", x, -304); p.rHead:SetPoint("RIGHT", 0, 0)
  p.rBox = W.Box(p, 10, 10, "panel2")
  p.rBox:SetPoint("TOPLEFT", x, -326); p.rBox:SetPoint("BOTTOMRIGHT", 0, 18)
  p.rScroll = W.Scroll(p.rBox)
  p.rScroll:SetPoint("TOPLEFT", 6, -6); p.rScroll:SetPoint("BOTTOMRIGHT", -6, 6)
  p.rNone = W.Text(p.rBox, 10, "muted"); p.rNone:SetPoint("TOPLEFT", 10, -10); p.rNone:SetText(L.AW_REQS_NONE)
  p.reqs = W.Pool(p.rScroll.content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(24)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 2, 0); r.text:SetWordWrap(false)
    r.no = W.Button(r, L.AW_REJECT, false, 20); r.no:SetPoint("RIGHT", 0, 0)
    r.ok = W.Button(r, L.AW_APPROVE, true, 20); r.ok:SetPoint("RIGHT", r.no, "LEFT", -4, 0)
    r.text:SetPoint("RIGHT", r.ok, "LEFT", -6, 0)
    r.ok:SetScript("OnClick", function(self) Pts.Decide(self:GetParent().id, true) end)
    r.no:SetScript("OnClick", function(self) Pts.Decide(self:GetParent().id, false) end)
    return r
  end)
  p.offNote = W.Text(p, 9, "muted"); p.offNote:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", x, 2); p.offNote:SetPoint("RIGHT", 0, 0)
  p.offNote:SetText(L.AW_OFFICER_NOTE)
end

local function refreshAward(p)
  local manager, gm = G.IsManager(), Pts.IsGM()
  p.mHead:SetText(L.AW_MEMBERS)
  p.searchHint:SetShown((p.search:GetText() or "") == "" and not p.search:HasFocus())
  local list = members()
  local w = p.list:GetWidth()
  for i, k in ipairs(list) do
    local r = p.rows:Get(i)
    r.key = k
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 2, -(i - 1) * ROW_H - 2)
    local m = G.roster[k]
    r.text:SetText(m.online and m.name or U.Color("ff8a8580", m.name))
    r.rank:SetText(m.rankName or "")
    r:SetChecked(A.sel[k] and true or false)
  end
  p.rows:HideFrom(#list + 1)
  p.list:SetContentHeight(#list * ROW_H + 4)
  p.count:SetText(L.AW_SELECTED:format(selectedCount()))
  p.pot:Refresh(); p.ev:Refresh()
  local cap = Pts.Cap()
  p.capHint:SetText(gm and L.AW_CAP_GMNOTE or (cap > 0 and L.AW_CAP_HINT:format(cap) or L.AW_CAP_NONE))
  p.book:SetEnabled(manager)
  if not p.cap:HasFocus() then p.cap:SetText(tostring(cap)) end
  p.cap:SetEnabled(gm); p.capSave:SetShown(gm)
  p.capNote:SetText(gm and "" or L.AW_CAP_GM)
  -- requests: the guild master decides, officers see their own
  local reqs = {}
  for _, r in ipairs(Pts.OpenRequests()) do
    if gm or r.by == G.MyKey() then reqs[#reqs + 1] = r end
  end
  for i, r in ipairs(reqs) do
    local row = p.reqs:Get(i)
    row.id = r.id
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(i - 1) * 26); row:SetPoint("RIGHT", p.rScroll.content, "RIGHT", 0, 0)
    row.text:SetText(L.AW_REQ_LINE:format(G.Display(r.by), r.amt, G.Display(r.who), r.note or "–"))
    row.ok:SetShown(gm); row.no:SetShown(gm)
  end
  p.reqs:HideFrom(#reqs + 1)
  p.rScroll:SetContentHeight(#reqs * 26 + 2)
  p.rNone:SetShown(#reqs == 0)
end

---------------------------------------------------------------------------
-- Audit
---------------------------------------------------------------------------
local AUD_COLS = { { "by", 0 }, { "n", 80 }, { "plus", 80 }, { "minus", 80 }, { "max", 80 }, { "rev", 90 } }

local function auditEntries()
  local since = AUD.period == "week" and Pts.PeriodStart("week") or Pts.PeriodStart("season")
  return Pts.Entries(function(e)
    return (e.ts or 0) >= since and (e.why == "manual" or e.why == "revert" or e.ask ~= nil)
  end)
end

local function buildAudit(p)
  p.head = UI.Section(p, L.AUD_HEAD); p.head:SetPoint("TOPLEFT", 0, 0); p.head:SetPoint("RIGHT", 0, 0)
  p.chips = UI.ChipRow(p, function() return { { "week", L.AUD_WEEK }, { "season", L.AUD_SEASON } } end,
    function() return AUD.period end, function(v) AUD.period = v; UI.Refresh() end)
  p.chips:SetPoint("TOPLEFT", 0, -22); p.chips:SetWidth(300)
  p.hint = W.Text(p, 10, "muted"); p.hint:SetPoint("TOPLEFT", p.chips, "BOTTOMLEFT", 0, -4); p.hint:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  p.hint:SetJustifyH("LEFT"); p.hint:SetText(L.AUD_HINT)
  p.tBox = W.Box(p, 10, 150, "panel2")
  p.tBox:SetPoint("TOPLEFT", p.hint, "BOTTOMLEFT", 0, -8); p.tBox:SetPoint("RIGHT", 0, 0)
  p.th = {}
  for i, c in ipairs(AUD_COLS) do
    local h = W.Text(p.tBox, 10, "title")
    h:SetText(L["AUD_" .. c[1]:upper()] or c[1])
    if i > 1 then h:SetJustifyH("RIGHT") end
    p.th[i] = h
  end
  p.tLine = p.tBox:CreateTexture(nil, "ARTWORK"); p.tLine:SetHeight(1)
  p.tRows = W.Pool(p.tBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(18)
    r.c = {}
    for i = 1, #AUD_COLS do
      r.c[i] = W.Text(r, 10, "text")
      if i > 1 then r.c[i]:SetJustifyH("RIGHT") end
    end
    return r
  end)
  p.lHead = UI.Section(p, L.AUD_LIST); p.lHead:SetPoint("TOPLEFT", p.tBox, "BOTTOMLEFT", 0, -10); p.lHead:SetPoint("RIGHT", 0, 0)
  p.lBox = W.Box(p, 10, 10, "panel2")
  p.lBox:SetPoint("TOPLEFT", p.lHead, "BOTTOMLEFT", 0, -6); p.lBox:SetPoint("BOTTOMRIGHT", 0, 0)
  p.lScroll = W.Scroll(p.lBox)
  p.lScroll:SetPoint("TOPLEFT", 8, -6); p.lScroll:SetPoint("BOTTOMRIGHT", -8, 6)
  p.none = W.Text(p.lBox, 10, "muted"); p.none:SetPoint("TOPLEFT", 10, -10); p.none:SetText(L.AUD_NONE)
  p.lRows = W.Pool(p.lScroll.content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(18)
    r.when = W.Text(r, 10, "muted"); r.when:SetPoint("LEFT", 0, 0); r.when:SetWidth(80)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 86, 0); r.text:SetWordWrap(false)
    r.amt = W.Text(r, 10, "title"); r.amt:SetPoint("RIGHT", 0, 0); r.amt:SetJustifyH("RIGHT")
    r.text:SetPoint("RIGHT", r.amt, "LEFT", -10, 0)
    return r
  end)
end

local function refreshAudit(p)
  local th = T.Current()
  p.chips:Refresh()
  local w = p.tBox:GetWidth()
  if not w or w < 100 then w = 840 end
  -- column positions
  local fixed = 0
  for i = 2, #AUD_COLS do fixed = fixed + AUD_COLS[i][2] end
  local xs, x = {}, 10
  for i, c in ipairs(AUD_COLS) do
    local cw = (i == 1) and (w - 20 - fixed) or c[2]
    xs[i] = { x, cw }
    x = x + cw
  end
  for i, h in ipairs(p.th) do
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", xs[i][1], -8); h:SetWidth(xs[i][2] - (i > 1 and 6 or 0))
  end
  p.tLine:ClearAllPoints(); p.tLine:SetPoint("TOPLEFT", 10, -24); p.tLine:SetPoint("TOPRIGHT", -10, -24)
  p.tLine:SetColorTexture(th.line[1], th.line[2], th.line[3], 0.8)
  local entries = auditEntries()
  local by, order = {}, {}
  local cap = Pts.Cap()
  for _, e in ipairs(entries) do
    local k = e.by or "?"
    local b = by[k]
    if not b then b = { key = k, n = 0, plus = 0, minus = 0, max = 0, rev = 0, flag = false }; by[k] = b; order[#order + 1] = b end
    b.n = b.n + 1
    local a = tonumber(e.amt) or 0
    if a > 0 then b.plus = b.plus + a else b.minus = b.minus + a end
    if math.abs(a) > math.abs(b.max) then b.max = a end
    if e.why == "revert" then b.rev = b.rev + 1 end
    if cap > 0 and math.abs(a) > cap and G.RankOf(k) ~= 0 then b.flag = true end
  end
  table.sort(order, function(a, b) return (a.plus - a.minus) > (b.plus - b.minus) end)
  local shown = math.min(#order, 6)
  for i = 1, shown do
    local b = order[i]
    local r = p.tRows:Get(i)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -28 - (i - 1) * 18); r:SetPoint("RIGHT", 0, 0)
    local vals = { G.Display(b.key) .. (b.flag and ("  " .. U.Color(U.WARN, L.AUD_FLAG)) or ""), b.n, "+" .. b.plus, b.minus, b.max, b.rev }
    for c = 1, #AUD_COLS do
      local fs = r.c[c]
      fs:ClearAllPoints(); fs:SetPoint("LEFT", xs[c][1], 0); fs:SetWidth(xs[c][2] - (c > 1 and 6 or 0))
      fs:SetText(tostring(vals[c]))
    end
  end
  p.tRows:HideFrom(shown + 1)
  -- single entries
  for i, e in ipairs(entries) do
    local r = p.lRows:Get(i)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 18); r:SetPoint("RIGHT", p.lScroll.content, "RIGHT", 0, 0)
    r.when:SetText(date("%d.%m. %H:%M", e.ts or 0))
    local t = G.Display(e.by) .. " » " .. G.Display(e.who)
    if e.note and e.why ~= "revert" then t = t .. " · " .. tostring(e.note) end
    if e.why == "revert" then t = t .. " · " .. L.AUD_REV end
    if e.ask then t = t .. " · " .. L.AUD_ASKED:format(G.Display(e.ask)) end
    r.text:SetText(t)
    local a = tonumber(e.amt) or 0
    r.amt:SetText((a > 0 and "+" or "") .. a .. " " .. U.Dot())
  end
  p.lRows:HideFrom(#entries + 1)
  p.lScroll:SetContentHeight(#entries * 18 + 2)
  p.none:SetShown(#entries == 0)
end

UI.AddTab("ledgeraward", {
  parent = "ledger", pos = 2,
  label = function() return L.AW_TAB end,
  shown = function() return G.IsManager() end,
  build = buildAward, refresh = refreshAward,
})
UI.AddTab("ledgeraudit", {
  parent = "ledger", pos = 3,
  label = function() return L.AUD_TAB end,
  build = buildAudit, refresh = refreshAudit,
})
