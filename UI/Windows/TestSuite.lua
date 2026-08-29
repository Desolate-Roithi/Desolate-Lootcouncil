local _, AT = ...
if AT.abortLoad then return end

---@class UI_TestSuite : AceModule
local UI_TestSuite = DesolateLootcouncil:NewModule("UI_TestSuite")

---@class (partial) DLC_Ref_UI_TestSuite
---@field db table
---@field API table
---@field GetModule fun(self: any, name: string, quiet?: boolean): any
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_UI_TestSuite]]

local STATUS_COLORS = {
    IDLE = "|cff888888IDLE|r",
    RUNNING = "|cffffff00RUNNING|r",
    PASS = "|cff00ff00PASS|r",
    FAIL = "|cffff2020FAIL|r"
}

function UI_TestSuite:OnInitialize()
    self.frame = nil
    self.scenarioRows = {}
end

function UI_TestSuite:ShowTestSuiteWindow()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local TestSuite = DesolateLootcouncil:GetModule("TestSuite")
    if not NativeGUI or not TestSuite then return end

    if not self.frame then
        local f = NativeGUI:CreateWindow("DLCTestSuiteFrame", "DLC In-Game Test Suite (2.0)", 840, 560, "TestSuite")
        self.frame = f

        -- Top Controls
        local btnRunAll = NativeGUI:CreateButton(f, "Run All Scenarios", 140, 24, "Bid")
        btnRunAll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)
        btnRunAll:SetScript("OnClick", function()
            TestSuite:RunAllScenarios()
            self:RefreshWindow()
        end)
        self.btnRunAll = btnRunAll

        local btnReset0 = NativeGUI:CreateButton(f, "Reset to State 0", 140, 24, "Pass")
        btnReset0:SetPoint("LEFT", btnRunAll, "RIGHT", 10, 0)
        btnReset0:SetScript("OnClick", function()
            TestSuite:ResetToStateZero()
            self:RefreshWindow()
        end)

        local btnCopyExport = NativeGUI:CreateButton(f, "Copy Step Export", 140, 24, "Pass")
        btnCopyExport:SetPoint("LEFT", btnReset0, "RIGHT", 10, 0)
        btnCopyExport:SetScript("OnClick", function()
            if self.exportEditBox then
                self.exportEditBox:SetText(TestSuite.lastExportString or "")
                self.exportEditBox:HighlightText()
                self.exportEditBox:SetFocus()
            end
        end)

        -- Left Panel: Scenarios ScrollFrame
        local scenarioScroll, scenarioContent = NativeGUI:CreateScrollFrame(f, -75, -120)
        scenarioScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -75)
        scenarioScroll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 110)
        scenarioScroll:SetWidth(420)
        self.scenarioScroll = scenarioScroll
        self.scenarioContent = scenarioContent

        -- Right Panel: Execution Log ScrollFrame
        local logScroll, logContent = NativeGUI:CreateScrollFrame(f, -75, -120)
        logScroll:SetPoint("TOPLEFT", scenarioScroll, "TOPRIGHT", 16, 0)
        logScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 110)
        self.logScroll = logScroll
        self.logContent = logContent

        local logText = logContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        logText:SetPoint("TOPLEFT", 8, -8)
        logText:SetPoint("TOPRIGHT", -8, -8)
        logText:SetJustifyH("LEFT")
        logText:SetJustifyV("TOP")
        self.logText = logText

        -- Bottom Panel: Copyable Export String Inspector
        local exportLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        exportLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 85)
        exportLabel:SetText("|cffffd700Step Export String Inspector (Ctrl+C to copy into Antigravity):|r")

        local container, eb = NativeGUI:CreateEditBox(f, "")
        container:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
        container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
        container:SetHeight(65)
        eb:SetScript("OnEditFocusGained", function() eb:HighlightText() end)
        self.exportContainer = container
        self.exportEditBox = eb
    end

    self.frame:Show()
    self:RefreshWindow()
end

function UI_TestSuite:RefreshWindow()
    if not self.frame or not self.frame:IsShown() then return end
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local TestSuite = DesolateLootcouncil:GetModule("TestSuite")
    if not NativeGUI or not TestSuite then return end

    -- Render Scenario Rows
    local rowHeight = 44
    local yOffset = 0

    for i, id in ipairs(TestSuite.scenarioOrder) do
        local scenario = TestSuite.scenarios[id]
        local row = self.scenarioRows[i]
        if not row then
            row = NativeGUI:AcquireRow(self.scenarioRows, i, self.scenarioContent, false)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", self.scenarioContent, "TOPLEFT", 0, -yOffset)
            row:SetPoint("TOPRIGHT", self.scenarioContent, "TOPRIGHT", -10, -yOffset)

            row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.title:SetPoint("TOPLEFT", 8, -6)
            row.title:SetJustifyH("LEFT")

            row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.desc:SetPoint("TOPLEFT", 8, -24)
            row.desc:SetJustifyH("LEFT")

            row.btnRun = NativeGUI:CreateButton(row, "Run", 55, 20, "Bid")
            row.btnRun:SetPoint("RIGHT", row, "RIGHT", -60, 0)

            row.statusLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.statusLbl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.statusLbl:SetWidth(50)
            row.statusLbl:SetJustifyH("CENTER")
        end

        row.title:SetText(scenario.name)
        row.desc:SetText(scenario.description)
        row.statusLbl:SetText(STATUS_COLORS[scenario.status] or scenario.status)
        row.btnRun:SetScript("OnClick", function()
            TestSuite:RunScenario(id)
            self:RefreshWindow()
        end)
        row:Show()
        yOffset = yOffset + rowHeight + 4
    end
    self.scenarioContent:SetHeight(math.max(1, yOffset))

    -- Render Log Text
    local logStr = table.concat(TestSuite.lastTestLogs or {}, "\n")
    if logStr == "" then logStr = "Ready to run in-game scenarios." end
    self.logText:SetText(logStr)
    self.logContent:SetHeight(math.max(1, self.logText:GetStringHeight() + 20))

    -- Populate Export Inspector
    if self.exportEditBox then
        self.exportEditBox:SetText(TestSuite.lastExportString or "")
    end
end
