---@type UI
local UI = DesolateLootcouncil:GetModule("UI")
local AceGUI = LibStub("AceGUI-3.0")



function UI:ShowMonitorWindow()
    if not self.monitorFrame then
        ---@type AceGUIWidget
        local frame = AceGUI:Create("Frame")
        frame:SetTitle("Session Monitor")
        frame:SetLayout("Flow")
        frame:SetWidth(650)
        frame:SetHeight(400)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.monitorFrame = frame
    end

    self.monitorFrame:Show()
    self.monitorFrame:ReleaseChildren()

    -- Helper: Vote Counts
    local function GetVoteCounts(guid)
        ---@type Distribution
        local Dist = DesolateLootcouncil:GetModule("Distribution")
        local votes = Dist and Dist.sessionVotes and Dist.sessionVotes[guid]
        local bids, rolls, tm, pass = 0, 0, 0, 0
        if votes then
            for _, voteType in pairs(votes) do
                if voteType == 1 then
                    bids = bids + 1
                elseif voteType == 2 then
                    rolls = rolls + 1
                elseif voteType == 3 then
                    tm = tm + 1
                elseif voteType == 4 then
                    pass = pass + 1
                end
            end
        end
        return string.format("|cff00ff00Bid:%d|r | |cffffd700Roll:%d|r | |cffeda55fTM:%d|r | |cffaaaaaaPass:%d|r", bids,
            rolls, tm, pass)
    end

    local session = DesolateLootcouncil.db.profile.session
    local items = session.bidding
    ---@type AceGUIWidget
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.monitorFrame:AddChild(scroll)

    if items then
        for i, item in ipairs(items) do
            local link = item.link
            local guid = item.sourceGUID or link
            -- Row Group
            ---@type AceGUIWidget
            local group = AceGUI:Create("SimpleGroup")
            group:SetLayout("Flow")
            group:SetFullWidth(true)

            -- CRITICAL FIX: Attach to ScrollFrame FIRST
            scroll:AddChild(group)

            -- 1. Link
            ---@type AceGUIWidget
            local labelLink = AceGUI:Create("InteractiveLabel")
            labelLink:SetText(link)
            labelLink:SetRelativeWidth(0.40)
            labelLink:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            labelLink:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            group:AddChild(labelLink)

            -- 2. Counts
            ---@type AceGUIWidget
            local labelCounts = AceGUI:Create("Label")
            labelCounts:SetText(GetVoteCounts(guid))
            labelCounts:SetRelativeWidth(0.35)
            group:AddChild(labelCounts)

            -- 3. Award Button
            ---@type AceGUIWidget
            local btnAward = AceGUI:Create("Button")
            btnAward:SetText("Award")
            btnAward:SetRelativeWidth(0.15)
            btnAward:SetCallback("OnClick", function()
                self:ShowAwardWindow(item)
            end)
            group:AddChild(btnAward)

            -- 4. Remove Button
            ---@type AceGUIWidget
            local btnRemove = AceGUI:Create("Button")
            btnRemove:SetText("X")
            btnRemove:SetRelativeWidth(0.10)
            btnRemove:SetCallback("OnClick", function()
                -- CRITICAL FIX: Safety Delay to prevent crash
                C_Timer.After(0.05, function()
                    ---@type Distribution
                    local Dist = DesolateLootcouncil:GetModule("Distribution")
                    if Dist and Dist.RemoveSessionItem then
                        Dist:RemoveSessionItem(guid)
                    end
                end)
            end)
            group:AddChild(btnRemove)
        end
    end

    -- Footer Buttons (Trades / Stop)
    local parent = (self.monitorFrame --[[@as table]]).frame
    if not self.monitorFrame.btnTrades then
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetText("Pending Trades")
        btn:SetWidth(120)
        btn:SetHeight(24)
        btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 20, 15)
        btn:SetFrameLevel(parent:GetFrameLevel() + 10)
        btn:SetScript("OnClick", function() self:ShowTradeListWindow() end)
        self.monitorFrame.btnTrades = btn
    end
    self.monitorFrame.btnTrades:Show()

    if not self.monitorFrame.btnEnd then
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetText("Stop Session")
        btn:SetWidth(120)
        btn:SetHeight(24)
        btn:SetPoint("BOTTOM", parent, "BOTTOM", 0, 15)
        btn:SetFrameLevel(parent:GetFrameLevel() + 10)
        btn:SetScript("OnClick", function()
            ---@type Distribution
            local Dist = DesolateLootcouncil:GetModule("Distribution")
            if Dist and Dist.SendStopSession then Dist:SendStopSession() end
        end)
        self.monitorFrame.btnEnd = btn
    end
    self.monitorFrame.btnEnd:Show()

    local function LayoutMonitor()
        local h = (self.monitorFrame --[[@as table]]).frame:GetHeight()
        if scroll then scroll:SetHeight(h - 80) end
        self.monitorFrame:DoLayout()
    end
    LayoutMonitor()
    self.monitorFrame:SetCallback("OnResize", LayoutMonitor)
