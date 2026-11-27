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
local PREVIEW_H = 86   -- the hint above the sample guild (window grows by this)

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
-- def.group: "guild" | "personal" | the id of a module's sidebar entry ("raids", "pvp");
-- without one the page goes to "more". The settings menu groups by it (0.9).
local SETTINGS_GROUP = { settings = "guild", modules = "guild", struct = "guild", ranks = "guild", persons = "personal" }
function UI.AddSettingsPage(id, def)
  local e = addEntry("settings", { group = "guild", hidden = true, order = 99 })
  def.group = def.group or SETTINGS_GROUP[id]
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
  win.navCount, win.headCount = nb, nh
  -- (0.9: no "Settings" entry at the foot any more – the gear in the header opens them)
  win.navBottom = y   -- the calendar below the navigation uses the rest
end

---------------------------------------------------------------------------
-- Settings menu (0.9): in the settings the side bar lists their pages,
-- grouped (Guild, Personal, one group per module). Groups fold in when the
-- list is taller than the side bar; a click on a group folds it out.
---------------------------------------------------------------------------
local function settingsGroups()
  local e = UI.entries.settings
  local groups, order = {}, {}
  local function add(g, vid)
    if not groups[g] then groups[g] = {}; order[#order + 1] = g end
    table.insert(groups[g], vid)
  end
  for _, vid in ipairs(e and e.tabs or {}) do
    local v = UI.views[vid]
    local ok, on = true, true
    if v and v.shown then ok, on = pcall(v.shown) end
    if v and (not ok or on) then
      local g = v.group or SETTINGS_GROUP[vid] or "more"
      if g ~= "guild" and g ~= "personal" and not UI.entries[g] then g = "more" end
      add(g, vid)
    end
  end
  local rank = function(g)
    if g == "guild" then return 0 elseif g == "personal" then return 1 elseif g == "more" then return 999 end
    return 10 + ((UI.entries[g] and UI.entries[g].order) or 100)
  end
  table.sort(order, function(a, b) return rank(a) < rank(b) end)
  local PRIO = { settings = 1, modules = 2, struct = 3, ranks = 4 }
  for _, list in pairs(groups) do
    local pos = {}
    for i, v in ipairs(list) do pos[v] = i end
    table.sort(list, function(a, b) return (PRIO[a] or 10 + pos[a]) < (PRIO[b] or 10 + pos[b]) end)
  end
  return order, groups
end

local function groupName(g)
  if g == "guild" then return ns.L.SET_G_GUILD end
  if g == "personal" then return ns.L.SET_G_PERSONAL end
  if g == "more" then return ns.L.SET_G_MORE end
  local e = UI.entries[g]
  return e and e.label and e.label() or g
end

local function buildSettingsNav()
  local side = win.side
  local th = T.Current()
  local f = win.setNav
  if not f then
    f = CreateFrame("Frame", nil, side)
    f:SetAllPoints()
    f.back = navButton(f)
    f.back:SetPoint("TOPLEFT", 6, -8); f.back:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    f.back.icon:SetTexture(W.Icon("back")); f.back.ownIcon = true
    f.back:SetScript("OnClick", function() UI.Show(win.lastMain or "home") end)
    f.heads, f.items = {}, {}
    f.open = {}
    win.setNav = f
  end
  f.back.text:SetText(ns.L.SET_BACK)
  f.back.icon:SetVertexColor(th.title[1], th.title[2], th.title[3])
  f.back.text:SetTextColor(th.title[1], th.title[2], th.title[3])
  local order, groups = settingsGroups()
  -- does everything fit?
  local need = 40
  for _, g in ipairs(order) do need = need + 22 + #groups[g] * 26 + 6 end
  local avail = (side:GetHeight() or 500) - 10
  local fold = need > avail
  local curGroup
  for _, g in ipairs(order) do for _, vid in ipairs(groups[g]) do if vid == win.current then curGroup = g end end end
  if fold and f.open[curGroup] == nil and curGroup then f.open[curGroup] = true end
  local y, nh, ni = -42, 0, 0
  for _, g in ipairs(order) do
    nh = nh + 1
    local h = f.heads[nh]
    if not h then
      h = CreateFrame("Button", nil, f)
      h:SetHeight(20)
      h.t = W.Text(h, 10, "muted"); h.t:SetPoint("LEFT", 8, 0)
      h.pm = W.Text(h, 11, "title"); h.pm:SetPoint("RIGHT", -8, 0)
      h:SetScript("OnClick", function(self) if self.fold then f.open[self.g] = not f.open[self.g]; UI.Refresh() end end)
      f.heads[nh] = h
    end
    h.g, h.fold = g, fold
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", 6, y); h:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    h.t:SetText(groupName(g))
    local open = not fold or f.open[g]
    h.pm:SetText(fold and (open and "-" or "+") or "")
    h:Show()
    y = y - 22
    if open then
      for _, vid in ipairs(groups[g]) do
        ni = ni + 1
        local b = f.items[ni]
        if not b then
          b = navButton(f)
          b.icon:Hide()
          b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 16, 0); b.text:SetPoint("RIGHT", -6, 0)
          b:SetScript("OnClick", function(self) UI.Show(self.view) end)
          f.items[ni] = b
        end
        b.view = vid
        b:SetHeight(24)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", 6, y); b:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        local v = UI.views[vid]
        b.text:SetText(v and v.label and v.label() or vid)
        b.badgeBg:Hide()
        local active = vid == win.current
        if active then
          b:SetBackdropColor(th.accent[1], th.accent[2], th.accent[3], 1); b.text:SetTextColor(1, 0.95, 0.85)
        else
          b:SetBackdropColor(0, 0, 0, 0); b.text:SetTextColor(th.text[1], th.text[2], th.text[3])
        end
        b:Show()
        y = y - 26
      end
    end
    y = y - 6
  end
  for i = nh + 1, #f.heads do f.heads[i]:Hide() end
  for i = ni + 1, #f.items do f.items[i]:Hide() end
  f:Show()
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
  -- trophies of the guild (0.9): small count next to the guild name, opens the banner page
  f.trophies = CreateFrame("Button", nil, head, "BackdropTemplate")
  f.trophies:SetHeight(18)
  W.Paint(f.trophies, { 0.16, 0.12, 0.06, 0.9 }, { 0.54, 0.43, 0.13, 1 })
  f.trophies.t = W.Text(f.trophies, 10, { 0.96, 0.89, 0.66 }); f.trophies.t:SetPoint("CENTER")
  f.trophies:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
  f.trophies:SetScript("OnClick", function() UI.Show("banner") end)
  f.trophies:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(ns.L.GA_TROPHIES, 1, 0.82, 0)
    GameTooltip:AddLine(ns.L.GA_TROPHIES_TIP, 1, 1, 1, true); GameTooltip:Show()
  end)
  f.trophies:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.trophies:Hide()
  local line = head:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(th.border[1], th.border[2], th.border[3], 1)
  line:SetHeight(1); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
  local close = W.Close(f)
  close:ClearAllPoints(); close:SetPoint("RIGHT", head, "RIGHT", -12, 0)
  f.gear = W.IconButton(head, "settings", 30, ns.L.TAB_SETTINGS)
  f.gear:SetPoint("RIGHT", close, "LEFT", -8, 0)
  f.gear:SetScript("OnClick", function()
    if UI.entryOf[win.current] == "settings" then UI.Show(win.lastMain or "home") else UI.Show("settings") end
  end)
  f.bell = W.IconButton(head, "bell", 30, ns.L.NOTICES)
  f.bell:SetPoint("RIGHT", f.gear, "LEFT", -4, 0)
  f.bell:SetScript("OnClick", function() UI.ToggleNotices() end)
  f.help = W.IconButton(head, "help", 30, ns.L.HELP)
  f.help:SetPoint("RIGHT", f.bell, "LEFT", -4, 0)
  -- "view as rank" (guild master): how the interface looks for a rank
  f.viewAs = W.Dropdown(head, 170, function()
    local o = { { -1, ns.L.VIEW_OWN } }
    for i = 0, 20 do local n = G.rankNames[i]; if n then o[#o + 1] = { i, ns.L.VIEW_AS:format(n) } end end
    return o
  end, function() return G.viewRank or -1 end, function(v)
    ns.Comm.viewWarned = nil
    G.SetViewRank(v >= 0 and v or nil)
  end)
  f.viewAs:SetPoint("RIGHT", f.help, "LEFT", -10, 0)
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

  -- preview: big hint above the sample guild
  local pb = W.Box(f, 10, PREVIEW_H - 8, "panel2")
  pb:SetPoint("TOPLEFT", SIDE + 10, -66); pb:SetPoint("RIGHT", -12, 0)
  pb:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1)
  pb.icon = W.IconTex(pb, "help", 30, "title")
  pb.icon:SetPoint("TOPLEFT", 16, -14)
  pb.head = W.Text(pb, 16, "title")
  pb.head:SetFont("Fonts\\MORPHEUS.TTF", 18, "")
  pb.head:SetPoint("TOPLEFT", pb.icon, "TOPRIGHT", 12, 2)
  pb.text = W.Text(pb, 11, "text")
  pb.text:SetPoint("TOPLEFT", pb.head, "BOTTOMLEFT", 0, -5)
  pb.text:SetPoint("RIGHT", pb, "RIGHT", -230, 0)
  pb.text:SetSpacing(2)
  pb.how = W.Button(pb, ns.L.PREVIEW_HOW, false, 26)
  pb.how:SetWidth(100)
  pb.how:SetPoint("RIGHT", -14, 0)
  pb.how:SetScript("OnClick", function() UI.ToggleHelp() end)
  pb.tell = W.Button(pb, ns.L.PREVIEW_TELL, true, 26)
  pb.tell:SetWidth(200)
  pb.tell:SetPoint("BOTTOMRIGHT", pb.how, "TOPRIGHT", 0, 6)
  pb.tell:SetScript("OnClick", function() if ns.Demo then ns.Demo.TellGuildMaster() end end)
  pb:Hide()
  f.previewBar = pb

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
-- preview on/off: the window grows by the hint so the pages keep their size
local function applyPreview()
  local on = ns.preview and true or false
  local pb = win.previewBar
  if on then
    local guild = G.RealInGuild()
    pb.head:SetText(guild and ns.L.PREVIEW_HEAD or ns.L.PREVIEW_HEAD_NOGUILD)
    pb.text:SetText(guild and ns.L.PREVIEW_TEXT or ns.L.PREVIEW_TEXT_NOGUILD)
    pb.tell:SetShown(guild)
    pb.how:ClearAllPoints()
    if guild then pb.how:SetPoint("BOTTOMRIGHT", -14, 14) else pb.how:SetPoint("RIGHT", -14, 0) end
  end
  if win.previewOn == on then return end
  win.previewOn = on
  win:SetHeight(W_HEIGHT + (on and PREVIEW_H or 0))
  win.body:ClearAllPoints()
  win.body:SetPoint("TOPLEFT", SIDE + 10, -66 - (on and PREVIEW_H or 0))
  win.body:SetPoint("BOTTOMRIGHT", -12, 36)
  pb:SetShown(on)
  for _, p in pairs(win.panels) do p:SetAlpha(on and 0.8 or 1) end
