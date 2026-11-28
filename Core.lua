local ADDON, ns = ...

-- Saved settings. Anything missing from the saved table is filled in from here on load,
-- so new options can be added later without wiping what is already saved.
ns.defaults = {
    replaceKey = true,    -- the key bound to "Toggle Quest Log" (L) opens this window instead of the map
    trackerOpensLog = true, -- clicking a quest in Blizzard's or Questie's tracker opens it here
    listTooltips = true,  -- hovering a quest in the list shows its objectives
    showLevels = true,    -- "[12] Quest name"
    colorByLevel = true,  -- difficulty colours (grey / green / yellow / orange / red)
    textShadow = true,    -- a pale shadow under the quest text, so it stands off the parchment
    headerColor = { 1, 1, 1 }, -- category titles: white, so they never look like a (yellow) quest
    collapsed = {},       -- [header title] = true, our own collapse state (the game's is left alone)
    selectedQuest = {},   -- ["Name-Realm"] = questID, the quest each character last had selected
    point = nil,          -- saved window position { point, relPoint, x, y }
    locked = false,       -- true: the window can't be dragged (padlock button)
    width = nil,          -- window size; nil = the classic 682 x 447
    height = nil,
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- "Name-Realm", for settings kept per character.
function ns.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function ns.Print(msg)
    print("|cff66ccffForever Standalone Quest Log|r: " .. tostring(msg))
end

------------------------------------------------------------------------
-- Key binding takeover
--
-- On Forever, L runs the game's TOGGLEQUESTLOG binding, which opens the world map with the
-- quest log attached. When replaceKey is on, every key bound to that action gets an override
-- binding that clicks a hidden button of ours instead. Override bindings sit on top of the
-- player's own bindings and are dropped with ClearOverrideBindings, so turning the option off
-- gives L back to the game without touching the player's key setup.
------------------------------------------------------------------------
local toggleButton = CreateFrame("Button", "ForeverQuestLogToggleButton", UIParent)
toggleButton:SetScript("OnClick", function() ns.Toggle() end)

local bindingOwner = CreateFrame("Frame")
local appliedKeys -- the keys the overrides were last set for, so repeat calls are cheap
local pendingBindings = false

function ns.ApplyBindings()
    if InCombatLockdown() then
        pendingBindings = true -- override bindings can't change in combat; retry on PLAYER_REGEN_ENABLED
        return
    end
    pendingBindings = false
    local keys = {}
    if ns.db.replaceKey then
        keys = { GetBindingKey("TOGGLEQUESTLOG") }
    end
    local sig = table.concat(keys, ",")
    if sig == appliedKeys then return end
    appliedKeys = sig
    ClearOverrideBindings(bindingOwner)
    for _, key in ipairs(keys) do
        SetOverrideBindingClick(bindingOwner, false, key, "ForeverQuestLogToggleButton")
    end
end

-- Labels for the entry Bindings.xml adds under Key Bindings > AddOns.
BINDING_HEADER_FOREVERQUESTLOG = "Forever Standalone Quest Log"
BINDING_NAME_FOREVERQUESTLOG_TOGGLE = "Toggle Forever Standalone Quest Log"

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("GROUP_ROSTER_UPDATE")    -- party members on each quest
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ForeverQuestLogDB = CopyDefaults(ForeverQuestLogDB or {}, ns.defaults)
        ns.db = ForeverQuestLogDB
        -- Layout 2 is the classic-art window; a position saved for the old, larger window would
        -- no longer fit, so it starts again at the classic left-panel spot.
        if (ns.db.layout or 1) < 2 then
            ns.db.point = nil
            ns.db.layout = 2
        end
        ns.db.lastShowMap = nil -- a Show Map diagnostic record from a test build; no longer written
        ns.ApplyFonts()
        ns.CreateWindow()
    elseif event == "PLAYER_LOGIN" or event == "UPDATE_BINDINGS" then
        if ns.db then ns.ApplyBindings() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingBindings then ns.ApplyBindings() end
    else
        -- Quest data changed. The window only rebuilds while it is open; otherwise it is
        -- marked stale and rebuilds the next time it is shown.
        ns.MarkDirty()
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_FOREVERQUESTLOG1 = "/fql"
SlashCmdList.FOREVERQUESTLOG = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" then
        ns.Toggle()
    elseif msg == "key" then
        ns.db.replaceKey = not ns.db.replaceKey
        appliedKeys = nil
        ns.ApplyBindings()
        ns.Print(ns.db.replaceKey and "L (Toggle Quest Log) now opens this window."
            or "L is back to the game's map quest log.")
    elseif msg == "levels" then
        ns.db.showLevels = not ns.db.showLevels
        ns.MarkDirty(true)
        ns.Print("Quest levels " .. (ns.db.showLevels and "shown." or "hidden."))
    elseif msg == "colors" or msg == "colours" then
        ns.db.colorByLevel = not ns.db.colorByLevel
        ns.MarkDirty(true)
        ns.Print("Difficulty colours " .. (ns.db.colorByLevel and "on." or "off."))
    elseif msg == "hooks" then
        local parts = {}
        for _, hook in ipairs(ns.HookStatus()) do
            parts[#parts + 1] = hook[1] .. " " .. (hook[2] and "|cff20ff20hooked|r" or "|cffff2020not found|r")
        end
        ns.Print("Redirected: " .. table.concat(parts, ", ") .. ".")
    elseif msg == "map" then
        ns.DebugQuestMap()
    elseif msg == "reset" then
        ns.db.point = nil
        ns.ResetPosition()
        ns.Print("Window position reset.")
    else
        ns.Print("/fql - toggle the window")
        ns.Print("/fql key - toggle whether L opens this window")
        ns.Print("/fql levels - toggle [level] prefixes")
        ns.Print("/fql colors - toggle difficulty colours")
        ns.Print("/fql reset - reset the window position")
        ns.Print("/fql hooks - check which quest clicks are being redirected")
    end
end
