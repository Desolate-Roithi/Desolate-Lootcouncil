# Desolate Lootcouncil

**Desolate Lootcouncil** is a World of Warcraft (Retail) addon designed to reintroduce a streamlined, fair, and automated "Master Loot" system. It layers a robust addon-controlled distribution system on top of WoW's default "Group Loot," centralizing control under a designated Loot Master to reduce confusion and automate the bidding process.

Current Version: **0.2.0-Beta**

📄 **[View Full Design Document](https://docs.google.com/document/d/1YSH8LIx4ka85DvqN9HsUKGpMZtdZnULBxX_Y53BeQN0/edit?usp=sharing)**

## 🚀 Key Features

### ✅ Currently Implemented

**Core Systems**
* **Robust Loot Master (LM) Detection:** Smart hierarchy (*Configured Name* > *Presence Check* > *Fallback to Group Leader*) prevents "ghost" assignments if the designated LM is offline.
* **Smart Alt-Linking:** The addon automatically recognizes Alts and links them to their Main Character. All priority checks and penalties are applied to the Main, ensuring fairness across an account.
* **Smart Priority Reversion:** Includes an intelligent "Undo" system. [cite_start]If an item is re-awarded (e.g., to correct a mistake), the previous winner is automatically restored to their original position in the priority list [cite: 655-660].

**Loot Management (LM Only)**
* [cite_start]**Loot Drop Window:** Review dropped items, auto-categorize them (Tier, Weapons, Collectables), and start bidding sessions [cite: 410-412].
* [cite_start]**Session Monitor:** A unified dashboard to watch live votes come in [cite: 678-680].
* **Disenchanter Dashboard:** Automatically scans the raid for players with the Enchanting profession. [cite_start]Allows the LM to instantly award trash loot to disenchanters without affecting their loot priority [cite: 610-617].
* **Intelligent Awarding:**
    * **Bids:** Sorted by **Priority Rank** (1 is highest). [cite_start]Alts display their Main's rank automatically [cite: 590-597].
    * **Rolls/Transmog:** Sorted by **Server-Side Roll** (1-100). [cite_start]The LM generates the roll to prevent client-side cheating [cite: 598-603].
    * [cite_start]**Penalty System:** Awarding a "Bid" item automatically moves the winner (or their Main) to the bottom of the Priority List[cite: 596].

**Voting & Distribution**
* [cite_start]**Flexible Voting:** Supports **Bid** (Priority), **Roll** (Random), **Transmog** (Random), and **Pass** [cite: 577-582].
* **Multi-Timer Support:** Handle multiple items simultaneously with individual countdowns.
* **Trade Automation:**
    * [cite_start]**Whisper Integration:** Automatically informs winners to trade [cite: 621-623].
    * [cite_start]**Pending Queue:** Tracks items owed to winners who are out of range or offline [cite: 625-627].
    * [cite_start]**Auto-Cleanup:** Successfully trading an item automatically removes it from the addon's loot session list [cite: 628-631].

**Configuration & Tools**
* **Priority Lists:** Fully customizable lists for Tier, Weapons, etc.
* **Session History:** A persistent log of every awarded item and priority change.
* [cite_start]**Developer Tools:** Debug mode toggle (`/dlc config`), solo simulation mode for testing UI without a group [cite: 687-688], and database dumps.

**Attendance & Decay**
* **Priority Decay System:** Automated loss of priority for players who miss raids. Configurable penalty amounts and manual review before applying.
* **Attendance Tracking:** Robust session management with roster snapshots. Includes a dedicated UI for reviewing attendance and deleting history records.
* **Session Persistence:** Full rehydration of active betting sessions and votes after a disconnect or UI reload.

**Simulation & Testing**
* **Active Simulation Module:** Power-user tools for testing. Use `/dlc sim` to add/remove virtual players and auto-generate complex voting scenarios.
* **Dual Identity Re-awards:** Intelligent handling of Alts during "Undo" operations. Restores the Main's priority position while preserving the Alt's name in the UI history.

## 🛠️ Installation

1.  Download the latest release.
2.  Extract the `Desolate_Lootcouncil` folder into your WoW Addons directory:
    `_retail_/Interface/AddOns/`
3.  Launch World of Warcraft.

## 💻 Usage & Commands

The addon uses **`/dlc`** as its primary command.

| Command | Description |
| :--- | :--- |
| `/dlc config` | Open the configuration settings (Roster, Priority Lists, Debug Mode). |
| `/dlc show` | Re-open the Voting Window if accidentally closed. |
| `/dlc monitor` | **(LM)** Open the Master Monitor (Live voting & awards). |
| `/dlc loot` | **(LM)** Open the Loot Drop window (Inbox for new items). |
| `/dlc trade` | **(LM)** Open the Pending Trades window. |
| `/dlc history` | **(Public)** Open the Session History log. |
| `/dlc status` | **(Public)** Show debug status (Current LM, version check). |
| `/dlc test` | **(LM)** Generate test items to simulate a loot drop: |
| `/dlc session` | **(LM)** Manage Raid Sessions (start, stop, kill, attend). |
| `/dlc sim` | **(Dev)** Manage Simulated Players (add, remove, vote, list, clear). |

---

### 📝 Changelog

**v0.2.0-Beta**
* **Feature:** Implemented **Attendance Tracking** with history review UI.
* **Feature:** Added **Priority Decay** system for raid absences.
* **Feature:** New **Simulation Module** for advanced testing (`/dlc sim`).
* **Feature:** Added **Session Persistence** for reloads/disconnects.
* **Fix:** Improved Alt detection in `AwardItem` using persistent roster lookup.
* **Fix:** Handled "Dual Identity" in `ReawardItem` to properly restore Main's position.
* **Refactor:** Unified all raid membership checks to support simulated players.

**v0.1.0-Beta**
* **Feature:** Added Smart Priority Reversion (Undo functionality).
* **Feature:** Added Disenchanter Dashboard with profession scanning.
* **Feature:** Implemented Auto-Cleanup on successful trade.
* **Feature:** Added Solo Simulation Mode for testing.
* **Feature:** Added `/dlc show` to recover closed windows.
* **Enhancement:** Debug Mode toggle to silence chat spam.
* **Enhancement:** Improved Main/Alt linking in voting logic.