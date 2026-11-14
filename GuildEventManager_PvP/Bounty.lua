local ADDON, P = ...
-- Bounties: a member puts honor on the head of an enemy player. Whoever of the
-- guild kills that player first gets the honor; it moves from the one who set
-- the bounty to the one who collected it.
--
-- Core rule: every client books only its own honor. So the honor is paid in
-- advance: the poster books a minus for himself when he sets the bounty
-- (Pts.SELF_NEG). The killer books the plus when his client sees the kill.
-- Expired or withdrawn bounties: the poster books the honor back.
--
-- Two members claiming the same bounty (both online, same moment): the earlier
-- claim wins, the later one books its plus back. A claim that arrives after the
-- poster withdrew or got his honor back undoes that refund on the poster's side.
local core = P.core
if not core then return end
local U, G, C, Pts = core.U, core.Guild, core.Comm, core.Points
local L = P.L

local DAY = 86400
local GRACE = DAY        -- the poster waits a day after expiry before booking back (late claims)
P.bounties = {}          -- id -> { id, by, target, tk, amt, ts, state = open|done|off, w, wts, offts, refunded }

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

local function days() return math.max(1, tonumber(P.Rules().bountyDays) or 7) end

-- smallest bounty: at least 5 above the honor of a normal kill; largest: 50
P.BOUNTY_CAP = 50
function P.BountyLimits()
  local r = P.Rules()
  local floor = (tonumber(r.kill) or 3) + 5
  local min = math.max(floor, tonumber(r.bountyMin) or floor)
  local max = math.min(P.BOUNTY_CAP, tonumber(r.bountyMax) or P.BOUNTY_CAP)
  if max < min then max = min end
  return min, math.min(max, P.BOUNTY_CAP)
end

-- a bounty only pays when the name is sure to be the own kill: the honor line,
-- or the enemy died in my target. A nameplate that died near me can be somebody
-- else's kill, so it does not count (the normal kill honor still does).
local SURE = { ["honor line"] = true, ["dead target"] = true, ["seen dying target"] = true }
P.BOUNTY_SOURCES = SURE

function P.BountyState(b)
  if b.state == "open" and U.Now() - (b.ts or 0) > days() * DAY then return "expired" end
  return b.state
end

