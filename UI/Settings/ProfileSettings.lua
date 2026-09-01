local _, AT = ...
if AT.abortLoad then return end

---@class UI_ProfileSettings : AceModule
local ProfileSettings = DesolateLootcouncil:NewModule("UI_ProfileSettings")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

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
        local profiles = DesolateLootcouncil.API:GetProfiles()
        local exists = false
        for _, profileName in ipairs(profiles) do
            if profileName == name then
                exists = true
                break
            end
        end

        DesolateLootcouncil.API:SetProfile(name)
        if exists then
            DesolateLootcouncil.API:ResetProfile()
            DesolateLootcouncil:DLC_Log("Reset profile: " .. DesolateLootcouncil.API:GetCurrentProfile())
        else
            DesolateLootcouncil:DLC_Log("Created/Switched to profile: " .. DesolateLootcouncil.API:GetCurrentProfile())
        end
        ProfileSettings.newProfileName = nil
        if LibStub and LibStub("AceConfigRegistry-3.0", true) then
            LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
        end
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

local GenerateExportString = function()
    ProfileSettings.generatedString = DesolateLootcouncil.API:ExportProfileData(ProfileSettings.exportSelection)
end

local GetExportString = function()
    return ProfileSettings.generatedString or ""
end

local ImportStringSet = function(info, val)
    ProfileSettings.importStringRaw = val and val:gsub("^%s+", ""):gsub("%s+$", "")
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

local DoImportToCurrent = function()
    local success, err = DesolateLootcouncil.API:ImportProfileData(ProfileSettings.importStringRaw, nil, true)
    if success then
        DesolateLootcouncil:DLC_Log("Import to current profile succeeded!", true)
        ProfileSettings.importStringRaw = nil
    else
        DesolateLootcouncil:DLC_Log(err, true)
    end
end

-- Options Definitions
local currentProfileOpt = {
    type = "select",
    name = L["Current Profile"],
    desc = L["Select an existing profile to switch to."],
    width = "double",
    order = 1,
    values = ValuesCurrentProfile,
    set = SetCurrentProfile,
    get = GetCurrentProfile,
}

local deleteBtnOpt = {
    type = "execute",
    name = L["Delete Profile"],
    desc = L["Delete the current profile (cannot delete Default)."],
    width = "normal",
    order = 2,
    confirm = true,
    confirmText = "Delete this profile forever?",
    func = DeleteProfile,
}

local newProfileNameOpt = {
    type = "input",
    name = L["New Profile Name"],
    desc = L["Enter name to create a new profile or reset an existing one."],
    width = "double",
    order = 3,
    set = NewProfileNameSet,
    get = NewProfileNameGet,
}

local createBtnOpt = {
    type = "execute",
    name = L["Create / Reset"],
    desc = L["Create a new profile with this name (or reset if it exists)."],
    width = "normal",
    order = 4,
    func = CreateNewProfile,
}

local copyFromOpt = {
    type = "select",
    name = L["Copy From Profile"],
    desc = L["Select a profile to copy data FROM (overwrites current!)."],
    width = "double",
    order = 5,
    values = ValuesCopyFrom,
    set = CopyTargetSet,
    get = CopyTargetGet,
}

local copyBtnOpt = {
    type = "execute",
    name = L["Copy"],
    desc = L["Overwrite current profile with data from selected profile."],
    width = "normal",
    order = 6,
    confirm = true,
    confirmText = "Are you sure you want to overwrite the CURRENT profile?",
    func = CopyProfile,
}

local descOpt = {
    type = "description",
    name = L["Export specific settings to share with others or move between profiles.\n"],
    order = 0,
}

