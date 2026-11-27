local ADDON, ns = ...
-- Settings page "My characters" (0.9): main, twinks of this account and who
-- may see them; for managers: link twinks of members without the addon.
local U, G, T, W, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI
local L = ns.L
local PS = ns.Persons

local function build(p)
  local left = CreateFrame("Frame", nil, p)
  left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -12, 0)
  local s1 = UI.Section(left, L.PS_MINE); s1:SetPoint("TOPLEFT", 0, 0)
  p.intro = W.Text(left, 10, "muted"); p.intro:SetPoint("TOPLEFT", s1, "BOTTOMLEFT", 0, -8); p.intro:SetPoint("RIGHT", left, "RIGHT", 0, 0)
  p.intro:SetJustifyH("LEFT"); p.intro:SetSpacing(2); p.intro:SetText(L.PS_INTRO)
  p.mine = CreateFrame("Frame", nil, left)
  p.mine:SetPoint("TOPLEFT", p.intro, "BOTTOMLEFT", 0, -8); p.mine:SetPoint("RIGHT", left, "RIGHT", 0, 0); p.mine:SetHeight(10)
  p.rows = W.Pool(p.mine, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(24)
    r.name = W.Text(r, 11, "text"); r.name:SetPoint("LEFT", 0, 0); r.name:SetWidth(150); r.name:SetJustifyH("LEFT")
    r.main = W.Button(r, L.PS_MAKE_MAIN, false, 20); r.main:SetPoint("LEFT", 156, 0); r.main:SetWidth(90)
    r.main:SetScript("OnClick", function(self) PS.SetMain(self:GetParent().key) end)
    r.tag = W.Text(r, 10, "title"); r.tag:SetPoint("LEFT", 160, 0)
    r.link = W.Check(r, L.PS_LINKED, function(self, on) PS.SetLinked(self:GetParent().key, on) end)
    r.link:SetPoint("LEFT", 256, 0)
    return r
  end)
  p.visL = W.Text(left, 10, "muted"); p.visL:SetPoint("TOPLEFT", p.mine, "BOTTOMLEFT", 0, -12); p.visL:SetText(L.PS_VIS)
  p.vis = W.Dropdown(left, 240, function()
    local o = {}
    for _, v in ipairs(PS.VIS) do o[#o + 1] = { v, L["PS_VIS_" .. v] } end
    return o
  end, function() return PS.Visibility() end, function(v) PS.SetVisibility(v) end)
  p.vis:SetPoint("TOPLEFT", p.visL, "BOTTOMLEFT", 0, -3)
  p.visHint = W.Text(left, 10, "muted"); p.visHint:SetPoint("TOPLEFT", p.vis, "BOTTOMLEFT", 0, -6); p.visHint:SetPoint("RIGHT", left, "RIGHT", 0, 0)
  p.visHint:SetJustifyH("LEFT")

  -- right: leadership
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", p, "TOP", 12, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
  p.right = right
  local s2 = UI.Section(right, L.PS_LEAD_HEAD); s2:SetPoint("TOPLEFT", 0, 0)
  p.leadIntro = W.Text(right, 10, "muted"); p.leadIntro:SetPoint("TOPLEFT", s2, "BOTTOMLEFT", 0, -8); p.leadIntro:SetPoint("RIGHT", right, "RIGHT", 0, 0)
  p.leadIntro:SetJustifyH("LEFT"); p.leadIntro:SetText(L.PS_LEAD_INTRO)
  local lt = W.Text(right, 10, "muted"); lt:SetPoint("TOPLEFT", p.leadIntro, "BOTTOMLEFT", 0, -10); lt:SetText(L.PS_TWINK)
  p.twink = W.Edit(right, 150, 22); p.twink:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 0, -3)
  local lm = W.Text(right, 10, "muted"); lm:SetPoint("TOPLEFT", lt, "TOPLEFT", 160, 0); lm:SetText(L.PS_OF)
  p.ofMain = W.Edit(right, 150, 22); p.ofMain:SetPoint("TOPLEFT", lm, "BOTTOMLEFT", 0, -3)
  W.NameComplete(p.twink, W.MemberNames)
  W.NameComplete(p.ofMain, W.MemberNames)
  p.assign = W.Button(right, L.PS_ASSIGN, true, 22); p.assign:SetPoint("TOPLEFT", p.twink, "BOTTOMLEFT", 0, -8)
  p.msg = W.Text(right, 10, "text"); p.msg:SetPoint("LEFT", p.assign, "RIGHT", 10, 0); p.msg:SetPoint("RIGHT", right, "RIGHT", 0, 0)
  p.assign:SetScript("OnClick", function()
    local a, m = (p.twink:GetText() or ""):match("^%s*(.-)%s*$"), (p.ofMain:GetText() or ""):match("^%s*(.-)%s*$")
    local ka, km = G.Resolve(a), G.Resolve(m)
    if not ka then p.msg:SetText(L.PS_UNKNOWN:format(a)); return end
    if not km then p.msg:SetText(L.PS_UNKNOWN:format(m)); return end
    if PS.Assign(ka, PS.MainOf(km)) then
      p.msg:SetText(L.PS_DONE:format(G.Display(ka), G.Display(PS.MainOf(km))))
      p.twink:SetText(""); p.ofMain:SetText("")
    end
  end)
  local s3 = UI.Section(right, L.PS_LIST); s3:SetPoint("TOPLEFT", p.assign, "BOTTOMLEFT", 0, -16)
  p.none = W.Text(right, 10, "muted"); p.none:SetPoint("TOPLEFT", s3, "BOTTOMLEFT", 0, -8); p.none:SetText(L.PS_NONE)
  p.list = W.Scroll(right)
  p.list:SetPoint("TOPLEFT", s3, "BOTTOMLEFT", 0, -6); p.list:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
  p.lRows = W.Pool(p.list.content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(20)
    r.text = W.Text(r, 10, "text"); r.text:SetPoint("LEFT", 0, 0); r.text:SetPoint("RIGHT", -70, 0); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    r.un = W.Button(r, L.PS_UNLINK, false, 18); r.un:SetPoint("RIGHT", 0, 0); r.un:SetWidth(64)
    r.un:SetScript("OnClick", function(self)
      for _, alt in ipairs(PS.Alts(self:GetParent().key)) do PS.Assign(alt, nil) end
    end)
    return r
  end)
