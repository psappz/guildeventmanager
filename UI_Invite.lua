local ADDON, ns = ...
-- Invitation popup: in the week before an event every member of the right
-- level who has not answered yet is asked to sign up. Two choices:
-- "Open GuildEventManager" (straight to the sign-up) or "Later" (asks again
-- in a few hours). Never during combat and not while the window is open.
local U, T, W, E, UI = ns.U, ns.Theme, ns.W, ns.Events, ns.UI
local L = ns.L
local P = {}
ns.UIInvite = P

local frame

local function leftText(ts)
  local left = (ts or 0) - U.Now()
  if left < 3600 then return ns.L.ASK_SOON end
  if left < 86400 then return ns.L.ASK_IN_HOURS:format(math.floor(left / 3600)) end
  local days = math.floor(left / 86400 + 0.5)
  if days <= 1 then return ns.L.ASK_TOMORROW end
  return ns.L.ASK_IN_DAYS:format(days)
end

local function build()
  local f = W.Box(UIParent, 360, 168, "bg")
  f:SetFrameStrata("DIALOG")
  f:SetPoint("TOP", 0, -140)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local th = T.Current()
  f:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)

  f.head = W.Text(f, 10, "muted")
  f.head:SetPoint("TOPLEFT", 14, -12)
  f.close = W.Close(f, function() P.Later() end)
  f.close:SetPoint("TOPRIGHT", -8, -8)

  f.tile = UI.DateTile(f, 48, 44)
  f.tile:SetPoint("TOPLEFT", 14, -32)
  f.name = W.Text(f, 15, "title")
  f.name:SetFont("Fonts\\MORPHEUS.TTF", 16, "")
  f.name:SetPoint("TOPLEFT", f.tile, "TOPRIGHT", 10, -2)
  f.name:SetPoint("RIGHT", -14, 0)
  f.name:SetWordWrap(false)
  f.when = W.Text(f, 10, "muted")
  f.when:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -5)
  f.when:SetPoint("RIGHT", -14, 0)
  f.when:SetWordWrap(false)
  f.tag = UI.Pill(f)
  f.tag:SetPoint("TOPLEFT", f.when, "BOTTOMLEFT", 0, -5)

  f.text = W.Text(f, 11, "text")
  f.text:SetPoint("TOPLEFT", f.tile, "BOTTOMLEFT", 0, -12)
  f.text:SetPoint("RIGHT", -14, 0)
  f.text:SetText(L.ASK_TEXT)

  f.later = W.Button(f, L.ASK_LATER, false, 24)
  f.later:SetWidth(100)
  f.later:SetPoint("BOTTOMRIGHT", -14, 12)
  f.later:SetScript("OnClick", function() P.Later() end)
  f.open = W.Button(f, L.ASK_OPEN, true, 24)
  f.open:SetWidth(190)
  f.open:SetPoint("RIGHT", f.later, "LEFT", -8, 0)
  f.open:SetScript("OnClick", function() P.Open() end)
  f.more = W.Text(f, 10, "muted")
  f.more:SetPoint("BOTTOMLEFT", 14, 18)

  -- Escape counts as "Later"
  _G.GuildEventManagerInvite = f
  if UISpecialFrames then table.insert(UISpecialFrames, "GuildEventManagerInvite") end
  f:SetScript("OnHide", function(self)
    if self.ev and not self.handled then E.SnoozeInvite(self.ev) end
    self.ev = nil
  end)
  f:Hide()
  return f
end

function P.Show(e, more)
  frame = frame or build()
  local f = frame
  local fresh = f.ev ~= e or not f:IsShown()
  f.ev, f.handled = e, false
  f.head:SetText(L.ASK_HEAD)
  f.tile:Set(e.start)
  f.name:SetText(e.name or "")
  f.when:SetText(U.FormatTime(e.start) .. " · " .. leftText(e.start))
  local tag, col = UI.ModuleTag(e.type)
  f.tag:Set(tag or ns.Modules.TypeName(e.type), false, col)
  f.more:SetText(more > 0 and L.ASK_MORE:format(more) or "")
  f:Show()
  if fresh then pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960) end
end

-- hide without counting it as "Later" (answered, cancelled, window opened)
function P.Hide()
  if frame and frame:IsShown() then frame.handled = true; frame:Hide() end
end

function P.Later()
  if not frame or not frame.ev then return end
  E.SnoozeInvite(frame.ev)
  frame.handled = true
  frame:Hide()
  U.Print(L.ASK_LATER_DONE)
end

function P.Open()
  if not frame or not frame.ev then return end
  local e = frame.ev
  E.SnoozeInvite(e, E.ASK_OPENED)
  frame.handled = true
  frame:Hide()
  if ns.UIEvents and ns.UIEvents.OpenSignup then ns.UIEvents.OpenSignup(e) end
end

-- called by E.CheckInvites (login, every 30 s, after an own sign-up)
function P.Update()
  local due = E.DueInvites()
  if frame and frame:IsShown() then
    -- still open? keep it; answered or gone: next one or close
    local cur = frame.ev
    for i, e in ipairs(due) do
      if e == cur then P.Show(e, #due - 1); return end
      if i == #due then break end
    end
    if #due == 0 then P.Hide(); return end
    frame.handled = true
  end
  if #due == 0 then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local win = UI.Frame and UI.Frame()
  if win and win:IsShown() then return end
  P.Show(due[1], #due - 1)
end

-- held back because of combat: show it as soon as the fight is over
local regen = CreateFrame("Frame")
regen:RegisterEvent("PLAYER_REGEN_ENABLED")
regen:SetScript("OnEvent", function()
  if #E.DueInvites() > 0 then ns.SafeCall("invites", E.CheckInvites) end
end)
