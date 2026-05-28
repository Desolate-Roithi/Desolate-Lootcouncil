local _, AT = ...
if AT.abortLoad then return end

---@class UI_Monitor : AceModule
local UI_Monitor = DesolateLootcouncil:NewModule("UI_Monitor", "AceEvent-3.0", "AceTimer-3.0")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
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

function UI_Monitor:BuildItemRow(index, item, isLM)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local link = item.link
    local guid = item.sourceGUID or link

    if not self.rowPool[index] then
        self.rowPool[index] = NativeGUI:CreateRowContainer(self.scrollContent, false)
    end
    local row = self.rowPool[index]
    row:Show()

    local rowHeight = 36
    row:SetHeight(rowHeight)

    local topOffset = (index - 1) * (rowHeight + 8)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
    row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

    -- 1. Icon
    if not row.itemIcon then
        local icon = CreateFrame("Button", nil, row)
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 8, 0)
        
        local tex = icon:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        icon.texture = tex
        
        row.itemIcon = icon
    end
    row.itemIcon.texture:SetTexture(C_Item.GetItemIconByID(item.itemID) or 134400)

    local function ShowTip()
        GameTooltip:SetOwner(row.itemIcon, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(item.link)
        GameTooltip:Show()
    end
    row.itemIcon:SetScript("OnClick", ShowTip)
    row.itemIcon:SetScript("OnEnter", ShowTip)
    row.itemIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 4. Action buttons (defined early for right anchoring target)
    if not row.actionFrame then
        row.actionFrame = CreateFrame("Frame", nil, row)
    end
    row.actionFrame:ClearAllPoints()
    row.actionFrame:SetSize(115, 26)
    row.actionFrame:SetPoint("RIGHT", row, "RIGHT", -12, 0)

    local kids = { row.actionFrame:GetChildren() }
    for _, kid in ipairs(kids) do
        kid:Hide()
        kid:ClearAllPoints()
    end

    local btnAward = NativeGUI:CreateButton(row.actionFrame, isLM and L["Award"] or L["View Rolls"], 75, 24, "Bid")
    btnAward:SetPoint("LEFT", 0, 0)
    btnAward:SetScript("OnClick", function()
        self:ShowAwardWindow(item)
    end)

    if isLM then
        local btnRemove = NativeGUI:CreateButton(row.actionFrame, "X", 32, 24, "Stop")
        btnRemove:SetPoint("LEFT", 80, 0)
        btnRemove:SetScript("OnClick", function()
            C_Timer.After(0.05, function()
                DesolateLootcouncil.API:RemoveSessionItem(guid)
            end)
        end)
    end

    -- 3. Vote Counts & Pending response
    local countsText, pendingList = self:GetVoteInfo(guid)

    if not row.countsFrame then
        local cf = CreateFrame("Frame", nil, row)
        cf:SetSize(220, 20)
        
        local text = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", 0, 0)
        text:SetPoint("RIGHT", 0, 0)
        text:SetJustifyH("RIGHT")
        cf.text = text
        
        row.countsFrame = cf
    end
    row.countsFrame:ClearAllPoints()
    row.countsFrame:SetPoint("RIGHT", row.actionFrame, "LEFT", -15, 0)
    row.countsFrame.text:SetText(countsText)

    if #pendingList > 0 then
        row.countsFrame:EnableMouse(true)
        row.countsFrame:SetScript("OnEnter", function(w)
            GameTooltip:SetOwner(w, "ANCHOR_CURSOR")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["Still Pending Response:"], 1, 1, 1)
            for _, name in ipairs(pendingList) do
                GameTooltip:AddLine("- " .. name, 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        row.countsFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        row.countsFrame:EnableMouse(false)
        row.countsFrame:SetScript("OnEnter", nil)
    end

    -- 2. Link Label (sandwiched in-between LEFT and RIGHT anchors)
    if not row.itemLabel then
        local lbl = CreateFrame("Button", nil, row)
        lbl:SetHeight(20)
        
        local text = lbl:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", 0, 0)
        text:SetPoint("RIGHT", 0, 0)
        text:SetJustifyH("LEFT")
        lbl.text = text
        
        row.itemLabel = lbl
    end
    row.itemLabel:ClearAllPoints()
    row.itemLabel:SetPoint("LEFT", row.itemIcon, "RIGHT", 10, 0)
    row.itemLabel:SetPoint("RIGHT", row.countsFrame, "LEFT", -15, 0)

    local _, properLink = C_Item.GetItemInfo(link)
    if not properLink then
        local itemObj = Item:CreateFromItemID(item.itemID)
        if not itemObj:IsItemEmpty() then
            itemObj:ContinueOnItemLoad(function()
                if self.monitorFrame and self.monitorFrame:IsShown() then
                    if self.refreshTimer then self.refreshTimer:Cancel() end
                    self.refreshTimer = C_Timer.NewTimer(0.15, function()
                        self.refreshTimer = nil
                        self:ShowMonitorWindow(true)
                    end)
                end
            end)
        end
        row.itemLabel.text:SetText(L["Loading..."])
    else
        row.itemLabel.text:SetText(properLink)
        row.itemIcon.texture:SetTexture(C_Item.GetItemIconByID(item.itemID) or 134400)
    end
    row.itemLabel:SetScript("OnClick", ShowTip)
    row.itemLabel:SetScript("OnEnter", ShowTip)
    row.itemLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.scrollContent:SetHeight(topOffset + rowHeight + 10)
end

function UI_Monitor:ShowMonitorWindow(isRefresh)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.monitorFrame then
        local frame = NativeGUI:CreateWindow("DLCMonitorFrame", L["Session Monitor"], 650, 400, "Monitor")
        frame:HookScript("OnHide", function()
            self.userClosedMonitor = true
        end)
        self.monitorFrame = frame
        self.rowPool = {}
    end

    if not isRefresh then
        self.userClosedMonitor = false
        self.monitorFrame:Show()
    elseif self.userClosedMonitor then
        return
    elseif not self.monitorFrame:IsShown() then
        return
    end

    -- Hide sizers or old elements safely
    for _, row in ipairs(self.rowPool) do
        row:Hide()
        row:ClearAllPoints()
    end

    local API = DesolateLootcouncil.API
    local isLM = API:IsLootMaster()
    local items = API:GetBiddingList()

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.monitorFrame, -50, -46)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end
    self.scrollFrame:Show()
    self.scrollContent:Show()

    if items then
        for i, item in ipairs(items) do
            self:BuildItemRow(i, item, isLM)
        end
    end

    -- Control Hub Navigation (Footer Bar)
    if not self.navGroup then
        local nav = CreateFrame("Frame", nil, self.monitorFrame)
        nav:SetHeight(38)
        nav:SetPoint("BOTTOMLEFT", self.monitorFrame, "BOTTOMLEFT", 12, 6)
        nav:SetPoint("BOTTOMRIGHT", self.monitorFrame, "BOTTOMRIGHT", -12, 6)
        self.navGroup = nav

        -- Reusable buttons
        self.btnTrades = NativeGUI:CreateButton(nav, L["Pending Trades"], 105, 24, "Pass")
        self.btnTrades:SetPoint("LEFT", 0, 0)
        self.btnTrades:SetScript("OnClick", function()
            local Trade = DesolateLootcouncil:GetModule("UI_TradeList", true)
            if Trade then Trade:ShowTradeListWindow() end
        end)

        self.btnLoot = NativeGUI:CreateButton(nav, L["Loot Backlog"], 90, 24, "Pass")
        self.btnLoot:SetPoint("LEFT", 110, 0)
        self.btnLoot:SetScript("OnClick", function()
            local LootUI = DesolateLootcouncil:GetModule("UI_Loot", true)
            if LootUI then LootUI:ShowLootWindow(DesolateLootcouncil.db.profile.session.loot) end
        end)

        self.btnHist = NativeGUI:CreateButton(nav, L["History"], 70, 24, "Pass")
        self.btnHist:SetPoint("LEFT", 205, 0)
        self.btnHist:SetScript("OnClick", function()
            local History = DesolateLootcouncil:GetModule("UI_History", true)
            if History then History:ShowHistoryWindow() end
        end)

        self.btnAttend = NativeGUI:CreateButton(nav, L["Attendance"], 85, 24, "Pass")
        self.btnAttend:SetPoint("LEFT", 280, 0)
        self.btnAttend:SetScript("OnClick", function()
            local Attendance = DesolateLootcouncil:GetModule("UI_Attendance", true)
            if Attendance then Attendance:ShowAttendanceWindow() end
        end)

        self.btnVer = NativeGUI:CreateButton(nav, L["Version Check"], 100, 24, "Pass")
        self.btnVer:SetPoint("LEFT", 370, 0)
        self.btnVer:SetScript("OnClick", function()
            local Version = DesolateLootcouncil:GetModule("UI_Version", true)
            if Version then Version:ShowVersionWindow() end
        end)

        if isLM then
            self.btnStop = NativeGUI:CreateButton(nav, L["Stop Session"], 105, 24, "Stop")
            self.btnStop:SetPoint("RIGHT", 0, 0)
            self.btnStop:SetScript("OnClick", function()
                DesolateLootcouncil.API:StopSession()
            end)
        end
    end
    self.navGroup:Show()

    -- Disenchanter Sidebar Attachment
    if not self.deFrame then
        local Sidebar = DesolateLootcouncil:GetModule("UI_Sidebar", true)
        if Sidebar then
            self.deFrame = Sidebar:AttachTo(self.monitorFrame)
        end
    end
    self:UpdateDisenchanters()
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
    
    if self.monitorFrame and self.monitorFrame.isCollapsed then
        self.deFrame:Hide()
    end
end

function UI_Monitor:CreateVoteRow(index, scroll, v, isLM, itemData)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.awardRowPool[index] then
        self.awardRowPool[index] = NativeGUI:CreateRowContainer(scroll, false)
    end
    local row = self.awardRowPool[index]
    row:Show()

    local rowHeight = 32
    row:SetHeight(rowHeight)

    local topOffset = (index - 1) * (rowHeight + 6)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -topOffset)
    row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -12, -topOffset)

    -- Give item button (created/positioned first for relative text anchor)
    if isLM then
        if not row.btnGive then
            local btn = NativeGUI:CreateButton(row, L["Give"], 50, 22, "Bid")
            row.btnGive = btn
        end
        row.btnGive:ClearAllPoints()
        row.btnGive:SetPoint("RIGHT", -10, 0)
        row.btnGive:Show()
        row.btnGive:SetScript("OnClick", function()
            self.awardFrame:Hide()
            local voteDesc = VOTE_TEXT[v.type] or "Unknown"
            DesolateLootcouncil.API:AwardItem(itemData.sourceGUID, v.name, voteDesc)
        end)
    elseif row.btnGive then
        row.btnGive:Hide()
    end

    -- Player Name
    local lblName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblName:SetSize(110, 20)
    lblName:SetPoint("LEFT", 10, 0)
    lblName:SetJustifyH("LEFT")
    lblName:SetText(DesolateLootcouncil:GetDisplayName(v.name))

    -- Rank / Roll value
    local rankText
    if v.type == 1 then
        rankText = (v.rank == 999) and "|cff9d9d9d" .. L["Unranked"] .. "|r" or ("#" .. v.rank)
        if v.rank <= 5 then rankText = "|cffffd700" .. rankText .. "|r" end
    else
        rankText = "Roll: " .. v.roll
    end

    local lblRank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblRank:SetSize(70, 20)
    lblRank:SetPoint("LEFT", lblName, "RIGHT", 10, 0)
    lblRank:SetJustifyH("LEFT")
    lblRank:SetText(rankText)

    -- Bid Response pill
    local lblResp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblResp:SetSize(80, 20)
    lblResp:SetPoint("LEFT", lblRank, "RIGHT", 10, 0)
    lblResp:SetJustifyH("LEFT")
    local color = VOTE_COLOR[v.type] or ""
    local txt = VOTE_TEXT[v.type] or "?"
    lblResp:SetText(color .. txt .. "|r")

    -- Voter Custom Note (sandwiched dynamically)
    local lblNote = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblNote:SetPoint("LEFT", lblResp, "RIGHT", 10, 0)
    lblNote:SetPoint("RIGHT", (isLM and row.btnGive or row), (isLM and "LEFT" or "RIGHT"), -10, 0)
    lblNote:SetJustifyH("LEFT")
    if v.note and v.note ~= "" then
        lblNote:SetText("|cffc79c6e" .. v.note .. "|r")
    else
        lblNote:SetText("")
    end

    scroll:SetHeight(topOffset + rowHeight + 10)
