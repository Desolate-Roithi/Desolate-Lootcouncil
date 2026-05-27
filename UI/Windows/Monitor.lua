local _, AT = ...
if AT.abortLoad then return end

---@class UI_Monitor : AceModule
local UI_Monitor = DesolateLootcouncil:NewModule("UI_Monitor", "AceEvent-3.0", "AceTimer-3.0")
local AceGUI = LibStub("AceGUI-3.0")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local VOTE_COLOR = { [1] = "|cff00ff00", [2] = "|cffffd700", [3] = "|cff00ffff", [4] = "|cffeda55f", [5] = "|cffaaaaaa" }
local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "OS", [4] = "TM", [5] = "Pass" }

function UI_Monitor:GetVoteInfo(guid)
    local API = DesolateLootcouncil.API
    local summary  = API:GetVoteSummary(guid)
    local votes    = summary.votes
    local isClosed = summary.isClosed

    local bids, rolls, os, tm, pass = 0, 0, 0, 0, 0
    local votedPlayers = {}
    for name, voteData in pairs(votes) do
        local vType = type(voteData) == "table" and voteData.type or voteData
        if vType == 1 then bids = bids + 1
        elseif vType == 2 then rolls = rolls + 1
        elseif vType == 3 then os = os + 1
        elseif vType == 4 then tm = tm + 1
        elseif vType == 5 then pass = pass + 1 end
        local score = API:GetScoreName(name)
        if score then votedPlayers[score] = true end
    end

    local countsText = string.format("|cff00ff00Bid:%d|r | |cffffd700Roll:%d|r | |cff00ffffOS:%d|r | |cffeda55fTM:%d|r | |cffaaaaaaPass:%d|r", bids, rolls, os, tm, pass)

    if isClosed then return countsText .. " |cffff0000[Closed]|r", {} end

    local pending = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local fullName = API:GetFullName("raid" .. i)
            local score = API:GetScoreName(fullName)
            if score and not votedPlayers[score] then table.insert(pending, API:GetDisplayName(fullName)) end
        end
    elseif IsInGroup() then
        local myFullName = API:GetFullName("player")
        local myScore = API:GetScoreName(myFullName)
        if myScore and not votedPlayers[myScore] then table.insert(pending, API:GetDisplayName(myFullName)) end

        for i = 1, GetNumSubgroupMembers() do
            local fullName = API:GetFullName("party" .. i)
            local score = API:GetScoreName(fullName)
            if score and not votedPlayers[score] then table.insert(pending, API:GetDisplayName(fullName)) end
        end
    else
        local myFullName = API:GetFullName("player")
        local myScore = API:GetScoreName(myFullName)
        if myScore and not votedPlayers[myScore] then table.insert(pending, API:GetDisplayName(myFullName)) end
    end

    local Sim = DesolateLootcouncil:GetModule("Simulation")
    if Sim and Sim.GetPendingVoters then
        local simPending = Sim:GetPendingVoters(guid)
        if simPending then
            for _, sName in ipairs(simPending) do table.insert(pending, API:GetDisplayName(sName)) end
        end
    end

    if #pending > 0 then countsText = countsText .. " |cffaaaaaa(Pending: " .. #pending .. ")|r" end
    return countsText, pending
end

