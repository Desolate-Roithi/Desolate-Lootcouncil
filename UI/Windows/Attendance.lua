local _, AT = ...
if AT.abortLoad then return end

---@class UI_Attendance : AceModule
local UI_Attendance = DesolateLootcouncil:NewModule("UI_Attendance")
local AceGUI = LibStub("AceGUI-3.0")
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
    local frame = AceGUI:Create("Frame")
    if isDecayEnabled then
        frame:SetTitle(L["Session Attendance & Decay Review"])
    else
        frame:SetTitle(L["Session Attendance Review (Decay Disabled)"])
    end
    frame:SetLayout("Flow")
    frame:SetWidth(650)
    frame:SetHeight(500)
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        self.attendanceFrame = nil
    end)
    self.attendanceFrame = frame

    -- [NEW] Position Persistence
    DesolateLootcouncil:MakeMovableWithSave(frame, "Attendance")

    -- 3. Top Label
    local label = AceGUI:Create("Label")
    label:SetText(L["Review attendance before ending session. Click names to move them between lists."])
    label:SetFullWidth(true)
    frame:AddChild(label)

    -- 4. Main Group (Horizontal Split)
    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetLayout("Flow")
    mainGroup:SetFullWidth(true)
    mainGroup:SetHeight(320)
    frame:AddChild(mainGroup)

    -- Left Column (Attended)
    local leftGroup = AceGUI:Create("InlineGroup")
    leftGroup:SetTitle(L["Attended (Safe)"])
    leftGroup:SetLayout("Fill")
    leftGroup:SetWidth(300)
    leftGroup:SetHeight(300)
    mainGroup:AddChild(leftGroup)

    local scrollAttended = AceGUI:Create("ScrollFrame")
    scrollAttended:SetLayout("List")
    leftGroup:AddChild(scrollAttended)
    self.scrollAttended = scrollAttended

    -- Right Column (Absent)
    local rightGroup = AceGUI:Create("InlineGroup")
    if isDecayEnabled then
        rightGroup:SetTitle(L["Absent (Apply Decay)"])
    else
        rightGroup:SetTitle(L["Absent (Reference Only)"])
    end
    rightGroup:SetLayout("Fill")
    rightGroup:SetWidth(300)
    rightGroup:SetHeight(300)
    mainGroup:AddChild(rightGroup)

    local scrollAbsent = AceGUI:Create("ScrollFrame")
    scrollAbsent:SetLayout("List")
    rightGroup:AddChild(scrollAbsent)
    self.scrollAbsent = scrollAbsent

    -- 5. Bottom Controls
    local controls = AceGUI:Create("SimpleGroup")
    controls:SetLayout("Flow")
    controls:SetFullWidth(true)
    frame:AddChild(controls)

    -- Decay Amount Slider (Conditional)
    if isDecayEnabled then
        local slider = AceGUI:Create("Slider")
        slider:SetLabel(L["Decay Amount"])
        slider:SetValue(currentDecayAmount)
        slider:SetSliderValues(0, 3, 1)
        slider:SetCallback("OnValueChanged", function(widget, event, value)
            currentDecayAmount = value
        end)
        slider:SetWidth(200)
        controls:AddChild(slider)

        -- Spacer
        local spacer = AceGUI:Create("Label")
        spacer:SetText("   ")
        spacer:SetWidth(20)
        controls:AddChild(spacer)
    end

    -- End Session (Only if Decay Disabled - otherwise we use the Apply button)
    if not isDecayEnabled then
        local btnEnd = AceGUI:Create("Button")
        btnEnd:SetText(L["End Session (Save History)"])
        btnEnd:SetWidth(200)
        btnEnd:SetCallback("OnClick", function()
            -- Call StopRaidSession(true) directly
            DesolateLootcouncil.API:StopRaidSession(true)
            frame:Hide()

            -- Refresh Config
            local Registry = LibStub("AceConfigRegistry-3.0", true)
            if Registry then Registry:NotifyChange("DesolateLootcouncil") end
        end)
        controls:AddChild(btnEnd)
    end

    -- Apply Decay & End (Conditional)
    if isDecayEnabled then
        local btnApply = AceGUI:Create("Button")
        btnApply:SetText(L["APPLY DECAY & END"])
        btnApply:SetWidth(180)
        btnApply:SetCallback("OnClick", function()
            self:ApplyDecayAndEndSession()
            frame:Hide()
        end)
        controls:AddChild(btnApply)
    end

    -- Initial Render
    self:UpdateAttendanceLists()
end

function UI_Attendance:CreateAttendedLabel(name)
    local btn = AceGUI:Create("InteractiveLabel")
    btn:SetText(DesolateLootcouncil:GetDisplayName(name))
    btn:SetColor(0.2, 1.0, 0.2) -- Greenish
    btn:SetCallback("OnClick", function()
        tempAttended[name] = nil
        tempAbsent[name] = true
        self:UpdateAttendanceLists()
    end)
    return btn
end

