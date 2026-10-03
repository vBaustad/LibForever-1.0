--- LibForever-1.0: the YippYapp settings.
-- Every YippYapp setting lives in OUR OWN window (the YippYapp window), because opening Blizzard's
-- Options closes whatever else the player had open. Blizzard's Options > AddOns > YippYapp keeps one
-- page with one button that opens our window.
--
--   LIB.OpenYippYappSettings(id)   open the settings in our window (with id: that addon's settings)
--   LIB.OpenAddonSettings(id)      the same, for one addon
--   LIB.RegisterOptionsPage(id, frame, name, height) -> handle
--       the addon's own settings panel, hosted in our window (name defaults to id). The frame stays
--       the addon's: the lib reparents it in, gives it the window's width, scrolls it when `height`
--       is taller than the room, and runs its OnShow every time it is shown. The handle has
--       :Open(); its GetID() is nil, because these are no longer Blizzard categories - open them
--       with LIB.OpenAddonSettings(id), never Settings.OpenToCategory.
--   LIB.BuildYippYappSettings(host)  the shared settings block, for the window
--   /yippyapp settings             opens it too
--
-- Every control reads its value again whenever the page is shown, so it never shows a stale value
-- after something changed elsewhere (an addon's own page, the launcher's right-click menu).
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 11
if (LIB.settingsVersion or 0) >= VERSION then return end
LIB.settingsVersion = VERSION

local COL_MINIMAP, COL_LAUNCHER = 210, 320   -- the Settings button is right-aligned instead

-- ---------------------------------------------------------------------------
-- The category: one panel, registered once
-- ---------------------------------------------------------------------------
-- A new frame starts out "shown", and Settings only calls Show() on the page it displays. A shown
-- frame's OnShow never fires then, so every page starts hidden and also gets an OnRefresh.
local panel = LIB.settingsPanel
if not panel then
    panel = CreateFrame("Frame")
    panel:Hide()
end
LIB.settingsPanel = panel

-- "Buy me a coffee": WoW can't open a browser, so the button shows the link ready to copy.
local BMC_URL = "buymeacoffee.com/vbaustad"
StaticPopupDialogs["LIBFOREVER_YIPPYAPP_BMC"] = {
    text = "Thanks for using YippYapp!\nCopy the link below if you'd like to buy me a coffee.",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 260,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox  -- the field name differs between client builds
        if not eb then return end
        eb:SetText(BMC_URL)
        eb:HighlightText()
        eb:SetFocus()
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

--- The window's footer has the coffee button; this opens its copyable link.
function LIB.ShowCoffeePopup()
    StaticPopup_Show("LIBFOREVER_YIPPYAPP_BMC")
end

-- ---------------------------------------------------------------------------
-- How wide is my page? (ask, never guess)
-- ---------------------------------------------------------------------------
-- The window sizes a hosted settings page itself, and a page long enough to need a scrollbar gets a
-- scrollbar's width less than one that doesn't. A page that picks its own number is wrong on one of
-- the two, and the symptom is text clipped mid-sentence.
local SCROLLBAR_W = 28
local FALLBACK_W = 572   -- only until the window has published its real width

local function PageWidth()
    return LIB.optionsPageWidth or FALLBACK_W
end

--- The content width your settings page has right now. Before it has ever been shown, the width it
--- is about to get - so lay out from OnOptionsResize rather than once at build time.
function LIB.OptionsWidth(panel)
    local w = (type(panel) == "table" and panel.GetWidth) and panel:GetWidth() or nil
    if w and w > 1 then return math.floor(w + 0.5) end
    -- Not laid out yet. A page that declared a height may end up scrolling, and being 28 pixels too
    -- narrow only wraps a line where being too wide would cut it off, so answer for the scrollbar.
    for _, entry in pairs(LIB.optionsPanels) do
        if entry.frame == panel and entry.height then return PageWidth() - SCROLLBAR_W end
    end
    return PageWidth()
end

--- Lay the page out whenever it has a width: fn(width) runs when the page is shown and again every
--- time the window resizes it, and never twice for the same width. Returns the width it starts with.
function LIB.OnOptionsResize(panel, fn)
    if type(panel) ~= "table" or type(fn) ~= "function" or not panel.HookScript then return nil end
    local last
    local function run()
        local w = LIB.OptionsWidth(panel)
        if w == last then return end
        last = w
        local ok, err = pcall(fn, w)
        if not ok then LIB.Debug("options page resize: %s", tostring(err)) end
    end
    panel:HookScript("OnSizeChanged", run)
    panel:HookScript("OnShow", run)
    if panel:IsShown() then run() end
    return LIB.OptionsWidth(panel)
end

-- The measurements our settings pages share, so six pages don't each invent their own. Advisory: a
-- page with a reason can differ, but matching these is what makes them look like one family.
local METRICS = {
    pad = 8,            -- from the page edge to its content
    indent = 26,        -- a control that belongs under the one above it
    controlX = 200,     -- where a row's control sits, measured from the page's left
    rowHeight = 26,
    gapSection = 16,    -- between blocks
    gapHeading = 18,    -- under a heading
    gapTight = 3,       -- between a control and its own description
    gapBlock = 12,      -- between rows inside a block
}

--- A copy of the house measurements (pad, indent, controlX, rowHeight, gapSection, gapHeading,
--- gapTight, gapBlock). Yours to change: it is a fresh table every time.
function LIB.OptionsMetrics()
    local copy = {}
    for k, v in pairs(METRICS) do copy[k] = v end
    return copy
end

-- ---------------------------------------------------------------------------
-- The help text at the bottom of an addon's settings page
-- ---------------------------------------------------------------------------
-- Every addon explains itself in the same four-or-so headed sections. The addon owns the words; the
-- library owns only where they sit, so six pages cannot drift into six paddings. It goes at the
-- BOTTOM, under the controls: somebody opening settings usually wants the switches, and the help is
-- what they scroll to. Headings stay visible rather than collapsing - a heading you have to click is
-- a heading you do not read.
local HELP_LEFT = 16          -- matches the headings on the shared page
local HELP_HEADING_GAP = 5    -- a heading to its own paragraph
local MIN_WRAP = 180          -- never wrap narrower than this, whatever the page says it is

--- Put an addon's help text at the bottom of its settings page.
---   LIB.AddHelp(panel, { { "What it does", "..." }, { "Getting started", "..." } }, y)
--- y is where to start, in the page's own coordinates (negative, like everything else on a page);
--- it returns the y it finished at, so the page can size itself or carry on below.
--- The text wraps to the page's real width and re-wraps whenever the window resizes it, so no caller
--- has to know how wide the page is. A section with no heading is just a paragraph. Calling it again
--- on the same panel replaces the text rather than drawing a second copy, so it is safe from OnShow.
function LIB.AddHelp(panel, sections, y)
    if type(panel) ~= "table" or type(sections) ~= "table" then return tonumber(y) or 0 end
    local block = panel.libForeverHelp
    if not block then
        block = { rows = {} }
        panel.libForeverHelp = block
    end
    block.top = tonumber(y) or block.top or 0

    local function Layout()
        local m = LIB.OptionsMetrics()
        local wrap = math.max(LIB.OptionsWidth(panel) - HELP_LEFT * 2, MIN_WRAP)
        local at = block.top
        for i, section in ipairs(sections) do
            local row = block.rows[i]
            if not row then
                row = {
                    heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
                    body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
                }
                row.body:SetJustifyH("LEFT")
                row.body:SetSpacing(2)
                block.rows[i] = row
            end
            local heading, body = section[1], section[2]
            row.heading:SetText(heading or "")
            row.heading:ClearAllPoints()
            row.heading:SetPoint("TOPLEFT", HELP_LEFT, at)
            row.heading:SetShown(heading ~= nil and heading ~= "")
            if heading and heading ~= "" then
                at = at - (row.heading:GetStringHeight() or 14) - HELP_HEADING_GAP
            end
            row.body:SetText(body or "")
            row.body:SetWidth(wrap)
            row.body:ClearAllPoints()
            row.body:SetPoint("TOPLEFT", HELP_LEFT, at)
            row.body:SetShown(body ~= nil and body ~= "")
            if body and body ~= "" then
                at = at - (row.body:GetStringHeight() or 14)
            end
            if i < #sections then at = at - m.gapSection end
        end
        -- Sections removed since the last call must not leave their old text behind.
        for i = #sections + 1, #block.rows do
            block.rows[i].heading:SetText("")
            block.rows[i].heading:Hide()
            block.rows[i].body:SetText("")
            block.rows[i].body:Hide()
        end
        block.bottom = at
        return at
    end

    block.Layout = Layout
    if not block.hooked and LIB.OnOptionsResize then
        block.hooked = true
        LIB.OnOptionsResize(panel, function() if block.Layout then block.Layout() end end)
    end
    return Layout()
end

--- How far down an addon's help text reaches, after the last layout: for a page that sizes itself.
function LIB.HelpBottom(panel)
    local block = type(panel) == "table" and panel.libForeverHelp
    return (block and block.bottom) or 0
end

-- A settings panel taller than the room it gets: put it in a scroll frame. The panel becomes the
-- scroll child, sized to the scroll frame's width and the given height. (Used by the window.)
function LIB.PanelScroller(page, height)
    local outer = CreateFrame("Frame")
    outer:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, outer, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_W, 4)
    page:SetParent(scroll)
    page:ClearAllPoints()
    -- The scroll frame has no size until it is anchored in the window, so start at the width this
    -- page will get there: a page that reads its width while building sees the right number.
    page:SetSize(PageWidth() - SCROLLBAR_W, height)
    scroll:SetScrollChild(page)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then page:SetWidth(w) end end)
    page:Show()
    outer.page, outer.scroll = page, scroll
    return outer
