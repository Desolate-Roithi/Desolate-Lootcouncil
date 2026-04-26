local _, AT = ...
if AT.abortLoad then return end

---@class UI_Monitor : AceModule
local UI_Monitor = DesolateLootcouncil:NewModule("UI_Monitor", "AceEvent-3.0", "AceTimer-3.0")
local AceGUI = LibStub("AceGUI-3.0")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]

-- [REMOVED] Redundant GetLinkedMain. Use DesolateLootcouncil:GetModule("Roster"):GetMain(name) instead.

local VOTE_COLOR = { [1] = "|cff00ff00", [2] = "|cffffd700", [3] = "|cff00ffff", [4] = "|cffeda55f", [5] = "|cffaaaaaa" }
local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "OS", [4] = "TM", [5] = "Pass" }

function UI_Monitor:GetVoteInfo(guid)
    local SessionData = DesolateLootcouncil:GetModule("Session")
    local isClosed = SessionData and SessionData.closedItems and SessionData.closedItems[guid]
    local votes = SessionData and SessionData.sessionVotes and SessionData.sessionVotes[guid] or {}

    local bids, rolls, os, tm, pass = 0, 0, 0, 0, 0
    local votedPlayers = {}
    for name, voteData in pairs(votes) do
        local vType = type(voteData) == "table" and voteData.type or voteData
        if vType == 1 then bids = bids + 1
        elseif vType == 2 then rolls = rolls + 1
        elseif vType == 3 then os = os + 1
        elseif vType == 4 then tm = tm + 1
        elseif vType == 5 then pass = pass + 1 end
        -- Use normalized name for lookup consistency
        local score = DesolateLootcouncil:GetScoreName(name)
        if score then votedPlayers[score] = true end
    end

    local countsText = string.format("|cff00ff00Bid:%d|r | |cffffd700Roll:%d|r | |cff00ffffOS:%d|r | |cffeda55fTM:%d|r | |cffaaaaaaPass:%d|r", bids, rolls, os, tm, pass)

    if isClosed then return countsText .. " |cffff0000[Closed]|r", {} end

    local pending = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local fullName = DesolateLootcouncil:GetFullName("raid" .. i)
            local score = DesolateLootcouncil:GetScoreName(fullName)
            if score and not votedPlayers[score] then table.insert(pending, DesolateLootcouncil:GetDisplayName(fullName)) end
        end
    elseif IsInGroup() then
        local myFullName = DesolateLootcouncil:GetFullName("player")
        local myScore = DesolateLootcouncil:GetScoreName(myFullName)
        if myScore and not votedPlayers[myScore] then table.insert(pending, DesolateLootcouncil:GetDisplayName(myFullName)) end

        for i = 1, GetNumSubgroupMembers() do
            local fullName = DesolateLootcouncil:GetFullName("party" .. i)
            local score = DesolateLootcouncil:GetScoreName(fullName)
            if score and not votedPlayers[score] then table.insert(pending, DesolateLootcouncil:GetDisplayName(fullName)) end
        end
    else
        local myFullName = DesolateLootcouncil:GetFullName("player")
        local myScore = DesolateLootcouncil:GetScoreName(myFullName)
        if myScore and not votedPlayers[myScore] then table.insert(pending, DesolateLootcouncil:GetDisplayName(myFullName)) end
    end

    local Sim = DesolateLootcouncil:GetModule("Simulation")
    if Sim and Sim.GetPendingVoters then
        local simPending = Sim:GetPendingVoters(guid)
        if simPending then
            for _, sName in ipairs(simPending) do table.insert(pending, DesolateLootcouncil:GetDisplayName(sName)) end
        end
    end

    if #pending > 0 then countsText = countsText .. " |cffaaaaaa(Pending: " .. #pending .. ")|r" end
    return countsText, pending
end

