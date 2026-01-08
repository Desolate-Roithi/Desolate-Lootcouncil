---@class Roster : AceModule, AceConsole-3.0
---@field rosterUI table
---@field OnEnable function
---@field AddMain fun(self: Roster, name: string) -- Delegate
---@field AddAlt fun(self: Roster, altName: string, mainName: string) -- Delegate
---@field DeleteMain fun(self: Roster, name: string) -- Delegate
---@field DeleteAlt fun(self: Roster, name: string) -- Delegate
---@class (partial) DLC_Ref_RosterSettings
---@field db table
---@field NewModule fun(self: DLC_Ref_RosterSettings, name: string, ...): any
---@field Print fun(self: DLC_Ref_RosterSettings, msg: string)
---@field AddMain fun(self: DLC_Ref_RosterSettings, name: string)
---@field AddAlt fun(self: DLC_Ref_RosterSettings, altName: string, mainName: string)
---@field RemovePlayer fun(self: DLC_Ref_RosterSettings, name: string)

---@type DLC_Ref_RosterSettings
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_RosterSettings]]
local Roster = DesolateLootcouncil:NewModule("Roster", "AceConsole-3.0") --[[@as Roster]]

-- Temp storage for UI inputs
Roster.rosterUI = { newMain = "", newAlt = "", selectedMain = nil, deleteMainSelect = nil, deleteAltSelect = nil, isAlt = false, removeSelect = nil }

function Roster:OnEnable()
    -- Initialize or Reset Roster UI state
    self.rosterUI = { newMain = "", newAlt = "", selectedMain = nil, deleteMainSelect = nil, deleteAltSelect = nil, isAlt = false, removeSelect = nil }
end

-- Helper: Generate the status list text
local function GetRosterListText()
    local db = DesolateLootcouncil.db.profile
    local text = ""

    -- Gather mains and their alts
    local data = {} -- [mainName] = {alts = {}}
    if db and db.MainRoster then
        for main in pairs(db.MainRoster) do
            data[main] = { alts = {} }
        end
    end

    if db and db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            if data[main] then
                table.insert(data[main].alts, alt)
            else
                -- Orphaned alt or main missing
                -- data[main] = { alts = {alt} } -- Optional: show orphans
            end
        end
    end

    -- Sort Mains
    local sortedMains = {}
    for main in pairs(data) do table.insert(sortedMains, main) end
    table.sort(sortedMains)

    for _, main in ipairs(sortedMains) do
        local altList = data[main].alts
        table.sort(altList)
        local altStr = #altList > 0 and (" -> " .. table.concat(altList, ", ")) or ""
        text = text .. "|cffffd700" .. main .. "|r" .. altStr .. "\n"
    end

    if text == "" then text = "Roster is empty." end

    return text
end

-- Helper: Dropdown sources
local function GetMainsDropdown()
    local list = {}
    if DesolateLootcouncil.db then
        if DesolateLootcouncil.db.profile.MainRoster then
            for name in pairs(DesolateLootcouncil.db.profile.MainRoster) do
                list[name] = name
            end
        end
    end
    return list
end

local function GetAltsDropdown()
    local list = {}
    if DesolateLootcouncil.db then
        if DesolateLootcouncil.db.profile.playerRoster.alts then
            for name in pairs(DesolateLootcouncil.db.profile.playerRoster.alts) do
                list[name] = name
            end
        end
    end
    return list
end

function Roster:GetOptions()
    return {
        name = "Roster",
        type = "group",
        order = 2,
        args = {
            -- SECTION: ADD / EDIT
            headerAdd = { type = "header", name = "Manage Roster", order = 1 },
            inputName = {
                type = "input",
                name = "Add Player (Name-Realm)",
                desc = "Enter the player Name-Realm.",
                order = 2,
                get = function() return self.rosterUI.newMain end,
                set = function(_, val) self.rosterUI.newMain = val end,
            },
            isAltToggle = {
                type = "toggle",
                name = "Is Alt?",
                order = 3,
                get = function() return self.rosterUI.isAlt end,
                set = function(_, val) self.rosterUI.isAlt = val end,
            },
            selectMainLink = {
                type = "select",
                name = "Select Main",
                order = 4,
                values = GetMainsDropdown,
                hidden = function() return not self.rosterUI.isAlt end,
                get = function() return self.rosterUI.selectedMain end,
                set = function(_, val) self.rosterUI.selectedMain = val end,
            },
            btnAdd = {
                type = "execute",
                name = "Add / Save",
                order = 5,
                func = function()
                    local name = self.rosterUI.newMain
                    if not name or name == "" then return end

                    if self.rosterUI.isAlt then
                        local main = self.rosterUI.selectedMain
                        if main and main ~= "" then
                            DesolateLootcouncil:AddAlt(name, main)
                        else
                            DesolateLootcouncil:Print("Error: You must select a Main for this Alt.")
                        end
                    else
                        DesolateLootcouncil:AddMain(name)
                    end
                    self.rosterUI.newMain = ""
                end,
            },

            -- SECTION: REMOVE
            headerRemove = { type = "header", name = "Remove Player", order = 10 },
            selectRemove = {
                type = "select",
                name = "Select Player to Remove",
                desc = "Removes Main (and unlinks alts) or Remove Alt.",
                order = 11,
                values = function()
                    local list = GetMainsDropdown()
                    local alts = GetAltsDropdown()
                    for k, v in pairs(alts) do list[k] = v .. " (Alt)" end
                    return list
                end,
                get = function() return self.rosterUI.removeSelect end,
                set = function(_, val) self.rosterUI.removeSelect = val end,
            },
            btnRemove = {
                type = "execute",
                name = "Remove",
                order = 12,
                confirm = true,
                func = function()
                    local target = self.rosterUI.removeSelect
                    if not target then return end

                    DesolateLootcouncil:RemovePlayer(target)

                    self.rosterUI.removeSelect = nil
                end,
            },

            -- SECTION: DISPLAY LIST
            headerL = { type = "header", name = "Current Roster", order = 20 },
            listDisplay = {
                type = "description", name = GetRosterListText, order = 21, fontSize = "medium"
            },
        }
    }
end
