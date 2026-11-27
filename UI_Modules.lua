local ADDON, ns = ...
-- Modules of the guild (API 7): the info card (from the bell or the settings)
-- and the settings page "Modules" with interest per add-on module.
local U, G, T, W, UI = ns.U, ns.Guild, ns.Theme, ns.W, ns.UI
local K = ns.Catalog
local L = ns.L
local MU = {}
ns.ModuleUI = MU

local function title(id)
  local info = K.Info(id)
  local def = ns.Modules.modules[id]
  if def then return def.name or (def.nameKey and L[def.nameKey]) or id end
  return info and info.name or id
end

local function statusText(id)
  if K.IsCore(id) then return U.Color("ff6fbf73", L.MOD_CORE_TAG) end
  if ns.Modules.Installed(id) then return U.Color("ff6fbf73", L.MOD_INSTALLED) end
  return U.Color(U.WARN, L.MOD_NOT_INSTALLED)
end

---------------------------------------------------------------------------
-- Info card
---------------------------------------------------------------------------
local function buildCard()
  local win = ns.Float.Get("modinfo", { title = "", width = 380, height = 300, strata = "DIALOG", point = { "CENTER", 0, 60 } })
  local c = win.content
  win.status = W.Text(c, 11, "text"); win.status:SetPoint("TOPLEFT", 0, -2); win.status:SetPoint("RIGHT", 0, 0)
  win.desc = W.Text(c, 11, "text"); win.desc:SetPoint("TOPLEFT", win.status, "BOTTOMLEFT", 0, -8); win.desc:SetPoint("RIGHT", 0, 0)
  win.desc:SetSpacing(2)
  win.points = W.Text(c, 11, "text"); win.points:SetPoint("TOPLEFT", win.desc, "BOTTOMLEFT", 0, -8); win.points:SetPoint("RIGHT", 0, 0)
  win.points:SetSpacing(3)
  win.get = W.Text(c, 10, "muted"); win.get:SetPoint("TOPLEFT", win.points, "BOTTOMLEFT", 0, -10); win.get:SetPoint("RIGHT", 0, 0)
  win.get:SetSpacing(2)
  win.yes = W.Button(c, L.MOD_JOIN, true, 22); win.yes:SetWidth(150)
  win.yes:SetPoint("BOTTOMLEFT", 0, 0)
  win.no = W.Button(c, L.MOD_NOT_INTERESTED, false, 22); win.no:SetWidth(170)
  win.no:SetPoint("LEFT", win.yes, "RIGHT", 8, 0)
  win.yes:SetScript("OnClick", function() K.SetInterest(win.mod, true); win:Close() end)
  win.no:SetScript("OnClick", function() K.SetInterest(win.mod, false); win:Close() end)
  return win
end

