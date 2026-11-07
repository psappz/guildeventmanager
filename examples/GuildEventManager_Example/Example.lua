-- GuildEventManager example module: "Scavenger hunt"
-- Copy this folder, rename it (folder, .toc, module id) and build your own event module.
-- Only GuildEventManagerAPI is used; see docs/MODULES.md for every function.
local ADDON, ns = ...
local API = GuildEventManagerAPI
if not API or API.version < 1 then return end   -- core missing or too old

local ID = "hunt"                                -- module id: letters, digits, _

-- 1. Register: strings, event type, own point pot, achievement, rules
local ok = API.RegisterModule({
  id = ID, nameKey = "HUNT_MODULE", version = 1,
  requires = { api = 1 },
  locales = {
    enUS = {
      HUNT_MODULE = "Scavenger hunt",
      HUNT_TYPE = "Scavenger hunt",
      HUNT_TYPE_DESC = "The leader hides clues across the world. Whoever finds an item reports it with /gem found <item>.",
      HUNT_POT = "Finds",
      HUNT_GOAL_1 = "First clue found",
      HUNT_ACH = "Treasure Hunter",
      HUNT_ACH_DESC = "Find %d items in scavenger hunts",
      HUNT_TAB = "Hunt",
      HUNT_FOUND = "%s found: %s",
      HUNT_NONE = "Nothing found yet.",
      HUNT_NOT_RUNNING = "No scavenger hunt is running.",
    },
    deDE = {
      HUNT_MODULE = "Schnitzeljagd",
      HUNT_TYPE = "Schnitzeljagd",
      HUNT_TYPE_DESC = "Die Leitung versteckt Hinweise in der Welt. Wer einen Gegenstand findet, meldet ihn mit /gem found <Gegenstand>.",
      HUNT_POT = "Funde",
      HUNT_GOAL_1 = "Erster Hinweis gefunden",
      HUNT_ACH = "Schatzsucher",
      HUNT_ACH_DESC = "Bei Schnitzeljagden %d Gegenstände finden",
      HUNT_TAB = "Jagd",
      HUNT_FOUND = "%s hat gefunden: %s",
      HUNT_NONE = "Noch nichts gefunden.",
      HUNT_NOT_RUNNING = "Es läuft keine Schnitzeljagd.",
    },
  },
  eventTypes = {
    { id = "hunt", nameKey = "HUNT_TYPE", descKey = "HUNT_TYPE_DESC", kind = "short", group = "none",
      icon = "Interface\\Icons\\INV_Misc_Map_01", goalKeys = { "HUNT_GOAL_1" } },
  },
  pots = { { id = "finds", nameKey = "HUNT_POT" } },
  achievements = {
    { id = "hunter", nameKey = "HUNT_ACH", descKey = "HUNT_ACH_DESC", stat = "why", why = "hunt_find", n = 10, pts = 25,
      scope = "forever", icon = "Interface\\Icons\\INV_Misc_Spyglass_02" },
  },
  rules = { pointsPerFind = 5 },
})
if not ok then return end
local L = API.L

-- 2. Own command: /gem found <item>  -> own points in the module pot, message to the guild
local function runningHunt()
  for _, e in ipairs(API.GetEvents(function(e) return e.type == "hunt" and e.status == "running" end)) do return e end
end

API.AddCommand("found", function(item)
  local e = runningHunt()
  if not e then API.Print(L.HUNT_NOT_RUNNING); return end
  local rules = API.GetRules(ID)
  API.ReportOwn("finds", rules.pointsPerFind, "hunt_find", { note = item, ev = e.id })
  API.Send(ID, "FOUND", { item = item })
end)

-- 3. Guild messages of this module (only from guild members, only when activated)
local finds = {}   -- this session
API.Listen(ID, "FOUND", function(data, senderKey)
  table.insert(finds, 1, { who = senderKey, item = tostring(data.item or "?"), t = API.Now() })
  API.Print(L.HUNT_FOUND:format(API.DisplayName(senderKey), tostring(data.item)))
  API.Refresh()
end)

-- 4. Callbacks of the core
API.On("EVENT_STARTED", function(e)
  if e.type == "hunt" then wipe(finds); API.Refresh() end
end)

-- 5. Own tab
local W = API.Widgets
API.AddTab("hunt", {
  label = function() return L.HUNT_TAB end,
  build = function(panel)
    local head = API.Section(panel, L.HUNT_MODULE)
    head:SetPoint("TOPLEFT", 0, 0)
    panel.list = W.Text(panel, 12, "text")
    panel.list:SetPoint("TOPLEFT", 0, -28); panel.list:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.list:SetSpacing(4)
  end,
  refresh = function(panel)
    local lines = {}
    for i, f in ipairs(finds) do
      if i > 20 then break end
      lines[#lines + 1] = L.HUNT_FOUND:format(API.DisplayName(f.who), f.item)
    end
    panel.list:SetText(#lines > 0 and table.concat(lines, "\n") or L.HUNT_NONE)
  end,
})