end

local function refresh(p)
  local mine = PS.MyChars()
  for i, c in ipairs(mine) do
    local r = p.rows:Get(i)
    r.key = c.key
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 26); r:SetPoint("RIGHT", p.mine, "RIGHT", 0, 0)
    r.name:SetText(G.Display(c.key) .. (c.key == G.MyKey() and " *" or ""))
    r.main:SetShown(not c.main and c.linked)
    r.tag:SetShown(c.main); r.tag:SetText(L.PS_MAIN)
    r.link:SetShown(not c.main); r.link:SetChecked(c.linked)
  end
  p.rows:HideFrom(#mine + 1)
  p.mine:SetHeight(math.max(1, #mine * 26))
  p.vis:Refresh()
  p.visHint:SetText(L["PS_VIS_HINT_" .. PS.Visibility()] or "")


  local lead = G.IsLead()
  p.right:SetShown(lead)
  if not lead then return end
  -- persons with twinks
  local seen, list = {}, {}
  for key in pairs(G.roster) do
    local m = PS.MainOf(key)
    if not seen[m] then
      seen[m] = true
      local alts = PS.Alts(m)
      if #alts > 0 then list[#list + 1] = { key = m, alts = alts, src = PS.Source(m) } end
    end
  end
  table.sort(list, function(a, b) return G.Display(a.key) < G.Display(b.key) end)
  for i, x in ipairs(list) do
    local r = p.lRows:Get(i)
    r.key = x.key
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 20); r:SetPoint("RIGHT", p.list.content, "RIGHT", 0, 0)
    local names = {}
    for _, a in ipairs(x.alts) do names[#names + 1] = G.Display(a) end
    r.text:SetText(G.Display(x.key) .. ": " .. table.concat(names, ", ") .. "  " ..
      U.Color(T.Hex(T.Current().muted), "(" .. (L["PS_SRC_" .. (x.src or "lead")] or "") .. ")"))
    r.un:SetShown(x.src == "lead")
  end
  p.lRows:HideFrom(#list + 1)
  p.list:SetContentHeight(#list * 20)
  p.none:SetShown(#list == 0)
end

UI.AddSettingsPage("persons", {
  label = function() return L.PS_TAB end,
  build = build, refresh = refresh,
})
ns.On("PERSONS_CHANGED", function() if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end end)
