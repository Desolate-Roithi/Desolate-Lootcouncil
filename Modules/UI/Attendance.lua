---@class (partial) UI
local UI = DesolateLootcouncil:GetModule("UI")
local AceGUI = LibStub("AceGUI-3.0")


-- State for the Attendance Window
local tempAttended = {}
local tempAbsent = {}
local currentDecayAmount = 1

StaticPopupDialogs["DLC_CONFIRM_DELETE_HISTORY"] = {
    text = "Are you sure you want to delete this attendance record? This cannot be undone.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        UI:DeleteHistoryEntry(UI.selectedHistoryIndex)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function UI:ShowAttendanceWindow()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then
        DesolateLootcouncil:DLC_Log("No active session to review.", true)
        return
    end

    -- 1. Initialize Temp Lists
    tempAttended = {}
    tempAbsent = {}
    currentDecayAmount = config.defaultPenalty or 1

    local roster = DesolateLootcouncil.db.profile.MainRoster or {}
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
        frame:SetTitle("Session Attendance & Decay Review")
    else
        frame:SetTitle("Session Attendance Review (Decay Disabled)")
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
    DesolateLootcouncil:RestoreFramePosition(frame, "Attendance")
    local function SavePos(f)
        DesolateLootcouncil:SaveFramePosition(f, "Attendance")
    end
    local rawFrame = frame.frame --[[@as any]]
    rawFrame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        SavePos(frame)
    end)
    rawFrame:SetScript("OnHide", function() SavePos(frame) end)
    DesolateLootcouncil:ApplyCollapseHook(frame)

    -- 3. Top Label
    local label = AceGUI:Create("Label")
    label:SetText("Review attendance before ending session. Click names to move them between lists.")
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
    leftGroup:SetTitle("Attended (Safe)")
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
        rightGroup:SetTitle("Absent (Apply Decay)")
    else
        rightGroup:SetTitle("Absent (Reference Only)")
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
        slider:SetLabel("Decay Amount")
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

    -- Save & Close / End No Decay
    local btnClose = AceGUI:Create("Button")
    if isDecayEnabled then
        btnClose:SetText("Close (No Action)")
        btnClose:SetCallback("OnClick", function()
            frame:Hide()
        end)
    else
        btnClose:SetText("End Session (Save History)")
        btnClose:SetCallback("OnClick", function()
            -- Call StopRaidSession(true) directly
            local Session = DesolateLootcouncil:GetModule("Session")
            if Session then
                Session:StopRaidSession(true)
            end
            frame:Hide()

            -- Refresh Config
            local Registry = LibStub("AceConfigRegistry-3.0", true)
            if Registry then Registry:NotifyChange("DesolateLootcouncil") end
        end)
    end
    btnClose:SetWidth(200)
    controls:AddChild(btnClose)

    -- Apply Decay & End (Conditional)
    if isDecayEnabled then
        local btnApply = AceGUI:Create("Button")
        btnApply:SetText("APPLY DECAY & END")
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

function UI:UpdateAttendanceLists()
    if not self.attendanceFrame then return end

    self.scrollAttended:ReleaseChildren()
    self.scrollAbsent:ReleaseChildren()

    -- Render Attended
    local listAttended = {}
    for k in pairs(tempAttended) do table.insert(listAttended, k) end
    table.sort(listAttended)

    for _, name in ipairs(listAttended) do
        local btn = AceGUI:Create("InteractiveLabel")
        btn:SetText(name)
        btn:SetColor(0.2, 1.0, 0.2) -- Greenish
        btn:SetCallback("OnClick", function()
            -- Move to Absent
            tempAttended[name] = nil
            tempAbsent[name] = true
            self:UpdateAttendanceLists()
        end)
        self.scrollAttended:AddChild(btn)
    end

    -- Render Absent
    local listAbsent = {}
    for k in pairs(tempAbsent) do table.insert(listAbsent, k) end
    table.sort(listAbsent)

    for _, name in ipairs(listAbsent) do
        local btn = AceGUI:Create("InteractiveLabel")
        btn:SetText(name)
        btn:SetColor(1.0, 0.4, 0.4) -- Reddish
        btn:SetCallback("OnClick", function()
            -- Move to Attended
            tempAbsent[name] = nil
            tempAttended[name] = true
            self:UpdateAttendanceLists()
        end)
        self.scrollAbsent:AddChild(btn)
    end
end

