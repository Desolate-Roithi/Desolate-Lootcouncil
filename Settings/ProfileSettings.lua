---@class ProfileSettings : AceModule
local ProfileSettings = DesolateLootcouncil:NewModule("ProfileSettings")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

-- Libraries for serialization (using AceSerializer mixed into Core)
---@type DesolateLootcouncil
local DLC = DesolateLootcouncil

function ProfileSettings:GetProfileOptions()
    local db = DLC.db

    local options = {
        name = "Profiles",
        type = "group",
        order = 100, -- End of list
        args = {
            -- --- 1. Basic Profile Management (AceDB Wrappers) ---
            management = {
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
                            local profiles = db:GetProfiles()
                            local t = {}
                            for _, v in ipairs(profiles) do t[v] = v end
                            return t
                        end,
                        set = function(info, key) db:SetProfile(key) end,
                        get = function(info) return db:GetCurrentProfile() end,
                    },
                    newProfileName = {
                        type = "input",
                        name = "New Profile Name",
                        width = 1.0,
                        order = 2,
                        set = function(info, val) self.newProfileName = val end,
                        get = function(info) return self.newProfileName end,
                    },
                    createBtn = {
                        type = "execute",
                        name = "Create / Reset",
                        desc = "Create a new profile with this name (or reset if it exists).",
                        width = 0.5,
                        order = 3,
                        func = function()
                            if self.newProfileName and self.newProfileName ~= "" then
                                db:SetProfile(self.newProfileName)
                                self.newProfileName = nil
                                DLC:DLC_Log("Created/Switched to profile: " .. db:GetCurrentProfile())
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
                            local profiles = db:GetProfiles()
                            local current = db:GetCurrentProfile()
                            local t = {}
                            for _, v in pairs(profiles) do
                                if v ~= current then t[v] = v end
                            end
                            return t
                        end,
                        set = function(info, val) self.copyTarget = val end,
                        get = function(info) return self.copyTarget end,
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
                                db:CopyProfile(self.copyTarget)
                                DLC:DLC_Log("Copied data from: " .. self.copyTarget)
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
                            local current = db:GetCurrentProfile()
                            if current == "Default" then
                                DLC:DLC_Log("Cannot delete Default profile.", true)
                                return
                            end
                            db:SetProfile("Default")
                            db:DeleteProfile(current)
                            DLC:DLC_Log("Deleted profile: " .. current)
                        end,
                    }
                }
            },
            -- --- 2. Advanced Import/Export ---
            importExport = {
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
                    -- Export Config
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
                        set = function(info, key, state)
                            self.exportSelection = self.exportSelection or {}
                            self.exportSelection[key] = state
                        end,
                        get = function(info, key)
                            return self.exportSelection and self.exportSelection[key]
                        end,
                    },
                    genExport = {
                        type = "execute",
                        name = "Generate Export String",
                        width = 1.0,
                        order = 2,
                        func = function() self:GenerateExport() end,
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
                    -- Import Config
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
                        set = function(info, val) self.importStringRaw = val end,
                        get = function(info) return self.importStringRaw end,
                    },
                    importProfileName = {
                        type = "input",
                        name = "New Profile Name (Import)",
                        desc = "Imports always create a new profile for safety.",
                        width = 1.5,
                        order = 12,
                        set = function(info, val) self.importName = val end,
                        get = function(info) return self.importName end,
                    },
                    doImport = {
                        type = "execute",
                        name = "Import Data",
                        width = 1.0,
                        order = 13,
                        func = function() self:RunImport() end,
                    }
                }
            }
        }
    }
    return options
end

-- Logic: Export
function ProfileSettings:GenerateExport()
    if not self.exportSelection then return end
    local p = DLC.db.profile
    local data = {}

    -- Slice data based on selection
    if self.exportSelection["Config"] then
        data.config = {
            minLootQuality = p.minLootQuality,
            enableAutoLoot = p.enableAutoLoot,
            DecayConfig = p.DecayConfig, -- Partial overlap with Roster?
        }
    end
    if self.exportSelection["Roster"] then
        data.Roster = {
            MainRoster = p.MainRoster,
            playerRoster = p.playerRoster
        }
    end
    if self.exportSelection["PriorityLists"] then
        -- Structure only (Names)
        data.PriorityListsStructure = {}
        if p.PriorityLists then
            for i, list in ipairs(p.PriorityLists) do
                table.insert(data.PriorityListsStructure, { name = list.name })
            end
        end
    end
    if self.exportSelection["PriorityContent"] then
        data.PriorityListsContent = p.PriorityLists -- Full dump
    end
    if self.exportSelection["History"] then
        data.History = {
            session = p.session,          -- Contains awarded/bidding
            AttendanceHistory = p.AttendanceHistory,
            PriorityLog = DLC.PriorityLog -- This might be global, need to check persistence
        }
    end

    -- Serialize & Encode
    local serialized = DLC:Serialize(data)
    local encoded = DLC.Base64 and DLC.Base64:Encode(serialized) or serialized

    self.generatedString = encoded
end

-- Logic: Import
function ProfileSettings:RunImport()
    if not self.importStringRaw or self.importStringRaw == "" then
        DLC:DLC_Log("Import Error: String is empty.", true)
        return
    end
    if not self.importName or self.importName == "" then
        DLC:DLC_Log("Import Error: Please specify a name for the new profile.", true)
        return
    end

    -- Decode & Deserialize
    local decoded = self.importStringRaw
    if DLC.Base64 then
        -- Attempt decode (simple check: if it looks like base64 or just try)
        if not string.find(decoded, "^{") then -- Serialized table usually starts with ^1 or something, base64 chars are different
            decoded = DLC.Base64:Decode(self.importStringRaw)
        end
    end

    local success, data = DLC:Deserialize(decoded)
    if not success then
        DLC:DLC_Log("Import Error: Invalid string format / Decode failed.", true)
        return
    end

    -- Create/Switch to New Profile
    DLC.db:SetProfile(self.importName)
    DLC:DLC_Log("Created profile '" .. self.importName .. "' for import.", true)

    -- Merge Data (Profile is now active profile)
    local p = DLC.db.profile

    if data.config then
        for k, v in pairs(data.config) do p[k] = v end
        DLC:DLC_Log("Imported Config.")
    end
    if data.Roster then
        p.MainRoster = data.Roster.MainRoster
        p.playerRoster = data.Roster.playerRoster
        DLC:DLC_Log("Imported Roster.")
    end
    if data.PriorityListsContent then
        p.PriorityLists = data.PriorityListsContent
        DLC:DLC_Log("Imported Full Priority Lists.")
    elseif data.PriorityListsStructure then
        -- Apply names only, clear content? Or try to map?
        -- Simplest: Recreate structure
        local newLists = {}
        for _, l in ipairs(data.PriorityListsStructure) do
            table.insert(newLists, { name = l.name, players = {}, items = {} })
        end
        p.PriorityLists = newLists
        DLC:DLC_Log("Imported Priority List Structure (Empty Content).")
    end
    if data.History then
        -- Merge or Overwrite? Overwrite for history is safer to preserve integrity of the imported blob
        if data.History.session then p.session = data.History.session end
        if data.History.AttendanceHistory then p.AttendanceHistory = data.History.AttendanceHistory end
        DLC:DLC_Log("Imported History.")
    end

    self.importStringRaw = nil
    self.importName = nil
    AceConfigRegistry:NotifyChange("DesolateLootcouncil")
end
