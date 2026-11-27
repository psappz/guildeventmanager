local ADDON, ns = ...
-- Achievements tab: own progress, earned plaques, and (for managers) the
-- settings of every achievement: threshold, points, name, honor name, duration.
local U, G, T, W, UI, A = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI, ns.Achievements
local L = ns.L
local V = {}

local ROW_H = 58
local GROW_H = 66   -- guild achievement cards

local function build(p)
  local th = T.Current()
  local head = UI.Section(p, L.GA_TAB)
  head:SetPoint("TOPLEFT", 0, 0)
  p.mineHint = W.Text(p, 10, "muted")
  p.mineHint:SetPoint("TOPLEFT", 0, -22); p.mineHint:SetPoint("RIGHT", p, "RIGHT", -290, 0)
  p.mineHint:SetWordWrap(false)
  p.mineHint:SetText(L.GA_TAB_HINT)
  p.total = W.Text(p, 11, "muted")
  p.preview = W.Button(p, L.SHOW_PLAQUE, false, 20)
  p.preview:SetPoint("TOPRIGHT", 0, 2)
  p.preview:SetScript("OnClick", function() ns.Plaque.Test() end)
  p.total:SetPoint("RIGHT", p.preview, "LEFT", -10, 0)
  head.line:SetPoint("RIGHT", p.total, "LEFT", -8, 0)

  p.scroll = W.Scroll(p)
  p.scroll:SetPoint("TOPLEFT", 0, -42); p.scroll:SetPoint("BOTTOMRIGHT", -290, 0)
  p.rows = W.Pool(p.scroll.content, function(parent)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetHeight(ROW_H - 6)
    W.Paint(r, th.panel2, th.line)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(36, 36); r.icon:SetPoint("LEFT", 8, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = W.Text(r, 12, "text"); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 0)
    r.desc = W.Text(r, 10, "muted"); r.desc:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3); r.desc:SetPoint("RIGHT", -90, 0); r.desc:SetWordWrap(false)
    r.bar = W.Bar(r, 4); r.bar:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 1); r.bar:SetWidth(180)
    r.prog = W.Text(r, 9, "muted"); r.prog:SetPoint("LEFT", r.bar, "RIGHT", 8, 0)
    r.pts = W.Text(r, 16, "title"); r.pts:SetPoint("RIGHT", -12, 4); r.pts:SetJustifyH("RIGHT")
    r.when = W.Text(r, 9, "muted"); r.when:SetPoint("TOPRIGHT", r.pts, "BOTTOMRIGHT", 0, -2); r.when:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self) V.gsel = nil; V.Select(self.idx) end)
    return r
  end)

  -- guild achievements (0.9): gold cards above the own achievements
  p.gHead = W.Text(p.scroll.content, 12, "title"); p.gHead:SetJustifyH("LEFT")
  p.mHead = W.Text(p.scroll.content, 12, { 0.5, 0.7, 1 }); p.mHead:SetJustifyH("LEFT")
  p.cards = W.Pool(p.scroll.content, function(parent)
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetHeight(GROW_H - 6)
    W.Paint(c, { 0.16, 0.12, 0.07, 1 }, { 0.54, 0.43, 0.13, 1 })
    c.icon = ns.UITrophies.Icon(c, 40); c.icon:SetPoint("LEFT", 8, 0)
    c.name = W.Text(c, 12, "title"); c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, 2)
    c.desc = W.Text(c, 10, "muted"); c.desc:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3); c.desc:SetPoint("RIGHT", -110, 0); c.desc:SetWordWrap(false)
    c.bar = W.Bar(c, 4); c.bar:SetPoint("TOPLEFT", c.desc, "BOTTOMLEFT", 0, -6); c.bar:SetWidth(180)
    c.prog = W.Text(c, 9, "muted"); c.prog:SetPoint("LEFT", c.bar, "RIGHT", 8, 0); c.prog:SetPoint("RIGHT", -10, 0); c.prog:SetJustifyH("LEFT"); c.prog:SetWordWrap(false)
    c.pips = {}
    for i = 1, 4 do
      local pip = c:CreateTexture(nil, "ARTWORK")
      pip:SetSize(10, 10); pip:SetPoint("TOPRIGHT", -10 - (4 - i) * 14, -10)
      pip:SetTexture("Interface\\Buttons\\WHITE8X8")
      c.pips[i] = pip
    end
    c.tierName = W.Text(c, 9, "muted"); c.tierName:SetPoint("TOPRIGHT", -10, -24); c.tierName:SetJustifyH("RIGHT")
    c:SetScript("OnClick", function(self) V.gsel = self.id; V.sel = nil; UI.Refresh() end)
    c:SetScript("OnEnter", function(self) if self.x then ns.UITrophies.Tooltip(self, self.x, self.x.tier, self.x.season and ns.GuildAch.SeasonLabel(self.x.season) or nil) end end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
  end)

  -- editor (managers)
  local ed = W.Box(p, 280, 10, "panel2")
  ed:SetPoint("TOPRIGHT", 0, -26); ed:SetPoint("BOTTOMRIGHT", 0, 0)
  p.ed = ed
  ed.title = W.Text(ed, 12, "title"); ed.title:SetPoint("TOPLEFT", 10, -10); ed.title:SetPoint("RIGHT", -10, 0)
  ed.info = W.Text(ed, 10, "muted"); ed.info:SetPoint("TOPLEFT", 10, -32); ed.info:SetPoint("RIGHT", -10, 0)
  ed.info:SetSpacing(2)
  local y = -60
  local function field(key, w, numeric)
    local l = W.Text(ed, 10, "muted"); l:SetPoint("TOPLEFT", 10, y); l:SetText(L["AE_" .. key])
    local e = W.Edit(ed, w or 258, 22); e:SetPoint("TOPLEFT", 10, y - 14)
    if numeric then e:SetNumeric(true) end
    y = y - 44
    ed[key] = e
    ed["l" .. key] = l
    return e
  end
  field("NAME"); field("N", 90, true); field("PTS", 90, true)
  ed.lPTS:ClearAllPoints(); ed.lPTS:SetPoint("TOPLEFT", 130, y + 44)
  ed.PTS:ClearAllPoints(); ed.PTS:SetPoint("TOPLEFT", 130, y + 30)
  y = y + 44
  local l = W.Text(ed, 10, "muted"); l:SetPoint("TOPLEFT", 10, y); l:SetText(L.AE_SCOPE)
  ed.lSCOPE = l
  ed.scope = W.Dropdown(ed, 258, function() return { { "season", L.SCOPE_season }, { "forever", L.SCOPE_forever } } end,
    function() return ed.f and ed.f.scope end, function(v) ed.f.scope = v end)
  ed.scope:SetPoint("TOPLEFT", 10, y - 14)
  y = y - 44
  field("HONOR")
  local l2 = W.Text(ed, 10, "muted"); l2:SetPoint("TOPLEFT", 10, y); l2:SetText(L.AE_HONORSCOPE)
  ed.lHSCOPE = l2
  ed.hscope = W.Dropdown(ed, 258, function() return { { "season", L.SCOPE_season }, { "forever", L.SCOPE_forever } } end,
    function() return ed.f and (ed.f.honorScope or "season") end, function(v) ed.f.honorScope = v end)
  ed.hscope:SetPoint("TOPLEFT", 10, y - 14)
  y = y - 46
  ed.on = W.Check(ed, L.AE_ON)
  ed.on:SetPoint("TOPLEFT", 10, y)
  -- guild achievements: thresholds per tier and on / off
  ed.gl = W.Text(ed, 10, "muted"); ed.gl:SetPoint("TOPLEFT", 10, -64); ed.gl:SetText(L.GA_ED_TIERS)
  ed.gt = {}
  for i = 1, 4 do
    local e = W.Edit(ed, 58, 22); e:SetNumeric(true)
    e:SetPoint("TOPLEFT", 10 + (i - 1) * 64, -80)
    local c = ns.GuildAch.COLORS[i]
    e.lab = W.Text(ed, 9, { c[1], c[2], c[3] }); e.lab:SetPoint("TOPLEFT", e, "BOTTOMLEFT", 2, -2); e.lab:SetText(ns.GuildAch.TierName(i))
    ed.gt[i] = e
  end
  ed.gon = W.Check(ed, L.AE_ON); ed.gon:SetPoint("TOPLEFT", 10, -124)
  ed.ghint = W.Text(ed, 10, "muted"); ed.ghint:SetPoint("TOPLEFT", 10, -152); ed.ghint:SetPoint("RIGHT", -10, 0); ed.ghint:SetSpacing(2)
  ed.ghint:SetText(L.GA_ED_HINT)
  ed.gsave = W.Button(ed, L.SAVE, true, 22); ed.gsave:SetPoint("BOTTOMRIGHT", -10, 10)
  ed.gsave:SetScript("OnClick", function()
    local d = V.gsel and ns.GuildAch.Def(V.gsel)
    if not d then return end
    local tiers = {}
    for i = 1, #d.tiers do tiers[i] = tonumber(ed.gt[i]:GetText()) or d.tiers[i] end
    if ns.GuildAch.Edit(d.id, ed.gon:GetChecked() and true or false, tiers) then ns.GuildAch.Dirty(); U.Print(L.SAVED) end
    V.gloaded = nil
    UI.Refresh()
  end)
  ed.save = W.Button(ed, L.SAVE, true, 22)
  ed.save:SetPoint("BOTTOMRIGHT", -10, 10)
  ed.save:SetScript("OnClick", function() V.Save() end)
  ed.reset = W.Button(ed, L.RESET_ACHS, false, 22)
  ed.reset:SetPoint("BOTTOMLEFT", 10, 10)
  ed.reset:SetScript("OnClick", function()
    W.Dialog({ text = L.RESET_ACHS_CONFIRM, onAccept = function()
      ns.Profile.Update(function(pr) pr.achs = nil; pr.achOv = nil end)
      A.Dirty()
    end })
  end)
  ed.readonly = W.Text(ed, 10, "muted")
  ed.readonly:SetPoint("BOTTOMLEFT", 10, 10); ed.readonly:SetPoint("RIGHT", -10, 0)
  ed.readonly:SetText(L.AE_READONLY)
