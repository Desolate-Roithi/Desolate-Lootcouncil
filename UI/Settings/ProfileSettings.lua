local _, AT = ...
if AT.abortLoad then return end

---@class UI_ProfileSettings : AceModule
local ProfileSettings = DesolateLootcouncil:NewModule("UI_ProfileSettings")

-- Helper functions
local ValuesCurrentProfile = function()
    local profiles = DesolateLootcouncil.API:GetProfiles()
    local t = {}
    for _, v in ipairs(profiles) do t[v] = v end
    return t
end

local SetCurrentProfile = function(info, key)
    DesolateLootcouncil.API:SetProfile(key)
end

local GetCurrentProfile = function()
    return DesolateLootcouncil.API:GetCurrentProfile()
end

local NewProfileNameSet = function(info, val)
    ProfileSettings.newProfileName = val
end

local NewProfileNameGet = function()
    return ProfileSettings.newProfileName
end

local CreateNewProfile = function()
    local name = ProfileSettings.newProfileName
    if name and name ~= "" then
        DesolateLootcouncil.API:SetProfile(name)
        ProfileSettings.newProfileName = nil
        DesolateLootcouncil:DLC_Log("Created/Switched to profile: " .. DesolateLootcouncil.API:GetCurrentProfile())
    end
end

local ValuesCopyFrom = function()
    local profiles = DesolateLootcouncil.API:GetProfiles()
    local current = DesolateLootcouncil.API:GetCurrentProfile()
    local t = {}
    for _, v in ipairs(profiles) do
        t[v] = (v ~= current) and v or nil
    end
    return t
end

local CopyTargetSet = function(info, val)
    ProfileSettings.copyTarget = val
end

local CopyTargetGet = function()
    return ProfileSettings.copyTarget
end

local CopyProfile = function()
    if ProfileSettings.copyTarget then
        DesolateLootcouncil.API:CopyProfile(ProfileSettings.copyTarget)
        DesolateLootcouncil:DLC_Log("Copied data from: " .. ProfileSettings.copyTarget)
        ProfileSettings.copyTarget = nil
    end
end

local DeleteProfile = function()
    local current = DesolateLootcouncil.API:GetCurrentProfile()
    if current == "Default" then
        DesolateLootcouncil:DLC_Log("Cannot delete Default profile.", true)
        return
    end
    DesolateLootcouncil.API:SetProfile("Default")
    DesolateLootcouncil.API:DeleteProfile(current)
    DesolateLootcouncil:DLC_Log("Deleted profile: " .. current)
end

local ExportOptsSet = function(info, key, state)
    ProfileSettings.exportSelection = ProfileSettings.exportSelection or {}
    ProfileSettings.exportSelection[key] = state
end

local ExportOptsGet = function(info, key)
    return ProfileSettings.exportSelection and ProfileSettings.exportSelection[key]
end

local GenerateExportString = function()
    ProfileSettings.generatedString = DesolateLootcouncil.API:ExportProfileData(ProfileSettings.exportSelection)
end

local GetExportString = function()
    return ProfileSettings.generatedString or ""
end

local ImportStringSet = function(info, val)
    ProfileSettings.importStringRaw = val
end

local ImportStringGet = function()
    return ProfileSettings.importStringRaw
end

local ImportProfileNameSet = function(info, val)
    ProfileSettings.importName = val
end

local ImportProfileNameGet = function()
    return ProfileSettings.importName
end

local DoImport = function()
    local success, err = DesolateLootcouncil.API:ImportProfileData(ProfileSettings.importStringRaw, ProfileSettings.importName)
    if success then
        DesolateLootcouncil:DLC_Log("Import succeeded!", true)
        ProfileSettings.importStringRaw = nil
        ProfileSettings.importName = nil
    else
        DesolateLootcouncil:DLC_Log(err, true)
    end
end

-- Options Definitions
local currentProfileOpt = {
    type = "select",
    name = "Current Profile",
    desc = "Select an existing profile to switch to.",
    width = 1.5,
    order = 1,
    values = ValuesCurrentProfile,
    set = SetCurrentProfile,
    get = GetCurrentProfile,
}

local newProfileNameOpt = {
    type = "input",
    name = "New Profile Name",
    width = 1.0,
    order = 2,
    set = NewProfileNameSet,
    get = NewProfileNameGet,
}

