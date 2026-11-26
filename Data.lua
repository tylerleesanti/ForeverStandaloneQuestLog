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

-- filter: lower-case search text, or nil. A header is kept if its name matches (then all of its
-- quests show) or if any of its quests match.
function ns.BuildRows(filter)
    ExpandGameHeaders()
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
    return d
end
