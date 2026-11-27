local ADDON, ns = ...

-- Layout and art follow Blizzard's dual-pane Classic quest log (Wrath, Blizzard_UIPanels_Game/Wrath/
-- QuestLogFrame.xml): a 682x447 window on UI-QuestLogDualPane-Left/-RIGHT, quest list on the left
-- page, details on the parchment page on the right, opened at the old left-panel spot (0, -104).
-- These are the sizes at the classic (default) window size; the window can be resized from the
-- settings, which stretches the list and details by the difference (see ns.ApplySize).
local WIDTH, HEIGHT = 682, 447
local LIST_X, LIST_Y, LIST_W, LIST_H = 19, -75, 305, 335
local DETAIL_RIGHT, DETAIL_Y, DETAIL_W, DETAIL_H = -32, -77, 298, 333
local textW = DETAIL_W - 12 -- detail text width inside the scroll pane (follows the window width)
ns.DEFAULT_WIDTH, ns.DEFAULT_HEIGHT = WIDTH, HEIGHT

-- Stretchable art. The classic window is two textures (Left: art x 0-512 of a 512x512 file, RIGHT:
-- art x 512-682 of a 256x512 file), 445 tall. It's cut into a grid: the fixed columns/rows hold the
-- borders, portrait, title bar, the divider between the pages and the button bar, and keep their
-- size; the stretch ones are plain page and parchment, which spread to fill a bigger window.
local ART_COLS = { 0, 70, 300, 380, 620, 682 }   -- art x breaks
local COL_STRETCH = { false, "list", false, "detail", false }
local ART_ROWS = { 0, 80, 400, 445 }             -- art y breaks (from the top)
local ROW_STRETCH = { false, true, false }
local artPieces = {}

-- Parchment text colours (the game's "Parchment" material).
local TITLE_R, TITLE_G, TITLE_B = 0, 0, 0
local TEXT_R, TEXT_G, TEXT_B = 0.18, 0.12, 0.06
local DONE_R, DONE_G, DONE_B = 0.35, 0.35, 0.35

local DQ = "Interface\\QuestFrame\\"
local BTN = "Interface\\Buttons\\"

local frame, listScroll, listChild, detailScroll, detailChild
local countText, searchBox, emptyText
local abandonBtn, trackBtn, shareBtn, mapBtn
local rowPool = {}
local rows = {}          -- current flat row data
local selectedQuestID
local dirty = true
local refreshQueued = false

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function QuestColor(level)
    if ns.db.colorByLevel and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level)
        if c then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

local function QuestLabel(q)
    if ns.db.showLevels and q.level and q.level > 0 then
        return ("[%d] %s"):format(q.level, q.title)
    end
    return q.title
end

-- The right-hand tag, as the classic log shows it: (Failed) / (Complete) / Elite / Dungeon...
local function QuestTag(q)
    if q.failed then return "(" .. (FAILED or "Failed") .. ")" end
    if q.complete then return "(" .. (COMPLETE or "Complete") .. ")" end
    return q.tag
end

-- Money as gold/silver/copper icons. The global GetCoinTextureString is broken on Forever (it calls
-- something that isn't there), so prefer the C_CurrencyInfo version and fall back to plain text.
local function MoneyText(copper)
    for _, fn in ipairs({ C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString, GetMoneyString,
        GetCoinTextureString }) do
        if fn then
            local ok, s = pcall(fn, copper)
            if ok and type(s) == "string" and s ~= "" then return s end
        end
    end
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    return (g > 0 and g .. "g " or "") .. ((g > 0 or s > 0) and s .. "s " or "") .. c .. "c"
end

local function InsertQuestLink(q)
    local link = GetQuestLink and GetQuestLink(q.questID)
    if not link then return end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        ChatFrameUtil.InsertLink(link)
    elseif ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
    end
end

local function ToggleWatch(questID)
    if not C_QuestLog.GetQuestWatchType then return end
    if C_QuestLog.GetQuestWatchType(questID) ~= nil then
        C_QuestLog.RemoveQuestWatch(questID)
    else
        C_QuestLog.AddQuestWatch(questID)
    end
end

------------------------------------------------------------------------
-- Quest list
------------------------------------------------------------------------
local function OnRowClick(row)
    local data = row.data
    if not data then return end
    if data.isHeader then
        ns.db.collapsed[data.title] = not ns.db.collapsed[data.title] or nil
        ns.Refresh()
        return
    end
    if IsShiftKeyDown() then
        InsertQuestLink(data)
        return
    end
    if IsControlKeyDown() then
        ToggleWatch(data.questID)
        return
    end
    selectedQuestID = data.questID
    ns.Refresh()
end

-- The tooltip shown while hovering a quest in the list: its objectives and progress, so quests can
-- be checked without selecting each one, plus who in the party is on it.
local function ShowRowTooltip(row, q)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(QuestLabel(q), QuestColor(q.level))
    if q.failed then
        GameTooltip:AddLine(FAILED or "Failed", 1, 0.2, 0.2)
    elseif q.complete then
        GameTooltip:AddLine("Ready to turn in", 0.2, 1, 0.2)
    end
    local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.questID)
    for _, o in ipairs(objectives or {}) do
        if o.text and o.text ~= "" then
            if o.finished then
                GameTooltip:AddLine("- " .. o.text, 0.5, 0.5, 0.5, true)
            else
                GameTooltip:AddLine("- " .. o.text, 1, 1, 1, true)
            end
        end
    end
    if q.party and #q.party > 0 then
        GameTooltip:AddLine("Party: " .. table.concat(q.party, ", "), 0.6, 0.8, 1, true)
    end
    GameTooltip:Show()
