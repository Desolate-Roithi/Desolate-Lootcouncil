# Desolate Lootcouncil

An automated Master Loot helper for World of Warcraft Retail. Desolate Lootcouncil coordinates bidding, priority lists, and item distribution alongside the default Group Loot system.

**Latest Version:** v1.0.6-Alpha  
**Last Updated:** 2026-06-05  
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

### v1.0.6-Alpha
* **Settings Layout & NativeGUI Size Persistence**:
    - Resolved a layout issue where double-clicking the title bar to collapse a window (saving the collapsed 220x42 dimensions to the DB) caused the window to load at an extremely narrow width of 220 on next reload. The persistence engine now saves the original expanded dimensions when a window is collapsed, and the creation logic programmatically collapses windows on reload once all child elements are fully initialized.

### v1.0.5-Alpha
* **Raid-Only Roster Gating**:
    - Restricted the automatic scanning and adding of new players to the priority lists to Raid groups and Raid instances only. This prevents officers' databases from being altered and warnings about alts being printed in 5-man party groups.
* **WoW 12.0.7 API Compatibility**:
    - Checked all group management API shifts coming in Patch 12.0.7 (such as global functions migrating into `C_PartyInfo`) and verified full compatibility.

### v1.0.4-Alpha
* **Trade Window Auto-Refresh**:
    - Added automatic refresh for the Pending Trades and History windows on item award/re-award, decoupling modules.
* **UI Row Pooling & Virtual Scrolling**:
    - Optimized rendering with virtual row pooling, reducing nested layout nesting levels, and enhancing the Item Manager.

### v1.0.3-Alpha
* **Group Leader & Loot Master Robustness**:
    - Added leader change tracking to automatically reset and recalculate the Loot Master when the Group Leader changes.
* **Item Manager Sync Gate**:
    - Prevented automatic or manual item manager database syncing in raids with fewer than 10 players to avoid spamming small groups.
* **History Retention**:
    - Ensured that the awarded items database (`session.awarded`) is preserved and only wiped on starting a new raid session rather than individual voting sessions.
* **Recipe Voting Options**:
    - Added specialized recipe voting buttons (Item Class 9). Displays exactly 3 buttons on the Voting Window: "Ready to Craft" (for immediate learning), "Unskilled" (for missing profession skill levels), and "Pass".
* **EditBox Shift-Click Link Insertion**:
    - Allowed raiders to Shift-Click item links into custom EditBox input fields (e.g. the Item Manager's item name input) and restored keyboard focus.

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

---

## Beta Releases (v0.8.5-Beta - v0.9.5-Beta)

Major features and stability improvements introduced during the Beta phase:
* **Modular Architecture**: Separated the background automatic passing systems from the front-end interface to improve latency and stability.
* **Alt and Roster Management**: Added automatic registration of mains, alt-character linking, and intelligent raid disband alert suppression.
* **Encounter Tools**: Integrated a custom boss sequence widget (for Lu'Ra encounter) allowing coordination of raid markers.
* **Network & Database Safety**: Improved packet routing, hardened database check validation, and added trade safeguards to prevent accidental item equipping.
* **Localization Foundation**: Structured UI systems to support multi-language localizations.