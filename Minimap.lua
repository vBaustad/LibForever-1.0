--- LibForever-1.0: minimap buttons through LibDataBroker-1.1 + LibDBIcon-1.0.
-- LibDBIcon draws the button with the client's own ring geometry, so it sits right in the ring.
-- LibForever doesn't embed either library: each addon ships them in its own Libs\ and this helper
-- looks them up when it is called. Without them it returns false and the addon carries on.
--
-- By default all YippYapp addons share ONE minimap button (LibDBIcon id "YippYapp"): left-click opens
-- a row with one icon per addon (click one to open that addon; the last icon opens the YippYapp
-- window), and right-click opens the YippYapp settings. Every addon keeps its own LDB object, so
-- broker displays (Titan, ChocolateBar, ElvUI) still list each one; only the LibDBIcon minimap view is
-- grouped. Ungrouped, each addon gets its own button with its own clicks, as before.
--
--   LIB.RegisterMinimapButton(id, opts, savedTable) -> true/false
--       opts = { icon, label, OnClick(frame, button), OnTooltipShow(tooltip), migrateAngle }
--       savedTable.minimap is LibDBIcon's own db ({ hide, minimapPos, lock }), created if missing;
--       a new one starts at opts.migrateAngle (degrees, math.deg(atan2(dy, dx))) when given.
--       Calling it again with the same id updates the button instead of registering twice.
--   LIB.SetMinimapButtonShown(id, shown)   whether this addon is on the minimap (grouped or alone)
--   LIB.IsMinimapButtonShown(id) -> bool
--   LIB.SetMinimapGrouped(on)   LIB.IsMinimapGrouped() -> bool   (default on)
--
-- The shared button's state (grouped flag, LibDBIcon position) lives in every registered addon's
-- saved table as savedTable.yippyappMinimap: one table, referenced from all of them, so it survives
-- whichever of our addons are installed. The lib has no SavedVariables of its own.
local ADDON = ...
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 11
if (LIB.minimapVersion or 0) >= VERSION then return end
LIB.minimapVersion = VERSION

-- The lib's own files, inside whichever addon this copy was loaded from.
if type(ADDON) == "string" then
    LIB.mediaPath = LIB.mediaPath or ("Interface\\AddOns\\" .. ADDON .. "\\Libs\\LibForever-1.0\\Media\\")
end

local GROUP = "YippYapp"
-- The YippYapp emblem (Media\yippyapp.tga) on the shared button; set to false to borrow the first
-- addon's icon instead (e.g. if the file is ever missing from a release).
local EMBLEM_READY = true

local function Emblem()
    return EMBLEM_READY and LIB.mediaPath and (LIB.mediaPath .. "yippyapp") or nil
end

local buttons = LIB.minimapButtons or {}  -- [id] = { store, object, opts, order }
LIB.minimapButtons = buttons
local shared = LIB.minimapShared or { data = {} }
LIB.minimapShared = shared
local registerCount = LIB.minimapRegisterCount or 0

local function Libs()
    return LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
end

