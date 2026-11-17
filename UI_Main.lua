local ADDON, ns = ...
-- Main window: header (crest, guild, bell, settings), sidebar with the guild's
-- own areas and one entry per module, sub-tabs inside an entry, and the family
-- bar at the bottom like in the other Manager addons.
--
-- Entries (sidebar) hold one or more views (tabs). Modules add an entry with
-- UI.AddModule; UI.AddTab stays as the short form (one entry with one view, or
-- one more view in an existing entry with def.parent).
local U, G, T, W = ns.U, ns.Guild, ns.Theme, ns.W
local UI = {}
ns.UI = UI

UI.views = {}      -- view id -> { label = fn, build = fn(parent), refresh = fn(panel) }
UI.entries = {}    -- entry id -> { id, label = fn, icon, group, order, tabs = { view ids }, badge = fn, hidden }
UI.entryOf = {}    -- view id -> entry id
local win

local W_WIDTH, W_HEIGHT, SIDE = 1080, 620, 184

-- the guild's own areas, in this order
local CORE = { "home", "events", "ledger", "ach", "banner" }
local CORE_ICONS = {
  home = "home", events = "events", ledger = "ledger", ach = "ach", banner = "banner",
}
for k, v in pairs(CORE_ICONS) do CORE_ICONS[k] = ns.W.Icon(v) end
-- sidebar groups in this order; modules pick one with def.category
UI.GROUPS = { "guild", "module", "holiday" }

local function addEntry(id, def)
  local e = UI.entries[id] or { id = id, tabs = {} }
  e.label = def.label or e.label
  e.icon = def.icon or e.icon
  e.group = def.category or def.group or e.group or "module"
  e.order = def.order or e.order or 100
  e.badge = def.badge or e.badge
  e.hidden = def.hidden or e.hidden
  UI.entries[id] = e
  if win then win.navDirty = true end
  return e
end

