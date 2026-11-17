local ADDON, ns = ...
-- Help: the "?" in the header shows help for the page the user is on. While
-- the guild has not switched the addon on, it carries a red 1 and explains
-- what to do: members are told to wait for the guild master, the guild master
-- gets a step-by-step guide on the settings page. The same guide, the other
-- way round, switches the addon off again (link at the bottom of the settings).
local U, G, T, W, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI
local L = ns.L
local H = {}
ns.UIHelp = H

H.topics = {}   -- view or entry id -> fn() returning title, text

-- modules: UI.AddHelp("raidplan", function() return title, text end)
function UI.AddHelp(id, fn) H.topics[id] = fn end

local function topicFor(view)
  local fn = H.topics[view] or H.topics[UI.entryOf[view] or ""]
  if not fn then return nil end
  local ok, title, text = pcall(fn)
  if ok and title then return title, text end
end

-- core pages
local function core(key)
  return function() return L["HELP_T_" .. key], L["HELP_X_" .. key] end
end
for _, id in ipairs({ "home", "events", "ledger", "ach", "banner", "settings" }) do UI.AddHelp(id, core(id)) end

-- needs the guild master?
function H.NeedsActivation()
  return G.InGuild() and not G.IsActivated()
end

---------------------------------------------------------------------------
-- The box under the "?"
---------------------------------------------------------------------------
local function buildBox(win)
  local box = W.Box(win, 380, 40, "panel2")
  box:SetPoint("TOPRIGHT", win.help, "BOTTOMRIGHT", 0, -6)
  box:SetFrameLevel(win:GetFrameLevel() + 30)
  box:EnableMouse(true)
  local th = T.Current()
  box:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
  box.title = W.Text(box, 13, "title")
  box.title:SetPoint("TOPLEFT", 14, -12); box.title:SetPoint("RIGHT", -14, 0)
  box.text = W.Text(box, 11, "text")
  box.text:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -8); box.text:SetPoint("RIGHT", -14, 0)
  box.text:SetSpacing(3)
  box.btn = W.Button(box, "", true, 24)
  box.btn:SetWidth(200)
  box.btn:SetPoint("TOPLEFT", box.text, "BOTTOMLEFT", 0, -12)
  box.btn:SetScript("OnClick", function(self)
    box:Hide()
    if self.action then self.action() end
  end)
  box:Hide()
  win.helpBox = box
  return box
end

function UI.ToggleHelp()
  local win = UI.Frame()
  if not win then return end
  local box = win.helpBox or buildBox(win)
  if box:IsShown() then box:Hide(); return end
  if win.noticeBox then win.noticeBox:Hide() end

  local title, text, btn, action
  if not G.InGuild() then
    title, text = L.HELP_T_noguild, L.HELP_X_noguild
  elseif not G.IsActivated() then
    if G.IsLeader() then
      title, text, btn = L.HELP_ACT_GM_T, L.HELP_ACT_GM_X, L.HELP_ACT_GO
      action = function() H.ShowGuide("on") end
    else
      title, text = L.HELP_ACT_MEMBER_T, L.HELP_ACT_MEMBER_X
    end
  else
    title, text = topicFor(win.current)
    if not title then title, text = L.HELP_T_none, L.HELP_X_none end
  end
  box.title:SetText(title or "")
  box.text:SetText(text or "")
  box.btn:SetShown(btn ~= nil)
  if btn then W.SetLabel(box.btn, btn) end
  box.btn.action = action
  local h = 12 + box.title:GetStringHeight() + 8 + box.text:GetStringHeight() + 14
  if btn then h = h + 12 + 24 end
  box:SetHeight(h)
  box:Show()
end

---------------------------------------------------------------------------
-- The guide on the settings page: switch on ("on") or off ("off")
---------------------------------------------------------------------------
local function stepRow(card, n)
  local th = T.Current()
  local r = CreateFrame("Frame", nil, card)
  r:SetHeight(60)
  r.badge = r:CreateTexture(nil, "ARTWORK")
  r.badge:SetSize(34, 34); r.badge:SetPoint("TOPLEFT", 0, 0)
  r.badge:SetTexture(W.ICONS .. "dot")
  r.badge:SetVertexColor(th.title[1], th.title[2], th.title[3])
  r.num = r:CreateFontString(nil, "OVERLAY")
  r.num:SetFont("Fonts\\MORPHEUS.TTF", 20, "")
  r.num:SetPoint("CENTER", r.badge, "CENTER", 0, 0)
  r.num:SetTextColor(0.08, 0.06, 0.04)
  r.num:SetText(tostring(n))
  r.title = W.Text(r, 14, "title")
  r.title:SetPoint("TOPLEFT", r.badge, "TOPRIGHT", 12, -2); r.title:SetPoint("RIGHT", 0, 0)
  r.text = W.Text(r, 11, "text")
  r.text:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -6); r.text:SetPoint("RIGHT", 0, 0)
  r.text:SetSpacing(3)
  r.btn = W.Button(r, "", false, 24)
  r.btn:SetWidth(210)
  r.btn:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -8)
  return r
end

