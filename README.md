# Desolate Lootcouncil

An automated Master Loot helper for World of Warcraft Retail. Desolate Lootcouncil coordinates bidding, priority lists, and item distribution alongside the default Group Loot system.

**Latest Version:** v1.0.0  
**Last Updated:** 2026-06-06  
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
| `/dlc reset` | Reset all window layout sizes and positions to defaults. |
| `/dlc sim` | Developer tool to test simulated scenarios and players. |

## Installation
1. Download the latest release.
2. Extract the folder into your `Interface/AddOns/` directory.
3. Restart or reload World of Warcraft.

---

## Recent Changes

### v1.0.0
Official stable release of Desolate Lootcouncil, introducing a complete Native UI visual overhaul, a customizable theme engine, and significant stability enhancements:
* **Custom UI & Theme Engine**:
    - Replaced generic `AceGUI` windows with a premium custom Native UI framework.
    - Added pre-packaged themes including `Fel`, `Classic`, `Midnight`, and `Minimalist`.
    - Centralized all window sizing and layouts configuration under `UI/Layouts.lua`.
* **Recipe-Specific Voting**:
    - Introduced specialized buttons for recipe items (Item Class 9): *"Ready to Craft"* (immediate learning) and *"Unskilled"* (profession but insufficient skill).
* **Link Insertion & EditBox Improvements**:
    - Enabled Shift-Clicking item links from bags/chat directly into custom EditBox inputs (e.g. in the Item Manager).
* **Layout Reset & Self-Healing**:
    - Added the `/dlc reset` and `/dlc resetpositions` commands to clear and reset all coordinates in real-time.
    - Implemented layout self-healing to automatically discard narrow/corrupted window dimensions saved during collapsed states.
* **Automation & Stability**:
    - Automatically refreshes the Pending Trades and History windows on item award/re-award.
    - Gated roster scanning/alt alerts to actual raid groups of 10+ players.
    - Hardened Loot Master tracking against group leader changes.
    - Unified semantic versioning logic and resolved localization gaps in English and German.

---

## Beta Releases (v0.8.5-Beta - v0.9.5-Beta)

Major features and stability improvements introduced during the Beta phase:
* **Modular Architecture**: Separated the background automatic passing systems from the front-end interface to improve latency and stability.
* **Alt and Roster Management**: Added automatic registration of mains, alt-character linking, and intelligent raid disband alert suppression.
* **Encounter Tools**: Integrated a custom boss sequence widget (for Lu'Ra encounter) allowing coordination of raid markers.
* **Network & Database Safety**: Improved packet routing, hardened database check validation, and added trade safeguards to prevent accidental item equipping.
* **Localization Foundation**: Structured UI systems to support multi-language localizations.