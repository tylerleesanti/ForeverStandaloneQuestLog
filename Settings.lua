local ADDON, ns = ...

------------------------------------------------------------------------
-- Fonts
--
-- The window draws with font objects of its own, copied from the game's (so they keep the game's
-- typeface and outline) with only the size changed. Every font string using one of them follows a
-- size change at once; the window then relays itself out for the new line heights.
------------------------------------------------------------------------
local MIN_SIZE, MAX_SIZE = 8, 24

-- key = { the game font it copies, the setting that sizes it }
local FONTS = {
    name   = { "GameFontNormalLeft", "fontName" },   -- quest names in the list
    tag    = { "GameFontNormal",     "fontName" },   -- the Elite / (Complete) tag, sized with the names
    header = { "GameFontNormalLeft", "fontHeader" }, -- area (zone) titles in the list
    body   = { "QuestFont",          "fontText" },   -- quest text on the details page
    title  = { "QuestTitleFont",     "fontText" },   -- headings on the details page, kept larger than the text
}

ns.fonts = {}
local baseSize = {} -- the copied game font's own size, per key

local function BaseFont(name)
    return _G[name] or GameFontNormal
end

-- The size a setting is at when it hasn't been changed: the game font's own size.
function ns.DefaultFontSize(setting)
    for key, f in pairs(FONTS) do
        if f[2] == setting and key ~= "tag" and key ~= "title" then
            return baseSize[key]
        end
    end
end

function ns.FontSize(setting)
    return ns.db[setting] or ns.DefaultFontSize(setting)
end

function ns.ApplyFonts()
    -- First pass: create the font objects and read every base size (the title's size below needs
    -- the body's, and pairs() gives no order).
    for key, f in pairs(FONTS) do
        if not ns.fonts[key] then
            local base = BaseFont(f[1])
            local obj = CreateFont("ForeverQuestLogFont_" .. key)
            obj:CopyFontObject(base)
            ns.fonts[key] = obj
            baseSize[key] = math.floor((select(2, base:GetFont())) + 0.5)
        end
    end
    for key, f in pairs(FONTS) do
        local obj = ns.fonts[key]
        local path, _, flags = BaseFont(f[1]):GetFont()
        local size
        if key == "title" then
            -- headings keep the game's gap over the body text (e.g. 18 over 13)
            size = ns.FontSize("fontText") + (baseSize.title - baseSize.body)
        else
            size = ns.FontSize(f[2])
        end
        obj:SetFont(path, size, flags or "")
    end
end

-- List row height: tall enough for the bigger of the two list fonts.
function ns.RowHeight()
    return math.max(16, math.max(ns.FontSize("fontName"), ns.FontSize("fontHeader")) + 4)
end

------------------------------------------------------------------------
-- Settings panel (opened by the cogwheel, sits beside the window)
------------------------------------------------------------------------
local panel
local widgets = {}
local syncing = false

local function Changed()
    if syncing then return end
    ns.ApplyFonts()
    ns.MarkDirty()
end

-- What a slider edits. Font sliders by default; the window size sliders pass their own.
local FONT_SLIDER = {
    min = MIN_SIZE, max = MAX_SIZE, step = 1,
    default = function(setting) return ns.DefaultFontSize(setting) end,
    apply = Changed,
}

-- Classic options slider: the UI-SliderBar art, label above, low/high labels below, value on the right.
-- The default value is stored as nil, so a later change to the default still carries over.
local function MakeSlider(label, setting, anchor, y, opts)
    opts = opts or FONT_SLIDER
    local MIN_SIZE, MAX_SIZE = opts.min, opts.max
    local s = CreateFrame("Slider", nil, panel, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(160, 17)
    s:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
    s:SetHitRectInsets(0, 0, -10, -10)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(MIN_SIZE, MAX_SIZE)
    s:SetValueStep(opts.step)
    s:SetObeyStepOnDrag(true)

    local text = s:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    text:SetText(label)

    local low = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, 3)
    low:SetText(MIN_SIZE)
    local high = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, 3)
    high:SetText(MAX_SIZE)

    local value = s:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", s, "RIGHT", 10, 0)

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        value:SetText(v)
        if syncing then return end
        ns.db[setting] = (v ~= opts.default(setting)) and v or nil
        opts.apply()
    end)
    s.setting = setting
    s.current = function() return ns.db[setting] or opts.default(setting) end
    widgets[#widgets + 1] = s
    return s
end

local function MakeCheck(label, key, anchor, y, onChange)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -4, y)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        if onChange then onChange() end
        ns.MarkDirty()
    end)
    cb.key = key
    widgets[#widgets + 1] = cb
    return cb
end

local DEFAULT_HEADER_COLOR = { 1, 1, 1 }

local function SetHeaderColor(r, g, b)
    local c = ns.db.headerColor
    c[1], c[2], c[3] = r, g, b
    if widgets.swatch then widgets.swatch.fill:SetColorTexture(r, g, b) end
    ns.MarkDirty()
end

-- A colour swatch that opens the game's colour picker (new SetupColorPickerAndShow API, or the old fields).
local function MakeColorSwatch(label, anchor, y)
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, y)
    text:SetText(label)

    local swatch = CreateFrame("Button", nil, panel)
    swatch:SetSize(20, 20)
    swatch:SetPoint("LEFT", text, "RIGHT", 10, 0)
    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.6, 0.6, 0.6)
    swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
    swatch.fill:SetPoint("TOPLEFT", 2, -2)
    swatch.fill:SetPoint("BOTTOMRIGHT", -2, 2)

    swatch:SetScript("OnClick", function()
        local c = ns.db.headerColor
        local pr, pg, pb = c[1], c[2], c[3]
        local function onChange() SetHeaderColor(ColorPickerFrame:GetColorRGB()) end
        local function onCancel() SetHeaderColor(pr, pg, pb) end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = pr, g = pg, b = pb, hasOpacity = false,
                swatchFunc = onChange, cancelFunc = onCancel,
            })
        else
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.func = onChange
            ColorPickerFrame.cancelFunc = onCancel
            ColorPickerFrame:SetColorRGB(pr, pg, pb)
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)
    widgets.swatch = swatch
    return text
