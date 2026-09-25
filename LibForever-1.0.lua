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
--   store      saved-variable defaults, schema versions and ordered migrations, and whether
--              the client loaded the saved variables at all (SavedVariablesLoaded)
local MAJOR, MINOR = "LibForever-1.0", 16
local LIB = LibStub and LibStub:NewLibrary(MAJOR, MINOR)
if not LIB then return end

LIB.callbacks = LIB.callbacks or {}
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
--- A realm name in the spelling addon messages and the guild roster use: no spaces, hyphens or
--- apostrophes. The client hands out the other spelling too - UnitName's second return is raw
--- ("Bleeding Hollow"), while the sender of an addon message is normalised ("BleedingHollow") - so a
--- key built from one never matches a key built from the other. Run any realm you didn't get from an
--- addon message through this first.
function LIB.NormalizeRealm(realm)
    return (tostring(realm or ""):gsub("[%s%-']", ""))
end

-- The extra parentheses matter: gsub returns the string AND the number of replacements, and without
-- them a caller that passes Realm() straight on carries that number with it.
function LIB.Realm()
    return GetNormalizedRealmName() or LIB.NormalizeRealm(GetRealmName())
end

--- Always "Name-Realm", the form addon messages and the guild roster use.
function LIB.FullName(name)
    if not name or name == "" then return nil end
    if not name:find("-", 1, true) then name = name .. "-" .. LIB.Realm() end
    return name
end

-- A value the client is keeping from us (identity is restricted in a battleground, for instance).
-- Touching one the wrong way is an error, so this is the only thing that looks at it, and anything
-- unexpected counts as secret rather than risking the comparison.
local function Secret(v)
    if not issecretvalue then return false end
    local ok, secret = pcall(issecretvalue, v)
    return (not ok) or (secret and true or false)
end

-- The second value UnitName returns is NOT always a realm. Forever has regional unique names, and
-- then a character can carry a surname, which arrives in that same slot. The client resolves it this
-- way itself (Blizzard_UnitPopup/Mainline/UnitPopupUtils.lua:124): for a unit, second value plus
-- RegionalUniqueNamesEnabled() means surname, joined with the surname separator; otherwise it is a
-- realm, joined with a dash. Code that reads only the first value sees "Lorr" for a player the server
-- calls "Lorr Den", and then every key, comparison and whisper built from it is wrong for exactly the
-- players who have a surname - including yourself, which is how you end up not recognising your own
-- messages coming back. Nothing here reads the second value without deciding which one it is.
-- (The UnitSurnameOwn CVar is a different thing: display only. The UI shortens the name itself, see
-- Blizzard_UnitFrame/Mainline/UnitFrame.lua:155, so it never reaches what UnitName gives us.)
local function Separator(which, fallback)
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    local v = consts and consts[which]
    return type(v) == "string" and v or fallback
end