end

function V.Select(idx)
  V.sel = idx
  UI.Refresh()
end

function V.Save()
  local p = V.panel
  local ed = p.ed
  local idx = V.sel
  local cur = idx and A.List()[idx]
  if not cur then return end
  A.Edit(cur.id, function(a)
    local name = ed.NAME:GetText()
    a.name = (name ~= "" and name ~= A.Name(a)) and name or a.name
    a.n = math.max(1, tonumber(ed.N:GetText()) or a.n)
    a.pts = math.max(-1000, tonumber(ed.PTS:GetText()) or a.pts)
    a.scope = ed.f.scope
    local honor = ed.HONOR:GetText()
    if honor == "" then a.honor = nil; a.honorKey = nil
    elseif honor ~= A.Honor(a) then a.honor = honor end
    a.honorScope = ed.f.honorScope
    a.on = ed.on:GetChecked() and true or false
  end)
  A.Dirty()
  U.Print(L.SAVED)
end

local function refresh(p)
  V.panel = p
  local th = T.Current()
  local me = G.MyKey()
  local list = A.List()
  local mine = 0
  -- guild achievements: the list incl. switched off ones for managers
  local GA = ns.GuildAch
  local states = {}
  for _, x in ipairs(GA.All()) do states[x.def.id] = x end
  local gdefs = {}
  for _, d in ipairs(GA.List()) do
    if states[d.id] or G.IsManager() then gdefs[#gdefs + 1] = d end
  end
  -- earned first, then by progress
  table.sort(gdefs, function(a, b)
    local xa, xb = states[a.id], states[b.id]
    local ta, tb = xa and xa.tier or -1, xb and xb.tier or -1
    if ta ~= tb then return ta > tb end
    local pa = xa and xa.next and xa.have / xa.next or 0
    local pb = xb and xb.next and xb.have / xb.next or 0
    if pa ~= pb then return pa > pb end
    return GA.Name(a) < GA.Name(b)
  end)
  local y = 0
  p.gHead:ClearAllPoints(); p.gHead:SetPoint("TOPLEFT", 2, -y); p.gHead:SetText(L.GA_HEAD .. U.Color(T.Hex(th.muted), "  " .. L.GA_HEAD_SUB))
  y = y + 20
  for i, d in ipairs(gdefs) do
    local c = p.cards:Get(i)
    local x = states[d.id] or { def = d, have = 0, tier = 0, next = d.tiers[1], tierTs = {}, seasons = {}, top = {}, mine = 0 }
    c.id, c.x = d.id, x
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y); c:SetPoint("RIGHT", p.scroll.content, "RIGHT", -2, 0)
    local inSeason = d.scope == "season" and x.tier > 0 and x.season
    c.icon:Set(x, x.tier, inSeason and GA.SeasonLabel(x.season) or nil, inSeason and x.season or nil)
    c.name:SetText(GA.Name(d) .. (d.scope == "season" and U.Color(T.Hex(th.muted), "  · " .. L.GA_PER_SEASON) or "")
      .. ((d.on == false) and U.Color(U.WARN, "  " .. L.OFF) or ""))
    c.desc:SetText(GA.Desc(d))
    for k, pip in ipairs(c.pips) do
      local col = GA.COLORS[k]
      local has = d.tiers[k] ~= nil
      pip:SetShown(has)
      if k <= x.tier then pip:SetVertexColor(col[1], col[2], col[3], 1) else pip:SetVertexColor(col[1] * 0.3, col[2] * 0.3, col[3] * 0.3, 1) end
    end
    c.tierName:SetText(x.tier > 0 and GA.TierName(x.tier) or "—")
    if x.next then
      local from = x.tier > 0 and d.tiers[x.tier] or 0
      c.bar:SetValue(math.min(1, (x.have - from) / math.max(1, x.next - from)))
      local col = GA.COLORS[x.tier + 1] or GA.COLORS[3]
      c.bar:SetStatusBarColor(col[1], col[2], col[3])
      local tops = {}
      for _, tp in ipairs(x.top or {}) do if tp then tops[#tops + 1] = G.Display(tp.who) .. " " .. tp.n end end
      c.prog:SetText(L.GA_NEXT_SHORT:format(x.have, x.next, GA.TierName(x.tier + 1))
        .. (#tops > 0 and ("  ·  " .. table.concat(tops, ", ")) or "") .. U.Color("ff7fb2ff", "  " .. L.GA_YOU:format(x.mine or 0)))
      c.bar:Show()
    else
      c.bar:Hide()
      c.prog:SetText(L.GA_ALL_TIERS .. U.Color("ff7fb2ff", "  " .. L.GA_YOU:format(x.mine or 0)))
    end
    local sel = V.gsel == d.id
    c:SetBackdropBorderColor(unpack(sel and { 1, 0.85, 0.4, 1 } or { 0.54, 0.43, 0.13, 1 }))
    c:Show()
    y = y + GROW_H
  end
  p.cards:HideFrom(#gdefs + 1)
  y = y + 6
  p.mHead:ClearAllPoints(); p.mHead:SetPoint("TOPLEFT", 2, -y); p.mHead:SetText(L.ACH_MINE .. U.Color(T.Hex(th.muted), "  " .. L.ACH_MINE_HINT))
  y = y + 20
  local y0 = y
  for i, a in ipairs(list) do
    local r = p.rows:Get(i)
    r.idx = i
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(y0 + (i - 1) * ROW_H)); r:SetPoint("RIGHT", p.scroll.content, "RIGHT", -2, 0)
    local got = A.Has(me, a.id)
    local prog = A.Progress(me, a)
    r.icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.icon:SetDesaturated(not got)
    local secret = a.hidden and not got and not G.IsManager()
    r.name:SetText((secret and L.ACH_HIDDEN_NAME or A.Name(a)) .. ((a.on == false) and U.Color(U.WARN, "  " .. L.OFF) or "")
      .. ((a.hidden and not secret) and U.Color(T.Hex(th.muted), "  " .. L.ACH_HIDDEN_TAG) or ""))
    local honor = A.Honor(a)
    r.desc:SetText(secret and L.ACH_HIDDEN_DESC or (A.Desc(a) .. (honor and (" · " .. L.HONOR_PREFIX:format(honor)) or "")))
    if secret then r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
    r.bar:SetValue(math.min(1, prog / math.max(1, a.n)))
    r.bar:SetShown(not got and not secret); r.prog:SetShown(not got and not secret)
    r.prog:SetText(math.min(prog, a.n) .. " / " .. a.n)
    r.pts:SetText(a.pts or 0)
    local times = (got and a.repeatable) and A.Count(me, a.id) or 1
    r.when:SetText(got and (U.FormatTime(got.ts) .. (times > 1 and ("  ×" .. times) or "")) or L.POINTS)
    if got then mine = mine + (a.pts or 0) * times end
    local sel = V.sel == i
    r:SetBackdropBorderColor(unpack(sel and th.title or (got and th.title or th.line)))
    r:SetAlpha((got or sel) and 1 or 0.85)
  end
  p.rows:HideFrom(#list + 1)
  p.scroll:SetContentHeight(y0 + #list * ROW_H)
  p.total:SetText(L.ACH_POINTS_TOTAL:format(mine))

  local ed = p.ed
  local a = V.sel and list[V.sel]
  local manager = G.IsManager()
  local gd = V.gsel and GA.Def(V.gsel)
  local gman = manager or G.IsLead()
  for _, w in ipairs({ ed.gl, ed.gon, ed.gsave, ed.ghint }) do w:SetShown(gd ~= nil and gman) end
  for i, e in ipairs(ed.gt) do local on = gd ~= nil and gman and gd.tiers[i] ~= nil; e:SetShown(on); e.lab:SetShown(on) end
  for _, w in ipairs({ ed.NAME, ed.N, ed.PTS, ed.HONOR, ed.scope, ed.hscope, ed.on, ed.save, ed.reset,
    ed.lNAME, ed.lN, ed.lPTS, ed.lHONOR, ed.lSCOPE, ed.lHSCOPE }) do w:SetShown(manager and a ~= nil and not gd) end
  if gd then
    ed.reset:Hide()
    ed.readonly:SetShown(not gman)
    ed.title:SetText(GA.Name(gd))
    local x = states[gd.id]
    local parts = {}
    for i, n in ipairs(gd.tiers) do parts[#parts + 1] = GA.TierName(i) .. " " .. n end
    ed.info:SetText(GA.Desc(gd) .. "\n" .. table.concat(parts, " · ") .. (gd.scope == "season" and ("  (" .. L.GA_PER_SEASON .. ")") or ""))
    if gman and V.gloaded ~= gd.id then
      V.gloaded = gd.id
      for i, e in ipairs(ed.gt) do e:SetText(gd.tiers[i] and tostring(gd.tiers[i]) or "") end
      ed.gon:SetChecked(gd.on ~= false)
    end
    return
  end
  ed.reset:SetShown(manager)
  ed.readonly:SetShown(not manager)
  if not a then
    ed.title:SetText(L.AE_PICK)
    ed.info:SetText(manager and L.AE_PICK_HINT or L.AE_INFO_MEMBER)
    return
  end
  ed.title:SetText(A.Name(a))
  -- who has it already
  local holders = {}
  for key, earned in pairs(A.Earned()) do
    for _, e in ipairs(earned) do if e.id == a.id then holders[#holders + 1] = G.Display(key) end end
  end
  table.sort(holders)
  ed.info:SetText(L.AE_HOLDERS:format(#holders) .. (#holders > 0 and (": " .. table.concat(holders, ", ", 1, math.min(#holders, 6)) .. (#holders > 6 and " …" or "")) or ""))
  if V.loaded ~= V.sel or not ed.f then
    V.loaded = V.sel
    ed.f = { scope = a.scope or "season", honorScope = a.honorScope or "season" }
    ed.NAME:SetText(A.Name(a))
    ed.N:SetText(tostring(a.n))
    ed.PTS:SetText(tostring(a.pts or 0))
    ed.HONOR:SetText(A.Honor(a) or "")
    ed.on:SetChecked(a.on ~= false)
  end
  ed.scope:Refresh(); ed.hscope:Refresh()
end

UI.RegisterView("ach", {
  label = function() return L.GA_TAB end,
  build = build,
  refresh = refresh,
})
