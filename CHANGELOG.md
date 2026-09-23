# Changelog

## 1.0.3

- Hardening of the guild comms: every incoming message now passes a per-sender budget (30 messages per
  prefix per 10 seconds), so one broken or hostile client can't make our addons work without bound. What
  it dropped shows up in `CommStats` as `OverBudget`. The tables behind that, and the list of players
  heard on the guild channel, are capped as well.
- New `LIB.Sanitize(text, maxLen)`: strips control characters, turns "|" into "/" so no |H link,
  |T texture or |c colour can survive, trims and caps the length without cutting a UTF-8 character in
  half. Everything an addon takes from another player should go through it before being stored, sent
  or shown.
- Performance: the launcher's two per-frame handlers stop themselves the moment the bar is hidden, and
  the minimap and window position passes that work around Forever's reset now stop after login instead
  of running again on every zone change.

- All YippYapp settings now live in the YippYapp window, not in Blizzard's Options: opening Blizzard's
  Options closes whatever else you had open. Options > AddOns > YippYapp keeps one button that opens the
  window. The minimap button opens the window on left-click and its settings on right-click, and each
  addon's page has a settings wheel.
- A card's button now opens the addon itself, and only says "What's new" when that addon has something
  you haven't seen. Addons that need setting up say what the action is ("Create macros", "Scan prices").
- The welcome window no longer opens by itself at all, for now. While WoW: Forever forgets saved settings
  on a cold start, "already seen" cannot survive, so it would greet you every session. Open it whenever you
  like from the minimap button or /yippyapp. (In the code: AUTO_OPEN_FOR_SETUP and AUTO_OPEN_FOR_NOTICE in
  Welcome.lua, to switch back on once the client is fixed.)
- While the game has failed to load saved settings, nothing is flagged as needing setup either: we can't
  know what you have already done.
- The window says plainly that WoW: Forever currently forgets addon settings when you restart the game.

- Welcome window: it now opens on a home page with a card per installed addon. Anything that still needs
  setting up comes first, highlighted and with the reason; the rest sit under "All set". A card opens that
  addon's page, which has a back button and a sidebar for hopping between addons. The tab row is gone, so
  the window copes with any number of addons.
- The home page carries a gold-on-black banner: the addons are actively developed during the Forever beta,
  and every bug report and comment on CurseForge helps. Its button shows a link listing every YippYapp addon
  on CurseForge, ready to copy. The window opens once after this update so everyone sees it.
- YippYapp settings page: a "Buy me a coffee" button, and the page scrolls when the Settings window is
  shorter than it.
- Settings pages now always show their current values the first time they are opened.
  LIB.RegisterOptionsPage takes an optional page height and then scrolls the page.

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
