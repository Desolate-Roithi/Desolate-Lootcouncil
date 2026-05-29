local _, AT = ...
if AT.abortLoad then return end

---@class UI_Attendance : AceModule
local UI_Attendance = DesolateLootcouncil:NewModule("UI_Attendance")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

-- State for the Attendance Window
local tempAttended = {}
local tempAbsent = {}
local currentDecayAmount = 1

StaticPopupDialogs["DLC_CONFIRM_DELETE_HISTORY"] = {
    text = L["Are you sure you want to delete this attendance record? This cannot be undone."],
    button1 = L["Yes"],
    button2 = L["No"],
    OnAccept = function()
        UI_Attendance:DeleteHistoryEntry(UI_Attendance.selectedHistoryIndex)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function RefreshSettingsUI()
    local SettingsUI = DesolateLootcouncil:GetModule("UI_Settings", true)
    if SettingsUI and SettingsUI.settingsFrame and SettingsUI.settingsFrame:IsShown() then
        SettingsUI:RenderTabs()
    end
end

local function CreateAttendanceColumns(self, frame, theme, isDecayEnabled)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    -- Left Column (Attended)
    local leftPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    leftPanel:SetSize(296, 330)
    leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -65)
    leftPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    leftPanel:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.4)
    leftPanel:SetBackdropBorderColor(theme.border[1] * 0.4, theme.border[2] * 0.4, theme.border[3] * 0.4, 0.4)

    local leftTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 10, -8)
    leftTitle:SetText(L["Attended (Safe)"])
    leftTitle:SetTextColor(0.2, 1.0, 0.2)

    local scrollAttended, scrollContentAttended = NativeGUI:CreateScrollFrame(leftPanel, -30, -8)
    scrollAttended:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 8, -30)
    scrollAttended:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -8, 8)
    self.scrollContentAttended = scrollContentAttended

    -- Right Column (Absent)
    local rightPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    rightPanel:SetSize(296, 330)
    rightPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -65)
    rightPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    rightPanel:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.4)
    rightPanel:SetBackdropBorderColor(theme.border[1] * 0.4, theme.border[2] * 0.4, theme.border[3] * 0.4, 0.4)

    local rightTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightTitle:SetPoint("TOPLEFT", 10, -8)
    rightTitle:SetText(isDecayEnabled and L["Absent (Apply Decay)"] or L["Absent (Reference Only)"])
    rightTitle:SetTextColor(1.0, 0.4, 0.4)

    local scrollAbsent, scrollContentAbsent = NativeGUI:CreateScrollFrame(rightPanel, -30, -8)
    scrollAbsent:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 8, -30)
    scrollAbsent:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -8, 8)
    self.scrollContentAbsent = scrollContentAbsent
end

local function CreateAttendanceBottomControls(self, frame, isDecayEnabled)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if isDecayEnabled then
        local stepper = NativeGUI:CreateStepper(frame, L["Decay Amount"], 240, 0, 3, 1, currentDecayAmount, function(val)
            currentDecayAmount = val
        end)
        stepper:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)

        local btnApply = NativeGUI:CreateButton(frame, L["APPLY DECAY & END"], 200, 28, "Pass")
        btnApply:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
        btnApply:SetScript("OnClick", function()
            self:ApplyDecayAndEndSession()
            frame:Hide()
        end)
    else
        local btnEnd = NativeGUI:CreateButton(frame, L["End Session (Save History)"], 240, 28, "Pass")
        btnEnd:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
        btnEnd:SetScript("OnClick", function()
            DesolateLootcouncil.API:StopRaidSession(true)
            frame:Hide()
            RefreshSettingsUI()
        end)
    end
end

