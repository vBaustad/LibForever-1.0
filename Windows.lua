--- LibForever-1.0: window handling shared by every YippYapp window.
-- Our windows used to share a strata without being toplevel, so two overlapping windows mixed their
-- children and a click didn't bring one to the front. Registered windows instead:
--   * are toplevel on one strata and come to the front when shown or clicked;
--   * drag by their frame and remember where they were put, in the addon's own saved table;
--   * the first time (nothing saved yet) open beside our other open windows instead of on top of
--     them, or cascade when there is no room;
--   * close one at a time with Escape, the frontmost first.
-- No ShowUIPanel/UIPanelWindows: those are Blizzard's panel manager and taint-prone.
--
--   LIB.RegisterWindow(frame, savedTable, key)
--       savedTable[key] = { x = left, y = top } (TOPLEFT against UIParent's BOTTOMLEFT, the format our
--       addons already use, so existing positions carry over). savedTable may be nil: then the window
--       is placed fresh every session. Registering replaces the frame's OnDragStart/OnDragStop and
--       takes it out of UISpecialFrames; OnShow, OnHide and OnMouseDown are hooked, not replaced.
--       After registering, add your own OnShow/OnHide with HookScript: SetScript would drop our
--       hooks, and Escape would then stop closing windows.
--       The close button (ClosePanelButton / CloseButton / a UIPanelCloseButton child) is rewired to
--       f:Hide(), so it works in combat (Blizzard's goes through HideUIPanel, which refuses there);
--       f.onCloseCallback(button) is still honoured: return false to keep the frame open.
--   LIB.RaiseWindow(frame)             bring it to the front
--   LIB.ResetWindowPosition(frame)     forget the saved position: centre it (or beside our open windows)
--   LIB.RegisterPopup(frame)
--       Escape handling only, for small popups that keep their own place and DIALOG strata: the
--       frame leaves UISpecialFrames, and Escape closes the most recently shown open popup before
--       any window. Hooks OnShow/OnHide and rewires its close button the same way; calling it twice
--       is harmless.
-- Escape and the close buttons only ever call :Hide() on our own frames, never HideUIPanel, so they
-- work in combat too.
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 3
if (LIB.windowsVersion or 0) >= VERSION then return end
LIB.windowsVersion = VERSION

local STRATA = "HIGH"
local GAP = 12      -- between side-by-side windows
local CASCADE = 32  -- offset when there is no room beside

local windows = LIB.windows or {}  -- [frame] = { store, key, raised, placed }
LIB.windows = windows
local raiseCount = LIB.windowRaiseCount or 0
local popups = LIB.windowPopups or {}  -- [frame] = order it was last shown in
LIB.windowPopups = popups

-- ---------------------------------------------------------------------------
-- Geometry, all in UIParent units
-- ---------------------------------------------------------------------------
local function Ratio(f)
    return f:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function Rect(f)
    local l, t = f:GetLeft(), f:GetTop()
    if not l or not t then return nil end
    local r = Ratio(f)
    return { l = l * r, t = t * r, w = f:GetWidth() * r, h = f:GetHeight() * r }
end

local function Overlaps(a, b)
    return a.l < b.l + b.w and b.l < a.l + a.w and a.t - a.h < b.t and b.t - b.h < a.t
end

local function OnScreen(a)
    return a.l >= 0 and a.t <= UIParent:GetHeight() and a.l + a.w <= UIParent:GetWidth() and a.t - a.h >= 0
end

local function MoveTo(f, l, t)
    local r = Ratio(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l / r, t / r)
end

-- Our other windows that are open, frontmost last.
local function OpenOthers(self)
    local list = {}
    for f, w in pairs(windows) do
        if f ~= self and f:IsShown() then
            local rect = Rect(f)
            if rect then rect.raised = w.raised or 0; list[#list + 1] = rect end
        end
    end
    table.sort(list, function(a, b) return a.raised < b.raised end)
    return list
end

-- First placement: keep the addon's own default anchor when nothing else of ours is open;
-- otherwise the free spot beside an open window that is nearest the screen centre, else a cascade.
local function Place(f)
    local others = OpenOthers(f)
    if #others == 0 then return end
    local r = Ratio(f)
    local w, h = f:GetWidth() * r, f:GetHeight() * r
    local cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    local best, bestDist
    for _, o in ipairs(others) do
        local spots = {
            { l = o.l + o.w + GAP, t = o.t },                        -- right of it
            { l = o.l - GAP - w, t = o.t },                          -- left of it
            { l = o.l + (o.w - w) / 2, t = o.t - o.h - GAP },        -- below it
            { l = o.l + (o.w - w) / 2, t = o.t + h + GAP },          -- above it
        }
        for _, s in ipairs(spots) do
            s.w, s.h = w, h
            local free = OnScreen(s)
            for _, q in ipairs(others) do
                if free and Overlaps(s, q) then free = false end
            end
            if free then
                local dx, dy = s.l + w / 2 - cx, s.t - h / 2 - cy
                local d = dx * dx + dy * dy
                if not bestDist or d < bestDist then best, bestDist = s, d end
            end
        end
    end
    if not best then
        local top = others[#others]
        best = { l = top.l + CASCADE, t = top.t - CASCADE }
        best.l = math.max(0, math.min(UIParent:GetWidth() - w, best.l))
        best.t = math.min(UIParent:GetHeight(), math.max(h, best.t))
    end
    MoveTo(f, best.l, best.t)
end

local function Restore(f)
    local w = windows[f]
    local pos = w and w.store and w.store[w.key]
    if type(pos) == "table" and pos.x and pos.y then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Front-to-back order
-- ---------------------------------------------------------------------------
function LIB.RaiseWindow(f)
    local w = windows[f]
    if not w then return end
    raiseCount = raiseCount + 1
    LIB.windowRaiseCount = raiseCount
    w.raised = raiseCount
    f:Raise()
end

local function Frontmost()
    local top, topRaised
    for f, w in pairs(windows) do
        if f:IsShown() and (not topRaised or (w.raised or 0) > topRaised) then top, topRaised = f, w.raised or 0 end
    end
    return top
end

-- The popup to close first: the most recently shown one still on screen.
local function LastPopup()
    local top, topOrder
    for f, order in pairs(popups) do
        if f:IsVisible() and (not topOrder or order > topOrder) then top, topOrder = f, order end
    end
    return top
end

-- Escape: Blizzard's UISpecialFrames closes every listed frame at once. Only this stand-in is listed
-- (built once, reused by newer copies of this file); it is shown while any of our popups or windows
-- is, and closing it closes just one: the last popup, else the frontmost window.
local escape = LIB.windowEscape
if not escape then
    escape = CreateFrame("Frame", "LibForeverWindowEscape", UIParent)
    LIB.windowEscape = escape
    tinsert(UISpecialFrames, "LibForeverWindowEscape")
end

-- Hooks call through LIB, so frames hooked by an older copy use this version's code.
function LIB.SyncWindowEscape()
    LIB.windowEscapeSyncing = true
    escape:SetShown(LastPopup() ~= nil or Frontmost() ~= nil)
    LIB.windowEscapeSyncing = nil
end
local function SyncLater() C_Timer.After(0, function() LIB.SyncWindowEscape() end) end

escape:SetScript("OnHide", function()
    -- Only an Escape press counts: not our own sync, and not the whole UI being hidden (Alt+Z).
    if LIB.windowsVersion ~= VERSION or LIB.windowEscapeSyncing or not UIParent:IsVisible() then return end
    local top = LastPopup() or Frontmost()
    if top then top:Hide() end
    -- More of ours still open: the next Escape closes the next one.
    SyncLater()
end)
LIB.SyncWindowEscape()

-- The template's X (UIPanelCloseButton) closes through HideUIPanel, which refuses in combat for addon
-- frames ("Interface action failed because of an AddOn"). Plain Hide() on our unprotected frames
-- always works, so the X is rewired to that, keeping Blizzard's onCloseCallback contract.
local function FindCloseButton(f)
    if f.ClosePanelButton then return f.ClosePanelButton end
    if f.CloseButton then return f.CloseButton end
    for _, child in ipairs({ f:GetChildren() }) do
        if child.GetScript and child:GetObjectType() == "Button"
            and child:GetScript("OnClick") == UIPanelCloseButton_OnClick then
            return child
        end
    end
end

local function RewireClose(f)
    local close = FindCloseButton(f)
    if not close then return end
    close:SetScript("OnClick", function(self)
        local go = true
        if f.onCloseCallback then go = f.onCloseCallback(self) end
        if go then f:Hide() end
    end)
end

local function LeaveSpecialFrames(f)
    local name = f:GetName()
    if not name then return end
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then tremove(UISpecialFrames, i) end
    end
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
function LIB.RegisterWindow(f, savedTable, key)
    if not f then return end
    local w = windows[f]
    if not w then
        w = {}
        windows[f] = w
        f:HookScript("OnShow", function(self)
            local ww = windows[self]
            if not ww then return end
            if not ww.placed and not Restore(self) then Place(self) end
            ww.placed = true
            LIB.RaiseWindow(self)
            LIB.SyncWindowEscape()
        end)
        f:HookScript("OnHide", function() SyncLater() end)
        f:HookScript("OnMouseDown", function(self) LIB.RaiseWindow(self) end)
    end
    w.store, w.key = savedTable, key or "pos"

    f:SetToplevel(true)
    f:SetFrameStrata(STRATA)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        LIB.RaiseWindow(self)
        -- A window holding protected (secure) children can't be moved in combat; say so.
        if InCombatLockdown() and self:IsProtected() then
            UIErrorsFrame:AddMessage("Can't move this window during combat.", 1, 0.2, 0.2)
            return
        end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Our saved table remembers it, not the client's layout cache.
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        local ww = windows[self]
        if ww and ww.store then ww.store[ww.key] = { x = self:GetLeft(), y = self:GetTop() } end
    end)

    -- Escape goes through the stand-in above, one window at a time; the X works in combat.
    LeaveSpecialFrames(f)
    RewireClose(f)

    if Restore(f) then w.placed = true end
    if f:IsShown() then
        if not w.placed then Place(f) w.placed = true end
        LIB.RaiseWindow(f)
        LIB.SyncWindowEscape()
    end
end

function LIB.ResetWindowPosition(f)
    local w = windows[f]
    if not w then return end
    if w.store then w.store[w.key] = nil end
    w.placed = true
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    if f:IsShown() then Place(f) end
end

-- Popups: only Escape handling. Their place, strata and scripts stay the addon's own.
function LIB.RegisterPopup(f)
    if not f then return end
    LeaveSpecialFrames(f)
    RewireClose(f)
    if popups[f] then return end
    popups[f] = f:IsShown() and raiseCount + 1 or 0
    f:HookScript("OnShow", function(self)
        raiseCount = raiseCount + 1
        LIB.windowRaiseCount = raiseCount
        popups[self] = raiseCount
        LIB.SyncWindowEscape()
    end)
    f:HookScript("OnHide", function() SyncLater() end)
    LIB.SyncWindowEscape()
end
