-- GuildEventManager example PvP extension: "Duels"
-- Shows how a PvP module plugs into the PvP module of GuildEventManager:
-- an own PvP event type, a deed that gives guild honor (with a rule and a
-- daily cap the event managers can change), an achievement and a callback.
local ADDON, ns = ...
local API = GuildEventManagerAPI
if not (API and API.PvP) then return end         -- needs the core and its PvP module
local PvP = API.PvP

local ID = "duels"

local ok = API.RegisterModule({
  id = ID, nameKey = "DUEL_MODULE", version = 1,
  requires = { api = 1, pvp = 1 },
  locales = {
    enUS = {
      DUEL_MODULE = "Duels",
      DUEL_TYPE = "Duel tournament",
      DUEL_TYPE_DESC = "Members duel each other in rounds. Every duel won against a guild member gives guild honor.",
      DUEL_GOAL_1 = "Group stage finished",
      DUEL_GOAL_2 = "Final fought",
      DUEL_DEED = "won a duel against %s",
      DUEL_RULE = "Honor per duel",
      DUEL_CAP = "Duel honor per day",
      DUEL_ACH = "Duelist",
      DUEL_ACH_DESC = "Win %d duels against guild members",
    },
    deDE = {
      DUEL_MODULE = "Duelle",
      DUEL_TYPE = "Duellturnier",
      DUEL_TYPE_DESC = "Mitglieder treten in Runden gegeneinander an. Jedes gewonnene Duell gegen ein Gildenmitglied bringt Gildenehre.",
      DUEL_GOAL_1 = "Gruppenphase beendet",
      DUEL_GOAL_2 = "Finale ausgetragen",
      DUEL_DEED = "gewann ein Duell gegen %s",
      DUEL_RULE = "Ehre je Duell",
      DUEL_CAP = "Duell-Ehre pro Tag",
      DUEL_ACH = "Duellant",
      DUEL_ACH_DESC = "%d Duelle gegen Gildenmitglieder gewinnen",
    },
  },
  eventTypes = {
    { id = "duel_tournament", nameKey = "DUEL_TYPE", descKey = "DUEL_TYPE_DESC", kind = "short", group = "none",
      icon = "Interface\\Icons\\Ability_Dualwield", goalKeys = { "DUEL_GOAL_1", "DUEL_GOAL_2" } },
  },
  -- achievements count ledger entries: why = the deed id
  achievements = {
    { id = "duelist", nameKey = "DUEL_ACH", descKey = "DUEL_ACH_DESC", stat = "why", why = "duel_win", n = 10, pts = 25,
      scope = "season", icon = "Interface\\Icons\\INV_Sword_27" },
  },
})
if not ok then return end
local L = API.L

-- The deed: appears in the honor roll ("won a duel against X") and adds two
-- rules to the honor rules form of the PvP tab (honor per duel, daily cap).
PvP.RegisterDeed("duel_win", { labelKey = "DUEL_DEED", honor = 5, ruleLabelKey = "DUEL_RULE",
  dailyCap = 25, capLabelKey = "DUEL_CAP" })

-- Detect won duels from the system message "%1$s has defeated %2$s in a duel"
local function duelPattern()
  local fmt = _G.DUEL_WINNER_KNOCKOUT or _G.DUEL_WINNER_RETREAT
  if type(fmt) ~= "string" then return nil end
  local pat = fmt:gsub("%%%d?%$?s", "\001"):gsub("%p", "%%%0"):gsub("\001", "(.+)")
  return "^" .. pat .. "$"
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:SetScript("OnEvent", function(_, _, msg)
  local pat = duelPattern()
  if not pat or type(msg) ~= "string" then return end
  local winner, loser = msg:match(pat)
  if not winner then return end
  -- only duels between two guild members, reported by the winner
  if API.MemberKey(winner) == API.PlayerKey() and API.IsGuildMember(loser) then
    API.SafeCall("duelWin", PvP.ReportDeed, "duel_win", { note = loser })
  end
end)

-- React to the PvP module: e.g. a blood debt redeemed during a tournament
PvP.On("DEBT_PAID", function(debt, cold)
  -- your code
end)
