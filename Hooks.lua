local ADDON, ns = ...

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
    local modules = _G.QuestieLoader and QuestieLoader._modules
    local utils = modules and modules.TrackerUtils
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
-- Both trackers can load after this add-on, so try again as add-ons load.
------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function()
    if not ns.db then return end
    HookBlizzardTracker()
    HookQuestie()
end)

-- For /fql debug-style checks.
function ns.HookStatus()
    local n = 0
    for _ in pairs(hookedModules) do n = n + 1 end
    return n, questieHooked
end
