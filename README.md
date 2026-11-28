# Forever Standalone Quest Log

A classic-style quest log window for WoW Forever. Forever draws the modern quest log attached to the world map; this add-on brings back a standalone two-pane window in the old Classic look, opened with **L** at the classic spot on the left side of the screen.

## Features

- **Classic two-pane window.** Quest list on the left page, quest details on the parchment on the right, in the original Classic quest log art, buttons and close button.
- **Quest levels and difficulty colours.** `[24] Quest name`, coloured grey / green / yellow / orange / red by difficulty, with Elite, Dungeon, Daily, Weekly, Repeatable, (Complete) and (Failed) tags, and a countdown on timed quests.
- **Search** by quest name or zone, and **collapsible zones** that don't affect the game's own map log. The **All** button above the list expands or collapses every zone at once.
- **Remembers your place.** The window reopens on the quest you last had selected, or the one you're super-tracking.
- **Details page** with objectives and progress (finished ones greyed out), the description, and the rewards: XP, money and reward items. Hover an item for its tooltip (Shift compares it with what you're wearing), Shift-click to link it, Ctrl-click to try it on.
- **Questie details.** With Questie installed, the details page shows the reputation rewards (with your bonuses applied), who gives the quest and who you turn it in to (and in which zone), its required level, and the quest before and after it in its chain.
- **Hover tooltips.** Hover a quest in the list to see its objectives and progress without selecting it.
- **Turn-in hint.** Finished quests say where to hand them in ("Return to Elder Bloodhoof in Thunder Bluff"), in the tooltip and on the details page; from Questie's data when the game doesn't say.
- **Quest items.** For quests with an item to use, a button in the bottom bar uses it. The game doesn't let add-ons show this kind of button in combat, so it steps aside while you fight and comes back afterwards.
- **Party members on the quest.** A count next to each quest your party shares, and their names on the details page.
- **Abandon, Share and Track** buttons. Shift-click a quest to link it in chat, Ctrl-click to track or untrack it.
- **Show Map** button: opens the world map at the zone where the quest is turned in (once it's complete) or where its objectives are. Uses Questie's quest data when Questie is installed; otherwise the game's own quest location, or your current zone.
- **Quest clicks open this window.** Clicking a quest in Questie's tracker or Blizzard's (including its right-click "View in Quest Log"), or clicking a quest timer, opens it here instead of on the world map. The micro menu's Quest Log button opens this window too, like L.
- **Settings** (cogwheel): text size for quest names, category titles and quest text, category title colour, window width and height, and toggles for levels, colours, list tooltips, the L key and quest clicks.
- **Lock** (padlock): left-click to lock or unlock dragging, right-click to put the window back at the classic left-side spot.

## Commands

- `/fql` toggles the window
- `/fql key` toggles whether L opens this window or the game's map quest log
- `/fql levels` toggles quest levels
- `/fql colors` toggles difficulty colours
- `/fql reset` moves the window back to the left side of the screen
- `/fql hooks` checks which quest clicks are being redirected

There's also a **Toggle Forever Standalone Quest Log** key binding under Key Bindings → AddOns.

## Notes

- Built for the WoW Forever client (interface 16001), which uses the modern `C_QuestLog` API.
- If you've collapsed a zone in the game's map quest log, this window expands it again: the game hides quests under collapsed zones from add-ons.

## License

MIT
