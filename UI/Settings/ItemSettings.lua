local _, AT = ...
if AT.abortLoad then return end

---@class UI_ItemSettings : AceModule
local ItemSettings = DesolateLootcouncil:NewModule("UI_ItemSettings")

function ItemSettings:GetItemOptions()
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
                local Manager = DesolateLootcouncil:GetModule("UI_ItemManager", true)
                if Manager then
                    Manager:ShowItemManagerWindow()
                end
                local settingsFrame = DesolateLootcouncil:GetModule("UI_Settings", true)
                if settingsFrame and settingsFrame.settingsFrame then
                    settingsFrame.settingsFrame:Hide()
                end
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
