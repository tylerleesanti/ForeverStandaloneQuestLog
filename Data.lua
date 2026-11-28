local ADDON, ns = ...

-- Reads the player's quest log through the modern C_QuestLog API (what the Forever client has;
-- the classic GetQuestLogTitle family does not exist there) and turns it into a flat list of
-- rows for the window: headers, plus the quests under each header that is not collapsed.

local function MaxQuests()
    if C_QuestLog.GetMaxNumQuestsCanAccept then
        local n = C_QuestLog.GetMaxNumQuestsCanAccept()
        if n and n > 0 then return n end
    end
    return MAX_QUESTS or 20
end

local function TagFor(questID)
    if not C_QuestLog.GetQuestTagInfo then return nil end
    local info = C_QuestLog.GetQuestTagInfo(questID)
    return info and info.tagName
end

local function IsWatched(questID)
    if C_QuestLog.GetQuestWatchType then
        return C_QuestLog.GetQuestWatchType(questID) ~= nil
    end
    return false
end

-- The game keeps its own collapse state for headers, and a collapsed header hides its quests
-- from C_QuestLog entirely. This window has its own collapse state instead, so any header the
-- game has collapsed (from the map log) is expanded first, or its quests would be missing here.
local function ExpandGameHeaders()
    if not ExpandQuestHeader then return end
    local n = C_QuestLog.GetNumQuestLogEntries()
    for i = n, 1, -1 do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader and info.isCollapsed then
            ExpandQuestHeader(i)
        end
    end
end

