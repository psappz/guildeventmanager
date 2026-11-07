local ADDON, P = ...
-- War drums (Horde) / storm bells (Alliance): a call to a place in three
-- levels. Help: every member. Rally and attack: guild event managers.
-- Whoever follows and arrives in time gets honor; the first one is marked.
local core = P.core
if not core then return end
local U, G, T, C, Pts = core.U, core.Guild, core.Theme, core.Comm, core.Points
local L = P.L

P.LEVELS = { "help", "rally", "attack" }
P.drums = {}   -- id -> drum

local function position()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return nil end
  local x, y = pos:GetXY()
  if not x or (x == 0 and y == 0) then return nil end
  return map, x, y
end
P.Position = position

function P.CanDrum(level)
  if level == "help" then return true end
  return G.IsManager()
end

function P.LevelName(level) return L["PVP_LVL_" .. (level or "help")] end

function P.Drum(level, text)
  level = level or "help"
  if not C.CanSend() then U.Print(core.L.NOT_ACTIVE); return end
  if not P.CanDrum(level) then U.Print(core.L.NO_RIGHTS); return end
  if not P.OpenWorld() then U.Print(L.PVP_DRUM_INSTANCE); return end
  local map, x, y = position()
  if not map then U.Print(L.PVP_DRUM_NOPOS); return end
  local d = { id = U.NewId(), lvl = level, map = map, x = math.floor(x * 1000) / 1000, y = math.floor(y * 1000) / 1000,
    zone = GetZoneText and GetZoneText() or "", sub = GetSubZoneText and GetSubZoneText() or "",
    text = (text and text ~= "") and text:sub(1, 80) or nil, by = G.MyKey(), ts = U.Now(), mine = true, arrivals = 0 }
  P.drums[d.id] = d
  C.Send("DRUM", { d = { id = d.id, lvl = d.lvl, map = d.map, x = d.x, y = d.y, zone = d.zone, sub = d.sub, text = d.text, by = d.by, ts = d.ts } })
  U.Print(L.PVP_DRUM_SENT:format(T.Word("DRUM"), P.LevelName(level)))
  if core.UI then core.UI.Refresh() end
end

function P.DrumText(d)
  local where = d.zone .. ((d.sub and d.sub ~= "" and d.sub ~= d.zone) and (" – " .. d.sub) or "")
  return L.PVP_DRUM_LINE:format(T.Word("DRUM"), P.LevelName(d.lvl), G.Display(d.by), where,
    math.floor(d.x * 100), math.floor(d.y * 100)) .. (d.text and (": " .. d.text) or "")
end

function P.SetWaypoint(d)
  if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return false end
  local ok = pcall(function()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(d.map, d.x, d.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end)
  return ok
end

-- Drums of the last minutes, newest first
function P.ActiveDrums()
  local list, now = {}, U.Now()
  local window = (P.Rules().drumWindow or 10) * 60
  for id, d in pairs(P.drums) do
    if now - d.ts <= window then list[#list + 1] = d
    elseif now - d.ts > 3600 then P.drums[id] = nil end
  end
  table.sort(list, function(a, b) return a.ts > b.ts end)
  return list
end

C.On("DRUM", function(data, from)
  local d = data.d
  if type(d) ~= "table" or not d.id or P.drums[d.id] then return end
  d.lvl = d.lvl or "help"
  if d.lvl ~= "help" and not G.IsManager(from) then return end
  d.by = from
  d.x, d.y, d.map = tonumber(d.x), tonumber(d.y), tonumber(d.map)
  if not (d.x and d.y and d.map) then return end
  d.arrivals = 0
  d.ts = U.Now()   -- own clock: the arrival window starts on receipt
  P.drums[d.id] = d
  P.Notice(P.DrumText(d))
  P.PlaySignal()
  if not (core.db and core.db.pvpNoWaypoint) then P.SetWaypoint(d) end
  if core.UI then core.UI.Refresh() end
  P.TickSoon()
end)

C.On("DRUMARR", function(data)
  local d = data.id and P.drums[data.id]
  if d then d.arrivals = (d.arrivals or 0) + 1 end
end)

-- Arrival check every 3 seconds while a drum is open
function P.Tick()
  local open = false
  local r = P.Rules()
  local radius = (r.drumRadius or 4) / 100
  for _, d in ipairs(P.ActiveDrums()) do
    if not d.mine and not d.arrived then
      open = true
      local map, x, y = position()
      if map == d.map and math.sqrt((x - d.x) ^ 2 + (y - d.y) ^ 2) <= radius then
        d.arrived = true
        local first = (d.arrivals or 0) == 0
        Pts.AddSelf("honor", r.drum, "drum", { flag = first and "first" or nil, note = d.zone })
        C.Send("DRUMARR", { id = d.id })
        U.Print(L.PVP_DRUM_ARRIVED:format(r.drum) .. (first and (" " .. L.PVP_DRUM_FIRST) or ""))
      end
    end
  end
  if open then core.Schedule("gemPvpDrumTick", 3, P.Tick) end
end

function P.TickSoon() core.Schedule("gemPvpDrumTick", 1, P.Tick) end

-- /gem drum help|rally|attack [text]   (German: hilfe|sammeln|angriff)
local ALIAS = { help = "help", hilfe = "help", rally = "rally", sammeln = "rally", attack = "attack", angriff = "attack" }
core.SlashExt.drum = function(rest)
  local lvl, text = (rest or ""):match("^(%S*)%s*(.-)$")
  P.Drum(ALIAS[(lvl or ""):lower()] or "help", ALIAS[(lvl or ""):lower()] and text or rest)
end
core.SlashExt.trommel = core.SlashExt.drum
core.SlashExt.glocke = core.SlashExt.drum
