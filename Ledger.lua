local ADDON, ns = ...
-- How ledger entries read in the honor book: every module tells which entries
-- are its own and how they read (API.AddLedgerFormat). The core formats event
-- and achievement points.
local U, G = ns.U, ns.Guild
local Lg = { formats = {}, order = {} }
ns.Ledger = Lg

-- def = { label = fn -> tag text, match = fn(e) -> bool, text = fn(e) -> deed text }
function Lg.AddFormat(id, def)
  if type(def) ~= "table" or type(def.match) ~= "function" then return false end
  if not Lg.formats[id] then Lg.order[#Lg.order + 1] = id end
  Lg.formats[id] = def
  return true
end

-- which format an entry belongs to (modules first, core last)
function Lg.FormatOf(e)
  for i = #Lg.order, 1, -1 do
    local id = Lg.order[i]
    local f = Lg.formats[id]
    local ok, hit = pcall(f.match, e)
    if ok and hit then return id, f end
  end
end

-- id, label, color
function Lg.Tag(e)
  local id, f = Lg.FormatOf(e)
  local col = f and f.color or (ns.UI and ns.UI.COLORS and ns.UI.COLORS[id == "core" and "events" or id])
  return id, f and f.label and f.label() or id or "?", col
end

function Lg.Text(e)
  local _, f = Lg.FormatOf(e)
  if f and f.text then
    local ok, t = pcall(f.text, e)
    if ok and t then return t end
  end
  return ns.L.LEDGER_OTHER:format(e.why or "?")
end

-- Core: event points and achievement points
local WHY = { participate = "LEDGER_PARTICIPATE", lead = "LEDGER_LEAD", goal = "LEDGER_GOAL", manual = "LEDGER_MANUAL", revert = "LEDGER_REVERT" }
Lg.AddFormat("core", {
  label = function() return ns.L.LEDGER_TAG_EVENTS end,
  match = function(e) return e.pot == "event" or e.pot == "ach" end,
  text = function(e)
    local ev = e.ev and ns.Events.Get(e.ev)
    local name = ev and ev.name or e.note or "?"
    if e.pot == "ach" then return ns.L.LEDGER_ACH:format(e.note or "?") end
    local key = WHY[e.why] or "LEDGER_MANUAL"
    return ns.L[key]:format(name)
  end,
})
