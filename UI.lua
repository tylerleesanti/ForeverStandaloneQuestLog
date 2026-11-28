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
local DONE_R, DONE_G, DONE_B = 0.3, 0.3, 0.3

local DQ = "Interface\\QuestFrame\\"
local BTN = "Interface\\Buttons\\"
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

local frame, listScroll, listChild, detailScroll, detailChild
local countText, searchBox, emptyText
local abandonBtn, trackBtn, shareBtn, mapBtn
local rowPool = {}
local rows = {}          -- current flat row data
local selectedQuestID    -- saved per character in ns.db.selectedQuest, so the window reopens on it
local pendingScroll = true -- scroll the remembered quest into view the first time the window opens
local expandAllBtn
local itemBtn, UpdateQuestItem -- the quest item button (Quest item section)
local detailTimer        -- { fontString, timeEnd } for the details pane's "Time left" line
local timerTicker
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

-- Seconds as a clock: 4:05, or 1:04:05 past an hour.
local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

local function TimeLeft(q)
    return q.timeEnd and math.max(0, q.timeEnd - GetTime())
end

-- Daily / Weekly / Repeatable, or nil.
local function FrequencyName(q)
    local F = Enum and Enum.QuestFrequency
    if q.frequency == (F and F.Daily or 1) then return DAILY or "Daily" end
    if q.frequency == (F and F.Weekly or 2) then return WEEKLY or "Weekly" end
    if q.repeatable then return "Repeatable" end
end

-- The right-hand tag, as the classic log shows it: (Failed) / (Complete) / Elite / Dungeon, with
-- (Daily), (Weekly) or (Repeatable) added, and the time left on a timed quest.
local function QuestTag(q)
    if q.failed then return "(" .. (FAILED or "Failed") .. ")" end
    if q.complete then return "(" .. (COMPLETE or "Complete") .. ")" end
    local tag = q.tag
    local freq = FrequencyName(q)
    if freq then tag = tag and (tag .. " (" .. freq .. ")") or ("(" .. freq .. ")") end
    if q.timeEnd then
        local clock = "|cffff6060" .. Clock(TimeLeft(q)) .. "|r"
        tag = tag and (clock .. " " .. tag) or clock
    end
    return tag
end

