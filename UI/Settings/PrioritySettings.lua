local _, AT = ...
if AT.abortLoad then return end

---@class UI_PrioritySettings : AceModule
local PrioritySettings = DesolateLootcouncil:NewModule("UI_PrioritySettings")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function PrioritySettings:OnInitialize()
    self.tempListName = ""
    self.tempSelectedListIndex = nil
    self.tempRenameVal = ""
end

function PrioritySettings:GetCreateGroupOptions()
    local API = DesolateLootcouncil.API

    return {
        type = "group",
        name = L["Create New List"],
        inline = true,
        order = 1,
        args = {
            newListName = {
                type = "input",
                name = L["New List Name"],
                desc = L["Enter name for the new priority category."],
                order = 1,
                width = "double",
                get = function() return self.tempListName end,
                set = function(_, val) self.tempListName = val end,
            },
            createBtn = {
                type = "execute",
                name = L["Create List"],
                desc = L["Create the priority list and initialize it for all roster members."],
                order = 2,
                width = "normal",
                func = function()
                    if self.tempListName and self.tempListName ~= "" then
                        API:AddPriorityList(self.tempListName)
                        self.tempListName = ""
                    end
                end,
            }
        }
    }
end

function PrioritySettings:GetManageListsGroupOptions()
    local API = DesolateLootcouncil.API

    return {
        type = "group",
        name = L["Manage Existing Lists"],
        inline = true,
        order = 2,
        args = {
            selectList = {
                type = "select",
                name = L["Select List to Edit"],
                desc = L["Choose a priority list to rename or remove."],
                order = 1,
                width = "normal",
                values = function()
                    local names = API:GetPriorityListNames()
                    local options = {}
                    for i, v in ipairs(names) do options[i] = v end
                    return options
                end,
                get = function() return self.tempSelectedListIndex end,
                set = function(_, val) self.tempSelectedListIndex = val end,
            },
            renameInput = {
                type = "input",
                name = L["Rename List"],
                desc = L["Enter the new title for this priority list."],
                order = 2,
                width = "normal",
                get = function() return self.tempRenameVal end,
                set = function(_, val) self.tempRenameVal = val end,
            },
            renameBtn = {
                type = "execute",
                name = L["Rename (Confirm)"],
                desc = L["Save the new name for this priority list."],
                order = 3,
                width = "normal",
                disabled = function() return not self.tempSelectedListIndex or not self.tempRenameVal or self.tempRenameVal == "" end,
                func = function()
                    if self.tempSelectedListIndex and self.tempRenameVal ~= "" then
                        API:RenamePriorityList(self.tempSelectedListIndex, self.tempRenameVal)
                        self.tempRenameVal = ""
                        self.tempSelectedListIndex = nil
                    end
                end
            },
            deleteBtn = {
                type = "execute",
                name = L["Delete List"],
                desc = L["Permanently delete this priority list."],
                order = 4,
                width = "normal",
                disabled = function() return not self.tempSelectedListIndex end,
                confirm = true,
                confirmText = "Are you sure you want to delete this list?",
                func = function()
                    if self.tempSelectedListIndex then
                        API:RemovePriorityList(self.tempSelectedListIndex)
                        self.tempSelectedListIndex = nil
                        self.tempRenameVal = ""
                    end
                end,
            }
        }
    }
end

function PrioritySettings:GetSeasonGroupOptions()
    local API = DesolateLootcouncil.API

    return {
        type = "group",
        name = L["Season Management & Actions"],
        inline = true,
        order = 1,
        args = {
            shuffleBtn = {
                type = "execute",
                name = L["Shuffle / Start Season"],
                desc = L["Randomize player order across all priority lists and clear historic session logs."],
                order = 1,
                width = "normal",
                confirm = true,
                confirmText = "This will randomize ALL priority lists and clear history. Continue?",
                func = function()
                    API:ShuffleLists()
                end,
            },
            syncBtn = {
                type = "execute",
                name = L["Sync Missing Players"],
                desc = L["Append any unranked roster members to the bottom of all priority lists."],
                order = 2,
                width = "normal",
                func = function()
                    API:SyncMissingPlayers()
                end,
            },
            historyBtn = {
                type = "execute",
                name = L["View History Log"],
                desc = L["Open the Audit & Priority Ledger history window."],
                order = 3,
                width = "normal",
                func = function()
                    local LogUI = DesolateLootcouncil:GetModule("UI_PriorityLogHistory", true)
                    if LogUI then
                        LogUI:ShowLogWindow()
                    else
                        DesolateLootcouncil:Print("LogViewer module not loaded.")
                    end
                end,
            }
        }
    }