end

local function Sync()
    syncing = true
    for _, w in ipairs(widgets) do
        if w.setting then
            w:SetValue(w.current())
        elseif w.key then
            w:SetChecked(ns.db[w.key] and true or false)
        end
    end
    if widgets.swatch then
        local c = ns.db.headerColor
        widgets.swatch.fill:SetColorTexture(c[1], c[2], c[3])
    end
    syncing = false
end

function ns.ToggleSettings()
    if panel then panel:SetShown(not panel:IsShown()) end
end

-- The panel sits against the window's right edge, so dragging the width slider would move the
-- panel (and the slider under the cursor) with every step. While that slider is held, the panel is
-- pinned to the screen where it is; on release it goes back against the window's new edge.
local settingsWindow

local function AttachPanel()
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", settingsWindow, "TOPRIGHT", -4, -12)
end

local function FreezePanel()
    local left, top = panel:GetLeft(), panel:GetTop()
    if not left or not top then return end
    panel:ClearAllPoints()
    -- GetLeft/GetTop and SetPoint offsets are both in the panel's own scale, so no conversion.
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function ns.CreateSettings(window)
    settingsWindow = window
    panel = CreateFrame("Frame", "ForeverQuestLogSettingsFrame", window, "BackdropTemplate")
    panel:SetSize(270, 530)
    AttachPanel()
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true) -- a wide window could otherwise push it off the right edge
    panel:Hide()
    panel:SetScript("OnShow", Sync)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText(SETTINGS or "Settings")

    local anchor = panel:CreateFontString(nil, "ARTWORK")
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOPLEFT", 26, -44)

    local s1 = MakeSlider("Quest name size", "fontName", anchor, -22)
    local s2 = MakeSlider("Category title size", "fontHeader", s1, -38)
    local s3 = MakeSlider("Quest text size", "fontText", s2, -38)

    -- Window size. The classic size is the default; below the minimums the pages get too narrow to read.
    local function applySize() if not syncing then ns.ApplySize() end end
    local s4 = MakeSlider("Window width", "width", s3, -38, {
        min = 560, max = 1400, step = 10,
        default = function() return ns.DEFAULT_WIDTH end, apply = applySize,
    })
    s4:HookScript("OnMouseDown", FreezePanel)
    s4:HookScript("OnMouseUp", AttachPanel)
    s4:HookScript("OnHide", AttachPanel) -- closed mid-drag
    local s5 = MakeSlider("Window height", "height", s4, -38, {
        min = 360, max = 1000, step = 10,
        default = function() return ns.DEFAULT_HEIGHT end, apply = applySize,
    })

    local c1 = MakeCheck("Show quest levels", "showLevels", s5, -24)
    local c2 = MakeCheck("Colour by difficulty", "colorByLevel", c1, 0)
    c2:SetPoint("TOPLEFT", c1, "BOTTOMLEFT", 0, 2)
    local c3 = MakeCheck("L opens this window", "replaceKey", c2, 0, function() ns.ApplyBindings(true) end)
    c3:SetPoint("TOPLEFT", c2, "BOTTOMLEFT", 0, 2)

    local c4 = MakeCheck("Quest clicks open this window", "trackerOpensLog", c3, 0)
    c4:SetPoint("TOPLEFT", c3, "BOTTOMLEFT", 0, 2)
    local c5 = MakeCheck("Quest tooltips in the list", "listTooltips", c4, 0)
    c5:SetPoint("TOPLEFT", c4, "BOTTOMLEFT", 0, 2)

    MakeColorSwatch("Category title colour", c5, -12)

    local reset = CreateFrame("Button", nil, panel)
    reset:SetSize(140, 21)
    reset:SetPoint("BOTTOM", 0, 18)
    ns.StyleClassicButton(reset, RESET_TO_DEFAULT or "Reset to Default", function()
        ns.db.fontName, ns.db.fontHeader, ns.db.fontText = nil, nil, nil
        local d = DEFAULT_HEADER_COLOR
        ns.db.headerColor = { d[1], d[2], d[3] }
        ns.db.width, ns.db.height = nil, nil
        -- The checkboxes go back to their defaults too.
        for _, w in ipairs(widgets) do
            if w.key and type(ns.defaults[w.key]) == "boolean" then ns.db[w.key] = ns.defaults[w.key] end
        end
        ns.ApplyBindings() -- "L opens this window" may have changed
        Sync()
        ns.ApplyFonts()
        ns.ApplySize()
        ns.MarkDirty()
    end)
end
