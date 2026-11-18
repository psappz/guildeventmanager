local ADDON, R = ...
-- Raid assignments tab: one card per class with tasks. Only players in the
-- line-up appear, with their group. A click on a cell opens a short list with
-- what the player can cast; gaps are yellow. "Your task" on top for everyone.
local core = R.core
local U, G, T, W, UI, E = core.U, core.Guild, core.Theme, core.W, core.UI, core.Events
local L = R.L

local NAME_W, CELL_W, CELL_H, ROW_GAP = 150, 66, 22, 4
local WARN = "fff0c060"

local function nameOf(x)
  local c = x.class and R.CLASS_COLOR and R.CLASS_COLOR[x.class] or "ffd0c8bc"
  return U.Color(c, G.Display(x.key)) .. U.Color("ff8a8078", "  G" .. tostring(x.group or "?"))
end

-- a cell: shows the short label, opens the options on click
local function cell(parent, w)
  local b = W.Button(parent, "", false, CELL_H)
  b:SetWidth(w or CELL_W)
  b.label:SetWordWrap(false)
  b:SetScript("OnClick", function(self)
    if not self.options then return end
    W.OpenMenu(self, function(_, root)
      -- at a boss setup: back to the standard, or "nothing" just here
      if self.boss and self.boss > 0 then
        root:CreateRadio(L.RAID_A_STD_OPT, function() return not self.own end, function() self.set(nil) end)
        root:CreateRadio(L.RAID_A_NONE_OPT, function() return self.own and self.value == nil end, function() self.set("-") end)
      else
        root:CreateRadio(L.RAID_A_NONE_OPT, function() return self.value == nil end, function() self.set(nil) end)
      end
      for _, o in ipairs(self.options) do
        root:CreateRadio(o[2], function() return self.value == o[1] end, function() self.set(o[1]) end)
      end
    end)
  end)
  b:SetScript("OnEnter", function(self)
    if not self.own or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(L.RAID_A_BOSS_OWN); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return b
end

-- own = differs at this boss setup (marked with a dot)
local function setCell(b, value, text, options, set, edit, warn, own, boss)
  b.value, b.options, b.set, b.own, b.boss = value, edit and options or nil, set, own, boss
  local th = T.Current()
  local t = text or "–"
  if warn then t = U.Color(WARN, t) elseif not value then t = U.Color(T.Hex(th.muted), t) end
  if own then t = U.Color(T.Hex(th.title), "• ") .. t end
  W.SetLabel(b, t)
  b:SetEnabled(edit)
end

local function opts(list)
  local o = {}
  for _, x in ipairs(list) do o[#o + 1] = { x.id, R.AName(list, x.id) } end
  return o
end

local function card(parent, title)
  local th = T.Current()
  local c = W.Box(parent, 10, 10, "panel2")
  c:SetBackdropBorderColor(th.line[1], th.line[2], th.line[3], 1)
  c.title = W.Text(c, 13, "title"); c.title:SetPoint("TOPLEFT", 10, -8); c.title:SetText(title)
  c.sub = W.Text(c, 10, "muted"); c.sub:SetPoint("LEFT", c.title, "RIGHT", 10, 0); c.sub:SetPoint("RIGHT", -10, 0)
  c.sub:SetWordWrap(false)
  c.rows = {}
  c.head = {}
  c.note = W.Text(c, 10, "text"); c.note:SetSpacing(2)
  return c
end

-- a row of a card: name and cells
local function row(c, i, n, w)
  local r = c.rows[i]
  if not r then
    r = CreateFrame("Frame", nil, c)
    r:SetHeight(CELL_H)
    r.name = W.Text(r, 11, "text"); r.name:SetPoint("LEFT", 0, 0); r.name:SetWidth(NAME_W - 6); r.name:SetWordWrap(false)
    r.cells = {}
    c.rows[i] = r
  end
  for j = 1, n do
    if not r.cells[j] then r.cells[j] = cell(r, w) end
    local b = r.cells[j]
    b:SetWidth(w or CELL_W)
    b:ClearAllPoints(); b:SetPoint("LEFT", NAME_W + (j - 1) * ((w or CELL_W) + 4), 0)
    b:Show()
  end
  for j = n + 1, #r.cells do r.cells[j]:Hide() end
  r:Show()
  return r
end

local function headers(c, labels, w)
  for j, txt in ipairs(labels) do
    local h = c.head[j]
    if not h then h = W.Text(c, 10, "muted"); h:SetWordWrap(false); h:SetJustifyH("CENTER"); c.head[j] = h end
    h:SetWidth(w or CELL_W)
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", 10 + NAME_W + (j - 1) * ((w or CELL_W) + 4), -30)
    h:SetText(txt); h:Show()
  end
  for j = #labels + 1, #c.head do c.head[j]:Hide() end
end

-- lay out the rows of a card from y and return the card height
local function place(c, n, y0)
  local y = y0
  for i = 1, n do
    local r = c.rows[i]
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, -y); r:SetPoint("RIGHT", c, "RIGHT", -10, 0)
    y = y + CELL_H + ROW_GAP
  end
  for i = n + 1, #c.rows do c.rows[i]:Hide() end
  if c.note:GetText() and c.note:GetText() ~= "" then
    c.note:ClearAllPoints(); c.note:SetPoint("TOPLEFT", 10, -(y + 2)); c.note:SetPoint("RIGHT", -10, 0)
    y = y + c.note:GetStringHeight() + 8
  end
  return y + 8
end

function R.BuildAssign(p)
  p.chips = R.RaidChips(p)
  p.auto = W.Button(p, L.RAID_A_AUTO, false, 22); p.auto:SetWidth(170)
  p.post = W.Button(p, L.RAID_A_POST, false, 22); p.post:SetWidth(140)
  p.post:SetPoint("TOPRIGHT", 0, 0)
  p.auto:SetPoint("RIGHT", p.post, "LEFT", -6, 0)
  -- the boss setup: differences per boss (shared with the line-up)
  p.boss = W.Dropdown(p, 200, function()
    local e = R.Current(); local t = e and R.TemplateOf(e)
    local o = { { 0, L.RAID_SETUP_STD } }
    if t then for pos, i in ipairs(R.BossOrder(t)) do o[#o + 1] = { i, pos .. ". " .. R.BossName(t, i) } end end
    return o
  end, function() local e = R.Current(); return e and R.Plan(e).b or 0 end,
  function(v) local e = R.Current(); if e then if R.CanEdit(e) then R.SetBoss(e, v) else R.Plan(e).b = v end; UI.Refresh() end end)
  p.boss:SetPoint("RIGHT", p.auto, "LEFT", -6, 0)
  p.auto:SetScript("OnClick", function() local e = R.Current(); if e then R.AutoAssign(e); UI.Refresh() end end)
  p.post:SetScript("OnClick", function() local e = R.Current(); if e then R.PostAssignments(e) end end)
  p.mine = W.Box(p, 10, 10, "panel2")
  p.mine:SetPoint("TOPLEFT", 0, -32); p.mine:SetPoint("RIGHT", 0, 0); p.mine:SetHeight(30)
  p.mine.text = W.Text(p.mine, 11, "text"); p.mine.text:SetPoint("LEFT", 10, 0); p.mine.text:SetPoint("RIGHT", -10, 0)
  p.mine.text:SetWordWrap(false)
  p.scroll = W.Scroll(p)
  p.scroll:SetPoint("TOPLEFT", 0, -70); p.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
  local col = p.scroll.content
  p.cards = {
    pal = card(col, L.RAID_A_PAL),
    sha = card(col, L.RAID_A_SHA),
    wl = card(col, L.RAID_A_WL),
    pri = card(col, L.RAID_A_PRI),
  }
  p.empty = W.Text(col, 11, "muted"); p.empty:SetPoint("TOPLEFT", 0, -4); p.empty:SetPoint("RIGHT", 0, 0)
  p.empty:SetSpacing(2)
end

function R.RefreshAssign(p)
  p.chips:Refresh()
  local e = R.Current()
  for _, c in pairs(p.cards) do c:Hide() end
  p.auto:SetShown(e ~= nil and R.CanEdit(e)); p.post:SetShown(e ~= nil)
  if not e then p.mine:Hide(); p.empty:SetText(L.RAID_NONE); p.empty:Show(); return end
  local edit = R.CanEdit(e)
  local who = R.AssignPlayers(e)
  local boss = R.Plan(e).b or 0
  p.boss:Refresh()
  local gaps = R.AssignGaps(e, boss)
  local mine = R.MyTasks(e, nil, boss)
  local function get(kind, key, field) return R.AGet(e, kind, key, field, boss) end
  p.mine:Show()
  p.mine.text:SetText(U.Color(T.Hex(T.Current().title), L.RAID_A_MINE) .. "  " .. (#mine > 0 and table.concat(mine, " · ") or U.Color("ff8a8078", L.RAID_A_MINE_NONE)))
  local y = 0
  local any = #who.pal + #who.sha + #who.wl + #who.pri > 0
  p.empty:SetShown(not any)
  if not any then p.empty:SetText(L.RAID_A_EMPTY) end

  -- paladins: a blessing per class, an aura
  local c = p.cards.pal
  if #who.pal > 0 then
    c:Show(); c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y); c:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
    c.sub:SetText(L.RAID_A_PAL_SUB)
    local labels = {}
    for _, cl in ipairs(who.classes) do labels[#labels + 1] = R.ClassName(cl) end
    labels[#labels + 1] = L.RAID_A_AURA
    headers(c, labels)
    local bless, aura = opts(R.A_BLESS), opts(R.A_AURA)
    for i, x in ipairs(who.pal) do
      local r = row(c, i, #who.classes + 1)
      r.name:SetText(nameOf(x))
      for j, cl in ipairs(who.classes) do
        local v, own = get("pal", x.key, "c:" .. cl)
        setCell(r.cells[j], v, v and R.AShort("bless", v) or "–", bless,
          function(id) R.SetBlessing(e, x.key, cl, id, boss); UI.Refresh() end, edit, (not v) and gaps.noBless[cl], own, boss)
      end
      local b = r.cells[#who.classes + 1]
      local av, aown = get("pal", x.key, "aura")
      setCell(b, av, av and R.AShort("aura", av) or "–", aura, function(id) R.SetAura(e, x.key, id, boss); UI.Refresh() end, edit, nil, aown, boss)
    end
    local miss = {}
    for _, cl in ipairs(who.classes) do if gaps.noBless[cl] then miss[#miss + 1] = R.ClassName(cl) end end
    c.note:SetText(#miss > 0 and U.Color(WARN, L.RAID_A_GAP_BLESS:format(table.concat(miss, ", "))) or "")
    local h = place(c, #who.pal, 48)
    c:SetHeight(h); y = y + h + 8
  end

  -- shamans: one totem per element (works in the own group)
  c = p.cards.sha
  if #who.sha > 0 then
    c:Show(); c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y); c:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
    c.sub:SetText(L.RAID_A_SHA_SUB)
    local labels = {}
    for _, el in ipairs(R.A_ELEMENTS) do labels[#labels + 1] = L["RAID_A_EL_" .. el] end
    headers(c, labels, 140)
    for i, x in ipairs(who.sha) do
      local r = row(c, i, #R.A_ELEMENTS, 140)
      r.name:SetText(nameOf(x))
      for j, el in ipairs(R.A_ELEMENTS) do
        local v, own = get("sha", x.key, el)
        setCell(r.cells[j], v, v and R.AName(R.A_TOTEM[el], v) or "–", opts(R.A_TOTEM[el]),
          function(id) R.SetTotem(e, x.key, el, id, boss); UI.Refresh() end, edit, nil, own, boss)
      end
    end
    local t = {}
    for _, g in ipairs(gaps.noWF) do t[#t + 1] = tostring(g) end
    c.note:SetText(#t > 0 and U.Color(WARN, L.RAID_A_GAP_WF:format(table.concat(t, ", "))) or "")
    local h = place(c, #who.sha, 48)
    c:SetHeight(h); y = y + h + 8
  end

  -- warlocks: a curse and a bane on the boss
  c = p.cards.wl
  if #who.wl > 0 then
    c:Show(); c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y); c:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
    c.sub:SetText(L.RAID_A_WL_SUB)
    headers(c, { L.RAID_A_CURSE, L.RAID_A_BANE }, 180)
    for i, x in ipairs(who.wl) do
      local r = row(c, i, 2, 180)
      r.name:SetText(nameOf(x))
      local cv, cown = get("wl", x.key, "curse")
      local bv, bown = get("wl", x.key, "bane")
      setCell(r.cells[1], cv, cv and R.AName(R.A_CURSE, cv) or "–", opts(R.A_CURSE),
        function(id) R.SetCurse(e, x.key, "curse", id, boss); UI.Refresh() end, edit, cv and gaps.dupCurse[cv], cown, boss)
      setCell(r.cells[2], bv, bv and R.AName(R.A_BANE, bv) or "–", opts(R.A_BANE),
        function(id) R.SetCurse(e, x.key, "bane", id, boss); UI.Refresh() end, edit, nil, bown, boss)
    end
    local d = {}
    for id in pairs(gaps.dupCurse) do d[#d + 1] = R.AName(R.A_CURSE, id) end
    c.note:SetText(#d > 0 and U.Color(WARN, L.RAID_A_GAP_CURSE:format(table.concat(d, ", "))) or "")
    local h = place(c, #who.wl, 48)
    c:SetHeight(h); y = y + h + 8
  end

  -- priests: fear ward on a tank
  c = p.cards.pri
  if #who.pri > 0 then
    c:Show(); c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y); c:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
    c.sub:SetText(L.RAID_A_PRI_SUB)
    headers(c, { L.RAID_A_FW_ON }, 220)
    local tanks = {}
    for _, t in ipairs(who.tanks) do tanks[#tanks + 1] = { t.key, G.Display(t.key) .. "  (" .. (L["RAID_ROLE_" .. tostring(t.role)] or t.role or "") .. ")" } end
    for i, x in ipairs(who.pri) do
      local r = row(c, i, 1, 220)
      r.name:SetText(nameOf(x))
      local v, own = get("fw", x.key, "t")
      setCell(r.cells[1], v, v and G.Display(v) or "–", tanks, function(k) R.SetFearWard(e, x.key, k, boss); UI.Refresh() end, edit, nil, own, boss)
    end
    c.note:SetText(#who.tanks == 0 and U.Color(WARN, L.RAID_A_NO_TANKS) or "")
    local h = place(c, #who.pri, 48)
    c:SetHeight(h); y = y + h + 8
  end
  p.scroll:SetContentHeight(y)
end
