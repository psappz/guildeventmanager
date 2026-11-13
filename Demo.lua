local ADDON, ns = ...
-- Demo mode for screenshots: /gem demo [alliance]
-- Fills the window with sample data for the guild "Neocortex" and invented
-- member names. Nothing is sent, nothing is saved: all demo data lives in
-- memory only and is gone after /gem demo off or /reload. While the demo
-- runs, incoming guild messages are ignored.
local U, G, T = ns.U, ns.Guild, ns.Theme
local D = {}
ns.Demo = D

local DAY = 86400

local MEMBERS = {
  { "Durgash", 0 }, { "Krazja", 1 }, { "Morvok", 1 }, { "Telanis", 2 }, { "Zul'kara", 2 }, { "Brakkar", 2 },
  { "Ishara", 3 }, { "Gorrum", 3 }, { "Velith", 3 }, { "Nazgrul", 3 }, { "Shaari", 3 }, { "Torvak", 4 },
  { "Mirela", 4 }, { "Ruk'tar", 4 }, { "Fenlira", 4 }, { "Ogrash", 4 }, { "Senjin", 4 }, { "Kael'ris", 4 },
}
local ENEMIES = { "Aldric", "Elowen", "Brannick", "Seraphine", "Torin", "Maelis", "Gerrit", "Lyanna", "Corwin", "Isolde",
  "Dorian", "Brynja", "Aeron", "Tamsin", "Halvard" }

local TEXT = {
  deDE = {
    ranks = { [0] = "Kriegshäuptling", "Offizier", "Veteran", "Krieger", "Rekrut" },
    zones = { "Vorgebirge des Hügellands", "Arathihochland", "Eschental", "Schlingendorntal", "Brachland" },
    sub = { "Tarrens Mühle", "Burg Stromgarde", "Astranaar", "Grom'gol", "Wegekreuz" },
    raid = "Überfall auf Tarrens Mühle", raidDesc = "Wir sammeln uns in Hammerfall und ziehen gemeinsam nach Tarrens Mühle. Wachen zuerst, dann der Anführer, zum Schluss setzen wir das Klanbanner.",
    goals = { "Treffpunkt Hammerfall erreicht", "3 Wachen besiegt", "Banner in Tarrens Mühle gesetzt" },
    defense = "Verteidigung von Hammerfall", rp = "Lagerfeuer in Grom'gol", ritual = "Aufnahme der Rekruten",
    meet = "Gildentreffen in Orgrimmar", raid2 = "Kriegszug ins Eschental", raid3 = "Überfall auf Southshore",
    drum = "3 Schurken an der Mühle", defGoal = "Angriff abgewehrt",
    stakes = { "ein Fass Donnerbräu", "50 Gold", "die erste Wache in Tarrens Mühle", "das Lagerfeuer-Lied" },
    oaths = { "Ich besiege den Hauptmann von Southshore", "Ich halte Hammerfall eine Woche lang", "Ich bringe Aldric zu Fall" },
  },
  enUS = {
    ranks = { [0] = "Warchief", "Officer", "Veteran", "Warrior", "Recruit" },
    zones = { "Hillsbrad Foothills", "Arathi Highlands", "Ashenvale", "Stranglethorn Vale", "The Barrens" },
    sub = { "Tarren Mill", "Stromgarde Keep", "Astranaar", "Grom'gol", "The Crossroads" },
    raid = "Raid on Tarren Mill", raidDesc = "We gather in Hammerfall and ride to Tarren Mill together. Guards first, then the leader, and finally we raise the clan banner.",
    goals = { "Reached Hammerfall", "Defeated 3 guards", "Banner raised in Tarren Mill" },
    defense = "Defense of Hammerfall", rp = "Campfire in Grom'gol", ritual = "Welcoming the recruits",
    meet = "Guild meeting in Orgrimmar", raid2 = "Warband into Ashenvale", raid3 = "Raid on Southshore",
    drum = "3 rogues at the mill", defGoal = "Attack repelled",
    stakes = { "a barrel of Thunderbrew", "50 gold", "the first guard at Tarren Mill", "the campfire song" },
    oaths = { "I will defeat the captain of Southshore", "I will hold Hammerfall for a week", "I will bring Aldric down" },
  },
}

local HORDE_RANKS = { "Scout", "Grunt", "Sergeant", "Senior Sergeant", "First Sergeant", "Stone Guard", "Blood Guard",
  "Legionnaire", "Centurion", "Champion", "Lieutenant General", "General", "Warlord", "High Warlord" }
local HORDE_RANKS_DE = { "Späher", "Grunzer", "Feldwebel", "Oberfeldwebel", "Hauptfeldwebel", "Steingardist", "Blutgardist",
  "Legionär", "Zenturio", "Champion", "Generalleutnant", "General", "Kriegsherr", "Oberster Kriegsherr" }
