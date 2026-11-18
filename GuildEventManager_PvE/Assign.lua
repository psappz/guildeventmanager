local ADDON, R = ...
-- Raid assignments: blessings and auras of the paladins, totems of the
-- shamans, curse and bane of the warlocks, fear ward of the priests.
-- The data follows what WoW Forever offers (checked with /gem probe, 17.11.2026):
-- no Salvation, no Blessing of Light, no Curse of Shadow; banes are their own
-- kind next to curses. Names come from the game (spell IDs) in the client
-- language; where Forever gave a spell a new ID, the addon's own text is used.
-- Everything travels with the event (e.pve.a), the raid lead changes it.
local core = R.core
local U, G, E = core.U, core.Guild, core.Events
local L = R.L

R.A_BLESS = {
  { id = "kings", sp = 20217 }, { id = "might", sp = 19740 }, { id = "wisdom", sp = 19742 },
}
R.A_AURA = {
  { id = "devotion", sp = 465 }, { id = "retribution", sp = 7294 }, { id = "concentration", sp = 19746 },
  { id = "shadowres", sp = 19876 }, { id = "frostres", sp = 19888 }, { id = "fireres", sp = 19891 },
}
R.A_ELEMENTS = { "earth", "fire", "water", "air" }
R.A_TOTEM = {
  earth = { { id = "strength", sp = 8075 }, { id = "tremor", sp = 8143 } },
  fire  = { { id = "flametongue", sp = 8227 }, { id = "magma", sp = 8190 } },
  water = { { id = "manaspring", sp = 5675 }, { id = "healing", sp = 5394 }, { id = "fireres", sp = 8184 },
            { id = "poison", sp = 8166 }, { id = "disease", sp = 8170 } },
  air   = { { id = "windfury", sp = 8512 }, { id = "grace", sp = 8835 }, { id = "natureres", sp = 10595 }, { id = "grounding", sp = 8177 } },
}
R.A_CURSE = {
  { id = "elements" }, { id = "recklessness", sp = 704 }, { id = "weakness", sp = 702 },
  { id = "tongues", sp = 1714 }, { id = "exhaustion", sp = 18223 },
}
R.A_BANE = { { id = "agony", sp = 980 }, { id = "doom", sp = 603 }, { id = "havoc" } }

-- melee classes get Might, the others Wisdom (hybrids heal or cast in most raids)
R.A_MIGHT_CLASSES = { WARRIOR = true, ROGUE = true, HUNTER = true }

local function spellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, i = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(i) == "table" and i.name then return i.name end
  end
  if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok and n then return n end end
end

local function find(list, id) for _, o in ipairs(list) do if o.id == id then return o end end end

-- full name of an option (from the game where possible)
local function text(k)
  local v = L[k]
  if v and v ~= k then return v end
end
function R.AName(list, id)
  local o = find(list, id)
  if not o then return nil end
  return spellName(o.sp) or text("RAID_A_" .. id) or id
end
-- short label for the narrow table cells
function R.AShort(kind, id)
  return text("RAID_AS_" .. kind .. "_" .. id) or text("RAID_A_" .. id) or id
end

function R.Assign(e)
  local p = R.Plan(e)
  p.a = p.a or {}
  local a = p.a
  a.pal = a.pal or {}; a.sha = a.sha or {}; a.wl = a.wl or {}; a.fw = a.fw or {}
  a.b = a.b or {}
  return a
end

---------------------------------------------------------------------------
-- Values: the standard set, and per boss setup single values that differ
-- (e.g. Fire Resistance at Onyxia). "-" at a boss means: nothing there.
-- kind/field: pal "aura" or "c:CLASS" · sha element · wl "curse"/"bane" · fw "t"
---------------------------------------------------------------------------
local function slot(t, kind, key, create)
  local k = t[kind]
  if not k then if not create then return nil end; k = {}; t[kind] = k end
  local x = k[key]
  if kind == "fw" then return k end
  if not x then if not create then return nil end; x = {}; k[key] = x end
  return x
end

local function read(t, kind, key, field)
  if not t then return nil end
  if kind == "fw" then return t.fw and t.fw[key] end
  local x = t[kind] and t[kind][key]
  if not x then return nil end
  if field:sub(1, 2) == "c:" then return x.cls and x.cls[field:sub(3)] end
  return x[field]
end

local function write(t, kind, key, field, v)
  if kind == "fw" then t.fw = t.fw or {}; t.fw[key] = v; return end
  local x = slot(t, kind, key, true)
  if field:sub(1, 2) == "c:" then x.cls = x.cls or {}; x.cls[field:sub(3)] = v else x[field] = v end
end

