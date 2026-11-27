local ADDON, ns = ...
-- Settings page "Guild ranks" (0.9, guild leadership only): who leads the
-- guild, twink ranks, inactive members, purge, bank characters; preview and
-- protected buttons for the changes (addons may not change ranks themselves).
local U, G, T, W, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI
local L = ns.L
local R = ns.Ranks

local function rankOptions()
  local o = {}
  for i = 1, 20 do local n = G.rankNames[i]; if n then o[#o + 1] = { n, n } end end
  return o
end

local function set(field, v) ns.Profile.Update(function(pr) pr[field] = v end) end

-- A protected macro button on UIParent over a placeholder in the page
-- (anchoring it to our window would make the window protected)
local function secureSlot(parent, name, onPre)
  local th = T.Current()
  local slot = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  slot:SetHeight(26)
  W.Paint(slot, th.accent, th.title)
  slot.label = W.Text(slot, 12, "text"); slot.label:SetPoint("CENTER")
  local sb = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
  sb:SetFrameStrata("DIALOG")
  sb:RegisterForClicks("AnyUp", "AnyDown")
  sb:SetAttribute("type", "macro")
  sb:Hide()
  sb:SetScript("PreClick", function(self) onPre(self.covered) end)
  sb:HookScript("PostClick", function() ns.Schedule("gemRankRefresh", 3, function() if ns.UI.Refresh then ns.UI.Refresh() end end) end)
  sb:SetScript("OnEnter", function() slot:SetBackdropBorderColor(1, 1, 1) end)
  sb:SetScript("OnLeave", function() W.Paint(slot, th.accent, th.title) end)
  function slot.sync()
    if InCombatLockdown and InCombatLockdown() then return end
    if slot:IsVisible() and slot.active and slot:GetLeft() and slot:GetBottom() then
      local sc = (slot:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
      sb:ClearAllPoints()
      sb:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", slot:GetLeft() * sc, slot:GetBottom() * sc)
      sb:SetSize(slot:GetWidth() * sc, slot:GetHeight() * sc)
      if not sb:IsShown() then sb:Show() end
    elseif sb:IsShown() then sb:Hide() end
  end
  -- macro text and covered entries; only out of combat
  function slot.Set(macro, covered, active)
    slot:SetAlpha(active and 1 or 0.4)
    if InCombatLockdown and InCombatLockdown() then return end
    sb.covered = covered
    sb:SetAttribute("macrotext", macro)
    slot.active = active
    slot.sync()
  end
  local acc = 0
  slot:SetScript("OnUpdate", function(_, dt) acc = acc + dt; if acc > 0.2 then acc = 0; slot.sync() end end)
  slot:SetScript("OnHide", function() if not (InCombatLockdown and InCombatLockdown()) then sb:Hide() end end)
  slot.secure = sb
  return slot
end

local function para(parent, anchor, dy)
  local t = W.Text(parent, 10, "muted")
  t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, dy or -6); t:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
  t:SetJustifyH("LEFT"); t:SetSpacing(2)
  return t
end

local function build(p)
  -- left: settings (scrolls)
  local ls = W.Scroll(p)
  ls:SetPoint("TOPLEFT", 0, 0); ls:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -12, 0)
  local c = ls.content
  p.leftScroll = ls

  local s0 = UI.Section(c, L.RK_INTRO_HEAD); s0:SetPoint("TOPLEFT", 0, 0)
  p.twHint = para(c, s0, -8); p.twHint:SetText(L.RK_INTRO)
  local s2 = UI.Section(c, L.RK_INACTIVE); s2:SetPoint("TOPLEFT", p.twHint, "BOTTOMLEFT", 0, -18)
  p.inOn = W.Check(c, L.RK_INACTIVE_ON, function(_, on) set("inactiveOn", on and true or false) end)
  p.inOn:SetPoint("TOPLEFT", s2, "BOTTOMLEFT", 0, -8)
  local dl = W.Text(c, 10, "muted"); dl:SetPoint("TOPLEFT", p.inOn, "BOTTOMLEFT", 0, -12); dl:SetText(L.RK_DAYS)
  local function dayEdit(anchor, field, def)
    local e = W.Edit(c, 60, 22); e:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    e:SetNumeric(true)
    local function save(self)
      local v = tonumber(self:GetText())
      if v and v >= 1 and v ~= (ns.Profile.Get()[field] or def) then set(field, math.floor(v)) end
    end
    e:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", save)
    return e
  end
  p.days = dayEdit(dl, "inactiveDays", 30)
  p.inHint = para(c, dl, -10)

  local s3 = UI.Section(c, L.RK_PURGE); s3:SetPoint("TOPLEFT", p.inHint, "BOTTOMLEFT", 0, -18)
  p.puOn = W.Check(c, L.RK_PURGE_ON, function(_, on) set("purgeOn", on and true or false) end)
  p.puOn:SetPoint("TOPLEFT", s3, "BOTTOMLEFT", 0, -8)
  local pl = W.Text(c, 10, "muted"); pl:SetPoint("TOPLEFT", p.puOn, "BOTTOMLEFT", 0, -12); pl:SetText(L.RK_PURGE_DAYS)
  p.puDays = dayEdit(pl, "purgeDays", 90)
  p.puHint = para(c, pl, -10)

  p.remind = W.Check(c, L.RK_REMIND_ON, function(_, on) set("rankRemind", on and true or false) end)
  p.remind:SetPoint("TOPLEFT", p.puHint, "BOTTOMLEFT", 0, -16)

  -- right: rank changes (top) and purge (bottom)
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", p, "TOP", 12, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
  local top = CreateFrame("Frame", nil, right)
  top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("RIGHT", 0, 0); top:SetPoint("BOTTOM", right, "CENTER", 0, 6)
  local bottom = CreateFrame("Frame", nil, right)
  bottom:SetPoint("TOPLEFT", right, "LEFT", 0, -6); bottom:SetPoint("BOTTOMRIGHT", 0, 0)

  local sp = UI.Section(top, L.RK_PLAN); sp:SetPoint("TOPLEFT", 0, 0)
  -- addons may not set ranks (SetGuildMemberRank is forbidden): the count, then
  -- one row per character; a click on the target rank opens the guild window
  -- with that member selected, where the rank is picked in Blizzard's list
  p.count = W.Text(top, 12, "title"); p.count:SetPoint("TOPLEFT", sp, "BOTTOMLEFT", 0, -8)
  p.btnHint = para(top, p.count, -6)
  local function list(parent, anchor)
    local sc = W.Scroll(parent)
    sc:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8); sc:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    sc.rows = W.Pool(sc.content, function(pa)
      local r = CreateFrame("Frame", nil, pa)
      r:SetHeight(18)
      r.name = W.Text(r, 10, "text"); r.name:SetPoint("LEFT", 0, 0); r.name:SetWidth(120); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
      r.change = W.Text(r, 10, "text"); r.change:SetPoint("LEFT", 124, 0); r.change:SetWidth(150); r.change:SetJustifyH("LEFT"); r.change:SetWordWrap(false)
      r.why = W.Text(r, 10, "muted"); r.why:SetPoint("LEFT", 278, 0); r.why:SetPoint("RIGHT", 0, 0); r.why:SetJustifyH("LEFT"); r.why:SetWordWrap(false)
      return r
    end)
    sc.none = W.Text(parent, 10, "muted"); sc.none:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10); sc.none:SetText(L.RK_NONE)
    return sc
  end
  p.planList = W.Scroll(top)
  p.planList:SetPoint("TOPLEFT", p.btnHint, "BOTTOMLEFT", 0, -8); p.planList:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
  p.planList.rows = W.Pool(p.planList.content, function(pa)
    local r = CreateFrame("Frame", nil, pa)
    r:SetHeight(22)
    r.name = W.Text(r, 10, "text"); r.name:SetPoint("LEFT", 0, 0); r.name:SetWidth(118); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.cur = W.Text(r, 10, "muted"); r.cur:SetPoint("LEFT", 120, 0); r.cur:SetWidth(96); r.cur:SetJustifyH("LEFT"); r.cur:SetWordWrap(false)
    r.arrow = W.Text(r, 11, "title"); r.arrow:SetPoint("LEFT", 216, 0); r.arrow:SetText("»")
    r.to = W.Button(r, "", true, 20); r.to:SetPoint("LEFT", 230, 0); r.to:SetWidth(120)
    r.to:SetScript("OnClick", function(self)
      local x = self:GetParent().x
      if not x then return end
      local ok = R.OpenInGuild(x.key)
      p.pick = x
      ns.UI.Refresh()
    end)
    r.why = W.Text(r, 9, "muted"); r.why:SetPoint("LEFT", r.to, "RIGHT", 8, 0); r.why:SetPoint("RIGHT", 0, 0); r.why:SetJustifyH("LEFT"); r.why:SetWordWrap(false)
    return r
  end)
  p.planList.none = W.Text(top, 10, "muted"); p.planList.none:SetPoint("TOPLEFT", p.btnHint, "BOTTOMLEFT", 0, -10); p.planList.none:SetText(L.RK_NONE)

  local sq = UI.Section(bottom, L.RK_PURGE_LIST); sq:SetPoint("TOPLEFT", 0, 0)
  p.puCheck = W.Check(bottom, L.RK_PURGE_CHECKED, function() ns.UI.Refresh() end)
  p.puCheck:SetPoint("TOPLEFT", sq, "BOTTOMLEFT", 0, -8)
  p.puBtn = secureSlot(bottom, "GuildEventManagerPurgeButton", function(covered)
    R.PurgeClicked(covered)
    p.puCheck:SetChecked(false)
  end)
  p.puBtn:SetPoint("TOPLEFT", p.puCheck, "BOTTOMLEFT", 0, -8); p.puBtn:SetPoint("RIGHT", bottom, "RIGHT", 0, 0)
  p.puBtnHint = para(bottom, p.puBtn, -6)
  p.purgeList = list(bottom, p.puBtnHint)
