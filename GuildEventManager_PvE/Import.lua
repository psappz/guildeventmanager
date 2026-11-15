local ADDON, R = ...
-- Raid-Helper import: the event JSON (button "JSON" in Raid-Helper, or
-- https://raid-helper.xyz/api/v4/events/<id>) is pasted into the addon.
-- Discord names are matched to characters once; the match is kept per
-- Discord ID. A sign-up made in the addon always wins over the import.
local core = R.core
if not core then return end
local U, G, E = core.U, core.Guild, core.Events
local L = R.L

---------------------------------------------------------------------------
-- A small JSON reader (objects, arrays, strings, numbers, true/false/null)
---------------------------------------------------------------------------
local function utf8char(c)
  if c < 0x80 then return string.char(c) end
  if c < 0x800 then return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64) end
  return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
end

function R.ParseJSON(s)
  if type(s) ~= "string" then return nil, "no text" end
  local pos, len = 1, #s
  local value
  local function ws()
    pos = s:find("[^ \t\r\n]", pos) or (len + 1)
  end
  local function fail(msg) error({ msg = msg .. " @" .. pos }, 0) end
  local function str()
    pos = pos + 1
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail("unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local n = s:sub(pos + 1, pos + 1)
        local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if map[n] then out[#out + 1] = map[n]; pos = pos + 2
        elseif n == "u" then
          local hex = s:sub(pos + 2, pos + 5)
          local cp = tonumber(hex, 16) or 63
          pos = pos + 6
          -- surrogate pair
          if cp >= 0xD800 and cp <= 0xDBFF and s:sub(pos, pos + 1) == "\\u" then
            local lo = tonumber(s:sub(pos + 2, pos + 5), 16) or 0
            pos = pos + 6
            cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
            out[#out + 1] = string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64, 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
          else
            out[#out + 1] = utf8char(cp)
          end
        else fail("bad escape") end
      else
        local stop = s:find('["\\]', pos) or (len + 1)
        out[#out + 1] = s:sub(pos, stop - 1)
        pos = stop
      end
    end
    return table.concat(out)
  end
  function value()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local obj = {}
      ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        ws()
        if s:sub(pos, pos) ~= '"' then fail("key expected") end
        local k = str()
        ws()
        if s:sub(pos, pos) ~= ":" then fail("colon expected") end
        pos = pos + 1
        obj[k] = value()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then fail("comma expected") end
      end
    elseif c == "[" then
      pos = pos + 1
      local arr = {}
      ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return arr end
        if d ~= "," then fail("comma expected") end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then fail("unexpected '" .. c .. "'") end
      pos = pos + #num
      return tonumber(num)
    end
  end
  local ok, res = pcall(value)
  if not ok then return nil, type(res) == "table" and res.msg or tostring(res) end
  return res
end

---------------------------------------------------------------------------
-- Reading a Raid-Helper event
---------------------------------------------------------------------------
-- returns { title, start, list = { { id, name, class, tree, role, st, note, pos, t } } } or nil, error
function R.ReadRaidHelper(text)
  local data, err = R.ParseJSON(text)
  if not data then return nil, err end
  if type(data) ~= "table" then return nil, "no object" end
  local ev = data.signUps and data or data.event or data
  local su = ev.signUps or ev.signups
  if type(su) ~= "table" then return nil, L.RAID_IMP_NOSIGNUPS end
  local out = { title = ev.title or ev.displayTitle, start = tonumber(ev.startTime), list = {} }
  for _, x in ipairs(su) do
    if type(x) == "table" and x.name then
      local spec = x.specName and R.RH_SPECS[x.specName]
      local st = R.RH_STATUS[x.className] or R.RH_STATUS[x.status] or (x.status == "primary" and "in") or "in"
      local role = spec and spec[3] or R.RH_ROLES[x.roleName] or R.RH_ROLES[x.className]
      out.list[#out.list + 1] = {
        id = tostring(x.userId or x.name), name = tostring(x.name), class = spec and spec[1], tree = spec and spec[2],
        role = role, st = st, note = x.note and tostring(x.note):sub(1, E.COMMENT_MAX) or nil,
        pos = tonumber(x.position) or #out.list + 1, t = tonumber(x.entryTime),
        spec = x.specName,
      }
    end
  end
  table.sort(out.list, function(a, b) return a.pos < b.pos end)
  return out
end

-- best guess for a Discord name: the saved match, else a guild member whose
-- name appears in it ("Woodryda//Breitling" -> Woodryda or Breitling)
function R.GuessMember(entry)
  local s = R.Store()
  local saved = s.discord[entry.id]
  if saved and G.roster[saved] then return saved, true end
  local name = entry.name
  local key = G.Resolve(name)
  if key then return key end
  for part in name:gmatch("[^/|,%s%(%)%[%]]+") do
    local k = G.Resolve(part)
    if k then return k end
  end
  -- a member whose name starts the Discord name
  local low = name:lower()
  for k, r in pairs(G.roster) do
    local n = r.name:lower():gsub("%-.*$", "")
    if #n >= 4 and low:find(n, 1, true) then return k end
  end
end

-- apply an import to event e; map = { [discordId] = memberKey | false }
-- returns added, kept (sign-up in the addon), skipped
function R.ApplyImport(e, imp, map)
  if not R.CanEdit(e) then U.Print(L.NO_RIGHTS); return 0, 0, 0 end
  local s = R.Store()
  e.signups = e.signups or {}
  local added, kept, skipped = 0, 0, 0
  for _, x in ipairs(imp.list) do
    local key = map[x.id]
    if key then
      s.discord[x.id] = key
      local cur = e.signups[key]
      if cur and cur.src ~= "rh" then
        kept = kept + 1
      else
        e.signups[key] = { on = x.st ~= "out", st = x.st, c = x.note, src = "rh",
          f = { role = x.role, class = x.class, tree = x.tree }, t = x.t or U.Now() }
        -- class and spec from Raid-Helper fill gaps in the spec list
        local sp = s.specs[key]
        if x.class and (not sp or not sp.m) then
          s.specs[key] = { class = x.class, m = { x.tree, x.role }, o = sp and sp.o, t = 1, src = "rh" }
        end
        added = added + 1
      end
    else
      skipped = skipped + 1
    end
  end
  R.Changed(e)
  return added, kept, skipped
end
