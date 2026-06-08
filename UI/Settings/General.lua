local _, AT = ...
if AT.abortLoad then return end

---@class UI_GeneralSettings : AceModule
local GeneralSettings = DesolateLootcouncil:NewModule("UI_GeneralSettings")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local selectedHandoverTarget = nil

local function GetOfficerNamesInRaid()
    local list = {}
    local db = DesolateLootcouncil.db.profile
    local MainRoster = db.MainRoster or {}
    for name, data in pairs(MainRoster) do
        if data.isOfficer and DesolateLootcouncil:IsUnitInRaid(name) and not DesolateLootcouncil:SmartCompare(name, "player") then
            list[name] = DesolateLootcouncil:GetDisplayName(name)
        end
    end
    return list
end

local function CanHandover()
    local Session = DesolateLootcouncil:GetModule("Session")
    if not Session.clientLootList or #Session.clientLootList == 0 then
        return true
    end
    local db = DesolateLootcouncil.db.profile
    local bidding = db.session and db.session.bidding or {}
    for _, item in ipairs(bidding) do
        local guid = item.sourceGUID or item.link
        if not Session.closedItems or not Session.closedItems[guid] then
            return false
        end
    end
    return true
end

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
            claimLMRole = {
                type = "execute",
                name = L["Claim LM Role"],
                desc = L["No Loot Master is detected in the raid. Claim the role to enable session management."],
                order = 1.2,
                width = "normal",
                hidden = function()
                    return not API:IsOfficerOrLM() or API:IsLootMaster() or not API:IsLMAbsent()
                end,
                confirm = true,
                confirmText = "No Loot Master has been detected in the group for 60+ seconds. Do you want to claim the Loot Master role?",
                func = function()
                    API:ClaimLMRole()
                end,
            },
            handoverHeader = {
                type = "header",
                name = L["Hand Over LM Role"],
                order = 1.4,
                hidden = function() return not API:IsLootMaster() end,
            },
            handoverTarget = {
                type = "select",
                name = L["Select Officer for Handover"],
                desc = L["Choose an officer in the raid to hand over the Loot Master role to."],
                order = 1.5,
                width = "normal",
                values = GetOfficerNamesInRaid,
                get = function() return selectedHandoverTarget end,
                set = function(_, val) selectedHandoverTarget = val end,
                hidden = function() return not API:IsLootMaster() end,
            },
            handoverBtn = {
                type = "execute",
                name = L["Hand Over LM Role"],
                desc = L["Start the handover process to the selected officer."],
                order = 1.6,
                width = "normal",
                disabled = function() return not selectedHandoverTarget or not CanHandover() end,
                hidden = function() return not API:IsLootMaster() end,
                func = function()
                    if not selectedHandoverTarget then return end
                    if not CanHandover() then
                        DesolateLootcouncil:Print("Cannot hand over during an active vote. Award or remove all items first.")
                        return
                    end
                    API:SendLMHandoverOffer(selectedHandoverTarget)
                    selectedHandoverTarget = nil
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
                name = "Privately whisper Priority Lists and Roster to all raid Officers. Regular members cannot read this data.",
                order = 11,
                hidden = function() return not API:IsLootMaster() end,
            },
            shareWithOfficersBtn = {
                type = "execute",
                name = "Share Priority & Roster with Officers",
                desc = "Sends both Priority Lists and Roster to all current raid officers via private whisper.",
                order = 12,
                width = "full",
                hidden = function() return not API:IsLootMaster() end,
                confirm = true,
                confirmText = "This will overwrite the Priority Lists and Roster on all officers' clients. Continue?",
                func = function()
                    API:ShareDataWithOfficers("PRIORITY")
                    API:ShareDataWithOfficers("ROSTER")
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
