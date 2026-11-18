local ADDON, R = ...
-- "Raids" in the side bar: overview with sign-ups and own spec, line-up with
-- drag & drop and buff overview, raid night, Raid-Helper import, settings.
local core = R.core
if not core then return end
local U, G, T, W, UI, E = core.U, core.Guild, core.Theme, core.W, core.UI, core.Events
local L = R.L
local API = GuildEventManagerAPI
local V = { sel = nil, hl = nil, pick = nil }
R.V = V

local KIND_ORDER = { "tank", "heal", "melee", "range", "unknown" }

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------
local function current()
  local e = V.sel and E.Get(V.sel)
  if e and R.IsRaid(e) then return e end
  e = R.NextRaid()
  if not e then
    local all = R.RaidEvents(false)
    e = all[1]
  end
  V.sel = e and e.id
  return e
end
R.Current = current

local function nameOf(x)
  local c = x.class and R.CLASS_COLOR[x.class] or "ffd0c8bc"
  return U.Color(c, G.Display(x.key))
end

local function raidChips(p)
  local row = UI.ChipRow(p, function()
    local o = {}
    for i, e in ipairs(R.RaidEvents(true)) do
      if i > 6 then break end
      o[#o + 1] = { e.id, e.name .. " · " .. date("%d.%m.", e.start) }
    end
    if #o == 0 then o[1] = { "none", L.RAID_NONE } end
    return o
  end, function() local e = current(); return e and e.id or "none" end, function(v)
    if v ~= "none" then V.sel = v; V.pick = nil; UI.Refresh() end
  end)
  row:SetPoint("TOPLEFT", 0, 0); row:SetPoint("RIGHT", p, "RIGHT", -230, 0)
  return row
end

local function bossOptions(e)
  local t = R.TemplateOf(e)
  local o = { { 0, L.RAID_SETUP_STD } }
  if t then for i, b in ipairs(t.bosses) do o[#o + 1] = { i, i .. ". " .. b } end end
  return o
end

local function roleIcon(parent)
  local tx = parent:CreateTexture(nil, "OVERLAY")
  tx:SetSize(15, 15)
  return tx
end

local function empty(p, text)
  p.none = p.none or W.Text(p, 12, "muted")
  p.none:SetPoint("TOPLEFT", 0, -40)
  p.none:SetText(text)
  return p.none
end

-- text window for the Discord export
local textWin
function R.ShowText(title, text)
  if not textWin then
    local th = T.Current()
    local w = CreateFrame("Frame", "GuildEventManagerRaidText", UIParent, "BackdropTemplate")
    w:SetSize(560, 380); w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    W.Paint(w, th.bg, th.border)
    w:EnableMouse(true); w:SetMovable(true); w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildEventManagerRaidText")
    w.title = W.Text(w, 14, "title"); w.title:SetPoint("TOPLEFT", 14, -12)
    w.hint = W.Text(w, 10, "muted"); w.hint:SetPoint("TOPLEFT", 14, -32); w.hint:SetText(L.RAID_EXPORT_HINT)
    local box = W.Box(w, 10, 10, "panel2")
    box:SetPoint("TOPLEFT", 12, -52); box:SetPoint("BOTTOMRIGHT", -12, 40)
    local sc = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 6, -6); sc:SetPoint("BOTTOMRIGHT", -26, 6)
    local eb = CreateFrame("EditBox", nil, sc)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetMaxLetters(0)
    eb:SetFont("Fonts\\ARIALN.TTF", 12, "")
    eb:SetWidth(500)
    eb:SetTextColor(th.text[1], th.text[2], th.text[3])
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); w:Hide() end)
    eb:SetScript("OnTextChanged", function(self, user) if user and w.text then self:SetText(w.text); self:HighlightText() end end)
    sc:SetScrollChild(eb)
    w.edit = eb
    w.close = W.Button(w, CLOSE or "Close", false, 22); w.close:SetPoint("BOTTOMRIGHT", -12, 10)
    w.close:SetScript("OnClick", function() w:Hide() end)
    textWin = w
  end
  textWin.title:SetText(title)
  textWin.text = text
  textWin.edit:SetText(text)
  textWin:Show()
  textWin.edit:SetFocus(); textWin.edit:HighlightText()
end

