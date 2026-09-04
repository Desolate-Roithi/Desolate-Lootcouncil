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

function UI_InteractiveTestBar:UpdateRoleDisplay(role)
    self.currentRole = role or "LM"

    if self.btnRole then
        if self.currentRole == "LM" then
            self.btnRole:SetText("|cffffd700Role: LM|r")
        elseif self.currentRole == "Officer" then
            self.btnRole:SetText("|cff00ffffRole: Officer|r")
        else
            self.btnRole:SetText("|cff00ff00Role: Raider|r")
        end
    end

    if self.statusText then
        if self.currentRole == "LM" then
            self.statusText:SetText(L["Active Simulation [Role: Loot Master] - Full session control and awarding authority."])
        elseif self.currentRole == "Officer" then
            self.statusText:SetText(L["Active Simulation [Role: Council Officer] - Review bids, monitor votes, council parity."])
        else
            self.statusText:SetText(L["Active Simulation [Role: Raider] - Cast personal votes and submit item roll/pass choices."])
        end
    end

    if self.btnAward then
        if self.currentRole == "LM" then
            self.btnAward:SetText(L["Auto-Award Next"])
        else
            self.btnAward:SetText(L["LM Auto-Award"])
        end
    end

    if self.btnOpenMonitor then
        if self.currentRole == "Raider" then
            self.btnOpenMonitor:SetEnabled(false)
            self.btnOpenMonitor:SetText("|cff777777" .. L["Monitor UI"] .. "|r")
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor", true)
            if Monitor and Monitor.monitorFrame and Monitor.monitorFrame:IsShown() then
                Monitor.monitorFrame:Hide()
            end
        else
            self.btnOpenMonitor:SetEnabled(true)
            self.btnOpenMonitor:SetText(L["Monitor UI"])
        end
    end
end