local exportOptsGroupOpt = {
    type = "group",
    name = L["Data Domains to Export"],
    inline = true,
    order = 1,
    args = {
        all = {
            type = "toggle",
            name = "|cffffd700" .. L["Entire Profile (Export Everything)"] .. "|r",
            desc = L["Exports a complete backup of all profile modules."],
            width = "full",
            order = 1,
            get = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] end,
            set = function(_, val)
                ProfileSettings.exportSelection = ProfileSettings.exportSelection or {}
                ProfileSettings.exportSelection["All"] = val
                if val then
                    ProfileSettings.exportSelection["Roster"] = false
                    ProfileSettings.exportSelection["PriorityRankings"] = false
                    ProfileSettings.exportSelection["PriorityStructure"] = false
                    ProfileSettings.exportSelection["IM"] = false
                    ProfileSettings.exportSelection["History"] = false
                    ProfileSettings.exportSelection["Config"] = false
                end
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end,
        },
        roster = {
            type = "toggle",
            name = L["Roster (Mains & Alts)"],
            width = "half",
            order = 2,
            disabled = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] end,
            get = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["Roster"] end,
            set = function(_, val)
                if ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] then return end
                ProfileSettings.exportSelection = ProfileSettings.exportSelection or {}
                ProfileSettings.exportSelection["Roster"] = val
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end,
        },
        priorityRankings = {
            type = "toggle",
            name = L["Priority Lists (with Player Rankings)"],
            desc = L["Exports list definitions and active player order."],
            width = "half",
            order = 3,
            disabled = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] end,
            get = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["PriorityRankings"] end,
            set = function(_, val)
                if ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] then return end
                ProfileSettings.exportSelection = ProfileSettings.exportSelection or {}
                ProfileSettings.exportSelection["PriorityRankings"] = val
                if val then
                    ProfileSettings.exportSelection["PriorityStructure"] = false
                end
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end,
        },
        priorityStructure = {
            type = "toggle",
            name = L["Priority Lists (Empty Structure)"],
            desc = L["Exports empty list definitions/templates without raider rankings."],
            width = "half",
            order = 4,
            disabled = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] end,
            get = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["PriorityStructure"] end,
            set = function(_, val)
                if ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] then return end
                ProfileSettings.exportSelection = ProfileSettings.exportSelection or {}
                ProfileSettings.exportSelection["PriorityStructure"] = val
                if val then
                    ProfileSettings.exportSelection["PriorityRankings"] = false
                end
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end,
        },
        im = {
            type = "toggle",
            name = L["Item Manager (Catalogs)"],
            desc = L["Exports item assignments and managed priority lists."],
            width = "half",
            order = 5,
            disabled = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] end,
            get = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["IM"] end,
            set = function(_, val)
                if ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] then return end
                ProfileSettings.exportSelection = ProfileSettings.exportSelection or {}
                ProfileSettings.exportSelection["IM"] = val
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end,
        },
        history = {
            type = "toggle",
            name = L["Raid Attendance & Award History"],
            width = "half",
            order = 6,
            disabled = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] end,
            get = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["History"] end,
            set = function(_, val)
                if ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] then return end
                ProfileSettings.exportSelection = ProfileSettings.exportSelection or {}
                ProfileSettings.exportSelection["History"] = val
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end,
        },
        config = {
            type = "toggle",
            name = L["General Config & Decay Rules"],
            width = "half",
            order = 7,
            disabled = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] end,
            get = function() return ProfileSettings.exportSelection and ProfileSettings.exportSelection["Config"] end,
            set = function(_, val)
                if ProfileSettings.exportSelection and ProfileSettings.exportSelection["All"] then return end
                ProfileSettings.exportSelection = ProfileSettings.exportSelection or {}
                ProfileSettings.exportSelection["Config"] = val
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end,
        },
    }
}

local genExportOpt = {
    type = "execute",
    name = L["Generate Export String"],
    desc = L["Encode and package the selected domains into a shareable export string."],
    width = "full",
    order = 2,
    func = GenerateExportString,
}

local exportStringOpt = {
    type = "input",
    name = L["Export String"],
    width = "full",
    multiline = 4,
    order = 3,
    set = function() end,
    get = GetExportString,
}

local importHeaderOpt = {
    type = "header",
    name = L["Import Profile Payload"],
    order = 10,
}

local importStringOpt = {
    type = "input",
    name = L["Paste Import String"],
    desc = L["Paste a base64 export string generated from Desolate Loot Council."],
    width = "full",
    multiline = 4,
    order = 11,
    set = ImportStringSet,
    get = ImportStringGet,
}

local importProfileNameOpt = {
    type = "input",
    name = L["New Profile Name (Import)"],
    desc = L["Imports always create a new profile for safety."],
    width = "normal",
    order = 12,
    set = ImportProfileNameSet,
    get = ImportProfileNameGet,
}

local doImportOpt = {
    type = "execute",
    name = L["Import to New Profile"],
    desc = L["Import data into a newly created profile."],
    width = "normal",
    order = 13,
    func = DoImport,
}

local doImportToCurrentOpt = {
    type = "execute",
    name = L["Import to Current Profile"],
    desc = L["Import data directly into the active profile."],
    width = "normal",
    order = 14,
    confirm = true,
    confirmText = L["Are you sure you want to import directly into your CURRENT active profile? This cannot be undone."],
    func = DoImportToCurrent,
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
        name = L["Profile Management"],
        order = 1,
        inline = true,
        args = {}
    }
    local args = opts.args
    args.currentProfile = currentProfileOpt
    args.deleteBtn = deleteBtnOpt
    args.newProfileName = newProfileNameOpt
    args.createBtn = createBtnOpt
    args.copyFrom = copyFromOpt
    args.copyBtn = copyBtnOpt
    return opts
end

function ProfileSettings:GetImportExportOptions()
    local opts = {
        type = "group",
        name = L["Import / Export"],
        order = 2,
        inline = true,
        args = {}
    }
    local args = opts.args
    args.desc = descOpt
    args.exportOpts = exportOptsGroupOpt
    args.genExport = genExportOpt
    args.exportString = exportStringOpt
    args.importHeader = importHeaderOpt
    args.importString = importStringOpt
    args.importProfileName = importProfileNameOpt
    args.doImport = doImportOpt
    args.doImportToCurrent = doImportToCurrentOpt
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
