local ADDON, P = ...
-- "Bounties" tab: put honor on the head of an enemy player, see open bounties,
-- the most wanted enemies and who collected what.
local core = P.core
if not core then return end
local U, G, T, W, UI = core.U, core.Guild, core.Theme, core.W, core.UI
local L = P.L

local ROW = 24
local DAY = 86400

local function build(p)
  ---------------------------------------------------------------- left: set a bounty, open bounties
  local left = CreateFrame("Frame", nil, p)
  left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -12, 0)
  p.head = UI.Section(left, L.PVP_BNT_TITLE)
  p.head:SetPoint("TOPLEFT", 0, 0)

  p.name = W.Edit(left, 10, 22)
  p.name:SetPoint("TOPLEFT", 0, -38)
  p.name:SetMaxLetters(48)
  p.take = W.Button(left, L.PVP_BNT_TAKE, false, 22)
  p.amt = W.Edit(left, 56, 22)
  p.amt:SetMaxLetters(3)
  if p.amt.SetNumeric then p.amt:SetNumeric(true) end
  p.btn = W.Button(left, L.PVP_BNT_POST, true, 22)
  p.btn:SetPoint("TOPRIGHT", 0, -38)
  p.amt:SetPoint("RIGHT", p.btn, "LEFT", -6, 0)
  p.take:SetPoint("RIGHT", p.amt, "LEFT", -6, 0)
  p.name:SetPoint("RIGHT", p.take, "LEFT", -6, 0)
  local function label(edit, text)
    local t = W.Text(left, 9, "muted")
    t:SetPoint("BOTTOMLEFT", edit, "TOPLEFT", 2, 2)
    t:SetText(text)
    return t
  end
  label(p.name, L.PVP_BNT_L_NAME)
  label(p.amt, L.PVP_BNT_L_AMT)
  -- take over the current target (an enemy player)
  p.take:SetScript("OnClick", function()
    local ok, n, r = pcall(UnitName, "target")
    if ok and n and not (issecretvalue and issecretvalue(n)) and UnitIsPlayer and UnitIsPlayer("target") then
      if r and r ~= "" and not (issecretvalue and issecretvalue(r)) then n = n .. " " .. r end
      p.name:SetText(n)
    else
      U.Print(L.PVP_BNT_NOTARGET)
    end
  end)
  p.btn:SetScript("OnClick", function()
    local name, amt = p.name:GetText(), tonumber(p.amt:GetText())
    if not amt then U.Print(L.PVP_BNT_RANGE:format(P.BountyLimits())); return end
    W.Dialog({ text = L.PVP_BNT_CONFIRM_Q:format(amt, name), accept = L.PVP_BNT_POST, onAccept = function()
      if P.PostBounty(name, amt) then p.name:SetText(""); p.amt:SetText("") end
      p.name:ClearFocus(); p.amt:ClearFocus()
    end })
  end)

  p.hint = W.Text(left, 10, "muted")
  p.hint:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -4); p.hint:SetPoint("RIGHT", 0, 0)
  p.hint:SetSpacing(2)

  p.openHead = UI.Section(left, L.PVP_BNT_OPEN)
  p.openHead:SetPoint("TOPLEFT", p.hint, "BOTTOMLEFT", 0, -12)
  p.openBox = W.Box(left, 10, 10, "panel2")
  p.openBox:SetPoint("TOPLEFT", p.openHead, "BOTTOMLEFT", 0, -8); p.openBox:SetPoint("BOTTOMRIGHT", 0, 0)
  p.openRows = W.Pool(p.openBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW)
    r.amt = W.Text(r, 12, "accent"); r.amt:SetPoint("LEFT", 6, 0); r.amt:SetWidth(40); r.amt:SetJustifyH("RIGHT")
    r.b1 = W.Button(r, "", false, 18); r.b1:SetPoint("RIGHT", -4, 0)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", r.amt, "RIGHT", 8, 0); r.text:SetPoint("RIGHT", r.b1, "LEFT", -6, 0)
    r.text:SetWordWrap(false)
    return r
  end)
  p.openEmpty = W.Text(p.openBox, 10, "muted")
  p.openEmpty:SetPoint("TOPLEFT", 8, -8); p.openEmpty:SetPoint("RIGHT", -8, 0)
  p.openEmpty:SetSpacing(2)
  p.openEmpty:SetText(L.PVP_BNT_OPEN_NONE)

  ---------------------------------------------------------------- right: most wanted, collected
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", p, "TOP", 12, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
  p.wantHead = UI.Section(right, L.PVP_BNT_WANTED)
  p.wantHead:SetPoint("TOPLEFT", 0, 0)
  p.wantBox = W.Box(right, 10, 5 * 20 + 10, "panel2")
  p.wantBox:SetPoint("TOPLEFT", p.wantHead, "BOTTOMLEFT", 0, -8); p.wantBox:SetPoint("RIGHT", 0, 0)
  p.wantRows = W.Pool(p.wantBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(20)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -50, 0); r.text:SetWordWrap(false)
    r.sum = W.Text(r, 10, "accent"); r.sum:SetPoint("RIGHT", -6, 0); r.sum:SetJustifyH("RIGHT")
    return r
  end)
  p.wantEmpty = W.Text(p.wantBox, 10, "muted")
  p.wantEmpty:SetPoint("TOPLEFT", 8, -8); p.wantEmpty:SetPoint("RIGHT", -8, 0)
  p.wantEmpty:SetText(L.PVP_BNT_OPEN_NONE)

  p.wonHead = UI.Section(right, L.PVP_BNT_DONE)
  p.wonHead:SetPoint("TOPLEFT", p.wantBox, "BOTTOMLEFT", 0, -14)
  p.wonBox = W.Box(right, 10, 10, "panel2")
  p.wonBox:SetPoint("TOPLEFT", p.wonHead, "BOTTOMLEFT", 0, -8); p.wonBox:SetPoint("BOTTOMRIGHT", 0, 0)
  p.wonRows = W.Pool(p.wonBox, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(18)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -50, 0); r.text:SetWordWrap(false)
    r.when = W.Text(r, 9, "muted"); r.when:SetPoint("RIGHT", -6, 0); r.when:SetJustifyH("RIGHT")
    return r
  end)
  p.wonEmpty = W.Text(p.wonBox, 10, "muted")
  p.wonEmpty:SetPoint("TOPLEFT", 8, -8); p.wonEmpty:SetPoint("RIGHT", -8, 0)
  p.wonEmpty:SetText(L.PVP_BNT_DONE_NONE)