-- effective value at a boss setup (boss 0 or nil = standard)
function R.AGet(e, kind, key, field, boss)
  local a = R.Assign(e)
  boss = tonumber(boss) or 0
  if boss > 0 then
    local v = read(a.b[boss] or a.b[tostring(boss)], kind, key, field)
    if v == "-" then return nil, true end
    if v ~= nil then return v, true end
  end
  return read(a, kind, key, field), false
end

-- set a value; at a boss setup v = nil removes the difference, "-" means nothing
function R.ASet(e, kind, key, field, v, boss)
  if not R.CanEdit(e) then return end
  local a = R.Assign(e)
  boss = tonumber(boss) or 0
  if boss > 0 then
    a.b[boss] = a.b[boss] or {}
    write(a.b[boss], kind, key, field, v)
  else
    write(a, kind, key, field, v)
  end
  R.Changed(e)
end

local function curBoss(e, boss) return boss or R.Plan(e).b or 0 end

local function className(c)
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c
end
R.ClassName = className

-- who is in the line-up, by class
function R.AssignPlayers(e)
  local lineup = R.Lineup(e)
  local out = { pal = {}, sha = {}, wl = {}, pri = {}, tanks = {}, classes = {}, all = lineup, groupOf = {} }
  local seen = {}
  for _, x in ipairs(lineup) do
    out.groupOf[x.key] = x.group
    if x.class then
      if not seen[x.class] then seen[x.class] = true; out.classes[#out.classes + 1] = x.class end
      if x.class == "PALADIN" then out.pal[#out.pal + 1] = x end
      if x.class == "SHAMAN" then out.sha[#out.sha + 1] = x end
      if x.class == "WARLOCK" then out.wl[#out.wl + 1] = x end
      if x.class == "PRIEST" then out.pri[#out.pri + 1] = x end
    end
    if x.kind == "tank" then out.tanks[#out.tanks + 1] = x end
  end
  local order = { WARRIOR = 1, PALADIN = 2, ROGUE = 3, HUNTER = 4, SHAMAN = 5, DRUID = 6, PRIEST = 7, MAGE = 8, WARLOCK = 9 }
  table.sort(out.classes, function(x, y) return (order[x] or 99) < (order[y] or 99) end)
  -- main tank first
  table.sort(out.tanks, function(x, y) return (x.role == "mt" and 0 or 1) < (y.role == "mt" and 0 or 1) end)
  return out
end

-- setters (raid lead); boss = the boss setup (nil/0 = standard)
function R.SetBlessing(e, pal, class, id, boss) R.ASet(e, "pal", pal, "c:" .. class, id, boss) end
function R.SetAura(e, pal, id, boss) R.ASet(e, "pal", pal, "aura", id, boss) end
function R.SetTotem(e, sha, element, id, boss) R.ASet(e, "sha", sha, element, id, boss) end
function R.SetCurse(e, wl, what, id, boss) R.ASet(e, "wl", wl, what, id, boss) end
function R.SetFearWard(e, pri, tank, boss) R.ASet(e, "fw", pri, "t", tank, boss) end

-- a sensible start the raid lead adjusts
function R.AutoAssign(e)
  if not R.CanEdit(e) then return end
  local who = R.AssignPlayers(e)
  local a = R.Assign(e)
  a.pal, a.sha, a.wl, a.fw = {}, {}, {}, {}   -- the standard set; boss differences stay
  -- blessings: the first paladin Kings for everyone, the second Might / Wisdom,
  -- the third the other one of Might / Wisdom
  local auras = { "devotion", "concentration", "retribution", "fireres", "shadowres", "frostres" }
  for i, p in ipairs(who.pal) do
    local cls = {}
    for _, c in ipairs(who.classes) do
      local might = R.A_MIGHT_CLASSES[c]
      if i == 1 then cls[c] = "kings"
      elseif i == 2 then cls[c] = might and "might" or "wisdom"
      elseif i == 3 then cls[c] = might and "wisdom" or "might" end
    end
    a.pal[p.key] = { cls = cls, aura = auras[i] }
  end
  -- totems: Windfury where the group has melee, else Grace of Air; Strength of Earth, Mana Spring
  local melee = {}
  for _, x in ipairs(who.all) do if x.kind == "melee" or x.kind == "tank" then melee[x.group] = true end end
  for _, s in ipairs(who.sha) do
    a.sha[s.key] = { earth = "strength", water = "manaspring", air = melee[s.group] and "windfury" or "grace" }
  end
  -- curses: Elements, Recklessness, Weakness, ... one each; every warlock keeps Agony as bane
  local curses = { "elements", "recklessness", "weakness", "tongues", "exhaustion" }
  for i, w in ipairs(who.wl) do a.wl[w.key] = { curse = curses[i], bane = "agony" } end
  -- fear ward: one priest per tank, main tank first
  for i, p in ipairs(who.pri) do
    local t = who.tanks[i]
    if t then a.fw[p.key] = t.key end
  end
  R.Changed(e)
end

-- what is missing or twice
function R.AssignGaps(e, boss)
  boss = curBoss(e, boss)
  local who = R.AssignPlayers(e)
  local gaps = { noBless = {}, dupCurse = {}, noWF = {} }
  if #who.pal > 0 then
    for _, c in ipairs(who.classes) do
      local any = false
      for _, p in ipairs(who.pal) do if R.AGet(e, "pal", p.key, "c:" .. c, boss) then any = true end end
      if not any then gaps.noBless[c] = true end
    end
  end
  local seen = {}
  for _, w in ipairs(who.wl) do
    local c = R.AGet(e, "wl", w.key, "curse", boss)
    if c then
      if seen[c] then gaps.dupCurse[c] = true end
      seen[c] = true
    end
  end
  -- groups with melee but no Windfury totem from a shaman in the group
  local melee, wf = {}, {}
  for _, x in ipairs(who.all) do if x.kind == "melee" then melee[x.group] = true end end
  for _, s in ipairs(who.sha) do if R.AGet(e, "sha", s.key, "air", boss) == "windfury" then wf[s.group] = true end end
  if #who.sha > 0 then
    for g in pairs(melee) do if not wf[g] then gaps.noWF[#gaps.noWF + 1] = g end end
    table.sort(gaps.noWF)
  end
  return gaps
end

-- the own tasks, as lines of text
function R.MyTasks(e, key, boss)
  key = key or G.MyKey()
  boss = curBoss(e, boss)
  local who = R.AssignPlayers(e)
  local out = {}
  local function get(kind, field) return (R.AGet(e, kind, key, field, boss)) end
  local isPal, isSha, isWl = false, false, false
  for _, x in ipairs(who.pal) do if x.key == key then isPal = true end end
  for _, x in ipairs(who.sha) do if x.key == key then isSha = true end end
  for _, x in ipairs(who.wl) do if x.key == key then isWl = true end end
  if isPal then
    local p = { aura = get("pal", "aura") }
    local by = {}
    for _, c in ipairs(who.classes) do
      local id = get("pal", "c:" .. c)
      if id then by[id] = by[id] or {}; table.insert(by[id], className(c)) end
    end
    local nClasses = #who.classes
    for _, bl in ipairs(R.A_BLESS) do
      local list = by[bl.id]
      if list then
        table.sort(list)
        local whom = (#list >= nClasses and nClasses > 1) and L.RAID_A_ALL or table.concat(list, ", ")
        out[#out + 1] = L.RAID_A_TASK_BLESS:format(R.AName(R.A_BLESS, bl.id), whom)
      end
    end
    if p.aura then out[#out + 1] = R.AName(R.A_AURA, p.aura) end
  end
  if isSha then
    local t = {}
    for _, el in ipairs(R.A_ELEMENTS) do local v = get("sha", el); if v then t[#t + 1] = R.AName(R.A_TOTEM[el], v) end end
    if #t > 0 then out[#out + 1] = table.concat(t, ", ") end
  end
  if isWl then
    local t = {}
    local c, b = get("wl", "curse"), get("wl", "bane")
    if c then t[#t + 1] = R.AName(R.A_CURSE, c) end
    if b then t[#t + 1] = R.AName(R.A_BANE, b) end
    if #t > 0 then out[#out + 1] = L.RAID_A_TASK_BOSS:format(table.concat(t, " + ")) end
  end
  local fw = get("fw", "t")
  if fw then out[#out + 1] = L.RAID_A_TASK_FW:format(spellName(6346) or L.RAID_A_fearward, G.Display(fw)) end
  return out
end

-- lines for the raid chat (short, one per player)
function R.AssignLines(e, boss)
  local who = R.AssignPlayers(e)
  local lines = {}
  local function add(x)
    local tasks = R.MyTasks(e, x.key, boss)
    if #tasks > 0 then lines[#lines + 1] = G.Display(x.key) .. ": " .. table.concat(tasks, " · ") end
  end
  for _, list in ipairs({ who.pal, who.sha, who.wl, who.pri }) do for _, x in ipairs(list) do add(x) end end
  return lines
end

function R.PostAssignments(e)
  local lines = R.AssignLines(e)
  if #lines == 0 then U.Print(L.RAID_A_NONE); return end
  local ch = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY") or nil
  if not ch then U.Print(L.RAID_A_NOGROUP); return end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local t, boss = R.TemplateOf(e), R.Plan(e).b or 0
  local head = e.name .. ((boss > 0 and t) and (" · " .. R.BossName(t, boss)) or "")
  pcall(send, "[GEM] " .. L.RAID_A_HEAD:format(head), ch)
  for _, l in ipairs(lines) do pcall(send, l:sub(1, 250), ch) end
end
