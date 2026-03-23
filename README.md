# Desolate Lootcouncil

A Master Loot automation tool for WoW Retail. Desolate Lootcouncil manages bidding, priority, and item distribution on top of the standard Group Loot system.

**Latest Version:** v0.4.2-Beta  
**Last Updated:** 2026-03-23  
**Compatibility:** WoW 12.0.1 (Midnight)  


📄 [View Design Document](https://docs.google.com/document/d/1YSH8LIx4ka85DvqN9HsUKGpMZtdZnULBxX_Y53BeQN0/edit?usp=sharing)

## 🚀 Features

### For Loot Masters
* **Automation:** Smart LM detection and automatic disenchanter assignment.
* **Fairness:** Automatic Alt-to-Main linking ensures priority points and penalties apply to the account, not just the character.
* **Control:** A unified Session Monitor to track live bids and an "Undo" system to revert mistaken awards.
* **Security:** Server-side rolls for Transmog/Offspec to prevent client-side manipulation.

### For Raiders
* **Simple UI:** Clean buttons for Bid (Priority), Roll, Transmog, or Pass.
* **Trade Helpers:** Automatic whispers when you win and a "Pending Queue" if you're out of range or offline during the award.
* **Transparency:** Publicly accessible session history and priority logs.

### For Developers
* **Simulation:** Use `/dlc sim` to spawn virtual players and test voting logic solo.
* **Testing:** Comprehensive unit/integration test suite included.

## 💻 Commands

| Command | Description |
| :--- | :--- |
| `/dlc config` | Open configuration (Roster, Priority, Debug). |
| `/dlc monitor` | **(LM)** Live session & award dashboard. |
| `/dlc loot` | **(LM)** Inbox for new dropped items. |
| `/dlc im` | Open Item Manager window. |
| `/dlc trade` | **(LM)** Pending trades queue. |
| `/dlc history` | View award logs and priority changes. |
| `/dlc sim` | **(Dev)** Manage simulated players and scenarios. |

## 🛠️ Installation
1. Download the latest release.
2. Extract `Desolate_Lootcouncil` to `_retail_/Interface/AddOns/`.
3. Restart WoW.

---

## 📝 Recent Changes
 
### v0.4.2-Beta
* **Session Restoration:** Improved login logic; sessions now persist for up to 12 hours. LMs are prompted to close stale or ungrouped sessions on login.
* **Assist Synchronization:** Added real-time vote syncing. Assistants can now view roll progress in the Session Monitor.
* **UI Monitor:** The "Award" button is replaced with "View Rolls" for non-LMs to prevent accidental distribution while ensuring transparency.
* **Micro-Fixes:** Corrected an off-by-one error in player counting for auto-pass and added a 0.5s safety delay to trade completion logic.
* **Sidebar:** The disenchanter sidebar now automatically hides when the Monitor window is collapsed.

### v0.4.1-Beta
* **Item Caching:** Fixed display issues where items would show as "ID" instead of names. Windows now automatically refresh as soon as item data is cached (ContinueOnItemLoad).
* **Item Manager:** Added `/dlc im` slash command and a "Sync Raid" button for officers to share item-to-list categorizations with the raid.
* **Roster:** Improved attendance logs with descriptive rejection reasons (alt resolution) and actionable stale-session alerts.
* **Auto-Pass:** Added detailed logging when auto-pass is blocked to explain exactly how many raid members are missing the addon.

### v0.4.0-Beta
* **Loot Display:** Items now show the correct dropped ilvl and affixes in all windows (Loot, Vote, Trade, Monitor).
* **Trading:** All pending items for a player are now staged in a single trade window; awarded items are removed from the pending list automatically.
* **Vote Window:** Already-awarded items are filtered out of the Loot Vote window.
* **Loot Window:** Restricted to the Loot Master only (or Raid Assist for read-only view).
* **Autopass:** Enabled by default; only passes on managed items; only triggers when all in-zone online raid members have the addon.
* **History:** Loot History is now broadcast to all raiders on each award and auto-refreshes when open. Accessible from Settings → General.
* **Monitor Collapse:** Footer buttons and disenchanter sidebar correctly hide when the window is minimised.
* **Version Window:** Refresh/Ping button now waits 1.5 s for responses before re-rendering.
* **Session Persistence:** Loot Master identity is saved across /reload.
* **Stability:** Fixed `db.callbacks:Register` crash on login (`RegisterCallback` API correction).

### v0.3.3-Beta
* **Fixes:** corrected disenchanters overview to only display characters with the Enchanting profession and accurately show the latest expansion's skill level.
* **Communication:** improved data handling for profession skill levels in addon messages.

### v0.3.2-Beta
* **Automation:** Set up CurseForge automation with GitHub Actions and optimized `.pkgmeta`.
* **Architecture:** Restructured XML embeds, moving all library and script imports to specialized XML files (`Libs/Libs.xml` and `Desolate_Lootcouncil.xml`).
* **Cleanup:** Cleaned up the `.toc` file, leaving only metadata and the main XML entry point.

### v0.3.1-Beta
* **Stability:** Fixed critical bugs involving collapsed windows and "Auto Pass" errors during active sessions.
* **UI:** Added "Pending Voters" tooltips and polished layout clipping in the Vote window.
* **Tests:** Fully updated the persistence mocks in the automated test suite.

### v0.3.0-Beta
* **Refactor:** Migrated to a "Hub-and-Spoke" architecture for better performance.
* **Linking:** Standardized Alt-to-Main resolution across all modules.
* **Testing:** Introduced a Python-based test runner with 15 core integration tests.