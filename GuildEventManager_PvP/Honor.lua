local ADDON, P = ...
-- Mak'gora and oaths: deeds that the addon cannot see itself, so other guild
-- members confirm them as witnesses.
--
-- Mak'gora: a formal duel between two guild members with a stake. The
-- challenged one accepts, they duel, a witness (not one of the two) confirms
-- the winner. The winner's client books the honor. Once a week per pair.
--
-- Oath: a member swears to do something (small / great / mighty oath). Two
-- witnesses confirm that it was fulfilled; then the swearer gets the honor.
--
-- Every client only books its own honor (core rule). Witness confirmations are
-- kept and sent again when the other one comes online, so nobody has to be
-- online at the same time as the swearer.
local core = P.core
if not core then return end
local U, G, T, C, Pts, W = core.U, core.Guild, core.Theme, core.Comm, core.Points, core.W
local L = P.L

local HOUR, DAY = 3600, 86400
P.maks = {}    -- id -> { id, a, b, stake, ts, state = open|fight|done|off, wit = { [witness] = winner }, winner }
P.oaths = {}   -- id -> { id, by, text, lvl, amt, ts, wit = { [witness] = true }, state = open|done|off }

local function store()
  local c = P.Char()
  c.maks = c.maks or {}
  c.oaths = c.oaths or {}
  c.wit = c.wit or {}      -- my confirmations: id -> winner key (Mak'gora) or true (oath)
  return c
end

local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

local function remember(kind, x)
  if core.demo then return end
  store()[kind][x.id] = x
end

-- keep the own lists short: nothing older than 30 days
local function prune()
  if core.demo then return end
  local c, now = store(), U.Now()
  for _, kind in ipairs({ "maks", "oaths" }) do
    for id, x in pairs(c[kind]) do if now - (x.ts or 0) > 30 * DAY then c[kind][id] = nil end end
  end
end

---------------------------------------------------------------------------
-- Mak'gora
---------------------------------------------------------------------------
P.MAK_OPEN = 30 * 60     -- a challenge waits 30 minutes for an answer
P.MAK_FIGHT = 2 * HOUR   -- an accepted Mak'gora waits 2 hours for its witnesses

local function pairKey(a, b) if a < b then return a .. "|" .. b end return b .. "|" .. a end

-- Already a Mak'gora of these two in the last 7 days?
function P.MakgoraThisWeek(a, b)
  local key, since = pairKey(a, b), U.Now() - 7 * DAY
  for _, e in ipairs(Pts.Entries(function(e) return e.why == "makgora" and not e.reverted and (e.ts or 0) >= since end)) do
    if e.note and pairKey(e.who, e.note) == key then return true end
  end
  for _, m in pairs(P.maks) do
    local st = P.MakState(m)
    if (st == "fight" or st == "done") and m.ts >= since and pairKey(m.a, m.b) == key then return true end
  end
  return false
end

function P.MakState(m)
  local now = U.Now()
  if m.state == "open" and now - m.ts > P.MAK_OPEN then return "off" end
  if m.state == "fight" and now - (m.acc or m.ts) > P.MAK_FIGHT then return "off" end
  return m.state
end

-- Mak'goras that are still open or being fought, newest first
function P.ActiveMakgoras()
  local list = {}
  for _, m in pairs(P.maks) do
    local st = P.MakState(m)
    if st == "open" or st == "fight" then list[#list + 1] = m end
  end
  table.sort(list, function(x, y) return x.ts > y.ts end)
  return list
end

local function sendMak(m)
  C.Send("MAKG", { m = { id = m.id, a = m.a, b = m.b, stake = m.stake, ts = m.ts, state = m.state, acc = m.acc } })
end

function P.Challenge(name, stake)
  if not C.CanSend() then U.Print(core.L.NOT_ACTIVE); return end
  local me = G.MyKey()
  local b = name and G.Resolve(name)
  if not b then U.Print(L.PVP_MAK_NOMEMBER:format(name or "?")); return end
  if b == me then U.Print(L.PVP_MAK_SELF); return end
  for _, m in ipairs(P.ActiveMakgoras()) do
    if m.a == me or m.b == me then U.Print(L.PVP_MAK_BUSY); return end
  end
  if P.MakgoraThisWeek(me, b) then U.Print(L.PVP_MAK_WEEK:format(G.Display(b))); return end
  local m = { id = U.NewId(), a = me, b = b, stake = (stake and stake ~= "") and stake:sub(1, 60) or nil,
    ts = U.Now(), state = "open", wit = {} }
  P.maks[m.id] = m
  remember("maks", m)
  sendMak(m)
  U.Print(L.PVP_MAK_SENT:format(G.Display(b)))
  if core.UI then core.UI.Refresh() end
end

local function myOpenChallenge()
  local me = G.MyKey()
  for _, m in ipairs(P.ActiveMakgoras()) do
    if m.b == me and P.MakState(m) == "open" then return m end
  end
end

function P.Answer(id, ok)
  local m = id and P.maks[id] or myOpenChallenge()
  if not m or m.b ~= G.MyKey() or P.MakState(m) ~= "open" then U.Print(L.PVP_MAK_NONE); return end
  if ok and P.MakgoraThisWeek(m.a, m.b) then ok = false; U.Print(L.PVP_MAK_WEEK:format(G.Display(m.a))) end
  m.state = ok and "fight" or "off"
  m.acc = U.Now()
  remember("maks", m)
  C.Send("MAKGANS", { id = m.id, ok = ok and 1 or 0 })
  if ok then U.Print(L.PVP_MAK_ACCEPTED_ME:format(G.Display(m.a))) end
  if core.UI then core.UI.Refresh() end
end

-- the winner's client books the honor once enough witnesses agree
local function checkMakWin(m)
  if m.booked or P.MakState(m) ~= "fight" then return end
  local me = G.MyKey()
  if m.a ~= me and m.b ~= me then return end
  local need = math.max(1, tonumber(P.Rules().makgoraWitnesses) or 1)
  local votes, names = 0, {}
  for wkey, winner in pairs(m.wit or {}) do
    if winner == me and wkey ~= m.a and wkey ~= m.b then votes = votes + 1; names[#names + 1] = wkey end
  end
  if votes < need then return end
  m.booked = true
  m.state = "done"
  m.winner = me
  local loser = (m.a == me) and m.b or m.a
  remember("maks", m)
  local e = Pts.AddSelf("honor", tonumber(P.Rules().makgora) or 10, "makgora",
    { note = loser, ch = m.a, mk = m.id, wit = table.concat(names, ","), stake = m.stake })
  C.Send("MAKGDONE", { id = m.id, w = me })
  if e then
    P.Notice(L.PVP_MAK_WON:format(G.Display(loser), e.amt))
    core.Fire("PVP_MAKGORA", m, me, loser)
  end
  if core.UI then core.UI.Refresh() end
end

-- A witness confirms the winner
function P.Witness(id, winner)
  local me = G.MyKey()
  local m = id and P.maks[id]
  if not m then
    -- /gem witness <name>: the one running Mak'gora that this name fights in
    local key = winner and G.Resolve(winner)
    for _, x in ipairs(P.ActiveMakgoras()) do
      if key and P.MakState(x) == "fight" and (x.a == key or x.b == key) then m = x end
    end
    winner = key
  end
  if not m or P.MakState(m) ~= "fight" then U.Print(L.PVP_MAK_NONE); return end
  if me == m.a or me == m.b then U.Print(L.PVP_MAK_OWN); return end
  if winner ~= m.a and winner ~= m.b then U.Print(L.PVP_MAK_NONE); return end
  m.wit = m.wit or {}
  m.wit[me] = winner
  store().wit[m.id] = winner
  C.Send("MAKGWIT", { id = m.id, w = winner })
  U.Print(L.PVP_MAK_WITNESSED:format(G.Display(winner)))
  if core.UI then core.UI.Refresh() end
end

C.On("MAKG", function(data, from)
  local d = data.m
  if type(d) ~= "table" or not d.id or not d.b or d.a ~= from then return end
  if not G.Resolve(d.b) and not core.demo then return end
  local m = P.maks[d.id]
  local fresh = not m
  if not m then
    m = { id = d.id, a = from, b = d.b, stake = type(d.stake) == "string" and d.stake:sub(1, 60) or nil,
      ts = math.min(U.Now(), tonumber(d.ts) or U.Now()), wit = {} }
    m.state = d.state == "fight" and "fight" or "open"
    m.acc = tonumber(d.acc)
    P.maks[m.id] = m
  end
  local me = G.MyKey()
  if fresh and P.MakState(m) == "open" then
    if m.b == me then
      P.PlaySignal()
      P.Notice(L.PVP_MAK_CHALLENGED:format(G.Display(m.a)) .. (m.stake and (" " .. L.PVP_MAK_STAKE:format(m.stake)) or ""))
      if W and W.Dialog then
        W.Dialog({ text = L.PVP_MAK_DIALOG:format(G.Display(m.a), m.stake or L.PVP_MAK_NOSTAKE),
          accept = L.PVP_MAK_ACCEPT, cancel = L.PVP_MAK_DECLINE, onAccept = function() P.Answer(m.id, true) end })
      end
    else
      U.Print(L.PVP_MAK_ANNOUNCE:format(G.Display(m.a), G.Display(m.b)) .. (m.stake and (" " .. L.PVP_MAK_STAKE:format(m.stake)) or ""))
    end
  end
  -- I confirmed this one before (the duelist was offline): send it again
  local mine = store().wit[m.id]
  if mine and me ~= m.a and me ~= m.b then
    core.Schedule("gemMakWit" .. m.id, 2 + math.random() * 4, function() C.Send("MAKGWIT", { id = m.id, w = mine }) end)
  end
  core.Fire("PVP_MAKGORA_NEW", m)
  if core.UI then core.UI.Refresh() end
end)

C.On("MAKGANS", function(data, from)
  local m = data.id and P.maks[data.id]
  if not m or m.b ~= from or m.state ~= "open" then return end
  m.state = tonumber(data.ok) == 1 and "fight" or "off"
  m.acc = U.Now()
  if m.a == G.MyKey() then
    remember("maks", m)
    U.Print(m.state == "fight" and L.PVP_MAK_ACCEPTED:format(G.Display(m.b)) or L.PVP_MAK_DECLINED:format(G.Display(m.b)))
  elseif m.state == "fight" then
    U.Print(L.PVP_MAK_WITNESS_CALL:format(G.Display(m.a), G.Display(m.b)))
  end
  if core.UI then core.UI.Refresh() end
end)

C.On("MAKGWIT", function(data, from)
  local m = data.id and P.maks[data.id]
  if not m or from == m.a or from == m.b then return end
  if data.w ~= m.a and data.w ~= m.b then return end
  m.wit = m.wit or {}
  m.wit[from] = data.w
  checkMakWin(m)
  if core.UI then core.UI.Refresh() end
end)

C.On("MAKGDONE", function(data, from)
  local m = data.id and P.maks[data.id]
  if not m or data.w ~= from or (from ~= m.a and from ~= m.b) then return end
  m.state = "done"; m.winner = from
  if core.UI then core.UI.Refresh() end
end)

-- The game's duel result in the system chat helps the witness: it asks to confirm.
-- (May be unreadable on this client; then the witness confirms in the tab.)
local duelPatterns
local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local pat = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  local order = {}
  -- "%2$s" (the $ is escaped above: "%2%$s") and plain "%s"
  pat = pat:gsub("%%(%d)%%%$s", function(i) order[#order + 1] = tonumber(i); return "(.+)" end)
  pat = pat:gsub("%%s", function() order[#order + 1] = #order + 1; return "(.+)" end)
  return "^" .. pat .. "$", order
end

local function onSystem(msg)
  if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
  if not duelPatterns then
    duelPatterns = {}
    -- KNOCKOUT: "%2$s has defeated %1$s" (2 = winner); RETREAT: "%2$s has fled from %1$s" (1 = winner)
    for g, win in pairs({ DUEL_WINNER_KNOCKOUT = 2, DUEL_WINNER_RETREAT = 1 }) do
      local pat, order = toPattern(_G[g])
      if pat then duelPatterns[#duelPatterns + 1] = { pat, order, win } end
    end
    if #duelPatterns == 0 then duelPatterns = nil; return end
  end
  for _, dp in ipairs(duelPatterns) do
    local caps = { msg:match(dp[1]) }
    if #caps >= 2 then
      local byIndex = {}
      for k, idx in ipairs(dp[2]) do byIndex[idx] = caps[k] end
      local wi = dp[3]
      local winner, loser = G.Resolve(byIndex[wi] or ""), G.Resolve(byIndex[3 - wi] or "")
      local me = G.MyKey()
      for _, m in ipairs(P.ActiveMakgoras()) do
        if P.MakState(m) == "fight" and winner and loser and pairKey(m.a, m.b) == pairKey(winner, loser)
          and me ~= m.a and me ~= m.b and not (m.wit and m.wit[me]) then
          W.Dialog({ text = L.PVP_MAK_SEEN:format(G.Display(winner), G.Display(loser)), accept = L.PVP_MAK_CONFIRM,
            onAccept = function() P.Witness(m.id, winner) end })
        end
      end
      return
    end
  end
end

---------------------------------------------------------------------------
-- Oaths
---------------------------------------------------------------------------
P.OATH_MAX = 3   -- open oaths per member

function P.OathHonor(lvl) return tonumber(P.Rules()["oath" .. (lvl or 1)]) or 10 end

function P.OathState(o)
  if o.state == "open" and U.Now() - o.ts > (tonumber(P.Rules().oathDays) or 14) * DAY then return "off" end
  return o.state
end

function P.OpenOaths()
  local list = {}
  for _, o in pairs(P.oaths) do if P.OathState(o) == "open" then list[#list + 1] = o end end
  table.sort(list, function(x, y) return x.ts > y.ts end)
  return list
end

local function sendOath(o)
  C.Send("OATH", { o = { id = o.id, text = o.text, lvl = o.lvl, ts = o.ts } })
end

function P.Swear(lvl, text)
  if not C.CanSend() then U.Print(core.L.NOT_ACTIVE); return end
  lvl = math.max(1, math.min(3, tonumber(lvl) or 1))
  text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if text == "" then U.Print(L.PVP_OATH_USAGE); return end
  local me, n = G.MyKey(), 0
  for _, o in ipairs(P.OpenOaths()) do if o.by == me then n = n + 1 end end
  if n >= P.OATH_MAX then U.Print(L.PVP_OATH_MAX:format(P.OATH_MAX)); return end
  local o = { id = U.NewId(), by = me, text = text:sub(1, 80), lvl = lvl, ts = U.Now(), wit = {}, state = "open" }
  P.oaths[o.id] = o
  remember("oaths", o)
  sendOath(o)
  U.Print(L.PVP_OATH_SWORN:format(L["PVP_OATH_LVL" .. lvl], P.OathHonor(lvl), tonumber(P.Rules().oathWitnesses) or 2))
  if core.UI then core.UI.Refresh() end
end

function P.Withdraw(id)
  local o = P.oaths[id]
  if not o or o.by ~= G.MyKey() or o.state ~= "open" then return end
  o.state = "off"
  remember("oaths", o)
  C.Send("OATHDEL", { id = id })
  if core.UI then core.UI.Refresh() end
end

local function checkOath(o)
  if o.by ~= G.MyKey() or P.OathState(o) ~= "open" then return end
  local need = math.max(1, tonumber(P.Rules().oathWitnesses) or 2)
  local names = {}
  for wkey in pairs(o.wit or {}) do if wkey ~= o.by then names[#names + 1] = wkey end end
  if #names < need then return end
  o.state = "done"
  remember("oaths", o)
  local e = Pts.AddSelf("honor", P.OathHonor(o.lvl), "oath", { note = o.text:sub(1, 40), flag = "lvl" .. o.lvl, wit = table.concat(names, ",") })
  C.Send("OATHDONE", { id = o.id })
  if e then
    P.Notice(L.PVP_OATH_DONE:format(o.text, e.amt))
    core.Fire("PVP_OATH_FULFILLED", o)
  end
  if core.UI then core.UI.Refresh() end
end

function P.ConfirmOath(id)
  local o = P.oaths[id]
  local me = G.MyKey()
  if not o or P.OathState(o) ~= "open" then return end
  if o.by == me then U.Print(L.PVP_OATH_OWN); return end
  o.wit = o.wit or {}
  o.wit[me] = true
  store().wit[o.id] = true
  C.Send("OATHWIT", { id = o.id })
  U.Print(L.PVP_OATH_WITNESSED:format(G.Display(o.by)))
  if core.UI then core.UI.Refresh() end
end

C.On("OATH", function(data, from)
  local d = data.o
  if type(d) ~= "table" or not d.id or type(d.text) ~= "string" then return end
  local o = P.oaths[d.id]
  if not o then
    o = { id = d.id, by = from, text = d.text:sub(1, 80), lvl = math.max(1, math.min(3, tonumber(d.lvl) or 1)),
      ts = tonumber(d.ts) or U.Now(), wit = {}, state = "open" }
    if o.ts > U.Now() then o.ts = U.Now() end
    P.oaths[o.id] = o
    if P.OathState(o) == "open" then
      U.Print(L.PVP_OATH_ANNOUNCE:format(G.Display(from), L["PVP_OATH_LVL" .. o.lvl], o.text))
    end
  end
  if store().wit[o.id] and from ~= G.MyKey() then
    core.Schedule("gemOathWit" .. o.id, 2 + math.random() * 4, function() C.Send("OATHWIT", { id = o.id }) end)
  end
  if core.UI then core.UI.Refresh() end
end)

C.On("OATHWIT", function(data, from)
  local o = data.id and P.oaths[data.id]
  if not o or from == o.by then return end
  o.wit = o.wit or {}
  o.wit[from] = true
  checkOath(o)
  if core.UI then core.UI.Refresh() end
end)

C.On("OATHDEL", function(data, from)
  local o = data.id and P.oaths[data.id]
  if o and o.by == from then o.state = "off"; if core.UI then core.UI.Refresh() end end
end)

C.On("OATHDONE", function(data, from)
  local o = data.id and P.oaths[data.id]
  if o and o.by == from then o.state = "done"; if core.UI then core.UI.Refresh() end end
end)

---------------------------------------------------------------------------
-- Login and HELLO: load the own lists, send open ones again
---------------------------------------------------------------------------
local function load()
  prune()
  local c = store()
  for id, m in pairs(c.maks) do if not P.maks[id] then P.maks[id] = m end end
  for id, o in pairs(c.oaths) do if not P.oaths[id] then P.oaths[id] = o end end
end

local function resend()
  if core.demo or not C.CanSend() then return end
  local me = G.MyKey()
  for _, m in ipairs(P.ActiveMakgoras()) do if m.a == me then sendMak(m) end end
  for _, o in ipairs(P.OpenOaths()) do if o.by == me then sendOath(o) end end
end
P.ResendHonor = resend

C.On("HELLO", function() core.Schedule("gemHonorResend", 4 + math.random() * 10, resend) end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:SetScript("OnEvent", function(_, event, msg)
  if event == "PLAYER_LOGIN" then
    core.Schedule("gemHonorLoad", 5, function() load(); core.Schedule("gemHonorResend", 20, resend) end)
  elseif event == "CHAT_MSG_SYSTEM" then
    core.SafeCall("pvp duel", onSystem, msg)
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- /gem makgora <name> [stake] · /gem makgora accept|decline · /gem witness <winner>
core.SlashExt.makgora = function(rest)
  local a, b = (rest or ""):match("^(%S*)%s*(.-)$")
  local w = (a or ""):lower()
  if w == "accept" or w == "annehmen" or w == "ja" or w == "yes" then P.Answer(nil, true)
  elseif w == "decline" or w == "ablehnen" or w == "nein" or w == "no" then P.Answer(nil, false)
  elseif a and a ~= "" then P.Challenge(a, b)
  else U.Print(L.PVP_MAK_USAGE) end
end
core.SlashExt["mak'gora"] = core.SlashExt.makgora
core.SlashExt.witness = function(rest) P.Witness(nil, (rest or ""):match("^%s*(%S+)")) end
core.SlashExt.zeuge = core.SlashExt.witness
-- /gem oath [1|2|3] <text>
core.SlashExt.oath = function(rest)
  local lvl, text = (rest or ""):match("^([123])%s+(.+)$")
  P.Swear(lvl or 1, text or rest)
end
core.SlashExt.schwur = core.SlashExt.oath
