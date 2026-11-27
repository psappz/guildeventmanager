local ADDON, ns = ...
-- Notices behind the bell in the window header: new events, a duel that waits
-- for its witness, a new bounty, a raid line-up ... Kept per character for 7
-- days, at most 30. Modules add their own with API.AddNotice.
local U = ns.U
local N = {}
ns.Notices = N

local KEEP, MAX = 7 * 86400, 30

local function store()
  if not ns.db then return {} end
  ns.db.notices = ns.db.notices or {}
  return ns.db.notices
end

local function prune()
  local list, now = store(), U.Now()
  for i = #list, 1, -1 do
    if now - (list[i].at or 0) > KEEP then table.remove(list, i) end
  end
  while #list > MAX do table.remove(list, 1) end
end

-- n = { key, group, text, view = "events" | open = function, ev = event id }
-- key: one notice per key (a newer one replaces the older)
function N.Add(n)
  if type(n) ~= "table" or not n.text then return end
  local list = store()
  if n.key then
    for i = #list, 1, -1 do if list[i].key == n.key then table.remove(list, i) end end
  end
  list[#list + 1] = { key = n.key, group = n.group, text = n.text, view = n.view, ev = n.ev, mod = n.mod, at = n.at or U.Now(), read = false }
  if n.open then N.handlers = N.handlers or {}; N.handlers[n.key or n.text] = n.open end
  prune()
  ns.Fire("NOTICE", n)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function N.Remove(key)
  local list = store()
  for i = #list, 1, -1 do if list[i].key == key then table.remove(list, i) end end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- newest first
function N.List()
  prune()
  local out = {}
  local list = store()
  for i = #list, 1, -1 do out[#out + 1] = list[i] end
  return out
end

function N.Unread()
  local n = 0
  for _, x in ipairs(store()) do if not x.read then n = n + 1 end end
  return n
end

function N.MarkRead()
  for _, x in ipairs(store()) do x.read = true end
end

function N.Open(n)
  local fn = N.handlers and N.handlers[n.key or n.text]
  if fn then return ns.SafeCall("notice", fn) end
  if n.mod and ns.ModuleUI then return ns.ModuleUI.Show(n.mod) end   -- a new module of the guild
  if n.ev and ns.Events.Get(n.ev) and ns.UIEvents then
    ns.UI.Show("events")
    ns.UIEvents.OpenDetail(ns.Events.Get(n.ev))
    return
  end
  if n.view then ns.UI.Show(n.view) end
end
