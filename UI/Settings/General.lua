local _, AT = ...
if AT.abortLoad then return end

---@class UI_GeneralSettings : AceModule
local GeneralSettings = DesolateLootcouncil:NewModule("UI_GeneralSettings")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local selectedHandoverTarget = nil

local function GetOfficerNamesInRaid()
    local list = {}
    local db = DesolateLootcouncil.db.profile
    
    local members = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank, subgroup, level, class, fileName, zone, online = GetRaidRosterInfo(i) -- luacheck: ignore rank subgroup level class fileName zone
            if name and online then
                table.insert(members, name)
            end
        end
    elseif IsInGroup() then
        table.insert(members, (UnitName("player")))
        for i = 1, GetNumSubgroupMembers() do
            local name = UnitName("party" .. i)
            if name and UnitIsConnected("party" .. i) then
                table.insert(members, name)
            end
        end
    else
        table.insert(members, (UnitName("player")))
    end

    for index, groupMemberName in ipairs(members) do
        if not DesolateLootcouncil:SmartCompare(groupMemberName, "player") then
            local mainName = groupMemberName
            if db.playerRoster and db.playerRoster.alts then
                local memberScoreName = DesolateLootcouncil:GetScoreName(groupMemberName)
                for alt, main in pairs(db.playerRoster.alts) do
                    if DesolateLootcouncil:GetScoreName(alt) == memberScoreName then
                        mainName = main
                        break
                    end
                end
            end
            
            local mainScore = DesolateLootcouncil:GetScoreName(mainName)
            local memberScore = DesolateLootcouncil:GetScoreName(groupMemberName)
            local isOfficer = false
            if db.MainRoster then
                for rosterName, rosterData in pairs(db.MainRoster) do
                    local rScore = DesolateLootcouncil:GetScoreName(rosterName)
                    if rScore == mainScore or rScore == memberScore then
                        if rosterData.isOfficer then
                            isOfficer = true
                        end
                        if isOfficer then break end
                    end
                end
            end
            
            if isOfficer then
                local displayName = DesolateLootcouncil:GetDisplayName(mainName)
                if not DesolateLootcouncil:SmartCompare(groupMemberName, mainName) then
                    displayName = string.format("%s (%s)", displayName, Ambiguate(groupMemberName, "none"))
                end
                list[groupMemberName] = displayName
            end
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

local function BuildLMSection(API)
    return {
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
                    DesolateLootcouncil:Print(L["Cannot hand over during an active vote. Award or remove all items first."])
                    return
                end
                if not DesolateLootcouncil:IsUnitInRaid(selectedHandoverTarget) or not DesolateLootcouncil:IsUnitOnline(selectedHandoverTarget) then
                    DesolateLootcouncil:Print(string.format(L["Cannot hand over: %s is no longer in the group or online."], selectedHandoverTarget))
                    selectedHandoverTarget = nil
                    return
                end
                API:SendLMHandoverOffer(selectedHandoverTarget)
                selectedHandoverTarget = nil
            end,
        },
    }
end

local function BuildLootSection(API)
    return {
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
                ["Midnight"]   = "Midnight (Void)",
                ["Classic"]    = "Classic Slate",
                ["Minimalist"] = "Pure Dark (Minimal)",
                ["Fel"]        = "Emerald Fel",
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
    }
end

local function BuildAutopassSection(API)
    return {
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
end

function GeneralSettings:GetGeneralOptions()
    local API = DesolateLootcouncil.API
    local args = {}

    for k, v in pairs(BuildLMSection(API))       do args[k] = v end
    for k, v in pairs(BuildLootSection(API))     do args[k] = v end
    for k, v in pairs(BuildAutopassSection(API)) do args[k] = v end

    return {
        name = "General",
        type = "group",
        order = 1,
        args = args,
    }
end

