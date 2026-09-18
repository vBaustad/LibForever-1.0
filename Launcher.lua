--- LibForever-1.0: the launcher notch.
-- One small bronze bar on a screen edge, shared by every addon that embeds LibForever: each addon
-- registers a button (white line icon), so the bar grows sideways as more of our addons are installed.
-- It wears Forever's own "heavybronze" frame with cut corners.
-- Drag slides it along its screen edge; it never leaves the edges. Right-click the bar for its options.
--
--   LIB.RegisterLauncher({ id, label, icon, onClick(button), status(), tooltip = {...}, order }, savedTable)
--   LIB.SetLauncherBadge(id, count)       LIB.SetLauncherHidden(id, hidden)   LIB.IsLauncherHidden(id)
--   LIB.LauncherOptions(parent, id) -> frame for an addon's settings page (show-icon toggle + bar style)
--
-- The lib has no SavedVariables of its own. Bar-wide settings (position, style) are written into every
-- registered addon's saved table and the newest copy wins; an addon's own icon toggle lives only in
-- that addon's table (savedTable.notchHidden[id]). With no icons shown the bar hides completely.
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 4
if (LIB.launcherVersion or 0) >= VERSION then return end
LIB.launcherVersion = VERSION

-- Designed at full size, then the whole bar is scaled down: the bronze corners are 32px and need the room.
local SCALE = 0.62
local ICON, GAP, PAD_X, HEIGHT = 32, 14, 32, 68
-- How far the bar sits past the screen edge; the rest is visible and the icons are centred in that part.
local TUCK = 22
local BRACKET_SCALE = 0.7

local entries = LIB.launcherEntries or {}
LIB.launcherEntries = entries
local stores = LIB.launcherStores or {}
LIB.launcherStores = stores
local notch = LIB.notchFrame
local dragPos  -- live position while dragging, saved on release
local expanded -- collapse style: the bar is open because the mouse is over it
local COLLAPSED_W = 22 -- the three-dot handle
local Expand   -- defined below; dragging needs it

local function Position()
    if dragPos then return dragPos end
    local best
    for _, db in ipairs(stores) do
        local p = db.notch
        if p and p.edge and p.v == 2 and (not best or (p.t or 0) > (best.t or 0)) then best = p end
    end
    return best or { edge = "TOP", offset = 0.5, t = 0 }
end

local function SavePosition(edge, offset)
    local p = { edge = edge, offset = offset, t = time(), v = 2 }
    for _, db in ipairs(stores) do db.notch = p end
end

-- Bar-wide preference shared through every registered saved table; newest write wins.
local function Pref(key, default)
    local best
    for _, db in ipairs(stores) do
        local p = db.notchPrefs and db.notchPrefs[key]
        if type(p) == "table" and (not best or (p.t or 0) > (best.t or 0)) then best = p end
    end
    if best then return best.value end
    return default
end

local function SetPref(key, value)
    local p = { value = value, t = time() }
    for _, db in ipairs(stores) do
        db.notchPrefs = db.notchPrefs or {}
        db.notchPrefs[key] = p
    end
end

local function Collapsed()
    return Pref("style", "grow") == "collapse" and not expanded and not dragPos
end

