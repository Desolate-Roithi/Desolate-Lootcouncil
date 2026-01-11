---@class ItemSettings : AceModule
local ItemSettings = DesolateLootcouncil:NewModule("ItemSettings")

function ItemSettings:GetItemOptions()
    return {
        name = "Items",
        type = "group",
        order = 3,
        args = {
            header = {
                type = "header",
                name = "Item Categorization",
                order = 0,
            },
            addItem = {
                type = "group",
                inline = true,
                name = "Manual Categorization",
                args = {
                    inputLink = {
                        type = "input",
                        name = "Item Name/Link/ID",
                        order = 1,
                        set = function(info, val) self.tempItem = val end,
                        get = function(info) return self.tempItem end,
                    },
                    targetList = {
                        type = "select",
                        name = "Target List",
                        order = 2,
                        values = function() return DesolateLootcouncil:GetModule("Priority"):GetPriorityListNames() end,
                        set = function(info, val)
                            if self.tempItem then
                                DesolateLootcouncil:GetModule("Loot"):AddItemToList(self.tempItem, val)
                                self.tempItem = nil
                            end
                        end,
                    }
                }
            },
        }
    }
end
