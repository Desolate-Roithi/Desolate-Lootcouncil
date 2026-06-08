local _, AT = ...
if AT.abortLoad then return end

---@class UI_Monitor : AceModule
local UI_Monitor = DesolateLootcouncil:NewModule("UI_Monitor", "AceEvent-3.0", "AceTimer-3.0")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function UI_Monitor:GetVoteInfo(guid)
    local API                       = DesolateLootcouncil.API
    local summary                   = API:GetVoteSummary(guid)
    local votes                     = summary.votes
    local isClosed                  = summary.isClosed

    local bids, rolls, os, tm, pass = 0, 0, 0, 0, 0
    local votedPlayers              = {}
    for name, voteData in pairs(votes) do
        local vType = type(voteData) == "table" and voteData.type or voteData
        if vType == 1 then
            bids = bids + 1
        elseif vType == 2 then
            rolls = rolls + 1
        elseif vType == 3 then
            os = os + 1
        elseif vType == 4 then
            tm = tm + 1
        elseif vType == 5 then
            pass = pass + 1
        end
        local score = API:GetScoreName(name)
        if score then votedPlayers[score] = true end
    end

    local countsText = string.format(
        "|cffff8000Bid:%d|r | |cffa335eeRoll:%d|r | |cff0070ddOS:%d|r | |cff1eff00TM:%d|r | |cff9d9d9dPass:%d|r",
        bids, rolls, os, tm, pass
    )

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
        local simPending = Sim:GetPendingVoters(guid, votedPlayers)
        if simPending then
            for _, sName in ipairs(simPending) do table.insert(pending, sName) end
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
    NativeGUI:SetupItemIconButton(row, item, 24, 8, 0)

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
        local AwardUI = DesolateLootcouncil:GetModule("UI_Award", true)
        if AwardUI then AwardUI:ShowAwardWindow(item) end
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
        cf:SetSize(330, 20)

        local text = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", 0, 0)
        text:SetPoint("RIGHT", 0, 0)
        text:SetJustifyH("RIGHT")
        text:SetWordWrap(false)
        cf.text = text

        row.countsFrame = cf
    end
    row.countsFrame:ClearAllPoints()
    row.countsFrame:SetPoint("RIGHT", row.actionFrame, "LEFT", -5, 0)
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
        text:SetWordWrap(false)
        lbl.text = text

        row.itemLabel = lbl
    end
    row.itemLabel:ClearAllPoints()
    row.itemLabel:SetPoint("LEFT", row.itemIcon, "RIGHT", 10, 0)
    row.itemLabel:SetPoint("RIGHT", row.countsFrame, "LEFT", 2, 0)

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
    if not DesolateLootcouncil:AmIOfficerOrLM() then
        if self.monitorFrame then self.monitorFrame:Hide() end
        return
    end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.monitorFrame then
        local frame = NativeGUI:CreateWindow("DLCMonitorFrame", L["Session Monitor"], "Monitor")
        frame:HookScript("OnHide", function()
            self.userClosedMonitor = true
        end)
        frame.OnCollapse = function()
            if self.scrollFrame then self.scrollFrame:Hide() end
            if self.navGroup then self.navGroup:Hide() end
            if self.deFrame then self.deFrame:Hide() end
        end
        frame.OnExpand = function()
            self:ShowMonitorWindow(true)
            self:UpdateDisenchanters()
        end
        self.monitorFrame = frame
        self.rowPool = {}

        -- Premium Disenchant Toggle Button next to Close (X) button
        if frame.titleBar then
            frame.titleBar:ClearAllPoints()
            frame.titleBar:SetPoint("TOPLEFT", 2, -2)
            frame.titleBar:SetPoint("TOPRIGHT", -64, -2)
        end

        local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
        local deBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        deBtn:SetSize(20, 20)
        deBtn:SetPoint("TOPRIGHT", frame.closeButton, "TOPLEFT", -6, 0)
        deBtn:SetFrameLevel(frame.closeButton:GetFrameLevel() + 5)
        deBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        deBtn:SetBackdropColor(theme.bg[1] * 1.5, theme.bg[2] * 1.5, theme.bg[3] * 1.5, 0.8)
        deBtn:SetBackdropBorderColor(unpack(theme.border))

        local deIcon = deBtn:CreateTexture(nil, "OVERLAY")
        deIcon:SetSize(14, 14)
        deIcon:SetPoint("CENTER", 0, 0)
        deIcon:SetTexture("Interface\\Icons\\spell_holy_removecurse")
        deIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        deBtn.icon = deIcon

        deBtn:SetScript("OnEnter", function()
            local activeTheme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
            deBtn:SetBackdropColor(unpack(activeTheme.buttonHover))
            deBtn:SetBackdropBorderColor(unpack(activeTheme.border))
            if deBtn.icon then
                deBtn.icon:SetDesaturated(false)
                deBtn.icon:SetVertexColor(1, 1, 1, 1)
            end
            GameTooltip:SetOwner(deBtn, "ANCHOR_TOP")
            GameTooltip:SetText(L["Toggle Disenchanters Sidebar"], 1, 1, 1)
            GameTooltip:Show()
        end)
        deBtn:SetScript("OnLeave", function()
            self:UpdateDisenchantersButtonState()
            GameTooltip:Hide()
        end)
        deBtn:SetScript("OnClick", function()
            if self.deFrame and self.deFrame:IsShown() then
                self.userClosedDE = true
            else
                self.userClosedDE = false
            end
            self:UpdateDisenchanters()
        end)

        self.deBtn = deBtn
    end

    if not isRefresh then
        self.userClosedMonitor = false
        self.monitorFrame:Show()
        if self.monitorFrame.isCollapsed then
            NativeGUI:ExpandWindow(self.monitorFrame, "Monitor")
        end
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

    if self.monitorFrame.isCollapsed then
        self.scrollFrame:Hide()
    else
        self.scrollFrame:Show()
        self.scrollContent:Show()
    end

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

        self.btnHist = NativeGUI:CreateButton(nav, L["Award Log"], 72, 24, "Pass")
        self.btnHist:SetPoint("LEFT", 205, 0)
        self.btnHist:SetScript("OnClick", function()
            local History = DesolateLootcouncil:GetModule("UI_History", true)
            if History then History:ShowSessionLootHistory() end
        end)

        self.btnAttend = NativeGUI:CreateButton(nav, L["Attendance"], 85, 24, "Pass")
        self.btnAttend:SetPoint("LEFT", 282, 0)
        self.btnAttend:SetScript("OnClick", function()
            local Attendance = DesolateLootcouncil:GetModule("UI_Attendance", true)
            if Attendance then Attendance:ShowAttendanceWindow() end
        end)

        self.btnVer = NativeGUI:CreateButton(nav, L["Version Check"], 100, 24, "Pass")
        self.btnVer:SetPoint("LEFT", 372, 0)
        self.btnVer:SetScript("OnClick", function()
            local Version = DesolateLootcouncil:GetModule("UI_Version", true)
            if Version then Version:ShowVersionWindow() end
        end)

        self.btnStop = NativeGUI:CreateButton(nav, L["Stop Session"], 95, 24, "Stop")
        self.btnStop:SetPoint("RIGHT", 0, 0)
        self.btnStop:SetScript("OnClick", function()
            local Session = DesolateLootcouncil:GetModule("Session", true)
            if Session and Session.SendStopSession then
                Session:SendStopSession()
            end
        end)
    end

    if self.monitorFrame.isCollapsed then
        self.navGroup:Hide()
    else
        self.navGroup:Show()
        if self.btnStop then
            if isLM then
                self.btnStop:Show()
            else
                self.btnStop:Hide()
            end
        end
    end

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
    self.userClosedDE = true
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
end

