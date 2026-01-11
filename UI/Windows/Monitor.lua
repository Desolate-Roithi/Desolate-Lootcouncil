---@class UI_Monitor : AceModule
local UI_Monitor = DesolateLootcouncil:NewModule("UI_Monitor")
local AceGUI = LibStub("AceGUI-3.0")

---@class (partial) DLC_Ref_Monitor
---@field db table
---@field GetModule fun(self: DLC_Ref_Monitor, name: string): any
---@field Print fun(self: DLC_Ref_Monitor, msg: string)
---@field RestoreFramePosition fun(self: DLC_Ref_Monitor, frame: any, windowName: string)
---@field SaveFramePosition fun(self: DLC_Ref_Monitor, frame: any, windowName: string)
---@field ApplyCollapseHook fun(self: DLC_Ref_Monitor, widget: any)
---@field DLC_Log fun(self: DLC_Ref_Monitor, msg: any, force?: boolean)

---@type DLC_Ref_Monitor
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Monitor]]

-- [NEW] Helper: Resolve Alt to Main (Exact + Realm-Smart)
local function GetLinkedMain(name)
    local db = DesolateLootcouncil.db.profile
    if not db.playerRoster or not db.playerRoster.alts then return nil end
    local alts = db.playerRoster.alts

    -- 1. Exact Match (The Happy Path)
    if alts[name] then
        return alts[name]
    end

    -- 2. Realm Fallback (If name has no realm, try appending current)
    if not string.find(name, "-") then
        local myRealm = GetRealmName()
        local tryName = name .. "-" .. myRealm
        if alts[tryName] then return alts[tryName] end
    end

    return nil
end

