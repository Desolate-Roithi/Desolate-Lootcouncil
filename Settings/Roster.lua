---@class RosterSettings : AceModule
local Roster = DesolateLootcouncil:NewModule("RosterSettings")

function Roster:GetOptions()
    return {
        name = "Roster",
        type = "group",
        order = 2,
        args = {
            header = {
                type = "header",
                name = "Roster Management",
                order = 0,
            },
            addMain = {
                type = "input",
                name = "Add Main",
                desc = "Add a player to the Main Roster.",
                order = 1,
                set = function(info, val) DesolateLootcouncil:GetModule("Roster") --[[@as Roster]]:AddMain(val) end,
            },
            addAltContainer = {
                type = "group",
                inline = true,
                name = "Add Alt",
                order = 2,
                args = {
                    altName = {
                        type = "input",
                        name = "Alt Name",
                        order = 1,
                        set = function(info, val) self.tempAlt = val end,
                        get = function(info) return self.tempAlt end,
                    },
                    mainName = {
                        type = "select",
                        name = "Link to Main",
                        order = 2,
                        values = function() return self:GetMainRosterList() end,
                        set = function(info, val)
                            if self.tempAlt then
                                DesolateLootcouncil:GetModule("Roster") --[[@as Roster]]:AddAlt(self.tempAlt, val)
                                self.tempAlt = nil
                            end
                        end,
                    }
                }
            },
            removePlayer = {
                type = "select",
                name = "Remove Player",
                desc = "Remove a player (Main or Alt) from the roster.",
                order = 3,
                values = function() return self:GetAllPlayersList() end,
                set = function(info, val) DesolateLootcouncil:GetModule("Roster") --[[@as Roster]]:RemovePlayer(val) end,
            },
        }
    }
end

function Roster:GetMainRosterList()
    local list = {}
    local db = DesolateLootcouncil.db.profile
    if db.MainRoster then
        for name, _ in pairs(db.MainRoster) do
            list[name] = name
        end
    end
    return list
end

function Roster:GetAllPlayersList()
    local list = self:GetMainRosterList()
    local db = DesolateLootcouncil.db.profile
    if db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            list[alt] = alt .. " (Alt of " .. main .. ")"
        end
    end
    return list
end
