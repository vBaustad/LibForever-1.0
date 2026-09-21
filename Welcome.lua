--- LibForever-1.0: the shared welcome window.
-- One window for every YippYapp addon instead of one first-time popup each. Every addon registers its
-- own page; the window shows one tab per page, and a quiet "psst" list of the rest of the family.
--
--   LIB.RegisterWelcome({
--       id = "AutoFeed",          -- unique; also the launcher entry whose line icon the page uses
--       title = "AutoFeed",       -- tab label and page heading
--       subtitle = "...",         -- optional one-liner under the heading
--       icon = "...",             -- the addon's emblem (e.g. its Media\icon); else its launcher line icon
--       version = 1,              -- intro version; raise it and the page counts as unseen again
--       build = function(page) end,     -- draws the page once, on first view (page size: page:GetSize())
--       onShow = function(page) end,    -- optional, every time the page is shown
--       needsSetup = function() return true end, -- optional: true auto-opens the window while unseen
--       launcher = "AutoFeed",    -- optional launcher entry id for the icon; defaults to id
--       order = 10,               -- optional tab order
--   }, savedTable)
--   LIB.OpenWelcome(id)            open it by hand: every page, with id (or the first unseen one) selected
--   LIB.IsWelcomeUnseen(id)        LIB.MarkWelcomeSeen(id)
--   /yippyapp                      opens it too; /yippyapp settings opens the shared YippYapp settings
--
-- "Seen" lives in the addon's own saved table: savedTable.welcomeSeen[id] = version. The lib has no
-- SavedVariables of its own.
--
-- After login (and a short wait) the lib looks at the unseen pages. If one of them needs setup, the
-- window opens by itself with just the unseen pages, never in combat or in an instance (it waits).
-- Otherwise nothing pops up and nothing is marked (the launcher is only ever buttons): the pages wait
-- for /yippyapp or the addon's own way in (e.g. a Welcome button on its settings page -> LIB.OpenWelcome).
-- A page counts as seen once it has actually been shown and the window closes.
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 8
if (LIB.welcomeVersion or 0) >= VERSION then return end
LIB.welcomeVersion = VERSION

-- The family, for the "psst" list. Edit freely: folder name, what it is, and how a player can use it
-- together with another one. Keep the combos true: usage tips the player puts together themselves,
-- never a claim that one addon reads or does something in another.
local CATALOG = {
    { name = "Guildhall",   what = "your guild's crafting directory",
      combo = "with Skillwright, see which guildie can craft the steps you'd rather skip" },
    { name = "AutoFeed",    what = "one-button macros for your best food, water and potions",
      combo = "with BuffWarden, class buffs and your own food and scroll buffs are both covered" },
    { name = "Skillwright", what = "the cheapest or fastest route to max profession skill",
      combo = "with Guildhall, find a guildie who already makes what your route needs" },
    { name = "BuffWarden",  what = "shows the class buffs you and your group are missing",
      combo = "with AutoFeed, your food and scroll buffs are covered too" },
    { name = "Campfire",    what = "see which guildies are nearby, and how far",
      combo = "with Guildhall, find the guildie who crafts for you and meet up" },
}
LIB.welcomeCatalog = CATALOG

local W, H = 620, 520
local AUTO_DELAY = 3

local pages = LIB.welcomePages or {}
LIB.welcomePages = pages

-- An older copy of this file already built the window: retire it; pages are redrawn in the new one.
if LIB.welcomeFrame then
    LIB.welcomeFrame:SetScript("OnHide", nil)
    LIB.welcomeFrame:Hide()
    LIB.welcomeFrame = nil
    for _, p in pairs(pages) do p.page = nil end
end

local win           -- the window, built on first open
local shown = {}    -- ids of the pages in the window right now, in tab order
local viewed = {}   -- ids actually looked at since the window opened
local loginDone = LIB.welcomeLoginDone
local autoPending   -- an auto-open is waiting for combat or the instance to end

-- ---------------------------------------------------------------------------
-- Seen state
-- ---------------------------------------------------------------------------
local function SeenTable(p)
    if not p.store then
        p.sessionSeen = p.sessionSeen or {}
        return p.sessionSeen
    end
    if type(p.store.welcomeSeen) ~= "table" then p.store.welcomeSeen = {} end
    return p.store.welcomeSeen
end

local function Unseen(p)
    return (tonumber(SeenTable(p)[p.id]) or 0) < (p.version or 1)
end

function LIB.IsWelcomeUnseen(id)
    local p = pages[id]
    return p and Unseen(p) or false
end

local function NeedsSetup(p)
    if not p.needsSetup then return false end
    local ok, res = pcall(p.needsSetup)
    return ok and res and true or false
end

