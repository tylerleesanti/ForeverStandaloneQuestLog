# Forever Standalone Quest Log

A classic-style quest log window for WoW Forever. Forever draws the modern quest log attached to the world map; this add-on brings back a standalone two-pane window in the old Classic look, opened with **L** at the classic spot on the left side of the screen.

## Features

- **Classic two-pane window.** Quest list on the left page, quest details on the parchment on the right, in the original Classic quest log art, buttons and close button.
- **Quest levels and difficulty colours.** `[24] Quest name`, coloured grey / green / yellow / orange / red by difficulty, with Elite, Dungeon, (Complete) and (Failed) tags.
- **Search** by quest name or zone, and **collapsible zones** that don't affect the game's own map log.
- **Details page** with objectives and progress (finished ones greyed out), the description, and XP and money rewards.
- **Abandon, Share and Track** buttons. Shift-click a quest to link it in chat, Ctrl-click to track or untrack it.
- **Show Map** button: opens the world map at the zone where the quest is turned in (once it's complete) or where its objectives are. Uses Questie's quest data when Questie is installed; otherwise the game's own quest location, or your current zone.
- **Tracker clicks open this window.** Clicking a quest in Questie's tracker (or Blizzard's) opens it here instead of on the world map.
- **Settings** (cogwheel): text size for quest names, zone titles and quest text, zone title colour, window width and height, and toggles for levels, colours, the L key and tracker clicks.
- **Lock** (padlock): left-click to lock or unlock dragging, right-click to put the window back at the classic left-side spot.

## Commands

- `/fql` toggles the window
- `/fql key` toggles whether L opens this window or the game's map quest log
- `/fql levels` toggles quest levels
- `/fql colors` toggles difficulty colours
- `/fql reset` moves the window back to the left side of the screen
- `/fql hooks` checks that tracker clicks are being redirected

There's also a **Toggle Forever Standalone Quest Log** key binding under Key Bindings → AddOns.

## Notes

- Built for the WoW Forever client (interface 16001), which uses the modern `C_QuestLog` API.
- If you've collapsed a zone in the game's map quest log, this window expands it again: the game hides quests under collapsed zones from add-ons.

## License

MIT