-- The full tag for a list row: party members on the quest as a count first, then QuestTag.
-- [2] (Complete)
local function RowTag(q)
    local tag = QuestTag(q) or ""
    if q.party and #q.party > 0 then
        tag = ("|cff99ccff[%d]|r%s"):format(#q.party, tag ~= "" and (" " .. tag) or "")
    end
    return tag
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
    local freq = FrequencyName(q)
    if freq then GameTooltip:AddLine(freq .. " quest", 0.6, 0.8, 1) end
    if q.timeEnd and not q.complete and not q.failed then
        GameTooltip:AddLine("Time left: " .. Clock(TimeLeft(q)), 1, 0.4, 0.4)
    end
    if q.failed then
        GameTooltip:AddLine(FAILED or "Failed", 1, 0.2, 0.2)
    elseif q.complete then
        -- A finished quest shows where to hand it in instead of its (all done) objectives.
        GameTooltip:AddLine("Ready to turn in", 0.2, 1, 0.2)
        local hint = ns.TurnInHint(q)
        if hint then GameTooltip:AddLine(hint, 1, 1, 1, true) end
    end
    local objectives = not q.complete and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.questID)
    for _, o in ipairs(objectives or {}) do
        if o.text and o.text ~= "" then
            if o.finished then
                GameTooltip:AddLine("- " .. o.text, 0.5, 0.5, 0.5, true)
            else
                GameTooltip:AddLine("- " .. o.text, 1, 1, 1, true)
            end
        end
    end
    if q.chain then GameTooltip:AddLine("Part of a quest chain", 0.75, 0.75, 0.8) end
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

    -- Chain icon after the name of a quest that's part of a chain (placed in UpdateList).
    row.chain = row:CreateTexture(nil, "ARTWORK")
    row.chain:SetTexture(MEDIA .. "chain")
    row.chain:Hide()

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

    -- Keep the selection if the quest is still listed (it's remembered between sessions), otherwise
    -- fall back to the quest you're super-tracking, then to the first quest.
    local superID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    local found, super, first
    for _, r in ipairs(rows) do
        if not r.isHeader then
            first = first or r
            if r.questID == selectedQuestID then found = r end
            if superID and r.questID == superID then super = r end
        end
    end
    local selected = found or super or first
    selectedQuestID = selected and selected.questID
    if selectedQuestID then ns.db.selectedQuest[ns.CharKey()] = selectedQuestID end

    -- Expand / Collapse all: a minus while any category is open (click closes them all), else a plus.
    local anyOpen = false
    for _, r in ipairs(rows) do
        if r.isHeader and not r.collapsed then anyOpen = true end
    end
    expandAllBtn.collapseAll = anyOpen
    expandAllBtn.icon:SetTexture(BTN .. (anyOpen and "UI-MinusButton-Up" or "UI-PlusButton-Up"))

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
            row.chain:Hide()
            row.text:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
        else
            local cr, cg, cb = QuestColor(r.level)
            row.expand:Hide()
            row.expandGlow:Hide()
            row.watch:SetShown(r.watched)
            row.text:SetFontObject(ns.fonts.name)
            row.text:SetText(QuestLabel(r))
            row.text:SetTextColor(cr, cg, cb)
            row.tag:SetText(RowTag(r))
            row.tag:SetTextColor(cr, cg, cb)
            if r.chain then
                -- The name gives up room for the icon, which sits right after its last letter.
                local size = math.min(11, rowHeight - 4)
                local room = size + 3
                row.text:SetPoint("RIGHT", row.tag, "LEFT", -4 - room, 0)
                local avail = listChild:GetWidth() - 22 - row.tag:GetStringWidth() - 4 - room
                local nameW = math.min(row.text:GetUnboundedStringWidth(), math.max(0, avail))
                row.chain:SetSize(size, size)
                row.chain:ClearAllPoints()
                row.chain:SetPoint("LEFT", row, "LEFT", 20 + nameW + 3, 0)
                row.chain:Show()
            else
                row.chain:Hide()
                row.text:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
            end
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

    -- Scroll the list so the quest is in the middle (or as near as the list allows): the quest being
    -- opened to, or the remembered one the first time the window opens.
    -- Done on the next frame, once the scroll frame has picked up the list's new height.
    local scrollTo = revealQuestID or (pendingScroll and selectedQuestID)
    pendingScroll = false
    if scrollTo then
        for i, r in ipairs(rows) do
            if not r.isHeader and r.questID == scrollTo then
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
        detailLines[i] = fs
    end
    fs:SetFontObject(font)
    fs:SetShadowOffset(0, 0) -- dark text on parchment reads better without the drop shadow
    fs:Show()
    return fs
end

-- Reward item buttons, as the classic log drew them: the icon with its count, and the name in the
-- dark box beside it, two to a row. Hover for the tooltip (Shift compares), Shift-click to
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

    -- The dark box behind the name, with a border in the item's rarity colour. Drawn from plain
    -- colour textures rather than the classic UI-QuestItemNameFrame art: that art is nearly black,
    -- so tinting it can't show a colour, and its border isn't a separate piece that could be tinted.
    local box = CreateFrame("Frame", nil, b)
    box:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 1, -2)
    box:SetSize(102, 33)
    b.box = box
    b.fill = box:CreateTexture(nil, "BACKGROUND")
    b.fill:SetColorTexture(0, 0, 0, 0.6)
    b.edges = {} -- four sides, then four corner pixels (placed by LayoutNameBox)
    for k = 1, 8 do
        local e = box:CreateTexture(nil, "BORDER")
        e:SetColorTexture(1, 1, 1)
        b.edges[k] = e
    end
    b.name = box:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    b.name:SetPoint("TOPLEFT", 6, -2)
    b.name:SetPoint("BOTTOMRIGHT", -4, 2)
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

