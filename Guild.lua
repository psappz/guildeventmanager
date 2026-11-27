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
  if ns.demo then return G.demoMe end
  local k = G.UnitKey("player")
  if k then return k end
  local n, second = UnitName("player")
  if second and second ~= "" then return G.Key(n .. " " .. second) end
  return G.Key(n)
end

-- The real guild state, also during the demo/preview (which shows the sample
-- guild "Neocortex"): activation, the guild master check and the help use these.
function G.RealInGuild() return IsInGuild and IsInGuild() or false end
function G.RealName() return GetGuildInfo and GetGuildInfo("player") end
function G.RealIsLeader() return IsGuildLeader and IsGuildLeader() or false end

function G.InGuild()
  if ns.demo then return true end
  return G.RealInGuild()
end

function G.Name()
  if ns.demo then return ns.demoGuild end
  local n = GetGuildInfo and GetGuildInfo("player")
  return n
end

-- Storage key of the current guild: "Name@EU" (see U.Scope), nil without guild;
-- real = the real guild even while the sample guild is shown
function G.StoreKey(real)
  local n = real and G.RealName() or G.Name()
  if not n or n == "" then return nil end
  local sc = U.Scope()
  return sc and (n .. "@" .. sc) or n
end

function G.RequestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
  elseif GuildRoster then GuildRoster() end
end

function G.ReadRoster()
  if ns.demo then return 0 end
  wipe(G.roster)
  wipe(G.alias)
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  for i = 1, n do
    local name, rankName, rankIndex, level, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
    if name then
      -- days offline (0 = online); used by the inactive rank (0.9)
      local off = 0
      if not online and GetGuildRosterLastOnline then
        local y, mo, d, h = GetGuildRosterLastOnline(i)
        off = (y or 0) * 365 + (mo or 0) * 30 + (d or 0) + (h or 0) / 24
      end
      local display = G.StripRealm(name)
      local short = tostring(display):match("^(.+)%-[^%-]+$")
      if short then G.alias[G.Key(short)] = G.Key(display) end
      G.roster[G.Key(display)] = { name = display, rankName = rankName, rankIndex = rankIndex, level = level, online = online, class = class, idx = i, offDays = off }
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
  if inCombat() or not G.RealInGuild() then return false end
  local key = G.StoreKey(true)
  if not key or not ns.db then return false end
  local text = GetGuildInfoText and GetGuildInfoText() or ""
  ns.db.markers = ns.db.markers or {}
  -- Right after login or a reconnect the game has not loaded the guild info yet
  -- and returns an empty text. That is "unknown", not "removed": keep what we
  -- knew and read again later, otherwise the guild looks deactivated for a while.
  if text == nil or text == "" or (issecretvalue and issecretvalue(text)) then return false end
  local v, id = tostring(text):match(G.MARKER_PATTERN)
  ns.db.markers[key] = v and ("[GEM:" .. v .. ":" .. id .. "]") or false
  G.markerRead = key
  G.markerAt = GetTime()
  return true
end

function G.Marker()
  local key = G.StoreKey(true)
  if not key or not ns.db then return nil end
  local m = ns.db.markers and ns.db.markers[key]
  -- read once per session; while there is no code, look again every minute so
  -- members who are online when the guild master pastes it switch on by themselves
  if G.markerRead ~= key or (not m and GetTime() - (G.markerAt or 0) > 60) then
    G.ReadMarker()
    m = ns.db.markers and ns.db.markers[key]
  end
  return m or nil
end

function G.IsActivated()
  -- the screenshot demo acts as an active guild; the preview for members of a
  -- guild that is not switched on yet keeps asking the real guild
  if ns.demo and not ns.preview then return true end
  if not G.RealInGuild() or not G.StoreKey(true) then
    -- during a reconnect or a loading screen the game briefly reports "no guild";
    -- stay active for two minutes before believing it
    if G.lastActive and GetTime() - G.lastActive < 120 then return true end
    return false
  end
  local on = G.Marker() ~= nil
  if on then G.lastActive = GetTime() end
  return on
end

function G.IsLeader()
  if ns.demo then return true end
  if G.viewRank and G.viewRank ~= 0 then return false end   -- "view as rank" (0.9)
  return IsGuildLeader and IsGuildLeader() or false
end

-- The real guild master, also while he looks at the interface as another rank
function G.IsRealLeader()
  return IsGuildLeader and IsGuildLeader() or false
end

function G.RankOf(key)
  local r = key and G.roster[key]
  -- "view as rank": the guild master sees the interface as this rank would
  if G.viewRank and r and key == G.MyKey() then return G.viewRank end
  return r and r.rankIndex
end

-- View the interface as another rank (guild master only; nil = own view).
-- Only the display changes: nothing is sent to the guild meanwhile.
function G.SetViewRank(idx)
  if idx ~= nil and not G.IsRealLeader() then return end
  G.viewRank = idx
  if ns.Persons then ns.Persons.Dirty() end
  if ns.UI and ns.UI.Frame and ns.UI.Frame() then ns.UI.Frame().navDirty = true end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
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

-- Guild leadership (0.9): the guild master and the ranks chosen in the settings
-- (Settings -> Guild ranks). All features that organise the guild (ranks,
-- inactive members, purge, twinks of members outside the guild) are theirs.
function G.IsLeadRank(rank)
  if rank == nil then return false end
  if rank == 0 then return true end
  if ns.Struct then return ns.Struct.HasRank("lead", rank) end
  local p = ns.Profile and ns.Profile.Get()
  for _, r in ipairs(p and p.leadRanks or {}) do if r == rank then return true end end
  return false
end

function G.IsLead(key)
  key = key or G.MyKey()
  if key == G.MyKey() and G.IsLeader() then return true end
  return G.IsLeadRank(G.RankOf(key))
end

-- New marker for the guild master to paste (random check value)
function G.NewMarker()
  return string.format("[GEM:1:%04x]", math.random(0, 0xffff))
end
