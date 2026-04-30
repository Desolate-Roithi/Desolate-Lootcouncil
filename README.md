# Desolate Lootcouncil

A Master Loot automation tool for WoW Retail. Desolate Lootcouncil manages bidding, priority, and item distribution on top of the standard Group Loot system.

**Latest Version:** v0.7.9-Beta  
**Last Updated:** 2026-05-01  
**Compatibility:** WoW 12.0.5 (Midnight)  

## 🚀 Features

### For Loot Masters
* **Automation:** Smart LM detection and automatic disenchanter assignment.
* **Fairness:** Automatic Alt-to-Main linking ensures priority points and penalties apply to the account, not just the character.
* **Control:** A unified Session Monitor to track live bids and an "Undo" system to revert mistaken awards.
* **Security:** Server-side rolls for Transmog/Offspec to prevent client-side manipulation.
* **Cross-Realm Support:** Robust name-realm handling for consistent tracking across connected realms.

### For Raiders
* **Simple UI:** Clean buttons for Bid (Priority), Roll, Offspec, Transmog, or Pass.
* **Autopass Automation:** Fully automated roll/pass logic based on item categories and session settings.
* **Trade Helpers:** Automatic whispers when you win and a "Pending Queue" if you're out of range or offline during the award.
* **Transparency:** Publicly accessible session history and priority logs.

## 💻 Commands

| Command | Description |
| :--- | :--- |
| `/dlc config` | Open configuration (Roster, Priority, Debug). |
| `/dlc vote` | Re-open the Voting Window (if a session is active). |
| `/dlc monitor` | **(LM/Assist)** Live session & award dashboard. |
| `/dlc loot` | **(LM)** Inbox for new dropped items. |
| `/dlc im` | Open Item Manager window. |
| `/dlc trade` | **(LM)** Pending trades queue. |
| `/dlc history` | View award logs and priority changes. |
| `/dlc status` | View current LM, Autopass, and session status. |
| `/dlc version` | Check addon versions across the raid. |
| `/dlc sim` | **(Dev)** Manage simulated players and scenarios. |

## 🛠️ Installation
1. Download the latest release.
2. Extract `Desolate_Lootcouncil` to `_retail_/Interface/AddOns/`.
3. Restart WoW.

---

## 📝 Recent Changes

### v0.7.9-Beta
* **Autopass Stability & Initialization**:
    - **Initialization Fix**: Autopass state no longer reports as `nil` on cold-start; it now defaults to a deterministic `false` state until a session begins.
    - **Persistence across Zones**: Resolved a critical issue where moving between wings in a raid (e.g., internal zone transitions) would reset the Autopass state. The LM is now intelligently re-prompted if the state becomes desynced mid-session.
* **Trade Window Accuracy**:
    - **Soulbound Guard**: Added a mandatory `isBound` check to the automated trade staging logic. This ensures that the addon correctly distinguishes between the fresh, tradeable drop and any soulbound copies the Loot Master may already have in their bags.

### v0.7.8-Beta
* **Loot Automation Stability**:
    - Added a 0.05s delay to auto-roll/pass actions to ensure compatibility with Blizzard's internal UI state updates (RCLootCouncil parity).
    - Restricted corpse scanning logic to the **Loot Master only**. This eliminates redundant network traffic and prevents raider backlog issues during large boss kills.
    - Implemented a **Solo-Cleanup routine**: The addon now automatically wipes stale loot backlogs if you log in outside of a raid, ensuring the UI stays clean.
* **Trade Management**:
    - Introduced a 0.2s delay for trade item staging. This prevents race conditions with the WoW server that previously caused items to fail to move into the trade window.
    - Added defensive guards to the Trade Frame to prevent accidental "self-equipping" of items during automated trade sessions.
* **UI & Disenchanter Sidebar**:
    - Fixed a visibility bug where the Disenchanter sidebar would "ghost" or fail to hide when the Session Monitor was collapsed or expanded.
    - Optimized the sidebar refresh logic to correctly handle version-check data arrivals during active combat.

### v0.7.5-Beta
* **Communication & Synchronization**:
    - **Heartbeat Autopass Sync**: Added the `sessionAutopass` state to the periodic heartbeat and `START_LOOT_ROLL` events to ensure late-joiners never miss the "Auto-Pass" signal.
    - **Channel Safety**: Implemented a `GetBroadcastChannel` utility to safely route messages via `RAID` or `PARTY` depending on current group status.
* **Loot Council Refactor**:
    - **Re-award Restoration**: Completely reworked the `ReawardItem` function. It now correctly restores a player's original priority position and restores all previous voting data to the monitor.
    - **Modular Awarding**: Split the massive `AwardItem` function into testable helper methods for broadcasting, recording, and cleanup.
* **General UI Improvements**:
    - Added a detailed `/dlc status` command to verify current LM, Autopass status, and session counts.
    - Resolved a layout bug in the **Monitor UI** that caused the scroll frame to hide itself incorrectly when expanded from a collapsed state.
    - Implemented `SmartCompare` for player names to handle 12.0.1 "Secret" (opaque) string returns safely.

### v0.7.3-Beta
* **Network Architecture Overhaul**: Optimized the entire communication engine by transitioning from whisper-based voting (which caused LM lag spikes) to a high-performance **RAID Channel Pub/Sub** model.
* **Intelligent Heartbeats**: Replaced the constant 1.5s "Sync" pulse with a 30-second **Serialized Heartbeat**. This uses a pre-cached payload to resync the full item list and vote matrix to late-joiners and reloaders without overhead.
* **UI Focus & Retention**: 
    - **Newest on Top**: Both the Loot Backlog and Voting windows now display new additions at the top of the list for immediate visibility.
    - **Scroll Stickiness**: Fixed the "Scroll Snap" bug; the windows now remember your exact scroll position during automated UI refreshes.
* **Loot Collection Stability**: 
    - **Duplicate Drop Fix**: Resolved a long-standing issue where identical items from the same boss were discarded. Keys now include slot indices (`sourceGUID-itemID-slot`).
    - **Global Localization**: Switched to Blizzard global strings (`LOOT_ITEM_SELF`, etc.) to ensure LM loot detection works reliably on German, English, and other localized clients.
    - **Reload Persistence**: The Boss Corpse deduplication store now resides in the database, preventing items from reappearing in the backlog after a UI reload.
* **Network Throttling**: Enchanting skill data is now only broadcast once per session, and empty Skill 0 entries are dropped to reduce packet size.

### v0.7.1-Beta
* **Core UI Structural Refactor**: Successfully modularized monolithic functions across all primary UI windows (`Attendance`, `ItemManager`, `Monitor`, `PrioritySettings`).
* **Arrow Code Elimination**: Eliminated deep layout nesting, significantly reducing complexity and potential for scope-related bugs.
* **Encapsulated Configuration**: Configuration and profile management logic now reside in discrete, dedicated methods, improving AceConfig integration stability.
* **Refactor Verified**: Full unit test suite (`Priority`, `Roster`, `Comm`) confirms 0% regression and 100% functional parity with 0.7.0.

### v0.7.0-Beta
* **Decay System Overhaul**: Replaced the Priority Decay algorithm with a mathematically sound Bottom-To-Top Bubble-Down algorithm. Priority penalties now correctly push absent players below present players without gap collision.
* **Monitor Stabilization**: Resolved an AceGUI frame recycling bug that caused the Session Monitor to immediately hide itself during rapid UI window instantiation loops (`/dlc test`).