-- Places the name box's border one screen pixel thick, whatever the UI scale, with rounded
-- corners: each side stops two pixels short of the corner, and a single pixel set in diagonally
-- joins it to the next side. The dark fill sits inside the border, so its corners are cut too.
local function LayoutNameBox(b)
    local p = 1
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        p = PixelUtil.GetNearestPixelSize(1, b.box:GetEffectiveScale(), 1)
    end
    if b.edgePixel == p then return end
    b.edgePixel = p
    b.fill:ClearAllPoints()
    b.fill:SetPoint("TOPLEFT", p, -p)
    b.fill:SetPoint("BOTTOMRIGHT", -p, p)
    local e = b.edges
    for k = 1, 8 do e[k]:ClearAllPoints() end
    e[1]:SetPoint("TOPLEFT", 2 * p, 0);     e[1]:SetPoint("TOPRIGHT", -2 * p, 0);     e[1]:SetHeight(p)
    e[2]:SetPoint("BOTTOMLEFT", 2 * p, 0);  e[2]:SetPoint("BOTTOMRIGHT", -2 * p, 0);  e[2]:SetHeight(p)
    e[3]:SetPoint("TOPLEFT", 0, -2 * p);    e[3]:SetPoint("BOTTOMLEFT", 0, 2 * p);    e[3]:SetWidth(p)
    e[4]:SetPoint("TOPRIGHT", 0, -2 * p);   e[4]:SetPoint("BOTTOMRIGHT", 0, 2 * p);   e[4]:SetWidth(p)
    e[5]:SetPoint("TOPLEFT", p, -p)
    e[6]:SetPoint("TOPRIGHT", -p, -p)
    e[7]:SetPoint("BOTTOMLEFT", p, p)
    e[8]:SetPoint("BOTTOMRIGHT", -p, p)
    for k = 5, 8 do e[k]:SetSize(p, p) end
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
    -- The name sits in the dark box, so it's drawn in the item's rarity colour (grey,
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
    -- The box's border takes the same colour; common (white) items get a softer, half-strength one.
    local plain = r > 0.95 and g > 0.95 and bl > 0.95
    LayoutNameBox(b)
    for _, e in ipairs(b.edges) do e:SetVertexColor(r, g, bl, plain and 0.5 or 1) end
    b.lastShift = nil
    b:Show()
end

-- The info icon at the end of the quest's name on the details page. Hovering it shows what Questie
-- knows about the quest: who gives it, who takes it, its required level and its chain.
local INFO_SIZE = 16
local infoBtn, measureFS

local function ShowQuestInfo(self)
    local qi = self.info
    if not qi then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.title or "Quest info", 1, 0.82, 0)
    for _, row in ipairs({ { "Given by", qi.giver }, { "Turn in to", qi.finisher },
        { "Required level", qi.requiredLevel }, { "Follows", qi.previous }, { "Leads to", qi.nextQuest } }) do
        if row[2] then GameTooltip:AddLine("|cffffd100" .. row[1] .. ":|r " .. row[2], 1, 1, 1, true) end
    end
    if self.questID then
        GameTooltip:AddLine("|cffffd100Quest ID:|r " .. self.questID, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function InfoButton()
    if infoBtn then return infoBtn end
    infoBtn = CreateFrame("Button", nil, detailChild)
    infoBtn:SetSize(INFO_SIZE, INFO_SIZE)
    -- Our own icon (Media/info.tga, made by tools/make_info_icon.py): a gold coin with a dark rim
    -- and a dark "i". The game's InformationIcon is tiny and looked blurry scaled up.
    infoBtn:SetNormalTexture(MEDIA .. "info")
    infoBtn:SetHighlightTexture(MEDIA .. "info")
    local hl = infoBtn:GetHighlightTexture()
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)
    infoBtn:SetScript("OnEnter", ShowQuestInfo)
    infoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return infoBtn
end

