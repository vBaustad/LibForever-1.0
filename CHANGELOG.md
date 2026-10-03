# Changelog

## Unreleased

- Fixed before anyone else saw it: removing the welcome window took a scroll helper with it that the
  settings window still used, so opening the window wrote an error to the chat frame.
- The welcome window is gone - the home page with its cards, every addon's page in it, and the beta
  banner. Each addon's own explanation moved onto its settings page, which is where you go looking
  for it. What is left is one window: a list of your YippYapp addons and the settings of whichever
  one you pick.
- The launcher bar is gone, and with it the shared YippYapp settings page, which had nothing left on
  it. The YippYapp minimap button is simply how it works now; each addon decides whether it appears
  in the row, on its own settings page.
- The settings the launcher and the welcome window saved are cleared out of every addon's file, once,
  by the library that put them there. Hiding an addon from the old bar is NOT read as hiding it from
  the minimap: different things, and nobody asked for the second.
- Old versions of our addons keep working. Everything they call that has been removed now quietly
  does nothing instead of erroring, because the newest copy of the library serves every addon you
  have installed - including the ones you have not updated yet.
- Fixed: on the YippYapp settings page the per-addon "Settings..." buttons were cut off at the right
  edge. The page's content was built at a fixed 600 wide inside a window that gives it 544, so
  everything right-aligned sat past the visible edge. It now takes the width it is actually given.
- New: LIB.AddHelp(panel, sections, y) puts an addon's help text at the bottom of its own settings
  page, wrapped to the real page width and re-wrapped when the window resizes, so every addon's help
  reads the same way instead of six pages inventing six layouts.
- The footer's "Buy me a coffee" is now a line you can read rather than a small icon, and the
  "Psst - you have all 6 YippYapp addons" line is gone.

## 1.0.6

- Names: when the client's second value is neither our realm nor obviously a surname, the client's own
  realm check settles it (UnitRealmRelationship, with the unit's GUID as backup) instead of a setting
  deciding. Without that, a group member from another realm was read as having a surname.
- /yippyapp debug now prints every source the client has for your own name side by side, raw, with nil
  and an empty value told apart, next to the spelling the guild roster uses. One run of it says which
  part of the client actually knows your surname.
- Names: which of the two values UnitName returns is a realm is now decided by looking at the value -
  your own realm is a realm however it is spelled - instead of trusting a setting to say what it means.
- Characters with a surname were only half recognised. WoW: Forever gives the surname as the second
  value from UnitName - the same slot that holds the realm when surnames are off - so anything built
  from the first value alone called "Lorr Den" just "Lorr". That is why your own messages could come
  back looking like someone else's. Names are now put together the way the client does it itself, and
  UnitKey and Me() share one code path so they can't drift apart.
- /yippyapp debug now prints what the client says your name is next to the spelling the guild roster
  uses, and says plainly when the two disagree.
- New: LIB.IsMyStoredName(key), so an addon can recognise records it saved under the old short name
  and merge them instead of starting over. It accepts either spelling of your own name and refuses
  anyone else's, including a player who shares your first name.
- The welcome window opens by itself again, once, when an addon needs setting up or an update brings
  a new message - but only on a client that keeps your settings (build 70009 and newer). On an older
  client it stays quiet, because "already seen" can't survive there and it would greet you at every
  reload, which is the thing people rightly complained about.
- Fixed while testing that: a window that opened by itself never recorded that you had seen it, so the
  same card brought it back at the next login until the addon was set up. It now counts as seen when
  you close it - one greeting per addon, and a newly installed addon still gets its own.
- WoW: Forever build 70009 fixes the client bug that lost addon settings, so the warning about it now
  depends on the client you are running. On 70009 and newer nothing is said, because an empty settings
  file there simply means you just installed us - and the note about Forever forgetting settings is
  gone from the window's home page too, with the cards taking the space back.
- On a fixed client a brand-new player now gets their setup prompts again: we no longer mistake a
  first install for lost data and hide them.
- On an older client nothing changes: the warning, the note and the caution are all still there.
- Fixed: LIB.Realm() returned two values when it had to fall back on the raw realm name (the string and
  gsub's replacement count), so a caller passing it straight on carried the number with it.
- New: LIB.UnitKey(unit) and LIB.NormalizeRealm(realm). UnitName gives another player's realm raw
  ("Bleeding Hollow") while an addon message's sender is normalised ("BleedingHollow"), so a key built
  from one never matched the same player heard through the other. That was a real bug in Campfire;
  now nobody has to know about it.
  UnitKey also answers nil when the client is keeping a unit's identity secret (in a battleground,
  for instance) - nil there means "we don't know who this is right now", not "nobody is there".

## 1.0.5

- Settings pages no longer have to guess how wide they are. `LIB.OptionsWidth(panel)` answers with the
  width the page actually has, and `LIB.OnOptionsResize(panel, fn)` calls you with it whenever the window
  shows or resizes the page. A page that scrolls gets 28 pixels less than one that doesn't, which is why
  a hard-coded number was wrong on one of the two and cut text off mid-sentence.
- `LIB.OptionsMetrics()` hands out the measurements our pages share (padding, indent, control column,
  row height and the standard gaps), so six pages don't each invent their own.

## 1.0.4

- New: `/yippyapp test` - one command that says whether anything is broken. Each addon can
  register its own test (LIB.RegisterSelfTest), and on top of those the runner opens and closes every
  window and settings page, draws every welcome card and page, and fires every launcher tooltip. It
  never runs in combat and puts back everything it touched, including the "seen" flags.
- Fixed: opening one addon's page before the window had ever been opened this session threw an error
  instead of opening it (an addon's own "Welcome" button could land there).
- Housekeeping before the next release: the three views in the welcome window now switch through one
  place, so no view can leave another one's frames on screen, and the two switches that turn
  opening-by-itself back on sit next to the machinery they control.
- Removed what nothing reads any more: LIB.frames, LIB.welcomeCatalog, LIB.LayoutLauncher,
  LIB.RefreshMinimapButtons, and LIB.RegisterSettingsPage with the table behind it (settings pages
  are registered with RegisterOptionsPage). The no-op LIB.RequestRoster and LIB.SetLauncherBadge stay:
  addon versions already on CurseForge call them, and the newest embedded copy of the library is the
  one that answers.
- The welcome window no longer writes a "notice seen" flag while it never opens by itself.
- README: the provider contract between our addons (ProvideData/GetData, Keep and Tier) is written down.
- The warning about settings that didn't load no longer tells you to restart the game to get them
  back: a full restart sometimes works and often doesn't, and sending people to relog for nothing is
  worse than saying nothing. It now says what is true - the client couldn't read them this session,
  it's a Forever bug, and the addons run on defaults until it can. The note in the window adds the
  only sure answer: keep a copy of your WTF folder.
- The library now decides whether the saved variables loaded about 2 seconds after login instead of 5,
  so an addon asking SavedVariablesLoaded() gets the truth sooner.
- If you already had the window open when that answer arrived, the cards are drawn again, so they stop
  asking you to set up addons we can no longer tell are set up.

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
