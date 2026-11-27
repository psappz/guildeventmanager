local ADDON, ns = ...
-- Guild ranks (0.9): GEM works out which members should get another guild
-- rank and why; the guild master or an officer (manager rank from the
-- settings) applies it with one click.
--
-- * twink:    recognised twinks (ns.Persons) -> rank "Twink"
-- * inactive: a person whose characters were all offline inactiveDays -> rank "Inaktiv"
-- * back:     unlinked twinks / members active again get their old rank back
--
-- Addons may not change ranks (SetGuildMemberRank is forbidden in Forever).
-- GEM builds the slash commands (/gpromote, /gdemote: one step each) for a
-- protected macro button (max. 255 characters); each click runs the next batch.
-- Old ranks are kept in s.rankPrev[key] (rank index, 0 = guild master).
local U, G = ns.U, ns.Guild
local R = {}
ns.Ranks = R

local function store()
  local s = ns.Store()
  if not s then return nil end
  s.rankPrev = s.rankPrev or {}
  if s.twinkPrev then   -- first 0.9 builds
    for k, v in pairs(s.twinkPrev) do if s.rankPrev[k] == nil then s.rankPrev[k] = v end end
    s.twinkPrev = nil
  end
  return s
end

local function prof() return ns.Profile and ns.Profile.Get() or {} end

function R.RankByName(name)
  local want = tostring(name or ""):lower()
  if want == "" then return nil end
  for i, n in pairs(G.rankNames) do
    if type(n) == "string" and n:lower() == want then return i end
  end
end

local function first(base)
  local t = ns.Struct and ns.Struct.Ranks(base) or {}
  return t[1]
end
function R.TwinkRank() return first("twink") end
function R.OfficerTwinkRank() return first("otwink") end
function R.InactiveRank()
  if prof().inactiveOn == false then return nil end
  return first("inactive")
end

-- Bank characters: ranks, inactivity and purge leave them alone
function R.IsBank(key)
  if not key then return false end
  local b = prof().bankChars
  if type(b) == "table" and b[key] == true then return true end
  local r = G.roster[key]
  return r and ns.Struct and ns.Struct.HasRank("bank", r.rankIndex) or false
end

function R.SetBank(key, on)
  if not key or not R.Allowed() then return end
  ns.Profile.Update(function(pr)
    pr.bankChars = pr.bankChars or {}
    pr.bankChars[key] = on and true or nil
  end)
end

-- Days the person (all characters in the roster, bank characters aside) has been offline
function R.PersonOffDays(key)
  local P = ns.Persons
  local min
  for _, k in ipairs(P and P.Chars(key) or { key }) do
    local r = G.roster[k]
    if r and not R.IsBank(k) then
      local d = r.online and 0 or (r.offDays or 0)
      if not min or d < min then min = d end
    end
  end
  return min or 0
end

-- Rank of the main, as it will be (an inactive main counts with his old rank)
local function mainRank(main, s, ina)
  local r = G.roster[main]
  if not r then return nil end
  if ina and r.rankIndex == ina and s.rankPrev[main] then return s.rankPrev[main] end
  return r.rankIndex
end

