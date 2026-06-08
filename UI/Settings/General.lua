local _, AT = ...
if AT.abortLoad then return end

---@class UI_GeneralSettings : AceModule
local GeneralSettings = DesolateLootcouncil:NewModule("UI_GeneralSettings")

function GeneralSettings:GetGeneralOptions()
    local API = DesolateLootcouncil.API

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
                get = function() return API:GetConfiguredLM() end,
                set = function(_, val)
                    API:SetConfiguredLM(val)
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
                get = function() return API:GetMinLootQuality() end,
                set = function(_, val) API:SetMinLootQuality(val) end,
            },
            enableAutoLoot = {
                type = "toggle",
                name = "Enable Automated Rolling / Passing",
                desc = "Automatically roll on items above threshold (LM) or pass (Raiders).",
                order = 3,
                width = "full",
                get = function() return API:GetEnableAutoLoot() end,
                set = function(_, val) API:SetEnableAutoLoot(val) end,
            },
            enableAutoTrade = {
                type = "toggle",
                name = "Enable Automated Trade Staging",
                desc = "Automatically stage awarded items in the trade window when trading the winner.",
                order = 3.5,
                width = "full",
                get = function() return API:GetEnableAutoTrade() end,
                set = function(_, val) API:SetEnableAutoTrade(val) end,
            },
            debugMode = {
                type = "toggle",
                name = "Enable Debug Mode",
                desc = "Show debug messages in chat.",
                order = 4,
                width = "full",
                get = function() return API:GetDebugMode() end,
                set = function(_, val) API:SetDebugMode(val) end,
            },
            themeHeader = {
                type = "header",
                name = "UI Theme",
                order = 7,
            },
            activeTheme = {
                type = "select",
                name = "Active Theme",
                desc = "Select the appearance of the user interface.",
                order = 8,
                width = "normal",
                values = {
                    ["Midnight"] = "Midnight (Void)",
                    ["Classic"] = "Classic Slate",
                    ["Minimalist"] = "Pure Dark (Minimal)",
                    ["Fel"] = "Emerald Fel",
                },
                get = function() return API:GetActiveTheme() end,
                set = function(_, val)
                    API:SetActiveTheme(val)
                end,
            },
            resetLayout = {
                type = "execute",
                name = "Reset Window Layout",
                desc = "Reset the positions of all addon windows to their default center status.",
                order = 5,
                width = "normal",
                func = function()
                    API:ResetWindowLayout()
                end,
            },
            openHistory = {
                type = "execute",
                name = "Loot History",
                desc = "Open the Loot History window showing all awarded items.",
                order = 6,
                width = "normal",
                func = function()
                    local UI_History = DesolateLootcouncil:GetModule("UI_History", true)
                    if UI_History then UI_History:ShowHistoryWindow() end
                end,
            },
            shareHeader = {
                type = "header",
                name = "Loot Master: Share Data",
                order = 10,
                hidden = function() return not API:IsLootMaster() end,
            },
            shareDesc = {
                type = "description",
                name = "Privately whisper Priority Lists and Roster to all Raid Assists. Regular members cannot read this data.",
                order = 11,
                hidden = function() return not API:IsLootMaster() end,
            },
            shareWithAssistsBtn = {
                type = "execute",
                name = "Share Priority & Roster with Assists",
                desc = "Sends both Priority Lists and Roster to all current raid assists via private whisper.",
                order = 12,
                width = "full",
                hidden = function() return not API:IsLootMaster() end,
                confirm = true,
                confirmText = "This will overwrite the Priority Lists and Roster on all assists' clients. Continue?",
                func = function()
                    API:ShareDataWithAssists("PRIORITY")
                    API:ShareDataWithAssists("ROSTER")
                end,
            },
            autopassHeader = {
                type = "header",
                name = "Loot Master: Autopass Settings",
                order = 20,
                hidden = function() return not API:IsLootMaster() end,
            },
            repromptAutopass = {
                type = "execute",
                name = "Re-open Autopass Choice",
                desc = "Opens the 'Enable Autopass' popup again to change the global setting for this session.",
                order = 21,
                width = "full",
                hidden = function() return not API:IsLootMaster() end,
                func = function()
                    API:RepromptAutopass()
                end,
            },
        }
    }
end
