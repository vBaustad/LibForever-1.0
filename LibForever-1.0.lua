--- LibForever-1.0
-- Shared plumbing for the WoW: Forever addons (Guildhall, Campfire, ForeverStats).
-- Embedded in each addon: whichever copy is newest wins, and all of them then share one instance,
-- so two of our addons loaded together can read each other's live data without any saved-variable tricks.
--
-- Modules:
--   identity   who am I / who is that (realmless names, surnames)
--   roster     the guild roster, kept fresh, with online state
--   comm       guild addon messages: prefix per addon, throttled, queued while chat is locked down
--   map        where am I, and how far away is that in yards (map sizes from the client's own data)
--   data       shared access to generated Forever data (recipes, professions, stations)
--   store      saved-variable defaults, schema versions and ordered migrations
local MAJOR, MINOR = "LibForever-1.0", 1
local LIB = LibStub and LibStub:NewLibrary(MAJOR, MINOR)
if not LIB then return end

LIB.callbacks = LIB.callbacks or {}
LIB.frames = LIB.frames or {}

-- ---------------------------------------------------------------------------
-- Events and callbacks
-- ---------------------------------------------------------------------------
local handlers = LIB.handlers or {}
LIB.handlers = handlers
local eventFrame = LIB.eventFrame or CreateFrame("Frame")
LIB.eventFrame = eventFrame
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then LIB.Debug("%s handler: %s", event, tostring(err)) end
    end
end)

function LIB.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

function LIB.Listen(name, fn)
    LIB.callbacks[name] = LIB.callbacks[name] or {}
    table.insert(LIB.callbacks[name], fn)
end

