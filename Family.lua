-- Manager family: shows which of psappz' Manager addons are installed (same file in every member)
-- Copyright (C) 2026 psappz - MIT
local _, ns = ...

local F = {}
ns.Family = F
F.MEMBERS = { "ConfigManager", "LegacyManager", "RecipeManager", "DungeonManager", "GuildEventManager" }
F.URL = "curseforge.com/members/psappz/projects"

local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
local MISSING = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t"

local function state(name)
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)) or (IsAddOnLoaded and IsAddOnLoaded(name))
    if loaded then return "loaded" end
    local get = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    if get then
        local ok, n, _, _, _, reason = pcall(get, name)
        if ok and n and reason ~= "MISSING" then return "installed" end
    end
    return "missing"
end

-- One line, e.g. "Manager family: [ok] ConfigManager  [ok] LegacyManager  [x] RecipeManager ..."
function F.Line(title)
    local parts = {}
    for _, name in ipairs(F.MEMBERS) do
        local s = state(name)
        if s == "loaded" then table.insert(parts, READY .. " |cffffffff" .. name .. "|r")
        elseif s == "installed" then table.insert(parts, READY .. " |cff9a9a9a" .. name .. "|r")
        else table.insert(parts, MISSING .. " |cff9a9a9a" .. name .. "|r") end
    end
    return (title or "Manager family") .. ":  " .. table.concat(parts, "   ")
end

function F.Missing()
    local out = {}
    for _, name in ipairs(F.MEMBERS) do if state(name) == "missing" then table.insert(out, name) end end
    return out
end

-- Opens a sibling addon's main window (only when it is loaded)
function F.Open(name)
    if state(name) ~= "loaded" then return false end
    if name == "LegacyManager" and _G.LegacyManagerAPI and LegacyManagerAPI.Open then return pcall(LegacyManagerAPI.Open) end
    local fn = SlashCmdList and SlashCmdList[string.upper(name)]
    if fn then return pcall(fn, "") end
    return false
end

-- Clickable family bar: "Manager family:  [ok] ConfigManager  [ok] LegacyManager ..."
function F.Bar(parent, title, font)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(10, 16)
    bar.title = bar:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    bar.title:SetPoint("LEFT")
    bar.title:SetText((title or "Manager family") .. ":")
    bar.buttons = {}
    local prev = bar.title
    for _, name in ipairs(F.MEMBERS) do
        local b = CreateFrame("Button", nil, bar)
        b:SetHeight(16)
        b.text = b:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        b.text:SetPoint("LEFT")
        b:SetPoint("LEFT", prev, "RIGHT", 10, 0)
        b.name = name
        b:SetScript("OnClick", function(self) F.Open(self.name) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.name, 1, 0.82, 0)
            if state(self.name) == "loaded" then GameTooltip:AddLine("Click: open", 1, 1, 1)
            else GameTooltip:AddLine(F.URL, 0.7, 0.7, 0.7) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.buttons[#bar.buttons + 1] = b
        prev = b
    end
    function bar:Refresh()
        for _, b in ipairs(self.buttons) do
            local s = state(b.name)
            local icon = (s == "missing") and MISSING or READY
            local color = (s == "loaded") and "|cffffffff" or "|cff9a9a9a"
            b.text:SetText(icon .. " " .. color .. b.name .. "|r")
            b:SetWidth(b.text:GetStringWidth())
        end
    end
    bar:Refresh()
    return bar
end
