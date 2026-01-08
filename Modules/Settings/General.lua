---@class GeneralSettings : AceModule
---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
local GeneralSettings = DesolateLootcouncil:NewModule("GeneralSettings") --[[@as GeneralSettings]]

function GeneralSettings:GetGeneralOptions()
    return {
        name = "General",
        type = "group",
        order = 1,
        args = {
            lootMaster = {
                type = "input",
                name = "Loot Master Name",
                order = 1,
                get = function() return DesolateLootcouncil.db.profile.configuredLM end,
                set = function(_, val)
                    DesolateLootcouncil.db.profile.configuredLM = val
                    DesolateLootcouncil:UpdateLootMasterStatus()
                end,
            },
            minQuality = {
                type = "select",
                name = "Min Loot Quality",
                order = 2,
                values = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" },
                get = function() return DesolateLootcouncil.db.profile.minLootQuality end,
                set = function(_, val) DesolateLootcouncil.db.profile.minLootQuality = val end,
            },
            enableAutoLoot = {
                type = "toggle",
                name = "Enable Automated Looting",
                desc =
                "LM: Auto-acquires items (Need > Greed > Transmog > DE). Aborts on BoP Collectables. Raiders: Auto-Pass.",
                order = 3,
                width = "full",
                get = function() return DesolateLootcouncil.db.profile.enableAutoLoot end,
                set = function(_, val) DesolateLootcouncil.db.profile.enableAutoLoot = val end,
            },
        }
    }
end