function UI_Monitor:ShowMonitorWindow()
    if not self.monitorFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Session Monitor")
        frame:SetLayout("Flow")
        frame:SetWidth(650)
        frame:SetHeight(400)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.monitorFrame = frame

        -- [NEW] Position Persistence
        DesolateLootcouncil:RestoreFramePosition(frame, "Monitor")
        local function SavePos(f)
            DesolateLootcouncil:SaveFramePosition(f, "Monitor")
        end
        local rawFrame = (frame --[[@as any]]).frame
        rawFrame:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            SavePos(frame)
        end)
        rawFrame:SetScript("OnHide", function() SavePos(frame) end)
        DesolateLootcouncil:ApplyCollapseHook(frame)
    end

    self.monitorFrame:Show()
    self.monitorFrame:ReleaseChildren()

    -- Helper: Vote Counts
    local function GetVoteCounts(guid)
        local Session = DesolateLootcouncil:GetModule("Session")
        local votes = Session and Session.sessionVotes and Session.sessionVotes[guid]
        local bids, rolls, tm, pass = 0, 0, 0, 0
        if votes then
            for _, voteData in pairs(votes) do
                local vType = type(voteData) == "table" and voteData.type or voteData
                if vType == 1 then
                    bids = bids + 1
                elseif vType == 2 then
                    rolls = rolls + 1
                elseif vType == 3 then
                    tm = tm + 1
                elseif vType == 4 then
                    pass = pass + 1
                end
            end
        end
        return string.format("|cff00ff00Bid:%d|r | |cffffd700Roll:%d|r | |cffeda55fTM:%d|r | |cffaaaaaaPass:%d|r",
            bids, rolls, tm, pass)
    end

    local session = DesolateLootcouncil.db.profile.session
    local items = session.bidding

    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.monitorFrame:AddChild(scroll)

    if items then
        for i, item in ipairs(items) do
            local link = item.link
            local guid = item.sourceGUID or link

            ---@type AceGUISimpleGroup
            local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            group:SetLayout("Flow")
            group:SetFullWidth(true)
            scroll:AddChild(group)

            -- Link
            ---@type AceGUIInteractiveLabel
            local labelLink = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
            labelLink:SetText(link)
            labelLink:SetRelativeWidth(0.40)
            labelLink:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner((widget --[[@as any]]).frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            labelLink:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            group:AddChild(labelLink)

            -- Counts
            ---@type AceGUILabel
            local labelCounts = AceGUI:Create("Label") --[[@as AceGUILabel]]
            labelCounts:SetText(GetVoteCounts(guid))
            labelCounts:SetRelativeWidth(0.35)
            group:AddChild(labelCounts)

            -- Award Button
            ---@type AceGUIButton
            local btnAward = AceGUI:Create("Button") --[[@as AceGUIButton]]
            btnAward:SetText("Award")
            btnAward:SetRelativeWidth(0.15)
            btnAward:SetCallback("OnClick", function()
                self:ShowAwardWindow(item)
            end)
            group:AddChild(btnAward)

            -- Remove Button
            ---@type AceGUIButton
            local btnRemove = AceGUI:Create("Button") --[[@as AceGUIButton]]
            btnRemove:SetText("X")
            btnRemove:SetRelativeWidth(0.10)
            btnRemove:SetCallback("OnClick", function()
                C_Timer.After(0.05, function()
                    local Session = DesolateLootcouncil:GetModule("Session")
                    if Session and Session.RemoveSessionItem then
                        Session:RemoveSessionItem(guid)
                    end
                end)
            end)
            group:AddChild(btnRemove)
        end
    end

    -- Footer
    local parent = (self.monitorFrame --[[@as any]]).frame
    local mFrame = self.monitorFrame --[[@as any]]
    if not mFrame.btnTrades then
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetText("Pending Trades")
        btn:SetWidth(120)
        btn:SetHeight(24)
        btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 20, 15)
        btn:SetFrameLevel(parent:GetFrameLevel() + 10)
        btn:SetScript("OnClick", function()
            local Trade = DesolateLootcouncil:GetModule("UI_TradeList")
            if Trade then Trade:ShowTradeListWindow() end
        end)
        mFrame.btnTrades = btn
    end
    mFrame.btnTrades:Show()

    if not mFrame.btnEnd then
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetText("Stop Session")
        btn:SetWidth(120)
        btn:SetHeight(24)
        btn:SetPoint("BOTTOM", parent, "BOTTOM", 0, 15)
        btn:SetFrameLevel(parent:GetFrameLevel() + 10)
        btn:SetScript("OnClick", function()
            local Session = DesolateLootcouncil:GetModule("Session")
            if Session and Session.SendStopSession then Session:SendStopSession() end
        end)
        mFrame.btnEnd = btn
    end
    mFrame.btnEnd:Show()

    local function LayoutMonitor()
        local h = (self.monitorFrame --[[@as any]]).frame:GetHeight()
        if scroll then scroll:SetHeight(h - 80) end
        self.monitorFrame:DoLayout()
        -- Sync Sidebar Height
        if self.deFrame then self.deFrame:SetHeight(h) end
    end
    LayoutMonitor()
    self.monitorFrame:SetCallback("OnResize", LayoutMonitor)

    -- [NEW] Re-Scan Logic
    local Loot = DesolateLootcouncil:GetModule("Loot")
    if Loot and Loot.ScanDisenchanters then
        Loot:ScanDisenchanters()
    end

    -- [NEW] Disenchanter Sidebar (External Widget)
    if not self.deFrame then
        local Sidebar = DesolateLootcouncil:GetModule("UI_Sidebar")
        if Sidebar then
            self.deFrame = Sidebar:AttachTo(self.monitorFrame)
        end
    end
    self:UpdateDisenchanters()
end

function UI_Monitor:UpdateDisenchanters()
    if not self.deFrame then return end
    local Sidebar = DesolateLootcouncil:GetModule("UI_Sidebar")
    if Sidebar then
        Sidebar:UpdateDisenchanters(self.deFrame)
    end
end

