local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
---@type ItemSettings
local ItemSettings = DesolateLootcouncil:NewModule("ItemSettings")

---@class ItemSettings : AceModule
---@field GetItemOptions function
---@field selectedListIndex number
---@field itemInput string

ItemSettings.selectedListIndex = 1
ItemSettings.itemInput = ""

function ItemSettings:GetItemOptions()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db then return {} end
    local args = {}

    -- 1. List Selector
    local listOptions = {}
    local priorityLists = db.PriorityLists or {}
    for i, list in ipairs(priorityLists) do
        listOptions[i] = list.name
    end

    args.headerSelect = { type = "header", name = "Select List to Configure", order = 1 }
    args.selectList = {
        type = "select",
        name = "Target List",
        values = listOptions,
        order = 2,
        style = "dropdown",
        width = "double",
        set = function(_, val) ItemSettings.selectedListIndex = val end,
        get = function() return ItemSettings.selectedListIndex end,
    }

    -- 2. Add Item Input
    args.headerAdd = { type = "header", name = "Add Item", order = 10 }
    args.inputItem = {
        type = "input",
        name = "Item Link or ID",
        desc = "Paste an item link or type an item ID.",
        order = 11,
        width = "double",
        set = function(_, val) ItemSettings.itemInput = val end,
        get = function() return ItemSettings.itemInput end,
    }
    args.btnAdd = {
        type = "execute",
        name = "Add Item",
        order = 12,
        func = function()
            if ItemSettings.itemInput and ItemSettings.itemInput ~= "" then
                DesolateLootcouncil:AddItemToList(ItemSettings.itemInput, ItemSettings.selectedListIndex)
                ItemSettings.itemInput = ""
            end
        end,
    }

    -- 3. Display Items
    args.headerItems = { type = "header", name = "Assigned Items", order = 20 }

    local currentList = priorityLists[self.selectedListIndex]
    if currentList and currentList.items then
        local index = 0
        for itemID, _ in pairs(currentList.items) do
            index = index + 1
            local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
            if not name then
                name = "Loading [" .. itemID .. "]..."
                -- Trigger a silent cache query
                -- The UI will refresh on next update/event, or user can click refresh
            end

            args["item_" .. itemID] = {
                type = "group",
                name = name,
                inline = true,
                order = 20 + index,
                args = {
                    icon = {
                        type = "description",
                        name = " ",
                        image = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                        order = 1,
                        width = "half",
                    },
                    desc = {
                        type = "description",
                        name = link or name,
                        order = 2,
                        width = "double",
                    },
                    btnDelete = {
                        type = "execute",
                        name = "Remove",
                        order = 3,
                        width = "half",
                        func = function() DesolateLootcouncil:RemoveItemFromList(self.selectedListIndex, itemID) end,
                    }
                }
            }
        end
    else
        args.noItems = {
            type = "description",
            name = "No items assigned to this list.",
            order = 21,
        }
    end

    return {
        name = "Item Lists",
        type = "group",
        order = 4, -- After Priority
        args = args
    }
end