local ALLIANCE_RANKS = { "Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major", "Knight", "Knight-Lieutenant",
  "Knight-Captain", "Knight-Champion", "Lieutenant Commander", "Commander", "Marshal", "Field Marshal", "Grand Marshal" }
local ALLIANCE_RANKS_DE = { "Gefreiter", "Fußknecht", "Landsknecht", "Feldwebel", "Fähnrich", "Leutnant", "Hauptmann",
  "Kürassier", "Ritter der Allianz", "Feldkommandant", "Rittmeister", "Marschall", "Feldmarschall", "Großmarschall" }

local function lang() return ns.activeLocale or (GetLocale and GetLocale()) or "enUS" end

local function rankName(n)
  -- the game's own rank names are in the client language; use them only if the addon speaks it too
  if lang() == (GetLocale and GetLocale()) then
    local ok, name = pcall(GetPVPRankInfo, n + 4)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  local de = lang() == "deDE"
  if T.Faction() == "alliance" then return (de and ALLIANCE_RANKS_DE or ALLIANCE_RANKS)[n] end
  return (de and HORDE_RANKS_DE or HORDE_RANKS)[n]
end

local function key(name) return G.Key(name) end

local function build()
  local tx = TEXT[lang()] or TEXT.enUS
  local now = U.Now()
  -- own seeded generator: the same demo data every time (WoW has no math.randomseed)
  local seed = 20261107
  local function rnd(a, b)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local f = seed / 2147483648
    if not a then return f end
    if not b then return math.floor(f * a) + 1 end
    return a + math.floor(f * (b - a + 1))
  end

  -- roster
  local roster, ranks = {}, {}
  for i = 0, 4 do ranks[i] = tx.ranks[i] end
  for _, m in ipairs(MEMBERS) do
    roster[key(m[1])] = { name = m[1], rankName = tx.ranks[m[2]], rankIndex = m[2], level = 60, online = rnd() < 0.6 }
  end
  local me = key(MEMBERS[1][1])

  -- profile: the real one (settings stay readable), with manager rank 1
  local profile = U.Copy(ns.Profile.Get())
  profile.managerRank = 1; profile.managerRankName = tx.ranks[1]; profile.managerHigher = true
  profile.activeTypes = {}

  local store = { profile = profile, events = {}, ledger = {}, pvpstats = {} }
  local ev, lg = store.events, store.ledger
  local n = 0
  local function id() n = n + 1; return "demo" .. n end
  local function entry(who, pot, amt, why, ts, extra)
    local e = { id = id(), who = who, pot = pot, amt = amt, why = why, ts = ts, by = who }
    for k, v in pairs(extra or {}) do e[k] = v end
    lg[e.id] = e
    return e
  end
  local function signups(count, at)
    local s = {}
    local i = 0
    for _, m in ipairs(MEMBERS) do
      i = i + 1
      if i <= count then s[key(m[1])] = { on = true, t = at } end
    end
    return s
  end

  -- past events with attendance and points
  local past = {
    { "warband", tx.raid3, 3, 14, { tx.goals[1], tx.goals[2] }, true },
    { "warband", tx.raid2, 9, 11, { tx.goals[1], tx.goals[2], tx.goals[3] }, true },
    { "rp", tx.rp, 6, 9 }, { "ritual", tx.ritual, 13, 12 }, { "meet", tx.meet, 16, 15 },
    { "defense", tx.defense, 19, 10, { tx.goals[1] }, false }, { "warband", tx.raid, 22, 13, { tx.goals[1], tx.goals[2], tx.goals[3] }, true },
  }
  for _, p in ipairs(past) do
    local start = now - p[3] * DAY - 3600 * 2
    local e = { id = id(), type = p[1], name = p[2], desc = "", leader = me, kind = "short", start = start, finish = start + 7200,
      group = (p[1] == "warband" or p[1] == "defense" or p[1] == "ritual") and "raid" or "none", status = "done",
      signups = signups(p[4], start - DAY), attended = {}, upd = start + 7200, created = start - 2 * DAY, by = me }
    if p[5] then
      e.goals = {}
      for gi, g in ipairs(p[5]) do e.goals[#e.goals + 1] = { text = g, done = p[6] or gi == 1 } end
    end
    local done = 0
    for _, g in ipairs(e.goals or {}) do if g.done then done = done + 1 end end
    local full = e.goals and done == #e.goals
    local i = 0
    for _, m in ipairs(MEMBERS) do
      i = i + 1
      if i <= p[4] then
        local k = key(m[1])
        e.attended[k] = true
        entry(k, "event", 10, "participate", start + 7200, { ev = e.id, flag = full and "full" or nil, by = me })
        if done > 0 then entry(k, "event", done * 5, "goal", start + 7200, { ev = e.id, by = me }) end
      end
    end
    entry(me, "event", 15, "lead", start + 7200, { ev = e.id })
    ev[e.id] = e
  end

  -- running warband
  local run = { id = id(), type = "warband", name = tx.raid, desc = tx.raidDesc, leader = key("Krazja"), kind = "short",
    start = now - 40 * 60, finish = now + 80 * 60, group = "raid", gmin = 10, gmax = 40, status = "running",
    signups = signups(14, now - DAY), upd = now - 40 * 60, created = now - 2 * DAY, by = me,
    goals = { { text = tx.goals[1], done = true }, { text = tx.goals[2], done = true }, { text = tx.goals[3], done = false } } }
  ev[run.id] = run
  -- announced
  local function planned(t, name, inDays, hour, count, group, goals)
    local d = date("*t", now + inDays * DAY)
    local start = time({ year = d.year, month = d.month, day = d.day, hour = hour, min = 0 })
    local e = { id = id(), type = t, name = name, desc = "", leader = me, kind = "short", start = start, group = group,
      status = "planned", signups = signups(count, now), upd = now, created = now - DAY, by = me, goals = goals }
    ev[e.id] = e
  end
  planned("defense", tx.defense, 1, 20, 9, "raid", { { text = tx.defGoal, done = false } })
  planned("rp", tx.rp, 2, 21, 7, "none")
  planned("ritual", tx.ritual, 4, 20, 11, "raid")

  -- guild honor: kills, debts, drums over the last 25 days
  for i, m in ipairs(MEMBERS) do
    local k = key(m[1])
    local kills = math.floor((#MEMBERS - i + 2) * (3 + rnd() * 5))
    for j = 1, kills do
      local zone = rnd(#tx.zones)
      entry(k, "honor", 3, "kill", now - rnd() * 25 * DAY, { note = ENEMIES[rnd(#ENEMIES)], zone = tx.zones[zone] })
    end
    for j = 1, math.floor(kills / 12) do
      entry(k, "honor", 20, "debt", now - rnd() * 25 * DAY, { note = ENEMIES[rnd(#ENEMIES)], zone = tx.zones[rnd(#tx.zones)],
        flag = (j == 1 and i <= 3) and "cold" or nil })
    end
    for j = 1, math.floor(kills / 8) do
      entry(k, "honor", 5, "drum", now - rnd() * 25 * DAY, { note = tx.zones[rnd(#tx.zones)], flag = (j <= 2 and i <= 4) and "first" or nil })
    end
    -- PvP statistics
    local rank = math.max(1, math.min(13, 12 - i + rnd(2)))
    local sow = math.floor(kills * (0.5 + rnd() * 0.3))
    local sbg = math.floor(kills * (1 + rnd() * 2))
    store.pvpstats[k] = {
      sow = sow, sbg = sbg, ow = sow + math.floor(kills * (2 + rnd() * 3)), bg = sbg + math.floor(kills * (4 + rnd() * 6)),
      life = math.floor(kills * (25 + rnd() * 40)), dk = rnd(0, 6), today = rnd(0, 18), week = rnd(15, 140),
      yday = rnd(0, 30), lastweek = rnd(20, 160), rank = rank + 4, rankName = rankName(rank),
      high = rank + 5, highName = rankName(math.min(14, rank + 1)), prog = rnd(5, 95),
      season = ns.Points.SeasonStart(), ts = now - rnd(60, 7200),
    }
  end
  -- last season (for the podium) and duels of honor / oaths
  local lastSeason = ns.Points.SeasonStart() - 1
  for i = 1, 8 do
    local k = key(MEMBERS[i][1])
    for j = 1, (10 - i) * 4 do entry(k, "honor", 3, "kill", lastSeason - rnd() * 20 * DAY, { note = ENEMIES[rnd(#ENEMIES)], zone = tx.zones[rnd(#tx.zones)] }) end
  end
  local duels = { { 2, 5 }, { 1, 3 }, { 4, 6 }, { 2, 7 }, { 3, 1 }, { 2, 8 }, { 5, 4 } }
  for j, d in ipairs(duels) do
    local w, l = key(MEMBERS[d[1]][1]), key(MEMBERS[d[2]][1])
    entry(w, "honor", 10, "makgora", now - (j * 2.5 + rnd()) * DAY, { note = l, ch = (j % 2 == 0) and w or l,
      stake = tx.stakes[(j - 1) % #tx.stakes + 1], wit = key(MEMBERS[9][1]) })
  end
  entry(key(MEMBERS[3][1]), "honor", 25, "oath", now - 6 * DAY, { note = tx.oaths[2], flag = "lvl2" })
  entry(key(MEMBERS[6][1]), "honor", 10, "oath", now - 3 * DAY, { note = tx.oaths[3], flag = "lvl1" })

  -- a few most recent deeds, so the honor roll starts lively
  entry(me, "honor", 20, "debt", now - 300, { note = "Aldric", zone = tx.zones[1], flag = "cold" })
  entry(key("Krazja"), "honor", 5, "drum", now - 420, { note = tx.zones[1], flag = "first" })
  entry(key("Morvok"), "honor", 3, "kill", now - 600, { note = "Seraphine", zone = tx.zones[1] })
  entry(key("Telanis"), "honor", 3, "kill", now - 660, { note = "Corwin", zone = tx.zones[1] })

  -- own character: open debts, today's kills
  local char = { debts = {
    { id = id(), name = "Brannick", t = now - 2 * 3600, zone = tx.zones[1], state = "open" },
    { id = id(), name = "Lyanna", t = now - 26 * 3600, zone = tx.zones[3], state = "open" },
    { id = id(), name = "Halvard", t = now - 4 * DAY, zone = tx.zones[2], state = "open" },
  }, kills = { day = date("%Y-%m-%d", now), honor = 27, victims = {} }, hk = { ow = 412, bg = 1380, sow = 96, sbg = 214, season = ns.Points.SeasonStart() } }

  return { roster = roster, ranks = ranks, me = me, store = store, char = char, tx = tx }
end

function D.Start(faction)
  if ns.demo then D.Stop() end
  local data = build()
  D.saved = { roster = G.roster, ranks = G.rankNames, faction = T.forced }
  G.roster = data.roster
  G.rankNames = data.ranks
  G.demoMe = data.me
  ns.demoGuild = "Neocortex"
  ns.demoStore = data.store
  ns.demoChar = data.char
  if faction and faction ~= T.Faction() then
    if ns.UI and ns.UI.Frame() then U.Print(ns.L.DEMO_RELOAD); return end
    T.forced = faction
  end
  ns.demo = true
  ns.Achievements.Dirty()
  -- war drums of the PvP module
  local P = GuildEventManagerAPI.pvp
  if P and P.drums then
    D.savedDrums = P.drums
    P.drums = {}
    local now = U.Now()
    local tx = data.tx
    P.drums.d1 = { id = "d1", lvl = "help", map = 1424, x = 0.62, y = 0.21, zone = tx.zones[1], sub = tx.sub[1], text = tx.drum,
      by = G.Key("Krazja"), ts = now - 150, arrivals = 2 }
    P.drums.d2 = { id = "d2", lvl = "rally", map = 1417, x = 0.46, y = 0.38, zone = tx.zones[2], sub = tx.sub[2],
      by = G.Key("Morvok"), ts = now - 420, arrivals = 5, arrived = true }
  end
  -- duels of honor and oaths of the PvP module
  if P and P.maks then
    D.savedHonor = { P.maks, P.oaths }
    local now, tx = U.Now(), data.tx
    local function k(n) return G.Key(n) end
    P.maks = {
      m1 = { id = "m1", a = k("Krazja"), b = data.me, stake = tx.stakes[1], ts = now - 120, state = "open", wit = {} },
      m2 = { id = "m2", a = k("Morvok"), b = k("Telanis"), stake = tx.stakes[2], ts = now - 600, acc = now - 500, state = "fight", wit = {} },
    }
    P.oaths = {
      o1 = { id = "o1", by = data.me, text = tx.oaths[1], lvl = 3, ts = now - 2 * 86400, state = "open", wit = { [k("Krazja")] = true } },
      o2 = { id = "o2", by = k("Morvok"), text = tx.oaths[3], lvl = 2, ts = now - 86400, state = "open", wit = {} },
    }
  end
  U.Print(ns.L.DEMO_ON)
  if ns.UI then ns.UI.Show("pvp") end
end

function D.Stop()
  if not ns.demo then return end
  ns.demo = false
  G.roster = D.saved.roster
  G.rankNames = D.saved.ranks
  T.forced = D.saved.faction
  ns.demoStore, ns.demoChar, G.demoMe = nil, nil, nil
  local P = GuildEventManagerAPI.pvp
  if P and D.savedDrums then P.drums = D.savedDrums end
  if P and D.savedHonor then P.maks, P.oaths = D.savedHonor[1], D.savedHonor[2]; D.savedHonor = nil end
  ns.Achievements.Dirty()
  G.RequestRoster()
  U.Print(ns.L.DEMO_OFF)
  if ns.UI then ns.UI.Refresh() end
end

ns.SlashExt = ns.SlashExt or {}
ns.SlashExt.demo = function(rest)
  rest = (rest or ""):lower()
  if rest == "off" or rest == "aus" then D.Stop()
  else D.Start(rest:find("^al") and "alliance" or (rest:find("^ho") and "horde") or nil) end
end
