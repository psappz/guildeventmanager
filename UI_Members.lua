local ADDON, ns = ...
-- Members (0.9): one row per person – main, addon rank, functions and posts,
-- twinks (fold out with +), characters outside the guild (guild leadership
-- only, only from members with the addon who share them), last online.
-- Right-click (leadership): addon rank, link twinks, org chart.
local U, G, T, W, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI
local L = ns.L
local PS, R, S = ns.Persons, ns.Ranks, ns.Struct

local ROW, SUB = 20, 17

local function cname(key, cls)
  local r = G.roster[key]
  return "|cff" .. S.ClassHex(cls or (r and r.class)) .. G.Display(key) .. "|r"
end

local function seen(days)
  if not days then return "" end
  if days <= 0 then return "|cff40c040" .. L.MB_ONLINE .. "|r" end
  if days < 1 then return L.MB_TODAY end
  return L.MB_DAYS:format(math.floor(days))
end

local function rankText(key)
  local r = G.roster[key]
  local x = S.MemberRank(key)
  local t = x and x.name or (r and G.rankNames[r.rankIndex]) or ""
  if x and x.virt and r then t = t .. " |cff9a8a7a(" .. (G.rankNames[r.rankIndex] or "") .. ")|r" end
  local tags = {}
  if r then for _, f in ipairs(S.FuncsOfRank(r.rankIndex)) do tags[#tags + 1] = S.Tag(f) end end
  local function classes(n)
    local cs = {}
    for _, c in ipairs(n.cls or {}) do cs[#cs + 1] = S.ClassName(c) end
    return #cs > 0 and (" " .. table.concat(cs, ", ")) or ""
  end
  for _, n in ipairs(S.PostsOf(key)) do
    if n.kind ~= "gm" and n.kind ~= "off" and n.kind ~= "member" then
      local f = (n.kind == "raid" and S.Func("raid")) or (n.kind == "cls" and S.Func("cls")) or nil
      local col = f and f.col or "ff805c"
      tags[#tags + 1] = "|cff" .. col .. "[" .. S.KindName(n) .. (n.kind == "cls" and classes(n) or "") .. "]|r"
    end
    for _, d in ipairs(n.duties or {}) do
      local lb = S.DutyLabel(d)
      if lb then tags[#tags + 1] = "|cff" .. S.DutyCol(d) .. "[" .. lb .. (d == "cls" and classes(n) or "") .. "]|r" end
    end
  end
  return t .. (#tags > 0 and ("  " .. table.concat(tags, " ")) or "")
end

local function persons(lead)
  local seenM, out, chars = {}, {}, 0
  for key in pairs(G.roster) do
    chars = chars + 1
    local m = PS.MainOf(key)
    if G.roster[m] == nil then m = key end
    if not seenM[m] then
      seenM[m] = true
      local tw = {}
      for _, k in ipairs(PS.Alts(m)) do if G.roster[k] then tw[#tw + 1] = k end end
      table.sort(tw, function(a, b) return G.Display(a) < G.Display(b) end)
      local r = G.roster[m]
      out[#out + 1] = { main = m, twinks = tw, ext = lead and PS.ExternalOf(m) or {},
        off = R.PersonOffDays(m), cls = r and r.class, order = S.Order(m) }
    end
  end
  return out, chars
end

local COLS = { { 16 }, { 150, "MB_COL_MAIN" }, { 0, "MB_COL_RANK" }, { 46, "MB_COL_TWINKS" }, { 150, "MB_COL_EXT", lead = true }, { 72, "MB_COL_SEEN" } }

local function layout(width, frame, cells, lead)
  local fixed = 0
  for _, c in ipairs(COLS) do if not c.lead or lead then fixed = fixed + c[1] + 6 end end
  local x = 0
  for i, c in ipairs(COLS) do
    local fs = cells[i]
    if fs then
      local show = not c.lead or lead
      fs:SetShown(show)
      if show then
        local cw = c[1] > 0 and c[1] or math.max(140, width - fixed - 6)
        fs:ClearAllPoints()
        if fs.Set and fs.items then fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -3) else fs:SetPoint("LEFT", frame, "LEFT", x, 0) end
        fs:SetWidth(cw)
        x = x + cw + 6
      end
    end
  end
end

-- small context menu
local menu
local function showMenu(owner, key)
  local th = T.Current()
  if not menu then
    menu = CreateFrame("Frame", "GuildEventManagerMemberMenu", UIParent, "BackdropTemplate")
    W.Paint(menu, th.panel, th.title)
    menu:SetFrameStrata("DIALOG")
    menu:EnableMouse(true)
    menu.items = {}
    menu:SetScript("OnHide", function(self) self.key = nil end)
  end
  local items = {}
  items[#items + 1] = { head = G.Display(key) }
  for _, x in ipairs(S.RanksFor(key)) do
    local cur = S.MemberRank(key)
    items[#items + 1] = { text = (cur and cur.id == x.id and "> " or "   ") .. L.MB_SET_RANK:format(x.name), fn = function() S.SetMemberRank(key, x.id) end }
  end
  items[#items + 1] = { text = L.MB_LINK_TWINKS, fn = function() ns.UI.Show("persons") end }
  items[#items + 1] = { text = L.MB_TO_ORG, fn = function() ns.UI.Show("org") end }
  for i, it in ipairs(items) do
    local b = menu.items[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(18)
      b.t = W.Text(b, 11, "text"); b.t:SetPoint("LEFT", 8, 0)
      b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.08)
      menu.items[i] = b
    end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 2, -4 - (i - 1) * 18); b:SetPoint("RIGHT", -2, 0)
    b.t:SetText(it.head and ("|cffe6ba5c" .. it.head .. "|r") or it.text)
    b:SetScript("OnClick", function() menu:Hide(); if it.fn then it.fn() end end)
    b:EnableMouse(not it.head)
    b:Show()
  end
  for i = #items + 1, #menu.items do menu.items[i]:Hide() end
  menu:SetSize(220, #items * 18 + 8)
  local x, y = GetCursorPosition()
  local sc = UIParent:GetEffectiveScale() or 1
  menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / sc, y / sc)
  menu:Show()
  ns.Schedule("gemMemberMenu", 6, function() if menu and not menu:IsMouseOver() then menu:Hide() end end)
end

local function build(p)
  local th = T.Current()
  p.open, p.filter = {}, "all"
  p.search = W.Edit(p, 160, 22); p.search:SetPoint("TOPLEFT", 0, 0)
  p.searchL = W.Text(p.search, 10, "muted"); p.searchL:SetPoint("LEFT", 6, 0); p.searchL:SetText(L.MB_SEARCH)
  p.search:SetScript("OnTextChanged", function(self) p.searchL:SetShown(self:GetText() == ""); ns.UI.Refresh() end)
  p.fb = {}
  local prev = p.search
  for _, f in ipairs({ "all", "mine", "online", "ina" }) do
    local b = W.Button(p, L["MB_F_" .. f], false, 20)
    b:SetWidth(90); b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    b:SetScript("OnClick", function() p.filter = f; ns.UI.Refresh() end)
    b.f = f
    p.fb[#p.fb + 1] = b
    prev = b
  end
  p.count = W.Text(p, 10, "muted"); p.count:SetPoint("TOPRIGHT", 0, -4)
  p.head = CreateFrame("Frame", nil, p)
  p.head:SetHeight(20)
  p.head:SetPoint("TOPLEFT", p.search, "BOTTOMLEFT", 0, -8); p.head:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  local line = p.head:CreateTexture(nil, "ARTWORK"); line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", 0, 0); line:SetPoint("BOTTOMRIGHT", 0, 0)
  line:SetColorTexture(th.title[1], th.title[2], th.title[3], 0.5)
  p.heads = {}
  for i, c in ipairs(COLS) do
    if c[2] then local h = W.Text(p.head, 10, "title"); h:SetText(L[c[2]]); p.heads[i] = h end
  end
  p.note = W.Text(p, 9, "muted"); p.note:SetPoint("BOTTOMLEFT", 0, 0); p.note:SetPoint("RIGHT", p, "RIGHT", 0, 0); p.note:SetJustifyH("LEFT")
  p.list = W.Scroll(p)
  p.list:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -2); p.list:SetPoint("BOTTOMRIGHT", 0, 16)
  p.rows = W.Pool(p.list.content, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.cells = {}
    r.pm = CreateFrame("Button", nil, r, "BackdropTemplate")
    r.pm:SetSize(14, 14)
    W.Paint(r.pm, th.accent, th.title)
    r.pm.t = W.Text(r.pm, 11, "text"); r.pm.t:SetPoint("CENTER", 0, 1)
    r.pm:SetScript("OnClick", function(self) local k = self:GetParent().key; if k then p.open[k] = not p.open[k]; ns.UI.Refresh() end end)
    r.cells[1] = r.pm
    for i = 2, #COLS do
      local fs = W.Text(r, 10, "text"); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
      r.cells[i] = fs
    end
    r.cells[3] = W.Badges(r)
    r:SetScript("OnClick", function(self, btn)
      if btn == "RightButton" and self.key and S.CanEdit() then showMenu(self, self.key)
      elseif self.key and self.hasTw then p.open[self.key] = not p.open[self.key]; ns.UI.Refresh() end
    end)
    r:SetScript("OnEnter", function(self)
      if not self.ext or #self.ext == 0 then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(L.MB_COL_EXT, 1, 0.82, 0)
      for _, e in ipairs(self.ext) do
        GameTooltip:AddDoubleLine("|cff" .. S.ClassHex(e.cl) .. e.n .. "|r", e.lv and tostring(e.lv) or "", 1, 1, 1, 0.7, 0.7, 0.7)
      end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
  end)
  p.subs = W.Pool(p.list.content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(SUB)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0, 0, 0, 0.25)
    r.cells = {}
    for i = 2, #COLS do
      local fs = W.Text(r, 10, "text"); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
      r.cells[i] = fs
    end
    r.cells[3] = W.Badges(r)
    return r
  end)
end

local function refresh(p)
  local lead = G.IsLead()
  local list, chars = persons(lead)
  local q = (p.search:GetText() or ""):lower()
  local mine = S.MyClasses(G.MyKey())
  local f = {}
  for _, x in ipairs(list) do
    local ok = true
    if q ~= "" then
      local hay = { G.Display(x.main) }
      for _, k in ipairs(x.twinks) do hay[#hay + 1] = G.Display(k) end
      for _, e in ipairs(x.ext) do hay[#hay + 1] = e.n end
      ok = table.concat(hay, " "):lower():find(q, 1, true) ~= nil
    end
    if ok and p.filter == "mine" then ok = x.cls and mine[x.cls] or false end
    if ok and p.filter == "online" then ok = (x.off or 1) <= 0 end
    if ok and p.filter == "ina" then
      local r = G.roster[x.main]
      ok = r and S.HasRank("inactive", r.rankIndex) or false
    end
    if ok then f[#f + 1] = x end
  end
  table.sort(f, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return G.Display(a.main) < G.Display(b.main)
  end)
  for _, b in ipairs(p.fb) do
    b:SetAlpha(p.filter == b.f and 1 or 0.6)
    if b.f == "mine" then b:SetShown(next(mine) ~= nil) end
  end
  p.count:SetText(L.MB_COUNT:format(#f, chars))
  p.note:SetText(lead and L.MB_LEAD_NOTE2 or L.MB_MEMBER_NOTE)
  local w = p:GetWidth() or 700
  layout(w, p.head, p.heads, lead)
  local y, ns_, nr = 0, 0, 0
  for i, x in ipairs(f) do
    nr = i
    local r = p.rows:Get(i)
    r.key, r.ext, r.hasTw = x.main, x.ext, #x.twinks > 0
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", p.list.content, "RIGHT", 0, 0)
    r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
    layout(w, r, r.cells, lead)
    r.pm:SetShown(#x.twinks > 0)
    r.pm.t:SetText(p.open[x.main] and "-" or "+")
    local mr = G.roster[x.main]
    r.cells[2]:SetText(cname(x.main) .. (mr and mr.level and (" |cff9a8a7a" .. mr.level .. "|r") or ""))
    local bh = r.cells[3]:Set(S.Badges(x.main, true), r.cells[3]:GetWidth())
    local rh = math.max(ROW, bh + 6)
    r:SetHeight(rh)
    r.cells[4]:SetText(#x.twinks > 0 and tostring(#x.twinks) or "|cff9a8a7a-|r")
    local ex = {}
    for _, e in ipairs(x.ext) do ex[#ex + 1] = "|cff" .. S.ClassHex(e.cl) .. e.n .. "|r" end
    r.cells[5]:SetText(table.concat(ex, ", "))
    r.cells[6]:SetText(seen(x.off))
    y = y + rh
    if p.open[x.main] then
      for _, k in ipairs(x.twinks) do
        ns_ = ns_ + 1
        local s = p.subs:Get(ns_)
        s:ClearAllPoints(); s:SetPoint("TOPLEFT", 0, -y); s:SetPoint("RIGHT", p.list.content, "RIGHT", 0, 0)
        layout(w, s, s.cells, lead)
        local tr = G.roster[k]
        s.cells[2]:SetText("   |cff9a8a7a>|r " .. cname(k) .. (tr and tr.level and (" |cff9a8a7a" .. tr.level .. "|r") or ""))
        local tags = {}
        if tr then for _, fn in ipairs(S.FuncsOfRank(tr.rankIndex)) do tags[#tags + 1] = S.Tag(fn) end end
        local sh = s.cells[3]:Set(S.Badges(k, false), s.cells[3]:GetWidth())
        s:SetHeight(math.max(SUB, sh + 4))
        s.cells[4]:SetText(""); s.cells[5]:SetText("")
        s.cells[6]:SetText(tr and seen(tr.online and 0 or tr.offDays) or "")
        y = y + s:GetHeight()
      end
    end
  end
  p.rows:HideFrom(nr + 1)
  p.subs:HideFrom(ns_ + 1)
  p.list:SetContentHeight(y)
end

UI.AddTab("members", {
  label = function() return L.MB_TAB end,
  icon = W.Icon("members"),
  category = "guild",
  order = 6,
  build = build, refresh = refresh,
})