end

local function refresh(p)
  local th = T.Current()
  local muted = T.Hex(th.muted)
  local me = G.MyKey()
  local r = P.Rules()
  local days = math.max(1, tonumber(r.bountyDays) or 7)

  local bmin, bmax = P.BountyLimits()
  p.hint:SetText(L.PVP_BNT_HINT:format(bmin, bmax, days)
    .. "\n" .. L.PVP_BNT_BALANCE:format(P.MyHonorBalance()))

  -- open bounties
  local open = P.OpenBounties()
  local h = p.openBox:GetHeight() or 0
  local fit = math.max(1, math.floor((h - 10) / ROW))
  local n = 0
  for _, b in ipairs(open) do
    if n >= fit then break end
    n = n + 1
    local row = p.openRows:Get(n)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -5 - (n - 1) * ROW); row:SetPoint("RIGHT", p.openBox, "RIGHT", 0, 0)
    row.amt:SetText(b.amt)
    local left = math.max(0, math.ceil((b.ts + days * DAY - U.Now()) / DAY))
    row.text:SetText(b.target .. U.Color(muted, " · " .. L.PVP_BNT_BY:format(G.Display(b.by)) .. " · " .. L.PVP_BNT_LEFT:format(left)))
    if b.by == me then
      W.SetLabel(row.b1, L.PVP_BNT_CANCEL)
      row.b1:SetScript("OnClick", function()
        W.Dialog({ text = L.PVP_BNT_CANCEL_Q:format(b.target, b.amt), accept = L.PVP_BNT_CANCEL, onAccept = function() P.CancelBounty(b.id) end })
      end)
      row.b1:Show()
    else
      row.b1:Hide()
    end
  end
  p.openRows:HideFrom(n + 1)
  p.openEmpty:SetShown(n == 0)

  -- most wanted: open bounties summed per enemy
  local sums, order = {}, {}
  for _, b in ipairs(open) do
    local s = sums[b.tk]
    if not s then s = { name = b.target, sum = 0, n = 0 }; sums[b.tk] = s; order[#order + 1] = s end
    s.sum = s.sum + b.amt; s.n = s.n + 1
  end
  table.sort(order, function(x, y) return x.sum > y.sum end)
  local w = 0
  for i, s in ipairs(order) do
    if i > 5 then break end
    w = w + 1
    local row = p.wantRows:Get(w)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -5 - (w - 1) * 20); row:SetPoint("RIGHT", p.wantBox, "RIGHT", 0, 0)
    row.text:SetText(i .. ". " .. s.name .. (s.n > 1 and U.Color(muted, " · " .. L.PVP_BNT_COUNT:format(s.n)) or ""))
    row.sum:SetText(s.sum)
  end
  p.wantRows:HideFrom(w + 1)
  p.wantEmpty:SetShown(w == 0)

  -- collected
  local won = P.WonBounties()
  local wh = p.wonBox:GetHeight() or 0
  local wfit = math.max(1, math.floor((wh - 10) / 18))
  local k = 0
  for _, b in ipairs(won) do
    if k >= wfit then break end
    k = k + 1
    local row = p.wonRows:Get(k)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -5 - (k - 1) * 18); row:SetPoint("RIGHT", p.wonBox, "RIGHT", 0, 0)
    row.text:SetText(L.PVP_BNT_WON_LINE:format(G.Display(b.w), b.target, b.amt) .. U.Color(muted, " · " .. L.PVP_BNT_BY:format(G.Display(b.by))))
    row.when:SetText(date("%d.%m.", b.wts or b.ts))
  end
  p.wonRows:HideFrom(k + 1)
  p.wonEmpty:SetShown(k == 0)
end

UI.AddTab("pvpbounty", {
  parent = "pvp",
  label = function() return L.TAB_PVPBOUNTY end,
  build = build,
  refresh = refresh,
})
