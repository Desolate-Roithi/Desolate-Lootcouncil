---@type UI
local UI = DesolateLootcouncil:GetModule("UI")
local AceGUI = LibStub("AceGUI-3.0")

function UI:ShowMonitorWindow()
    if not self.monitorFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Session Monitor")
        frame:SetLayout("Flow")
        frame:SetWidth(600)
        frame:SetHeight(400)
        frame:SetCallback("OnClose", function(widget)
            widget:Hide()
        end)
        self.monitorFrame = frame
    end

    self.monitorFrame:Show()
    self.monitorFrame:ReleaseChildren()

    -- Helper to count votes
    local function GetVoteCounts(guid)
        ---@type Distribution
        local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
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
        return string.format("Bids: %d | Rolls: %d | TM: %d | Pass: %d", bids, rolls, tm, pass)
    end

    -- Data Source: Session Bidding List
    local session = DesolateLootcouncil.db.profile.session
    local items = session.bidding

    -- ScrollFrame
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.monitorFrame:AddChild(scroll)

    if items then
        for i, data in ipairs(items) do
            local link = data.link
            local guid = data.sourceGUID or link

            -- Row
            ---@type AceGUISimpleGroup
            local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            group:SetLayout("Flow")
            group:SetFullWidth(true)

            -- 1. Item Link (0.5)
            ---@type AceGUIInteractiveLabel
            local labelLink = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
            labelLink:SetText(link)
            labelLink:SetRelativeWidth(0.50)
            labelLink:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            labelLink:SetCallback("OnLeave", function() GameTooltip:Hide() end)

            -- 2. Counts (0.3)
            ---@type AceGUILabel
            local labelCounts = AceGUI:Create("Label") --[[@as AceGUILabel]]
            labelCounts:SetText(GetVoteCounts(guid))
            labelCounts:SetRelativeWidth(0.30)
            labelCounts:SetColor(1, 1, 1) -- White

            -- 3. Award Button (0.2)
            ---@type AceGUIButton
            local btnAward = AceGUI:Create("Button") --[[@as AceGUIButton]]
            btnAward:SetText("Award")
            btnAward:SetRelativeWidth(0.20)
            btnAward:SetCallback("OnClick", function()
                self:ShowAwardWindow(data)
            end)

            group:AddChild(labelLink)
            group:AddChild(labelCounts)
            group:AddChild(btnAward)
            scroll:AddChild(group)
        end
    end
    -- Create Pending Trades Button (Pinned to Bottom Left)
    if not (self.monitorFrame --[[@as any]]).btnTrades then
        local parent = (self.monitorFrame --[[@as any]]).frame
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetText("Pending Trades")
        btn:SetWidth(120)
        btn:SetHeight(24)
        btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 20, 15) -- FIXED ANCHOR
        btn:SetFrameLevel(parent:GetFrameLevel() + 10)           -- FORCE ON TOP
        btn:SetScript("OnClick", function()
            self:ShowTradeListWindow()
        end); -- Semicolon to separate statement
        (self.monitorFrame --[[@as any]]).btnTrades = btn
    end
    (self.monitorFrame --[[@as any]]).btnTrades:Show()

    -- End Session Button (Center)
    if not (self.monitorFrame --[[@as any]]).btnEnd then
        local parent = (self.monitorFrame --[[@as any]]).frame
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetText("Stop Session")
        btn:SetWidth(120)
        btn:SetHeight(24)
        btn:SetPoint("BOTTOM", parent, "BOTTOM", 0, 15) -- FIXED ANCHOR
        btn:SetFrameLevel(parent:GetFrameLevel() + 10)  -- FORCE ON TOP
        btn:SetScript("OnClick", function()
            ---@type Loot
            local Loot = DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
            if Loot.EndSession then
                Loot:EndSession()
                self:CloseMasterLootWindow() -- Visual Close
            end
        end);
        (self.monitorFrame --[[@as any]]).btnEnd = btn
    end
    (self.monitorFrame --[[@as any]]).btnEnd:Show()

    -- Resize layout for footer space
    local function LayoutMonitor()
        local h = (self.monitorFrame --[[@as any]]).frame:GetHeight()
        -- Footer space: Reserve 80px at bottom to safely clear buttons
        if scroll then scroll:SetHeight(h - 80) end
        self.monitorFrame:DoLayout()
    end
    LayoutMonitor()
    self.monitorFrame:SetCallback("OnResize", LayoutMonitor)