function UI_Attendance:ShowAttendanceWindow()
    local config = DesolateLootcouncil.API:GetAttendanceConfig()
    if not config.sessionActive then
        DesolateLootcouncil:DLC_Log(L["No active session to review."], true)
        return
    end

    -- 1. Initialize Temp Lists
    tempAttended = {}
    tempAbsent = {}
    currentDecayAmount = config.defaultPenalty or 1

    local roster = DesolateLootcouncil.API:GetMainRoster()
    for name, _ in pairs(roster) do
        if config.currentAttendees[name] then
            tempAttended[name] = true
        else
            tempAbsent[name] = true
        end
    end

    -- 2. Create Frame
    local isDecayEnabled = config.enabled
    local titleText = isDecayEnabled and L["Session Attendance & Decay Review"] or L["Session Attendance Review (Decay Disabled)"]

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()

    if self.attendanceFrame then
        self.attendanceFrame:Hide()
    end

    local frame = NativeGUI:CreateWindow("DLCAttendanceFrame", titleText, 640, 480, "Attendance")
    self.attendanceFrame = frame

    DesolateLootcouncil:MakeMovableWithSave(frame, "Attendance")

    -- 3. Top Label
    local topLabel = NativeGUI:CreateLabel(frame, L["Review attendance before ending session. Click names to move them between lists."], "GameFontHighlightSmall", 600)
    topLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -45)

    -- 4. Columns & Controls (Extracted Helpers)
    CreateAttendanceColumns(self, frame, theme, isDecayEnabled)
    CreateAttendanceBottomControls(self, frame, isDecayEnabled)

    -- Initial Render
    self:UpdateAttendanceLists()
    frame:Show()
end


function UI_Attendance:UpdateAttendanceLists()
    if not self.attendanceFrame then return end

    -- Hide old children
    local attKids = { self.scrollContentAttended:GetChildren() }
    for _, kid in ipairs(attKids) do kid:Hide(); kid:ClearAllPoints() end
    local absKids = { self.scrollContentAbsent:GetChildren() }
    for _, kid in ipairs(absKids) do kid:Hide(); kid:ClearAllPoints() end

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()

    local listAttended = {}
    for k in pairs(tempAttended) do table.insert(listAttended, k) end
    table.sort(listAttended)

    local offsetAtt = 0
    for _, name in ipairs(listAttended) do
        local btn = CreateFrame("Button", nil, self.scrollContentAttended, "BackdropTemplate")
        btn:SetSize(260, 24)
        btn:SetPoint("TOPLEFT", self.scrollContentAttended, "TOPLEFT", 4, -offsetAtt)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(theme.bg[1] + 0.05, theme.bg[2] + 0.05, theme.bg[3] + 0.05, 0.3)
        btn:SetBackdropBorderColor(theme.border[1] * 0.3, theme.border[2] * 0.3, theme.border[3] * 0.3, 0.3)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 8, 0)
        fs:SetText(DesolateLootcouncil:GetDisplayName(name))
        fs:SetTextColor(0.2, 1.0, 0.2)
        btn:SetFontString(fs)

        btn:SetScript("OnEnter", function()
            btn:SetBackdropColor(theme.buttonHover[1], theme.buttonHover[2], theme.buttonHover[3], 0.6)
        end)
        btn:SetScript("OnLeave", function()
            btn:SetBackdropColor(theme.bg[1] + 0.05, theme.bg[2] + 0.05, theme.bg[3] + 0.05, 0.3)
        end)

        btn:SetScript("OnClick", function()
            tempAttended[name] = nil
            tempAbsent[name] = true
            self:UpdateAttendanceLists()
        end)

        btn:Show()
        offsetAtt = offsetAtt + 28
    end
    self.scrollContentAttended:SetHeight(offsetAtt + 10)

    local listAbsent = {}
    for k in pairs(tempAbsent) do table.insert(listAbsent, k) end
    table.sort(listAbsent)

    local offsetAbs = 0
    for _, name in ipairs(listAbsent) do
        local btn = CreateFrame("Button", nil, self.scrollContentAbsent, "BackdropTemplate")
        btn:SetSize(260, 24)
        btn:SetPoint("TOPLEFT", self.scrollContentAbsent, "TOPLEFT", 4, -offsetAbs)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(theme.bg[1] + 0.05, theme.bg[2] + 0.05, theme.bg[3] + 0.05, 0.3)
        btn:SetBackdropBorderColor(theme.border[1] * 0.3, theme.border[2] * 0.3, theme.border[3] * 0.3, 0.3)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 8, 0)
        fs:SetText(DesolateLootcouncil:GetDisplayName(name))
        fs:SetTextColor(1.0, 0.4, 0.4)
        btn:SetFontString(fs)

        btn:SetScript("OnEnter", function()
            btn:SetBackdropColor(theme.buttonHover[1], theme.buttonHover[2], theme.buttonHover[3], 0.6)
        end)
        btn:SetScript("OnLeave", function()
            btn:SetBackdropColor(theme.bg[1] + 0.05, theme.bg[2] + 0.05, theme.bg[3] + 0.05, 0.3)
        end)

        btn:SetScript("OnClick", function()
            tempAbsent[name] = nil
            tempAttended[name] = true
            self:UpdateAttendanceLists()
        end)

        btn:Show()
        offsetAbs = offsetAbs + 28
    end
    self.scrollContentAbsent:SetHeight(offsetAbs + 10)