function UI_Monitor:ShowAwardWindow(itemData)
    if not itemData then
        if self.awardFrame then self.awardFrame:Hide() end
        return
    end

    if not self.awardFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Award Item")
        frame:SetLayout("Flow")
        frame:SetWidth(500)
        frame:SetHeight(500)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.awardFrame = frame

        -- [NEW] Position Persistence
        DesolateLootcouncil:RestoreFramePosition(frame, "Award")
        local function SavePos(f)
            DesolateLootcouncil:SaveFramePosition(f, "Award")
        end
        local rawFrame = (frame --[[@as any]]).frame
        rawFrame:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            SavePos(frame)
        end)
        rawFrame:SetScript("OnHide", function() SavePos(frame) end)
        DesolateLootcouncil:ApplyCollapseHook(frame)
    end
    self.awardFrame:Show()
    self.awardFrame:ReleaseChildren()

    local catText = itemData.category and (" (" .. itemData.category .. ")") or ""
    ---@type AceGUILabel
    local header = AceGUI:Create("Label") --[[@as AceGUILabel]]
    header:SetText(itemData.link .. "|cffaaaaaa" .. catText .. "|r")
    header:SetFullWidth(true)
    header:SetJustifyH("CENTER")
    header:SetFontObject(GameFontNormalLarge)
    self.awardFrame:AddChild(header)

    local Session = DesolateLootcouncil:GetModule("Session")
    local votes = Session and Session.sessionVotes and Session.sessionVotes[itemData.sourceGUID]

    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    self.awardFrame:AddChild(scroll)

    -- [CHANGED] Smart Rank Lookup with Alt Logic
    local function GetPlayerRank(playerName, category)
        local db = DesolateLootcouncil.db.profile
        if not db.PriorityLists then return 999 end

        -- Resolve Alt -> Main
        local searchName = playerName
        local linkedMain = GetLinkedMain(playerName)
        if linkedMain then
            searchName = linkedMain
        end

        for _, list in ipairs(db.PriorityLists) do
            if list.name == category then
                for rank, pName in ipairs(list.players) do
                    if pName == searchName then return rank end
                end
            end
        end
        return 999
    end

    local voteList = {}
    if votes then
        for voter, voteData in pairs(votes) do
            local vType = type(voteData) == "table" and voteData.type or voteData
            local vRoll = (type(voteData) == "table" and voteData.roll) or 0

            if vType ~= 4 then
                local rank = GetPlayerRank(voter, itemData.category)
                table.insert(voteList, { name = voter, type = vType, roll = vRoll, rank = rank })
            end
        end

        table.sort(voteList, function(a, b)
            if a.type ~= b.type then return a.type < b.type end
            if a.type == 1 then
                if a.rank ~= b.rank then return a.rank < b.rank end
                return a.roll > b.roll
            end
            return a.roll > b.roll
        end)
    end

    local VOTE_COLOR = { [1] = "|cff00ff00", [2] = "|cffffd700", [3] = "|cffeda55f", [4] = "|cffaaaaaa" }
    local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "TM", [4] = "Pass" }

    if #voteList == 0 then
        ---@type AceGUILabel
        local lbl = AceGUI:Create("Label") --[[@as AceGUILabel]]
        lbl:SetText("No active votes.")
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    else
        for _, v in ipairs(voteList) do
            ---@type AceGUISimpleGroup
            local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            row:SetLayout("Flow")
            row:SetFullWidth(true)
            scroll:AddChild(row)

            ---@type AceGUILabel
            local lblName = AceGUI:Create("Label") --[[@as AceGUILabel]]
            lblName:SetText(v.name)
            lblName:SetRelativeWidth(0.30)
            row:AddChild(lblName)

            local rankText = ""
            if v.type == 1 then
                rankText = (v.rank == 999) and "|cff9d9d9dUnranked|r" or ("#" .. v.rank)
                if v.rank <= 5 then rankText = "|cffffd700" .. rankText .. "|r" end
            else
                rankText = "Roll: " .. v.roll
            end

            ---@type AceGUILabel
            local lblRank = AceGUI:Create("Label") --[[@as AceGUILabel]]
            lblRank:SetText(rankText)
            lblRank:SetRelativeWidth(0.20)
            row:AddChild(lblRank)

            ---@type AceGUILabel
            local lblResp = AceGUI:Create("Label") --[[@as AceGUILabel]]
            local color = VOTE_COLOR[v.type] or ""
            local txt = VOTE_TEXT[v.type] or "?"
            lblResp:SetText(color .. txt .. "|r")
            lblResp:SetRelativeWidth(0.25)
            row:AddChild(lblResp)

            ---@type AceGUIButton
            local btnGive = AceGUI:Create("Button") --[[@as AceGUIButton]]
            btnGive:SetText("Give")
            btnGive:SetRelativeWidth(0.25)
            btnGive:SetCallback("OnClick", function()
                self.awardFrame:Hide()
                local Loot = DesolateLootcouncil:GetModule("Loot")
                if Loot and Loot.AwardItem then
                    local voteDesc = VOTE_TEXT[v.type] or "Unknown"
                    Loot:AwardItem(itemData.sourceGUID, v.name, voteDesc)
                end
            end)
            row:AddChild(btnGive)
        end
    end

    -- [NEW] Disenchanters Section
    local Comm = DesolateLootcouncil:GetModule("Comm")
    local disenchanters = {}

    if Comm and Comm.playerEnchantingSkill then
        for name, skill in pairs(Comm.playerEnchantingSkill) do
            if skill > 0 then
                table.insert(disenchanters, { name = name, skill = skill })
            end
        end
        table.sort(disenchanters, function(a, b) return a.skill > b.skill end)
    end
    -- [DEBUG]
    DesolateLootcouncil:DLC_Log("Monitor: Disenchanters found: " .. #disenchanters)

    if #disenchanters > 0 then
        ---@type AceGUILabel
        local deHeader = AceGUI:Create("Label") --[[@as AceGUILabel]]
        deHeader:SetText("\n|cffaaaaaaDisenchanters|r")
        deHeader:SetFullWidth(true)
        deHeader:SetJustifyH("CENTER")
        deHeader:SetFontObject(GameFontNormal)
        scroll:AddChild(deHeader)

        for _, de in ipairs(disenchanters) do
            ---@type AceGUISimpleGroup
            local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            row:SetLayout("Flow")
            row:SetFullWidth(true)
            scroll:AddChild(row)

            ---@type AceGUILabel
            local lblName = AceGUI:Create("Label") --[[@as AceGUILabel]]
            lblName:SetText(de.name)
            lblName:SetRelativeWidth(0.30)
            row:AddChild(lblName)

            ---@type AceGUILabel
            local lblSkill = AceGUI:Create("Label") --[[@as AceGUILabel]]
            lblSkill:SetText("Lvl " .. de.skill)
            lblSkill:SetRelativeWidth(0.45)
            row:AddChild(lblSkill)

            ---@type AceGUIButton
            local btnGive = AceGUI:Create("Button") --[[@as AceGUIButton]]
            btnGive:SetText("Give")
            btnGive:SetRelativeWidth(0.25)
            btnGive:SetCallback("OnClick", function()
                self.awardFrame:Hide()
                local Loot = DesolateLootcouncil:GetModule("Loot")
                if Loot and Loot.AwardItem then
                    Loot:AwardItem(itemData.sourceGUID, de.name, "Disenchant")
                end
            end)
            row:AddChild(btnGive)
        end
    end
end

function UI_Monitor:CloseMasterLootWindow()
    if self.monitorFrame then self.monitorFrame:Hide() end
end

UI_Monitor.ShowMasterLootWindow = UI_Monitor.ShowMonitorWindow
