local ADDON, P = ...
-- "Duels & Oaths" tab: duels of honor with witnesses, oaths, and the season results
-- (podium of the last seasons, progress of the guild towards "Unstoppable").
local core = P.core
if not core then return end
local U, G, T, W, UI, Pts = core.U, core.Guild, core.Theme, core.W, core.UI, core.Points
local L = P.L
local V = { lvl = 1 }

local ROW = 24

local function build(p)
  ---------------------------------------------------------------- left: duels of honor
  local left = CreateFrame("Frame", nil, p)
  left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -12, 0)
  p.makHead = UI.Section(left, "")
  p.makHead:SetPoint("TOPLEFT", 0, 0)
  p.makName = W.Edit(left, 130, 22)
  p.makName:SetPoint("TOPLEFT", 0, -24)
  p.makName:SetMaxLetters(40)
  p.makStake = W.Edit(left, 10, 22)
  p.makStake:SetPoint("LEFT", p.makName, "RIGHT", 6, 0)
  p.makStake:SetMaxLetters(60)
  p.makBtn = W.Button(left, L.PVP_MAK_CHALLENGE, true, 22)
  p.makBtn:SetPoint("TOPRIGHT", 0, -24)
  p.makStake:SetPoint("RIGHT", p.makBtn, "LEFT", -6, 0)
  p.makBtn:SetScript("OnClick", function()
    P.Challenge(p.makName:GetText(), p.makStake:GetText())
    p.makName:ClearFocus(); p.makStake:ClearFocus(); p.makStake:SetText("")
  end)
  p.makHint = W.Text(left, 10, "muted")
  p.makHint:SetPoint("TOPLEFT", p.makName, "BOTTOMLEFT", 0, -4); p.makHint:SetPoint("RIGHT", 0, 0)
  p.makHint:SetSpacing(2)

  p.makBox = W.Box(left, 10, 4 * ROW + 10, "panel2")
  p.makBox:SetPoint("TOPLEFT", p.makHint, "BOTTOMLEFT", 0, -8); p.makBox:SetPoint("RIGHT", 0, 0)
  p.makRows = W.Pool(p.makBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 6, 0); r.text:SetWordWrap(false)
    r.b2 = W.Button(r, "", false, 18); r.b2:SetPoint("RIGHT", -4, 0)
    r.b1 = W.Button(r, "", false, 18); r.b1:SetPoint("RIGHT", r.b2, "LEFT", -4, 0)
    r.text:SetPoint("RIGHT", r.b1, "LEFT", -6, 0)
    return r
  end)
  p.makEmpty = W.Text(p.makBox, 10, "muted")
  p.makEmpty:SetPoint("TOPLEFT", 8, -8); p.makEmpty:SetPoint("RIGHT", -8, 0)
  p.makEmpty:SetSpacing(2)

  p.resHead = UI.Section(left, L.PVP_MAK_RESULTS)
  p.resHead:SetPoint("TOPLEFT", p.makBox, "BOTTOMLEFT", 0, -14)
  p.resBox = W.Box(left, 10, 10, "panel2")
  p.resBox:SetPoint("TOPLEFT", p.resHead, "BOTTOMLEFT", 0, -8); p.resBox:SetPoint("BOTTOMRIGHT", 0, 20)
  p.resRows = W.Pool(p.resBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(18)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -50, 0); r.text:SetWordWrap(false)
    r.when = W.Text(r, 9, "muted"); r.when:SetPoint("RIGHT", -6, 0); r.when:SetJustifyH("RIGHT")
    return r
  end)
  p.resEmpty = W.Text(p.resBox, 10, "muted")
  p.resEmpty:SetPoint("TOPLEFT", 8, -8); p.resEmpty:SetPoint("RIGHT", -8, 0)
  p.resEmpty:SetText(L.PVP_MAK_RESULTS_NONE)
  p.record = W.Text(left, 10, "muted")
  p.record:SetPoint("BOTTOMLEFT", 0, 2); p.record:SetPoint("RIGHT", 0, 0)

  ---------------------------------------------------------------- right: oaths and season
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", p, "TOP", 12, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
  p.oathHead = UI.Section(right, L.PVP_OATH_TITLE)
  p.oathHead:SetPoint("TOPLEFT", 0, 0)
  p.oathText = W.Edit(right, 10, 22)
  p.oathText:SetPoint("TOPLEFT", 0, -24)
  p.oathText:SetMaxLetters(80)
  p.oathLvl = W.Dropdown(right, 120, function()
    local o = {}
    for i = 1, 3 do o[#o + 1] = { i, L["PVP_OATH_LVL" .. i] .. " · " .. P.OathHonor(i) } end
    return o
  end, function() return V.lvl end, function(v) V.lvl = v; UI.Refresh() end)
  p.oathBtn = W.Button(right, L.PVP_OATH_SWEAR, true, 22)
  p.oathBtn:SetPoint("TOPRIGHT", 0, -24)
  p.oathLvl:SetPoint("RIGHT", p.oathBtn, "LEFT", -6, 0)
  p.oathText:SetPoint("RIGHT", p.oathLvl, "LEFT", -6, 0)
  p.oathBtn:SetScript("OnClick", function()
    P.Swear(V.lvl, p.oathText:GetText())
    p.oathText:SetText(""); p.oathText:ClearFocus()
  end)
  p.oathHint = W.Text(right, 10, "muted")
  p.oathHint:SetPoint("TOPLEFT", p.oathText, "BOTTOMLEFT", 0, -4); p.oathHint:SetPoint("RIGHT", 0, 0)
  p.oathHint:SetSpacing(2)
  p.oathBox = W.Box(right, 10, 5 * ROW + 10, "panel2")
  p.oathBox:SetPoint("TOPLEFT", p.oathHint, "BOTTOMLEFT", 0, -8); p.oathBox:SetPoint("RIGHT", 0, 0)
  p.oathRows = W.Pool(p.oathBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 6, 0); r.text:SetWordWrap(false)
    r.btn = W.Button(r, "", false, 18); r.btn:SetPoint("RIGHT", -4, 0)
    r.text:SetPoint("RIGHT", r.btn, "LEFT", -6, 0)
    return r
  end)
  p.oathEmpty = W.Text(p.oathBox, 10, "muted")
  p.oathEmpty:SetPoint("TOPLEFT", 8, -8); p.oathEmpty:SetPoint("RIGHT", -8, 0)
  p.oathEmpty:SetSpacing(2)

  p.seasonHead = UI.Section(right, L.PVP_SEASON_TITLE)
  p.seasonHead:SetPoint("TOPLEFT", p.oathBox, "BOTTOMLEFT", 0, -14)
  p.goalText = W.Text(right, 10, "text")
  p.goalText:SetPoint("TOPLEFT", p.seasonHead, "BOTTOMLEFT", 0, -8); p.goalText:SetPoint("RIGHT", 0, 0)
  p.goalBar = W.Bar(right, 8)
  p.goalBar:SetPoint("TOPLEFT", p.goalText, "BOTTOMLEFT", 0, -5); p.goalBar:SetPoint("RIGHT", 0, 0)
  p.podBox = W.Box(right, 10, 10, "panel2")
  p.podBox:SetPoint("TOPLEFT", p.goalBar, "BOTTOMLEFT", 0, -10); p.podBox:SetPoint("BOTTOMRIGHT", 0, 20)
  p.podRows = W.Pool(p.podBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(32)
    r.when = W.Text(r, 10, "title"); r.when:SetPoint("TOPLEFT", 6, -2)
    r.total = W.Text(r, 9, "muted"); r.total:SetPoint("TOPRIGHT", -6, -3); r.total:SetJustifyH("RIGHT")
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("TOPLEFT", 6, -16); r.text:SetPoint("RIGHT", -6, 0); r.text:SetWordWrap(false)
    return r
  end)
  p.podEmpty = W.Text(p.podBox, 10, "muted")
  p.podEmpty:SetPoint("TOPLEFT", 8, -8); p.podEmpty:SetPoint("RIGHT", -8, 0)
  p.podEmpty:SetSpacing(2)
  p.champ = W.Text(right, 10, "muted")
  p.champ:SetPoint("BOTTOMLEFT", 0, 2); p.champ:SetPoint("RIGHT", 0, 0)
