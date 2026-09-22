# LibForever-1.0

The shared library behind **YippYapp**, a family of addons for WoW: Forever (Guildhall, AutoFeed,
Skillwright, BuffWarden, Campfire). It is built for Forever only: the Mainline 12.x API with Midnight's
addon restrictions. It has no Classic Era or retail fallbacks.

Every addon embeds its own copy through [LibStub](https://www.wowace.com/projects/libstub). The newest
copy wins, and the rest share that one instance, so our addons can read each other's live data.
Each module carries its own version, so a newer copy of one file takes over without reloading the others.
The library has no SavedVariables of its own. Anything it remembers goes in the calling addon's saved
table, and state shared by the whole family (like the launcher and the grouped minimap button) is copied
into every registered addon's table.

## Modules

Load them from your TOC in this order, after LibStub. The core comes first; after that you only need
the modules you use.

| File | What it gives you |
|---|---|
| `LibForever-1.0.lua` | **Core.** Events and callbacks: `On(event, fn)`, `Listen`, `Fire`, `Debounce`. Identity: `Me`, `FullName`, `ShortName`, `ColorName`. The guild roster, from the updates the server sends: `roster`, `IsOnline`, `IsGuildie` (roster only) and `KnownGuildie` (roster, or heard on the guild addon channel). Guild addon comms: `RegisterComm`, `Send` (needs AceComm-3.0), with `CommStats(prefix)` for a sent/received count. Map distance in yards: `MyPosition`, `Distance`. Shared data: `ProvideData`, `GetData`. Saved-variable defaults and migrations: `PrepareDB(db, defaults, migrations, version)`. |
| `Maps.lua` | Generated Forever map sizes, which `Distance` uses. |
| `Launcher.lua` | **An optional launcher bar** at a screen edge, with one button per addon. It is off by default, and players turn it on from the YippYapp settings page. `RegisterLauncher(entry, savedTable)`, `SetLauncherHidden(id, hidden)`, `SetLauncherEnabled(on)`. `LauncherOptions(parent, id)` gives you a 300x60 block for your own settings page that links to the YippYapp page. |
| `Windows.lua` | **Window handling.** `RegisterWindow(frame, savedTable, key)` makes a window toplevel and draggable and saves where it was put. The first time, it opens beside our other open windows. Escape closes one window at a time, and the close button works in combat. `RegisterPopup(frame)` gives a popup the same Escape and close handling. |
| `Welcome.lua` | **One shared welcome window.** `RegisterWelcome(page, savedTable)` adds a tab for your addon, and `OpenWelcome(id)` or `/yippyapp` opens the window. It only opens by itself when an addon needs setup, and never in combat or in an instance. |
| `Minimap.lua` | **Minimap buttons**, through LibDataBroker-1.1 and LibDBIcon-1.0, which your addon ships. `RegisterMinimapButton(id, opts, savedTable)` and `SetMinimapButtonShown(id, shown)`. By default the YippYapp addons share one minimap button that opens a row of their buttons (`SetMinimapGrouped`). Each addon keeps its own LDB object for broker displays. |
| `Settings.lua` | **The YippYapp settings page**, at Options > AddOns > YippYapp or `/yippyapp settings`. It has minimap grouping and the launcher, and for each addon its minimap and launcher buttons with a link to its own page. `RegisterOptionsPage(id, frame, name)` lists your settings page under YippYapp and returns its category. `OpenYippYappSettings()` opens the page. |

```
Libs\LibStub\LibStub.lua
Libs\LibForever-1.0\LibForever-1.0.lua
Libs\LibForever-1.0\Maps.lua
Libs\LibForever-1.0\Launcher.lua
Libs\LibForever-1.0\Windows.lua
Libs\LibForever-1.0\Welcome.lua
Libs\LibForever-1.0\Minimap.lua
Libs\LibForever-1.0\Settings.lua
```

```lua
local LIB = LibStub("LibForever-1.0")

-- Your settings page, listed under YippYapp in Options > AddOns.
local category = LIB.RegisterOptionsPage("MyAddon", myPanel)
-- The shared launcher and minimap buttons (both optional).
LIB.RegisterLauncher({ id = "MyAddon", label = "MyAddon", icon = ICON, onClick = Toggle }, MyAddonDB)
LIB.RegisterMinimapButton("MyAddon", { icon = ICON, label = "MyAddon", OnClick = OnClick }, MyAddonDB)
-- Your main window: toplevel, draggable, remembered, closed by Escape.
LIB.RegisterWindow(myWindow, MyAddonDB, "pos")
```

Each file's header comment documents its full API.

## Rules for code that uses it

- **Never close Blizzard's Settings panel from addon code:** no `SettingsPanel:Close()`, `HideUIPanel(SettingsPanel)` or
  `ToggleGameMenu()`. Closing it returns to the game menu, which calls a protected function, and from addon code that
  is blocked (`ADDON_ACTION_FORBIDDEN`). To show one of your windows from a settings page, open it above the panel
  and leave the panel open, as the welcome window does.
- Don't gate addon messages on `InChatLockdown()`. That lockdown is for real chat; addon messages go out, and
  `Send` deals with a refused message itself.

## Embedding

Pull the library in through `.pkgmeta` externals. The CurseForge packager then fetches the tagged
release when it builds your addon:

```yaml
externals:
  Libs/LibForever-1.0:
    url: https://github.com/vBaustad/LibForever-1.0
    tag: v1.0.0
```

The `Media/` folder (the YippYapp emblem and the launcher preview) is part of the library and comes along.

For development, make `Libs\LibForever-1.0` a directory junction or symlink to one checkout, not a
copy. A stale copy that loads first would still run its own old modules.

## License

MIT. See [LICENSE](LICENSE).
