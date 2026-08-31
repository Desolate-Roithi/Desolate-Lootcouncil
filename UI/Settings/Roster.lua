local _, AT = ...
if AT.abortLoad then return end

---@class UI_RosterSettings : AceModule
local RosterSettings = DesolateLootcouncil:NewModule("UI_RosterSettings")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local GetManageSelect = function()
    return RosterSettings.tempManageSelect or RosterSettings.tempRemove or RosterSettings.tempOfficerSelect or RosterSettings.tempRenameSelect
end

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
    local allMains = DesolateLootcouncil.API:GetMainRosterList()
    local target = GetManageSelect()
    if not target then return allMains end

    local filtered = {}
    for k, v in pairs(allMains) do
        if not DesolateLootcouncil:SmartCompare(k, target) and not DesolateLootcouncil:SmartCompare(v, target) then
            filtered[k] = v
        end
    end
    return filtered
end

local GetTempMain = function()
    return RosterSettings.tempMain
end

local SetTempMain = function(info, val)
    RosterSettings.tempMain = val
end

local GetTempIsOfficer = function()
    return RosterSettings.tempIsOfficer
end

local SetTempIsOfficer = function(info, val)
    RosterSettings.tempIsOfficer = val
end

local SavePlayer = function()
    local name = RosterSettings.tempName
    if not name or name == "" then return end

    if RosterSettings.tempIsAlt then
        if not RosterSettings.tempMain then
            DesolateLootcouncil:Print(L["Please select a Main character."])
            return
        end
        if DesolateLootcouncil:SmartCompare(name, RosterSettings.tempMain) then
            DesolateLootcouncil:Print(L["A character cannot be linked as an alt of itself."])
            return
        end
        local ok = DesolateLootcouncil.API:AddAlt(name, RosterSettings.tempMain)
        if ok then
            RosterSettings.tempName = ""
            RosterSettings.tempMain = nil
            RosterSettings.tempIsAlt = false
            RosterSettings.tempIsOfficer = false
        end
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

-- Unified Manage Player Actions
local SetManageSelect = function(info, val)
    RosterSettings.tempManageSelect = val
    RosterSettings.tempRemove = val
    RosterSettings.tempOfficerSelect = val
    RosterSettings.tempRenameSelect = val
    RosterSettings.tempManageLinkMain = nil
    RosterSettings.tempRenameNew = ""
end

local GetManageOfficerToggle = function()
    local target = GetManageSelect()
    if not target then return false end
    local db = DesolateLootcouncil.db.profile
    if db.MainRoster and type(db.MainRoster[target]) == "table" then
        return db.MainRoster[target].isOfficer == true
    end
    return false
end

local SetManageOfficerToggle = function(info, checked)
    local target = GetManageSelect()
    if target then
        DesolateLootcouncil.API:SetOfficer(target, checked)
    end
end

local GetManageLinkMain = function()
    return RosterSettings.tempManageLinkMain
end

local SetManageLinkMain = function(info, val)
    RosterSettings.tempManageLinkMain = val
end

local LinkSelectedAsAltAction = function()
    local target = GetManageSelect()
    local main = RosterSettings.tempManageLinkMain
    if not target or not main then
        DesolateLootcouncil:Print(L["Please select both a player and a target Main character."])
        return
    end
    if DesolateLootcouncil:SmartCompare(target, main) then
        DesolateLootcouncil:Print(L["A character cannot be linked as an alt of itself."])
        return
    end
    local ok = DesolateLootcouncil.API:AddAlt(target, main)
    if ok then
        DesolateLootcouncil:Print(string.format(L["Linked '%s' as an alt of '%s'."], DesolateLootcouncil:Ambiguate(target), DesolateLootcouncil:Ambiguate(main)))
        RosterSettings.tempManageLinkMain = nil
        SetManageSelect(nil, target)
    end
end

local PromoteSelectedAltAction = function()
    local target = GetManageSelect()
    if not target then return end
    local ok = DesolateLootcouncil.API:AddMain(target)
    if ok then
        DesolateLootcouncil:Print(string.format(L["Promoted '%s' to Main character."], DesolateLootcouncil:Ambiguate(target)))
        SetManageSelect(nil, target)
    end
