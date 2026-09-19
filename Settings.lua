--- LibForever-1.0: the one YippYapp settings page (Options > AddOns > YippYapp).
-- Everything the YippYapp addons share is set here, once, instead of on every addon's own page:
-- the grouped minimap button, the launcher bar, and for each installed addon its minimap and launcher
-- buttons plus a way to its own settings. The page is registered once, however many embedded copies
-- load; the newest copy of this file draws it.
--
--   LIB.OpenYippYappSettings()                 open the page (not in combat: the Settings panel is protected)
--   LIB.RegisterOptionsPage(id, frame, name) -> category
--       the addon's own settings page as a subcategory under YippYapp (name defaults to id); also
--       sets what the page's "Settings..." button opens. Returns nil without the Settings API, and
--       then the addon registers its own top-level category. Calling it again returns the same category.
--   LIB.RegisterSettingsPage(id, categoryOrFunc)
--       optional: what the addon's "Settings" button opens - a Settings category (or its ID), or a
--       function. Without it the page looks for a Settings category named like the addon's id.
--   /yippyapp settings                         opens it too
--
-- Every control reads its value again whenever the page is shown, so it never shows a stale value
-- after something changed elsewhere (an addon's own page, the launcher's right-click menu).
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 2
if (LIB.settingsVersion or 0) >= VERSION then return end
LIB.settingsVersion = VERSION

LIB.settingsPages = LIB.settingsPages or {}

local ROW_H = 28
local COL_MINIMAP, COL_LAUNCHER, COL_SETTINGS = 250, 360, 460

-- ---------------------------------------------------------------------------
-- The category: one panel, registered once
-- ---------------------------------------------------------------------------
local panel = LIB.settingsPanel or CreateFrame("Frame")
LIB.settingsPanel = panel

local function Register()
    if LIB.settingsCategory or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local category = Settings.RegisterCanvasLayoutCategory(panel, "YippYapp")
    Settings.RegisterAddOnCategory(category)
    LIB.settingsCategory = category
end
Register()
if not LIB.settingsCategory then LIB.On("PLAYER_LOGIN", function() Register() end) end

local function CombatMessage(what)
    UIErrorsFrame:AddMessage(what .. " can't open during combat.", 1, 0.2, 0.2)
end

function LIB.OpenYippYappSettings()
    if InCombatLockdown() then CombatMessage("The YippYapp settings") return end
    Register()
    local category = LIB.settingsCategory
    if category and Settings and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
end

function LIB.RegisterSettingsPage(id, categoryOrFunc)
    if id then LIB.settingsPages[id] = categoryOrFunc end
end

-- An addon's own settings page, listed under YippYapp in Options > AddOns. Blizzard's category list
-- picks up subcategories added after the parent was registered (it rebuilds the list), and opening a
-- subcategory expands its parent, so load order between our addons doesn't matter.
LIB.optionsPages = LIB.optionsPages or {}

function LIB.RegisterOptionsPage(id, frame, name)
    if not id or not frame then return nil end
    if LIB.optionsPages[id] then return LIB.optionsPages[id] end
    Register()
    local parent = LIB.settingsCategory
    if not (parent and Settings.RegisterCanvasLayoutSubcategory) then return nil end
    -- Sort our addons by name under YippYapp, where the client supports it.
    if parent.SetShouldSortAlphabetically then pcall(parent.SetShouldSortAlphabetically, parent, true) end
    local category = Settings.RegisterCanvasLayoutSubcategory(parent, frame, name or id)
    if not category then return nil end
    LIB.optionsPages[id] = category
    LIB.RegisterSettingsPage(id, category)
    return category
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
    return LIB.settingsPages[id] or FindCategory(id) or (label ~= id and FindCategory(label)) or nil
end

local function OpenAddonSettings(id, label)
    if InCombatLockdown() then CombatMessage(label .. "'s settings") return end
    local target = SettingsTarget(id, label)
    if type(target) == "function" then
        target()
    elseif type(target) == "table" and target.GetID then
        Settings.OpenToCategory(target:GetID())
    elseif target then
        Settings.OpenToCategory(target)
    end
end

local function Addons()
    local byId = {}
    local function add(id) if type(id) == "string" and id:sub(1, 1) ~= "_" then byId[id] = true end end
    for id in pairs(LIB.minimapButtons or {}) do add(id) end
    for id in pairs(LIB.launcherEntries or {}) do add(id) end
    for id in pairs(LIB.welcomePages or {}) do add(id) end
    for id in pairs(LIB.settingsPages) do add(id) end
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

local function Build()
    local old = panel.content
    if old and old.libVersion == VERSION then return old end
    if old then old:Hide() end
    local c = CreateFrame("Frame", nil, panel)
    c.libVersion = VERSION
    c:SetAllPoints()
    panel.content = c

    -- Title
    local emblem = c:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(36, 36)
    emblem:SetPoint("TOPLEFT", 14, -12)
    if LIB.mediaPath then emblem:SetTexture(LIB.mediaPath .. "yippyapp") end
    local title = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 10, -2)
    title:SetText("YippYapp")
    local sub = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetText("Settings shared by the YippYapp addons for WoW: Forever. Each addon's own settings are listed under YippYapp on the left.")

    -- Shared
    local y = -64
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
    c.list:SetSize(600, ROW_H)

    -- Bottom: welcome, then the quiet psst list
    c.welcome = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    c.welcome:SetSize(180, 22)
    c.welcome:SetPoint("TOPLEFT", c.list, "BOTTOMLEFT", 14, -14)
    c.welcome:SetText("Welcome / what's new")
    c.welcome:SetScript("OnClick", function()
        -- The Options panel is protected in combat; leave it open then.
        if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then SettingsPanel:Close() end
        if LIB.OpenWelcome then LIB.OpenWelcome() end
    end)
    c.psst = c:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    c.psst:SetPoint("TOPLEFT", c.welcome, "BOTTOMLEFT", 2, -16)
    c.psst:SetWidth(580)
    c.psst:SetJustifyH("LEFT")
    c.psst:SetSpacing(2)

    function c:Row(i)
        local r = self.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, self.list)
        r:SetSize(600, ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(22, 22)
        r.icon:SetPoint("LEFT", 16, 0)
        r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
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
        r.settings:SetPoint("LEFT", COL_SETTINGS, 0)
        r.settings:SetText("Settings...")
        r.settings:SetScript("OnClick", function() OpenAddonSettings(r.id, r.label) end)
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
        self.welcome:SetShown(LIB.OpenWelcome ~= nil)
        self.psst:SetText(LIB.WelcomePsstText and LIB.WelcomePsstText() or "")
    end
    return c
end

-- Through LIB, so a newer copy of this file takes the panel over.
function LIB.YippYappSettingsOnShow()
    local c = Build()
    c:Show()
    c:Refresh()
end
panel:SetScript("OnShow", function() LIB.YippYappSettingsOnShow() end)
if panel:IsVisible() then LIB.YippYappSettingsOnShow() end