end

-- Hovering a quest brightens its text, as in the classic log; leaving restores its colour.
local function OnRowEnter(row)
    if row.data and not row.data.isHeader then
        row.text:SetTextColor(1, 1, 1)
        row.tag:SetTextColor(1, 1, 1)
        if ns.db.listTooltips then ShowRowTooltip(row, row.data) end
    end
end

local function OnRowLeave(row)
    if row.data and not row.data.isHeader then
        local r, g, b = QuestColor(row.data.level)
        row.text:SetTextColor(r, g, b)
        row.tag:SetTextColor(r, g, b)
    end
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function GetRow(i)
    local row = rowPool[i]
    if row then return row end
    row = CreateFrame("Button", nil, listChild)
    -- height and vertical position are set in UpdateList, since they follow the font size setting
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", OnRowLeave)

    -- Selection bar, tinted with the quest's colour (QuestLogSkillHighlight in the classic log).
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetTexture(DQ .. "UI-QuestLogTitleHighlight")
    row.selected:SetBlendMode("ADD")
    row.selected:Hide()

    -- Header +/- button art, with its hover glow.
    row.expand = row:CreateTexture(nil, "ARTWORK")
    row.expand:SetSize(16, 16)
    row.expand:SetPoint("LEFT", 3, 0)
    row.expandGlow = row:CreateTexture(nil, "HIGHLIGHT")
    row.expandGlow:SetSize(16, 16)
    row.expandGlow:SetPoint("LEFT", 3, 0)
    row.expandGlow:SetTexture(BTN .. "UI-PlusButton-Hilight")
    row.expandGlow:SetBlendMode("ADD")

    -- Tracked check, where the +/- sits on a header.
    row.watch = row:CreateTexture(nil, "ARTWORK")
    row.watch:SetSize(16, 16)
    row.watch:SetPoint("LEFT", 2, 0)
    row.watch:SetTexture(BTN .. "UI-CheckBox-Check")

    row.tag = row:CreateFontString(nil, "ARTWORK")
    row.tag:SetFontObject(ns.fonts.tag)
    row.tag:SetPoint("RIGHT", -2, 0)
    row.tag:SetJustifyH("RIGHT")

    row.text = row:CreateFontString(nil, "ARTWORK")
    row.text:SetFontObject(ns.fonts.name)
    row.text:SetPoint("LEFT", 20, 0)
    row.text:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    rowPool[i] = row
    return row
end

-- Set by ns.OpenToQuest: the quest to bring into view on the next list update.
local revealQuestID

-- Finds the title of the header a quest sits under in the game's log.
local function HeaderTitleFor(questID)
    local title
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                title = info.title
            elseif info.questID == questID then
                return title
            end
        end
    end
end

