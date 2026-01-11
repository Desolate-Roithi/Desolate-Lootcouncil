---@class SlashCommands
local SlashCommands = {}
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")

function SlashCommands.Handle(input)
    if not input or input:trim() == "" then
        DesolateLootcouncil:OpenConfig()
        return
    end

    local args = { strsplit(" ", input) }
    local cmd = string.lower(args[1])

    -- Configuration
    if cmd == "config" or cmd == "options" then
        DesolateLootcouncil:OpenConfig()

        -- Reset
    elseif cmd == "reset" then
        if DesolateLootcouncil.db and DesolateLootcouncil.db.ResetDB then
            DesolateLootcouncil.db:ResetDB()
            DesolateLootcouncil:Print("Configuration reset.")
        else
            DesolateLootcouncil:Print("Error: Database reset not available.")
        end

        -- Version
    elseif cmd == "version" then
        local UI = DesolateLootcouncil:GetModule("UI")
        if UI and UI.ShowVersionWindow then UI:ShowVersionWindow() end

        -- Voting Window (Re-open)
    elseif cmd == "show" or cmd == "vote" then
        local session = DesolateLootcouncil.db.profile.session
        if session and session.bidding and #session.bidding > 0 then
            local UI = DesolateLootcouncil:GetModule("UI")
            if UI and UI.ShowVotingWindow then UI:ShowVotingWindow(session.bidding) end
        else
            DesolateLootcouncil:Print("No active voting session to show.")
        end

        -- Test Items (LM Only)
    elseif cmd == "test" then
        if DesolateLootcouncil:AmILootMaster() then
            local Loot = DesolateLootcouncil:GetModule("Loot")
            if Loot and Loot.AddTestItems then Loot:AddTestItems() end
        else
            DesolateLootcouncil:Print("Only the Loot Master can allow test items.")
        end

        -- Loot Window (LM Only)
    elseif cmd == "loot" then
        if DesolateLootcouncil:AmILootMaster() then
            local UI = DesolateLootcouncil:GetModule("UI")
            if UI and UI.ShowLootWindow then
                UI:ShowLootWindow(DesolateLootcouncil.db.profile.session.loot)
            end
        else
            DesolateLootcouncil:Print("Only the Loot Master can view the Loot Window.")
        end

        -- Monitor (LM Only)
    elseif cmd == "monitor" or cmd == "master" then
        if DesolateLootcouncil:AmILootMaster() then
            local UI = DesolateLootcouncil:GetModule("UI")
            if UI and UI.ShowMonitorWindow then UI:ShowMonitorWindow() end
        else
            DesolateLootcouncil:Print("Only the Loot Master can view the Monitor.")
        end

        -- History
    elseif cmd == "history" then
        local UI = DesolateLootcouncil:GetModule("UI")
        if UI and UI.ShowHistoryWindow then UI:ShowHistoryWindow() end

        -- Trade List (LM Only)
    elseif cmd == "trade" then
        if DesolateLootcouncil:AmILootMaster() then
            local UI = DesolateLootcouncil:GetModule("UI")
            if UI and UI.ShowTradeListWindow then UI:ShowTradeListWindow() end
        end

        -- Debug / Status
    elseif cmd == "status" or cmd == "verbose" or cmd == "dump" then
        local Debug = DesolateLootcouncil:GetModule("Debug")
        if Debug then
            if cmd == "status" and Debug.ShowStatus then
                Debug:ShowStatus()
            elseif cmd == "verbose" and Debug.ToggleVerbose then
                Debug:ToggleVerbose()
            elseif cmd == "dump" and Debug.DumpKeys then
                Debug:DumpKeys()
            end
        end

        -- Manual Add
    elseif cmd == "add" then
        local arg = args[2]
        if arg then
            local Loot = DesolateLootcouncil:GetModule("Loot")
            if Loot and Loot.AddManualItem then Loot:AddManualItem(arg) end
        else
            DesolateLootcouncil:Print("Usage: /dlc add [ItemLink]")
        end

        -- Session Management
    elseif cmd == "session" then
        local Roster = DesolateLootcouncil:GetModule("Roster")
        if Roster and Roster.HandleSlashCommand then
            Roster:HandleSlashCommand(table.concat(args, " ", 2))
        end

        -- Simulation
    elseif cmd == "sim" then
        local Sim = DesolateLootcouncil:GetModule("Simulation")
        if Sim then Sim:HandleSlashCommand(table.concat(args, " ", 2)) end
    else
        DesolateLootcouncil:Print("Unknown command.")
        DesolateLootcouncil:Print("Available Commands:")
        DesolateLootcouncil:Print("  |cff33ff99/dlc config|r - Open configuration")
        DesolateLootcouncil:Print("  |cff33ff99/dlc show|r - Re-open Voting Window")
        DesolateLootcouncil:Print("  |cff33ff99/dlc history|r - Open Loot History")
        DesolateLootcouncil:Print("  |cff33ff99/dlc version|r - Check versions")
        DesolateLootcouncil:Print("  |cff33ff99/dlc status|r - Show debug status")
        DesolateLootcouncil:Print("Loot Master (LM) Only:")
        DesolateLootcouncil:Print("  |cff33ff99/dlc monitor|r - Open Master Monitor")
        DesolateLootcouncil:Print("  |cff33ff99/dlc loot|r - Open Loot Drop Window")
        DesolateLootcouncil:Print("  |cff33ff99/dlc trade|r - Open Trade List")
        DesolateLootcouncil:Print("  |cff33ff99/dlc session|r - Manage Sessions (start/stop)")
        DesolateLootcouncil:Print("  |cff33ff99/dlc test|r - Generate Test Items")
    end
end

DesolateLootcouncil.SlashCommands = SlashCommands
