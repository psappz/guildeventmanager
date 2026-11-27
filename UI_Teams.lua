local ADDON, ns = ...
-- Teams tab of the event detail (0.9): events with group "teams" get the tabs
-- "Sign-ups" and "Teams". The teams tab spans the whole width:
--   leaders: bar (size, suggestions, random / balanced / by hand, + team,
--            announce), hint line, team cards (leader on top, gold) on the
--            left, a column on the right with "not assigned" over the full
--            height – it shares the column with the team standings of a
--            contest once there are scores.
--   members: before announcing a short note; then "you are in team n" and
--            the cards (own team framed gold), standings on the right.
-- Drag names onto a name (swap) or a card (move); or click two names, or a
-- name and a card; double-click makes the team leader.
local U, G, T, W = ns.U, ns.Guild, ns.Theme, ns.W
local L = ns.L
local TM = ns.Teams
local V = {}
ns.UITeams = V

local ROW_H, SIDE_W, GAP = 18, 150, 8

local function classHex(key)
  local r = G.roster[key]
  return ns.Struct and ns.Struct.ClassHex(r and r.class) or "ede3d4"
end

-- Drop target under the cursor while dragging (or with a picked name):
-- a name = swap, a team card = add, "not assigned" = take out
local function target(p, self)
  for _, pool in ipairs({ p.rows, p.unRows }) do
    for _, r in ipairs(pool.items) do
      if r:IsShown() and r ~= self and r.key ~= p.drag and r:IsMouseOver() then return "swap", r end
    end
  end
  for _, c in ipairs(p.cards.items) do
    if c:IsShown() and c:IsMouseOver() then return "add", c end
  end
  if p.un:IsShown() and p.un:IsMouseOver() then return "add", p.un end
end

-- highlight: gold frame around a card (added), orange frame and fill on a
-- name (replaced); the old colours come back when the target changes
local SWAP = { 1, 0.55, 0.2 }
local EVLEAD = { 0.45, 0.7, 1 }   -- event leadership: blue
local function unmark(p)
  local h = p.hl
  if not h then return end
  h.f:SetBackdropColor(unpack(h.bg)); h.f:SetBackdropBorderColor(unpack(h.bd))
  p.hl = nil
end
local function mark(p, kind, f)
  if p.hl and p.hl.f == f then return end
  unmark(p)
  if not f then return end
  local th = T.Current()
  p.hl = { f = f, bg = { f:GetBackdropColor() }, bd = { f:GetBackdropBorderColor() } }
  if kind == "swap" then
    f:SetBackdropColor(SWAP[1] * 0.35, SWAP[2] * 0.35, SWAP[3] * 0.35, 1); f:SetBackdropBorderColor(SWAP[1], SWAP[2], SWAP[3], 1)
  else
    f:SetBackdropColor(th.title[1] * 0.18, th.title[2] * 0.18, th.title[3] * 0.18, 1); f:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1)
  end
end
local function hint(p, kind, f)
  if not kind then return "" end
  if kind == "swap" then return "|cffff8c33" .. L.TM_DROP_SWAP:format(G.Display(f.key)) .. "|r" end
  if f.team == 0 then return L.TM_DROP_OUT end
  local tl = TM.Get(p.ev)
  return L.TM_DROP_ADD:format(tl and tl.list[f.team] and TM.Name(tl.list[f.team], f.team) or f.team)
end
V.Target = target

