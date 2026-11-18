local ADDON, ns = ...
-- Themed widgets. Colours come from the faction theme (ns.Theme); the menu
-- keeps a dark background in both themes so its text stays readable.
local T = ns.Theme
local W = {}
ns.W = W

function W.C()
  local th = T.Current()
  th.menuText = { 0.93, 0.89, 0.83 }
  return th
end

local BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
}
W.BACKDROP = BACKDROP

local function paint(f, bg, border)
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  local b = border or W.C().line
  f:SetBackdropBorderColor(b[1], b[2], b[3], b[4] or 1)
end
W.Paint = paint

-- kind: "bg" (window), "panel" (card), "panel2" (inner card)
function W.Box(parent, w, h, kind)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(w or 100, h or 24)
  paint(f, W.C()[kind or "panel"])
  return f
end

function W.Text(parent, size, color, flags)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11, flags or "")
  local c = W.C()[color or "text"] or color
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetJustifyH("LEFT")
  return fs
end

function W.Color(fs, color)
  local c = type(color) == "table" and color or W.C()[color or "text"]
  fs:SetTextColor(c[1], c[2], c[3])
end

-- Button; primary = accent colour (faction red / blue) with light text
function W.Button(parent, text, primary, h)
  local th = W.C()
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetHeight(h or 22)
  local bg = primary and th.accent or th.panel2
  local border = primary and th.border or th.line
  paint(b, bg, border)
  local fs = b:CreateFontString(nil, "OVERLAY")
  fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
  local tc = primary and { 1, 0.95, 0.85 } or th.text
  fs:SetTextColor(tc[1], tc[2], tc[3])
  fs:SetPoint("CENTER")
  fs:SetText(text or "")
  b.label = fs
  b:SetWidth(math.max(40, fs:GetStringWidth() + 22))
  b:SetScript("OnEnter", function(self)
    if self:IsEnabled() then self:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1) end
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(self.tip[1], 1, 0.82, 0)
      if self.tip[2] then GameTooltip:AddLine(self.tip[2], 1, 1, 1, true) end
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    GameTooltip:Hide()
  end)
  b:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
  b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
  return b
end

-- Choice chip: a small button that can be selected (one of several options)
-- a capsule button (rounded ends, like the mockup): fill + outline, 3-sliced
local function capsule(b)
  local parts = {}
  for _, kind in ipairs({ "pill", "pill_line" }) do
    local layer = kind == "pill" and "BACKGROUND" or "BORDER"
    local L = b:CreateTexture(nil, layer); L:SetTexture(W.ICONS .. kind); L:SetTexCoord(0, 0.25, 0, 1)
    local M = b:CreateTexture(nil, layer); M:SetTexture(W.ICONS .. kind); M:SetTexCoord(0.25, 0.75, 0, 1)
    local R = b:CreateTexture(nil, layer); R:SetTexture(W.ICONS .. kind); R:SetTexCoord(0.75, 1, 0, 1)
    L:SetPoint("TOPLEFT"); L:SetPoint("BOTTOMLEFT")
    R:SetPoint("TOPRIGHT"); R:SetPoint("BOTTOMRIGHT")
    M:SetPoint("TOPLEFT", L, "TOPRIGHT"); M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT")
    parts[kind] = { L, M, R }
  end
  local function size()
    local h = b:GetHeight()
    for _, set in pairs(parts) do set[1]:SetWidth(h / 2); set[3]:SetWidth(h / 2) end
  end
  b:HookScript("OnSizeChanged", size)
  size()
  function b:SetCapsuleColors(fill, line)
    for _, t in ipairs(parts.pill) do t:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1) end
    for _, t in ipairs(parts.pill_line) do t:SetVertexColor(line[1], line[2], line[3], line[4] or 1) end
  end
end

