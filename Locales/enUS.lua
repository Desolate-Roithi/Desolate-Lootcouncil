local L = LibStub("AceLocale-3.0"):NewLocale("DesolateLootcouncil", "enUS", true, true)
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
L["... and %d older entries"] = true
L["Copy All Position Changes"] = true
L["Position Changes Log"] = true
L["Press Ctrl+C to copy all position changes for this session."] = true
L["Position log only available for current session."] = true
L["Decay disabled."] = true
L["No decay applied yet."] = true
L["Decay of %d positions was applied when session ended."] = true
L["Export Event"] = true
L["Export Raid Event"] = true
L["Press Ctrl+C to copy the export string below. You can import this into any profile via Settings > Profiles > Import to Current Profile."] = true

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
L["Item #%d (Loading...)"] = true


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
L["Audit & Priority Ledger"] = true
L["View Session Audit Trail"] = true
L["No history logs found."] = true
L["No audit log entries recorded."] = true
L["Only the Loot Master or Officers can view the Audit Ledger."] = true

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
L["Item reverted to monitor window."] = true
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
L["An active raid session from %s was found.\nWould you like to save and close the previous session and start a new one for today?"] = true
L["Save & Start New"] = true
L["Keep Previous"] = true
L["Keeping previous session active."] = true
L["The raid group has disbanded. Would you like to end and save the current raid session?"] = true
L["End & Save Session"] = true
L["Keep Active"] = true
L["Review & Apply Decay"] = true
L["APPLY DECAY"] = true
L["Decay has already been applied for the last session."] = true
L["No active raid session or pending attendance history to review."] = true
L["Review attendees and absences for this saved raid session. Click names to move between lists, then click Apply Decay."] = true

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
L["Autopass is disabled because not everyone in the raid has the addon."] = true
L["Autopass is disabled because the following members do not have the addon: %s"] = true
L["Sync Autopass"] = true
L["Not Prompted"] = true
L["Enabled"] = true
L["Disabled"] = true
L["Autopass state synced to raid group."] = true
L["Highest Found Version: %s  |  Autopass: %s"] = true
L["[Decay] %s moved from position #%d to #%d in %s list (+%d decay for absence)."] = true
L["Revote"] = true

-- Priority Lists & Categories
L["Tier"] = true
L["Weapons"] = true
L["Rest"] = true
L["Collectables"] = true
L["Trinkets and Cantrips"] = true
L["Recipes"] = true
L["Junk/Pass"] = true

-- Unassigned Players Review
L["Unassigned"] = true
L["Unassigned Players Review"] = true
L["Add All as Mains"] = true
L["Dismiss All"] = true
L["Link Alt"] = true
L["Add Main"] = true
L["Please select a Main character first."] = true
L["No unassigned players found.\nAll detected players are properly mapped."] = true
L["Notice: %d player(s) in Main roster are missing from priority lists (%s). Click 'Sync Missing Players' in Priority settings to append them."] = true
L["Decay of %d applied to players: %s"] = true
L["Decay of %d positions was applied when session ended (no absent players)."] = true
L["Sync to Lists"] = true
L["View Only - Loot Master controls assignment"] = true
L["Select Main..."] = true
L["Auto-switched profile to '%s' (matched Loot Master raid roster)."] = true
L["Add as Main"] = true
L["Link to Main"] = true
L["Added new Priority List: %s"] = true
L["Alt"] = true
L["Characters in attendance:"] = true
L["Systems/Attendance Loaded"] = true
L["Systems/ItemCatalog Loaded"] = true

-- Audit Ledger Viewer
L["All Events"] = true
L["Loot Awards"] = true
L["Decay Penalties"] = true
L["Manual Shifts"] = true
L["Roster Changes"] = true
L["Copy Audit Ledger"] = true
L["Filter:"] = true
L["Search:"] = true
L["Audit ledger copied to clipboard."] = true

