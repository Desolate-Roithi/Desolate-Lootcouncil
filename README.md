# Desolate Lootcouncil

An automated Master Loot helper for World of Warcraft Retail. Desolate Lootcouncil coordinates bidding, priority lists, and item distribution alongside the default Group Loot system.

**Latest Version:** v1.2.4  
**Last Updated:** 2026-08-29  
**Compatibility:** WoW 12.1.0 (Midnight)  

## Features

### For Loot Masters
* **Automation:** Automatically detects the Loot Master and manages disenchanting assignments.
* **Alt Linking & Unassigned Queue:** Tracks alts and mains, with a dedicated review staging queue for unknown characters.
* **Session Control:** Monitor active bids in real time and revert mistaken item awards easily.
* **Modular Profile Export/Import:** Granular sharing of rosters, empty list structures, rankings, item catalogs, and history.
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
| `/dlc unassigned` | Review and map unknown characters detected during raid sessions. |
| `/dlc reset` | Reset all window layout sizes and positions to defaults. |
| `/dlc sim` | Developer tool to test simulated scenarios and players. |

## Installation
1. Download the latest release.
2. Extract the folder into your `Interface/AddOns/` directory.
3. Restart or reload World of Warcraft.

---

## Recent Changes

### v1.2.4 (2026-08-29)
* **Dynamic Item & Class Icon Resolution**:
  * Raid History now dynamically resolves all item icons on-demand via Blizzard's native APIs (`C_Item.GetItemInfo` / `C_Item.GetItemIconByID`) with `Item:CreateFromItemID` async load hooks matching Item Manager.
  * Resolved character class colors dynamically for attendees using Main Roster and alt mappings.
* **Robust Profile Import & Serialization**:
  * Enhanced `DecodePayload` to strip enclosing whitespace and markdown backticks from imported strings.
  * Ensured complete Main Roster class attributes and uncorrupted boss kill rosters across profile exports.
  * Instant config dialog refresh via `AceConfigRegistry-3.0` notification upon profile import.

### v1.2.3 (2026-08-24)
* **LibDeflate Stream Compression (`!DLC1:`)**:
  * Integrated `LibDeflate` into the core library stack and `.pkgmeta` externals.
  * Exports (Single Events, Full Profiles, Item Manager, History) are now stream-compressed, cutting export string lengths by **~75%–85%**.
  * Fully backward-compatible: The importer automatically recognizes `!DLC1:` compressed strings, legacy Base64, and raw string formats.
* **Lossless Export & History Compaction**:
  * Item Manager lists serialize as compact numeric arrays.
  * Stripped duplicate `fullItemData` tables from history records while preserving complete item details, winner attributes, and vote logs.
  * Retroactive decay compaction migrates redundant decay strings into structured attendance fields, dramatically reducing SavedVariables file sizes.
* **Single Raid History Event Export & Merge Import**:
  * Added **Export Event** button to the Raid History window to share individual raid sessions without exporting your entire database.
  * Importing single events merges cleanly into the active profile without overwriting existing history.
* **Decay Filtering & Multi-Language Parsing**:
  * Position Changes section in Raid History filters out decay messages so only manual position changes are displayed.
  * Dynamic decay pattern matcher automatically derives localized formats across all registered `AceLocale-3.0` translations.
* **UI & Workflow Improvements**:
  * Opening the Item Manager from the Settings window no longer automatically closes the Settings window.

### v1.2.2 (2026-08-23)
* **Unassigned Players Staging & Review Queue**:
  * Added dedicated review window (`/dlc unassigned`) and notification badges in Version check and Roster settings for unknown characters.
  * Easy one-click actions: **Add as Main**, **Link to Main** (with Main dropdown), **Add All as Mains**, and **Dismiss**.
