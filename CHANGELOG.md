# Changelog

## 1.0.0

The first public release. This is the shared library behind the YippYapp addons for WoW: Forever.

- **Core:** events and callbacks, and identity that copes with realmless names and hidden surnames. The guild
  roster is built from the updates the server sends; the library never requests it, because that request
  shows Forever's "blocked" dialog. Guild comms queue while chat is locked down. Map distances are in yards,
  with correct maths across zones on the same continent. Saved-variable defaults and migrations.
  A newer copy of the core safely takes over from an older one.
- **Launcher:** an optional bar at a screen edge, with one button per addon. It is off by default for new
  players; players who had already moved it or restyled it keep it on. It shows no notifications. You can
  drag it along any screen edge, and it can collapse until hovered. Its state is kept in every registered
  addon's saved table.
- **Windows:** registered windows are toplevel and draggable and remember their position. The first time,
  they open beside the other open windows. Escape closes one window or popup at a time, frontmost first.
  Close buttons work in combat.
- **Welcome:** one welcome window for the whole family, with one tab per addon and a quiet list of the
  sibling addons. It opens by itself only when an addon needs setup, and never in combat or in an instance.
  `/yippyapp` opens it.
- **Minimap:** minimap buttons through LibDataBroker and LibDBIcon. By default the family shares one
  YippYapp button that opens a row of the addons' buttons; this grouping can be turned off.
- **Settings:** one YippYapp page under Options > AddOns, with each addon's own settings page listed
  under it. The page holds the shared settings and a row per addon for its minimap and launcher buttons.
  `/yippyapp settings` opens it.