local function makeRow(p, parent)
  local th = T.Current()
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetHeight(ROW_H - 2)
  W.Paint(b, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
  b.t = W.Text(b, 10, "text"); b.t:SetPoint("LEFT", 4, 0); b.t:SetPoint("RIGHT", -4, 0); b.t:SetJustifyH("LEFT"); b.t:SetWordWrap(false)
  b:RegisterForDrag("LeftButton")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnEnter", function(self) if p.pick and p.pick ~= self.key and not p.drag then mark(p, "swap", self); p.info2 = hint(p, "swap", self); V.Hint() end end)
  b:SetScript("OnLeave", function() if p.pick and not p.drag then unmark(p); p.info2 = nil; V.Hint() end end)
  b:SetScript("OnClick", function(self, button)
    if not TM.CanEdit(p.ev) then return end
    if button == "RightButton" then V.NameMenu(self); return end
    unmark(p); p.info2 = nil
    local now = GetTime and GetTime() or 0
    if self.last and now - self.last < 0.35 then
      -- double click: team leader
      if self.team and self.team > 0 then TM.SetLeader(p.ev, self.key) end
      p.pick, self.last = nil, nil
    elseif p.pick and p.pick ~= self.key then
      TM.Swap(p.ev, p.pick, self.key); p.pick = nil; self.last = nil
    else
      p.pick = (p.pick == self.key) and nil or self.key
      self.last = now
    end
    V.Refresh()
  end)
  b:SetScript("OnDragStart", function(self)
    if not TM.CanEdit(p.ev) then return end
    p.drag = self.key
    local gh = V.ghost
    if not gh then
      gh = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
      gh:SetSize(150, 34); gh:SetFrameStrata("TOOLTIP")
      W.Paint(gh, th.panel2, th.title)
      gh.t = W.Text(gh, 10, "title"); gh.t:SetPoint("TOPLEFT", 6, -4); gh.t:SetPoint("RIGHT", -6, 0); gh.t:SetJustifyH("LEFT")
      gh.h = W.Text(gh, 10, "muted"); gh.h:SetPoint("TOPLEFT", gh.t, "BOTTOMLEFT", 0, -3); gh.h:SetPoint("RIGHT", -6, 0); gh.h:SetJustifyH("LEFT")
      gh:SetScript("OnUpdate", function(g)
        local cx, cy = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale() or 1
        g:ClearAllPoints(); g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / sc + 14, cy / sc - 10)
        local pp = V.panel
        if pp and pp.drag then
          local kind, f = target(pp, g.src)
          mark(pp, kind, f)
          g.h:SetText(hint(pp, kind, f))
          local w = math.max(g.t:GetStringWidth(), g.h:GetStringWidth()) + 14
          g:SetWidth(math.max(90, w))
        end
      end)
      V.ghost = gh
    end
    gh.src = self
    gh.t:SetText(G.Display(self.key)); gh.h:SetText(""); gh:Show()
  end)
  b:SetScript("OnDragStop", function(self)
    if V.ghost then V.ghost:Hide() end
    local key = p.drag
    local kind, f = target(p, self)
    unmark(p)
    p.drag = nil
    if not key or not p.ev or not kind then return end
    if kind == "swap" then TM.Swap(p.ev, key, f.key) else TM.Move(p.ev, key, f.team) end
    V.Refresh()
  end)
  return b
end

local function makeCard(p, parent, dashed)
  local th = T.Current()
  local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
  W.Paint(c, th.panel2, th.line)
  c.title = W.Text(c, 11, dashed and "muted" or "title"); c.title:SetPoint("TOPLEFT", 6, -5); c.title:SetPoint("RIGHT", -40, 0)
  c.title:SetJustifyH("LEFT"); c.title:SetWordWrap(false)
  c.val = W.Text(c, 11, "title"); c.val:SetPoint("TOPRIGHT", -6, -5)
  if not dashed then
    -- team name: click = rename / delete (leaders); with a picked name it is part of the card
    c.head = CreateFrame("Button", nil, c)
    c.head:SetPoint("TOPLEFT", 0, 0); c.head:SetPoint("RIGHT", 0, 0); c.head:SetHeight(20)
    c.head:SetScript("OnClick", function()
      if p.pick then c:GetScript("OnClick")(c) return end
      if not TM.CanEdit(p.ev) then return end
      V.TeamMenu(c)
    end)
    c.head:SetScript("OnEnter", function(self)
      if p.pick then c:GetScript("OnEnter")(c) return end
      if not TM.CanEdit(p.ev) then return end
      c.title:SetTextColor(1, 1, 1)
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.TM_HEAD_TIP, 1, 1, 1); GameTooltip:Show()
    end)
    c.head:SetScript("OnLeave", function()
      GameTooltip:Hide()
      W.Color(c.title, "title")
      c:GetScript("OnLeave")(c)
    end)
    -- empty last line: drop here to add
    c.drop = CreateFrame("Frame", nil, c, "BackdropTemplate")
    c.drop:SetHeight(ROW_H - 2)
    W.Paint(c.drop, { 0, 0, 0, 0 }, { th.line[1], th.line[2], th.line[3], 0.6 })
    c.drop.t = W.Text(c.drop, 10, "muted"); c.drop.t:SetPoint("CENTER"); c.drop.t:SetText(L.TM_DROP_HERE)
  end
  c:SetScript("OnClick", function(self)
    if p.pick and p.ev then unmark(p); p.info2 = nil; TM.Move(p.ev, p.pick, self.team); p.pick = nil; V.Refresh() end
  end)
  c:SetScript("OnEnter", function(self) if p.pick and not p.drag then mark(p, "add", self); p.info2 = hint(p, "add", self); V.Hint() end end)
  c:SetScript("OnLeave", function(self)
    if p.pick and not p.drag and p.hl and p.hl.f == self and not self:IsMouseOver() then unmark(p); p.info2 = nil; V.Hint() end
  end)
  return c
