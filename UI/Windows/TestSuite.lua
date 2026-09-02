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

local SCENARIO_WINDOWS = {
    roster_priority_lifecycle        = function()
        local S = DesolateLootcouncil:GetModule("Settings", true)
        if S and S.OpenSettingsWindow then S:OpenSettingsWindow() end
    end,
    live_loot_bidding_awards         = function()
        local M = DesolateLootcouncil:GetModule("UI_Monitor", true)
        if M then M:ShowMonitorWindow() end
    end,
    attendance_encounters_queue      = function()
        local H = DesolateLootcouncil:GetModule("UI_RaidHistory", true)
        if H then H:ShowRaidHistoryWindow() end
    end,
    officer_comms_sync_handover      = function()
        local V = DesolateLootcouncil:GetModule("UI_Version", true)
        if V then V:ShowVersionWindow(true) end
    end,
    automation_autopass_trade        = function()
        local T = DesolateLootcouncil:GetModule("UI_TradeList", true)
        if T then T:ShowTradeListWindow() end
    end,
    database_integrity_serialization = function()
        local P = DesolateLootcouncil:GetModule("UI_PriorityLogHistory", true)
        if P then
            if P.ShowLogWindow then
                P:ShowLogWindow()
            elseif P.ShowLogHistoryWindow then
                P:ShowLogHistoryWindow()
            end
        end
    end,
}

function UI_TestSuite:OnInitialize()
    self.frame = nil
    self.scenarioRows = {}
    self.selectedScenarioId = nil
end

function UI_TestSuite:SetExportPayload(text, label)
    if self.exportEditBox then
        self.exportEditBox.fullText = text or ""
        self.exportEditBox:SetText(text or "")
        if self.exportScrollFrame and self.exportScrollContent then
            local sfWidth = self.exportScrollFrame:GetWidth() or 880
            self.exportEditBox:SetWidth(math.max(100, sfWidth - 16))
            local height = self.exportEditBox:GetHeight()
            self.exportScrollContent:SetHeight(math.max(60, height + 14))
        end
        self.exportEditBox:HighlightText()
        self.exportEditBox:SetFocus()
    end
    if label and self.exportLabel then
        self.exportLabel:SetText(label)
    end
end

local function OpenScenarioWindow(scenarioId)
    local opener = scenarioId and SCENARIO_WINDOWS[scenarioId]
    if opener then opener() end
end

local function OnStepAdvanced(self, scenarioId)
    self.selectedScenarioId = scenarioId
    self:RefreshWindow()
    OpenScenarioWindow(scenarioId)
end

local function OnStepThroughFinished(self, btnStepThrough)
    btnStepThrough:SetText("Step-by-Step (Visual)")
    local UI = DesolateLootcouncil:GetModule("UI", true)
    if UI and UI.CloseAllWindows then UI:CloseAllWindows() end
    if self.frame then
        self.frame:Show()
        self.frame:Raise()
    end
    self:RefreshWindow()
end

