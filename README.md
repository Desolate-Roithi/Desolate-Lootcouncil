# Desolate Lootcouncil

**Desolate Lootcouncil** is a World of Warcraft (Retail) addon designed to reintroduce a streamlined, fair, and automated "Master Loot" system. [cite_start]It layers a robust addon-controlled distribution system on top of WoW's default "Group Loot," centralizing control under a designated Loot Master to reduce confusion and automate the bidding process[cite: 3, 4, 5].

📄 **[View Full Design Document](https://docs.google.com/document/d/1YSH8LIx4ka85DvqN9HsUKGpMZtdZnULBxX_Y53BeQN0/edit?usp=sharing)**

## 🚀 Key Features

### ✅ Currently Implemented
* **Robust Loot Master (LM) Detection:**
    * [cite_start]Smart hierarchy: *Configured Name* > *Presence Check* > *Fallback to Group Leader*[cite: 26, 30, 38].
    * [cite_start]Prevents "ghost" assignments if the designated LM is offline or not in the group[cite: 31, 33].
* **Unified UI Module (Refactored):**
    * Clean code separation for `Loot`, `Voting`, `Monitor`, and `Utility` windows.
* **Loot Management (LM Only):**
    * [cite_start]**Loot Drop Window:** Review dropped items, categorize them (Tier, Weapons, Collectables), and start bidding sessions[cite: 74, 91, 111].
    * [cite_start]**Session Monitor:** Live tracking of items currently up for vote[cite: 310].
    * [cite_start]**Distribution:** Supports **Bid**, **Roll**, **Transmog**, and **Pass** voting options[cite: 235, 236, 237, 238].
* **Voting System:**
    * **Multi-Timer Support:** Overlapping sessions run simultaneously with individual item countdowns.
    * **Live Feedback:** UI updates in real-time as votes come in.
* **Post-Distribution Tools:**
    * [cite_start]**Smart Trade Tracker:** Remembers who won what and helps initiate trades[cite: 266, 269].
    * **Session History:** A persistent log of awarded items for the current session.
* **Developer Tools:**
    * Debug mode (`/dlc verbose`), simulated loot sessions, and connection status checks.

### 🚧 Planned / In Progress
* **Advanced Roster Management:**
    * [cite_start]Main/Alt character mapping[cite: 115, 126].
    * [cite_start]Priority Decay system for raid absences[cite: 130, 161].
    * [cite_start]Manual priority sorting for "Bid" winners[cite: 121, 250].
* **Automated Native Interaction:**
    * [cite_start]Auto-Need/Greed for the LM on the native WoW loot frame[cite: 58].
    * [cite_start]Auto-Pass for standard raiders to declutter their screen[cite: 56].
* **Session Persistence:**
    * [cite_start]Robust handling of disconnects/reloads during active bidding[cite: 278].
    * [cite_start]Logic to detect "Session End" via zoning or logout[cite: 180, 194].

## 🛠️ Installation

1.  Download the latest release.
2.  Extract the `Desolate_Lootcouncil` folder into your WoW Addons directory:
    `_retail_/Interface/AddOns/`
3.  Launch World of Warcraft.

## 💻 Usage & Commands

The addon uses **`/dlc`** as its primary command.

| Command | Description |
| :--- | :--- |
| `/dlc config` | Open the configuration settings. |
| `/dlc history` | **(Public)** Open the Session History window to see awarded loot. |
| `/dlc status` | **(Public)** Show debug status (Current LM, version check). |
| `/dlc loot` | **(LM Only)** Open the Loot Drop window (Inbox for new items). |
| `/dlc monitor` | **(LM Only)** Open the Master Looter interface (Live voting & awards). |
| `/dlc trade` | **(LM Only)** Open the Pending Trades window. |
| `/dlc test` | **(LM Only)** Generate test items to simulate a loot drop. |