local function Members()
    local list = {}
    for id, b in pairs(buttons) do
        if not (b.store.minimap and b.store.minimap.hide) then list[#list + 1] = b end
    end
    table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return list
end

function LIB.IsMinimapGrouped()
    return shared.data.group ~= false
end

-- ---------------------------------------------------------------------------
-- Shared state: adopt the first saved copy we see, then point every addon's table at the same one
-- ---------------------------------------------------------------------------
local function Adopt(store)
    local saved = store.yippyappMinimap
    -- Take whatever this addon remembers and we don't have yet. An EMPTY saved table must not count
    -- as "adopted": that used to freeze the shared state empty for good, so the shared button lost
    -- its place on every reload.
    if type(saved) == "table" and saved ~= shared.data then
        for k, v in pairs(saved) do
            if shared.data[k] == nil then shared.data[k] = v end
        end
    end
    -- Still no place of its own: start where this addon's own button was.
    if shared.data.minimapPos == nil and store.minimap and store.minimap.minimapPos then
        shared.data.minimapPos = store.minimap.minimapPos
    end
    store.yippyappMinimap = shared.data
end

-- ---------------------------------------------------------------------------
-- The row the shared button opens: one icon per addon, plus the YippYapp window at the end.
-- Clicking an icon opens THAT addon, which is the everyday path: two clicks from the minimap, the
-- same as before the window existed.
-- ---------------------------------------------------------------------------
local SIZE, PAD, GAP = 28, 8, 6
local flyout = LIB.minimapFlyout

-- What one entry in the row does: open the addon itself (the welcome window knows each addon's own
-- action), else its minimap click.
local function OpenEntry(id, frame, mouse)
    mouse = mouse or "LeftButton"
    if id == GROUP then
        if mouse == "RightButton" and LIB.OpenYippYappSettings then
            LIB.OpenYippYappSettings()
        elseif LIB.OpenWelcome then
            LIB.OpenWelcome()
        end
        return
    end
    local e = buttons[id]
    -- The family's convention: left-click opens the addon (its own window, or its settings when it
    -- hasn't got one), right-click always opens that addon's settings.
    if mouse ~= "LeftButton" then
        if LIB.optionsPanels and LIB.optionsPanels[id] and LIB.OpenAddonSettings then
            LIB.OpenAddonSettings(id)
        elseif e and e.opts.OnClick then
            e.opts.OnClick(frame, mouse)          -- its own right-click, usually its settings
        elseif LIB.OpenAddonSettings then
            LIB.OpenAddonSettings(id)             -- never nothing
        end
    elseif LIB.OpenAddon then
        LIB.OpenAddon(id)
    elseif e and e.opts.OnClick then
        e.opts.OnClick(frame, mouse)
    end
end

local function FlyoutButton(i)
    local b = flyout.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, flyout)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    b:SetScript("OnClick", function(self, mouse)
        flyout:Hide()
        OpenEntry(self.id, self, mouse)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if self.id == GROUP then
            GameTooltip:AddLine("YippYapp", 1, 0.82, 0.3)
            GameTooltip:AddLine("Left-click: your addons and what's new", 1, 1, 1)
            GameTooltip:AddLine("Right-click: YippYapp settings", 1, 1, 1)
        else
            local e = buttons[self.id]
            if not e then return end
            if e.opts.OnTooltipShow then e.opts.OnTooltipShow(GameTooltip)
            else GameTooltip:AddLine(e.opts.label or self.id, 1, 0.82, 0.3) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    flyout.buttons[i] = b
    return b
end

local function BuildFlyout()
    if flyout and flyout.libVersion == VERSION then return end
    if flyout then flyout:Hide() end
    flyout = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    LIB.minimapFlyout = flyout
    flyout.libVersion = VERSION
    flyout.buttons = {}
    flyout:SetFrameStrata("DIALOG")
    flyout:SetClampedToScreen(true)
    flyout:EnableMouse(true)
    flyout:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    flyout:SetBackdropColor(0.05, 0.04, 0.03, 0.92)
    flyout:SetBackdropBorderColor(0.85, 0.80, 0.70, 1)
    flyout:Hide()
    -- A click anywhere else closes it (the shared button itself toggles it).
    flyout:SetScript("OnEvent", function(self)
        if self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver()) then return end
        self:Hide()
    end)
    flyout:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    flyout:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    if LIB.RegisterPopup then LIB.RegisterPopup(flyout) end  -- Escape closes it
end

