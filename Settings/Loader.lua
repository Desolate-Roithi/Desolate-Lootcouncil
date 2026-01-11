---@class SettingsLoader
local SettingsLoader = {}

function SettingsLoader.GetOptions()
    local options = {
        type = "group",
        name = "Desolate Loot Council",
        handler = DesolateLootcouncil,
        args = {}
    }

    ---@type GeneralSettings
    local General = DesolateLootcouncil:GetModule("GeneralSettings", true)
    if General and General.GetGeneralOptions then
        options.args.general = General:GetGeneralOptions()
    end

    ---@type ItemSettings
    local Items = DesolateLootcouncil:GetModule("ItemSettings", true)
    if Items and Items.GetItemOptions then
        options.args.items = Items:GetItemOptions()
    end

    ---@type RosterSettings
    local RosterSettings = DesolateLootcouncil:GetModule("RosterSettings", true)
    if RosterSettings and RosterSettings.GetOptions then
        options.args.roster = RosterSettings:GetOptions()
    end

    ---@type PrioritySettings
    local Priority = DesolateLootcouncil:GetModule("PrioritySettings", true)
    if Priority and Priority.GetOptions then
        options.args.priority = Priority:GetOptions()
    end

    ---@type LootSettings
    local LootRules = DesolateLootcouncil:GetModule("LootSettings", true)
    if LootRules and LootRules.GetOptions then
        options.args.lootRules = LootRules:GetOptions()
    end

    -- UI Module injects its own Attendance options
    ---@type UI_Attendance
    local Attendance = DesolateLootcouncil:GetModule("UI_Attendance", true)
    if Attendance and Attendance.GetAttendanceOptions then
        options.args.attendance = Attendance:GetAttendanceOptions()
    end

    return options
end

DesolateLootcouncil.SettingsLoader = SettingsLoader
return SettingsLoader
