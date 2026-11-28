local _, ns = ...

-- Sends "open the quest log at this quest" clicks from the quest trackers to this window instead of
-- the world map's quest log. Each hook falls back to the original when the setting is off or the
-- quest isn't in the log, so nothing is lost if this window can't show it.

------------------------------------------------------------------------
-- Blizzard's objective tracker (Blizzard_ObjectiveTracker on Forever)
--
-- A plain click on a quest's title runs QuestObjectiveTrackerMixin:OnBlockHeaderClick, which ends in
-- QuestMapFrame_OpenToQuestDetails (opens the map). The method is replaced on the tracker module
-- frame only, never the global QuestMapFrame_OpenToQuestDetails: the world map calls that too, and
-- an add-on replacing it would taint the map for the session. Modified clicks (shift-link,
-- untrack), right-click menus and anything else still go to Blizzard's handler.
------------------------------------------------------------------------
local hookedModules = {}

local function HookTrackerModule(module)
    if not module or hookedModules[module] or type(module.OnBlockHeaderClick) ~= "function" then return end
    hookedModules[module] = true
    local original = module.OnBlockHeaderClick
    module.OnBlockHeaderClick = function(self, block, mouseButton, ...)
        if ns.db.trackerOpensLog and mouseButton ~= "RightButton" and not IsModifiedClick()
            and block and ns.OpenToQuest(block.id) then
            return
        end
        return original(self, block, mouseButton, ...)
    end
end

local function HookBlizzardTracker()
    -- The quest module, plus the campaign module where a client has one (same mixin).
    HookTrackerModule(_G.QuestObjectiveTracker)
    HookTrackerModule(_G.CampaignQuestObjectiveTracker)
end

------------------------------------------------------------------------
-- Questie's tracker
--
-- Questie's quest lines and their right-click "Show in Quest Log" entry both call
-- TrackerUtils:ShowQuestLog(quest). Questie's own replacement on Forever won't open the log in
-- combat; this window can, so that limit doesn't apply here.
------------------------------------------------------------------------
local questieHooked = false

local function HookQuestie()
    if questieHooked then return end
    local utils = ns.QuestieModule("TrackerUtils")
    if not utils or type(utils.ShowQuestLog) ~= "function" then return end
    questieHooked = true
    local original = utils.ShowQuestLog
    utils.ShowQuestLog = function(self, quest, ...)
        if ns.db.trackerOpensLog and quest and ns.OpenToQuest(quest.Id) then
            return
        end
        return original(self, quest, ...)
    end
end

------------------------------------------------------------------------
-- The Quest Log micro button (on the micro menu, which Bartender4 also shows)
--
-- Its click runs ToggleQuestLog, the same as L. When L opens this window, the button does too;
-- in quick keybind mode it keeps the game's handler so the button can still be bound.
------------------------------------------------------------------------
local microHooked = false

local function HookMicroButton()
    local button = _G.QuestLogMicroButton
    if microHooked or not button then return end
    local original = button:GetScript("OnClick")
    if not original then return end
    microHooked = true
    button:SetScript("OnClick", function(self, ...)
        local quickKeybind = KeybindFrames_InQuickKeybindMode and KeybindFrames_InQuickKeybindMode()
        if ns.db.replaceKey and not quickKeybind then
            ns.Toggle()
            return
        end
        return original(self, ...)
    end)
end

------------------------------------------------------------------------
-- Blizzard's quest details pop-up (QuestLogPopupDetailFrame)
--
-- The tracker's right-click "View in Quest Log" entry calls QuestUtil.OpenQuestDetails, which ends
-- in QuestLogPopupDetailFrame:ShowQuest. Like the tracker, the method is replaced on that frame only.
------------------------------------------------------------------------
local popupHooked = false

local function HookPopup()
    local popup = _G.QuestLogPopupDetailFrame
    if popupHooked or not popup or type(popup.ShowQuest) ~= "function" then return end
    popupHooked = true
    local original = popup.ShowQuest
    popup.ShowQuest = function(self, questID, ...)
        if ns.db.trackerOpensLog and ns.OpenToQuest(questID) then
            return
        end
        return original(self, questID, ...)
    end
end

------------------------------------------------------------------------
-- Quest timers (the box timed quests show; Blizzard_QuestTimer)
--
-- Clicking a timer runs QuestTimerButtonMixin:OnClick, which opens the map log (or, in the classic
-- variant, a QuestLogFrame Forever doesn't have). The timer buttons come from a pool and copy the
-- mixin when they're made, so the mixin is changed for buttons made later and any that already
-- exist are changed directly.
------------------------------------------------------------------------
local timerHooked = false

local function TimerQuestID(button)
    if button.questID then return button.questID end
    -- The classic variant keeps a timer index instead of a quest ID.
    local index = GetQuestIndexForTimer and button.GetID and GetQuestIndexForTimer(button:GetID())
    local info = index and C_QuestLog.GetInfo and C_QuestLog.GetInfo(index)
    return info and info.questID
end

local function WrapTimerClick(original)
    return function(self, ...)
        if ns.db.trackerOpensLog and ns.OpenToQuest(TimerQuestID(self)) then
            return
        end
        return original(self, ...)
    end
end

local function HookQuestTimer()
    local mixin = _G.QuestTimerButtonMixin
    if timerHooked or type(mixin) ~= "table" or type(mixin.OnClick) ~= "function" then return end
    timerHooked = true
    local original = mixin.OnClick
    local wrapped = WrapTimerClick(original)
    mixin.OnClick = wrapped
    local timerFrame = _G.QuestTimerFrame
    local pools = timerFrame and timerFrame.pools
    if pools and pools.EnumerateActive then
        for button in pools:EnumerateActive() do
            if button.OnClick == original then button.OnClick = wrapped end
        end
    end
end

------------------------------------------------------------------------
-- The trackers and Blizzard's frames can load after this add-on, so try again as add-ons load.
------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function()
    if not ns.db then return end
    HookBlizzardTracker()
    HookQuestie()
    HookMicroButton()
    HookPopup()
    HookQuestTimer()
end)

-- For /fql hooks.
function ns.HookStatus()
    local n = 0
    for _ in pairs(hookedModules) do n = n + 1 end
    return {
        { "Blizzard tracker", n > 0 },
        { "Questie tracker", questieHooked },
        { "Quest Log button", microHooked },
        { "Quest details pop-up", popupHooked },
        { "Quest timers", timerHooked },
    }
end