function UI_Attendance:CreateAbsentLabel(name)
    local btn = AceGUI:Create("InteractiveLabel")
    btn:SetText(DesolateLootcouncil:GetDisplayName(name))
    btn:SetColor(1.0, 0.4, 0.4) -- Reddish
    btn:SetCallback("OnClick", function()
        tempAbsent[name] = nil
        tempAttended[name] = true
        self:UpdateAttendanceLists()
    end)
    return btn
end

function UI_Attendance:UpdateAttendanceLists()
    if not self.attendanceFrame then return end

    self.scrollAttended:ReleaseChildren()
    self.scrollAbsent:ReleaseChildren()

    local listAttended = {}
    for k in pairs(tempAttended) do table.insert(listAttended, k) end
    table.sort(listAttended)

    for _, name in ipairs(listAttended) do
        self.scrollAttended:AddChild(self:CreateAttendedLabel(name))
    end

    local listAbsent = {}
    for k in pairs(tempAbsent) do table.insert(listAbsent, k) end
    table.sort(listAbsent)

    for _, name in ipairs(listAbsent) do
        self.scrollAbsent:AddChild(self:CreateAbsentLabel(name))
    end
end

--- Bottom-to-top bubble-down algorithm for a single priority list.
--- Absent players are each moved `penalty` positions toward the bottom.
--- Processing back-to-front prevents earlier shifts from corrupting later indices.
---@param listObj table   A PriorityList object { name, players, ... }
---@param penalty  number Positions to decay each absent player
function UI_Attendance:CalculateListDecay(listObj, penalty)
    local DLC      = DesolateLootcouncil
    local listName = listObj.name

    -- Shallow-copy so we can iterate safely while mutating
    local newList = {}
    for _, name in ipairs(listObj.players) do
        table.insert(newList, name)
    end

    DLC:DLC_Log("Processing List Category: [" .. listName .. "] with " .. #newList .. " entries.")

    -- Iterate backwards: bottom → top
    for i = #newList, 1, -1 do
        local name = newList[i]
        if tempAbsent[name] then
            local targetIdx = i + penalty

            table.remove(newList, i)

            -- Cap to the last valid insertion position
            if targetIdx > #newList + 1 then
                targetIdx = #newList + 1
            end

            table.insert(newList, targetIdx, name)
        end
    end

    -- Diagnostic logging (top 5 slots)
    if #newList > 0 then
        DLC:DLC_Log(" >> Sort Winner Rank 1: " .. DLC:GetDisplayName(newList[1]))
    end
    DLC:DLC_Log(" --- Final Standings for [" .. listName .. "] ---")
    for k = 1, math.min(5, #newList) do
        local stateStr = tempAbsent[newList[k]] and "(Absent)" or "(Present)"
        DLC:DLC_Log("#" .. k .. ": " .. DLC:GetDisplayName(newList[k]) .. " " .. stateStr)
    end

    -- Write the sorted result back into the DB object in-place
    listObj.players = newList
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

    -- Refresh the Config UI immediately.
    DLC:DLC_Log("Triggering UI Refresh...")
    local Registry = LibStub("AceConfigRegistry-3.0", true)
    if Registry then Registry:NotifyChange("DesolateLootcouncil") end

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
            self:CalculateListDecay(listObj, currentDecayAmount)
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
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
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
                        LibStub("AceConfigDialog-3.0"):Close("DesolateLootcouncil")
                    end
                else
                    DesolateLootcouncil.API:StartRaidSession()
                    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
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
                    list["CURRENT"] = string.format("|cff00ff00[ACTIVE]|r %s (%d Players)", date("%Y-%m-%d"), activeCount)
                end

                for i, entry in ipairs(history) do
                    local count = 0
                    if entry.attendees then
                        for _ in pairs(entry.attendees) do count = count + 1 end
                    end
                    list[i] = string.format("%s - %s (%d Players)", entry.date or "N/A", entry.zone or "Unknown", count)
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
        historyDetails = {
            type = "description",
            name = function()
                local idx = self.selectedHistoryIndex
                if not idx then return L["Select a session to view details."] end
                local attendees = {}

                if idx == "CURRENT" then
                    if config.currentAttendees then
                        for name in pairs(config.currentAttendees) do 
                            table.insert(attendees, DesolateLootcouncil:GetDisplayName(name)) 
                        end
                    end
                else
                    local history = DesolateLootcouncil.API:GetAttendanceHistory()
                    local entry = history[idx]
                    if entry and entry.attendees then
                        for name in pairs(entry.attendees) do 
                            table.insert(attendees, DesolateLootcouncil.API:GetDisplayName(name)) 
                        end
                    else
                        return L["Error: History entry not found or empty."]
                    end
                end

                if #attendees == 0 then return "|cffffd700" .. L["No attendees recorded."] .. "|r" end
                table.sort(attendees)
                return "|cffffd700" .. string.format(L["Attendees (%d):"], #attendees) .. "|r\n" .. table.concat(attendees, ", ")
            end,
            order = 22,
        }
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