-- Persons offline purgeDays: all their characters (bank characters aside)
-- { { key, off, main } }; only ranks below the own one, never the guild master
function R.PurgePlan()
  local out = {}
  local pr = prof()
  local my = G.roster[G.MyKey() or ""]
  if pr.purgeOn == false or not my or not my.rankIndex then return out end
  local days = tonumber(pr.purgeDays) or 90
  local P = ns.Persons
  for key, r in pairs(G.roster) do
    if not R.IsBank(key) and r.rankIndex and r.rankIndex > my.rankIndex and r.rankIndex ~= 0 then
      local main = P and P.MainOf(key) or key
      local off = R.PersonOffDays(main)
      if off >= days then out[#out + 1] = { key = key, off = off, main = main } end
    end
  end
  table.sort(out, function(a, b)
    local ma, mb = G.Display(a.main), G.Display(b.main)
    if ma ~= mb then return ma < mb end
    if (a.key == a.main) ~= (b.key == b.main) then return a.key == a.main end
    return G.Display(a.key) < G.Display(b.key)
  end)
  return out
end

-- The rank changes GEM suggests: { { key, from, to, why = "twink"|"otwink"|"inactive"|"back" } }
-- * a person offline inactiveDays: main and twinks -> inactive
-- * twinks of an active person -> "Twink", or "Offizierstwink" if the main leads the guild
-- * otherwise: who has the twink/inactive rank and an old rank on record gets it back
function R.Plan()
  local out = {}
  local s = store()
  local my = G.roster[G.MyKey() or ""]
  if not s or not my or not my.rankIndex then return out end
  local P = ns.Persons
  local pr = prof()
  local tw, otw, ina = R.TwinkRank(), R.OfficerTwinkRank(), R.InactiveRank()
  local days = tonumber(pr.inactiveDays) or 30
  local purge = {}
  for _, x in ipairs(R.PurgePlan()) do purge[x.key] = true end
  for key, r in pairs(G.roster) do
    local cur = r.rankIndex
    -- only ranks below the own one can be changed; never the guild master or a bank character
    if cur and cur > my.rankIndex and cur ~= 0 and not R.IsBank(key) and not purge[key] then
      local main = P and P.MainOf(key) or key
      local want, why
      if ina and R.PersonOffDays(main) >= days then
        want, why = ina, "inactive"
      elseif main ~= key and (tw or otw) then
        local mr = mainRank(main, s, ina)
        if otw and mr and G.IsLeadRank(mr) then want, why = otw, "otwink"
        else want, why = tw or otw, "twink" end
      elseif (ns.Struct.HasRank("twink", cur) or ns.Struct.HasRank("otwink", cur) or ns.Struct.HasRank("inactive", cur)) and s.rankPrev[key] then
        want, why = s.rankPrev[key], "back"
      end
      local S = ns.Struct
      if (why == "twink" and S.HasRank("twink", cur)) or (why == "otwink" and S.HasRank("otwink", cur))
        or (why == "inactive" and S.HasRank("inactive", cur)) then want = nil end
      if want and want ~= cur and want > my.rankIndex then
        out[#out + 1] = { key = key, from = cur, to = want, why = why }
      end
    end
  end
  local order = { back = 1, otwink = 2, twink = 3, inactive = 4 }
  table.sort(out, function(a, b)
    if a.why ~= b.why then return order[a.why] < order[b.why] end
    return G.Display(a.key) < G.Display(b.key)
  end)
  return out
end

-- /gremove for the next batch of the purge list
function R.PurgeMacro()
  local lines, covered, len = {}, {}, 0
  for _, x in ipairs(R.PurgePlan()) do
    local r = G.roster[x.key]
    if r and r.name then
      local cmd = "/gremove " .. r.name
      if len + #cmd + 1 > 255 then break end
      lines[#lines + 1] = cmd
      len = len + #cmd + 1
      covered[#covered + 1] = x
    end
  end
  return table.concat(lines, "\n"), covered
end

function R.PurgeClicked(covered)
  local s = store()
  if s then for _, x in ipairs(covered or {}) do s.rankPrev[x.key] = nil end end
  ns.Schedule("gemRankRoster", 2, G.RequestRoster)
end

-- Macro text for the next batch and the entries it covers
function R.Macro()
  local lines, covered, len = {}, {}, 0
  for _, x in ipairs(R.Plan()) do
    local r = G.roster[x.key]
    if r and r.name then
      local cmd = (x.to > x.from and "/gdemote " or "/gpromote ") .. r.name
      local steps = math.abs(x.to - x.from)
      local add = (#cmd + 1) * steps
      if len + add > 255 then break end
      for _ = 1, steps do lines[#lines + 1] = cmd end
      len = len + add
      covered[#covered + 1] = x
    end
  end
  return table.concat(lines, "\n"), covered
end

-- Opens the guild window with the member selected; the guild master picks the
-- rank there (Blizzard's own list may set ranks, addons may not). Only C
-- functions and the plain toggle are used, so Blizzard's frame is not tainted.
function R.OpenInGuild(key)
  local r = G.roster[key]
  if not r or not r.idx or (InCombatLockdown and InCombatLockdown()) then return false end
  -- remember the old rank (the change itself happens in Blizzard's window)
  local s = store()
  local plan = R.Plan()
  for _, x in ipairs(plan) do
    if x.key == key and s then
      if x.why == "back" then s.rankPrev[key] = nil elseif s.rankPrev[key] == nil then s.rankPrev[key] = x.from end
    end
  end
  if SetGuildRosterSelection then pcall(SetGuildRosterSelection, r.idx) end
  local shown = (GuildFrame and GuildFrame:IsShown()) or (CommunitiesFrame and CommunitiesFrame:IsShown())
  if not shown then
    if ToggleGuildFrame then pcall(ToggleGuildFrame)
    elseif ToggleFriendsFrame then pcall(ToggleFriendsFrame, 3) end
  end
  ns.Schedule("gemRankRoster", 3, G.RequestRoster)
  -- our window stands back (strata LOW) while Blizzard's guild window is open
  local win = ns.UI and ns.UI.Frame and ns.UI.Frame()
  if win then
    win:SetFrameStrata("LOW")
    local function guildOpen()
      for _, n in ipairs({ "GuildFrame", "CommunitiesFrame", "FriendsFrame", "GuildMemberDetailFrame" }) do
        local f = _G[n]
        if f and f.IsShown and f:IsShown() then return true end
      end
      return false
    end
    local seen = false
    local t = 0
    if not R.watch then R.watch = CreateFrame("Frame") end
    R.watch:SetScript("OnUpdate", function(self, dt)
      t = t + dt
      if t < 0.3 then return end
      t = 0
      local open = guildOpen()
      if open then seen = true end
      -- back to the front once the guild window was closed (or never came within 3 s)
      if (seen and not open) or (not seen and (self.waited or 0) > 3) then
        win:SetFrameStrata("HIGH")
        self:SetScript("OnUpdate", nil)
        self.waited = nil
      elseif not seen then self.waited = (self.waited or 0) + 0.3 end
    end)
  end
  return true
end

-- Right before the button runs the macro: remember the old ranks
function R.Clicked(covered)
  local s = store()
  if not s then return end
  for _, x in ipairs(covered or {}) do
    if x.why == "back" then s.rankPrev[x.key] = nil
    elseif s.rankPrev[x.key] == nil then s.rankPrev[x.key] = x.from end
  end
  ns.Schedule("gemRankRoster", 2, G.RequestRoster)
end

function R.Allowed()
  return G.IsLead() and not ns.demo
end

-- Reminder for the leadership, once per session
local reminded
local function remind()
  if reminded or not R.Allowed() or prof().rankRemind == false then return end
  ns.Schedule("gemRankRemind", 10, function()
    local plan, purge = R.Plan(), R.PurgePlan()
    if (#plan > 0 or #purge > 0) and not reminded then
      reminded = true
      if #plan > 0 then U.Print((ns.L.RK_REMIND or "%d"):format(#plan)) end
      if #purge > 0 then U.Print((ns.L.RK_PURGE_REMIND or "%d"):format(#purge)) end
    end
  end)
end
ns.On("PERSONS_CHANGED", remind)
ns.On("ROSTER_READ", remind)
