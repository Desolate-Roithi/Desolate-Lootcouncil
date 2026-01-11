---@class SlashCommands
local SlashCommands = {}

function SlashCommands.Handle(input)
    if not input or input:trim() == "" then
        DesolateLootcouncil:OpenConfig()
    elseif input == "reset" then
        DesolateLootcouncil.db:ResetDB()
        DesolateLootcouncil:Print("Configuration reset.")
    elseif input == "config" then
        DesolateLootcouncil:OpenConfig()
    elseif input == "version" then
        ---@type UI
        local UI = DesolateLootcouncil:GetModule("UI")
        if UI then UI:ShowVersionWindow() end
    else
        DesolateLootcouncil:Print("Unknown command. Usage: /dlc [config|reset|version]")
    end
end

DesolateLootcouncil.SlashCommands = SlashCommands