end

function UI:ShowAwardWindow(itemData)
    if not self.awardFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Award Item")
        frame:SetLayout("Flow")
        frame:SetWidth(400)
        frame:SetHeight(450)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.awardFrame = frame
    end

    self.awardFrame:Show()
    self.awardFrame:ReleaseChildren()

    -- Header: Item Link
    ---@type AceGUILabel
    local header = AceGUI:Create("Label") --[[@as AceGUILabel]]
    header:SetText(itemData.link)
    header:SetFullWidth(true)
    header:SetJustifyH("CENTER")
    header:SetFontObject(GameFontNormalLarge)
    self.awardFrame:AddChild(header)

    -- Data Source: Votes
    ---@type Distribution
    local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
    local votes = Dist and Dist.sessionVotes and Dist.sessionVotes[itemData.sourceGUID]

    -- Scroll for Voters
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    self.awardFrame:AddChild(scroll)

    -- Flatten and Sort Votes
    local voteList = {}
    if votes then
        for voter, voteType in pairs(votes) do
            table.insert(voteList, { name = voter, type = voteType })
        end
        table.sort(voteList, function(a, b)
            if a.type == b.type then return a.name < b.name end
            return a.type < b.type -- 1 (Bid) < 2 (Roll) < 3 (TM) < 4 (Pass)
        end)
    end

    local VOTE_COLOR = { [1] = "|cff00ff00", [2] = "|cffffd700", [3] = "|cffeda55f", [4] = "|cffaaaaaa" }
    local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "Transmog", [4] = "Pass" }

    if #voteList == 0 then
        local lbl = AceGUI:Create("Label") --[[@as AceGUILabel]]
        lbl:SetText("No votes cast yet.")
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    else
        for _, v in ipairs(voteList) do
            ---@type AceGUISimpleGroup
            local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            row:SetLayout("Flow")
            row:SetFullWidth(true)

            -- Name (0.4)
            ---@type AceGUILabel
            local lblName = AceGUI:Create("Label") --[[@as AceGUILabel]]
            lblName:SetText(v.name)
            lblName:SetRelativeWidth(0.40)

            -- Response (0.3)
            ---@type AceGUILabel
            local lblResp = AceGUI:Create("Label") --[[@as AceGUILabel]]
            local color = VOTE_COLOR[v.type] or ""
            local txt = VOTE_TEXT[v.type] or "?"
            lblResp:SetText(color .. txt .. "|r")
            lblResp:SetRelativeWidth(0.30)

            -- Give Button (0.3)
            ---@type AceGUIButton
            local btnGive = AceGUI:Create("Button") --[[@as AceGUIButton]]
            btnGive:SetText("Give")
            btnGive:SetRelativeWidth(0.30)
            btnGive:SetCallback("OnClick", function()
                self.awardFrame:Hide()
                ---@type Loot
                local Loot = DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
                if Loot.AwardItem then
                    local voteDesc = VOTE_TEXT[v.type] or "Unknown"
                    Loot:AwardItem(itemData.sourceGUID, v.name, voteDesc)
                else
                    DesolateLootcouncil:Print("Loot:AwardItem not implemented yet for " .. v.name)
                end
            end)

            row:AddChild(lblName)
            row:AddChild(lblResp)
            row:AddChild(btnGive)
            scroll:AddChild(row)
        end
    end
end

function UI:CloseMasterLootWindow()
    if self.monitorFrame then
        self.monitorFrame:Hide()
    end
end

-- Alias for legacy support
UI.ShowMasterLootWindow = UI.ShowMonitorWindow