end

function PrioritySettings:GetViewsGroupOptions()
    return {
        type = "group",
        name = L["Priority Category Overviews"],
        inline = true,
        order = 2,
        args = self:GetPriorityListViewOptions()
    }
end

function PrioritySettings:GetOptions()
    return {
        name = "Priority Lists",
        type = "group",
        childGroups = "tab",
        order = 3,
        args = {
            configTab = {
                type = "group",
                name = L["Configuration"],
                order = 1,
                args = {
                    createGroup = self:GetCreateGroupOptions(),
                    manageGroup = self:GetManageListsGroupOptions()
                }
            },
            manageTab = {
                type = "group",
                name = L["Management & Views"],
                order = 2,
                args = {
                    desc = {
                        type = "description",
                        name = L["Manage seasonal Priority Lists. Use the 'Sync' button to add new roster members without re-shuffling."],
                        order = 0,
                    },
                    seasonGroup = self:GetSeasonGroupOptions(),
                    viewsGroup = self:GetViewsGroupOptions()
                }
            }
        }
    }
end

function PrioritySettings:GetOverrideFunc(listName, names)
    return function()
        local OverrideUI = DesolateLootcouncil:GetModule("UI_PriorityOverride", true)
        if OverrideUI and OverrideUI.ShowPriorityOverrideWindow then
            local idx = nil
            for k, v in ipairs(names) do
                if v == listName then idx = k; break end
            end
            if idx then
                OverrideUI:ShowPriorityOverrideWindow(idx)
            else
                DesolateLootcouncil:Print(L["Error parsing list index."])
            end
        else
            DesolateLootcouncil:Print(L["UI Module 'PriorityOverride' not available."])
        end
    end
end

function PrioritySettings:GetPriorityListViewOptions()
    local API = DesolateLootcouncil.API
    local args = {}
    local names = API:GetPriorityListNames()
    local dbLists = API:GetPriorityLists()

    if not self.showContentMap then self.showContentMap = {} end

    for i, listName in ipairs(names) do
        local listObj = nil
        for _, l in ipairs(dbLists) do
            if l.name == listName then listObj = l; break end
        end

        local playerCount = (listObj and listObj.players) and #listObj.players or 0
        local headerTitle = string.format("%s  |cff888888(%d Raiders)|r", API:GetLocalizedListName(listName), playerCount)

        args["grp_" .. i] = {
            type = "group",
            name = headerTitle,
            inline = true,
            order = i,
            args = {
                showBtn = {
                    type = "execute",
                    name = self.showContentMap[listName] and L["Hide Ranking"] or L["Show Ranking"],
                    desc = L["Toggle the inline ranking table for this priority list."],
                    order = 1,
                    width = "normal",
                    func = function() self.showContentMap[listName] = not self.showContentMap[listName] end,
                },
                manualBtn = {
                    type = "execute",
                    name = L["Manual Override (Drag & Drop)"],
                    desc = L["Open the interactive visual drag & drop override window for this priority list."],
                    order = 2,
                    width = "double",
                    func = self:GetOverrideFunc(listName, names),
                }
            }
        }

        if self.showContentMap[listName] then
            if listObj and listObj.players and #listObj.players > 0 then
                local contentStr = ""
                for rank, player in ipairs(listObj.players) do
                    contentStr = contentStr .. string.format("|cffeda55fRank #%d:|r %s\n", rank, API:GetDisplayName(player))
                end

                args["grp_" .. i].args.contentDisplay = {
                    type = "description",
                    name = contentStr,
                    order = 1.5,
                    fontSize = "medium",
                }
            else
                args["grp_" .. i].args.contentDisplay = {
                    type = "description",
                    name = "|cff888888" .. L["No players found in this list."] .. "|r",
                    order = 1.5,
                }
            end
        end
    end

    return args
end
