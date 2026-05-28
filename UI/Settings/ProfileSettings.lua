local _, AT = ...
if AT.abortLoad then return end

---@class UI_ProfileSettings : AceModule
local ProfileSettings = DesolateLootcouncil:NewModule("UI_ProfileSettings")

function ProfileSettings:OnInitialize()
    self.exportSelection = {}
    self.generatedString = ""
    self.newProfileName = nil
    self.copyTarget = nil
    self.importStringRaw = nil
    self.importName = nil
end

function ProfileSettings:GetManagementOptions()
    local API = DesolateLootcouncil.API
    return {
        type = "group",
        name = "Profile Management",
        order = 1,
        inline = true,
        args = {
            currentProfile = {
                type = "select",
                name = "Current Profile",
                desc = "Select an existing profile to switch to.",
                width = 1.5,
                order = 1,
                values = function()
                    local profiles = API:GetProfiles()
                    local t = {}
                    for _, v in ipairs(profiles) do t[v] = v end
                    return t
                end,
                set = function(_, key) API:SetProfile(key) end,
                get = function() return API:GetCurrentProfile() end,
            },
            newProfileName = {
                type = "input",
                name = "New Profile Name",
                width = 1.0,
                order = 2,
                set = function(_, val) self.newProfileName = val end,
                get = function() return self.newProfileName end,
            },
            createBtn = {
                type = "execute",
                name = "Create / Reset",
                desc = "Create a new profile with this name (or reset if it exists).",
                width = 0.5,
                order = 3,
                func = function()
                    if self.newProfileName and self.newProfileName ~= "" then
                        API:SetProfile(self.newProfileName)
                        self.newProfileName = nil
                        DesolateLootcouncil:DLC_Log("Created/Switched to profile: " .. API:GetCurrentProfile())
                    end
                end,
            },
            copyFrom = {
                type = "select",
                name = "Copy From Profile",
                desc = "Select a profile to copy data FROM (overwrites current!).",
                width = 1.5,
                order = 4,
                values = function()
                    local profiles = API:GetProfiles()
                    local current = API:GetCurrentProfile()
                    local t = {}
                    for _, v in ipairs(profiles) do
                        if v ~= current then t[v] = v end
                    end
                    return t
                end,
                set = function(_, val) self.copyTarget = val end,
                get = function() return self.copyTarget end,
            },
            copyBtn = {
                type = "execute",
                name = "Copy",
                desc = "Overwrite current profile with data from selected profile.",
                width = 0.5,
                order = 5,
                confirm = true,
                confirmText = "Are you sure you want to overwrite the CURRENT profile?",
                func = function()
                    if self.copyTarget then
                        API:CopyProfile(self.copyTarget)
                        DesolateLootcouncil:DLC_Log("Copied data from: " .. self.copyTarget)
                        self.copyTarget = nil
                    end
                end,
            },
            deleteBtn = {
                type = "execute",
                name = "Delete Profile",
                desc = "Delete the current profile (cannot delete Default).",
                width = 1.0,
                order = 6,
                confirm = true,
                confirmText = "Delete this profile forever?",
                func = function()
                    local current = API:GetCurrentProfile()
                    if current == "Default" then
                        DesolateLootcouncil:DLC_Log("Cannot delete Default profile.", true)
                        return
                    end
                    API:SetProfile("Default")
                    API:DeleteProfile(current)
                    DesolateLootcouncil:DLC_Log("Deleted profile: " .. current)
                end,
            }
        }
    }
end

function ProfileSettings:GetImportExportOptions()
    local API = DesolateLootcouncil.API
    return {
        type = "group",
        name = "Import / Export",
        order = 2,
        inline = true,
        args = {
            desc = {
                type = "description",
                name = "Export specific settings to share with others or move between profiles.\n",
                order = 0,
            },
            exportOpts = {
                type = "multiselect",
                name = "Data to Export",
                desc = "Select which sections to include.",
                width = "full",
                order = 1,
                values = {
                    ["Roster"] = "Roster (Mains/Alts/Decay)",
                    ["PriorityLists"] = "Priority Lists (Names/Order)",
                    ["PriorityContent"] = "Priority List Content (Players/Items)",
                    ["History"] = "Loot History & Attendance",
                    ["Config"] = "General Config & Loot Rules",
                },
                set = function(_, key, state)
                    self.exportSelection = self.exportSelection or {}
                    self.exportSelection[key] = state
                end,
                get = function(_, key)
                    return self.exportSelection and self.exportSelection[key]
                end,
            },
            genExport = {
                type = "execute",
                name = "Generate Export String",
                width = 1.0,
                order = 2,
                func = function()
                    self.generatedString = API:ExportProfileData(self.exportSelection)
                end,
            },
            exportString = {
                type = "input",
                name = "Export String",
                width = "full",
                multiline = 5,
                order = 3,
                set = function() end,
                get = function() return self.generatedString or "" end,
            },
            importHeader = {
                type = "header",
                name = "Import",
                order = 10,
            },
            importString = {
                type = "input",
                name = "Paste Import String",
                width = "full",
                multiline = 5,
                order = 11,
                set = function(_, val) self.importStringRaw = val end,
                get = function() return self.importStringRaw end,
            },
            importProfileName = {
                type = "input",
                name = "New Profile Name (Import)",
                desc = "Imports always create a new profile for safety.",
                width = 1.5,
                order = 12,
                set = function(_, val) self.importName = val end,
                get = function() return self.importName end,
            },
            doImport = {
                type = "execute",
                name = "Import Data",
                width = 1.0,
                order = 13,
                func = function()
                    local success, err = API:ImportProfileData(self.importStringRaw, self.importName)
                    if success then
                        DesolateLootcouncil:DLC_Log("Import succeeded!", true)
                        self.importStringRaw = nil
                        self.importName = nil
                    else
                        DesolateLootcouncil:DLC_Log(err, true)
                    end
                end,
            }
        }
    }
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
