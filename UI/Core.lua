local _, AT = ...
if AT.abortLoad then return end

---@class UI : AceModule, AceConsole-3.0, AceEvent-3.0, AceTimer-3.0
---@field updateTimer any
---@field ShowLootWindow fun(self: UI, lootTable: table|nil)
---@field ShowVotingWindow fun(self: UI, lootTable: table|nil, isRefresh: boolean?)
---@field ShowMonitorWindow fun(self: UI)
---@field ShowAwardWindow fun(self: UI, itemData: table|nil)
---@field CloseMasterLootWindow fun(self: UI)
---@field ShowMasterLootWindow fun(self: UI)
---@field ShowHistoryWindow fun(self: UI)
---@field ShowAttendanceWindow fun(self: UI)
---@field ShowTradeListWindow fun(self: UI)
---@field RefreshTradeWindow fun(self: UI)
---@field ShowPriorityOverrideWindow fun(self: UI, listIndex: number)
---@field ShowVersionWindow fun(self: UI, isTest: boolean?)
---@field ResetVoting fun(self: UI)
---@field RemoveVotingItem fun(self: UI, guid: string)

---@class (partial) DLC_Ref_UI
---@field GetModule fun(self: DLC_Ref_UI, name: string): any
---@field NewModule fun(self: DLC_Ref_UI, name: string, ...): any

---@type DLC_Ref_UI
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_UI]]
---@type UI
local UI = DesolateLootcouncil:NewModule("UI", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

---@diagnostic disable-next-line: inject-field
function UI:OnEnable()
    -- Forward messages if needed, or register core UI events
    self:RegisterMessage("DLC_VERSION_UPDATE", function()
        -- [STEADY] Batch updates to 2 seconds to keep list responsive but un-spammed.
        if self.updateTimer then return end -- Already scheduled

        self.updateTimer = self:ScheduleTimer(function()
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
            if Monitor then Monitor:UpdateDisenchanters() end
            self.updateTimer = nil
        end, 2) -- 2 second debounce
    end)

    -- Register Blizzard Settings Panel Category
    local blizzOptionsFrame = CreateFrame("Frame", "DesolateLootcouncilBlizOptions", UIParent)
    blizzOptionsFrame.name = "Desolate Loot Council"

    local title = blizzOptionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Desolate Loot Council")

    local desc = blizzOptionsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText(L["Open the configuration window to manage settings, priority lists, and rosters."])

    local btn = CreateFrame("Button", nil, blizzOptionsFrame, "UIPanelButtonTemplate")
    btn:SetSize(180, 26)
    btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    btn:SetText(L["Open Settings Window"])
    btn:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            SettingsPanel:Hide()
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            InterfaceOptionsFrame:Hide()
        end
        DesolateLootcouncil:OpenConfig()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(blizzOptionsFrame, "Desolate Loot Council")
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(blizzOptionsFrame)
    end
end

-- ============================================================================
-- DELEGATES
-- ============================================================================

function UI:ShowLootWindow(lootTable)
    local M = DesolateLootcouncil:GetModule("UI_Loot")
    if M then M:ShowLootWindow(lootTable) end
end

function UI:ShowVotingWindow(lootTable, isRefresh)
    local M = DesolateLootcouncil:GetModule("UI_Voting")
    if M then M:ShowVotingWindow(lootTable, isRefresh) end
end

function UI:ShowMonitorWindow()
    local M = DesolateLootcouncil:GetModule("UI_Monitor")
    if M then M:ShowMonitorWindow() end
end

function UI:ShowMasterLootWindow()
    self:ShowMonitorWindow()
end

function UI:CloseMasterLootWindow()
    local M = DesolateLootcouncil:GetModule("UI_Monitor")
    if M then M:CloseMasterLootWindow() end
end

function UI:ShowAwardWindow(itemData)
    local M = DesolateLootcouncil:GetModule("UI_Award")
    if M then M:ShowAwardWindow(itemData) end
end

function UI:ShowHistoryWindow()
    local M = DesolateLootcouncil:GetModule("UI_History")
    if M then M:ShowHistoryWindow() end
end

function UI:ShowAttendanceWindow()
    local M = DesolateLootcouncil:GetModule("UI_Attendance")
    if M then M:ShowAttendanceWindow() end
end

function UI:ShowTradeListWindow()
    local M = DesolateLootcouncil:GetModule("UI_TradeList")
    if M then M:ShowTradeListWindow() end
end

function UI:RefreshTradeWindow()
    -- Forward to Show (which refreshes)
    self:ShowTradeListWindow()
end

function UI:ShowPriorityOverrideWindow(listIndex)
    local M = DesolateLootcouncil:GetModule("UI_PriorityOverride")
    if M then M:ShowPriorityOverrideWindow(listIndex) end
end

function UI:ShowVersionWindow(isTest)
    local M = DesolateLootcouncil:GetModule("UI_Version")
    if M then M:ShowVersionWindow(isTest) end
end

function UI:ShowSettingsWindow()
    local M = DesolateLootcouncil:GetModule("UI_Settings")
    if M then M:ShowSettingsWindow() end
end

function UI:ResetVoting()
    local V = DesolateLootcouncil:GetModule("UI_Voting")
    if V then V:ResetVoting() end

    local M = DesolateLootcouncil:GetModule("UI_Monitor")
    if M and M.monitorFrame then M.monitorFrame:Hide() end

    local A = DesolateLootcouncil:GetModule("UI_Award")
    if A and A.awardFrame then A.awardFrame:Hide() end

    self:Print("Voting data cleared.")
end

function UI:RemoveVotingItem(guid)
    local V = DesolateLootcouncil:GetModule("UI_Voting")
    if V then V:RemoveVotingItem(guid) end
end
