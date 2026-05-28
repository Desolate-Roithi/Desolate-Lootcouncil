local _, AT = ...
if AT.abortLoad then return end

---@class UI_History : AceModule
local UI_History = DesolateLootcouncil:NewModule("UI_History", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function UI_History:ShowHistoryWindow()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.historyFrame then
        local frame = NativeGUI:CreateWindow("DLCHistoryFrame", L["Session History"], 500, 420, "History")
        self.historyFrame = frame
        self.rowPool = {}
    end

    self.historyFrame:Show()

    for _, r in ipairs(self.rowPool) do
        r:Hide()
        r:ClearAllPoints()
    end

    local awarded = DesolateLootcouncil.API:GetAwardedList()

    -- 1. Date Processing
    local dates = {}
    local dateMap = {}
    for _, item in ipairs(awarded) do
        local d = date("%Y-%m-%d", item.timestamp or time())
        if not dateMap[d] then
            dateMap[d] = true
            table.insert(dates, d)
        end
    end
    -- Sort Newest -> Oldest
    table.sort(dates, function(a, b) return a > b end)

    -- Default Selection
    if not self.selectedHistoryDate and #dates > 0 then
        self.selectedHistoryDate = dates[1]
    end
    if self.selectedHistoryDate and not dateMap[self.selectedHistoryDate] then
        self.selectedHistoryDate = #dates > 0 and dates[1] or nil
    end

    -- Create/Update Date Dropdown
    local dropdownList = {}
    for _, d in ipairs(dates) do
        dropdownList[d] = d
    end

    if not self.dateDrop then
        local dropContainer = NativeGUI:CreateDropdown(self.historyFrame, L["Select Date"], 220, dropdownList, self.selectedHistoryDate, function(key)
            self.selectedHistoryDate = key
            self:ShowHistoryWindow()
        end)
        dropContainer:SetPoint("TOPLEFT", self.historyFrame, "TOPLEFT", 16, -42)
        self.dateDrop = dropContainer
    else
        self.dateDrop:SetList(dropdownList)
        self.dateDrop:SetValue(self.selectedHistoryDate)
    end

    -- Create/Update Delete Button
    if not self.btnDelete then
        local btn = NativeGUI:CreateButton(self.historyFrame, L["Delete Date"], 120, 24, "Stop")
        btn:SetPoint("TOPRIGHT", self.historyFrame, "TOPRIGHT", -16, -42)
        btn:SetScript("OnClick", function()
            if not self.selectedHistoryDate then return end

            local countRemoved = 0
            for i = #awarded, 1, -1 do
                local item = awarded[i]
                local d = date("%Y-%m-%d", item.timestamp or time())
                if d == self.selectedHistoryDate then
                    table.remove(awarded, i)
                    countRemoved = countRemoved + 1
                end
            end

            DesolateLootcouncil:DLC_Log(string.format(L["Removed %d entries for %s"], countRemoved, self.selectedHistoryDate))
            self.selectedHistoryDate = nil
            self:ShowHistoryWindow()
        end)
        self.btnDelete = btn
    end

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.historyFrame, -80, -16)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    self.scrollFrame:Show()
    self.scrollContent:Show()

    local hasItems = false
    local topOffset = 0
    local rowHeight = 32
    local count = 0

    if self.selectedHistoryDate then
        for i = #awarded, 1, -1 do
            local item = awarded[i]
            local d = date("%Y-%m-%d", item.timestamp or time())

            if d == self.selectedHistoryDate then
                hasItems = true
                count = count + 1

                if not self.rowPool[count] then
                    self.rowPool[count] = NativeGUI:CreateRowContainer(self.scrollContent, false)
                end
                local row = self.rowPool[count]
                row:Show()
                row:SetHeight(rowHeight)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
                row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

                -- Re-award Button (created early for right anchoring target)
                if not row.btnReaward then
                    local btn = NativeGUI:CreateButton(row, L["Re-award"], 80, 24, "Bid")
                    row.btnReaward = btn
                end
                row.btnReaward:ClearAllPoints()
                row.btnReaward:SetPoint("RIGHT", -8, 0)
                row.btnReaward:Show()
                row.btnReaward:SetScript("OnClick", function()
                    DesolateLootcouncil.API:ReawardItem(i)
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

                local function ShowTip()
                    if item.link then
                        GameTooltip:SetOwner(row.iconBtn, "ANCHOR_CURSOR")
                        GameTooltip:SetHyperlink(item.link)
                        GameTooltip:Show()
                    end
                end
                row.iconBtn:SetScript("OnClick", ShowTip)
                row.iconBtn:SetScript("OnEnter", ShowTip)
                row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                -- Type Label (right-aligned next to Re-award button)
                if not row.typeLabel then
                    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    lbl:SetSize(80, 20)
                    lbl:SetJustifyH("RIGHT")
                    row.typeLabel = lbl
                end
                row.typeLabel:ClearAllPoints()
                row.typeLabel:SetPoint("RIGHT", row.btnReaward, "LEFT", -10, 0)
                row.typeLabel:SetTextColor(0.7, 0.7, 0.7)
                row.typeLabel:SetText("(" .. (item.voteType or "?") .. ")")
                row.typeLabel:Show()

                -- Text Label (sandwiched dynamically)
                if not row.itemLabel then
                    local btn = CreateFrame("Button", nil, row)
                    btn:SetHeight(20)
                    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    txt:SetPoint("LEFT", 0, 0)
                    txt:SetPoint("RIGHT", 0, 0)
                    txt:SetJustifyH("LEFT")
                    btn.text = txt
                    row.itemLabel = btn
                end
                row.itemLabel:ClearAllPoints()
                row.itemLabel:SetPoint("LEFT", row.iconBtn, "RIGHT", 8, 0)
                row.itemLabel:SetPoint("RIGHT", row.typeLabel, "LEFT", -10, 0)

                local class = item.winnerClass
                local classColor = class and RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr or "ffffffff"
                row.itemLabel.text:SetText((item.link or "???") .. " -> |c" .. classColor .. DesolateLootcouncil:GetDisplayName(item.winner or "Unknown") .. "|r")
                row.itemLabel:Show()
                row.itemLabel:SetScript("OnClick", ShowTip)
                row.itemLabel:SetScript("OnEnter", ShowTip)
                row.itemLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)

                topOffset = topOffset + rowHeight + 8
            end
        end
    end

    if not hasItems then
        if not self.emptyLabel then
            self.emptyLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            self.emptyLabel:SetPoint("TOPLEFT", 10, -10)
        end
        self.emptyLabel:SetText(L["No entries for this date."])
        self.emptyLabel:Show()
        self.scrollContent:SetHeight(40)
    else
        if self.emptyLabel then self.emptyLabel:Hide() end
        self.scrollContent:SetHeight(topOffset + 10)
    end
end

function UI_History:OnEnable()
    self:RegisterMessage("DLC_HISTORY_UPDATED", "OnHistoryUpdated")
end

function UI_History:OnHistoryUpdated()
    if self.historyFrame and self.historyFrame:IsShown() then
        self:ShowHistoryWindow()
    end
end
