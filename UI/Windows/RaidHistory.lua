local _, AT = ...
if AT.abortLoad then return end

---@class UI_RaidHistory : AceModule
local UI_RaidHistory = DesolateLootcouncil:NewModule("UI_RaidHistory", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

-- ============================================================
-- Section helpers
-- ============================================================

local SECTION_ICONS = {
    loot      = "Interface\\Icons\\INV_Misc_Bag_11",
    attend    = "Interface\\Icons\\Achievement_General_StayClassy",
    decay     = "Interface\\Icons\\ability_warlock_fireandbrimstone",
    positions = "Interface\\Icons\\inv_misc_scrollunrolled01d",
}

--- Returns colour-coded class name string.
local function ClassColour(class, name)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return "|cff" .. c.colorStr .. name .. "|r" end
    return name
end

--- Formats a Unix timestamp into a short HH:MM string.
local function FmtTime(ts)
    if not ts then return "" end
    return date("%H:%M", ts)
end

--- Inserts a section header row into the scroll content.
local function MakeSectionHeader(NativeGUI, parent, text, yOffset, icon)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -yOffset)

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 0 })
    row:SetBackdropColor(theme.bg[1] * 1.6, theme.bg[2] * 1.6, theme.bg[3] * 1.6, 0.7)

    if icon then
        local tex = row:CreateTexture(nil, "OVERLAY")
        tex:SetSize(14, 14)
        tex:SetPoint("LEFT", 8, 0)
        tex:SetTexture(icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", 28, 0)
    lbl:SetText(text)
    lbl:SetTextColor(0.9, 0.8, 0.4, 1)

    return row, yOffset + 28
end

--- Inserts a simple text row.
local function MakeTextRow(parent, text, yOffset, indent, colour)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", indent or 14, -yOffset)
    lbl:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -yOffset)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    if colour then lbl:SetTextColor(unpack(colour)) end
    lbl:SetText(text)
    local h = math.max(lbl:GetStringHeight(), 14)
    return lbl, yOffset + h + 6
end

-- ============================================================
-- Public API
-- ============================================================

--- Opens the Combined Raid History window.
--- @param preselect number|string|nil  optional index into AttendanceHistory to pre-select
function UI_RaidHistory:ShowRaidHistoryWindow(preselect)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.frame then
        local frame = NativeGUI:CreateWindow("DLCRaidHistoryFrame", L["Raid History"], 680, 520, "RaidHistory")
        self.frame = frame
        self.rowCache = {}

        -- ---- Dropdown: Session selector ----
        local dropContainer = NativeGUI:CreateDropdown(frame, L["Select Session"], 320, {}, nil, function(key)
            self.selectedIndex = key
            self:Refresh()
        end)
        dropContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
        self.sessionDrop = dropContainer

        -- ---- Delete button ----
        local btnDel = NativeGUI:CreateButton(frame, L["Delete Entry"], 110, 24, "Stop")
        btnDel:SetPoint("LEFT", dropContainer, "RIGHT", 10, 0)
        btnDel:SetScript("OnClick", function()
            if not self.selectedIndex or self.selectedIndex == "CURRENT" then return end
            DesolateLootcouncil.API:DeleteAttendanceHistoryEntry(self.selectedIndex)
            -- Also remove matched loot entries (they share timestamp-based IDs)
            self.selectedIndex = nil
            self:ShowRaidHistoryWindow()
        end)
        self.btnDelete = btnDel

        -- ---- Scroll area ----
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(frame, -80, -16)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    self.frame:Show()

    -- Populate session dropdown
    local API = DesolateLootcouncil.API
    local config = API:GetAttendanceConfig()
    local history = API:GetAttendanceHistory()

    local dropList = {}
    if config.sessionActive then
        local cnt = 0
        for _ in pairs(config.currentAttendees) do cnt = cnt + 1 end
        dropList["CURRENT"] = string.format("|cff00ff00[ACTIVE]|r %s (%d)", date("%Y-%m-%d"), cnt)
    end
    for i, entry in ipairs(history) do
        local cnt = 0
        if entry.attendees then for _ in pairs(entry.attendees) do cnt = cnt + 1 end end
        dropList[i] = string.format("%s — %s (%d)", entry.date or "?", entry.zone or "Unknown", cnt)
    end

    self.sessionDrop:SetList(dropList)

    if preselect then
        self.selectedIndex = preselect
    end
    if self.selectedIndex and not dropList[self.selectedIndex] then
        self.selectedIndex = nil
    end
    if not self.selectedIndex then
        if config.sessionActive then
            self.selectedIndex = "CURRENT"
        elseif #history > 0 then
            self.selectedIndex = 1
        end
    end
    self.sessionDrop:SetValue(self.selectedIndex)

    -- Update delete-btn state
    self.btnDelete:SetEnabled(self.selectedIndex and self.selectedIndex ~= "CURRENT")

    self:Refresh()
