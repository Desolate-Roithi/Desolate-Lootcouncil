---@class Roster : AceModule, AceConsole-3.0
---@field rosterUI table
---@field OnEnable function
---@field AddMain fun(self: Roster, name: string)
---@field AddAlt fun(self: Roster, altName: string, mainName: string)
---@field DeleteMain fun(self: Roster, name: string)
---@field DeleteAlt fun(self: Roster, name: string)
---@class (partial) DLC_Ref_RosterSettings
---@field db table
---@field NewModule fun(self: DLC_Ref_RosterSettings, name: string, ...): any
---@field Print fun(self: DLC_Ref_RosterSettings, msg: string)

---@type DLC_Ref_RosterSettings
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_RosterSettings]]
local Roster = DesolateLootcouncil:NewModule("Roster", "AceConsole-3.0") --[[@as Roster]]

-- Temp storage for UI inputs
Roster.rosterUI = { newMain = "", newAlt = "", selectedMain = nil, deleteMainSelect = nil, deleteAltSelect = nil }

function Roster:OnEnable()
    -- Initialize or Reset Roster UI state
    self.rosterUI = { newMain = "", newAlt = "", selectedMain = nil, deleteMainSelect = nil, deleteAltSelect = nil }
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
        for name in pairs(DesolateLootcouncil.db.profile.MainRoster) do
            list[name] = name
        end
    end
    return list
end

local function GetAltsDropdown()
    local list = {}
    if DesolateLootcouncil.db then
        for name in pairs(DesolateLootcouncil.db.profile.playerRoster.alts) do
            list[name] = name
        end
    end
    return list
end

function Roster:AddMain(name)
    if not name or name == "" then return end
    local db = DesolateLootcouncil.db
    if not db then return end
    local devDB = db.profile
    if not devDB then return end

    devDB.MainRoster[name] = { addedAt = time() } -- Store main with timestamp
    devDB.playerRoster.alts[name] = nil           -- Ensure not an alt
    DesolateLootcouncil:Print("Added Main: " .. name)
end

function Roster:AddAlt(altName, mainName)
    if not altName or not mainName then return end

    if altName == mainName then
        DesolateLootcouncil:Print("Error: Cannot add a player as an alt to themselves.")
        return
    end

    local profile = DesolateLootcouncil.db.profile
    local roster = profile.playerRoster

    -- 1. Check if the 'new alt' was previously a Main with their own alts
    -- We need to re-parent those alts to the NEW main.
    for existingAlt, existingMain in pairs(roster.alts) do
        if existingMain == altName then
            roster.alts[existingAlt] = mainName
            DesolateLootcouncil:Print("Re-linked inherited alt: " .. existingAlt .. " -> " .. mainName)
        end
    end
    -- 2. Perform the standard assignment
    roster.alts[altName] = mainName
    -- 3. Remove from Mains list if present
    if profile.MainRoster[altName] then
        profile.MainRoster[altName] = nil
        DesolateLootcouncil:Print("Converted Main to Alt: " .. altName)
    end

    DesolateLootcouncil:Print("Linked Alt " .. altName .. " to " .. mainName)
    -- 4. Refresh UI -- (The UI auto-refreshes on next interaction, but ensuring data consistency is key)
end

function Roster:DeleteMain(name)
    if not name then return end
    local db = DesolateLootcouncil.db
    if not db then return end
    local profile = db.profile
    if not profile then return end

    if profile.MainRoster and profile.MainRoster[name] then
        profile.MainRoster[name] = nil
        -- Unlink alts
        if profile.playerRoster and profile.playerRoster.alts then
            for alt, main in pairs(profile.playerRoster.alts) do
                if main == name then
                    profile.playerRoster.alts[alt] = nil
                    DesolateLootcouncil:Print("Unlinked Alt: " .. alt)
                end
            end
        end
        DesolateLootcouncil:Print("Deleted Main: " .. name)
    end
end

function Roster:DeleteAlt(name)
    if not name then return end
    local roster = DesolateLootcouncil.db.profile.playerRoster
    if roster.alts[name] then
        roster.alts[name] = nil
        DesolateLootcouncil:Print("Deleted Alt: " .. name)
    end
end

function Roster:GetOptions()
    return {
        name = "Roster",
        type = "group",
        order = 2,
        args = {
            -- SECTION: ADD / EDIT
            headerAdd = { type = "header", name = "Add / Edit", order = 1 },
            inputMain = {
                type = "input",
                name = "Main Name",
                desc = "Press Enter to Save",
                order = 2,
                get = function() return self.rosterUI.newMain end,
                set = function(_, val)
                    self.rosterUI.newMain = val
                    self:AddMain(val)
                    self.rosterUI.newMain = ""
                end,
            },
            inputAlt = {
                type = "input",
                name = "Alt Name",
                order = 3,
                get = function() return self.rosterUI.newAlt end,
                set = function(_, val) self.rosterUI.newAlt = val end,
            },
            selectMain = {
                type = "select",
                name = "Link to Main",
                order = 4,
                values = GetMainsDropdown,
                get = function() return self.rosterUI.selectedMain end,
                set = function(_, val) self.rosterUI.selectedMain = val end,
            },
            btnAddAlt = {
                type = "execute",
                name = "Save Alt Link",
                order = 5,
                func = function()
                    local alt = self.rosterUI.newAlt
                    local main = self.rosterUI.selectedMain
                    if alt and alt ~= "" and main then
                        self:AddAlt(alt, main)
                        self.rosterUI.newAlt = "" -- Clear input
                    else
                        DesolateLootcouncil:Print("Error: Invalid Alt Name or Main not selected.")
                    end
                end,
            },

            -- SECTION: DELETE
            headerDel = { type = "header", name = "Delete Members", order = 10 },
            selectDelMain = {
                type = "select",
                name = "Delete Main",
                order = 11,
                values = GetMainsDropdown,
                get = function() return self.rosterUI.deleteMainSelect end,
                set = function(_, val) self.rosterUI.deleteMainSelect = val end,
            },
            btnDelMain = {
                type = "execute",
                name = "Delete Main",
                order = 12,
                confirm = true,
                func = function()
                    self:DeleteMain(self.rosterUI.deleteMainSelect)
                    self.rosterUI.deleteMainSelect = nil
                end,
            },
            selectDelAlt = {
                type = "select",
                name = "Delete Alt",
                order = 13,
                values = GetAltsDropdown,
                get = function() return self.rosterUI.deleteAltSelect end,
                set = function(_, val) self.rosterUI.deleteAltSelect = val end,
            },
            btnDelAlt = {
                type = "execute",
                name = "Delete Alt",
                order = 14,
                confirm = true,
                func = function()
                    self:DeleteAlt(self.rosterUI.deleteAltSelect)
                    self.rosterUI.deleteAltSelect = nil
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
