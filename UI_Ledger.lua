local ADDON, ns = ...
-- Honor book: every booking of every module in one list, with the module as
-- a tag and a filter per module. Managers strike entries with a right-click.
local U, G, T, W, UI, Pts, Lg = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI, ns.Points, ns.Ledger
local L = ns.L
local V = { filter = "all" }
local MAX = 120

local function build(p)
  local th = T.Current()
  p.head = UI.Section(p, L.TAB_LEDGER)
  p.head:SetPoint("TOPLEFT", 0, 0)
  p.chips = UI.ChipRow(p, function()
    local o = { { "all", L.LEDGER_ALL } }
    for _, id in ipairs(Lg.order) do
      local f = Lg.formats[id]
      o[#o + 1] = { id, f.label and f.label() or id }
    end
    return o
  end, function() return V.filter end, function(v) V.filter = v; UI.Refresh() end)
  p.chips:SetPoint("TOPLEFT", 0, -22); p.chips:SetPoint("RIGHT", 0, 0)
  p.box = W.Box(p, 10, 10, "panel2")
  p.box:SetPoint("TOPLEFT", 0, -52); p.box:SetPoint("BOTTOMRIGHT", 0, 18)
  p.scroll = W.Scroll(p.box)
  p.scroll:SetPoint("TOPLEFT", 6, -6); p.scroll:SetPoint("BOTTOMRIGHT", -6, 6)
  p.rows = W.Pool(p.scroll.content, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(20)
    r:RegisterForClicks("RightButtonUp")
    r.tag = UI.Pill(r); r.tag:SetPoint("LEFT", 0, 0)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 84, 0); r.text:SetPoint("RIGHT", -96, 0); r.text:SetWordWrap(false)
    r.pts = W.Text(r, 11, "title"); r.pts:SetPoint("RIGHT", -52, 0); r.pts:SetJustifyH("RIGHT")
    r.when = W.Text(r, 9, "muted"); r.when:SetPoint("RIGHT", -2, 0); r.when:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self)
      if not G.IsManager() or not self.entry or self.entry.reverted then return end
      W.OpenMenu(self, function(_, root)
        root:CreateTitle(G.Display(self.entry.who))
        root:CreateButton(L.LEDGER_REVERT_ACT, function() Pts.Revert(self.entry.id) end)
      end)
    end)
    return r
  end)
  p.empty = W.Text(p.scroll.content, 10, "muted")
  p.empty:SetPoint("TOPLEFT", 2, -4)
  p.empty:SetText(L.LEDGER_EMPTY)
  p.hint = W.Text(p, 10, "muted")
  p.hint:SetPoint("BOTTOMLEFT", 0, 0)
end

local function refresh(p)
  local th = T.Current()
  p.chips:Refresh()
  local list = Pts.Entries(function(e)
    if V.filter == "all" then return true end
    return (Lg.FormatOf(e)) == V.filter
  end)
  local n = 0
  for _, e in ipairs(list) do
    n = n + 1
    if n > MAX then break end
    local row = p.rows:Get(n)
    row.entry = e
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(n - 1) * 22); row:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
    local _, tag = Lg.Tag(e)
    row.tag:Set(tag, false)
    local deed = Lg.Text(e)
    local txt = G.Display(e.who) .. U.Color(T.Hex(th.muted), " · " .. deed .. ((e.zone and e.zone ~= "") and (" · " .. e.zone) or ""))
    if e.reverted then txt = U.Color("ff808080", G.Display(e.who) .. " · " .. deed .. " · " .. L.LEDGER_REVERTED) end
    row.text:SetText(txt)
    row.pts:SetText((e.amt > 0 and "+" or "") .. e.amt)
    row.when:SetText(date("%d.%m. %H:%M", e.ts))
  end
  local shown = math.min(n, MAX)
  p.rows:HideFrom(shown + 1)
  p.empty:SetShown(shown == 0)
  p.scroll:SetContentHeight(shown * 22)
  p.hint:SetText(G.IsManager() and L.LEDGER_HINT_MGR or L.LEDGER_HINT)
end

UI.RegisterView("ledger", {
  label = function() return L.TAB_LEDGER end,
  build = build,
  refresh = refresh,
})