local function Sorted(filter)
    local list = {}
    for _, p in pairs(pages) do
        if not filter or filter(p) then list[#list + 1] = p end
    end
    table.sort(list, function(a, b)
        if (a.order or 50) ~= (b.order or 50) then return (a.order or 50) < (b.order or 50) end
        return a.id < b.id
    end)
    return list
end

function LIB.MarkWelcomeSeen(id)
    local p = pages[id]
    if not p then return end
    SeenTable(p)[id] = p.version or 1
end

-- ---------------------------------------------------------------------------
-- Psst: the rest of the family, installed ones ticked
-- ---------------------------------------------------------------------------
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"

local function Installed(name)
    if not C_AddOns then return false end
    if C_AddOns.DoesAddOnExist then return C_AddOns.DoesAddOnExist(name) and true or false end
    local _, _, _, _, reason = C_AddOns.GetAddOnInfo(name)
    return reason ~= "MISSING"
end

local SHARED_H = 26  -- the "shared settings" line above the psst list

local function PsstText(onlyTitle)
    local have, rest = {}, {}
    for _, a in ipairs(CATALOG) do
        if Installed(a.name) then have[#have + 1] = TICK .. " " .. a.name
        else rest[#rest + 1] = a end
    end
    local lines = {}
    if #rest == 0 then
        lines[1] = "Psst - you have the whole YippYapp family. They work even better together."
    elseif onlyTitle then
        lines[1] = ("Psst - %s has siblings in the YippYapp family:"):format(onlyTitle)
    else
        lines[1] = "Psst - there are more addons in the YippYapp family:"
    end
    if #have > 0 and #rest > 0 then lines[#lines + 1] = "   " .. table.concat(have, "    ") end
    for _, a in ipairs(rest) do
        lines[#lines + 1] = ("   |cffb0a890%s|r - %s; %s."):format(a.name, a.what, a.combo)
    end
    if #rest == 0 then lines[#lines + 1] = "   " .. table.concat(have, "    ") end
    return table.concat(lines, "\n")
end
LIB.WelcomePsstText = PsstText  -- the YippYapp settings page shows the same list

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local Select, Close

-- A page's own emblem; without one, its launcher's white line icon, tinted like on the launcher.
local function SetIcon(tex, p)
    if p.icon then
        tex:SetTexture(p.icon)
        tex:SetVertexColor(1, 1, 1, 1)
        return
    end
    local e = LIB.launcherEntries and LIB.launcherEntries[p.launcher or p.id]
    tex:SetTexture((e and e.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetVertexColor(0.92, 0.88, 0.80, 0.92)
end

local TAB_H, TAB_GAP, TAB_ICON = 37, 5, 16
local TAB_PAD = 20   -- on each side of the icon and label; squeezed when many tabs must fit

local function MakeTab(parent)
    local b = CreateFrame("Button", nil, parent, "MinimalTabTemplate")
    b:SetHeight(TAB_H)
    -- The label sits in the middle of the tab, with the addon's line icon in front of it.
    b.Text:ClearAllPoints()
    b.Text:SetPoint("CENTER", b, "CENTER", (TAB_ICON + TAB_GAP) / 2, 0)
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetSize(TAB_ICON, TAB_ICON)
    icon:SetPoint("RIGHT", b.Text, "LEFT", -TAB_GAP, 0)
    icon:SetVertexColor(0.92, 0.88, 0.80, 0.92)
    b.icon = icon
    b:SetScript("OnClick", function(self) Select(self.id) end)
    return b
end

local function Build()
    win = CreateFrame("Frame", "LibForeverWelcome", UIParent, "SettingsFrameTemplate")
    LIB.welcomeFrame = win
    win:SetSize(W, H)
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

    win.tabs = {}
    win.divider = win:CreateTexture(nil, "ARTWORK")
    win.divider:SetAtlas("Options_HorizontalDivider")
    win.divider:SetHeight(1)

    win.body = CreateFrame("Frame", nil, win)
    win.icon = win.body:CreateTexture(nil, "ARTWORK")
    win.icon:SetSize(32, 32)
    win.icon:SetPoint("TOPLEFT", 0, 0)
    win.icon:SetVertexColor(0.92, 0.88, 0.80, 0.92)
    win.heading = win.body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.heading:SetPoint("TOPLEFT", win.icon, "TOPRIGHT", 10, -1)
    win.subtitle = win.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.subtitle:SetPoint("TOPLEFT", win.heading, "BOTTOMLEFT", 0, -3)
    win.subtitle:SetPoint("RIGHT", win.body, "RIGHT", 0, 0)
    win.subtitle:SetJustifyH("LEFT")
    win.subtitle:SetWordWrap(false)

    win.done = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.done:SetSize(96, 22)
    win.done:SetPoint("BOTTOMRIGHT", -16, 16)
    win.done:SetScript("OnClick", function()
        -- Walk through the tabs not looked at yet, then close.
        for _, id in ipairs(shown) do
            if not viewed[id] then Select(id) return end
        end
        win:Hide()
    end)

    win.psst = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.psst:SetPoint("BOTTOMLEFT", 24, 18)
    win.psst:SetWidth(W - 48 - 110)
    win.psst:SetJustifyH("LEFT")
    win.psst:SetSpacing(2)
    win.psstRule = win:CreateTexture(nil, "ARTWORK")
    win.psstRule:SetAtlas("Options_HorizontalDivider")
    win.psstRule:SetHeight(1)
    win.psstRule:SetPoint("BOTTOMLEFT", win.psst, "TOPLEFT", -6, 8)
    win.psstRule:SetPoint("RIGHT", win, "RIGHT", -20, 0)

    -- A fixed line on every page: the shared settings are in one place for all the addons.
    win.shared = CreateFrame("Frame", nil, win)
    win.shared:SetSize(W - 48, SHARED_H)
    win.shared:SetPoint("BOTTOMLEFT", win.psstRule, "TOPLEFT", 6, 6)
    local sharedText = win.shared:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sharedText:SetPoint("LEFT", 0, 0)
    sharedText:SetWidth(W - 48 - 160)
    sharedText:SetJustifyH("LEFT")
    sharedText:SetText("The minimap button, the launcher and other settings for all YippYapp addons are in "
        .. "|cffffd100Options > AddOns > YippYapp|r (or |cffffd100/yippyapp settings|r).")
    local sharedButton = CreateFrame("Button", nil, win.shared, "UIPanelButtonTemplate")
    sharedButton:SetSize(150, 22)
    sharedButton:SetPoint("RIGHT", 0, 0)
    sharedButton:SetText("YippYapp settings...")
    sharedButton:SetScript("OnClick", function()
        if LIB.OpenYippYappSettings then LIB.OpenYippYappSettings() end
    end)

    -- HookScript: RegisterWindow already hooked OnHide for Escape; SetScript would drop that.
    win:HookScript("OnHide", function() Close() end)
end

local function UpdateDone()
    local left = false
    for _, id in ipairs(shown) do if not viewed[id] then left = true end end
    win.done:SetText(left and "Next" or (DONE or "Done"))
end

function Select(id)
    local p = pages[id]
    if not p then return end
    viewed[id] = true
    for _, b in ipairs(win.tabs) do
        if b:IsShown() then
            b:SetSelected(b.id == id)
        end
    end
    for _, q in pairs(pages) do if q.page then q.page:Hide() end end
    SetIcon(win.icon, p)
    win.heading:SetText(p.title or p.id)
    win.subtitle:SetText(p.subtitle or "")
    local top = p.subtitle and p.subtitle ~= "" and -46 or -42
    local fresh = not p.page
    p.page = p.page or CreateFrame("Frame", nil, win.body)
    -- The body is taller without tabs; keep the page filling it either way.
    p.page:ClearAllPoints()
    p.page:SetPoint("TOPLEFT", 0, top)
    p.page:SetSize(win.body:GetWidth(), win.body:GetHeight() + top)
    if fresh then
        if p.build then
            local ok, err = pcall(p.build, p.page)
            if not ok then
                LIB.Debug("welcome page %s: %s", id, tostring(err))
                local fs = p.page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                fs:SetPoint("TOPLEFT")
                fs:SetText("This page could not be drawn.")
            end
        end
    end
    p.page:Show()
    if p.onShow then pcall(p.onShow, p.page) end
    UpdateDone()
end

-- Opens the window with the given pages (a list of page tables) and one of them selected.
local function Show(list, selectId)
    if #list == 0 then return end
    if not win then Build() end
    -- Reopened while open: settle what was looked at so far, then swap the contents.
    if win:IsShown() then Close() end
    wipe(shown)
    wipe(viewed)

    local single = #list == 1
    local title = single and ("Welcome to " .. (list[1].title or list[1].id)) or "Welcome to YippYapp"
    if win.NineSlice and win.NineSlice.Text then win.NineSlice.Text:SetText(title) end

    for _, b in ipairs(win.tabs) do b:Hide() end
    -- The row starts at the same left margin as the page below it, and is squeezed to fit the window.
    local labels, textWidth = {}, 0
    for i, p in ipairs(list) do
        local b = win.tabs[i] or MakeTab(win)
        win.tabs[i] = b
        b.Text:SetText(p.title or p.id)
        labels[i] = b.Text:GetStringWidth()
        textWidth = textWidth + labels[i]
    end
    local room = W - 24 - 20 - (#list - 1) * TAB_GAP - #list * (TAB_ICON + TAB_GAP)
    local pad = math.max(8, math.min(TAB_PAD, math.floor((room - textWidth) / (2 * #list))))
    local prev
    for i, p in ipairs(list) do
        shown[i] = p.id
        local b = win.tabs[i]
        b.id = p.id
        SetIcon(b.icon, p)
        b:SetWidth(labels[i] + TAB_ICON + TAB_GAP + pad * 2)
        b:ClearAllPoints()
        if prev then b:SetPoint("TOPLEFT", prev, "TOPRIGHT", TAB_GAP, 0) else b:SetPoint("TOPLEFT", 24, -27) end
        b:SetShown(not single)
        prev = b
    end

    local bodyTop = single and -38 or -74
    win.divider:SetShown(not single)
    win.divider:ClearAllPoints()
    win.divider:SetPoint("TOPLEFT", 18, -64)
    win.divider:SetPoint("TOPRIGHT", -20, -64)

    -- With only one of our addons installed, the window is simply that addon's own welcome.
    local onlyOne = #Sorted() == 1 and (list[1].title or list[1].id) or nil
    win.psst:SetText(PsstText(onlyOne))
    local psstH = win.psst:GetStringHeight() or 60
    win.body:ClearAllPoints()
    win.body:SetPoint("TOPLEFT", 24, bodyTop)
    win.body:SetSize(W - 48, H + bodyTop - (18 + psstH + 22 + SHARED_H + 6))

    win:Show()
    local pick = pages[selectId] and selectId or nil
    if not pick then
        for _, p in ipairs(list) do if Unseen(p) then pick = p.id break end end
    end
    Select(pick or list[1].id)
end

-- Closing marks every page that was actually shown as seen.
function Close()
    for id in pairs(viewed) do
        local p = pages[id]
        if p then SeenTable(p)[id] = p.version or 1 end
    end
    wipe(viewed)
end

-- id may be a page id or a launcher entry id.
function LIB.OpenWelcome(id)
    if id and not pages[id] then
        for _, p in pairs(pages) do if p.launcher == id then id = p.id break end end
    end
    Show(Sorted(), id)
end

-- ---------------------------------------------------------------------------
-- Opening by itself: only for an unseen page that needs setup, never in combat or an instance
-- ---------------------------------------------------------------------------
local function CanAutoOpen()
    if InCombatLockdown() or UnitAffectingCombat("player") then return false end
    local inInstance = IsInInstance()
    return not inInstance
end

local function Evaluate()
    if LIB.welcomeVersion ~= VERSION or not loginDone then return end
    if win and win:IsShown() then return end
    local unseen = Sorted(Unseen)
    local setup = false
    for _, p in ipairs(unseen) do if NeedsSetup(p) then setup = true end end
    if not setup then autoPending = nil return end
    if not CanAutoOpen() then autoPending = true return end
    autoPending = nil
    Show(unseen)
end

function LIB.RegisterWelcome(entry, savedTable)
    if type(entry) ~= "table" or not entry.id then return end
    entry.store = savedTable
    local old = pages[entry.id]
    if old and old.page then old.page:Hide() end
    pages[entry.id] = entry
    -- Registered after login (a load-on-demand addon): look again shortly.
    if loginDone then LIB.Debounce("welcome", AUTO_DELAY, Evaluate) end
end

LIB.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if LIB.welcomeVersion ~= VERSION then return end
    if not loginDone and (isLogin or isReload) then
        loginDone = true
        LIB.welcomeLoginDone = true
        LIB.Debounce("welcome", AUTO_DELAY, Evaluate)
    elseif autoPending then
        LIB.Debounce("welcome", AUTO_DELAY, Evaluate)
    end
end)

LIB.On("PLAYER_REGEN_ENABLED", function()
    if LIB.welcomeVersion ~= VERSION or not autoPending then return end
    LIB.Debounce("welcome", AUTO_DELAY, Evaluate)
end)

-- A newer copy of this file loaded after the login check already ran in an older one.
if loginDone then LIB.Debounce("welcome", AUTO_DELAY, Evaluate) end

SLASH_YIPPYAPP1 = "/yippyapp"
SlashCmdList.YIPPYAPP = function(msg)
    -- Support-only: the launcher's state per addon, for bug reports.
    if msg and msg:lower():match("^%s*debug") then
        if LIB.DebugLauncher then LIB.DebugLauncher() end
        if LIB.DebugMinimap then LIB.DebugMinimap() end
        return
    end
    -- "/yippyapp settings": the shared YippYapp settings page.
    if msg and msg:lower():match("^%s*setting") then
        if LIB.OpenYippYappSettings then LIB.OpenYippYappSettings() end
        return
    end
    if LIB.OpenWelcome then LIB.OpenWelcome() end
end