function UI_InteractiveTestBar:ShowBar(initialRole)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local role = initialRole or (DesolateLootcouncil.API and DesolateLootcouncil.API.GetInteractiveSimRole and DesolateLootcouncil.API:GetInteractiveSimRole()) or "LM"
    self.currentRole = role

    if not self.barFrame then
        local frame = NativeGUI:CreateWindow("DLCInteractiveTestBarFrame", L["Interactive Test Controller"], "InteractiveTestBar")
        self.barFrame = frame
        frame:SetSize(860, 85)
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", 0, -45)

        local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -30)
        self.statusText = statusText

        -- Button 1: Role Switcher (LM -> Officer -> Raider)
        local btnRole = NativeGUI:CreateButton(frame, "Role: LM", 110, 24, "Default")
        btnRole:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
        btnRole:SetScript("OnClick", function()
            local nextRole
            if self.currentRole == "LM" then
                nextRole = "Officer"
            elseif self.currentRole == "Officer" then
                nextRole = "Raider"
            else
                nextRole = "LM"
            end
            if DesolateLootcouncil.API and DesolateLootcouncil.API.SetInteractiveSimRole then
                DesolateLootcouncil.API:SetInteractiveSimRole(nextRole)
            end
            self:UpdateRoleDisplay(nextRole)
        end)
        btnRole:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Simulation Role Persona"], 1, 0.82, 0)
            GameTooltip:AddLine(L["Click to cycle through roles: LM -> Officer -> Raider."], 1, 1, 1, true)
            GameTooltip:AddLine(L["Tests interface visibility, permissions, and vote workflows for each rank."], 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        btnRole:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.btnRole = btnRole

        -- Button 2: Add Items to Backlog
        local btnAddItems = NativeGUI:CreateButton(frame, L["Add Items"], 90, 24, "Action")
        btnAddItems:SetPoint("LEFT", btnRole, "RIGHT", 6, 0)
        btnAddItems:SetScript("OnClick", function()
            -- Ensure player has LM permissions to open and manage the Loot Window
            if self.currentRole ~= "LM" then
                if DesolateLootcouncil.API and DesolateLootcouncil.API.SetInteractiveSimRole then
                    DesolateLootcouncil.API:SetInteractiveSimRole("LM")
                end
                self:UpdateRoleDisplay("LM")
            end

            local addedCount = 0
            if DesolateLootcouncil.API and DesolateLootcouncil.API.AddSimulationBacklogItems then
                addedCount = DesolateLootcouncil.API:AddSimulationBacklogItems()
            end

            local LootUI = DesolateLootcouncil:GetModule("UI_Loot", true)
            if LootUI and LootUI.ShowLootWindow then
                local session = DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.session
                LootUI:ShowLootWindow(session and session.loot)
            end

            DesolateLootcouncil:Print(string.format(L["Added %d items to the loot backlog and opened the Loot window."], addedCount))
        end)
        btnAddItems:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Add Backlog Items"], 1, 0.82, 0)
            GameTooltip:AddLine(L["Stages sample drops into the Loot Master backlog and opens the distribution window to test connection status and Start Bidding."], 1, 1, 1, true)
            if self.currentRole ~= "LM" then
                GameTooltip:AddLine(L["Switches active persona to Loot Master if needed."], 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end)
        btnAddItems:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.btnAddItems = btnAddItems

        -- Button 3: Simulate Raider Votes
        local btnVote = NativeGUI:CreateButton(frame, L["Simulate Votes"], 105, 24, "Bid")
        btnVote:SetPoint("LEFT", btnAddItems, "RIGHT", 6, 0)
        btnVote:SetScript("OnClick", function()
            local count = DesolateLootcouncil.API:SimulateRaiderVotes()
            DesolateLootcouncil:Print(string.format(L["Injected %d simulated raider votes."], count))
        end)
        self.btnVote = btnVote

        -- Button 4: Auto-Award Next Item
        local btnAward = NativeGUI:CreateButton(frame, L["Auto-Award Next"], 120, 24, "Action")
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

        -- Button 5: Toggle Voting Window
        local btnOpenVoting = NativeGUI:CreateButton(frame, L["Voting UI"], 80, 24, "Default")
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

        -- Button 6: Toggle Monitor Window
        local btnOpenMonitor = NativeGUI:CreateButton(frame, L["Monitor UI"], 85, 24, "Default")
        btnOpenMonitor:SetPoint("LEFT", btnOpenVoting, "RIGHT", 6, 0)
        btnOpenMonitor:SetScript("OnClick", function()
            if self.currentRole == "Raider" or not DesolateLootcouncil:AmIOfficerOrLM() then
                DesolateLootcouncil:Print(L["The Session Monitor is restricted to Loot Masters and Council Officers."])
                return
            end
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor", true)
            if Monitor then
                if Monitor.monitorFrame and Monitor.monitorFrame:IsShown() then
                    Monitor.monitorFrame:Hide()
                elseif Monitor.ShowMonitorWindow then
                    Monitor:ShowMonitorWindow()
                end
            end
        end)
        btnOpenMonitor:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Monitor UI"], 1, 0.82, 0)
            if self.currentRole == "Raider" then
                GameTooltip:AddLine(L["Restricted: Raiders cannot access the Council Monitor."], 1, 0.2, 0.2, true)
            else
                GameTooltip:AddLine(L["Toggle Council Session Monitor window."], 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        btnOpenMonitor:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.btnOpenMonitor = btnOpenMonitor

        -- Button 7: Complete & Verify (keeps auditor open)
        local btnComplete = NativeGUI:CreateButton(frame, L["Complete & Verify"], 130, 24, "Bid")
        btnComplete:SetPoint("LEFT", btnOpenMonitor, "RIGHT", 6, 0)
        btnComplete:SetScript("OnClick", function()
            DesolateLootcouncil.API:CompleteAndVerifySim()
        end)
        btnComplete:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Complete & Verify"], 1, 0.82, 0)
            GameTooltip:AddLine(L["Concludes the session, records all remaining awards, and keeps the Audit Ledger open for review."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btnComplete:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.btnComplete = btnComplete

        -- Button 8: End / Cancel
        local btnCancel = NativeGUI:CreateButton(frame, L["Cancel"], 70, 24, "Stop")
        btnCancel:SetPoint("LEFT", btnComplete, "RIGHT", 6, 0)
        btnCancel:SetScript("OnClick", function()
            DesolateLootcouncil.API:StopInteractiveLootTest()
        end)
        self.btnCancel = btnCancel
    end

    self:UpdateRoleDisplay(self.currentRole)
    self.barFrame:Show()
    if self.barFrame.Raise then
        pcall(function() self.barFrame:Raise() end)
    end
end

function UI_InteractiveTestBar:HideBar()
    if self.barFrame then
        self.barFrame:Hide()
    end
end