-- Settings (General, Priority, Profile, Roster)
L["Appearance & Themes"] = true
L["Automation & Loot Rules"] = true
L["Enable Automated Rolling / Passing"] = true
L["Enable Automated Trade Staging"] = true
L["Enable Debug Mode"] = true
L["Loot History"] = true
L["Loot Master & Handover"] = true
L["Minimum Loot Quality"] = true
L["Name of the designated Loot Master (PlayerName)."] = true
L["Open the Audit & Priority Ledger showing historical priority shifts, loot awards, and decay penalties."] = true
L["Open the Loot History window showing all awarded items."] = true
L["Opens the 'Enable Autopass' popup again to change the global setting for this session."] = true
L["Privately whisper Priority Lists and Roster to all current raid officers. Regular members cannot read this data."] = true
L["Re-open Autopass Choice"] = true
L["Reset Window Layout"] = true
L["Reset the positions of all addon windows to their default center status."] = true
L["Select the color scheme and visual styling for all addon windows."] = true
L["Share Priority & Roster with Officers"] = true
L["Show verbose diagnostic and debug messages in chat."] = true
L["Threshold for auto-looting and detecting items."] = true
L["Tools & Quick Actions"] = true

-- Priority Settings
L["Append any unranked roster members to the bottom of all priority lists."] = true
L["Choose a priority list to rename or remove."] = true
L["Configuration"] = true
L["Create List"] = true
L["Create New List"] = true
L["Create the priority list and initialize it for all roster members."] = true
L["Delete List"] = true
L["Enter name for the new priority category."] = true
L["Enter the new title for this priority list."] = true
L["Error parsing list index."] = true
L["Hide Ranking"] = true
L["Manage Existing Lists"] = true
L["Manage seasonal Priority Lists. Use the 'Sync' button to add new roster members without re-shuffling."] = true
L["Management & Views"] = true
L["Manual Override (Drag & Drop)"] = true
L["New List Name"] = true
L["No players found in this list."] = true
L["Open the Audit & Priority Ledger history window."] = true
L["Open the interactive visual drag & drop override window for this priority list."] = true
L["Permanently delete this priority list."] = true
L["Priority Category Overviews"] = true
L["Randomize player order across all priority lists and clear historic session logs."] = true
L["Rename (Confirm)"] = true
L["Rename List"] = true
L["Save the new name for this priority list."] = true
L["Season Management & Actions"] = true
L["Select List to Edit"] = true
L["Show Ranking"] = true
L["Shuffle / Start Season"] = true
L["Sync Missing Players"] = true
L["Toggle the inline ranking table for this priority list."] = true
L["UI Module 'PriorityOverride' not available."] = true
L["View History Log"] = true

-- Profile Settings
L["Copy"] = true
L["Copy From Profile"] = true
L["Create / Reset"] = true
L["Create a new profile with this name (or reset if it exists)."] = true
L["Current Profile"] = true
L["Data Domains to Export"] = true
L["Delete Profile"] = true
L["Delete the current profile (cannot delete Default)."] = true
L["Encode and package the selected domains into a shareable export string."] = true
L["Enter name to create a new profile or reset an existing one."] = true
L["Entire Profile (Export Everything)"] = true
L["Export String"] = true
L["Export specific settings to share with others or move between profiles.\n"] = true
L["Exports a complete backup of all profile modules."] = true
L["Exports empty list definitions/templates without raider rankings."] = true
L["Exports item assignments and managed priority lists."] = true
L["Exports list definitions and active player order."] = true
L["General Config & Decay Rules"] = true
L["Generate Export String"] = true
L["Import / Export"] = true
L["Import Profile Payload"] = true
L["Import data into a newly created profile."] = true
L["Import to New Profile"] = true
L["Imports always create a new profile for safety."] = true
L["Item Manager (Catalogs)"] = true
L["New Profile Name"] = true
L["New Profile Name (Import)"] = true
L["Overwrite current profile with data from selected profile."] = true
L["Paste Import String"] = true
L["Paste a base64 export string generated from Desolate Loot Council."] = true
L["Priority Lists (Empty Structure)"] = true
L["Priority Lists (with Player Rankings)"] = true
L["Profile Management"] = true
L["Raid Attendance & Award History"] = true
L["Roster (Mains & Alts)"] = true
L["Select a profile to copy data FROM (overwrites current!)."] = true
L["Select an existing profile to switch to."] = true