function UI_Monitor:BuildItemRow(scroll, item, isLM)
    local link = item.link
    local guid = item.sourceGUID or link
    local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme", true)

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
                    if self.refreshTimer then self.refreshTimer:Cancel() end
                    self.refreshTimer = C_Timer.NewTimer(0.15, function()
                        self.refreshTimer = nil
                        self:ShowMonitorWindow()
                    end)
                end
            end)
        end
        labelLink:SetText(L["Loading..."])
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
            GameTooltip:AddLine(L["Still Pending Response:"], 1, 1, 1)
            for _, name in ipairs(pendingList) do
                GameTooltip:AddLine("- " .. name, 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        labelCounts:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    end
    group:AddChild(labelCounts)

    local btnAward = AceGUI:Create("Button") --[[@as AceGUIButton]]
    btnAward:SetText(isLM and L["Award"] or L["View Rolls"])
    btnAward:SetRelativeWidth(0.15)
    btnAward:SetCallback("OnClick", function()
        self:ShowAwardWindow(item)
    end)
    group:AddChild(btnAward)
    if UI_Theme then UI_Theme:ApplyTheme(btnAward) end

    local btnRemove = AceGUI:Create("Button") --[[@as AceGUIButton]]
    btnRemove:SetText("X")
    btnRemove:SetRelativeWidth(0.10)
    btnRemove:SetCallback("OnClick", function()
        C_Timer.After(0.05, function()
            DesolateLootcouncil.API:RemoveSessionItem(guid)
        end)
    end)
    if isLM then
        group:AddChild(btnRemove)
        if UI_Theme then UI_Theme:ApplyTheme(btnRemove) end
    end
end

function UI_Monitor:ShowMonitorWindow(isRefresh)
    local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme", true)

    if not self.monitorFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle(L["Session Monitor"])
        frame:SetLayout("Flow")
        frame:SetWidth(650)
        frame:SetHeight(400)
        frame:SetCallback("OnClose", function(widget)
            self.userClosedMonitor = true
            widget:Hide()
        end)
        self.monitorFrame = frame

        -- [NEW] Position Persistence
        DesolateLootcouncil.Persistence:MakeMovableWithSave(frame, "Monitor")
    end

    if UI_Theme then
        UI_Theme:ApplyTheme(self.monitorFrame)
    end

    if not isRefresh then
        self.userClosedMonitor = false
        self.monitorFrame:Show()
        local frame = (self.monitorFrame --[[@as any]]).frame
        if frame then
            frame.startCollapsed = nil
            if frame.isCollapsed then
                DesolateLootcouncil.Persistence:ToggleWindowCollapse(self.monitorFrame)
            end
        end
    elseif self.userClosedMonitor then
        return
    elseif not (self.monitorFrame.frame and self.monitorFrame.frame:IsShown()) then
        return
    end

    self.monitorFrame:ReleaseChildren()

    local API = DesolateLootcouncil.API
    local isLM = API:IsLootMaster()
    local items = API:GetBiddingList()

    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.monitorFrame:AddChild(scroll)
    if UI_Theme then UI_Theme:ApplyTheme(scroll) end

    if items then
        for _, item in ipairs(items) do
            self:BuildItemRow(scroll, item, isLM)
        end
    end

    -- P15: Control Hub Navigation Menu (Dynamic footer layout)
    ---@type AceGUISimpleGroup
    local navGroup = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    navGroup:SetLayout("Flow")
    navGroup:SetFullWidth(true)
    self.monitorFrame:AddChild(navGroup)

    -- Trades
    local btnTrades = AceGUI:Create("Button")
    btnTrades:SetText(L["Pending Trades"])
    btnTrades:SetWidth(110)
    btnTrades:SetCallback("OnClick", function()
        local Trade = DesolateLootcouncil:GetModule("UI_TradeList", true)
        if Trade then Trade:ShowTradeListWindow() end
    end)
    navGroup:AddChild(btnTrades)
    if UI_Theme then UI_Theme:ApplyTheme(btnTrades) end

    -- Backlog / Collection
    local btnLoot = AceGUI:Create("Button")
    btnLoot:SetText(L["Loot Backlog"])
    btnLoot:SetWidth(100)
    btnLoot:SetCallback("OnClick", function()
        local LootUI = DesolateLootcouncil:GetModule("UI_Loot", true)
        if LootUI then LootUI:ShowLootWindow(DesolateLootcouncil.db.profile.session.loot) end
    end)
    navGroup:AddChild(btnLoot)
    if UI_Theme then UI_Theme:ApplyTheme(btnLoot) end

    -- History
    local btnHist = AceGUI:Create("Button")
    btnHist:SetText(L["History"])
    btnHist:SetWidth(80)
    btnHist:SetCallback("OnClick", function()
        local History = DesolateLootcouncil:GetModule("UI_History", true)
        if History then History:ShowHistoryWindow() end
    end)
    navGroup:AddChild(btnHist)
    if UI_Theme then UI_Theme:ApplyTheme(btnHist) end

    -- Attendance
    local btnAttend = AceGUI:Create("Button")
    btnAttend:SetText(L["Attendance"])
    btnAttend:SetWidth(95)
    btnAttend:SetCallback("OnClick", function()
        local Attendance = DesolateLootcouncil:GetModule("UI_Attendance", true)
        if Attendance then Attendance:ShowAttendanceWindow() end
    end)
    navGroup:AddChild(btnAttend)
    if UI_Theme then UI_Theme:ApplyTheme(btnAttend) end

    -- Version Check
    local btnVer = AceGUI:Create("Button")
    btnVer:SetText(L["Version Check"])
    btnVer:SetWidth(110)
    btnVer:SetCallback("OnClick", function()
        local Version = DesolateLootcouncil:GetModule("UI_Version", true)
        if Version then Version:ShowVersionWindow() end
    end)
    navGroup:AddChild(btnVer)
    if UI_Theme then UI_Theme:ApplyTheme(btnVer) end

    -- Stop Session (LM only)
    if isLM then
        local btnStop = AceGUI:Create("Button")
        btnStop:SetText(L["Stop Session"])
        btnStop:SetWidth(110)
        btnStop:SetCallback("OnClick", function()
            DesolateLootcouncil.API:StopSession()
        end)
        navGroup:AddChild(btnStop)
        if UI_Theme then
            UI_Theme:ApplyTheme(btnStop)
            -- Custom glowing red border/hover for termination button
            btnStop.frame:SetBackdropBorderColor(0.8, 0.2, 0.2, 1.0)
        end
    end

    local function LayoutMonitor()
        local rawFrame = (self.monitorFrame --[[@as any]]).frame
        local h = rawFrame:GetHeight()
        local isCollapsedNow = rawFrame.isCollapsed

        if h > 100 and not isCollapsedNow then
            local scrollFrame = scroll and (scroll --[[@as any]]).frame
            if scrollFrame then
                scroll:SetHeight(h - 100)
                scrollFrame:Show()
            end
            if navGroup and navGroup.frame then navGroup.frame:Show() end
        else
            local scrollFrame = scroll and (scroll --[[@as any]]).frame
            if scrollFrame then scrollFrame:Hide() end
            if navGroup and navGroup.frame then navGroup.frame:Hide() end
        end

        self.monitorFrame:DoLayout()
        if self.deFrame then
            self.deFrame:SetHeight(h)
            if isCollapsedNow then 
                self.deFrame:Hide() 
            else
                self:UpdateDisenchanters()
            end
        end
    end

    self.layoutMonitor = LayoutMonitor
    LayoutMonitor()
    self.monitorFrame:SetCallback("OnResize", LayoutMonitor)

    -- Disenchanter Sidebar
    if not self.deFrame then
        local Sidebar = DesolateLootcouncil:GetModule("UI_Sidebar", true)
        if Sidebar then
            self.deFrame = Sidebar:AttachTo(self.monitorFrame)
        end
    end
    self:UpdateDisenchanters()

    if self.monitorFrame then self.monitorFrame:Show() end
end

function UI_Monitor:OnEnable()
    self:RegisterMessage("DLC_VERSION_UPDATE", function()
        self:UpdateDisenchanters()
    end)
    self:RegisterMessage("DLC_SESSION_STARTED", "OnSessionStarted")
    self:RegisterMessage("DLC_SESSION_STOPPED", "OnSessionStopped")
    self:RegisterMessage("DLC_SESSION_RESTORED", "OnSessionRestored")
    self:RegisterMessage("DLC_ITEM_REMOVED", "OnItemRemoved")
end

function UI_Monitor:OnSessionStarted(eventName, cleanList, isLM)
    if isLM then
        self:ShowMonitorWindow()
    end
end

function UI_Monitor:OnSessionStopped()
    if self.monitorFrame then self.monitorFrame:Hide() end
    if self.awardFrame then self.awardFrame:Hide() end
end

function UI_Monitor:OnSessionRestored(eventName, clientLootList, isLM)
    if isLM then
        self:ShowMonitorWindow()
    end
end

function UI_Monitor:OnItemRemoved(eventName, guid)
    self:ShowMonitorWindow(true)
end

function UI_Monitor:UpdateDisenchanters()
    if not self.deFrame then return end
    local Sidebar = DesolateLootcouncil:GetModule("UI_Sidebar", true)
    if Sidebar then
        Sidebar:UpdateDisenchanters(self.deFrame)
    end
    
    local mFrame = self.monitorFrame and (self.monitorFrame --[[@as any]]).frame
    if mFrame and mFrame.isCollapsed then
        self.deFrame:Hide()
    end
end

function UI_Monitor:CreateVoteRow(scroll, v, isLM, itemData)
    local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme", true)

    local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    scroll:AddChild(row)

    -- Player Name
    local lblName = AceGUI:Create("Label") --[[@as AceGUILabel]]
    lblName:SetText(DesolateLootcouncil:GetDisplayName(v.name))
    lblName:SetRelativeWidth(0.26)
    row:AddChild(lblName)

    -- Rank / Roll value
    local rankText
    if v.type == 1 then
        rankText = (v.rank == 999) and "|cff9d9d9d" .. L["Unranked"] .. "|r" or ("#" .. v.rank)
        if v.rank <= 5 then rankText = "|cffffd700" .. rankText .. "|r" end
    else
        rankText = "Roll: " .. v.roll
    end

    local lblRank = AceGUI:Create("Label") --[[@as AceGUILabel]]
    lblRank:SetText(rankText)
    lblRank:SetRelativeWidth(0.14)
    row:AddChild(lblRank)

    -- Bid Response pill
    local lblResp = AceGUI:Create("Label") --[[@as AceGUILabel]]
    local color = VOTE_COLOR[v.type] or ""
    local txt = VOTE_TEXT[v.type] or "?"
    lblResp:SetText(color .. txt .. "|r")
    lblResp:SetRelativeWidth(0.18)
    row:AddChild(lblResp)

    -- Voter Custom Note (Gold/Tan typography)
    local lblNote = AceGUI:Create("Label") --[[@as AceGUILabel]]
    if v.note and v.note ~= "" then
        lblNote:SetText("|cffc79c6e" .. v.note .. "|r")
    else
        lblNote:SetText("")
    end
    lblNote:SetRelativeWidth(0.22)
    row:AddChild(lblNote)

    -- Give item button
    local btnGive = AceGUI:Create("Button") --[[@as AceGUIButton]]
    btnGive:SetText(L["Give"])
    btnGive:SetRelativeWidth(0.20)
    btnGive:SetCallback("OnClick", function()
        self.awardFrame:Hide()
        local voteDesc = VOTE_TEXT[v.type] or "Unknown"
        DesolateLootcouncil.API:AwardItem(itemData.sourceGUID, v.name, voteDesc)
    end)
    if isLM then
        row:AddChild(btnGive)
        if UI_Theme then UI_Theme:ApplyTheme(btnGive) end
    end
end

function UI_Monitor:CreateDisenchanterRow(scroll, de, isLM, itemData)
    local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme", true)

    local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    scroll:AddChild(row)

    local lblName = AceGUI:Create("Label") --[[@as AceGUILabel]]
    lblName:SetText(DesolateLootcouncil:GetDisplayName(de.name))
    lblName:SetRelativeWidth(0.30)
    row:AddChild(lblName)

    local lblSkill = AceGUI:Create("Label") --[[@as AceGUILabel]]
    lblSkill:SetText(string.format(L["Lvl %d"], de.skill))
    lblSkill:SetRelativeWidth(0.45)
    row:AddChild(lblSkill)

    local btnGive = AceGUI:Create("Button") --[[@as AceGUIButton]]
    btnGive:SetText(L["Give"])
    btnGive:SetRelativeWidth(0.25)
    btnGive:SetCallback("OnClick", function()
        self.awardFrame:Hide()
        DesolateLootcouncil.API:AwardItem(itemData.sourceGUID, de.name, "Disenchant")
    end)
    if isLM then
        row:AddChild(btnGive)
        if UI_Theme then UI_Theme:ApplyTheme(btnGive) end
    end
end

function UI_Monitor:ShowAwardWindow(itemData)
    if not itemData then
        if self.awardFrame then self.awardFrame:Hide() end
        return
    end

    local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme", true)
    local isLM = DesolateLootcouncil.API:IsLootMaster()

    if not self.awardFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle(L["Award Item"])
        frame:SetLayout("Flow")
        frame:SetWidth(500)
        frame:SetHeight(500)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.awardFrame = frame

        -- [NEW] Position Persistence
        DesolateLootcouncil.Persistence:MakeMovableWithSave(frame, "Award")
    end

    if UI_Theme then
        UI_Theme:ApplyTheme(self.awardFrame)
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

    local API  = DesolateLootcouncil.API
    local guid = itemData.sourceGUID or itemData.link
    local summary = API:GetVoteSummary(guid)
    local votes   = summary.votes

    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    self.awardFrame:AddChild(scroll)
    if UI_Theme then UI_Theme:ApplyTheme(scroll) end

    local voteList = {}
    if votes then
        for voter, voteData in pairs(votes) do
            local vType = type(voteData) == "table" and voteData.type or voteData
            local vRoll = (type(voteData) == "table" and voteData.roll) or 0
            local vNote = (type(voteData) == "table" and voteData.note) or ""

            if vType ~= 5 then
                local rank = API:GetPlayerRankInList(voter, itemData.category)
                table.insert(voteList, { name = voter, type = vType, roll = vRoll, rank = rank, note = vNote })
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
        lbl:SetText(L["No active votes."])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    else
        for _, v in ipairs(voteList) do
            self:CreateVoteRow(scroll, v, isLM, itemData)
        end
    end

    -- Disenchanters Section
    local disenchanters = API:GetDisenchanterList()
    if DesolateLootcouncil.db.profile.debugMode then
        DesolateLootcouncil:DLC_Log("Monitor: Disenchanters found: " .. #disenchanters)
    end

    if #disenchanters > 0 then
        ---@type AceGUILabel
        local deHeader = AceGUI:Create("Label") --[[@as AceGUILabel]]
        deHeader:SetText("\n|cffaaaaaa" .. L["Disenchanters"] .. "|r")
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
