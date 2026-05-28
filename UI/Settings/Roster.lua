local _, AT = ...
if AT.abortLoad then return end

---@class UI_RosterSettings : AceModule
local RosterSettings = DesolateLootcouncil:NewModule("UI_RosterSettings")

function RosterSettings:OnInitialize()
    self.tempName = ""
    self.tempIsAlt = false
    self.tempMain = nil
    self.tempRemove = nil
end

function RosterSettings:GetManageGroupOptions()
    local API = DesolateLootcouncil.API

    return {
        type = "group",
        name = "Manage Roster",
        order = 1,
        inline = true,
        args = {
            addPlayer = {
                type = "input",
                name = "Add Player (Name-Realm)",
                desc = "Enter player name. Defaults to current realm if omitted.",
                order = 1,
                width = "double",
                get = function() return self.tempName end,
                set = function(_, val) self.tempName = val end,
            },
            isAlt = {
                type = "toggle",
                name = "Is Alt?",
                desc = "Check if this player is an alt.",
                order = 2,
                width = "half",
                get = function() return self.tempIsAlt end,
                set = function(_, val) self.tempIsAlt = val end,
            },
            targetMain = {
                type = "select",
                name = "Link to Main",
                desc = "Select the Main character for this Alt.",
                order = 3,
                hidden = function() return not self.tempIsAlt end,
                values = function() return API:GetMainRosterList() end,
                get = function() return self.tempMain end,
                set = function(_, val) self.tempMain = val end,
            },
            saveBtn = {
                type = "execute",
                name = "Add / Save",
                desc = "Add or update the player in the roster.",
                order = 4,
                width = "full",
                func = function()
                    local name = self.tempName
                    if not name or name == "" then return end

                    if self.tempIsAlt then
                        if self.tempMain then
                            API:AddAlt(name, self.tempMain)
                            self.tempName = ""
                            self.tempMain = nil
                            self.tempIsAlt = false
                        else
                            DesolateLootcouncil:Print("Please select a Main character.")
                        end
                    else
                        API:AddMain(name)
                        self.tempName = ""
                    end
                end,
            },
        }
    }
end

function RosterSettings:GetRemoveGroupOptions()
    local API = DesolateLootcouncil.API

    return {
        type = "group",
        name = "Remove Player",
        order = 2,
        inline = true,
        args = {
            removeSelect = {
                type = "select",
                name = "Select Player to Remove",
                order = 1,
                width = "double",
                values = function() return API:GetAllPlayersList() end,
                get = function() return self.tempRemove end,
                set = function(_, val) self.tempRemove = val end,
            },
            removeBtn = {
                type = "execute",
                name = "Remove",
                order = 2,
                func = function()
                    if self.tempRemove then
                        API:RemovePlayer(self.tempRemove)
                        self.tempRemove = nil
                    end
                end
            }
        }
    }
end

function RosterSettings:GetDisplayGroupOptions()
    local API = DesolateLootcouncil.API

    return {
        type = "group",
        name = "Current Roster",
        order = 3,
        inline = true,
        args = {
            rosterList = {
                type = "description",
                name = function() return API:GetRosterText() end,
                order = 1,
            }
        }
    }
end

function RosterSettings:GetOptions()
    return {
        name = "Roster",
        type = "group",
        order = 2,
        args = {
            manageGroup = self:GetManageGroupOptions(),
            removeGroup = self:GetRemoveGroupOptions(),
            displayGroup = self:GetDisplayGroupOptions()
        }
    }
end
