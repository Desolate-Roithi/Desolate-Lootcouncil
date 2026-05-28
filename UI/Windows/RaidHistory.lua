local _, AT = ...
if AT.abortLoad then return end

---@class UI_RaidHistory : AceModule
local UI_RaidHistory = DesolateLootcouncil:NewModule("UI_RaidHistory", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

-- ============================================================
-- Constants
-- ============================================================

local SECTION_ICONS = {
    loot      = "Interface\\Icons\\INV_Misc_Bag_11",
    attend    = "Interface\\Icons\\Achievement_General_StayClassy",
    decay     = "Interface\\Icons\\ability_warlock_fireandbrimstone",
    positions = "Interface\\Icons\\inv_misc_scrollunrolled01d",
}

local VOTE_COLOURS = {
    Bid  = { 0.0, 0.8, 0.0  },
    Roll = { 1.0, 0.85, 0.0 },
    OS   = { 0.0, 0.85, 0.85 },
    TM   = { 0.93, 0.65, 0.37 },
}

-- ============================================================
-- Widget Pool Helpers
-- ============================================================
-- All dynamic regions live inside Frame containers so they can
-- be hidden/reparented cleanly. Raw FontStrings are never created
-- directly on the scrollContent parent, which would cause them to
-- get "stuck" when the scrollContent is reused across Refresh() calls.
-- ============================================================

--- Return (and lazily create) the n-th item from pool, parented to `parent`.
local function PoolGet(pool, n, factory, parent)
    if not pool[n] then
        pool[n] = factory(parent)
    end
    local w = pool[n]
    w:ClearAllPoints()
    w:Show()
    return w
end

--- Hide every item in pool (does NOT clear points here; PoolGet does that).
local function PoolReset(pool)
    for _, w in ipairs(pool) do w:Hide() end
end

-- ---- Factory: collapsible section header ----
local function FactoryHeader(parent)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(26)

    local iconTex = row:CreateTexture(nil, "OVERLAY")
    iconTex:SetSize(14, 14)
    iconTex:SetPoint("LEFT", 8, 0)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.iconTex = iconTex

    local titleLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("LEFT", 28, 0)
    titleLbl:SetTextColor(0.9, 0.8, 0.4, 1)
    row.titleLbl = titleLbl

    local arrowLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrowLbl:SetPoint("RIGHT", -10, 0)
    arrowLbl:SetTextColor(0.55, 0.55, 0.55)
    row.arrowLbl = arrowLbl

    row:SetScript("OnEnter", function(self) self:SetAlpha(0.75) end)
    row:SetScript("OnLeave", function(self) self:SetAlpha(1.0)  end)
    return row
end

-- ---- Factory: plain text row ----
local function FactoryTextRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    row.lbl = lbl
    return row
end

-- ---- Factory: attendee name tag ----
local function FactoryNameTag(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetAllPoints()
    lbl:SetJustifyH("LEFT")
    row.lbl = lbl
    return row
end

-- ---- Factory: loot item row ----
local function FactoryLootRow(parent)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(30)

    local iconBtn = CreateFrame("Button", nil, row)
    iconBtn:SetSize(20, 20)
    iconBtn:SetPoint("LEFT", 14, 0)
    local iconTex = iconBtn:CreateTexture(nil, "BACKGROUND")
    iconTex:SetAllPoints()
    row.iconBtn = iconBtn
    row.iconTex = iconTex

    local vtLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    vtLbl:SetWidth(36)
    vtLbl:SetJustifyH("RIGHT")
    row.vtLbl = vtLbl

    local timeLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeLbl:SetWidth(46)
    timeLbl:SetJustifyH("RIGHT")
    timeLbl:SetTextColor(0.5, 0.5, 0.5)
    row.timeLbl = timeLbl

    local infoLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoLbl:SetJustifyH("LEFT")
    infoLbl:SetWordWrap(false)
    row.infoLbl = infoLbl

    local btnReaward = NativeGUI:CreateButton(row, L["Re-award"], 72, 22, "Bid")
    row.btnReaward = btnReaward

    return row
end

-- ============================================================
-- Helpers
-- ============================================================

local function ClassColour(class, name)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return "|cff" .. c.colorStr .. name .. "|r" end
    return name
end

local function FmtTime(ts)
    if not ts then return "" end
    return date("%H:%M", ts)
end

-- ============================================================
-- Public: Open window
-- ============================================================

function UI_RaidHistory:ShowRaidHistoryWindow(preselect)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.frame then
        local frame = NativeGUI:CreateWindow("DLCRaidHistoryFrame", L["Raid History"], 680, 520, "RaidHistory")
        self.frame = frame

        -- Collapsed state per section (false = expanded)
        self.collapsed = { loot = false, attend = false, positions = false, decay = false }

        -- Widget pools (grow lazily; cleared on each Refresh)
        self.pHeaders  = {}   -- section header frames
        self.pTextRows = {}   -- plain text rows
        self.pNameTags = {}   -- attendee name tags
        self.pLootRows = {}   -- loot item rows

        -- Dropdown
        local drop = NativeGUI:CreateDropdown(frame, L["Select Session"], 320, {}, nil, function(key)
            self.selectedIndex = key
            self:Refresh()
        end)
        drop:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
        self.sessionDrop = drop

        -- Delete button — aligned to dropdown top edge
        local btnDel = NativeGUI:CreateButton(frame, L["Delete Entry"], 110, 24, "Stop")
        btnDel:SetPoint("TOPLEFT", drop, "TOPRIGHT", 10, 0)
        btnDel:SetScript("OnClick", function()
            if not self.selectedIndex or self.selectedIndex == "CURRENT" then return end
            DesolateLootcouncil.API:DeleteAttendanceHistoryEntry(self.selectedIndex)
            self.selectedIndex = nil
            self:ShowRaidHistoryWindow()
        end)
        self.btnDelete = btnDel

        -- Scroll area
        local sf, sc = NativeGUI:CreateScrollFrame(frame, -80, -16)
        self.scrollFrame   = sf
        self.scrollContent = sc
    end

    self.frame:Show()

    -- Build dropdown list
    local API    = DesolateLootcouncil.API
    local config = API:GetAttendanceConfig()
    local hist   = API:GetAttendanceHistory()

    local dropList = {}
    if config.sessionActive then
        local cnt = 0
        for _ in pairs(config.currentAttendees) do cnt = cnt + 1 end
        dropList["CURRENT"] = string.format("|cff00ff00[ACTIVE]|r %s (%d)", date("%Y-%m-%d"), cnt)
    end
    for i, entry in ipairs(hist) do
        local cnt = 0
        if entry.attendees then for _ in pairs(entry.attendees) do cnt = cnt + 1 end end
        dropList[i] = string.format("%s - %s (%d)", entry.date or "?", entry.zone or "Unknown", cnt)
    end

    self.sessionDrop:SetList(dropList)

    if preselect ~= nil then self.selectedIndex = preselect end
    if self.selectedIndex and not dropList[self.selectedIndex] then
        self.selectedIndex = nil
    end
    if not self.selectedIndex then
        if config.sessionActive then
            self.selectedIndex = "CURRENT"
        elseif #hist > 0 then
            self.selectedIndex = 1
        end
    end

    self.sessionDrop:SetValue(self.selectedIndex)
    self.btnDelete:SetEnabled(self.selectedIndex ~= nil and self.selectedIndex ~= "CURRENT")

    self:Refresh()
end

-- ============================================================
-- Public: Rebuild scroll content
-- ============================================================

function UI_RaidHistory:Refresh()
    if not self.scrollContent then return end

    -- Reset all pools (hide every pooled widget)
    PoolReset(self.pHeaders)
    PoolReset(self.pTextRows)
    PoolReset(self.pNameTags)
    PoolReset(self.pLootRows)

    -- Pool cursors
    local hN, tN, nN, lN = 0, 0, 0, 0

    local sc     = self.scrollContent
    local API    = DesolateLootcouncil.API
    local config = API:GetAttendanceConfig()
    local hist   = API:GetAttendanceHistory()
    local idx    = self.selectedIndex
    local theme  = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    local db     = DesolateLootcouncil.db.profile

    -- ---- Cursor ----
    local yOffset = 6

    -- ---- Helper: next pooled header ----
    local function NextHeader()
        hN = hN + 1
        return PoolGet(self.pHeaders, hN, FactoryHeader, sc)
    end

    -- ---- Helper: next pooled text row ----
    local function NextTextRow()
        tN = tN + 1
        return PoolGet(self.pTextRows, tN, FactoryTextRow, sc)
    end

    -- ---- Helper: next pooled name tag ----
    local function NextNameTag()
        nN = nN + 1
        return PoolGet(self.pNameTags, nN, FactoryNameTag, sc)
    end

    -- ---- Helper: next pooled loot row ----
    local function NextLootRow()
        lN = lN + 1
        return PoolGet(self.pLootRows, lN, FactoryLootRow, sc)
    end

    -- ---- Helper: add a plain text row ----
    local function AddText(text, indent, colour)
        local tr = NextTextRow()
        tr:SetPoint("TOPLEFT",  sc, "TOPLEFT",  indent or 14, -yOffset)
        tr:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12,          -yOffset)
        tr.lbl:SetPoint("TOPLEFT",  tr, "TOPLEFT",  0, -3)
        tr.lbl:SetPoint("TOPRIGHT", tr, "TOPRIGHT", 0, -3)
        tr.lbl:SetText(text)
        if colour then
            tr.lbl:SetTextColor(unpack(colour))
        else
            tr.lbl:SetTextColor(0.85, 0.85, 0.85)
        end
        local h = math.max(tr.lbl:GetStringHeight() + 8, 18)
        tr:SetHeight(h)
        yOffset = yOffset + h + 2
    end

    -- ---- Helper: collapsible section header ----
    -- Returns true if the section is currently collapsed.
    local function AddHeader(sectionKey, icon, label)
        local row = NextHeader()
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0,   -yOffset)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -yOffset)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 0 })
        row:SetBackdropColor(theme.bg[1] * 1.6, theme.bg[2] * 1.6, theme.bg[3] * 1.6, 0.7)
        row.iconTex:SetTexture(icon)
        row.titleLbl:SetText(label)

        local isCollapsed = self.collapsed[sectionKey]
        row.arrowLbl:SetText(isCollapsed and "[+]" or "[-]")

        -- Capture sectionKey for the toggle closure
        local capturedKey = sectionKey
        row:SetScript("OnClick", function()
            self.collapsed[capturedKey] = not self.collapsed[capturedKey]
            self:Refresh()
        end)

        yOffset = yOffset + 28
        return isCollapsed
    end

    -- ================================================================
    -- No session selected
    -- ================================================================
    if not idx then
        AddText(L["Select a session to view details."], 14, { 0.6, 0.6, 0.6 })
        sc:SetHeight(50)
        return
    end

    -- ================================================================
    -- Resolve session entry
    -- ================================================================
    local sessionEntry
    local isCurrent = (idx == "CURRENT")

    if isCurrent then
        sessionEntry = {
            date      = date("%Y-%m-%d %H:%M:%S"),
            zone      = GetRealZoneText() or "Unknown",
            attendees = config.currentAttendees or {},
            sessionID = config.currentSessionID,
        }
    else
        sessionEntry = hist[idx]
        if not sessionEntry then
            sc:SetHeight(40)
            return
        end
    end

    -- ================================================================
    -- SECTION 1 — LOOT AWARDED
    -- ================================================================
    local lootCollapsed = AddHeader("loot", SECTION_ICONS.loot, L["Loot Awarded"])

    if not lootCollapsed then
        local awarded           = API:GetAwardedList()
        local lootCount         = 0
        local sessionDatePrefix = sessionEntry.date and sessionEntry.date:sub(1, 10)

        for awardIdx, item in ipairs(awarded) do
            local include
            if isCurrent then
                include = true
            else
                local d = item.timestamp and date("%Y-%m-%d", item.timestamp)
                include = (d and sessionDatePrefix and d == sessionDatePrefix) or false
            end

            if include then
                lootCount = lootCount + 1
                local row = NextLootRow()
                row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0,   -yOffset)
                row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -yOffset)

                -- Alternating stripe
                if lootCount % 2 == 0 then
                    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 0 })
                    row:SetBackdropColor(theme.bg[1] * 1.2, theme.bg[2] * 1.2, theme.bg[3] * 1.2, 0.3)
                else
                    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 0 })
                    row:SetBackdropColor(0, 0, 0, 0)
                end

                -- Icon
                row.iconTex:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.iconBtn:SetScript("OnEnter", function()
                    if item.link then
                        GameTooltip:SetOwner(row.iconBtn, "ANCHOR_CURSOR")
                        GameTooltip:SetHyperlink(item.link)
                        GameTooltip:Show()
                    end
                end)
                row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                -- Re-award
                row.btnReaward:ClearAllPoints()
                row.btnReaward:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                local capturedIdx = awardIdx
                row.btnReaward:SetScript("OnClick", function()
                    DesolateLootcouncil.API:ReawardItem(capturedIdx)
                    C_Timer.After(0.1, function()
                        self:ShowRaidHistoryWindow(self.selectedIndex)
                    end)
                end)

                -- Time
                row.timeLbl:ClearAllPoints()
                row.timeLbl:SetPoint("RIGHT", row.btnReaward, "LEFT", -6, 0)
                row.timeLbl:SetText(FmtTime(item.timestamp))

                -- Vote type
                local vt    = item.voteType or "?"
                local vtCol = VOTE_COLOURS[vt] or { 0.6, 0.6, 0.6 }
                row.vtLbl:ClearAllPoints()
                row.vtLbl:SetPoint("RIGHT", row.timeLbl, "LEFT", -4, 0)
                row.vtLbl:SetText(vt)
                row.vtLbl:SetTextColor(unpack(vtCol))

                -- Info (item + winner)
                local winnerDisp = DesolateLootcouncil:GetDisplayName(item.winner or "Unknown")
                local colWinner  = ClassColour(item.winnerClass, winnerDisp)
                row.infoLbl:ClearAllPoints()
                row.infoLbl:SetPoint("LEFT",  row.iconBtn, "RIGHT", 6, 0)
                row.infoLbl:SetPoint("RIGHT", row.vtLbl,   "LEFT", -6, 0)
                row.infoLbl:SetText((item.link or "???") .. " - " .. colWinner)

                yOffset = yOffset + 32
            end
        end

        if lootCount == 0 then
            AddText(L["No loot awarded in this session."], 14, { 0.5, 0.5, 0.5 })
        end
    end

    yOffset = yOffset + 6

    -- ================================================================
    -- SECTION 2 — PLAYERS ATTENDED
    -- ================================================================
    local attendCollapsed = AddHeader("attend", SECTION_ICONS.attend, L["Players Attended"])

    if not attendCollapsed then
        local attendees = {}
        if sessionEntry.attendees then
            for name in pairs(sessionEntry.attendees) do
                table.insert(attendees, API:GetDisplayName(name))
            end
        end
        table.sort(attendees)

        if #attendees == 0 then
            AddText(L["No attendees recorded."], 14, { 0.5, 0.5, 0.5 })
        else
            local COL_W    = 180
            local COL_CNT  = 3
            local ROW_H    = 18
            local rowsNeed = math.ceil(#attendees / COL_CNT)

            for r = 1, rowsNeed do
                for c = 1, COL_CNT do
                    local ni   = (r - 1) * COL_CNT + c
                    local name = attendees[ni]
                    if name then
                        local nt = NextNameTag()
                        nt:SetWidth(COL_W)
                        nt:SetPoint("TOPLEFT", sc, "TOPLEFT", 14 + (c - 1) * COL_W, -yOffset)
                        nt.lbl:SetText("- " .. name)
                        nt.lbl:SetTextColor(0.85, 0.85, 0.85)
                    end
                end
                yOffset = yOffset + ROW_H + 2
            end
            yOffset = yOffset + 4
        end
    end

    yOffset = yOffset + 6

    -- ================================================================
    -- SECTION 3 — PRIORITY POSITION CHANGES
    -- Reads from db.SessionPositionLog[sessionID] (populated since
    -- the session-tracking feature was added). Old archived entries
    -- without sessionID gracefully show a notice.
    -- ================================================================
    local posCollapsed = AddHeader("positions", SECTION_ICONS.positions, L["Position Changes"])

    if not posCollapsed then
        local posChanges = {}
        local posKey

        if isCurrent then
            posKey = sessionEntry.sessionID and tostring(sessionEntry.sessionID)
        else
            posKey = sessionEntry.sessionID and tostring(sessionEntry.sessionID)
        end

        local splBucket = posKey and db.SessionPositionLog and db.SessionPositionLog[posKey]
        if splBucket then
            for _, e in ipairs(splBucket) do
                table.insert(posChanges, e)
            end
        end

        if #posChanges > 0 then
            -- Show newest-first, cap at 30
            local startIdx = math.max(1, #posChanges - 29)
            for i = #posChanges, startIdx, -1 do
                AddText(posChanges[i], 14)
            end
            if #posChanges > 30 then
                AddText(string.format(L["... and %d more entries"], #posChanges - 30),
                    14, { 0.5, 0.5, 0.5 })
            end
        elseif not isCurrent and not sessionEntry.sessionID then
            AddText(L["Position log not available (pre-dates session tracking)."],
                14, { 0.5, 0.5, 0.5 })
        else
            AddText(L["No position changes recorded."], 14, { 0.5, 0.5, 0.5 })
        end
    end

    yOffset = yOffset + 6

    -- ================================================================
    -- SECTION 4 — DECAY APPLIED
    -- ================================================================
    local decayCollapsed = AddHeader("decay", SECTION_ICONS.decay, L["Decay Applied"])

    if not decayCollapsed then
        local decayEntries = {}

        -- Look for decay-tagged lines in the same session position log
        local posKey = sessionEntry.sessionID and tostring(sessionEntry.sessionID)
        local splBucket = posKey and db.SessionPositionLog and db.SessionPositionLog[posKey]
        if splBucket then
            for _, entry in ipairs(splBucket) do
                local lower = entry:lower()
                if lower:find("decay") or lower:find("absent") then
                    table.insert(decayEntries, entry)
                end
            end
        end

        if #decayEntries > 0 then
            for _, entry in ipairs(decayEntries) do
                AddText(entry, 14, { 0.93, 0.65, 0.37 })
            end
        else
            local decayEnabled = config.enabled
            local penalty      = config.defaultPenalty or 0
            local decayStr
            if not decayEnabled then
                decayStr = L["Decay disabled."]
            elseif isCurrent then
                decayStr = L["No decay applied yet."]
            else
                decayStr = string.format(
                    L["Decay of %d positions was applied when session ended."], penalty)
            end
            AddText(decayStr, 14, { 0.5, 0.5, 0.5 })
        end
    end

    yOffset = yOffset + 16
    sc:SetHeight(yOffset)
end

function UI_RaidHistory:OnEnable()
    self:RegisterMessage("DLC_HISTORY_UPDATED", function()
        if self.frame and self.frame:IsShown() then
            self:Refresh()
        end
    end)
end