-- Roster Settings
L["A character cannot be linked as an alt of itself."] = true
L["Add / Save"] = true
L["Add Player (Name-Realm)"] = true
L["Add Raider to Roster"] = true
L["Apply cascading rename for this member."] = true
L["Check if this player is an alt."] = true
L["Choose a Main character to convert and link this character under as an Alt without retyping."] = true
L["Convert this character into an alt under the selected Main."] = true
L["Council Officer"] = true
L["Current Roster & Linked Alts"] = true
L["Enter new name to cascade across roster, priority lists, and history logs."] = true
L["Enter player name. Defaults to current realm if omitted."] = true
L["Grant council officer permissions to this player."] = true
L["Is Alt?"] = true
L["Is Officer?"] = true
L["Link as Alt"] = true
L["Linked '%s' as an alt of '%s'."] = true
L["Manage Selected Player"] = true
L["No Roster Found."] = true
L["Open the Unassigned Players Review window to assign detected raid members as Mains or Alts."] = true
L["Permanently remove this member from the roster and priority lists."] = true
L["Please select a Main character."] = true
L["Please select both a player and a target Main character."] = true
L["Promote this Alt character to an independent Main roster member."] = true
L["Promote to Main"] = true
L["Promoted '%s' to Main character."] = true
L["Remove Member"] = true
L["Rename Player"] = true
L["Rename to (Name-Realm)"] = true
L["Review Unassigned Players (0)"] = true
L["Review Unassigned Players (|cffffd700%d Pending|r)"] = true
L["Roster is currently empty. Add members above."] = true
L["Save this character to the raid roster."] = true
L["Select Member to Manage"] = true
L["Select any Main or Alt from the roster to edit role, link as alt, rename, or remove."] = true
L["Select the Main character for this Alt."] = true
L["Set as Alt of Main"] = true
L["Toggle council officer status and permissions for this player."] = true
L["Unassigned Players Queue"] = true

-- Attendance Review & Window
L["Amount of priority positions lost per missed raid session."] = true
L["Default Penalty (Ranks)"] = true
L["Enable Priority Decay for Absences"] = true
L["End Session & Review"] = true
L["If enabled, unexcused absent players will suffer rank decay on priority lists at the end of the raid session."] = true
L["Live Raid Session Control"] = true
L["Priority Decay Rules"] = true
L["Select Saved Session"] = true

-- Interactive Simulation Controller (/dlc test)
L["Active Live Simulation: Test voting, priority overrides, and loot master awards."] = true
L["Auto-Award Next"] = true
L["Awarded %s to %s."] = true
L["Complete & Verify"] = true
L["Injected %d simulated raider votes."] = true
L["Interactive Test Controller"] = true
L["Monitor UI"] = true
L["No remaining items in bidding queue."] = true
L["Simulate Votes"] = true
L["Voting UI"] = true
L["Interactive Test Session cancelled."] = true
L["Interactive Test Session completed. Total awards: %d."] = true

-- Priority Log History & Audit Ledger
L["All Sessions"] = true
L["Catalog Changes"] = true
L["Current Session"] = true
L["Press Ctrl+C to copy the audit ledger export below."] = true
L["Priority Shifts"] = true
L["Raid Sessions"] = true
L["No active items to vote on."] = true

-- Additional Permission and General Keys
L["Active Theme"] = true
L["Audit Ledger"] = true
L["Automatically roll on items above threshold (LM) or pass (Raiders)."] = true
L["Automatically stage awarded items in the trade window when trading the winner."] = true
L["Decay for last session skipped."] = true
L["No active voting session to show."] = true
L["No attendance history found."] = true
L["Only the Loot Master can allow test items."] = true
L["Only the Loot Master can start a raid session."] = true
L["Only the Loot Master can stop a raid session."] = true
L["Only the Loot Master can view the Loot Window."] = true
L["Only the Loot Master can view the Trade List."] = true
L["Only the Loot Master or Officers can modify priority lists."] = true
L["Only the Loot Master or Officers can view the Monitor."] = true

