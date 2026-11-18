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
function E.CanCreate(typeId, key)
  if G.IsManager(key) then return true end
  local t = typeId and ns.Modules.Type(typeId)
  if t and type(t.canCreate) == "function" then
    local ok, res = pcall(t.canCreate, key or G.MyKey())
    return ok and res and true or false
  end
  return false
end
function E.CanManage(e, key)
  if not e then return G.IsManager(key) end
  return E.CanCreate(e.type, key)
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
  e.upd = math.max(U.Now(), (e.upd or 0) + 1)
  events()[e.id] = e
  send(e)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  return e
end

-- fields: type, name, desc, kind, start, finish, group, gmin, gmax
function E.Create(fields)
  if not E.CanCreate(fields.type) then U.Print(ns.L.NO_RIGHTS); return nil end
  local t = ns.Modules.Type(fields.type)
  local e = {
    id = U.NewId(), type = fields.type,
    name = (fields.name and fields.name ~= "") and fields.name or ns.Modules.TypeName(fields.type),
    desc = fields.desc or "",
    leader = fields.leader or G.MyKey(),
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
    status = "planned", signups = {}, created = U.Now(), by = G.MyKey(),
  }
  if e.kind == "season" then
    e.start = ns.Points.SeasonStart(); e.finish = ns.Points.SeasonEnd()
  end
  E.Save(e)
  U.Print(ns.L.EVT_ANNOUNCED:format(e.name))
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
function E.End(e, attended)
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
  if book and n >= (p.pts.leadMin or 5) and (p.pts.lead or 0) > 0 and e.leader then
    ns.Points.Add(e.leader, "event", p.pts.lead, "lead", e.id)
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
      add(G.UnitKey(unit), true)
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
function E.CanSignUp(e, key)
  local t = e and ns.Modules.Type(e.type)
  if t and t.canSignUp then
    local ok, a, b = pcall(t.canSignUp, e, key)
    if ok then return a ~= false, b end
  end
  return true
end

function E.SetSignup(e, opts)
  if not C.CanSend() and not ns.demo then U.Print(ns.L.NOT_ACTIVE); return end
  opts = opts or {}
  local st = SIGN_OK[opts.st] and opts.st or "in"
  if st ~= "out" then
    local ok, why = E.CanSignUp(e)
    if not ok then U.Print(why or ns.L.SIGN_NOT_ALLOWED); return false, why end
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
  local s = { on = st ~= "out", st = st, c = c, f = f, t = U.Now(), lv = lv }
  e.signups[G.MyKey()] = s
  C.Send("SIGN", { ev = e.id, on = s.on, st = st, c = c, f = f, lv = lv })
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
  if not E.CanCreate(e.type, from) then return end
  local list = events()
  local old = list[e.id]
  if old and (tonumber(old.upd) or 0) >= (tonumber(e.upd) or 0) then
    old.signups = mergeSignups(old.signups, e.signups)
    return
  end
  e.signups = mergeSignups(old and old.signups, e.signups)
  list[e.id] = e
  ns.Fire("EVENT_UPDATED", e, old == nil)
  if not old and E.IsOpen(e) and (U.Now() - (tonumber(e.created) or 0)) < 900 and ns.db.notify ~= false then
    U.Print(ns.L.EVT_NEW:format(T.Word("GUILD"), e.name, U.FormatTime(e.start)))
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  end
  if not old and E.IsOpen(e) and ns.Notices then
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
  e.signups[from] = { on = st ~= "out", st = st, c = c, f = f, t = U.Now(), lv = lv }
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