-- The unit's real realm, straight from its GUID (GetPlayerInfoByGUID returns realmName). This is the
-- fact that settles "surname or another realm" for a second value that isn't our own realm: on paper
-- the two are the same thing, just a second string. It may answer nothing at all (the API is
-- MayReturnNothing, and a GUID isn't always there yet), and then we fall back on the setting.
local function RealmFromGUID(unit)
    if not (UnitGUID and GetPlayerInfoByGUID) then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or type(guid) ~= "string" or guid == "" then return nil end
    local ok2, _, _, _, _, _, _, realm = pcall(GetPlayerInfoByGUID, guid)
    if not ok2 or Secret(realm) or type(realm) ~= "string" or realm == "" then return nil end
    return realm
end

-- name, surname, realm for a unit - whichever of the last two the client actually gave us, and nil
-- for all three when we aren't allowed to know who this is. UnitNameUnmodified first, which is the
-- client's own preference (UnitPopupShared.lua:7) and is not affected by anything that renames a unit.
local function NameParts(unit)
    local get = UnitNameUnmodified or UnitName
    local name, second = get(unit)
    if Secret(name) or Secret(second) then return nil end
    if not name or name == "" or name == UNKNOWNOBJECT then return nil end
    if second == "" then second = nil end
    if not second then return name, nil, nil end
    -- Test the value before trusting a setting about what the value means: our own realm, however it
    -- is spelled, is a realm no matter what any CVar says. We have been caught twice reading a setting
    -- as if it were a fact.
    local ours = LIB.Realm()
    local flat = LIB.NormalizeRealm(second)
    if flat == ours or flat == LIB.NormalizeRealm(GetRealmName and GetRealmName() or "") then
        return name, nil, second          -- a realm: our own
    end
    -- Not our realm, so it is either another realm or a surname, and those look identical as text.
    -- Ask the GUID, which knows the unit's actual realm, before falling back on a setting.
    local actual = RealmFromGUID(unit)
    if actual then
        if LIB.NormalizeRealm(actual) == flat then return name, nil, second end  -- another realm
        return name, second, nil                                                -- a surname
    end
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        return name, second, nil          -- a surname, as far as the setting knows
    end
    return name, nil, second              -- another realm
end

--- The "Name-Realm" key for a unit, in the spelling everything else here uses. Use it instead of
--- building a key out of UnitName yourself: it puts the surname back on, normalises the realm (the
--- one the client gives you is raw and would never match the same player heard on the addon channel),
--- and it knows the name can be secret when the client restricts identity - in a battleground, say.
--- nil means "we don't know who this is right now", never "there is nobody there": don't cache it,
--- don't delete anything over it, just ask again later.
function LIB.UnitKey(unit)
    local name, surname, realm = NameParts(unit or "player")
    if not name then return nil end
    if surname then name = name .. Separator("CHARACTERNAME_SURNAME_SEPARATOR", " ") .. surname end
    if realm then return name .. "-" .. LIB.NormalizeRealm(realm) end
    return LIB.FullName(name)
end

--- Who I am, as "Name-Realm" with the surname included. One code path with UnitKey, so the surname
--- and the secret check can't be right in one place and wrong in the other.
function LIB.Me()
    if not LIB.me then LIB.me = LIB.UnitKey("player") end
    return LIB.me
end

--- Is this stored name the character we are playing now? It accepts the short form a key written
--- before surnames were handled - "Duplo-Realm" for "Duplo Bonk-Realm" - and the other way round, so
--- an addon migrating its own records can find them without inventing its own rule for it.
--- ONLY for recognising yourself. "Duplo" and "Duplo Bonk" can be two different players, and this
--- deliberately treats them as one, which is safe for your own saved data and wrong for anyone else's.
function LIB.IsMyStoredName(key)
    if type(key) ~= "string" or key == "" then return false end
    local me = LIB.Me()
    if not me then return false end
    if key == me then return true end
    local myName, myRealm = me:match("^(.*)%-([^%-]+)$")
    local name, realm = key:match("^(.*)%-([^%-]+)$")
    if not (myName and name) then return false end
    if LIB.NormalizeRealm(realm) ~= LIB.NormalizeRealm(myRealm) then return false end
    if name == myName then return true end   -- the same name, written with the raw realm spelling
    local first, myFirst = name:match("^%S+"), myName:match("^%S+")
    if first ~= myFirst then return false end
    -- One of the two must be the bare first name: a real difference in surname is a different player.
    return name == first or myName == myFirst
end

--- Support-only, from /yippyapp debug: every source the client has for our own name, printed raw and
--- side by side, plus the spelling the SERVER uses for us in the guild roster. Nothing here is
--- interpreted: nil prints as nil and an empty string as "", because telling those two apart is the
--- whole point. One run of this says which API actually carries the surname.
function LIB.DebugIdentity()
    local function out(fmt, ...) print("|cffffd100YippYapp|r " .. fmt:format(...)) end
    -- Raw: nil, "" and a real string must all look different.
    local function raw(v)
        if v == nil then return "nil" end
        if type(v) ~= "string" then return tostring(v) end
        if v == "" or v:match("^%s+$") then return "<" .. v .. "> (" .. #v .. " chars)" end
        return v
    end
    local function pair(label, fn, ...)
        if type(fn) ~= "function" then out("%s: MISSING", label) return end
        local ok, a, b = pcall(fn, ...)
        if not ok then out("%s: error (%s)", label, tostring(a)) return end
        out("%s: [1]=%s  [2]=%s", label, raw(a), raw(b))
    end

    out("--- who the client says we are ---")
    pair("UnitName(player)", UnitName, "player")
    pair("UnitNameUnmodified(player)", UnitNameUnmodified, "player")
    pair("UnitFullName(player)", UnitFullName, "player")
    pair("GetUnitName(player, true)", GetUnitName, "player", true)
    if UnitGUID and UnitNameFromGUID then
        local ok, guid = pcall(UnitGUID, "player")
        if ok and guid then pair("UnitNameFromGUID(own guid)", UnitNameFromGUID, guid) end
    end
    if UnitGUID and GetPlayerInfoByGUID then
        pair("GetPlayerInfoByGUID(own guid) name/realm", function()
            local guid = UnitGUID("player")
            if not guid then return nil, nil end
            local _, _, _, _, _, n, r = GetPlayerInfoByGUID(guid)
            return n, r
        end)
    else
        out("GetPlayerInfoByGUID: MISSING")
    end
    pair("GetNormalizedRealmName / GetRealmName", function()
        return (GetNormalizedRealmName and GetNormalizedRealmName()), (GetRealmName and GetRealmName())
    end)
    pair("RegionalUniqueNamesEnabled", RegionalUniqueNamesEnabled)
    pair("ShouldDisplaySurname", C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname)
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    out("separators: surname=%s realm=%s", raw(consts and consts.CHARACTERNAME_SURNAME_SEPARATOR),
        raw(consts and consts.CHARACTERNAME_REALMNAME_SEPARATOR))
    out("we call ourselves: %s", raw(LIB.Me()))

    -- The server's own spelling of us, straight from the roster rows rather than our parsed copy.
    out("--- what the server calls us ---")
    local first = tostring((UnitNameUnmodified or UnitName)("player") or ""):match("^%S+") or ""
    local shown, members = 0, (GetNumGuildMembers and GetNumGuildMembers()) or 0
    if GetGuildRosterInfo and members > 0 then
        for i = 1, members do
            local ok, full = pcall(GetGuildRosterInfo, i)
            if ok and type(full) == "string" and first ~= "" and full:find(first, 1, true) then
                shown = shown + 1
                -- Print the row exactly as the server sent it AND what we make of it: a row without a
                -- realm is normal, and comparing the raw form against our key would only look wrong.
                local norm = LIB.FullName(full)
                out("roster row %d: raw=%s -> %s%s", i, raw(full), norm,
                    norm == LIB.Me() and " (matches what we call ourselves)"
                    or " |cffff4040(DIFFERENT from what we call ourselves)|r")
                if shown >= 3 then break end
            end
        end
    end
    if shown == 0 then
        if members == 0 then
            out("no guild roster to compare against (no guild, or it hasn't arrived yet)")
        else
            out("none of the %d roster rows contains %q", members, first)
        end
    end
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

--- Make text from anyone else safe to store, send and show: no control characters, no UI escape
--- codes (a "|" becomes "/", so |H links, |T textures and |c colours can't survive), trimmed, and
--- capped. Use it on EVERYTHING that arrives from another player before storing or displaying it.
function LIB.Sanitize(s, maxLen)
    s = tostring(s or "")
    s = s:gsub("%c", " "):gsub("|", "/")
    s = strtrim(s)
    maxLen = tonumber(maxLen) or 128
    if #s > maxLen then
        s = s:sub(1, maxLen)
        -- Never cut a UTF-8 character in half: step back over the trailing bytes, and if that last
        -- character didn't fit whole, drop it.
        local i = #s
        while i > 0 do
            local b = s:byte(i)
            if b < 0x80 or b >= 0xC0 then break end
            i = i - 1
        end
        local lead = i > 0 and s:byte(i) or 0
        if lead >= 0xC0 then
            local need = (lead >= 0xF0 and 4) or (lead >= 0xE0 and 3) or 2
            if #s - i + 1 < need then s = s:sub(1, i - 1) end
        end
    end
    return s
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
LIB.guildHeardCount = LIB.guildHeardCount or 0
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
-- A hostile or broken client must not be able to make us work without bound: each sender gets a
-- budget per prefix, and anything above it is dropped before the addon ever sees it.
local BUDGET, BUDGET_WINDOW = 30, 10   -- messages per sender per prefix, per this many seconds
local heard = LIB.commHeard or {}      -- [prefix][sender] = { n, since }
LIB.commHeard = heard

-- The budget table itself must not grow all session either: once it holds more senders than a large
-- guild would, everything outside the current window goes.
local MAX_SENDERS = 300

local function Prune(perPrefix, now)
    local n = 0
    for _ in pairs(perPrefix) do n = n + 1 end
    if n <= MAX_SENDERS then return end
    for who, row in pairs(perPrefix) do
        if now - row.since > BUDGET_WINDOW then perPrefix[who] = nil end
    end
end

local function WithinBudget(prefix, sender)
    local now = (GetTime and GetTime()) or 0
    local perPrefix = heard[prefix]
    if not perPrefix then
        perPrefix = {}
        heard[prefix] = perPrefix
    end
    Prune(perPrefix, now)
    local row = perPrefix[sender]
    if not row or now - row.since > BUDGET_WINDOW then
        perPrefix[sender] = { n = 1, since = now }
        return true
    end
    row.n = row.n + 1
    if row.n <= BUDGET then return true end
    if row.n == BUDGET + 1 then LIB.Debug("%s: %s is over budget, dropping", prefix, tostring(sender)) end
    return false
end
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
        if not WithinBudget(prefix, sender) then
            local s = Stats(prefix)
            s.refused.OverBudget = (s.refused.OverBudget or 0) + 1
            return
        end
        -- Remember senders we hear on the guild channel, but never without a limit.
        if dist == "GUILD" and LIB.guildHeardCount < 500 and not LIB.guildHeard[sender] then
            LIB.guildHeard[sender] = true
            LIB.guildHeardCount = LIB.guildHeardCount + 1
        end
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
-- Did the saved variables load at all?
-- Forever beta (build 69913) sometimes starts without reading SavedVariables at all: the globals are
-- nil at ADDON_LOADED and after, every addon rebuilds its defaults, and the next logout writes those
-- over the good files. It is confirmed on Blizzard's own forums (EU 629888 / US 2353992) and hits
-- other addons and Blizzard's frames too, so it is the client, not us.
-- We can't recover what never loaded, but we can SAY so, and let the addons go quiet instead of
-- publishing empty data. Each registered saved table gets a marker once per session; a table that
-- comes back without its marker did not load.
-- Fixed by the client in build 70009. An empty store looks identical whichever caused it, so what we
-- are allowed to CLAIM depends on the client: on a build that still has the bug, silence would leave
-- someone hunting for settings that are gone; on a build that doesn't, the only remaining explanation
-- is a first install, and a red "your settings couldn't be read" is then both untrue and the first
-- thing a new player ever sees from us. The machinery stays either way - people run old clients, and
-- the bug can come back - it just stops talking.
--   LIB.RegisterSavedTable(t)      add a table to the check (the lib adds the ones it knows)
--   LIB.SavedVariablesLoaded()     false only when we are sure they did not load, else true
--   LIB.SavedVariablesBugPossible()  whether this client can lose them at all
--   LIB.Listen("SAVED_VARIABLES_EMPTY", fn)   fires once, a second or two after login
-- ---------------------------------------------------------------------------
LIB.savedTables = LIB.savedTables or {}
LIB.savedVariablesState = LIB.savedVariablesState or "unknown"

function LIB.RegisterSavedTable(t)
    if type(t) ~= "table" then return end
    for _, known in ipairs(LIB.savedTables) do if known == t then return end end
    LIB.savedTables[#LIB.savedTables + 1] = t
    -- Registered after the check has run: give it this session's marker too.
    if LIB.savedVariablesState ~= "unknown" then t.yippyappSeen = time() end
end

local function AllSavedTables()
    local list, seen = {}, {}
    local function add(t)
        if type(t) == "table" and not seen[t] then
            seen[t] = true
            list[#list + 1] = t
        end
    end
    for _, t in ipairs(LIB.savedTables) do add(t) end
    for _, t in ipairs(LIB.launcherStores or {}) do add(t) end
    for _, b in pairs(LIB.minimapButtons or {}) do add(b.store) end
    for _, p in pairs(LIB.welcomePages or {}) do add(p.store) end
    return list
end

--- The client's build number, the SECOND return from GetBuildInfo ("1.60.1" first, then "70009").
--- The fourth is the interface version (11215), which would compare as an older build forever.
function LIB.ClientBuild()
    if not GetBuildInfo then return nil end
    local ok, _, build = pcall(GetBuildInfo)
    return ok and tonumber(build) or nil
end

local FIXED_IN_BUILD = 70009

--- Can this client lose saved variables on a cold start? Everything we say to a player about lost
--- settings has to go through this, so nobody repeats the build check.
--- There are three states, and this tells the two empty ones apart:
---   SavedVariablesLoaded() true                   they loaded, or it is too early to tell
---   loaded false (and this true)                  empty on a client that can lose them: say so
---   empty on a client that can't                  a first install; we say nothing and
---                                                 SavedVariablesLoaded() stays true
function LIB.SavedVariablesBugPossible()
    local build = LIB.ClientBuild()
    -- A build number we can't read: keep quiet. Being silent on an affected client leaves one player
    -- puzzled; claiming lost settings on a fixed one lies to every new player at their first login.
    return build ~= nil and build < FIXED_IN_BUILD
end

--- False only when we are sure this session started without the saved variables.
function LIB.SavedVariablesLoaded()
    return LIB.savedVariablesState ~= "empty"
end

local function CheckSavedVariables()
    if LIB.savedVariablesState ~= "unknown" then return end
    local list = AllSavedTables()
    if #list < 2 then return end          -- too little to tell: say nothing
    local marked = 0
    for _, t in ipairs(list) do
        if t.yippyappSeen then marked = marked + 1 end
    end
    if marked > 0 then
        LIB.savedVariablesState = "loaded"
    elseif LIB.SavedVariablesBugPossible() then
        LIB.savedVariablesState = "empty"
    else
        -- Nothing marked, on a client that cannot lose saved variables: this is a first install.
        -- "fresh" counts as loaded everywhere, so a new player still gets their setup prompts.
        LIB.savedVariablesState = "fresh"
    end
    for _, t in ipairs(list) do t.yippyappSeen = time() end
    if LIB.savedVariablesState == "empty" then
        -- One line only, once per session for the whole family; the welcome window's note carries the
        -- detail. A genuine first install looks the same from in here, so the wording says "couldn't be
        -- read", not "you lost them" - and it never tells anyone to relog, because that doesn't work.
        print("|cffff4040YippYapp:|r your saved settings couldn't be read this session - a known WoW: Forever "
            .. "bug, not these addons. There is nothing to do from in here; a full restart sometimes brings "
            .. "them back, often not. Until then the addons run on defaults.")
        LIB.Fire("SAVED_VARIABLES_EMPTY")
    end
end

if firstLoad then
    -- Two passes: the early one answers as soon as everyone has registered, so an addon asking
    -- SavedVariablesLoaded() gets the truth sooner; the late one covers a slow or late registration.
    LIB.On("PLAYER_LOGIN", function()
        C_Timer.After(2, CheckSavedVariables)
        C_Timer.After(5, CheckSavedVariables)
    end)
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
