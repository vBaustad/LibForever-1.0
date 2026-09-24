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

local VERSION = 9
if (LIB.settingsVersion or 0) >= VERSION then return end
LIB.settingsVersion = VERSION

local ROW_H = 28
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

-- ---------------------------------------------------------------------------
-- The addons: everything registered with any part of the lib
-- ---------------------------------------------------------------------------
local function FindCategory(name)
    if not (SettingsPanel and SettingsPanel.GetAllCategories) then return nil end
    local ok, list = pcall(SettingsPanel.GetAllCategories, SettingsPanel)
    if not ok or type(list) ~= "table" then return nil end
    for _, category in ipairs(list) do
        if category.GetName and category:GetName() == name then return category end
    end
end

local function SettingsTarget(id, label)
    if LIB.optionsPanels[id] then return "panel" end
    return FindCategory(id) or (label ~= id and FindCategory(label)) or nil
end

local function OpenSettingsFor(id, label)
    local target = SettingsTarget(id, label)
    if target == "panel" then
        LIB.OpenAddonSettings(id)
    elseif type(target) == "function" then
        target()
    elseif type(target) == "table" and target.GetID and target:GetID() then
        if InCombatLockdown() then CombatMessage(label .. "'s settings") return end
        Settings.OpenToCategory(target:GetID())
    end
end