local function ToggleFlyout(anchor, members)
    BuildFlyout()
    if flyout:IsShown() then flyout:Hide() return end
    for _, b in ipairs(flyout.buttons) do b:Hide() end
    local n = 0
    for _, e in ipairs(members) do
        n = n + 1
        local b = FlyoutButton(n)
        b.id = e.id
        b.icon:SetTexture(e.opts.icon)
        b.icon:SetVertexColor(1, 1, 1, 1)
        b:ClearAllPoints()
        b:SetPoint("LEFT", PAD + (n - 1) * (SIZE + GAP), 0)
        b:Show()
    end
    -- Last in the row: the YippYapp window itself.
    n = n + 1
    local last = FlyoutButton(n)
    last.id = GROUP
    last.icon:SetTexture(Emblem() or (members[1] and members[1].opts.icon))
    last.icon:SetVertexColor(1, 1, 1, 1)
    last:ClearAllPoints()
    last:SetPoint("LEFT", PAD + (n - 1) * (SIZE + GAP), 0)
    last:Show()

    flyout:SetSize(PAD * 2 + n * SIZE + (n - 1) * GAP, SIZE + PAD * 2)
    -- Open towards the middle of the screen.
    flyout.anchor = anchor
    flyout:ClearAllPoints()
    local x = anchor:GetCenter()
    x = x and x * anchor:GetEffectiveScale() / UIParent:GetEffectiveScale() or 0
    if x > UIParent:GetWidth() / 2 then
        flyout:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    else
        flyout:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    end
    flyout:Show()
end

-- The shared button's handlers go through LIB, so a newer copy of this file takes them over.
-- It is the way into the YippYapp window: left-click opens it, right-click opens it on the settings.
function LIB.MinimapGroupClick(frame, mouse)
    if mouse == "RightButton" then
        if LIB.OpenYippYappSettings then LIB.OpenYippYappSettings() end
        return
    end
    local members = Members()
    if #members == 1 then
        OpenEntry(members[1].id, frame, mouse)   -- one addon: straight there
    else
        ToggleFlyout(frame, members)             -- the row: one click per addon
    end
end

function LIB.MinimapGroupTooltip(tooltip)
    local members = Members()
    local emblem = Emblem()
    tooltip:AddLine((emblem and ("|T" .. emblem .. ":16:16:0:0|t ") or "") .. "YippYapp", 1, 0.82, 0.3)
    tooltip:AddLine("Left-click: pick an addon to open", 1, 1, 1)
    tooltip:AddLine("Right-click: YippYapp settings", 1, 1, 1)
    for _, e in ipairs(members) do tooltip:AddLine(e.opts.label or e.id, 0.8, 0.8, 0.8) end
end

-- ---------------------------------------------------------------------------
-- What the minimap shows
-- ---------------------------------------------------------------------------
local function Refresh()
    local ldb, dbicon = Libs()
    if not ldb or not dbicon then return end
    local members = Members()
    local grouped = LIB.IsMinimapGrouped()

    local obj = ldb:GetDataObjectByName(GROUP)
    if grouped and #members > 0 then
        local icon = #members > 1 and Emblem() or members[1].opts.icon
        if not obj then
            obj = ldb:NewDataObject(GROUP, {
                type = "launcher", label = "YippYapp", icon = icon, iconCoords = { 0, 1, 0, 1 },
                OnClick = function(frame, mouse) LIB.MinimapGroupClick(frame, mouse) end,
                OnTooltipShow = function(tooltip) LIB.MinimapGroupTooltip(tooltip) end,
            })
        end
        if obj then
            obj.icon = icon
            if dbicon:IsRegistered(GROUP) then
                pcall(dbicon.Refresh, dbicon, GROUP, shared.data)
            else
                local ok, err = pcall(dbicon.Register, dbicon, GROUP, obj, shared.data)
                if not ok then LIB.Debug("minimap group: %s", tostring(err)) end
            end
        end
    elseif dbicon:IsRegistered(GROUP) then
        dbicon:Hide(GROUP)
    end

    for id, b in pairs(buttons) do
        local show = not grouped and not (b.store.minimap and b.store.minimap.hide)
        if show and not dbicon:IsRegistered(id) then
            local ok, err = pcall(dbicon.Register, dbicon, id, b.object, b.store.minimap)
            if not ok then LIB.Debug("minimap button %s: %s", id, tostring(err)) end
        elseif dbicon:IsRegistered(id) then
            if show then dbicon:Refresh(id, b.store.minimap) else dbicon:Hide(id) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------