end

-- right click on a name: tank icon on / off, team leader
function V.NameMenu(row)
  local p = V.panel
  local e, key = p.ev, row.key
  W.OpenMenu(row, function(_, root)
    root:CreateTitle(G.Display(key))
    local tank = TM.IsTank(e, key)
    root:CreateButton(tank and L.TM_TANK_OFF or L.TM_TANK_ON, function() TM.SetTank(e, key, not tank); V.Refresh() end)
    if row.team and row.team > 0 then
      root:CreateButton(L.TM_MAKE_LEAD, function() TM.SetLeader(e, key); V.Refresh() end)
    end
  end)
end

-- click on a team name: rename or delete
function V.TeamMenu(card)
  local p = V.panel
  local e, i = p.ev, card.team
  local t = TM.Get(e)
  local team = t and t.list[i]
  if not team then return end
  W.OpenMenu(card.head, function(_, root)
    root:CreateTitle(TM.Name(team, i))
    root:CreateButton(L.TM_RENAME, function()
      W.Dialog({ text = L.TM_RENAME_Q:format(L.TM_TEAM_N:format(team.id or i)), edit = true, editText = team.name or "",
        accept = L.TM_RENAME, onAccept = function(text) TM.Rename(e, i, text); V.Refresh() end })
    end)
    root:CreateButton(L.TM_DELETE, function()
      if #team.m == 0 then TM.Delete(e, i); V.Refresh(); return end
      W.Dialog({ text = L.TM_DELETE_Q:format(TM.Name(team, i), #team.m), accept = L.TM_DELETE,
        onAccept = function() TM.Delete(e, i); V.Refresh() end })
    end)
  end)
end

-- builds the tab into a frame of the event detail
function V.Build(p)
  local th = T.Current()
  V.panel = p
  -- leader bar
  p.bar = CreateFrame("Frame", nil, p)
  p.bar:SetPoint("TOPLEFT", 0, 0); p.bar:SetPoint("RIGHT", 0, 0); p.bar:SetHeight(22)
  p.sizeL = W.Text(p.bar, 10, "muted"); p.sizeL:SetPoint("LEFT", 0, 0); p.sizeL:SetText(L.TM_SIZE)
  p.size = W.Edit(p.bar, 34, 20); p.size:SetPoint("LEFT", p.sizeL, "RIGHT", 6, 0); p.size:SetNumeric(true)
  p.size:SetScript("OnEnterPressed", function(self) self:ClearFocus(); V.Refresh() end)
  p.sugg = W.Pool(p.bar, function(parent)
    local b = W.Button(parent, "", false, 20)
    b:SetScript("OnClick", function(self) p.size:SetText(tostring(self.size)); V.Refresh() end)
    return b
  end)
  local function draw(mode)
    local e = p.ev
    if not e then return end
    local s = tonumber(p.size:GetText()) or (TM.Get(e) and TM.Get(e).size) or 5
    TM.Set(e, TM.Draw(e, s, mode)); p.pick = nil
    V.Refresh()
  end
  p.rand = W.Button(p.bar, L.TM_RANDOM, false, 20); p.rand:SetScript("OnClick", function() draw("random") end)
  p.bal = W.Button(p.bar, L.TM_BALANCED, false, 20); p.bal:SetScript("OnClick", function() draw("balanced") end)
  p.hand = W.Button(p.bar, L.TM_BYHAND, false, 20); p.hand:SetScript("OnClick", function() draw("manual") end)
  p.add = W.Button(p.bar, L.TM_ADD, false, 20); p.add:SetScript("OnClick", function() if p.ev then TM.AddTeam(p.ev); V.Refresh() end end)
  for _, b in ipairs({ p.rand, p.bal, p.hand, p.add }) do W.SetLabel(b, b.label:GetText()) end
  p.withLead = W.Check(p, L.TM_WITH_LEAD, function(_, on)
    ns.db.teamsWithLead = on and true or false
    local e = p.ev
    local tl = e and TM.Get(e)
    if tl then local c = U.Copy(tl); c.withLead = on and true or false; TM.Set(e, c) end
    V.Refresh()
  end)
  p.needTank = W.Check(p, L.TM_NEED_TANK, function(_, on)
    local e = p.ev
    local c = U.Copy(TM.Get(e) or { size = tonumber(p.size:GetText()) or 5, list = {} })
    c.needTank = on and true or false
    TM.Set(e, c)
    V.Refresh()
  end)
  p.needTank:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(L.TM_NEED_TANK, 1, 0.82, 0)
    GameTooltip:AddLine(L.TM_NEED_TANK_TIP, 1, 1, 1, true); GameTooltip:Show()
  end)
  p.needTank:HookScript("OnLeave", function() GameTooltip:Hide() end)
  p.withLead:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(L.TM_WITH_LEAD, 1, 0.82, 0)
    GameTooltip:AddLine(L.TM_WITH_LEAD_TIP, 1, 1, 1, true); GameTooltip:Show()
  end)
  p.withLead:HookScript("OnLeave", function() GameTooltip:Hide() end)
  p.pub = W.Button(p.bar, L.TM_PUBLISH, true, 20); W.SetLabel(p.pub, L.TM_PUBLISH)
  p.pub:SetPoint("RIGHT", 0, 0)
  p.pub:SetScript("OnClick", function() if p.ev then TM.Publish(p.ev); V.Refresh() end end)
  -- hint line (leaders) / own team (members)
  p.info = W.Text(p, 10, "muted"); p.info:SetJustifyH("LEFT")
  p.mine = W.Box(p, 10, 24, "panel2")
  p.mine:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1)
  p.mineT = W.Text(p.mine, 11, "title"); p.mineT:SetPoint("LEFT", 8, 0); p.mineT:SetPoint("RIGHT", -8, 0); p.mineT:SetJustifyH("LEFT")
  -- body: cards left, side column right
  p.body = CreateFrame("Frame", nil, p)
  p.scroll = W.Scroll(p.body)
  p.side = CreateFrame("Frame", nil, p.body)
  p.side:SetPoint("TOPRIGHT", 0, 0); p.side:SetPoint("BOTTOMRIGHT", 0, 0); p.side:SetWidth(SIDE_W)
  p.un = makeCard(p, p.side, true)
  p.un.team = 0
  p.unScroll = W.Scroll(p.un)
  p.unScroll:SetPoint("TOPLEFT", 4, -22); p.unScroll:SetPoint("BOTTOMRIGHT", -4, 4)
  p.stand = W.Box(p.side, 10, 10, "panel2")
  p.standTitle = W.Text(p.stand, 11, "title"); p.standTitle:SetPoint("TOPLEFT", 6, -5); p.standTitle:SetText(L.TM_STANDINGS)
  p.standText = W.Text(p.stand, 10, "text"); p.standText:SetPoint("TOPLEFT", 6, -22); p.standText:SetPoint("RIGHT", -6, 0)
  p.standText:SetJustifyH("LEFT"); p.standText:SetSpacing(3)
  p.cards = W.Pool(p.scroll.content, function(parent) return makeCard(p, parent) end)
  p.rows = W.Pool(p.scroll.content, function(parent) return makeRow(p, parent) end)
  p.unRows = W.Pool(p.unScroll.content, function(parent) return makeRow(p, parent) end)
  p:SetScript("OnSizeChanged", function() V.Refresh() end)
  ns.On("TEAMS_CHANGED", function() V.Refresh() end)
  ns.On("CONTEST_SCORE", function(e) if p.ev and e and e.id == p.ev.id then V.Refresh() end end)