local function UpdateList()
    if revealQuestID then
        -- Opening to a quest: expand its zone so it is listed (OpenToQuest already cleared the search).
        local header = HeaderTitleFor(revealQuestID)
        if header then ns.db.collapsed[header] = nil end
    end
    local filter = searchBox:GetText()
    filter = filter ~= "" and filter:lower() or nil

    local numQuests, maxQuests
    rows, numQuests, maxQuests = ns.BuildRows(filter)
    countText:SetFormattedText("%s: %d/%d", QUESTS_LABEL or "Quests", numQuests, maxQuests)
    if numQuests >= maxQuests then
        countText:SetTextColor(1, 0.2, 0.2)
    else
        countText:SetTextColor(1, 0.82, 0)
    end

    -- Keep the selection if the quest is still listed, otherwise fall back to the first quest.
    local found, first
    for _, r in ipairs(rows) do
        if not r.isHeader then
            first = first or r
            if r.questID == selectedQuestID then found = r end
        end
    end
    local selected = found or first
    selectedQuestID = selected and selected.questID

    local rowHeight = ns.RowHeight()
    for i, r in ipairs(rows) do
        local row = GetRow(i)
        row.data = r
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)
        row:Show()
        if r.isHeader then
            row.expand:SetTexture(BTN .. (r.collapsed and "UI-PlusButton-Up" or "UI-MinusButton-Up"))
            row.expand:Show()
            row.expandGlow:Show()
            row.watch:Hide()
            row.selected:Hide()
            row.text:SetFontObject(ns.fonts.header)
            row.text:SetText(r.title)
            local hc = ns.db.headerColor
            row.text:SetTextColor(hc[1], hc[2], hc[3])
            row.tag:SetText("")
        else
            local cr, cg, cb = QuestColor(r.level)
            row.expand:Hide()
            row.expandGlow:Hide()
            row.watch:SetShown(r.watched)
            row.text:SetFontObject(ns.fonts.name)
            row.text:SetText(QuestLabel(r))
            row.text:SetTextColor(cr, cg, cb)
            -- Party members on the quest, as a count before the tag: [2] (Complete)
            local tag = QuestTag(r) or ""
            if r.party and #r.party > 0 then
                tag = ("|cff99ccff[%d]|r%s"):format(#r.party, tag ~= "" and (" " .. tag) or "")
            end
            row.tag:SetText(tag)
            row.tag:SetTextColor(cr, cg, cb)
            local isSelected = r.questID == selectedQuestID
            row.selected:SetShown(isSelected)
            if isSelected then row.selected:SetVertexColor(cr, cg, cb) end
        end
    end
    for i = #rows + 1, #rowPool do
        rowPool[i]:Hide()
        rowPool[i].data = nil
    end
    listChild:SetHeight(math.max(1, #rows * rowHeight))

    if revealQuestID then
        -- Scroll the list so the quest is in the middle (or as near as the list allows).
        -- Done on the next frame, once the scroll frame has picked up the list's new height.
        for i, r in ipairs(rows) do
            if r.questID == revealQuestID then
                local target = (i - 1) * rowHeight - (listScroll:GetHeight() - rowHeight) / 2
                local maxScroll = math.max(0, #rows * rowHeight - listScroll:GetHeight())
                local scroll = math.min(math.max(0, target), maxScroll)
                C_Timer.After(0, function() listScroll:SetVerticalScroll(scroll) end)
                break
            end
        end
        revealQuestID = nil
    end
    emptyText:SetShown(#rows == 0)
    if #rows == 0 then
        emptyText:SetText(filter and "No quests match your search."
            or (QUESTLOG_NO_QUESTS_TEXT or "You have no quests."))
    end
    return selected
end

------------------------------------------------------------------------
-- Details pane (dark text on the parchment page)
------------------------------------------------------------------------
local detailLines = {} -- reusable font strings

local function DetailLine(i, font)
    local fs = detailLines[i]
    if not fs then
        fs = detailChild:CreateFontString(nil, "ARTWORK")
        fs:SetWidth(textW)
        fs:SetJustifyH("LEFT")
        fs:SetShadowOffset(0, 0) -- dark text on parchment reads better without the drop shadow
        detailLines[i] = fs
    end
    fs:SetFontObject(font)
    fs:SetShadowOffset(0, 0)
    fs:Show()
    return fs
end

-- Reward item buttons, as the classic log drew them: the icon with its count, and the name on the
-- name-frame tab beside it, two to a row. Hover for the tooltip (Shift compares), Shift-click to
-- link it, Ctrl-click to try it on.
local itemButtons = {}
local ITEM_COL, ITEM_ROW = 147, 44

local function ItemTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetQuestLogItem, GameTooltip, b.item.kind, b.item.index, b.item.questID)
    if not ok then pcall(GameTooltip.SetQuestLogItem, GameTooltip, b.item.kind, b.item.index) end
    if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
    GameTooltip:Show()
end

local function ItemButton(i)
    local b = itemButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, detailChild)
    b:SetSize(ITEM_COL - 4, 40)
    b:RegisterForClicks("LeftButtonUp")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(37, 37)
    b.icon:SetPoint("TOPLEFT", 0, 0)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -2, 2)
    b.count:SetJustifyH("RIGHT")

    local nameFrame = b:CreateTexture(nil, "BACKGROUND")
    b.nameFrame = nameFrame
    nameFrame:SetSize(128, 64)
    nameFrame:SetPoint("LEFT", b.icon, "RIGHT", -10, 0)
    nameFrame:SetTexture(DQ .. "UI-QuestItemNameFrame")
    b.name = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    b.name:SetSize(90, 36)
    b.name:SetPoint("LEFT", nameFrame, "LEFT", 15, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetShadowOffset(1, -1) -- light text on the dark tab reads better with the shadow

    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(b.icon)
    glow:SetTexture(BTN .. "ButtonHilight-Square")
    glow:SetBlendMode("ADD")

    b:SetScript("OnEnter", ItemTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Holding or letting go of Shift while hovering redraws the tooltip with or without the comparison.
    b:SetScript("OnUpdate", function(self)
        if not GameTooltip:IsOwned(self) then return end
        local shift = IsModifiedClick("COMPAREITEMS")
        if shift ~= self.lastShift then
            self.lastShift = shift
            ItemTooltip(self)
        end
    end)
    b:SetScript("OnClick", function(self)
        local link = GetQuestLogItemLink and GetQuestLogItemLink(self.item.kind, self.item.index, self.item.questID)
        if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    itemButtons[i] = b
    return b
end

local function SetItemButton(b, item)
    b.item = item
    b.icon:SetTexture(item.texture or 134400) -- question mark until the item loads
    if item.usable == false then
        b.icon:SetVertexColor(0.9, 0, 0)
    else
        b.icon:SetVertexColor(1, 1, 1)
    end
    b.count:SetText(item.count and item.count > 1 and item.count or "")
    b.name:SetText(item.name or RETRIEVING_ITEM_INFO or "Loading...")
    -- The name sits on the dark name-frame tab, so it's drawn in the item's rarity colour (grey,
    -- white, green, blue, purple...) rather than the parchment's dark ink.
    local r, g, bl = 1, 1, 1
    if item.quality then
        if C_Item and C_Item.GetItemQualityColor then
            r, g, bl = C_Item.GetItemQualityColor(item.quality)
        elseif GetItemQualityColor then
            r, g, bl = GetItemQualityColor(item.quality)
        end
    end
    r, g, bl = r or 1, g or 1, bl or 1
    b.name:SetTextColor(r, g, bl)
    -- The tab behind the name gets a light wash of the same colour: halfway between its own art
    -- (white = untinted) and the rarity colour, so common items keep the plain tab.
    local TINT = 0.5
    b.nameFrame:SetVertexColor(1 - TINT + TINT * r, 1 - TINT + TINT * g, 1 - TINT + TINT * bl)
    b.lastShift = nil
    b:Show()
end

local function UpdateDetails(q)
    local lines = {}
    local titleFont = ns.fonts.title
    local bodyFont = ns.fonts.body
    local function add(font, text, r, g, b, gap)
        lines[#lines + 1] = { font = font, text = text, r = r, g = g, b = b, gap = gap or 4 }
    end

    if q then
        local d = ns.GetDetails(q)
        add(titleFont, d.title, TITLE_R, TITLE_G, TITLE_B, 5)
        if d.objectiveText then add(bodyFont, d.objectiveText, TEXT_R, TEXT_G, TEXT_B, 6) end
        for _, o in ipairs(d.objectives) do
            if o.finished then
                add(bodyFont, "- " .. o.text, DONE_R, DONE_G, DONE_B, 3)
            else
                add(bodyFont, "- " .. o.text, TEXT_R, TEXT_G, TEXT_B, 3)
            end
        end

        -- From Questie's database: who gives and takes the quest, its level and its chain.
        local qi = d.questie
        if qi then
            local gap = 10
            local function info(label, value)
                if value then
                    add(bodyFont, label .. ": " .. value, TEXT_R, TEXT_G, TEXT_B, gap)
                    gap = 2
                end
            end
            info("Given by", qi.giver)
            info("Turn in to", qi.finisher)
            info("Required level", qi.requiredLevel)
            info("Follows", qi.previous)
            info("Leads to", qi.nextQuest)
        end
        if q.party and #q.party > 0 then
            add(bodyFont, "Party members on this quest: " .. table.concat(q.party, ", "), TEXT_R, TEXT_G, TEXT_B, 6)
        end

        if d.description then
            add(titleFont, QUEST_DESCRIPTION or "Description", TITLE_R, TITLE_G, TITLE_B, 14)
            add(bodyFont, d.description, TEXT_R, TEXT_G, TEXT_B, 6)
        end

        local hasChoices, hasRewards = #d.choices > 0, #d.rewards > 0
        if d.xp or d.money or hasChoices or hasRewards then
            add(titleFont, REWARDS or "Rewards", TITLE_R, TITLE_G, TITLE_B, 14)
            if hasChoices then
                add(bodyFont, REWARD_CHOICES or "You will be able to choose one of these rewards:", TEXT_R, TEXT_G, TEXT_B, 6)
                lines[#lines + 1] = { items = d.choices, gap = 4 }
            end
            if hasRewards then
                add(bodyFont, hasChoices and (REWARD_ITEMS or "You will also receive:")
                    or (REWARD_ITEMS_ONLY or "You will receive:"), TEXT_R, TEXT_G, TEXT_B, 6)
                lines[#lines + 1] = { items = d.rewards, gap = 4 }
            end
            if d.xp then
                local xp = BreakUpLargeNumbers and BreakUpLargeNumbers(d.xp) or d.xp
                add(bodyFont, ("Experience: %s"):format(xp), TEXT_R, TEXT_G, TEXT_B, 6)
            end
            if d.money then
                add(bodyFont, "Money: " .. MoneyText(d.money), TEXT_R, TEXT_G, TEXT_B, 4)
            end
        end
    end

    local y = 0
    local numText, numItems = 0, 0
    -- Items per row follow the window width: a column every ITEM_COL, and the last item needs about
    -- ITEM_FIT for its icon and the visible part of its name tab. Two fit at the classic size,
    -- one when the window is made narrower, three or more when it's made much wider.
    local ITEM_FIT = 130
    local cols = math.max(1, math.floor((textW - ITEM_FIT) / ITEM_COL) + 1)
    for _, l in ipairs(lines) do
        y = y + l.gap
        if l.items then
            for k, item in ipairs(l.items) do
                numItems = numItems + 1
                local b = ItemButton(numItems)
                SetItemButton(b, item)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 4 + ((k - 1) % cols) * ITEM_COL, -(y + math.floor((k - 1) / cols) * ITEM_ROW))
            end
            y = y + math.ceil(#l.items / cols) * ITEM_ROW
        else
            numText = numText + 1
            local fs = DetailLine(numText, l.font)
            fs:SetText(l.text)
            fs:SetTextColor(l.r, l.g, l.b)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 4, -y)
            y = y + fs:GetStringHeight()
        end
    end
    for i = numText + 1, #detailLines do detailLines[i]:Hide() end
    for i = numItems + 1, #itemButtons do
        itemButtons[i]:Hide()
        itemButtons[i].item = nil
    end
    detailChild:SetHeight(math.max(1, y + 8))

    -- Bottom buttons follow the selected quest.
    abandonBtn:SetEnabled(q ~= nil)
    trackBtn:SetEnabled(q ~= nil)
    trackBtn:SetText(q and q.watched and (UNTRACK_QUEST_ABBREV or "Untrack") or (TRACK_QUEST_ABBREV or "Track"))
    local canShare = q and IsInGroup() and C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(q.questID)
    shareBtn:SetEnabled(canShare and true or false)
    mapBtn:SetEnabled(q ~= nil)
end

------------------------------------------------------------------------
-- Refresh scheduling
------------------------------------------------------------------------
function ns.Refresh()
    if not frame or not frame:IsShown() then
        dirty = true
        return
    end
    dirty = false
    local selected = UpdateList()
    UpdateDetails(selected)
end

-- Quest events come in bursts; rebuild once on the next frame instead of once per event.
function ns.MarkDirty()
    dirty = true
    if frame and frame:IsShown() and not refreshQueued then
        refreshQueued = true
        C_Timer.After(0, function()
            refreshQueued = false
            if dirty then ns.Refresh() end
        end)
    end
end

function ns.Toggle()
    if not frame then return end
    frame:SetShown(not frame:IsShown())
end

-- Opens the window on a quest: selects it, expands its zone and scrolls it into view. Returns false
-- when the quest isn't in the player's log, so a caller can fall back to the game's own handling.
function ns.OpenToQuest(questID)
    if not frame or not questID then return false end
    local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then return false end
    if searchBox:GetText() ~= "" then searchBox:SetText("") end -- a search could hide the quest
    selectedQuestID = questID
    revealQuestID = questID
    if detailScroll then detailScroll:SetVerticalScroll(0) end
    if frame:IsShown() then
        ns.Refresh()
    else
        dirty = true
        frame:Show() -- OnShow refreshes
    end
    return true
end

-- Where the classic log opened: the left UI panel slot, flush left, 104px below the top.
function ns.ResetPosition()
    ns.db.point = nil
    ns.ApplyPosition()
end

-- Puts the window where it belongs: the spot you dragged it to, or the classic spot. Run on every
-- show, so nothing else (the game's own saved frame layout) can leave it somewhere else.
function ns.ApplyPosition()
    if not frame then return end
    frame:ClearAllPoints()
    local p = ns.db.point
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    end
end

------------------------------------------------------------------------
-- Abandon confirmation
------------------------------------------------------------------------
StaticPopupDialogs.FOREVERQUESTLOG_ABANDON = {
    text = "Abandon \"%s\"?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, questID)
        C_QuestLog.SetSelectedQuest(questID)
        local setAbandon = C_QuestLog.SetAbandonQuest or SetAbandonQuest
        local abandon = C_QuestLog.AbandonQuest or AbandonQuest
        if setAbandon and abandon then
            setAbandon()
            abandon()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

local function SelectedRow()
    for _, r in ipairs(rows) do
        if not r.isHeader and r.questID == selectedQuestID then return r end
    end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
-- Forever's UIPanelButtonTemplate and UIPanelCloseButton are the modern (red, atlas) versions,
-- which don't fit the classic art, so these buttons use the classic textures directly.
local function SetButtonArt(b, normal, pushed, disabled, highlight, l, r, t, bottom)
    for setter, file in pairs({ SetNormalTexture = normal, SetPushedTexture = pushed,
        SetDisabledTexture = disabled, SetHighlightTexture = highlight }) do
        b[setter](b, file)
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local tex = b[getter](b)
        if tex and l then tex:SetTexCoord(l, r, t, bottom) end
    end
    b:GetHighlightTexture():SetBlendMode("ADD")
end

-- Classic red-and-gold panel button art and fonts on an existing button (the settings panel uses it too).
function ns.StyleClassicButton(b, label, onClick)
    SetButtonArt(b, BTN .. "UI-Panel-Button-Up", BTN .. "UI-Panel-Button-Down",
        BTN .. "UI-Panel-Button-Disabled", BTN .. "UI-Panel-Button-Highlight", 0, 0.625, 0, 0.6875)
    b:SetNormalFontObject(GameFontNormal)
    b:SetHighlightFontObject(GameFontHighlight)
    b:SetDisabledFontObject(GameFontDisable)
    b:SetPushedTextOffset(1, -1)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
end

local function MakeButton(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 21)
    ns.StyleClassicButton(b, label, onClick)
    return b
end

-- The classic cogwheel (UI-OptionsButton), left of the close button in the title bar.
------------------------------------------------------------------------
-- Show Map
--
-- Opens the world map on the selected quest's zone, with the quest selected so the map highlights
-- it. Done the way Questie does it on Forever: select the quest, then let the client open the map
-- (C_Map.OpenWorldMap). Calling the map's own Lua (QuestMapFrame_OpenToQuestDetails, or
-- WorldMapFrame:SetMapID) from an add-on taints the map for the session, which later gets its
-- buttons blocked in combat, and the client call is refused in combat anyway.
------------------------------------------------------------------------
local function QuestMapID(questID)
    local id = GetQuestUiMapID and GetQuestUiMapID(questID)
    if (not id or id == 0) and C_QuestLog.GetNextWaypoint then
        id = C_QuestLog.GetNextWaypoint(questID)
    end
    if id and id ~= 0 then return id end
end

local function QuestieModule(name)
    local modules = _G.QuestieLoader and QuestieLoader._modules
    return modules and modules[name]
end

local function MapName(mapID)
    local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or "?"
end

-- Where the map should open for a quest, from Questie's quest database: the zone of the nearest
-- turn-in once the quest is complete, otherwise of the nearest unfinished objective. Read straight
-- from the database rather than through Questie's tracker, whose "show on map" only works for quests
-- its tracker has matched up. `say` (optional) gets a line per step, for /fql map.
-- Returns the uiMapID, and Questie's quest object (for flashing its icons).
local function QuestieQuestMap(questID, say)
    say = say or function() end
    local DB, DU, Z = QuestieModule("QuestieDB"), QuestieModule("DistanceUtils"), QuestieModule("ZoneDB")
    if not (DB and DU and Z) then
        say("Questie: not loaded")
        return nil
    end
    local ok, quest = pcall(DB.GetQuest, questID)
    if not ok or not quest then
        say("Questie: doesn't know quest " .. questID .. (ok and "" or (" (error: " .. tostring(quest) .. ")")))
        return nil
    end
    local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    local okSpawn, spawn, zone
    if complete and quest.Finisher then
        okSpawn, spawn, zone = pcall(DU.GetNearestFinisherOrStarter, quest.Finisher)
        say(("Questie: complete, nearest turn-in: area %s"):format(tostring(okSpawn and zone or spawn)))
    else
        okSpawn, spawn, zone = pcall(DU.GetNearestSpawnForQuest, quest)
        say(("Questie: %s, nearest objective: area %s"):format(complete and "complete (no turn-in data)" or "not complete",
            tostring(okSpawn and zone or spawn)))
    end
    if not okSpawn or not zone then return nil end
    local mapID = Z:GetUiMapIdByAreaId(zone)
    say(("Questie: area %s is map %s (%s)"):format(tostring(zone), tostring(mapID), MapName(mapID)))
    return mapID, quest
end

-- The map to open for a quest: Questie's answer, else the game's own quest map data, else the
-- player's zone.
local function ResolveQuestMap(questID, say)
    say = say or function() end
    local mapID, quest = QuestieQuestMap(questID, say)
    if mapID then return mapID, quest end
    mapID = QuestMapID(questID)
    say(("Game: quest map %s (%s)"):format(tostring(mapID), MapName(mapID)))
    if mapID then return mapID end
    mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    say(("Fallback: your zone, map %s (%s)"):format(tostring(mapID), MapName(mapID)))
    return mapID
end

local function OpenMapToQuest(q)
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage("Can't open the map in combat.", 1, 0.1, 0.1)
        return
    end
    C_QuestLog.SetSelectedQuest(q.questID)
    local mapID, questieQuest = ResolveQuestMap(q.questID)
    if C_Map.OpenWorldMap and mapID then
        C_Map.OpenWorldMap(mapID)
    else
        ToggleWorldMap()
    end
    frame:Hide() -- like the classic button, the map takes over from the log
    -- With Questie, flash the quest's icons on the map so the turn-in or objective stands out.
    local utils = QuestieModule("TrackerUtils")
    if questieQuest and utils and type(utils.FlashFinisher) == "function" then
        pcall(utils.FlashFinisher, utils, questieQuest)
    end
end

-- /fql map: prints how Show Map picks the map for the selected quest.
function ns.DebugQuestMap()
    local q
    for _, r in ipairs(rows) do
        if not r.isHeader and r.questID == selectedQuestID then q = r end
    end
    if not q then
        ns.Print("Select a quest in the window first.")
        return
    end
    ns.Print(("Show Map for \"%s\" (quest %d):"):format(q.title, q.questID))
    local mapID = ResolveQuestMap(q.questID, function(line) ns.Print("  " .. line) end)
    ns.Print(("  Opens map %s (%s)"):format(tostring(mapID), MapName(mapID)))
end

-- The classic "Show Map" button: the label, then the little map picture (UI-QuestMap_Button's top
-- half is the normal state, the bottom half pressed).
local function MakeMapButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(32)
    local art = b:CreateTexture(nil, "ARTWORK")
    art:SetSize(48, 32)
    art:SetPoint("RIGHT")
    art:SetTexture(DQ .. "UI-QuestMap_Button")
    art:SetTexCoord(0.125, 0.875, 0, 0.5)
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(art)
    glow:SetTexture(DQ .. "UI-QuestMap_Button")
    glow:SetTexCoord(0.125, 0.875, 0, 0.5)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.4)

    local text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("RIGHT", art, "LEFT", 2, 0)
    text:SetText(SHOW_MAP or "Show Map")
    b:SetWidth(48 + text:GetStringWidth())

    b:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then art:SetTexCoord(0.125, 0.875, 0.5, 1) end
    end)
    b:SetScript("OnMouseUp", function() art:SetTexCoord(0.125, 0.875, 0, 0.5) end)
    b:SetScript("OnClick", function()
        for _, r in ipairs(rows) do
            if not r.isHeader and r.questID == selectedQuestID then return OpenMapToQuest(r) end
        end
    end)
    b:SetScript("OnEnable", function()
        art:SetDesaturated(false)
        text:SetFontObject(GameFontNormal)
    end)
    b:SetScript("OnDisable", function()
        art:SetDesaturated(true)
        text:SetFontObject(GameFontDisable)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SHOW_MAP or "Show Map")
        GameTooltip:AddLine("Open the world map where this quest takes you next: the turn-in once it's complete, otherwise its objectives (with Questie).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function MakeCogButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b:SetNormalTexture(BTN .. "UI-OptionsButton")
    b:SetPushedTexture(BTN .. "UI-OptionsButton")
    b:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
    b:SetHighlightTexture(BTN .. "UI-OptionsButton")
    b:GetHighlightTexture():SetBlendMode("ADD")
    b:SetScript("OnClick", function() ns.ToggleSettings() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SETTINGS or "Settings")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function MakeCloseButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 32)
    SetButtonArt(b, BTN .. "UI-Panel-MinimizeButton-Up", BTN .. "UI-Panel-MinimizeButton-Down",
        BTN .. "UI-Panel-MinimizeButton-Disabled", BTN .. "UI-Panel-MinimizeButton-Highlight")
    b:SetScript("OnClick", function() parent:Hide() end)
    return b
end

------------------------------------------------------------------------
-- Window size
------------------------------------------------------------------------
-- Cuts the classic art into the ART_COLS x ART_ROWS grid and places each piece, stretching the
-- "list" and "detail" columns by their share of the extra width and the middle row by the extra height.
local function LayoutArt(extraList, extraDetail, extraH)
    local extra = { list = extraList, detail = extraDetail }
    local used = 0
    local destY = 0
    for r = 1, #ART_ROWS - 1 do
        local ya, yb = ART_ROWS[r], ART_ROWS[r + 1]
        local h = (yb - ya) + (ROW_STRETCH[r] and extraH or 0)
        local destX = 0
        for c = 1, #ART_COLS - 1 do
            local xa, xb = ART_COLS[c], ART_COLS[c + 1]
            local w = (xb - xa) + (COL_STRETCH[c] and extra[COL_STRETCH[c]] or 0)
            -- A column crossing art x 512 takes its two halves from the two files.
            for _, part in ipairs({ { 0, 512, "UI-QuestLogDualPane-Left", 512 }, { 512, 682, "UI-QuestLogDualPane-RIGHT", 256 } }) do
                local s, e = math.max(xa, part[1]), math.min(xb, part[2])
                if e > s then
                    used = used + 1
                    local tex = artPieces[used]
                    if not tex then
                        tex = frame:CreateTexture(nil, "BORDER")
                        if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
                        if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
                        artPieces[used] = tex
                    end
                    local scale = w / (xb - xa)
                    tex:SetTexture(DQ .. part[3])
                    tex:SetTexCoord((s - part[1]) / part[4], (e - part[1]) / part[4], ya / 512, yb / 512)
                    tex:ClearAllPoints()
                    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", destX + (s - xa) * scale, -destY)
                    tex:SetSize((e - s) * scale, h)
                    tex:Show()
                end
            end
            destX = destX + w
        end
        destY = destY + h
    end
    for i = used + 1, #artPieces do artPieces[i]:Hide() end
end

-- Applies the saved size: frame, art, list and details. Extra width is shared between the two pages.
function ns.ApplySize()
    if not frame then return end
    local width = ns.db.width or WIDTH
    local height = ns.db.height or HEIGHT
    local extraW, extraH = width - WIDTH, height - HEIGHT
    local extraList = math.floor(extraW / 2)
    local extraDetail = extraW - extraList

    frame:SetSize(width, height)
    LayoutArt(extraList, extraDetail, extraH)

    local listW = LIST_W + extraList
    listScroll:SetSize(listW, LIST_H + extraH)
    listChild:SetWidth(listW)
    countText:ClearAllPoints()
    countText:SetPoint("TOPRIGHT", frame, "TOPLEFT", LIST_X + listW, -48)

    local detailW = DETAIL_W + extraDetail
    detailScroll:SetSize(detailW, DETAIL_H + extraH)
    detailChild:SetWidth(detailW)
    textW = detailW - 12
    for _, fs in ipairs(detailLines) do fs:SetWidth(textW) end

    ns.MarkDirty()
end

------------------------------------------------------------------------
-- Position lock
------------------------------------------------------------------------
local lockBtn

local function UpdateLockButton()
    if not lockBtn then return end
    local state = ns.db.locked and "Locked" or "Unlocked"
    lockBtn:SetNormalTexture(BTN .. "LockButton-" .. state .. "-Up")
    lockBtn:SetPushedTexture(BTN .. "LockButton-" .. state .. "-Up")
    lockBtn:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
end

local function ShowLockTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.db.locked and "Position locked" or "Position unlocked")
    GameTooltip:AddLine("Left-click: " .. (ns.db.locked and "unlock" or "lock") .. " the window's position", 1, 1, 1)
    GameTooltip:AddLine("Right-click: move it back to the left side of the screen", 1, 1, 1)
    GameTooltip:Show()
end

local function MakeLockButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 32) -- same as the close button; the padlock art has padding built in, so smaller looks squished
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHighlightTexture(BTN .. "UI-Panel-MinimizeButton-Highlight")
    b:GetHighlightTexture():SetBlendMode("ADD")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ns.ResetPosition()
        else
            ns.db.locked = not ns.db.locked
            UpdateLockButton()
        end
        if GameTooltip:IsOwned(self) then ShowLockTooltip(self) end
    end)
    b:SetScript("OnEnter", ShowLockTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lockBtn = b
    UpdateLockButton()
    return b
end

function ns.CreateWindow()
    frame = CreateFrame("Frame", "ForeverQuestLogFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Dragging marks a named frame "user placed", and the game then restores it from its own
        -- layout file (WTF\...\layout-local.txt), overriding this add-on. The position is kept in
        -- ForeverQuestLogDB instead, so the game's copy is switched off.
        self:SetUserPlaced(false)
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.point = { point, relPoint, x, y }
    end)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetUserPlaced(false) -- drops the game's old saved copy from layout-local.txt at next logout
    frame:Hide()
    tinsert(UISpecialFrames, "ForeverQuestLogFrame") -- Escape closes it
    ns.ApplyPosition()

    -- Art: the book portrait sits under the frame art, which has a round hole for it.
    local book = frame:CreateTexture(nil, "BACKGROUND")
    book:SetSize(64, 64)
    book:SetPoint("TOPLEFT", 3, -4)
    book:SetTexture(DQ .. "UI-QuestLog-BookIcon")

    -- Frame art: built (and rebuilt on resize) by LayoutArt.

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetSize(300, 14)
    title:SetPoint("TOP", 0, -15)
    title:SetText(QUEST_LOG or "Quest Log")

    local close = MakeCloseButton(frame)
    close:SetPoint("TOPRIGHT", 2, -8)

    -- Cogwheel just left of the X, centred on the same line (the X's centre is 24px down).
    local cog = MakeCogButton(frame)
    cog:SetPoint("RIGHT", close, "LEFT", 2, 0)
    ns.CreateSettings(frame)

    -- Padlock left of the cogwheel.
    local lock = MakeLockButton(frame)
    lock:SetPoint("RIGHT", cog, "LEFT", 4, 0) -- overlaps its own transparent padding, so the gap matches the cog's

    -- Show Map, where the classic dual-pane log had it (QuestLogFrameShowMapButton: TOPRIGHT -25, -38).
    mapBtn = MakeMapButton(frame)
    mapBtn:SetPoint("TOPRIGHT", -25, -38)

    -- Search box and quest count in the band above the list.
    searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("TOPLEFT", 80, -44)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function() ns.Refresh() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local searchHint = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    searchHint:SetPoint("LEFT", 2, 0)
    searchHint:SetText(SEARCH or "Search")
    searchBox:HookScript("OnTextChanged", function(self) searchHint:SetShown(self:GetText() == "") end)

    countText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    countText:SetJustifyH("RIGHT")

    -- Quest list (left page). Sizes are set in ns.ApplySize.
    listScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", LIST_X, LIST_Y)
    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetHeight(1)
    listScroll:SetScrollChild(listChild)

    emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    emptyText:SetWidth(200)
    emptyText:SetPoint("CENTER", listScroll, "CENTER", -6, 16)

    -- Details (right parchment page)
    detailScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPRIGHT", DETAIL_RIGHT, DETAIL_Y)
    detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetHeight(1)
    detailScroll:SetScrollChild(detailChild)

    -- Bottom buttons: Abandon | Share | Track along the left, Close on the right. The classic
    -- log widens and lifts this bar when docked in the dual-pane window (QuestLogControlPanel_UpdatePosition).
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetSize(307, 26)
    panel:SetPoint("BOTTOMLEFT", 18, 11)

    abandonBtn = MakeButton(panel, ABANDON_QUEST_ABBREV or "Abandon", 110, function()
        local q = SelectedRow()
        if q then
            local dialog = StaticPopup_Show("FOREVERQUESTLOG_ABANDON", q.title)
            if dialog then dialog.data = q.questID end
        end
    end)
    abandonBtn:SetPoint("LEFT", 0, 1)

    trackBtn = MakeButton(panel, TRACK_QUEST_ABBREV or "Track", 100, function()
        local q = SelectedRow()
        if q then ToggleWatch(q.questID) end
    end)
    trackBtn:SetPoint("RIGHT", -3, 1)

    shareBtn = MakeButton(panel, SHARE_QUEST_ABBREV or "Share", 1, function()
        local q = SelectedRow()
        if q then
            C_QuestLog.SetSelectedQuest(q.questID)
            QuestLogPushQuest()
        end
    end)
    shareBtn:SetPoint("LEFT", abandonBtn, "RIGHT")
    shareBtn:SetPoint("RIGHT", trackBtn, "LEFT")

    local closeBtn = MakeButton(frame, CLOSE or "Close", 80, function() frame:Hide() end)
    closeBtn:SetHeight(22)
    closeBtn:SetPoint("BOTTOMRIGHT", -7, 14)

    frame:SetScript("OnShow", function()
        ns.ApplyPosition()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN or 844)
        if dirty then ns.Refresh() end
    end)
    frame:SetScript("OnHide", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_CLOSE or 845)
        searchBox:ClearFocus()
    end)

    ns.ApplySize()
end
