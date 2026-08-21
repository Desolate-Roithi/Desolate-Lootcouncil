# Desolate Lootcouncil

An automated Master Loot helper for World of Warcraft Retail. Desolate Lootcouncil coordinates bidding, priority lists, and item distribution alongside the default Group Loot system.

**Latest Version:** v1.2.0  
**Last Updated:** 2026-08-22  
**Compatibility:** WoW 12.1.0 (Midnight)  

## Release v1.2.0 (2026-08-22)

* **Autopass & Relog Stability**:
  * Fixed startup/relog nil table crash in `DoAllGroupMembersHaveAddon` by initializing Comm caches on addon initialize.
  * Prevented non-LM group invites and reloads from clobbering the Loot Master's active Autopass configurations.
  * Replaced Blizzard `CheckInteractDistance` calls with taint-safe range verification to prevent `ADDON_ACTION_BLOCKED` combat errors.
* **Trade System & Cross-Realm Staging**:
  * Fixed cross-realm name normalization in trade staging to reliably match players across different connected realms.
  * Ensured awarded items are immediately marked as traded upon trade completion and cleared from Pending Trades.
  * Enhanced bag item filtering to correctly differentiate BoP tradeable raid drops from untradeable Warbound copies.
* **Item Revote & Voting Window Reopening**:
  * Added **Revote** button to the Award window header for Loot Masters to restart voting when necessary.
  * Cleared stale local/session votes and activeState on item reopen.
  * Handled `DLC_ITEM_REOPENED` in Voting and Monitor windows to un-collapse frames, clear previous selections, and restart full countdown timers.
* **Session Window Lifecycle & Cascading Cleanup**:
  * Closing the central Session Monitor window (via 'X' button, Escape, or Stop Session) now cascades to close all child session windows (Pending Trades, Award Log, Attendance, Loot Backlog, Version Check, Disenchanter sidebar).
  * Expanded `UI:CloseAllWindows()` to support all frame property variants (`sessionFrame`, `tradeListFrame`, `deFrame`, etc.).
* **100% UI-API Compliance**:
  * Refactored all UI components to query and trigger actions exclusively through `DesolateLootcouncil.API` (`Core/API.lua`), fully decoupling the frontend presentation layer from backend systems.
* **Roster Management & History**:
  * Added `SanitizeMainsAndAlts` to prevent alts and previous season characters from polluting the Main Roster.
  * Added point decay event logging to session history to ensure all roster point decays are tracked.
  * Clarified re-award message to *"Item reverted to monitor window"* in English and German.

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

### v1.0.1
Maintenance and bugfix release focused on account-wide profile persistence, Loot Master character swapping, copyable log history, and visual refinements:
* **Account-wide Profile & LM Swaps**:
    - Enabled seamless Loot Master character swaps (e.g. Druid -> Mage -> Priest) during active raid sessions without canceling the session.
    - Implemented a profile switching check on login: automatically prompts the Loot Master to continue or stop the active session.
    - Active raid session data and profiles are correctly preserved in the global DB.
* **Item Manager Profile Integration**:
    - Moved Item Manager priority lists directly into the AceDB profile layout to survive profile changes, copies, and resets.
    - Normalized imported base64 profile data to prevent duplicate item entries.
    - Fixed list sync loop spam (every 30s) by converting list item IDs from string representations to numeric values inside the comparison check.
* **Priority Log History Selection**:
    - Replaced the non-interactive font string label pool with a selectable, copyable multi-line editbox in the Priority Log History window.
    - Bypassed main name resolution during roster removals to log the exact alt character name (e.g., `Roithitest`) in sync logs.
* **Themed & Collapsible Disenchanters Dock**:
    - Colored the "Disenchanters" section header in the Award window to match the active theme's colors (`theme.textHeader`).
    - Added a collapsible/expandable arrow indicator next to the label (points right when collapsed, down when expanded) that responds to double-clicks.
* **Localization & Stability**:
    - Added missing localization strings for `"Resume Session"` and `"Resuming active raid session."` in both English and German locales.
    - Resolved linter warnings and issues, resulting in a fully passing test suite (32/32 tests) and a clean static analysis (0 warnings/errors).

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