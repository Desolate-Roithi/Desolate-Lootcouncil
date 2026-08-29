local _, AT = ...
if AT.abortLoad then return end

---@class UI_RosterSettings : AceModule
local RosterSettings = DesolateLootcouncil:NewModule("UI_RosterSettings")

-- Helper functions
local GetTempName = function()
    return RosterSettings.tempName
end

local SetTempName = function(info, val)
    RosterSettings.tempName = val
end

local GetTempIsAlt = function()
    return RosterSettings.tempIsAlt
end

local SetTempIsAlt = function(info, val)
    RosterSettings.tempIsAlt = val
    if val then
        RosterSettings.tempIsOfficer = false
    end
end

local TargetMainHidden = function()
    return not RosterSettings.tempIsAlt
end

local TargetMainValues = function()
    return DesolateLootcouncil.API:GetMainRosterList()
end

local GetTempMain = function()
    return RosterSettings.tempMain
end

local SetTempMain = function(info, val)
    RosterSettings.tempMain = val
end

local SavePlayer = function()
    local name = RosterSettings.tempName
    if not name or name == "" then return end

    if RosterSettings.tempIsAlt then
        if not RosterSettings.tempMain then
            DesolateLootcouncil:Print("Please select a Main character.")
            return
        end
        DesolateLootcouncil.API:AddAlt(name, RosterSettings.tempMain)
        RosterSettings.tempName = ""
        RosterSettings.tempMain = nil
        RosterSettings.tempIsAlt = false
        RosterSettings.tempIsOfficer = false
    else
        DesolateLootcouncil.API:AddMain(name)
        if RosterSettings.tempIsOfficer then
            DesolateLootcouncil.API:SetOfficer(name, true)
        end
        RosterSettings.tempName = ""
        RosterSettings.tempIsOfficer = false
    end
end

local GetRemoveValues = function()
    return DesolateLootcouncil.API:GetAllPlayersList()
end

local GetPlayerSorting = function()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.MainRoster then return {} end

    local mains = {}
    for main in pairs(db.MainRoster) do
        table.insert(mains, main)
    end
    table.sort(mains, function(a, b) return a:lower() < b:lower() end)

    local mainToAlts = {}
    if db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            if not mainToAlts[main] then mainToAlts[main] = {} end
            table.insert(mainToAlts[main], alt)
        end
    end
    for _, altList in pairs(mainToAlts) do
        table.sort(altList, function(a, b) return a:lower() < b:lower() end)
    end

    local sorted = {}
    for _, main in ipairs(mains) do
        table.insert(sorted, main)
        if mainToAlts[main] then
            for _, alt in ipairs(mainToAlts[main]) do
                table.insert(sorted, alt)
            end
        end
    end
    return sorted
end

local GetTempRemove = function()
    return RosterSettings.tempRemove
end

local SetTempRemove = function(info, val)
    RosterSettings.tempRemove = val
end

local RemovePlayer = function()
    if RosterSettings.tempRemove then
        DesolateLootcouncil.API:RemovePlayer(RosterSettings.tempRemove)
        RosterSettings.tempRemove = nil
    end
end

-- Rename Player
local GetTempRenameSelect = function()
    return RosterSettings.tempRenameSelect
end

local SetTempRenameSelect = function(info, val)
    RosterSettings.tempRenameSelect = val
end

local GetTempRenameNew = function()
    return RosterSettings.tempRenameNew or ""
end

local SetTempRenameNew = function(info, val)
    RosterSettings.tempRenameNew = val
end

local RenamePlayerAction = function()
    local oldName = RosterSettings.tempRenameSelect
    local newName = RosterSettings.tempRenameNew
    if oldName and newName and newName ~= "" then
        local ok = DesolateLootcouncil.API:RenamePlayer(oldName, newName)
        if ok then
            RosterSettings.tempRenameSelect = nil
            RosterSettings.tempRenameNew = ""
        end
    end
end

local GetRosterText = function()
    return DesolateLootcouncil.API:GetRosterText()
end

-- Options Definitions
local addPlayerOpt = {
    type = "input",
    name = "Add Player (Name-Realm)",
    desc = "Enter player name. Defaults to current realm if omitted.",
    order = 1,
    width = "double",
    get = GetTempName,
    set = SetTempName,
}

local isAltOpt = {
    type = "toggle",
    name = "Is Alt?",
    desc = "Check if this player is an alt.",
    order = 2,
    width = "half",
    get = GetTempIsAlt,
    set = SetTempIsAlt,
}

local targetMainOpt = {
    type = "select",
    name = "Link to Main",
    desc = "Select the Main character for this Alt.",
    order = 3,
    hidden = TargetMainHidden,
    values = TargetMainValues,
    get = GetTempMain,
    set = SetTempMain,
}

local isOfficerOpt = {
    type = "toggle",
    name = "Is Officer?",
    desc = "Grant council officer permissions to this player.",
    order = 4,
    width = "half",
    hidden = function() return RosterSettings.tempIsAlt end,
    get = GetTempIsOfficer,
    set = SetTempIsOfficer,
}

local saveBtnOpt = {
    type = "execute",
    name = "Add / Save",
    order = 5,
    width = "full",
    func = SavePlayer,
}

local GetOfficerValues = function()
    return DesolateLootcouncil.API:GetMainRosterList()
end

local GetTempOfficerSelect = function()
    return RosterSettings.tempOfficerSelect
end

local SetTempOfficerSelect = function(info, val)
    RosterSettings.tempOfficerSelect = val
end