function LIB.RegisterMinimapButton(id, opts, savedTable)
    if not id or type(opts) ~= "table" or type(savedTable) ~= "table" then return false end
    local ldb, dbicon = Libs()
    if not ldb or not dbicon then return false end

    if type(savedTable.minimap) ~= "table" then
        savedTable.minimap = {}
        if tonumber(opts.migrateAngle) then savedTable.minimap.minimapPos = tonumber(opts.migrateAngle) % 360 end
    end

    local obj = ldb:GetDataObjectByName(id)
    if not obj then
        obj = ldb:NewDataObject(id, { type = "launcher", icon = opts.icon, iconCoords = { 0, 1, 0, 1 } })
        if not obj then return false end
    end
    -- Set (or refresh on a second call) through the proxy, so LDB displays see the change.
    obj.icon = opts.icon
    obj.label = opts.label or id
    obj.OnClick = opts.OnClick
    obj.OnTooltipShow = opts.OnTooltipShow

    local b = buttons[id]
    if not b then
        registerCount = registerCount + 1
        LIB.minimapRegisterCount = registerCount
        b = { id = id, order = registerCount }
        buttons[id] = b
    end
    b.store, b.object, b.opts = savedTable, obj, opts
    -- For the diagnostics: what this addon's own button remembered when it registered.
    b.loadedPos = savedTable.minimap and savedTable.minimap.minimapPos
    Adopt(savedTable)
    if LIB.NoteMinimapRead then LIB.NoteMinimapRead("register " .. id) end
    Refresh()
    return true
end

function LIB.SetMinimapButtonShown(id, shown)
    local b = buttons[id]
    if not b then return end
    b.store.minimap = b.store.minimap or {}
    b.store.minimap.hide = not shown or nil
    Refresh()
end

function LIB.IsMinimapButtonShown(id)
    local b = buttons[id]
    if not b then return false end
    return not (b.store.minimap and b.store.minimap.hide)
end

function LIB.SetMinimapGrouped(on)
    shared.data.group = on and true or false
    Refresh()
end

-- Support diagnostics (a hidden command): where the shared button's place is meant to come from.
function LIB.DebugMinimap()
    local function out(fmt, ...) print("|cffffd100YippYapp|r " .. fmt:format(...)) end
    local ldb, dbicon = Libs()
    local button = dbicon and dbicon:GetMinimapButton(GROUP)
    out("minimap v%d, grouped=%s, LDB=%s, LibDBIcon=%s, shared button=%s, its db is the shared table: %s",
        VERSION, tostring(LIB.IsMinimapGrouped()), tostring(ldb ~= nil), tostring(dbicon ~= nil),
        tostring(button ~= nil), tostring(button ~= nil and button.db == shared.data))
    out("shared state: minimapPos=%s, hide=%s, group=%s", tostring(shared.data.minimapPos),
        tostring(shared.data.hide), tostring(shared.data.group))
    for id, b in pairs(buttons) do
        out("%s: own minimapPos=%s (at register %s), table shared: %s, in the group: %s, own button: %s", id,
            tostring(b.store.minimap and b.store.minimap.minimapPos), tostring(b.loadedPos),
            tostring(b.store.yippyappMinimap == shared.data), tostring(LIB.IsMinimapButtonShown(id)),
            tostring(dbicon ~= nil and dbicon:IsRegistered(id)))
    end
end

-- ---------------------------------------------------------------------------
-- Late saved variables, and a client that moves things back
-- Forever resets saved positions after a reload for other addons and for Blizzard's own frames too,
-- so the position is read and applied again at several points instead of only once at load: nothing
-- here ever writes a default over a saved position. Only a drag writes (LibDBIcon does that itself).
-- LIB.MinimapDebug() prints what was seen and when, which separates "nothing saved at load" from
-- "we applied it and something moved it afterwards".
-- ---------------------------------------------------------------------------
local trace = LIB.minimapTrace or {}
LIB.minimapTrace = trace

