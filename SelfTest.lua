--- LibForever-1.0: /yippyapp test - one command that shows nothing is broken.
-- After a round of tidying, the only answer that counts comes from the game, not from a review. Each
-- addon registers a function that exercises its own code; on top of those, the runner does the cheap
-- things that catch a deletion someone was still using: it opens and closes every registered window
-- and settings page, draws every welcome card, and fires every launcher button's tooltip. Most
-- "we removed something that was still in use" bugs show up right there.
--
--   LIB.RegisterSelfTest(id, fn)   fn() -> ok, message. Throwing counts as a failure, and so does
--                                  returning false; the message is shown either way.
--   LIB.RunSelfTests()             what /yippyapp test runs. Returns passed, failed.
--
-- Everything runs inside pcall, so a broken test is a reported failure and never a broken client.
-- It refuses to run in combat, and it puts back what it touched: a window that was closed ends up
-- closed, and a window that was open stays open, so running the test changes nothing a player set.
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 1
if (LIB.selfTestVersion or 0) >= VERSION then return end
LIB.selfTestVersion = VERSION

local tests = LIB.selfTests or {}
LIB.selfTests = tests

--- Register an addon's own test. Call it once, at login.
function LIB.RegisterSelfTest(id, fn)
    if type(id) ~= "string" or type(fn) ~= "function" then return false end
    tests[id] = fn
    return true
end

local function Print(fmt, ...)
    print("|cffffd100YippYapp|r " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

-- Every addon the library knows about, however it registered itself.
local function Addons()
    local ids = {}
    local function add(t) for id in pairs(t or {}) do if type(id) == "string" then ids[id] = true end end end
    add(LIB.minimapButtons)
    add(LIB.optionsPanels)
    add(tests)
    local list = {}
    for id in pairs(ids) do
        if id:sub(1, 1) ~= "_" then list[#list + 1] = id end
    end
    table.sort(list)
    return list
end

-- ---------------------------------------------------------------------------
-- Leaving everything as we found it
-- ---------------------------------------------------------------------------
local function Snapshot()
    local snap = { windows = {} }
    for f in pairs(LIB.windows or {}) do snap.windows[f] = f:IsShown() end
    snap.welcomeShown = LIB.welcomeFrame and LIB.welcomeFrame:IsShown() or false
    return snap
end

local function Restore(snap)
    -- The settings window goes back to open or closed as we found it.
    if LIB.welcomeFrame and LIB.welcomeFrame:IsShown() ~= snap.welcomeShown then
        LIB.welcomeFrame:SetShown(snap.welcomeShown)
    end
    for f, shown in pairs(snap.windows) do
        if f:IsShown() ~= shown then pcall(f.SetShown, f, shown) end
    end
    if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
end

-- ---------------------------------------------------------------------------
-- The checks
-- ---------------------------------------------------------------------------
-- Failures are collected per addon, so one line can say everything about it.
local function Fail(found, id, what, err)
    found[id] = found[id] or {}
    table.insert(found[id], ("%s (%s)"):format(what, tostring(err)))
end

local function Try(found, id, what, fn, ...)
    if type(fn) ~= "function" then return true end
    local ok, err = pcall(fn, ...)
    if not ok then Fail(found, id, what, err) end
    return ok
end

-- Each addon's settings page, shown in our window the way a player would open it.
local function CheckSettings(found)
    for _, id in ipairs(Addons()) do
        if LIB.optionsPanels and LIB.optionsPanels[id] and LIB.OpenAddonSettings then
            Try(found, id, "settings page", LIB.OpenAddonSettings, id)
        end
    end
end

-- Our windows: open, close, and back to how they were.
local function CheckWindows(other)
    for f in pairs(LIB.windows or {}) do
        local name = (f.GetName and f:GetName()) or "a window"
        local ok, err = pcall(function()
            f:Show()
            f:Hide()
        end)
        if not ok then other[#other + 1] = ("%s: %s"):format(name, tostring(err)) end
    end
end

-- ---------------------------------------------------------------------------
-- The run
-- ---------------------------------------------------------------------------
function LIB.RunSelfTests()
    if InCombatLockdown() then
        Print("the self-test doesn't run in combat - try again when you're out of it.")
        return 0, 0
    end
    local list = Addons()
    if #list == 0 then
        Print("no YippYapp addon has registered anything to test.")
        return 0, 0
    end

    local snap = Snapshot()
    local found, other, ran = {}, {}, {}

    for _, id in ipairs(list) do
        local fn = tests[id]
        if fn then
            ran[id] = true
            local ok, res, msg = pcall(fn)
            if not ok then
                Fail(found, id, "self-test", res)
            elseif res == false then
                Fail(found, id, "self-test", msg or "the addon reported a failure")
            elseif type(msg) == "string" and msg ~= "" then
                ran[id] = msg          -- "ok, message": the message is shown beside PASS
            elseif type(res) == "string" then
                ran[id] = res          -- a test that just returns a message counts as a pass
            end
        end
    end

    CheckWindows(other)
    CheckSettings(found)
    Restore(snap)

    local passed, failed, untested = 0, 0, 0
    for _, id in ipairs(list) do
        local problems = found[id]
        if problems then
            failed = failed + 1
            Print("|cffff4040%s: FAIL|r - %s", id, table.concat(problems, "; "))
        elseif ran[id] then
            passed = passed + 1
            local note = type(ran[id]) == "string" and (" - " .. ran[id]) or ""
            Print("|cff40ff40%s: PASS|r%s", id, note)
        else
            untested = untested + 1
            passed = passed + 1
            Print("%s: no self-test (the shared checks passed)", id)
        end
    end
    -- Errors that belong to no single addon (a shared window, the welcome window itself).
    for _, line in ipairs(other) do
        Print("|cffff4040error:|r %s", line)
    end

    if failed == 0 and #other == 0 then
        Print("%d of %d passed%s.", passed, #list,
            untested > 0 and (", %d of them without a self-test of their own"):format(untested) or "")
    else
        Print("%d of %d passed, %d with errors%s. Please report them with /yippyapp debug.",
            passed, #list, failed,
            #other > 0 and (", and %d error(s) outside any one addon"):format(#other) or "")
    end
    return passed, failed + #other
end
