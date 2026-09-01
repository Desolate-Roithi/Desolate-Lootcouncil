local _, AT = ...
if AT.abortLoad then return end

---@class UI_InteractiveTestBar : AceModule
local UI_InteractiveTestBar = DesolateLootcouncil:NewModule("UI_InteractiveTestBar")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

---@class (partial) DLC_Ref_UI_TestBar
---@field db table
---@field GetModule fun(self: any, name: string, silent?: boolean): any
---@field Print fun(self: any, msg: string)

---@type DLC_Ref_UI_TestBar
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_UI_TestBar]]

function UI_InteractiveTestBar:ShowBar()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.barFrame then
        local frame = NativeGUI:CreateWindow("DLCInteractiveTestBarFrame", L["Interactive Test Controller"], "InteractiveTestBar")
        self.barFrame = frame
        frame:SetSize(720, 85)
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", 0, -45)

        local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -30)
        statusText:SetText(L["Active Live Simulation: Test voting, priority overrides, and loot master awards."])
        self.statusText = statusText

        -- Button 1: Simulate Raider Votes
        local btnVote = NativeGUI:CreateButton(frame, L["Simulate Votes"], 125, 24, "Bid")
        btnVote:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
        btnVote:SetScript("OnClick", function()
            local count = DesolateLootcouncil.API:SimulateRaiderVotes()
            DesolateLootcouncil:Print(string.format(L["Injected %d simulated raider votes."], count))
        end)
        self.btnVote = btnVote

        -- Button 2: Auto-Award Next Item
        local btnAward = NativeGUI:CreateButton(frame, L["Auto-Award Next"], 125, 24, "Action")
        btnAward:SetPoint("LEFT", btnVote, "RIGHT", 6, 0)
        btnAward:SetScript("OnClick", function()
            local item, winner = DesolateLootcouncil.API:AutoAwardNextSimItem()
            if item and winner then
                DesolateLootcouncil:Print(string.format(L["Awarded %s to %s."], item.link or item.itemID or "Item", winner))
            else
                DesolateLootcouncil:Print(L["No remaining items in bidding queue."])
            end
        end)
        self.btnAward = btnAward

        -- Button 3: Toggle Voting Window
        local btnOpenVoting = NativeGUI:CreateButton(frame, L["Voting UI"], 90, 24, "Default")
        btnOpenVoting:SetPoint("LEFT", btnAward, "RIGHT", 6, 0)
        btnOpenVoting:SetScript("OnClick", function()
            local Voting = DesolateLootcouncil:GetModule("UI_Voting", true)
            if Voting then
                if Voting.votingFrame and Voting.votingFrame:IsShown() then
                    Voting.votingFrame:Hide()
                else
                    Voting:ShowVotingWindow()
                end
            end
        end)
        self.btnOpenVoting = btnOpenVoting

        -- Button 4: Toggle Monitor Window
        local btnOpenMonitor = NativeGUI:CreateButton(frame, L["Monitor UI"], 95, 24, "Default")
        btnOpenMonitor:SetPoint("LEFT", btnOpenVoting, "RIGHT", 6, 0)
        btnOpenMonitor:SetScript("OnClick", function()
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor", true)
            if Monitor and Monitor.ShowMonitorWindow then
                Monitor:ShowMonitorWindow()
            end
        end)
        self.btnOpenMonitor = btnOpenMonitor

        -- Button 5: Complete & Verify
        local btnComplete = NativeGUI:CreateButton(frame, L["Complete & Verify"], 135, 24, "Bid")
        btnComplete:SetPoint("LEFT", btnOpenMonitor, "RIGHT", 6, 0)
        btnComplete:SetScript("OnClick", function()
            DesolateLootcouncil.API:CompleteAndVerifySim()
        end)
        self.btnComplete = btnComplete

        -- Button 6: End / Cancel
        local btnCancel = NativeGUI:CreateButton(frame, L["Cancel"], 75, 24, "Stop")
        btnCancel:SetPoint("LEFT", btnComplete, "RIGHT", 6, 0)
        btnCancel:SetScript("OnClick", function()
            DesolateLootcouncil.API:StopInteractiveLootTest()
        end)
        self.btnCancel = btnCancel
    end

    self.barFrame:Show()
    self.barFrame:Raise()
end

function UI_InteractiveTestBar:HideBar()
    if self.barFrame then
        self.barFrame:Hide()
    end
end
