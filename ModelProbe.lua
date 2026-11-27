local ADDON, ns = ...
-- /gem probe model: can this client show an enemy player as a model for the
-- WANTED posters? Opens a window with three panes for the current target:
--   A  live:    the model of the unit itself (only while it exists)
--   B  rebuilt: a model of the same race and sex, dressed in the items read by
--               inspecting the target (if the client lets us inspect him)
--   C  race:    the same race and sex, without items
-- Every step is tried with pcall and written to the chat and to
-- ns.db.modelProbe (export: "Model probe"). It also notes the GUID of the
-- target: for NPCs it holds the zone id that layer addons use.
-- Test tool, not a feature.
local U = ns.U
local MP = {}
ns.ModelProbe = MP

local SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }
local RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Undead = 5, Tauren = 6,
  Gnome = 7, Troll = 8, Goblin = 9, BloodElf = 10, Draenei = 11 }

local log, win, insp
MP.RaceFile = { [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf", [5] = "Scourge", [6] = "Tauren",
  [7] = "Gnome", [8] = "Troll", [9] = "Goblin", [10] = "BloodElf", [11] = "Draenei" }

local function note(k, v)
  local line = k .. ": " .. tostring(v)
  log.lines[#log.lines + 1] = line
  print("  |cffe6ba5c[model]|r " .. line)
end

local function has(obj, name) return type(obj) == "table" and type(obj[name]) == "function" end

local function try(label, fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if ok then note(label, "ok" .. (a ~= nil and (" -> " .. tostring(a)) or "") .. (b ~= nil and (", " .. tostring(b)) or "") .. (c ~= nil and (", " .. tostring(c)) or ""))
  else note(label, "ERROR " .. tostring(a)) end
  return ok, a, b, c
end

local function pane(parent, x, title)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  p:SetPoint("TOPLEFT", x, -34)
  p:SetSize(190, 250)
  if p.SetBackdrop then
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    p:SetBackdropColor(0.08, 0.06, 0.05, 1); p:SetBackdropBorderColor(0.9, 0.73, 0.36, 1)
  end
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  t:SetPoint("BOTTOM", p, "TOP", 0, 3); t:SetText(title)
  p.titleText = title
  p.status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.status:SetPoint("BOTTOMLEFT", 4, 4); p.status:SetPoint("BOTTOMRIGHT", -4, 4); p.status:SetText("")
  return p
end

local function model(p, kind)
  local ok, m = pcall(CreateFrame, kind, nil, p)
  if not ok or not m then note(kind, "cannot be created: " .. tostring(m)); return nil end
  m:SetPoint("TOPLEFT", 1, -1); m:SetPoint("BOTTOMRIGHT", -1, 18)
  return m
end

local function build()
  local w = CreateFrame("Frame", "GuildEventManagerModelProbe", UIParent, "BackdropTemplate")
  w:SetSize(612, 300)
  w:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -140)
  w:SetFrameStrata("DIALOG")
  w:EnableMouse(true); w:SetMovable(true); w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
  if w.SetBackdrop then
    w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    w:SetBackdropColor(0.1, 0.07, 0.055, 0.96); w:SetBackdropBorderColor(0.9, 0.73, 0.36, 1)
  end
  w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  w.title:SetPoint("TOPLEFT", 10, -9)
  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  w.a = pane(w, 12, "A · live")
  w.b = pane(w, 211, "B · rebuilt + items")
  w.c = pane(w, 410, "C · race only")
  w:Hide()
  return w
end

-- B and C: a model of the given race and sex
local function custom(p, raceID, sex, label)
  local m = model(p, "DressUpModel") or model(p, "PlayerModel")
  if not m then p.status:SetText("no model frame"); return nil end
  note(label .. " methods", ("SetCustomRace=%s SetUnit=%s Undress=%s TryOn=%s SetPortraitZoom=%s SetAnimation=%s SetSequence=%s"):format(
    tostring(has(m, "SetCustomRace")), tostring(has(m, "SetUnit")), tostring(has(m, "Undress")), tostring(has(m, "TryOn")),
    tostring(has(m, "SetPortraitZoom")), tostring(has(m, "SetAnimation")), tostring(has(m, "SetSequence"))))
  if label == "B" and has(m, "SetUnit") then try(label .. " SetUnit(player)", m.SetUnit, m, "player") end
  if not has(m, "SetCustomRace") then
    -- fallback: load the bare race model by its file path
    local file = MP.RaceFile and MP.RaceFile[raceID]
    if file and has(m, "SetModel") then
      local g = (sex == 1) and "Female" or "Male"
      for _, ext in ipairs({ ".m2", ".mdx" }) do
        local path = ("Character\\%s\\%s\\%s%s%s"):format(file, g, file, g, ext)
        local ok = pcall(m.SetModel, m, path)
        local got = has(m, "GetModelFileID") and select(2, pcall(m.GetModelFileID, m)) or (has(m, "GetModel") and select(2, pcall(m.GetModel, m)))
        note(label .. " SetModel " .. path, tostring(ok) .. " · now " .. tostring(got))
      end
      p.status:SetText("SetModel by path")
    else
      p.status:SetText("no SetCustomRace")
    end
    return m
  end
  local ok = try(label .. (" SetCustomRace(%s, %s)"):format(tostring(raceID), tostring(sex)), m.SetCustomRace, m, raceID, sex)
  if has(m, "Undress") then try(label .. " Undress", m.Undress, m) end
  p.status:SetText(ok and "race set" or "SetCustomRace failed")
  return m
end

local function dress(m, links)
  if not m or not has(m, "TryOn") then return 0 end
  local n = 0
  for _, l in ipairs(links) do
    if pcall(m.TryOn, m, l) then n = n + 1 end
  end
  return n
end

local function readItems(unit)
  local links = {}
  for _, s in ipairs(SLOTS) do
    local ok, l = pcall(GetInventoryItemLink, unit, s)
    if ok and l then links[#links + 1] = l end
  end
  return links
end

local function finishInspect()
  if not insp then return end
  local links = readItems("target")
  note("inspect items", #links .. " visible item links" .. (#links > 0 and (" (first: " .. links[1] .. ")") or ""))
  local n = dress(insp.m, links)
  note("B TryOn", n .. " of " .. #links .. " items put on")
  if win and win.b then win.b.status:SetText(n .. " items on") end
  log.items = #links
  insp = nil
  pcall(ClearInspectPlayer)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("INSPECT_READY")
ev:SetScript("OnEvent", function() ns.SafeCall("modelprobe", finishInspect) end)

function MP.Run()
  if not ns.db then return end
  log = { at = date("%Y-%m-%d %H:%M"), lines = {} }
  ns.db.modelProbe = log
  U.Print("Model probe – results below and in the export (\"Model probe\")")

  local unit = UnitExists("target") and "target" or "player"
  if unit == "player" then note("target", "none – testing with yourself. Target an enemy player for the real test.") end
  local name = UnitName(unit)
  local isPlayer = UnitIsPlayer(unit)
  local enemy = UnitIsEnemy and UnitIsEnemy("player", unit)
  local okR, rName, rFile, rId = pcall(UnitRace, unit)
  local sex = UnitSex(unit)
  note("unit", ("%s · player=%s · enemy=%s · race=%s/%s/%s · sex=%s · level=%s · class=%s"):format(
    tostring(name), tostring(isPlayer), tostring(enemy), tostring(rName), tostring(rFile), tostring(rId),
    tostring(sex), tostring(UnitLevel(unit)), tostring((UnitClass(unit)))))
  note("guid", tostring(UnitGUID(unit)))
  if not isPlayer then note("hint", "target is no player – the GUID above is what a layer check would read") end

  win = win or build()
  -- fresh panes on every run (models keep state)
  for _, k in ipairs({ "a", "b", "c" }) do
    local old = win[k]
    local x = select(4, old:GetPoint(1))
    old:Hide()
    win[k] = pane(win, x, old.titleText)
  end
  win.title:SetText("GEM model probe · " .. tostring(name))
  win:Show()

  -- 2D portrait (the round one of the target frame)
  local tex = win.a:CreateTexture(nil, "OVERLAY")
  tex:SetSize(48, 48); tex:SetPoint("TOPRIGHT", -4, -4)
  try("2D SetPortraitTexture", SetPortraitTexture, tex, unit)

  -- A: live model of the unit
  local ma = model(win.a, "PlayerModel")
  if ma then
    local ok = try("A SetUnit(" .. unit .. ")", ma.SetUnit, ma, unit)
    if has(ma, "SetPortraitZoom") then try("A SetPortraitZoom(0.6)", ma.SetPortraitZoom, ma, 0.6) end
    if has(ma, "SetAnimation") then try("A SetAnimation(0)", ma.SetAnimation, ma, 0) end
    win.a.status:SetText(ok and "live model" or "SetUnit failed")
  end

  local raceID = (type(rId) == "number" and rId) or RACE_IDS[rFile or ""] or 1
  local gender = (sex == 3) and 1 or 0

  -- C: race and sex only
  custom(win.c, raceID, gender, "C")

  -- B: race and sex plus inspected items
  local mb = custom(win.b, raceID, gender, "B")
  local okC, can = pcall(CanInspect, unit)
  local okD, near = pcall(CheckInteractDistance, unit, 1)
  note("inspect", ("CanInspect=%s · in inspect range=%s"):format(tostring(okC and can), tostring(okD and near)))
  local direct = readItems(unit)
  note("items without inspect", #direct)
  if unit == "player" then
    note("B TryOn (own items)", dress(mb, direct) .. " of " .. #direct)
  elseif okC and can and mb then
    insp = { m = mb }
    local ok = try("NotifyInspect", NotifyInspect, unit)
    if ok then
      win.b.status:SetText("inspecting …")
      ns.Schedule("modelprobeInspect", 3, function()
        if insp then note("inspect", "no INSPECT_READY after 3 s – reading anyway"); ns.SafeCall("modelprobe", finishInspect) end
      end)
    else insp = nil end
  else
    win.b.status:SetText("cannot inspect")
  end
  return log
end

-- /gem probe model
local before = ns.SlashExt.probe
ns.SlashExt.probe = function(rest)
  local a = (rest or ""):lower():match("^%s*(%S*)")
  if a ~= "model" then return before(rest) end
  ns.SafeCall("modelprobe", MP.Run)
end

ns.Export.Add("Model probe", function()
  local p = ns.db and ns.db.modelProbe
  if not p then return { "not run yet (/gem probe model)" } end
  local out = { "run at: " .. p.at }
  for _, l in ipairs(p.lines) do out[#out + 1] = l end
  return out
end)

---------------------------------------------------------------------------
-- /gem probe sound: listen to sound candidates for the bounty posters.
--   /gem probe sound          list the candidates
--   /gem probe sound 3        play number 3
--   /gem probe sound all      play all, one every 4 seconds
--   /gem probe sound find     list SOUNDKIT names of this client that fit
--   /gem probe sound kit 6595 / file 567275   play any SoundKitID / FileDataID
-- Game files only play by FileDataID or SoundKitID in WoW Forever (paths fail).
-- Results go to ns.db.soundProbe (export "Sound probe").
---------------------------------------------------------------------------
local SP = {}
ns.SoundProbe = SP
local CAND = {
  { "new",  "Kriegstrommeln (Oger-Trommeln)",          "file", 567275 },
  { "new",  "Glocke Allianz (Sturmwind)",               "kit",  6594 },
  { "new",  "Glocke Allianz (Datei)",                   "file", 566564 },
  { "new",  "Glocke Horde",                             "kit",  6595 },
  { "new",  "Glocke Nachtelfen",                        "file", 566558 },
  { "new",  "Glocke Stämme (Tauren)",                   "file", 566027 },
  { "new",  "Glocke Karazhan",                          "file", 566254 },
  { "new",  "Schlachtzugswarnung",                      "kit",  8959 },
  { "new",  "Bereitschaftscheck",                       "kit",  8960 },
  { "new",  "Schlachtfeld-Einladung",                   "key",  "PVP_THROUGH_QUEUE" },
  { "new",  "Jubel",                                    "file", 567283 },
  { "new",  "Explosion",                                "file", 566982 },
  { "new",  "Tor Lordaeron (Wham!)",                    "file", 566946 },
  { "won",  "Gewehrschuss (zufällig, Classic)",         "kit",  1148 },
  { "won",  "Gewehrschuss 1",                           "file", 921248 },
  { "won",  "Gewehrschuss 2",                           "file", 921250 },
  { "won",  "Gewehrschuss 3",                           "file", 921252 },
  { "won",  "Gewehrschuss 4",                           "file", 921254 },
  { "won",  "Gewehrschuss 5",                           "file", 921256 },
  { "won",  "Gewehrschuss 6",                           "file", 921258 },
  { "won",  "Maschinengewehr",                          "kit",  18445 },
}
local found = {}

local function slog()
  ns.db.soundProbe = ns.db.soundProbe or { at = date("%Y-%m-%d %H:%M"), res = {} }
  return ns.db.soundProbe
end

local function play(i)
  local c = CAND[i] or found[i - 100]
  if not c then U.Print("Keine Nummer " .. tostring(i)); return end
  local ok, will
  if c[3] == "file" then ok, will = pcall(PlaySoundFile, c[4], "Master")
  else
    local id = c[3] == "key" and SOUNDKIT and SOUNDKIT[c[4]] or c[4]
    if not id then ok, will = true, nil
    else ok, will = pcall(PlaySound, id, "Master") end
  end
  local res = (ok and will) and "spielt" or (ok and "kein Ton (gibt es nicht oder Ton aus)" or ("Fehler: " .. tostring(will)))
  print(("  |cffe6ba5c[sound %d]|r %s · %s %s · %s"):format(i, c[2], c[3], tostring(c[4]), res))
  slog().res[tostring(i)] = c[2] .. " = " .. res
end

local function list()
  U.Print("Sound-Hörprobe: /gem probe sound <Nummer> · all · find · kit <ID> · file <ID>")
  local head
  for i, c in ipairs(CAND) do
    if c[1] ~= head then head = c[1]; print(head == "new" and "  Neues Kopfgeld:" or "  Kopfgeld eingelöst:") end
    print(("    %2d  %s"):format(i, c[2]))
  end
  if #found > 0 then
    print("  Aus dem Client (find):")
    for i, c in ipairs(found) do print(("    %3d  %s"):format(100 + i, c[2])) end
  end
end

local function find()
  wipe(found)
  if type(SOUNDKIT) ~= "table" then U.Print("SOUNDKIT gibt es in diesem Client nicht."); return end
  local keys = {}
  for k, v in pairs(SOUNDKIT) do
    local u = tostring(k):upper()
    if type(v) == "number" and (u:find("DRUM") or u:find("BELL") or u:find("GONG") or u:find("GUN") or u:find("SHOT")
      or u:find("CANNON") or u:find("HORN") or u:find("FLAG") or u:find("PVP") or u:find("WARNING") or u:find("BOUNTY")) then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do found[#found + 1] = { "find", "SOUNDKIT." .. k, "kit", SOUNDKIT[k] } end
  slog().find = keys
  list()
end

local before2 = ns.SlashExt.probe
ns.SlashExt.probe = function(rest)
  local a, b = (rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
  if a ~= "sound" then return before2(rest) end
  if b == "" then list()
  elseif b == "find" then find()
  elseif b == "kit" or b == "file" then
    local id = tonumber((rest or ""):match("^%s*%S+%s+%S+%s+(%d+)"))
    if not id then U.Print("Benutzung: /gem probe sound kit <SoundKitID> · /gem probe sound file <FileDataID>"); return end
    CAND[900] = { "test", (b == "kit" and "SoundKit " or "Datei ") .. id, b, id }
    play(900)
  elseif b == "all" then
    U.Print("Spiele alle " .. #CAND .. " nacheinander, alle 4 Sekunden …")
    for i = 1, #CAND do ns.Schedule("gemSoundProbe" .. i, (i - 1) * 4, function() play(i) end) end
  else play(tonumber(b) or 0) end
end

ns.Export.Add("Sound probe", function()
  local p = ns.db and ns.db.soundProbe
  if not p then return { "not run yet (/gem probe sound)" } end
  local out = { "run at: " .. p.at }
  for k, v in pairs(p.res) do out[#out + 1] = k .. ": " .. v end
  return out
end)

---------------------------------------------------------------------------
-- /gem probe layer: which functions of this client know the layer?
-- (WoW Forever shows "Layer B" in its own UI.) Lists every global and every
-- C_ namespace member whose name contains "layer", "shard" or "phase"; calls
-- the ones that only read (Get…, Is…, Has…, Current…) and shows their result.
---------------------------------------------------------------------------
local function layerProbe(tag, words, extra)
  tag, words = tag or "layer", words or { "layer", "shard", "phase" }
  local lines = {}
  local function add(s) lines[#lines + 1] = s; print("  |cffe6ba5c[" .. tag .. "]|r " .. s) end
  local function hit(n)
    n = n:lower():gsub("player", "")
    for _, w in ipairs(words) do if n:find(w, 1, true) then return true end end
    return false
  end
  local function tryCall(label, fn)
    local short = label:match("[%.:]?([%w_]+)$") or label
    if not (short:find("^Get") or short:find("^Is") or short:find("^Has") or short:find("^Current")) then add(label .. " (not called)"); return end
    local res = { pcall(fn) }
    local out = {}
    for i = 2, math.min(#res, 6) do
      local v = res[i]
      if type(v) == "table" then
        local t = {}
        for k, x in pairs(v) do if #t < 8 then t[#t + 1] = tostring(k) .. "=" .. tostring(x) end end
        out[#out + 1] = "{" .. table.concat(t, ", ") .. "}"
      else out[#out + 1] = tostring(v) end
    end
    add(label .. " -> " .. (res[1] and "" or "ERROR ") .. table.concat(out, ", "))
  end
  U.Print(tag == "layer" and "Layer probe – results below and in the export (\"Layer probe\")"
    or "Realm probe – results below and in the export (\"Realm probe\")")
  if extra then extra(add, tryCall) end
  local names = {}
  for k, v in pairs(_G) do
    if type(k) == "string" then
      if hit(k) and type(v) == "function" then names[#names + 1] = { k, v }
      elseif hit(k) and type(v) == "table" then names[#names + 1] = { k .. " (table)", nil }
      end
      if type(v) == "table" and k:find("^C_") then
        for m, fn in pairs(v) do
          if type(m) == "string" and hit(m) and type(fn) == "function" then names[#names + 1] = { k .. "." .. m, fn } end
        end
        if hit(k) then
          for m, fn in pairs(v) do if type(fn) == "function" then names[#names + 1] = { k .. "." .. tostring(m), fn } end end
        end
      end
    end
  end
  table.sort(names, function(a, b) return a[1] < b[1] end)
  if #names == 0 then add("nothing found") end
  local seen = {}
  for _, n in ipairs(names) do
    if not seen[n[1]] then
      seen[n[1]] = true
      if n[2] then tryCall(n[1], n[2]) else add(n[1]) end
    end
  end
  if tag ~= "layer" then
    if ns.db then ns.db.realmProbe = { at = date("%Y-%m-%d %H:%M"), lines = lines } end
    return
  end
  if UnitGUID then add("target GUID: " .. tostring(UnitGUID("target"))) end
  if ns.db then ns.db.layerProbe = { at = date("%Y-%m-%d %H:%M"), lines = lines } end
end

-- /gem probe realm: what does the client say about region, ruleset and realm?
-- (Forever has mega realms per region and ruleset.)
local function realmExtra(add, tryCall)
  local function call(label, fn, ...)
    if type(fn) ~= "function" then add(label .. " -> (missing)"); return end
    local res = { pcall(fn, ...) }
    local out = {}
    for i = 2, math.min(#res, 8) do out[#out + 1] = string.format("%q", tostring(res[i])) end
    add(label .. " -> " .. (res[1] and "" or "ERROR ") .. table.concat(out, ", "))
  end
  call("GetCurrentRegion()", GetCurrentRegion)
  call("GetCurrentRegionName()", GetCurrentRegionName)
  call("GetRealmName()", GetRealmName)
  call("GetNormalizedRealmName()", GetNormalizedRealmName)
  call("GetRealmID()", GetRealmID)
  call("UnitFullName(player)", UnitFullName, "player")
  call("UnitGUID(player)", UnitGUID, "player")
  call("UnitFactionGroup(player)", UnitFactionGroup, "player")
  call("GetLocale()", GetLocale)
  call("GetBuildInfo()", GetBuildInfo)
  call("C_GameRules.IsHardcoreActive()", C_GameRules and C_GameRules.IsHardcoreActive)
  call("C_Seasons.HasActiveSeason()", C_Seasons and C_Seasons.HasActiveSeason)
  call("C_Seasons.GetActiveSeason()", C_Seasons and C_Seasons.GetActiveSeason)
  call("IsWarModeDesired()", C_PvP and C_PvP.IsWarModeDesired)
  call("GetZonePVPInfo()", GetZonePVPInfo)
  -- the realm part the server adds to names in the guild roster
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  local me = UnitName("player")
  for i = 1, n do
    local full = GetGuildRosterInfo(i)
    if type(full) == "string" and me and full:find(me, 1, true) == 1 then add("guild roster, own name: " .. full); break end
  end
  for i = 1, math.min(n, 3) do add("guild roster " .. i .. ": " .. tostring((GetGuildRosterInfo(i)))) end
end

local before4 = ns.SlashExt.probe
ns.SlashExt.probe = function(rest)
  local a = (rest or ""):lower():match("^%s*(%S*)")
  if a ~= "realm" then return before4(rest) end
  ns.SafeCall("realmprobe", layerProbe, "realm", { "region", "realm", "ruleset", "gamerule", "hardcore", "season" }, realmExtra)
end

ns.Export.Add("Realm probe", function()
  local p = ns.db and ns.db.realmProbe
  if not p then return { "not run yet (/gem probe realm)" } end
  local out = { "run at: " .. p.at }
  for _, l in ipairs(p.lines) do out[#out + 1] = l end
  return out
end)

local before3 = ns.SlashExt.probe
ns.SlashExt.probe = function(rest)
  local a = (rest or ""):lower():match("^%s*(%S*)")
  if a ~= "layer" then return before3(rest) end
  ns.SafeCall("layerprobe", layerProbe)
end

ns.Export.Add("Layer probe", function()
  local p = ns.db and ns.db.layerProbe
  if not p then return { "not run yet (/gem probe layer)" } end
  local out = { "run at: " .. p.at }
  for _, l in ipairs(p.lines) do out[#out + 1] = l end
  return out
end)