-- How wide the last line of a wrapped font string is, so the icon can sit right after it. The game
-- doesn't report line widths, so this redoes the word wrap with a hidden measuring string.
local function LastLineWidth(fs, text, width)
    if not measureFS then
        measureFS = detailChild:CreateFontString(nil, "ARTWORK")
        measureFS:Hide()
    end
    measureFS:SetFontObject(fs:GetFontObject())
    local function w(t) measureFS:SetText(t); return measureFS:GetUnboundedStringWidth() end
    local full = w(text)
    if full <= width then return full end
    local line
    for word in text:gmatch("%S+") do
        local candidate = line and (line .. " " .. word) or word
        if line and w(candidate) > width then line = word else line = candidate end
    end
    return line and w(line) or full
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
        if q.questID and q.questID > 0 then
            -- The info icon at the end of the name: Questie's details (when it's loaded) and the
            -- quest ID. Leave room for it.
            local l = lines[#lines]
            l.info, l.questID, l.width = d.questie or {}, q.questID, textW - INFO_SIZE - 4
        end
        local freq = FrequencyName(q)
        if freq then add(bodyFont, freq .. " quest", 0.1, 0.25, 0.55, 2) end
        if q.timeEnd and not q.complete and not q.failed then
            add(bodyFont, "Time left: " .. Clock(TimeLeft(q)), 0.6, 0.05, 0.05, 2)
            lines[#lines].timeEnd = q.timeEnd -- ticks down every second (see TickTimers)
        end
        if d.objectiveText then add(bodyFont, d.objectiveText, TEXT_R, TEXT_G, TEXT_B, 6) end
        for _, o in ipairs(d.objectives) do
            if o.finished then
                add(bodyFont, "- " .. o.text, DONE_R, DONE_G, DONE_B, 3)
            else
                add(bodyFont, "- " .. o.text, TEXT_R, TEXT_G, TEXT_B, 3)
            end
        end
        -- A finished quest says where to hand it in (in the normal text colour: green on the
        -- parchment was hard to read).
        if d.turnIn then add(bodyFont, d.turnIn, TEXT_R, TEXT_G, TEXT_B, 8) end

        if q.party and #q.party > 0 then
            add(bodyFont, "Party members on this quest: " .. table.concat(q.party, ", "), TEXT_R, TEXT_G, TEXT_B, 6)
        end

        if d.description then
            add(titleFont, QUEST_DESCRIPTION or "Description", TITLE_R, TITLE_G, TITLE_B, 14)
            add(bodyFont, d.description, TEXT_R, TEXT_G, TEXT_B, 6)
        end

        local hasChoices, hasRewards = #d.choices > 0, #d.rewards > 0
        if d.xp or d.money or d.reputation or hasChoices or hasRewards then
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
            -- Reputation (with Questie): one line per faction, "+250 Stormwind", losses too.
            if d.reputation then
                add(bodyFont, (REPUTATION or "Reputation") .. ":", TEXT_R, TEXT_G, TEXT_B, 6)
                for _, rep in ipairs(d.reputation) do
                    local text = ("%s%d %s"):format(rep.amount > 0 and "+" or "", rep.amount, rep.name)
                    if rep.amount > 0 then
                        add(bodyFont, "  " .. text, TEXT_R, TEXT_G, TEXT_B, 2)
                    else
                        add(bodyFont, "  " .. text, 0.55, 0.05, 0.05, 2)
                    end
                end
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
    detailTimer = nil
    local infoShown = false
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
            fs:SetWidth(l.width or textW)
            fs:SetText(l.text)
            fs:SetTextColor(l.r, l.g, l.b)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 4, -y)
            local height = fs:GetStringHeight()
            if l.info then
                -- The info icon, just after the last word of the name, centred on its line.
                local numLines = math.max(1, fs:GetNumLines())
                local lineH = height / numLines
                local b = InfoButton()
                b.info, b.questID, b.title = l.info, l.questID, l.text
                b:ClearAllPoints()
                b:SetPoint("LEFT", detailChild, "TOPLEFT", 4 + LastLineWidth(fs, l.text, l.width) + 4,
                    -(y + (numLines - 0.5) * lineH))
                b:Show()
                infoShown = true
            end
            y = y + height
            if l.timeEnd then detailTimer = { fs, l.timeEnd } end
        end
    end
    for i = numText + 1, #detailLines do detailLines[i]:Hide() end
    if infoBtn and not infoShown then infoBtn:Hide() end
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
    UpdateQuestItem(q)
end

-- Once a second while the window is open: count down the timed quests in the list and on the
-- details page, without rebuilding anything.
local function TickTimers()
    for _, row in ipairs(rowPool) do
        local q = row:IsShown() and row.data
        if q and not q.isHeader and q.timeEnd then row.tag:SetText(RowTag(q)) end
    end
    if detailTimer then
        detailTimer[1]:SetText("Time left: " .. Clock(detailTimer[2] - GetTime()))
    end
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
-- Expand / Collapse all
--
-- The classic log's "All" +/- above the list: closes every category while any is open, otherwise
-- opens them all.
------------------------------------------------------------------------
local function MakeExpandAllButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(44, 20)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT")
    b.icon:SetTexture(BTN .. "UI-MinusButton-Up")
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(b.icon)
    glow:SetTexture(BTN .. "UI-PlusButton-Hilight")
    glow:SetBlendMode("ADD")
    local text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", b.icon, "RIGHT", 2, 0)
    text:SetText(ALL or "All")
    b:SetScript("OnClick", function(self)
        local collapse = self.collapseAll
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and info.isHeader and info.title then
                ns.db.collapsed[info.title] = collapse or nil
            end
        end
        ns.db.collapsed[OTHER or "Other"] = collapse or nil -- the made-up header for quests outside any
        ns.Refresh()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.collapseAll and "Collapse all" or "Expand all")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

------------------------------------------------------------------------
-- Quest item
--
-- For quests with an item to use ("Use the Torch on the Hut"), a button in the bottom bar to use it.
-- Using an item takes a secure action button, and the game won't let an add-on show, hide or move
-- one in combat. A secure button inside this window would also lock the window itself in combat
-- (it couldn't be closed with Escape), so the button belongs to UIParent instead and is only
-- placed over the window: it's taken away as combat starts and comes back when combat ends.
------------------------------------------------------------------------
local function ItemTooltip_Special(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if not (b.logIndex and pcall(GameTooltip.SetQuestLogSpecialItem, GameTooltip, b.logIndex)) and b.link then
        GameTooltip:SetHyperlink(b.link)
    end
    GameTooltip:AddLine("Click to use", 0.2, 1, 0.2)
    GameTooltip:Show()
end

local function UpdateItemCooldown(b)
    if not b.logIndex or not GetQuestLogSpecialItemCooldown then return end
    local ok, start, duration, enable = pcall(GetQuestLogSpecialItemCooldown, b.logIndex)
    if ok and start and CooldownFrame_Set then
        CooldownFrame_Set(b.cooldown, start, duration, enable)
        local grey = duration and duration > 0 and enable == 0
        b.icon:SetVertexColor(grey and 0.4 or 1, grey and 0.4 or 1, grey and 0.4 or 1)
    end
end

local function MakeQuestItemButton()
    local b = CreateFrame("Button", "ForeverQuestLogItemButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(26, 26)
    b:SetFrameStrata(frame:GetFrameStrata())
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "item")
    b:Hide()

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()
    b:SetPushedTexture(BTN .. "UI-Quickslot-Depress")
    b:SetHighlightTexture(BTN .. "ButtonHilight-Square")
    b:GetHighlightTexture():SetBlendMode("ADD")

    -- The item's name, to the left of the button.
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    b.label:SetPoint("RIGHT", b, "LEFT", -6, 0)
    b.label:SetWidth(170)
    b.label:SetJustifyH("RIGHT")
    b.label:SetWordWrap(false)

    b:SetScript("OnEnter", ItemTooltip_Special)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The window raises itself when clicked; keep the button above it.
    b:SetScript("OnUpdate", function(self)
        local level = frame:GetFrameLevel() + 20
        if self:GetFrameLevel() ~= level then self:SetFrameLevel(level) end
    end)
    b:RegisterEvent("PLAYER_REGEN_DISABLED")
    b:RegisterEvent("PLAYER_REGEN_ENABLED")
    b:RegisterEvent("BAG_UPDATE_COOLDOWN")
    b:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- The last moment before combat locks it: take it off the window.
            self:Hide()
            self:ClearAllPoints()
        elseif event == "PLAYER_REGEN_ENABLED" then
            ns.MarkDirty() -- puts it back if the window is still open
        elseif self:IsShown() then
            UpdateItemCooldown(self)
        end
    end)
    return b
end

-- Shows the item of quest q in the bottom bar, or hides the button. Nothing changes in combat.
function UpdateQuestItem(q)
    if not itemBtn or InCombatLockdown() then return end
    local link, texture, charges, showWhenComplete
    if q and q.logIndex and GetQuestLogSpecialItemInfo then
        local ok
        ok, link, texture, charges, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, q.logIndex)
        if not ok then link = nil end
    end
    if not link or (q.complete and not showWhenComplete) or not frame:IsShown() then
        itemBtn:Hide()
        itemBtn.logIndex, itemBtn.link = nil, nil
        return
    end
    local itemID = tonumber(link:match("item:(%d+)"))
    itemBtn:SetAttribute("item", itemID and ("item:" .. itemID) or link)
    itemBtn.logIndex, itemBtn.link = q.logIndex, link
    itemBtn.icon:SetTexture(texture or 134400)
    itemBtn.count:SetText(charges and charges > 1 and charges or "")
    itemBtn.label:SetText(link:match("%[(.-)%]") or "")
    UpdateItemCooldown(itemBtn)
    -- In the bottom bar, left of the Close button.
    itemBtn:ClearAllPoints()
    itemBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -95, 12)
    itemBtn:Show()
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

    -- Expand / Collapse all, the search box and the quest count in the band above the list.
    expandAllBtn = MakeExpandAllButton(frame)
    expandAllBtn:SetPoint("TOPLEFT", 76, -44)

    searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetSize(112, 20)
    searchBox:SetPoint("TOPLEFT", 128, -44)
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

    itemBtn = MakeQuestItemButton()

    frame:SetScript("OnShow", function()
        ns.ApplyPosition()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN or 844)
        if pendingScroll then
            -- First open this session: back to the quest this character last had selected (read
            -- here rather than at load, when the character's name may not be known yet).
            selectedQuestID = selectedQuestID or ns.db.selectedQuest[ns.CharKey()]
        end
        if dirty then ns.Refresh() else UpdateQuestItem(SelectedRow()) end
        if not timerTicker then timerTicker = C_Timer.NewTicker(1, TickTimers) end
    end)
    frame:SetScript("OnHide", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_CLOSE or 845)
        searchBox:ClearFocus()
        if timerTicker then timerTicker:Cancel(); timerTicker = nil end
        if not InCombatLockdown() then itemBtn:Hide() end -- in combat it's already gone
    end)

    ns.ApplySize()
end
