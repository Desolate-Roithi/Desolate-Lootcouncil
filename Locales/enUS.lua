local L = LibStub("AceLocale-3.0"):NewLocale("DesolateLootcouncil", "enUS", true)
if not L then return end

-- Global
L["Close"] = true
L["Loading..."] = true
L["Desolate Loot Council Settings"] = true

-- Attendance.lua
L["Are you sure you want to delete this attendance record? This cannot be undone."] = true
L["Yes"] = true
L["No"] = true
L["No active session to review."] = true
L["Session Attendance & Decay Review"] = true
L["Session Attendance Review (Decay Disabled)"] = true
L["Review attendance before ending session. Click names to move them between lists."] = true
L["Attended (Safe)"] = true
L["Absent (Apply Decay)"] = true
L["Absent (Reference Only)"] = true
L["Decay Amount"] = true
L["End Session (Save History)"] = true
L["APPLY DECAY & END"] = true
L["Applied +%d Position Decay to all lists for absent players."] = true
L["Decay Amount is 0. No priorities changed."] = true
L["Deleted attendance history entry."] = true
L["Settings"] = true
L["Enable Priority Decay"] = true
L["If enabled, absent players will suffer priority decay."] = true
L["Default Penalty"] = true
L["Amount of priority lost per missed raid."] = true
L["Session Control"] = true
L["Session Active"] = true
L["Session Inactive"] = true
L["End Session"] = true
L["Start Session"] = true
L["Open the Attendance Review window to process decay and end the session."] = true
L["Start a new raid session."] = true
L["Raid History"] = true
L["Select Session"] = true
L["View details of current or past raid sessions."] = true
L["Delete Entry"] = true
L["Permanently delete the selected history record."] = true
L["Select a session to view details."] = true
L["Error: History entry not found or empty."] = true
L["No attendees recorded."] = true
L["Attendees (%d):"] = true
L["Open Full History"] = true
L["Open the combined raid history window for the selected session."] = true
L["Attendance & Decay"] = true

-- History.lua
L["Session History"] = true
L["Session Loot History"] = true
L["Select Date"] = true
L["Delete Date"] = true
L["Re-award"] = true
L["No entries for this date."] = true
L["Removed %d entries for %s"] = true
L["No loot awarded in this session."] = true

-- RaidHistory.lua
L["Raid History"] = true
L["Loot Awarded"] = true
L["Players Attended"] = true
L["Position Changes"] = true
L["Decay Applied"] = true
L["No position changes recorded."] = true
L["Position log not available (pre-dates session tracking)."] = true
L["... and %d more entries"] = true
L["Position log only available for current session."] = true
L["Decay disabled."] = true
L["No decay applied yet."] = true
L["Decay of %d positions was applied when session ended."] = true

-- Monitor.lua
L["Loot Monitor"] = true
L["Unassign"] = true
L["Push Item"] = true
L["Assigning %s..."] = true
L["Still Pending Response:"] = true
L["Roll Details for "] = true
L["Confirm Award"] = true
L["Cancel"] = true
L["Award"] = true
L["View Rolls"] = true
L["Session Monitor"] = true
L["Pending Trades"] = true
L["Stop Session"] = true
L["Loot Backlog"] = true
L["History"] = true
L["Session History"] = true
L["Attendance"] = true
L["Version Check"] = true
L["Unranked"] = true
L["Give"] = true
L["Lvl %d"] = true
L["Award Item"] = true
L["No active votes."] = true
L["Disenchanters"] = true
L["OS"] = true
L["TM"] = true
L["Bid"] = true
L["Roll"] = true
L["Pass"] = true

