local _, AT = ...
if AT.abortLoad then return end

---@class UI_PriorityLogHistory : AceModule
local UI_PriorityLogHistory = DesolateLootcouncil:NewModule("UI_PriorityLogHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function UI_PriorityLogHistory:ShowLogWindow()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.logFrame then
        local frame = NativeGUI:CreateWindow("DLCPriorityHistoryFrame", L["Priority Log History"], "PriorityHistory")
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

    -- Hide legacy label pool if any
    if self.labelPool then
        for _, lbl in ipairs(self.labelPool) do
            lbl:Hide()
        end
    end

    if #history == 0 then
        if self.editBox then self.editBox:Hide() end
        if not self.emptyLabel then
            self.emptyLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            self.emptyLabel:SetPoint("TOPLEFT", 10, -10)
        end
        self.emptyLabel:SetText(L["No history logs found."])
        self.emptyLabel:Show()
        self.scrollContent:SetHeight(40)
    else
        if self.emptyLabel then self.emptyLabel:Hide() end

        if not self.editBox then
            local eb = CreateFrame("EditBox", nil, self.scrollContent)
            eb:SetMultiLine(true)
            eb:SetMaxLetters(0)
            eb:SetAutoFocus(false)
            eb:SetFontObject("GameFontHighlightSmall")
            eb:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
            
            local isResetting = false
            eb:SetScript("OnTextChanged", function(selfEdit)
                if isResetting then return end
                if selfEdit.fullText and selfEdit:GetText() ~= selfEdit.fullText then
                    isResetting = true
                    selfEdit:SetText(selfEdit.fullText)
                    isResetting = false
                end
            end)
            eb:SetEnabled(true)
            self.editBox = eb
        end

        self.editBox:ClearAllPoints()
        self.editBox:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 10, -10)
        self.editBox:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -10, -10)
        self.editBox:SetWidth(self.scrollFrame:GetWidth() - 20)

        local lines = {}
        for i = #history, 1, -1 do
            table.insert(lines, history[i])
        end
        local fullText = table.concat(lines, "\n")

        self.editBox.fullText = fullText
        self.editBox:SetText(fullText)
        self.editBox:Show()

        local height = self.editBox:GetHeight()
        if height < 40 then height = 40 end
        self.scrollContent:SetHeight(height + 20)
    end
end