function MU.Show(id)
  if not id then return end
  local win = MU.card or buildCard()
  MU.card = win
  win.mod = id
  local info = K.Info(id) or {}
  win:SetTitle(L.MOD_CARD_TITLE:format(title(id)))
  local by = info.by and L.MOD_BY:format(G.Display(info.by)) or ""
  win.status:SetText(statusText(id) .. (by ~= "" and ("  ·  " .. by) or ""))
  local desc = info.desc
  local def = ns.Modules.modules[id]
  local a = def and type(def.about) == "table" and def.about
  if a and a.descKey then desc = L[a.descKey] end      -- own language when installed
  win.desc:SetText(desc and desc ~= "" and desc or "")
  local pts = {}
  for _, p in ipairs(info.points or {}) do pts[#pts + 1] = "• " .. p end
  win.points:SetText(table.concat(pts, "\n"))
  local lines = {}
  if not ns.Modules.Installed(id) and not K.IsCore(id) then
    lines[#lines + 1] = L.MOD_GET_HINT
    if info.get then lines[#lines + 1] = L.MOD_GET:format(info.get) end
  end
  if info.v then lines[#lines + 1] = L.MOD_VERSION:format(info.v, K.OwnVersion(id) or "–") end
  win.get:SetText(table.concat(lines, "\n"))
  local optional = not K.IsCore(id)
  win.yes:SetShown(optional); win.no:SetShown(optional)
  if optional then
    local on = K.IsInterested(id)
    W.SetLabel(win.yes, on and U.Color("ff6fbf73", L.MOD_JOIN) or L.MOD_JOIN)
    W.SetLabel(win.no, (not on) and U.Color(U.WARN, L.MOD_NOT_INTERESTED) or L.MOD_NOT_INTERESTED)
  end
  local h = 28 + win.status:GetStringHeight() + 8 + win.desc:GetStringHeight() + 8 + win.points:GetStringHeight() + 10 + win.get:GetStringHeight() + (optional and 40 or 14) + 12
  win:Resize(380, math.max(160, h))
  ns.Notices.Remove("mod:" .. id)
  win:Open()
end

---------------------------------------------------------------------------
-- Settings page "Modules"
---------------------------------------------------------------------------
local function ids()
  local seen, list = {}, {}
  local function add(id) if id and not seen[id] then seen[id] = true; list[#list + 1] = id end end
  for _, id in ipairs(ns.Modules.order or {}) do if id ~= "core" then add(id) end end
  for id in pairs(K.List()) do add(id) end
  table.sort(list, function(a, b)
    local ca, cb = K.IsCore(a), K.IsCore(b)
    if ca ~= cb then return ca end
    return title(a) < title(b)
  end)
  return list
end

local function build(p)
  p.head = UI.Section(p, L.MOD_PAGE); p.head:SetPoint("TOPLEFT", 0, 0)
  p.hint = W.Text(p, 10, "muted"); p.hint:SetPoint("TOPLEFT", 0, -24); p.hint:SetPoint("RIGHT", 0, 0)
  p.hint:SetText(L.MOD_PAGE_HINT); p.hint:SetSpacing(2)
  p.alertChat = W.Check(p, L.ALERT_CHAT, function(_, on) if ns.db then ns.db.alertChat = on or nil end end)
  p.alertChat:SetPoint("BOTTOMLEFT", 2, 4)
  p.scroll = W.Scroll(p)
  p.scroll:SetPoint("TOPLEFT", 0, -64); p.scroll:SetPoint("BOTTOMRIGHT", 0, 26)
  p.rows = W.Pool(p.scroll.content, function(parent)
    local r = W.Box(parent, 10, 50, "panel2")
    r.name = W.Text(r, 12, "title"); r.name:SetPoint("TOPLEFT", 10, -8)
    r.state = W.Text(r, 10, "text"); r.state:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.info = W.Button(r, L.MOD_INFO, false, 20); r.info:SetWidth(70); r.info:SetPoint("RIGHT", -8, 0)
    r.info:SetScript("OnClick", function() MU.Show(r.id) end)
    r.toggle = W.Check(r, L.MOD_JOIN, function(_, on) K.SetInterest(r.id, on) end)
    r.toggle:SetPoint("RIGHT", r.info, "LEFT", -120, 0)
    r.remove = W.Button(r, L.MOD_REMOVE, false, 20); r.remove:SetWidth(90)
    r.remove:SetPoint("RIGHT", r.info, "LEFT", -8, 0)
    r.remove:SetScript("OnClick", function()
      W.Dialog({ text = L.MOD_REMOVE_Q:format(title(r.id)), onAccept = function() K.Remove(r.id) end })
    end)
    -- 0.9: areas of the module (guild master unlocks them)
    r.areaLabel = W.Text(r, 10, "muted"); r.areaLabel:SetPoint("TOPLEFT", r.state, "BOTTOMLEFT", 0, -8)
    r.areaChecks = {}
    return r
  end)
end

local function refresh(p)
  p.alertChat:SetChecked(ns.db and ns.db.alertChat)
  local list = ids()
  local y = 0
  local mgr = G.IsManager()
  for i, id in ipairs(list) do
    local r = p.rows:Get(i)
    r.id = id
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", p.scroll.content, "RIGHT", -2, 0)
    r.name:SetText(title(id))
    local own, info = K.OwnVersion(id), K.Info(id)
    local v = own and ("  ·  " .. L.MOD_YOURS:format(own)) or ""
    r.state:SetText(statusText(id) .. v)
    local optional = not K.IsCore(id)
    r.toggle:SetShown(optional)
    if optional then r.toggle:SetChecked(K.IsInterested(id)) end
    r.remove:SetShown(mgr and optional and info ~= nil)
    if r.remove:IsShown() then r.toggle:ClearAllPoints(); r.toggle:SetPoint("RIGHT", r.remove, "LEFT", -110, 0)
    else r.toggle:ClearAllPoints(); r.toggle:SetPoint("RIGHT", r.info, "LEFT", -110, 0) end
    -- areas: the guild master ticks, everybody else reads
    local areas = K.Areas(id)
    local gm = G.IsLeader()
    for _, c in ipairs(r.areaChecks) do c:Hide() end
    if #areas > 0 then
      r.areaLabel:Show()
      if gm then
        r.areaLabel:SetText(L.AREA_UNLOCK)
        local prev = r.areaLabel
        for j, a in ipairs(areas) do
          local c = r.areaChecks[j]
          if not c then
            c = W.Check(r, "", function(self, on) K.SetArea(self.mod, self.area, on) end)
            r.areaChecks[j] = c
          end
          c.mod, c.area = id, a.id
          c.text:SetText(a.name)
          c:SetChecked(K.AreaOn(id, a.id))
          c:ClearAllPoints(); c:SetPoint("LEFT", prev, "RIGHT", j == 1 and 10 or 70, 0)
          c:Show()
          prev = c
        end
      else
        local parts = {}
        for _, a in ipairs(areas) do
          parts[#parts + 1] = a.name .. ": " .. (K.AreaOn(id, a.id) and ("|cff6fbf73" .. L.AREA_ON .. "|r") or ("|cff9a8f80" .. L.AREA_OFF .. "|r"))
        end
        r.areaLabel:SetText(table.concat(parts, "   ·   "))
      end
      r:SetHeight(70)
    else
      r.areaLabel:Hide()
      r:SetHeight(50)
    end
    y = y + r:GetHeight() + 4
  end
  p.rows:HideFrom(#list + 1)
  p.scroll:SetContentHeight(y)
end

UI.AddSettingsPage("modules", {
  label = function() return L.MOD_PAGE end,
  build = build,
  refresh = refresh,
})