-- Voting.lua
L["Loot Vote"] = true
L["You voted: |cffaaaaaaAuto Pass|r"] = true
L["Closed"] = true
L["Syncing..."] = true
L["Change"] = true
L["Bid"] = true
L["Roll"] = true
L["Offspec"] = true
L["T-Mog"] = true
L["Pass"] = true
L["You voted: %s%s|r"] = true
L["Voted: %s%s|r"] = true
L["You voted: |cffaaaaaaAuto Pass|r"] = true
L["Award Log"] = true
L["Loot Log"] = true
L["ToDebugString"] = true
L["Toggle Disenchanters Sidebar"] = true
L["You voted: %s%s|r%s"] = true
L["Add Private Note"] = true
L["Add note to Loot Master..."] = true
L["Voter Note"] = true
L["min"] = true
L["sec"] = true
L["|cffff8000Vote closing in %s \226\128\148 still need your vote:|r %s"] = true
L["You have outstanding loot votes! Type /dlc vote to reopen."] = true

-- ItemManager.lua
L["Item Manager"] = true
L["Item Name/Link/ID"] = true
L["Target List"] = true
L["Add"] = true
L["Sync Raid"] = true
L["Item Manager lists synced to raid."] = true
L["Remove"] = true
L["Assigned Items"] = true
L["Select List to View"] = true
L["Removed item ID: %s"] = true
L["No assigned items."] = true


-- TradeList.lua
L["Trade"] = true
L["%s is out of trade range."] = true
L["Could not auto-target %s. Please target them manually and click Trade again."] = true
L["Marked %s as traded."] = true
L["No pending trades."] = true


-- Version.lua
L["Desolate Loot Council - Versions"] = true
L["Highest Found Version: %s"] = true
L["Not Installed / Missing"] = true
L["%s (Current)"] = true
L["%s (Outdated)"] = true
L["Refresh / Ping"] = true
L["Wait %.0fs"] = true
L["Pinging..."] = true

-- PriorityOverride.lua
L["Override: %s"] = true
L["Manual Override: Moved %s from %d to %d in %s."] = true

-- PriorityLogHistory.lua
L["Priority Log History"] = true
L["No history logs found."] = true

-- Loot.lua (Systems)
L["Addon Connection: [%d] / [%d]"] = true
L["Refresh (%.0fs)"] = true
L["Refresh Connections"] = true
L["Systems/Loot Loaded"] = true
L["Wiped stale loot backlog from previous session."] = true
L["Added Item %d to '%s'"] = true
L["Item unassigned from all priority lists."] = true
L["Skipped low quality item: %s"] = true
L["--- LOOT SCAN START (%d slots) ---"] = true
L["--- SCAN END ---"] = true
L["AUTO-ADDED from self-loot: %s"] = true
L["AUTO-ADDED from roll: %s"] = true
L["Loot backlog cleared (dedup store preserved)."] = true
L["Manually added: %s"] = true
L["Winner of %s is %s! (%s)"] = true
L["You have been awarded %s! Trade me."] = true
L["Restored %d votes for re-awarded item."] = true
L["Re-awarded item: %s"] = true
L["Item reverted to bidding session."] = true
L["Added test items to session."] = true
L["Triggered disenchanter scan via version check."] = true

-- Trade.lua (Systems)
L["Systems/Trade Loaded"] = true
L["Bypassed Blizzard trade confirmation: %s"] = true
L["Staged %s for %s."] = true
L["Could not find %s in bags for %s."] = true
L["Trade complete. %s marked as delivered to %s."] = true

-- Popups
L["Do you want to enable Autopass for this raid session?\n(Raid members will automatically pass on managed loot)"] = true
L["Enable"] = true
L["A previous Loot Session is still active. Do you want to close it?"] = true
L["Yes (Close Session)"] = true
L["No (Keep Active)"] = true
L["Are you sure you want to perform this action?"] = true
L["Resume Session"] = true
L["Resuming active raid session."] = true

-- New Keys
L["All window positions have been reset."] = true
L["Warning: No Loot Master configured. Use /dlc config to set one."] = true
L["Role Update: You are Loot Master."] = true
L["Role Update: You are Raider."] = true
L["Loot Master"] = true
L["Raider"] = true
L["Role Update: You are %s (LM: %s)"] = true
L["Added item: %s"] = true
L["Added new Priority List: %s (Initialized with shuffled roster)"] = true
L["Removed Priority List: %s"] = true
L["Renamed list to: %s"] = true
L["Only the Loot Master or Raid Assists can view the Loot History."] = true
L["Only the Loot Master can add items to the session."] = true
L["Open the configuration window to manage settings, priority lists, and rosters."] = true
L["Open Settings Window"] = true