end

local RenameSelectedAction = function()
    local oldName = GetManageSelect()
    local newName = RosterSettings.tempRenameNew
    if oldName and newName and newName ~= "" then
        local ok = DesolateLootcouncil.API:RenamePlayer(oldName, newName)
        if ok then
            SetManageSelect(nil, newName)
            RosterSettings.tempRenameNew = ""
        end
    end
end

local RemoveSelectedAction = function()
    local target = GetManageSelect()
    if target then
        DesolateLootcouncil.API:RemovePlayer(target)
        SetManageSelect(nil, nil)
    end
end

local GetRosterFormattedText = function()
    local db = DesolateLootcouncil.db.profile
    if not db.MainRoster then return "|cff888888" .. L["No Roster Found."] .. "|r" end

    local sortedMains = {}
    local totalMains = 0
    local totalOfficers = 0
    local totalAlts = 0

    for name, data in pairs(db.MainRoster) do
        table.insert(sortedMains, name)
        totalMains = totalMains + 1
        if type(data) == "table" and data.isOfficer then
            totalOfficers = totalOfficers + 1
        end
    end
    table.sort(sortedMains, function(a, b) return a:lower() < b:lower() end)

    local mainToAlts = {}
    if db.playerRoster and db.playerRoster.alts then
        for alt, parent in pairs(db.playerRoster.alts) do
            if not DesolateLootcouncil:SmartCompare(alt, parent) then
                totalAlts = totalAlts + 1
                if not mainToAlts[parent] then mainToAlts[parent] = {} end
                table.insert(mainToAlts[parent], alt)
            end
        end
    end

    local lines = {}
    table.insert(lines, string.format("|cffffd700Mains:|r %d   |cff00ffffAlts:|r %d   |cffa335eeOfficers:|r %d", totalMains, totalAlts, totalOfficers))
    table.insert(lines, "|cff444444--------------------------------------------------|r")

    if totalMains == 0 then
        table.insert(lines, "|cff888888" .. L["Roster is currently empty. Add members above."] .. "|r")
        return table.concat(lines, "\n")
    end

    for _, main in ipairs(sortedMains) do
        local data = db.MainRoster[main]
        local isOfficer = type(data) == "table" and data.isOfficer
        local officerBadge = isOfficer and " |cffa335ee[Officer]|r" or ""
        local displayMain = DesolateLootcouncil:Ambiguate(main)

        table.insert(lines, string.format("• |cffffffff%s|r%s", displayMain, officerBadge))

        local alts = mainToAlts[main]
        if alts and #alts > 0 then
            table.sort(alts, function(a, b) return a:lower() < b:lower() end)
            for _, alt in ipairs(alts) do
                if not DesolateLootcouncil:SmartCompare(alt, main) then
                    local displayAlt = DesolateLootcouncil:Ambiguate(alt)
                    table.insert(lines, string.format("    |cff888888-> %s (Alt)|r", displayAlt))
                end
            end
        end
    end

    return table.concat(lines, "\n")
end

function RosterSettings:OnInitialize()
    self.tempName = ""
    self.tempIsAlt = false
    self.tempIsOfficer = false
    self.tempMain = nil
    self.tempManageSelect = nil
    self.tempManageLinkMain = nil
    self.tempRemove = nil
    self.tempOfficerSelect = nil
    self.tempRenameSelect = nil
    self.tempRenameNew = ""
end

function RosterSettings:GetUnassignedGroupOptions()
    local GetUnassignedButtonText = function()
        local unassigned = DesolateLootcouncil.API:GetUnassignedPlayers()
        local count = #unassigned
        if count > 0 then
            return string.format(L["Review Unassigned Players (|cffffd700%d Pending|r)"], count)
        end
        return L["Review Unassigned Players (0)"]
    end

    return {
        type = "group",
        name = L["Unassigned Players Queue"],
        order = 5,
        inline = true,
        args = {
            reviewBtn = {
                type = "execute",
                name = GetUnassignedButtonText,
                desc = L["Open the Unassigned Players Review window to assign detected raid members as Mains or Alts."],
                order = 1,
                width = "full",
                func = function()
                    local win = DesolateLootcouncil:GetModule("UI_UnassignedPlayers", true)
                    if win and win.ShowUnassignedWindow then
                        win:ShowUnassignedWindow()
                    end
                end,
            }
        }
    }