end

--- Rebuilds the scroll content for the currently selected session.
function UI_RaidHistory:Refresh()
    -- Purge old dynamic widgets
    for _, w in ipairs(self.rowCache) do
        w:Hide()
        w:SetParent(UIParent)
    end
    wipe(self.rowCache)

    if not self.scrollContent then return end

    local API = DesolateLootcouncil.API
    local config = API:GetAttendanceConfig()
    local history = API:GetAttendanceHistory()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    local idx = self.selectedIndex
    if not idx then
        local lbl = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", 14, -14)
        lbl:SetText(L["Select a session to view details."])
        table.insert(self.rowCache, lbl)
        self.scrollContent:SetHeight(40)
        return
    end

    -- Resolve session entry
    local sessionEntry  -- AttendanceHistory entry (date, zone, attendees)
    local isCurrent = (idx == "CURRENT")

    if isCurrent then
        sessionEntry = {
            date      = date("%Y-%m-%d %H:%M:%S"),
            zone      = GetRealZoneText() or "Unknown",
            attendees = config.currentAttendees or {},
        }
    else
        sessionEntry = history[idx]
        if not sessionEntry then
            self.scrollContent:SetHeight(40)
            return
        end
    end

    local yOffset = 8

    -- ================================================================
    -- SECTION 1: LOOT AWARDED
    -- ================================================================
    local _, yNew = MakeSectionHeader(NativeGUI, self.scrollContent,
        L["Loot Awarded"], yOffset, SECTION_ICONS.loot)
    yOffset = yNew

    local awarded = API:GetAwardedList()
    local lootCount = 0

    -- Filter loot that belongs to this session.
    -- Strategy: for CURRENT we show everything in session.awarded (it resets on session end).
    -- For archived sessions we match by date string prefix against the timestamp.
    local sessionDatePrefix = sessionEntry.date and sessionEntry.date:sub(1, 10) or nil

    for awardIdx, item in ipairs(awarded) do
        local include
        if isCurrent then
            include = true
        else
            -- Match by date prefix on the award timestamp
            local d = item.timestamp and date("%Y-%m-%d", item.timestamp) or nil
            include = (d and sessionDatePrefix and d == sessionDatePrefix) or false
        end

        if include then
            lootCount = lootCount + 1
            local row = CreateFrame("Frame", nil, self.scrollContent, "BackdropTemplate")
            row:SetHeight(30)
            row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -yOffset)
            row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -yOffset)

            local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
            if lootCount % 2 == 0 then
                row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 0 })
                row:SetBackdropColor(theme.bg[1] * 1.2, theme.bg[2] * 1.2, theme.bg[3] * 1.2, 0.3)
            end
            table.insert(self.rowCache, row)

            -- Item icon
            local iconBtn = CreateFrame("Button", nil, row)
            iconBtn:SetSize(20, 20)
            iconBtn:SetPoint("LEFT", 14, 0)
            local tex = iconBtn:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints()
            tex:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            iconBtn:SetScript("OnEnter", function()
                if item.link then
                    GameTooltip:SetOwner(iconBtn, "ANCHOR_CURSOR")
                    GameTooltip:SetHyperlink(item.link)
                    GameTooltip:Show()
                end
            end)
            iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            table.insert(self.rowCache, iconBtn)
            iconBtn:SetParent(row)

            -- Vote type pill
            local vt = item.voteType or "?"
            local vtColour = { 0.6, 0.6, 0.6 }
            if vt == "Bid" then vtColour = { 0.0, 0.8, 0.0 }
            elseif vt == "Roll" then vtColour = { 1.0, 0.85, 0.0 }
            elseif vt == "OS" then vtColour = { 0.0, 0.85, 0.85 }
            elseif vt == "TM" then vtColour = { 0.93, 0.65, 0.37 } end

            -- Re-award button (right side)
            local btnReaward = NativeGUI:CreateButton(row, L["Re-award"], 72, 22, "Bid")
            btnReaward:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            local capturedIdx = awardIdx
            btnReaward:SetScript("OnClick", function()
                DesolateLootcouncil.API:ReawardItem(capturedIdx)
                C_Timer.After(0.1, function()
                    self:ShowRaidHistoryWindow(self.selectedIndex)
                end)
            end)
            table.insert(self.rowCache, btnReaward)
            btnReaward:SetParent(row)

            -- Time label
            local timeLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            timeLbl:SetWidth(46)
            timeLbl:SetPoint("RIGHT", btnReaward, "LEFT", -6, 0)
            timeLbl:SetJustifyH("RIGHT")
            timeLbl:SetTextColor(0.5, 0.5, 0.5)
            timeLbl:SetText(FmtTime(item.timestamp))

            -- Vote-type label
            local vtLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            vtLbl:SetWidth(36)
            vtLbl:SetPoint("RIGHT", timeLbl, "LEFT", -6, 0)
            vtLbl:SetJustifyH("RIGHT")
            vtLbl:SetTextColor(unpack(vtColour))
            vtLbl:SetText(vt)

            -- Item link + winner label (fills remaining space)
            local infoLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            infoLbl:SetPoint("LEFT", iconBtn, "RIGHT", 6, 0)
            infoLbl:SetPoint("RIGHT", vtLbl, "LEFT", -6, 0)
            infoLbl:SetJustifyH("LEFT")
            infoLbl:SetWordWrap(false)
            local winnerDisp = DesolateLootcouncil:GetDisplayName(item.winner or "Unknown")
            local colWinner = ClassColour(item.winnerClass, winnerDisp)
            infoLbl:SetText((item.link or "???") .. " → " .. colWinner)

            yOffset = yOffset + 32
        end
    end

    if lootCount == 0 then
        _, yOffset = MakeTextRow(self.scrollContent, L["No loot awarded in this session."], yOffset, 14, { 0.5, 0.5, 0.5 })
    end

    yOffset = yOffset + 8

    -- ================================================================
    -- SECTION 2: PLAYERS ATTENDED
    -- ================================================================
    _, yOffset = MakeSectionHeader(NativeGUI, self.scrollContent,
        L["Players Attended"], yOffset, SECTION_ICONS.attend)

    local attendees = {}
    if sessionEntry.attendees then
        for name in pairs(sessionEntry.attendees) do
            local dispName = DesolateLootcouncil.API:GetDisplayName(name)
            table.insert(attendees, dispName)
        end
    end
    table.sort(attendees)

    if #attendees == 0 then
        _, yOffset = MakeTextRow(self.scrollContent, L["No attendees recorded."], yOffset, 14, { 0.5, 0.5, 0.5 })
    else
        -- Build a multi-column grid (3 columns)
        local colW = 180
        local colCount = 3
        local rowH = 18
        local rowsNeeded = math.ceil(#attendees / colCount)

        for r = 1, rowsNeeded do
            for c = 1, colCount do
                local nameIdx = (r - 1) * colCount + c
                local name = attendees[nameIdx]
                if name then
                    local lbl = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    lbl:SetWidth(colW)
                    lbl:SetHeight(rowH)
                    lbl:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 14 + (c - 1) * colW, -yOffset)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetText("• " .. name)
                    table.insert(self.rowCache, lbl)
                end
            end
            yOffset = yOffset + rowH + 2
        end
        yOffset = yOffset + 4
    end

    yOffset = yOffset + 8

    -- ================================================================
    -- SECTION 3: PRIORITY POSITION CHANGES
    -- (from db.History — timestamped strings, filter by date prefix)
    -- ================================================================
    _, yOffset = MakeSectionHeader(NativeGUI, self.scrollContent,
        L["Position Changes"], yOffset, SECTION_ICONS.positions)

    local priorityLog = DesolateLootcouncil.db.profile.History or {}
    local posChanges = {}
    for _, entry in ipairs(priorityLog) do
        -- Each entry is a string like "[HH:MM] msg" — we look for ones
        -- containing today's or matching date context.
        -- Since Priority only stores strings (no timestamps), we show all on CURRENT,
        -- and for archived we note it's not available.
        if isCurrent then
            table.insert(posChanges, entry)
        end
    end

    if isCurrent and #posChanges > 0 then
        -- Show newest-first, capped at 20
        local shown = 0
        for i = #posChanges, math.max(1, #posChanges - 19), -1 do
            _, yOffset = MakeTextRow(self.scrollContent, posChanges[i], yOffset, 14)
            shown = shown + 1
        end
        if #posChanges > 20 then
            _, yOffset = MakeTextRow(self.scrollContent,
                string.format("... and %d more entries", #posChanges - 20),
                yOffset, 14, { 0.5, 0.5, 0.5 })
        end
    elseif isCurrent then
        _, yOffset = MakeTextRow(self.scrollContent, L["No position changes recorded."], yOffset, 14, { 0.5, 0.5, 0.5 })
    else
        _, yOffset = MakeTextRow(self.scrollContent, L["Position log only available for current session."], yOffset, 14, { 0.5, 0.5, 0.5 })
    end

    yOffset = yOffset + 8

    -- ================================================================
    -- SECTION 4: DECAY APPLIED
    -- ================================================================
    _, yOffset = MakeSectionHeader(NativeGUI, self.scrollContent,
        L["Decay Applied"], yOffset, SECTION_ICONS.decay)

    -- Decay info is embedded in the Priority log strings
    local decayEntries = {}
    if isCurrent then
        for _, entry in ipairs(priorityLog) do
            if entry:lower():find("decay") or entry:lower():find("absent") then
                table.insert(decayEntries, entry)
            end
        end
    end

    if isCurrent and #decayEntries > 0 then
        for _, entry in ipairs(decayEntries) do
            _, yOffset = MakeTextRow(self.scrollContent, entry, yOffset, 14, { 0.93, 0.65, 0.37 })
        end
    else
        local decayCfg = config
        local decayEnabled = decayCfg.enabled
        local penalty = decayCfg.defaultPenalty or 0
        local decayStr
        if not decayEnabled then
            decayStr = L["Decay disabled."]
        elseif isCurrent then
            decayStr = L["No decay applied yet."]
        else
            decayStr = string.format(L["Decay of %d positions was applied when session ended."], penalty)
        end
        _, yOffset = MakeTextRow(self.scrollContent, decayStr, yOffset, 14, { 0.5, 0.5, 0.5 })
    end

    yOffset = yOffset + 16
    self.scrollContent:SetHeight(yOffset)
end

function UI_RaidHistory:OnEnable()
    self:RegisterMessage("DLC_HISTORY_UPDATED", function()
        if self.frame and self.frame:IsShown() then
            self:Refresh()
        end
    end)
end