function LIB.Fire(name, ...)
    local list = LIB.callbacks[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then LIB.Debug("%s callback: %s", name, tostring(err)) end
    end
end

function LIB.Debug(fmt, ...)
    if not LIB.debug then return end
    print("|cff88aaffLibForever|r: " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

local debounces = {}
function LIB.Debounce(key, delay, fn)
    if debounces[key] then debounces[key]:Cancel() end
    debounces[key] = C_Timer.NewTimer(delay, function()
        debounces[key] = nil
        fn()
    end)
end

-- ---------------------------------------------------------------------------
-- Identity: names are realmless in Forever and surnames can be hidden
-- ---------------------------------------------------------------------------
function LIB.Realm()
    return GetNormalizedRealmName() or (GetRealmName() or ""):gsub("[%s%-]", "")
end

--- Always "Name-Realm", the form addon messages and the guild roster use.
function LIB.FullName(name)
    if not name or name == "" then return nil end
    if not name:find("-", 1, true) then name = name .. "-" .. LIB.Realm() end
    return name
end

function LIB.Me()
    if not LIB.me then
        local n = UnitName("player")
        if not n or n == UNKNOWNOBJECT then return nil end
        LIB.me = LIB.FullName(n)
    end
    return LIB.me
end

--- Name for display: drops our own realm, and the surname when the player hides it.
function LIB.ShortName(full)
    if not full then return "?" end
    local short = Ambiguate(full, "none")
    if C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname and not C_PlayerInfo.ShouldDisplaySurname() then
        short = short:match("^(%S+)") or short
    end
    return short
end

function LIB.ClassColor(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then return "ffcccccc" end
    return c.colorStr or ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

function LIB.ColorName(full, classFile)
    return "|c" .. LIB.ClassColor(classFile) .. LIB.ShortName(full) .. "|r"
end

-- ---------------------------------------------------------------------------
-- Guild roster
-- ---------------------------------------------------------------------------
LIB.roster = LIB.roster or {}      -- ["Name-Realm"] = { online, class, level, rankIndex, zone }
LIB.rosterReady = LIB.rosterReady or false

function LIB.GuildKey()
    if not IsInGuild() then return nil end
    local name, _, _, realm = GetGuildInfo("player")
    if not name then return nil end
    return name .. "-" .. (realm or LIB.Realm())
end

function LIB.RequestRoster()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

function LIB.IsOnline(full)
    if full == LIB.Me() then return true end
    local r = LIB.roster[full]
    return (r and r.online) or false
end

function LIB.IsGuildie(full)
    return LIB.roster[full] ~= nil
end

local function RebuildRoster()
    local total = GetNumGuildMembers()
    if not total or total == 0 then return end
    local old, new, cameOnline = LIB.roster, {}, {}
    for i = 1, total do
        local name, _, rankIndex, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            local full = LIB.FullName(name)
            new[full] = { online = online and true or false, class = classFile, level = level, rankIndex = rankIndex, zone = zone }
            if online and old[full] and not old[full].online then cameOnline[#cameOnline + 1] = full end
        end
    end
    LIB.roster = new
    local first = not LIB.rosterReady
    LIB.rosterReady = true
    LIB.Fire("ROSTER", first)
    for _, full in ipairs(cameOnline) do LIB.Fire("MEMBER_ONLINE", full) end
end

LIB.On("GUILD_ROSTER_UPDATE", function() LIB.Debounce("roster", 1, RebuildRoster) end)
LIB.On("PLAYER_GUILD_UPDATE", function()
    LIB.RequestRoster()
    LIB.Fire("GUILD_CHANGED")
end)

-- ---------------------------------------------------------------------------
-- Comms: one registered prefix per addon, queued while chat is locked down
-- ---------------------------------------------------------------------------
LIB.comms = LIB.comms or {}
local held = {}

function LIB.InChatLockdown()
    return (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) or false
end

--- Register a message prefix. onMessage(prefix, text, distribution, senderFullName)
function LIB.RegisterComm(prefix, onMessage)
    local AceComm = LibStub and LibStub("AceComm-3.0", true)
    if not AceComm then
        LIB.Debug("AceComm-3.0 missing; %s cannot sync", prefix)
        return false
    end
    local holder = { prefix = prefix }
    AceComm:Embed(holder)
    holder:RegisterComm(prefix, function(_, text, dist, sender)
        sender = LIB.FullName(sender)
        if not sender or sender == LIB.Me() then return end
        if dist ~= "GUILD" and dist ~= "WHISPER" then return end
        if dist == "WHISPER" and not LIB.IsGuildie(sender) then return end
        onMessage(prefix, text, dist, sender)
    end)
    LIB.comms[prefix] = holder
    return true
end

--- Send a message. Held (up to 60) while addon chat is locked down, then flushed.
function LIB.Send(prefix, text, dist, target, prio)
    local holder = LIB.comms[prefix]
    if not holder or not IsInGuild() then return end
    prio = prio or "NORMAL"
    if LIB.InChatLockdown() then
        if #held < 60 then held[#held + 1] = { prefix = prefix, text = text, dist = dist, target = target, prio = prio } end
        return false
    end
    holder:SendCommMessage(prefix, text, dist, target, prio)
    return true
end

C_Timer.NewTicker(10, function()
    if LIB.InChatLockdown() or #held == 0 then return end
    local queue = held
    held = {}
    for _, m in ipairs(queue) do
        local holder = LIB.comms[m.prefix]
        if holder then holder:SendCommMessage(m.prefix, m.text, m.dist, m.target, m.prio) end
    end
end)

-- ---------------------------------------------------------------------------
-- Map maths: normalised map coordinates in, yards out (sizes in Maps.lua)
-- ---------------------------------------------------------------------------
function LIB.MapId()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

--- Your position on your current map: uiMapID, x, y (0-1), or nil indoors/instanced.
function LIB.MyPosition()
    local mapId = LIB.MapId()
    if not mapId or not C_Map.GetPlayerMapPosition then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapId, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return mapId, x, y
end

function LIB.MapName(mapId)
    local info = mapId and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    return (info and info.name) or (LIB.Maps and LIB.Maps[mapId] and "map " .. mapId) or "?"
end

--- Distance in yards between two map positions, or nil when they aren't comparable
--- (different maps that aren't the same zone, or a map we have no size for).
function LIB.Distance(mapA, xA, yA, mapB, xB, yB)
    if not (mapA and mapB and xA and xB) then return nil end
    local sizes = LIB.Maps
    if not sizes then return nil end
    if mapA == mapB then
        local m = sizes[mapA]
        if not m then return nil end
        local dx, dy = (xA - xB) * m[1], (yA - yB) * m[2]
        return math.sqrt(dx * dx + dy * dy)
    end
    -- Different maps: compare in world coordinates when both sit on the same parent continent.
    local a, b = sizes[mapA], sizes[mapB]
    if not a or not b or a[5] == 0 or a[5] ~= b[5] then return nil end
    local ax, ay = a[3] - yA * a[1], a[4] - xA * a[2]
    local bx, by = b[3] - yB * b[1], b[4] - xB * b[2]
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- ---------------------------------------------------------------------------
-- Shared data: whatever generated Forever data an addon has loaded
-- ---------------------------------------------------------------------------
LIB.sources = LIB.sources or {}

--- Addons publish their generated data here; every addon can then read it.
function LIB.ProvideData(name, tbl)
    LIB.sources[name] = tbl
end

function LIB.GetData(name)
    return LIB.sources[name]
end

-- ---------------------------------------------------------------------------
-- Saved variables: defaults, schema version and ordered migrations
-- ---------------------------------------------------------------------------
--- Prepare a saved-variable table: fills defaults, runs migrations[n] in order, stamps the version.
function LIB.PrepareDB(db, defaults, migrations, currentVersion)
    db = db or {}
    for k, v in pairs(defaults or {}) do
        if db[k] == nil then
            db[k] = (type(v) == "table") and CopyTable(v) or v
        end
    end
    local from = db.schema or currentVersion
    for v = from + 1, currentVersion do
        local fn = migrations and migrations[v]
        if fn then
            local ok, err = pcall(fn, db)
            if not ok then
                LIB.Debug("migration to %d failed: %s", v, tostring(err))
                return db, false
            end
        end
        db.schema = v
    end
    db.schema = db.schema or currentVersion
    return db, true
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
LIB.On("PLAYER_LOGIN", function()
    LIB.Me()
    LIB.RequestRoster()
    C_Timer.NewTicker(60, LIB.RequestRoster)
    LIB.Fire("LOGIN")
end)