function W.Chip(parent, text, w, h)
  local th = W.C()
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 60, h or 22)
  capsule(b)
  local fs = b:CreateFontString(nil, "OVERLAY")
  fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
  fs:SetPoint("LEFT", 8, 0); fs:SetPoint("RIGHT", -8, 0)
  fs:SetWordWrap(false)
  fs:SetText(text or "")
  b.label = fs
  function b:SetSelected(on)
    self.selected = on and true or false
    local bg = self.selected and th.accent or th.panel2
    local bd = self.selected and th.title or th.line
    self:SetCapsuleColors(bg, bd)
    local tc = self.selected and { 1, 0.95, 0.85 } or th.text
    fs:SetTextColor(tc[1], tc[2], tc[3])
  end
  b:SetScript("OnEnter", function(self)
    self:SetCapsuleColors(self.selected and th.accent or th.panel2, th.title)
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(self.tip[1], 1, 0.82, 0)
      if self.tip[2] then GameTooltip:AddLine(self.tip[2], 1, 1, 1, true) end
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self) self:SetSelected(self.selected); GameTooltip:Hide() end)
  b:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
  b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
  b:SetSelected(false)
  return b
end

function W.SetLabel(b, text)
  b.label:SetText(text or "")
  b:SetWidth(math.max(40, b.label:GetStringWidth() + 22))
end

---------------------------------------------------------------------------
-- Icons (Media/Icons, own drawings): white ones are tinted, the coloured
-- ones (check, cross, unknown, dash, role_*) are used as they are.
---------------------------------------------------------------------------
W.ICONS = "Interface\\AddOns\\GuildEventManager\\Media\\Icons\\"
function W.Icon(name) return W.ICONS .. name end
function W.IsOwnIcon(path) return type(path) == "string" and path:sub(1, #W.ICONS) == W.ICONS end
-- an icon inside a text: W.InlineIcon("check", 12)
function W.InlineIcon(name, size)
  size = size or 12
  return "|T" .. W.ICONS .. name .. ":" .. size .. ":" .. size .. "|t"
end
-- yes / no / unknown as an inline icon
function W.Mark(v, size)
  if v == nil then return W.InlineIcon("dash", size) end
  return W.InlineIcon(v and "check" or "cross", size)
end

-- a texture for an icon, tinted with a theme colour key (or { r, g, b })
function W.IconTex(parent, name, size, color, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetSize(size or 16, size or 16)
  t:SetTexture(W.ICONS .. name)
  local c = type(color) == "table" and color or W.C()[color or "muted"]
  if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
  return t
end

-- a flat button with an icon; :SetCount(n) shows a red dot with a number
function W.IconButton(parent, name, size, tip)
  local th = W.C()
  size = size or 28
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(size, size)
  paint(b, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
  b.icon = W.IconTex(b, name, math.floor(size * 0.68), "muted")
  b.icon:SetPoint("CENTER")
  b:SetScript("OnEnter", function(self)
    self:SetBackdropColor(th.panel2[1], th.panel2[2], th.panel2[3], 0.9)
    self.icon:SetVertexColor(th.title[1], th.title[2], th.title[3])
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(type(self.tip) == "function" and self.tip() or self.tip)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0, 0, 0, 0)
    self.icon:SetVertexColor(th.muted[1], th.muted[2], th.muted[3])
    GameTooltip:Hide()
  end)
  b.tip = tip
  b.dot = b:CreateTexture(nil, "OVERLAY")
  b.dot:SetSize(15, 15); b.dot:SetPoint("TOPRIGHT", 1, 1)
  b.dot:SetTexture(W.ICONS .. "dot"); b.dot:SetVertexColor(0.80, 0.22, 0.16)
  b.count = b:CreateFontString(nil, "OVERLAY")
  b.count:SetFont("Fonts\\ARIALN.TTF", 9, "")
  b.count:SetPoint("CENTER", b.dot, "CENTER", 0, 0)
  b.count:SetTextColor(1, 1, 1)
  function b:SetCount(n)
    n = tonumber(n) or 0
    self.dot:SetShown(n > 0); self.count:SetShown(n > 0)
    self.count:SetText(n > 9 and "9+" or tostring(n))
  end
  b:SetCount(0)
  return b
end

function W.Close(parent, onClick)
  local b = W.IconButton(parent, "close", 22)
  b:SetPoint("TOPRIGHT", -6, -6)
  b:SetScript("OnClick", onClick or function() parent:Hide() end)
  return b
end

function W.Bar(parent, h)
  local th = W.C()
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetHeight(h or 6)
  bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
  bar:SetStatusBarColor(th.title[1], th.title[2], th.title[3])
  bar:SetMinMaxValues(0, 1)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  return bar
end

function W.Edit(parent, w, h, multi)
  local th = W.C()
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  paint(e, { 0, 0, 0, 0.25 }, th.line)
  e:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  e:SetTextColor(th.text[1], th.text[2], th.text[3])
  e:SetTextInsets(6, 6, multi and 4 or 0, multi and 4 or 0)
  e:SetSize(w or 120, h or 22)
  e:SetAutoFocus(false)
  if multi then e:SetMultiLine(true) end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  if not multi then e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end) end
  return e
end

function W.Check(parent, label, onClick)
  local th = W.C()
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(14, 14)
  paint(b, { 0, 0, 0, 0.25 }, th.line)
  b.mark = b:CreateTexture(nil, "OVERLAY")
  b.mark:SetPoint("TOPLEFT", 3, -3); b.mark:SetPoint("BOTTOMRIGHT", -3, 3)
  b.mark:SetColorTexture(th.title[1], th.title[2], th.title[3], 1)
  b.text = W.Text(b, 11)
  b.text:SetPoint("LEFT", b, "RIGHT", 6, 0)
  b.text:SetText(label or "")
  function b:SetChecked(on) self.checked = on and true or false; self.mark:SetShown(self.checked) end
  function b:GetChecked() return self.checked end
  b:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if onClick then onClick(self, self.checked) end
  end)
  b:SetChecked(false)
  return b
