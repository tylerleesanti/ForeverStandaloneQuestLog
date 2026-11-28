# Changelog

## 1.1.0

### New

- **Dark theme.** Pick Classic (the quest log art, still the default) or Dark, a flat dark window with light text, slim scroll bars and flat buttons, from the Theme dropdown in the settings.
- **Reward items** on the details page, with their tooltips (hold Shift to compare), Shift-click to link and Ctrl-click to try on. Each name sits in a dark box with a border in the item's rarity colour, and items per row follow the window width.
- **Questie details:**
  - reputation rewards, with your bonuses applied;
  - a chain icon after quests that are part of a chain;
  - an info icon after the quest's name. Hover it to see who gives the quest, who takes it and where, its required level, and the quests before and after it in its chain.
- **Quest ID** in the info pop-up, with or without Questie.
- **List tooltips:** hover a quest to see its objectives and progress.
- **Turn-in hints:** finished quests say where to hand them in, in the tooltip and on the details page.
- **Daily, Weekly and Repeatable tags,** and a countdown on timed quests.
- **Quest item button:** quests with an item to use get a button in the bottom bar (out of combat).
- **Party members on each quest:** a count in the list, and their names on the details page.
- **All button:** expands or collapses every category at once.
- **Picks up where you left off:** the window reopens on the quest you last had selected (per character), or the one you're super-tracking.
- **More ways to open it:** the Quest Log micro button, the tracker's "View in Quest Log" and quest timers now open this window.

### Changed

- **Settings:**
  - "Zone title" is now "category title";
  - the panel holds still while you drag the width slider;
  - Reset to Default also resets the checkboxes and the theme.

### Fixed

- Delivery quests no longer repeat their summary as their objective and turn-in text.

## 1.0.0

First release.

- Standalone two-pane quest log window in the Classic quest log art, opened with L at the classic spot on the left side of the screen.
- Quest levels, difficulty colours, and Elite / Dungeon / Complete / Failed tags.
- Search by quest or zone, and collapsible zones.
- Details page with objectives, description, and XP and money rewards.
- Abandon, Share and Track buttons; shift-click to link, ctrl-click to track.
- Show Map button: opens the world map where the quest is turned in (completed quests) or where its next objective is, using Questie's data when Questie is installed.
- Clicking a quest in Questie's or Blizzard's tracker opens it in this window.
- Settings panel (cogwheel): text sizes, zone title colour, window width and height, and feature toggles.
- Padlock button to lock the window's position; right-click it to reset the position.
