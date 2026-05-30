local _, AT = ...
if AT.abortLoad then return end

---@class UI_History : AceModule
local UI_History = DesolateLootcouncil:NewModule("UI_History", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local function RenderHistoryRow(self, count, item, itemIndex, topOffset, rowHeight, NativeGUI)
    if not self.rowPool[count] then
        self.rowPool[count] = NativeGUI:CreateRowContainer(self.scrollContent, false)
    end
    local row = self.rowPool[count]
    row:Show()
    row:SetHeight(rowHeight)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT",  self.scrollContent, "TOPLEFT",  0,   -topOffset)
    row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

    -- Re-award Button (anchors right first)
    if not row.btnReaward then
        local btn = NativeGUI:CreateButton(row, L["Re-award"], 80, 24, "Bid")
        row.btnReaward = btn
    end
    row.btnReaward:ClearAllPoints()
    row.btnReaward:SetPoint("RIGHT", -8, 0)
    row.btnReaward:Show()
    row.btnReaward:SetScript("OnClick", function()
        DesolateLootcouncil.API:ReawardItem(itemIndex)
    end)

    -- Item icon
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

    local function ShowTip()
        if item.link then
            GameTooltip:SetOwner(row.iconBtn, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(item.link)
            GameTooltip:Show()
        end
    end
    row.iconBtn:SetScript("OnClick",  ShowTip)
    row.iconBtn:SetScript("OnEnter",  ShowTip)
    row.iconBtn:SetScript("OnLeave",  function() GameTooltip:Hide() end)

    -- Vote-type label (hidden — now inlined in itemLabel text below)
    if not row.typeLabel then
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetWidth(50)
        lbl:SetJustifyH("RIGHT")
        row.typeLabel = lbl
    end
    row.typeLabel:Hide()

    -- Item link + winner label (fills space between icon and Re-award)
    if not row.itemLabel then
        local btn = CreateFrame("Button", nil, row)
        btn:SetHeight(20)
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", 0, 0)
        txt:SetPoint("RIGHT", 0, 0)
        txt:SetJustifyH("LEFT")
        txt:SetWordWrap(false)
        btn.text = txt
        row.itemLabel = btn
    end
    row.itemLabel:ClearAllPoints()
    row.itemLabel:SetPoint("LEFT",  row.iconBtn,   "RIGHT", 8,  0)
    row.itemLabel:SetPoint("RIGHT", row.btnReaward, "LEFT", -8, 0)

    local class      = item.winnerClass or DesolateLootcouncil:GetModule("Roster"):GetUnitClass(item.winner)
    local winnerDisp = DesolateLootcouncil:GetDisplayName(item.winner or "Unknown")
    local colWinner  = NativeGUI:FormatClassColor(class, winnerDisp)
    local vtColor    = "ff888888"
    if item.voteType then
        local vc = NativeGUI.VOTE_COLORS[item.voteType]
        if vc then
            vtColor = vc.hex:sub(3)
        end
    end
    local vt         = item.voteType and (" |c" .. vtColor .. "(" .. item.voteType .. ")|r") or ""
    row.itemLabel.text:SetText((item.link or "???") .. " - " .. colWinner .. vt)
    row.itemLabel:Show()
    row.itemLabel:SetScript("OnClick",  ShowTip)
    row.itemLabel:SetScript("OnEnter",  ShowTip)
    row.itemLabel:SetScript("OnLeave",  function() GameTooltip:Hide() end)
end

--- Opens a lightweight loot history window scoped to the CURRENT raid session.
--- Allows the Loot Master to quickly re-award items from this session.
function UI_History:ShowSessionLootHistory()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.sessionFrame then
        local frame = NativeGUI:CreateWindow("DLCSessionHistoryFrame", L["Session Loot History"], "SessionHistory")
        self.sessionFrame = frame
        self.rowPool = {}
    end

    self.sessionFrame:Show()

    -- Hide all pooled rows
    for _, r in ipairs(self.rowPool) do
        r:Hide()
        r:ClearAllPoints()
    end

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.sessionFrame, -50, -16)
        self.scrollFrame  = scrollFrame
        self.scrollContent = scrollContent
    end
    self.scrollFrame:Show()
    self.scrollContent:Show()

    local bidding = DesolateLootcouncil.API:GetBiddingList()
    local isSessionActive = bidding and #bidding > 0
    local awarded = isSessionActive and DesolateLootcouncil.API:GetAwardedList() or {}

    local hasItems  = false
    local topOffset = 0
    local rowHeight = 32
    local count     = 0

    -- Show newest first (iterate in reverse)
    for i = #awarded, 1, -1 do
        local item = awarded[i]
        hasItems = true
        count = count + 1

        RenderHistoryRow(self, count, item, i, topOffset, rowHeight, NativeGUI)

        topOffset = topOffset + rowHeight + 6
    end

    if not hasItems then
        if not self.emptyLabel then
            self.emptyLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            self.emptyLabel:SetPoint("TOPLEFT", 10, -10)
        end
        self.emptyLabel:SetText(L["No loot awarded in this session."])
        self.emptyLabel:Show()
        self.scrollContent:SetHeight(40)
    else
        if self.emptyLabel then self.emptyLabel:Hide() end
        self.scrollContent:SetHeight(topOffset + 10)
    end
end

--- Kept for backward-compat. Redirects to ShowSessionLootHistory.
UI_History.ShowHistoryWindow = UI_History.ShowSessionLootHistory

function UI_History:OnEnable()
    self:RegisterMessage("DLC_HISTORY_UPDATED", "OnHistoryUpdated")
end

function UI_History:OnHistoryUpdated()
    if self.sessionFrame and self.sessionFrame:IsShown() then
        self:ShowSessionLootHistory()
    end
end