end

function RosterSettings:GetManageGroupOptions()
    return {
        type = "group",
        name = L["Add Raider to Roster"],
        order = 10,
        inline = true,
        args = {
            addPlayer = {
                type = "input",
                name = L["Add Player (Name-Realm)"],
                desc = L["Enter player name. Defaults to current realm if omitted."],
                order = 1,
                width = "double",
                get = GetTempName,
                set = SetTempName,
            },
            isAlt = {
                type = "toggle",
                name = L["Is Alt?"],
                desc = L["Check if this player is an alt."],
                order = 2,
                width = "half",
                get = GetTempIsAlt,
                set = SetTempIsAlt,
            },
            targetMain = {
                type = "select",
                name = L["Link to Main"],
                desc = L["Select the Main character for this Alt."],
                order = 3,
                width = "normal",
                hidden = TargetMainHidden,
                values = TargetMainValues,
                get = GetTempMain,
                set = SetTempMain,
            },
            isOfficer = {
                type = "toggle",
                name = L["Is Officer?"],
                desc = L["Grant council officer permissions to this player."],
                order = 4,
                width = "half",
                hidden = function() return RosterSettings.tempIsAlt end,
                get = GetTempIsOfficer,
                set = SetTempIsOfficer,
            },
            saveBtn = {
                type = "execute",
                name = L["Add / Save"],
                desc = L["Save this character to the raid roster."],
                order = 5,
                width = "normal",
                func = SavePlayer,
            },
        }
    }
end

function RosterSettings:GetPlayerControlGroupOptions()
    local isPlayerSelected = function() return GetManageSelect() ~= nil end
    local isSelectedMain = function()
        local target = GetManageSelect()
        if not target then return false end
        local db = DesolateLootcouncil.db.profile
        return db.MainRoster and db.MainRoster[target] ~= nil
    end

    return {
        type = "group",
        name = L["Manage Selected Player"],
        order = 20,
        inline = true,
        args = {
            manageSelect = {
                type = "select",
                name = L["Select Member to Manage"],
                desc = L["Select any Main or Alt from the roster to edit role, link as alt, rename, or remove."],
                order = 1,
                width = "double",
                values = GetRemoveValues,
                sorting = GetPlayerSorting,
                get = GetManageSelect,
                set = SetManageSelect,
            },
            manageOfficerToggle = {
                type = "toggle",
                name = L["Council Officer"],
                desc = L["Toggle council officer status and permissions for this player."],
                order = 2,
                width = "normal",
                hidden = function() return not isPlayerSelected() or not isSelectedMain() end,
                get = GetManageOfficerToggle,
                set = SetManageOfficerToggle,
            },
            managePromoteBtn = {
                type = "execute",
                name = L["Promote to Main"],
                desc = L["Promote this Alt character to an independent Main roster member."],
                order = 2.5,
                width = "normal",
                hidden = function() return not isPlayerSelected() or isSelectedMain() end,
                func = PromoteSelectedAltAction,
            },
            manageLinkMain = {
                type = "select",
                name = L["Set as Alt of Main"],
                desc = L["Choose a Main character to convert and link this character under as an Alt without retyping."],
                order = 3,
                width = "normal",
                hidden = function() return not isPlayerSelected() end,
                values = TargetMainValues,
                get = GetManageLinkMain,
                set = SetManageLinkMain,
            },
            manageLinkBtn = {
                type = "execute",
                name = L["Link as Alt"],
                desc = L["Convert this character into an alt under the selected Main."],
                order = 4,
                width = "normal",
                disabled = function() return not RosterSettings.tempManageLinkMain end,
                hidden = function() return not isPlayerSelected() end,
                func = LinkSelectedAsAltAction,
            },
            manageRenameNew = {
                type = "input",
                name = L["Rename to (Name-Realm)"],
                desc = L["Enter new name to cascade across roster, priority lists, and history logs."],
                order = 5,
                width = "normal",
                hidden = function() return not isPlayerSelected() end,
                get = function() return RosterSettings.tempRenameNew or "" end,
                set = function(_, val) RosterSettings.tempRenameNew = val end,
            },
            manageRenameBtn = {
                type = "execute",
                name = L["Rename Player"],
                desc = L["Apply cascading rename for this member."],
                order = 6,
                width = "normal",
                disabled = function() return not RosterSettings.tempRenameNew or RosterSettings.tempRenameNew == "" end,
                hidden = function() return not isPlayerSelected() end,
                func = RenameSelectedAction,
            },
            manageRemoveBtn = {
                type = "execute",
                name = L["Remove Member"],
                desc = L["Permanently remove this member from the roster and priority lists."],
                order = 7,
                width = "normal",
                hidden = function() return not isPlayerSelected() end,
                confirm = true,
                confirmText = "Are you sure you want to remove this player from the roster?",
                func = RemoveSelectedAction,
            },
        }
    }