local function buildGuide(win)
  local g = CreateFrame("Frame", nil, win.body)
  g:SetAllPoints(win.body)
  g:SetFrameLevel(win.body:GetFrameLevel() + 40)
  g:EnableMouse(true)
  local dim = g:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.72)

  local card = W.Box(g, 520, 420, "panel")
  card:SetPoint("CENTER", 0, 10)
  local th = T.Current()
  card:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1)
  g.card = card
  g.head = W.Text(card, 20, "title")
  g.head:SetFont("Fonts\\MORPHEUS.TTF", 22, "")
  g.head:SetPoint("TOPLEFT", 22, -18); g.head:SetPoint("RIGHT", -48, 0)
  local close = W.Close(card, function() g:Hide() end)
  close:SetPoint("TOPRIGHT", -10, -10)

  g.rows = {}
  for i = 1, 3 do
    local r = stepRow(card, i)
    r:SetPoint("LEFT", 22, 0); r:SetPoint("RIGHT", -22, 0)
    g.rows[i] = r
  end
  g.status = W.Text(card, 12, "text")
  g.status:SetPoint("LEFT", 22, 0); g.status:SetPoint("RIGHT", -22, 0)
  g.status:SetSpacing(3)
  g.note = W.Text(card, 10, "muted")
  g.note:SetPoint("LEFT", 22, 0); g.note:SetPoint("RIGHT", -22, 0)
  g.note:SetSpacing(2)
  g.ok = W.Button(card, CLOSE or "OK", true, 24)
  g.ok:SetWidth(120)
  g.ok:SetPoint("BOTTOMRIGHT", -22, 16)
  g.ok:SetScript("OnClick", function() g:Hide() end)

  -- the status follows the guild info while the guide is open
  local acc = 0
  g:SetScript("OnUpdate", function(self, el)
    acc = acc + el
    if acc < 1 then return end
    acc = 0
    H.UpdateGuide()
  end)
  g:Hide()
  win.guide = g
  return g
end

local function showCode()
  local m = G.Marker() or G.NewMarker()
  W.Dialog({ text = L.SET_MARKER_TEXT, edit = true, editText = m, noCancel = true, accept = CLOSE or "OK" })
end

local function checkAgain()
  local g = UI.Frame() and UI.Frame().guide
  if g then g.checked = true end
  G.markerRead = nil
  G.RequestRoster()
  ns.Schedule("gemRecheck", 1.5, function()
    ns.CheckActivation()
    H.UpdateGuide()
  end)
end

local function layout(g)
  local y = -60
  for _, r in ipairs(g.rows) do
    local h = 2 + r.title:GetStringHeight() + 6 + r.text:GetStringHeight()
    if r.btn:IsShown() then h = h + 8 + 24 end
    h = math.max(h, 36)
    r:SetHeight(h)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 22, y); r:SetPoint("RIGHT", -22, 0)
    y = y - h - 18
  end
  g.status:ClearAllPoints(); g.status:SetPoint("TOPLEFT", 22, y); g.status:SetPoint("RIGHT", -22, 0)
  y = y - g.status:GetStringHeight() - (g.note:GetText() ~= "" and 10 or 0)
  g.note:ClearAllPoints(); g.note:SetPoint("TOPLEFT", 22, y); g.note:SetPoint("RIGHT", -22, 0)
  y = y - g.note:GetStringHeight() - 16 - 24 - 16
  g.card:SetHeight(-y)
end

function H.UpdateGuide()
  local win = UI.Frame()
  local g = win and win.guide
  if not g or not g:IsShown() then return end
  local th = T.Current()
  local active = G.IsActivated()
  local r1, r2, r3 = g.rows[1], g.rows[2], g.rows[3]
  if g.kind == "off" then
    local code = G.Marker() or "[GEM:…]"
    g.head:SetText(L.GUIDE_OFF_T)
    r1.title:SetText(L.GUIDE_OFF_STEP1_T); r1.text:SetText(L.GUIDE_OFF_STEP1_X); r1.btn:Hide()
    r2.title:SetText(L.GUIDE_OFF_STEP2_T); r2.text:SetText(L.GUIDE_OFF_STEP2_X:format(U.Color(T.Hex(th.title), code))); r2.btn:Hide()
    r3.title:SetText(L.GUIDE_STEP3_T); r3.text:SetText(L.GUIDE_OFF_STEP3_X)
    W.SetLabel(r3.btn, L.GUIDE_CHECK); r3.btn:SetScript("OnClick", checkAgain); r3.btn:Show()
    if not active then
      g.status:SetText(U.Color(T.Hex(th.good), L.GUIDE_OFF_DONE))
    else
      g.status:SetText(g.checked and U.Color(U.WARN, L.GUIDE_OFF_WAIT) or "")
    end
    g.note:SetText(L.GUIDE_OFF_NOTE)
  else
    g.head:SetText(L.GUIDE_ACT_T)
    r1.title:SetText(L.GUIDE_STEP1_T); r1.text:SetText(L.GUIDE_STEP1_X)
    W.SetLabel(r1.btn, L.GUIDE_STEP1_B); r1.btn:SetScript("OnClick", showCode); r1.btn:Show()
    r2.title:SetText(L.GUIDE_STEP2_T); r2.text:SetText(L.GUIDE_STEP2_X); r2.btn:Hide()
    r3.title:SetText(L.GUIDE_STEP3_T); r3.text:SetText(L.GUIDE_STEP3_X)
    W.SetLabel(r3.btn, L.GUIDE_CHECK); r3.btn:SetScript("OnClick", checkAgain); r3.btn:Show()
    if active then
      g.status:SetText(U.Color(T.Hex(th.good), L.GUIDE_DONE:format(G.Name() or "?")))
    else
      g.status:SetText(g.checked and U.Color(U.WARN, L.GUIDE_WAIT) or "")
    end
    g.note:SetText("")
  end
  layout(g)
end

-- kind "on": switch on (guild master, not active yet); "off": switch off
function H.ShowGuide(kind)
  UI.Show("settings")
  local win = UI.Frame()
  if not win then return end
  if win.helpBox then win.helpBox:Hide() end
  local g = win.guide or buildGuide(win)
  g.kind = kind or "on"
  g.checked = false
  g:Show()
  H.UpdateGuide()
end