end

-- Scroll area: returns the scroll frame; put rows into frame.content
function W.Scroll(parent)
  local s = CreateFrame("ScrollFrame", nil, parent)
  local c = CreateFrame("Frame", nil, s)
  c:SetSize(10, 10)
  s:SetScrollChild(c)
  s.content = c
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, c:GetHeight() - self:GetHeight())
    local v = math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40))
    self:SetVerticalScroll(v)
  end)
  s:SetScript("OnSizeChanged", function(self, w) c:SetWidth(w) end)
  function s:SetContentHeight(h)
    c:SetHeight(math.max(1, h))
    local max = math.max(0, h - self:GetHeight())
    if self:GetVerticalScroll() > max then self:SetVerticalScroll(max) end
  end
  return s
end

-- Pool of rows inside a parent: W.Pool(parent, create) -> pool:Get(i), pool:HideFrom(n)
function W.Pool(parent, create)
  local pool = { items = {} }
  function pool:Get(i)
    local r = self.items[i]
    if not r then r = create(parent, i); self.items[i] = r end
    r:Show()
    return r
  end
  function pool:HideFrom(n) for i = n, #self.items do self.items[i]:Hide() end end
  return pool
end

-- Dropdown: a button that opens the menu; options = { { value, text } }
function W.Dropdown(parent, width, getOptions, getValue, onSelect)
  local b = W.Button(parent, "", false, 22)
  b:SetWidth(width or 140)
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", 8, 0)
  b.label:SetPoint("RIGHT", -18, 0)
  b.label:SetJustifyH("LEFT")
  b.label:SetWordWrap(false)
  local arrow = W.Text(b, 9, "muted")
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetText("v")
  function b:Refresh()
    local v = getValue()
    for _, o in ipairs(getOptions()) do if o[1] == v then self.label:SetText(o[2]); return end end
    self.label:SetText(v and tostring(v) or "–")
  end
  b:SetScript("OnClick", function(self)
    W.OpenMenu(self, function(_, root)
      local opts = getOptions()
      for _, o in ipairs(opts) do
        root:CreateRadio(o[2], function() return getValue() == o[1] end, function() onSelect(o[1]); self:Refresh() end)
      end
    end)
  end)
  b:Refresh()
  return b
end