end

--- Persists the reviewed attendance map into DecayConfig, notifies the UI,
--- and triggers session stop via the Roster module.
---@param attendedMap table  Map of { [playerName] = true } for attended players
function UI_Attendance:CommitAttendanceToHistory(attendedMap)
    local DLC    = DesolateLootcouncil
    local config = DLC.db.profile.DecayConfig

    -- Overwrite attendees with the LM-reviewed set for accurate history.
    config.currentAttendees = {}
    for name in pairs(attendedMap) do
        config.currentAttendees[name] = true
    end

    DLC:DLC_Log("Triggering UI Refresh...")
    RefreshSettingsUI()

    DesolateLootcouncil.API:StopRaidSession(true)
end

function UI_Attendance:ApplyDecayAndEndSession()
    if not currentDecayAmount then currentDecayAmount = 1 end

    local dbLists = DesolateLootcouncil.API:GetPriorityLists()
    local DLC = DesolateLootcouncil

    DLC:DLC_Log("--- ApplyDecay Started (Amount: " .. currentDecayAmount .. ") ---")

    if currentDecayAmount > 0 then
        if #dbLists == 0 then
            DLC:DLC_Log("CRITICAL: PriorityLists table is empty or nil!", true)
        end

        for _, listObj in ipairs(dbLists) do
            DesolateLootcouncil.API:CalculateListDecay(listObj, currentDecayAmount, tempAbsent)
        end

        DLC:DLC_Log(string.format(L["Applied +%d Position Decay to all lists for absent players."], currentDecayAmount))
    else
        DLC:DLC_Log(L["Decay Amount is 0. No priorities changed."])
    end

    self:CommitAttendanceToHistory(tempAttended)
end


function UI_Attendance:DeleteHistoryEntry(index)
    if not index or index == "CURRENT" then return end

    local db = DesolateLootcouncil.db.profile
    if db.AttendanceHistory and db.AttendanceHistory[index] then
        DesolateLootcouncil.API:DeleteAttendanceHistoryEntry(index)
        DesolateLootcouncil:DLC_Log(L["Deleted attendance history entry."], true)

        -- Reset Selection
        self.selectedHistoryIndex = nil

        -- Refresh Config
        RefreshSettingsUI()
    end
end

function UI_Attendance:GetSettingsGroupOptions(config)
    return {
        settingsHeader = {
            type = "header",
            name = L["Settings"],
            order = 1,
        },
        enabled = {
            type = "toggle",
            name = L["Enable Priority Decay"],
            desc = L["If enabled, absent players will suffer priority decay."],
            order = 2,
            get = function() return config.enabled end,
            set = function(_, val) config.enabled = val end,
        },
        defaultPenalty = {
            type = "select",
            name = L["Default Penalty"],
            desc = L["Amount of priority lost per missed raid."],
            order = 3,
            values = { [0] = "0", [1] = "1", [2] = "2", [3] = "3" },
            get = function() return config.defaultPenalty end,
            set = function(_, val) config.defaultPenalty = val end,
        }
    }