function UI_Monitor:BuildItemRow(scroll, item, isLM)
    local link = item.link
    local guid = item.sourceGUID or link

    local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    group:SetLayout("Flow")
    group:SetFullWidth(true)
    scroll:AddChild(group)

    local itemIcon = AceGUI:Create("Icon")
    itemIcon:SetImage(C_Item.GetItemIconByID(item.itemID) or 134400)
    itemIcon:SetImageSize(24, 24)
    itemIcon:SetRelativeWidth(0.05)
    itemIcon:SetCallback("OnClick", function()
        GameTooltip:SetOwner((itemIcon --[[@as any]]).frame, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(item.link)
        GameTooltip:Show()
    end)
    itemIcon:SetCallback("OnEnter", function()
        GameTooltip:SetOwner((itemIcon --[[@as any]]).frame, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(item.link)
        GameTooltip:Show()
    end)
    itemIcon:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    group:AddChild(itemIcon)

    local labelLink = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
    local _, properLink = C_Item.GetItemInfo(link)
    if not properLink then
        local itemObj = Item:CreateFromItemID(item.itemID)
        if not itemObj:IsItemEmpty() then
            itemObj:ContinueOnItemLoad(function()
                if self.monitorFrame and (self.monitorFrame --[[@as any]]).frame:IsShown() then
                    self:ShowMonitorWindow()
                end
            end)
        end
        labelLink:SetText("Loading...")
    else
        labelLink:SetText(properLink)
        itemIcon:SetImage(C_Item.GetItemIconByID(item.itemID) or 134400)
    end
    labelLink:SetRelativeWidth(0.35)
    labelLink:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner((widget --[[@as any]]).frame, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(item.link)
        GameTooltip:Show()
    end)
    labelLink:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    group:AddChild(labelLink)

    local countsText, pendingList = self:GetVoteInfo(guid)

    local labelCounts = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
    labelCounts:SetText(countsText)
    labelCounts:SetRelativeWidth(0.35)

    if #pendingList > 0 then
        labelCounts:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner((widget --[[@as any]]).frame, "ANCHOR_CURSOR")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Still Pending Response:", 1, 1, 1)
            for _, name in ipairs(pendingList) do
                GameTooltip:AddLine("- " .. name, 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        labelCounts:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    end
    group:AddChild(labelCounts)

    local btnAward = AceGUI:Create("Button") --[[@as AceGUIButton]]
    btnAward:SetText(isLM and "Award" or "View Rolls")
    btnAward:SetRelativeWidth(0.15)
    btnAward:SetCallback("OnClick", function()
        self:ShowAwardWindow(item)
    end)
    group:AddChild(btnAward)

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
    if isLM then group:AddChild(btnRemove) end
end

function UI_Monitor:ShowMonitorWindow(isRefresh)
    if not self.monitorFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Session Monitor")
        frame:SetLayout("Flow")
        frame:SetWidth(650)
        frame:SetHeight(400)
        frame:SetCallback("OnClose", function(widget)
            self.userClosedMonitor = true -- B3: Track user-intent close vs system close
            widget:Hide()
        end)
        self.monitorFrame = frame

        -- [NEW] Position Persistence
        DesolateLootcouncil.Persistence:RestoreFramePosition(frame, "Monitor")
        local function SavePos(f)
            DesolateLootcouncil.Persistence:SaveFramePosition(f, "Monitor")
        end
        local rawFrame = (frame --[[@as any]]).frame
        rawFrame:HookScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            SavePos(frame)
        end)
        rawFrame:HookScript("OnHide", function() SavePos(frame) end)
        DesolateLootcouncil.Persistence:ApplyCollapseHook(frame, "Monitor")
    end

    if not isRefresh then
        -- B3: Clear the user-close flag when a new session explicitly opens the window
        self.userClosedMonitor = false
        self.monitorFrame:Show()
        -- Ensure window is maximized if it was previously collapsed
        local frame = (self.monitorFrame --[[@as any]]).frame
        if frame then
            frame.startCollapsed = nil -- Cancel initial hook timer
            if frame.isCollapsed then
                DesolateLootcouncil.Persistence:ToggleWindowCollapse(self.monitorFrame)
            end
        end
    elseif self.userClosedMonitor then
        return -- Respect user's explicit close during refresh cycles
    elseif not (self.monitorFrame.frame and self.monitorFrame.frame:IsShown()) then
        return -- Window hidden by system but not yet re-opened by new session
    end

    self.monitorFrame:ReleaseChildren()

    local session = DesolateLootcouncil.db.profile.session
    local isLM = DesolateLootcouncil:AmILootMaster()
    local SessionInfo = DesolateLootcouncil:GetModule("Session")
    local items = isLM and session.bidding or (SessionInfo and SessionInfo.clientLootList or {})
    local parent = (self.monitorFrame --[[@as any]]).frame

    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.monitorFrame:AddChild(scroll)

    if items then
        for _, item in ipairs(items) do
            self:BuildItemRow(scroll, item, isLM)
        end
    end

    local mFrame = self.monitorFrame --[[@as any]]
    local isCollapsed = mFrame.frame and mFrame.frame.isCollapsed

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
    -- Bug 2: Only show footer buttons when not collapsed AND LM only for trades
    if not isCollapsed and isLM then mFrame.btnTrades:Show() else mFrame.btnTrades:Hide() end

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
    -- Bug 2: Only show footer buttons when not collapsed
    if not isCollapsed and isLM then mFrame.btnEnd:Show() else mFrame.btnEnd:Hide() end

    local function LayoutMonitor()
        local rawFrame = (self.monitorFrame --[[@as any]]).frame
        local h = rawFrame:GetHeight()
        local isCollapsedNow = rawFrame.isCollapsed

        -- Safety: If collapsed, don't try to layout the scroll frame with negative size
        if h > 80 and not isCollapsedNow then
            local scrollFrame = scroll and (scroll --[[@as any]]).frame
            if scrollFrame then
                scroll:SetHeight(h - 80)
                scrollFrame:Show()
            end
        else
            local scrollFrame = scroll and (scroll --[[@as any]]).frame
            if scrollFrame then scrollFrame:Hide() end
        end

        self.monitorFrame:DoLayout()
        -- Sync Sidebar: only drive visibility from collapsed state;
        -- UpdateDisenchanters owns the show/hide when data is present.
        if self.deFrame then
            self.deFrame:SetHeight(h)
            if isCollapsedNow then 
                self.deFrame:Hide() 
            else
                self:UpdateDisenchanters()
            end
        end
    end
    -- Store on self so Persistence.ToggleWindowCollapse can re-trigger it after expand.
    self.layoutMonitor = LayoutMonitor
    LayoutMonitor()
    self.monitorFrame:SetCallback("OnResize", LayoutMonitor)

    -- [NEW] Disenchanter Sidebar (External Widget)
    if not self.deFrame then
        local Sidebar = DesolateLootcouncil:GetModule("UI_Sidebar")
        if Sidebar then
            self.deFrame = Sidebar:AttachTo(self.monitorFrame)
        end
    end
    self:UpdateDisenchanters()

    -- PROBLEM 15: ALWAYS call :Show() to ensure the window reappears (for both LMs and Assistants!)
    if self.monitorFrame then self.monitorFrame:Show() end
end

function UI_Monitor:OnEnable()
    -- Refresh sidebar whenever a version-check response arrives (enchanting skill data)
    self:RegisterMessage("DLC_VERSION_UPDATE", function()
        self:UpdateDisenchanters()
    end)
end

function UI_Monitor:UpdateDisenchanters()
    if not self.deFrame then return end
    local Sidebar = DesolateLootcouncil:GetModule("UI_Sidebar")
    if Sidebar then
        Sidebar:UpdateDisenchanters(self.deFrame)
    end
    
    -- Ensure the sidebar doesn't show up if the monitor is currently collapsed
    local mFrame = self.monitorFrame and (self.monitorFrame --[[@as any]]).frame
    if mFrame and mFrame.isCollapsed then
        self.deFrame:Hide()
    end
end
function UI_Monitor:CreateVoteRow(scroll, v, isLM, itemData)
    local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    scroll:AddChild(row)

    local lblName = AceGUI:Create("Label") --[[@as AceGUILabel]]
    lblName:SetText(DesolateLootcouncil:GetDisplayName(v.name))
    lblName:SetRelativeWidth(0.30)
    row:AddChild(lblName)

    local rankText
    if v.type == 1 then
        rankText = (v.rank == 999) and "|cff9d9d9dUnranked|r" or ("#" .. v.rank)
        if v.rank <= 5 then rankText = "|cffffd700" .. rankText .. "|r" end
    else
        rankText = "Roll: " .. v.roll
    end

    local lblRank = AceGUI:Create("Label") --[[@as AceGUILabel]]
    lblRank:SetText(rankText)
    lblRank:SetRelativeWidth(0.20)
    row:AddChild(lblRank)

    local lblResp = AceGUI:Create("Label") --[[@as AceGUILabel]]
    local color = VOTE_COLOR[v.type] or ""
    local txt = VOTE_TEXT[v.type] or "?"
    lblResp:SetText(color .. txt .. "|r")
    lblResp:SetRelativeWidth(0.25)
    row:AddChild(lblResp)

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
    if isLM then row:AddChild(btnGive) end
end

function UI_Monitor:CreateDisenchanterRow(scroll, de, isLM, itemData)
    local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    scroll:AddChild(row)

    local lblName = AceGUI:Create("Label") --[[@as AceGUILabel]]
    lblName:SetText(DesolateLootcouncil:GetDisplayName(de.name))
    lblName:SetRelativeWidth(0.30)
    row:AddChild(lblName)

    local lblSkill = AceGUI:Create("Label") --[[@as AceGUILabel]]
    lblSkill:SetText("Lvl " .. de.skill)
    lblSkill:SetRelativeWidth(0.45)
    row:AddChild(lblSkill)

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
    if isLM then row:AddChild(btnGive) end
end

function UI_Monitor:ShowAwardWindow(itemData)
    if not itemData then
        if self.awardFrame then self.awardFrame:Hide() end
        return
    end

    -- B15: Hoist isLM to function scope — it's stable and was re-declared 3 times below
    local isLM = DesolateLootcouncil:AmILootMaster()

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
        DesolateLootcouncil.Persistence:RestoreFramePosition(frame, "Award")
        local function SavePos(f)
            DesolateLootcouncil.Persistence:SaveFramePosition(f, "Award")
        end
        local rawFrame = (frame --[[@as any]]).frame
        rawFrame:HookScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            SavePos(frame)
        end)
        rawFrame:HookScript("OnHide", function() SavePos(frame) end)
        DesolateLootcouncil.Persistence:ApplyCollapseHook(frame, "Award")
    end
    self.awardFrame:Show()
    self.awardFrame:ReleaseChildren()

    local catText = itemData.category and (" (" .. itemData.category .. ")") or ""
    ---@type AceGUILabel
    local header = AceGUI:Create("Label") --[[@as AceGUILabel]]

    local _, properLink = C_Item.GetItemInfo(itemData.link)
    header:SetText((properLink or itemData.link) .. "|cffaaaaaa" .. catText .. "|r")
    header:SetFullWidth(true)
    header:SetJustifyH("CENTER")
    header:SetFontObject(GameFontNormalLarge)
    self.awardFrame:AddChild(header)

    local Session = DesolateLootcouncil:GetModule("Session")
    local guid = itemData.sourceGUID or itemData.link
    local votes = Session and Session.sessionVotes and Session.sessionVotes[guid]

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
        local Roster = DesolateLootcouncil:GetModule("Roster")
        local searchName = Roster and Roster:GetMain(playerName) or playerName
        local searchScore = DesolateLootcouncil:GetScoreName(searchName)

        for _, list in ipairs(db.PriorityLists) do
            if list.name == category then
                for rank, pName in ipairs(list.players) do
                    if DesolateLootcouncil:GetScoreName(pName) == searchScore then return rank end
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

            if vType ~= 5 then
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

    if #voteList == 0 then
        local lbl = AceGUI:Create("Label") --[[@as AceGUILabel]]
        lbl:SetText("No active votes.")
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    else
        for _, v in ipairs(voteList) do
            self:CreateVoteRow(scroll, v, isLM, itemData)
        end
    end

    -- [NEW] Disenchanters Section
    local Comm = DesolateLootcouncil:GetModule("Comm")
    local disenchanters = {}

    if Comm and Comm.playerEnchantingSkill then
        for name, skill in pairs(Comm.playerEnchantingSkill) do
            if skill > 0 then
                local inGroup = false
                if DesolateLootcouncil:IsUnitInRaid(name) then
                    inGroup = true
                else
                    -- Fallback: Blizzard API might expect the short name for local-realm players
                    local shortName = Ambiguate(name, "none")
                    if UnitInRaid(shortName) or UnitInParty(shortName) then
                        inGroup = true
                    end
                end

                if inGroup then
                    table.insert(disenchanters, { name = name, skill = skill })
                end
            end
        end
        table.sort(disenchanters, function(a, b) return a.skill > b.skill end)
    end
    if DesolateLootcouncil.db.profile.debugMode then
        DesolateLootcouncil:DLC_Log("Monitor: Disenchanters found: " .. #disenchanters)
    end

    if #disenchanters > 0 then
        ---@type AceGUILabel
        local deHeader = AceGUI:Create("Label") --[[@as AceGUILabel]]
        deHeader:SetText("\n|cffaaaaaaDisenchanters|r")
        deHeader:SetFullWidth(true)
        deHeader:SetJustifyH("CENTER")
        deHeader:SetFontObject(GameFontNormal)
        scroll:AddChild(deHeader)

        for _, de in ipairs(disenchanters) do
            self:CreateDisenchanterRow(scroll, de, isLM, itemData)
        end
    end
end

function UI_Monitor:CloseMasterLootWindow()
    if self.monitorFrame then self.monitorFrame:Hide() end
end

UI_Monitor.ShowMasterLootWindow = UI_Monitor.ShowMonitorWindow