---------------------------------------------------------------------------
-- Own dialog: W.Dialog{ text, edit = true, editText, accept, cancel, onAccept = function(text) end, noCancel, alt, onAlt }
---------------------------------------------------------------------------
local dialog
local function buildDialog()
  local d = W.Box(UIParent, 440, 140, "bg")
  d:SetBackdropBorderColor(W.C().border[1], W.C().border[2], W.C().border[3], 1)
  d:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  d:SetFrameStrata("DIALOG")
  d:SetToplevel(true)
  d:EnableMouse(true)
  d:SetMovable(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  d:Hide()
  _G.GuildEventManagerDialog = d
  tinsert(UISpecialFrames, "GuildEventManagerDialog")
  d.text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d.text:SetPoint("TOPLEFT", 16, -16)
  d.text:SetPoint("TOPRIGHT", -16, -16)
  d.text:SetJustifyH("LEFT")
  d.text:SetSpacing(2)
  local e = CreateFrame("EditBox", nil, d, "BackdropTemplate")
  paint(e, { 0, 0, 0, 0.5 }, W.C().line)
  e:SetFontObject(GameFontHighlightSmall)
  e:SetTextInsets(6, 6, 0, 0)
  e:SetHeight(22)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", function() d:Hide() end)
  e:SetScript("OnEnterPressed", function() d.ok:Click() end)
  d.edit = e
  d.ok = W.Button(d, OKAY or "OK", true, 24)
  d.cancel = W.Button(d, CANCEL or "Cancel", false, 24)
  d.cancel:SetScript("OnClick", function() d:Hide() end)
  d.alt = W.Button(d, "", true, 24)
  d.alt:SetScript("OnClick", function()
    local fn = d.onAlt
    d:Hide()
    if fn then fn() end
  end)
  d.ok:SetScript("OnClick", function()
    local fn, txt = d.onAccept, d.edit:IsShown() and d.edit:GetText() or nil
    d:Hide()
    if fn then fn(txt) end
  end)
  return d
end

function W.Dialog(opts)
  dialog = dialog or buildDialog()
  local d = dialog
  d.onAccept = opts.onAccept
  d.onAlt = opts.onAlt
  d.text:SetText(opts.text or "")
  W.SetLabel(d.ok, opts.accept or OKAY or "OK")
  W.SetLabel(d.cancel, opts.cancel or CANCEL or "Cancel")
  d.cancel:SetShown(not opts.noCancel)
  local h = 16 + d.text:GetStringHeight() + 14
  if opts.edit then
    d.edit:ClearAllPoints()
    d.edit:SetPoint("TOPLEFT", d.text, "BOTTOMLEFT", 0, -12)
    d.edit:SetPoint("RIGHT", -16, 0)
    d.edit:SetText(opts.editText or "")
    d.edit:Show()
    h = h + 34
  else
    d.edit:Hide()
  end
  d.ok:ClearAllPoints(); d.cancel:ClearAllPoints()
  d.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
  if opts.noCancel then d.ok:SetPoint("BOTTOMRIGHT", -16, 14) else d.ok:SetPoint("RIGHT", d.cancel, "LEFT", -8, 0) end
  -- optional second choice (alt, onAlt) left of the accept button
  d.alt:ClearAllPoints()
  if opts.alt then
    W.SetLabel(d.alt, opts.alt)
    d.alt:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
    d.alt:Show()
  else
    d.alt:Hide()
  end
  d:SetHeight(h + 24 + 28)
  d:Show()
  if opts.edit then d.edit:SetFocus(); d.edit:HighlightText() end
end

---------------------------------------------------------------------------
-- Own context menu instead of Blizzard's MenuUtil. Same builder calls as MenuUtil:
-- W.OpenMenu(owner, function(owner, root) root:CreateTitle(..) root:CreateRadio(..) root:CreateButton(..) end)
-- A button with entries of its own opens a submenu on the right.
---------------------------------------------------------------------------
local Node = {}
Node.__index = Node
local function newNode(kind, text, fn, isSel) return setmetatable({ kind = kind, text = text, fn = fn, isSel = isSel, items = {} }, Node) end
function Node:CreateTitle(t) table.insert(self.items, newNode("title", t)) end
function Node:CreateDivider() table.insert(self.items, newNode("div")) end
function Node:CreateRadio(t, isSel, fn) local n = newNode("radio", t, fn, isSel); table.insert(self.items, n); return n end
function Node:CreateButton(t, fn) local n = newNode("button", t, fn); table.insert(self.items, n); return n end

local levels, catcher = {}, nil
local ROW_H = 20
local function hideFrom(depth)
  for d = depth, #levels do levels[d]:Hide() end
  if depth <= 1 and catcher then catcher:Hide() end
end

local showLevel
local function getLevel(depth)
  local f = levels[depth]
  if f then return f end
  f = W.Box(UIParent, 160, 40)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel(10 + depth * 5)
  f:SetBackdropColor(0.08, 0.06, 0.05, 0.98)
  f:EnableMouse(true)
  f.rows = {}
  f:Hide()
  levels[depth] = f
  return f
end

local function getRow(f, i, depth)
  local r = f.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, f)
  r:SetHeight(ROW_H)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetColorTexture(W.C().border[1], W.C().border[2], W.C().border[3], 0.25)
  r.hl:SetAllPoints()
  r.mark = r:CreateTexture(nil, "OVERLAY")
  r.mark:SetSize(8, 8)
  r.mark:SetPoint("LEFT", 8, 0)
  r.mark:SetColorTexture(W.C().title[1], W.C().title[2], W.C().title[3], 1)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", 22, 0)
  r.text:SetJustifyH("LEFT")
  r.arrow = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.arrow:SetPoint("RIGHT", -8, 0)
  r.arrow:SetText(">")
  r.line = r:CreateTexture(nil, "ARTWORK")
  r.line:SetColorTexture(W.C().border[1], W.C().border[2], W.C().border[3], 0.5)
  r.line:SetHeight(1)
  r.line:SetPoint("LEFT", 6, 0)
  r.line:SetPoint("RIGHT", -6, 0)
  r:SetScript("OnEnter", function(self)
    local n = self.node
    if n and #n.items > 0 then showLevel(n, depth + 1, self) else hideFrom(depth + 1) end
  end)
  r:SetScript("OnClick", function(self)
    local n = self.node
    if not n or n.kind == "title" or n.kind == "div" then return end
    if #n.items > 0 then showLevel(n, depth + 1, self) return end
    hideFrom(1)
    if n.fn then n.fn() end
  end)
  f.rows[i] = r
  return r
