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
    boss      = "Interface\\Icons\\inv_misc_skull_02",
    attend    = "Interface\\Icons\\Achievement_General_StayClassy",
    decay     = "Interface\\Icons\\ability_warlock_fireandbrimstone",
    positions = "Interface\\Icons\\inv_misc_scrollunrolled01d",
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
    row:EnableMouse(true)
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetAllPoints()
    lbl:SetJustifyH("LEFT")
    row.lbl = lbl
    return row
end

-- ---- Factory: boss row ----
local function FactoryBossRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)
    row:EnableMouse(true)

    local iconTex = row:CreateTexture(nil, "OVERLAY")
    iconTex:SetSize(14, 14)
    iconTex:SetPoint("LEFT", 4, 0)
    row.iconTex = iconTex

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", 22, 0)
    lbl:SetPoint("RIGHT", -10, 0)
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



local function RaidHistorySort(a, b)
    if a == "CURRENT" then return true end
    if b == "CURRENT" then return false end
    local numA = tonumber(a)
    local numB = tonumber(b)
    if numA and numB then
        return numA < numB
    end
    return tostring(a) < tostring(b)
end

-- ============================================================
-- Public: Open window
-- ============================================================

function UI_RaidHistory:ShowRaidHistoryWindow(preselect)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.frame then
        local frame = NativeGUI:CreateWindow("DLCRaidHistoryFrame", L["Raid History"], "RaidHistory")
        self.frame = frame

        -- Collapsed state per section (false = expanded)
        self.collapsed = { loot = false, boss = false, attend = false, positions = false, decay = false }

        -- Widget pools (grow lazily; cleared on each Refresh)
        self.pHeaders  = {}   -- section header frames
        self.pTextRows = {}   -- plain text rows
        self.pNameTags = {}   -- attendee name tags
        self.pLootRows = {}   -- loot item rows
        self.pBossRows = {}   -- boss rows

        -- Dropdown
        local drop, dropBtn = NativeGUI:CreateDropdown(frame, L["Select Session"], 320, {}, nil, function(key)
            self.selectedIndex = key
            self:Refresh()
        end, RaidHistorySort)
        drop:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
        self.sessionDrop = drop

        -- Delete button — aligned to dropdown top edge
        local btnDel = NativeGUI:CreateButton(frame, L["Delete Entry"], 110, 24, "Stop")
        btnDel:SetPoint("LEFT", dropBtn, "RIGHT", 10, 0)
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
-- Section Renderers
-- ============================================================

function UI_RaidHistory:RenderLootSection(sc, theme, NativeGUI, sessionEntry, isCurrent, layoutState, NextLootRow, AddText, AddHeader)
    local lootCollapsed = AddHeader("loot", SECTION_ICONS.loot, L["Loot Awarded"])

    if not lootCollapsed then
        local API = DesolateLootcouncil.API
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
                row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0,   -layoutState.yOffset)
                row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -layoutState.yOffset)

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
                row.timeLbl:SetText(NativeGUI:FormatTime(item.timestamp))

                -- Vote type
                local vt    = item.voteType or "?"
                local vtCol = { 0.6, 0.6, 0.6 }
                local vc = NativeGUI.VOTE_COLORS[vt]
                if vc then vtCol = { vc.r, vc.g, vc.b } end
                row.vtLbl:ClearAllPoints()
                row.vtLbl:SetPoint("RIGHT", row.timeLbl, "LEFT", -4, 0)
                row.vtLbl:SetText(vt)
                row.vtLbl:SetTextColor(unpack(vtCol))

                -- Info (item + winner)
                local winnerDisp = DesolateLootcouncil:GetDisplayName(item.winner or "Unknown")
                local colWinner  = NativeGUI:FormatClassColor(item.winnerClass, winnerDisp)
                row.infoLbl:ClearAllPoints()
                row.infoLbl:SetPoint("LEFT",  row.iconBtn, "RIGHT", 6, 0)
                row.infoLbl:SetPoint("RIGHT", row.vtLbl,   "LEFT", -6, 0)
                row.infoLbl:SetText((item.link or "???") .. " - " .. colWinner)

                layoutState.yOffset = layoutState.yOffset + 32
            end
        end

        if lootCount == 0 then
            AddText(L["No loot awarded in this session."], 14, { 0.5, 0.5, 0.5 })
        end
    end

    layoutState.yOffset = layoutState.yOffset + 6
