# Changelog

## 1.0.2

- Addon messages go by the game's own answer: sent, or refused (for example during an encounter). Refused
  messages wait and are sent again when the restriction lifts. LIB.CommStats shows sent, received and refused.
- Guildies are recognised from the guild addon channel too, so whispers from them are never dropped when the
  guild roster is empty or incomplete (LIB.KnownGuildie).
- Our windows and popups open above Blizzard's Settings instead of closing it, which could raise an
  ADDON_ACTION_FORBIDDEN error.
- Welcome window: tab labels are centred on the tab art.

## 1.0.1

- **Addon messages are sent again.** Messages were held back while the game's chat lockdown was on, but that
  lockdown only covers real chat, so nothing was sent at all. LIB.Send now sends straight away.
- LIB.WhisperName(full): whispers to players on your own realm drop the realm suffix, so they arrive.
- LIB.CommStats(prefix): messages sent and received this session.
- The shared YippYapp minimap button keeps its position after a reload.
- Options > AddOns > YippYapp is now a parent category, with each addon's settings page under it.
- Welcome window: tabs line up with the page and the labels are centred; the unseen dots are gone.
- Launcher on/off is remembered reliably.

## 1.0.0

The first public release. This is the shared library behind the YippYapp addons for WoW: Forever.

- **Core:** events and callbacks, and identity that copes with realmless names and hidden surnames. The guild
  roster is built from the updates the server sends; the library never requests it, because that request
  shows Forever's "blocked" dialog. Guild addon messages go out straight away: chat messaging lockdown does
  not apply to addon messages, and the library counts what each prefix sends and receives. Map distances are in yards,
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
