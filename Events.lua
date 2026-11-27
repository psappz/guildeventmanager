local ADDON, ns = ...
-- Guild events: announced, started and ended by guild event managers.
-- Run types: short (one evening), multiday, multiweek, season (whole season).
-- Group requirement: none, party, raid, teams.
local U, G, C, T = ns.U, ns.Guild, ns.Comm, ns.Theme
local E = {}
ns.Events = E

E.KINDS = { "short", "multiday", "multiweek", "season" }
E.GROUPS = { "none", "party", "raid", "teams" }
E.STATUS = { planned = 1, running = 2, done = 3, cancelled = 4 }
-- sign-up states: in (yes), tent (tentative), late, bench (volunteers to sit out), out (no)
E.SIGN = { "in", "tent", "late", "bench", "out" }
local SIGN_OK = { ["in"] = true, tent = true, late = true, bench = true, out = true }
E.COMMENT_MAX = 60

-- Who may create / edit / run an event of a type: guild event managers, plus
-- whatever the type allows (raids: a rank set in the settings)
-- Officers, the guild leadership and the guild master may lead every event
-- (0.9): manager rank, lead ranks (incl. GM), officer/council/GM posts in the
-- org chart – for the person, so his twinks too
function E.CanLeadAny(key)
  key = key or G.MyKey()
  local main = ns.Persons and ns.Persons.MainOf(key) or key
  local chars = ns.Persons and ns.Persons.Chars and ns.Persons.Chars(main) or { main }
  local list = { key }
  for _, k in ipairs(chars) do if k ~= key then list[#list + 1] = k end end
  for _, k in ipairs(list) do
    if G.IsManager(k) or G.IsLead(k) then return true end
  end
  if ns.Struct and ns.Struct.AllNodes then
    for _, n in ipairs(ns.Struct.AllNodes()) do
      if n.who and (n.kind == "off" or n.kind == "gm" or n.kind == "council")
        and (ns.Persons and ns.Persons.MainOf(n.who) or n.who) == main then return true end
    end
  end
  return false
end

-- 0.9: may a new event of this type be created here and now? Areas the guild
-- master has not unlocked and holidays outside their time are closed. Only
-- for creating: events that arrive from others are not checked against it.
function E.TypeOpen(typeId)
  local t = typeId and ns.Modules.Type(typeId)
  if not t then return true end
  if ns.Catalog and not ns.Catalog.TypeOpen(t) then return false end
  if ns.Holidays and not ns.Holidays.TypeOpen(t) then return false end
  return true
end

function E.CanCreate(typeId, key)
  if E.CanLeadAny(key) then return true end
  local t = typeId and ns.Modules.Type(typeId)
  if t and type(t.canCreate) == "function" then
    local ok, res = pcall(t.canCreate, key or G.MyKey())
    return ok and res and true or false
  end
  return false
end
function E.CanManage(e, key)
  if not e then return G.IsManager(key) end
  if E.IsLeader(e, key) then return true end   -- the event's own leaders
  return E.CanCreate(e.type, key)
end

-- Event leadership (0.9): one or more leaders; e.leader stays the first one
function E.Leaders(e)
  if not e then return {} end
  if type(e.leaders) == "table" and #e.leaders > 0 then return e.leaders end
  return e.leader and { e.leader } or {}
end

function E.IsLeader(e, key)
  key = key or G.MyKey()
  for _, k in ipairs(E.Leaders(e)) do if k == key then return true end end
  return false
end

-- Raid events (PvE raid types) need at least one raid lead among the leaders
function E.IsRaid(typeId) return type(typeId) == "string" and typeId:sub(1, 5) == "raid_" end

-- nil = fine, else the error text
function E.CheckLeaders(typeId, leaders)
  if type(leaders) ~= "table" or #leaders == 0 then return ns.L.ED_ERR_LEAD end
  if E.IsRaid(typeId) and ns.Struct then
    for _, k in ipairs(leaders) do if ns.Struct.IsRaidLead(k) or E.CanLeadAny(k) then return nil end end
    return ns.L.ED_ERR_RAIDLEAD
  end
end

local function events()
  local s = ns.Store()
  return s and s.events or {}
end

function E.Get(id) return events()[id] end

-- Sorted: running, planned (soonest first), then done/cancelled (newest first)
function E.List(filter)
  local list = {}
  for _, e in pairs(events()) do
    if not filter or filter(e) then list[#list + 1] = e end
  end
  table.sort(list, function(a, b)
    local sa, sb = E.STATUS[a.status] or 9, E.STATUS[b.status] or 9
    if sa ~= sb then return sa < sb end
    if sa <= 2 then return (a.start or 0) < (b.start or 0) end
    return (a.start or 0) > (b.start or 0)
  end)
  return list
end

function E.IsOpen(e) return e.status == "planned" or e.status == "running" end

function E.Icon(e)
  local t = ns.Modules.Type(e.type)
  return (t and t.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function E.TypeMissing(e) return ns.Modules.Type(e.type) == nil end

---------------------------------------------------------------------------
-- Writing (managers)
---------------------------------------------------------------------------
local function send(e) C.Send("EVT", { e = e }) end

function E.Save(e)
  if not E.CanManage(e) then U.Print(ns.L.NO_RIGHTS); return nil end
  e.fields = E.CleanFields(e.fields)
  e.set = E.CleanSettings(e.type, e.set, e)
  if ns.Teams then e.teams = ns.Teams.Clean(e.teams) end
  if ns.Series then e.rep = ns.Series.Clean(e.rep); if e.rep and not e.series then e.series = e.id end end
  e.upd = math.max(U.Now(), (e.upd or 0) + 1)
  events()[e.id] = e
  send(e)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return e
end

-- fields: type, name, desc, kind, start, finish, group, gmin, gmax
function E.Create(fields)
  if not E.CanCreate(fields.type) then U.Print(ns.L.NO_RIGHTS); return nil end
  if not E.TypeOpen(fields.type) then U.Print(ns.L.TYPE_CLOSED); return nil end
  local t = ns.Modules.Type(fields.type)
  local e = {
    id = U.NewId(), type = fields.type,
    name = (fields.name and fields.name ~= "") and fields.name or ns.Modules.TypeName(fields.type),
    desc = fields.desc or "",
    leader = (fields.leaders and fields.leaders[1]) or fields.leader or G.MyKey(),
    leaders = fields.leaders,
    kind = fields.kind or (t and t.kind) or "short",
    start = fields.start or U.Now(),
    finish = fields.finish,
    group = fields.group or (t and t.group) or "none",
    gmin = fields.gmin, gmax = fields.gmax,
    lvl = tonumber(fields.lvl), -- lowest character level that is asked to sign up, nil = all
    remind = fields.remind,     -- remind members to sign up (nil = the type's default)
    pts = fields.pts,  -- own participation points, nil = profile default
    goals = fields.goals, -- { { text, done } }
    fields = fields.fields, -- own questions of this event { { id, label, kind, options } }
    set = fields.set,       -- settings of the event leader (type's `settings`)
    rep = ns.Series and ns.Series.Clean(fields.rep) or nil,  -- repeat (API 7)
    status = "planned", signups = {}, created = U.Now(), by = G.MyKey(),
  }
  if e.kind == "season" then
    e.start = ns.Points.SeasonStart(); e.finish = ns.Points.SeasonEnd()
  end
  if e.rep then e.series = e.id end
  E.Save(e)
  U.Print(ns.L.EVT_ANNOUNCED:format(e.name))
  if e.rep and ns.Series then ns.SafeCall("series", ns.Series.Fill) end
  return e
end

function E.Start(e)
  e.status = "running"; e.started = U.Now()
  E.Save(e)
  C.Send("EVTSTART", { ev = e.id })
  ns.Fire("EVENT_STARTED", e, true)
end

function E.Cancel(e)
  e.status = "cancelled"
  E.Save(e)
  ns.Fire("EVENT_CANCELLED", e)
end

-- attended: { key = true }; writes participation and organiser points
-- res (API 7, results screen of the leader): { rows = { [key] = { pp = place points,
-- bo = bonus, v = value, pl = place } }, note = text } -> booked and kept as protocol
function E.End(e, attended, res)
  local p = ns.Profile.Get()
  local per = tonumber(e.pts) or p.pts.participate
  local n = 0
  e.attended = {}
  local book = G.IsManager()
  if not book then per = 0; U.Print(ns.L.EVT_END_NO_POINTS) end
  local done, total = E.GoalCount(e)
  local full = total > 0 and done == total
  local t = ns.Modules.Type(e.type)
  for key, on in pairs(attended or {}) do
    if on then
      e.attended[key] = true
      n = n + 1
      -- the type may multiply the points for taking part (raids: early sign-up)
      local factor = 1
      if t and t.pointsFactor then
        local ok, f = pcall(t.pointsFactor, e, key)
        if ok and tonumber(f) and f > 0 then factor = f end
      end
      if per > 0 then ns.Points.Add(key, "event", math.floor(per * factor + 0.5), "participate", e.id, nil, full and { flag = "full" } or nil) end
      if book and done > 0 and (p.pts.goal or 0) > 0 then ns.Points.Add(key, "event", done * p.pts.goal, "goal", e.id) end
    end
  end
  if book and n >= (p.pts.leadMin or 5) and (p.pts.lead or 0) > 0 then
    for _, k in ipairs(E.Leaders(e)) do ns.Points.Add(k, "event", p.pts.lead, "lead", e.id) end
  end
  -- results of the referee: place points and bonuses, kept as a protocol on the event
  if type(res) == "table" then
    local rows = {}
    for key, r in pairs(type(res.rows) == "table" and res.rows or {}) do
      local pp, bo = math.floor(tonumber(r.pp) or 0), math.floor(tonumber(r.bo) or 0)
      if book and pp ~= 0 then ns.Points.Add(key, "event", pp, "place", e.id, nil, r.pl and { place = r.pl } or nil) end
      if book and bo ~= 0 then ns.Points.Add(key, "event", bo, "bonus", e.id) end
      rows[#rows + 1] = { k = key, v = tonumber(r.v), pl = tonumber(r.pl), pp = pp, bo = bo, p = e.attended[key] and true or nil }
    end
    table.sort(rows, function(a, b)
      if (a.pl or 999) ~= (b.pl or 999) then return (a.pl or 999) < (b.pl or 999) end
      return a.k < b.k
    end)
    e.result = { at = U.Now(), by = G.MyKey(), note = type(res.note) == "string" and res.note:sub(1, 200) or nil, rows = rows }
  end
  e.status = "done"; e.ended = U.Now()
  E.Save(e)
  ns.Fire("EVENT_ENDED", e, e.attended)
  U.Print(ns.L.EVT_ENDED:format(e.name, n))
end

function E.GoalCount(e)
  local done, total = 0, 0
  for _, g in ipairs(e.goals or {}) do
    total = total + 1
    if g.done then done = done + 1 end
  end
  return done, total
end

function E.ToggleGoal(e, i)
  local g = e.goals and e.goals[i]
  if not g or not E.CanManage(e) then return end
  g.done = not g.done
  E.Save(e)
end

-- Everyone who could have taken part: guild members in my group plus sign-ups
function E.Candidates(e)
  local list, have = {}, {}
  local function add(key, inGroup)
    if key and G.roster[key] and not have[key] then
      have[key] = true
      list[#list + 1] = { key = key, inGroup = inGroup, signed = E.IsSigned(e, key) }
    end
  end
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  if n > 0 then
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
      local unit = raid and ("raid" .. i) or (i == n and "player" or ("party" .. i))
      local k = G.UnitKey(unit)
      if not k and ns.Persons then
        -- a twink outside the guild counts for its person (0.9; known to the
        -- leadership when the member shares his characters)
        local nm, second = UnitName(unit)
        if nm then k = ns.Persons.ExternalOwner((second and second ~= "") and (nm .. " " .. second) or nm) end
      end
      add(k, true)
    end
  else
    add(G.MyKey(), true)
  end
  for key, s in pairs(e.signups or {}) do if s.on and s.st ~= "bench" then add(key, false) end end
  table.sort(list, function(a, b) return G.Display(a.key) < G.Display(b.key) end)
  return list
end

---------------------------------------------------------------------------
-- Sign-ups (every member)
---------------------------------------------------------------------------
-- state of a member's sign-up: "in" | "tent" | "late" | "bench" | "out" | nil
function E.Status(e, key)
  local s = e and e.signups and e.signups[key or G.MyKey()]
  if not s then return nil end
  if s.st and SIGN_OK[s.st] then return s.st end
  return s.on and "in" or "out"
end

function E.Signup(e, key) return e and e.signups and e.signups[key or G.MyKey()] end

-- taking part: yes or late (tentative and bench are not counted)
function E.IsSigned(e, key)
  local st = E.Status(e, key)
  return st == "in" or st == "late"
end

function E.SignCount(e, st)
  local n = 0
  for key in pairs(e.signups or {}) do
    local x = E.Status(e, key)
    if st then if x == st then n = n + 1 end
    elseif x == "in" or x == "late" then n = n + 1 end
  end
  return n
end

-- sign-ups sorted by time, { key, st, c, f, t }
function E.SignupList(e)
  local list = {}
  for key, s in pairs(e.signups or {}) do
    list[#list + 1] = { key = key, st = E.Status(e, key), c = s.c, f = s.f or {}, t = tonumber(s.t) or 0 }
  end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.key < b.key end)
  return list
end

---------------------------------------------------------------------------
-- Sign-up fields: questions of the event type (modules, API) and of the event
-- itself (event editor). kind: auto | choice | multi | number | check | text
---------------------------------------------------------------------------
function E.Fields(e)
  local out = {}
  local t = e and ns.Modules.Type(e.type)
  for _, f in ipairs(t and t.signupFields or {}) do out[#out + 1] = f end
  for _, f in ipairs(e and e.fields or {}) do out[#out + 1] = f end
  return out
end

-- The event's own questions (event editor, travels with the event): only
-- plain data, a few kinds, short texts – also for events from other members
E.Q_MAX, E.Q_OPTS = 5, 6
E.Q_KINDS = { choice = true, number = true, text = true }
function E.CleanFields(list)
  if type(list) ~= "table" then return nil end
  local out, seen = {}, {}
  for _, f in ipairs(list) do
    if #out >= E.Q_MAX then break end
    if type(f) == "table" and E.Q_KINDS[f.kind] and type(f.id) == "string" and f.id:match("^q%d%d?$") and not seen[f.id]
      and type(f.label) == "string" and f.label ~= "" then
      seen[f.id] = true
      local q = { id = f.id, kind = f.kind, label = f.label:sub(1, 60), required = f.required and true or nil, yn = f.yn and true or nil }
      if f.kind == "choice" then
        q.options = {}
        if q.yn then
          q.options = { { "yes", "YES" }, { "no", "NO" } }
        else
          for _, o in ipairs(type(f.options) == "table" and f.options or {}) do
            local v = type(o) == "table" and o[1] or o
            if type(v) == "string" and v ~= "" and #q.options < E.Q_OPTS then
              v = v:sub(1, 20); q.options[#q.options + 1] = { v, v }
            end
          end
        end
        if #q.options >= 2 then out[#out + 1] = q end
      else
        if f.kind == "number" then q.min = 0; q.max = 99999 end
        out[#out + 1] = q
      end
    end
  end
  return #out > 0 and out or nil
end

---------------------------------------------------------------------------
-- Settings of the event leader (API 7): an event type lists them in
-- `settings`, the editor shows them, the values travel as e.set.
-- { id, kind = "choice"|"multi"|"number"|"check"|"text"|"time"|"date",
--   label|labelKey, options = { { value, labelKey|text } } or fn(e), default, min, max, showIf = fn(values) }
---------------------------------------------------------------------------
E.SET_KINDS = { choice = true, multi = true, number = true, check = true, text = true, time = true, date = true }
E.SET_MAX = 20

function E.SettingDefs(typeId)
  local t = typeId and ns.Modules.Type(typeId)
  return t and type(t.settings) == "table" and t.settings or {}
end

function E.SettingOptions(def, e)
  local o = def.options
  if type(o) == "function" then local ok, r = pcall(o, e); o = ok and r or nil end
  local out = {}
  for _, x in ipairs(type(o) == "table" and o or {}) do
    local v = type(x) == "table" and x[1] or x
    local label = type(x) == "table" and x[2] or tostring(x)
    if v ~= nil then out[#out + 1] = { v, (type(label) == "string" and rawget(ns.L, label)) or ns.L[label] or label } end
  end
  return out
end

local function hasOption(opts, v) for _, o in ipairs(opts) do if o[1] == v then return true end end end

local function validTime(v)
  local h, m = tostring(v):match("^(%d%d?):(%d%d)$")
  h, m = tonumber(h), tonumber(m)
  if h and h < 24 and m < 60 then return string.format("%02d:%02d", h, m) end
end
local function validDate(v)
  local y, mo, d = tostring(v):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  mo, d = tonumber(mo), tonumber(d)
  if y and mo >= 1 and mo <= 12 and d >= 1 and d <= 31 then return v end
end

-- one value checked against its definition; nil = invalid
function E.SettingValue(def, v, e)
  local k = def.kind
  if v == nil then return nil end
  if k == "number" then
    v = tonumber(v); if not v then return nil end
    if def.min and v < def.min then v = def.min end
    if def.max and v > def.max then v = def.max end
    return v
  elseif k == "check" then return v and true or false
  elseif k == "text" then return type(v) == "string" and v:sub(1, def.maxLen or 60) or nil
  elseif k == "time" then return validTime(v)
  elseif k == "date" then return validDate(v)
  elseif k == "choice" then
    local opts = E.SettingOptions(def, e)
    return (#opts == 0 or hasOption(opts, v)) and v or nil
  elseif k == "multi" then
    if type(v) ~= "table" then return nil end
    local opts, out = E.SettingOptions(def, e), {}
    for _, x in ipairs(v) do if (#opts == 0 or hasOption(opts, x)) and #out < 12 then out[#out + 1] = x end end
    return out
  end
end

-- Values of the event (defaults filled in). Unknown types (module not
-- installed here): the raw values, only plain data.
function E.Settings(e)
  local defs = E.SettingDefs(e and e.type)
  local raw = type(e and e.set) == "table" and e.set or {}
  local out = {}
  if #defs == 0 then
    for k, v in pairs(raw) do out[k] = v end
    return out
  end
  for _, d in ipairs(defs) do
    local v = raw[d.id]
    if v == nil then v = E.FieldDefault(d, e) end
    out[d.id] = v
  end
  return out
end

-- cleaned e.set: known type -> only defined ids with valid values;
-- unknown type -> plain values only (string ids, scalars or short lists)
function E.CleanSettings(typeId, raw, e)
  if type(raw) ~= "table" then return nil end
  local defs = E.SettingDefs(typeId)
  local out, n = {}, 0
  if #defs > 0 then
    for _, d in ipairs(defs) do
      if type(d.id) == "string" and E.SET_KINDS[d.kind] then
        local v = E.SettingValue(d, raw[d.id], e)
        if v ~= nil then out[d.id] = v; n = n + 1 end
      end
    end
  else
    for k, v in pairs(raw) do
      if n >= E.SET_MAX then break end
      if type(k) == "string" and #k <= 24 then
        local tv = type(v)
        if tv == "number" or tv == "boolean" then out[k] = v; n = n + 1
        elseif tv == "string" then out[k] = v:sub(1, 60); n = n + 1
        elseif tv == "table" then
          local l = {}
          for _, x in ipairs(v) do if (type(x) == "string" or type(x) == "number") and #l < 12 then l[#l + 1] = x end end
          out[k] = l; n = n + 1
        end
      end
    end
  end
  return n > 0 and out or nil
end

-- the type's own check of all values: nil or an error text
function E.ValidateSettings(typeId, values)
  local t = typeId and ns.Modules.Type(typeId)
  if t and type(t.validate) == "function" then
    local ok, err = pcall(t.validate, values)
    if ok and err then return err end
  end
end

function E.FieldDefault(f, e)
  if type(f.default) == "function" then
    local ok, v = pcall(f.default, e)
    return ok and v or nil
  end
  return f.default
end

function E.FieldLabel(f) return f.label or (f.labelKey and ns.L[f.labelKey]) or f.id end

-- the value of an auto field for me, read from the game now
function E.AutoValue(f, e)
  if f.kind ~= "auto" or type(f.get) ~= "function" then return nil end
  local ok, v = pcall(f.get, e)
  if ok then return v end
end

local function cleanValue(f, v)
  if v == nil then return nil end
  if f.kind == "number" or f.kind == "auto" then
    if f.kind == "auto" and type(v) == "string" then return v:sub(1, 30) end
    v = tonumber(v); if not v then return nil end
    if f.min and v < f.min then v = f.min end
    if f.max and v > f.max then v = f.max end
    return v
  elseif f.kind == "check" then return v and true or false
  elseif f.kind == "multi" then
    if type(v) ~= "table" then return nil end
    local out = {}
    for _, x in ipairs(v) do if #out < 10 then out[#out + 1] = tostring(x):sub(1, 20) end end
    return out
  else
    return tostring(v):sub(1, f.kind == "text" and E.COMMENT_MAX or 20)
  end
end

-- check a field value; returns an error text or nil
function E.CheckField(f, v)
  if f.required and (v == nil or v == "") then return ns.L.FIELD_REQUIRED:format(E.FieldLabel(f)) end
  if type(f.validate) == "function" then
    local ok, err = pcall(f.validate, v)
    if ok and err then return err end
  end
end

-- the own sign-up: opts = { st, c, f = { [fieldId] = value } }
-- may the character sign up (declining is always possible)? The event type
-- can decide (canSignUp(e, key) -> ok, reason), e.g. raids by level
-- may this character say yes? -> ok, reason (when not), notes (hints when yes; API 7)
function E.CanSignUp(e, key)
  local miss = ns.Catalog and ns.Catalog.MissingFor(e)
  if miss then return false, miss end           -- add-on module not installed: no taking part
  local t = e and ns.Modules.Type(e.type)
  if t and t.canSignUp then
    local ok, a, b, c = pcall(t.canSignUp, e, key)
    if ok then
      local notes
      if type(c) == "table" then
        notes = {}
        for _, n in ipairs(c) do if type(n) == "string" and n ~= "" and #notes < 4 then notes[#notes + 1] = n end end
        if #notes == 0 then notes = nil end
      elseif type(c) == "string" and c ~= "" then notes = { c } end
      return a ~= false, b, notes
    end
  end
  return true
end

-- the type's rules (API 7): { { icon, title, text }, ... } or nil
function E.Rules(e)
  local t = e and ns.Modules.Type(e.type)
  if not (t and type(t.rules) == "function") then return nil end
  local ok, list = pcall(t.rules, e)
  if not ok or type(list) ~= "table" then return nil end
  local out = {}
  for _, r in ipairs(list) do
    if type(r) == "table" and (r.title or r.text) and #out < 8 then
      out[#out + 1] = { icon = r.icon, title = tostring(r.title or ""), text = tostring(r.text or "") }
    end
  end
  return #out > 0 and out or nil
end

function E.SetSignup(e, opts)
  if not C.CanSend() and not ns.demo then U.Print(ns.L.NOT_ACTIVE); return end
  opts = opts or {}
  local st = SIGN_OK[opts.st] and opts.st or "in"
  if st ~= "out" then
    local ok, why, notes = E.CanSignUp(e)
    if not ok then U.Print(why or ns.L.SIGN_NOT_ALLOWED); return false, why end
    if notes and E.Status(e) ~= st then for _, n in ipairs(notes) do U.Print(U.Color(U.WARN, n)) end end
  end
  local f = {}
  for _, fd in ipairs(E.Fields(e)) do
    local v = (fd.kind == "auto") and E.AutoValue(fd, e) or (opts.f and opts.f[fd.id])
    if v == nil and fd.default ~= nil and fd.kind ~= "auto" then v = E.FieldDefault(fd, e) end
    if st ~= "out" then
      local err = E.CheckField(fd, v)
      if err then U.Print(err); return false, err end
    end
    f[fd.id] = cleanValue(fd, v)
  end
  local c = opts.c and tostring(opts.c):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, E.COMMENT_MAX) or nil
  if c == "" then c = nil end
  e.signups = e.signups or {}
  -- the character's level when signing up (the lowest one is kept: an early
  -- sign-up stays early even after levelling)
  local prev = e.signups[G.MyKey()]
  local lv = tonumber(UnitLevel and UnitLevel("player"))
  if prev and tonumber(prev.lv) and (not lv or prev.lv < lv) then lv = prev.lv end
  -- "for the whole series" (API 7): stays until the member answers again without it
  local all = opts.all or nil
  local s = { on = st ~= "out", st = st, c = c, f = f, t = U.Now(), lv = lv, all = all }
  e.signups[G.MyKey()] = s
  C.Send("SIGN", { ev = e.id, on = s.on, st = st, c = c, f = f, lv = lv, all = all })
  ns.Fire("SIGNUP_CHANGED", e, G.MyKey(), s)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return true
end

-- API 1: plain yes / no
function E.SignUp(e, on)
  local cur = E.Signup(e)
  return E.SetSignup(e, { st = on and "in" or "out", c = cur and cur.c, f = cur and cur.f })
end

---------------------------------------------------------------------------
-- Invite with one click: everyone signed up with yes or late who is online
-- and not in the group yet; a party turns into a raid once more than five
---------------------------------------------------------------------------
local inviteQueue, inviteEv
local function inviteName(key)
  local r = G.roster[key]
  return r and r.name or key
end
local function canInvite()
  if not IsInGroup or not IsInGroup() then return true end
  return (UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) or false
end
local function inGroup(key)
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, n do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    if G.UnitKey(unit) == key then return true end
  end
  return key == G.MyKey()
end
local function doInvite(name)
  local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  if fn then pcall(fn, name) end
end

function E.InviteStep()
  if not inviteQueue or #inviteQueue == 0 then inviteQueue = nil; return end
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local raid = IsInRaid and IsInRaid()
  if not raid and n >= 2 and (#inviteQueue + n) > 5 and UnitIsGroupLeader and UnitIsGroupLeader("player") then
    local conv = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
    if conv then pcall(conv) end
  end
  local room = raid and 40 - n or 5 - math.max(n, 1)
  if not raid and n <= 1 then room = 4 end
  local sent = 0
  while #inviteQueue > 0 and room > 0 do
    doInvite(table.remove(inviteQueue, 1))
    room = room - 1; sent = sent + 1
  end
  if #inviteQueue > 0 then ns.Schedule("gemInviteStep", 3, E.InviteStep) end
end

-- returns invited, offline
function E.InviteAll(e)
  if not canInvite() then U.Print(ns.L.INVITE_NO_LEAD); return 0, {} end
  G.RequestRoster()
  local list, offline = {}, {}
  for _, s in ipairs(E.SignupList(e)) do
    if (s.st == "in" or s.st == "late") and not inGroup(s.key) then
      local r = G.roster[s.key]
      if r and r.online then list[#list + 1] = inviteName(s.key) else offline[#offline + 1] = G.Display(s.key) end
    end
  end
  local count = #list
  inviteQueue, inviteEv = U.Copy(list), e.id
  E.InviteStep()
  U.Print(ns.L.INVITE_DONE:format(count, #offline > 0 and (" · " .. ns.L.INVITE_OFFLINE:format(table.concat(offline, ", "))) or ""))
  ns.Fire("EVENT_INVITED", e, list)
  return count, offline
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function mergeSignups(old, new)
  local out = {}
  for k, v in pairs(old or {}) do out[k] = v end
  for k, v in pairs(new or {}) do
    if type(v) == "table" and (not out[k] or (tonumber(v.t) or 0) >= (tonumber(out[k].t) or 0)) then out[k] = v end
  end
  return out
end

C.On("EVT", function(data, from)
  local e = data.e
  if type(e) ~= "table" or not e.id then return end
  local prev = events()[e.id]
  -- managers of the type, or a leader of the event as it is known here (0.9)
  if not E.CanCreate(e.type, from) and not (prev and E.IsLeader(prev, from)) then return end
  e.fields = E.CleanFields(e.fields)
  if ns.Teams then e.teams = ns.Teams.Clean(e.teams) end
  e.set = E.CleanSettings(e.type, e.set, e)
  if ns.Series then e.rep = ns.Series.Clean(e.rep) end
  if e.series ~= nil and type(e.series) ~= "string" then e.series = nil end
  local list = events()
  local old = list[e.id]
  if ns.Contest then ns.Contest.Merge(old, e) end
  if old and (tonumber(old.upd) or 0) >= (tonumber(e.upd) or 0) then
    old.signups = mergeSignups(old.signups, e.signups)
    if ns.Contest then ns.Contest.Merge(e, old) end   -- e holds both by now
    return
  end
  e.signups = mergeSignups(old and old.signups, e.signups)
  list[e.id] = e
  ns.Fire("EVENT_UPDATED", e, old == nil)
  if e.result and not (old and old.result) and ns.Contest then
    ns.Fire("EVENT_RESULTS", e, e.result)
    ns.SafeCall("contestResult", ns.Contest.AnnounceResult, e)
  end
  local muted = ns.Catalog and ns.Catalog.Muted(e)
  if not old and not muted and E.IsOpen(e) and (U.Now() - (tonumber(e.created) or 0)) < 900 and ns.db.notify ~= false then
    U.Print(ns.L.EVT_NEW:format(T.Word("GUILD"), e.name, U.FormatTime(e.start)))
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  end
  if not old and not muted and E.IsOpen(e) and ns.Notices then
    ns.Notices.Add({ key = "ev:" .. e.id, group = ns.L.TAB_EVENTS, text = ns.L.NOTICE_NEW_EVENT:format(e.name, U.FormatTime(e.start)), ev = e.id })
  end
  ns.Achievements.Dirty()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

C.On("EVTSTART", function(data)
  local e = data.ev and E.Get(data.ev)
  if not e then return end
  ns.Fire("EVENT_STARTED", e, false)
  local msg = ns.L.EVT_STARTS_NOW:format(e.name)
  U.Print(U.Color(U.GOLD, msg))
  if RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.8, b = 0 })
  end
end)

C.On("SIGN", function(data, from)
  local e = data.ev and E.Get(data.ev)
  if not e or not from then return end
  e.signups = e.signups or {}
  local st = SIGN_OK[data.st] and data.st or (data.on and "in" or "out")
  local f = {}
  if type(data.f) == "table" then
    for _, fd in ipairs(E.Fields(e)) do if data.f[fd.id] ~= nil then f[fd.id] = cleanValue(fd, data.f[fd.id]) end end
  end
  local c = type(data.c) == "string" and data.c:sub(1, E.COMMENT_MAX) or nil
  local lv = tonumber(data.lv)
  if lv and (lv < 1 or lv > 200) then lv = nil end
  local prev = e.signups[from]
  if prev and tonumber(prev.lv) and (not lv or prev.lv < lv) then lv = prev.lv end
  e.signups[from] = { on = st ~= "out", st = st, c = c, f = f, t = U.Now(), lv = lv, all = data.all and true or nil }
  ns.Fire("SIGNUP_CHANGED", e, from, e.signups[from])
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

---------------------------------------------------------------------------
-- Reminders: 10 minutes before a planned event (for sign-ups and managers),
-- and a short summary after login
---------------------------------------------------------------------------
local reminded = {}
function E.Tick()
  ns.Schedule("gemEventTick", 30, E.Tick)
  if ns.demo or not G.IsActivated() then return end
  ns.SafeCall("invites", E.CheckInvites)
  if ns.Contest then ns.SafeCall("contest", ns.Contest.Tick) end
  if ns.Series then ns.SafeCall("series", ns.Series.Tick) end
  if ns.Reminders then ns.SafeCall("reminders", ns.Reminders.Tick) end
  local now = U.Now()
  for _, e in pairs(events()) do
    if e.status == "planned" and e.kind == "short" and not reminded[e.id] then
      local left = (e.start or 0) - now
      if left > 0 and left <= 600 and (E.IsSigned(e) or E.CanManage(e)) then
        reminded[e.id] = true
        local msg = ns.L.EVT_REMINDER:format(e.name, math.ceil(left / 60))
        U.Print(U.Color(U.GOLD, msg))
        if RaidNotice_AddMessage and RaidWarningFrame then
          pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, { r = 1, g = 0.8, b = 0 })
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Open invitations: a planned event that a member of the right level has not
-- answered yet. A notice under the bell for every one; in the week before the
-- event a popup that has to be answered ("open" or "later").
---------------------------------------------------------------------------
E.ASK_DAYS = 7
E.ASK_SNOOZE = 3 * 3600      -- "Later" hides the popup for this long
E.ASK_OPENED = 15 * 60       -- after "Open" give the member time to answer

function E.MinLevel(e)
  local v = e and tonumber(e.lvl)
  if v and v > 1 then
    v = math.floor(v)
    return v
  end
  return nil
end
function E.LevelOf(key)
  if not key or key == G.MyKey() then return UnitLevel and UnitLevel("player") end
  local r = G.roster[key]
  return r and r.level
end
-- true when the character is of the event's level (unknown level counts as yes)
function E.Qualifies(e, key)
  local min = E.MinLevel(e)
  if not min then return true end
  local lv = tonumber(E.LevelOf(key))
  if not lv or lv <= 0 then return true end
  return lv >= min
end
-- reminders on? (checkbox in the editor; without a choice the type decides:
-- raids remind, the other types don't)
function E.Remind(e)
  if not e then return false end
  if e.remind ~= nil then return e.remind and true or false end
  local t = ns.Modules.Type(e.type)
  return t and t.remind and true or false
end

-- planned, not answered yet, of the right level
function E.Unanswered(e, key)
  if not e or e.status ~= "planned" or e.kind == "season" then return false end
  if (tonumber(e.start) or 0) <= U.Now() then return false end
  if E.Status(e, key) then return false end
  return E.Qualifies(e, key)
end

-- the member is reminded to say yes or no
function E.NeedsAnswer(e, key)
  if ns.Catalog and ns.Catalog.Muted(e) then return false end   -- "not interested"
  return E.Remind(e) and E.Unanswered(e, key)
end
-- own open invitations, soonest first
function E.OpenInvites()
  local list = {}
  for _, e in pairs(events()) do if E.NeedsAnswer(e) then list[#list + 1] = e end end
  table.sort(list, function(a, b) return (a.start or 0) < (b.start or 0) end)
  return list
end

-- "Later" holds only for this session: after every login and /reload the
-- popup comes again
E.askSnooze = {}
local function askStore()
  local c = ns.char
  if not c then return {}, E.askSnooze end
  c.askNotice = c.askNotice or {}
  c.askSnooze = nil
  return c.askNotice, E.askSnooze
end

function E.SnoozeInvite(e, secs)
  local _, snooze = askStore()
  if e and e.id then snooze[e.id] = U.Now() + (secs or E.ASK_SNOOZE) end
end

-- the popups that are due now (in the week before the event, not snoozed)
function E.DueInvites()
  local _, snooze = askStore()
  local now, out = U.Now(), {}
  for _, e in ipairs(E.OpenInvites()) do
    if (e.start or 0) - now <= E.ASK_DAYS * 86400 and (snooze[e.id] or 0) <= now then out[#out + 1] = e end
  end
  return out
end

function E.CheckInvites()
  if ns.demo or not G.IsActivated() then return end
  local noticed, snooze = askStore()
  local open = {}
  for _, e in ipairs(E.OpenInvites()) do
    open[e.id] = true
    if not noticed[e.id] and ns.Notices then
      noticed[e.id] = true
      ns.Notices.Remove("ev:" .. e.id)
      ns.Notices.Add({ key = "ask:" .. e.id, group = ns.L.TAB_EVENTS, text = ns.L.NOTICE_ASK:format(e.name, U.FormatTime(e.start)), ev = e.id })
    end
  end
  for id in pairs(noticed) do
    if not open[id] then
      noticed[id] = nil
      if ns.Notices then ns.Notices.Remove("ask:" .. id) end
    end
  end
  for id in pairs(snooze) do if not open[id] then snooze[id] = nil end end
  if ns.UIInvite then ns.UIInvite.Update() end
end

-- right after login / reload: as soon as the guild is known to be switched on
ns.On("ACTIVATED", function()
  ns.Schedule("gemInviteFirst", 2, function() ns.SafeCall("invites", E.CheckInvites) end)
end)

ns.On("SIGNUP_CHANGED", function(e, key)
  if key == G.MyKey() then E.CheckInvites() end
end)

function E.LoginNotice()
  if not G.IsActivated() then return end
  local ask = #E.OpenInvites()
  if ask > 0 then U.Print(U.Color(U.GOLD, ns.L.LOGIN_ASK:format(ask))) end
  local planned, running = 0, 0
  for _, e in pairs(events()) do
    if e.status == "planned" then planned = planned + 1 elseif e.status == "running" then running = running + 1 end
  end
  if planned + running > 0 then U.Print(ns.L.LOGIN_EVENTS:format(running, planned)) end
end
