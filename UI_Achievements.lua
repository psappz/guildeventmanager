local ADDON, ns = ...
-- Achievements tab: own progress, earned plaques, and (for managers) the
-- settings of every achievement: threshold, points, name, honor name, duration.
local U, G, T, W, UI, A = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI, ns.Achievements
local L = ns.L
local V = {}

local ROW_H = 58

local function build(p)
  local th = T.Current()
  local head = UI.Section(p, T.Word("ACHS"))
  head:SetPoint("TOPLEFT", 0, 0)
  p.total = W.Text(p, 11, "muted")
  p.preview = W.Button(p, L.SHOW_PLAQUE, false, 20)
  p.preview:SetPoint("TOPRIGHT", 0, 2)
  p.preview:SetScript("OnClick", function() ns.Plaque.Test() end)
  p.total:SetPoint("RIGHT", p.preview, "LEFT", -10, 0)
  head.line:SetPoint("RIGHT", p.total, "LEFT", -8, 0)

  p.scroll = W.Scroll(p)
  p.scroll:SetPoint("TOPLEFT", 0, -26); p.scroll:SetPoint("BOTTOMRIGHT", -290, 0)
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
    r:SetScript("OnClick", function(self) V.Select(self.idx) end)
    return r
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
  ed.save = W.Button(ed, L.SAVE, true, 22)
  ed.save:SetPoint("BOTTOMRIGHT", -10, 10)
  ed.save:SetScript("OnClick", function() V.Save() end)
  ed.reset = W.Button(ed, L.RESET_ACHS, false, 22)
  ed.reset:SetPoint("BOTTOMLEFT", 10, 10)
  ed.reset:SetScript("OnClick", function()
    W.Dialog({ text = L.RESET_ACHS_CONFIRM, onAccept = function()
      ns.Profile.Update(function(pr) pr.achs = U.Copy(A.AllDefaults()) end)
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
  if not idx then return end
  ns.Profile.Update(function(pr)
    local a = pr.achs[idx]
    if not a then return end
    local name = ed.NAME:GetText()
    a.name = (name ~= "" and name ~= A.Name(a)) and name or a.name
    a.n = math.max(1, tonumber(ed.N:GetText()) or a.n)
    a.pts = math.max(0, tonumber(ed.PTS:GetText()) or a.pts)
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
  for i, a in ipairs(list) do
    local r = p.rows:Get(i)
    r.idx = i
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); r:SetPoint("RIGHT", p.scroll.content, "RIGHT", -2, 0)
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
    r.when:SetText(got and U.FormatTime(got.ts) or L.POINTS)
    if got then mine = mine + (a.pts or 0) end
    local sel = V.sel == i
    r:SetBackdropBorderColor(unpack(sel and th.title or (got and th.title or th.line)))
    r:SetAlpha((got or sel) and 1 or 0.85)
  end
  p.rows:HideFrom(#list + 1)
  p.scroll:SetContentHeight(#list * ROW_H)
  p.total:SetText(L.ACH_POINTS_TOTAL:format(mine))

  local ed = p.ed
  local a = V.sel and list[V.sel]
  local manager = G.IsManager()
  for _, w in ipairs({ ed.NAME, ed.N, ed.PTS, ed.HONOR, ed.scope, ed.hscope, ed.on, ed.save, ed.reset,
    ed.lNAME, ed.lN, ed.lPTS, ed.lHONOR, ed.lSCOPE, ed.lHSCOPE }) do w:SetShown(manager and a ~= nil) end
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
  label = function() return T.Word("ACHS") end,
  build = build,
  refresh = refresh,
})