end

local function fill(sc, items, text)
  for i, x in ipairs(items) do
    local r = sc.rows:Get(i)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 18); r:SetPoint("RIGHT", sc.content, "RIGHT", 0, 0)
    local a, b, c = text(x)
    r.name:SetText(a); r.change:SetText(b); r.why:SetText(c)
  end
  sc.rows:HideFrom(#items + 1)
  sc:SetContentHeight(#items * 18)
  sc.none:SetShown(#items == 0)
end

local function refresh(p)
  local pr = ns.Profile.Get()
  p.inOn:SetChecked(pr.inactiveOn ~= false)
  if not p.days:HasFocus() then p.days:SetText(tostring(pr.inactiveDays or 30)) end
  p.inHint:SetText(R.InactiveRank() and L.RK_INACTIVE_TEXT:format(pr.inactiveDays or 30) or L.RK_NO_INACTIVE)
  p.puOn:SetChecked(pr.purgeOn ~= false)
  if not p.puDays:HasFocus() then p.puDays:SetText(tostring(pr.purgeDays or 90)) end
  p.puHint:SetText(L.RK_PURGE_TEXT:format(pr.purgeDays or 90))
  p.remind:SetChecked(pr.rankRemind ~= false)
  p.leftScroll:SetContentHeight(360)

  -- rank changes
  local plan = R.Plan()
  local macro, covered = R.Macro()
  p.count:SetText(#plan > 0 and L.RK_COUNT:format(#plan) or L.RK_BUTTON_NONE)
  local pick = p.pick and G.roster[p.pick.key] and p.pick
  if pick and G.roster[pick.key].rankIndex == pick.to then pick = nil; p.pick = nil end
  p.btnHint:SetText(#plan == 0 and "" or (pick and L.RK_PICK:format(G.Display(pick.key), G.rankNames[pick.to] or "?") or L.RK_HOWTO))
  local sc = p.planList
  for i, x in ipairs(plan) do
    local r = sc.rows:Get(i)
    r.x = x
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 24); r:SetPoint("RIGHT", sc.content, "RIGHT", 0, 0)
    r.name:SetText(G.Display(x.key))
    r.cur:SetText(G.rankNames[x.from] or "?")
    W.SetLabel(r.to, G.rankNames[x.to] or "?"); r.to:SetWidth(120)
    local why = L["RK_WHY_" .. x.why] or x.why
    if x.why == "inactive" then why = why:format(math.floor(R.PersonOffDays(x.key))) end
    r.why:SetText(why)
    r:Show()
  end
  sc.rows:HideFrom(#plan + 1)
  sc:SetContentHeight(#plan * 24)
  sc.none:SetShown(#plan == 0)

  -- purge
  local purge = R.PurgePlan()
  local pm, pc = R.PurgeMacro()
  local ok = p.puCheck:GetChecked() and #purge > 0
  p.puCheck:SetShown(#purge > 0)
  p.puBtn.label:SetText(#purge > 0 and L.RK_PURGE_BUTTON:format(#purge) or L.RK_PURGE_NONE)
  p.puBtn.Set(pm, pc, ok)
  p.puBtnHint:SetText(#purge == 0 and "" or (not ok and L.RK_PURGE_FIRST or (#purge > #pc and L.RK_BATCH:format(#pc) or L.RK_PURGE_FINAL)))
  fill(p.purgeList, purge, function(x)
    local r = G.roster[x.key]
    return G.Display(x.key), r and G.rankNames[r.rankIndex] or "",
      (x.key == x.main and L.RK_MAIN or L.RK_TWINK_OF:format(G.Display(x.main))) .. " · " .. L.RK_OFF_DAYS:format(math.floor(x.off))
  end)
end

UI.AddSettingsPage("ranks", {
  label = function() return L.RK_TAB end,
  shown = function() return R.Allowed() end,
  build = build, refresh = refresh,
})
