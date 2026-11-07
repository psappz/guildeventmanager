local ADDON, ns = ...
-- Faction themes: Horde = Orc / Orgrimmar, Alliance = Human / Stormwind.
-- Same mechanics for both; only colours, crests, words and sounds differ.
local T = {}
ns.Theme = T

T.THEMES = {
  horde = {
    key = "horde",
    bg = { 0.10, 0.07, 0.055, 0.97 },
    panel = { 0.145, 0.10, 0.08, 1 },
    panel2 = { 0.185, 0.13, 0.105, 1 },
    border = { 0.55, 0.16, 0.11, 1 },
    line = { 0.42, 0.33, 0.27, 1 },
    title = { 0.90, 0.73, 0.36 },
    text = { 0.93, 0.89, 0.83 },
    muted = { 0.74, 0.68, 0.61 },
    accent = { 0.66, 0.19, 0.11, 1 },
    good = { 0.49, 0.78, 0.42 },
    tint = { 1, 0.62, 0.55 },
    glow = { 1, 0.35, 0.2 },
    crest = "Interface\\TargetingFrame\\UI-PVP-Horde",
    banner = { 0.49, 0.14, 0.09 },
  },
  alliance = {
    key = "alliance",
    bg = { 0.07, 0.10, 0.16, 0.97 },
    panel = { 0.92, 0.88, 0.78, 1 },
    panel2 = { 0.86, 0.81, 0.69, 1 },
    border = { 0.72, 0.54, 0.16, 1 },
    line = { 0.60, 0.54, 0.38, 1 },
    title = { 0.94, 0.84, 0.54 },
    text = { 0.11, 0.14, 0.20 },
    muted = { 0.30, 0.33, 0.40 },
    accent = { 0.14, 0.28, 0.49, 1 },
    good = { 0.18, 0.48, 0.23 },
    tint = { 0.75, 0.85, 1 },
    glow = { 0.45, 0.65, 1 },
    crest = "Interface\\TargetingFrame\\UI-PVP-Alliance",
    banner = { 0.14, 0.28, 0.49 },
  },
}

function T.Faction()
  if T.forced then return T.forced end
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return (f == "Alliance") and "alliance" or "horde"
end

function T.Current() return T.THEMES[T.Faction()] end

-- Faction words: the Horde says "clan", the Alliance "order". Keys live in the locale.
function T.Word(key)
  local L = ns.L
  if T.Faction() == "alliance" then return L["A_" .. key] end
  return L["H_" .. key]
end

function T.Hex(c)
  return string.format("ff%02x%02x%02x", (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255)
end
