--- LibForever-1.0
-- Shared plumbing for the YippYapp addons for WoW: Forever (Guildhall, AutoFeed, Skillwright, BuffWarden,
-- Campfire).
-- Embedded in each addon: whichever copy is newest wins, and all of them then share one instance,
-- so two of our addons loaded together can read each other's live data without any saved-variable tricks.
--
-- Modules:
--   identity   who am I / who is that (realmless names, surnames, whisper targets)
--   roster     the guild roster, kept fresh, with online state
--   comm       guild addon messages: one prefix per addon, sent at once, lockdown refusals retried
--   map        where am I, and how far away is that in yards (map sizes from the client's own data)
--   data       shared access to generated Forever data (recipes, professions, stations)
--   store      saved-variable defaults, schema versions and ordered migrations
local MAJOR, MINOR = "LibForever-1.0", 6
local LIB = LibStub and LibStub:NewLibrary(MAJOR, MINOR)
if not LIB then return end

LIB.callbacks = LIB.callbacks or {}
LIB.frames = LIB.frames or {}
-- A newer copy of this file runs over an older one: all state lives on LIB, and the event handlers
-- below are registered only once (they call through LIB, so they use the newest code).
local firstLoad = not LIB.coreHooked
LIB.coreHooked = true

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

local debounces = LIB.debounces or {}
LIB.debounces = debounces
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

--- The name the server accepts for a whisper (chat or addon): plain for someone on our own realm,
--- because "Name-OurRealm" answers "No player named ... is currently playing". Other realms keep
--- their suffix. Storage and comparisons still use the full "Name-Realm" form.
function LIB.WhisperName(full)
    if not full or full == "" then return full end
    local name, realm = full:match("^(.-)%-(.+)$")
    if not name then return full end
    local function plain(s) return (s or ""):gsub("[%s%-']", ""):lower() end
    return plain(realm) == plain(LIB.Realm()) and name or full
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

-- Kept for old callers, but does nothing: C_GuildInfo.GuildRoster() pops Forever's "blocked from an
-- action only available to the Blizzard UI" dialog, even inside pcall. The roster comes from the
-- GUILD_ROSTER_UPDATE events the server sends by itself.
function LIB.RequestRoster() end

function LIB.IsOnline(full)
    if full == LIB.Me() then return true end
    local r = LIB.roster[full]
    return (r and r.online) or false
end

--- Strict: only true when the guild roster we hold lists them. The roster can be empty or partial
--- (we never request it; see RequestRoster), so use KnownGuildie to accept messages.
function LIB.IsGuildie(full)
    return LIB.roster[full] ~= nil
end

--- Lenient: in the roster, OR heard from on the GUILD addon channel this session (only guild
--- members can reach us there). Use this to accept whispers: a partial roster must not drop replies.
LIB.guildHeard = LIB.guildHeard or {}
function LIB.KnownGuildie(full)
    return full ~= nil and (LIB.roster[full] ~= nil or LIB.guildHeard[full] == true)
end

function LIB.RebuildRoster()
    if not IsInGuild() then return end
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

if firstLoad then
    LIB.On("GUILD_ROSTER_UPDATE", function() LIB.Debounce("roster", 1, LIB.RebuildRoster) end)
    LIB.On("PLAYER_GUILD_UPDATE", function() LIB.Fire("GUILD_CHANGED") end)
end

-- ---------------------------------------------------------------------------
-- Comms: one registered prefix per addon
-- Addon messages are NOT gated by chat messaging lockdown: the client's own documentation gives
-- C_ChatInfo.SendAddonMessage no lockdown clause, while the chat-line getters carry
-- SecretInChatMessagingLockdown. We used to hold messages back up front during that lockdown, which
-- silenced our addons for the rest of the session. Never gate addon comms with a check beforehand.
-- What decides is the client's answer to each send (Enum.SendAddonMessageResult), which AceComm and
-- ChatThrottleLib hand back per chunk: a message counts as sent only when every chunk went out; one
-- refused with AddOnMessageLockdown is sent again, whole, once the restriction lifts.
-- ---------------------------------------------------------------------------
LIB.comms = LIB.comms or {}
LIB.commStats = LIB.commStats or {}   -- [prefix] = { sent, received, refused = { [reason] = n } }
LIB.commRetry = LIB.commRetry or {}   -- messages refused by a lockdown, oldest first
local MAX_RETRY = 20

local RESULT = Enum and Enum.SendAddonMessageResult or {}
local RESULT_NAME = {}
for name, code in pairs(RESULT) do RESULT_NAME[code] = name end
local LOCKDOWN = RESULT.AddOnMessageLockdown or 11

--- Only for REAL chat (a whisper the player would read), never for addon messages.
function LIB.InChatLockdown()
    return (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) or false
end

local function Stats(prefix)
    local s = LIB.commStats[prefix]
    if not s then
        s = { sent = 0, received = 0, refused = {} }
        LIB.commStats[prefix] = s
    end
    s.refused = s.refused or {}
    return s
end

--- This session's traffic for a prefix, for an addon's status line:
--- sent (whole messages that went out), received, refused (total), waiting (queued for a retry),
--- and a table of refusals by reason name (e.g. AddOnMessageLockdown, TargetOffline).
function LIB.CommStats(prefix)
    local s = Stats(prefix)
    local refused, waiting = 0, 0
    for _, n in pairs(s.refused) do refused = refused + n end
    for _, m in ipairs(LIB.commRetry) do if m.prefix == prefix then waiting = waiting + 1 end end
    return s.sent, s.received, refused, waiting, s.refused
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
        if dist == "GUILD" then LIB.guildHeard[sender] = true end
        if dist == "WHISPER" and not LIB.KnownGuildie(sender) then return end
        Stats(prefix).received = Stats(prefix).received + 1
        onMessage(prefix, text, dist, sender)
    end)
    LIB.comms[prefix] = holder
    return true
