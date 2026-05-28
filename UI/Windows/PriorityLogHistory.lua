local _, AT = ...
if AT.abortLoad then return end

---@class UI_PriorityLogHistory : AceModule
local UI_PriorityLogHistory = DesolateLootcouncil:NewModule("UI_PriorityLogHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function UI_PriorityLogHistory:ShowLogWindow()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.logFrame then
        local frame = NativeGUI:CreateWindow("DLCPriorityHistoryFrame", L["Priority Log History"], 600, 400, "PriorityHistory")
        self.logFrame = frame
        self.labelPool = {}
    end

    self.logFrame:Show()

    for _, lbl in ipairs(self.labelPool) do
        lbl:Hide()
        lbl:ClearAllPoints()
    end

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.logFrame, -50, -16)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    self.scrollFrame:Show()
    self.scrollContent:Show()

    local db = DesolateLootcouncil.db.profile
    local history = db.History or {}

    local topOffset = 10
    local count = 0

    -- Show Newest First
    for i = #history, 1, -1 do
        count = count + 1
        if not self.labelPool[count] then
            local lbl = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetJustifyH("LEFT")
            self.labelPool[count] = lbl
        end
        local lbl = self.labelPool[count]
        lbl:ClearAllPoints()
        lbl:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 10, -topOffset)
        lbl:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -16, -topOffset)
        lbl:SetText(history[i])
        lbl:Show()

        topOffset = topOffset + lbl:GetStringHeight() + 8
    end

    if #history == 0 then
        if not self.emptyLabel then
            self.emptyLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            self.emptyLabel:SetPoint("TOPLEFT", 10, -10)
        end
        self.emptyLabel:SetText(L["No history logs found."])
        self.emptyLabel:Show()
        self.scrollContent:SetHeight(40)
    else
        if self.emptyLabel then self.emptyLabel:Hide() end
        self.scrollContent:SetHeight(topOffset + 10)
    end
end
