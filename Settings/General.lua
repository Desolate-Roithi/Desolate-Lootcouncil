---@class GeneralSettings : AceModule
local GeneralSettings = DesolateLootcouncil:NewModule("GeneralSettings")

function GeneralSettings:GetGeneralOptions()
    return {
        name = "General",
        type = "group",
        order = 1,
        args = {
            header = {
                type = "header",
                name = "General Configuration",
                order = 0,
            },
            debugMode = {
                type = "toggle",
                name = "Debug Mode",
                desc = "Show debug messages in chat.",
                order = 1,
                get = function(info) return DesolateLootcouncil.db.profile.debugMode end,
                set = function(info, val) DesolateLootcouncil.db.profile.debugMode = val end,
            },
            verboseMode = {
                type = "toggle",
                name = "Verbose Logging",
                desc = "Show detailed logs.",
                order = 2,
                get = function(info) return DesolateLootcouncil.db.profile.verboseMode end,
                set = function(info, val) DesolateLootcouncil.db.profile.verboseMode = val end,
            },
            configuredLM = {
                type = "input",
                name = "Loot Master",
                desc = "Name of the Loot Master (PlayerName)",
                order = 3,
                get = function(info) return DesolateLootcouncil.db.profile.configuredLM end,
                set = function(info, val)
                    DesolateLootcouncil.db.profile.configuredLM = val
                    DesolateLootcouncil:UpdateLootMasterStatus()
                end,
            },
            minLootQuality = {
                type = "select",
                name = "Minimum Loot Quality",
                desc = "Threshold for auto-looting/detecting items.",
                order = 4,
                values = {
                    [2] = "Uncommon (Green)",
                    [3] = "Rare (Blue)",
                    [4] = "Epic (Purple)",
                    [5] = "Legendary (Orange)"
                },
                get = function(info) return DesolateLootcouncil.db.profile.minLootQuality end,
                set = function(info, val) DesolateLootcouncil.db.profile.minLootQuality = val end,
            },
            enableAutoLoot = {
                type = "toggle",
                name = "Auto Loot",
                desc = "Automatically loot items above threshold (LM) or pass (Raiders).",
                order = 5,
                get = function(info) return DesolateLootcouncil.db.profile.enableAutoLoot end,
                set = function(info, val) DesolateLootcouncil.db.profile.enableAutoLoot = val end,
            },
        }
    }
end