local function addView(entry, vid, def, pos)
  UI.views[vid] = def
  UI.entryOf[vid] = entry.id
  for _, v in ipairs(entry.tabs) do if v == vid then return end end
  if pos then table.insert(entry.tabs, math.min(pos, #entry.tabs + 1), vid) else entry.tabs[#entry.tabs + 1] = vid end
  if win then win.navDirty = true end
end

-- Core views: each its own entry (settings is reached by the gear in the header)
function UI.RegisterView(id, def)
  for i, c in ipairs(CORE) do
    if c == id then
      local e = addEntry(id, { label = def.label, icon = CORE_ICONS[id], group = "guild", order = i })
      addView(e, id, def, 1)
      return
    end
  end
  if id == "settings" then
    local e = addEntry("settings", { label = def.label, group = "guild", hidden = true, order = 99 })
    addView(e, id, def, 1)
    return
  end
  UI.views[id] = def
end

-- A sidebar entry for a module: def = { label = fn, icon, category = "module"|"holiday",
-- order, badge = fn() -> text, tabs = { { id, label = fn, build, refresh }, ... } }
function UI.AddModule(id, def)
  local e = addEntry(id, def)
  for _, t in ipairs(def.tabs or {}) do addView(e, t.id, t) end
  return e
end

-- Short form: def.parent adds a view to an existing entry, otherwise the view
-- gets an entry of its own (API 1 behaviour)
function UI.AddTab(id, def)
  if def.parent then
    local e = UI.entries[def.parent] or addEntry(def.parent, { label = def.parentLabel or def.label })
    addView(e, id, def, def.pos)
  else
    local e = addEntry(id, { label = def.label, icon = def.icon, category = def.category, order = def.order })
    addView(e, id, def, 1)
  end
end

-- One more page in the settings (rules of a module and the like)
function UI.AddSettingsPage(id, def)
  local e = addEntry("settings", { group = "guild", hidden = true, order = 99 })
  addView(e, id, def)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function navButton(parent)
  local th = T.Current()
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetHeight(28)
  W.Paint(b, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(17, 17); b.icon:SetPoint("LEFT", 9, 0)
  b.text = W.Text(b, 12, "text")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
  b.badgeBg = CreateFrame("Frame", nil, b, "BackdropTemplate")
  b.badgeBg:SetHeight(16)
  b.badgeBg:SetPoint("RIGHT", -6, 0)
  W.Paint(b.badgeBg, { th.title[1] * 0.3, th.title[2] * 0.3, th.title[3] * 0.3, 1 }, { th.title[1] * 0.55, th.title[2] * 0.55, th.title[3] * 0.55, 1 })
  b.badge = W.Text(b.badgeBg, 9, "title")
  b.badge:SetPoint("CENTER", 0, 0)
  b.text:SetPoint("RIGHT", b.badgeBg, "LEFT", -4, 0)
  b.text:SetWordWrap(false)
  b:SetScript("OnEnter", function(self) if not self.active then self:SetBackdropColor(th.panel2[1], th.panel2[2], th.panel2[3], 0.8) end end)
  b:SetScript("OnLeave", function(self) if not self.active then self:SetBackdropColor(0, 0, 0, 0) end end)
  b:SetScript("OnClick", function(self) UI.Show(self.entry) end)
  return b
end

local function groupLabel(parent)
  local fs = W.Text(parent, 10, "muted")
  return fs
end

local function buildNav()
  local side = win.side
  win.navDirty = false
  win.navBtns = win.navBtns or {}
  win.navHeads = win.navHeads or {}
  for _, b in pairs(win.navBtns) do b:Hide() end
  for _, h in pairs(win.navHeads) do h:Hide() end
  local y, nb, nh = -10, 0, 0
  for _, grp in ipairs(UI.GROUPS) do
    local list = {}
    for _, e in pairs(UI.entries) do
      if e.group == grp and not e.hidden and #e.tabs > 0 then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
    if #list > 0 then
      nh = nh + 1
      local h = win.navHeads[nh] or groupLabel(side)
      win.navHeads[nh] = h
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", 14, y - 4)
      h:SetText(ns.L["NAV_" .. grp:upper()] or grp)
      h:Show()
      y = y - 22
      for _, e in ipairs(list) do
        nb = nb + 1
        local b = win.navBtns[nb] or navButton(side)
        win.navBtns[nb] = b
        b.entry = e.id
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", 6, y); b:SetPoint("RIGHT", side, "RIGHT", -6, 0)
        b.icon:SetTexture(e.icon or W.Icon("chevron"))
        b.ownIcon = W.IsOwnIcon(e.icon) or not e.icon
        if b.ownIcon then b.icon:SetTexCoord(0, 1, 0, 1) else b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); b.icon:SetVertexColor(1, 1, 1) end
        b:Show()
        y = y - 30
      end
      y = y - 8
    end
  end
end

local function buildWindow()
  local th = T.Current()
  local f = W.Box(UIParent, W_WIDTH, W_HEIGHT, "bg")
  f:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.window = { p, rp, x, y }
  end)
  f:Hide()
  _G.GuildEventManagerFrame = f
  tinsert(UISpecialFrames, "GuildEventManagerFrame")
  if ns.db.window then
    local w = ns.db.window
    f:ClearAllPoints()
    f:SetPoint(w[1] or "CENTER", UIParent, w[2] or "CENTER", w[3] or 0, w[4] or 0)
  end

  -- header: crest (opens the banner), guild, bell, settings
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(56)
  local hbg = head:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints()
  hbg:SetColorTexture(th.banner[1], th.banner[2], th.banner[3], 0.35)
  local crestBtn = CreateFrame("Button", nil, head)
  crestBtn:SetSize(44, 44); crestBtn:SetPoint("LEFT", 12, -2)
  local crest = crestBtn:CreateTexture(nil, "ARTWORK")
  crest:SetAllPoints()
  crest:SetTexture(W.Icon("crest_" .. th.key))
  -- the guild's own emblem on a shield in the tabard colour (when the guild has a tabard)
  crestBtn.fill = crestBtn:CreateTexture(nil, "ARTWORK", nil, 1); crestBtn.fill:SetAllPoints(); crestBtn.fill:SetTexture(W.Icon("shield_fill"))
  crestBtn.emblem = crestBtn:CreateTexture(nil, "ARTWORK", nil, 2); crestBtn.emblem:SetSize(28, 28); crestBtn.emblem:SetPoint("CENTER", 0, 1)
  crestBtn.rim = crestBtn:CreateTexture(nil, "ARTWORK", nil, 3); crestBtn.rim:SetAllPoints(); crestBtn.rim:SetTexture(W.Icon("shield_rim"))
  crestBtn.hidden = CreateFrame("Frame", nil, crestBtn); crestBtn.hidden:Hide()
  crestBtn.dBg = crestBtn.hidden:CreateTexture(); crestBtn.dBo = crestBtn.hidden:CreateTexture()
  crestBtn.crest = crest
  function crestBtn:Update()
    local t = ns.Tabard and ns.Tabard.Read()
    local ok = false
    if t and t.bg and SetLargeGuildTabardTextures then
      ok = pcall(SetLargeGuildTabardTextures, "player", self.emblem, self.dBg, self.dBo)
      local c = t.bg
      -- a little lighter than the cloth so a dark tabard still shows on the dark header
      self.fill:SetVertexColor(math.min(1, c[1] * 1.3 + 0.08), math.min(1, c[2] * 1.3 + 0.08), math.min(1, c[3] * 1.3 + 0.08))
    end
    self.fill:SetShown(ok); self.emblem:SetShown(ok); self.rim:SetShown(ok)
    self.crest:SetShown(not ok)
  end
  f.crestBtn = crestBtn
  crestBtn:SetScript("OnClick", function() UI.Show("banner") end)
  crestBtn.tip = { ns.L.TAB_BANNER }
  f.title = W.Text(head, 19, "title")
  f.title:SetFont("Fonts\\MORPHEUS.TTF", 21, "")
  f.title:SetPoint("TOPLEFT", crestBtn, "TOPRIGHT", 10, -2)
  f.title:SetText("GuildEventManager")
  f.sub = W.Text(head, 11, { 0.85, 0.80, 0.72 })
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  local line = head:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(th.border[1], th.border[2], th.border[3], 1)
  line:SetHeight(1); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
  local close = W.Close(f)
  close:ClearAllPoints(); close:SetPoint("RIGHT", head, "RIGHT", -12, 0)
  f.gear = W.IconButton(head, "settings", 30, ns.L.TAB_SETTINGS)
  f.gear:SetPoint("RIGHT", close, "LEFT", -8, 0)
  f.gear:SetScript("OnClick", function() UI.Show("settings") end)
  f.bell = W.IconButton(head, "bell", 30, ns.L.NOTICES)
  f.bell:SetPoint("RIGHT", f.gear, "LEFT", -4, 0)
  f.bell:SetScript("OnClick", function() UI.ToggleNotices() end)
  f.help = W.IconButton(head, "help", 30, ns.L.HELP)
  f.help:SetPoint("RIGHT", f.bell, "LEFT", -4, 0)
  f.help:SetScript("OnClick", function() UI.ToggleHelp() end)

  -- sidebar
  f.side = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.side:SetPoint("TOPLEFT", 1, -57); f.side:SetPoint("BOTTOMLEFT", 1, 29)
  f.side:SetWidth(SIDE)
  W.Paint(f.side, { th.bg[1] * 0.85, th.bg[2] * 0.85, th.bg[3] * 0.85, 1 }, th.line)
  f.navDirty = true

  -- content with optional sub-tabs
  f.body = W.Box(f, 10, 10, "panel")
  f.body:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
  f.body:SetPoint("TOPLEFT", SIDE + 10, -66)
  f.body:SetPoint("BOTTOMRIGHT", -12, 36)
  f.panels = {}
  f.subtabs = {}

  -- not activated / no guild
  f.notice = W.Text(f.body, 13, "text")
  f.notice:SetPoint("TOPLEFT", 24, -24); f.notice:SetPoint("RIGHT", -24, 0)
  f.notice:SetSpacing(4)

  -- notices (bell)
  f.noticeBox = W.Box(f, 340, 40, "panel2")
  f.noticeBox:SetPoint("TOPRIGHT", f.bell, "BOTTOMRIGHT", 0, -6)
  f.noticeBox:SetFrameLevel(f:GetFrameLevel() + 30)
  f.noticeBox:EnableMouse(true)
  f.noticeBox:Hide()
  f.noticeRows = W.Pool(f.noticeBox, function(parent)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetHeight(36)
    W.Paint(r, th.panel, th.line)
    r.group = W.Text(r, 9, "title"); r.group:SetPoint("TOPLEFT", 8, -5)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("TOPLEFT", r.group, "BOTTOMLEFT", 0, -3); r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
      f.noticeBox:Hide()
      if self.n then ns.Notices.Open(self.n) end
    end)
    return r
  end)
  f.noticeEmpty = W.Text(f.noticeBox, 10, "muted")
  f.noticeEmpty:SetPoint("TOPLEFT", 10, -12)
  f.noticeEmpty:SetText(ns.L.NOTICES_NONE)

  -- footer: family bar in the family look (dark blue)
  local foot = CreateFrame("Frame", nil, f, "BackdropTemplate")
  foot:SetPoint("BOTTOMLEFT", 1, 1); foot:SetPoint("BOTTOMRIGHT", -1, 1); foot:SetHeight(28)
  W.Paint(foot, { 0.059, 0.102, 0.157, 1 }, { 0.184, 0.365, 0.6, 1 })
  f.family = ns.Family.Bar(foot, ns.L.FAMILY)
  f.family:SetPoint("LEFT", 12, 0)
  local ver = foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ver:SetPoint("RIGHT", -12, 0)
  ver:SetText("v" .. (ns.VERSION or "?") .. " · /gem")
  return f
