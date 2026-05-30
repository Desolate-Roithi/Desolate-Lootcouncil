# Desolate Lootcouncil

An automated Master Loot helper for World of Warcraft Retail. Desolate Lootcouncil coordinates bidding, priority lists, and item distribution alongside the default Group Loot system.

**Latest Version:** v1.0.2-Alpha  
**Last Updated:** 2026-05-31  
**Compatibility:** WoW 12.0.5 (Midnight)  

## Features

### For Loot Masters
* **Automation:** Automatically detects the Loot Master and manages disenchanting assignments.
* **Alt Linking:** Tracks alts and links them to main characters so priority rankings and penalties apply to the player's account.
* **Session Control:** Monitor active bids in real time and revert mistaken item awards easily.
* **Security:** Offspec and Transmog rolls are handled server-side to prevent manipulation.
* **Cross-Realm:** Handles player name and realm formatting seamlessly.

### For Raiders
* **Clean Interface:** One-click options for Main Spec (Priority), Roll, Offspec, Transmog, or Pass.
* **Automatic Passing:** Automatically passes or rolls on items depending on your settings and active priority lists.
* **Trade Management:** Whispers winners automatically and queues items for trade if a player is out of range or offline.
* **Logs:** View active priority logs and raid loot histories directly in-game.

## Commands

| Command | Description |
| :--- | :--- |
| `/dlc config` | Open the main configuration panel (Roster, Priority, Settings). |
| `/dlc vote` | Re-open the voting frame if a loot session is currently active. |
| `/dlc monitor` | Open the officer dashboard to track active bids and awards. |
| `/dlc loot` | Open the loot inbox to view newly dropped items. |
| `/dlc im` | Open the Item Manager to assign items to specific priority lists. |
| `/dlc trade` | Open the pending trades queue. |
| `/dlc history` | Open the session loot and attendance history window. |
| `/dlc status` | Print current connection, session, and autopass statuses to chat. |
| `/dlc version` | Query and verify addon versions installed by raid members. |
| `/dlc sim` | Developer tool to test simulated scenarios and players. |

## Installation
1. Download the latest release.
2. Extract the folder into your `Interface/AddOns/` directory.
3. Restart or reload World of Warcraft.

---

## Recent Changes

### v1.0.2-Alpha
* **Localization Auditing**:
    - Fixed a missing translation error for private voter notes inside the award window.
    - Added the missing settings action confirmation prompt.
    - Verified all translation strings across the codebase are fully covered in English and German.

### v1.0.1-Alpha
* **Unified Window Management**:
    - Standardized how all windows scale and position themselves, ensuring sizes are stored and restored consistently across reloads.
    - Removed hardcoded window dimensions to support scaling naturally.
* **Voting Frame Optimizations**:
    - Fixed a bug where reloading a session would reset the active countdown timer or re-trigger completed milestone warnings.
    - Blocked raider-only voting notifications from showing up for Loot Masters.
* **Award Notes Tooltip**:
    - Replaced raw note text displays in the award panel with a compact note icon. Hovering over the icon displays the player's private note.

### v1.0.0-Alpha
* **UI Themes**:
    - Cleaned up the core theme engine logic to make styling custom controls (buttons, inputs, dropdowns) more modular.
    - Reworked the main voting window layout to improve rendering speed and responsiveness.
* **Autopass Syncing**:
    - Added detailed log outputs to help officers diagnose automatic pass decisions.
    - Added an automatic state synchronization check when raid members load zones or run version checks.

### v0.9.2-Beta
* **Roster Disband Spam Fix**:
    - Fixed a bug where party roster changes in solo play or dungeons would print incorrect raid disband alerts. The alert now only displays when an active master loot session ends.

### v0.9.1-Beta
* **Network Stability**:
    - Improved packet routing and connection reliability under the current game client APIs.

### v0.9.0-Beta
* **Modular Code Separation**:
    - Separated the background automatic passing system from the front-end user interface.
    - Improved overall stability during periods of high server latency.

### v0.8.6-Beta
* **Encounter Widget Polish**:
    - Added a coordinate widget tool to allow solo players to test and preview sequences.
    - Roster management now automatically registers untracked addon users as mains during active sessions.
    - Added trade safety checks to ensure items cannot be accidentally equipped while trading.

### v0.8.5-Beta
* **Multi-Language Preparations**:
    - Structured all UI text blocks to support dynamic localization dictionaries.
    - Hardened the database validation check logic before automated pass actions are triggered.