end

function UI_Monitor:CreateDisenchanterRow(index, scroll, de, isLM, itemData)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.deRowPool[index] then
        self.deRowPool[index] = NativeGUI:CreateRowContainer(scroll, false)
    end
    local row = self.deRowPool[index]
    row:Show()

    local rowHeight = 32
    row:SetHeight(rowHeight)

    local topOffset = (index - 1) * (rowHeight + 6)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -topOffset)
    row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -12, -topOffset)

    if isLM then
        if not row.btnGive then
            local btn = NativeGUI:CreateButton(row, L["Give"], 50, 22, "Bid")
            row.btnGive = btn
        end
        row.btnGive:ClearAllPoints()
        row.btnGive:SetPoint("RIGHT", -10, 0)
        row.btnGive:Show()
        row.btnGive:SetScript("OnClick", function()
            self.awardFrame:Hide()
            DesolateLootcouncil.API:AwardItem(itemData.sourceGUID, de.name, "Disenchant")
        end)
    elseif row.btnGive then
        row.btnGive:Hide()
    end

    local lblName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblName:SetSize(130, 20)
    lblName:SetPoint("LEFT", 10, 0)
    lblName:SetJustifyH("LEFT")
    lblName:SetText(DesolateLootcouncil:GetDisplayName(de.name))

    local lblSkill = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblSkill:SetPoint("LEFT", lblName, "RIGHT", 10, 0)
    lblSkill:SetPoint("RIGHT", (isLM and row.btnGive or row), (isLM and "LEFT" or "RIGHT"), -10, 0)
    lblSkill:SetJustifyH("LEFT")
    lblSkill:SetText(string.format(L["Lvl %d"], de.skill))


    scroll:SetHeight(topOffset + rowHeight + 10)
