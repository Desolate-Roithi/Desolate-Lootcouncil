local _, AT = ...
if AT.abortLoad then return end

---@class UI_TradeList : AceModule
local UI_TradeList = DesolateLootcouncil:NewModule("UI_TradeList")
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
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(24, 24)
        btn:SetPoint("LEFT", 8, 0)
        local tex = btn:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        btn.texture = tex
        row.iconBtn = btn
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
        local btn = CreateFrame("Button", nil, row)
        btn:SetHeight(20)
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", 0, 0)
        txt:SetPoint("RIGHT", 0, 0)
        txt:SetJustifyH("LEFT")
        btn.text = txt
        row.linkLabel = btn
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

    for _, r in ipairs(self.rowPool) do
        r:Hide()
        r:ClearAllPoints()
    end

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

                if not self.rowPool[pendingCount] then
                    self.rowPool[pendingCount] = NativeGUI:CreateRowContainer(self.scrollContent, false)
                end
                local row = self.rowPool[pendingCount]
                row:Show()
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