end

function UI.Frame() return win end

-- Notices list under the bell
function UI.ToggleNotices()
  if not win then return end
  local box = win.noticeBox
  if box:IsShown() then box:Hide(); return end
  if win.helpBox then win.helpBox:Hide() end
  local list = ns.Notices and ns.Notices.List() or {}
  local th = T.Current()
  for i, n in ipairs(list) do
    if i > 8 then break end
    local r = win.noticeRows:Get(i)
    r.n = n
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 40); r:SetPoint("RIGHT", box, "RIGHT", -6, 0)
    r.group:SetText((n.group or "") .. "  " .. U.Color(T.Hex(th.muted), date("%d.%m. %H:%M", n.at or U.Now())))
    r.text:SetText(n.text or "")
  end
  local shown = math.min(#list, 8)
  win.noticeRows:HideFrom(shown + 1)
  win.noticeEmpty:SetShown(shown == 0)
  box:SetHeight(math.max(40, shown * 40 + 12))
  box:Show()
  if ns.Notices then ns.Notices.MarkRead() end
  UI.Refresh()
end

-- id: a view id or an entry id (opens the entry's last view)
function UI.Show(id)
  win = win or buildWindow()
  if win.navDirty then buildNav() end
  local entry = id and UI.entries[id]
  if entry and UI.views[id] == nil then id = entry.last or entry.tabs[1] end
  id = id or win.current or "home"
  if not UI.views[id] then id = "home" end
  win.current = id
  local eid = UI.entryOf[id]
  if win.guide and eid ~= "settings" then win.guide:Hide() end
  if win.helpBox then win.helpBox:Hide() end
  if eid and UI.entries[eid] then UI.entries[eid].last = id end
  for vid, p in pairs(win.panels) do p:SetShown(vid == id) end
  win.noticeBox:Hide()
  local opened = not win:IsShown()
  win:Show()
  UI.Refresh()
  if opened then ns.Fire("WINDOW_OPENED") end
end

function UI.Toggle(id)
  if win and win:IsShown() and (not id or id == win.current) then win:Hide() else UI.Show(id) end
end

-- What may be shown: settings always (the guild master activates there),
-- everything else only in an activated guild
local function blockedText()
  if not G.InGuild() then return ns.L.NO_GUILD end
  if not G.IsActivated() then
    return G.IsLeader() and ns.L.NOT_ACTIVE_GM or ns.L.NOT_ACTIVE_MEMBER
  end
end

local function refreshChrome()
  local th = T.Current()
  if win.navDirty then buildNav() end
  local cur = UI.entryOf[win.current]
  for _, b in ipairs(win.navBtns or {}) do
    if b:IsShown() then
      local e = UI.entries[b.entry]
      local active = b.entry == cur
      b.active = active
      b.text:SetText(e.label and e.label() or e.id)
      local badge = e.badge and e.badge()
      b.badge:SetText(badge or "")
      b.badgeBg:SetShown(badge ~= nil and badge ~= "")
      b.badgeBg:SetWidth(math.max(16, b.badge:GetStringWidth() + 10))
      if active then
        b:SetBackdropColor(th.accent[1], th.accent[2], th.accent[3], 1)
        b.text:SetTextColor(1, 0.95, 0.85)
        if b.ownIcon then b.icon:SetVertexColor(1, 0.95, 0.85) end
      else
        b:SetBackdropColor(0, 0, 0, 0)
        b.text:SetTextColor(th.text[1], th.text[2], th.text[3])
        if b.ownIcon then b.icon:SetVertexColor(th.muted[1], th.muted[2], th.muted[3]) end
      end
    end
  end
  -- sub-tabs of the open entry
  local e = cur and UI.entries[cur]
  local tabs = (e and #e.tabs > 1) and e.tabs or {}
  local prev
  for i, vid in ipairs(tabs) do
    local b = win.subtabs[i]
    if not b then
      b = W.Button(win.body, "", false, 24)
      b:SetScript("OnClick", function(self) UI.Show(self.view) end)
      win.subtabs[i] = b
    end
    b.view = vid
    local v = UI.views[vid]
    W.SetLabel(b, v and v.label and v.label() or vid)
    local active = vid == win.current
    b:SetBackdropColor(unpack(active and th.accent or th.panel2))
    b.label:SetTextColor(unpack(active and { 1, 0.95, 0.85 } or th.text))
    b:ClearAllPoints()
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, -10) end
    b:Show()
    prev = b
  end
  for i = #tabs + 1, #win.subtabs do win.subtabs[i]:Hide() end
  win.hasTabs = #tabs > 0
  -- bell: unread count
  local unread = ns.Notices and ns.Notices.Unread() or 0
  win.bell:SetCount(unread)
  -- help: a red 1 while the guild master still has to switch the addon on
  win.help:SetCount((ns.UIHelp and ns.UIHelp.NeedsActivation()) and 1 or 0)
end

function UI.Refresh()
  if not win or not win:IsShown() then return end
  ns.Schedule("gemUIRefresh", 0.05, function()
    if not win:IsShown() then return end
    local season = date("%d.%m.", ns.Points.SeasonStart()) .. " – " .. date("%d.%m.", ns.Points.SeasonEnd() - 1)
    win.title:SetText(G.InGuild() and (G.Name() or "?") or "GuildEventManager")
    if win.crestBtn then win.crestBtn:Update() end
    win.sub:SetText(G.InGuild()
      and ns.L.HEADER_SUB2:format(T.Word("GUILD"), season)
      or ns.L.NO_GUILD_SHORT)
    win.family:Refresh()
    refreshChrome()
    local id = win.current
    local blocked = blockedText()
    if blocked and UI.entryOf[id] ~= "settings" then
      for _, p in pairs(win.panels) do p:Hide() end
      win.notice:SetText(blocked)
      win.notice:Show()
      return
    end
    win.notice:Hide()
    local v = UI.views[id]
    if not v then return end
    local p = win.panels[id]
    local top = win.hasTabs and -44 or -12
    if not p then
      p = CreateFrame("Frame", nil, win.body)
      win.panels[id] = p
      p:SetPoint("TOPLEFT", 12, top); p:SetPoint("BOTTOMRIGHT", -12, 12)
      v.build(p)
    else
      p:ClearAllPoints()
      p:SetPoint("TOPLEFT", 12, top); p:SetPoint("BOTTOMRIGHT", -12, 12)
    end
    p:Show()
    v.refresh(p)
  end)
end

-- Section heading with a thin line
function UI.Section(parent, text)
  local fs = W.Text(parent, 12, "title")
  fs:SetText(text)
  local l = parent:CreateTexture(nil, "ARTWORK")
  local c = T.Current().line
  l:SetColorTexture(c[1], c[2], c[3], 0.7)
  l:SetHeight(1)
  l:SetPoint("LEFT", fs, "RIGHT", 8, 0)
  l:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
  fs.line = l
  return fs
end

-- Small coloured label ("pill")
-- colours for module tags and sign-up states
UI.COLORS = {
  events = { 0.85, 0.70, 0.32 }, pvp = { 0.86, 0.33, 0.27 }, pve = { 0.90, 0.72, 0.30 }, holiday = { 0.35, 0.75, 0.68 },
  ["in"] = { 0.40, 0.75, 0.52 }, late = { 0.40, 0.75, 0.52 }, tent = { 0.90, 0.72, 0.30 }, bench = { 0.50, 0.62, 0.85 },
  out = { 0.86, 0.40, 0.33 }, none = { 0.55, 0.50, 0.46 },
}

function UI.Pill(parent)
  local b = W.Box(parent, 40, 18, "panel2")
  b.text = W.Text(b, 10, "muted")
  b.text:SetPoint("CENTER")
  -- color = { r, g, b }: a tinted tag (module or state)
  function b:Set(text, live, color)
    self.text:SetText(text or "")
    local th = T.Current()
    if color then
      self:SetBackdropColor(color[1] * 0.32, color[2] * 0.32, color[3] * 0.32, 1)
      self:SetBackdropBorderColor(color[1] * 0.6, color[2] * 0.6, color[3] * 0.6, 1)
      self.text:SetTextColor(math.min(1, color[1] * 1.15), math.min(1, color[2] * 1.15), math.min(1, color[3] * 1.15))
    elseif live then
      self:SetBackdropColor(th.accent[1], th.accent[2], th.accent[3], 1)
      self:SetBackdropBorderColor(th.line[1], th.line[2], th.line[3], 1)
      self.text:SetTextColor(1, 0.95, 0.85)
    else
      self:SetBackdropColor(th.panel2[1], th.panel2[2], th.panel2[3], 1)
      self:SetBackdropBorderColor(th.line[1], th.line[2], th.line[3], 1)
      self.text:SetTextColor(th.muted[1], th.muted[2], th.muted[3])
    end
    self:SetWidth(self.text:GetStringWidth() + 14)
    self:SetShown(text ~= nil and text ~= "")
  end
  return b
end

-- tag of an event type's module: label, color (nil for the core's own types)
function UI.ModuleTag(typeId)
  local t = typeId and ns.Modules.Type(typeId)
  local mod = t and t.module and ns.Modules.modules[t.module]
  if not mod or not mod.tag then return nil end
  local label = mod.tag.key and ns.L[mod.tag.key] or mod.tag.label
  return label, mod.tag.color or UI.COLORS[t.module]
end

-- a sign-up state as tag: text, color
function UI.StateTag(st)
  if not st then return ns.L.HOME_NOT_SIGNED, UI.COLORS.none end
  return ns.L.YOU_ST:format(ns.L["ST_" .. st]), UI.COLORS[st]
end

-- date tile: weekday small, day and month big
function UI.DateTile(parent, w, h)
  local th = T.Current()
  local d = W.Box(parent, w or 40, h or 36, "panel")
  d.wd = W.Text(d, 9, "muted"); d.wd:SetPoint("TOP", 0, -4)
  d.day = W.Text(d, 13, "title"); d.day:SetPoint("BOTTOM", 0, 5)
  d.day:SetFont("Fonts\\MORPHEUS.TTF", 14, "")
  function d:Set(ts)
    if not ts then self:Hide(); return end
    local wd = tonumber(date("%w", ts)) + 1
    self.wd:SetText(ns.L["WD_" .. wd] or date("%a", ts))
    self.day:SetText(date("%d.%m.", ts))
    self:Show()
  end
  return d
end

-- Row of chips to pick one value: opts = { { value, label }, ... }
function UI.ChipRow(parent, getOpts, getValue, onPick, w)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(24)
  row.chips = {}
  function row:Refresh()
    local opts = getOpts()
    local prev
    for i, o in ipairs(opts) do
      local c = self.chips[i]
      if not c then
        c = W.Chip(self, "", w, 22)
        c:SetScript("OnClick", function(b) onPick(b.value) end)
        self.chips[i] = c
      end
      c.value = o[1]
      W.SetLabel(c, o[2])
      if not w then c:SetWidth(c.label:GetStringWidth() + 24) end
      c:SetSelected(getValue() == o[1])
      c:ClearAllPoints()
      if prev then c:SetPoint("LEFT", prev, "RIGHT", 4, 0) else c:SetPoint("LEFT", 0, 0) end
      c:Show()
      prev = c
    end
    for i = #opts + 1, #self.chips do self.chips[i]:Hide() end
  end
  return row
end