-- Names of the party members who are also on a quest (an empty list when solo or in a raid,
-- where the game only reports party units).
function ns.PartyOnQuest(questID)
    local names = {}
    if not C_QuestLog.IsUnitOnQuest or IsInRaid() then return names end
    for i = 1, GetNumSubgroupMembers() do
        local unit = "party" .. i
        local ok, onQuest = pcall(C_QuestLog.IsUnitOnQuest, unit, questID)
        if ok and onQuest then names[#names + 1] = UnitName(unit) or "?" end
    end
    return names
end

local function IsRepeatable(questID)
    if not C_QuestLog.IsRepeatableQuest then return false end
    local ok, repeatable = pcall(C_QuestLog.IsRepeatableQuest, questID)
    return ok and repeatable or false
end

-- Timed quests: the GetTime() at which the time runs out, or nil. C_QuestLog.GetTimeAllowed is the
-- modern call (as Blizzard's tracker uses it); the classic quest timer list is the fallback.
local function ClassicTimers()
    local ends = {}
    if not GetQuestTimers or not GetQuestIndexForTimer then return ends end
    local ok, timers = pcall(function() return { GetQuestTimers() } end)
    if not ok then return ends end
    for i, seconds in ipairs(timers) do
        local okIndex, logIndex = pcall(GetQuestIndexForTimer, i)
        if okIndex and logIndex and type(seconds) == "number" then ends[logIndex] = GetTime() + seconds end
    end
    return ends
end

local function TimeEnd(questID, logIndex, classicEnds)
    if C_QuestLog.GetTimeAllowed then
        local ok, total, elapsed = pcall(C_QuestLog.GetTimeAllowed, questID)
        if ok and type(total) == "number" and type(elapsed) == "number" and total > 0 and elapsed < total then
            return GetTime() - elapsed + total
        end
    end
    return classicEnds[logIndex]
end

-- filter: lower-case search text, or nil. A header is kept if its name matches (then all of its
-- quests show) or if any of its quests match.
function ns.BuildRows(filter)
    ExpandGameHeaders()
    local classicEnds = ClassicTimers()
    local rows, numQuests = {}, 0
    local header -- the current header row
    local headerMatches = false
    local n = C_QuestLog.GetNumQuestLogEntries()

    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHidden then
            if info.isHeader then
                header = { isHeader = true, title = info.title or "?", count = 0, children = {} }
                headerMatches = not filter or header.title:lower():find(filter, 1, true) ~= nil
                rows[#rows + 1] = header
            else
                numQuests = numQuests + 1
                local q = {
                    logIndex = i,
                    questID = info.questID,
                    title = info.title or "?",
                    level = info.level or 0,
                    suggestedGroup = info.suggestedGroup,
                    tag = TagFor(info.questID),
                    complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID),
                    failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(info.questID),
                    watched = IsWatched(info.questID),
                    party = ns.PartyOnQuest(info.questID),
                    frequency = info.frequency, -- Enum.QuestFrequency: 1 daily, 2 weekly
                    repeatable = IsRepeatable(info.questID),
                    timeEnd = TimeEnd(info.questID, i, classicEnds),
                }
                if not header then -- quests before any header (rare): give them one
                    header = { isHeader = true, title = OTHER or "Other", count = 0, children = {} }
                    headerMatches = not filter
                    rows[#rows + 1] = header
                end
                header.count = header.count + 1
                if headerMatches or q.title:lower():find(filter, 1, true) then
                    header.children[#header.children + 1] = q
                end
            end
        end
    end

    -- Flatten: drop headers with nothing to show, skip children of collapsed headers.
    local flat = {}
    for _, h in ipairs(rows) do
        if #h.children > 0 then
            flat[#flat + 1] = h
            h.collapsed = ns.db.collapsed[h.title] and not filter -- searching always shows matches
            if not h.collapsed then
                for _, q in ipairs(h.children) do flat[#flat + 1] = q end
            end
        end
    end
    return flat, numQuests, MaxQuests()
end

-- Item rewards: "choice" (pick one) or "reward" (always given). An item the client hasn't loaded
-- yet comes back without a name; the window is refreshed once it loads.
local requested = {}

local function RewardItems(kind, questID)
    local count, info
    if kind == "choice" then
        count, info = GetNumQuestLogChoices, GetQuestLogChoiceInfo
    else
        count, info = GetNumQuestLogRewards, GetQuestLogRewardInfo
    end
    local items = {}
    if not count or not info then return items end
    local ok, n = pcall(count, questID, true)
    if not ok or type(n) ~= "number" then return items end
    for i = 1, n do
        local okInfo, name, texture, num, quality, usable, itemID = pcall(info, i, questID)
        if okInfo and (name or texture or itemID) then
            items[#items + 1] = { kind = kind, index = i, questID = questID, name = name, texture = texture,
                count = num, quality = quality, usable = usable, itemID = itemID }
            if not name and itemID and not requested[itemID] and Item and Item.CreateFromItemID then
                requested[itemID] = true
                Item:CreateFromItemID(itemID):ContinueOnItemLoad(function() ns.MarkDirty() end)
            end
        end
    end
    return items
end

------------------------------------------------------------------------
-- Questie's quest database: who gives and takes the quest, where, its required level and chain.
-- Read straight from Questie's modules, all inside pcall: Questie can change between versions,
-- and a missing piece only leaves that line out.
------------------------------------------------------------------------
local function QuestieModule(name)
    local modules = _G.QuestieLoader and QuestieLoader._modules
    return modules and modules[name]
end
ns.QuestieModule = QuestieModule

local function AreaName(areaID)
    if not areaID then return nil end
    local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
    if name and name ~= "" then return name end
    local Z = QuestieModule("ZoneDB")
    local ok, mapID = pcall(function() return Z:GetUiMapIdByAreaId(areaID) end)
    local info = ok and mapID and C_Map.GetMapInfo(mapID)
    return info and info.name
end

-- The nearest NPC or object of a Starts / Finisher list, as "Name (Zone)".
local function NearestPerson(list)
    local DU = QuestieModule("DistanceUtils")
    if not list or not DU then return nil end
    local ok, _, zone, name = pcall(DU.GetNearestFinisherOrStarter, list)
    if not ok or not name then return nil end
    local area = AreaName(zone)
    return area and ("%s (%s)"):format(name, area) or name
end

local function QuestName(DB, questID)
    local ok, name = pcall(DB.QueryQuestSingle, questID, "name")
    return ok and type(name) == "string" and name or nil
end

local questieCache = {}

function ns.QuestieInfo(questID)
    local DB = QuestieModule("QuestieDB")
    if not DB or type(DB.GetQuest) ~= "function" then return nil end
    local ok, quest = pcall(DB.GetQuest, questID)
    if not ok or type(quest) ~= "table" then return nil end
    local info = {}

    -- Giver: an NPC or object, or an item that starts the quest.
    info.giver = NearestPerson(quest.Starts)
    if not info.giver and quest.Starts and type(quest.Starts.Item) == "table" and quest.Starts.Item[1] then
        local okItem, item = pcall(DB.GetItem, DB, quest.Starts.Item[1])
        if okItem and type(item) == "table" and item.name then info.giver = item.name end
    end
    info.finisher = NearestPerson(quest.Finisher)

    if type(quest.requiredLevel) == "number" and quest.requiredLevel > 0 then
        info.requiredLevel = quest.requiredLevel
    end

    -- Chain: the quest before this one (when there's exactly one) and the next one.
    local cached = questieCache[questID]
    if not cached then
        cached = {}
        if type(quest.preQuestSingle) == "table" and #quest.preQuestSingle == 1 then
            cached.previous = QuestName(DB, quest.preQuestSingle[1])
        end
        local nextID = quest.nextQuestInChain
        if type(nextID) == "number" and nextID > 0 then cached.nextQuest = QuestName(DB, nextID) end
        questieCache[questID] = cached
    end
    info.previous, info.nextQuest = cached.previous, cached.nextQuest
    return info
end

-- Reputation rewards, from Questie (the game only reports them for the modern "major" factions).
-- QuestieReputation already applies the bonuses that apply to you (racial, Diplomat and so on).
-- Returns a list of { name, amount }, or nil.
function ns.ReputationRewards(questID)
    local R = QuestieModule("QuestieReputation")
    if not R or type(R.GetReputationReward) ~= "function" then return nil end
    local ok, rewards = pcall(R.GetReputationReward, questID)
    if not ok or type(rewards) ~= "table" then return nil end
    local list = {}
    for _, pair in ipairs(rewards) do
        local factionID, amount = pair[1], pair[2]
        local okName, name = pcall(R.GetFactionName, factionID)
        if okName and type(name) == "string" and type(amount) == "number" and amount ~= 0 then
            list[#list + 1] = { name = name, amount = math.floor(amount + 0.5) }
        end
    end
    return #list > 0 and list or nil
end

-- Where to hand in a finished quest: the game's own completion text ("Return to Elder Bloodhoof in
-- Thunder Bluff.") when it has one, else the nearest turn-in from Questie's database.
-- Returns the text, and true when it came from Questie.
function ns.TurnInHint(q)
    if not q or not q.complete or q.failed then return nil end
    if GetQuestLogCompletionText then
        local ok, text = pcall(GetQuestLogCompletionText, q.logIndex)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    local DB = QuestieModule("QuestieDB")
    if DB and type(DB.GetQuest) == "function" then
        local ok, quest = pcall(DB.GetQuest, q.questID)
        local finisher = ok and type(quest) == "table" and NearestPerson(quest.Finisher)
        if finisher then return "Return to " .. finisher .. ".", true end
    end
end

-- Everything the details pane shows for one quest.
function ns.GetDetails(q)
    local d = { title = q.title, level = q.level, tag = q.tag, objectives = {} }

    -- GetQuestLogQuestText reads the selected quest, so select it first (only when it changes,
    -- so a refresh never re-selects the same quest over and over).
    if not C_QuestLog.GetSelectedQuest or C_QuestLog.GetSelectedQuest() ~= q.questID then
        C_QuestLog.SetSelectedQuest(q.questID)
    end
    if GetQuestLogQuestText then
        local ok, desc, objText = pcall(GetQuestLogQuestText, q.logIndex)
        if ok then
            d.description = type(desc) == "string" and desc or nil
            d.objectiveText = type(objText) == "string" and objText or nil
        end
    end

    local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.questID)
    for _, o in ipairs(objectives or {}) do
        if o.text and o.text ~= "" then
            d.objectives[#d.objectives + 1] = { text = o.text, finished = o.finished }
        end
    end

    if GetQuestLogRewardXP then
        local ok, xp = pcall(GetQuestLogRewardXP, q.questID)
        if ok and type(xp) == "number" and xp > 0 then d.xp = xp end
    end
    if GetQuestLogRewardMoney then
        local ok, money = pcall(GetQuestLogRewardMoney, q.questID)
        if ok and type(money) == "number" and money > 0 then d.money = money end
    end
    d.choices = RewardItems("choice", q.questID)
    d.rewards = RewardItems("reward", q.questID)
    d.questie = ns.QuestieInfo(q.questID)
    d.turnIn, d.turnInFromQuestie = ns.TurnInHint(q)
    d.reputation = ns.ReputationRewards(q.questID)
    return d
end
