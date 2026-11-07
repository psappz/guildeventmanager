local ADDON, ns = ...
-- Guild state: membership, roster, activation marker, rights.
-- The addon belongs to the guild the player is in right now. It stays silent
-- until the guild master has put the marker [GEM:...] into the guild info.
local U = ns.U
local G = {}
ns.Guild = G

G.MARKER_PATTERN = "%[GEM:(%d+):(%x+)%]"
G.roster = {}      -- key -> { name, rankName, rankIndex, online }
G.rankNames = {}
G.alias = {}       -- roster name without its last "-part" -> roster key   -- index (0 = guild master) -> name

-- One key for every spelling Forever uses: "Monaco Stenz", "Monaco-Stenz", "monaco stenz-Realm"
function G.Key(name)
  if not name then return nil end
  local k = tostring(name):lower():gsub("[%-%s]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return k
end

-- The roster gives names with the realm ("Monaco Stenz-Realm"), the client
-- without ("Monaco-Stenz"). Forever names may contain spaces or hyphens
-- themselves, so only a suffix that really is the realm gets removed.
local function squash(s) return (tostring(s or ""):lower():gsub("[%s%-']", "")) end
function G.StripRealm(name)
  if not name then return nil end
  name = tostring(name)
  local base, suffix = name:match("^(.+)%-([^%-]+)$")
  if base then
    local r1 = GetRealmName and GetRealmName()
    local r2 = GetNormalizedRealmName and GetNormalizedRealmName()
    local sx = squash(suffix)
    if (r1 and sx == squash(r1)) or (r2 and sx == squash(r2)) then return base end
  end
  return name
end

-- Resolves any spelling to the roster key
function G.Resolve(name)
  if not name then return nil end
  local k = G.Key(G.StripRealm(name))
  if G.roster[k] then return k end
  k = G.Key(name)
  if G.roster[k] then return k end
  -- other realm suffix (connected realms): drop the last part
  local noRealm = G.Key((tostring(name):gsub("%-[^%-]+$", "")))
  if G.roster[noRealm] then return noRealm end
  -- roster names with a realm suffix we could not recognise
  return G.alias[G.Key(G.StripRealm(name))] or G.alias[k]
end

function G.Display(key)
  local r = key and G.roster[key]
  return r and r.name or key or "?"
end

-- Forever returns first and last name separately: UnitName -> "Monaco", "Stenz".
-- The second value can also be a realm on other clients, so try every spelling.
function G.UnitKey(unit)
  local n, second = UnitName(unit)
  if not n then return nil end
  if second and second ~= "" then
    return G.Resolve(n .. " " .. second) or G.Resolve(n .. "-" .. second) or G.Resolve(n)
  end
  return G.Resolve(n)
end

function G.MyKey()
  local k = G.UnitKey("player")
  if k then return k end
  local n, second = UnitName("player")
  if second and second ~= "" then return G.Key(n .. " " .. second) end
  return G.Key(n)
end

function G.InGuild() return IsInGuild and IsInGuild() end

function G.Name()
  local n = GetGuildInfo and GetGuildInfo("player")
  return n
end

-- Storage key of the current guild (guild + realm), nil without guild
function G.StoreKey()
  local n = G.Name()
  if not n then return nil end
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
  return n .. "@" .. realm
end

function G.RequestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
  elseif GuildRoster then GuildRoster() end
end

function G.ReadRoster()
  wipe(G.roster)
  wipe(G.alias)
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  for i = 1, n do
    local name, rankName, rankIndex, level, _, _, _, _, online = GetGuildRosterInfo(i)
    if name then
      local display = G.StripRealm(name)
      local short = tostring(display):match("^(.+)%-[^%-]+$")
      if short then G.alias[G.Key(short)] = G.Key(display) end
      G.roster[G.Key(display)] = { name = display, rankName = rankName, rankIndex = rankIndex, level = level, online = online }
    end
  end
  wipe(G.rankNames)
  local nr = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
  for i = 1, nr do G.rankNames[i - 1] = GuildControlGetRankName(i) end
  return n
end

function G.Members()
  local list = {}
  for k, r in pairs(G.roster) do list[#list + 1] = k end
  table.sort(list, function(a, b) return G.Display(a) < G.Display(b) end)
  return list
end

-- Activation: the marker in the guild info (addons may read it, not write it).
-- The Forever client (Midnight engine) blocks GetGuildInfoText in combat and
-- reports ADDON_ACTION_BLOCKED. So the guild info is read only out of combat,
-- once per session (plus "check again" and a guild change), and the result is
-- kept per guild in the saved variables.
local function inCombat()
  return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

function G.ReadMarker()
  if inCombat() or not G.InGuild() then return false end
  local key = G.StoreKey()
  if not key or not ns.db then return false end
  local text = GetGuildInfoText and GetGuildInfoText() or ""
  local v, id = tostring(text):match(G.MARKER_PATTERN)
  ns.db.markers = ns.db.markers or {}
  ns.db.markers[key] = v and ("[GEM:" .. v .. ":" .. id .. "]") or false
  G.markerRead = key
  return true
end

function G.Marker()
  local key = G.StoreKey()
  if not key or not ns.db then return nil end
  if G.markerRead ~= key then G.ReadMarker() end
  local m = ns.db.markers and ns.db.markers[key]
  return m or nil
end

function G.IsActivated() return G.InGuild() and G.Marker() ~= nil end

function G.IsLeader() return IsGuildLeader and IsGuildLeader() or false end

function G.RankOf(key)
  local r = key and G.roster[key]
  return r and r.rankIndex
end

-- Guild event manager: the guild master, plus the rank set in the profile
-- (and, if chosen, every higher rank).
function G.IsManager(key)
  key = key or G.MyKey()
  if key == G.MyKey() and G.IsLeader() then return true end
  local rank = G.RankOf(key)
  if rank == nil then return false end
  if rank == 0 then return true end
  local p = ns.Profile and ns.Profile.Get()
  local mr = p and p.managerRank
  if mr == nil then return false end
  if rank == mr then return true end
  return p.managerHigher and rank < mr or false
end

-- New marker for the guild master to paste (random check value)
function G.NewMarker()
  return string.format("[GEM:1:%04x]", math.random(0, 0xffff))
end
