local ADDON, P = ...
-- "PvP Kills" tab: honorable kills of the guild in the open world and in
-- battlegrounds (season / total), plus the game's own numbers per member:
-- lifetime honorable and dishonorable kills, today, this week, PvP rank.
local core = P.core
if not core then return end
local U, G, T, W, UI = core.U, core.Guild, core.Theme, core.W, core.UI
local L = P.L
local V = { sort = "stot", desc = true }

local ROW_H = 20
-- id, label key, width (0 = rest), group, sort value
local COLS = {
  { id = "#", w = 34 },
  { id = "name", key = "PVPK_COL_NAME", w = 0, sort = function(r) return G.Display(r.key):lower() end },
  { id = "rank", key = "PVPK_COL_RANK", w = 130, sort = function(r) return r.s.rank or 0 end },
  { id = "sow", key = "PVPK_COL_OW", w = 58, group = "PVPK_GRP_SEASON", sort = function(r) return r.sow end },
  { id = "sbg", key = "PVPK_COL_BG", w = 58, group = "PVPK_GRP_SEASON", sort = function(r) return r.sbg end },
  { id = "ow", key = "PVPK_COL_OW", w = 58, group = "PVPK_GRP_TOTAL", sort = function(r) return r.s.ow or 0 end },
  { id = "bg", key = "PVPK_COL_BG", w = 58, group = "PVPK_GRP_TOTAL", sort = function(r) return r.s.bg or 0 end },
  { id = "life", key = "PVPK_COL_HK", w = 70, group = "PVPK_GRP_GAME", sort = function(r) return r.s.life or -1 end },
  { id = "dk", key = "PVPK_COL_DK", w = 62, group = "PVPK_GRP_GAME", sort = function(r) return r.s.dk or -1 end },
  { id = "today", key = "PVPK_COL_TODAY", w = 50, group = "PVPK_GRP_GAME", sort = function(r) return r.s.today or -1 end },
  { id = "week", key = "PVPK_COL_WEEK", w = 54, group = "PVPK_GRP_GAME", sort = function(r) return r.s.week or -1 end },
}
local SORT_TOTAL = function(r) return r.stot end

local function fmt(v) if v == nil then return "–" end return tostring(math.floor(v)) end

local function layout(parent, cells, size, color, width)
  local fixed = 0
  for _, c in ipairs(COLS) do fixed = fixed + c.w end
  local x = 0
  for i, c in ipairs(COLS) do
    local fs = cells[i]
    if not fs then fs = W.Text(parent, size, color); cells[i] = fs end
    local w = c.w > 0 and c.w or math.max(80, width - fixed - 4)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", parent, "LEFT", x + 4, 0)
    fs:SetWidth(w - 8)
    fs:SetWordWrap(false)
    fs:SetJustifyH((c.id == "name" or c.id == "rank" or c.id == "#") and "LEFT" or "RIGHT")
    c.x, c.width = x, w
    x = x + w
  end
end

