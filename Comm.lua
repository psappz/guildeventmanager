local ADDON, ns = ...
-- Guild communication over the guild addon channel.
-- * silent until the guild is activated (marker in the guild info)
-- * accepts only senders from the own guild roster
-- * splits long messages, throttles sending, drops duplicates
local U, G = ns.U, ns.Guild
local C = {}
ns.Comm = C

C.PREFIX = "GEM1"
local MAXLEN = 240
local handlers = {}
local queue = {}
local partial = {}   -- sender .. mid -> { total, parts, count, t }
local seen = {}      -- message ids already handled

---------------------------------------------------------------------------
-- Serialiser: tables of strings, numbers, booleans and nested tables
---------------------------------------------------------------------------
local function esc(s) return (s:gsub("[\\{}=;]", function(c) return "\\" .. c end)) end

local function ser(v)
  local t = type(v)
  if t == "string" then return "s" .. esc(v)
  elseif t == "number" then return "n" .. tostring(v)
  elseif t == "boolean" then return v and "b1" or "b0"
  elseif t == "table" then
    local out = {}
    for k, x in pairs(v) do
      local tk = type(k)
      if (tk == "string" or tk == "number") and type(x) ~= "function" then
        out[#out + 1] = ser(k) .. "=" .. ser(x)
      end
    end
    return "{" .. table.concat(out, ";") .. "}"
  end
  return "b0"
end
C.Serialize = ser

local function deser(s, i)
  local tag = s:sub(i, i)
  if tag == "{" then
    local t = {}
    i = i + 1
    while s:sub(i, i) ~= "}" do
      if i > #s then error("bad table") end
      local k; k, i = deser(s, i)
      if s:sub(i, i) ~= "=" then error("bad pair") end
      local v; v, i = deser(s, i + 1)
      t[k] = v
      if s:sub(i, i) == ";" then i = i + 1 end
    end
    return t, i + 1
  end
  -- scalar: read until an unescaped = ; or }
  local j, buf = i + 1, {}
  while j <= #s do
    local c = s:sub(j, j)
    if c == "\\" then buf[#buf + 1] = s:sub(j + 1, j + 1); j = j + 2
    elseif c == "=" or c == ";" or c == "}" then break
    else buf[#buf + 1] = c; j = j + 1 end
  end
  local raw = table.concat(buf)
  if tag == "s" then return raw, j
  elseif tag == "n" then return tonumber(raw), j
  elseif tag == "b" then return raw == "1", j end
  error("bad tag " .. tostring(tag))
end

function C.Deserialize(s)
  local ok, v = pcall(deser, s, 1)
  if ok then return v end
  return nil
end

---------------------------------------------------------------------------
-- Debug log (/gem debug): last 50 sends and receives
---------------------------------------------------------------------------
local function log(dir, kind, who, size)
  local db = ns.db
  if not db then return end
  db.commLog = db.commLog or {}
  table.insert(db.commLog, 1, { t = U.Timestamp(), dir = dir, kind = kind, who = who, size = size })
  while #db.commLog > 50 do table.remove(db.commLog) end
  if ns.debug then U.Print(("|cff9fb4c8%s %s %s (%d B)|r"):format(dir, kind, tostring(who), size or 0)) end
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local sender = CreateFrame("Frame")
sender:Hide()
local nextAt = 0
sender:SetScript("OnUpdate", function(self)
  if GetTime() < nextAt then return end
  local m = table.remove(queue, 1)
  if not m then self:Hide(); return end
  local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  local ok, err = pcall(fn, C.PREFIX, m.text, m.dist, m.target)
  if not ok then ns.LogError("comm", err) end
  nextAt = GetTime() + 0.25
end)

local midCounter = 0
local function enqueue(text, dist, target)
  queue[#queue + 1] = { text = text, dist = dist, target = target }
  sender:Show()
end

-- Allowed to talk? Only with guild, activated, and not switched off
function C.CanSend()
  if ns.demo then return false end
  return G.InGuild() and G.IsActivated() and not (ns.db and ns.db.silent)
end

-- kind: short tag ("PROF", "EVT", ...), data: table
function C.Send(kind, data, dist, target)
  dist = dist or "GUILD"
  if ns.demo then return false end
  if dist == "GUILD" and not C.CanSend() then return false end
  data = data or {}
  data._id = data._id or U.NewId()
  seen[data._id] = true
  local body = kind .. "\t" .. ser(data)
  log("->", kind, dist, #body)
  if #body <= MAXLEN then
    enqueue("S" .. body, dist, target)
  else
    midCounter = (midCounter + 1) % 1000
    local mid = string.format("%x%03d", U.Now() % 65536, midCounter)
    local size = MAXLEN - 20
    local total = math.ceil(#body / size)
    for i = 1, total do
      enqueue(("C%s:%d:%d:"):format(mid, i, total) .. body:sub((i - 1) * size + 1, i * size), dist, target)
    end
  end
  return true
end

-- Several handlers per kind (core and modules may both listen, e.g. to HELLO)
function C.On(kind, fn)
  handlers[kind] = handlers[kind] or {}
  table.insert(handlers[kind], fn)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function dispatch(body, senderName, dist)
  local kind, payload = body:match("^(%u+)\t(.*)$")
  if not kind then return end
  local data = C.Deserialize(payload)
  if type(data) ~= "table" then return end
  if data._id then
    if seen[data._id] then return end
    seen[data._id] = true
  end
  local key = G.Resolve(senderName)
  log("<-", kind, senderName, #body)
  if dist == "GUILD" and not key then return end   -- not in our roster: ignore
  for _, fn in ipairs(handlers[kind] or {}) do
    ns.SafeCall("comm:" .. kind, fn, data, key or G.Key(senderName), dist)
  end
end

function C.OnMessage(prefix, text, dist, senderName)
  if prefix ~= C.PREFIX or not text then return end
  if not G.IsActivated() then return end     -- guild master has not activated the addon
  if ns.demo then return end                 -- demo data must not mix with real messages
  if (G.Resolve(senderName) or G.Key(senderName)) == G.MyKey() and dist == "GUILD" then return end -- own echo
  local t = text:sub(1, 1)
  if t == "S" then
    dispatch(text:sub(2), senderName, dist)
  elseif t == "C" then
    local mid, i, total, part = text:match("^C(%x+):(%d+):(%d+):(.*)$")
    i, total = tonumber(i), tonumber(total)
    if not mid or not i or not total then return end
    local k = senderName .. mid
    local p = partial[k] or { total = total, parts = {}, count = 0, t = GetTime() }
    partial[k] = p
    if not p.parts[i] then p.parts[i] = part; p.count = p.count + 1 end
    if p.count == p.total then
      partial[k] = nil
      dispatch(table.concat(p.parts), senderName, dist)
    end
  end
  -- forget unfinished messages after 60 s
  for k, p in pairs(partial) do if GetTime() - p.t > 60 then partial[k] = nil end end
end

function C.Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(C.PREFIX)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(C.PREFIX)
  end
end
