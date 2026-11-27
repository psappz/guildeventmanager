local ADDON, P = ...
-- "Bounties" tab (0.9): the WANTED posters of the open bounties as a carousel,
-- below them every bounty of the last days as a table. On the right: the
-- week in review, public enemies and the guild chest. A click on a poster or
-- a row opens the poster in large with "add GP", "withdraw" and so on.
local core = P.core
if not core then return end
local U, G, T, W, UI = core.U, core.Guild, core.Theme, core.W, core.UI
local L = P.L

local ROW = 22
local DAY = 86400
local state = { idx = 1, auto = true, sort = "total", dir = -1, last = 0 }

local function carouselList()
  local list = P.OpenBounties()
  -- collected ones stay a week (with their stamp), after the open ones
  local now = U.Now()
  for _, b in ipairs(P.WonBounties()) do
    if now - (b.wts or 0) <= 7 * DAY then list[#list + 1] = b end
  end
  return list
end

---------------------------------------------------------------------------
-- Large poster with actions
---------------------------------------------------------------------------
local detail
local function buildDetail()
  local d = W.Box(UIParent, 560, 476, "bg")
  d:SetFrameStrata("DIALOG")
  d:SetToplevel(true)
  d:SetPoint("CENTER", 0, 30)
  d:EnableMouse(true); d:SetMovable(true); d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving); d:SetScript("OnDragStop", d.StopMovingOrSizing)
  _G.GuildEventManagerBountyDetail = d
  tinsert(UISpecialFrames, "GuildEventManagerBountyDetail")
  d.poster = P.NewPoster(d)
  d.poster:SetPoint("TOPLEFT", 12, -13)
  local side = CreateFrame("Frame", nil, d)
  side:SetPoint("TOPLEFT", d.poster, "TOPRIGHT", 14, 0); side:SetPoint("BOTTOMRIGHT", -12, 12)
  d.close = W.Close(d, function() d:Hide() end); d.close:SetPoint("TOPRIGHT", -6, -6)
  d.title = W.Text(side, 14, "title"); d.title:SetPoint("TOPLEFT", 0, 0); d.title:SetPoint("RIGHT", -20, 0); d.title:SetWordWrap(false)
  d.info = W.Text(side, 11, "text"); d.info:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -8); d.info:SetPoint("RIGHT", 0, 0)
  d.info:SetSpacing(3); d.info:SetJustifyH("LEFT")
  d.addHead = W.Text(side, 11, "title"); d.addHead:SetText(L.WNT_ADD_HEAD)
  d.adds = {}
  for i, amt in ipairs({ 5, 10, 25 }) do
    local b = W.Button(side, "+" .. amt .. " " .. P.GPTag(), false, 22)
    b:SetWidth(66)
    b.amt = amt
    d.adds[i] = b
  end
  d.addHint = W.Text(side, 9, "muted"); d.addHint:SetSpacing(2); d.addHint:SetJustifyH("LEFT")
  d.cancel = W.Button(side, L.PVP_BNT_CANCEL, false, 22)
  d.call = W.Button(side, L.WNT_FIND, false, 22)
  d:Hide()
  return d
end

