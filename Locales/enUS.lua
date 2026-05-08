local L = LibStub("AceLocale-3.0"):NewLocale("DesolateLootcouncil", "enUS", true)
if not L then return end

-- Global
L["Close"] = true
L["Loading..."] = true

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
L["Attendance & Decay"] = true

-- History.lua
L["Session History"] = true
L["Select Date"] = true
L["Delete Date"] = true
L["Re-award"] = true
L["No entries for this date."] = true
L["Removed %d entries for %s"] = true

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
L["Systems/Loot Loaded"] = true
L["Wiped stale loot backlog from previous session."] = true
L["Added Item %d to '%s'"] = true
L["Item unassigned from all priority lists."] = true
L["Skipped low quality item: %s"] = true
L["--- LOOT SCAN START (%d slots) ---"] = true
L["--- SCAN END ---"] = true
L["AUTO-ADDED from self-loot: %s"] = true
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


