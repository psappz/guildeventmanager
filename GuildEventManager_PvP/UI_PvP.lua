local ADDON, P = ...
-- PvP tab: war drums, own blood debts, honor roll of the guild, and (for
-- guild event managers) the honor rules.
local core = P.core
if not core then return end
local U, G, T, W, UI, Pts = core.U, core.Guild, core.Theme, core.W, core.UI, core.Points
local L = P.L
local V = {}

local RULES = { "kill", "perVictim", "dailyCap", "debt", "debtDays", "coldMin", "drum", "drumWindow", "drumRadius" }

local function build(p)
  local th = T.Current()
  ---------------------------------------------------------------- left: drums
  local left = CreateFrame("Frame", nil, p)
  left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -12, 0)
  p.drumHead = UI.Section(left, "")
  p.drumHead:SetPoint("TOPLEFT", 0, 0)
  p.drumText = W.Edit(left, 10, 22)
  p.drumText:SetPoint("TOPLEFT", 0, -24); p.drumText:SetPoint("RIGHT", 0, 0)
  p.drumText:SetMaxLetters(80)
  p.drumHint = W.Text(left, 10, "muted")
  p.drumHint:SetPoint("TOPLEFT", p.drumText, "BOTTOMLEFT", 0, -4)
  p.drumHint:SetText(L.PVP_DRUM_TEXT_HINT)
  p.drumBtns = {}
  local prev
  for _, lvl in ipairs(P.LEVELS) do
    local b = W.Button(left, P.LevelName(lvl), lvl ~= "help", 24)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", p.drumHint, "BOTTOMLEFT", 0, -8) end
    b:SetScript("OnClick", function()
      P.Drum(lvl, p.drumText:GetText())
      p.drumText:SetText(""); p.drumText:ClearFocus()
    end)
    b.tip = { P.LevelName(lvl), L["PVP_LVL_" .. lvl .. "_TIP"] }
    b.lvl = lvl
    p.drumBtns[#p.drumBtns + 1] = b
    prev = b
  end
  p.drumList = W.Box(left, 10, 96, "panel2")
  p.drumList:SetPoint("TOPLEFT", p.drumBtns[1], "BOTTOMLEFT", 0, -10); p.drumList:SetPoint("RIGHT", 0, 0)
  p.drumRows = W.Pool(p.drumList, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(18)
    r.text = W.Text(r, 10, "text")
    r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -60, 0); r.text:SetWordWrap(false)
    r.way = W.Button(r, L.PVP_WAYPOINT, false, 16)
    r.way:SetPoint("RIGHT", -4, 0)
    return r
  end)
  p.drumEmpty = W.Text(p.drumList, 10, "muted")
  p.drumEmpty:SetPoint("TOPLEFT", 8, -8); p.drumEmpty:SetPoint("RIGHT", -8, 0)
  p.drumEmpty:SetSpacing(2)

  -- own debts
  p.debtHead = UI.Section(left, "")
  p.debtHead:SetPoint("TOPLEFT", p.drumList, "BOTTOMLEFT", 0, -14)
  p.debtBox = W.Box(left, 10, 10, "panel2")
  p.debtBox:SetPoint("TOPLEFT", p.debtHead, "BOTTOMLEFT", 0, -8); p.debtBox:SetPoint("BOTTOMRIGHT", 0, 22)
  p.debtRows = W.Pool(p.debtBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(18)
    r.name = W.Text(r, 11, "text"); r.name:SetPoint("LEFT", 6, 0)
    r.info = W.Text(r, 10, "muted"); r.info:SetPoint("RIGHT", -6, 0); r.info:SetJustifyH("RIGHT")
    return r
  end)
  p.debtEmpty = W.Text(p.debtBox, 10, "muted")
  p.debtEmpty:SetPoint("TOPLEFT", 8, -8); p.debtEmpty:SetPoint("RIGHT", -8, 0)
  p.debtEmpty:SetSpacing(2)
  p.today = W.Text(left, 10, "muted")
  p.today:SetPoint("BOTTOMLEFT", 0, 4)

  ---------------------------------------------------------------- right: honor roll / rules
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", p, "TOP", 12, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
  p.right = right
  p.rollHead = UI.Section(right, L.PVP_ROLL)
  p.rollHead:SetPoint("TOPLEFT", 0, 0)
  p.rulesBtn = W.Button(right, L.PVP_RULES, false, 20)
  p.rulesBtn:SetPoint("TOPRIGHT", 0, 2)
  p.rulesBtn:SetScript("OnClick", function() V.showRules = not V.showRules; UI.Refresh() end)
  p.rollHead.line:SetPoint("RIGHT", p.rulesBtn, "LEFT", -8, 0)

  p.roll = W.Box(right, 10, 10, "panel2")
  p.roll:SetPoint("TOPLEFT", 0, -24); p.roll:SetPoint("BOTTOMRIGHT", 0, 0)
  p.rollScroll = W.Scroll(p.roll)
  p.rollScroll:SetPoint("TOPLEFT", 6, -6); p.rollScroll:SetPoint("BOTTOMRIGHT", -6, 6)
  p.rollRows = W.Pool(p.rollScroll.content, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(18)
    r:RegisterForClicks("RightButtonUp")
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 2, 0); r.text:SetPoint("RIGHT", -70, 0); r.text:SetWordWrap(false)
    r.pts = W.Text(r, 11, "title"); r.pts:SetPoint("RIGHT", -36, 0); r.pts:SetJustifyH("RIGHT")
    r.when = W.Text(r, 9, "muted"); r.when:SetPoint("RIGHT", -2, 0); r.when:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self)
      if not G.IsManager() or not self.entry or self.entry.reverted then return end
      W.OpenMenu(self, function(_, root)
        root:CreateTitle(G.Display(self.entry.who))
        root:CreateButton(L.PVP_REVERT, function() Pts.Revert(self.entry.id) end)
      end)
    end)
    return r
  end)
  p.rollEmpty = W.Text(p.rollScroll.content, 10, "muted")
  p.rollEmpty:SetPoint("TOPLEFT", 2, -4); p.rollEmpty:SetPoint("RIGHT", p.rollScroll.content, "RIGHT", -2, 0)
  p.rollEmpty:SetText(L.PVP_ROLL_EMPTY)

  -- rules form (managers edit, everyone can read)
  p.rules = W.Box(right, 10, 10, "panel2")
  p.rules:SetPoint("TOPLEFT", 0, -24); p.rules:SetPoint("BOTTOMRIGHT", 0, 0)
  p.rules:Hide()
  p.ruleEdits = {}
  -- built-in rules plus rules of PvP extension modules (GuildEventManagerAPI.PvP.AddRule)
  local keys = {}
  for _, k in ipairs(RULES) do keys[#keys + 1] = { key = k, label = L["PVP_R_" .. k] } end
  for _, r in ipairs(P.extraRules or {}) do keys[#keys + 1] = { key = r.key, label = r.label or (r.labelKey and L[r.labelKey]) or r.key } end
  p.ruleKeys = keys
  p.rulesScroll = W.Scroll(p.rules)
  p.rulesScroll:SetPoint("TOPLEFT", 0, 0); p.rulesScroll:SetPoint("BOTTOMRIGHT", 0, 40)
  local rc = p.rulesScroll.content
  for i, k in ipairs(keys) do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local l = W.Text(rc, 10, "muted")
    l:SetPoint("TOPLEFT", 10 + col * 136, -10 - row * 50)
    l:SetWidth(128); l:SetWordWrap(false)
    l:SetText(k.label)
    local e = W.Edit(rc, 90, 22)
    e:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3)
    p.ruleEdits[k.key] = e
  end
  local rows = math.ceil(#keys / 3)
  p.rulesHint = W.Text(rc, 10, "muted")
  p.rulesHint:SetPoint("TOPLEFT", 10, -14 - rows * 50); p.rulesHint:SetPoint("RIGHT", rc, "RIGHT", -10, 0)
  p.rulesScroll:SetContentHeight(rows * 50 + 80)
  p.rulesHint:SetSpacing(2)
  p.rulesHint:SetText(L.PVP_RULES_HINT)
  p.rulesSave = W.Button(p.rules, core.L.SAVE, true, 22)
  p.rulesSave:SetPoint("BOTTOMRIGHT", -10, 10)
  p.rulesSave:SetScript("OnClick", function()
    core.Profile.Update(function(pr)
      pr.pvp = pr.pvp or {}
      for _, k in ipairs(p.ruleKeys) do
        local v = tonumber((string.gsub(p.ruleEdits[k.key]:GetText() or "", ",", ".")))
        if v and v >= 0 then pr.pvp[k.key] = v end
      end
    end)
    U.Print(core.L.SAVED)
  end)
  p.rulesDefault = W.Button(p.rules, core.L.RESET_ACHS, false, 22)
  p.rulesDefault:SetPoint("RIGHT", p.rulesSave, "LEFT", -6, 0)
  p.rulesDefault:SetScript("OnClick", function()
    core.Profile.Update(function(pr) pr.pvp = U.Copy(P.DEFAULTS) end)
  end)
end

local WHY = { kill = "PVP_DEED_KILL", debt = "PVP_DEED_DEBT", drum = "PVP_DEED_DRUM", revert = "PVP_DEED_REVERT" }

local function refresh(p)
  local th = T.Current()
  local manager = G.IsManager()
  local r = P.Rules()

  -- drums
  p.drumHead:SetText(T.Word("DRUM"))
  for _, b in ipairs(p.drumBtns) do b:SetEnabled(P.CanDrum(b.lvl)) end
  local drums = P.ActiveDrums()
  for i, d in ipairs(drums) do
    if i > 4 then break end
    local row = p.drumRows:Get(i)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -4 - (i - 1) * 22); row:SetPoint("RIGHT", p.drumList, "RIGHT", 0, 0)
    local state = d.mine and L.PVP_DRUM_MINE or (d.arrived and L.PVP_DRUM_DONE or U.FormatSpan(r.drumWindow * 60 - (U.Now() - d.ts)))
    row.text:SetText(P.DrumText(d) .. U.Color(T.Hex(th.muted), "  · " .. state))
    row.way:SetShown(not d.mine)
    row.way:SetScript("OnClick", function() P.SetWaypoint(d) end)
  end
  p.drumRows:HideFrom(math.min(#drums, 4) + 1)
  p.drumEmpty:SetShown(#drums == 0)
  p.drumEmpty:SetText(L.PVP_DRUM_NONE:format(r.drum, r.drumWindow))

  -- debts
  local debts = P.OpenDebts()
  p.debtHead:SetText(T.Word("DEBTS") .. " (" .. #debts .. ")")
  local maxAge = (r.debtDays or 7) * 86400
  for i, d in ipairs(debts) do
    if i > 8 then break end
    local row = p.debtRows:Get(i)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -4 - (i - 1) * 20); row:SetPoint("RIGHT", p.debtBox, "RIGHT", 0, 0)
    row.name:SetText(d.name)
    row.info:SetText((d.zone or "") .. " · " .. L.PVP_DEBT_LEFT:format(U.FormatSpan(maxAge - (U.Now() - d.t))))
  end
  p.debtRows:HideFrom(math.min(#debts, 8) + 1)
  p.debtEmpty:SetShown(#debts == 0)
  p.debtEmpty:SetText(L.PVP_DEBT_NONE:format(T.Word("DEBT"), r.debtDays, r.debt))
  local k = P.KillsToday()
  p.today:SetText(L.PVP_TODAY:format(k.honor or 0, r.dailyCap))

  -- right side
  local showRules = V.showRules
  p.roll:SetShown(not showRules)
  p.rules:SetShown(showRules)
  W.SetLabel(p.rulesBtn, showRules and L.PVP_ROLL or L.PVP_RULES)
  p.rollHead:SetText(showRules and L.PVP_RULES or L.PVP_ROLL)
  if showRules then
    for _, k in ipairs(p.ruleKeys) do
      local e = p.ruleEdits[k.key]
      if not e:HasFocus() then e:SetText(tostring(r[k.key] or "")) end
      e:SetEnabled(manager)
    end
    p.rulesSave:SetShown(manager); p.rulesDefault:SetShown(manager)
    return
  end
  local list = Pts.Entries(function(e) return e.pot == "honor" end)
  local n = 0
  for _, e in ipairs(list) do
    n = n + 1
    if n > 60 then break end
    local row = p.rollRows:Get(n)
    row.entry = e
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(n - 1) * 20); row:SetPoint("RIGHT", p.rollScroll.content, "RIGHT", 0, 0)
    local deed = P.DeedLabel and P.DeedLabel(e)
    if not deed then
      deed = L[WHY[e.why] or "PVP_DEED_OTHER"]
      if e.why == "debt" or e.why == "kill" then deed = deed:format(e.note or "?") end
    end
    if e.why == "debt" then deed = deed .. " (" .. T.Word("DEBT") .. ")" end
    local txt = G.Display(e.who) .. U.Color(T.Hex(th.muted), " · " .. deed .. ((e.zone and e.zone ~= "") and (" · " .. e.zone) or ""))
    if e.reverted then txt = U.Color("ff808080", G.Display(e.who) .. " · " .. deed .. " · " .. L.PVP_REVERTED) end
    row.text:SetText(txt)
    row.pts:SetText((e.amt > 0 and "+" or "") .. e.amt)
    row.when:SetText(date("%d.%m.", e.ts))
  end
  p.rollRows:HideFrom(math.min(n, 60) + 1)
  p.rollEmpty:SetShown(n == 0)
  p.rollScroll:SetContentHeight(math.min(n, 60) * 20)
end

UI.AddTab("pvp", {
  label = function() return L.TAB_PVP end,
  build = build,
  refresh = refresh,
})

-- the drum list counts down: refresh the open tab every few seconds
local function pulse()
  core.Schedule("gemPvpPulse", 5, pulse)
  local f = UI.Frame()
  if f and f:IsShown() and f.current == "pvp" then UI.Refresh() end
end
core.Schedule("gemPvpPulse", 5, pulse)