function UI:ApplyDecayAndEndSession()
    if not currentDecayAmount then currentDecayAmount = 1 end

    local db = DesolateLootcouncil.db.profile
    local DLC = DesolateLootcouncil

    DLC:DLC_Log("--- ApplyDecay Started (Amount: " .. currentDecayAmount .. ") ---")

    if currentDecayAmount > 0 then
        -- 1. Iterate ALL Priority Lists (Tier, Weapons, etc.)
        if not db.PriorityLists or #db.PriorityLists == 0 then
            DLC:DLC_Log("CRITICAL: PriorityLists table is empty or nil!", true)
        end

        for _, listObj in ipairs(db.PriorityLists or {}) do
            local listName = listObj.name
            local currentList = listObj.players -- Array of strings (names)
            DLC:DLC_Log("Processing List Category: [" .. listName .. "] with " .. #currentList .. " entries.")

            local tempList = {}

            -- Populate tempList with object {name, priority, isAbsent}
            for i, name in ipairs(currentList) do
                local isAbsent = tempAbsent[name] or false
                local prio = i
                if isAbsent then
                    prio = prio + currentDecayAmount
                end

                table.insert(tempList, {
                    name = name,
                    priority = prio,
                    isAbsent = isAbsent
                })
            end

            -- 5. Sort based on new priorities
            table.sort(tempList, function(a, b)
                -- 1. Primary Sort: Penalty-Adjusted Priority (Lower is better)
                if a.priority ~= b.priority then
                    return a.priority < b.priority
                end

                -- 2. Secondary Sort: Attendance (Present beats Absent if priorities match)
                if a.isAbsent ~= b.isAbsent then
                    return not a.isAbsent
                end

                -- 3. Tertiary Sort: Alphabetical (Stability)
                return a.name < b.name
            end)

            if #tempList > 0 then
                DLC:DLC_Log(" >> Sort Winner Rank 1: " .. tempList[1].name .. " (Prio: " .. tempList[1].priority .. ")")
            end

            -- 4. Normalize (Renumber 1..N) and Flatten
            local newList = {}
            for _, entry in ipairs(tempList) do
                table.insert(newList, entry.name)
            end

            -- Final Standings Log
            DLC:DLC_Log(" --- Final Standings for [" .. listName .. "] ---")
            for k = 1, math.min(5, #newList) do
                -- We need to find the priority from tempList logic.
                -- Wait, 'newList' is just names. 'tempList' still exists and is sorted.
                -- tempList[k] corresponds to the player at Rank k.
                DLC:DLC_Log("#" .. k .. ": " .. tempList[k].name .. " (Prio " .. tempList[k].priority .. ")")
            end

            -- Update the DB list in place
            listObj.players = newList
        end

        DLC:DLC_Log(string.format("Applied +%d Position Decay to all lists for absent players.", currentDecayAmount))
    else
        DLC:DLC_Log("Decay Amount is 0. No priorities changed.")
    end

    -- 5. Notify Config Change (Refresh UI immediately)
    DLC:DLC_Log("Triggering UI Refresh...")
    local Registry = LibStub("AceConfigRegistry-3.0", true)
    if Registry then
        Registry:NotifyChange("DesolateLootcouncil")
    end

    -- Update the session attendees to match our reviewed list (for history accuracy)
    local config = DesolateLootcouncil.db.profile.DecayConfig
    config.currentAttendees = {}
    for name, _ in pairs(tempAttended) do
        config.currentAttendees[name] = true
    end

    -- Call Session:StopRaidSession(true)
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session then
        Session:StopRaidSession(true)
    else
        DLC:DLC_Log("Error: Session module not found.", true)
    end
end

function UI:DeleteHistoryEntry(index)
    if not index or index == "CURRENT" then return end

    local db = DesolateLootcouncil.db.profile
    if db.AttendanceHistory and db.AttendanceHistory[index] then
        table.remove(db.AttendanceHistory, index)
        DesolateLootcouncil:DLC_Log("Deleted attendance history entry.", true)

        -- Reset Selection
        self.selectedHistoryIndex = nil

        -- Refresh Config
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function UI:GetAttendanceOptions()
    local db = DesolateLootcouncil.db.profile
    local config = db.DecayConfig

    local options = {
        type = "group",
        name = "Attendance & Decay",
        order = 4,
        args = {
            settingsHeader = {
                type = "header",
                name = "Settings",
                order = 1,
            },
            enabled = {
                type = "toggle",
                name = "Enable Priority Decay",
                desc = "If enabled, absent players will suffer priority decay.",
                order = 2,
                get = function() return config.enabled end,
                set = function(_, val) config.enabled = val end,
            },
            defaultPenalty = {
                type = "select",
                name = "Default Penalty",
                desc = "Amount of priority lost per missed raid.",
                order = 3,
                values = { [0] = "0", [1] = "1", [2] = "2", [3] = "3" },
                get = function() return config.defaultPenalty end,
                set = function(_, val) config.defaultPenalty = val end,
            },
            sessionHeader = {
                type = "header",
                name = "Session Control",
                order = 10,
            },
            status = {
                type = "description",
                name = function()
                    if config.sessionActive then
                        return "|cff00ff00Session Active|r"
                    else
                        return "|cffff0000Session Inactive|r"
                    end
                end,
                fontSize = "medium",
                order = 11,
            },
            controlBtn = {
                type = "execute",
                name = function()
                    return config.sessionActive and "End Session" or "Start Session"
                end,
                desc = function()
                    return config.sessionActive and
                        "Open the Attendance Review window to process decay and end the session." or
                        "Start a new raid session."
                end,
                func = function()
                    local Session = DesolateLootcouncil:GetModule("Session")
                    if not Session then return end

                    if config.sessionActive then
                        -- End Session -> Open Popup
                        if self.ShowAttendanceWindow then
                            self:ShowAttendanceWindow()
                            -- Close Config to focus on Popup
                            LibStub("AceConfigDialog-3.0"):Close("DesolateLootcouncil")
                        end
                    else
                        -- Start Session
                        if Session.StartRaidSession then
                            Session:StartRaidSession()
                            -- Refresh Config to update button/status
                            LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
                        else
                            DesolateLootcouncil:DLC_Log("Error: StartRaidSession not found in Session module.", true)
                        end
                    end
                end,
                order = 12,
            },
            historyHeader = {
                type = "header",
                name = "Raid History",
                order = 20,
            },
            historyList = {
                type = "select",
                name = "Select Session",
                desc = "View details of current or past raid sessions.",
                order = 21,
                values = function()
                    local history = db.AttendanceHistory or {}
                    local list = {}

                    -- 1. [ACTIVE] Entry
                    if config.sessionActive then
                        local activeCount = 0
                        for _ in pairs(config.currentAttendees) do activeCount = activeCount + 1 end
                        list["CURRENT"] = string.format("|cff00ff00[ACTIVE]|r %s (%d Players)", date("%Y-%m-%d"),
                            activeCount)
                    end

                    -- 2. History Entries (Newest First)
                    -- Since AceConfig selection values must be Strings or Numbers, and keys are unordered in 'pairs',
                    -- we rely on the implementation.
                    -- Issue: "values" table keys are the 'value' passed to set/get.
                    -- If we use index numbers, they persist.
                    -- We will use the Index 1..N as the key.

                    for i, entry in ipairs(history) do
                        local count = 0
                        if entry.attendees then
                            for _ in pairs(entry.attendees) do count = count + 1 end
                        end
                        -- Format: YYYY-MM-DD - Zone (Count)
                        list[i] = string.format("%s - %s (%d Players)", entry.date or "N/A", entry.zone or "Unknown",
                            count)
                    end
                    return list
                end,
                get = function() return self.selectedHistoryIndex end,
                set = function(_, val) self.selectedHistoryIndex = val end,
                width = "double",
            },
            deleteBtn = {
                type = "execute",
                name = "Delete Entry",
                desc = "Permanently delete the selected history record.",
                order = 23,
                disabled = function()
                    return not self.selectedHistoryIndex or self.selectedHistoryIndex == "CURRENT"
                end,
                func = function()
                    StaticPopup_Show("DLC_CONFIRM_DELETE_HISTORY")
                end,
                width = "half",
            },
            historyDetails = {
                type = "description",
                name = function()
                    local idx = self.selectedHistoryIndex
                    if not idx then return "Select a session to view details." end

                    local attendees = {}

                    -- Handle CURRENT vs HISTORY
                    if idx == "CURRENT" then
                        if config.currentAttendees then
                            for name in pairs(config.currentAttendees) do
                                table.insert(attendees, name)
                            end
                        end
                    else
                        local history = db.AttendanceHistory or {}
                        local entry = history[idx]
                        if entry and entry.attendees then
                            for name in pairs(entry.attendees) do
                                table.insert(attendees, name)
                            end
                        else
                            return "Error: History entry not found or empty."
                        end
                    end

                    if #attendees == 0 then return "|cffffd700No attendees recorded.|r" end
                    table.sort(attendees)

                    return "|cffffd700Attendees (" .. #attendees .. "):|r\n" .. table.concat(attendees, ", ")
                end,
                order = 22,
            },
        }
    }
    return options
end