end

function UI_Attendance:GetSessionControlOptions(config)
    return {
        sessionHeader = {
            type = "header",
            name = L["Session Control"],
            order = 10,
        },
        status = {
            type = "description",
            name = function()
                if config.sessionActive then return "|cff00ff00" .. L["Session Active"] .. "|r"
                else return "|cffff0000" .. L["Session Inactive"] .. "|r" end
            end,
            fontSize = "medium",
            order = 11,
        },
        controlBtn = {
            type = "execute",
            name = function() return config.sessionActive and L["End Session"] or L["Start Session"] end,
            desc = function()
                return config.sessionActive and
                    L["Open the Attendance Review window to process decay and end the session."] or
                    L["Start a new raid session."]
            end,
            func = function()
                if config.sessionActive then
                    if self.ShowAttendanceWindow then
                        self:ShowAttendanceWindow()
                    end
                else
                    DesolateLootcouncil.API:StartRaidSession()
                    RefreshSettingsUI()
                end
            end,
            order = 12,
        }
    }
end

function UI_Attendance:GetRaidHistoryOptions(config)
    return {
        historyHeader = {
            type = "header",
            name = L["Raid History"],
            order = 20,
        },
        historyList = {
            type = "select",
            name = L["Select Session"],
            desc = L["View details of current or past raid sessions."],
            order = 21,
            values = function()
                local history = DesolateLootcouncil.API:GetAttendanceHistory()
                local list = {}

                if config.sessionActive then
                    local activeCount = 0
                    for _ in pairs(config.currentAttendees) do activeCount = activeCount + 1 end
                    list["CURRENT"] = string.format("  |cff00ff00[ACTIVE]|r %s (%d Players)", date("%Y-%m-%d"), activeCount)
                end

                for i, entry in ipairs(history) do
                    local count = 0
                    if entry.attendees then
                        for _ in pairs(entry.attendees) do count = count + 1 end
                    end
                    list[i] = string.format("[%d] %s - %s (%d Players)", i, entry.date or "N/A", entry.zone or "Unknown", count)
                end
                return list
            end,
            get = function() return self.selectedHistoryIndex end,
            set = function(_, val) self.selectedHistoryIndex = val end,
            width = "double",
        },
        deleteBtn = {
            type = "execute",
            name = L["Delete Entry"],
            desc = L["Permanently delete the selected history record."],
            order = 23,
            disabled = function() return not self.selectedHistoryIndex or self.selectedHistoryIndex == "CURRENT" end,
            func = function() StaticPopup_Show("DLC_CONFIRM_DELETE_HISTORY") end,
            width = "half",
        },
        viewBtn = {
            type = "execute",
            name = L["Open Full History"],
            desc = L["Open the combined raid history window for the selected session."],
            order = 24,
            disabled = function() return not self.selectedHistoryIndex end,
            func = function()
                local RaidHistory = DesolateLootcouncil:GetModule("UI_RaidHistory", true)
                if RaidHistory then
                    RaidHistory:ShowRaidHistoryWindow(self.selectedHistoryIndex)
                end
            end,
            width = "normal",
        },
    }
end

function UI_Attendance:GetAttendanceOptions()
    local config = DesolateLootcouncil.API:GetAttendanceConfig()

    local options = {
        type = "group",
        name = L["Attendance & Decay"],
        order = 4,
        args = {}
    }

    local settings = self:GetSettingsGroupOptions(config)
    for k, v in pairs(settings) do options.args[k] = v end

    local sessionCtrl = self:GetSessionControlOptions(config)
    for k, v in pairs(sessionCtrl) do options.args[k] = v end

    local history = self:GetRaidHistoryOptions(config)
    for k, v in pairs(history) do options.args[k] = v end

    return options
end