* **Modular Profile Export & Import**:
  * Added granular export categories: Entire Profile, Roster (Mains/Alts), Priority Lists (with Player Rankings), Priority Lists (Empty Structure without Players), Item Manager Catalogs, Raid Attendance & History, and Config/Decay.
  * Added non-destructive merging (importing priority lists preserves item catalogs and vice versa).
  * Added native enabled/disabled states and mutual exclusivity to settings checkboxes.
* **UI Polish & Layout Adjustments**:
  * Fixed footer button overlapping in Version check window with dynamic width distribution.
  * Added window position persistence for the Unassigned Players Review window.

### v1.2.1 (2026-08-22)
* **Pre-Populated Item Manager Starter Catalog**: Included 114+ raid items categorized across 6 default priority lists (**Tier**, **Weapons**, **Rest**, **Collectables**, **Trinkets and Cantrips**, **Recipes**) with full localization so new users start with organized categories right away.
* **Automatic Season/Tier Catalog Migration**: Added expansion-aware season tier tracking (`CATALOG_TIER = "midnight-s2"`) to seamlessly refresh the item catalog across upcoming raid seasons.
* **Single Source of Truth**: Centralized starter catalog constants in `Core/Constants.lua` to streamline future season releases.

### v1.2.0 (2026-08-22)
* **Autopass & Relog Stability**:
  * Fixed startup/relog `nil` table crash in `DoAllGroupMembersHaveAddon` by initializing communication caches on load.
  * Prevented non-LM group invites and reloads from clobbering the Loot Master's active Autopass configurations.
  * Replaced Blizzard `CheckInteractDistance` calls with taint-safe range verification to eliminate combat errors.
* **Trade System & Cross-Realm Staging**:
  * Fixed cross-realm name normalization in trade staging to reliably match players across connected realms.
  * Ensured awarded items are immediately marked as traded upon trade completion and cleared from Pending Trades.
  * Enhanced bag item filtering to correctly differentiate BoP tradeable raid drops from untradeable Warbound copies.
* **Item Revote & Voting Window Reopening**:
  * Added **Revote** button to the Award window header for Loot Masters to restart voting when necessary.
  * Cleared stale local/session votes and activeState on item reopen.
  * Handled `DLC_ITEM_REOPENED` in Voting and Monitor windows to un-collapse frames, clear previous selections, and restart full countdown timers.
* **Session Window Lifecycle & Cascading Cleanup**:
  * Closing the central Session Monitor window (via 'X' button, Escape, or Stop Session) now cascades to close all child session windows (Pending Trades, Award Log, Attendance, Loot Backlog, Version Check, Disenchanter sidebar).
  * Expanded `UI:CloseAllWindows()` to support all frame property variants.
* **100% UI-API Compliance**:
  * Refactored all UI components to query and trigger actions exclusively through `DesolateLootcouncil.API` (`Core/API.lua`), fully decoupling the frontend presentation layer from backend systems.
* **Roster Management & History**:
  * Added `SanitizeMainsAndAlts` to prevent alts and previous season characters from polluting the Main Roster.
  * Added point decay event logging to session history to ensure all roster point decays are tracked.
  * Clarified re-award message to *"Item reverted to monitor window"* in English and German.

---

## Previous Releases (v1.0.0 - v1.1.2)

Key features and improvements introduced in earlier releases:
* **Custom Native UI & Theme Engine**: Replaced generic frames with a custom Native UI framework featuring pre-packaged themes (`Fel`, `Classic`, `Midnight`, `Minimalist`) and layout self-healing.
* **Account-wide Profile Persistence & LM Swapping**: Enabled seamless Loot Master character swaps mid-raid without losing session data, with full profile persistence.
* **Item Manager Profile Integration**: Added priority list management directly in AceDB profiles with base64 import/export and live syncing.
* **Recipe-Specific Voting & Disenchanting**: Integrated specialized recipe voting buttons (*"Ready to Craft"*, *"Unskilled"*) and collapsible disenchanter docking.
* **WoW 12.1.0 (Midnight) Compatibility**: Added `issecretvalue()` and `pcall` protections across leader and unit inspection APIs.