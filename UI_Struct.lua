local ADDON, ns = ...
-- Settings page "Guild structure" (0.9, guild leadership): ranks in the addon
-- (order, virtual ranks, outside the order) and functions (name, colour, WoW ranks).
local U, G, T, W, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI
local L = ns.L
local S = ns.Struct

local ROW = 24

local function wowOptions()
  local o = {}
  for i = 0, 20 do local n = G.rankNames[i]; if n then o[#o + 1] = { i, (i + 1) .. " · " .. n } end end
  return o
end

local function tagsOf(wow)
  local t = {}
  for _, f in ipairs(S.FuncsOfRank(wow)) do t[#t + 1] = S.Tag(f) end
  return table.concat(t, " ")
end

local function build(p)
  local th = T.Current()
  -- left: ranks in the addon
  local left = CreateFrame("Frame", nil, p)
  left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", p, "BOTTOM", 30, 0)
  local s1 = UI.Section(left, L.ST_RANKS); s1:SetPoint("TOPLEFT", 0, 0)
  p.rIntro = W.Text(left, 10, "muted"); p.rIntro:SetPoint("TOPLEFT", s1, "BOTTOMLEFT", 0, -6); p.rIntro:SetPoint("RIGHT", left, "RIGHT", -8, 0)
  p.rIntro:SetJustifyH("LEFT"); p.rIntro:SetText(L.ST_RANKS_TEXT)
  p.rList = W.Scroll(left)
  p.rList:SetPoint("TOPLEFT", p.rIntro, "BOTTOMLEFT", 0, -6); p.rList:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -8, 30)
  p.addV = W.Button(left, L.ST_ADD_VIRT, false, 22); p.addV:SetPoint("BOTTOMLEFT", 0, 2); p.addV:SetWidth(150)
  p.addV:SetScript("OnClick", function()
    S.Edit(function(st)
      local at = #st.ranks + 1
      for i, r in ipairs(st.ranks) do if r.out then at = i; break end end
      table.insert(st.ranks, at, { id = S.NewId(), name = L.ST_NEW_RANK, wow = (G.roster[G.MyKey()] and 5) or 0, virt = true })
    end)
  end)
  p.ro = W.Text(left, 10, "muted"); p.ro:SetPoint("LEFT", p.addV, "RIGHT", 10, 0)
  p.rRows = W.Pool(p.rList.content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW)
    -- the chevron points right: turned up and down
    -- up and down on top of each other (narrow column)
    r.up = W.IconButton(r, "chevron", 12, L.ST_UP); r.up:SetPoint("TOPLEFT", 0, 0); r.up.icon:SetRotation(math.pi / 2)
    r.down = W.IconButton(r, "chevron", 12, L.ST_DOWN); r.down:SetPoint("BOTTOMLEFT", 0, 0); r.down.icon:SetRotation(-math.pi / 2)
    r.num = W.Text(r, 10, "muted"); r.num:SetPoint("LEFT", 14, 0); r.num:SetWidth(14)
    r.name = W.Edit(r, 120, 20); r.name:SetPoint("LEFT", 30, 0)
    r.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    r.name:SetScript("OnEditFocusLost", function(self)
      local id, v = self:GetParent().id, (self:GetText() or ""):match("^%s*(.-)%s*$")
      if v ~= "" then S.Edit(function(st) for _, x in ipairs(st.ranks) do if x.id == id then x.name = v end end end) end
    end)
    -- functions of the WoW rank as small boxes; they shrink and wrap, the row grows
    r.tags = W.Badges(r); r.tags:SetPoint("TOPLEFT", r.name, "TOPRIGHT", 6, 2); r.tags:SetWidth(112)
    r.wow = W.Dropdown(r, 120, wowOptions, function() return r.wowVal end, function(v)
      local id = r.id
      S.Edit(function(st) for _, x in ipairs(st.ranks) do if x.id == id then x.wow = v end end end)
    end)
    r.wow:SetPoint("RIGHT", -72, 0)
    -- colour of the rank (round badge): click picks the next colour
    r.col = CreateFrame("Button", nil, r, "BackdropTemplate")
    r.col:SetSize(14, 14); r.col:SetPoint("RIGHT", r.wow, "LEFT", -6, 0)
    W.Paint(r.col, { 1, 1, 1, 1 }, { 0, 0, 0, 1 })
    r.col:SetScript("OnClick", function()
      local id = r.id
      S.Edit(function(st)
        for _, x in ipairs(st.ranks) do
          if x.id == id then
            local cur, nxt = S.RankCol(x), S.COLORS[1]
            for i, c in ipairs(S.COLORS) do if c == cur then nxt = S.COLORS[i % #S.COLORS + 1] end end
            x.col = nxt
          end
        end
      end)
    end)
    r.col:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.ST_RANK_COL); GameTooltip:Show() end)
    r.col:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.out = W.Button(r, "", false, 18); r.out:SetWidth(46); r.out:SetPoint("RIGHT", -22, 0)
    r.out:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.ST_OUT); GameTooltip:Show() end)
    r.out:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.del = W.IconButton(r, "close", 18, L.ST_DEL); r.del:SetPoint("RIGHT", 0, 0)
    local function move(d)
      local id = r.id
      S.Edit(function(st)
        local i
        for k, x in ipairs(st.ranks) do if x.id == id then i = k end end
        if not i then return end
        -- the next rank in the same part (in the order / outside) in that direction
        local out = st.ranks[i].out and true or false
        local j = i + d
        while st.ranks[j] and ((st.ranks[j].out and true or false) ~= out) do j = j + d end
        -- the guild master's rank stays at the top
        if st.ranks[j] and st.ranks[j].wow ~= 0 and st.ranks[i].wow ~= 0 then st.ranks[i], st.ranks[j] = st.ranks[j], st.ranks[i] end
      end)
    end
    r.up:SetScript("OnClick", function() move(-1) end)
    r.down:SetScript("OnClick", function() move(1) end)
    r.out:SetScript("OnClick", function()
      local id = r.id
      S.Edit(function(st)
        local i
        for k, x in ipairs(st.ranks) do if x.id == id then i = k end end
        local x = table.remove(st.ranks, i)
        x.out = (not x.out) or nil
        if x.out then st.ranks[#st.ranks + 1] = x
        else
          local at = #st.ranks + 1
          for k, y in ipairs(st.ranks) do if y.out then at = k; break end end
          table.insert(st.ranks, at, x)
        end
      end)
    end)
    r.del:SetScript("OnClick", function()
      local id = r.id
      S.Edit(function(st) for k, x in ipairs(st.ranks) do if x.id == id then table.remove(st.ranks, k); break end end end)
    end)
    return r
  end)
  p.outHead = W.Text(p.rList.content, 10, "muted"); p.outHead:SetText(L.ST_OUTSIDE)

  -- right: functions
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", p, "TOP", 42, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
  local s2 = UI.Section(right, L.ST_FUNCS); s2:SetPoint("TOPLEFT", 0, 0)
  p.fList = W.Scroll(right)
  p.fList:SetPoint("TOPLEFT", s2, "BOTTOMLEFT", 0, -6); p.fList:SetPoint("RIGHT", right, "RIGHT", 0, 0)
  p.fRows = W.Pool(p.fList.content, function(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(20)
    W.Paint(b, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    b.sw = b:CreateTexture(nil, "ARTWORK"); b.sw:SetSize(10, 10); b.sw:SetPoint("LEFT", 4, 0)
    b.name = W.Text(b, 11, "text"); b.name:SetPoint("LEFT", 20, 0); b.name:SetWidth(110)
    b.ranks = W.Text(b, 9, "muted"); b.ranks:SetPoint("LEFT", 134, 0); b.ranks:SetPoint("RIGHT", -2, 0); b.ranks:SetWordWrap(false)
    b:SetScript("OnClick", function(self) p.fsel = self.id; ns.UI.Refresh() end)
    return b
  end)
  p.addF = W.Button(right, L.ST_ADD_FUNC, false, 20); p.addF:SetWidth(110)
  p.addF:SetScript("OnClick", function()
    local id = S.NewId()
    S.Edit(function(st) st.funcs[#st.funcs + 1] = { id = id, name = L.ST_NEW_FUNC, col = "ff805c", ranks = {} } end)
    p.fsel = id
  end)
  -- editor of the selected function
  local ed = CreateFrame("Frame", nil, right, "BackdropTemplate")
  W.Paint(ed, th.panel, th.line)
  ed:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 0, 0); ed:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0); ed:SetHeight(230)
  p.addF:SetPoint("BOTTOMLEFT", ed, "TOPLEFT", 0, 6)
  p.fList:SetPoint("BOTTOM", p.addF, "TOP", 0, 6)
  p.ed = ed
  local nl = W.Text(ed, 10, "muted"); nl:SetPoint("TOPLEFT", 8, -8); nl:SetText(L.ST_F_NAME)
  ed.name = W.Edit(ed, 160, 20); ed.name:SetPoint("TOPLEFT", nl, "BOTTOMLEFT", 0, -3)
  ed.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  ed.name:SetScript("OnEditFocusLost", function(self)
    local v = (self:GetText() or ""):match("^%s*(.-)%s*$")
    local id = p.fsel
    if v ~= "" then S.Edit(function(st) for _, f in ipairs(st.funcs) do if f.id == id then f.name = v end end end) end
  end)
  ed.del = W.Button(ed, L.ST_DEL_FUNC, false, 20); ed.del:SetPoint("LEFT", ed.name, "RIGHT", 8, 0); ed.del:SetWidth(80)
  ed.del:SetScript("OnClick", function()
    local id = p.fsel
    S.Edit(function(st)
      for k, f in ipairs(st.funcs) do
        if f.id == id and not S.FIXED[f.base or ""] then
          table.remove(st.funcs, k)
          st.deleted = st.deleted or {}; st.deleted[id] = true   -- presets do not come back
          break
        end
      end
    end)
    p.fsel = nil
  end)
  local cl = W.Text(ed, 10, "muted"); cl:SetPoint("TOPLEFT", ed.name, "BOTTOMLEFT", 0, -8); cl:SetText(L.ST_F_COLOR)
  ed.sw = {}
  for i, c in ipairs(S.COLORS) do
    local b = CreateFrame("Button", nil, ed, "BackdropTemplate")
    b:SetSize(16, 16)
    b:SetPoint("TOPLEFT", cl, "BOTTOMLEFT", (i - 1) * 20, -3)
    local r, g, bl = tonumber(c:sub(1, 2), 16) / 255, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255
    W.Paint(b, { r, g, bl, 1 }, { 0, 0, 0, 1 })
    b.col = c
    b:SetScript("OnClick", function(self)
      local id = p.fsel
      S.Edit(function(st) for _, f in ipairs(st.funcs) do if f.id == id then f.col = self.col end end end)
    end)
    ed.sw[i] = b
  end
  local rl = W.Text(ed, 10, "muted"); rl:SetPoint("TOPLEFT", cl, "BOTTOMLEFT", 0, -26); rl:SetText(L.ST_F_RANKS)
  ed.rb = {}
  for i = 0, 11 do
    local b = W.Button(ed, "", false, 18)
    b:SetWidth(112)
    b:SetPoint("TOPLEFT", rl, "BOTTOMLEFT", (i % 3) * 116, -3 - math.floor(i / 3) * 20)
    b.wow = i
    b:SetScript("OnClick", function(self)
      local id, w = p.fsel, self.wow
      if not S.CanEditLead(id) then return end
      S.Edit(function(st)
        for _, f in ipairs(st.funcs) do
          if f.id == id then
            local has
            for k, x in ipairs(f.ranks) do if x == w then table.remove(f.ranks, k); has = true; break end end
            if not has then f.ranks[#f.ranks + 1] = w; table.sort(f.ranks) end
          end
        end
      end)
    end)
    ed.rb[i] = b
  end
  ed.hint = W.Text(ed, 10, "muted"); ed.hint:SetPoint("RIGHT", ed, "RIGHT", -8, 0); ed.hint:SetJustifyH("LEFT")
  ed.rl = rl
end

-- the leadership function may only be changed by the guild master
function S.CanEditLead(id)
  local f = S.FuncById(id)
  if f and f.base == "lead" then return G.RankOf(G.MyKey()) == 0 end
  return S.CanEdit()
end

local function refresh(p)
  local st = S.Get()
  local th = T.Current()
  -- ranks
  local y, n, k = 0, 0, 0
  local outShown = false
  local list = {}
  for _, x in ipairs(st.ranks) do if not x.out and x.wow == 0 then list[#list + 1] = x end end
  for _, x in ipairs(st.ranks) do if not x.out and x.wow ~= 0 then list[#list + 1] = x end end
  for _, x in ipairs(st.ranks) do if x.out then list[#list + 1] = x end end
  for i, x in ipairs(list) do
    if x.out and not outShown then
      outShown = true
      p.outHead:ClearAllPoints(); p.outHead:SetPoint("TOPLEFT", 0, -y - 6)
      y = y + 22
    end
    local r = p.rRows:Get(i)
    r.id, r.wowVal = x.id, x.wow
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", p.rList.content, "RIGHT", 0, 0)
    if not x.out then k = k + 1 end
    r.num:SetText(x.out and "–" or tostring(k))
    if not r.name:HasFocus() then r.name:SetText(x.name or "") end
    local badges = {}
    if x.virt then badges[#badges + 1] = { text = L.ST_VIRT, col = "ff805c" } end
    for _, f in ipairs(S.FuncsOfRank(x.wow)) do badges[#badges + 1] = { text = f.name, col = f.col } end
    -- room between the name and the colour square (the right part is anchored to the row's right edge)
    local rw = p.rList.content:GetWidth() or 0
    if rw < 300 then rw = (p.rList:GetWidth() or 460) end
    local avail = math.max(60, rw - 212 - 156 - 8)
    r.tags:SetWidth(avail)
    local th2 = r.tags:Set(badges, avail)
    local rh = math.max(ROW, th2 + 8)
    r:SetHeight(rh)
    local gm = x.wow == 0
    r.up:SetShown(not gm); r.down:SetShown(not gm); r.out:SetShown(not gm)
    r.wow:Refresh()
    local c = S.RankCol(x)
    r.col:SetBackdropColor(tonumber(c:sub(1, 2), 16) / 255, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255, 1)
    r.del:SetShown(x.virt and true or false)
    W.SetLabel(r.out, x.out and L.ST_TO_IN or L.ST_TO_OUT); r.out:SetWidth(46)
    y = y + rh
    n = i
  end
  p.outHead:SetShown(outShown)
  p.rRows:HideFrom(n + 1)
  p.rList:SetContentHeight(y)
  local used = {}
  for _, x in ipairs(st.ranks) do used[x.wow] = true end
  local miss = {}
  for i = 0, 20 do if G.rankNames[i] and not used[i] then miss[#miss + 1] = G.rankNames[i] end end
  p.ro:SetText(#miss > 0 and L.ST_MISSING:format(table.concat(miss, ", ")) or "")

  -- functions
  local yy = 0
  for i, f in ipairs(st.funcs) do
    local b = p.fRows:Get(i)
    b.id = f.id
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", p.fList.content, "TOPLEFT", 0, -yy); b:SetPoint("RIGHT", p.fList.content, "RIGHT", 0, 0)
    local c = f.col or "bdad9c"
    b.sw:SetColorTexture(tonumber(c:sub(1, 2), 16) / 255, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255, 1)
    b.name:SetText(f.name or "")
    local rn = {}
    for _, w in ipairs(f.ranks or {}) do rn[#rn + 1] = G.rankNames[w] or tostring(w) end
    b.ranks:SetText(table.concat(rn, ", "))
    if p.fsel == f.id then b:SetBackdropColor(th.panel2[1], th.panel2[2], th.panel2[3], 1); b:SetBackdropBorderColor(th.title[1], th.title[2], th.title[3], 1)
    else b:SetBackdropColor(0, 0, 0, 0); b:SetBackdropBorderColor(0, 0, 0, 0) end
    yy = yy + 21
  end
  p.fRows:HideFrom(#st.funcs + 1)
  p.fList:SetContentHeight(yy)
  if not p.fsel or not S.FuncById(p.fsel) then p.fsel = st.funcs[1] and st.funcs[1].id end
  local f = S.FuncById(p.fsel)
  local ed = p.ed
  ed:SetShown(f ~= nil)
  if f then
    if not ed.name:HasFocus() then ed.name:SetText(f.name or "") end
    ed.del:SetShown(not S.FIXED[f.base or ""])
    for _, b in ipairs(ed.sw) do
      if b.col == f.col then b:SetBackdropBorderColor(1, 1, 1, 1) else b:SetBackdropBorderColor(0, 0, 0, 1) end
    end
    local on = {}
    for _, w in ipairs(f.ranks or {}) do on[w] = true end
    local canLead = S.CanEditLead(f.id)
    for i, b in pairs(ed.rb) do
      local nm = G.rankNames[i]
      b:SetShown(nm ~= nil and not (f.base == "lead" and i == 0))
      if nm then
        b.label:SetText(on[i] and ("|cff" .. (f.col or "e6ba5c") .. nm .. "|r") or nm)
        b:SetAlpha(on[i] and 1 or 0.55)
      end
    end
    local h = L["ST_BASE_" .. (f.base or "own")] or ""
    if f.base == "lead" and not canLead then h = h .. "\n" .. L.RK_LEAD_GM end
    ed.hint:SetText(h)
    -- the editor is as tall as its rank buttons need; the list above scrolls
    local nr = 0
    for i = 0, 11 do if G.rankNames[i] then nr = i + 1 end end
    local rows = math.max(1, math.ceil(nr / 3))
    ed.hint:ClearAllPoints(); ed.hint:SetPoint("TOPLEFT", ed.rl, "BOTTOMLEFT", 0, -8 - rows * 20); ed.hint:SetPoint("RIGHT", ed, "RIGHT", -8, 0)
    ed:SetHeight(104 + rows * 20 + 40)
  end
end

UI.AddSettingsPage("struct", {
  label = function() return L.ST_TAB end,
  shown = function() return S.CanEdit() end,
  build = build, refresh = refresh,
})
