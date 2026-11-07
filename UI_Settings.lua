local ADDON, ns = ...
-- Settings tab. Guild settings (activation, event rights, points, season,
-- event types) are the guild profile: only managers change them, and the
-- event rights only the guild master. Personal settings sit at the bottom right.
local U, G, T, W, UI, P = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI, ns.Profile
local L = ns.L
local V = {}

local LANGS = { { "auto", "Auto" }, { "enUS", "English" }, { "deDE", "Deutsch" }, { "frFR", "Français" },
  { "esES", "Español" }, { "itIT", "Italiano" }, { "ptBR", "Português" } }

local function num(e, fallback)
  local v = tonumber((string.gsub(e:GetText() or "", ",", ".")))
  return v or fallback
end

local function build(p)
  local th = T.Current()
  -- left column
  local left = CreateFrame("Frame", nil, p)
  left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -12, 0)
  local s1 = UI.Section(left, L.SET_ACTIVATION); s1:SetPoint("TOPLEFT", 0, 0)
  p.act = W.Box(left, 10, 64, "panel2")
  p.act:SetPoint("TOPLEFT", 0, -22); p.act:SetPoint("RIGHT", 0, 0)
  p.actText = W.Text(p.act, 11, "text")
  p.actText:SetPoint("TOPLEFT", 10, -8); p.actText:SetPoint("RIGHT", -10, 0)
  p.actText:SetSpacing(2)
  p.mkMarker = W.Button(left, L.SET_MARKER_BTN, true, 22)
  p.mkMarker:SetPoint("TOPLEFT", p.act, "BOTTOMLEFT", 0, -6)
  p.mkMarker:SetScript("OnClick", function()
    local m = G.Marker() or G.NewMarker()
    W.Dialog({ text = L.SET_MARKER_TEXT, edit = true, editText = m, noCancel = true, accept = CLOSE or "OK" })
  end)
  p.recheck = W.Button(left, L.SET_RECHECK, false, 22)
  p.recheck:SetPoint("LEFT", p.mkMarker, "RIGHT", 6, 0)
  p.recheck:SetScript("OnClick", function() G.markerRead = nil; G.RequestRoster(); ns.Schedule("gemRecheck", 1.5, ns.CheckActivation) end)

  local s2 = UI.Section(left, L.SET_RIGHTS); s2:SetPoint("TOPLEFT", p.mkMarker, "BOTTOMLEFT", 0, -16)
  local lr = W.Text(left, 10, "muted"); lr:SetPoint("TOPLEFT", s2, "BOTTOMLEFT", 0, -8); lr:SetText(L.SET_RANK)
  p.rank = W.Dropdown(left, 220, function()
    local o = { { -1, L.SET_RANK_NONE } }
    for i = 1, 9 do if G.rankNames[i] then o[#o + 1] = { i, i .. " · " .. G.rankNames[i] } end end
    return o
  end, function() return P.Get().managerRank or -1 end, function(v)
    P.Update(function(pr)
      pr.managerRank = (v >= 0) and v or nil
      pr.managerRankName = (v >= 0) and G.rankNames[v] or nil
    end)
  end)
  p.rank:SetPoint("TOPLEFT", lr, "BOTTOMLEFT", 0, -3)
  p.higher = W.Check(left, L.SET_HIGHER, function(self, on) P.Update(function(pr) pr.managerHigher = on end) end)
  p.higher:SetPoint("LEFT", p.rank, "RIGHT", 12, 0)
  p.rightsHint = W.Text(left, 10, "muted")
  p.rightsHint:SetPoint("TOPLEFT", p.rank, "BOTTOMLEFT", 0, -6); p.rightsHint:SetPoint("RIGHT", left, "RIGHT", 0, 0)

  local s3 = UI.Section(left, L.SET_POINTS); s3:SetPoint("TOPLEFT", p.rightsHint, "BOTTOMLEFT", 0, -14)
  p.fields = {}
  local function field(key, x, y, anchor)
    local l = W.Text(left, 10, "muted"); l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y); l:SetText(L["SET_" .. key])
    local e = W.Edit(left, 90, 22); e:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3)
    p.fields[key] = e
    return e
  end
  field("W_EVENT", 0, -8, s3); field("W_HONOR", 104, -8, s3); field("W_ACH", 208, -8, s3)
  field("P_PART", 0, -54, s3); field("P_LEAD", 104, -54, s3); field("P_LEADMIN", 208, -54, s3)
  local ls = W.Text(left, 10, "muted"); ls:SetPoint("TOPLEFT", s3, "BOTTOMLEFT", 0, -100); ls:SetText(L.SET_SEASON)
  p.season = W.Dropdown(left, 194, function()
    return { { "2weeks", L.SEASON_2weeks }, { "month", L.SEASON_month }, { "quarter", L.SEASON_quarter } }
  end, function() return P.Get().season end, function(v) P.Update(function(pr) pr.season = v end) end)
  p.season:SetPoint("TOPLEFT", ls, "BOTTOMLEFT", 0, -3)
  local lb = W.Text(left, 10, "muted"); lb:SetPoint("TOPLEFT", s3, "BOTTOMLEFT", 208, -100); lb:SetText(L.SET_BANNER)
  p.bannerTh = W.Edit(left, 130, 22); p.bannerTh:SetPoint("TOPLEFT", lb, "BOTTOMLEFT", 0, -3)
  p.applyPts = W.Button(left, L.SAVE, true, 22)
  p.applyPts:SetPoint("TOPLEFT", p.season, "BOTTOMLEFT", 0, -10)
  p.applyPts:SetScript("OnClick", function()
    local f = p.fields
    P.Update(function(pr)
      pr.weights.event = num(f.W_EVENT, pr.weights.event)
      pr.weights.honor = num(f.W_HONOR, pr.weights.honor)
      pr.weights.ach = num(f.W_ACH, pr.weights.ach)
      pr.pts.participate = math.max(0, math.floor(num(f.P_PART, pr.pts.participate)))
      pr.pts.lead = math.max(0, math.floor(num(f.P_LEAD, pr.pts.lead)))
      pr.pts.leadMin = math.max(1, math.floor(num(f.P_LEADMIN, pr.pts.leadMin)))
      local th3 = {}
      for v in (p.bannerTh:GetText() or ""):gmatch("%d+") do th3[#th3 + 1] = tonumber(v) end
      if #th3 == 3 and th3[1] < th3[2] and th3[2] < th3[3] then pr.banner = th3
      else U.Print(L.SET_BANNER_BAD) end
    end)
    U.Print(L.SAVED)
  end)

  -- right column
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", p, "TOP", 12, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
  local s4 = UI.Section(right, L.SET_TYPES); s4:SetPoint("TOPLEFT", 0, 0)
  p.typesBox = W.Box(right, 10, 170, "panel2")
  p.typesBox:SetPoint("TOPLEFT", 0, -22); p.typesBox:SetPoint("RIGHT", 0, 0)
  p.typesScroll = W.Scroll(p.typesBox)
  p.typesScroll:SetPoint("TOPLEFT", 8, -8); p.typesScroll:SetPoint("BOTTOMRIGHT", -8, 8)
  p.types = W.Pool(p.typesScroll.content, function(parent)
    local c = W.Check(parent, "")
    c.mod = W.Text(parent, 10, "muted")
    c.mod:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    c.mod:SetPoint("TOP", c, "TOP", 0, 0)
    c:HookScript("OnHide", function(self) self.mod:Hide() end)
    c:HookScript("OnShow", function(self) self.mod:Show() end)
    return c
  end)
  p.typesHint = W.Text(right, 10, "muted")
  p.typesHint:SetPoint("TOPLEFT", p.typesBox, "BOTTOMLEFT", 0, -6); p.typesHint:SetPoint("RIGHT", 0, 0)
  p.typesHint:SetText(L.SET_TYPES_HINT)
  p.resetBtn = W.Button(right, L.SET_RESET, false, 22)
  p.resetBtn:SetPoint("TOPLEFT", p.typesHint, "BOTTOMLEFT", 0, -10)
  p.resetBtn:SetScript("OnClick", function()
    W.Dialog({ text = L.SET_RESET_CONFIRM, onAccept = P.ResetDefaults })
  end)
  p.sendBtn = W.Button(right, L.SET_SEND, true, 22)
  p.sendBtn:SetPoint("LEFT", p.resetBtn, "RIGHT", 6, 0)
  p.sendBtn:SetScript("OnClick", function() P.Broadcast(); U.Print(L.SET_SENT) end)

  local s5 = UI.Section(right, L.SET_PERSONAL); s5:SetPoint("TOPLEFT", p.resetBtn, "BOTTOMLEFT", 0, -18)
  local ll = W.Text(right, 10, "muted"); ll:SetPoint("TOPLEFT", s5, "BOTTOMLEFT", 0, -8); ll:SetText(L.SET_LANGUAGE)
  p.lang = W.Dropdown(right, 160, function() return LANGS end, function() return ns.db.language or "auto" end, function(v)
    ns.db.language = v
    U.Print(L.SET_LANGUAGE_RELOAD)
  end)
  p.lang:SetPoint("TOPLEFT", ll, "BOTTOMLEFT", 0, -3)
  p.minimap = W.Check(right, L.SET_MINIMAP, function(self, on)
    if (not ns.db.minimap.hide) ~= on then ns.Minimap.ToggleShown() end
  end)
  p.minimap:SetPoint("TOPLEFT", p.lang, "BOTTOMLEFT", 0, -10)
  p.silent = W.Check(right, L.SET_SILENT, function(self, on) ns.db.silent = on end)
  p.silent:SetPoint("TOPLEFT", p.minimap, "BOTTOMLEFT", 0, -8)
  p.notify = W.Check(right, L.SET_NOTIFY, function(self, on) ns.db.notify = on end)
  p.notify:SetPoint("TOPLEFT", p.silent, "BOTTOMLEFT", 0, -8)
end

local function refresh(p)
  local th = T.Current()
  local pr = P.Get()
  local manager = G.IsManager()
  local leader = G.IsLeader()

  -- activation
  local marker = G.Marker()
  if not G.InGuild() then
    p.actText:SetText(L.NO_GUILD)
    p.act:SetBackdropBorderColor(unpack(th.line))
  elseif marker then
    p.actText:SetText(L.SET_ACTIVE:format(G.Name(), marker))
    p.act:SetBackdropBorderColor(th.good[1], th.good[2], th.good[3], 1)
  else
    p.actText:SetText(leader and L.NOT_ACTIVE_GM or L.NOT_ACTIVE_MEMBER)
    p.act:SetBackdropBorderColor(th.accent[1], th.accent[2], th.accent[3], 1)
  end
  p.act:SetHeight(p.actText:GetStringHeight() + 18)
  p.mkMarker:SetShown(leader)
  p.recheck:ClearAllPoints()
  if leader then p.recheck:SetPoint("LEFT", p.mkMarker, "RIGHT", 6, 0) else p.recheck:SetPoint("TOPLEFT", p.act, "BOTTOMLEFT", 0, -6) end

  -- rights
  p.rank:Refresh()
  p.rank:SetEnabled(leader)
  p.higher:SetChecked(pr.managerHigher)
  p.higher:SetEnabled(leader)
  local who = pr.managerRank and (pr.managerRank .. " · " .. (G.rankNames[pr.managerRank] or pr.managerRankName or "?")) or L.SET_RANK_NONE
  p.rightsHint:SetText((manager and L.SET_YOU_MANAGER or L.SET_YOU_MEMBER) .. "  " .. L.SET_RIGHTS_NOW:format(who))

  -- points (do not overwrite while typing)
  local f = p.fields
  local function set(e, v) if not e:HasFocus() then e:SetText(tostring(v)) end end
  set(f.W_EVENT, pr.weights.event); set(f.W_HONOR, pr.weights.honor); set(f.W_ACH, pr.weights.ach)
  set(f.P_PART, pr.pts.participate); set(f.P_LEAD, pr.pts.lead); set(f.P_LEADMIN, pr.pts.leadMin)
  set(p.bannerTh, table.concat(pr.banner or {}, " / "))
  for _, e in pairs(f) do e:SetEnabled(manager) end
  p.bannerTh:SetEnabled(manager)
  p.season:Refresh(); p.season:SetEnabled(manager)
  p.applyPts:SetShown(manager)

  -- event types
  local list = ns.Modules.AllTypes()
  for i, t in ipairs(list) do
    local c = p.types:Get(i)
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", 2, -(i - 1) * 22 - 2)
    c.text:SetText(ns.Modules.TypeName(t.id) .. (t.missing and ("  " .. U.Color(U.WARN, L.MODULE_MISSING)) or ""))
    local mod = ns.Modules.modules[t.module]
    c.mod:SetText(mod and (mod.name or L[mod.nameKey]) or tostring(t.module or ""))
    c:SetChecked(P.IsTypeActive(t.id))
    c:SetEnabled(manager)
    c.typeId = t.id
    c:SetScript("OnClick", function(self)
      if not G.IsManager() then return end
      local on = not P.IsTypeActive(self.typeId)
      P.Update(function(pp) pp.activeTypes[self.typeId] = on end)
    end)
  end
  p.types:HideFrom(#list + 1)
  p.typesScroll:SetContentHeight(#list * 22 + 4)
  p.resetBtn:SetShown(manager)
  p.sendBtn:SetShown(manager)

  -- personal
  p.lang:Refresh()
  p.minimap:SetChecked(not ns.db.minimap.hide)
  p.silent:SetChecked(ns.db.silent)
  p.notify:SetChecked(ns.db.notify ~= false)
end

UI.RegisterView("settings", {
  label = function() return L.TAB_SETTINGS end,
  build = build,
  refresh = refresh,
})
