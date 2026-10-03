--- LibForever-1.0: the YippYapp window.
-- One window for every YippYapp addon, and the home of every YippYapp setting: Blizzard's own Options
-- closes whatever else the player had open, so the page it gets holds nothing but a button that opens
-- this. A sidebar lists the addons that have a settings page; picking one shows it. That is the whole
-- window now.
--
--   LIB.OpenYippYappSettings(id)   open it (Settings.lua); with an id, straight to that addon
--   LIB.OpenAddonSettings(id)      the same, by addon
--   LIB.OpenAddon(id)              open an ADDON, through the click its minimap button registered
--   /yippyapp                      opens it too; /yippyapp test runs the self-tests
--
-- The file is still called Welcome.lua because all six addons name it in their TOC, and WoW skips a
-- TOC entry whose file is missing WITHOUT a word of warning - six addons would lose this window and
-- the first symptom would be a minimap click doing nothing. Renaming it means moving six TOC lines in
-- the same breath, which is a separate, deliberate step, not a tidy-up.
--
-- WHAT WAS HERE BEFORE: a welcome window - a home page of cards, a page per addon, a beta banner, and
-- machinery that decided when to open itself. It is gone. Each addon's own words moved onto its
-- settings page through LIB.AddHelp, which is where somebody looking for help actually goes, and the
-- "seen" state that only ever existed to decide whether to pop up went with it. The entry points
-- stay, doing nothing, at the bottom of this file: a published addon still calls them.
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 21
if (LIB.welcomeVersion or 0) >= VERSION then return end
LIB.welcomeVersion = VERSION

-- An older copy of this file already built the window: retire it.
if LIB.welcomeFrame then
    LIB.welcomeFrame:SetScript("OnHide", nil)
    LIB.welcomeFrame:Hide()
    LIB.welcomeFrame = nil
end

local win           -- the window, built on first open

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local Close, ShowSettings, OpenAddon

-- An addon's emblem, taken from the minimap button it registered: now that the welcome pages and the
-- launcher are gone, that registration is the one record an addon still keeps of itself.
local function SetIcon(tex, id)
    local b = LIB.minimapButtons and LIB.minimapButtons[id]
    local icon = b and b.opts and b.opts.icon
    tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetVertexColor(1, 1, 1, 1)
end

--- Open an addon the way the family agreed: its own main window, and when it has none, its settings.
--- The minimap row and the addons themselves come through here. The click comes from the addon's
--- minimap button, because after the welcome pages and the launcher went that is the only place left
--- saying how an addon opens - so an addon that registers a minimap button needs nothing else.
function LIB.OpenAddon(id)
    local hasPanel = LIB.optionsPanels and LIB.optionsPanels[id]
    local b = LIB.minimapButtons and LIB.minimapButtons[id]
    local click = b and b.opts and b.opts.OnClick
    if not click then
        -- No way in of its own: its settings are the sensible landing place.
        if hasPanel and LIB.OpenAddonSettings then return LIB.OpenAddonSettings(id) end
        return
    end
    if win then win:Hide() end
    local ok, err = pcall(click, b.button or b.object, "LeftButton")
    if not ok then LIB.Debug("open %s: %s", tostring(id), tostring(err)) end
end
OpenAddon = LIB.OpenAddon

-- The window's own size. The page it hosts keeps the width it was drawn for, and the sidebar sits
-- beside it, so the window is as wide as both.
local W, H = 620, 520
local PAGE_W = W - 48
-- The width a settings page hosted here is given. Published so no page has to guess it;
-- LIB.OptionsWidth(panel) is what an addon asks (Settings.lua).
LIB.optionsPageWidth = PAGE_W
local SIDEBAR_W = 168
local WIN_W = 24 + SIDEBAR_W + 12 + PAGE_W + 24
local TOTAL_H = H
local PAGE_TOP = -40          -- where a hosted settings page starts
local BOTTOM_BAR = 46         -- the button row along the bottom