local function build(p)
  local th = T.Current()
  p.cards = {}
  local labels = { "PVPK_CARD_SOW", "PVPK_CARD_SBG", "PVPK_CARD_OW", "PVPK_CARD_BG" }
  for i = 1, 4 do
    local c = W.Box(p, 10, 56, "panel2")
    c.label = W.Text(c, 10, "muted"); c.label:SetPoint("TOPLEFT", 10, -8); c.label:SetPoint("RIGHT", -8, 0)
    c.label:SetText(L[labels[i]])
    c.value = W.Text(c, 20, "title"); c.value:SetPoint("BOTTOMLEFT", 10, 7)
    c.sub = W.Text(c, 10, "muted"); c.sub:SetPoint("BOTTOMRIGHT", -10, 10); c.sub:SetJustifyH("RIGHT")
    p.cards[i] = c
  end
  p.cards[1]:SetPoint("TOPLEFT", 0, 0)
  for i = 2, 4 do p.cards[i]:SetPoint("TOPLEFT", p.cards[i - 1], "TOPRIGHT", 8, 0) end
  p:SetScript("OnSizeChanged", function(self, w)
    local cw = (w - 24) / 4
    for _, c in ipairs(self.cards) do c:SetWidth(cw) end
  end)

  local head = UI.Section(p, L.PVPK_MEMBERS)
  head:SetPoint("TOPLEFT", 0, -70)
  p.head = head
  p.hint = W.Text(p, 10, "muted")
  p.hint:SetPoint("TOPRIGHT", 0, -72)
  p.hint:SetText(L.PVPK_SORT_HINT)
  head.line:SetPoint("RIGHT", p.hint, "LEFT", -8, 0)

  -- group labels and clickable column headers
  p.groups = CreateFrame("Frame", nil, p)
  p.groups:SetPoint("TOPLEFT", 0, -92); p.groups:SetPoint("RIGHT", p, "RIGHT", 0, 0); p.groups:SetHeight(14)
  p.groupText = {}
  p.cols = CreateFrame("Frame", nil, p)
  p.cols:SetPoint("TOPLEFT", 0, -106); p.cols:SetPoint("RIGHT", p, "RIGHT", 0, 0); p.cols:SetHeight(18)
  p.colCells = {}
  p.colBtns = {}
  for i, c in ipairs(COLS) do
    if c.sort then
      local b = CreateFrame("Button", nil, p.cols)
      b:SetHeight(18)
      b:SetScript("OnClick", function()
        if V.sort == c.id then V.desc = not V.desc else V.sort = c.id; V.desc = c.id ~= "name" end
        UI.Refresh()
      end)
      p.colBtns[i] = b
    end
  end
  local line = p:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(th.line[1], th.line[2], th.line[3], 0.8)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", p.cols, "BOTTOMLEFT", 0, -1); line:SetPoint("TOPRIGHT", p.cols, "BOTTOMRIGHT", 0, -1)

  p.scroll = W.Scroll(p)
  p.scroll:SetPoint("TOPLEFT", 0, -128); p.scroll:SetPoint("BOTTOMRIGHT", 0, 22)
  p.rows = W.Pool(p.scroll.content, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.cells = {}
    r:SetScript("OnEnter", function(self)
      local s = self.row and self.row.s
      if not s then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(G.Display(self.row.key), 1, 0.82, 0)
      if s.rankName then GameTooltip:AddDoubleLine(L.PVPK_COL_RANK, s.rankName .. (s.prog and ("  (" .. s.prog .. " %)") or ""), 0.8, 0.8, 0.8, 1, 1, 1) end
      if s.highName then GameTooltip:AddDoubleLine(L.PVPK_TIP_HIGH, s.highName, 0.8, 0.8, 0.8, 1, 1, 1) end
      GameTooltip:AddDoubleLine(L.PVPK_TIP_YDAY, fmt(s.yday), 0.8, 0.8, 0.8, 1, 1, 1)
      GameTooltip:AddDoubleLine(L.PVPK_TIP_LASTWEEK, fmt(s.lastweek), 0.8, 0.8, 0.8, 1, 1, 1)
      GameTooltip:AddLine(L.PVPK_TIP_UPDATED:format(U.FormatSpan(U.Now() - (s.ts or U.Now()))), 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
  end)
  p.empty = W.Text(p.scroll.content, 11, "muted")
  p.empty:SetPoint("TOPLEFT", 4, -6); p.empty:SetPoint("RIGHT", p.scroll.content, "RIGHT", -4, 0)
  p.empty:SetText(L.PVPK_EMPTY)
  p.foot = W.Text(p, 10, "muted")
  p.foot:SetPoint("BOTTOMLEFT", 0, 2); p.foot:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  p.foot:SetText(L.PVPK_FOOT)
end

local function refresh(p)
  local th = T.Current()
  local width = p.cols:GetWidth()
  if not width or width < 100 then width = 840 end
  layout(p.cols, p.colCells, 10, "muted", width)

  -- headers
  for i, c in ipairs(COLS) do
    local label = c.id == "#" and "#" or L[c.key]
    if V.sort == c.id then label = label .. (V.desc and " v" or " ^") end
    p.colCells[i]:SetText(label)
    if V.sort == c.id then W.Color(p.colCells[i], "title") else W.Color(p.colCells[i], "muted") end
    local b = p.colBtns[i]
    if b then b:ClearAllPoints(); b:SetPoint("LEFT", p.cols, "LEFT", c.x, 0); b:SetWidth(c.width) end
  end
  -- group labels centred over their columns
  local gi = 0
  local i = 1
  while i <= #COLS do
    local c = COLS[i]
    if c.group then
      local j, w = i, 0
      while j <= #COLS and COLS[j].group == c.group do w = w + COLS[j].width; j = j + 1 end
      gi = gi + 1
      local fs = p.groupText[gi]
      if not fs then fs = W.Text(p.groups, 9, "title"); p.groupText[gi] = fs end
      fs:ClearAllPoints(); fs:SetPoint("LEFT", p.groups, "LEFT", c.x, 0); fs:SetWidth(w); fs:SetJustifyH("RIGHT")
      fs:SetText(L[c.group])
      i = j
    else
      i = i + 1
    end
  end

  -- rows
  local rows = P.StatRows()
  local sum = { sow = 0, sbg = 0, ow = 0, bg = 0, n = 0 }
  for _, r in ipairs(rows) do
    sum.sow = sum.sow + r.sow; sum.sbg = sum.sbg + r.sbg
    sum.ow = sum.ow + (r.s.ow or 0); sum.bg = sum.bg + (r.s.bg or 0); sum.n = sum.n + 1
  end
  local sortFn = SORT_TOTAL
  for _, c in ipairs(COLS) do if c.id == V.sort and c.sort then sortFn = c.sort end end
  table.sort(rows, function(a, b)
    local va, vb = sortFn(a), sortFn(b)
    if va == vb then return a.stot > b.stot end
    if V.desc then return va > vb end
    return va < vb
  end)

  local values = { sum.sow, sum.sbg, sum.ow, sum.bg }
  for k, c in ipairs(p.cards) do
    c.value:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(values[k]) or values[k])
    c.sub:SetText(L.PVPK_MEMBERS_N:format(sum.n))
  end

  local my = G.MyKey()
  for n, r in ipairs(rows) do
    local row = p.rows:Get(n)
    row.row = r
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(n - 1) * ROW_H); row:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
    row:SetWidth(width)
    if r.key == my then row.bg:SetColorTexture(th.accent[1], th.accent[2], th.accent[3], 0.25)
    elseif n % 2 == 0 then row.bg:SetColorTexture(0, 0, 0, 0.12)
    else row.bg:SetColorTexture(0, 0, 0, 0) end
    layout(row, row.cells, 11, "text", width)
    local s = r.s
    local vals = {
      n .. ".", G.Display(r.key),
      s.rankName or "–",
      fmt(r.sow), fmt(r.sbg), fmt(s.ow), fmt(s.bg), fmt(s.life), fmt(s.dk), fmt(s.today), fmt(s.week),
    }
    for k, fs in ipairs(row.cells) do
      fs:SetText(vals[k])
      if k == 1 or k == 4 or k == 5 then W.Color(fs, "title")
      elseif k == 3 or k == 9 then W.Color(fs, "muted")
      else W.Color(fs, "text") end
    end
  end
  p.rows:HideFrom(#rows + 1)
  p.empty:SetShown(#rows == 0)
  p.scroll:SetContentHeight(#rows * ROW_H)
end

UI.AddTab("pvpkills", {
  label = function() return L.TAB_PVPKILLS end,
  build = build,
  refresh = refresh,
})