function UI_Monitor:OnSessionRestored(eventName, clientLootList, isLM)
    if isLM then
        self:ShowMonitorWindow()
    end
end

function UI_Monitor:OnItemRemoved(eventName, guid)
    self:ShowMonitorWindow(true)
end

function UI_Monitor:UpdateDisenchantersButtonState()
    if not self.deBtn then return end
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    local isShown = self.deFrame and self.deFrame:IsShown()

    if isShown then
        -- Active state: Glowing border, slightly brightened button background
        self.deBtn:SetBackdropBorderColor(unpack(theme.border))
        self.deBtn:SetBackdropColor(theme.bg[1] * 2.0, theme.bg[2] * 2.0, theme.bg[3] * 2.0, 0.9)
        if self.deBtn.icon then
            self.deBtn.icon:SetDesaturated(false)
            self.deBtn.icon:SetVertexColor(1, 1, 1, 1)
        end
    else
        -- Inactive/Muted state: Grey border, darker background, desaturated icon
        self.deBtn:SetBackdropBorderColor(theme.border[1] * 0.3, theme.border[2] * 0.3, theme.border[3] * 0.3, 0.5)
        self.deBtn:SetBackdropColor(theme.bg[1] * 1.0, theme.bg[2] * 1.0, theme.bg[3] * 1.0, 0.7)
        if self.deBtn.icon then
            self.deBtn.icon:SetDesaturated(true)
            self.deBtn.icon:SetVertexColor(0.5, 0.5, 0.5, 0.6)
        end
    end
end

function UI_Monitor:UpdateDisenchanters()
    if not self.deFrame then return end
    local Sidebar = DesolateLootcouncil:GetModule("UI_Sidebar", true)
    if Sidebar then
        Sidebar:UpdateDisenchanters(self.deFrame)
    end

    if self.userClosedDE == true or (self.monitorFrame and self.monitorFrame.isCollapsed) then
        self.deFrame:Hide()
    elseif self.userClosedDE == false then
        self.deFrame:Show()
    else
        -- Default scan-based visibility
        local disenchanters = DesolateLootcouncil.API:GetDisenchanterList()
        if #disenchanters > 0 then
            self.deFrame:Show()
        else
            self.deFrame:Hide()
        end
    end

    self:UpdateDisenchantersButtonState()
end

function UI_Monitor:CloseMasterLootWindow()
    if self.monitorFrame then self.monitorFrame:Hide() end
end

