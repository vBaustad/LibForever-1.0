--- LibForever-1.0: the shared welcome window.
-- One window for every YippYapp addon, and the home of every YippYapp setting (Blizzard's Options
-- closes whatever else the player had open, so it only holds a button that opens this window).
-- It opens on a home page with one card per installed addon: the ones that need setting up first,
-- highlighted and with the reason; the rest below under "All set". A card's button opens the addon
-- itself, or its page when there is something new. The page has a back button, a sidebar for hopping
-- between addons and a settings wheel to that addon's own settings. The home page also carries the
-- beta banner, the note about Forever forgetting settings, and a quiet "psst" list of the family.
--
--   LIB.RegisterWelcome({
--       id = "AutoFeed",          -- unique; also the launcher entry whose line icon the page uses
--       title = "AutoFeed",       -- tab label and page heading
--       subtitle = "...",         -- optional one-liner under the heading
--       icon = "...",             -- the addon's emblem (e.g. its Media\icon); else its launcher line icon
--       version = 1,              -- intro version; raise it and the page counts as unseen again
--       build = function(page) end,     -- draws the page once, on first view (page size: page:GetSize())
--       onShow = function(page) end,    -- optional, every time the page is shown
--       needsSetup = function() return true end, -- optional: true puts the addon first on the home page
--       reason = "no macros yet",   -- optional: why it needs setting up, shown on its card
--       setupLabel = "Create macros", -- optional: the real action, on the badge and the button;
--                                 -- a function works too, for several setup states (nil -> "Set up")
--       blurb = "...",              -- optional: the one line on its card (else subtitle, else catalogue)
--       onOpen = function() end,    -- optional: what "Open" runs (else the addon's launcher click)
--       launcher = "AutoFeed",      -- optional launcher entry id for the icon; defaults to id
--       order = 10,                 -- optional order
--   }, savedTable)
--   LIB.OpenWelcome(id)            open it by hand: the home page, or straight to one addon's page
--   LIB.OpenWelcomeSettings(id)    open it on the settings view (id: that addon's own settings)
--   LIB.RegisterWelcomePage(...)   the same as RegisterWelcome
--   LIB.IsWelcomeUnseen(id)        LIB.MarkWelcomeSeen(id)
--   /yippyapp                      opens it too; /yippyapp settings opens the shared YippYapp settings
--
-- "Seen" lives in the addon's own saved table: savedTable.welcomeSeen[id] = version. The lib has no
-- SavedVariables of its own.
--
-- The home page carries a gold-on-black beta banner: the addons are actively developed, and bug
-- reports and comments on CurseForge help (its button shows the link to all YippYapp addons there).
--
-- After login (and a short wait) the lib looks at the unseen pages. If one of them needs setup, the
-- window opens by itself with just the unseen pages, never in combat or in an instance (it waits).
-- It also opens once, on the home page, after an update brings a new banner message (NOTICE below;
-- remembered as savedTable.welcomeNotice once the window is closed).
-- Otherwise nothing pops up and nothing is marked (the launcher is only ever buttons): the pages wait
-- for /yippyapp or the addon's own way in (e.g. a Welcome button on its settings page -> LIB.OpenWelcome).
-- A page counts as seen once it has actually been shown and the window closes.
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 13
if (LIB.welcomeVersion or 0) >= VERSION then return end
LIB.welcomeVersion = VERSION

-- The family, for the "psst" line and the one-line blurb on a card.
local CATALOG = {
    { name = "Guildhall",   what = "your guild's crafting directory", },
    { name = "AutoFeed",    what = "one-button macros for your best food, water and potions", },
    { name = "Skillwright", what = "the cheapest or fastest route to max profession skill", },
    { name = "BuffWarden",  what = "shows the class buffs you and your group are missing", },
    { name = "Campfire",    what = "see which guildies are nearby, and how far", },
    { name = "BagWarden",   what = "keeps your bags tidy", },
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
local viewed = {}   -- ids actually looked at since the window opened
local loginDone = LIB.welcomeLoginDone
local homeShown     -- the home page has been looked at since the window opened
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
-- Psst: one line about the rest of the family
-- ---------------------------------------------------------------------------

local function Installed(name)
    if not C_AddOns then return false end
    if C_AddOns.DoesAddOnExist then return C_AddOns.DoesAddOnExist(name) and true or false end
    local _, _, _, _, reason = C_AddOns.GetAddOnInfo(name)
    return reason ~= "MISSING"
end

local SHARED_H = 26  -- the "shared settings" line above the psst list

local function PsstText()
    local have, rest = 0, {}
    for _, a in ipairs(CATALOG) do
        if Installed(a.name) then have = have + 1 else rest[#rest + 1] = a.name end
    end
    -- Always ONE line. With the whole family the sentence says it; otherwise the names, cut short
    -- rather than allowed to wrap.
    if #rest == 0 then
        return ("Psst - you have all %d YippYapp addons."):format(have)
    end
    local names = table.concat(rest, ", ")
    if #names > 60 then names = names:sub(1, 57):gsub(",?%s*$", "") .. "..." end
    return ("Psst - more in the YippYapp family: |cffb0a890%s|r."):format(names)
end
LIB.WelcomePsstText = PsstText  -- the YippYapp settings page shows the same list

-- ---------------------------------------------------------------------------
-- The window: a home page with one card per addon, and the addon pages behind it
-- ---------------------------------------------------------------------------
local Select, Close, ShowHome, ShowSettings, OpenAddon

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

-- One line about what an addon does: its own subtitle, else the family catalogue.
--- Open an addon the way the family agreed: its own main window (onOpen, else its launcher click),
--- and when it has none, its settings. Never a what's-new page - those are only reached from inside
--- this window. Used by the minimap row, the cards and the addons themselves.
function LIB.OpenAddon(id)
    local p = pages[id]
    local hasPanel = LIB.optionsPanels and LIB.optionsPanels[id]
    local run = p and p.onOpen
    if not run then
        local e = LIB.launcherEntries and LIB.launcherEntries[(p and p.launcher) or id]
        run = e and e.onClick and function() e.onClick("LeftButton") end
    end
    if not run then
        -- No main window: its settings are the sensible landing place.
        if hasPanel and LIB.OpenAddonSettings then return LIB.OpenAddonSettings(id) end
        return Select(id)
    end
    if win then win:Hide() end
    local ok, err = pcall(run)
    if not ok then LIB.Debug("open %s: %s", tostring(id), tostring(err)) end
    -- Enforcement: if the addon's own action just put us on a what's-new page, that isn't where a
    -- minimap click belongs. Send it to that addon's settings instead.
    if win and win:IsShown() and win.mode == "page" and hasPanel and LIB.OpenAddonSettings then
        LIB.OpenAddonSettings(id)
    end
end
OpenAddon = LIB.OpenAddon

local function Blurb(p)
    if p.blurb and p.blurb ~= "" then return p.blurb end
    if p.subtitle and p.subtitle ~= "" then return p.subtitle end
    for _, a in ipairs(CATALOG) do
        if a.name == p.id then return a.what:sub(1, 1):upper() .. a.what:sub(2) .. "." end
    end
    return ""
end

-- Nothing to set up while the client hasn't loaded the saved settings: we can't know what the
-- player has already done, so we never badge, nag or open for setup in that state.
local function SetupKnown()
    return not (LIB.SavedVariablesLoaded and not LIB.SavedVariablesLoaded())
end

-- The action to offer, for the badge and the button: a string, or a function so an addon with
-- several setup states can name the matching one ("Join a guild" / "Open your Blacksmithing window").
local function SetupLabel(p)
    local label = p.setupLabel
    if type(label) == "function" then
        local ok, text = pcall(label)
        label = ok and text or nil
    end
    return label or "Set up"
end

local function SetupReason(p)
    if not SetupKnown() or not NeedsSetup(p) then return nil end
    local reason = p.reason or p.setupReason
    if type(reason) == "function" then
        local ok, text = pcall(reason)
        reason = ok and text or nil
    end
    return reason or "needs setting up"
end

-- Sizes. The addon pages keep the width they were drawn for, so the window is wide enough for the
-- page plus the sidebar beside it.
local PAGE_W = W - 48
local SIDEBAR_W = 168
local WIN_W = 24 + SIDEBAR_W + 12 + PAGE_W + 24
local BANNER_H, BANNER_GAP = 52, 10
local DISCLAIMER_H = 30   -- the line about Forever forgetting settings, under the banner
local TOTAL_H = H + BANNER_H + BANNER_GAP
local CONTENT_TOP = -38       -- below the title bar
local PAGE_TOP = -64          -- below the back button on an addon page
local BOTTOM_BAR = 46         -- the button row along the bottom
local CARD_W, CARD_MIN_H, CARD_GAP = 228, 74, 12
local HOME_MIN_H = 150   -- the card area's own height, before it grows with the cards

-- CurseForge's search for "yippyapp" in WoW addons, filtered to the Forever game version (88568):
-- every YippYapp addon in one list, to pick one to report a bug or comment on.
local CURSEFORGE_URL = "https://www.curseforge.com/wow/search?class=addons&search=yippyapp&gameVersionTypeId=88568"

StaticPopupDialogs["LIBFOREVER_YIPPYAPP_LINK"] = {
    text = "All YippYapp addons on CurseForge\nCopy the link below, then pick one to report a bug or comment.",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 360,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox  -- the field name differs between client builds
        if not eb then return end
        eb:SetText(CURSEFORGE_URL)
        eb:HighlightText()
        eb:SetFocus()
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function ShowCurseForge()
    StaticPopup_Show("LIBFOREVER_YIPPYAPP_LINK")
end

-- An unnamed scroll frame doesn't expose its scroll bar by name: find the slider among its children,
-- and hide it (with its arrows) when everything fits, so no stray buttons float over the page.
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

local function Box(parent, gold)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.03, 0.02, gold and 0.95 or 0.55)
    f:SetBackdropBorderColor(gold and 1 or 0.62, gold and 0.82 or 0.56, gold and 0.30 or 0.44, 1)
    return f
end

-- The beta banner on the home page: actively developed, and reports and comments help.
local function BuildBanner(parent, width)
    local b = Box(parent, true)
    b:SetSize(width, BANNER_H)
    local star = b:CreateTexture(nil, "ARTWORK")
    star:SetSize(34, 34)
    star:SetPoint("LEFT", 10, 0)
    if LIB.mediaPath then star:SetTexture(LIB.mediaPath .. "yippyapp") end
    local button = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    button:SetSize(120, 24)
    button:SetPoint("RIGHT", -10, 0)
    button:SetText("CurseForge")
    button:SetScript("OnClick", ShowCurseForge)
    local title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", star, "TOPRIGHT", 10, 1)
    title:SetPoint("RIGHT", button, "LEFT", -12, 0)
    title:SetJustifyH("LEFT")
    title:SetText("Actively developed during the Forever beta")
    local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    text:SetPoint("RIGHT", button, "LEFT", -12, 0)
    text:SetJustifyH("LEFT")
    text:SetText("We're improving every YippYapp addon. Found a bug or have an idea? "
        .. "Every report and comment on |cffffd100CurseForge|r helps a lot!")
    return b
end

-- Shown once to everyone after an update that brings a new banner message: raise NOTICE then.
-- Stored in each addon's own saved table (welcomeNotice), like "seen".
local NOTICE = 1

-- Fail safe: the window opens by itself only when NO saved table says the message has been seen.
-- One table that can't be read or written (a per-character table on a fresh alt, an addon that
-- registers later, or Forever losing saved variables) must never bring the window back every reload.
local function NoticePending()
    if LIB.welcomeNoticeMarked then return false end
    local any = false
    for _, p in pairs(pages) do
        if p.store then
            any = true
            if (tonumber(p.store.welcomeNotice) or 0) >= NOTICE then return false end
        end
    end
    return any
end

local function MarkNoticeSeen()
    LIB.welcomeNoticeMarked = true   -- also covers addons that register later this session
    -- Saved variables that never loaded: remember it for this session only, don't write.
    if LIB.SavedVariablesLoaded and not LIB.SavedVariablesLoaded() then return end
    for _, p in pairs(pages) do
        if p.store then p.store.welcomeNotice = NOTICE end
    end
end

-- ---------------------------------------------------------------------------
-- Cards on the home page
-- ---------------------------------------------------------------------------
local function CardFor(i)
    local card = win.cards[i]
    if card then return card end
    card = Box(win.cardHost)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)
    card.badge = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.badge:SetJustifyH("RIGHT")
    card.badge:SetTextColor(1, 0.82, 0.30)
    card.badge:SetText("SET UP")   -- the text is replaced per addon in FillCard
    -- Every text in a card has a width and wraps; the card grows to fit what it holds.
    card.reason = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.reason:SetJustifyH("LEFT")
    card.reason:SetTextColor(1, 0.82, 0.30)
    card.reason:SetWordWrap(true)
    card.blurb = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.blurb:SetJustifyH("LEFT")
    card.blurb:SetWordWrap(true)
    card.blurb:SetSpacing(2)
    card.news = CreateFrame("Button", nil, card)
    card.news:SetSize(80, 18)
    card.news.text = card.news:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.news.text:SetAllPoints()
    card.news.text:SetText("What's new")
    card.news.text:SetTextColor(1, 0.82, 0.30)
    card.news:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.92, 0.6) end)
    card.news:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0.30) end)
    card.news:SetScript("OnClick", function(self) Select(self:GetParent().id) end)

    card.button = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.button:SetSize(88, 21)
    card.button:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        if parent.action == "addon" then OpenAddon(parent.id) else Select(parent.id) end
    end)
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(self) Select(self.id) end)
    card:SetScript("OnEnter", function(self)
        if not self.tooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.title or self.id, 1, 0.82, 0.3)
        for _, line in ipairs(self.tooltip) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.cards[i] = card
    return card