end

-- hint line: with a picked name what a click would do
function V.Hint()
  local p = V.panel
  if not p or not p.infoBase then return end
  local extra = ""
  if p.pick then extra = "   |cffffffff" .. L.TM_PICKED:format(G.Display(p.pick)) .. "|r" .. (p.info2 and p.info2 ~= "" and ("   " .. p.info2) or "") end
  p.info:SetText(p.infoBase .. extra)
end

-- shows the event in the tab
function V.Attach(p, e)
  if not (p.ev and e and p.ev.id == e.id) then p.pick = nil; p.size:SetText("") end
  p.ev = e
  V.Refresh()
end

local function fillRow(p, b, key, team, lead, e)
  local th = T.Current()
  b.key, b.team = key, team
  local ev = TM.IsEventLead(e, key)
  local tag = ""
  if ev then tag = "  |cff73b3ff" .. ((team == 0) and L.TM_REFEREE or L.TM_EVLEAD) .. "|r" end
  local icons = (TM.IsTank(e, key) and (" " .. W.InlineIcon("role_tank", 11)) or "") .. (TM.IsHealer(e, key) and (" " .. W.InlineIcon("role_heal", 11)) or "")
  b.t:SetText("|cff" .. classHex(key) .. G.Display(key) .. "|r" .. icons .. tag)
  if p.pick == key then b:SetBackdropBorderColor(1, 1, 1, 1); b:SetBackdropColor(1, 1, 1, 0.08)
  elseif lead then b:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1); b:SetBackdropColor(th.title[1] * 0.25, th.title[2] * 0.25, th.title[3] * 0.25, 1)
  elseif ev then b:SetBackdropBorderColor(EVLEAD[1], EVLEAD[2], EVLEAD[3], 1); b:SetBackdropColor(EVLEAD[1] * 0.2, EVLEAD[2] * 0.2, EVLEAD[3] * 0.2, 1)
  else b:SetBackdropBorderColor(0, 0, 0, 0); b:SetBackdropColor(0, 0, 0, 0) end
  b:Show()
