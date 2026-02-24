---@class ItemSettings : AceModule
local ItemSettings = DesolateLootcouncil:NewModule("ItemSettings")

function ItemSettings:GetItemOptions()
    local db = DesolateLootcouncil.db.profile

    local args = {
        desc = {
            type = "description",
            name = "Manage your priority lists and assigned items in the dedicated window.",
            order = 1,
        },
        openBtn = {
            type = "execute",
            name = "Open Item Manager",
            desc = "Open the standalone Item Manager window to add or remove items from priority lists.",
            width = 1.5,
            order = 2,
            func = function()
                local Manager = DesolateLootcouncil:GetModule("UI_ItemManager")
                if Manager then
                    Manager:ShowItemManagerWindow()
                end
                LibStub("AceConfigDialog-3.0"):Close("DesolateLootcouncil") -- Close options to focus on manager
            end,
        }
    }

    return {
        name = "Item Lists",
        type = "group",
        order = 5,
        args = args
    }
end