function UI_TestSuite:ShowTestSuiteWindow()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local TestSuite = DesolateLootcouncil:GetModule("TestSuite")
    if not NativeGUI or not TestSuite then return end

    TestSuite:EnsureSandboxProfile()

    if not self.frame then
        local f = NativeGUI:CreateWindow("DLCTestSuiteFrame", "DLC In-Game Test Suite (2.0)", 960, 640, "TestSuite")
        self.frame = f

        -- Top Controls
        local btnRunAll = NativeGUI:CreateButton(f, "Run All (Fast)", 120, 24, "Bid")
        btnRunAll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)
        btnRunAll:SetScript("OnClick", function()
            TestSuite:StopStepThrough()
            TestSuite:RunAllScenarios()
            self:RefreshWindow()
        end)
        self.btnRunAll = btnRunAll

        local btnStepThrough = NativeGUI:CreateButton(f, "Step-by-Step (Visual)", 145, 24, "Note")
        btnStepThrough:SetPoint("LEFT", btnRunAll, "RIGHT", 6, 0)
        btnStepThrough:SetScript("OnClick", function()
            if TestSuite.isStepping then
                TestSuite:StopStepThrough()
                btnStepThrough:SetText("Step-by-Step (Visual)")
            else
                btnStepThrough:SetText("Pause Step-by-Step")
                TestSuite:StartStepThrough(
                    function(scenarioId) OnStepAdvanced(self, scenarioId) end,
                    function() OnStepThroughFinished(self, btnStepThrough) end,
                    2.0
                )
            end
        end)
        self.btnStepThrough = btnStepThrough

        local btnStepNext = NativeGUI:CreateButton(f, "Next Scenario >>", 120, 24, "Roll")
        btnStepNext:SetPoint("LEFT", btnStepThrough, "RIGHT", 6, 0)
        btnStepNext:SetScript("OnClick", function()
            TestSuite:StepNext(function(scenarioId) OnStepAdvanced(self, scenarioId) end)
        end)
        self.btnStepNext = btnStepNext

        local btnReset0 = NativeGUI:CreateButton(f, "Reset State 0", 105, 24, "Stop")
        btnReset0:SetPoint("LEFT", btnStepNext, "RIGHT", 6, 0)
        btnReset0:SetScript("OnClick", function()
            local _, raw = TestSuite:ResetToStateZero()
            self.selectedScenarioId = "roster_priority_lifecycle"
            self:RefreshWindow()
            self:SetExportPayload(raw or "", "|cffffd700Loaded: [State 0 Baseline] (Ctrl+C to copy):|r")
        end)
        self.btnReset0 = btnReset0

        local btnRestoreProfile = NativeGUI:CreateButton(f, "Restore Profile", 115, 24, "Pass")
        btnRestoreProfile:SetPoint("LEFT", btnReset0, "RIGHT", 6, 0)
        btnRestoreProfile:SetScript("OnClick", function()
            local restored = TestSuite:RestoreOriginalProfile()
            if restored then
                if DesolateLootcouncil.DLC_Log then
                    DesolateLootcouncil:DLC_Log(string.format("Restored profile back to '%s'.", restored))
                end
                if self.exportLabel then
                    self.exportLabel:SetText(string.format("|cff00ff00Active profile restored to: [%s]|r", restored))
                end
            end
        end)
        self.btnRestoreProfile = btnRestoreProfile

        local btnLiveSim = NativeGUI:CreateButton(f, "Live Loot Sim", 105, 24, "Bid")
        btnLiveSim:SetPoint("LEFT", btnRestoreProfile, "RIGHT", 6, 0)
        btnLiveSim:SetScript("OnClick", function()
            DesolateLootcouncil.API:StartInteractiveLootTest()
        end)
        self.btnLiveSim = btnLiveSim

        local summaryText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summaryText:SetPoint("RIGHT", f, "TOPRIGHT", -20, -48)
        summaryText:SetJustifyH("RIGHT")
        self.summaryText = summaryText

        -- Left Container Panel: Scenario Queue
        local leftPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
        leftPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -72)
        leftPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 178)
        leftPanel:SetWidth(450)
        NativeGUI:ApplyTiledBackdrop(leftPanel)
        local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
        NativeGUI:StyleRowBackdrop(leftPanel, theme, false)

        local leftHeader = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        leftHeader:SetPoint("TOPLEFT", 10, -8)
        leftHeader:SetText("|cffffd700SCENARIO QUEUE (Click row to inspect):|r")

        local scenarioScroll, scenarioContent = NativeGUI:CreateScrollFrame(leftPanel, -28, 8)
        self.scenarioScroll = scenarioScroll
        self.scenarioContent = scenarioContent

        -- Right Container Panel: Execution Log & Error Inspector
        local rightPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
        rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 12, 0)
        rightPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 178)
        NativeGUI:ApplyTiledBackdrop(rightPanel)
        NativeGUI:StyleRowBackdrop(rightPanel, theme, false)

        local btnCopyLog = NativeGUI:CreateButton(rightPanel, "Copy Log", 72, 18, "Pass")
        btnCopyLog:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -8, -5)
        btnCopyLog:SetScript("OnClick", function()
            self:SetExportPayload(self.rawLogText or "", "|cffffd700Loaded: [Scenario Execution Log] (Ctrl+C to copy):|r")
        end)
        self.btnCopyLog = btnCopyLog

        local btnOpenUI = NativeGUI:CreateButton(rightPanel, "Open Target UI", 105, 18, "Roll")
        btnOpenUI:SetPoint("RIGHT", btnCopyLog, "LEFT", -6, 0)
        btnOpenUI:SetScript("OnClick", function()
            local selectedId = self.selectedScenarioId or TestSuite.scenarioOrder[1]
            local opener = selectedId and SCENARIO_WINDOWS[selectedId]
            if opener then
                opener()
            else
                local M = DesolateLootcouncil:GetModule("UI_Monitor", true)
                if M then M:ShowMonitorWindow() end
            end
        end)
        self.btnOpenUI = btnOpenUI

        local rightHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rightHeader:SetPoint("TOPLEFT", 10, -8)
        rightHeader:SetText("|cffffd700INSPECTOR:|r")
        self.rightHeader = rightHeader

        local statusHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusHeader:SetPoint("LEFT", rightHeader, "RIGHT", 6, 0)
        statusHeader:SetPoint("RIGHT", btnOpenUI, "LEFT", -6, 0)
        statusHeader:SetJustifyH("LEFT")
        statusHeader:SetWordWrap(false)
        self.statusHeader = statusHeader

        local logScroll, logContent = NativeGUI:CreateScrollFrame(rightPanel, -30, 8)
        self.logScroll = logScroll
        self.logContent = logContent

        local logText = logContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        logText:SetPoint("TOPLEFT", 8, -6)
        logText:SetPoint("TOPRIGHT", -8, -6)
        logText:SetJustifyH("LEFT")
        logText:SetJustifyV("TOP")
        self.logText = logText

        -- Bottom Panel: Export String Inspector & Checkpoints
        -- Row 1: Header Label (Left) + Copy Actions (Right)
        local btnCopySelected = NativeGUI:CreateButton(f, "Copy Export", 100, 22, "Bid")
        btnCopySelected:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 142)
        btnCopySelected:SetScript("OnClick", function()
            local selectedId = self.selectedScenarioId or TestSuite.scenarioOrder[1]
            local selectedResult = selectedId and TestSuite.scenarioResults and TestSuite.scenarioResults[selectedId]
            local expStr = (selectedResult and selectedResult.exportString) or TestSuite.lastExportString or ""
            self:SetExportPayload(expStr, "|cffffd700Loaded: [Final PostRun State] (Ctrl+C to copy):|r")
        end)

        local btnCopyState0 = NativeGUI:CreateButton(f, "Copy State 0", 100, 22, "Pass")
        btnCopyState0:SetPoint("RIGHT", btnCopySelected, "LEFT", -6, 0)
        btnCopyState0:SetScript("OnClick", function()
            local _, raw = TestSuite:ResetToStateZero()
            self:SetExportPayload(raw or "", "|cffffd700Loaded: [State 0 Baseline] (Ctrl+C to copy):|r")
        end)

        local exportLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        exportLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 146)
        exportLabel:SetPoint("RIGHT", btnCopyState0, "LEFT", -10, 0)
        exportLabel:SetJustifyH("LEFT")
        exportLabel:SetWordWrap(false)
        exportLabel:SetText("|cffffd700Step Export Inspector (Ctrl+C to copy payload):|r")
        self.exportLabel = exportLabel

        -- Row 2: Full Width Step Checkpoint Buttons Container (supports 1 or 2 rows)
        local stepBtnContainer = CreateFrame("Frame", nil, f)
        stepBtnContainer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 92)
        stepBtnContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 92)
        stepBtnContainer:SetHeight(44)
        self.stepBtnContainer = stepBtnContainer
        self.stepBtnPool = {}

        -- Row 3: Multiline Scrollable Read-Only Copy Box Container
        local copyFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
        copyFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
        copyFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
        copyFrame:SetHeight(74)
        NativeGUI:ApplyTiledBackdrop(copyFrame)
        NativeGUI:StyleRowBackdrop(copyFrame, theme, false)
        self.copyFrame = copyFrame

        local sf, sc = NativeGUI:CreateScrollFrame(copyFrame, -4, 4)
        self.exportScrollFrame = sf
        self.exportScrollContent = sc

        local eb = NativeGUI:CreateReadOnlyCopyBox(sc)
        eb:SetPoint("TOPLEFT", sc, "TOPLEFT", 6, -4)
        eb:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -6, -4)
        eb:SetWidth(math.max(100, (sf:GetWidth() or 880) - 16))
        eb:SetFontObject("GameFontHighlightSmall")
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

    local passedCount = 0
    local failedCount = 0
    local totalCount = #TestSuite.scenarioOrder

    -- Render Scenario Rows
    local rowHeight = 46
    local yOffset = 0

    for i, id in ipairs(TestSuite.scenarioOrder) do
        local scenario = TestSuite.scenarios[id]
        if scenario.status == "PASS" then
            passedCount = passedCount + 1
        elseif scenario.status == "FAIL" then
            failedCount = failedCount + 1
        end

        local isSelected = (self.selectedScenarioId == id) or (not self.selectedScenarioId and i == 1)
        if not self.selectedScenarioId and i == 1 then
            self.selectedScenarioId = id
        end

        local row = self.scenarioRows[i]
        if not row then
            row = NativeGUI:AcquireRow(self.scenarioRows, i, self.scenarioContent, isSelected)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", self.scenarioContent, "TOPLEFT", 0, -yOffset)
            row:SetPoint("TOPRIGHT", self.scenarioContent, "TOPRIGHT", -6, -yOffset)
            row:EnableMouse(true)

            local btnRun = NativeGUI:CreateButton(row, "Run", 46, 20, "Bid")
            btnRun:SetPoint("RIGHT", row, "RIGHT", -56, 0)
            row.btnRun = btnRun

            local statusLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            statusLbl:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            statusLbl:SetWidth(46)
            statusLbl:SetJustifyH("CENTER")
            row.statusLbl = statusLbl

            local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            title:SetPoint("TOPLEFT", 8, -6)
            title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -110, -6)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)
            row.title = title

            local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            desc:SetPoint("TOPLEFT", 8, -24)
            desc:SetPoint("TOPRIGHT", row, "TOPRIGHT", -110, -24)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(false)
            row.desc = desc
        end

        row:SetScript("OnMouseDown", function()
            self.selectedScenarioId = id
            self:RefreshWindow()
        end)

        local activeTheme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
        NativeGUI:StyleRowBackdrop(row, activeTheme, isSelected)

        row.title:SetText(scenario.name)
        row.desc:SetText(scenario.description)
        row.statusLbl:SetText(STATUS_COLORS[scenario.status] or scenario.status)
        row.btnRun:SetScript("OnClick", function()
            self.selectedScenarioId = id
            TestSuite:RunScenario(id)
            self:RefreshWindow()
            local opener = id and SCENARIO_WINDOWS[id]
            if opener then opener() end
        end)
        row:Show()
        yOffset = yOffset + rowHeight + 4
    end
    self.scenarioContent:SetHeight(math.max(1, yOffset))

    -- Render Top Summary
    if self.summaryText then
        local currentProf = (DesolateLootcouncil.db and DesolateLootcouncil.db.GetCurrentProfile and DesolateLootcouncil.db:GetCurrentProfile()) or "TestSuite_Sandbox"
        self.summaryText:SetText(string.format(
            "|cff888888Profile:|r |cffffd700%s|r  |  |cff888888Total:|r %d  |  |cff00ff00Passed:|r %d  |  |cffff2020Failed:|r %d",
            currentProf, totalCount, passedCount, failedCount
        ))
    end

    -- Render Selected Scenario Logs & Inspector
    local selectedId = self.selectedScenarioId or TestSuite.scenarioOrder[1]
    local selectedScenario = selectedId and TestSuite.scenarios[selectedId]
    local selectedResult = selectedId and TestSuite.scenarioResults and TestSuite.scenarioResults[selectedId]

    if selectedScenario then
        local durStr = (selectedResult and selectedResult.duration) and string.format(" (%.3fs)", selectedResult.duration) or ""
        self.statusHeader:SetText(string.format("%s%s", STATUS_COLORS[selectedScenario.status] or selectedScenario.status, durStr))

        local logLines = {}
        if selectedResult and selectedResult.logs and #selectedResult.logs > 0 then
            for _, l in ipairs(selectedResult.logs) do
                table.insert(logLines, l)
            end
        elseif TestSuite.lastTestLogs and #TestSuite.lastTestLogs > 0 then
            for _, l in ipairs(TestSuite.lastTestLogs) do
                table.insert(logLines, l)
            end
        else
            table.insert(logLines, string.format("Scenario [%s] ready. Click 'Run' to execute.", selectedScenario.name))
        end

        if selectedScenario.errorMsg then
            table.insert(logLines, 1, string.format("|cffff2020[FAILURE ERROR]: %s|r", selectedScenario.errorMsg))
        end

        if selectedResult and selectedResult.stepExports and #selectedResult.stepExports > 0 then
            table.insert(logLines, "")
            table.insert(logLines, "|cffffd700--- Step Checkpoints Captured ---|r")
            for idx, chk in ipairs(selectedResult.stepExports) do
                table.insert(logLines, string.format("  #%d [%s] - %d chars", idx, chk.label or ("Step " .. idx), #(chk.exportString or "")))
            end
        end

        local combinedLog = table.concat(logLines, "\n")
        self.rawLogText = combinedLog
        self.logText:SetText(combinedLog)
        self.logContent:SetHeight(math.max(1, self.logText:GetStringHeight() + 25))

        -- Populate Export EditBox with selected scenario export
        local expStr = (selectedResult and selectedResult.exportString) or TestSuite.lastExportString or ""
        self:SetExportPayload(expStr, "|cffffd700Step Export Inspector (Ctrl+C to copy payload):|r")

        -- Render dynamic Step Checkpoint Buttons in 1 or 2 rows
        if self.stepBtnPool then
            for _, btn in ipairs(self.stepBtnPool) do
                btn:Hide()
                btn:ClearAllPoints()
            end

            if selectedResult and selectedResult.stepExports and #selectedResult.stepExports > 0 then
                local numSteps = #selectedResult.stepExports
                local totalWidth = 928
                local spacing = 6

                if numSteps <= 5 then
                    local btnW = math.floor((totalWidth - (numSteps - 1) * spacing) / numSteps)
                    local xOffset = 0
                    for idx, chk in ipairs(selectedResult.stepExports) do
                        if not self.stepBtnPool[idx] then
                            self.stepBtnPool[idx] = NativeGUI:CreateButton(self.stepBtnContainer or self.frame, "", 100, 22, "Roll")
                        end
                        local btn = self.stepBtnPool[idx]
                        local rawLabel = chk.label or ("Step " .. idx)
                        local displayLabel = rawLabel:gsub("^Part_%d+_", ""):gsub("_", " ")
                        local shortLabel = string.format("#%d %s", idx, displayLabel)
                        if #shortLabel > 24 then
                            shortLabel = shortLabel:sub(1, 22) .. ".."
                        end
                        btn:SetText(shortLabel)
                        btn:SetWidth(btnW)
                        btn:SetHeight(22)
                        btn:ClearAllPoints()
                        btn:SetPoint("LEFT", self.stepBtnContainer or self.frame, "LEFT", xOffset, 10)
                        btn:SetScript("OnClick", function()
                            self:SetExportPayload(chk.exportString or "", string.format("|cffffd700Loaded Step #%d [%s] (%d chars) — Ctrl+C:|r", idx, rawLabel, #(chk.exportString or "")))
                        end)
                        btn:SetScript("OnEnter", function(selfBtn)
                            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
                            GameTooltip:AddLine(string.format("Step #%d: %s", idx, rawLabel), 1, 0.82, 0)
                            GameTooltip:AddLine(string.format("Payload: %d characters", #(chk.exportString or "")), 1, 1, 1)
                            GameTooltip:AddLine("Click to load into copy field below.", 0.7, 0.7, 0.7)
                            GameTooltip:Show()
                        end)
                        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                        btn:Show()
                        xOffset = xOffset + btnW + spacing
                    end
                else
                    -- 2-row layout for > 5 steps to prevent cramped buttons and truncation
                    local row1Count = math.ceil(numSteps / 2)
                    local row2Count = numSteps - row1Count
                    local row1W = math.floor((totalWidth - (row1Count - 1) * spacing) / row1Count)
                    local row2W = math.floor((totalWidth - (row2Count - 1) * spacing) / row2Count)

                    for idx, chk in ipairs(selectedResult.stepExports) do
                        if not self.stepBtnPool[idx] then
                            self.stepBtnPool[idx] = NativeGUI:CreateButton(self.stepBtnContainer or self.frame, "", 100, 20, "Roll")
                        end
                        local btn = self.stepBtnPool[idx]
                        local rawLabel = chk.label or ("Step " .. idx)
                        local displayLabel = rawLabel:gsub("^Part_%d+_", ""):gsub("_", " ")
                        local shortLabel = string.format("#%d %s", idx, displayLabel)
                        if #shortLabel > 26 then
                            shortLabel = shortLabel:sub(1, 24) .. ".."
                        end
                        btn:SetText(shortLabel)
                        btn:SetHeight(20)
                        btn:ClearAllPoints()

                        if idx <= row1Count then
                            local xOffset = (idx - 1) * (row1W + spacing)
                            btn:SetWidth(row1W)
                            btn:SetPoint("LEFT", self.stepBtnContainer or self.frame, "LEFT", xOffset, 12)
                        else
                            local subIdx = idx - row1Count
                            local xOffset = (subIdx - 1) * (row2W + spacing)
                            btn:SetWidth(row2W)
                            btn:SetPoint("LEFT", self.stepBtnContainer or self.frame, "LEFT", xOffset, -10)
                        end

                        btn:SetScript("OnClick", function()
                            self:SetExportPayload(chk.exportString or "", string.format("|cffffd700Loaded Step #%d [%s] (%d chars) — Ctrl+C:|r", idx, rawLabel, #(chk.exportString or "")))
                        end)
                        btn:SetScript("OnEnter", function(selfBtn)
                            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
                            GameTooltip:AddLine(string.format("Step #%d: %s", idx, rawLabel), 1, 0.82, 0)
                            GameTooltip:AddLine(string.format("Payload: %d characters", #(chk.exportString or "")), 1, 1, 1)
                            GameTooltip:AddLine("Click to load into copy field below.", 0.7, 0.7, 0.7)
                            GameTooltip:Show()
                        end)
                        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                        btn:Show()
                    end
                end
            end
        end
    end
end


