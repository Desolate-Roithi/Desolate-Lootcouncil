# Desolate Lootcouncil

**Desolate Lootcouncil** is a World of Warcraft (Retail) addon designed to reintroduce a streamlined, fair, and automated "Master Loot" system. It layers a robust addon-controlled distribution system on top of WoW's default "Group Loot," centralizing control under a designated Loot Master to reduce confusion and automate the bidding process.

📄 **[View Full Design Document](https://docs.google.com/document/d/1YSH8LIx4ka85DvqN9HsUKGpMZtdZnULBxX_Y53BeQN0/edit?usp=sharing)**

## 🚀 Key Features

### ✅ Currently Implemented

**Core Systems**
* **Robust Loot Master (LM) Detection:** Smart hierarchy (*Configured Name* > *Presence Check* > *Fallback to Group Leader*) prevents "ghost" assignments if the designated LM is offline.
* **Smart Alt-Linking:** The addon automatically recognizes Alts and links them to their Main Character. All priority checks and penalties are applied to the Main, ensuring fairness across an account.

**Loot Management (LM Only)**
* **Loot Drop Window:** Review dropped items, auto-categorize them (Tier, Weapons, Collectables), and start bidding sessions.
* **Session Monitor:** A unified dashboard to watch live votes come in.
* **Intelligent Awarding:**
    * **Bids:** Sorted by **Priority Rank** (1 is highest). Alts display their Main's rank automatically.
    * **Rolls/Transmog:** Sorted by **Server-Side Roll** (1-100). The LM generates the roll to prevent client-side cheating.
    * **Penalty System:** Awarding a "Bid" item automatically moves the winner (or their Main) to the bottom of the Priority List.

**Voting & Distribution**
* **Flexible Voting:** Supports **Bid** (Priority), **Roll** (Random), **Transmog** (Random), and **Pass**.
* **Multi-Timer Support:** Handle multiple items simultaneously with individual countdowns.
* **Smart Trade Tracker:** The addon remembers who won what. When you open a trade window with a winner, it automatically stages the correct item.

**Configuration & Tools**
* **Priority Lists:** fully customizable Drag-and-Drop lists for Tier, Weapons, etc.
* **Session History:** A persistent log of every awarded item and priority change.
* **Developer Tools:** Debug mode, simulated voting sessions, and database dumps for troubleshooting.

### 🚧 Planned / In Progress
* **Priority Decay:** Automated decay system for raid absences.
* **Automated Native Interaction:**
    * Auto-Need/Greed for the LM on the native WoW loot frame.
    * Auto-Pass for standard raiders.
* **Session Persistence:** Robust handling of disconnects/reloads during active bidding.

## 🛠️ Installation

1.  Download the latest release.
2.  Extract the `Desolate_Lootcouncil` folder into your WoW Addons directory:
    `_retail_/Interface/AddOns/`
3.  Launch World of Warcraft.

## 💻 Usage & Commands

The addon uses **`/dlc`** as its primary command.

| Command | Description |
| :--- | :--- |
| `/dlc config` | Open the configuration settings (Roster, Priority Lists). |
| `/dlc monitor` | **(LM)** Open the Master Monitor (Live voting & awards). |
| `/dlc loot` | **(LM)** Open the Loot Drop window (Inbox for new items). |
| `/dlc trade` | **(LM)** Open the Pending Trades window. |
| `/dlc history` | **(Public)** Open the Session History log. |
| `/dlc status` | **(Public)** Show debug status (Current LM, version check). |
| `/dlc test` | **(LM)** Generate test items to simulate a loot drop. |
| `/dlc dump` | **(Debug)** Print raw database keys for roster troubleshooting. |