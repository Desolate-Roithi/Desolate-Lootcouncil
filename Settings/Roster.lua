---@class RosterSettings : AceModule
local RosterSettings = DesolateLootcouncil:NewModule("RosterSettings")

function RosterSettings:OnInitialize()
    self.tempName = ""
    self.tempIsAlt = false
    self.tempMain = nil
    self.tempRemove = nil
end

function RosterSettings:GetOptions()
    return {
        name = "Roster",
        type = "group",
        order = 2,
        args = {
            manageGroup = {
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
                        set = function(info, val) self.tempName = val end,
                    },
                    isAlt = {
                        type = "toggle",
                        name = "Is Alt?",
                        desc = "Check if this player is an alt.",
                        order = 2,
                        width = "half",
                        get = function() return self.tempIsAlt end,
                        set = function(info, val) self.tempIsAlt = val end,
                    },
                    targetMain = {
                        type = "select",
                        name = "Link to Main",
                        desc = "Select the Main character for this Alt.",
                        order = 3,
                        hidden = function() return not self.tempIsAlt end,
                        values = function() return self:GetMainRosterList() end,
                        get = function() return self.tempMain end,
                        set = function(info, val) self.tempMain = val end,
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

                            ---@type Roster
                            local RosterSys = DesolateLootcouncil:GetModule("Roster")

                            if self.tempIsAlt then
                                if self.tempMain then
                                    RosterSys:AddAlt(name, self.tempMain)
                                    self.tempName = ""
                                    self.tempMain = nil
                                    self.tempIsAlt = false
                                else
                                    DesolateLootcouncil:Print("Please select a Main character.")
                                end
                            else
                                RosterSys:AddMain(name)
                                self.tempName = ""
                            end
                        end,
                    },
                }
            },
            removeGroup = {
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
                        values = function() return self:GetAllPlayersList() end,
                        get = function() return self.tempRemove end,
                        set = function(info, val) self.tempRemove = val end,
                    },
                    removeBtn = {
                        type = "execute",
                        name = "Remove",
                        order = 2,
                        func = function()
                            if self.tempRemove then
                                DesolateLootcouncil:GetModule("Roster"):RemovePlayer(self.tempRemove)
                                self.tempRemove = nil
                            end
                        end
                    }
                }
            },
            displayGroup = {
                type = "group",
                name = "Current Roster",
                order = 3,
                inline = true,
                args = {
                    rosterList = {
                        type = "description",
                        name = function() return self:GetRosterText() end,
                        order = 1,
                    }
                }
            }
        }
    }
end

function RosterSettings:GetMainRosterList()
    local list = {}
    local db = DesolateLootcouncil.db.profile
    if db.MainRoster then
        for name, _ in pairs(db.MainRoster) do
            list[name] = name
        end
    end
    return list
end

function RosterSettings:GetAllPlayersList()
    local list = self:GetMainRosterList()
    local db = DesolateLootcouncil.db.profile
    if db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            list[alt] = alt .. " (Alt of " .. main .. ")"
        end
    end
    return list
end

function RosterSettings:GetRosterText()
    local db = DesolateLootcouncil.db.profile
    if not db.MainRoster then return "No Roster Found." end

    local text = ""
    local sortedMains = {}
    for name in pairs(db.MainRoster) do table.insert(sortedMains, name) end
    table.sort(sortedMains)

    for _, main in ipairs(sortedMains) do
        text = text .. main

        -- Find alts
        local alts = {}
        if db.playerRoster and db.playerRoster.alts then
            for alt, parent in pairs(db.playerRoster.alts) do
                if parent == main then
                    table.insert(alts, alt)
                end
            end
        end

        if #alts > 0 then
            table.sort(alts)
            text = text .. " -> " .. table.concat(alts, ", ")
        end

        text = text .. "\n"
    end

    return text
end