L["Bosses & Pulls"] = true
L["No boss logs recorded for this session."] = true

L["Ready to Craft"] = true
L["Unskilled"] = true
L["Ready"] = true
L["Roll to receive this recipe because you have the profession and required skill to craft it."] = true
L["Roll for this recipe even though you do not meet the skill or profession requirements yet."] = true
L["Pass on this recipe."] = true
L["Bid priority points on this item."] = true
L["Roll for main spec usage."] = true
L["Roll for offspec usage."] = true
L["Roll for transmogrification collection."] = true
L["Pass on this item."] = true
L["Trade window full. Remaining items will be staged in the next trade."] = true

-- Handover & Decay popups
L["No Loot Master has been detected in the group for 60+ seconds. Do you want to claim the Loot Master role?"] = true
L["Yes (Claim LM)"] = true
L["%s is handing you the Loot Master role. Accept?"] = true
L["Accept"] = true
L["Decline"] = true
L["The last raid session (%s, %s) has pending decay. Apply decay now before starting a new session?"] = true
L["Apply Decay"] = true
L["Skip"] = true
L["Review First"] = true
L["Claim LM Role"] = true
L["No Loot Master is detected in the raid. Claim the role to enable session management."] = true
L["Hand Over LM Role"] = true
L["Start the handover process to the selected officer."] = true
L["Choose an officer in the raid to hand over the Loot Master role to."] = true
L["Select Officer for Handover"] = true
L["Loot Master handover received. Do you want to continue the running loot session, or clear it and start a new one?"] = true
L["Continue Session"] = true
L["Start New Session"] = true

-- EJ Loot Import
L["DLC"] = true
L["Add to IM"] = true
L["DLC Loot Import"] = true
L["%d items staged across %d lists"] = true
L["— Skip —"] = true
L["No loot found for this boss."] = true
L["Officer only."] = true

-- Reworked Handover & Offline Scenarios
L["%s is handing you the Loot Master role. Do you want to continue the running raid session, or start a new one?"] = true
L["%s is handing you the Loot Master role. Do you want to continue the running raid session, start a new one, or decline the handover?"] = true
L["%s is offering you the Loot Master role. Accept or decline?"] = true
L["The active Loot Master is %s. Handover of active sessions should ideally be initiated by the active LM. Force handover anyway?"] = true
L["Declined Loot Master handover from %s."] = true
L["Loot Master %s has left the group. Leadership falls back to %s."] = true
L["Raid Leader %s has left the group. %s is now the group leader and Loot Master."] = true
L["Yes (Force)"] = true
L["Decline Handover"] = true
L["Accept LM"] = true

-- Pre-commit Code Review Additions
L["Cannot hand over: %s is no longer in the group or online."] = true
L["Cannot hand over during an active vote. Award or remove all items first."] = true
L["Import to Current Profile"] = true
L["Import data directly into the active profile."] = true
L["Are you sure you want to import directly into your CURRENT active profile? This cannot be undone."] = true
L["Raid leadership received. Started new Loot Master session."] = true
L["Accepted Loot Master handover from %s (restored session)."] = true
L["Accepted Loot Master handover from %s (started new session)."] = true

-- Missing Keys (Post Code-Review D1 patch)
L["An active raid session was found.\nWould you like to resume this session or end it?"] = true
L["An active raid session was found (inactive for %.1f hours).\nWould you like to resume this session or end it?"] = true
L["Handover to %s timed out."] = true
L["Only the Loot Master or Officers can view the Loot History."] = true
L["Raid leadership received. Loot Master session restored."] = true
L["Add all loot from this boss/raid to the import staging area."] = true
