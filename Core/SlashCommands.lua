local _, AT = ...
if AT.abortLoad then return end

---@class SlashCommands
local SlashCommands = {}
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function SlashCommands.Handle(input)
    if not input or input:trim() == "" then
        DesolateLootcouncil:OpenConfig()
        return
    end

    local args = { strsplit(" ", input:trim()) }
    local cmd = string.lower(args[1] or "")

    -- 1. General & Raider Commands
    if cmd == "config" or cmd == "options" or cmd == "opt" or cmd == "settings" then
        DesolateLootcouncil:OpenConfig()

    elseif cmd == "priority" or cmd == "prio" or cmd == "prios" or cmd == "lists" then
        DesolateLootcouncil:OpenConfig("priority")

    elseif cmd == "roster" or cmd == "mains" or cmd == "alts" then
        if not args[2] or args[2] == "" then
            DesolateLootcouncil:OpenConfig("roster")
        else
            local Roster = DesolateLootcouncil:GetModule("Roster", true)
            if Roster and Roster.HandleSlashCommand then
                Roster:HandleSlashCommand(table.concat(args, " ", 2))
            end
        end

    elseif cmd == "vote" or cmd == "show" or cmd == "bids" then
        local SessionInfo = DesolateLootcouncil:GetModule("Session", true)
        local isLM = DesolateLootcouncil:AmILootMaster()
        local items = (isLM and DesolateLootcouncil.db.profile.session.bidding) or (SessionInfo and SessionInfo.clientLootList)
        if items and #items > 0 then
            local UI = DesolateLootcouncil:GetModule("UI", true)
            if UI and UI.ShowVotingWindow then UI:ShowVotingWindow(items) end
        else
            DesolateLootcouncil:Print(L["No active voting session to show."])
        end

    elseif cmd == "im" or cmd == "manager" or cmd == "items" then
        local UI = DesolateLootcouncil:GetModule("UI_ItemManager", true)
        if UI and UI.ShowItemManagerWindow then UI:ShowItemManagerWindow() end

    elseif cmd == "version" or cmd == "ver" then
        local UI = DesolateLootcouncil:GetModule("UI", true)
        if UI and UI.ShowVersionWindow then UI:ShowVersionWindow() end

    -- 2. Officer & Loot Master Core Hubs
    elseif cmd == "monitor" or cmd == "master" then
        if DesolateLootcouncil:AmIOfficerOrLM() then
            local UI = DesolateLootcouncil:GetModule("UI", true)
            if UI and UI.ShowMonitorWindow then UI:ShowMonitorWindow() end
        else
            DesolateLootcouncil:Print(L["Only the Loot Master or Officers can view the Monitor."])
        end

    elseif cmd == "loot" or cmd == "drops" then
        if DesolateLootcouncil:AmILootMaster() then
            local UI = DesolateLootcouncil:GetModule("UI", true)
            if UI and UI.ShowLootWindow then
                UI:ShowLootWindow(DesolateLootcouncil.db.profile.session.loot)
            end
        else
            DesolateLootcouncil:Print(L["Only the Loot Master can view the Loot Window."])
        end

    elseif cmd == "trade" or cmd == "tradelist" then
        if DesolateLootcouncil:AmILootMaster() then
            local UI = DesolateLootcouncil:GetModule("UI", true)
            if UI and UI.ShowTradeListWindow then UI:ShowTradeListWindow() end
        else
            DesolateLootcouncil:Print(L["Only the Loot Master can view the Trade List."])
        end

    elseif cmd == "unassigned" or cmd == "review" then
        if DesolateLootcouncil:AmIOfficerOrLM() then
            local UI = DesolateLootcouncil:GetModule("UI_UnassignedPlayers", true)
            if UI and UI.ShowUnassignedWindow then UI:ShowUnassignedWindow() end
        else
            DesolateLootcouncil:Print(L["Only the Loot Master or Officers can view the Loot History."])
        end

    elseif cmd == "history" or cmd == "raids" then
        if DesolateLootcouncil:AmIOfficerOrLM() then
            local UI = DesolateLootcouncil:GetModule("UI", true)
            if UI and UI.ShowHistoryWindow then UI:ShowHistoryWindow() end
        else
            DesolateLootcouncil:Print(L["Only the Loot Master or Officers can view the Loot History."])
        end

    elseif cmd == "audit" or cmd == "log" or cmd == "ledger" or cmd == "auditlog" then
        if DesolateLootcouncil:AmIOfficerOrLM() then
            local LogUI = DesolateLootcouncil:GetModule("UI_PriorityLogHistory", true)
            if LogUI and LogUI.ShowLogWindow then
                local sID = args[2]
                LogUI:ShowLogWindow(sID)
            end
        else
            DesolateLootcouncil:Print(L["Only the Loot Master or Officers can view the Audit Ledger."])
        end

    elseif cmd == "attendance" or cmd == "att" then
        if DesolateLootcouncil:AmIOfficerOrLM() then
            local Attendance = DesolateLootcouncil:GetModule("UI_Attendance", true)
            if Attendance and Attendance.ShowAttendanceWindow then
                Attendance:ShowAttendanceWindow()
            end
        else
            DesolateLootcouncil:Print(L["Only the Loot Master or Officers can view the Loot History."])
        end

    -- 3. Session & Decay Actions
    elseif cmd == "start" then
        if DesolateLootcouncil:AmILootMaster() then
            DesolateLootcouncil.API:StartRaidSession()
        else
            DesolateLootcouncil:Print(L["Only the Loot Master can start a raid session."])
        end

    elseif cmd == "stop" or cmd == "end" then
        if DesolateLootcouncil:AmILootMaster() then
            DesolateLootcouncil.API:StopRaidSession(true)
        else
            DesolateLootcouncil:Print(L["Only the Loot Master can stop a raid session."])
        end

    elseif cmd == "session" then
        local sub = args[2] and string.lower(args[2])
        if sub == "start" then
            if DesolateLootcouncil:AmILootMaster() then
                DesolateLootcouncil.API:StartRaidSession()
            else
                DesolateLootcouncil:Print(L["Only the Loot Master can start a raid session."])
            end
        elseif sub == "stop" or sub == "end" then
            if DesolateLootcouncil:AmILootMaster() then
                DesolateLootcouncil.API:StopRaidSession(true)
            else
                DesolateLootcouncil:Print(L["Only the Loot Master can stop a raid session."])
            end
        else
            local Roster = DesolateLootcouncil:GetModule("Roster", true)
            if Roster and Roster.HandleSlashCommand then
                Roster:HandleSlashCommand(table.concat(args, " ", 2))
            end
        end

    elseif cmd == "decay" or cmd == "applydecay" then
        if DesolateLootcouncil:AmIOfficerOrLM() then
            local Attendance = DesolateLootcouncil:GetModule("UI_Attendance", true)
            if Attendance and Attendance.ShowAttendanceWindow then
                Attendance:ShowAttendanceWindow()
            end
        else
            DesolateLootcouncil:Print(L["Only the Loot Master or Officers can modify priority lists."])
        end

    elseif cmd == "add" then
        if DesolateLootcouncil:AmILootMaster() then
            local arg = args[2]
            if arg then
                local Loot = DesolateLootcouncil:GetModule("Loot", true)
                if Loot and Loot.AddManualItem then Loot:AddManualItem(arg) end
            else
                DesolateLootcouncil:Print("Usage: /dlc add [ItemLink]")
            end
        else
            DesolateLootcouncil:Print(L["Only the Loot Master can add items to the session."])
        end

    -- 4. Testing, Diagnostics & Simulation
    elseif cmd == "test" then
        local sub = args[2] and string.lower(args[2])
        if sub == "auto" or sub == "quick" then
            if DesolateLootcouncil:AmILootMaster() then
                local Loot = DesolateLootcouncil:GetModule("Loot", true)
                if Loot and Loot.AddTestItems then Loot:AddTestItems() end
            else
                DesolateLootcouncil:Print(L["Only the Loot Master can allow test items."])
            end
        else
            local Sim = DesolateLootcouncil:GetModule("Simulation", true)
            if Sim and Sim.StartInteractiveLootTest then
                Sim:StartInteractiveLootTest()
            end
        end

    elseif cmd == "sim" or cmd == "simulate" then
        local Sim = DesolateLootcouncil:GetModule("Simulation", true)
        if Sim and Sim.HandleSlashCommand then
            Sim:HandleSlashCommand(table.concat(args, " ", 2))
        end

    elseif cmd == "testsuite" or cmd == "suite" or cmd == "dev" then
        local UI = DesolateLootcouncil:GetModule("UI_TestSuite", true)
        if UI and UI.ShowTestSuiteWindow then
            UI:ShowTestSuiteWindow()
        else
            DesolateLootcouncil:Print("TestSuite module not available.")
        end

    elseif cmd == "testunassigned" or cmd == "mockunassigned" then
        local profile = DesolateLootcouncil.db.profile
        if profile then
            profile.unassignedPlayers = profile.unassignedPlayers or {}
            profile.unassignedPlayers["Dustknight"] = { firstSeen = time(), source = "Raid", class = "WARRIOR" }
            profile.unassignedPlayers["Frostmage"] = { firstSeen = time() + 1, source = "Bid", class = "MAGE" }
            profile.unassignedPlayers["Holyheals"] = { firstSeen = time() + 2, source = "Version", class = "PRIEST" }
            profile.unassignedPlayers["Shadowstep"] = { firstSeen = time() + 3, source = "Raid", class = "ROGUE" }
            DesolateLootcouncil:Print("Injected 4 mock unassigned players (Dustknight, Frostmage, Holyheals, Shadowstep).")
            local UI = DesolateLootcouncil:GetModule("UI_UnassignedPlayers", true)
            if UI and UI.ShowUnassignedWindow then UI:ShowUnassignedWindow() end
        end

    elseif cmd == "status" or cmd == "verbose" or cmd == "dump" then
        local Debug = DesolateLootcouncil:GetModule("Debug", true)
        if Debug then
            if cmd == "status" and Debug.ShowStatus then
                Debug:ShowStatus()
            elseif cmd == "verbose" and Debug.ToggleVerbose then
                Debug:ToggleVerbose()
            elseif cmd == "dump" and Debug.DumpKeys then
                Debug:DumpKeys()
            end
        end

    elseif cmd == "reset" or cmd == "resetpositions" then
        if DesolateLootcouncil.Persistence and DesolateLootcouncil.Persistence.ResetPositions then
            DesolateLootcouncil.Persistence:ResetPositions()
        end

    -- 5. Help Menu
    else
        DesolateLootcouncil:Print("|cffffd700Desolate Loot Council Commands:|r")
        DesolateLootcouncil:Print("  |cff33ff99/dlc [config|opt]|r - Open Main Settings")
        DesolateLootcouncil:Print("  |cff33ff99/dlc [priority|prio]|r - Open Priority Lists & Rankings")
        DesolateLootcouncil:Print("  |cff33ff99/dlc roster|r - Open Raider Roster Management")
        DesolateLootcouncil:Print("  |cff33ff99/dlc vote|r - Re-open Loot Voting & Choice Window")
        DesolateLootcouncil:Print("  |cff33ff99/dlc im|r - Open Item Manager Catalogs")
        DesolateLootcouncil:Print("  |cff33ff99/dlc ver|r - Version & Addon Checker")
        DesolateLootcouncil:Print("  |cff33ff99/dlc reset|r - Reset all window positions to screen center")
        DesolateLootcouncil:Print("|cffffd700Officer & Loot Master Hubs:|r")
        DesolateLootcouncil:Print("  |cff33ff99/dlc monitor|r - Open Master Council Voting Monitor")
        DesolateLootcouncil:Print("  |cff33ff99/dlc loot|r - Open Loot Drop Staging Window")
        DesolateLootcouncil:Print("  |cff33ff99/dlc trade|r - Open Auto-Trade Staging List")
        DesolateLootcouncil:Print("  |cff33ff99/dlc unassigned|r - Review & Assign Unassigned Raiders")
        DesolateLootcouncil:Print("  |cff33ff99/dlc history|r - Open Raid Attendance & Award History")
        DesolateLootcouncil:Print("  |cff33ff99/dlc audit|r - Open Unified Priority Audit Ledger")
        DesolateLootcouncil:Print("  |cff33ff99/dlc att|r - Open Session Attendance & Decay Review")
        DesolateLootcouncil:Print("  |cff33ff99/dlc decay|r - Apply position decay for last raid session")
        DesolateLootcouncil:Print("  |cff33ff99/dlc [start|stop]|r - Start or End Raid Session")
        DesolateLootcouncil:Print("|cffffd700Testing & Tools:|r")
        DesolateLootcouncil:Print("  |cff33ff99/dlc test|r - Start Interactive Live Test Simulation")
        DesolateLootcouncil:Print("  |cff33ff99/dlc testsuite|r - Open Automated TestSuite Window")
    end
end

DesolateLootcouncil.SlashCommands = SlashCommands
