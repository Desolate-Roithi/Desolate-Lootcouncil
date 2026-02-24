# Desolate Lootcouncil

A Master Loot automation tool for WoW Retail. Desolate Lootcouncil manages bidding, priority, and item distribution on top of the standard Group Loot system.

**Latest Version:** v0.3.3-Beta  
**Last Updated:** 2026-02-25  
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
| `/dlc trade` | **(LM)** Pending trades queue. |
| `/dlc history` | View award logs and priority changes. |
| `/dlc sim` | **(Dev)** Manage simulated players and scenarios. |

## 🛠️ Installation
1. Download the latest release.
2. Extract `Desolate_Lootcouncil` to `_retail_/Interface/AddOns/`.
3. Restart WoW.

---

## 📝 Recent Changes

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