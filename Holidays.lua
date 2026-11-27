local ADDON, ns = ...
-- Holidays (0.9, API 7): modules bring their holidays as data (month/day of
-- start and end, realm time). The guild leadership may move them for its
-- guild (WoW Forever has no calendar window; Blizzard may shift the dates).
-- An event type with `holiday = "id"` can be created only from `lead` days
-- before the start until the end of the holiday.
--
--   API.AddHoliday({ id, nameKey, from = { 12, 16 }, to = { 1, 2 }, lead = 14, icon })
--   API.Holiday(id) -> { id, name, start, finish, active, soon, days } (the current or next one)
--   API.HolidayActive(id) -> bool
local U, G = ns.U, ns.Guild
local H = {}
ns.Holidays = H
H.defs, H.order = {}, {}

---------------------------------------------------------------------------
-- Realm calendar: timestamps for a date and time of the realm
---------------------------------------------------------------------------
-- days since 1970-01-01 of a civil date (proleptic Gregorian)
local function daysFromCivil(y, m, d)
  y = (m <= 2) and (y - 1) or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end
H.DaysFromCivil = daysFromCivil

-- the realm's date and time now: year, month, day, hour, minute
function H.RealmNow()
  if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
    local ok, d = pcall(C_DateAndTime.GetCurrentCalendarTime)
    if ok and type(d) == "table" and tonumber(d.year) and tonumber(d.month) and tonumber(d.monthDay) then
      return tonumber(d.year), tonumber(d.month), tonumber(d.monthDay), tonumber(d.hour) or 0, tonumber(d.minute) or 0
    end
  end
  local t = date("*t", U.Now())
  return t.year, t.month, t.day, t.hour, t.min
end

-- seconds the realm clock is ahead of UTC (rounded to 15 minutes)
function H.RealmOffset()
  local y, m, d, h, mi = H.RealmNow()
  local realmAsUTC = daysFromCivil(y, m, d) * 86400 + h * 3600 + mi * 60
  local diff = realmAsUTC - U.Now()
  return math.floor(diff / 900 + 0.5) * 900
end

-- timestamp of a realm date and time
function H.RealmTime(y, m, d, h, mi)
  return daysFromCivil(y, m, d) * 86400 + (h or 0) * 3600 + (mi or 0) * 60 - H.RealmOffset()
end

---------------------------------------------------------------------------
-- Definitions and the guild's dates
---------------------------------------------------------------------------
function H.Add(def)
  if type(def) ~= "table" or type(def.id) ~= "string" then return false end
  if type(def.from) ~= "table" or type(def.to) ~= "table" then return false end
  if not H.defs[def.id] then H.order[#H.order + 1] = def.id end
  H.defs[def.id] = def
  return true
end

function H.Name(id)
  local d = H.defs[id]
  if not d then return id end
  return d.name or (d.nameKey and ns.L[d.nameKey]) or id
end

-- the dates the guild uses: its own (profile) or the module's
function H.Dates(id)
  local d = H.defs[id]
  if not d then return nil end
  local p = ns.Profile.Get()
  local own = type(p.holidays) == "table" and p.holidays[id]
  if type(own) == "table" and type(own.from) == "table" and type(own.to) == "table" then return own.from, own.to, true end
  return d.from, d.to, false
end

-- the guild leadership moves a holiday (nil = back to the module's dates)
function H.SetDates(id, from, to)
  if not H.defs[id] then return false end
  return ns.Profile.Update(function(p)
    p.holidays = p.holidays or {}
    if from and to then p.holidays[id] = { from = { from[1], from[2] }, to = { to[1], to[2] } }
    else p.holidays[id] = nil end
  end)
end

-- the occurrence that runs now or comes next: start, finish (timestamps)
function H.Window(id, at)
  local from, to = H.Dates(id)
  if not from then return nil end
  at = at or U.Now()
  local y = H.RealmNow()
  for _, yy in ipairs({ y - 1, y, y + 1 }) do
    local s = H.RealmTime(yy, from[1], from[2], 0, 0)
    local endYear = (to[1] < from[1] or (to[1] == from[1] and to[2] < from[2])) and yy + 1 or yy
    local f = H.RealmTime(endYear, to[1], to[2], 23, 59) + 59
    if at <= f then return s, f end
  end
  return nil
end

function H.Info(id)
  local d = H.defs[id]
  if not d then return nil end
  local s, f = H.Window(id)
  if not s then return nil end
  local now = U.Now()
  local lead = (tonumber(d.lead) or 14) * 86400
  local _, _, own = H.Dates(id)
  return {
    id = id, name = H.Name(id), icon = d.icon, start = s, finish = f, moved = own,
    active = now >= s and now <= f,
    soon = now < s and now >= s - lead,
    days = now < s and math.ceil((s - now) / 86400) or math.max(0, math.ceil((f - now) / 86400)),
  }
end

function H.Active(id)
  local i = H.Info(id)
  return i and i.active or false
end

-- may events of this type be created now? (always true without holiday)
function H.TypeOpen(t)
  if not (t and t.holiday) then return true end
  local i = H.Info(t.holiday)
  if not i then return true end
  return i.active or i.soon
end

-- "from 16.12." for a closed type
function H.OpensText(t)
  local i = t and t.holiday and H.Info(t.holiday)
  if not i then return nil end
  local d = H.defs[t.holiday]
  local lead = (tonumber(d.lead) or 14) * 86400
  return ns.L.HOL_OPENS:format(date("%d.%m.", i.start - lead), i.name)
end