end

local MEDAL = { "|cffffd100", "|cffc0c0c0", "|cffcd7f32" }

local function refresh(p)
  local th = T.Current()
  local muted = T.Hex(th.muted)
  local me = G.MyKey()
  local r = P.Rules()

  -- duels of honor
  p.makHead:SetText(T.Word("MAKGORA"))
  p.makHint:SetText(L.PVP_MAK_SAFE .. "\n" .. L.PVP_MAK_HINT:format(r.makgora, r.makgoraWitnesses))
  local list = P.ActiveMakgoras()
  for i, m in ipairs(list) do
    if i > 4 then break end
    local row = p.makRows:Get(i)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -5 - (i - 1) * ROW); row:SetPoint("RIGHT", p.makBox, "RIGHT", 0, 0)
    local st = P.MakState(m)
    local votes = 0
    for _ in pairs(m.wit or {}) do votes = votes + 1 end
    local info = (st == "open") and L.PVP_MAK_ST_OPEN or L.PVP_MAK_ST_FIGHT:format(votes, r.makgoraWitnesses)
    row.text:SetText(L.PVP_MAK_VS:format(G.Display(m.a), G.Display(m.b))
      .. (m.stake and U.Color(muted, " · " .. m.stake) or "") .. U.Color(muted, " · " .. info))
    row.b1:Hide(); row.b2:Hide()
    row.b1:SetEnabled(true); row.b2:SetEnabled(true)
    if st == "open" and m.b == me then
      W.SetLabel(row.b1, L.PVP_MAK_ACCEPT); row.b1:SetScript("OnClick", function() P.Answer(m.id, true) end); row.b1:Show()
      W.SetLabel(row.b2, L.PVP_MAK_DECLINE); row.b2:SetScript("OnClick", function() P.Answer(m.id, false) end); row.b2:Show()
    elseif m.a == me or m.b == me then
      -- own challenge (sent, or accepted and waiting for witnesses): take it back
      W.SetLabel(row.b2, L.PVP_MAK_CANCEL); row.b2:SetScript("OnClick", function() P.CancelChallenge(m.id) end); row.b2:Show()
    elseif st == "fight" and m.a ~= me and m.b ~= me then
      local mine = m.wit and m.wit[me]
      W.SetLabel(row.b1, L.PVP_MAK_WINS:format(G.Display(m.a)))
      row.b1:SetScript("OnClick", function() P.Witness(m.id, m.a) end); row.b1:Show(); row.b1:SetEnabled(mine ~= m.a)
      W.SetLabel(row.b2, L.PVP_MAK_WINS:format(G.Display(m.b)))
      row.b2:SetScript("OnClick", function() P.Witness(m.id, m.b) end); row.b2:Show(); row.b2:SetEnabled(mine ~= m.b)
    end
  end
  p.makRows:HideFrom(math.min(#list, 4) + 1)
  p.makEmpty:SetShown(#list == 0)
  p.makEmpty:SetText(L.PVP_MAK_EMPTY)
  p.makBtn:SetEnabled(core.Comm.CanSend())

  local res = Pts.Entries(function(e) return e.why == "makgora" end)
  local n = 0
  for _, e in ipairs(res) do
    n = n + 1
    if n > 10 then break end
    local row = p.resRows:Get(n)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -4 - (n - 1) * 18); row:SetPoint("RIGHT", p.resBox, "RIGHT", 0, 0)
    local txt = L.PVP_MAK_RESULT:format(G.Display(e.who), e.note and G.Display(e.note) or "?")
      .. (e.stake and U.Color(muted, " · " .. e.stake) or "")
    if e.reverted then txt = U.Color("ff808080", txt .. " · " .. L.PVP_REVERTED) end
    row.text:SetText(txt)
    row.when:SetText(date("%d.%m.", e.ts))
  end
  p.resRows:HideFrom(math.min(n, 10) + 1)
  p.resEmpty:SetShown(n == 0)
  local w, l = P.MakgoraRecord(me)
  p.record:SetText(L.PVP_MAK_RECORD:format(w, l))

  -- oaths
  p.oathHint:SetText(L.PVP_OATH_HINT:format(r.oathWitnesses, r.oathDays))
  p.oathLvl:Refresh()
  p.oathBtn:SetEnabled(core.Comm.CanSend())
  local oaths = P.OpenOaths()
  for i, o in ipairs(oaths) do
    if i > 5 then break end
    local row = p.oathRows:Get(i)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -5 - (i - 1) * ROW); row:SetPoint("RIGHT", p.oathBox, "RIGHT", 0, 0)
    local votes = 0
    for _ in pairs(o.wit or {}) do votes = votes + 1 end
    row.text:SetText(G.Display(o.by) .. U.Color(muted, " · " .. L["PVP_OATH_LVL" .. o.lvl] .. " · ") .. o.text
      .. U.Color(muted, " · " .. L.PVP_OATH_VOTES:format(votes, r.oathWitnesses)))
    if o.by == me then
      W.SetLabel(row.btn, L.PVP_OATH_WITHDRAW)
      row.btn:SetScript("OnClick", function() P.Withdraw(o.id) end)
      row.btn:SetEnabled(true)
    else
      W.SetLabel(row.btn, L.PVP_OATH_CONFIRM)
      row.btn:SetScript("OnClick", function() P.ConfirmOath(o.id) end)
      row.btn:SetEnabled(not (o.wit and o.wit[me]))
    end
  end
  p.oathRows:HideFrom(math.min(#oaths, 5) + 1)
  p.oathEmpty:SetShown(#oaths == 0)
  p.oathEmpty:SetText(L.PVP_OATH_EMPTY)

  -- season
  local sum, goal = P.SeasonProgress()
  p.goalText:SetText(L.PVP_SEASON_GOAL:format(sum, goal, U.FormatTime(Pts.SeasonEnd())))
  p.goalBar:SetValue(goal > 0 and math.min(1, sum / goal) or 0)
  local seasons = P.SeasonResults(3)
  local shown = 0
  for _, s in ipairs(seasons) do
    if s.top[1] then
      shown = shown + 1
      local row = p.podRows:Get(shown)
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -4 - (shown - 1) * 34); row:SetPoint("RIGHT", p.podBox, "RIGHT", 0, 0)
      row.when:SetText(date("%d.%m.%Y", s.start) .. " – " .. date("%d.%m.%Y", s.stop - 1))
      row.total:SetText(L.PVP_SEASON_TOTAL:format(s.total))
      local parts = {}
      for i = 1, 3 do
        local t = s.top[i]
        if t then parts[#parts + 1] = MEDAL[i] .. i .. ".|r " .. G.Display(t.key) .. U.Color(muted, " (" .. t.honor .. ")") end
      end
      row.text:SetText(table.concat(parts, "   "))
    end
  end
  p.podRows:HideFrom(shown + 1)
  p.podEmpty:SetShown(shown == 0)
  p.podEmpty:SetText(L.PVP_SEASON_NONE)
  local champ = seasons[1] and seasons[1].top[1]
  p.champ:SetText(champ and L.PVP_SEASON_CHAMP:format(G.Display(champ.key), T.Word("HONOR_CHAMPION")) or "")
end

UI.AddTab("pvphonor", {
  label = function() return L.TAB_PVPHONOR end,
  build = build,
  refresh = refresh,
})