---------------------------------------------------------------------------
-- 1. Overview: sign-ups by role, own spec
---------------------------------------------------------------------------
local function specDropdowns(card, slot, y)
  local th = T.Current()
  local lab = W.Text(card, 10, "muted"); lab:SetPoint("TOPLEFT", 10, y)
  lab:SetText(slot == "m" and L.RAID_MAIN or L.RAID_OFF)
  local tree = W.Dropdown(card, slot == "m" and 160 or 140, function()
    local o = {}
    local class = card.rec and card.rec.class
    for i, sp in ipairs(class and R.SPECS[class] or {}) do o[#o + 1] = { i, R.SpecName(class, i) } end
    if slot == "o" then table.insert(o, 1, { 0, L.RAID_ROLE_none }) end
    -- main spec: "automatic" = the tree with the most talent points
    if slot == "m" then
      local got = R.ReadTalents()
      local det = got[1] and R.SpecName(class, got[1][1])
      table.insert(o, 1, { "auto", det and L.RAID_AUTO_SPEC:format(det) or L.RAID_AUTO_NONE })
    end
    return o
  end, function()
    if slot == "m" and card.rec and card.rec.auto then return "auto" end
    local x = card.rec and card.rec[slot]; return x and x[1] or 0
  end, function(v)
    if v == "auto" then
      card.rec.auto = true
      local got = R.ReadTalents()
      if got[1] then card.rec.m = { got[1][1], got[1][2] or R.DefaultRole(card.rec.class, got[1][1]) } end
      UI.Refresh(); return
    end
    if slot == "m" then card.rec.auto = false end
    if v == 0 then card.rec[slot] = nil; return end
    card.rec[slot] = card.rec[slot] or {}
    card.rec[slot][1] = v
    card.rec[slot][2] = R.DefaultRole(card.rec.class, v)
    UI.Refresh()
  end)
  tree:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", 0, -4)
  local role = W.Dropdown(card, slot == "m" and 120 or 130, function()
    local o = {}
    for _, r in ipairs(R.ROLES) do o[#o + 1] = { r, R.RoleName(r) } end
    return o
  end, function() local x = card.rec and card.rec[slot]; return x and x[2] end, function(v)
    if slot == "m" then card.rec.auto = false end
    card.rec[slot] = card.rec[slot] or { 1 }
    card.rec[slot][2] = v
  end)
  role:SetPoint("LEFT", tree, "RIGHT", 6, 0)
  return tree, role
end

local function buildOverview(p)
  p.chips = raidChips(p)
  p.new = W.Button(p, L.RAID_NEW, true, 22)
  p.new:SetPoint("TOPRIGHT", 0, 0)
  p.new:SetScript("OnClick", function()
    UI.Show("events")
    if core.UIEvents and core.UIEvents.OpenEditor then core.UIEvents.OpenEditor(nil, nil, { type = "raid_" .. (V.newTpl or "barrow") }) end
  end)
  p.tpl = W.Dropdown(p, 120, function()
    local o = {}
    for _, t in ipairs(R.TEMPLATES) do o[#o + 1] = { t.id, R.TplName(t) } end
    return o
  end, function() return V.newTpl or "barrow" end, function(v) V.newTpl = v end)
  p.tpl:SetPoint("RIGHT", p.new, "LEFT", -6, 0)

  p.head = W.Text(p, 14, "title"); p.head:SetPoint("TOPLEFT", 0, -34)
  p.info = W.Text(p, 10, "muted"); p.info:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -4)
  p.sign = W.Button(p, L.SIGN_ON, true, 22)
  p.sign:SetPoint("TOPRIGHT", p, "TOPRIGHT", -330, -34)
  p.sign:SetScript("OnClick", function()
    local e = current()
    if e then UI.Show("events"); core.UIEvents.OpenDetail(e) end
  end)

  p.box = W.Box(p, 10, 10, "panel2")
  p.box:SetPoint("TOPLEFT", 0, -76); p.box:SetPoint("BOTTOMRIGHT", -330, 0)
  p.scroll = W.Scroll(p.box)
  p.scroll:SetPoint("TOPLEFT", 8, -8); p.scroll:SetPoint("BOTTOMRIGHT", -8, 8)
  p.list = W.Text(p.scroll.content, 11, "text")
  p.list:SetPoint("TOPLEFT", 0, 0); p.list:SetPoint("RIGHT", 0, 0)
  p.list:SetSpacing(3)

  -- own spec
  local card = W.Box(p, 320, 250, "panel2")
  card:SetPoint("TOPRIGHT", 0, -34)
  p.card = card
  card.head = UI.Section(card, L.RAID_MYSPEC); card.head:SetPoint("TOPLEFT", 10, -10)
  card.head.line:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  card.class = W.Text(card, 11, "text"); card.class:SetPoint("TOPLEFT", 10, -34)
  card.mTree, card.mRole = specDropdowns(card, "m", -56)
  card.oTree, card.oRole = specDropdowns(card, "o", -106)
  card.src = W.Text(card, 10, "muted"); card.src:SetPoint("TOPLEFT", 10, -158); card.src:SetPoint("RIGHT", -10, 0)
  card.src:SetSpacing(2)
  card.read = W.Button(card, L.RAID_READ_TALENTS, false, 22)
  card.read:Hide()
  card.read:SetPoint("BOTTOMLEFT", 10, 10)
  card.read:SetScript("OnClick", function()
    local got = R.ReadTalents()
    if not got[1] and not got[2] then U.Print(L.RAID_TALENTS_NONE) end
    R.UpdateOwnSpec(true); card.rec = nil; UI.Refresh()
  end)
  card.save = W.Button(card, core.L.SAVE, true, 22)
  card.save:SetPoint("BOTTOMRIGHT", -10, 10)
  card.save:SetScript("OnClick", function()
    if not card.rec then return end
    local rec = card.rec
    rec.src = rec.auto and "auto" or "self"
    rec.auto = nil
    R.SaveSpec(nil, rec); card.rec = nil; UI.Refresh()
  end)
  p.hint = W.Text(p, 10, "muted"); p.hint:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -10); p.hint:SetPoint("RIGHT", 0, 0)
  p.hint:SetSpacing(2)
  p.hint:SetText(L.RAID_OVERVIEW_HINT)
end

local function refreshOverview(p)
  local th = T.Current()
  p.chips:Refresh()
  p.new:SetShown(R.CanCreate()); p.tpl:SetShown(R.CanCreate()); p.tpl:Refresh()
  -- own spec card
  local card = p.card
  if not card.rec then
    local cur = R.Spec() or {}
    card.rec = { class = cur.class or R.MyClass(), m = cur.m and U.Copy(cur.m), o = cur.o and U.Copy(cur.o), src = cur.src,
      auto = cur.src ~= "self" and cur.src ~= "lead" }
  end
  local cname = card.rec.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[card.rec.class]) or card.rec.class or "?"
  card.class:SetText(U.Color(R.CLASS_COLOR[card.rec.class or ""] or "ffffffff", cname))
  for _, d in ipairs({ card.mTree, card.mRole, card.oTree, card.oRole }) do d:Refresh() end
  local src = (R.Spec() or {}).src
  local pts = R.TalentPoints()
  card.src:SetText((L["RAID_SRC_" .. (src or "none")] or "") .. (pts and ("\n" .. U.Color("ffe3b45b", L.RAID_SPEC_POINTS:format(pts))) or ""))

  local e = current()
  p.sign:SetShown(e ~= nil and E.IsOpen(e))
  if not e then
    p.head:SetText(L.RAID_NONE); p.info:SetText(L.RAID_NONE_HINT)
    p.list:SetText(""); return
  end
  local t = R.TemplateOf(e)
  p.head:SetText(e.name)
  local st = E.Status(e)
  p.info:SetText(R.TplName(t) .. " · " .. U.FormatTime(e.start) .. " · " .. (e.leader and G.Display(e.leader) or "") .. " · " .. (st and L.YOU_ST:format(L["ST_" .. st]) or L.HOME_NOT_SIGNED))
  W.SetLabel(p.sign, st and L.SIGN_CHANGE or L.SIGN_ON)

  local need = R.Need(t)
  local by = { tank = {}, heal = {}, melee = {}, range = {}, unknown = {} }
  local other = { tent = {}, late = {}, bench = {}, out = {} }
  local yes = 0
  for _, s in ipairs(E.SignupList(e)) do
    local x = R.Player(e, s.key, 0)
    local line = nameOf(x) .. U.Color(T.Hex(th.muted), "  " .. (x.class and x.tree and R.SpecName(x.class, x.tree) or "") ..
      (x.off and (" · " .. L.RAID_CAN:format(R.RoleName(x.off))) or "") .. (x.c and ("  »" .. x.c .. "«") or "") .. (x.src == "rh" and "  [RH]" or ""))
    if s.st == "in" or s.st == "late" then
      yes = yes + 1
      local k = x.kind or "unknown"
      by[k][#by[k] + 1] = (s.st == "late" and (U.Color("ffe3b45b", L.ST_late .. ": ")) or "") .. line
    else
      other[s.st][#other[s.st] + 1] = line
    end
  end
  local lines = {}
  lines[#lines + 1] = U.Color(T.Hex(th.title), L.RAID_SIGNED_N:format(yes, t.size))
  for _, k in ipairs(KIND_ORDER) do
    local n = #by[k]
    local want = need[k]
    if k ~= "unknown" or n > 0 then
    local head = L["RAID_KIND_" .. k] .. " " .. n .. (want and ("/" .. want) or "") .. (k == "unknown" and ("  " .. U.Color(T.Hex(th.muted), L.RAID_UNKNOWN_HINT)) or "")
    local col = ((want and n < want) or k == "unknown") and "fff0a08f" or T.Hex(th.title)
    lines[#lines + 1] = " "
    lines[#lines + 1] = U.Color(col, head)
    for _, l in ipairs(by[k]) do lines[#lines + 1] = "   " .. l end
    end
  end
  for _, s in ipairs({ "tent", "bench", "out" }) do
    if #other[s] > 0 then
      lines[#lines + 1] = " "
      lines[#lines + 1] = U.Color(T.Hex(th.muted), L["ST_" .. s] .. " (" .. #other[s] .. ")")
      for _, l in ipairs(other[s]) do lines[#lines + 1] = "   " .. l end
    end
  end
  p.list:SetText(table.concat(lines, "\n"))
  p.scroll:SetContentHeight(p.list:GetStringHeight() + 6)
end

---------------------------------------------------------------------------
-- 2. Line-up: groups with drag & drop, side lists, buffs
---------------------------------------------------------------------------
local ghost
local function dragGhost()
  if ghost then return ghost end
  local th = T.Current()
  ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  ghost:SetSize(130, 22)
  ghost:SetFrameStrata("TOOLTIP")
  W.Paint(ghost, th.panel2, th.title)
  ghost.text = W.Text(ghost, 11, "text"); ghost.text:SetPoint("LEFT", 8, 0)
  ghost:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    self:ClearAllPoints(); self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + 8, y / s - 8)
  end)
  ghost:Hide()
  return ghost
end

local function targetUnderMouse()
  local f = (GetMouseFoci and GetMouseFoci()[1]) or (GetMouseFocus and GetMouseFocus())
  while f do
    if f.drop then return f.drop end
    f = f.GetParent and f:GetParent()
  end
end

local function endDrag()
  local key = V.drag
  V.drag = nil
  if ghost then ghost:Hide() end
  local e = current()
  local target = targetUnderMouse()
  if e and key and target then R.Drop(e, key, target) end
  UI.Refresh()
end

local function slotButton(parent)
  local th = T.Current()
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetHeight(22)
  W.Paint(b, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b.text = W.Text(b, 11, "text"); b.text:SetPoint("LEFT", 6, 0); b.text:SetPoint("RIGHT", -22, 0); b.text:SetWordWrap(false)
  b.sub = W.Text(b, 9, "muted"); b.sub:SetPoint("BOTTOMLEFT", 6, 3); b.sub:SetPoint("RIGHT", -22, 0); b.sub:SetWordWrap(false)
  b.sub:Hide()
  b.icon = roleIcon(b); b.icon:SetPoint("RIGHT", -4, 0)
  b:SetScript("OnDragStart", function(self)
    local e = current()
    if not self.key or not e or not R.CanEdit(e) then return end
    V.drag = self.key
    local g = dragGhost(); g.text:SetText(self.text:GetText()); g:Show()
  end)
  b:SetScript("OnDragStop", function() if V.drag then endDrag() end end)
  b:SetScript("OnReceiveDrag", function() if V.drag then endDrag() end end)
  b:SetScript("OnClick", function(self, button)
    local e = current()
    if not e then return end
    if button == "RightButton" then
      if not self.key or not R.CanEdit(e) then return end
      local key, plan = self.key, R.Plan(e)
      W.OpenMenu(self, function(_, root)
        root:CreateTitle(G.Display(key))
        local x = self.x
        root:CreateTitle(L.RAID_MENU_ROLE)
        for _, role in ipairs(R.RolesOf(x and x.class)) do
          local label = R.RoleName(role) .. ((x and x.role == role) and "  " .. W.InlineIcon("check", 11) or "")
          root:CreateButton(label, function() R.SetRole(e, key, role) end)
        end
        if x and x.byLead then root:CreateButton(L.RAID_MENU_ROLE_RESET, function() R.SetRole(e, key, nil) end) end
        if plan.b > 0 and self.x and self.x.off then
          root:CreateButton(self.x.swapped and L.RAID_MENU_MAIN or L.RAID_MENU_OFF:format(R.RoleName(self.x.off)), function() R.ToggleSwap(e, plan.b, key) end)
        end
        if plan.g[key] then root:CreateButton(L.RAID_MENU_OUT, function() R.Move(e, key, nil) end) end
      end)
      return
    end
    if not R.CanEdit(e) then return end
    if V.pick and V.pick ~= self.key then
      R.Drop(e, V.pick, self.drop); V.pick = nil
    elseif self.key then
      V.pick = (V.pick ~= self.key) and self.key or nil
    end
    UI.Refresh()
  end)
  b:SetScript("OnEnter", function(self)
    if not self.x then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(G.Display(self.x.key))
    GameTooltip:AddLine((self.x.role and R.RoleName(self.x.role) or L.RAID_KIND_unknown) .. (self.x.class and self.x.tree and (" · " .. R.SpecName(self.x.class, self.x.tree)) or ""), 1, 1, 1)
    if self.x.byLead then GameTooltip:AddLine(L.RAID_ROLE_BY_LEAD, 0.9, 0.7, 0.3) end
    if self.x.off then GameTooltip:AddLine(L.RAID_CAN:format(R.RoleName(self.x.off)), 0.8, 0.8, 0.8) end
    if self.x.c then GameTooltip:AddLine("»" .. self.x.c .. "«", 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function paintSlot(b, x, th, e)
  local hl = V.hl and x and R.Provides(V.hl, x)
  if x and V.pick == x.key then
    b:SetBackdropColor(0.23, 0.16, 0.12, 1); b:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1)
  elseif hl then
    b:SetBackdropColor(0.24, 0.19, 0.09, 1); b:SetBackdropBorderColor(0.89, 0.71, 0.36, 1)
  else
    b:SetBackdropColor(0, 0, 0, 0); b:SetBackdropBorderColor(0, 0, 0, 0)
  end
  b:SetAlpha((V.hl and x and not hl) and 0.4 or 1)
end

local function fillSlot(b, x, th, e, drop)
  b.x, b.key, b.drop = x, x and x.key, drop
  b.text:ClearAllPoints(); b.text:SetPoint("RIGHT", -22, 0)
  if b.two and x then b.text:SetPoint("TOPLEFT", 6, -3) else b.text:SetPoint("LEFT", 6, 0) end
  b.sub:SetShown(b.two and x ~= nil)
  if x then
    b.text:SetText(nameOf(x) .. (x.swapped and U.Color("ffe3b45b", " *") or "") .. (x.st == "late" and U.Color(T.Hex(th.muted), " (" .. L.ST_late .. ")") or ""))
    b.icon:SetTexture(x.kind and R.ROLE_ICON[x.kind] or W.Icon("unknown")); b.icon:Show()
    if b.two then
      local bits = { x.role and (R.RoleName(x.role) .. (x.byLead and "*" or "")) or U.Color("fff0a08f", L.RAID_KIND_unknown) }
      if x.class and x.tree then bits[#bits + 1] = R.SpecName(x.class, x.tree) end
      if x.off and x.off ~= x.role then bits[#bits + 1] = L.RAID_CAN:format(R.RoleName(x.swapped and x.main or x.off)) end
      b.sub:SetText(table.concat(bits, " · "))
    end
  else
    b.text:SetText(U.Color(T.Hex(th.muted), (V.pick or V.drag) and L.RAID_HERE or L.RAID_FREE))
    b.icon:Hide()
  end
  paintSlot(b, x, th, e)
end

local function buildPlan(p)
  p.chips = raidChips(p)
  p.boss = W.Dropdown(p, 220, function() local e = current(); return e and bossOptions(e) or { { 0, L.RAID_SETUP_STD } } end,
    function() local e = current(); return e and R.Plan(e).b or 0 end,
    function(v) local e = current(); if e then if R.CanEdit(e) then R.SetBoss(e, v) else R.Plan(e).b = v end; UI.Refresh() end end)
  p.boss:SetPoint("TOPRIGHT", 0, 0)
  p.counts = W.Text(p, 11, "text"); p.counts:SetPoint("TOPLEFT", 0, -32); p.counts:Hide()
  p.cpills = {}
  for i = 1, 6 do
    local pl = UI.Pill(p)
    if i == 1 then pl:SetPoint("TOPLEFT", 0, -30) else pl:SetPoint("LEFT", p.cpills[i - 1], "RIGHT", 5, 0) end
    p.cpills[i] = pl
  end
  p.auto = W.Button(p, L.RAID_AUTOFILL, false, 20)
  p.auto:SetPoint("TOPRIGHT", p, "TOPRIGHT", -310, -30)
  p.auto:SetScript("OnClick", function() local e = current(); if e then R.AutoFill(e) end end)
  p.clear = W.Button(p, L.RAID_CLEAR, false, 20)
  p.clear:SetPoint("RIGHT", p.auto, "LEFT", -6, 0)
  p.clear:SetScript("OnClick", function()
    local e = current()
    if e then W.Dialog({ text = L.RAID_CLEAR_Q, accept = L.RAID_CLEAR, onAccept = function() R.ClearPlan(e) end }) end
  end)

  p.grid = CreateFrame("Frame", nil, p)
  p.grid:SetPoint("TOPLEFT", 0, -56); p.grid:SetPoint("BOTTOMRIGHT", -310, 30)
  p.groups = {}
  for g = 1, 8 do
    local box = W.Box(p.grid, 10, 10, "panel2")
    box.drop = { group = g }
    box.head = W.Text(box, 10, "title"); box.head:SetPoint("TOPLEFT", 6, -4)
    box.fill = W.Text(box, 10, "muted"); box.fill:SetPoint("TOPRIGHT", -6, -4)
    box.slots = {}
    for i = 1, 5 do
      local s = slotButton(box)
      s.two = true; s:SetHeight(28)
      s:SetPoint("TOPLEFT", 2, -18 - (i - 1) * 28); s:SetPoint("RIGHT", box, "RIGHT", -2, 0)
      box.slots[i] = s
    end
    box.tags = {}
    box.buffs = W.Text(box, 9, "muted"); box.buffs:SetPoint("BOTTOMLEFT", 6, 4); box.buffs:SetPoint("RIGHT", -6, 0)
    box.buffs:SetWordWrap(false)
    p.groups[g] = box
  end
  p.hint = W.Text(p, 9, "muted"); p.hint:SetPoint("BOTTOMLEFT", 0, 0); p.hint:SetPoint("RIGHT", p, "RIGHT", -310, 0)
  p.hint:SetJustifyH("LEFT"); p.hint:SetWordWrap(true)

  -- right column: waiting lists, then buffs / debuffs / utility
  p.side = W.Box(p, 300, 10, "panel2")
  p.side:SetPoint("TOPRIGHT", 0, -30); p.side:SetPoint("BOTTOM", 0, 0)
  p.sideScroll = W.Scroll(p.side)
  p.sideScroll:SetPoint("TOPLEFT", 6, -6); p.sideScroll:SetPoint("BOTTOMRIGHT", -6, 6)
  local c = p.sideScroll.content
  p.sideHeads = W.Pool(c, function(parent) local fs = W.Text(parent, 11, "title"); return fs end)
  p.sideSlots = W.Pool(c, function(parent) return slotButton(parent) end)
  p.buffRows = W.Pool(c, function(parent)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetHeight(18)
    W.Paint(r, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    r.mark = W.Text(r, 11, "title"); r.mark:SetPoint("LEFT", 4, 0); r.mark:SetWidth(14)
    r.label = W.Text(r, 10, "text"); r.label:SetPoint("LEFT", 22, 0); r.label:SetPoint("RIGHT", -70, 0); r.label:SetWordWrap(false)
    r.who = W.Text(r, 10, "muted"); r.who:SetPoint("RIGHT", -4, 0); r.who:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self) if self.id then V.hl = (V.hl ~= self.id) and self.id or nil; UI.Refresh() end end)
    return r
  end)
end

local function refreshPlan(p)
  local th = T.Current()
  p.chips:Refresh(); p.boss:Refresh()
  local e = current()
  p.grid:SetShown(e ~= nil); p.side:SetShown(e ~= nil)
  if not e then
    for _, pl in ipairs(p.cpills) do pl:Hide() end
    p.counts:SetText(L.RAID_NONE); p.counts:Show(); p.auto:Hide(); p.clear:Hide(); p.hint:SetText("")
    return
  end
  local t = R.TemplateOf(e)
  p.counts:Hide()
  local plan = R.Plan(e)
  local boss = plan.b
  local edit = R.CanEdit(e)
  p.auto:SetShown(edit); p.clear:SetShown(edit)
  local list = R.Lineup(e, boss)
  local n = R.RoleCounts(list)
  local need = R.Need(t)
  local function pill(i, txt, short)
    p.cpills[i]:Set(txt, false, short and UI.COLORS.out or nil)
  end
  pill(1, L.RAID_IN_GROUPS:format(n.total, t.size), n.total < t.size)
  pill(2, L.RAID_KIND_tank .. " " .. n.tank .. "/" .. need.tank, n.tank < need.tank)
  pill(3, L.RAID_KIND_heal .. " " .. n.heal .. "/" .. need.heal, n.heal < need.heal)
  pill(4, L.RAID_KIND_melee .. " " .. n.melee)
  pill(5, L.RAID_KIND_range .. " " .. n.range)
  if n.unknown > 0 then pill(6, L.RAID_KIND_unknown .. " " .. n.unknown, true) else p.cpills[6]:Hide() end
  p.hint:SetText(edit and L.RAID_PLAN_HINT or L.RAID_PLAN_READONLY)

  -- grid
  local cols = t.groups == 8 and 4 or 2
  local rows = math.ceil(t.groups / cols)
  local gw = (p.grid:GetWidth() > 0 and p.grid:GetWidth() or 540)
  local w = (gw - (cols - 1) * 8) / cols
  local h = 18 + 5 * 28 + 24
  for g = 1, 8 do
    local box = p.groups[g]
    if g <= t.groups then
      local col, row = (g - 1) % cols, math.floor((g - 1) / cols)
      box:ClearAllPoints(); box:SetPoint("TOPLEFT", col * (w + 8), -row * (h + 8)); box:SetSize(w, h)
      local m = R.Group(e, g, boss)
      box.head:SetText(L.RAID_GROUP_N:format(g)); box.fill:SetText(#m .. "/5")
      for i = 1, 5 do fillSlot(box.slots[i], m[i], th, e, m[i] and { key = m[i].key } or { group = g }) end
      local have, miss = R.GroupBuffs(e, g, boss)
      local tags = {}
      for _, k in ipairs(miss) do tags[#tags + 1] = { L[k], UI.COLORS.out } end
      for _, id in ipairs(have) do tags[#tags + 1] = { L["RAID_B_" .. id], UI.COLORS["in"] } end
      box.buffs:SetText("")
      local xoff, used = 4, 0
      for i, tg in ipairs(tags) do
        local pl = box.tags[i]
        if not pl then pl = UI.Pill(box); box.tags[i] = pl end
        pl:Set(tg[1], false, tg[2])
        pl:ClearAllPoints()
        if xoff + pl:GetWidth() > w - 4 then pl:Hide() else
          pl:SetPoint("BOTTOMLEFT", xoff, 3); xoff = xoff + pl:GetWidth() + 4; used = i
        end
      end
      for i = #tags + 1, #box.tags do box.tags[i]:Hide() end
      box:Show()
    else
      box:Hide()
    end
  end

  -- side column
  local y, nh, ns, nb = 0, 0, 0, 0
  local c = p.sideScroll.content
  local function head(text)
    nh = nh + 1
    local fs = p.sideHeads:Get(nh)
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 2, -y); fs:SetText(text); fs:Show()
    y = y + 18
  end
  local function slot(x, drop)
    ns = ns + 1
    local s = p.sideSlots:Get(ns)
    s:ClearAllPoints(); s:SetPoint("TOPLEFT", 0, -y); s:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    fillSlot(s, x, th, e, drop)
    y = y + 22
  end
  local function buffRow(id, label, ok, who)
    nb = nb + 1
    local r = p.buffRows:Get(nb)
    r.id = id
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    r.mark:SetText(ok == nil and W.InlineIcon("unknown", 13) or W.Mark(ok, 13))
    r.label:SetText(label); r.who:SetText(who or "")
    if V.hl == id then r:SetBackdropColor(0.24, 0.19, 0.09, 1); r:SetBackdropBorderColor(0.89, 0.71, 0.36, 1)
    else r:SetBackdropColor(0, 0, 0, 0); r:SetBackdropBorderColor(0, 0, 0, 0) end
    y = y + 19
  end
  if V.hl then
    local cov = R.Coverage(e, boss)
    head(L.RAID_HL:format(L["RAID_B_" .. V.hl] or V.hl, cov[V.hl] and cov[V.hl].n or 0))
    y = y + 4
  end
  local pool = R.Pool(e, boss)
  head(L.RAID_POOL .. " (" .. #pool .. ")")
  for _, x in ipairs(pool) do slot(x, { key = x.key }) end
  if #pool == 0 then slot(nil, { group = false }) end
  local s = R.Store()
  for _, st in ipairs({ "tent", "bench" }) do
    local l = R.ByState(e, st, boss)
    if #l > 0 then
      y = y + 6
      head(L["ST_" .. st] .. " (" .. #l .. ")")
      for _, x in ipairs(l) do slot(x, { key = x.key }) end
    end
  end
  -- boss needs
  local needs = boss > 0 and R.BossNeeds(e, boss) or {}
  if #needs > 0 then
    y = y + 8
    head(L.RAID_BOSSNEED:format(t.bosses[boss]))
    for _, x in ipairs(needs) do buffRow(x.id == "tremor_all" and "tremor" or x.id, L["RAID_B_" .. x.id], (not x.unknown) and x.ok or nil, x.unknown and L.RAID_LATER or x.info) end
  end
  local cov = R.Coverage(e, boss)
  local function panel(title, defs, filter)
    y = y + 8
    head(title)
    for _, b in ipairs(defs) do
      if not filter or filter(b) then
        local n = cov[b.id] and cov[b.id].n or 0
        buffRow(b.id, L["RAID_B_" .. b.id], n > 0, n > 0 and (n .. "×") or L.RAID_MISSING)
      end
    end
  end
  panel(L.RAID_BUFFS_RAID, R.BUFFS, function(b) return b.scope == "raid" end)
  panel(L.RAID_BUFFS_GROUP, R.BUFFS, function(b) return b.scope == "group" end)
  panel(L.RAID_DEBUFFS, R.DEBUFFS)
  panel(L.RAID_UTILITY, R.UTILITY)
  p.sideHeads:HideFrom(nh + 1); p.sideSlots:HideFrom(ns + 1); p.buffRows:HideFrom(nb + 1)
  p.sideScroll:SetContentHeight(y + 6)
end

---------------------------------------------------------------------------
-- 3. Raid night: readiness, invite, sort, export
---------------------------------------------------------------------------
local COLS = { { "name", 150 }, { "grp", 50 }, { "role", 110 }, { "on", 60 }, { "addon", 60 }, { "lock", 150 }, { "amu", 70 }, { "bench", 60 } }

local function buildNight(p)
  p.chips = raidChips(p)
  p.boss = W.Dropdown(p, 220, function() local e = current(); return e and bossOptions(e) or { { 0, L.RAID_SETUP_STD } } end,
    function() local e = current(); return e and R.Plan(e).b or 0 end,
    function(v) local e = current(); if e then if R.CanEdit(e) then R.SetBoss(e, v) else R.Plan(e).b = v end; UI.Refresh() end end)
  p.boss:SetPoint("TOPRIGHT", 0, 0)
  local prev
  p.btns = {}
  local function btn(key, fn, primary)
    local b = W.Button(p, L[key], primary, 22)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 0, -32) end
    b:SetScript("OnClick", function() local e = current(); if e then fn(e) end end)
    prev = b
    p.btns[#p.btns + 1] = b
    return b
  end
  p.bInvite = btn("ACT_INVITE", function(e) E.InviteAll(e) end, true)
  p.bSort = btn("RAID_SORT", function(e) R.SortRaid(e) end)
  p.bAsk = btn("RAID_ASK", function() R.AskState(); U.Print(L.RAID_ASKED) end)
  p.bExport = btn("RAID_EXPORT", function(e) R.ShowText(L.RAID_EXPORT_TITLE, R.ExportText(e)) end)
  p.summary = W.Text(p, 11, "text"); p.summary:SetPoint("TOPLEFT", 0, -62); p.summary:SetPoint("RIGHT", 0, 0)
  p.box = W.Box(p, 10, 10, "panel2")
  p.box:SetPoint("TOPLEFT", 0, -84); p.box:SetPoint("BOTTOMRIGHT", 0, 18)
  local x = 8
  p.heads = {}
  for _, col in ipairs(COLS) do
    local fs = W.Text(p.box, 10, "muted"); fs:SetPoint("TOPLEFT", x, -8); fs:SetText(L["RAID_COL_" .. col[1]])
    p.heads[col[1]] = fs
    x = x + col[2]
  end
  p.scroll = W.Scroll(p.box)
  p.scroll:SetPoint("TOPLEFT", 6, -24); p.scroll:SetPoint("BOTTOMRIGHT", -6, 6)
  p.rows = W.Pool(p.scroll.content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(20)
    r.cells = {}
    local cx = 2
    for _, col in ipairs(COLS) do
      local fs = W.Text(r, 11, "text"); fs:SetPoint("LEFT", cx, 0); fs:SetWidth(col[2] - 6); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
      r.cells[col[1]] = fs
      cx = cx + col[2]
    end
    return r
  end)
  p.hint = W.Text(p, 9, "muted"); p.hint:SetPoint("BOTTOMLEFT", 0, 0); p.hint:SetText(L.RAID_NIGHT_HINT)
end

local function yes(v) return W.Mark(v, 13) end

local function refreshNight(p)
  p.chips:Refresh(); p.boss:Refresh()
  local e = current()
  for _, b in ipairs(p.btns) do b:SetShown(e ~= nil) end
  p.box:SetShown(e ~= nil)
  if not e then p.summary:SetText(L.RAID_NONE); return end
  local t = R.TemplateOf(e)
  local edit = R.CanEdit(e)
  p.bSort:SetEnabled(edit); p.bInvite:SetEnabled(edit)
  p.heads.amu:SetShown(t.amulet ~= nil)
  local plan = R.Plan(e)
  local s = R.Store()
  local rows, on, ready, locked = 0, 0, 0, 0
  local list = {}
  for _, su in ipairs(E.SignupList(e)) do
    if su.st ~= "out" then list[#list + 1] = su end
  end
  table.sort(list, function(a, b)
    local ga, gb = plan.g[a.key] or 99, plan.g[b.key] or 99
    if ga ~= gb then return ga < gb end
    return a.key < b.key
  end)
  for _, su in ipairs(list) do
    rows = rows + 1
    local x = R.Player(e, su.key, plan.b)
    local rd = R.Ready(e, su.key)
    local r = p.rows:Get(rows)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(rows - 1) * 21); r:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
    local c = r.cells
    c.name:SetText(nameOf(x) .. ((su.st ~= "in") and U.Color("ff8a8078", " · " .. L["ST_" .. su.st]) or ""))
    c.grp:SetText(plan.g[su.key] and tostring(plan.g[su.key]) or "–")
    c.role:SetText((x.role and R.RoleName(x.role) or U.Color("fff0a08f", L.RAID_KIND_unknown)) .. ((x.swapped or x.byLead) and " *" or ""))
    c.on:SetText(yes(rd.online)); c.addon:SetText(yes(rd.addon))
    c.lock:SetText(rd.locked and U.Color("fff0a08f", L.RAID_LOCKED:format(rd.locked.p or "")) or (rd.addon and U.Color("ff9fe0d4", L.RAID_FREE_LOCK) or U.Color("ff8a8078", "?")))
    c.amu:SetText(t.amulet and yes(rd.amulet) or ""); c.amu:SetShown(t.amulet ~= nil)
    c.bench:SetText((s.bench[su.key] or 0) > 0 and (s.bench[su.key] .. "×") or "")
    if rd.online then on = on + 1 end
    if rd.locked then locked = locked + 1 end
    if rd.online and not rd.locked and (not t.amulet or rd.amulet) then ready = ready + 1 end
  end
  p.rows:HideFrom(rows + 1)
  p.scroll:SetContentHeight(rows * 21)
  p.summary:SetText(L.RAID_NIGHT_SUM:format(rows, on, ready, locked))
end

---------------------------------------------------------------------------
-- 4. Raid-Helper import
---------------------------------------------------------------------------
local function buildImport(p)
  p.chips = raidChips(p)
  p.help = W.Text(p, 10, "muted"); p.help:SetPoint("TOPLEFT", 0, -30); p.help:SetPoint("RIGHT", 0, 0)
  p.help:SetSpacing(2); p.help:SetText(L.RAID_IMP_HELP)
  p.box = W.Box(p, 10, 10, "panel2")
  p.box:SetPoint("TOPLEFT", 0, -70); p.box:SetPoint("BOTTOMLEFT", 0, 34); p.box:SetWidth(330)
  local sc = CreateFrame("ScrollFrame", nil, p.box, "UIPanelScrollFrameTemplate")
  sc:SetPoint("TOPLEFT", 6, -6); sc:SetPoint("BOTTOMRIGHT", -26, 6)
  local eb = CreateFrame("EditBox", nil, sc)
  eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetMaxLetters(0)
  eb:SetFont("Fonts\\ARIALN.TTF", 10, "")
  eb:SetWidth(290)
  local th = T.Current()
  eb:SetTextColor(th.text[1], th.text[2], th.text[3])
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sc:SetScrollChild(eb)
  p.edit = eb
  p.read = W.Button(p, L.RAID_IMP_READ, true, 22)
  p.read:SetPoint("BOTTOMLEFT", 0, 4)
  p.read:SetScript("OnClick", function()
    local imp, err = R.ReadRaidHelper(p.edit:GetText())
    if not imp then V.imp = nil; p.status:SetText(U.Color("fff0a08f", L.RAID_IMP_ERR:format(err or "?"))); UI.Refresh(); return end
    V.imp = imp
    V.map = {}
    for _, x in ipairs(imp.list) do V.map[x.id] = R.GuessMember(x) or false end
    p.edit:ClearFocus()
    UI.Refresh()
  end)
  p.clearBtn = W.Button(p, L.RAID_IMP_CLEAR, false, 22)
  p.clearBtn:SetPoint("LEFT", p.read, "RIGHT", 6, 0)
  p.clearBtn:SetScript("OnClick", function() p.edit:SetText(""); V.imp = nil; UI.Refresh() end)
  p.status = W.Text(p, 10, "muted"); p.status:SetPoint("TOPLEFT", p.box, "TOPRIGHT", 12, 0); p.status:SetPoint("RIGHT", 0, 0)
  p.list = W.Box(p, 10, 10, "panel2")
  p.list:SetPoint("TOPLEFT", p.box, "TOPRIGHT", 12, -20); p.list:SetPoint("BOTTOMRIGHT", 0, 34)
  p.scroll = W.Scroll(p.list)
  p.scroll:SetPoint("TOPLEFT", 6, -6); p.scroll:SetPoint("BOTTOMRIGHT", -6, 6)
  p.rows = W.Pool(p.scroll.content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(24)
    r.name = W.Text(r, 11, "text"); r.name:SetPoint("LEFT", 2, 0); r.name:SetWidth(150); r.name:SetWordWrap(false); r.name:SetJustifyH("LEFT")
    r.spec = W.Text(r, 10, "muted"); r.spec:SetPoint("LEFT", 156, 0); r.spec:SetWidth(150); r.spec:SetWordWrap(false); r.spec:SetJustifyH("LEFT")
    r.dd = W.Dropdown(r, 160, function()
      local o = { { false, L.RAID_IMP_SKIP } }
      local names = {}
      for k, m in pairs(G.roster) do names[#names + 1] = { k, m.name } end
      table.sort(names, function(a, b) return a[2] < b[2] end)
      for _, n in ipairs(names) do o[#o + 1] = n end
      return o
    end, function() return r.entry and V.map and V.map[r.entry.id] or false end, function(v) if r.entry then V.map[r.entry.id] = v end end)
    r.dd:SetPoint("RIGHT", 0, 0)
    return r
  end)
  p.apply = W.Button(p, L.RAID_IMP_APPLY, true, 22)
  p.apply:SetPoint("BOTTOMRIGHT", 0, 4)
  p.apply:SetScript("OnClick", function()
    local e = current()
    if not e or not V.imp then return end
    local a, k, sk = R.ApplyImport(e, V.imp, V.map)
    U.Print(L.RAID_IMP_DONE:format(a, k, sk))
    V.imp = nil; p.edit:SetText("")
    UI.Show("raids")
  end)
end

local function refreshImport(p)
  p.chips:Refresh()
  local e = current()
  local imp = V.imp
  p.apply:SetShown(imp ~= nil and e ~= nil and R.CanEdit(e))
  p.list:SetShown(imp ~= nil)
  if not e then p.status:SetText(L.RAID_NONE)
  elseif not R.CanEdit(e) then p.status:SetText(L.RAID_IMP_RIGHTS)
  elseif not imp then p.status:SetText(L.RAID_IMP_EMPTY)
  else p.status:SetText(L.RAID_IMP_READ_N:format(#imp.list, imp.title or "?", e.name)) end
  local n = 0
  for _, x in ipairs(imp and imp.list or {}) do
    n = n + 1
    local r = p.rows:Get(n)
    r.entry = x
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(n - 1) * 26); r:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
    r.name:SetText((x.class and U.Color(R.CLASS_COLOR[x.class], x.name)) or x.name)
    r.spec:SetText((x.spec or "?") .. " · " .. L["ST_" .. x.st] .. (x.note and (" · »" .. x.note .. "«") or ""))
    r.dd:Refresh()
  end
  p.rows:HideFrom(n + 1)
  p.scroll:SetContentHeight(n * 26)
end

---------------------------------------------------------------------------
-- Settings page: who may create raids, role targets
---------------------------------------------------------------------------
-- the example under "early sign-up": with the values as typed, before saving
local function earlyHint(p)
  local rule = R.Early()
  local min = tonumber(p.earlyMin:GetText()) or rule.min
  local per = tonumber(p.perDay:GetText()) or rule.perDay
  if per < 1 then per = 1 end
  local cur = { min = min, perDay = math.floor(per) }
  local top = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
  local pts = core.Profile.Get().pts.participate or 10
  local text = L.RAID_EARLY_HINT:format(min, top, min, cur.perDay, R.EarlyDays(top, min, cur))
  if p.bonus:GetChecked() and cur.perDay > 1 then text = text .. " " .. L.RAID_EARLY_BONUS_EX:format(pts, cur.perDay, pts * cur.perDay) end
  p.earlyHint:SetText(text)
end

local function buildSettings(p)
  p.head = UI.Section(p, L.RAID_SETTINGS); p.head:SetPoint("TOPLEFT", 0, 0)
  p.rankLabel = W.Text(p, 11, "text"); p.rankLabel:SetPoint("TOPLEFT", 0, -30); p.rankLabel:SetText(L.RAID_RANK)
  p.rank = W.Dropdown(p, 220, function()
    local o = {}
    for i = 1, 9 do
      if G.rankNames[i] then o[#o + 1] = { i, L.RAID_RANK_MIN:format(G.rankNames[i]) } end
    end
    if #o == 0 then o[1] = { 1, L.RAID_RANK_MIN:format("1") } end
    return o
  end, function() return R.RaidRank() end, function(v)
    core.Profile.Update(function(pr) pr.raidRank = v end)
  end)
  p.rank:SetPoint("TOPLEFT", p.rankLabel, "BOTTOMLEFT", 0, -6)
  p.rankHint = W.Text(p, 10, "muted"); p.rankHint:SetPoint("LEFT", p.rank, "RIGHT", 10, 0); p.rankHint:SetPoint("RIGHT", 0, 0)
  p.rankHint:SetSpacing(2)
  -- early sign-up below the raid level (one level a day)
  p.earlyHead = UI.Section(p, L.RAID_EARLY); p.earlyHead:SetPoint("TOPLEFT", 0, -100)
  p.early = W.Check(p, L.RAID_EARLY_ON, function(_, on)
    core.Profile.Update(function(pr) pr.pve = pr.pve or {}; pr.pve.early = pr.pve.early or {}; pr.pve.early.on = on end)
  end)
  p.early:SetPoint("TOPLEFT", 0, -130)
  p.earlyMinL = W.Text(p, 11, "text"); p.earlyMinL:SetPoint("TOPLEFT", 0, -154); p.earlyMinL:SetText(L.RAID_EARLY_MIN)
  p.earlyMin = W.Edit(p, 44, 22); p.earlyMin:SetNumeric(true); p.earlyMin:SetMaxLetters(2)
  p.earlyMin:SetPoint("LEFT", p.earlyMinL, "RIGHT", 8, 0)
  p.earlyMin:SetScript("OnTextChanged", function() if p.earlyHint then earlyHint(p) end end)
  p.earlyMin:SetScript("OnEnterPressed", function(self)
    local v = tonumber(self:GetText())
    if v and v >= 1 then core.Profile.Update(function(pr) pr.pve = pr.pve or {}; pr.pve.early = pr.pve.early or {}; pr.pve.early.min = v end) end
    self:ClearFocus()
  end)
  p.perDayL = W.Text(p, 11, "text"); p.perDayL:SetPoint("LEFT", p.earlyMin, "RIGHT", 24, 0); p.perDayL:SetText(L.RAID_EARLY_PERDAY)
  p.perDay = W.Edit(p, 44, 22); p.perDay:SetNumeric(true); p.perDay:SetMaxLetters(2)
  p.perDay:SetPoint("LEFT", p.perDayL, "RIGHT", 8, 0)
  p.perDay:SetScript("OnTextChanged", function() if p.earlyHint then earlyHint(p) end end)
  p.perDay:SetScript("OnEnterPressed", function(self)
    local v = tonumber(self:GetText())
    if v and v >= 1 then core.Profile.Update(function(pr) pr.pve = pr.pve or {}; pr.pve.early = pr.pve.early or {}; pr.pve.early.perDay = v end) end
    self:ClearFocus()
  end)
  p.bonus = W.Check(p, L.RAID_EARLY_BONUS, function(_, on)
    core.Profile.Update(function(pr) pr.pve = pr.pve or {}; pr.pve.early = pr.pve.early or {}; pr.pve.early.bonus = on end)
    earlyHint(p)
  end)
  p.bonus:SetPoint("TOPLEFT", 0, -186)
  p.earlyHint = W.Text(p, 10, "muted"); p.earlyHint:SetPoint("TOPLEFT", 0, -210); p.earlyHint:SetPoint("RIGHT", 0, 0)
  p.earlyHint:SetSpacing(2)

  p.needHead = UI.Section(p, L.RAID_NEED); p.needHead:SetPoint("TOPLEFT", 0, -270)
  p.edits = {}
  for i, t in ipairs(R.TEMPLATES) do
    local y = -298 - (i - 1) * 34
    local l = W.Text(p, 11, "text"); l:SetPoint("TOPLEFT", 0, y - 4); l:SetWidth(200); l:SetText(R.TplName(t))
    local tl = W.Text(p, 10, "muted"); tl:SetPoint("TOPLEFT", 210, y - 4); tl:SetText(L.RAID_KIND_tank)
    local te = W.Edit(p, 40, 22); te:SetPoint("TOPLEFT", 270, y); te:SetNumeric(true)
    local hl = W.Text(p, 10, "muted"); hl:SetPoint("TOPLEFT", 330, y - 4); hl:SetText(L.RAID_KIND_heal)
    local he = W.Edit(p, 40, 22); he:SetPoint("TOPLEFT", 390, y); he:SetNumeric(true)
    p.edits[t.id] = { te, he }
  end
  p.save = W.Button(p, core.L.SAVE, true, 22)
  p.save:SetPoint("TOPLEFT", 0, -298 - #R.TEMPLATES * 34 - 6)
  p.save:SetScript("OnClick", function()
    core.Profile.Update(function(pr)
      pr.pve = pr.pve or {}
      local v = tonumber(p.earlyMin:GetText())
      if v and v >= 1 then pr.pve.early = pr.pve.early or {}; pr.pve.early.min = v end
      local per = tonumber(p.perDay:GetText())
      if per and per >= 1 then pr.pve.early = pr.pve.early or {}; pr.pve.early.perDay = per end
      pr.pve.need = pr.pve.need or {}
      for id, ed in pairs(p.edits) do
        pr.pve.need[id] = { tank = tonumber(ed[1]:GetText()), heal = tonumber(ed[2]:GetText()) }
      end
    end)
    U.Print(core.L.SAVED)
  end)
  p.note = W.Text(p, 10, "muted"); p.note:SetPoint("TOPLEFT", p.save, "BOTTOMLEFT", 0, -14); p.note:SetPoint("RIGHT", 0, 0)
  p.note:SetSpacing(2); p.note:SetText(L.RAID_SETTINGS_NOTE)
end

local function refreshSettings(p)
  p.rank:Refresh()
  p.rank:SetEnabled(G.IsLeader())
  p.rankHint:SetText(G.IsLeader() and L.RAID_RANK_HINT or L.RAID_RANK_GM)
  local mgr = G.IsManager()
  for _, t in ipairs(R.TEMPLATES) do
    local need = R.Need(t)
    local ed = p.edits[t.id]
    if not ed[1]:HasFocus() then ed[1]:SetText(tostring(need.tank or "")) end
    if not ed[2]:HasFocus() then ed[2]:SetText(tostring(need.heal or "")) end
    ed[1]:SetEnabled(mgr); ed[2]:SetEnabled(mgr)
  end
  p.save:SetShown(mgr)
  local rule = R.Early()
  p.early:SetChecked(rule.on)
  p.early:SetEnabled(mgr)
  if not p.earlyMin:HasFocus() then p.earlyMin:SetText(tostring(rule.min)) end
  p.earlyMin:SetEnabled(mgr)
  if not p.perDay:HasFocus() then p.perDay:SetText(tostring(rule.perDay)) end
  p.perDay:SetEnabled(mgr)
  p.bonus:SetChecked(rule.bonus); p.bonus:SetEnabled(mgr)
  earlyHint(p)
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
UI.AddModule("raids", {
  label = function() return L.TAB_RAIDS end,
  icon = W.Icon("raids"),
  category = "module",
  order = 5,
  badge = function()
    local n = 0
    for _, e in ipairs(R.RaidEvents(true)) do if not E.Status(e) and E.CanSignUp(e) then n = n + 1 end end
    return n > 0 and tostring(n) or nil
  end,
  tabs = {
    { id = "raids", label = function() return core.L.TAB_HOME end, build = buildOverview, refresh = refreshOverview },
    { id = "raidplan", label = function() return L.RAID_TAB_PLAN end, build = buildPlan, refresh = refreshPlan },
    { id = "raidnight", label = function() return L.RAID_TAB_NIGHT end, build = buildNight, refresh = refreshNight },
    { id = "raidimport", label = function() return L.RAID_TAB_IMPORT end, build = buildImport, refresh = refreshImport },
  },
})

-- help ("?" in the header)
if UI.AddHelp then
  for _, id in ipairs({ "raids", "raidplan", "raidnight", "raidimport" }) do
    UI.AddHelp(id, function() return core.L["HELP_T_" .. id], core.L["HELP_X_" .. id] end)
  end
end

UI.AddSettingsPage("raidsettings", {
  label = function() return L.TAB_RAIDS end,
  build = buildSettings,
  refresh = refreshSettings,
})

-- raid events read in the honor book like other events (core), nothing to add