-- ---------------------------------------------------------------------------
-- The sidebar on an addon page: hop between addons without going home first
-- ---------------------------------------------------------------------------
local function SideButton(i)
    local b = win.sideButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, win.sideHost)
    b:SetSize(SIDEBAR_W - 26, 26)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 6, 0)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.name:SetPoint("RIGHT", -4, 0)
    b.name:SetJustifyH("LEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0.30, 0.12)
    b:SetScript("OnClick", function(self) ShowSettings(self.id) end)
    win.sideButtons[i] = b
    return b
end

-- One row per addon with a settings page. There is no shared YippYapp row any more: the settings
-- that were on it went with the launcher, and the one that was left - grouping the minimap buttons -
-- is now simply how it works.
local function LayoutSidebar(currentId)
    local rows = {}
    for _, entry in ipairs(LIB.OptionsPanels and LIB.OptionsPanels() or {}) do
        rows[#rows + 1] = { id = entry.id, name = entry.name }
    end
    for _, b in ipairs(win.sideButtons) do b:Hide() end
    for i, row in ipairs(rows) do
        local b = SideButton(i)
        b.id = row.id
        SetIcon(b.icon, row.id)
        b.name:SetText(row.name)
        local current = row.id == currentId
        b.name:SetTextColor(current and 1 or 0.85, current and 0.82 or 0.85, current and 0.30 or 0.85)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
        b:Show()
    end
    win.sideHost:SetHeight(math.max(1, #rows * 28))
    return #rows
end

-- A scroll frame only needs its bar when the content is taller than the room. Hiding it when it is
-- not needed keeps a short sidebar from looking like it has more below.
local function ScrollBarOf(scroll)
    if scroll.libForeverBar then return scroll.libForeverBar end
    for _, child in ipairs({ scroll:GetChildren() }) do
        if child.IsObjectType and child:IsObjectType("Slider") then
            scroll.libForeverBar = child
            return child
        end
    end
end

local function FitScroll(scroll, host)
    local bar = ScrollBarOf(scroll)
    if not bar then return end
    local needed = (host:GetHeight() or 0) > (scroll:GetHeight() or 0) + 1
    bar:SetShown(needed)
    if not needed then scroll:SetVerticalScroll(0) end
end

-- ---------------------------------------------------------------------------
-- Building the window
-- ---------------------------------------------------------------------------
local function Build()
    win = CreateFrame("Frame", "LibForeverWelcome", UIParent, "SettingsFrameTemplate")
    LIB.welcomeFrame = win
    win:SetSize(WIN_W, TOTAL_H)
    win:SetPoint("CENTER", 0, 40)
    win:Hide()
    local bg = win:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 7, -18)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetAtlas("heavybronze-frame-background")
    if win.Bg then win.Bg:Hide() end
    -- Toplevel, draggable, Escape, and placed beside our other open windows. No saved table of
    -- its own, so it starts fresh each session.
    if LIB.RegisterWindow then
        LIB.RegisterWindow(win)
    else
        win:SetFrameStrata("HIGH")
        win:SetClampedToScreen(true)
        win:EnableMouse(true)
        win:SetMovable(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        tinsert(UISpecialFrames, "LibForeverWelcome")
    end

    win.sideButtons = {}

    win.side = CreateFrame("Frame", nil, win)
    win.side:SetPoint("TOPLEFT", 24, PAGE_TOP)
    win.side:SetPoint("BOTTOMLEFT", 24, BOTTOM_BAR)
    win.side:SetWidth(SIDEBAR_W)
    local sideScroll = CreateFrame("ScrollFrame", nil, win.side, "UIPanelScrollFrameTemplate")
    win.sideScroll = sideScroll
    sideScroll:SetPoint("TOPLEFT", 0, 0)
    sideScroll:SetPoint("BOTTOMRIGHT", -24, 0)
    win.sideHost = CreateFrame("Frame", nil, sideScroll)
    win.sideHost:SetSize(SIDEBAR_W - 26, 10)
    sideScroll:SetScrollChild(win.sideHost)

    -- Where an addon's own settings panel (or the shared settings) is hosted.
    win.settingsHost = CreateFrame("Frame", nil, win)
    win.settingsHost:SetPoint("TOPLEFT", 24 + SIDEBAR_W + 12, PAGE_TOP)
    win.settingsHost:SetSize(PAGE_W, TOTAL_H + PAGE_TOP - BOTTOM_BAR - 8)
    win.settingsHost:Hide()

    -- A thin line so the sidebar and the content read as two areas.
    win.sideDivider = win:CreateTexture(nil, "ARTWORK")
    win.sideDivider:SetColorTexture(0.55, 0.50, 0.42, 0.5)
    win.sideDivider:SetWidth(1)
    win.sideDivider:SetPoint("TOPLEFT", 24 + SIDEBAR_W + 4, PAGE_TOP + 4)
    win.sideDivider:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 24 + SIDEBAR_W + 4, BOTTOM_BAR + 6)
    win.sideDivider:Hide()

    -- The bottom row, on both views: where the shared settings are, and Done.
    win.done = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.done:SetSize(96, 22)
    win.done:SetPoint("BOTTOMRIGHT", -16, 14)
    win.done:SetText(DONE or "Done")
    win.done:SetScript("OnClick", function() win:Hide() end)

    -- Buy me a coffee: a line you can read, on the left of the footer, not a bare icon nobody
    -- recognises at 22 pixels. It says what it is, so it needs no tooltip to be understood.
    win.coffee = CreateFrame("Button", nil, win)
    win.coffee:SetHeight(24)
    local logo = win.coffee:CreateTexture(nil, "ARTWORK")
    logo:SetSize(18, 18)
    logo:SetPoint("LEFT", 0, 0)
    if LIB.mediaPath then logo:SetTexture(LIB.mediaPath .. "bmc-logo") end
    logo:SetAlpha(0.8)
    local coffeeText = win.coffee:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coffeeText:SetPoint("LEFT", logo, "RIGHT", 7, 0)
    coffeeText:SetText("Buy me a coffee")
    coffeeText:SetTextColor(0.82, 0.68, 0.38)
    local function FitCoffee()
        win.coffee:SetWidth(18 + 7 + math.max(coffeeText:GetStringWidth() or 90, 60))
    end
    FitCoffee()
    win.coffee:HookScript("OnShow", FitCoffee)   -- the string has no width until it is drawn
    win.coffee:SetPoint("BOTTOMLEFT", 24, 13)
    win.coffee:SetScript("OnEnter", function(self)
        logo:SetAlpha(1)
        coffeeText:SetTextColor(1, 0.85, 0.4)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Click to copy the link.", 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    win.coffee:SetScript("OnLeave", function()
        logo:SetAlpha(0.8)
        coffeeText:SetTextColor(0.82, 0.68, 0.38)
        GameTooltip:Hide()
    end)
    win.coffee:SetScript("OnClick", function()
        if LIB.ShowCoffeePopup then LIB.ShowCoffeePopup() end
    end)

    win.footerRule = win:CreateTexture(nil, "ARTWORK")
    win.footerRule:SetAtlas("Options_HorizontalDivider")
    win.footerRule:SetHeight(1)
    win.footerRule:SetPoint("BOTTOMLEFT", 18, BOTTOM_BAR + 2)
    win.footerRule:SetPoint("RIGHT", win, "RIGHT", -20, 0)

    -- HookScript: RegisterWindow already hooked OnHide for Escape; SetScript would drop that.
    win:HookScript("OnHide", function() Close() end)
end

-- ---------------------------------------------------------------------------
-- Showing the three views: the home page, an addon's page, and settings
-- ---------------------------------------------------------------------------
local function Prepare()
    if not win then Build() end
    -- Opened from the Settings panel: show above it rather than closing it (closing Blizzard's
    -- Settings from addon code is forbidden; see Settings.lua).
    local overSettings = SettingsPanel and SettingsPanel:IsShown()
    win:SetFrameStrata(overSettings and "FULLSCREEN_DIALOG" or "HIGH")
    win:Show()
    win:Raise()
end

-- One view is left - an addon's settings page - but it still goes through here, so the next view
-- someone adds cannot leave this one's frames on screen.
local function SetView()
    Prepare()                       -- builds the window the first time, and brings it up
    win.mode = "settings"
    win.settingsHost:Show()
end


-- Shared by the addon-page view and the settings view: sidebar on the left, content on the right.
local function ShowSplit(title, sidebarKind, currentId)
    win:SetHeight(TOTAL_H)
    if win.NineSlice and win.NineSlice.Text then win.NineSlice.Text:SetText(title) end
    local many = LayoutSidebar(currentId) > 1
    win.side:SetShown(many)
    win.sideDivider:SetShown(many)
    local left = many and (24 + SIDEBAR_W + 12) or 24
    win.settingsHost:ClearAllPoints()
    win.settingsHost:SetPoint("TOPLEFT", left, PAGE_TOP)
    C_Timer.After(0, function()
        if win and win:IsShown() and win.side:IsShown() then FitScroll(win.sideScroll, win.sideHost) end
    end)
end

-- One addon's settings page, hosted in our window. With no shared page left, opening the window with
-- no addon named lands on the first one in the sidebar rather than on nothing.
function ShowSettings(id)
    local panels = LIB.OptionsPanels and LIB.OptionsPanels() or {}
    if id and not (LIB.optionsPanels and LIB.optionsPanels[id]) then id = nil end
    if not id then id = panels[1] and panels[1].id end
    if not id then return end          -- no addon has a settings page: there is nothing to show
    SetView()
    win.settingsId = id
    ShowSplit((LIB.optionsPanels[id].name or id) .. " settings", id)

    -- Hide whatever was hosted before, then show what was asked for.
    for _, entry in ipairs(panels) do
        local shown = entry.frame.libForeverHost or entry.frame
        if shown ~= nil then shown:Hide() end
    end
    local entry = LIB.optionsPanels[id]
    local shown = entry.frame.libForeverHost
    if not shown then
        -- Taller than the room: the lib's scroll wrapper. Otherwise the panel itself.
        local room = win.settingsHost:GetHeight()
        if entry.height and entry.height > room and LIB.PanelScroller then
            shown = LIB.PanelScroller(entry.frame, entry.height)
        else
            shown = entry.frame
        end
        if LIB.PanelRefreshHook then LIB.PanelRefreshHook(shown, entry.frame) end
        entry.frame.libForeverHost = shown
        shown:SetParent(win.settingsHost)
    end
    shown:ClearAllPoints()
    shown:SetPoint("TOPLEFT", 0, 0)
    shown:SetSize(PAGE_W, win.settingsHost:GetHeight())
    shown:Show()
end

-- Closing used to record which pages had been seen. There are no pages and no "seen" any more.
function Close() end

--- Open the window on its settings view (id: that addon's own settings).
function LIB.OpenWelcomeSettings(id)
    ShowSettings(id)
end

-- ---------------------------------------------------------------------------
-- The welcome window, removed
-- ---------------------------------------------------------------------------
-- These are the entry points a published addon can still reach. The library is embedded in every
-- addon and the newest copy serves all of them, so an addon the player has not updated calls these
-- against this file. They accept what they were always given and do nothing, except that opening a
-- welcome page now lands on that addon's settings, which is where its text went.
-- They stay until the published versions calling them have aged out - several versions, not one,
-- because the trigger is a player updating one addon and not another.
function LIB.RegisterWelcome() end
function LIB.RegisterWelcomePage() end
function LIB.MarkWelcomeSeen() end
function LIB.IsWelcomeUnseen() return false end
function LIB.WelcomePsstText() return "" end
function LIB.WelcomeRedrawAfterSavedCheck() end

--- Was the welcome window; now the nearest thing that still exists.
function LIB.OpenWelcome(id)
    if id and LIB.optionsPanels and LIB.optionsPanels[id] then return ShowSettings(id) end
    ShowSettings()
end


SLASH_YIPPYAPP1 = "/yippyapp"
SlashCmdList.YIPPYAPP = function(msg)
    -- Support-only: the launcher's state per addon, for bug reports.
    if msg and msg:lower():match("^%s*debug") then
        if LIB.DebugIdentity then LIB.DebugIdentity() end
        if LIB.DebugLauncher then LIB.DebugLauncher() end
        if LIB.MinimapDebug then LIB.MinimapDebug() elseif LIB.DebugMinimap then LIB.DebugMinimap() end
        return
    end
    -- "/yippyapp test": run every addon's self-test, plus the library's own checks.
    if msg and msg:lower():match("^%s*test") then
        if LIB.RunSelfTests then LIB.RunSelfTests()
        else print("|cffffd100YippYapp|r the self-test isn't loaded (SelfTest.lua is missing from this addon).") end
        return
    end
    -- "/yippyapp settings": the shared YippYapp settings page.
    if msg and msg:lower():match("^%s*setting") then
        if LIB.OpenYippYappSettings then LIB.OpenYippYappSettings() end
        return
    end
    if LIB.OpenWelcome then LIB.OpenWelcome() end
end
