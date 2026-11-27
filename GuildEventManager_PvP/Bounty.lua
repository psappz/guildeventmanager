local ADDON, P = ...
-- Bounties: a member puts GP (the guild's points, pot "honor") on the head of
-- an enemy player. Whoever of the guild kills that player first gets them; a
-- group of guild members that kills him together shares them.
--
-- Core rule: every client books only its own points. So bounties are paid in
-- advance: the poster (and everyone who adds to it) books a minus for himself
-- (Pts.SELF_NEG). The hunters book their plus when their client is sure of the
-- kill. Expired or withdrawn bounties: every payer books his own share back.
-- Guild bounties (officers, weekly limit) are paid by nobody.
--
-- 0.9: WANTED posters. A bounty also carries what the poster's client knows
-- about the enemy (race, sex, class, level, where and when he was seen); any
-- member who sees him later updates it. See Wanted.lua for the posters.
local core = P.core
if not core then return end
local U, G, C, Pts = core.U, core.Guild, core.Comm, core.Points
local L = P.L

local DAY, WEEK = 86400, 7 * 86400
local GRACE = DAY        -- payers wait a day after expiry before booking back (late claims)
local SHARE_WAIT = 4     -- seconds to collect the claims of the own group before booking
P.bounties = {}          -- id -> bounty (see P.NewBounty)

-- same spelling rule as the kill detection: "Name-Realm" / "First Last" -> "name realm" / "first last"
local function tkey(name)
  return name and (tostring(name):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%-%s]+", " ")) or nil
end
P.BountyKey = tkey

local function store()
  local c = P.Char()
  c.bounties = c.bounties or {}
  return c.bounties
end

local function remember(b)
  if core.demo then return end
  store()[b.id] = b
end

local function refreshUI() if core.UI and core.UI.Refresh then core.UI.Refresh() end end
local function fire(ev, ...) core.Fire(ev, ...) end

local function rule(k, def) local v = tonumber(P.Rules()[k]); if v == nil then return def end; return v end
local function days() return math.max(1, rule("bountyDays", 7)) end

-- smallest bounty: at least 5 above the GP of a normal kill; largest: 50 (per person)
P.BOUNTY_CAP = 50
function P.BountyLimits()
  local floor = rule("kill", 3) + 5
  local min = math.max(floor, rule("bountyMin", floor))
  local max = math.min(P.BOUNTY_CAP, rule("bountyMax", P.BOUNTY_CAP))
  if max < min then max = min end
  return min, math.min(max, P.BOUNTY_CAP)
end

-- a bounty only pays when the name is sure to be the own kill: the honor line,
-- or the enemy died in my target. A nameplate that died near me can be somebody
-- else's kill, so it does not count (the normal kill GP still do).
local SURE = { ["honor line"] = true, ["dead target"] = true, ["seen dying target"] = true }
P.BOUNTY_SOURCES = SURE

-- total = the poster's amount plus everything added by others
function P.BountyTotal(b)
  local sum = tonumber(b.amt) or 0
  for _, a in pairs(b.adds or {}) do sum = sum + (tonumber(a) or 0) end
  return sum
end

function P.BountyState(b)
  if b.state == "open" and U.Now() - (b.ts or 0) > days() * DAY then return "expired" end
  return b.state
end

-- "GP" with the coin in front, for amounts on screen (never for guild chat)
function P.GPTag(big) return U.Coin(big) .. " " .. L.GP_SHORT end

function P.BountyEnds(b) return (b.ts or 0) + days() * DAY end

-- open bounties, highest first
function P.OpenBounties()
  local res = {}
  for _, b in pairs(P.bounties) do if P.BountyState(b) == "open" then res[#res + 1] = b end end
  table.sort(res, function(x, y)
    local tx, ty = P.BountyTotal(x), P.BountyTotal(y)
    if tx ~= ty then return tx > ty end
    return (x.ts or 0) < (y.ts or 0)
  end)
  return res
end

-- collected bounties, newest first
function P.WonBounties()
  local res = {}
  for _, b in pairs(P.bounties) do if b.state == "done" then res[#res + 1] = b end end
  table.sort(res, function(x, y) return (x.wts or 0) > (y.wts or 0) end)
  return res
end

-- every bounty of the last n days (open, collected, expired, withdrawn), newest first
function P.RecentBounties(n)
  local res, now = {}, U.Now()
  for _, b in pairs(P.bounties) do
    local t = b.wts or b.offts or b.ts or 0
    if now - t <= (n or 7) * DAY or P.BountyState(b) == "open" then res[#res + 1] = b end
  end
  table.sort(res, function(x, y) return (x.ts or 0) > (y.ts or 0) end)
  return res
end

-- sum of open bounties on a name (for the target notice and the UI)
function P.BountyOn(name)
  local k, sum, n = tkey(name), 0, 0
  for _, b in ipairs(P.OpenBounties()) do if b.tk == k then sum = sum + P.BountyTotal(b); n = n + 1 end end
  return sum, n
end

local function myBalance()
  local t = Pts.Totals("season")[G.MyKey()]
  return t and t.pots.honor or 0
end
P.MyHonorBalance = myBalance
P.MyGP = myBalance

---------------------------------------------------------------------------
-- What we know about enemy players we saw (target, mouseover, nameplates):
-- race, sex, class, level, zone, time. Filled by Detect.lua (P.NoteEnemy).
---------------------------------------------------------------------------
P.seenEnemies = P.seenEnemies or {}
local seenCount = 0

local function secret(v) return issecretvalue and issecretvalue(v) or false end
local function clean(v) if v == nil or secret(v) then return nil end return v end

-- The layer: the game has no function for it. A creature's GUID is
-- Creature-0-[server]-[map]-[zoneUID]-[npc]-[spawn]; server and zoneUID name the
-- layer (the way LayerSwap and Nova World Buffs read it). Letters like "Layer B"
-- are given by every client itself, so between players only the raw id can be
-- compared: the poster says "yours" or "another".
local layerNow, layerVotes = nil, {}
local function readLayer(unit)
  if not UnitGUID then return end
  local ok, guid = pcall(UnitGUID, unit)
  if not ok or type(guid) ~= "string" or secret(guid) then return end
  local kind, server, zoneUID = guid:match("^(%a+)%-%d+%-(%d+)%-%d+%-(%d+)%-")
  if kind ~= "Creature" or not server or not zoneUID then return end
  if UnitPlayerControlled then
    if U.UnitTrue(UnitPlayerControlled, unit) then return end
  end
  local id = server .. "-" .. zoneUID
  layerVotes[id] = layerVotes[id] or {}
  layerVotes[id][guid] = true
  local n = 0
  for _ in pairs(layerVotes[id]) do n = n + 1 end
  if n >= 2 and layerNow ~= id then layerNow = id end   -- two different creatures agree
end
P.ReadLayer = readLayer

function P.Layer() return layerNow end

function P.LayerText(id)
  if not id then return "–" end
  if layerNow and id == layerNow then return L.WNT_LAYER_SAME end
  if layerNow then return L.WNT_LAYER_OTHER end
  return "?"
end

do
  local lf = CreateFrame("Frame")
  lf:RegisterEvent("PLAYER_TARGET_CHANGED")
  lf:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  lf:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  lf:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  lf:RegisterEvent("PLAYER_ENTERING_WORLD")
  lf:SetScript("OnEvent", function(_, ev, unit)
    if ev == "ZONE_CHANGED_NEW_AREA" or ev == "PLAYER_ENTERING_WORLD" then layerNow, layerVotes = nil, {}; return end
    local u = (ev == "PLAYER_TARGET_CHANGED" and "target") or (ev == "UPDATE_MOUSEOVER_UNIT" and "mouseover") or unit
    if u then pcall(readLayer, u) end
  end)
end

local function zoneNow()
  local z = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText()) or ""
  local s = GetSubZoneText and GetSubZoneText() or ""
  return clean(z) or "", clean(s) or ""
end

function P.UnitInfo(unit)
  local i = {}
  local ok, rName, rFile = pcall(UnitRace, unit)
  if ok then i.r = clean(rName); i.rf = clean(rFile) end
  local okS, sx = pcall(UnitSex, unit)
  if okS then i.sx = clean(sx) end
  local okC, cName, cFile = pcall(UnitClass, unit)
  if okC then i.cl = clean(cName); i.cf = clean(cFile) end
  local okL, lv = pcall(UnitLevel, unit)
  if okL then i.lv = tonumber(clean(lv)) end
  i.z, i.sz = zoneNow()
  i.st = U.Now()
  return i
end

function P.NoteEnemy(unit, name)
  if not unit or not name then return end
  local k = tkey(name)
  local old = P.seenEnemies[k]
  if old and U.Now() - (old.st or 0) < 10 then return end
  local i = P.UnitInfo(unit)
  i.name = name
  if not old then
    seenCount = seenCount + 1
    if seenCount == 1 then for _ in pairs(P.seenEnemies) do seenCount = seenCount + 1 end end
    if seenCount > 300 then   -- keep the cache small: drop the oldest half
      local list = {}
      for kk, v in pairs(P.seenEnemies) do list[#list + 1] = { kk, v.st or 0 } end
      table.sort(list, function(a, b) return a[2] < b[2] end)
      for n = 1, math.floor(#list / 2) do P.seenEnemies[list[n][1]] = nil end
      seenCount = #list - math.floor(#list / 2)
    end
  end
  P.seenEnemies[k] = i
  P.BountySighted(name, i)
end

function P.SeenInfo(name) return P.seenEnemies[tkey(name)] end

-- copy the fields of an info table that are filled (newer data wins)
local INFO = { "r", "rf", "sx", "cl", "cf", "lv", "z", "sz", "st", "ly" }
local function mergeInfo(b, i)
  if type(i) ~= "table" then return false end
  b.i = b.i or {}
  if (tonumber(i.st) or 0) < (tonumber(b.i.st) or 0) then
    -- older sighting: only fill gaps (race and class never change)
    for _, f in ipairs(INFO) do if b.i[f] == nil and i[f] ~= nil then b.i[f] = i[f] end end
    return false
  end
  for _, f in ipairs(INFO) do
    local v = i[f]
    if v ~= nil then
      if type(v) == "string" then v = v:sub(1, 48) end
      b.i[f] = v
    end
  end
  return true
end
P.MergeBountyInfo = mergeInfo

local function packInfo(i)
  if type(i) ~= "table" then return nil end
  local o = {}
  for _, f in ipairs(INFO) do o[f] = i[f] end
  return o
end

-- note of the poster (0.9): up to 200 characters, not on the poster itself,
-- only in the tooltip of the poster on screen and in the large view
P.NOTE_MAX = 200
function P.CleanNote(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("|", "/"):gsub("[\r\n\t]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  -- cut after 200 characters, not inside a multi-byte character
  local n, i = 0, 1
  while i <= #s do
    n = n + 1
    if n > P.NOTE_MAX then return s:sub(1, i - 1) end
    local c = s:byte(i)
    i = i + ((c >= 240 and 4) or (c >= 224 and 3) or (c >= 192 and 2) or 1)
  end
  return s
end

local function send(kind, data) if not core.demo then C.Send(kind, data) end end
local function sendBounty(b)
  send("BNTY", { b = { id = b.id, by = b.by, target = b.target, amt = b.amt, ts = b.ts, gb = b.gb, i = packInfo(b.i), n = b.note } })
end

---------------------------------------------------------------------------
-- Guild bounties (officers, paid by nobody) and their weekly limit
---------------------------------------------------------------------------
-- week starts Monday 00:00 (local clock of the server time)
function P.WeekStart(now)
  now = now or U.Now()
  local t = date("*t", now)
  local wd = (t.wday + 5) % 7          -- Monday = 0
  return now - wd * DAY - t.hour * 3600 - t.min * 60 - t.sec
end

function P.GuildChestUsed()
  local ws, used = P.WeekStart(), 0
  for _, b in pairs(P.bounties) do
    -- set this week and not withdrawn (an expired one was offered all the same)
    if b.gb and (b.ts or 0) >= ws and (b.state ~= "off" or b.expired) then used = used + (tonumber(b.amt) or 0) end
  end
  -- triple bonuses are paid from the chest too
  for _, b in pairs(P.bounties) do
    if b.tri and (b.tri.ts or 0) >= ws then used = used + (tonumber(b.tri.amt) or 0) end
  end
  return used, rule("guildBountyWeek", 100)
end

function P.CanGuildBounty() return G.IsManager() end

---------------------------------------------------------------------------
-- Setting, adding, withdrawing
---------------------------------------------------------------------------
-- may I put a bounty on this name? returns ok, reason text
function P.CanPostOn(name, amt, guild)
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  if name == "" then return false, L.PVP_BNT_NONAME end
  if G.Resolve(name) then return false, L.PVP_BNT_GUILD:format(name) end
  local min, max = P.BountyLimits()
  amt = math.floor(tonumber(amt) or 0)
  if amt < min or amt > max then return false, L.PVP_BNT_RANGE:format(min, max) end
  local k, now = tkey(name), U.Now()
  -- one open bounty per enemy and poster; a pause after a bounty was collected
  local pause = rule("bountyPause", 6) * 3600
  for _, b in pairs(P.bounties) do
    if b.tk == k then
      if P.BountyState(b) == "open" and (b.by == G.MyKey() or (guild and b.gb)) then return false, L.PVP_BNT_ALREADY:format(name) end
      if b.state == "done" and now - (b.wts or 0) < pause then
        return false, L.PVP_BNT_PAUSE:format(name, math.ceil((pause - (now - (b.wts or 0))) / 3600))
      end
    end
  end
  -- not on enemies far below the own level
  local info = P.SeenInfo(name)
  local gap = rule("bountyGap", 5)
  local mine = UnitLevel and tonumber(UnitLevel("player")) or nil
  if info and info.lv and info.lv > 0 and mine and info.lv < mine - gap then
    return false, L.PVP_BNT_LOWLEVEL:format(name, info.lv, mine - gap)
  end
  if guild then
    if not P.CanGuildBounty() then return false, L.PVP_BNT_NOTOFFICER end
    local used, limit = P.GuildChestUsed()
    if used + amt > limit then return false, L.PVP_BNT_CHEST:format(math.max(0, limit - used), limit) end
  else
    local me, open = G.MyKey(), 0
    for _, b in ipairs(P.OpenBounties()) do if b.by == me and not b.gb then open = open + 1 end end
    local maxOpen = rule("bountyOpen", 3)
    if maxOpen > 0 and open >= maxOpen then return false, L.PVP_BNT_MAXOPEN:format(maxOpen) end
    if myBalance() < amt then return false, L.PVP_BNT_POOR:format(myBalance()) end
  end
  return true
end

-- opts: { guild = true } for a guild bounty, note = text (up to 200 characters)
function P.PostBounty(name, amt, opts)
  opts = opts or {}
  if not C.CanSend() then U.Print(core.L.NOT_ACTIVE); return end
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  amt = math.floor(tonumber(amt) or 0)
  local ok, why = P.CanPostOn(name, amt, opts.guild)
  if not ok then U.Print(why); return end
  local me = G.MyKey()
  local b = { id = U.NewId(), by = me, target = name, tk = tkey(name), amt = amt, ts = U.Now(), state = "open",
    gb = opts.guild and 1 or nil, adds = {}, note = P.CleanNote(opts.note) }
  local seen = P.SeenInfo(name)
  if seen then mergeInfo(b, seen) end
  if not b.gb then
    local e = Pts.AddSelf("honor", -amt, "bounty", { note = name, bid = b.id, flag = "set" })
    if not e then return end
  end
  P.bounties[b.id] = b
  remember(b)
  sendBounty(b)
  U.Print((b.gb and L.PVP_BNT_SET_GUILD or L.PVP_BNT_SET):format(amt, name, days()))
  fire("PVP_BOUNTY_NEW", b, true)
  refreshUI()
  return b
end

-- put more GP on an open bounty (paid in advance, back when it expires)
function P.AddToBounty(id, amt)
  local b = P.bounties[id]
  if not b or P.BountyState(b) ~= "open" then return end
  if b.test then U.Print("GEM: test bounty, nothing booked."); return end
  if not C.CanSend() then U.Print(core.L.NOT_ACTIVE); return end
  local me = G.MyKey()
  amt = math.floor(tonumber(amt) or 0)
  local mine = (b.adds and b.adds[me] or 0) + ((b.by == me and not b.gb) and b.amt or 0)
  amt = math.min(amt, P.BOUNTY_CAP - mine)
  if amt <= 0 then U.Print(L.PVP_BNT_ADD_MAX:format(P.BOUNTY_CAP)); return end
  if myBalance() < amt then U.Print(L.PVP_BNT_POOR:format(myBalance())); return end
  local e = Pts.AddSelf("honor", -amt, "bounty", { note = b.target, bid = b.id, flag = "add" })
  if not e then return end
  b.adds = b.adds or {}
  b.adds[me] = (b.adds[me] or 0) + amt
  remember(b)
  send("BNTYADD", { id = b.id, a = b.adds[me] })
  U.Print(L.PVP_BNT_ADDED:format(amt, b.target, P.BountyTotal(b)))
  fire("PVP_BOUNTY_ADD", b, me, amt)
  refreshUI()
  return true
end

function P.CanCancel(b)
  if b and b.test then return false end
  if not b or b.by ~= G.MyKey() or P.BountyState(b) ~= "open" then return false end
  for k, a in pairs(b.adds or {}) do if k ~= b.by and (a or 0) > 0 then return false end end
  return true
end

local function refund(b, why)
  if b.refunded or b.gb then b.refunded = true; return end
  local e = Pts.AddSelf("honor", b.amt, "bounty", { note = b.target, bid = b.id, flag = why })
  if e then b.refunded = true end
end

local function refundAdd(b, why)
  local me = G.MyKey()
  local a = b.adds and b.adds[me]
  if not a or a <= 0 or b.addBack then return end
  local e = Pts.AddSelf("honor", a, "bounty", { note = b.target, bid = b.id, flag = why or "addback" })
  if e then b.addBack = true end
end

function P.CancelBounty(id)
  local b = P.bounties[id]
  if not P.CanCancel(b) then return end
  b.state = "off"; b.offts = U.Now()
  refund(b, "back")
  remember(b)
  send("BNTYDEL", { id = id })
  U.Print(L.PVP_BNT_CANCELLED:format(b.target, b.amt))
  fire("PVP_BOUNTY_OFF", b, "back")
  refreshUI()
end

-- payers book expired bounties back (after a grace day for late claims)
local function expire()
  local me, now = G.MyKey(), U.Now()
  if not C.CanSend() then return end
  for _, b in pairs(P.bounties) do
    local late = now - (b.ts or 0) > days() * DAY + GRACE
    if late and (b.state == "open" or (b.state == "off" and b.expired)) then
      if b.by == me and b.state == "open" then
        b.state = "off"; b.offts = now; b.expired = true
        refund(b, "exp")
        remember(b)
        send("BNTYDEL", { id = b.id, exp = 1 })
        U.Print(L.PVP_BNT_EXPIRED:format(b.target, P.BountyTotal(b)))
        fire("PVP_BOUNTY_OFF", b, "exp")
      end
      if b.adds and b.adds[me] and not b.addBack then
        refundAdd(b, "addback")
        remember(b)
      end
    end
    -- withdrawn by the poster: contributors (if any slipped in) get theirs back at once
    if b.state == "off" and not b.expired and b.adds and b.adds[me] and not b.addBack and b.by ~= me then
      refundAdd(b, "addback"); remember(b)
    end
  end
end
P.ExpireBounties = expire

---------------------------------------------------------------------------
-- Collecting: the own group shares, a bonus for repeated kills
---------------------------------------------------------------------------
-- guild keys of my party / raid (with me)
local function groupKeys()
  local set = { [G.MyKey()] = true }
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  if n > 0 then
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
      local unit = raid and ("raid" .. i) or ("party" .. i)
      if U.UnitTrue(UnitExists, unit) then
        local k = G.UnitKey(unit)
        if k then set[k] = true end
      end
    end
  end
  return set
end
P.GroupKeys = groupKeys

-- equal shares, the remainder goes to the first names in alphabetical order
function P.SplitShares(total, keys)
  local list = {}
  for _, k in ipairs(keys) do list[#list + 1] = k end
  table.sort(list)
  local n, out = #list, {}
  if n == 0 then return out end
  local base, rest = math.floor(total / n), total % n
  for i, k in ipairs(list) do out[k] = base + (i <= rest and 1 or 0) end
  return out
end

-- more than SELF_MAX: several entries; only the first carries the flag
-- (achievements count "won" entries)
local function bookPlus(amt, extra)
  local first
  while amt > 0 do
    local part = math.min(amt, Pts.SELF_MAX)
    local x = extra
    if first then
      x = {}
      for k, v in pairs(extra) do x[k] = v end
      x.flag = (extra.flag or "") .. "+"
    end
    local e = Pts.AddSelf("honor", part, "bounty", x)
    if not e then break end
    first = first or e
    amt = amt - part
  end
  return first
end

local pending = {}   -- bounty id -> { ts, hits = { key = ts } } while collecting the group's claims

local function finishClaim(b)
  local pc = pending[b.id]
  pending[b.id] = nil
  if not pc or b.state ~= "open" then return end
  local me, group = G.MyKey(), groupKeys()
  local ws = {}
  for k, t in pairs(pc.hits) do
    if k == me or (group[k] and math.abs(t - pc.ts) <= 30) then ws[#ws + 1] = k end
  end
  table.sort(ws)
  local total = P.BountyTotal(b)
  local shares = P.SplitShares(total, ws)
  local mine = shares[me] or 0
  local pe
  for _, x in ipairs(P.PublicEnemies and P.PublicEnemies() or {}) do if x.tk == b.tk then pe = 1 end end
  local e = bookPlus(mine, { note = b.target, bid = b.id, flag = "won", ch = b.by, n = #ws, pe = pe })
  if not e then return end
  b.state = "done"; b.w = ws[1]; b.ws = ws; b.wts = pc.ts; b.myShare = mine
  b.rep = { n = 1, last = pc.ts, till = pc.ts + rule("bonusMin", 15) * 60, ws = ws }
  remember(b)
  send("BNTYWON", { id = b.id, w = ws[1], ws = table.concat(ws, ","), ts = pc.ts })
  P.Notice(L.PVP_BNT_WON:format(mine, b.target, G.Display(b.by)))
  fire("PVP_BOUNTY_WON", b, true)
  refreshUI()
end

local function claim(b, ts)
  if pending[b.id] then return end
  local me = G.MyKey()
  ts = ts or U.Now()
  pending[b.id] = { ts = ts, hits = { [me] = ts } }
  send("BNTYHIT", { id = b.id, ts = ts })
  core.Schedule("gemBntyClaim" .. b.id, SHARE_WAIT, function() finishClaim(b) end)
end

-- repeated kills after the bounty was collected: bonus from the guild chest
local function countRepeat(b, ts)
  local r = b.rep
  if not r or r.paid or ts > r.till then return end
  if ts - (r.last or 0) < 15 then return end      -- the same kill reported by several members
  r.n = r.n + 1; r.last = ts
  local need = rule("bonusKills", 3)
  if r.n >= need then
    r.paid = true
    local bonus = rule("bonus", 10)
    local me = G.MyKey()
    local shares = P.SplitShares(bonus, r.ws or { me })
    local mine = shares[me] or 0
    if mine > 0 then
      bookPlus(mine, { note = b.target, bid = b.id, flag = "triple", n = #(r.ws or {}) })
    end
    b.tri = { ts = ts, amt = bonus }
    -- one big message to the guild: from the first name of the group
    if (r.ws or { me })[1] == me and core.Contest and core.Contest.AlertGuild then
      core.Contest.AlertGuild(L.PVP_BNT_TRIPLE_ALL:format(table.concat((function()
        local names = {}
        for _, k in ipairs(r.ws or { me }) do names[#names + 1] = G.Display(k) end
        return names
      end)(), ", "), b.target, need, rule("bonusMin", 15), bonus))
    end
    P.Notice(L.PVP_BNT_TRIPLE:format(need, b.target, mine))
    fire("PVP_BOUNTY_TRIPLE", b)
  end
  remember(b)
  refreshUI()
end

core.On("PVP_KILL", function(name, kind, source)
  if not name then return end
  local k, me = tkey(name), G.MyKey()
  if source and not SURE[source] then
    for _, b in ipairs(P.OpenBounties()) do
      if b.tk == k and b.by ~= me then U.Print(L.PVP_BNT_UNSURE:format(name)); break end
    end
    return
  end
  local now = U.Now()
  for _, b in ipairs(P.OpenBounties()) do
    if b.tk == k and (b.by ~= me or b.gb) then claim(b, now) end
  end
  -- a repeat kill of a bounty my group collected
  for _, b in pairs(P.bounties) do
    if b.tk == k and b.state == "done" and b.rep and not b.rep.paid and now <= b.rep.till then
      local inIt = false
      for _, w in ipairs(b.rep.ws or {}) do if w == me then inIt = true end end
      if inIt then
        send("BNTYREP", { id = b.id, ts = now })
        countRepeat(b, now)
      end
    end
  end
  refreshUI()
end)

---------------------------------------------------------------------------
-- Sightings: any member who sees a wanted enemy updates the poster
---------------------------------------------------------------------------
local lastSent, lastZoneHint = {}, {}
function P.BountySighted(name, i)
  local k = tkey(name)
  local hit
  for _, b in pairs(P.bounties) do
    if b.tk == k and P.BountyState(b) == "open" then
      mergeInfo(b, i); remember(b); hit = b
    end
  end
  if not hit then return end
  if not lastSent[k] or GetTime() - lastSent[k] > 300 then
    lastSent[k] = GetTime()
    send("BNTYSEEN", { k = k, n = name:sub(1, 48), i = packInfo(i) })
  end
  fire("PVP_BOUNTY_SEEN", hit, true)
end

---------------------------------------------------------------------------
-- Public enemies: an enemy who killed 3 different members within 7 days
---------------------------------------------------------------------------
local function foes()
  if not core.db then return {} end
  core.db.pvpFoes = core.db.pvpFoes or {}
  return core.db.pvpFoes
end

local function noteFoeKill(name, who, t)
  local k = tkey(name)
  if not k or G.Resolve(name) then return end
  local f = foes()
  local e = f[k] or { name = name, kills = {} }
  e.name = name
  e.kills[who] = math.max(e.kills[who] or 0, t)
  f[k] = e
end

function P.PublicEnemies()
  local out, now = {}, U.Now()
  local need = rule("foeMembers", 3)
  for k, e in pairs(foes()) do
    local n = 0
    for who, t in pairs(e.kills) do
      if now - t <= WEEK then n = n + 1 else e.kills[who] = nil end
    end
    if n == 0 then foes()[k] = nil
    elseif n >= need then
      local sum = P.BountyOn(e.name)
      out[#out + 1] = { name = e.name, tk = k, n = n, open = sum > 0 }
    end
  end
  table.sort(out, function(a, b) return a.n > b.n end)
  return out
end

-- a member died to an enemy player: tell the guild (for the public enemies)
core.On("PVP_DEBT_NEW", function(d)
  if not d or not d.name then return end
  local me, now = G.MyKey(), U.Now()
  noteFoeKill(d.name, me, now)
  send("FOEKILL", { n = d.name:sub(1, 48), t = now })
  P.OfferBountyAfterDeath(d)
end)

-- after a death: offer a bounty right away (Wanted.lua shows the offer)
function P.OfferBountyAfterDeath(d)
  if P.ShowDeathOffer then core.SafeCall("pvpBountyOffer", P.ShowDeathOffer, d) end
end

local toldFoe = {}
local function checkPublicEnemies()
  if not G.IsManager() then return end
  for _, f in ipairs(P.PublicEnemies()) do
    if not f.open and not toldFoe[f.tk] then
      toldFoe[f.tk] = true
      local text = L.PVP_BNT_FOE_NOTICE:format(f.name, f.n)
      if core.Notices then core.Notices.Add({ key = "foe:" .. f.tk, group = L.TAB_PVP, text = text, view = "pvp" }) end
    end
  end
end

---------------------------------------------------------------------------
-- Weekly recap (shown in the bounty tab, posted Sundays 20:00 to the guild chat)
---------------------------------------------------------------------------
function P.WeekRecap(ws)
  ws = ws or P.WeekStart()
  local we = ws + WEEK
  local r = { set = 0, done = 0, paid = 0, triples = 0, hunters = {} }
  for _, b in pairs(P.bounties) do
    if (b.ts or 0) >= ws and (b.ts or 0) < we then r.set = r.set + 1 end
    if b.state == "done" and (b.wts or 0) >= ws and (b.wts or 0) < we then
      r.done = r.done + 1
      local total = P.BountyTotal(b)
      r.paid = r.paid + total
      for k, v in pairs(P.SplitShares(total, b.ws or { b.w })) do
        r.hunters[k] = r.hunters[k] or { n = 0, gp = 0 }
        r.hunters[k].n = r.hunters[k].n + 1
        r.hunters[k].gp = r.hunters[k].gp + v
      end
    end
    if b.tri and (b.tri.ts or 0) >= ws and (b.tri.ts or 0) < we then r.triples = r.triples + 1 end
  end
  local best
  for k, h in pairs(r.hunters) do
    if not best or h.n > best.n or (h.n == best.n and h.gp > best.gp) then best = { key = k, n = h.n, gp = h.gp } end
  end
  r.best = best
  local open = P.OpenBounties()
  r.most = open[1]
  return r
end

local recapDone = {}
local function weekId(t) return date("%Y-%m-%d", P.WeekStart(t)) end
local function postRecap()
  if not G.IsManager() or not C.CanSend() then return end
  local id = weekId()
  if recapDone[id] or (core.db and core.db.pvpRecap == id) then return end
  local r = P.WeekRecap()
  if r.set == 0 and r.done == 0 then return end
  recapDone[id] = true
  if core.db then core.db.pvpRecap = id end
  send("RECAP", { w = id })
  local text = L.PVP_BNT_RECAP_CHAT:format(r.set, r.done, r.paid)
  if r.best then text = text .. " " .. L.PVP_BNT_RECAP_BEST:format(G.Display(r.best.key), r.best.n) end
  if SendChatMessage then pcall(SendChatMessage, text, "GUILD") end
end

C.On("RECAP", function(data)
  if type(data.w) == "string" then recapDone[data.w] = true; if core.db then core.db.pvpRecap = data.w end end
end)

local function recapTick()
  local t = date("*t", U.Now())
  if t.wday == 1 and t.hour >= 20 and t.hour < 23 then
    -- managers wait a random moment; the first one posts, the others hear RECAP
    core.Schedule("gemBntyRecap", 5 + math.random() * 90, postRecap)
  end
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
C.On("BNTY", function(data, from)
  local d = type(data.b) == "table" and data.b
  if not d or type(d.id) ~= "string" or d.by ~= from or type(d.target) ~= "string" then return end
  local amt = tonumber(d.amt)
  if not amt or amt < 1 or amt > P.BOUNTY_CAP then return end
  local b = P.bounties[d.id]
  if b then
    local changed = mergeInfo(b, d.i)
    if not b.note and d.n then b.note = P.CleanNote(d.n); changed = changed or b.note ~= nil end
    if changed then remember(b); refreshUI() end
    return
  end
  if d.gb and not G.IsManager(from) then return end
  b = { id = d.id, by = from, target = d.target:sub(1, 48), tk = tkey(d.target), amt = math.floor(amt),
        ts = tonumber(d.ts) or U.Now(), state = "open", gb = d.gb and 1 or nil, adds = {}, note = P.CleanNote(d.n) }
  mergeInfo(b, d.i)
  P.bounties[b.id] = b
  remember(b)
  local fresh = P.BountyState(b) == "open" and U.Now() - b.ts < 600
  fire("PVP_BOUNTY_NEW", b, false, fresh)
  refreshUI()
end)

C.On("BNTYADD", function(data, from)
  local b = type(data.id) == "string" and P.bounties[data.id]
  local a = tonumber(data.a)
  if not b or not a or a < 0 or a > P.BOUNTY_CAP or from == G.MyKey() then return end
  b.adds = b.adds or {}
  local old = b.adds[from] or 0
  if a <= old then return end
  b.adds[from] = math.floor(a)
  remember(b)
  fire("PVP_BOUNTY_ADD", b, from, a - old)
  refreshUI()
end)

C.On("BNTYSEEN", function(data, from)
  if type(data.k) ~= "string" or type(data.i) ~= "table" then return end
  local hit
  for _, b in pairs(P.bounties) do
    if b.tk == data.k and P.BountyState(b) == "open" then
      if mergeInfo(b, data.i) then remember(b) end
      hit = b
    end
  end
  if not hit then return end
  -- members in the same zone get a short hint
  local z = zoneNow()
  if data.i.z and data.i.z == z and (not lastZoneHint[data.k] or GetTime() - lastZoneHint[data.k] > 300) then
    lastZoneHint[data.k] = GetTime()
    U.Print(U.Color(U.GOLD, L.PVP_BNT_NEARBY:format(G.Display(from), hit.target, data.i.sz ~= "" and data.i.sz or data.i.z)))
  end
  fire("PVP_BOUNTY_SEEN", hit, false)
  refreshUI()
end)

C.On("BNTYDEL", function(data, from)
  local b = type(data.id) == "string" and P.bounties[data.id]
  if not b or b.by ~= from then return end
  if b.state == "open" then
    b.state = "off"; b.offts = U.Now(); b.expired = data.exp and true or nil
    remember(b)
    fire("PVP_BOUNTY_OFF", b, data.exp and "exp" or "back")
    -- withdrawn: contributors book theirs back at once
    if not b.expired then refundAdd(b, "addback"); remember(b) end
  end
  refreshUI()
end)

C.On("BNTYHIT", function(data, from)
  local pc = type(data.id) == "string" and pending[data.id]
  local ts = tonumber(data.ts)
  if pc and ts then pc.hits[from] = ts end
end)

C.On("BNTYREP", function(data, from)
  local b = type(data.id) == "string" and P.bounties[data.id]
  local ts = tonumber(data.ts)
  if not b or not ts or not b.rep or b.rep.paid then return end
  local inIt = false
  for _, w in ipairs(b.rep.ws or {}) do if w == from then inIt = true end end
  if inIt then countRepeat(b, ts) end
end)

local function splitList(s)
  local out = {}
  for k in tostring(s or ""):gmatch("[^,]+") do out[#out + 1] = k end
  return out
end

C.On("BNTYWON", function(data, from)
  local b = type(data.id) == "string" and P.bounties[data.id]
  local ts = tonumber(data.ts)
  if not b or not ts or (from == b.by and not b.gb) then return end
  local ws = splitList(data.ws)
  if #ws == 0 then ws = { data.w or from } end
  local fromIn = false
  for _, k in ipairs(ws) do if k == from then fromIn = true end end
  if not fromIn then return end
  if ts - b.ts > days() * DAY + 60 then return end          -- killed after it ran out
  local me = G.MyKey()
  if b.state == "done" then
    -- the same group: nothing to do
    for _, k in ipairs(b.ws or { b.w }) do if k == from then return end end
    -- two groups: the earlier claim wins (same second: the smaller first name)
    if b.wts < ts or (b.wts == ts and (b.w or "") < (ws[1] or "")) then return end
    if b.myShare and b.myShare > 0 then
      Pts.AddSelf("honor", -math.min(b.myShare, Pts.SELF_MAX), "bounty", { note = b.target, bid = b.id, flag = "dup" })
      U.Print(L.PVP_BNT_LOST:format(b.target, G.Display(from)))
      b.myShare = nil
    end
  elseif b.state == "off" and b.by == me and b.refunded and not b.gb then
    -- collected before my withdrawal / refund reached the killer: take the refund back
    Pts.AddSelf("honor", -b.amt, "bounty", { note = b.target, bid = b.id, flag = "late" })
    b.refunded = nil
  end
  if b.addBack and b.adds and b.adds[me] then
    Pts.AddSelf("honor", -b.adds[me], "bounty", { note = b.target, bid = b.id, flag = "late" })
    b.addBack = nil
  end
  pending[b.id] = nil
  local mine = false
  for _, k in ipairs(ws) do if k == me then mine = true end end
  b.state = "done"; b.w = ws[1]; b.ws = ws; b.wts = ts
  if not mine then b.myShare = nil end
  remember(b)
  local names = {}
  for _, k in ipairs(ws) do names[#names + 1] = G.Display(k) end
  local who = table.concat(names, ", ")
  if b.by == me or (b.adds and b.adds[me]) then
    if core.Notices then
      core.Notices.Add({ key = "bnty:" .. b.id, group = L.TAB_PVP, text = L.PVP_BNT_PAID:format(who, b.target, P.BountyTotal(b)), view = "pvp" })
    end
  end
  fire("PVP_BOUNTY_WON", b, false)
  refreshUI()
end)

C.On("FOEKILL", function(data, from)
  if type(data.n) ~= "string" then return end
  noteFoeKill(data.n:sub(1, 48), from, tonumber(data.t) or U.Now())
  core.Schedule("gemBntyFoes", 3, checkPublicEnemies)
end)

---------------------------------------------------------------------------
-- Target notice: an enemy with a bounty in the target frame
---------------------------------------------------------------------------
local told = {}
local function onTarget()
  if not U.UnitTrue(UnitExists, "target") or not U.UnitTrue(UnitIsPlayer, "target")
    or not U.UnitTrue(UnitIsEnemy, "player", "target") then return end
  local ok, n, r = pcall(UnitName, "target")
  if not ok or not n or (issecretvalue and (issecretvalue(n) or (r and issecretvalue(r)))) then return end
  local name = (r and r ~= "") and (n .. " " .. r) or n
  local sum, cnt = P.BountyOn(name)
  if sum <= 0 and r and r ~= "" then sum, cnt = P.BountyOn(n) end
  if sum <= 0 then return end
  local k = tkey(name)
  if told[k] and GetTime() - told[k] < 300 then return end
  told[k] = GetTime()
  P.Notice(L.PVP_BNT_TARGET:format(name, sum, cnt))
end

---------------------------------------------------------------------------
-- Login, HELLO, pruning
---------------------------------------------------------------------------
-- Bounties older than the posters (0.8) carry no race, class or place. Fill
-- them from enemies seen before (kept across sessions) and from blood debts
-- (zone and time of the kill). Sightings fill the rest as they come.
local function enrich(b)
  if b.i and b.i.rf and b.i.z then return end
  local seen = P.seenEnemies[b.tk or tkey(b.target or "")]
  if seen then mergeInfo(b, seen) end
  if not (b.i and b.i.z) then
    local best
    for _, d in pairs(P.Char().debts or {}) do
      if type(d) == "table" and d.name and tkey(d.name) == b.tk and d.zone and (not best or (d.t or 0) > (best.t or 0)) then best = d end
    end
    if best then mergeInfo(b, { z = best.zone, st = best.t }) end
  end
end
P.EnrichBounty = enrich

local function load()
  local c, now = store(), U.Now()
  -- the cache of seen enemies lives in the saved variables (account wide)
  if core.db then
    core.db.pvpSeen = core.db.pvpSeen or {}
    for k, v in pairs(P.seenEnemies) do core.db.pvpSeen[k] = v end
    P.seenEnemies = core.db.pvpSeen
    for k, v in pairs(P.seenEnemies) do
      if type(v) ~= "table" or now - (v.st or 0) > 30 * DAY then P.seenEnemies[k] = nil end
    end
  end
  for id, b in pairs(c) do
    if now - (b.ts or 0) > 30 * DAY then c[id] = nil
    else
      b.adds = b.adds or {}
      if not P.bounties[id] then P.bounties[id] = b end
    end
  end
  for _, b in pairs(P.bounties) do if P.BountyState(b) == "open" then pcall(enrich, b) end end
end

-- the poster sends his open bounties again, contributors their part, the
-- hunters their claims of the last 14 days
local function resend()
  if core.demo or not C.CanSend() then return end
  local me, now = G.MyKey(), U.Now()
  for _, b in pairs(P.bounties) do
    if b.by == me and P.BountyState(b) == "open" then sendBounty(b)
    elseif b.by == me and b.state == "off" and now - (b.offts or 0) < 14 * DAY then send("BNTYDEL", { id = b.id, exp = b.expired and 1 or nil })
    end
    if P.BountyState(b) == "open" and b.adds and b.adds[me] then send("BNTYADD", { id = b.id, a = b.adds[me] }) end
    if b.state == "done" and b.myShare and now - (b.wts or 0) < 14 * DAY then
      if b.by ~= me then sendBounty(b) end   -- ignored unless sent by the poster; harmless
      send("BNTYWON", { id = b.id, w = b.w, ws = table.concat(b.ws or { b.w }, ","), ts = b.wts })
    end
  end
end
P.ResendBounties = resend

C.On("HELLO", function() core.Schedule("gemBountyResend", 6 + math.random() * 10, resend) end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:SetScript("OnEvent", function(_, ev)
  if ev == "PLAYER_LOGIN" then
    load()
    if C_Timer and C_Timer.NewTicker then
      C_Timer.NewTicker(300, function()
        core.SafeCall("pvpBountyExpire", expire)
        core.SafeCall("pvpBountyRecap", recapTick)
        core.SafeCall("pvpBountyFoes", checkPublicEnemies)
      end)
    end
    core.Schedule("gemBountyExpire", 20, expire)
    core.Schedule("gemBountyFoes", 40, checkPublicEnemies)
  else
    core.SafeCall("pvpBountyTarget", onTarget)
  end
end)

---------------------------------------------------------------------------
-- Slash: /gem bounty <name> <GP> | /gem kopfgeld ...
---------------------------------------------------------------------------
-- /gem bounty test [clear]: five local test bounties (never sent, nothing booked)
local TESTS = {
  { "Valandris", 25, "Human", 2, "Paladin", "PALADIN", 58, "Arathihochland", "Zuflucht", 1, 0.2, true },
  { "Brogni Steinbart", 40, "Dwarf", 2, "Jäger", "HUNTER", 60, "Brennende Steppe", nil, 2, 2 },
  { "Lunarisa", 15, "NightElf", 3, "Druidin", "DRUID", 55, "Eschental", "Astranaar", 3, 5 },
  { "Fizzlebolt", 60, "Gnome", 2, "Hexenmeister", "WARLOCK", 60, "Tanaris", "Gadgetzan", 1, 26, false, 1 },
  { "Nathiko Frostpfeil", 8, "Skyborne", 3, "Magierin", "MAGE", 47, "Brachland", "Wegkreuz", 2, 50 },
}
local function testBounties(clear)
  local c = store()
  for id, b in pairs(P.bounties) do
    if b.test then P.bounties[id] = nil; c[id] = nil end
  end
  if clear then U.Print("GEM: test bounties removed."); refreshUI(); return end
  local now, me = U.Now(), G.MyKey()
  for n, t in ipairs(TESTS) do
    local b = { id = "test" .. n, test = true, by = n == 3 and me or ("Testjäger" .. n), target = t[1], tk = tkey(t[1]),
      amt = t[2], ts = now - (n - 1) * 9 * 3600, state = "open", gb = t[12], adds = {},
      i = { r = t[3] == "NightElf" and "Nachtelf" or (t[3] == "Skyborne" and "Himmelsgeborene") or (t[3] == "Gnome" and "Gnom")
              or (t[3] == "Dwarf" and "Zwerg") or "Mensch",
            rf = t[3], sx = t[4], cl = t[5], cf = t[6], lv = t[7], z = t[8], sz = t[9],
            st = now - math.floor(t[11] * 3600), ly = t[10] == 1 and P.Layer() or ("x-" .. n) } }
    if n == 2 then b.adds["Testhelfer"] = 15 end
    P.bounties[b.id] = b
    c[b.id] = b
  end
  U.Print("GEM: 5 test bounties added (/gem bounty test clear removes them).")
  refreshUI()
  P.ShowWanted(P.bounties.test1, "new", { sound = false })
end

local function bountyCmd(rest)
  rest = tostring(rest or ""):match("^%s*(.-)%s*$")
  if rest == "test" or rest == "test clear" then return testBounties(rest == "test clear") end
  local name, amt = rest:match("^(.-)%s+(%d+)$")
  if not name or name == "" then
    U.Print(L.PVP_BNT_USAGE)
    for _, b in ipairs(P.OpenBounties()) do
      U.Print(("  %s: %d · %s"):format(b.target, P.BountyTotal(b), G.Display(b.by)))
    end
    return
  end
  P.PostBounty(name, amt)
end
core.SlashExt.bounty = bountyCmd
core.SlashExt.kopfgeld = bountyCmd