end

local CARD_PAD, CARD_LINES = 12, 2

-- Fill a card and work out how tall it needs to be. Nothing is positioned vertically yet: the row
-- does that once it knows the tallest card in it.
local function FillCard(card, p, full)
    local inner = CARD_W - CARD_PAD * 2
    local reason = SetupReason(p)
    card.id, card.title = p.id, p.title or p.id
    card:SetWidth(CARD_W)
    card:SetBackdropBorderColor(reason and 1 or 0.62, reason and 0.82 or 0.56, reason and 0.30 or 0.44, 1)
    card:SetBackdropColor(0.04, 0.03, 0.02, reason and 0.95 or 0.5)
    card:SetAlpha(full and 1 or 0.9)

    local iconSize = full and 32 or 22
    card.icon:SetSize(iconSize, iconSize)
    card.icon:ClearAllPoints()
    card.icon:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
    SetIcon(card.icon, p)

    card.badge:ClearAllPoints()
    card.badge:SetPoint("TOPRIGHT", -CARD_PAD, -CARD_PAD - 2)
    card.badge:SetText(SetupLabel(p):upper())
    card.badge:SetShown(reason ~= nil)

    card.name:ClearAllPoints()
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, -1)
    card.name:SetWidth(inner - iconSize - 8 - (reason and card.badge:GetStringWidth() + 8 or 0))
    card.name:SetText(p.title or p.id)

    local y = CARD_PAD + math.max(iconSize, 18)
    local full_text = {}

    card.reason:ClearAllPoints()
    card.reason:SetPoint("TOPLEFT", CARD_PAD, -(y + 4))
    card.reason:SetWidth(inner)
    if card.reason.SetMaxLines then pcall(card.reason.SetMaxLines, card.reason, CARD_LINES) end
    card.reason:SetText(reason or "")
    card.reason:SetShown(reason ~= nil)
    if reason then
        y = y + 4 + math.min(card.reason:GetStringHeight() or 12, CARD_LINES * 13)
        full_text[#full_text + 1] = "Needs setting up: " .. reason
    end

    local blurb = full and Blurb(p) or ""
    card.blurb:ClearAllPoints()
    card.blurb:SetPoint("TOPLEFT", CARD_PAD, -(y + 6))
    card.blurb:SetWidth(inner)
    if card.blurb.SetMaxLines then pcall(card.blurb.SetMaxLines, card.blurb, CARD_LINES) end
    card.blurb:SetText(blurb)
    card.blurb:SetShown(blurb ~= "")
    if blurb ~= "" then
        y = y + 6 + math.min(card.blurb:GetStringHeight() or 12, CARD_LINES * 13)
        full_text[#full_text + 1] = blurb
    end

    card.button:ClearAllPoints()
    card.button:SetPoint("BOTTOMRIGHT", -CARD_PAD, CARD_PAD - 2)
    card.news:ClearAllPoints()
    card.news:SetPoint("BOTTOMLEFT", CARD_PAD, CARD_PAD)
    -- The primary button always opens the addon (the everyday thing). Setting up comes first when
    -- it is needed, and anything unseen is a small link beside it, never the only way in.
    card.button:SetText(reason and SetupLabel(p) or "Open")
    card.action = reason and "page" or "addon"
    card.news:SetShown(Unseen(p) and not reason)
    card.tooltip = #full_text > 0 and full_text or nil
    card:Show()
    -- Room for the text, then the button row.
    return math.max(CARD_MIN_H, math.ceil(y + 10 + 21 + CARD_PAD - 2))
end

local function LayoutCards()
    local list = Sorted()
    local width = win.cardHost:GetWidth()
    if not width or width < CARD_W then width = WIN_W - 48 - 26 end
    local cols = math.max(1, math.floor((width + CARD_GAP) / (CARD_W + CARD_GAP)))
    local needy, fine = {}, {}
    for _, p in ipairs(list) do
        if SetupReason(p) then needy[#needy + 1] = p else fine[#fine + 1] = p end
    end
    for _, c in ipairs(win.cards) do c:Hide() end

    local i, top = 0, 0
    -- One group at a time: fill every card in a row, then give the whole row the tallest height.
    local function Rows(group, full)
        for first = 1, #group, cols do
            local rowH, row = 0, {}
            for n = first, math.min(first + cols - 1, #group) do
                i = i + 1
                local card = CardFor(i)
                rowH = math.max(rowH, FillCard(card, group[n], full))
                row[#row + 1] = card
            end
            for n, card in ipairs(row) do
                card:SetHeight(rowH)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", (n - 1) * (CARD_W + CARD_GAP), top)
            end
            top = top - rowH - CARD_GAP
        end
    end

    Rows(needy, true)
    win.allSet:ClearAllPoints()
    win.allSet:SetPoint("TOPLEFT", 2, top - 2)
    win.allSet:SetShown(#fine > 0 and #needy > 0)
    if #fine > 0 and #needy > 0 then top = top - 22 end
    Rows(fine, #needy == 0)

    local height = math.max(1, -top + 6)
    win.cardHost:SetHeight(height)
    return height
end

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
    b:SetScript("OnClick", function(self)
        if self.kind == "settings" then
            ShowSettings(self.id ~= "_shared" and self.id or nil)
        else
            Select(self.id)
        end
    end)
    win.sideButtons[i] = b
    return b
end

-- kind = "pages" (the addons' welcome pages) or "settings" (YippYapp + the addons' own panels).
local function LayoutSidebar(kind, currentId)
    local rows = {}
    if kind == "settings" then
        rows[1] = { id = "_shared", name = "YippYapp", shared = true }
        for _, entry in ipairs(LIB.OptionsPanels and LIB.OptionsPanels() or {}) do
            rows[#rows + 1] = { id = entry.id, name = entry.name, page = pages[entry.id] }
        end
    else
        for _, p in ipairs(Sorted()) do rows[#rows + 1] = { id = p.id, name = p.title or p.id, page = p } end
    end
    for _, b in ipairs(win.sideButtons) do b:Hide() end
    for i, row in ipairs(rows) do
        local b = SideButton(i)
        b.id, b.kind = row.id, kind
        if row.shared then
            b.icon:SetTexture(LIB.mediaPath and (LIB.mediaPath .. "yippyapp"))
            b.icon:SetVertexColor(1, 1, 1, 1)
        elseif row.page then
            SetIcon(b.icon, row.page)
        else
            b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
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

    -- Home: the banner, then a card per addon in a scrolling grid.
    win.cards, win.sideButtons = {}, {}
    win.home = CreateFrame("Frame", nil, win)
    win.home:SetPoint("TOPLEFT", 24, CONTENT_TOP)
    win.home:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -24, BOTTOM_BAR)
    win.banner = BuildBanner(win.home, WIN_W - 48)
    win.banner:SetPoint("TOPLEFT", 0, 0)
    -- People think the addons are broken when Forever forgets their settings, so say it here too.
    win.disclaimer = win.home:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.disclaimer:SetPoint("TOPLEFT", 2, -(BANNER_H + 8))
    win.disclaimer:SetPoint("RIGHT", win.home, "RIGHT", -2, 0)
    win.disclaimer:SetJustifyH("LEFT")
    win.disclaimer:SetSpacing(2)
    win.disclaimer:SetText("|cffffd100Note:|r WoW: Forever currently forgets addon settings when you "
        .. "restart the game - a known client bug, not these addons. Your settings may look reset.")

    local cardScroll = CreateFrame("ScrollFrame", nil, win.home, "UIPanelScrollFrameTemplate")
    win.cardScroll = cardScroll
    cardScroll:SetPoint("TOPLEFT", 0, -(BANNER_H + BANNER_GAP + DISCLAIMER_H))
    cardScroll:SetPoint("BOTTOMRIGHT", -26, 0)
    win.cardHost = CreateFrame("Frame", nil, cardScroll)
    win.cardHost:SetSize(WIN_W - 48 - 26, 10)
    cardScroll:SetScrollChild(win.cardHost)
    cardScroll:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then win.cardHost:SetWidth(w) LayoutCards() end
    end)
    win.allSet = win.cardHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.allSet:SetText("All set")
    win.allSet:SetTextColor(0.75, 0.72, 0.66)

    -- An addon page: a back button, the sidebar, and the page itself at its own size.
    win.back = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.back:SetSize(110, 22)
    win.back:SetPoint("TOPLEFT", 24, CONTENT_TOP + 4)
    win.back:SetText("< All addons")
    win.back:SetScript("OnClick", function() ShowHome() end)

    -- The settings wheel in the corner of an addon page: straight to that addon's settings.
    win.gear = CreateFrame("Button", nil, win)
    win.gear:SetSize(22, 22)
    win.gear:SetPoint("TOPRIGHT", -46, CONTENT_TOP + 2)
    win.gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    win.gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    win.gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Settings", 1, 0.82, 0.3)
        GameTooltip:Show()
    end)
    win.gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.gear:SetScript("OnClick", function() ShowSettings(win.current) end)
    win.gear:Hide()

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

    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT", 24 + SIDEBAR_W + 12, PAGE_TOP)
    win.body:SetSize(PAGE_W, TOTAL_H + PAGE_TOP - BOTTOM_BAR - 8)
    win.icon = win.body:CreateTexture(nil, "ARTWORK")
    win.icon:SetSize(32, 32)
    win.icon:SetPoint("TOPLEFT", 0, 0)
    win.heading = win.body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.heading:SetPoint("TOPLEFT", win.icon, "TOPRIGHT", 10, -1)
    win.subtitle = win.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.subtitle:SetPoint("TOPLEFT", win.heading, "BOTTOMLEFT", 0, -3)
    win.subtitle:SetPoint("RIGHT", win.body, "RIGHT", 0, 0)
    win.subtitle:SetJustifyH("LEFT")
    win.subtitle:SetWordWrap(false)

    -- The bottom row, on both views: where the shared settings are, and Done.
    win.done = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.done:SetSize(96, 22)
    win.done:SetPoint("BOTTOMRIGHT", -16, 14)
    win.done:SetText(DONE or "Done")
    win.done:SetScript("OnClick", function() win:Hide() end)

    -- Buy me a coffee lives in the window's footer, once, not inside a settings panel.
    win.coffee = CreateFrame("Button", nil, win)
    win.coffee:SetSize(22, 22)
    local logo = win.coffee:CreateTexture(nil, "ARTWORK")
    logo:SetAllPoints()
    if LIB.mediaPath then logo:SetTexture(LIB.mediaPath .. "bmc-logo") end
    logo:SetAlpha(0.75)
    win.coffee:SetScript("OnEnter", function(self)
        logo:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Buy me a coffee", 1, 0.85, 0.2)
        GameTooltip:AddLine("Click to copy the link.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    win.coffee:SetScript("OnLeave", function() logo:SetAlpha(0.75) GameTooltip:Hide() end)
    win.coffee:SetScript("OnClick", function()
        if LIB.ShowCoffeePopup then LIB.ShowCoffeePopup() end
    end)

    win.settingsButton = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.settingsButton:SetSize(150, 22)
    win.settingsButton:SetPoint("RIGHT", win.done, "LEFT", -8, 0)
    win.coffee:SetPoint("RIGHT", win.settingsButton, "LEFT", -12, 0)
    win.settingsButton:SetText("YippYapp settings...")
    win.settingsButton:SetScript("OnClick", function()
        if LIB.OpenYippYappSettings then LIB.OpenYippYappSettings() end
    end)

    win.psst = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.psst:SetPoint("BOTTOMLEFT", 24, 14)
    win.psst:SetPoint("RIGHT", win.coffee, "LEFT", -12, 0)
    win.psst:SetJustifyH("LEFT")
    win.psst:SetWordWrap(false)   -- one line, always: it is cut short rather than wrapping
    win.psstRule = win:CreateTexture(nil, "ARTWORK")
    win.psstRule:SetAtlas("Options_HorizontalDivider")
    win.psstRule:SetHeight(1)
    win.psstRule:SetPoint("BOTTOMLEFT", 18, BOTTOM_BAR + 2)
    win.psstRule:SetPoint("RIGHT", win, "RIGHT", -20, 0)

    -- HookScript: RegisterWindow already hooked OnHide for Escape; SetScript would drop that.
    win:HookScript("OnHide", function() Close() end)
end

-- ---------------------------------------------------------------------------
-- Showing the two views
-- ---------------------------------------------------------------------------
local function Prepare()
    if not win then Build() end
    win.psst:SetText(PsstText(#Sorted() == 1 and (Sorted()[1].title or Sorted()[1].id) or nil))
    -- Opened from the Settings panel: show above it rather than closing it (closing Blizzard's
    -- Settings from addon code is forbidden; see Settings.lua).
    local overSettings = SettingsPanel and SettingsPanel:IsShown()
    win:SetFrameStrata(overSettings and "FULLSCREEN_DIALOG" or "HIGH")
    win:Show()
    win:Raise()
end

function ShowHome()
    Prepare()
    homeShown = true
    win.mode = "home"
    win.settingsButton:Show()
    if win.NineSlice and win.NineSlice.Text then win.NineSlice.Text:SetText("YippYapp") end
    win.home:Show()
    win.sideDivider:Hide()
    win.back:Hide()
    win.gear:Hide()
    win.side:Hide()
    win.body:Hide()
    win.settingsHost:Hide()
    for _, p in pairs(pages) do if p.page then p.page:Hide() end end
    -- The home page is as tall as its cards need, between a floor and the full window height, so a
    -- couple of addons don't leave a large empty area.
    local cards = LayoutCards()
    local chrome = -CONTENT_TOP + BANNER_H + BANNER_GAP + DISCLAIMER_H + BOTTOM_BAR + 8
    win:SetHeight(chrome + math.max(HOME_MIN_H, math.min(cards, TOTAL_H - chrome)))
    C_Timer.After(0, function()
        if win and win:IsShown() and win.home:IsShown() then
            LayoutCards()
            FitScroll(win.cardScroll, win.cardHost)
        end
    end)
end

-- Shared by the addon-page view and the settings view: sidebar on the left, content on the right.
local function ShowSplit(title, sidebarKind, currentId)
    Prepare()
    win.home:Hide()
    win.back:Show()
    win:SetHeight(TOTAL_H)
    if win.NineSlice and win.NineSlice.Text then win.NineSlice.Text:SetText(title) end
    local many = LayoutSidebar(sidebarKind, currentId) > 1
    win.side:SetShown(many)
    win.sideDivider:SetShown(many)
    local left = many and (24 + SIDEBAR_W + 12) or 24
    win.body:ClearAllPoints()
    win.body:SetPoint("TOPLEFT", left, PAGE_TOP)
    win.settingsHost:ClearAllPoints()
    win.settingsHost:SetPoint("TOPLEFT", left, PAGE_TOP)
    C_Timer.After(0, function()
        if win and win:IsShown() and win.side:IsShown() then FitScroll(win.sideScroll, win.sideHost) end
    end)
end

-- Open one addon's page (a card, the sidebar or LIB.OpenWelcome(id) lead here).
function Select(id)
    local p = pages[id]
    if not p then return ShowHome() end
    win.mode = "page"
    win.settingsButton:Show()
    viewed[id] = true
    win.current = id
    ShowSplit(p.title or p.id, "pages", id)
    win.settingsHost:Hide()
    win.body:Show()
    win.gear:SetShown(LIB.optionsPanels ~= nil and LIB.optionsPanels[id] ~= nil)

    for _, q in pairs(pages) do if q.page then q.page:Hide() end end
    SetIcon(win.icon, p)
    win.heading:SetText(p.title or p.id)
    win.subtitle:SetText(p.subtitle or "")
    local top = p.subtitle and p.subtitle ~= "" and -46 or -42
    local fresh = not p.page
    p.page = p.page or CreateFrame("Frame", nil, win.body)
    p.page:ClearAllPoints()
    p.page:SetPoint("TOPLEFT", 0, top)
    p.page:SetSize(PAGE_W, win.body:GetHeight() + top)
    if fresh and p.build then
        local ok, err = pcall(p.build, p.page)
        if not ok then
            LIB.Debug("welcome page %s: %s", id, tostring(err))
            local fs = p.page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            fs:SetPoint("TOPLEFT")
            fs:SetText("This page could not be drawn.")
        end
    end
    p.page:Show()
    if p.onShow then pcall(p.onShow, p.page) end
end

-- The settings view: the shared YippYapp settings, or one addon's own panel, hosted in our window.
function ShowSettings(id)
    if not win then Build() end
    local panels = LIB.OptionsPanels and LIB.OptionsPanels() or {}
    if id and not (LIB.optionsPanels and LIB.optionsPanels[id]) then id = nil end
    win.mode = "settings"
    win.settingsId = id
    win.settingsButton:Hide()
    ShowSplit(id and ((LIB.optionsPanels[id].name or id) .. " settings") or "YippYapp settings",
        "settings", id or "_shared")
    win.body:Hide()
    win.gear:Hide()
    win.settingsHost:Show()

    -- Hide whatever was hosted before, then show what was asked for.
    if win.sharedSettings then win.sharedSettings:Hide() end
    for _, entry in ipairs(panels) do
        local shown = entry.frame.libForeverHost or entry.frame
        if shown ~= nil then shown:Hide() end
    end
    if not id then
        win.sharedSettings = win.sharedSettings or (LIB.BuildYippYappSettings and LIB.BuildYippYappSettings(win.settingsHost))
        if win.sharedSettings then
            win.sharedSettings:Show()
            if win.sharedSettings.Refresh then win.sharedSettings:Refresh() end
        end
        return
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

-- Closing marks every page that was looked at as seen, and the banner's message as read.
function Close()
    for id in pairs(viewed) do
        local p = pages[id]
        if p then SeenTable(p)[id] = p.version or 1 end
    end
    if homeShown or next(viewed) then MarkNoticeSeen() end
    homeShown = false
    wipe(viewed)
end

--- Open the window on its settings view (id: that addon's own settings).
function LIB.OpenWelcomeSettings(id)
    if not win then Build() end
    ShowSettings(id)
end

--- Open the window: on the home page, or straight to one addon's page.
--- id may be a page id or a launcher entry id.
function LIB.OpenWelcome(id)
    if #Sorted() == 0 then return end
    if id and not pages[id] then
        for _, p in pairs(pages) do if p.launcher == id then id = p.id break end end
    end
    if id and pages[id] then Select(id) else ShowHome() end
end

-- ---------------------------------------------------------------------------
-- Opening by itself: only for an unseen page that needs setup, never in combat or an instance
-- ---------------------------------------------------------------------------
local function CanAutoOpen()
    if InCombatLockdown() or UnitAffectingCombat("player") then return false end
    local inInstance = IsInInstance()
    return not inInstance
end

-- Opening by itself is OFF while Forever loses saved variables on a cold start (client bug 69913):
-- "seen" cannot survive that, so the window would greet everyone every session, which is worse than
-- missing the notice. Set these back to true when the client is fixed.
local AUTO_OPEN_FOR_SETUP = false    -- first run: open on the addons that need setting up
local AUTO_OPEN_FOR_NOTICE = false   -- once after an update with a new banner message

local Evaluate
function Evaluate()
    if LIB.welcomeVersion ~= VERSION or not loginDone then return end
    if win and win:IsShown() then return end
    -- If we can't trust what is saved, we don't know what the player has already seen or done.
    if LIB.SavedVariablesLoaded and not LIB.SavedVariablesLoaded() then autoPending = nil return end
    local setup = false
    if AUTO_OPEN_FOR_SETUP and SetupKnown() then
        for _, p in ipairs(Sorted(Unseen)) do if NeedsSetup(p) then setup = true end end
    end
    -- Besides setup, the window opens once after an update with a new banner message (NOTICE).
    local notice = AUTO_OPEN_FOR_NOTICE and NoticePending()
    if not setup and not notice then autoPending = nil return end
    -- Only the banner message would open the window: look again a few seconds later first, in case a
    -- saved table (and its "seen" flag) arrives late. Better to miss the notice than to nag.
    if notice and not setup and not LIB.welcomeNoticeRechecked then
        LIB.welcomeNoticeRechecked = true
        LIB.Debounce("welcome", 6, Evaluate)
        return
    end
    if not CanAutoOpen() then autoPending = true return end
    autoPending = nil
    ShowHome()
end

LIB.RegisterWelcomePage = nil  -- set below, after RegisterWelcome exists

function LIB.RegisterWelcome(entry, savedTable)
    if type(entry) ~= "table" or not entry.id then return end
    entry.store = savedTable
    -- Registered after the message was marked as seen: mark this addon too, so it doesn't bring
    -- the window back on the next login.
    if savedTable and LIB.welcomeNoticeMarked then savedTable.welcomeNotice = NOTICE end
    local old = pages[entry.id]
    if old and old.page then old.page:Hide() end
    pages[entry.id] = entry
    -- Registered after login (a load-on-demand addon): look again shortly.
    if loginDone then LIB.Debounce("welcome", AUTO_DELAY, Evaluate) end
end

LIB.RegisterWelcomePage = LIB.RegisterWelcome   -- the name the addons may use

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
        if LIB.MinimapDebug then LIB.MinimapDebug() elseif LIB.DebugMinimap then LIB.DebugMinimap() end
        return
    end
    -- "/yippyapp settings": the shared YippYapp settings page.
    if msg and msg:lower():match("^%s*setting") then
        if LIB.OpenYippYappSettings then LIB.OpenYippYappSettings() end
        return
    end
    if LIB.OpenWelcome then LIB.OpenWelcome() end
end