local function Sorted()
    local list = {}
    for _, e in pairs(entries) do
        if not e.hidden then list[#list + 1] = e end
    end
    table.sort(list, function(a, b)
        if (a.order or 50) ~= (b.order or 50) then return (a.order or 50) < (b.order or 50) end
        return a.id < b.id
    end)
    return list
end

-- Icons sit in the visible part of the bar, between the screen edge and the bronze border
-- on the far side (half the tuck, minus half that border).
local S = (TUCK - 12) / 2
local SHIFT = { TOP = { 0, -S }, BOTTOM = { 0, S }, LEFT = { S, 0 }, RIGHT = { -S, 0 } }
-- Corner brackets hidden under the screen edge on each side.
local TUCKED = { TOP = { TL = true, TR = true }, BOTTOM = { BL = true, BR = true },
                 LEFT = { TL = true, BL = true }, RIGHT = { TR = true, BR = true } }

local function Layout()
    if not notch then return end
    local list = Sorted()
    notch:SetShown(#list > 0)
    local collapsed = Collapsed()
    local width = collapsed and (PAD_X * 2 + COLLAPSED_W)
        or (PAD_X * 2 + #list * ICON + math.max(0, #list - 1) * GAP)
    notch:SetSize(width, HEIGHT)
    local pos = Position()
    local edge = SHIFT[pos.edge] and pos.edge or "TOP"
    local dx, dy = SHIFT[edge][1], SHIFT[edge][2]
    local badges = false
    for _, e in pairs(entries) do e.button:Hide() end
    for i, e in ipairs(list) do
        e.button:ClearAllPoints()
        e.button:SetPoint("LEFT", notch, "LEFT", PAD_X + (i - 1) * (ICON + GAP) + dx, dy)
        e.button:SetShown(not collapsed)
        if e.button.badge:IsShown() then badges = true end
    end
    notch.handle:ClearAllPoints()
    notch.handle:SetPoint("CENTER", notch, "CENTER", dx, dy)
    notch.handle:SetShown(collapsed)
    notch.handle.alert:SetShown(collapsed and badges)
    for c, t in pairs(notch.brackets or {}) do t:SetShown(not TUCKED[edge][c]) end

    -- Keep the whole bar on screen along its edge.
    local sw, sh = UIParent:GetWidth() / SCALE, UIParent:GetHeight() / SCALE
    local along = (edge == "LEFT" or edge == "RIGHT") and sh or sw
    local half = ((edge == "LEFT" or edge == "RIGHT") and HEIGHT or width) / 2 / along
    local off = math.max(half, math.min(1 - half, pos.offset or 0.5))
    notch:ClearAllPoints()
    if edge == "TOP" then
        notch:SetPoint("TOP", UIParent, "TOPLEFT", off * sw, TUCK)
    elseif edge == "BOTTOM" then
        notch:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", off * sw, -TUCK)
    elseif edge == "LEFT" then
        notch:SetPoint("LEFT", UIParent, "BOTTOMLEFT", -TUCK, off * sh)
    else
        notch:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", TUCK, off * sh)
    end
end
LIB.LayoutLauncher = Layout

-- Dragging never lets the bar float: it slides along its edge under the cursor and only jumps
-- to another edge once the cursor is clearly closer to that one.
local SWITCH_MARGIN = 80

local function CursorPosition(currentEdge)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local d = { LEFT = x, RIGHT = sw - x, BOTTOM = y, TOP = sh - y }
    local edge, best = currentEdge, (d[currentEdge] or math.huge) - SWITCH_MARGIN
    for k, v in pairs(d) do
        if v < best then edge, best = k, v end
    end
    local offset = (edge == "LEFT" or edge == "RIGHT") and (y / sh) or (x / sw)
    return edge, math.max(0, math.min(1, offset))
end

local function DragUpdate()
    local edge, offset = CursorPosition(dragPos.edge)
    if edge ~= dragPos.edge or math.abs(offset - dragPos.offset) > 0.0005 then
        dragPos.edge, dragPos.offset = edge, offset
        Layout()
    end
end

local function StartDrag()
    if dragPos or InCombatLockdown() then return end
    local p = Position()
    dragPos = { edge = p.edge, offset = p.offset or 0.5 }
    GameTooltip:Hide()
    notch:SetScript("OnUpdate", DragUpdate)
end

local function StopDrag()
    if not dragPos then return end
    notch:SetScript("OnUpdate", nil)
    local p = dragPos
    dragPos = nil
    SavePosition(p.edge, p.offset)
    expanded = nil
    Layout()
    -- Collapse style: stay open under the cursor, close once it moves away.
    if notch:IsMouseOver() then Expand() end
end

-- Collapse style: open while the mouse is over the bar, close shortly after it leaves.
local function HoverWatch(self, elapsed)
    if dragPos then return end
    if self:IsMouseOver() then
        self.away = 0
        return
    end
    self.away = (self.away or 0) + elapsed
    if self.away > 0.4 then
        expanded = nil
        self:SetScript("OnUpdate", nil)
        Layout()
    end
end

function Expand()
    if dragPos or Pref("style", "grow") ~= "collapse" then return end
    notch.away = 0
    if not expanded then
        expanded = true
        Layout()
    end
    notch:SetScript("OnUpdate", HoverWatch)
end

local function SetStyle(style)
    SetPref("style", style)
    expanded = nil
    notch:SetScript("OnUpdate", nil)
    Layout()
end

local function ResetPosition()
    SavePosition("TOP", 0.5)
    Layout()
end

local function ShowMenu()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(notch, function(_, root)
        root:CreateTitle("Forever launcher")
        root:CreateRadio("Always open", function() return Pref("style", "grow") ~= "collapse" end,
            function() SetStyle("grow") end)
        root:CreateRadio("Collapse until hovered", function() return Pref("style", "grow") == "collapse" end,
            function() SetStyle("collapse") end)
        root:CreateDivider()
        root:CreateButton("Reset position", ResetPosition)
    end)
end

-- Forever's own bronze frame (the "heavybronze" art its character creation uses):
-- sliced border, stone backdrop and cut-corner brackets.
local function Skin(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 8, -8)
    bg:SetPoint("BOTTOMRIGHT", -8, 8)
    bg:SetAtlas("heavybronze-frame-background")
    local frame = f:CreateTexture(nil, "BORDER")
    frame:SetAllPoints()
    frame:SetAtlas("heavybronze-frame-basic")
    f.brackets = {}
    for _, c in ipairs({ "TL", "TR", "BL", "BR" }) do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetAtlas("heavybronze-horz-cornerbracket-" .. c, true)
        local w, h = t:GetSize()
        t:SetSize(w * BRACKET_SCALE, h * BRACKET_SCALE)
        f.brackets[c] = t
        local point = ({ TL = "TOPLEFT", TR = "TOPRIGHT", BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT" })[c]
        t:SetPoint(point, 0, 0)
    end
end

local function BuildNotch()
    if notch then return end
    notch = CreateFrame("Frame", "LibForeverNotch", UIParent)
    LIB.notchFrame = notch
    notch:SetScale(SCALE)
    notch:SetFrameStrata("MEDIUM")
    notch:EnableMouse(true)
    notch:RegisterForDrag("LeftButton")
    Skin(notch)
    notch:SetScript("OnDragStart", StartDrag)
    notch:SetScript("OnDragStop", StopDrag)
    notch:SetScript("OnHide", StopDrag)
    notch:SetScript("OnEnter", Expand)
    notch:SetScript("OnMouseUp", function(_, mouse) if mouse == "RightButton" then ShowMenu() end end)

    -- Collapsed look: three small dots, plus a red one when any addon has a badge up.
    local handle = CreateFrame("Frame", nil, notch)
    handle:SetSize(COLLAPSED_W, 8)
    for i = 1, 3 do
        local d = handle:CreateTexture(nil, "OVERLAY")
        d:SetSize(6, 6)
        d:SetPoint("CENTER", (i - 2) * 8, 0)
        d:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        d:SetVertexColor(0.92, 0.88, 0.80, 0.9)
    end
    local alert = handle:CreateTexture(nil, "OVERLAY", nil, 1)
    alert:SetSize(10, 10)
    alert:SetPoint("CENTER", 14, 8)
    alert:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    alert:SetVertexColor(0.72, 0.10, 0.06)
    handle.alert = alert
    notch.handle = handle
end

local function MakeButton(e)
    local b = CreateFrame("Button", nil, notch)
    b:SetSize(ICON, ICON)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints()
    icon:SetTexture(e.icon)
    icon:SetVertexColor(0.92, 0.88, 0.80, 0.92)
    b.icon = icon

    local badge = CreateFrame("Frame", nil, b)
    badge:SetSize(20, 20)
    badge:SetPoint("TOPRIGHT", 8, 8)
    badge:SetFrameLevel(b:GetFrameLevel() + 3)
    local dot = badge:CreateTexture(nil, "ARTWORK")
    dot:SetAllPoints()
    dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    dot:SetVertexColor(0.72, 0.10, 0.06)
    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    badge.text:SetPoint("CENTER", 0, 0)
    badge:Hide()
    b.badge = badge

    b:SetScript("OnClick", function(_, mouse) if e.onClick then e.onClick(mouse) end end)
    b:SetScript("OnEnter", function(self)
        if dragPos then return end
        Expand()
        self.icon:SetVertexColor(1, 0.82, 0.40, 1)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        local edge = Position().edge
        if edge == "TOP" then GameTooltip:SetPoint("TOP", self, "BOTTOM", 0, -8)
        elseif edge == "BOTTOM" then GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 8)
        elseif edge == "LEFT" then GameTooltip:SetPoint("LEFT", self, "RIGHT", 8, 0)
        else GameTooltip:SetPoint("RIGHT", self, "LEFT", -8, 0) end
        GameTooltip:AddLine(e.label or e.id, 1, 0.82, 0.3)
        local s = e.status and e.status()
        if s and s ~= "" then GameTooltip:AddLine(s, 1, 1, 1, true) end
        for _, line in ipairs(e.tooltip or {}) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine("Drag to move along any screen edge. Right-click the bar's rim for options.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.92, 0.88, 0.80, 0.92)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStart", StartDrag)
    b:SetScript("OnDragStop", StopDrag)
    return b
end

function LIB.RegisterLauncher(entry, savedTable)
    if not entry or not entry.id then return end
    BuildNotch()
    if savedTable then
        local known = false
        for _, db in ipairs(stores) do if db == savedTable then known = true end end
        if not known then stores[#stores + 1] = savedTable end
    end
    local old = entries[entry.id]
    entry.store = savedTable
    if savedTable and savedTable.notchHidden and savedTable.notchHidden[entry.id] then entry.hidden = true end
    entry.button = old and old.button or MakeButton(entry)
    entry.button.icon:SetTexture(entry.icon)
    entries[entry.id] = entry
    Layout()
end

function LIB.SetLauncherBadge(id, count)
    local e = entries[id]
    if not e or not e.button then return end
    count = tonumber(count) or 0
    e.button.badge:SetShown(count > 0)
    e.button.badge.text:SetText(count > 9 and "9+" or tostring(count))
    Layout()
end

function LIB.SetLauncherHidden(id, hidden)
    local e = entries[id]
    if not e then return end
    e.hidden = hidden and true or nil
    if e.store then
        e.store.notchHidden = e.store.notchHidden or {}
        e.store.notchHidden[id] = e.hidden
    end
    Layout()
end

function LIB.IsLauncherHidden(id)
    local e = entries[id]
    return e and e.hidden or false
end

-- Settings block for an addon's options page: its own show-icon toggle plus the bar-wide style.
-- Returns a 300x100 frame; it reads the current values whenever it is shown.
function LIB.LauncherOptions(parent, id)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 100)
    local function check(label, y)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", 0, y)
        local l = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        l:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        l:SetText(label)
        cb.label = l
        return cb
    end
    local e = entries[id]
    local show = check(("Show %s on the Forever launcher"):format(e and e.label or id), 0)
    show:SetScript("OnClick", function(self) LIB.SetLauncherHidden(id, not self:GetChecked()) end)

    local note = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 4, -32)
    note:SetText("Launcher bar (shared by all Forever addons):")
    local open = check("Always open", -46)
    local collapse = check("Collapse until hovered", -72)
    open:SetScript("OnClick", function() SetStyle("grow"); f:Refresh() end)
    collapse:SetScript("OnClick", function() SetStyle("collapse"); f:Refresh() end)

    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(120, 22)
    reset:SetPoint("LEFT", open.label, "RIGHT", 24, 0)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", ResetPosition)

    function f:Refresh()
        show:SetChecked(not LIB.IsLauncherHidden(id))
        local c = Pref("style", "grow") == "collapse"
        open:SetChecked(not c)
        collapse:SetChecked(c)
    end
    f:SetScript("OnShow", f.Refresh)
    f:Refresh()
    return f
end

-- An addon with an older copy of this file loaded first and already built the bar: retire that
-- frame (its scripts point at the old code) and rebuild the bar and buttons with this version.
if notch and not notch.handle then
    local old = notch
    old:SetScript("OnUpdate", nil)
    old:Hide()
    old:SetScript("OnShow", old.Hide)
    notch, LIB.notchFrame = nil, nil
    BuildNotch()
    for _, e in pairs(entries) do
        if e.button then e.button:Hide() end
        e.button = MakeButton(e)
    end
    Layout()
end

LIB.On("DISPLAY_SIZE_CHANGED", function() Layout() end)
LIB.On("UI_SCALE_CHANGED", function() Layout() end)
