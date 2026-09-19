--- LibForever-1.0: minimap buttons through LibDataBroker-1.1 + LibDBIcon-1.0.
-- LibDBIcon draws the button with the client's own ring geometry, so it sits right in the ring.
-- LibForever doesn't embed either library: each addon ships them in its own Libs\ and this helper
-- looks them up when it is called. Without them it returns false and the addon carries on.
--
-- By default all YippYapp addons share ONE minimap button (LibDBIcon id "YippYapp"). Clicking it opens
-- a small row with each addon's own button; those behave exactly like the addon's button (same clicks,
-- same tooltip). With a single addon the shared button simply is that addon's button. Every addon keeps
-- its own LDB object, so broker displays (Titan, ChocolateBar, ElvUI) still list each one; only the
-- LibDBIcon minimap view is grouped. Ungrouped, each addon gets its own minimap button as before.
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

local VERSION = 3
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
local shared = LIB.minimapShared or { fresh = true, data = {} }
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
    if type(saved) == "table" and saved ~= shared.data then
        if shared.fresh then
            for k, v in pairs(saved) do shared.data[k] = v end
            shared.fresh = false
        end
    elseif shared.fresh and shared.data.minimapPos == nil and store.minimap and store.minimap.minimapPos then
        -- First time grouped: start where this addon's own button was.
        shared.data.minimapPos = store.minimap.minimapPos
    end
    store.yippyappMinimap = shared.data
end

-- ---------------------------------------------------------------------------
-- The row of addon buttons that the shared button opens
-- ---------------------------------------------------------------------------
local SIZE, PAD, GAP = 28, 8, 6
local flyout = LIB.minimapFlyout

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
        local e = buttons[self.id]
        if e and e.opts.OnClick then e.opts.OnClick(self, mouse) end
    end)
    b:SetScript("OnEnter", function(self)
        local e = buttons[self.id]
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if e.opts.OnTooltipShow then e.opts.OnTooltipShow(GameTooltip)
        else GameTooltip:AddLine(e.opts.label or self.id, 1, 0.82, 0.3) end
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
    for i, e in ipairs(members) do
        local b = FlyoutButton(i)
        b.id = e.id
        b.icon:SetTexture(e.opts.icon)
        b:ClearAllPoints()
        b:SetPoint("LEFT", PAD + (i - 1) * (SIZE + GAP), 0)
        b:Show()
    end
    flyout:SetSize(PAD * 2 + #members * SIZE + (#members - 1) * GAP, SIZE + PAD * 2)
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
function LIB.MinimapGroupClick(frame, mouse)
    local members = Members()
    if #members == 1 then
        if members[1].opts.OnClick then members[1].opts.OnClick(frame, mouse) end
    elseif #members > 1 then
        ToggleFlyout(frame, members)
    end
end

function LIB.MinimapGroupTooltip(tooltip)
    local members = Members()
    if #members == 1 then
        local o = members[1].opts
        if o.OnTooltipShow then o.OnTooltipShow(tooltip) else tooltip:AddLine(o.label or members[1].id) end
        return
    end
    local emblem = Emblem()
    tooltip:AddLine((emblem and ("|T" .. emblem .. ":16:16:0:0|t ") or "") .. "YippYapp", 1, 0.82, 0.3)
    tooltip:AddLine("Click to open your YippYapp addons.", 1, 1, 1)
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
    if flyout and (not grouped or #members < 2) then flyout:Hide() end

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
LIB.RefreshMinimapButtons = Refresh

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
    Adopt(savedTable)
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
    shared.fresh = false
    Refresh()
end

-- A newer copy loaded after addons registered with an older one: redraw with this version.
if next(buttons) then Refresh() end
