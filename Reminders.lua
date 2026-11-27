local ADDON, ns = ...
-- Own reminders of an event type (API 7), e.g. 30 minutes before with a check
-- list. For members who said yes, tentative or late. A check list opens as a
-- small window to tick off and close; once closed it does not come back for
-- this date (also not after /reload). The core's 10-minute reminder stays.
local U, G = ns.U, ns.Guild
local E = ns.Events
local R = {}
ns.Reminders = R

local SIGNED = { ["in"] = true, tentative = true, late = true }

local function done()
  if not ns.char then return {} end
  ns.char.remDone = ns.char.remDone or {}
  return ns.char.remDone
end

-- list of { before, text, checklist = { texts } } of the event's type
function R.For(e)
  local t = e and ns.Modules.Type(e.type)
  local out = {}
  for _, r in ipairs(t and type(t.reminders) == "table" and t.reminders or {}) do
    local before = tonumber(r.before)
    if before and before > 0 and before <= 7 * 86400 then
      local items = {}
      for _, k in ipairs(type(r.checklist) == "table" and r.checklist or {}) do
        if #items < 8 then items[#items + 1] = ns.L[k] or tostring(k) end
      end
      out[#out + 1] = { before = before, text = r.text or (r.textKey and ns.L[r.textKey]) or nil, checklist = #items > 0 and items or nil }
    end
  end
  return out
end

function R.Tick()
  if ns.demo then return end
  local now = U.Now()
  local store = ns.Store()
  for _, e in pairs(store and store.events or {}) do
    if e.status == "planned" and (e.start or 0) > now then
      local s = E.Status(e)
      if s and SIGNED[s] then
        for i, r in ipairs(R.For(e)) do
          local key = e.id .. ":" .. i
          if not done()[key] and now >= e.start - r.before then
            R.Show(e, r, key)
            break
          end
        end
      end
    end
  end
  -- forget dates long gone
  for k, at in pairs(done()) do if type(at) == "number" and now - at > 30 * 86400 then done()[k] = nil end end
end

local showing
function R.Show(e, r, key)
  local W = ns.W
  local mins = math.max(1, math.ceil(((e.start or 0) - U.Now()) / 60))
  local head = ns.L.REMIND_IN:format(e.name, mins)
  if not r.checklist then
    done()[key] = U.Now()
    ns.Contest.Alert(head .. (r.text and (" – " .. r.text) or ""), { sound = true })
    return
  end
  if showing == key then return end
  showing = key
  U.Print(U.Color(U.GOLD, head))
  local win = ns.Float.Get("checklist", { title = "", width = 300, height = 200, strata = "HIGH", point = { "TOP", 0, -160 },
    onClose = function(w) if w.key then done()[w.key] = U.Now() end; showing = nil end })
  if not win.items then
    win.text = W.Text(win.content, 11, "text"); win.text:SetPoint("TOPLEFT", 0, 0); win.text:SetPoint("RIGHT", 0, 0)
    win.text:SetSpacing(2)
    win.items = W.Pool(win.content, function(parent) return W.Check(parent, "") end)
    win.ok = W.Button(win.content, ns.L.REMIND_DONE, true, 22); win.ok:SetWidth(120)
    win.ok:SetPoint("BOTTOMRIGHT", 0, 0)
    win.ok:SetScript("OnClick", function() win:Close() end)
  end
  win.key = key
  win:SetTitle(head)
  win.text:SetText(r.text or "")
  local y = (r.text and (win.text:GetStringHeight() + 8)) or 0
  for i, item in ipairs(r.checklist) do
    local c = win.items:Get(i)
    c.text:SetText(item); c:SetChecked(false)
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", 2, -y)
    y = y + 22
  end
  win.items:HideFrom(#r.checklist + 1)
  win:Resize(300, 28 + y + 40)
  pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  win:Open()
end