end

function UI:ShowAwardWindow(itemData)
    if not itemData then
        if self.awardFrame then self.awardFrame:Hide() end
        return
    end

    if not self.awardFrame then
        ---@type AceGUIWidget
        local frame = AceGUI:Create("Frame")
        frame:SetTitle("Award Item")
        frame:SetLayout("Flow")
        frame:SetWidth(450)
        frame:SetHeight(500)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.awardFrame = frame
    end
    self.awardFrame:Show()
    self.awardFrame:ReleaseChildren()

    ---@type AceGUIWidget
    local header = AceGUI:Create("Label")
    header:SetText(itemData.link)
    header:SetFullWidth(true)
    header:SetJustifyH("CENTER")
    header:SetFontObject(GameFontNormalLarge)
    self.awardFrame:AddChild(header)

    ---@type Distribution
    local Dist = DesolateLootcouncil:GetModule("Distribution")
    local votes = Dist and Dist.sessionVotes and Dist.sessionVotes[itemData.sourceGUID]

    ---@type AceGUIWidget
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    self.awardFrame:AddChild(scroll)

    local voteList = {}
    if votes then
        for voter, voteType in pairs(votes) do
            table.insert(voteList, { name = voter, type = voteType })
        end
        table.sort(voteList, function(a, b)
            if a.type == b.type then return a.name < b.name end
            return a.type < b.type
        end)
    end

    local VOTE_COLOR = { [1] = "|cff00ff00", [2] = "|cffffd700", [3] = "|cffeda55f", [4] = "|cffaaaaaa" }
    local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "TM", [4] = "Pass" }

    if #voteList == 0 then
        ---@type AceGUIWidget
        local lbl = AceGUI:Create("Label")
        lbl:SetText("No votes cast yet.")
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    else
        for _, v in ipairs(voteList) do
            ---@type AceGUIWidget
            local row = AceGUI:Create("SimpleGroup")
            row:SetLayout("Flow")
            row:SetFullWidth(true)

            -- CRITICAL: Attach FIRST
            scroll:AddChild(row)

            ---@type AceGUIWidget
            local lblName = AceGUI:Create("Label")
            lblName:SetText(v.name)
            lblName:SetRelativeWidth(0.40)
            row:AddChild(lblName)

            ---@type AceGUIWidget
            local lblResp = AceGUI:Create("Label")
            local color = VOTE_COLOR[v.type] or ""
            local txt = VOTE_TEXT[v.type] or "?"
            lblResp:SetText(color .. txt .. "|r")
            lblResp:SetRelativeWidth(0.30)
            row:AddChild(lblResp)

            ---@type AceGUIWidget
            local btnGive = AceGUI:Create("Button")
            btnGive:SetText("Give")
            btnGive:SetRelativeWidth(0.30)
            btnGive:SetCallback("OnClick", function()
                self.awardFrame:Hide()
                ---@type Loot
                local Loot = DesolateLootcouncil:GetModule("Loot")
                if Loot and Loot.AwardItem then
                    local voteDesc = VOTE_TEXT[v.type] or "Unknown"
                    Loot:AwardItem(itemData.sourceGUID, v.name, voteDesc)
                end
            end)
            row:AddChild(btnGive)
        end
    end
end

function UI:CloseMasterLootWindow()
    if self.monitorFrame then self.monitorFrame:Hide() end
end

UI.ShowMasterLootWindow = UI.ShowMonitorWindow
