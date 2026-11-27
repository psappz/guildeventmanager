local ADDON, ns = ...
-- Org chart (0.9): posts of the guild as a tree – guild master, officers,
-- raid leads, class leads (with their classes and members), own posts.
-- "+" under a post folds its branch out. The guild leadership edits posts below.
local U, G, T, W, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI
local L = ns.L
local S = ns.Struct

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local NW, NH, GAP, VGAP, LINE_H = 118, 44, 8, 22, 12

local function hexRGB(c)
  c = c or "6b5445"
  return tonumber(c:sub(1, 2), 16) / 255, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255
end

local function kindCol(n)
  local f = (n.kind == "gm" or n.kind == "off" or n.kind == "council" or n.kind == "member") and S.Func("lead") or (n.kind == "raid" and S.Func("raid")) or (n.kind == "cls" and S.Func("cls"))
  return f and f.col or "ff805c"
end

-- tree items: posts and, below class leads, their classes
local function children(p, item)
  if item.cls then return {} end
  local out = {}
  for _, n in ipairs(S.Children(item.node.id)) do out[#out + 1] = { node = n } end
  if S.LeadsClasses(item.node) then
    for _, c in ipairs(item.node.cls or {}) do out[#out + 1] = { cls = c, parentId = item.node.id } end
  end
  return out
end

local function key(item) return item.cls and (item.parentId .. ":" .. item.cls) or tostring(item.node.id) end

local function nodeHeight(p, item)
  if item.cls and p.open[key(item)] then
    local m = (p.members[item.cls] or {})
    return NH + 4 + #m * LINE_H
  end
  if item.node and item.node.duties then
    local c = 0
    for _, d in ipairs(item.node.duties) do if S.DutyLabel(d) then c = c + 1 end end
    if c > 0 then return NH + 2 + c * LINE_H end
  end
  return NH
end

-- Layout. Each open post grows "down" (default) or "right" (the leadership
-- picks it with the + on the bottom or the right edge; kept per client).
-- Down: children side by side, or – with VERT_MIN or more below the top level –
-- listed downwards with a line on the left. Right: children listed beside the post.
local VERT_MIN, INDENT, VGAP2, HGAP = 4, 22, 8, 26

local function dirOf(k)
  local d = ns.db and ns.db.orgDir and ns.db.orgDir[k]
  return d == "right" and "right" or "down"
end

local function setDir(k, d)
  if not ns.db then return end
  ns.db.orgDir = ns.db.orgDir or {}
  ns.db.orgDir[k] = (d == "right") and "right" or nil
end

local function measure(p, item, depth)
  local k = key(item)
  local kids = p.open[k] and children(p, item) or {}
  item.kids = kids
  item.nh = nodeHeight(p, item)
  item.dir = dirOf(k)
  item.vert = item.dir == "down" and #kids >= VERT_MIN and depth > 1
  if #kids == 0 then item.w, item.h = NW, item.nh; return end
  if item.dir == "right" then
    local w, h = 0, 0
    for i, c in ipairs(kids) do measure(p, c, depth + 1); w = math.max(w, c.w); h = h + c.h + (i > 1 and VGAP2 or 0) end
    item.w, item.h = NW + HGAP + w, math.max(item.nh, h)
  elseif item.vert then
    local w, h = 0, item.nh
    for _, c in ipairs(kids) do measure(p, c, depth + 1); w = math.max(w, c.w); h = h + VGAP2 + c.h end
    item.w, item.h = math.max(NW, INDENT + w), h
  else
    local w, h = 0, 0
    for i, c in ipairs(kids) do measure(p, c, depth + 1); w = w + c.w + (i > 1 and GAP or 0); h = math.max(h, c.h) end
    item.w, item.h = math.max(NW, w), item.nh + VGAP + h
  end
end

local function place(p, item, x, y)
  item.y = y
  if item.dir == "right" and #(item.kids or {}) > 0 then
    item.x = x
    local cy = y
    for _, c in ipairs(item.kids) do place(p, c, x + NW + HGAP, cy); cy = cy + c.h + VGAP2 end
  elseif item.vert then
    item.x = x
    local cy = y + item.nh + VGAP2
    for _, c in ipairs(item.kids) do place(p, c, x + INDENT, cy); cy = cy + c.h + VGAP2 end
  else
    item.x = x + (item.w - NW) / 2
    local cx = x
    for _, c in ipairs(item.kids or {}) do place(p, c, cx, y + item.nh + VGAP); cx = cx + c.w + GAP end
  end
end

-- is "id" (or one of its parents) the post "anc"?
local function under(id, anc)
  local seen = 0
  while id ~= nil and seen < 50 do
    if id == anc then return true end
    local n = S.Node(id)
    id = n and n.parent
    seen = seen + 1
  end
  return false
end

local function build(p)
  local th = T.Current()
  p.open = {}
  p.head = W.Text(p, 10, "muted"); p.head:SetPoint("TOPLEFT", 0, 0); p.head:SetText(L.ORG_HINT)
  p.allOpen = W.Button(p, L.ORG_OPEN_ALL, false, 20); p.allOpen:SetPoint("TOPRIGHT", -96, 2); p.allOpen:SetWidth(110)
  p.allClose = W.Button(p, L.ORG_CLOSE_ALL, false, 20); p.allClose:SetPoint("TOPRIGHT", 0, 2); p.allClose:SetWidth(90)
  p.allOpen:SetScript("OnClick", function()
    for _, n in ipairs(S.Org().nodes) do p.open[tostring(n.id)] = true; for _, c in ipairs(n.cls or {}) do p.open[n.id .. ":" .. c] = true end end
    ns.UI.Refresh()
  end)
  p.allClose:SetScript("OnClick", function() p.open = {}; ns.UI.Refresh() end)
  -- templates (guild leadership): replace the chart, second click confirms
  p.tplVal = "classic"
  p.tpl = W.Dropdown(p, 150, function()
    local o = {}
    for _, t in ipairs(S.ORG_TEMPLATES) do o[#o + 1] = { t, L["ORG_T_" .. t] } end
    return o
  end, function() return p.tplVal end, function(v) p.tplVal = v; p.tplArm = nil; ns.UI.Refresh() end)
  p.tpl:SetPoint("RIGHT", p.allOpen, "LEFT", -150, 0)
  p.head:SetWordWrap(false)
  p.tplBtn = W.Button(p, L.ORG_T_APPLY, false, 20); p.tplBtn:SetPoint("LEFT", p.tpl, "RIGHT", 6, 0); p.tplBtn:SetWidth(130)
  p.tplBtn:SetScript("OnClick", function(self)
    if not p.tplArm then p.tplArm = true; self.label:SetText(L.ORG_T_SURE); return end
    p.tplArm = nil; self.label:SetText(L.ORG_T_APPLY)
    S.ApplyTemplate(p.tplVal); p.open = {}; p.sel = nil
  end)
  p.scroll = W.Scroll(p)
  p.scroll:SetPoint("TOPLEFT", 0, -26); p.scroll:SetPoint("BOTTOMRIGHT", 0, 138)
  p.canvas = p.scroll.content
  p.scroll:SetScript("OnSizeChanged", nil)   -- the canvas keeps its own width
  p.zoom = 1
  -- wheel: up/down, with Shift sideways; drag the background to move the chart
  p.scroll:SetScript("OnMouseWheel", function(self, delta)
    if IsShiftKeyDown and IsShiftKeyDown() then
      self:SetHorizontalScroll(math.max(0, math.min(p.maxH or 0, self:GetHorizontalScroll() - delta * 60)))
    else
      self:SetVerticalScroll(math.max(0, math.min(p.maxV or 0, self:GetVerticalScroll() - delta * 40)))
    end
    p.syncBar()
  end)
  p.scroll:EnableMouse(true)
  p.scroll:SetScript("OnMouseDown", function(self, btn)
    if btn ~= "LeftButton" then return end
    local x, y = GetCursorPosition()
    self.drag = { x = x, y = y, h = self:GetHorizontalScroll(), v = self:GetVerticalScroll() }
  end)
  p.scroll:SetScript("OnMouseUp", function(self) self.drag = nil end)
  p.scroll:SetScript("OnUpdate", function(self)
    local d = self.drag
    if not d then return end
    if not IsMouseButtonDown or not IsMouseButtonDown("LeftButton") then self.drag = nil; return end
    local x, y = GetCursorPosition()
    local sc = self:GetEffectiveScale() or 1
    self:SetHorizontalScroll(math.max(0, math.min(p.maxH or 0, d.h - (x - d.x) / sc)))
    self:SetVerticalScroll(math.max(0, math.min(p.maxV or 0, d.v + (y - d.y) / sc)))
    p.syncBar()
  end)
  -- position bar below the chart
  p.bar = p:CreateTexture(nil, "ARTWORK")
  p.bar:SetHeight(3)
  p.bar:SetColorTexture(th.title[1], th.title[2], th.title[3], 0.6)
  function p.syncBar()
    local w = p.scroll:GetWidth() or 0
    local maxH = p.maxH or 0
    if maxH <= 0 or w <= 0 then p.bar:Hide(); return end
    local frac = w / (w + maxH)
    local bw = math.max(30, w * frac)
    local pos = (p.scroll:GetHorizontalScroll() or 0) / maxH * (w - bw)
    p.bar:ClearAllPoints(); p.bar:SetPoint("TOPLEFT", p.scroll, "BOTTOMLEFT", pos, -2); p.bar:SetWidth(bw)
    p.bar:Show()
  end
  -- zoom
  p.zoomOut = W.Button(p, "-", false, 20); p.zoomOut:SetWidth(22)
  p.zoomL = W.Text(p, 10, "muted")
  p.zoomIn = W.Button(p, "+", false, 20); p.zoomIn:SetWidth(22)
  p.zoomIn:SetPoint("RIGHT", p.tpl, "LEFT", -12, 0)
  p.zoomL:SetPoint("RIGHT", p.zoomIn, "LEFT", -4, 0)
  p.zoomOut:SetPoint("RIGHT", p.zoomL, "LEFT", -4, 0)
  p.head:SetPoint("RIGHT", p.zoomOut, "LEFT", -8, 0)
  p.zoomOut:SetScript("OnClick", function() p.zoom = math.max(0.5, (p.zoom or 1) - 0.1); ns.UI.Refresh() end)
  p.zoomIn:SetScript("OnClick", function() p.zoom = math.min(1.5, (p.zoom or 1) + 0.1); ns.UI.Refresh() end)
  p.nodes = W.Pool(p.canvas, function(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(NW, NH)
    W.Paint(b, th.panel, th.line)
    b.stripe = b:CreateTexture(nil, "ARTWORK"); b.stripe:SetHeight(2); b.stripe:SetPoint("TOPLEFT", 1, -1); b.stripe:SetPoint("TOPRIGHT", -1, -1)
    b.kind = W.Text(b, 9, "muted"); b.kind:SetPoint("TOP", 0, -5); b.kind:SetWidth(NW - 6); b.kind:SetJustifyH("CENTER"); b.kind:SetWordWrap(false)
    b.who = W.Text(b, 11, "title"); b.who:SetPoint("TOP", b.kind, "BOTTOM", 0, -2); b.who:SetWidth(NW - 6); b.who:SetJustifyH("CENTER"); b.who:SetWordWrap(false)
    b.sub = W.Text(b, 9, "text"); b.sub:SetPoint("TOP", b.who, "BOTTOM", 0, -2); b.sub:SetWidth(NW - 6); b.sub:SetJustifyH("CENTER"); b.sub:SetWordWrap(false)
    b.list = W.Text(b, 10, "text"); b.list:SetPoint("TOPLEFT", 8, -NH + 2); b.list:SetWidth(NW - 12); b.list:SetJustifyH("LEFT"); b.list:SetSpacing(LINE_H - 10)
    b.duties = W.Text(b, 9, "text"); b.duties:SetPoint("TOPLEFT", 6, -NH + 2); b.duties:SetWidth(NW - 10); b.duties:SetJustifyH("CENTER"); b.duties:SetSpacing(LINE_H - 9)
    -- + on the bottom edge: grow down; + on the right edge: grow right
    local function edgeBtn(point, x, y, dir)
      local e = CreateFrame("Button", nil, b, "BackdropTemplate")
      e:SetSize(15, 15); e:SetPoint(point, x, y); e:SetFrameLevel(b:GetFrameLevel() + 6)
      W.Paint(e, th.accent, th.title)
      e.t = W.Text(e, 11, "text"); e.t:SetPoint("CENTER", 0, 1)
      e:SetScript("OnClick", function(self)
        local k = b.k
        if p.open[k] and dirOf(k) == dir then p.open[k] = nil
        else p.open[k] = true; setDir(k, dir) end
        ns.UI.Refresh()
      end)
      return e
    end
    b.pm = edgeBtn("BOTTOM", 0, -8, "down")
    b.pmR = edgeBtn("RIGHT", 8, 0, "right")
    local acc = 0
    b:SetScript("OnUpdate", function(self, dt)
      acc = acc + dt
      if acc < 0.1 then return end
      acc = 0
      local over = self:IsMouseOver(4, -10, -4, 10)
      if over ~= self.over then self.over = over; if self.edges then self.edges() end end
    end)
    -- drag a post onto another one: it moves there (guild leadership)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
      local n = self.nodeId and S.Node(self.nodeId)
      if not S.CanEdit() or not n or n.virtual or not n.parent then return end
      p.dragId = self.nodeId
      local gh = p.ghost
      if not gh then
        gh = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        gh:SetSize(NW, 22); gh:SetFrameStrata("TOOLTIP")
        W.Paint(gh, th.panel2, th.title)
        gh.t = W.Text(gh, 10, "title"); gh.t:SetPoint("CENTER")
        gh:SetScript("OnUpdate", function(g)
          local cx, cy = GetCursorPosition()
          local sc = UIParent:GetEffectiveScale() or 1
          g:ClearAllPoints(); g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / sc + 10, cy / sc - 14)
        end)
        p.ghost = gh
      end
      gh.t:SetText(S.KindName(n) .. (n.who and (" · " .. G.Display(n.who)) or ""))
      gh:Show()
    end)
    b:SetScript("OnDragStop", function(self)
      if p.ghost then p.ghost:Hide() end
      local id = p.dragId
      p.dragId = nil
      if not id then return end
      local target
      for _, t in ipairs(p.nodes.items) do
        if t:IsShown() and t ~= self and t.nodeId and t:IsMouseOver() then target = t.nodeId end
      end
      if target == nil or under(target, id) then return end
      S.EditOrg(function(o) for _, n in ipairs(o.nodes) do if n.id == id then n.parent = target end end end)
      p.open[tostring(target)] = true
    end)
    b:SetScript("OnClick", function(self) if self.nodeId then p.sel = self.nodeId; ns.UI.Refresh() end end)
    return b
  end)
  -- lines and box borders lie on their own layer above the boxes (but below their + buttons)
  p.lineLayer = CreateFrame("Frame", nil, p.canvas)
  p.lineLayer:SetAllPoints(p.canvas)
  p.lineLayer:SetFrameLevel(p.canvas:GetFrameLevel() + 2)
  p.lines = W.Pool(p.lineLayer, function(parent)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(th.line[1], th.line[2], th.line[3], 1)
    return t
  end)
  p.missing = W.Text(p, 10, "hot"); p.missing:SetPoint("BOTTOMLEFT", 0, 122); p.missing:SetPoint("RIGHT", p, "RIGHT", 0, 0); p.missing:SetJustifyH("LEFT")

  -- editor (guild leadership)
  local ed = CreateFrame("Frame", nil, p, "BackdropTemplate")
  W.Paint(ed, th.panel, th.line)
  ed:SetPoint("BOTTOMLEFT", 0, 0); ed:SetPoint("BOTTOMRIGHT", 0, 0); ed:SetHeight(116)
  p.ed = ed
  local function edit(fn) S.EditNode(p.sel, fn) end
  ed.kind = W.Dropdown(ed, 130, function()
    local o = {}
    for _, k in ipairs(S.KINDS) do o[#o + 1] = { k, L["ST_K_" .. k] } end
    return o
  end, function() local n = S.Node(p.sel); return n and n.kind end, function(v) edit(function(n) n.kind = v; if v ~= "cls" then n.cls = nil end end) end)
  ed.kind:SetPoint("TOPLEFT", 8, -8)
  ed.title = W.Edit(ed, 120, 22); ed.title:SetPoint("LEFT", ed.kind, "RIGHT", 6, 0)
  ed.title:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  ed.title:SetScript("OnEditFocusLost", function(self) local v = self:GetText(); edit(function(n) n.title = v end) end)
  ed.whoL = W.Text(ed, 10, "muted"); ed.whoL:SetPoint("LEFT", ed.title, "RIGHT", 10, 0); ed.whoL:SetText(L.ORG_WHO)
  ed.who = W.Edit(ed, 140, 22); ed.who:SetPoint("LEFT", ed.whoL, "RIGHT", 6, 0)
  ed.who:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  local function saveWho(text)
    local k = G.Resolve((text or ""):match("^%s*(.-)%s*$"))
    if k then edit(function(n) n.who = ns.Persons.MainOf(k) end) end
  end
  ed.who:SetScript("OnEditFocusLost", function(self) saveWho(self:GetText()) end)
  W.NameComplete(ed.who, W.MemberNames, saveWho)
  ed.add = W.Button(ed, L.ORG_ADD, false, 22); ed.add:SetPoint("LEFT", ed.who, "RIGHT", 8, 0); ed.add:SetWidth(110)
  ed.add:SetScript("OnClick", function()
    local pid = p.sel
    S.EditOrg(function(o)
      o.next = (o.next or #o.nodes + 1)
      o.nodes[#o.nodes + 1] = { id = o.next, kind = "cls", parent = pid, cls = {} }
      p.sel = o.next
      o.next = o.next + 1
    end)
    p.open[tostring(pid)] = true
  end)
  ed.del = W.Button(ed, L.ORG_DEL, false, 22); ed.del:SetPoint("LEFT", ed.add, "RIGHT", 6, 0); ed.del:SetWidth(80)
  ed.del:SetScript("OnClick", function()
    local id = p.sel
    S.EditOrg(function(o)
      local me
      for i, n in ipairs(o.nodes) do if n.id == id then me = i end end
      if not me or not o.nodes[me].parent then return end
      local parent = o.nodes[me].parent
      for _, n in ipairs(o.nodes) do if n.parent == id then n.parent = parent end end
      table.remove(o.nodes, me)
      p.sel = parent
    end)
  end)
  ed.auto = W.Check(ed, L.ORG_AUTO, function(_, on) edit(function(n) n.auto = on and true or nil end) end)
  ed.auto:SetPoint("LEFT", ed.title, "RIGHT", 10, 0)
  -- duties (row 2): presets and own ones
  ed.dutyL = W.Text(ed, 10, "muted"); ed.dutyL:SetPoint("TOPLEFT", 8, -92); ed.dutyL:SetText(L.ORG_DUTIES)
  -- one button per function of the structure (built in the refresh)
  ed.duty = W.Pool(ed, function(parent)
    local b = W.Button(parent, "", false, 18)
    b:SetWidth(96)
    b:SetScript("OnClick", function(self)
      local dd = self.d
      edit(function(n)
        n.duties = n.duties or {}
        local has
        for k, x in ipairs(n.duties) do if x == dd then has = k end end
        if has then table.remove(n.duties, has) else n.duties[#n.duties + 1] = dd end
      end)
    end)
    return b
  end)
  -- a new function: added to the structure and given to this post
  ed.own = W.Edit(ed, 150, 18); ed.own:SetPoint("LEFT", ed.dutyL, "RIGHT", 8, 0)
  ed.ownL = W.Text(ed.own, 10, "muted"); ed.ownL:SetPoint("LEFT", 6, 0); ed.ownL:SetText(L.ORG_NEW_FUNC)
  ed.own:SetScript("OnTextChanged", function(self) ed.ownL:SetShown(self:GetText() == "") end)
  ed.own:SetScript("OnEnterPressed", function(self)
    local v = (self:GetText() or ""):match("^%s*(.-)%s*$")
    self:SetText(""); self:ClearFocus()
    if v == "" then return end
    local id
    for _, f in ipairs(S.Get().funcs) do if f.name and f.name:lower() == v:lower() then id = f.id end end
    if not id then
      id = S.NewId()
      S.Edit(function(st) st.funcs[#st.funcs + 1] = { id = id, name = v, col = "ff805c", ranks = {} } end)
    end
    edit(function(n) n.duties = n.duties or {}; for _, x in ipairs(n.duties) do if x == id then return end end; n.duties[#n.duties + 1] = id end)
  end)
  ed.ownTags = W.Text(ed, 10, "muted"); ed.ownTags:SetPoint("LEFT", ed.own, "RIGHT", 10, 0); ed.ownTags:SetText(L.ORG_FUNC_HINT)
  ed.ownDel = CreateFrame("Frame", nil, ed)
  -- classes (row 3)
  ed.cls = {}
  for i, c in ipairs(CLASSES) do
    local b = W.Button(ed, S.ClassName(c), false, 18)
    b:SetWidth(78)
    b:SetPoint("TOPLEFT", 8 + (i - 1) * 82, -66)
    b.c = c
    b:SetScript("OnClick", function(self) S.ToggleClass(p.sel, self.c) end)
    ed.cls[i] = b
  end
  ed.ro = W.Text(ed, 10, "muted"); ed.ro:SetPoint("TOPLEFT", 8, -8); ed.ro:SetText(L.ORG_HINT_RO)
end

local function refresh(p)
  local th = T.Current()
  local org = S.Org()
  p.members = S.ClassMembers()
  local root
  for _, n in ipairs(org.nodes) do if not n.parent then root = n end end
  if not root then return end
  if p.open[tostring(root.id)] == nil then
    p.open[tostring(root.id)] = true
    for _, n in ipairs(S.Children(root.id)) do if n.kind == "off" or n.kind == "member" then p.open[tostring(n.id)] = true end end
  end
  local top = { node = root }
  measure(p, top, 1)
  place(p, top, 0, 0)
  local total, acc = top.w, top.h + 10
  local viewW = p.scroll:GetWidth() or 700
  -- full size (zoom by the leadership's choice); wider charts scroll sideways
  local scale = p.zoom or 1
  -- The canvas stays at scale 1: only the boxes are zoomed (their text). All
  -- lines and box borders are drawn on the canvas in whole units, so WoW cannot
  -- round them away at any zoom.
  p.canvas:SetScale(1)
  local z = scale
  local off = math.max(10, ((viewW / z) - total) / 2)
  local ni, li = 0, 0
  local function R(v) return math.floor(v + 0.5) end
  -- a line in layout units (x, y, w, h); thin sides stay one unit wide
  local function lineAt(X, Y, Wd, Ht, col)
    li = li + 1
    local t = p.lines:Get(li)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", p.canvas, "TOPLEFT", X, -Y)
    t:SetSize(math.max(1, Wd), math.max(1, Ht))
    col = col or th.line
    t:SetColorTexture(col[1], col[2], col[3], 1)
    t:Show()
  end
  local function line(x, y, w, h, col)
    lineAt(R(x * z), R(y * z), w <= 1 and 1 or R(w * z), h <= 1 and 1 or R(h * z), col)
  end
  local function box(x, y, w, h, col)
    local X, Y, Wd, Ht = R(x * z), R(y * z), R(w * z), R(h * z)
    lineAt(X, Y, Wd, 1, col); lineAt(X, Y + Ht - 1, Wd, 1, col)
    lineAt(X, Y, 1, Ht, col); lineAt(X + Wd - 1, Y, 1, Ht, col)
  end
  local function draw(item)
    ni = ni + 1
    local b = p.nodes:Get(ni)
    local x, y = off + item.x, item.y
    local h = item.nh
    b:SetScale(z)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", p.canvas, "TOPLEFT", R(x * z) / z, -R(y * z) / z); b:SetSize(NW, h)
    b.k = key(item)
    local hasKids
    if item.cls then hasKids = #(p.members[item.cls] or {}) > 0 else hasKids = #children(p, item) > 0 end
    -- the box itself has no border (drawn on the canvas); the stripe is at least two units
    if not b.flat then
      b.flat = true
      b:SetBackdrop({ bgFile = W.BACKDROP.bgFile })
      b:SetBackdropColor(th.panel[1], th.panel[2], th.panel[3], 1)
    end
    b.stripe:SetHeight(math.max(2, 2 / z))
    local border = (not item.cls and p.sel == item.node.id) and th.title or th.line
    box(x, y, NW, h, border)
    local open, dir = p.open[b.k], dirOf(b.k)
    b.edges = function()
      local over = b.over and S.CanEdit() ~= nil
      -- the edge in use shows "-"; the other one appears on mouse-over
      b.pm:SetShown(hasKids and ((open and dir == "down") or not open or (b.over and not item.cls)))
      b.pm.t:SetText((open and dir == "down") and "-" or "+")
      b.pmR:SetShown(hasKids and not item.cls and ((open and dir == "right") or b.over))
      b.pmR.t:SetText((open and dir == "right") and "-" or "+")
    end
    b.edges()
    if item.cls then
      b.nodeId = nil
      b.duties:Hide()
      local hex = S.ClassHex(item.cls)
      b.stripe:SetColorTexture(hexRGB(hex))
      b.kind:SetText(L.ORG_CLASS)
      b.who:SetText("|cff" .. hex .. S.ClassName(item.cls) .. "|r")
      local m = p.members[item.cls] or {}
      b.sub:SetText(L.ORG_PERSONS:format(#m))
      if p.open[b.k] then
        local names = {}
        for _, k in ipairs(m) do names[#names + 1] = G.Display(k) end
        b.list:SetText(table.concat(names, "\n")); b.list:Show()
      else b.list:Hide() end
    else
      local n = item.node
      b.nodeId = n.id
      b.stripe:SetColorTexture(hexRGB(S.KindCol(n)))
      b.kind:SetText(S.KindName(n))
      b.who:SetText(n.who and G.Display(n.who) or "|cff9a8a7a?|r")
      if n.kind == "council" then
        b.kind:SetText(L.ORG_COUNCIL)
        b.who:SetText(S.KindName(n))
        b.sub:SetText(n.auto and ("|cff9a8a7a" .. L.ORG_COUNCIL_AUTO .. "|r") or "")
      elseif n.kind == "member" then
        local r = G.roster[n.who]
        b.sub:SetText(r and ("|cff9a8a7aWoW: " .. (G.rankNames[r.rankIndex] or "") .. "|r") or "")
      elseif n.kind == "cls" then
        local cs = {}
        for _, c in ipairs(n.cls or {}) do cs[#cs + 1] = "|cff" .. S.ClassHex(c) .. S.ClassName(c) .. "|r" end
        b.sub:SetText(#cs > 0 and table.concat(cs, ", ") or ("|cff9a8a7a" .. L.ORG_NO_CLASS .. "|r"))
      else
        local r = n.who and G.roster[n.who]
        b.sub:SetText(r and ("|cff9a8a7a" .. (G.rankNames[r.rankIndex] or "") .. "|r") or "")
      end
      b.list:Hide()
      local dl = {}
      for _, d in ipairs(n.duties or {}) do
        local t = S.DutyLabel(d)
        if not t then -- function deleted in the structure
        elseif d == "cls" and n.cls and #n.cls > 0 then
          local cs = {}
          for _, c in ipairs(n.cls) do cs[#cs + 1] = "|cff" .. S.ClassHex(c) .. S.ClassName(c):sub(1, 4) .. "|r" end
          t = t .. ": " .. table.concat(cs, " ")
        end
        if t then dl[#dl + 1] = "|cff" .. S.DutyCol(d) .. t .. "|r" end
      end
      b.duties:SetText(table.concat(dl, "\n")); b.duties:SetShown(#dl > 0)
    end
    b:Show()
    local kids = item.kids or {}
    if #kids > 0 and item.dir == "right" then
      -- from the right edge to a spine, a stub to each child
      local mid = y + math.min(h, NH) / 2
      local sx = x + NW + HGAP / 2
      line(x + NW, mid, HGAP / 2, 1)
      local top, bot = mid, mid
      for _, k in ipairs(kids) do
        local km = k.y + math.min(k.nh, NH) / 2
        line(sx, km, off + k.x - sx, 1)
        top, bot = math.min(top, km), math.max(bot, km)
        draw(k)
      end
      line(sx, top, 1, bot - top + 1)
    elseif #kids > 0 and item.vert then
      -- line down the left side, a stub to each child
      local lx = x + 10
      local lastMid = 0
      for _, k in ipairs(kids) do
        local mid = k.y + math.min(k.nh, NH) / 2
        line(lx, mid, off + k.x - lx, 1)
        lastMid = mid
        draw(k)
      end
      line(lx, y + h, 1, lastMid - (y + h) + 1)
    elseif #kids > 0 then
      local cx = x + NW / 2
      local yb = y + h
      local ym = yb + VGAP / 2 + 2
      line(cx, yb, 1, ym - yb)
      local first, last = off + kids[1].x + NW / 2, off + kids[#kids].x + NW / 2
      if #kids > 1 then line(first, ym, last - first + 1, 1) end
      for _, k in ipairs(kids) do
        local kx = off + k.x + NW / 2
        line(kx, ym, 1, k.y - ym)
        draw(k)
      end
    end
  end
  draw(top)
  p.nodes:HideFrom(ni + 1)
  for i = li + 1, #p.lines.items do p.lines.items[i]:Hide() end
  local cw = math.max(viewW, (total + 20) * z)
  p.canvas:SetWidth(cw)
  p.canvas:SetHeight((acc + 10) * z)
  p.maxH = math.max(0, cw - viewW)
  p.maxV = math.max(0, (acc + 10) * z - (p.scroll:GetHeight() or 300))
  p.scroll:SetHorizontalScroll(math.min(p.maxH, p.scroll:GetHorizontalScroll() or 0))
  p.scroll:SetVerticalScroll(math.min(p.maxV, p.scroll:GetVerticalScroll() or 0))
  p.zoomL:SetText(math.floor(scale * 100 + 0.5) .. "%")
  p.syncBar()

  -- classes without a class lead
  local miss = {}
  for c in pairs(p.members) do if not S.ClassLeader(c) then miss[#miss + 1] = S.ClassName(c) end end
  table.sort(miss)
  p.missing:SetText(#miss > 0 and L.ORG_MISSING:format(table.concat(miss, ", ")) or "")

  -- editor
  local can = S.CanEdit()
  local n = p.sel and S.Node(p.sel)
  local ed = p.ed
  local edits = can and n ~= nil
  for _, w in ipairs({ ed.kind, ed.title, ed.whoL, ed.who, ed.add, ed.del, ed.auto, ed.dutyL, ed.own, ed.ownTags, ed.ownDel }) do w:SetShown(edits) end
  local funcs = S.DutyFuncs()
  for i, f in ipairs(funcs) do
    local b = ed.duty:Get(i)
    b.d = f.id
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 8 + ((i - 1) % 8) * 100, -40 - math.floor((i - 1) / 8) * 20)
    b:SetShown(edits and n.kind ~= "council")
    if edits then
      local on = S.HasDuty(n, f.id)
      b.label:SetText(on and ("|cff" .. (f.col or "e6ba5c") .. f.name .. "|r") or f.name)
      b:SetAlpha(on and 1 or 0.6)
    end
  end
  ed.duty:HideFrom(#funcs + 1)
  -- rows below the functions: classes (class lead), then "new function"; the editor grows
  local dutyRows = (edits and n.kind ~= "council") and math.ceil(#funcs / 8) or 0
  local clsY = -40 - dutyRows * 20 - 4
  local showCls = edits and S.LeadsClasses(n)
  for i, b in ipairs(ed.cls) do b:ClearAllPoints(); b:SetPoint("TOPLEFT", 8 + (i - 1) * 82, clsY) end
  local ownY = clsY - (showCls and 24 or 0)
  ed.dutyL:ClearAllPoints(); ed.dutyL:SetPoint("TOPLEFT", 8, ownY - 4)
  local h = math.max(60, -ownY + 26)
  if ed.h ~= h then
    ed.h = h
    ed:SetHeight(h)
    p.scroll:SetPoint("BOTTOMRIGHT", 0, h + 22)
    p.missing:ClearAllPoints(); p.missing:SetPoint("BOTTOMLEFT", 0, h + 6); p.missing:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  end
  if edits then ed.own:SetShown(n.kind ~= "council"); ed.dutyL:SetShown(n.kind ~= "council"); ed.ownTags:SetShown(n.kind ~= "council") end
  if can then S.MigrateDuties() end
  ed.ro:SetShown(not edits)
  ed.ro:SetText(can and L.ORG_PICK or L.ORG_HINT_RO)
  if edits then
    local virt = n.virtual
    ed.kind:Refresh()
    ed.kind:SetShown(not virt and n.parent ~= nil)
    ed.title:SetShown(not virt and (n.kind == "own" or n.kind == "council"))
    if not ed.title:HasFocus() then ed.title:SetText(n.title or "") end
    ed.whoL:SetShown(not virt and n.kind ~= "council"); ed.who:SetShown(not virt and n.kind ~= "council")
    if not ed.who:HasFocus() then ed.who:SetText(n.who and G.Display(n.who) or "") end
    ed.del:SetShown(not virt and n.parent ~= nil)
    ed.auto:SetShown(n.kind == "council"); ed.auto:SetChecked(n.auto and true or false)
    if virt then ed.add:ClearAllPoints(); ed.add:SetPoint("TOPLEFT", 8, -8)
    else ed.add:ClearAllPoints(); ed.add:SetPoint("LEFT", ed.who, "RIGHT", 8, 0) end
  end
  -- templates
  p.tpl:SetShown(can); p.tplBtn:SetShown(can)
  if can then p.tpl:Refresh() end
  local on = {}
  for _, c in ipairs(n and n.cls or {}) do on[c] = true end
  for _, b in ipairs(ed.cls) do
    b:SetShown(edits and S.LeadsClasses(n))
    local lead = S.ClassLeader(b.c)
    b.label:SetText(on[b.c] and ("|cff" .. S.ClassHex(b.c) .. S.ClassName(b.c) .. "|r") or S.ClassName(b.c))
    b:SetAlpha(on[b.c] and 1 or (lead and 0.4 or 0.75))
  end
end

UI.AddTab("org", {
  label = function() return L.ORG_TAB end,
  icon = W.Icon("org"),
  category = "guild",
  order = 7,
  build = build, refresh = refresh,
})