end

-- long menus (raids planned months ahead) show MENU_MAX rows and scroll with the mouse wheel
local MENU_MAX = 18
showLevel = function(node, depth, anchor)
  hideFrom(depth)
  local f = getLevel(depth)
  local width, y = node.width or 120, -6
  local all = node.items
  local maxOff = math.max(0, #all - MENU_MAX)
  node.off = math.min(maxOff, math.max(0, node.off or 0))
  local items = all
  if #all > MENU_MAX then
    items = {}
    for i = node.off + 1, node.off + MENU_MAX do items[#items + 1] = all[i] end
  end
  f:EnableMouseWheel(#all > MENU_MAX)
  f:SetScript("OnMouseWheel", function(_, delta)
    node.off = node.off - delta * 3
    showLevel(node, depth, anchor)
  end)
  f.more = f.more or W.Text(f, 9, "muted")
  f.more:SetShown(#all > MENU_MAX)
  if #all > MENU_MAX then
    f.more:ClearAllPoints(); f.more:SetPoint("BOTTOMRIGHT", -6, 3)
    f.more:SetText((node.off + 1) .. "–" .. (node.off + #items) .. " / " .. #all)
  end
  for i, n in ipairs(items) do
    local r = getRow(f, i, depth)
    r.node = n
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 1, y)
    r:SetPoint("RIGHT", -1, 0)
    local isDiv = n.kind == "div"
    r:SetHeight(isDiv and 8 or ROW_H)
    r.line:SetShown(isDiv)
    r.text:SetShown(not isDiv)
    r.text:SetText(n.text or "")
    r.text:SetTextColor(n.kind == "title" and W.C().title[1] or W.C().menuText[1], n.kind == "title" and W.C().title[2] or W.C().menuText[2], n.kind == "title" and W.C().title[3] or W.C().menuText[3])
    r.mark:SetShown(n.kind == "radio" and n.isSel and n.isSel() or false)
    r.arrow:SetShown(#n.items > 0)
    r.hl:SetShown(n.kind ~= "title" and not isDiv)
    r:EnableMouse(n.kind ~= "title" and not isDiv)
    r:Show()
    width = math.max(width, (r.text:GetStringWidth() or 0) + 22 + 28)
    y = y - (isDiv and 8 or ROW_H)
  end
  for i = #items + 1, #f.rows do f.rows[i]:Hide() end
  node.width = width
  f:SetSize(width, -y + 6 + (#all > MENU_MAX and 12 or 0))
  f:ClearAllPoints()
  if depth == 1 then f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  else f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 6) end
  f:SetClampedToScreen(true)
  f:Show()
end

function W.OpenMenu(owner, build)
  if not catcher then
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() hideFrom(1) end)
  end
  if levels[1] and levels[1]:IsShown() and levels[1].owner == owner then hideFrom(1) return end
  local root = newNode("root")
  build(owner, root)
  catcher:Show()
  showLevel(root, 1, owner)
  levels[1].owner = owner
end