end

local function Retry(m)
    local queue = LIB.commRetry
    if #queue >= MAX_RETRY then tremove(queue, 1) end  -- oldest out first
    queue[#queue + 1] = m
end

-- Called by ChatThrottleLib (through AceComm) for every chunk: (message, sent, bytes so far, result).
-- The last chunk reports bytes == the whole length; that is when the message is settled.
local function OnChunk(m, sent, bytes, result)
    if not sent and not m.refusal then m.refusal = result or RESULT.GeneralError or 9 end
    if (bytes or 0) < m.length then return end
    local s = Stats(m.prefix)
    if not m.refusal then
        s.sent = s.sent + 1
        -- Something went through: the restriction may be over, so try what was waiting.
        if #LIB.commRetry > 0 then LIB.Debounce("commRetry", 1, function() LIB.FlushHeld() end) end
        return
    end
    local reason = RESULT_NAME[m.refusal] or tostring(m.refusal)
    s.refused[reason] = (s.refused[reason] or 0) + 1
    if m.refusal == LOCKDOWN then
        m.refusal = nil
        Retry(m)
    end
end

local function Dispatch(m)
    local holder = LIB.comms[m.prefix]
    if not holder then return false end
    holder:SendCommMessage(m.prefix, m.text, m.dist, m.target, m.prio, OnChunk, m)
    return true
end

--- Send a message now (never held back beforehand). Returns true when it was handed to the client.
--- Whisper targets are normalised here, so callers can pass the full "Name-Realm" they store.
function LIB.Send(prefix, text, dist, target, prio)
    if not LIB.comms[prefix] or not IsInGuild() then return false end
    if dist == "WHISPER" then target = LIB.WhisperName(target) end
    return Dispatch({ prefix = prefix, text = text, dist = dist, target = target,
                      prio = prio or "NORMAL", length = #(text or "") })
end

--- Send again whatever an addon-message lockdown refused. Runs by itself when a restriction changes
--- or a message goes through; a message refused again simply waits for the next chance.
function LIB.FlushHeld()
    local queue = LIB.commRetry
    if #queue == 0 then return end
    LIB.commRetry = {}
    for _, m in ipairs(queue) do Dispatch(m) end
end
if firstLoad then
    pcall(LIB.On, "ADDON_RESTRICTION_STATE_CHANGED", function()
        if #LIB.commRetry > 0 then LIB.Debounce("commRetry", 1, function() LIB.FlushHeld() end) end
    end)
end

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
    -- Maps.lua rows are { width, height, top (world X), left (world Y), parent }: going down the map
    -- (map y) walks world X over the height, going right (map x) walks world Y over the width.
    local a, b = sizes[mapA], sizes[mapB]
    if not a or not b or a[5] == 0 or a[5] ~= b[5] then return nil end
    local ax, ay = a[3] - yA * a[2], a[4] - xA * a[1]
    local bx, by = b[3] - yB * b[2], b[4] - xB * b[1]
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
if firstLoad then
    LIB.On("PLAYER_LOGIN", function()
        LIB.Me()
        -- Whatever roster the client already holds; GUILD_ROSTER_UPDATE keeps it fresh from here.
        C_Timer.After(3, function() LIB.RebuildRoster() end)
        LIB.Fire("LOGIN")
    end)
end