local function Addons()
    local byId = {}
    local function add(id) if type(id) == "string" and id:sub(1, 1) ~= "_" then byId[id] = true end end
    for id in pairs(LIB.minimapButtons or {}) do add(id) end
    for id in pairs(LIB.launcherEntries or {}) do add(id) end
    for id in pairs(LIB.welcomePages or {}) do add(id) end
    local list = {}
    for id in pairs(byId) do
        local mm = LIB.minimapButtons and LIB.minimapButtons[id]
        local le = LIB.launcherEntries and LIB.launcherEntries[id]
        local wp = LIB.welcomePages and LIB.welcomePages[id]
        list[#list + 1] = {
            id = id,
            label = (le and le.label) or (mm and mm.opts and mm.opts.label) or (wp and wp.title) or id,
            icon = (mm and mm.opts and mm.opts.icon) or (wp and wp.icon),
            lineIcon = le and le.icon,
            minimap = mm ~= nil,
            launcher = le ~= nil,
        }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local function Check(parent, label, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    if label then
        cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb.label:SetText(label)
    end
    if tip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if label then GameTooltip:AddLine(label, 1, 0.82, 0.3) end
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

local function Heading(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetText(text)
    return fs
end

--- The shared YippYapp settings, built into whatever frame hosts them (our own window).
--- Returns a frame with :Refresh(); it scrolls when the host is shorter than the content.
function LIB.BuildYippYappSettings(host)
    local old = host.content
    if old and old.libVersion == VERSION then return old end
    if old then old:Hide() end
    local scroll = host.scroll
    if not scroll then
        scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 0, -4)
        scroll:SetPoint("BOTTOMRIGHT", -28, 4)
        scroll:SetScript("OnSizeChanged", function(_, w)
            if w and w > 0 and host.content then host.content:SetWidth(w) end
        end)
        host.scroll = scroll
    end
    local c = CreateFrame("Frame", nil, scroll)
    c.libVersion = VERSION
    c:SetSize(math.max(scroll:GetWidth() or 0, 600), 640)
    scroll:SetScrollChild(c)
    host.content = c

    -- The window's title bar and sidebar say where we are, so the panel starts straight in.
    local y = -6
    Heading(c, "Shared by all YippYapp addons"):SetPoint("TOPLEFT", 16, y)
    y = y - 20
    c.group = Check(c, "Group YippYapp minimap buttons",
        "One minimap button for all YippYapp addons; click it for each addon's own button. "
        .. "Off: every addon gets its own minimap button.")
    c.group:SetPoint("TOPLEFT", 12, y)
    c.group:SetScript("OnClick", function(self)
        if LIB.SetMinimapGrouped then LIB.SetMinimapGrouped(self:GetChecked()) end
        c:Refresh()
    end)
    y = y - 26
    c.launcher = Check(c, "Show the YippYapp launcher", LIB.launcherPreviewText)
    c.launcher:SetPoint("TOPLEFT", 12, y)
    c.launcher:SetScript("OnClick", function(self)
        if LIB.SetLauncherEnabled then LIB.SetLauncherEnabled(self:GetChecked()) end
        c:Refresh()
    end)
    y = y - 28

    -- Launcher off: what it looks like. On: its style and a reset.
    c.preview = CreateFrame("Frame", nil, c)
    c.preview:SetPoint("TOPLEFT", 42, y)
    c.preview:SetSize(240, 45)
    local pic = c.preview:CreateTexture(nil, "ARTWORK")
    pic:SetAllPoints()
    if LIB.mediaPath then pic:SetTexture(LIB.mediaPath .. "launcher-preview") end
    pic:SetTexCoord(0, 0.9375, 0, 0.7031)
    local caption = c.preview:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    caption:SetPoint("LEFT", c.preview, "RIGHT", 12, 0)
    caption:SetWidth(300)
    caption:SetJustifyH("LEFT")
    caption:SetText(LIB.launcherPreviewText or "")
    c.collapse = Check(c, "Collapse until hovered", "The bar shrinks to three dots and opens when the mouse is over it.")
    c.collapse:SetPoint("TOPLEFT", 36, y)
    c.collapse:SetScript("OnClick", function(self)
        if LIB.SetLauncherStyle then LIB.SetLauncherStyle(self:GetChecked() and "collapse" or "grow") end
    end)
    c.reset = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    c.reset:SetSize(130, 22)
    c.reset:SetPoint("TOPLEFT", 240, y - 2)
    c.reset:SetText("Reset position")
    c.reset:SetScript("OnClick", function() if LIB.ResetLauncherPosition then LIB.ResetLauncherPosition() end end)
    y = y - 54

    -- One row per addon
    Heading(c, "Your YippYapp addons"):SetPoint("TOPLEFT", 16, y)
    local function col(text, x)
        local fs = c:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", x, y - 2)
        fs:SetText(text)
    end
    col("Minimap button", COL_MINIMAP)
    col("Launcher button", COL_LAUNCHER)
    y = y - 20
    c.rowsTop = y
    c.rows = {}
    c.list = CreateFrame("Frame", nil, c)
    c.list:SetPoint("TOPLEFT", 0, y)
    c.list:SetPoint("RIGHT", c, "RIGHT", -8, 0)
    c.list:SetHeight(ROW_H)

    function c:Row(i)
        local r = self.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, self.list)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("RIGHT", self.list, "RIGHT", 0, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(22, 22)
        r.icon:SetPoint("LEFT", 16, 0)
        r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetWidth(COL_MINIMAP - 50)
        r.name:SetJustifyH("LEFT")
        r.minimap = Check(r)
        r.minimap:SetPoint("LEFT", COL_MINIMAP + 22, 0)
        r.minimap:SetScript("OnClick", function(cb)
            if LIB.SetMinimapButtonShown then LIB.SetMinimapButtonShown(r.id, cb:GetChecked()) end
        end)
        r.launcher = Check(r)
        r.launcher:SetPoint("LEFT", COL_LAUNCHER + 26, 0)
        r.launcher:SetScript("OnClick", function(cb)
            if LIB.SetLauncherHidden then LIB.SetLauncherHidden(r.id, not cb:GetChecked()) end
        end)
        r.settings = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.settings:SetSize(110, 22)
        r.settings:SetPoint("RIGHT", -8, 0)
        r.settings:SetText("Settings...")
        r.settings:SetScript("OnClick", function() OpenSettingsFor(r.id, r.label) end)
        self.rows[i] = r
        return r
    end

    function c:Refresh()
        self.group:SetShown(LIB.SetMinimapGrouped ~= nil)
        self.group.label:SetShown(LIB.SetMinimapGrouped ~= nil)
        self.group:SetChecked(LIB.IsMinimapGrouped and LIB.IsMinimapGrouped() or false)
        local on = LIB.IsLauncherEnabled and LIB.IsLauncherEnabled() or false
        self.launcher:SetChecked(on)
        self.preview:SetShown(not on)
        self.collapse:SetShown(on); self.collapse.label:SetShown(on)
        self.reset:SetShown(on)
        self.collapse:SetChecked(LIB.GetLauncherStyle and LIB.GetLauncherStyle() == "collapse")

        local list = Addons()
        for _, r in ipairs(self.rows) do r:Hide() end
        for i, a in ipairs(list) do
            local r = self:Row(i)
            r.id, r.label = a.id, a.label
            if a.icon then
                r.icon:SetTexture(a.icon)
                r.icon:SetVertexColor(1, 1, 1, 1)
            else
                r.icon:SetTexture(a.lineIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
                r.icon:SetVertexColor(0.92, 0.88, 0.80, 0.92)
            end
            r.name:SetText(a.label)
            r.minimap:SetShown(a.minimap)
            r.minimap:SetChecked(a.minimap and LIB.IsMinimapButtonShown(a.id) or false)
            r.launcher:SetShown(a.launcher)
            r.launcher:SetChecked(a.launcher and not LIB.IsLauncherHidden(a.id) or false)
            -- Launcher off: the per-addon choice still counts, but shows it only matters once it is on.
            r.launcher:SetAlpha(on and 1 or 0.5)
            r.settings:SetShown(SettingsTarget(a.id, a.label) ~= nil)
            r:Show()
        end
        self.list:SetHeight(math.max(1, #list) * ROW_H)
        -- As tall as the content: measured from the last row, once it has been laid out.
        C_Timer.After(0, function()
            local top, bottom = self:GetTop(), self.list:GetBottom()
            if top and bottom then self:SetHeight(top - bottom + 16) end
        end)
    end
    return c
end

-- Blizzard's page only holds the button; our window draws the settings themselves.
function LIB.YippYappSettingsOnShow()
    BuildBlizzardPage()
end
panel:SetScript("OnShow", function() LIB.YippYappSettingsOnShow() end)
panel.OnRefresh = function() LIB.YippYappSettingsOnShow() end
if panel:IsVisible() then LIB.YippYappSettingsOnShow() end
