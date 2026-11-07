local ADDON, ns = ...
local U = {}
ns.U = U

U.BLUE = "ff4fa3ff"
U.ADDON = "ffd4af37"
U.GOLD = "ffffd100"
U.WARN = "fff0b45a"
U.OK = "ff8fe39f"
U.MUTED = "ff9fb4c8"

function U.Color(hex, text) return "|c" .. hex .. tostring(text) .. "|r" end

function U.Print(msg)
  print(U.Color(U.ADDON, "GuildEventManager") .. ": " .. tostring(msg))
end

function U.Timestamp() return date("%Y-%m-%d %H:%M:%S") end

-- Calls fn safely and returns its first result (nil on error or when fn is missing).
function U.Try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
  return nil
end

-- Like U.Try, but returns all results (nothing on error).
local function dropStatus(ok, ...)
  if ok then return ... end
end
function U.TryAll(fn, ...)
  if type(fn) ~= "function" then return end
  return dropStatus(pcall(fn, ...))
end

function U.CharKey()
  local n, second = UnitName("player")
  local name = (n or "?") .. ((second and second ~= "") and (" " .. second) or "")
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
  return name .. "-" .. realm
end

function U.IsAddOnLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
  return IsAddOnLoaded and IsAddOnLoaded(name)
end

---------------------------------------------------------------------------
-- Error log: errors in event handlers are kept in the saved variables, so an
-- error during logout can still be read after the next login (/gem errors).
---------------------------------------------------------------------------
local function logError(where, err, stack)
  stack = stack or (debugstack and debugstack(3, 12, 0)) or ""
  local db = ns.db
  if db then
    db.errors = db.errors or {}
    table.insert(db.errors, 1, { t = U.Timestamp(), where = where, msg = tostring(err), stack = stack })
    while #db.errors > 20 do table.remove(db.errors) end
    db.unseenErrors = true
  end
  if not ns.leaving then U.Print(U.Color(U.WARN, tostring(err)) .. "  (/gem errors)") end
end
ns.LogError = logError

-- The handler runs at the error site, so the logged stack shows where it failed.
local lastStack
local function captureStack(err)
  lastStack = debugstack and debugstack(2, 12, 0) or nil
  return err
end

function ns.SafeCall(where, fn, ...)
  local ok, err = xpcall(fn, captureStack, ...)
  if not ok then logError(where, err, lastStack); lastStack = nil end
  return ok, err
end

---------------------------------------------------------------------------
-- Scheduler without timer objects (WoW Forever limits an addon to 500 timers).
-- A job with the same name replaces the pending one, which also debounces.
---------------------------------------------------------------------------
local due, ticker = {}, CreateFrame("Frame")
ticker:Hide()
local ready = {}
ticker:SetScript("OnUpdate", function(self)
  local now = GetTime()
  -- Collect first: a job may schedule new jobs, and adding keys to `due`
  -- while pairs() walks it is undefined ("invalid key to 'next'").
  for name, job in pairs(due) do
    if now >= job.at then ready[#ready + 1] = name end
  end
  for i = 1, #ready do
    local name = ready[i]
    ready[i] = nil
    local job = due[name]
    -- An earlier job may have unscheduled or rescheduled this one.
    if job and now >= job.at then
      due[name] = nil
      ns.SafeCall(name, job.fn)
    end
  end
  if not next(due) then self:Hide() end
end)

function ns.Schedule(name, delay, fn)
  due[name] = { at = GetTime() + delay, fn = fn }
  ticker:Show()
end

function ns.Unschedule(name) due[name] = nil end

---------------------------------------------------------------------------
-- Names: Forever writes characters as "First Last" in some logs and as
-- "First-Realm" in others. Keys are the plain character name without realm.
---------------------------------------------------------------------------
function U.Short(name)
  if not name then return nil end
  name = tostring(name):gsub("%-.*$", "")
  return name
end

function U.Me() return U.Short(UnitName("player")) end

function U.Now() return (GetServerTime and GetServerTime()) or time() end

-- Short unique id: sender + time + counter (enough to dedupe across clients)
local idCounter = 0
function U.NewId()
  idCounter = (idCounter + 1) % 46656
  return string.format("%s%x%03x", (U.Me() or "x"):sub(1, 4), U.Now(), idCounter)
end

function U.FormatTime(ts)
  if not ts or ts == 0 then return "–" end
  return date("%d.%m. %H:%M", ts)
end

function U.FormatSpan(sec)
  sec = math.max(0, math.floor(sec or 0))
  local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
  if d > 0 then return string.format("%dd %dh", d, h) end
  if h > 0 then return string.format("%d:%02d h", h, m) end
  return string.format("%d min", m)
end

function U.Copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = U.Copy(v) end
  return c
end