end

-- Backward Compatibility Wrappers for Legacy Tests (Hidden from in-game UI to prevent duplication)
function RosterSettings:GetOfficerGroupOptions()
    return {
        type = "group",
        name = "Manage Officers",
        order = 21,
        inline = true,
        hidden = true,
        args = {
            officerSelect = {
                type = "select",
                name = "Select Player to Update",
                order = 1,
                width = "double",
                values = TargetMainValues,
                get = GetManageSelect,
                set = SetManageSelect,
            },
            officerToggle = {
                type = "toggle",
                name = "Is Officer?",
                order = 2,
                get = GetManageOfficerToggle,
                set = SetManageOfficerToggle,
            }
        }
    }
end

function RosterSettings:GetRenameGroupOptions()
    return {
        type = "group",
        name = "Rename Player",
        order = 22,
        inline = true,
        hidden = true,
        args = {
            renameSelect = {
                type = "select",
                name = "Select Player to Rename",
                order = 1,
                width = "double",
                values = GetRemoveValues,
                sorting = GetPlayerSorting,
                get = GetManageSelect,
                set = SetManageSelect,
            },
            renameNewName = {
                type = "input",
                name = "New Name (Name-Realm)",
                order = 2,
                width = "normal",
                get = function() return RosterSettings.tempRenameNew or "" end,
                set = function(_, val) RosterSettings.tempRenameNew = val end,
            },
            renameBtn = {
                type = "execute",
                name = "Rename",
                order = 3,
                func = RenameSelectedAction,
            }
        }
    }
end

function RosterSettings:GetRemoveGroupOptions()
    return {
        type = "group",
        name = "Remove Player",
        order = 23,
        inline = true,
        hidden = true,
        args = {
            removeSelect = {
                type = "select",
                name = "Select Player to Remove",
                order = 1,
                width = "double",
                values = GetRemoveValues,
                sorting = GetPlayerSorting,
                get = GetManageSelect,
                set = SetManageSelect,
            },
            removeBtn = {
                type = "execute",
                name = "Remove",
                order = 2,
                func = RemoveSelectedAction,
            }
        }
    }
end

function RosterSettings:GetDisplayGroupOptions()
    return {
        type = "group",
        name = L["Current Roster & Linked Alts"],
        order = 30,
        inline = true,
        args = {
            rosterList = {
                type = "description",
                name = GetRosterFormattedText,
                order = 1,
                fontSize = "medium",
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
            unassignedGroup   = self:GetUnassignedGroupOptions(),
            manageGroup       = self:GetManageGroupOptions(),
            playerControlGroup = self:GetPlayerControlGroupOptions(),
            officerGroup      = self:GetOfficerGroupOptions(),
            renameGroup       = self:GetRenameGroupOptions(),
            removeGroup       = self:GetRemoveGroupOptions(),
            displayGroup      = self:GetDisplayGroupOptions()
        }
    }
end