end

function UI.Show(id)
  if ns.Demo then ns.Demo.SyncPreview(true) end
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
  if ns.preview then return nil end   -- members see the sample guild with a hint
  if not G.InGuild() then return ns.L.NO_GUILD end
  if not G.IsActivated() then
    return G.IsLeader() and ns.L.NOT_ACTIVE_GM or ns.L.NOT_ACTIVE_MEMBER
  end
end

local function refreshChrome()
  local th = T.Current()
  if win.navDirty then buildNav() end
  local cur = UI.entryOf[win.current]
  local inSet = cur == "settings"
  if not inSet then win.lastMain = win.current end
  for i, b in ipairs(win.navBtns or {}) do b:SetShown(not inSet and i <= (win.navCount or 0)) end
  for i, h in ipairs(win.navHeads or {}) do h:SetShown(not inSet and i <= (win.headCount or 0)) end
  if win.setBtn then
    win.setBtn:SetShown(not inSet)
    win.setBtn.text:SetText(ns.L.TAB_SETTINGS)
    win.setBtn.text:SetTextColor(th.text[1], th.text[2], th.text[3])
    win.setBtn.icon:SetVertexColor(th.muted[1], th.muted[2], th.muted[3])
    win.setBtn.badgeBg:Hide()
  end
  if inSet then buildSettingsNav() elseif win.setNav then win.setNav:Hide() end
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
  -- a view may hide its tab (def.shown = function() -> bool), e.g. for rights
  local vis = {}
  for _, vid in ipairs(e and e.tabs or {}) do
    local v = UI.views[vid]
    local ok, on = true, true
    if v and v.shown then ok, on = pcall(v.shown) end
    if not ok or on then vis[#vis + 1] = vid end
  end
  local tabs = (#vis > 1 and not inSet) and vis or {}
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
  if ns.Calendar then ns.SafeCall("calendar", ns.Calendar.Refresh) end
  -- help: a red 1 while the guild master still has to switch the addon on
  win.help:SetCount((ns.UIHelp and ns.UIHelp.NeedsActivation()) and 1 or 0)
end

function UI.Refresh()
  if not win or not win:IsShown() then return end
  ns.Schedule("gemUIRefresh", 0.05, function()
    if not win:IsShown() then return end
    local season = date("%d.%m.", ns.Points.SeasonStart()) .. " – " .. date("%d.%m.", ns.Points.SeasonEnd() - 1)
    applyPreview()
    win.title:SetText(G.InGuild() and ((G.Name() or "?") .. (ns.preview and ("  " .. U.Color(U.WARN, ns.L.PREVIEW_TAG)) or "")) or "GuildEventManager")
    if win.crestBtn then win.crestBtn:Update() end
    if win.trophies then
      local n = (G.InGuild() and ns.GuildAch) and ns.GuildAch.Count() or 0
      win.trophies.t:SetText("|TInterface\\Icons\\INV_Misc_Ribbon_01:12:12:0:0:64:64:6:58:6:58|t " .. n)
      win.trophies:SetWidth(win.trophies.t:GetStringWidth() + 14)
      win.trophies:SetShown(n > 0)
    end
    win.sub:SetText((ns.preview and ns.L.PREVIEW_SUB or G.InGuild()
      and ns.L.HEADER_SUB2:format(T.Word("GUILD"), season)
      or ns.L.NO_GUILD_SHORT)
      .. (G.viewRank and ("  " .. U.Color("ffff805c", ns.L.VIEW_ACTIVE:format(G.rankNames[G.viewRank] or "?"))) or ""))
    win.viewAs:SetShown(G.IsRealLeader() and not ns.demo)
    win.viewAs:Refresh()
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
      p:SetAlpha(win.previewOn and 0.8 or 1)
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
