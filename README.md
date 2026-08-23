# Desolate Lootcouncil

An automated Master Loot helper for World of Warcraft Retail. Desolate Lootcouncil coordinates bidding, priority lists, and item distribution alongside the default Group Loot system.

**Latest Version:** v1.2.2  
**Last Updated:** 2026-08-23  
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