function P.OpenBountyDetail(id)
  local b = P.bounties[id]
  if not b then return end
  detail = detail or buildDetail()
  local d = detail
  d.id = id
  d.poster:SetBounty(b)
  d.title:SetText(b.target)
  local i = b.i or {}
  local lines = {}
  local st = P.BountyState(b)
  lines[#lines + 1] = L.WNT_D_REWARD:format(P.BountyTotal(b), P.GPTag())
  local by = G.Display(b.by) .. (b.gb and (" · " .. L.WNT_D_CHEST) or "")
  lines[#lines + 1] = L.WNT_D_BY:format(by)
  for k, a in pairs(b.adds or {}) do
    if (a or 0) > 0 then lines[#lines + 1] = "   + " .. G.Display(k) .. ": " .. a .. " " .. P.GPTag() end
  end
  if i.st then lines[#lines + 1] = L.WNT_D_SEEN:format(P.WantedWhen(i.st), (i.sz and i.sz ~= "" and (i.sz .. ", ") or "") .. (i.z or "?")) end
  if st == "open" then lines[#lines + 1] = L.WNT_D_UNTIL:format(date("%d.%m. %H:%M", P.BountyEnds(b))) end
  if st == "done" then
    local names = {}
    for _, k in ipairs(b.ws or { b.w }) do names[#names + 1] = G.Display(k) end
    lines[#lines + 1] = U.Color(U.GOLD, L.WNT_D_DONE:format(table.concat(names, ", "), date("%d.%m. %H:%M", b.wts or 0)))
    if b.tri then lines[#lines + 1] = U.Color(U.GOLD, L.WNT_D_TRIPLE:format(b.tri.amt or 0, P.GPTag())) end
  end
  if b.note then
    lines[#lines + 1] = " "
    lines[#lines + 1] = U.Color(T.Hex(T.Current().title), L.WNT_D_NOTE)
    lines[#lines + 1] = b.note
  end
  d.info:SetText(table.concat(lines, "\n"))
  -- actions
  local open = st == "open"
  local me = G.MyKey()
  local mine = (b.adds and b.adds[me] or 0) + ((b.by == me and not b.gb) and b.amt or 0)
  d.addHead:ClearAllPoints(); d.addHead:SetPoint("TOPLEFT", d.info, "BOTTOMLEFT", 0, -16)
  for n, btn in ipairs(d.adds) do
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", d.addHead, "BOTTOMLEFT", (n - 1) * 72, -6)
    btn:SetShown(open)
    btn:SetEnabled(open and mine < P.BOUNTY_CAP and P.MyGP() >= btn.amt)
    btn:SetScript("OnClick", function() if P.AddToBounty(b.id, btn.amt) then P.OpenBountyDetail(b.id) end end)
  end
  d.addHead:SetShown(open)
  d.addHint:ClearAllPoints(); d.addHint:SetPoint("TOPLEFT", d.adds[1], "BOTTOMLEFT", 0, -6); d.addHint:SetPoint("RIGHT", d, "RIGHT", -12, 0)
  d.addHint:SetText(open and L.WNT_ADD_HINT:format(mine, P.BOUNTY_CAP, P.GPTag()) or "")
  d.cancel:ClearAllPoints(); d.cancel:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12 + 300 + 14, 12)
  d.cancel:SetShown(P.CanCancel(b))
  d.cancel:SetScript("OnClick", function()
    W.Dialog({ text = L.PVP_BNT_CANCEL_Q:format(b.target, b.amt), accept = L.PVP_BNT_CANCEL, onAccept = function()
      P.CancelBounty(b.id); d:Hide()
    end })
  end)
  d.call:ClearAllPoints(); d.call:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -12, 12)
  d.call:SetShown(open)
  d.call:SetScript("OnClick", function()
    if P.ToggleWatch and not P.WatchList()[P.NameKey(b.target)] then P.ToggleWatch(b.target) end
    U.Print(L.WNT_FIND_HINT:format(b.target))
  end)
  d:Show()
end

core.On("PVP_BOUNTY_ADD", function(b) if detail and detail:IsShown() and detail.id == b.id then P.OpenBountyDetail(b.id) end end)
core.On("PVP_BOUNTY_WON", function(b) if detail and detail:IsShown() and detail.id == b.id then P.OpenBountyDetail(b.id) end end)

---------------------------------------------------------------------------
-- Setting a bounty
---------------------------------------------------------------------------
local create
local function candidates()
  local list, seen, now = {}, {}, U.Now()
  local function add(name, why)
    local k = P.BountyKey(name)
    if not k or seen[k] then return end
    seen[k] = true
    list[#list + 1] = { name = name, why = why, i = P.SeenInfo(name) }
  end
  for _, d in ipairs(P.OpenDebts and P.OpenDebts() or {}) do add(d.name, T.Word("DEBT")) end
  local recent = {}
  for _, i in pairs(P.seenEnemies or {}) do if i.name and now - (i.st or 0) < 3600 then recent[#recent + 1] = i end end
  table.sort(recent, function(a, b) return (a.st or 0) > (b.st or 0) end)
  for _, i in ipairs(recent) do add(i.name, L.WNT_C_SEEN) end
  return list
end

local function buildCreate()
  local c = W.Box(UIParent, 440, 400, "bg")
  c:SetFrameStrata("DIALOG"); c:SetToplevel(true)
  c:SetPoint("CENTER", 0, 40)
  c:EnableMouse(true); c:SetMovable(true); c:RegisterForDrag("LeftButton")
  c:SetScript("OnDragStart", c.StartMoving); c:SetScript("OnDragStop", c.StopMovingOrSizing)
  _G.GuildEventManagerBountyCreate = c
  tinsert(UISpecialFrames, "GuildEventManagerBountyCreate")
  c.title = W.Text(c, 14, "title"); c.title:SetPoint("TOPLEFT", 14, -12); c.title:SetText(L.PVP_BNT_TITLE)
  c.close = W.Close(c, function() c:Hide() end); c.close:SetPoint("TOPRIGHT", -6, -6)
  c.sub = W.Text(c, 10, "muted"); c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4); c.sub:SetText(L.WNT_C_PICK)
  c.rows = W.Pool(c, function(parent)
    local b = W.Button(parent, "", false, 24)
    b.label:ClearAllPoints(); b.label:SetPoint("LEFT", 8, 0); b.label:SetPoint("RIGHT", -8, 0); b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    return b
  end)
  c.nameL = W.Text(c, 10, "muted"); c.nameL:SetText(L.PVP_BNT_L_NAME)
  c.name = W.Edit(c, 260, 22); c.name:SetMaxLetters(48)
  c.take = W.Button(c, L.PVP_BNT_TAKE, false, 22); c.take:SetWidth(120)
  c.amtL = W.Text(c, 10, "muted")
  c.amt = W.Edit(c, 60, 22); c.amt:SetMaxLetters(3); if c.amt.SetNumeric then c.amt:SetNumeric(true) end
  c.minus = W.Button(c, "−", false, 22); c.minus:SetWidth(26)
  c.plus = W.Button(c, "+", false, 22); c.plus:SetWidth(26)
  c.guild = W.Check(c, L.WNT_C_GUILD, function() c:Validate() end)
  c.noteL = W.Text(c, 10, "muted"); c.noteL:SetText(L.WNT_C_NOTE)
  c.noteN = W.Text(c, 10, "muted"); c.noteN:SetJustifyH("RIGHT")
  c.note = W.Edit(c, 412, 46, true); c.note:SetMaxLetters(P.NOTE_MAX)
  c.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  c.note:SetScript("OnTextChanged", function(self)
    local s = self:GetText() or ""
    local n = 0
    for _ in s:gmatch("[^\128-\191]") do n = n + 1 end
    c.noteN:SetText(n .. " / " .. P.NOTE_MAX)
  end)
  c.msg = W.Text(c, 10, "muted"); c.msg:SetSpacing(2); c.msg:SetJustifyH("LEFT")
  c.ok = W.Button(c, L.WNT_C_POST, true, 26); c.ok:SetWidth(150)
  c.cancel = W.Button(c, CANCEL or "Cancel", false, 26); c.cancel:SetWidth(100)
  c.cancel:SetScript("OnClick", function() c:Hide() end)

  function c:Validate()
    local name, amt = self.name:GetText() or "", tonumber(self.amt:GetText()) or 0
    local guild = self.guild:IsShown() and self.guild:GetChecked()
    local ok, why = P.CanPostOn(name, amt, guild)
    local th = T.Current()
    if ok then
      local i = P.SeenInfo(name)
      local bits = {}
      if i then
        if i.lv and i.lv > 0 then bits[#bits + 1] = L.PVP_AL_LEVEL:format(i.lv) end
        if i.r then bits[#bits + 1] = i.r end
        if i.cl then bits[#bits + 1] = i.cl end
      else bits[#bits + 1] = L.WNT_C_UNKNOWN end
      self.msg:SetText(table.concat(bits, " · ") .. "\n" .. (guild and L.WNT_C_GUILD_HINT or L.WNT_C_PAY_HINT:format(P.MyGP(), P.GPTag())))
      W.Color(self.msg, "muted")
    else
      self.msg:SetText(name ~= "" and why or "")
      self.msg:SetTextColor(1, 0.45, 0.35, 1)
    end
    self.ok:SetEnabled(ok and true or false)
  end
  c.name:SetScript("OnTextChanged", function() c:Validate() end)
  c.amt:SetScript("OnTextChanged", function() c:Validate() end)
  c.minus:SetScript("OnClick", function()
    local min = P.BountyLimits()
    c.amt:SetText(tostring(math.max(min, (tonumber(c.amt:GetText()) or min) - 5)))
  end)
  c.plus:SetScript("OnClick", function()
    local _, max = P.BountyLimits()
    c.amt:SetText(tostring(math.min(max, (tonumber(c.amt:GetText()) or 0) + 5)))
  end)
  c.take:SetScript("OnClick", function()
    if P.IsEnemyPlayer and P.IsEnemyPlayer("target") then
      local n = P.UnitNameOf("target")
      if n then
        if P.NoteEnemy then core.SafeCall("pvpNoteEnemy", P.NoteEnemy, "target", n) end
        c.name:SetText(n); return
      end
    end
    U.Print(L.PVP_BNT_NOTARGET)
  end)
  c.ok:SetScript("OnClick", function()
    local guild = c.guild:IsShown() and c.guild:GetChecked()
    if P.PostBounty(c.name:GetText(), tonumber(c.amt:GetText()), { guild = guild, note = c.note:GetText() }) then c:Hide() end
  end)
  c:Hide()
  return c
end

-- opts: { name, amt, guild }
function P.OpenBountyCreate(opts)
  opts = opts or {}
  create = create or buildCreate()
  local c = create
  local list = candidates()
  local n = 0
  for _, x in ipairs(list) do
    if n >= 6 then break end
    n = n + 1
    local b = c.rows:Get(n)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -54 - (n - 1) * 28); b:SetPoint("RIGHT", c, "RIGHT", -14, 0)
    local bits = { x.name }
    if x.i then
      if x.i.lv and x.i.lv > 0 then bits[#bits + 1] = L.PVP_AL_LEVEL:format(x.i.lv) end
      if x.i.r then bits[#bits + 1] = x.i.r end
      if x.i.cl then bits[#bits + 1] = x.i.cl end
    end
    bits[#bits + 1] = x.why
    W.SetLabel(b, table.concat(bits, " · "))
    b:SetScript("OnClick", function() c.name:SetText(x.name) end)
  end
  c.rows:HideFrom(n + 1)
  c.sub:SetText(n > 0 and L.WNT_C_PICK or L.WNT_C_NONE)
  local top = -54 - n * 28 - 12
  c.nameL:ClearAllPoints(); c.nameL:SetPoint("TOPLEFT", 14, top)
  c.name:ClearAllPoints(); c.name:SetPoint("TOPLEFT", c.nameL, "BOTTOMLEFT", 0, -3)
  c.take:ClearAllPoints(); c.take:SetPoint("LEFT", c.name, "RIGHT", 8, 0)
  local min, max = P.BountyLimits()
  c.amtL:SetText(L.WNT_C_AMT:format(min, max, P.GPTag()))
  c.amtL:ClearAllPoints(); c.amtL:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -10)
  c.minus:ClearAllPoints(); c.minus:SetPoint("TOPLEFT", c.amtL, "BOTTOMLEFT", 0, -3)
  c.amt:ClearAllPoints(); c.amt:SetPoint("LEFT", c.minus, "RIGHT", 4, 0)
  c.plus:ClearAllPoints(); c.plus:SetPoint("LEFT", c.amt, "RIGHT", 4, 0)
  local manager = P.CanGuildBounty()
  c.guild:SetShown(manager)
  if manager then
    local used, limit = P.GuildChestUsed()
    c.guild.text:SetText(L.WNT_C_GUILD:format(math.max(0, limit - used), limit, P.GPTag()))
  end
  c.guild:ClearAllPoints(); c.guild:SetPoint("LEFT", c.plus, "RIGHT", 16, 0)
  c.guild:SetChecked(opts.guild and manager or false)
  c.noteL:ClearAllPoints(); c.noteL:SetPoint("TOPLEFT", c.minus, "BOTTOMLEFT", 0, -12)
  c.note:ClearAllPoints(); c.note:SetPoint("TOPLEFT", c.noteL, "BOTTOMLEFT", 0, -3)
  c.noteN:ClearAllPoints(); c.noteN:SetPoint("BOTTOMRIGHT", c.note, "TOPRIGHT", 0, 3)
  c.note:SetText(opts.note or "")
  c.msg:ClearAllPoints(); c.msg:SetPoint("TOPLEFT", c.note, "BOTTOMLEFT", 0, -10); c.msg:SetPoint("RIGHT", c, "RIGHT", -14, 0)
  c.ok:ClearAllPoints(); c.ok:SetPoint("BOTTOMRIGHT", -14, 14)
  c.cancel:ClearAllPoints(); c.cancel:SetPoint("RIGHT", c.ok, "LEFT", -8, 0)
  c:SetHeight(-top + 240)
  c.name:SetText(opts.name or (list[1] and list[1].name) or "")
  c.amt:SetText(tostring(opts.amt or math.min(max, math.max(min, 20))))
  c:Validate()
  c:Show()
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
-- w: share of the width; align: how header and cells sit in the column
local COLS = {
  { key = "name", w = 0.18, label = "WNT_T_TARGET" },
  { key = "race", w = 0.19, label = "WNT_T_RACE" },
  { key = "lvl", w = 0.05, label = "WNT_T_LEVEL", align = "RIGHT" },
  { key = "seen", w = 0.25, label = "WNT_T_SEEN" },
  { key = "total", w = 0.08, label = "WNT_T_REWARD", align = "RIGHT" },
  { key = "by", w = 0.12, label = "WNT_T_BY" },
  { key = "state", w = 0.13, label = "WNT_T_STATE" },
}
local PADX, GAP = 12, 12          -- table inset, space between columns

-- x and width of each column for a table of width w
local function colGeo(w)
  local inner = w - 2 * PADX
  local geo, x = {}, PADX
  for k, c in ipairs(COLS) do
    local cw = math.floor(c.w * inner)
    geo[k] = { x = x, w = cw - GAP }
    x = x + cw
  end
  return geo
end

local function build(p)
  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPRIGHT", 0, 0); right:SetWidth(270); right:SetHeight(270)
  p.right = right
  -- carousel
  local car = W.Box(p, 10, 330, "panel2")
  car:SetPoint("TOPLEFT", 0, 0); car:SetPoint("RIGHT", right, "LEFT", -12, 0)
  p.car = car
  p.carHead = W.Text(car, 12, "title"); p.carHead:SetPoint("TOPLEFT", 10, -8); p.carHead:SetText(L.WNT_TAB_POSTERS)
  p.auto = W.Check(car, L.WNT_AUTO, function(_, on) state.auto = on end); p.auto:SetPoint("BOTTOMLEFT", 10, 8)
  p.postBtn = W.Button(car, L.PVP_BNT_TITLE, true, 22); p.postBtn:SetPoint("TOPRIGHT", -8, -4); p.postBtn:SetWidth(108)
  p.postBtn:SetScript("OnClick", function() P.OpenBountyCreate() end)
  -- carousel: five holders slide along a track; t is a holder's place relative
  -- to the centre (0 centre, -1/+1 the sides, -2/+2 outside, faded out)
  pcall(car.SetClipsChildren, car, true)
  local CS, SS = 0.62, 0.44                 -- scale in the centre / at the sides
  local function track(t)
    local a = math.abs(t)
    local sgn = t < 0 and -1 or 1
    local s, x, top, alpha
    if a <= 1 then
      s = CS + (SS - CS) * a
      x = (93 + 14 + 66) * a                -- half centre + gap + half side
      top = 28 + 16 * a
      alpha = 1 - 0.45 * a
    else
      local b = math.min(a - 1, 1)
      s = SS - 0.08 * b
      x = 173 + 150 * b
      top = 44 + 10 * b
      alpha = 0.55 * (1 - b)
    end
    return s, sgn * x, top, alpha
  end
  p.holders = {}
  for k = 1, 5 do
    local h = CreateFrame("Button", nil, car)
    h:SetSize(300, 450)
    h.poster = P.NewPoster(h)
    h.poster:SetPoint("TOPLEFT")
    h:SetScript("OnClick", function(self)
      if not self.t then return end
      if math.abs(self.t) < 0.5 then
        if self.poster.b then P.OpenBountyDetail(self.poster.b.id) end
      else
        state.idx = state.idx + (self.t < 0 and -1 or 1); state.last = GetTime()
      end
    end)
    p.holders[k] = h
  end
  function p:PlaceCarousel()
    local list = self.carList or {}
    local n = #list
    local pos = state.pos or state.idx
    local base = math.floor(pos + 0.5)
    for k, h in ipairs(self.holders) do
      local off = k - 3
      local idx = base + off
      local t = idx - pos
      local show = n > 0 and math.abs(t) < 2
      if n < 3 then show = show and (idx - base == 0 or (n == 2 and idx - base == 1)) end
      if show then
        local b = list[((idx - 1) % n) + 1]
        if h.bid ~= b.id or h.bts ~= (b.ts or 0) then h.poster:SetBounty(b); h.bid, h.bts = b.id, b.ts or 0 end
        local sc, x, top, alpha = track(t)
        h:SetScale(sc)
        h:ClearAllPoints()
        h:SetPoint("TOP", car, "TOP", x / sc, -top / sc)
        h:SetAlpha(alpha)
        h:SetFrameLevel(car:GetFrameLevel() + 10 - math.floor(math.abs(t) * 3))
        h.poster.noLive = math.abs(t) > 0.3
        h.t = t
        h:Show()
      else
        h:Hide(); h.t = nil
      end
    end
  end
  p.prev = W.Button(car, "<", false, 40); p.prev:SetWidth(24); p.prev:SetPoint("LEFT", 8, -10)
  p.next = W.Button(car, ">", false, 40); p.next:SetWidth(24); p.next:SetPoint("RIGHT", -8, -10)
  p.prev:SetFrameLevel(car:GetFrameLevel() + 20); p.next:SetFrameLevel(car:GetFrameLevel() + 20)
  p.prev:SetScript("OnClick", function() state.idx = state.idx - 1; state.last = GetTime() end)
  p.next:SetScript("OnClick", function() state.idx = state.idx + 1; state.last = GetTime() end)
  p.caption = W.Text(car, 11, "text"); p.caption:SetPoint("BOTTOM", car, "BOTTOM", 0, 8); p.caption:SetWordWrap(false)
  p.empty = W.Text(car, 11, "muted"); p.empty:SetPoint("CENTER", 0, -10); p.empty:SetWidth(360); p.empty:SetSpacing(2)
  p.empty:SetText(L.PVP_BNT_OPEN_NONE)
  -- auto rotation
  local acc = 0
  car:SetScript("OnUpdate", function(_, dt)
    -- glide towards the chosen poster (eased; a fast click series catches up)
    local pos = state.pos or state.idx
    if #(p.carList or {}) < 3 and pos ~= state.idx then state.pos = state.idx; UI.Refresh(); return end
    if pos ~= state.idx then
      local d = state.idx - pos
      local step = dt * math.max(3, math.abs(d) * 4)
      if math.abs(d) <= step then pos = state.idx else pos = pos + (d > 0 and step or -step) end
      state.pos = pos
      p:PlaceCarousel()
      if pos == state.idx then UI.Refresh() end
    end
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    if state.auto and GetTime() - state.last > 6 and not (detail and detail:IsShown()) and p:IsVisible() then
      local n = #carouselList()
      if n > 1 then state.idx = state.idx + 1; state.last = GetTime() end
    end
  end)

  -- right column: week, public enemies, chest
  p.week = W.Box(right, 270, 128, "panel2"); p.week:SetPoint("TOPLEFT")
  p.weekHead = W.Text(p.week, 12, "title"); p.weekHead:SetPoint("TOPLEFT", 10, -8); p.weekHead:SetText(L.WNT_WEEK)
  p.weekNums = {}
  for n = 1, 3 do
    local box = W.Box(p.week, 78, 40, "panel")
    box:SetPoint("TOPLEFT", 10 + (n - 1) * 84, -28)
    box.v = W.Text(box, 16, "hot"); box.v:SetPoint("TOP", 0, -4)
    box.l = W.Text(box, 9, "muted"); box.l:SetPoint("BOTTOM", 0, 4)
    p.weekNums[n] = box
  end
  p.weekText = W.Text(p.week, 10, "text"); p.weekText:SetPoint("TOPLEFT", 10, -74); p.weekText:SetPoint("RIGHT", -10, 0)
  p.weekText:SetSpacing(2); p.weekText:SetJustifyH("LEFT")

  p.foe = W.Box(right, 270, 132, "panel2"); p.foe:SetPoint("TOPLEFT", p.week, "BOTTOMLEFT", 0, -10)
  p.foeHead = W.Text(p.foe, 12, "title"); p.foeHead:SetPoint("TOPLEFT", 10, -8); p.foeHead:SetText(L.WNT_FOE)
  p.foeText = W.Text(p.foe, 10, "text"); p.foeText:SetPoint("TOPLEFT", 10, -28); p.foeText:SetPoint("RIGHT", -10, 0)
  p.foeText:SetSpacing(2); p.foeText:SetJustifyH("LEFT")
  p.foeBtn = W.Button(p.foe, "", true, 22); p.foeBtn:SetPoint("BOTTOMLEFT", 10, 26)
  p.chest = W.Text(p.foe, 9, "muted"); p.chest:SetPoint("BOTTOMLEFT", 10, 8); p.chest:SetPoint("RIGHT", -10, 0)

  -- table
  local tbl = W.Box(p, 10, 10, "panel2")
  tbl:SetPoint("TOPLEFT", car, "BOTTOMLEFT", 0, -12); tbl:SetPoint("BOTTOMRIGHT", 0, 0)
  p.tbl = tbl
  p.heads = {}
  -- headers: plain text over a thin line, click to sort
  p.headLine = tbl:CreateTexture(nil, "ARTWORK")
  p.headLine:SetHeight(1); p.headLine:SetPoint("TOPLEFT", PADX, -26); p.headLine:SetPoint("TOPRIGHT", -PADX, -26)
  for n, col in ipairs(COLS) do
    local h = CreateFrame("Button", nil, tbl)
    h:SetHeight(20)
    h.col = col
    h.label = W.Text(h, 10, "title")
    h.label:SetPoint("LEFT"); h.label:SetPoint("RIGHT"); h.label:SetJustifyH(col.align or "LEFT"); h.label:SetWordWrap(false)
    h:SetScript("OnEnter", function(self) W.Color(self.label, "text") end)
    h:SetScript("OnLeave", function(self) W.Color(self.label, "title") end)
    h:SetScript("OnClick", function()
      if state.sort == col.key then state.dir = -state.dir else state.sort = col.key; state.dir = (col.key == "name" or col.key == "by") and 1 or -1 end
      UI.Refresh()
    end)
    p.heads[n] = h
  end
  p.scroll = W.Scroll(tbl)
  p.scroll:SetPoint("TOPLEFT", 0, -30); p.scroll:SetPoint("BOTTOMRIGHT", 0, 4)
  p.rows = W.Pool(p.scroll.content, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW)
    r.stripe = r:CreateTexture(nil, "BACKGROUND", nil, 0); r.stripe:SetPoint("TOPLEFT", PADX - 4, 0); r.stripe:SetPoint("BOTTOMRIGHT", -(PADX - 4), 0)
    r.stripe:SetColorTexture(1, 1, 1, 0.025)
    r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1); r.hl:SetAllPoints(r.stripe); r.hl:SetColorTexture(1, 1, 1, 0.06); r.hl:Hide()
    r:SetScript("OnEnter", function(self) self.hl:Show() end)
    r:SetScript("OnLeave", function(self) self.hl:Hide() end)
    r.cells = {}
    for n = 1, #COLS do
      local c = W.Text(r, 10, "text"); c:SetWordWrap(false); c:SetJustifyH(COLS[n].align or "LEFT")
      r.cells[n] = c
    end
    return r
  end)
  p.tblEmpty = W.Text(tbl, 10, "muted"); p.tblEmpty:SetPoint("TOPLEFT", 10, -34); p.tblEmpty:SetText(L.PVP_BNT_OPEN_NONE)
end

local function stateText(b)
  local st = P.BountyState(b)
  if st == "open" then
    local left = math.max(0, P.BountyEnds(b) - U.Now())
    return L.WNT_ST_OPEN:format(U.FormatSpan and U.FormatSpan(left) or (math.ceil(left / DAY) .. " d")), "hot"
  elseif st == "done" then
    local names = {}
    for _, k in ipairs(b.ws or { b.w }) do names[#names + 1] = G.Display(k) end
    return L.WNT_ST_DONE:format(table.concat(names, ", ")), "good"
  elseif st == "expired" or b.expired then return L.WNT_ST_EXP, "muted"
  end
  return L.WNT_ST_OFF, "muted"
end

local SORT = {
  name = function(b) return b.target:lower() end,
  race = function(b) return ((b.i and b.i.r) or "") .. ((b.i and b.i.cl) or "") end,
  lvl = function(b) return tonumber(b.i and b.i.lv) or 0 end,
  seen = function(b) return (b.i and b.i.st) or 0 end,
  total = function(b) return P.BountyTotal(b) end,
  by = function(b) return G.Display(b.by):lower() end,
  state = function(b) local st = P.BountyState(b); return (st == "open" and 3 or (st == "done" and 2 or 1)) * 1e10 + (b.ts or 0) end,
}

local function refresh(p)
  local th = T.Current()
  -- carousel
  local list = carouselList()
  local n = #list
  p.empty:SetShown(n == 0)
  p.prev:SetShown(n > 1); p.next:SetShown(n > 1)
  p.auto:SetChecked(state.auto)
  p.carList = list
  for _, h in ipairs(p.holders) do h.bid = nil end      -- contents may have changed
  if n < 3 or not state.pos then state.pos = state.idx end
  p:PlaceCarousel()
  if n > 0 then
    local i = ((state.idx - 1) % n) + 1
    local cur = list[i]
    local st = P.BountyState(cur)
    p.caption:SetText(cur.target .. U.Color(T.Hex(th.muted), "  ·  " .. P.BountyTotal(cur) .. " " .. P.GPTag() .. "  ·  " .. stateText(cur) .. "  ·  " .. i .. "/" .. n))
  else
    p.caption:SetText("")
  end

  -- week in review
  local r = P.WeekRecap()
  local nums = { { r.set, L.WNT_W_SET }, { r.done, L.WNT_W_DONE }, { r.paid, L.WNT_W_PAID:format(P.GPTag()) } }
  for k, box in ipairs(p.weekNums) do box.v:SetText(tostring(nums[k][1])); box.l:SetText(nums[k][2]) end
  local lines = {}
  lines[#lines + 1] = L.WNT_W_HUNTER:format(r.best and (G.Display(r.best.key) .. " (" .. r.best.n .. ")") or "–")
  lines[#lines + 1] = L.WNT_W_MOST:format(r.most and (r.most.target .. " · " .. P.BountyTotal(r.most) .. " " .. P.GPTag()) or "–")
  lines[#lines + 1] = L.WNT_W_TRIPLE:format(r.triples)
  p.weekText:SetText(table.concat(lines, "\n"))

  -- public enemies
  local foes = P.PublicEnemies()
  local f1
  local fl = {}
  for _, f in ipairs(foes) do
    if #fl < 3 then fl[#fl + 1] = L.WNT_FOE_LINE:format(f.name, f.n) .. (f.open and U.Color(T.Hex(th.muted), " · " .. L.WNT_FOE_HAS) or "") end
    if not f.open and not f1 then f1 = f end
  end
  p.foeText:SetText(#fl > 0 and table.concat(fl, "\n") or L.WNT_FOE_NONE:format(P.Rules().foeMembers or 3))
  local manager = P.CanGuildBounty()
  local amt = tonumber(P.Rules().foeBounty) or 25
  p.foeBtn:SetShown(manager and f1 ~= nil)
  if f1 then
    W.SetLabel(p.foeBtn, L.WNT_FOE_BTN:format(amt, P.GPTag()))
    p.foeBtn:SetWidth(p.foeBtn.label:GetStringWidth() + 24)
    p.foeBtn:SetScript("OnClick", function() P.OpenBountyCreate({ name = f1.name, amt = amt, guild = true }) end)
  end
  local used, limit = P.GuildChestUsed()
  p.chest:SetText(L.WNT_CHEST_LINE:format(used, limit, P.GPTag()) .. (manager and "" or ("  ·  " .. L.WNT_CHEST_WHO)))

  -- table
  local w = p.tbl:GetWidth() or 600
  local geo = colGeo(w)
  local lc = th.line or th.muted
  p.headLine:SetColorTexture(lc[1], lc[2], lc[3], 0.8)
  for k, h in ipairs(p.heads) do
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", p.tbl, "TOPLEFT", geo[k].x, -5); h:SetWidth(geo[k].w)
    local arrow = state.sort == COLS[k].key and (state.dir < 0 and " v" or " ^") or ""
    h.label:SetText(L[COLS[k].label] .. arrow)
  end
  local all = P.RecentBounties(14)
  local fn = SORT[state.sort] or SORT.total
  table.sort(all, function(a, b)
    local ka, kb = fn(a), fn(b)
    if ka == kb then return (a.ts or 0) > (b.ts or 0) end
    if state.dir < 0 then return ka > kb end
    return ka < kb
  end)
  for i, b in ipairs(all) do
    local row = p.rows:Get(i)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW); row:SetPoint("RIGHT", p.scroll.content, "RIGHT", 0, 0)
    local inf = b.i or {}
    local lv = tonumber(inf.lv)
    local st, color = stateText(b)
    local by = G.Display(b.by)
    local more = 0
    for k, a in pairs(b.adds or {}) do if k ~= b.by and (a or 0) > 0 then more = more + 1 end end
    if more > 0 then by = by .. " +" .. more end
    if b.gb then by = by .. " (" .. L.WNT_D_CHEST .. ")" end
    local zone = inf.z and ((inf.sz and inf.sz ~= "" and inf.sz ~= inf.z) and (inf.sz .. ", " .. inf.z) or inf.z) or "?"
    local vals = { b.target, (inf.r or "?") .. " · " .. (inf.cl or "?"), (lv and lv > 0) and tostring(lv) or ((lv and lv < 0) and "??" or "?"),
      (inf.st and P.WantedWhen(inf.st) or "?") .. " · " .. zone, P.BountyTotal(b) .. " " .. P.GPTag(), by, st }
    row.stripe:SetShown(i % 2 == 0)
    for k, c in ipairs(row.cells) do
      c:ClearAllPoints(); c:SetPoint("LEFT", row, "LEFT", geo[k].x, 0); c:SetWidth(geo[k].w)
      c:SetText(vals[k])
      W.Color(c, k == 7 and color or (k == 5 and "hot" or "text"))
    end
    row:SetScript("OnClick", function() P.OpenBountyDetail(b.id) end)
  end
  p.rows:HideFrom(#all + 1)
  p.scroll:SetContentHeight(#all * ROW)
  p.tblEmpty:SetShown(#all == 0)
end

UI.AddTab("pvpbounty", {
  parent = "pvp",
  label = function() return L.TAB_PVPBOUNTY end,
  build = build,
  refresh = refresh,
})
