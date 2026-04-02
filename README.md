# Desolate Lootcouncil

A Master Loot automation tool for WoW Retail. Desolate Lootcouncil manages bidding, priority, and item distribution on top of the standard Group Loot system.

**Latest Version:** v0.7.3-Beta  
**Last Updated:** 2026-04-02  
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

### v0.6.5-Beta
* **Trade UI Bugfix**: Fixed invalid `STATIC_POPUP_SHOW` API event registration that blocked Trade Window confirmations from capturing items securely.
* **Voting Integrity**: Item GUID generators now use precise `GetTime()` timestamps instead of weak random boundaries to prevent identical loot drops from colliding and vanishing from the UI.

### v0.6.4-Beta
* **Voting Scroll Retention**: The Voting window no longer resets scroll position to the top when refreshing during an active session; depth is perfectly preserved on re-render.

### v0.6.3-Beta
* **Disenchant Stability**: Disenchanter list is now much smoother. Reduced visual flickering during ping intervals by caching skill data persistently and cleaning up roster tracking.

### v0.6.2-Beta
* **Chat Log Reduction**: Substantially cleaned up chat log formatting. Downgraded standard mechanical system logs (like background packet parsing) to Debug-only visibility. Added silence conditions while running solo.

### v0.6.1-Beta
* **Item Icons Polish**: Resolved anchoring bugs in History/Trade UI and fixed invisible frame artifacts that were overlapping tooltip interactables after the broader 0.6.0 icon rollout.
* **Rollback Stability**: Ensured backward compatibility following a partial reversion logic pass.

### v0.6.0-Beta
* **Item Icons Everywhere:** Integrated 24x24 interactive icons across Voting, Loot Collector, Session Monitor, History, and Trade List windows. Icons feature full tooltips on hover/click for rapid identification.
* **Offspec Voting:** Introduced a new "Offspec" vote category. It sits in priority between Transmog and Roll (Bid > Roll > Offspec > T-Mog > Pass).
* **UI Modernization:** Redesigned the Voting window rows to support a 5-button layout + Icon on a single line, even in minimized states.
* **LFR Safety:** Added automatic loot collection filtering for LFR/Looking For Raid. The Loot Collector now ignores LFR drops to prevent council interference in personal loot environments.
* **Simulation Visibility:** Simulation (`/dlc sim`) and Debug logs now output to chat even when solo, ensuring feedback is visible during development and testing.
* **Window Intelligence:** Minimized loot windows now automatically maximize when new loot is added to the session.
* **Technical Fixes:** 
    * Resolved "Cannot anchor to itself" Lua error in Trade List and History.
    * Fixed item name resolution (placeholder "Item...") using asynchronous `ContinueOnItemLoad` refresh.
    * Corrected Offspec count tracking in the Monitor summary index.