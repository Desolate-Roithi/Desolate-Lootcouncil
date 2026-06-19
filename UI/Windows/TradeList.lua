local _, AT = ...
if AT.abortLoad then return end

---@class UI_TradeList : AceModule
local UI_TradeList = DesolateLootcouncil:NewModule("UI_TradeList", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local function GetUnitIDForName(playerName)
    local targetScore = DesolateLootcouncil:GetScoreName(playerName)
    if not targetScore then return nil end

    for i = 1, 40 do
        local unit = "raid" .. i
        if DesolateLootcouncil:GetUnitScore(unit) == targetScore then return unit end
    end
    for i = 1, 4 do
        local unit = "party" .. i
        if DesolateLootcouncil:GetUnitScore(unit) == targetScore then return unit end
    end
    return nil
end

function UI_TradeList:RenderTradeRow(item, row, NativeGUI)
    local function ShowTip()
        GameTooltip:SetOwner(row.iconBtn, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(item.link)
        GameTooltip:Show()
    end

    -- Remove Button ("X") (created early for anchoring)
    if not row.btnRemove then
        local btn = NativeGUI:CreateButton(row, "X", 26, 24, "Stop")
        row.btnRemove = btn
    end
    row.btnRemove:ClearAllPoints()
    row.btnRemove:SetPoint("RIGHT", -8, 0)
    row.btnRemove:Show()
    row.btnRemove:SetScript("OnClick", function()
        item.traded = true
        DesolateLootcouncil:DLC_Log(string.format(L["Marked %s as traded."], item.link))
        
        local Sync = DesolateLootcouncil:GetModule("Sync", true)
        if Sync and Sync.ShareDataWithOfficers then
            local payload = {
                {
                    itemID    = item.itemID,
                    winner    = item.winner,
                    timestamp = item.timestamp
                }
            }
            Sync:ShareDataWithOfficers("TRADE_CONFIRMED", payload)
        end
        
        self:SendMessage("DLC_HISTORY_UPDATED")
        self:ShowTradeListWindow()
    end)

    -- Trade Button
    if not row.btnTrade then
        local btn = NativeGUI:CreateButton(row, L["Trade"], 60, 24, "Bid")
        row.btnTrade = btn
    end
    row.btnTrade:ClearAllPoints()
    row.btnTrade:SetPoint("RIGHT", row.btnRemove, "LEFT", -6, 0)
    row.btnTrade:Show()
    row.btnTrade:SetScript("OnClick", function()
        local unitID = GetUnitIDForName(item.winner)
        if unitID and CheckInteractDistance(unitID, 2) then
            InitiateTrade(unitID)
            return
        end
        local winnerScore = DesolateLootcouncil:GetScoreName(item.winner)
        if DesolateLootcouncil:GetUnitScore("target") == winnerScore then
            if CheckInteractDistance("target", 2) then
                InitiateTrade("target")
            else
                DesolateLootcouncil:DLC_Log(string.format(L["%s is out of trade range."], DesolateLootcouncil:GetDisplayName(item.winner)))
            end
            return
        end
        DesolateLootcouncil:DLC_Log(string.format(L["Could not auto-target %s. Please target them manually and click Trade again."],
            DesolateLootcouncil:GetDisplayName(item.winner)), true)
    end)

    -- Icon
    if not row.iconBtn then
        row.iconBtn = NativeGUI:CreateIcon(row, 24, 8)
    end
    row.iconBtn.texture:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.iconBtn:Show()
    row.iconBtn:SetScript("OnClick", ShowTip)
    row.iconBtn:SetScript("OnEnter", ShowTip)
    row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Winner Label (class colored, right aligned next to Trade button)
    if not row.winnerLabel then
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetSize(100, 20)
        lbl:SetJustifyH("RIGHT")
        row.winnerLabel = lbl
    end
    row.winnerLabel:ClearAllPoints()
    row.winnerLabel:SetPoint("RIGHT", row.btnTrade, "LEFT", -10, 0)
    row.winnerLabel:Show()

    local class = item.winnerClass or DesolateLootcouncil:GetModule("Roster"):GetUnitClass(item.winner)
    local winnerDisp = DesolateLootcouncil:GetDisplayName(item.winner)
    row.winnerLabel:SetText(NativeGUI:FormatClassColor(class, winnerDisp))

    -- Link Label (sandwiched dynamically)
    if not row.linkLabel then
        row.linkLabel = NativeGUI:CreateLinkLabel(row)
    end
    row.linkLabel:ClearAllPoints()
    row.linkLabel:SetPoint("LEFT", row.iconBtn, "RIGHT", 8, 0)
    row.linkLabel:SetPoint("RIGHT", row.winnerLabel, "LEFT", -10, 0)
    row.linkLabel.text:SetText(item.link)
    row.linkLabel:Show()
    row.linkLabel:SetScript("OnClick", ShowTip)
    row.linkLabel:SetScript("OnEnter", ShowTip)
    row.linkLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI_TradeList:ShowTradeListWindow()
    if not DesolateLootcouncil.API:IsLootMaster() then
        if self.tradeListFrame then self.tradeListFrame:Hide() end
        return
    end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.tradeListFrame then
        local frame = NativeGUI:CreateWindow("DLCTradeFrame", L["Pending Trades"], "Trade")
        self.tradeListFrame = frame
        self.rowPool = {}
    end

    self.tradeListFrame:Show()

    NativeGUI:ResetRowPool(self.rowPool)

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.tradeListFrame, -50, -16)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    self.scrollFrame:Show()
    self.scrollContent:Show()

    local awarded = DesolateLootcouncil.API:GetAwardedList()
    local pendingCount = 0
    local topOffset = 0
    local rowHeight = 32

    if awarded then
        for _, item in ipairs(awarded) do
            if not item.traded then
                pendingCount = pendingCount + 1

                local row = NativeGUI:AcquireRow(self.rowPool, pendingCount, self.scrollContent, false)
                row:SetHeight(rowHeight)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
                row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

                self:RenderTradeRow(item, row, NativeGUI)

                topOffset = topOffset + rowHeight + 8
            end
        end
    end

    if pendingCount == 0 then
        if not self.emptyLabel then
            self.emptyLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            self.emptyLabel:SetPoint("TOPLEFT", 10, -10)
        end
        self.emptyLabel:SetText(L["No pending trades."])
        self.emptyLabel:Show()
        self.scrollContent:SetHeight(40)
    else
        if self.emptyLabel then self.emptyLabel:Hide() end
        self.scrollContent:SetHeight(topOffset + 10)
    end
end

function UI_TradeList:OnEnable()
    self:RegisterMessage("DLC_HISTORY_UPDATED", "OnHistoryUpdated")
end

function UI_TradeList:OnHistoryUpdated()
    if self.tradeListFrame and self.tradeListFrame:IsShown() then
        self:ShowTradeListWindow()
    end
end