-- open bounties, highest first
function P.OpenBounties()
  local res = {}
  for _, b in pairs(P.bounties) do if P.BountyState(b) == "open" then res[#res + 1] = b end end
  table.sort(res, function(x, y) if x.amt ~= y.amt then return x.amt > y.amt end return (x.ts or 0) < (y.ts or 0) end)
  return res
end

-- collected bounties, newest first
function P.WonBounties()
  local res = {}
  for _, b in pairs(P.bounties) do if b.state == "done" then res[#res + 1] = b end end
  table.sort(res, function(x, y) return (x.wts or 0) > (y.wts or 0) end)
  return res
end

-- sum of open bounties on a name (for the target notice and the UI)
function P.BountyOn(name)
  local k, sum, n = tkey(name), 0, 0
  for _, b in ipairs(P.OpenBounties()) do if b.tk == k then sum = sum + b.amt; n = n + 1 end end
  return sum, n
end

local function myHonor()
  local t = Pts.Totals("season")[G.MyKey()]
  return t and t.pots.honor or 0
end
P.MyHonorBalance = myHonor

local function send(kind, data) if not core.demo then C.Send(kind, data) end end
local function sendBounty(b)
  send("BNTY", { b = { id = b.id, by = b.by, target = b.target, amt = b.amt, ts = b.ts } })
end

---------------------------------------------------------------------------
-- Setting and withdrawing
---------------------------------------------------------------------------
function P.PostBounty(name, amt)
  if not C.CanSend() then U.Print(core.L.NOT_ACTIVE); return end
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  amt = math.floor(tonumber(amt) or 0)
  local r = P.Rules()
  local min, max = P.BountyLimits()
  if name == "" then U.Print(L.PVP_BNT_NONAME); return end
  if G.Resolve(name) then U.Print(L.PVP_BNT_GUILD:format(name)); return end
  if amt < min or amt > max then U.Print(L.PVP_BNT_RANGE:format(min, max)); return end
  local me, open = G.MyKey(), 0
  for _, b in ipairs(P.OpenBounties()) do if b.by == me then open = open + 1 end end
  local maxOpen = tonumber(r.bountyOpen) or 3
  if maxOpen > 0 and open >= maxOpen then U.Print(L.PVP_BNT_MAXOPEN:format(maxOpen)); return end
  if myHonor() < amt then U.Print(L.PVP_BNT_POOR:format(myHonor())); return end
  local b = { id = U.NewId(), by = me, target = name, tk = tkey(name), amt = amt, ts = U.Now(), state = "open" }
  local e = Pts.AddSelf("honor", -amt, "bounty", { note = name, bid = b.id, flag = "set" })
  if not e then return end
  P.bounties[b.id] = b
  remember(b)
  sendBounty(b)
  U.Print(L.PVP_BNT_SET:format(amt, name, days()))
  core.Fire("PVP_BOUNTY_NEW", b)
  if core.UI and core.UI.Refresh then core.UI.Refresh() end
  return b
end

local function refund(b, why)
  if b.refunded then return end
  local e = Pts.AddSelf("honor", b.amt, "bounty", { note = b.target, bid = b.id, flag = why })
  if e then b.refunded = true end
end

function P.CancelBounty(id)
  local b = P.bounties[id]
  local me = G.MyKey()
  if not b or b.by ~= me or b.state ~= "open" then return end
  b.state = "off"; b.offts = U.Now()
  refund(b, "back")
  remember(b)
  send("BNTYDEL", { id = id })
  U.Print(L.PVP_BNT_CANCELLED:format(b.target, b.amt))
  if core.UI and core.UI.Refresh then core.UI.Refresh() end
end

-- the poster books expired bounties back (after a grace day for late claims)
local function expire()
  local me, now = G.MyKey(), U.Now()
  for _, b in pairs(P.bounties) do
    if b.by == me and b.state == "open" and now - b.ts > days() * DAY + GRACE and C.CanSend() then
      b.state = "off"; b.offts = now
      refund(b, "exp")
      remember(b)
      send("BNTYDEL", { id = b.id, exp = 1 })
      U.Print(L.PVP_BNT_EXPIRED:format(b.target, b.amt))
    end
  end
end

---------------------------------------------------------------------------
-- Collecting
---------------------------------------------------------------------------
local function claim(b)
  local me, now = G.MyKey(), U.Now()
  local e = Pts.AddSelf("honor", b.amt, "bounty", { note = b.target, bid = b.id, flag = "won", ch = b.by })
  if not e then return end
  b.state = "done"; b.w = me; b.wts = now; b.mine = e.id
  remember(b)
  send("BNTYWON", { id = b.id, w = me, ts = now })
  P.PlaySignal()
  P.Notice(L.PVP_BNT_WON:format(b.amt, b.target, G.Display(b.by)))
  core.Fire("PVP_BOUNTY_WON", b)
end

core.On("PVP_KILL", function(name, kind, source)
  if not name then return end
  if source and not SURE[source] then
    for _, b in ipairs(P.OpenBounties()) do
      if b.tk == tkey(name) and b.by ~= G.MyKey() then U.Print(L.PVP_BNT_UNSURE:format(name)); break end
    end
    return
  end
  local k, me = tkey(name), G.MyKey()
  for _, b in ipairs(P.OpenBounties()) do
    if b.tk == k and b.by ~= me then claim(b) end
  end
  if core.UI and core.UI.Refresh then core.UI.Refresh() end
end)

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
C.On("BNTY", function(data, from)
  local d = type(data.b) == "table" and data.b
  if not d or type(d.id) ~= "string" or d.by ~= from or type(d.target) ~= "string" then return end
  local amt = tonumber(d.amt)
  if not amt or amt < 1 or amt > P.BOUNTY_CAP then return end
  local b = P.bounties[d.id]
  if b then return end
  b = { id = d.id, by = from, target = d.target:sub(1, 48), tk = tkey(d.target), amt = math.floor(amt),
        ts = tonumber(d.ts) or U.Now(), state = "open" }
  P.bounties[b.id] = b
  remember(b)
  if P.BountyState(b) == "open" and U.Now() - b.ts < 600 then
    U.Print(L.PVP_BNT_ANNOUNCE:format(G.Display(from), b.amt, b.target))
  end
  if core.UI and core.UI.Refresh then core.UI.Refresh() end
end)

C.On("BNTYDEL", function(data, from)
  local b = type(data.id) == "string" and P.bounties[data.id]
  if not b or b.by ~= from then return end
  if b.state == "open" then b.state = "off"; b.offts = U.Now(); remember(b) end
  if core.UI and core.UI.Refresh then core.UI.Refresh() end
end)

C.On("BNTYWON", function(data, from)
  local b = type(data.id) == "string" and P.bounties[data.id]
  local ts = tonumber(data.ts)
  if not b or data.w ~= from or not ts or from == b.by then return end
  if ts - b.ts > days() * DAY + 60 then return end          -- killed after it ran out
  local me = G.MyKey()
  if b.state == "done" then
    if b.w == from then return end
    -- two claims: the earlier wins (same second: the smaller name)
    if b.wts < ts or (b.wts == ts and b.w < from) then return end
    if b.w == me and b.mine then
      Pts.AddSelf("honor", -b.amt, "bounty", { note = b.target, bid = b.id, flag = "dup" })
      U.Print(L.PVP_BNT_LOST:format(b.target, G.Display(from)))
    end
  elseif b.state == "off" and b.by == me and b.refunded then
    -- collected before my withdrawal / refund reached the killer: take the refund back
    Pts.AddSelf("honor", -b.amt, "bounty", { note = b.target, bid = b.id, flag = "late" })
    b.refunded = nil
  end
  b.state = "done"; b.w = from; b.wts = ts; b.mine = nil
  remember(b)
  if b.by == me then
    P.PlaySignal()
    P.Notice(L.PVP_BNT_PAID:format(G.Display(from), b.target, b.amt))
  else
    U.Print(L.PVP_BNT_COLLECTED:format(G.Display(from), b.amt, b.target))
  end
  core.Fire("PVP_BOUNTY_WON", b)
  if core.UI and core.UI.Refresh then core.UI.Refresh() end
end)

---------------------------------------------------------------------------
-- Target notice: an enemy with a bounty in the target frame
---------------------------------------------------------------------------
local told = {}
local function onTarget()
  if not (UnitExists and UnitIsPlayer and UnitIsEnemy) then return end
  if not UnitExists("target") or not UnitIsPlayer("target") or not UnitIsEnemy("player", "target") then return end
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
local function load()
  local c, now = store(), U.Now()
  for id, b in pairs(c) do
    if now - (b.ts or 0) > 30 * DAY then c[id] = nil
    elseif not P.bounties[id] then P.bounties[id] = b end
  end
end

-- the poster sends his open bounties again, the collector his claims of the last 14 days
local function resend()
  if core.demo or not C.CanSend() then return end
  local me, now = G.MyKey(), U.Now()
  for _, b in pairs(P.bounties) do
    if b.by == me and P.BountyState(b) == "open" then sendBounty(b)
    elseif b.by == me and b.state == "off" and now - (b.offts or 0) < 14 * DAY then send("BNTYDEL", { id = b.id })
    elseif b.state == "done" and b.w == me and now - (b.wts or 0) < 14 * DAY then
      sendBounty(b)   -- the receiver may not know it yet; BNTY is ignored if he does
      send("BNTYWON", { id = b.id, w = me, ts = b.wts })
    end
  end
end
P.ResendBounties = resend

-- BNTY from someone else than the poster is ignored, so a collector's copy of
-- the bounty only helps receivers who already know it. That is fine: the honor
-- itself travels in the ledger anyway.

C.On("HELLO", function() core.Schedule("gemBountyResend", 6 + math.random() * 10, resend) end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:SetScript("OnEvent", function(_, ev)
  if ev == "PLAYER_LOGIN" then
    load()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(300, function() core.SafeCall("pvpBountyExpire", expire) end) end
    core.Schedule("gemBountyExpire", 20, expire)
  else
    core.SafeCall("pvpBountyTarget", onTarget)
  end
end)

---------------------------------------------------------------------------
-- Slash: /gem bounty <name> <honor> | /gem kopfgeld ...
---------------------------------------------------------------------------
local function bountyCmd(rest)
  rest = tostring(rest or ""):match("^%s*(.-)%s*$")
  local name, amt = rest:match("^(.-)%s+(%d+)$")
  if not name or name == "" then
    U.Print(L.PVP_BNT_USAGE)
    for _, b in ipairs(P.OpenBounties()) do
      U.Print(("  %s: %d · %s"):format(b.target, b.amt, G.Display(b.by)))
    end
    return
  end
  P.PostBounty(name, amt)
end
core.SlashExt.bounty = bountyCmd
core.SlashExt.kopfgeld = bountyCmd