end

function V.Refresh()
  local p = V.panel
  if not p or not p:IsShown() or not p.ev then return end
  local e = ns.Events.Get(p.ev.id) or p.ev
  p.ev = e
  local th = T.Current()
  local can = TM.CanEdit(e)
  local t = TM.Get(e)
  local players = TM.DrawPlayers(e, TM.WithLead(e, t))
  if p.pick and not can then p.pick = nil end
  unmark(p)
  -- bar
  p.bar:SetShown(can)
  local y = 0
  if can then
    if not p.size:HasFocus() and (p.size:GetText() or "") == "" then p.size:SetText(tostring((t and t.size) or 5)) end
    local x = p.size
    local sug = TM.Suggest(#players)
    for i, s in ipairs(sug) do
      local b = p.sugg:Get(i)
      b.size = s.size
      W.SetLabel(b, L.TM_SUGG:format(s.count, s.size))
      b:ClearAllPoints(); b:SetPoint("LEFT", x, "RIGHT", i == 1 and 10 or 4, 0); b:Show()
      x = b
    end
    p.sugg:HideFrom(#sug + 1)
    p.rand:ClearAllPoints(); p.rand:SetPoint("LEFT", x, "RIGHT", 12, 0)
    p.bal:ClearAllPoints(); p.bal:SetPoint("LEFT", p.rand, "RIGHT", 4, 0)
    p.hand:ClearAllPoints(); p.hand:SetPoint("LEFT", p.bal, "RIGHT", 4, 0)
    p.add:ClearAllPoints(); p.add:SetPoint("LEFT", p.hand, "RIGHT", 12, 0)
    p.withLead:SetChecked(TM.WithLead(e, t))
    y = 28
  end
  -- hint / own team
  p.info:ClearAllPoints(); p.mine:ClearAllPoints()
  local show = can or (t and t.pub)
  if can then
    local sizes = TM.Split(#players, tonumber(p.size:GetText()) or 5)
    local parts = {}
    for _, n in ipairs(sizes) do parts[#parts + 1] = tostring(n) end
    p.infoBase = L.TM_INFO:format(#players, #sizes, table.concat(parts, "/"))
      .. ((t and t.pub) and ("   " .. U.Color(T.Hex(th.title), L.TM_IS_PUBLIC)) or "")
    V.Hint()
    -- "include event lead" right of the hint line
    p.withLead:ClearAllPoints(); p.withLead:SetPoint("TOPRIGHT", p, "TOPRIGHT", -(p.withLead.text:GetStringWidth() or 100) - 8, -y + 2)
    p.withLead:Show()
    p.needTank:SetChecked(TM.NeedTank(e, t))
    p.needTank:ClearAllPoints(); p.needTank:SetPoint("RIGHT", p.withLead, "LEFT", -(p.needTank.text:GetStringWidth() or 90) - 18, 0)
    p.needTank:Show()
    p.info:SetPoint("TOPLEFT", 0, -y); p.info:SetPoint("RIGHT", p.needTank, "LEFT", -12, 0); p.info:Show()
    p.mine:Hide()
    y = y + 22
  elseif not show then
    p.withLead:Hide(); p.needTank:Hide()
    p.info:SetText(L.TM_NOT_YET); p.info:SetPoint("TOPLEFT", 0, -6); p.info:SetPoint("RIGHT", 0, 0); p.info:Show()
    p.mine:Hide(); p.body:Hide()
    return
  else
    p.info:Hide(); p.withLead:Hide(); p.needTank:Hide()
    local i, team = TM.Of(e, G.MyKey())
    p.mineT:SetText(i and L.TM_MINE:format(TM.Name(team, i), team.lead and G.Display(team.lead) or "?") or L.TM_NONE_MINE)
    p.mine:SetPoint("TOPLEFT", 0, 0); p.mine:SetPoint("RIGHT", 0, 0); p.mine:Show()
    y = 32
  end
  -- body
  p.body:ClearAllPoints(); p.body:SetPoint("TOPLEFT", 0, -y); p.body:SetPoint("BOTTOMRIGHT", 0, 0); p.body:Show()
  local stand = (ns.Contest and ns.Contest.Is(e) and t) and TM.Standings(e) or {}
  local hasScore = false
  for _, s in ipairs(stand) do if s.value ~= 0 then hasScore = true end end
  local val = {}
  for _, s in ipairs(stand) do val[s.team] = s.value end
  local side = can or hasScore
  p.side:SetShown(side and true or false)
  p.scroll:ClearAllPoints(); p.scroll:SetPoint("TOPLEFT", 0, 0); p.scroll:SetPoint("BOTTOMLEFT", 0, 0)
  if side then p.scroll:SetPoint("RIGHT", p.side, "LEFT", -GAP, 0) else p.scroll:SetPoint("RIGHT", 0, 0) end
  -- side column: "not assigned" over the full height, shared with the standings
  local h = math.max(60, (p:GetHeight() or 300) - y)
  p.un:ClearAllPoints(); p.stand:ClearAllPoints()
  if can then
    local un = TM.Unassigned(e)
    p.un.title:SetText(L.TM_UNASSIGNED .. " (" .. #un .. ")"); p.un.val:SetText("")
    p.un:SetPoint("TOPLEFT", 0, 0); p.un:SetPoint("RIGHT", 0, 0)
    p.un:SetHeight(hasScore and math.floor((h - GAP) / 2) or h)
    p.un:Show()
    for i, k in ipairs(un) do
      local b = p.unRows:Get(i)
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); b:SetWidth(SIDE_W - 12)
      fillRow(p, b, k, 0, false, e)
    end
    p.unRows:HideFrom(#un + 1)
    p.unScroll:SetContentHeight(#un * ROW_H)
  else
    p.un:Hide()
  end
  if hasScore then
    local lines = {}
    for _, s in ipairs(stand) do lines[#lines + 1] = s.place .. ".  " .. s.name .. "  " .. U.Color(T.Hex(th.title), s.value) end
    p.standText:SetText(table.concat(lines, "\n"))
    if can then p.stand:SetPoint("TOPLEFT", p.un, "BOTTOMLEFT", 0, -GAP) else p.stand:SetPoint("TOPLEFT", 0, 0) end
    p.stand:SetPoint("BOTTOMRIGHT", 0, 0)
    p.stand:Show()
  else
    p.stand:Hide()
  end
  -- team cards: up to four per row, each row below the tallest card before
  local width = (p:GetWidth() or 680) - (side and (SIDE_W + GAP) or 0) - 14
  local perRow = math.max(1, math.min(4, math.floor((width + GAP) / (120 + GAP))))
  local cw = math.floor((width - (perRow - 1) * GAP) / perRow)
  local list = (show and t and t.list) or {}
  local myTeam = TM.Of(e, G.MyKey())
  local ni, rowTop, rowH = 0, 0, 0
  for i, team in ipairs(list) do
    local col = (i - 1) % perRow
    if col == 0 and i > 1 then rowTop = rowTop + rowH + GAP; rowH = 0 end
    local card = p.cards:Get(i)
    card.team = i
    local nRows = #team.m + (can and 1 or 0)
    local ch = 24 + math.max(1, nRows) * ROW_H + 6
    rowH = math.max(rowH, ch)
    card:ClearAllPoints(); card:SetPoint("TOPLEFT", col * (cw + GAP), -rowTop); card:SetSize(cw, ch)
    local noTank = false
    if TM.NeedTank(e, t) then
      noTank = true
      for _, k in ipairs(team.m) do if TM.IsTank(e, k) then noTank = false end end
    end
    card.title:SetText(TM.Name(team, i) .. "  |cff9a8a7a(" .. #team.m .. ")|r" .. (noTank and ("  |cffff805c" .. L.TM_NO_TANK .. "|r") or ""))
    card.head:SetShown(true)
    card.drop:SetShown(can and #team.m < TM.MAX)
    if can then
      card.drop:ClearAllPoints(); card.drop:SetPoint("TOPLEFT", 4, -22 - #team.m * ROW_H); card.drop:SetPoint("RIGHT", -4, 0)
    end
    card.val:SetText(hasScore and tostring(val[i] or 0) or "")
    local bd = (myTeam == i) and th.title or th.line
    card:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
    card:Show()
    -- the team leader always on top
    local shown = {}
    if team.lead then for _, k in ipairs(team.m) do if k == team.lead then shown[1] = k end end end
    for _, k in ipairs(team.m) do if k ~= shown[1] then shown[#shown + 1] = k end end
    for j, key in ipairs(shown) do
      ni = ni + 1
      local b = p.rows:Get(ni)
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -22 - (j - 1) * ROW_H); b:SetWidth(cw - 8)
      b:SetFrameLevel(card:GetFrameLevel() + 2)
      fillRow(p, b, key, i, team.lead == key, e)
    end
  end
  p.cards:HideFrom(#list + 1)
  p.rows:HideFrom(ni + 1)
  p.scroll:SetContentHeight(rowTop + rowH)
end

-- opens the event detail on the teams tab (API.ShowTeams, /gem testteams)
function V.Show(e)
  if not e or not ns.EventsUI then return end
  ns.EventsUI.OpenDetail(e, "teams")
end
