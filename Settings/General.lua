local _, AT = ...
if AT.abortLoad then return end

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
            configuredLM = {
                type = "input",
                name = "Loot Master",
                desc = "Name of the Loot Master (PlayerName)",
                order = 1,
                width = "normal",
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
                order = 2,
                width = "normal",
                values = {
                    [0] = "Poor (Grey)",
                    [1] = "Common (White)",
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
                name = "Enable Automated Rolling / Passing",
                desc = "Automatically roll on items above threshold (LM) or pass (Raiders).",
                order = 3,
                width = "full",
                get = function(info) return DesolateLootcouncil.db.profile.enableAutoLoot end,
                set = function(info, val) DesolateLootcouncil.db.profile.enableAutoLoot = val end,
            },
            debugMode = {
                type = "toggle",
                name = "Enable Debug Mode",
                desc = "Show debug messages in chat.",
                order = 4,
                width = "full",
                get = function(info) return DesolateLootcouncil.db.profile.debugMode end,
                set = function(info, val) DesolateLootcouncil.db.profile.debugMode = val end,
            },
            resetLayout = {
                type = "execute",
                name = "Reset Window Layout",
                desc = "Reset the positions of all addon windows to their default center status.",
                order = 5,
                width = "normal",
                func = function()
                    if DesolateLootcouncil.Persistence and DesolateLootcouncil.Persistence.ResetPositions then
                        DesolateLootcouncil.Persistence:ResetPositions()
                        DesolateLootcouncil:Print("All window positions have been reset.")
                    else
                        DesolateLootcouncil:Print("Persistence module not loaded.")
                    end
                end,
            },
            -- Bug 4: History link in settings so all players can open it
            openHistory = {
                type = "execute",
                name = "Loot History",
                desc = "Open the Loot History window showing all awarded items.",
                order = 6,
                width = "normal",
                func = function()
                    local UI = DesolateLootcouncil:GetModule("UI_History")
                    if UI then UI:ShowHistoryWindow() end
                end,
            }
        }
    }
end
