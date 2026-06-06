local _, AT = ...
if AT.abortLoad then return end

---@class UI_SettingsLoader
local SettingsLoader = {}

function SettingsLoader.GetOptions()
    local options = {
        type = "group",
        name = "Desolate Loot Council",
        args = {}
    }

    ---@type UI_GeneralSettings
    local General = DesolateLootcouncil:GetModule("UI_GeneralSettings", true)
    if General and General.GetGeneralOptions then
        options.args.general = General:GetGeneralOptions()
    end

    ---@type UI_ItemSettings
    local Items = DesolateLootcouncil:GetModule("UI_ItemSettings", true)
    if Items and Items.GetItemOptions then
        options.args.items = Items:GetItemOptions()
    end

    ---@type UI_RosterSettings
    local RosterSettings = DesolateLootcouncil:GetModule("UI_RosterSettings", true)
    if RosterSettings and RosterSettings.GetOptions then
        options.args.roster = RosterSettings:GetOptions()
    end

    ---@type UI_PrioritySettings
    local Priority = DesolateLootcouncil:GetModule("UI_PrioritySettings", true)
    if Priority and Priority.GetOptions then
        options.args.priority = Priority:GetOptions()
    end

    ---@type UI_Attendance
    local Attendance = DesolateLootcouncil:GetModule("UI_Attendance", true)
    if Attendance and Attendance.GetAttendanceOptions then
        options.args.attendance = Attendance:GetAttendanceOptions()
    end

    ---@type UI_ProfileSettings
    local Profiles = DesolateLootcouncil:GetModule("UI_ProfileSettings", true)
    if Profiles and Profiles.GetProfileOptions then
        options.args.profiles = Profiles:GetProfileOptions()
    end

    return options
end

DesolateLootcouncil.SettingsLoader = SettingsLoader
return SettingsLoader