end

function UI_RaidHistory:RenderBossSection(sc, theme, NativeGUI, sessionEntry, layoutState, NextBossRow, AddText, AddHeader)
    local bossCollapsed = AddHeader("boss", SECTION_ICONS.boss, L["Bosses & Pulls"])

    if not bossCollapsed then
        local bossLogs = sessionEntry.bossLogs
        if not bossLogs or #bossLogs == 0 then
            AddText(L["No boss logs recorded for this session."], 14, { 0.5, 0.5, 0.5 })
        else
            for _, b in ipairs(bossLogs) do
                local row = NextBossRow()
                row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  14, -layoutState.yOffset)
                row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -layoutState.yOffset)

                -- Icon: boss skull
                row.iconTex:SetTexture("Interface\\Icons\\inv_misc_skull_02")

                -- Construct display text
                local statusStr, statusColor
                if b.killed then
                    local timeStr = b.killedTime and date("%H:%M", b.killedTime) or "?"
                    statusStr = string.format("Defeated at %s", timeStr)
                    statusColor = "|cff20ff20" -- green
                else
                    statusStr = "Wiped"
                    statusColor = "|cffff3030" -- red
                end

                local displayName = string.format("%s - Pulls: %d (%s%s|r)", b.name, b.pulls or 1, statusColor, statusStr)
                row.lbl:SetText(displayName)

                -- Tooltip for the kill roster
                if b.killed and b.roster and #b.roster > 0 then
                    row:SetScript("OnEnter", function()
                        GameTooltip:SetOwner(row, "ANCHOR_TOP")
                        GameTooltip:ClearLines()
                        GameTooltip:AddLine(b.name .. " Kill Roster", 1, 1, 1)
                        GameTooltip:AddLine(" ", 1, 1, 1)
                        GameTooltip:AddLine(string.format("Players Present (%d):", #b.roster), 0.93, 0.65, 0.37)
                        for _, player in ipairs(b.roster) do
                            local classColorHex = NativeGUI:GetClassColorHex(player.class)
                            local disp = player.name
                            if player.main and player.main ~= player.name then
                                disp = disp .. " (Alt of " .. player.main .. ")"
                            end
                            GameTooltip:AddLine(string.format("• |c%s%s|r (%s)", classColorHex, disp, player.class), 0.8, 0.8, 0.8)
                        end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                else
                    row:SetScript("OnEnter", function()
                        GameTooltip:SetOwner(row, "ANCHOR_TOP")
                        GameTooltip:ClearLines()
                        GameTooltip:AddLine(b.name, 1, 1, 1)
                        if not b.killed then
                            GameTooltip:AddLine("No kill roster available (Boss not defeated).", 0.5, 0.5, 0.5)
                        else
                            GameTooltip:AddLine("No kill roster data recorded.", 0.5, 0.5, 0.5)
                        end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end

                layoutState.yOffset = layoutState.yOffset + 20
            end
        end
    end

    layoutState.yOffset = layoutState.yOffset + 6
end

function UI_RaidHistory:RenderAttendanceSection(sc, theme, NativeGUI, sessionEntry, layoutState, NextNameTag, AddText, AddHeader)
    local attendCollapsed = AddHeader("attend", SECTION_ICONS.attend, L["Players Attended"])

    if not attendCollapsed then
        local API = DesolateLootcouncil.API
        local db  = DesolateLootcouncil.db.profile
        local attendees = {}
        if sessionEntry.attendees then
            for rawName in pairs(sessionEntry.attendees) do
                table.insert(attendees, rawName)
            end
        end
        table.sort(attendees, function(a, b)
            return API:GetDisplayName(a) < API:GetDisplayName(b)
        end)

        if #attendees == 0 then
            AddText(L["No attendees recorded."], 14, { 0.5, 0.5, 0.5 })
        else
            local COL_W    = 180
            local COL_CNT  = 3
            local ROW_H    = 18
            local rowsNeed = math.ceil(#attendees / COL_CNT)

            for r = 1, rowsNeed do
                for c = 1, COL_CNT do
                    local ni      = (r - 1) * COL_CNT + c
                    local rawName = attendees[ni]
                    if rawName then
                        local nt = NextNameTag()
                        nt:SetWidth(COL_W)
                        nt:SetPoint("TOPLEFT", sc, "TOPLEFT", 14 + (c - 1) * COL_W, -layoutState.yOffset)

                        local displayName = API:GetDisplayName(rawName)
                        local chars = sessionEntry.attendeeDetails and sessionEntry.attendeeDetails[rawName]

                        if chars and next(chars) ~= nil then
                            local maxKills = -1
                            local bestClass = nil
                            local attendedList = {}
                            local iconMarkups = ""

                            local charNames = {}
                            for cName in pairs(chars) do
                                table.insert(charNames, cName)
                            end
                            table.sort(charNames)

                            for _, cName in ipairs(charNames) do
                                local cData = chars[cName]
                                local charClass = cData.class or "WARRIOR"
                                local kills = cData.kills or 0

                                iconMarkups = iconMarkups .. NativeGUI:GetClassIconMarkup(charClass, 13)

                                if kills > maxKills then
                                    maxKills = kills
                                    bestClass = charClass
                                end

                                table.insert(attendedList, { name = cName, class = charClass, kills = kills })
                            end

                            local colName = NativeGUI:FormatClassColor(bestClass or "WARRIOR", displayName)
                            nt.lbl:SetText("- " .. iconMarkups .. " " .. colName)

                            nt:SetScript("OnEnter", function()
                                GameTooltip:SetOwner(nt, "ANCHOR_TOP")
                                GameTooltip:ClearLines()
                                GameTooltip:AddLine(displayName, 1, 1, 1)
                                GameTooltip:AddLine(" ", 1, 1, 1)
                                GameTooltip:AddLine("Characters Attended:", 0.93, 0.65, 0.37)
                                for _, char in ipairs(attendedList) do
                                    local classColor = NativeGUI:GetClassColorHex(char.class)
                                    local charDisp = "|c" .. classColor .. char.name .. "|r"
                                    local killsStr = string.format("%d boss kills", char.kills)
                                    GameTooltip:AddLine(string.format("• %s (%s, %s)", charDisp, char.class, killsStr), 0.7, 0.7, 0.7)
                                end
                                GameTooltip:Show()
                            end)
                            nt:SetScript("OnLeave", function() GameTooltip:Hide() end)
                        else
                            local class = "WARRIOR"
                            local rData = db.MainRoster and db.MainRoster[rawName]
                            if rData and rData.class then class = rData.class end
                            local icon = NativeGUI:GetClassIconMarkup(class, 13)
                            local colName = NativeGUI:FormatClassColor(class, displayName)
                            nt.lbl:SetText("- " .. icon .. " " .. colName)

                            nt:SetScript("OnEnter", function()
                                GameTooltip:SetOwner(nt, "ANCHOR_TOP")
                                GameTooltip:ClearLines()
                                GameTooltip:AddLine(displayName, 1, 1, 1)
                                GameTooltip:AddLine("No detailed character/boss kills data available.", 0.5, 0.5, 0.5)
                                GameTooltip:Show()
                            end)
                            nt:SetScript("OnLeave", function() GameTooltip:Hide() end)
                        end
                    end
                end
                layoutState.yOffset = layoutState.yOffset + ROW_H + 2
            end
            layoutState.yOffset = layoutState.yOffset + 4
        end
    end

    layoutState.yOffset = layoutState.yOffset + 6
end

function UI_RaidHistory:RenderPositionChangesSection(sc, NativeGUI, sessionEntry, isCurrent, layoutState, AddText, AddHeader)
    local posCollapsed = AddHeader("positions", SECTION_ICONS.positions, L["Position Changes"])

    if not posCollapsed then
        local db  = DesolateLootcouncil.db.profile
        local posChanges = {}
        local posKey = sessionEntry.sessionID and tostring(sessionEntry.sessionID)

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

    layoutState.yOffset = layoutState.yOffset + 6
end

function UI_RaidHistory:RenderDecaySection(sc, NativeGUI, sessionEntry, isCurrent, config, layoutState, AddText, AddHeader)
    local decayCollapsed = AddHeader("decay", SECTION_ICONS.decay, L["Decay Applied"])

    if not decayCollapsed then
        local db  = DesolateLootcouncil.db.profile
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

    layoutState.yOffset = layoutState.yOffset + 6
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
    PoolReset(self.pBossRows)

    -- Pool cursors
    local hN, tN, nN, lN, bN = 0, 0, 0, 0, 0

    local sc     = self.scrollContent
    local API    = DesolateLootcouncil.API
    local config = API:GetAttendanceConfig()
    local hist   = API:GetAttendanceHistory()
    local idx    = self.selectedIndex
    local theme  = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    -- ---- Cursor ----
    local layoutState = { yOffset = 6 }

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

    -- ---- Helper: next pooled boss row ----
    local function NextBossRow()
        bN = bN + 1
        return PoolGet(self.pBossRows, bN, FactoryBossRow, sc)
    end

    -- ---- Helper: add a plain text row ----
    local function AddText(text, indent, colour)
        local tr = NextTextRow()
        tr:SetPoint("TOPLEFT",  sc, "TOPLEFT",  indent or 14, -layoutState.yOffset)
        tr:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12,          -layoutState.yOffset)
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
        layoutState.yOffset = layoutState.yOffset + h + 2
    end

    -- ---- Helper: collapsible section header ----
    -- Returns true if the section is currently collapsed.
    local function AddHeader(sectionKey, icon, label)
        local row = NextHeader()
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0,   -layoutState.yOffset)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -layoutState.yOffset)
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

        layoutState.yOffset = layoutState.yOffset + 28
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
            bossLogs  = config.bossLogs or {},
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
    self:RenderLootSection(sc, theme, NativeGUI, sessionEntry, isCurrent, layoutState, NextLootRow, AddText, AddHeader)

    -- ================================================================
    -- SECTION 2 — BOSSES & PULLS
    -- ================================================================
    self:RenderBossSection(sc, theme, NativeGUI, sessionEntry, layoutState, NextBossRow, AddText, AddHeader)

    -- ================================================================
    -- SECTION 3 — PLAYERS ATTENDED
    -- ================================================================
    self:RenderAttendanceSection(sc, theme, NativeGUI, sessionEntry, layoutState, NextNameTag, AddText, AddHeader)

    -- ================================================================
    -- SECTION 3 — PRIORITY POSITION CHANGES
    -- ================================================================
    self:RenderPositionChangesSection(sc, NativeGUI, sessionEntry, isCurrent, layoutState, AddText, AddHeader)

    -- ================================================================
    -- SECTION 4 — DECAY APPLIED
    -- ================================================================
    self:RenderDecaySection(sc, NativeGUI, sessionEntry, isCurrent, config, layoutState, AddText, AddHeader)

    layoutState.yOffset = layoutState.yOffset + 10
    sc:SetHeight(layoutState.yOffset)
end

function UI_RaidHistory:OnEnable()
    self:RegisterMessage("DLC_HISTORY_UPDATED", function()
        if self.frame and self.frame:IsShown() then
            self:Refresh()
        end
    end)
end
