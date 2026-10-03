--- LibForever-1.0: the launcher bar, removed.
-- The bar is gone. What is left here is its entry points, doing nothing, because the library is
-- embedded in every addon and the NEWEST copy serves all of them: a player who updates one addon and
-- keeps another at a published version has that older addon calling these functions against this
-- library. Deleting them outright turns that into an error on login for something the player did not
-- do wrong. AutoFeed v1.4.0-beta7 and Campfire v0.1.0-beta7 are on CurseForge calling in right now.
--
-- They stay until the published versions that call them have aged out, which is not on our schedule:
-- the trigger is a player updating one addon and not another. Several versions, not one.
--
-- LauncherOptions returns a real (empty) frame on purpose - shipped callers anchor to what it returns
-- and then anchor the rest of their page below it, so nil would be an error. Everything else returns
-- the quietest truthful answer: there is no bar, so nothing is shown in it.
local LIB = LibStub and LibStub("LibForever-1.0", true)
if not LIB then return end

local VERSION = 17
if (LIB.launcherVersion or 0) >= VERSION then return end
LIB.launcherVersion = VERSION

-- An older copy of this file may have built the bar before this one loaded.
if LIB.notchFrame then
    LIB.notchFrame:SetScript("OnUpdate", nil)
    LIB.notchFrame:Hide()
    LIB.notchFrame = nil
end
LIB.launcherEntries = {}
LIB.launcherStores = {}

function LIB.RegisterLauncher() end
function LIB.SetLauncherHidden() end
function LIB.SetLauncherBadge() end
function LIB.SetLauncherStyle() end
function LIB.SetLauncherEnabled() end
function LIB.ResetLauncherPosition() end
function LIB.LayoutLauncher() end

function LIB.IsLauncherHidden() return true end
function LIB.IsLauncherEnabled() return false end
function LIB.GetLauncherStyle() return "grow" end

--- Kept shaped as it was: callers anchor to the frame this returns, so it must be a frame.
function LIB.LauncherOptions(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 1)
    return f
end

function LIB.DebugLauncher()
    print("|cffffd100YippYapp|r the launcher bar was removed; its settings went with it.")
end