local createBtnOpt = {
    type = "execute",
    name = "Create / Reset",
    desc = "Create a new profile with this name (or reset if it exists).",
    width = 0.5,
    order = 3,
    func = CreateNewProfile,
}

local copyFromOpt = {
    type = "select",
    name = "Copy From Profile",
    desc = "Select a profile to copy data FROM (overwrites current!).",
    width = 1.5,
    order = 4,
    values = ValuesCopyFrom,
    set = CopyTargetSet,
    get = CopyTargetGet,
}

local copyBtnOpt = {
    type = "execute",
    name = "Copy",
    desc = "Overwrite current profile with data from selected profile.",
    width = 0.5,
    order = 5,
    confirm = true,
    confirmText = "Are you sure you want to overwrite the CURRENT profile?",
    func = CopyProfile,
}

local deleteBtnOpt = {
    type = "execute",
    name = "Delete Profile",
    desc = "Delete the current profile (cannot delete Default).",
    width = 1.0,
    order = 6,
    confirm = true,
    confirmText = "Delete this profile forever?",
    func = DeleteProfile,
}

local descOpt = {
    type = "description",
    name = "Export specific settings to share with others or move between profiles.\n",
    order = 0,
}

local exportOptsOpt = {
    type = "multiselect",
    name = "Data to Export",
    desc = "Select which sections to include.",
    width = "full",
    order = 1,
    values = {
        ["Roster"] = "Roster (Mains/Alts/Decay)",
        ["PriorityLists"] = "Priority Lists (Names/Order)",
        ["PriorityContent"] = "Priority List Content (Players/Items)",
        ["IM"] = "Item Manager (Managed Items)",
        ["History"] = "Loot History & Attendance",
        ["Config"] = "General Config & Loot Rules",
    },
    set = ExportOptsSet,
    get = ExportOptsGet,
}

local genExportOpt = {
    type = "execute",
    name = "Generate Export String",
    width = 1.0,
    order = 2,
    func = GenerateExportString,
}

local exportStringOpt = {
    type = "input",
    name = "Export String",
    width = "full",
    multiline = 5,
    order = 3,
    set = function() end,
    get = GetExportString,
}

local importHeaderOpt = {
    type = "header",
    name = "Import",
    order = 10,
}

local importStringOpt = {
    type = "input",
    name = "Paste Import String",
    width = "full",
    multiline = 5,
    order = 11,
    set = ImportStringSet,
    get = ImportStringGet,
}

local importProfileNameOpt = {
    type = "input",
    name = "New Profile Name (Import)",
    desc = "Imports always create a new profile for safety.",
    width = 1.5,
    order = 12,
    set = ImportProfileNameSet,
    get = ImportProfileNameGet,
}

local doImportOpt = {
    type = "execute",
    name = "Import Data",
    width = 1.0,
    order = 13,
    func = DoImport,
}

function ProfileSettings:OnInitialize()
    self.exportSelection = {}
    self.generatedString = ""
    self.newProfileName = nil
    self.copyTarget = nil
    self.importStringRaw = nil
    self.importName = nil
end

function ProfileSettings:GetManagementOptions()
    local opts = {
        type = "group",
        name = "Profile Management",
        order = 1,
        inline = true,
        args = {}
    }
    local args = opts.args
    args.currentProfile = currentProfileOpt
    args.newProfileName = newProfileNameOpt
    args.createBtn = createBtnOpt
    args.copyFrom = copyFromOpt
    args.copyBtn = copyBtnOpt
    args.deleteBtn = deleteBtnOpt
    return opts
end

function ProfileSettings:GetImportExportOptions()
    local opts = {
        type = "group",
        name = "Import / Export",
        order = 2,
        inline = true,
        args = {}
    }
    local args = opts.args
    args.desc = descOpt
    args.exportOpts = exportOptsOpt
    args.genExport = genExportOpt
    args.exportString = exportStringOpt
    args.importHeader = importHeaderOpt
    args.importString = importStringOpt
    args.importProfileName = importProfileNameOpt
    args.doImport = doImportOpt
    return opts
end

function ProfileSettings:GetProfileOptions()
    return {
        name = "Profiles",
        type = "group",
        order = 100,
        args = {
            management = self:GetManagementOptions(),
            importExport = self:GetImportExportOptions()
        }
    }
end
