# Desolate Lootcouncil

A Master Loot helper and priority list addon for World of Warcraft Retail. Desolate Lootcouncil lets raid teams run priority-based loot distribution alongside Blizzard's default Group Loot system, with automated roll passing, trade queues, and attendance tracking.

**Latest Version:** v2.2.5  
**Last Updated:** 2026-09-17  
**Compatibility:** WoW 12.1.0 (Midnight)  

## What It Does

### For Loot Masters & Officers
* **Loot Distribution:** Pick up boss drops, start voting sessions, and award items to raiders based on priority rankings, rolls, or offspec/transmog choices.
* **Priority Lists & Decay:** Manage multiple priority lists (Tier, Weapons, Trinkets, etc.) with automatic attendance-based rank decay after each raid.
* **Roster & Alt Management:** Link alts to mains so raiders keep their standing across characters. Unrecognized characters are caught in a staging queue for quick review.
* **Auto-Trading:** Automatically stages won items when trading raiders, verifies exact stats and tertiary rolls (Leech, Speed, Sockets), and clears completed trades.
* **Audit Trail & History:** Every bid, vote, award, and trade is logged in a searchable in-game audit ledger.
* **Profile Sharing:** Export and import rosters, priority lists, item catalogs, or full profiles using compressed strings.

### For Raiders
* **One-Click Voting:** Clean buttons for Main Spec (Priority), Free Roll, Offspec, Transmog, or Pass.
* **Smart Autopass:** Automatically rolls or passes on drops based on your priority lists and addon settings.
* **Trade Queue:** Whispers award winners and tracks pending trades if players are out of range or dead.
* **In-Game Visibility:** Check your current priority standing, session history, and raid attendance anytime.

## Slash Commands

All commands start with `/dlc`:

### Raider Commands
| Command | Description |
| :--- | :--- |
| `/dlc` or `/dlc config` | Open the main configuration panel. |
| `/dlc vote` | Re-open the voting window during an active loot session. |
| `/dlc ver` | Open the raid version check window to see who has the addon installed. |
| `/dlc reset` | Reset all window positions back to the center of the screen. |

### Officer & Loot Master Commands
| Command | Description |
| :--- | :--- |
| `/dlc monitor` | Open the council voting monitor to review bids, votes, and awards. |
| `/dlc loot` | Open the loot staging window to manage newly dropped items. |
| `/dlc trade` | Open the pending trades window. |
| `/dlc prio` | Open the Priority Lists and player ranking settings. |
| `/dlc roster` | Open Roster management (Mains and Alts). |
| `/dlc unassigned` | Open the review queue for newly detected or unassigned raiders. |
| `/dlc history` | Open past raid sessions and loot history. |
| `/dlc audit` | Open the full priority and trade audit ledger. |
| `/dlc att` | Open attendance tracking and session decay review. |
| `/dlc start` | Start a new raid session (Loot Master only). |
| `/dlc stop` | Conclude the active raid session (Loot Master only). |
| `/dlc decay [apply\|skip]` | Apply or skip position decay for the last concluded raid session. |
| `/dlc add [ItemLink]` | Manually add an item to the current loot session. |

### Diagnostics & Testing
| Command | Description |
| :--- | :--- |
| `/dlc test [lm\|officer\|raider]` | Start an interactive test session with mock drops and role switching. |
| `/dlc testsuite` | Open the in-game automated test suite window. |
| `/dlc status` | Print current connection, session, and autopass status to chat. |
| `/dlc sim` | Access developer simulation tools. |

## Installation
1. Download the latest release.
2. Extract the folder into your `Interface/AddOns/` directory.
3. Restart or reload World of Warcraft.

---

## Recent Changes

### v2.2.5 (2026-09-17)
* **Autotrading & Trade List Fixes**:
  * Fixed won items failing to auto-stage in trade when trading winners (both single drops and duplicate tokens).
  * Fixed completed trades getting stuck in the Pending Trades window due to client-side slot clearing.
  * Preserved Bonus IDs so raiders who win items with tertiary stats (Leech, Speed, Sockets) always receive the exact item, and plain winners are never given a tertiary copy.
  * Cleaned up player name resolution: backend systems now strictly use canonical `Name-Realm` to prevent cross-realm mismatches.
  * Improved the "Trade" button in the Pending Trades window to reliably target cross-realm raiders.
  * Added instant officer sync when manually removing an item from the pending trades list.

### v2.2.4 (2026-09-12)
* **Performance & Stability**:
  * Optimized loot chat parsing and roster decay processing on large raid rosters.
  * Cleaned up item link serialization and fixed duplicate method declarations.
  * Added automated integration tests for large multi-session scale testing.

### v2.2.3 (2026-09-12)
* **Trade & Group Safety**:
  * Added tradeability checks (`IsItemTradeableBoP`) to prevent staging locked or warbound items.
  * Hardened group checks to prevent comm bursts and heartbeat spam from offline members.
  * Fixed role swapping issues in the interactive simulation bar.

### v2.2.1 (2026-09-07)
* **Minimap & Addon Status**:
  * Added LibDataBroker (LDB) launcher support for minimap button addons (MBB, ButtonBag).
  * Fixed offline member tracking to prevent taint issues on Blizzard raid frames.

### v2.2.0 (2026-09-07)
* **New Features & Drop Handling**:
  * Added native minimap button with 360-degree orbital positioning.
  * Fixed multi-drop isolation so awarding one token does not remove remaining copies of the same item.
  * Improved raid history timestamps and added interactive test scenarios.

---

## Previous Releases

### v2.0.0 – v2.1.3 Highlights
* **Audit Ledger & History**: Full audit trail (`[DISCARD]`, `[SESSION]`, `[ROSTER]`, `[CATALOG]`, `[TRADE]`, `[AWARD]`) with virtual scrolling and session filters.
* **Item Manager**: Real-time category assignments, "Junk/Pass" filters, dynamic item icons, and starter raid catalogs.
* **Session Boundaries**: Prevented accidental sessions in delves, 5-mans, or LFR, and fixed disband popup loops.
* **Unassigned Queue**: Added dedicated `/dlc unassigned` window to easily assign new raiders as Mains or Alts.
* **Midnight Compatibility**: Protected against secret value errors and FrameXML taint.

### v1.0.0 – v1.2.7 Highlights
* **Native UI**: Custom theme engine (`Fel`, `Classic`, `Midnight`, `Minimalist`) with layout self-healing.
* **Profile Sharing**: Stream-compressed string exports (`!DLC1:`) for fast sharing of lists and rosters.
* **Loot Master Handovers**: Seamless mid-raid LM swapping without session data loss.
* **Recipe Voting**: Added dedicated voting buttons for recipes and profession items.