local GetOfficerToggle = function()
    if not RosterSettings.tempOfficerSelect then return false end
    local db = DesolateLootcouncil.db.profile
    local main = RosterSettings.tempOfficerSelect
    if db.MainRoster and type(db.MainRoster[main]) == "table" then
        return db.MainRoster[main].isOfficer == true
    end
    return false
end

local SetOfficerToggle = function(info, checked)
    if RosterSettings.tempOfficerSelect then
        DesolateLootcouncil.API:SetOfficer(RosterSettings.tempOfficerSelect, checked)
    end
end

local officerSelectOpt = {
    type = "select",
    name = "Select Player to Update",
    order = 1,
    width = "double",
    values = GetOfficerValues,
    get = GetTempOfficerSelect,
    set = SetTempOfficerSelect,
}

local officerToggleOpt = {
    type = "toggle",
    name = "Is Officer?",
    order = 2,
    get = GetOfficerToggle,
    set = SetOfficerToggle,
}

-- Rename Options
local renameSelectOpt = {
    type = "select",
    name = "Select Player to Rename",
    order = 1,
    width = "double",
    values = GetRemoveValues,
    sorting = GetPlayerSorting,
    get = GetTempRenameSelect,
    set = SetTempRenameSelect,
}

local renameNewInputOpt = {
    type = "input",
    name = "New Name (Name-Realm)",
    order = 2,
    width = "normal",
    get = GetTempRenameNew,
    set = SetTempRenameNew,
}

local renameBtnOpt = {
    type = "execute",
    name = "Rename",
    order = 3,
    func = RenamePlayerAction,
}

local removeSelectOpt = {
    type = "select",
    name = "Select Player to Remove",
    order = 1,
    width = "double",
    values = GetRemoveValues,
    sorting = GetPlayerSorting,
    get = GetTempRemove,
    set = SetTempRemove,
}

local removeBtnOpt = {
    type = "execute",
    name = "Remove",
    order = 2,
    func = RemovePlayer,
}

local rosterListOpt = {
    type = "description",
    name = GetRosterText,
    order = 1,
}

function RosterSettings:OnInitialize()
    self.tempName = ""
    self.tempIsAlt = false
    self.tempIsOfficer = false
    self.tempMain = nil
    self.tempRemove = nil
    self.tempOfficerSelect = nil
    self.tempRenameSelect = nil
    self.tempRenameNew = ""
end

function RosterSettings:GetManageGroupOptions()
    local opts = {
        type = "group",
        name = "Manage Roster",
        order = 1,
        inline = true,
        args = {}
    }
    local args = opts.args
    args.addPlayer = addPlayerOpt
    args.isAlt = isAltOpt
    args.isOfficer = isOfficerOpt
    args.targetMain = targetMainOpt
    args.saveBtn = saveBtnOpt
    return opts
end

function RosterSettings:GetOfficerGroupOptions()
    local opts = {
        type = "group",
        name = "Manage Officers",
        order = 1.5,
        inline = true,
        args = {}
    }
    local args = opts.args
    args.officerSelect = officerSelectOpt
    args.officerToggle = officerToggleOpt
    return opts
end

function RosterSettings:GetRenameGroupOptions()
    local opts = {
        type = "group",
        name = "Rename Player",
        order = 1.8,
        inline = true,
        args = {}
    }
    local args = opts.args
    args.renameSelect = renameSelectOpt
    args.renameNewName = renameNewInputOpt
    args.renameBtn = renameBtnOpt
    return opts
end

function RosterSettings:GetRemoveGroupOptions()
    local opts = {
        type = "group",
        name = "Remove Player",
        order = 2,
        inline = true,
        args = {}
    }
    local args = opts.args
    args.removeSelect = removeSelectOpt
    args.removeBtn = removeBtnOpt
    return opts
end

function RosterSettings:GetDisplayGroupOptions()
    local opts = {
        type = "group",
        name = "Current Roster",
        order = 3,
        inline = true,
        args = {}
    }
    local args = opts.args
    args.rosterList = rosterListOpt
    return opts
end

local GetUnassignedButtonText = function()
    local unassigned = DesolateLootcouncil.API:GetUnassignedPlayers()
    local count = #unassigned
    if count > 0 then
        return string.format("Review Unassigned Players (|cffffd700%d Pending|r)", count)
    end
    return "Review Unassigned Players (0)"
end

local reviewUnassignedOpt = {
    type = "execute",
    name = GetUnassignedButtonText,
    desc = "Open the Unassigned Players Review window to assign detected raid members as Mains or Alts.",
    order = 1,
    width = "full",
    func = function()
        local win = DesolateLootcouncil:GetModule("UI_UnassignedPlayers", true)
        if win and win.ShowUnassignedWindow then
            win:ShowUnassignedWindow()
        end
    end,
}

function RosterSettings:GetUnassignedGroupOptions()
    local opts = {
        type = "group",
        name = "Unassigned Players",
        order = 0.5,
        inline = true,
        args = {}
    }
    opts.args.reviewBtn = reviewUnassignedOpt
    return opts
end

function RosterSettings:GetOptions()
    return {
        name = "Roster",
        type = "group",
        order = 2,
        args = {
            unassignedGroup = self:GetUnassignedGroupOptions(),
            manageGroup = self:GetManageGroupOptions(),
            officerGroup = self:GetOfficerGroupOptions(),
            renameGroup = self:GetRenameGroupOptions(),
            removeGroup = self:GetRemoveGroupOptions(),
            displayGroup = self:GetDisplayGroupOptions()
        }
    }
end