-- Registering a sub-table of the addon's own DB (Guildhall passes its settings) is normal, and not
-- the same as the DB having been swapped underneath us.
local function SubTableOf(db, store)
    for _, v in pairs(db) do if v == store then return true end end
    return false
end

local function Note(phase)
    local row = { phase = phase, at = (GetTime and math.floor(GetTime() * 10) / 10) or 0,
                  shared = shared.data.minimapPos, button = nil, addons = {} }
    local _, dbicon = Libs()
    local button = dbicon and dbicon:GetMinimapButton(GROUP)
    row.button = button and button.db and button.db.minimapPos
    for id, b in pairs(buttons) do
        local saved = rawget(_G, id .. "DB")
        local keys = 0
        for _ in pairs(b.store) do keys = keys + 1 end
        row.addons[id] = {
            keys = keys,   -- 0 means the table we were handed holds nothing at all
            group = b.store.yippyappMinimap and b.store.yippyappMinimap.minimapPos,
            own = b.store.minimap and b.store.minimap.minimapPos,
            sameTable = b.store.yippyappMinimap == shared.data,
            savedGlobal = type(saved) == "table" and saved ~= b.store and not SubTableOf(saved, b.store) or false,
        }
    end
    trace[#trace + 1] = row
    if #trace > 12 then tremove(trace, 1) end
end

-- A saved table that arrived (or was replaced) after we first read it: take the position from it,
-- but never the other way round.
local function AdoptLate()
    for id, b in pairs(buttons) do
        Adopt(b.store)
        if shared.data.minimapPos == nil then
            local saved = rawget(_G, id .. "DB")
            local late = type(saved) == "table" and saved.yippyappMinimap
            local pos = (type(late) == "table" and late.minimapPos)
                or (type(saved) == "table" and type(saved.minimap) == "table" and saved.minimap.minimapPos)
            if pos then shared.data.minimapPos = pos end
        end
    end
end

LIB.NoteMinimapRead = Note   -- the registration path notes what it saw too

-- The workaround only has to cover login: after a few passes the client has done whatever it does,
-- so it stops instead of running again on every zone change.
local MAX_REAPPLY = 4
LIB.minimapReapplies = 0   -- a newer copy of this file gets its own passes

--- Read the saved position again and put the button back where it belongs.
function LIB.ReapplyMinimap(phase)
    if LIB.minimapVersion ~= VERSION then return end
    LIB.minimapReapplies = (LIB.minimapReapplies or 0) + 1
    if LIB.minimapReapplies > MAX_REAPPLY then return end
    AdoptLate()
    Note(phase or "reapply")
    Refresh()
end

if not LIB.minimapReapplyHooked then
    LIB.minimapReapplyHooked = true
    LIB.On("PLAYER_LOGIN", function() LIB.ReapplyMinimap("PLAYER_LOGIN") end)
    LIB.On("PLAYER_ENTERING_WORLD", function() LIB.ReapplyMinimap("PLAYER_ENTERING_WORLD") end)
    C_Timer.After(2, function() LIB.ReapplyMinimap("login + 2s") end)
end

-- Support diagnostics (a hidden command): what was read, and when.
function LIB.MinimapDebug()
    local function out(fmt, ...) print("|cffffd100YippYapp|r " .. fmt:format(...)) end
    LIB.DebugMinimap()
    if #trace == 0 then out("no minimap readings yet") return end
    for _, row in ipairs(trace) do
        out("%s (%.1fs): shared=%s, button=%s", row.phase, row.at, tostring(row.shared), tostring(row.button))
        for id, a in pairs(row.addons) do
            out("   %s: keys=%s, saved group=%s, own=%s, shares the table: %s%s", id, tostring(a.keys),
                tostring(a.group), tostring(a.own), tostring(a.sameTable),
                a.savedGlobal and ", NOTE: <Addon>DB is another table than the one it registered" or "")
        end
    end
end

-- A newer copy loaded after addons registered with an older one: redraw with this version.
if next(buttons) then Refresh() end
