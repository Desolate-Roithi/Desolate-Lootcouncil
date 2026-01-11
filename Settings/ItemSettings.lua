---@class ItemSettings : AceModule
local ItemSettings = DesolateLootcouncil:NewModule("ItemSettings")

function ItemSettings:GetItemOptions()
    local db = DesolateLootcouncil.db.profile

    local args = {
        header = {
            type = "header",
            name = "Manual Categorization",
            order = 1,
        },
        inputGroup = {
            type = "group",
            inline = true,
            name = "", -- No title for the group itself to avoid duplication
            order = 2,
            args = {
                inputLink = {
                    type = "input",
                    name = "Item Name/Link/ID",
                    desc = "Paste an item link or ID here.",
                    width = 1.6, -- Take up ~50-60%
                    order = 1,
                    set = function(info, val) self.tempItem = val end,
                    get = function(info) return self.tempItem end,
                },
                targetList = {
                    type = "select",
                    name = "Target List",
                    desc = "Select which priority list this item belongs to.",
                    width = 1.0, -- Take up ~30%
                    order = 2,
                    values = function()
                        local names = {}
                        local listNames = DesolateLootcouncil:GetModule("Priority"):GetPriorityListNames()
                        for i, name in ipairs(listNames) do
                            names[i] = name
                        end
                        return names
                    end,
                    set = function(info, val) self.tempList = val end,
                    get = function(info) return self.tempList end,
                },
                addBtn = {
                    type = "execute",
                    name = "Add",
                    desc = "Add item to the selected list.",
                    width = 0.4, -- Compact button
                    order = 3,
                    func = function()
                        if self.tempItem and self.tempList then
                            DesolateLootcouncil:GetModule("Loot"):AddItemToList(self.tempItem, self.tempList)
                            self.tempItem = nil
                            LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
                        end
                    end,
                }
            }
        },
        listHeader = {
            type = "header",
            name = "Assigned Items",
            order = 10,
        },
        viewList = {
            type = "select",
            name = "Select List to View",
            order = 11,
            values = function()
                local names = {}
                local listNames = DesolateLootcouncil:GetModule("Priority"):GetPriorityListNames()
                for i, name in ipairs(listNames) do
                    names[i] = name
                end
                return names
            end,
            set = function(info, val)
                self.viewListKey = val
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end,
            get = function(info)
                -- Default to first list if none selected
                if not self.viewListKey then
                    -- Default to 1 (first list)
                    self.viewListKey = 1
                end
                return self.viewListKey
            end,
            width = "full",
        }
    }

    -- Dynamic List of Assigned Items
    local index = 20
    if db.PriorityLists and self.viewListKey then
        for listIndex, list in ipairs(db.PriorityLists) do
            -- Filter: Only show items for the selected list index
            if listIndex == self.viewListKey and list.items then
                -- list.items is { [itemID] = true, ... }
                for itemID, _ in pairs(list.items) do
                    -- Item Name/Link Fetching
                    local itemName, itemLink = GetItemInfo(itemID)
                    if not itemName then itemName = "ID: " .. itemID end

                    args["item_" .. listIndex .. "_" .. itemID] = {
                        type = "group",
                        inline = true,
                        name = "",
                        order = index,
                        args = {
                            icon = {
                                type = "description",
                                name = " ",
                                image = GetItemIcon(itemID),
                                imageWidth = 24,
                                imageHeight = 24,
                                width = 0.15,
                                order = 1,
                            },
                            info = {
                                type = "description",
                                name = (itemLink or itemName),
                                fontSize = "medium",
                                width = 1.8,
                                order = 2,
                            },
                            remove = {
                                type = "execute",
                                name = "Remove",
                                width = 0.5,
                                order = 3,
                                func = function()
                                    list.items[itemID] = nil -- Remove using map key
                                    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
                                end,
                            }
                        }
                    }
                    index = index + 1
                end
            end
        end
    end

    if index == 20 then
        args.noItems = {
            type = "description",
            name = "\nNo items assigned to any priority list yet.",
            fontSize = "medium",
            order = 20,
        }
    end

    return {
        name = "Item Lists",
        type = "group",
        order = 5,
        args = args
    }
end
