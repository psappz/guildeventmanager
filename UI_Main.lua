local ADDON, ns = ...
-- Main window: faction header, tabs (Events, Banner, Achievements, Settings),
-- and the family bar at the bottom like in the other Manager addons.
local U, G, T, W = ns.U, ns.Guild, ns.Theme, ns.W
local UI = {}
ns.UI = UI

UI.views = {}      -- id -> { label = fn, build = fn(parent), refresh = fn(panel) }
UI.order = { "events", "banner", "ach", "settings" }
local win

function UI.RegisterView(id, def) UI.views[id] = def end

-- Modules add their own tab (before Settings). Must happen before the window opens.
function UI.AddTab(id, def)
  UI.views[id] = def
  for _, v in ipairs(UI.order) do if v == id then return end end
  table.insert(UI.order, #UI.order, id)
end

local function buildWindow()
  local th = T.Current()
  local f = W.Box(UIParent, 900, 600, "bg")
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

  -- header
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(56)
  local hbg = head:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints()
  hbg:SetColorTexture(th.banner[1], th.banner[2], th.banner[3], 0.35)
  local crest = head:CreateTexture(nil, "ARTWORK")
  crest:SetSize(44, 44); crest:SetPoint("LEFT", 12, -2)
  crest:SetTexture(th.crest)
  f.title = W.Text(head, 17, "title")
  f.title:SetPoint("TOPLEFT", crest, "TOPRIGHT", 8, -4)
  f.title:SetText("GuildEventManager")
  f.sub = W.Text(head, 11, { 0.85, 0.80, 0.72 })
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  local line = head:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(th.border[1], th.border[2], th.border[3], 1)
  line:SetHeight(1); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
  W.Close(f)

  -- tabs
  f.tabs = {}
  local prev
  for _, id in ipairs(UI.order) do
    local b = W.Button(f, "", false, 26)
    b.id = id
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 16, -66) end
    b:SetScript("OnClick", function(self) UI.Show(self.id) end)
    f.tabs[id] = b
    prev = b
  end

  -- content
  f.body = W.Box(f, 10, 10, "panel")
  f.body:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
  f.body:SetPoint("TOPLEFT", 16, -92)
  f.body:SetPoint("BOTTOMRIGHT", -16, 36)
  f.panels = {}

  -- not activated / no guild
  f.notice = W.Text(f.body, 13, "text")
  f.notice:SetPoint("TOPLEFT", 24, -24); f.notice:SetPoint("RIGHT", -24, 0)
  f.notice:SetSpacing(4)

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

function UI.Show(id)
  win = win or buildWindow()
  id = id or win.current or "events"
  win.current = id
  for vid, b in pairs(win.tabs) do
    local v = UI.views[vid]
    W.SetLabel(b, v and v.label() or vid)
    local th = T.Current()
    local active = vid == id
    b:SetBackdropColor(unpack(active and th.accent or th.panel2))
    b.label:SetTextColor(unpack(active and { 1, 0.95, 0.85 } or th.text))
  end
  for vid, p in pairs(win.panels) do p:SetShown(vid == id) end
  win:Show()
  UI.Refresh()
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

function UI.Refresh()
  if not win or not win:IsShown() then return end
  ns.Schedule("gemUIRefresh", 0.05, function()
    if not win:IsShown() then return end
    local th = T.Current()
    local season = date("%d.%m.", ns.Points.SeasonStart()) .. " – " .. date("%d.%m.", ns.Points.SeasonEnd() - 1)
    win.sub:SetText(G.InGuild()
      and ns.L.HEADER_SUB:format(G.Name() or "?", T.Word("GUILD"), season)
      or ns.L.NO_GUILD_SHORT)
    win.family:Refresh()
    local id = win.current
    local blocked = blockedText()
    if blocked and id ~= "settings" then
      for _, p in pairs(win.panels) do p:Hide() end
      win.notice:SetText(blocked)
      win.notice:Show()
      return
    end
    win.notice:Hide()
    local v = UI.views[id]
    if not v then return end
    local p = win.panels[id]
    if not p then
      p = CreateFrame("Frame", nil, win.body)
      p:SetPoint("TOPLEFT", 12, -12); p:SetPoint("BOTTOMRIGHT", -12, 12)
      win.panels[id] = p
      v.build(p)
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
function UI.Pill(parent)
  local b = W.Box(parent, 40, 18, "panel2")
  b.text = W.Text(b, 10, "muted")
  b.text:SetPoint("CENTER")
  function b:Set(text, live)
    self.text:SetText(text or "")
    local th = T.Current()
    if live then
      self:SetBackdropColor(th.accent[1], th.accent[2], th.accent[3], 1)
      self.text:SetTextColor(1, 0.95, 0.85)
    else
      self:SetBackdropColor(th.panel2[1], th.panel2[2], th.panel2[3], 1)
      self.text:SetTextColor(th.muted[1], th.muted[2], th.muted[3])
    end
    self:SetWidth(self.text:GetStringWidth() + 14)
    self:SetShown(text ~= nil and text ~= "")
  end
  return b
end
