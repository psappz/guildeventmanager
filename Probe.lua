local ADDON, ns = ...
-- /gem probe: what this client gives addons. WoW Forever runs a new engine
-- with Classic rules, so some things (talent groups, lockouts, waypoints,
-- protected buttons) are checked here instead of guessed. Modules add their
-- own checks with API.AddProbe. The result goes to the chat and into
-- /gem export.
local U = ns.U
local Pr = { checks = {} }
ns.Probe = Pr

-- fn() returns { { label, value }, ... }
function Pr.Add(id, fn)
  for _, c in ipairs(Pr.checks) do if c.id == id then c.fn = fn; return end end
  Pr.checks[#Pr.checks + 1] = { id = id, fn = fn }
end

local function has(v) return v ~= nil and "yes" or "no" end
local function try(fn, ...)
  local r = { pcall(fn, ...) }
  if not r[1] then return "error: " .. tostring(r[2]):sub(1, 60) end
  local out = {}
  for i = 2, math.min(#r, 8) do out[#out + 1] = ns.Export.Val(r[i]) end
  return #out > 0 and table.concat(out, ", ") or "(nothing)"
end
Pr.Has, Pr.Try = has, try

Pr.Add("core", function()
  local out = {}
  out[#out + 1] = { "engine", (GetBuildInfo and try(GetBuildInfo)) or "?" }
  out[#out + 1] = { "secret values", has(issecretvalue) }
  out[#out + 1] = { "guild roster class (col 11)", GetGuildRosterInfo and (function()
    local ok, _, _, _, _, _, _, _, _, _, _, class = pcall(GetGuildRosterInfo, 1)
    return ok and tostring(class) or "?"
  end)() or "no" }
  out[#out + 1] = { "invite (C_PartyInfo.InviteUnit / InviteUnit)", has(C_PartyInfo and C_PartyInfo.InviteUnit) .. " / " .. has(InviteUnit) }
  out[#out + 1] = { "convert to raid", has((C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid) }
  out[#out + 1] = { "SetRaidSubgroup / SwapRaidSubgroup", has(SetRaidSubgroup) .. " / " .. has(SwapRaidSubgroup) }
  out[#out + 1] = { "map waypoint (C_Map.SetUserWaypoint)", has(C_Map and C_Map.SetUserWaypoint and UiMapPoint) }
  out[#out + 1] = { "player position", (C_Map and C_Map.GetBestMapForUnit) and try(function()
    local m = C_Map.GetBestMapForUnit("player")
    local p = m and C_Map.GetPlayerMapPosition(m, "player")
    return m, p and p:GetXY()
  end) or "no" }
  out[#out + 1] = { "protected button (SecureActionButtonTemplate)", (function()
    local ok = pcall(CreateFrame, "Button", nil, UIParent, "SecureActionButtonTemplate")
    return ok and "yes" or "no"
  end)() }
  out[#out + 1] = { "paste box (characters kept)", (function()
    local ok, n = pcall(function()
      local eb = CreateFrame("EditBox", nil, UIParent)
      eb:SetMultiLine(true); eb:SetMaxLetters(0); eb:SetAutoFocus(false)
      eb:SetText(string.rep("x", 60000))
      local got = eb.GetNumLetters and eb:GetNumLetters() or #(eb:GetText() or "")
      eb:SetText(""); eb:Hide()
      return got
    end)
    return ok and tostring(n) .. " / 60000" or "?"
  end)() }
  out[#out + 1] = { "professions (fishing)", (GetProfessions and try(GetProfessions)) or (GetNumSkillLines and ("skill lines: " .. try(GetNumSkillLines))) or "no" }
  return out
end)

function Pr.Run()
  local lines = {}
  for _, c in ipairs(Pr.checks) do
    local ok, res = pcall(c.fn)
    if ok and type(res) == "table" then
      for _, x in ipairs(res) do lines[#lines + 1] = "[" .. c.id .. "] " .. tostring(x[1]) .. ": " .. tostring(x[2]) end
    else
      lines[#lines + 1] = "[" .. c.id .. "] error: " .. tostring(res)
    end
  end
  if ns.db then ns.db.probe = { at = date("%Y-%m-%d %H:%M"), lines = lines } end
  U.Print(ns.L.PROBE_HEAD)
  for _, l in ipairs(lines) do print("  " .. l) end
  return lines
end

ns.SlashExt.probe = function() Pr.Run() end

ns.Export.Add("Probe", function()
  local p = ns.db and ns.db.probe
  if not p then return { "not run yet (/gem probe)" } end
  local out = { "run at: " .. p.at }
  for _, l in ipairs(p.lines) do out[#out + 1] = l end
  return out
end)
