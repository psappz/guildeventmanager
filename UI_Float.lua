local ADDON, ns = ...
-- Small movable windows for modules (API 7): live rankings, check lists,
-- alarms. Themed like the main window (faction colours), position and lock
-- saved per window id, never protected (they may open and close in combat).
local W, T = ns.W, ns.Theme
local F = { wins = {} }
ns.Float = F

local function store()
  if not ns.db then return {} end
  ns.db.float = ns.db.float or {}
  return ns.db.float
end

local function savePos(win)
  local p, _, rp, x, y = win:GetPoint()
  local s = store()
  s[win.id] = s[win.id] or {}
  s[win.id].p, s[win.id].rp, s[win.id].x, s[win.id].y = p, rp, x, y
end

-- opts: { title, width, height, strata = "MEDIUM"|"HIGH", point = { "CENTER", 0, 120 },
--         onClose = fn(win), noClose = true, lockable = true }
function F.Get(id, opts)
  if F.wins[id] then return F.wins[id] end
  opts = opts or {}
  local th = T.Current()
  local win = CreateFrame("Frame", "GuildEventManagerFloat_" .. id, UIParent, "BackdropTemplate")
  win.id = id
  win:SetSize(opts.width or 240, opts.height or 160)
  win:SetFrameStrata(opts.strata or "MEDIUM")
  W.Paint(win, th.bg, th.title)
  win:SetClampedToScreen(true)
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", function(self) if not self.locked then self:StartMoving() end end)
  win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)

  local s = store()[id]
  if s and s.p then
    win:SetPoint(s.p, UIParent, s.rp, s.x, s.y)
  else
    local pt = opts.point or { "CENTER", 0, 120 }
    win:SetPoint(pt[1], UIParent, pt[1], pt[2] or 0, pt[3] or 0)
  end
  win.locked = s and s.locked or false

  win.title = W.Text(win, 12, "title")
  win.title:SetPoint("TOPLEFT", 10, -9); win.title:SetPoint("RIGHT", -52, 0)
  win.title:SetWordWrap(false)
  win.title:SetText(opts.title or "")

  if not opts.noClose then
    win.close = W.Close(win, function() win:Close() end)
    win.close:SetPoint("TOPRIGHT", -4, -4)
  end
  if opts.lockable ~= false then
    win.lock = W.IconButton(win, "lock", 16)
    win.lock:SetPoint("TOPRIGHT", -28, -7)
    local function show()
      win.lock:SetAlpha(win.locked and 1 or 0.45)
    end
    win.lock:SetScript("OnClick", function()
      win.locked = not win.locked
      local st = store(); st[id] = st[id] or {}; st[id].locked = win.locked
      show()
    end)
    win.lock:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(win.locked and ns.L.FLOAT_UNLOCK or ns.L.FLOAT_LOCK)
      GameTooltip:Show()
    end)
    win.lock:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    show()
  end

  win.content = CreateFrame("Frame", nil, win)
  win.content:SetPoint("TOPLEFT", 8, -28); win.content:SetPoint("BOTTOMRIGHT", -8, 8)

  function win:SetTitle(text) self.title:SetText(text or "") end
  function win:Open() self:Show() end
  function win:Close()
    self:Hide()
    if opts.onClose then ns.SafeCall("float:" .. id, opts.onClose, self) end
  end
  function win:Resize(w, h) self:SetSize(w or self:GetWidth(), h or self:GetHeight()) end
  function win:ResetPosition()
    local pt = opts.point or { "CENTER", 0, 120 }
    self:ClearAllPoints(); self:SetPoint(pt[1], UIParent, pt[1], pt[2] or 0, pt[3] or 0)
    local st = store(); st[id] = nil
  end

  win:Hide()
  F.wins[id] = win
  return win
end