end

function UI_Monitor:ShowAwardWindow(itemData)
    if not itemData then
        if self.awardFrame then self.awardFrame:Hide() end
        return
    end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local isLM = DesolateLootcouncil.API:IsLootMaster()

    if not self.awardFrame then
        local frame = NativeGUI:CreateWindow("DLCAwardFrame", L["Award Item"], 500, 500, "Award")
        self.awardFrame = frame
        self.awardRowPool = {}
        self.deRowPool = {}
    end

    self.awardFrame:Show()

    -- Reset pools
    for _, r in ipairs(self.awardRowPool) do r:Hide() end
    for _, r in ipairs(self.deRowPool) do r:Hide() end

    -- Custom centered item header
    local catText = itemData.category and (" (" .. itemData.category .. ")") or ""
    local _, properLink = C_Item.GetItemInfo(itemData.link)

    if not self.awardHeader then
        local header = self.awardFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOP", 0, -40)
        self.awardHeader = header
    end
    self.awardHeader:SetText((properLink or itemData.link) .. "|cffaaaaaa" .. catText .. "|r")

    local API  = DesolateLootcouncil.API
    local guid = itemData.sourceGUID or itemData.link
    local summary = API:GetVoteSummary(guid)
    local votes   = summary.votes

    if not self.awardScroll then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.awardFrame, -65, -16)
        self.awardScroll = scrollFrame
        self.awardScrollContent = scrollContent
    end
    self.awardScroll:Show()
    self.awardScrollContent:Show()
    self.awardScrollContent:SetHeight(1)

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

    local scrollHeight = 0
    if #voteList == 0 then
        if not self.awardEmptyLabel then
            local lbl = self.awardScrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("TOPLEFT", 10, -10)
            self.awardEmptyLabel = lbl
        end
        self.awardEmptyLabel:SetText(L["No active votes."])
        self.awardEmptyLabel:Show()
        scrollHeight = scrollHeight + 30
    else
        if self.awardEmptyLabel then self.awardEmptyLabel:Hide() end
        for idx, v in ipairs(voteList) do
            self:CreateVoteRow(idx, self.awardScrollContent, v, isLM, itemData)
            scrollHeight = scrollHeight + 38
        end
    end

    -- Disenchanters Section
    local disenchanters = API:GetDisenchanterList()
    if DesolateLootcouncil.db.profile.debugMode then
        DesolateLootcouncil:DLC_Log("Monitor: Disenchanters found: " .. #disenchanters)
    end

    if #disenchanters > 0 then
        if not self.deHeaderLabel then
            local deHeader = self.awardScrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            self.deHeaderLabel = deHeader
        end
        self.deHeaderLabel:ClearAllPoints()
        self.deHeaderLabel:SetPoint("TOP", self.awardScrollContent, "TOP", 0, -scrollHeight - 10)
        self.deHeaderLabel:SetText(L["Disenchanters"])
        self.deHeaderLabel:Show()

        scrollHeight = scrollHeight + 25

        for idx, de in ipairs(disenchanters) do
            local nextDeScroll = CreateFrame("Frame", nil, self.awardScrollContent)
            nextDeScroll:SetPoint("TOPLEFT", 0, -scrollHeight)
            self:CreateDisenchanterRow(idx, nextDeScroll, de, isLM, itemData)
            scrollHeight = scrollHeight + 38
        end
    elseif self.deHeaderLabel then
        self.deHeaderLabel:Hide()
    end

    self.awardScrollContent:SetHeight(scrollHeight + 10)
end

function UI_Monitor:CloseMasterLootWindow()
    if self.monitorFrame then self.monitorFrame:Hide() end
end

UI_Monitor.ShowMasterLootWindow = UI_Monitor.ShowMonitorWindow
