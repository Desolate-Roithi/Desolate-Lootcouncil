---@class PrioritySettings : AceModule
local PrioritySettings = DesolateLootcouncil:NewModule("PrioritySettings")

function PrioritySettings:OnInitialize()
    self.tempListName = ""
    self.tempSelectedListIndex = nil
    self.tempRenameVal = ""
end

function PrioritySettings:GetOptions()
    return {
        name = "Priority Lists",
        type = "group",
        childGroups = "tab", -- Enable Tabs
        order = 3,
        args = {
            configTab = {
                type = "group",
                name = "Configuration",
                order = 1,
                args = {
                    createGroup = {
                        type = "group",
                        name = "Create New List",
                        inline = true,
                        order = 1,
                        args = {
                            newListName = {
                                type = "input",
                                name = "New List Name",
                                order = 1,
                                width = "double",
                                get = function() return self.tempListName end,
                                set = function(info, val) self.tempListName = val end,
                            },
                            createBtn = {
                                type = "execute",
                                name = "Create List",
                                order = 2,
                                func = function()
                                    if self.tempListName and self.tempListName ~= "" then
                                        DesolateLootcouncil:GetModule("Priority"):AddPriorityList(self.tempListName)
                                        self.tempListName = ""
                                    end
                                end,
                            }
                        }
                    },
                    manageGroup = {
                        type = "group",
                        name = "Manage Existing Lists",
                        inline = true,
                        order = 2,
                        args = {
                            selectList = {
                                type = "select",
                                name = "Select List to Edit",
                                order = 1,
                                width = "normal",
                                values = function()
                                    local names = DesolateLootcouncil:GetModule("Priority"):GetPriorityListNames()
                                    -- Map array to Key=Index Value=Name for selection
                                    local options = {}
                                    for i, v in ipairs(names) do options[i] = v end
                                    return options
                                end,
                                get = function() return self.tempSelectedListIndex end,
                                set = function(info, val) self.tempSelectedListIndex = val end,
                            },
                            renameInput = {
                                type = "input",
                                name = "Rename List",
                                order = 2,
                                width = "normal",
                                get = function() return self.tempRenameVal end,
                                set = function(info, val) self.tempRenameVal = val end,
                            },
                            renameBtn = { -- Implicitly triggered by typing?
                                -- User screenshot shows input next to select. usually renaming needs a trigger or hitting enter.
                                -- AceConfig input 'set' triggers on Enter.
                                -- Let's make it so hitting Enter on renameInput performs the rename.
                                -- But we need a button for clear action or just rely on Enter.
                                -- Wait, screenshot shows "Delete List" button below.
                                type = "execute",
                                name = "Rename (Confirm)",
                                -- hidden = true, -- Or explicit button? Let's use the input's set for now but maybe a button is safer.
                                -- Input `set` handles it. Let's add a visual button if desired or just rely on Enter.
                                -- Standard AceConfig doesn't put buttons inline easily next to inputs without widths.
                                -- Let's rely on the input set.
                                order = 2.5,
                                width = "normal",
                                func = function()
                                    if self.tempSelectedListIndex and self.tempRenameVal ~= "" then
                                        DesolateLootcouncil:GetModule("Priority"):RenamePriorityList(
                                            self.tempSelectedListIndex, self.tempRenameVal)
                                        self.tempRenameVal = ""
                                        self.tempSelectedListIndex = nil
                                    end
                                end
                            },
                            deleteBtn = {
                                type = "execute",
                                name = "Delete List",
                                order = 3,
                                width = "full",
                                confirm = true,
                                confirmText = "Are you sure you want to delete this list?",
                                func = function()
                                    if self.tempSelectedListIndex then
                                        DesolateLootcouncil:GetModule("Priority"):RemovePriorityList(self
                                            .tempSelectedListIndex)
                                        self.tempSelectedListIndex = nil
                                        self.tempRenameVal = ""
                                    end
                                end,
                            }
                        }
                    }
                }
            },
            manageTab = {
                type = "group",
                name = "Management & Views",
                order = 2,
                args = {
                    desc = {
                        type = "description",
                        name =
                        "Manage seasonal Priority Lists. Use the 'Sync' button to add new roster members without re-shuffling.",
                        order = 0,
                    },
                    seasonGroup = {
                        type = "group",
                        name = "Season Management",
                        inline = true,
                        order = 1,
                        args = {
                            shuffleBtn = {
                                type = "execute",
                                name = "Shuffle / Start Season",
                                order = 1,
                                confirm = true,
                                confirmText = "This will randomize ALL priority lists and clear history. Continute?",
                                func = function()
                                    DesolateLootcouncil:GetModule("Priority"):ShuffleLists()
                                end,
                            },
                            syncBtn = {
                                type = "execute",
                                name = "Sync Missing Players",
                                order = 2,
                                func = function()
                                    DesolateLootcouncil:GetModule("Priority"):SyncMissingPlayers()
                                end,
                            },
                            historyBtn = {
                                type = "execute",
                                name = "View History Log",
                                order = 3,
                                width = "full", -- Make it stand out or fit row? Screenshot shows roughly same width
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
                    },
                    viewsGroup = {
                        type = "group",
                        name = "Priority List Views",
                        inline = true,
                        order = 2,
                        args = self:GetPriorityListViewOptions()
                    }
                }
            }
        }
    }
end

function PrioritySettings:GetPriorityListViewOptions()
    local args = {}
    local priorityModule = DesolateLootcouncil:GetModule("Priority")
    local names = priorityModule:GetPriorityListNames()
    local db = DesolateLootcouncil.db.profile

    if not self.showContentMap then self.showContentMap = {} end

    for i, listName in ipairs(names) do
        args["grp_" .. i] = {
            type = "group",
            name = listName,
            inline = true,
            order = i,
            args = {
                showBtn = {
                    type = "execute",
                    name = self.showContentMap[listName] and "Hide Content" or "Show Content",
                    order = 1,
                    func = function()
                        self.showContentMap[listName] = not self.showContentMap[listName]
                    end,
                },
                manualBtn = {
                    type = "execute",
                    name = "Manual Override (Drag & Drop)",
                    order = 2,
                    func = function()
                        local OverrideUI = DesolateLootcouncil:GetModule("UI_PriorityOverride", true)
                        if OverrideUI and OverrideUI.ShowPriorityOverrideWindow then
                            -- Find Index
                            local idx = nil
                            for k, v in ipairs(names) do
                                if v == listName then
                                    idx = k; break
                                end
                            end

                            if idx then
                                OverrideUI:ShowPriorityOverrideWindow(idx)
                            else
                                DesolateLootcouncil:Print("Error parsing list index.")
                            end
                        else
                            DesolateLootcouncil:Print("UI Module 'PriorityOverride' not available.")
                        end
                    end,
                }
            }
        }

        -- Dynamic Content
        if self.showContentMap[listName] then
            local listObj = nil
            if db.PriorityLists then
                for _, l in ipairs(db.PriorityLists) do
                    if l.name == listName then
                        listObj = l; break
                    end
                end
            end

            if listObj and listObj.players then
                local contentStr = ""
                for rank, player in ipairs(listObj.players) do
                    -- Styling: Rank #1: PlayerName
                    contentStr = contentStr .. string.format("|cffeda55fRank #%d:|r %s\n", rank, player)
                end

                args["grp_" .. i].args.contentDisplay = {
                    type = "description",
                    name = contentStr,
                    order = 1.5, -- Between buttons
                    fontSize = "medium",
                }
            else
                args["grp_" .. i].args.contentDisplay = {
                    type = "description",
                    name = "No players found in this list.",
                    order = 1.5,
                }
            end
        end
    end

    return args
end
