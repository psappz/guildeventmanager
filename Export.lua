local ADDON, ns = ...
-- Data export for support: /gem export shows everything this client knows about
-- the own character, guild state, ledger and errors as plain text in a window.
-- The player copies it (Ctrl+A, Ctrl+C) and sends it, e.g. pasted into Discord
-- (long texts become a file there). Modules add their own section with
-- API.AddExport(id, fn) -> fn() returns a list of lines.
local U, G, T, W, Pts = ns.U, ns.Guild, ns.Theme, ns.W, ns.Points
local X = {}
ns.Export = X
X.sections = {}   -- { { id, fn } }

function X.Add(id, fn)
  for _, s in ipairs(X.sections) do if s.id == id then s.fn = fn; return end end
  X.sections[#X.sections + 1] = { id = id, fn = fn }
end

local function secret(v) return issecretvalue and issecretvalue(v) or false end

-- one value in one line, tables flat ("k=v, k=v"), nested tables shortened
function X.Val(v, depth)
  depth = depth or 0
  if secret(v) then return "<secret>" end
  local t = type(v)
  if t == "string" then return (v:gsub("[\r\n|]", " ")) end
  if t ~= "table" then return tostring(v) end
  if depth > 1 then return "{…}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for i, k in ipairs(keys) do
    if i > 30 then parts[#parts + 1] = "… +" .. (#keys - 30); break end
    parts[#parts + 1] = tostring(k) .. "=" .. X.Val(v[k], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function meta(addon, field)
  local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if not f then return "?" end
  local ok, v = pcall(f, addon, field)
  return ok and v or "?"
end

local function when(ts) return ts and date("%Y-%m-%d %H:%M:%S", ts) or "-" end

local function coreLines(full)
  local out = {}
  local function add(k, v) out[#out + 1] = k .. ": " .. X.Val(v) end
  local ver, build = GetBuildInfo and GetBuildInfo()
  out[#out + 1] = "== GuildEventManager export =="
  add("exported", when(U.Now()))
  add("core", meta(ADDON, "Version")); add("pvp", meta("GuildEventManager_PvP", "Version"))
  add("client", tostring(ver) .. " (" .. tostring(build) .. ")"); add("locale", GetLocale and GetLocale())
  add("addon language", ns.activeLocale); add("demo", ns.demo and true or false)
  local mods = {}
  for _, id in ipairs(ns.Modules.order or {}) do mods[#mods + 1] = id end
  add("modules", table.concat(mods, ","))

  out[#out + 1] = ""
  out[#out + 1] = "== character =="
  add("key", G.MyKey()); add("unit name", { UnitName("player") }); add("realm", GetRealmName and GetRealmName())
  add("faction", T.Faction()); add("level", UnitLevel and UnitLevel("player"))

  out[#out + 1] = ""
  out[#out + 1] = "== guild =="
  add("in guild", G.InGuild()); add("name", G.Name()); add("store key", G.StoreKey())
  add("activated", G.IsActivated()); add("marker", G.Marker()); add("marker read", G.markerRead)
  add("last active", G.lastActive and string.format("%.0fs ago", GetTime() - G.lastActive) or "-")
  add("leader", G.IsLeader()); add("manager", G.IsManager()); add("rank", G.RankOf(G.MyKey()))
  local n = 0
  for _ in pairs(G.roster or {}) do n = n + 1 end
  add("roster", n)
  local pr = ns.Profile.Get()
  add("profile", { v = pr.v, by = pr.by, season = pr.season, pts = pr.pts })
  add("can send", ns.Comm.CanSend()); add("send queue", ns.Comm.QueueLength and ns.Comm.QueueLength())
  add("silent", ns.db and ns.db.silent)

  out[#out + 1] = ""
  out[#out + 1] = "== ledger =="
  local s = ns.Store()
  local all, mine, sum = 0, {}, {}
  local me = G.MyKey()
  for _, e in pairs(s and s.ledger or {}) do
    all = all + 1
    if e.who == me then
      mine[#mine + 1] = e
      local k = tostring(e.pot) .. "/" .. tostring(e.why)
      sum[k] = (sum[k] or 0) + (e.reverted and 0 or (tonumber(e.amt) or 0))
    end
  end
  table.sort(mine, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
  add("entries (guild)", all); add("entries (mine)", #mine); add("mine by pot/why", sum)
  for _, period in ipairs({ "week", "season", "all" }) do
    local t = Pts.Totals(period)[me]
    add("my total " .. period, t and math.floor(t.total) or 0)
  end
  add("guild total season", math.floor(Pts.GuildTotal("season")))
  local limit = full and #mine or math.min(#mine, 40)
  out[#out + 1] = ("-- my last %d entries (time pot why amt note flag by) --"):format(limit)
  for i = 1, limit do
    local e = mine[i]
    out[#out + 1] = ("%s %s %s %s %s %s %s%s"):format(when(e.ts), tostring(e.pot), tostring(e.why), tostring(e.amt),
      X.Val(e.note or "-"), tostring(e.flag or "-"), tostring(e.by or "-"), e.reverted and " REVERTED" or "")
  end

  out[#out + 1] = ""
  out[#out + 1] = "== events =="
  local st = {}
  for _, e in pairs(s and s.events or {}) do st[e.status or "?"] = (st[e.status or "?"] or 0) + 1 end
  add("by status", st)

  out[#out + 1] = ""
  out[#out + 1] = "== achievements (mine) =="
  local ids = {}
  for _, e in ipairs(ns.Achievements.Earned()[me] or {}) do ids[#ids + 1] = e.id end
  add("earned", table.concat(ids, ","))
  add("honor name", ns.Achievements.HonorName(me))

  out[#out + 1] = ""
  out[#out + 1] = "== errors =="
  local errs = ns.db and ns.db.errors or {}
  if #errs == 0 then out[#out + 1] = "none" end
  for i = math.max(1, #errs - 9), #errs do
    local e = errs[i]
    out[#out + 1] = ("%s [%s] %s"):format(tostring(e.t), tostring(e.where), X.Val(e.msg))
  end
  return out
end

function X.Build(full)
  local lines = {}
  local ok, res = pcall(coreLines, full)
  if ok then for _, l in ipairs(res) do lines[#lines + 1] = l end
  else lines[#lines + 1] = "core section failed: " .. tostring(res) end
  for _, sec in ipairs(X.sections) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== " .. sec.id .. " =="
    local ok2, res2 = pcall(sec.fn, full)
    if ok2 and type(res2) == "table" then
      for _, l in ipairs(res2) do lines[#lines + 1] = tostring(l) end
    else
      lines[#lines + 1] = "section failed: " .. tostring(res2)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "== end =="
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Window: read-only text, "select all" button
---------------------------------------------------------------------------
local win
local function window()
  if win then return win end
  local th = T.Current()
  win = CreateFrame("Frame", "GuildEventManagerExport", UIParent, "BackdropTemplate")
  win:SetSize(640, 460); win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  W.Paint(win, th.bg, th.border)
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  tinsert(UISpecialFrames, "GuildEventManagerExport")
  win.title = W.Text(win, 14, "title"); win.title:SetPoint("TOPLEFT", 14, -12)
  win.title:SetText(ns.L.EXPORT_TITLE)
  win.hint = W.Text(win, 10, "muted"); win.hint:SetPoint("TOPLEFT", 14, -32); win.hint:SetPoint("RIGHT", -14, 0)
  win.hint:SetSpacing(2); win.hint:SetText(ns.L.EXPORT_HINT)
  win.close = W.Button(win, CLOSE or "Close", false, 22); win.close:SetPoint("BOTTOMRIGHT", -12, 10)
  win.close:SetScript("OnClick", function() win:Hide() end)
  win.sel = W.Button(win, ns.L.EXPORT_SELECT, true, 22); win.sel:SetPoint("RIGHT", win.close, "LEFT", -6, 0)
  win.full = W.Button(win, ns.L.EXPORT_FULL, false, 22); win.full:SetPoint("BOTTOMLEFT", 12, 10)
  local box = W.Box(win, 10, 10, "panel2")
  box:SetPoint("TOPLEFT", 12, -66); box:SetPoint("BOTTOMRIGHT", -12, 40)
  local sc = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  sc:SetPoint("TOPLEFT", 6, -6); sc:SetPoint("BOTTOMRIGHT", -26, 6)
  local eb = CreateFrame("EditBox", nil, sc)
  eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetMaxLetters(0)
  eb:SetFont("Fonts\\ARIALN.TTF", 11, "")
  eb:SetWidth(570)
  eb:SetTextColor(th.text[1], th.text[2], th.text[3])
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); win:Hide() end)
  -- read only: typing restores the export
  eb:SetScript("OnTextChanged", function(self, user) if user and win.text then self:SetText(win.text); self:HighlightText() end end)
  sc:SetScrollChild(eb)
  win.edit = eb
  win.sel:SetScript("OnClick", function() eb:SetFocus(); eb:HighlightText() end)
  win.full:SetScript("OnClick", function() X.Show(true) end)
  return win
end

function X.Show(full)
  local w = window()
  w.text = X.Build(full)
  w.edit:SetText(w.text)
  w:Show()
  w.edit:SetFocus(); w.edit:HighlightText()
  U.Print(ns.L.EXPORT_DONE:format(#w.text))
end

ns.SlashExt = ns.SlashExt or {}
ns.SlashExt.export = function(rest) X.Show(rest and rest:find("full") and true or false) end
