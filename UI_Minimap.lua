local ADDON, ns = ...
-- Minimap button (LibDBIcon) and Blizzard addon compartment.
local U, G, T = ns.U, ns.Guild, ns.Theme
local MM = {}
ns.Minimap = MM

local NAME = "GuildEventManager"
local ICON = "Interface\\AddOns\\GuildEventManager\\Media\\GuildEventManagerIcon"

function MM.StatusLines()
  local L = ns.L
  local lines = {}
  if not G.InGuild() then
    lines[#lines + 1] = { L.NO_GUILD_SHORT, 0.62, 0.71, 0.78 }
    return lines
  end
  if not G.IsActivated() then
    lines[#lines + 1] = { L.STATUS_INACTIVE, 0.94, 0.71, 0.35 }
    return lines
  end
  local running, planned, nextE = 0, 0, nil
  for _, e in ipairs(ns.Events.List()) do
    if e.status == "running" then running = running + 1
    elseif e.status == "planned" then
      planned = planned + 1
      if not nextE or (e.start or 0) < (nextE.start or 0) then nextE = e end
    end
  end
  lines[#lines + 1] = { L.STATUS_EVENTS:format(running, planned), 1, 1, 1 }
  if nextE then lines[#lines + 1] = { L.STATUS_NEXT:format(nextE.name, U.FormatTime(nextE.start)), 1, 0.82, 0 } end
  local b = ns.Points.Banner()
  lines[#lines + 1] = { L.BANNER_LEVEL:format(T.Word("BANNER"), b.level, L["TIER_" .. b.level]), 0.9, 0.73, 0.36 }
  local me = ns.Points.Totals("season")[G.MyKey()]
  lines[#lines + 1] = { L.STATUS_ME:format(me and math.floor(me.total) or 0), 0.56, 0.89, 0.62 }
  return lines
end

local function fillTooltip(tt)
  tt:AddLine("GuildEventManager", 0.83, 0.69, 0.22)
  for _, l in ipairs(MM.StatusLines()) do tt:AddLine(l[1], l[2], l[3], l[4], true) end
  tt:AddLine(" ")
  tt:AddLine(ns.L.MINIMAP_TIP, 0.62, 0.71, 0.78, true)
end

local function click(button)
  if button == "RightButton" then ns.UI.Toggle("banner")
  elseif button == "MiddleButton" then ns.UI.Toggle("settings")
  else ns.UI.Toggle("events") end
end

function MM.Create()
  if MM.created then return end
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (LDB and DBI) then return end
  MM.created = true
  local obj = LDB:NewDataObject(NAME, {
    type = "launcher", label = NAME, icon = ICON,
    OnClick = function(_, button) ns.SafeCall("minimapClick", click, button) end,
    OnTooltipShow = function(tt) ns.SafeCall("minimapTip", fillTooltip, tt) end,
  })
  local m = ns.db.minimap
  m.minimapPos = m.minimapPos or 215
  DBI:Register(NAME, obj, m)
  MM.icon = DBI
end

function MM.ToggleShown()
  if not MM.icon then return end
  local m = ns.db.minimap
  m.hide = not m.hide
  if m.hide then MM.icon:Hide(NAME); U.Print(ns.L.MINIMAP_HIDDEN)
  else MM.icon:Show(NAME); U.Print(ns.L.MINIMAP_SHOWN) end
end

function GuildEventManager_OnAddonCompartmentClick(_, button) ns.SafeCall("compartment", click, button) end
function GuildEventManager_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  ns.SafeCall("compartmentTip", fillTooltip, GameTooltip)
  GameTooltip:Show()
end
function GuildEventManager_OnAddonCompartmentLeave() GameTooltip:Hide() end