end

-- Make sure a panel refreshes whenever it is shown: its own OnShow runs when the frame that is
-- actually shown (the panel, or its scroll wrapper) appears, and again from OnRefresh.
function LIB.PanelRefreshHook(shown, page)
    local function run()
        local onShow = page:GetScript("OnShow")
        if onShow then
            local ok, err = pcall(onShow, page)
            if not ok then LIB.Debug("options page OnShow: %s", tostring(err)) end
        end
    end
    if shown ~= page then shown:HookScript("OnShow", run) end
    if not shown.OnRefresh then shown.OnRefresh = function() run() end end
    shown:Hide()
end

-- Blizzard's Options gets ONE page with ONE button. Opening Blizzard's Options closes the player's
-- other windows, so every YippYapp setting lives in our own window instead.
local function BuildBlizzardPage()
    if panel.built then return end
    panel.built = true
    local emblem = panel:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(36, 36)
    emblem:SetPoint("TOPLEFT", 14, -14)
    if LIB.mediaPath then emblem:SetTexture(LIB.mediaPath .. "yippyapp") end
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 10, -4)
    title:SetText("YippYapp")
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, -64)
    text:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    text:SetJustifyH("LEFT")
    text:SetText("Every YippYapp setting lives in the YippYapp window, so opening them doesn't close "
        .. "what you had open.")
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(200, 24)
    open:SetPoint("TOPLEFT", 16, -104)
    open:SetText("Open YippYapp settings")
    open:SetScript("OnClick", function() LIB.OpenYippYappSettings() end)
