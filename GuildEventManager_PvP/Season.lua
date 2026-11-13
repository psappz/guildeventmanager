local ADDON, P = ...
-- Season results, worked out from the ledger on every client (no messages):
-- * podium: places 1-3 of guild honor in a finished season
-- * champion: place 1, honor name for the following season
-- * unstoppable: the guild collects seasonGoal honor in one season; everyone
--   who added honor in that season earns it
-- Plus the Mak'gora streak achievements (challenger, unbeaten).
local core = P.core
if not core then return end
local Pts = core.Points

-- Seasons before the running one, newest first: { { start, stop } }
-- (uses the current season length of the guild profile)
function P.PastSeasons(since, maxN)
  local list = {}
  local stop = Pts.SeasonStart()
  for _ = 1, maxN or 36 do
    if stop <= (since or 0) then break end
    local st = Pts.SeasonStart(stop - 1)
    list[#list + 1] = { start = st, stop = stop }
    stop = st
  end
  return list
end

local function firstHonorTs(entries)
  for _, e in ipairs(entries) do if e.pot == "honor" then return e.ts or 0 end end
end

-- Honor per member in [start, stop), sorted: { { key, honor } }
function P.SeasonRanking(entries, start, stop)
  local sum = {}
  for _, e in ipairs(entries) do
    local ts = e.ts or 0
    if e.pot == "honor" and ts >= start and ts < stop then sum[e.who] = (sum[e.who] or 0) + (e.amt or 0) end
  end
  local list = {}
  for key, h in pairs(sum) do if h > 0 then list[#list + 1] = { key = key, honor = h } end end
  table.sort(list, function(a, b)
    if a.honor ~= b.honor then return a.honor > b.honor end
    return a.key < b.key
  end)
  return list
end

-- Results of all finished seasons (for the tab): { { start, stop, top = { {key, honor} x3 }, total } }
function P.SeasonResults(maxN)
  local s = core.Store()
  if not s then return {} end
  local entries = {}
  for _, e in pairs(s.ledger) do
    if not e.reverted and e.why ~= "revert" and (e.amt or 0) > 0 and e.pot == "honor" then entries[#entries + 1] = e end
  end
  table.sort(entries, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
  local out = {}
  local first = firstHonorTs(entries)
  if not first then return out end
  for _, season in ipairs(P.PastSeasons(first, maxN)) do
    local rank = P.SeasonRanking(entries, season.start, season.stop)
    local total = 0
    for _, r in ipairs(rank) do total = total + r.honor end
    out[#out + 1] = { start = season.start, stop = season.stop, top = { rank[1], rank[2], rank[3] }, total = total }
  end
  return out
end

-- Guild honor of the running season and the goal
function P.SeasonProgress()
  local since = Pts.SeasonStart()
  local sum = 0
  for _, e in ipairs(Pts.Entries(function(e) return e.pot == "honor" and (e.ts or 0) >= since end)) do
    sum = sum + (e.amt or 0)
  end
  return sum, tonumber(P.Rules().seasonGoal) or 5000
end

local function placed(entries, places)
  local out = {}
  local first = firstHonorTs(entries)
  if not first then return out end
  for _, season in ipairs(P.PastSeasons(first)) do
    local rank = P.SeasonRanking(entries, season.start, season.stop)
    for i = 1, places do
      if rank[i] then out[#out + 1] = { who = rank[i].key, ts = season.stop, note = i } end
    end
  end
  return out
end

function P.AchPodium(entries) return placed(entries, 3) end

function P.AchChampion(entries)
  local out = {}
  for _, w in ipairs(placed(entries, 1)) do out[#out + 1] = w end
  return out
end

-- Every season (also the running one): once the guild total crosses the goal,
-- everyone with honor in that season so far earns it; later contributors on their next entry.
function P.AchUnstoppable(entries)
  local goal = tonumber(P.Rules().seasonGoal) or 5000
  if goal <= 0 then return {} end
  local out = {}
  local season, sum, reached, got, contributors
  for _, e in ipairs(entries) do
    if e.pot == "honor" then
      local st = Pts.SeasonStart(e.ts or 0)
      if st ~= season then season, sum, reached, got, contributors = st, 0, false, {}, {} end
      sum = sum + (e.amt or 0)
      contributors[e.who] = true
      if not reached and sum >= goal then
        reached = true
        for who in pairs(contributors) do got[who] = true; out[#out + 1] = { who = who, ts = e.ts } end
      elseif reached and not got[e.who] then
        got[e.who] = true; out[#out + 1] = { who = e.who, ts = e.ts }
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Mak'gora streaks. A won Mak'gora: who = winner, note = loser, ch = challenger.
---------------------------------------------------------------------------
local function maks(entries)
  local list = {}
  for _, e in ipairs(entries) do if e.why == "makgora" then list[#list + 1] = e end end
  return list
end

-- Mak'goras fought as the challenger (won or lost)
function P.AchChallenger(entries, _, a)
  local count, out = {}, {}
  for _, e in ipairs(maks(entries)) do
    local ch = e.ch
    if ch and (ch == e.who or ch == e.note) then
      count[ch] = (count[ch] or 0) + 1
      if count[ch] == a.n then out[#out + 1] = { who = ch, ts = e.ts } end
    end
  end
  return out
end

-- n won Mak'goras in a row without a loss
function P.AchUnbeaten(entries, _, a)
  local streak, out = {}, {}
  for _, e in ipairs(maks(entries)) do
    streak[e.who] = (streak[e.who] or 0) + 1
    if e.note then streak[e.note] = 0 end
    if streak[e.who] == a.n then out[#out + 1] = { who = e.who, ts = e.ts } end
  end
  return out
end

local function sortedMaks()
  local list = Pts.Entries(function(e) return e.why == "makgora" and not e.reverted end)
  table.sort(list, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
  return list
end

function P.ProgChallenger(key)
  local n = 0
  for _, e in ipairs(sortedMaks()) do if e.ch == key and (e.who == key or e.note == key) then n = n + 1 end end
  return n
end

function P.ProgUnbeaten(key)
  local n = 0
  for _, e in ipairs(sortedMaks()) do
    if e.who == key then n = n + 1 elseif e.note == key then n = 0 end
  end
  return n
end

-- Results of the Mak'goras of a member: wins, losses
function P.MakgoraRecord(key)
  local w, l = 0, 0
  for _, e in ipairs(sortedMaks()) do
    if e.who == key then w = w + 1 elseif e.note == key then l = l + 1 end
  end
  return w, l
end