end

local function Register()
    if LIB.settingsCategory or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    BuildBlizzardPage()
    local category = Settings.RegisterCanvasLayoutCategory(panel, "YippYapp")
    Settings.RegisterAddOnCategory(category)
    LIB.settingsCategory = category
end
Register()
if not LIB.settingsCategory then LIB.On("PLAYER_LOGIN", function() Register() end) end

--- Open the YippYapp settings in our own window. With an id, on that addon's settings.
function LIB.OpenYippYappSettings(id)
    if LIB.OpenWelcomeSettings then
        LIB.OpenWelcomeSettings(id)
        return
    end
    -- No welcome window in this build: fall back to Blizzard's page (it holds the button).
    Register()
    local category = LIB.settingsCategory
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage("The YippYapp settings can't open during combat.", 1, 0.2, 0.2)
        return
    end
    if category and Settings and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
end

--- Open one addon's settings in our window. Returns false (and says so in the debug log) when that
--- addon has no settings panel registered, so a click can never fail silently.
function LIB.OpenAddonSettings(id)
    if id and not (LIB.optionsPanels and LIB.optionsPanels[id]) then
        LIB.Debug("no settings panel registered for %s", tostring(id))
        LIB.OpenYippYappSettings()   -- the shared settings are better than nothing happening
        return false
    end
    LIB.OpenYippYappSettings(id)
    return true
end

-- ---------------------------------------------------------------------------
-- An addon's own settings panel, hosted in the YippYapp window
--   LIB.RegisterOptionsPage(id, frame, name, height)
-- The frame stays the addon's own; the lib reparents it into the window when that addon's settings
-- are shown, gives it the window's width (and scrolls it when `height` is taller than the room),
-- and runs its OnShow every time it is shown.
-- ---------------------------------------------------------------------------
LIB.optionsPanels = LIB.optionsPanels or {}
LIB.optionsPages = LIB.optionsPages or {}   -- kept: id -> what RegisterOptionsPage returned

function LIB.RegisterOptionsPage(id, frame, name, height)
    if not id or not frame then return nil end
    if LIB.optionsPages[id] then return LIB.optionsPages[id] end
    LIB.optionsPanels[id] = { frame = frame, name = name or id, height = height }
    frame:Hide()
    -- A handle the addon can keep. GetID() is nil on purpose: these pages are not Blizzard
    -- categories any more, so Settings.OpenToCategory must not be called with it.
    local handle = {
        id = id,
        GetID = function() return nil end,
        Open = function() LIB.OpenAddonSettings(id) end,
    }
    LIB.optionsPages[id] = handle
    return handle
end

--- The addon settings the window can show, in the order the sidebar lists them.
function LIB.OptionsPanels()
    local list = {}
    for id, entry in pairs(LIB.optionsPanels) do
        list[#list + 1] = { id = id, name = entry.name, frame = entry.frame, height = entry.height }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Blizzard's page only holds the button; our window draws the settings themselves.
function LIB.YippYappSettingsOnShow()
    BuildBlizzardPage()
end
panel:SetScript("OnShow", function() LIB.YippYappSettingsOnShow() end)
panel.OnRefresh = function() LIB.YippYappSettingsOnShow() end
if panel:IsVisible() then LIB.YippYappSettingsOnShow() end
