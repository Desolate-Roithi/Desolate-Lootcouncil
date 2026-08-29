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

-- ---- Factory: button row ----
local function FactoryButtonRow(parent)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)

    local btn = NativeGUI:CreateButton(row, "", 220, 24, "Action")
    btn:SetPoint("LEFT", 14, 0)
    row.btn = btn

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
        self.pHeaders    = {}   -- section header frames
        self.pTextRows   = {}   -- plain text rows
        self.pNameTags   = {}   -- attendee name tags
        self.pLootRows   = {}   -- loot item rows
        self.pBossRows   = {}   -- boss rows
        self.pButtonRows = {}   -- action button rows

        -- Dropdown
        local drop, dropBtn = NativeGUI:CreateDropdown(frame, L["Select Session"], 320, {}, nil, function(key)
            self.selectedIndex = key
            self:Refresh()
        end, RaidHistorySort)
        drop:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
        self.sessionDrop = drop

        -- Delete button — aligned to dropdown top edge
        local btnDel = NativeGUI:CreateButton(frame, L["Delete Entry"], 105, 24, "Stop")
        btnDel:SetPoint("LEFT", dropBtn, "RIGHT", 10, 0)
        btnDel:SetScript("OnClick", function()
            if not self.selectedIndex or self.selectedIndex == "CURRENT" then return end
            DesolateLootcouncil.API:DeleteAttendanceHistoryEntry(self.selectedIndex)
            self.selectedIndex = nil
            self:ShowRaidHistoryWindow()
        end)
        self.btnDelete = btnDel

        -- Export button — aligned to Delete button right edge
        local btnExport = NativeGUI:CreateButton(frame, L["Export Event"], 105, 24, "Action")
        btnExport:SetPoint("LEFT", btnDel, "RIGHT", 8, 0)
        btnExport:SetScript("OnClick", function()
            if not self.selectedIndex then return end
            self:ExportSelectedEvent()
        end)
        self.btnExport = btnExport

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
    self.btnExport:SetEnabled(self.selectedIndex ~= nil)

    self:Refresh()
end

function UI_RaidHistory:ExportSelectedEvent()
    if not self.selectedIndex then return end
    local API = DesolateLootcouncil.API
    local exportStr = API:ExportSingleRaidHistoryEvent(self.selectedIndex)
    if exportStr and exportStr ~= "" then
        self:ShowExportWindow(exportStr)
    end
end

function UI_RaidHistory:ShowExportWindow(exportStr)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.exportFrame then
        local frame = NativeGUI:CreateWindow("DLCRaidHistoryExportFrame", L["Export Raid Event"], "RaidHistoryExport")
        self.exportFrame = frame

        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
        desc:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -36)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetText(L["Press Ctrl+C to copy the export string below. You can import this into any profile via Settings > Profiles > Import to Current Profile."])
        self.exportDesc = desc

        local sf, sc = NativeGUI:CreateScrollFrame(frame, -85, -50)
        self.exportScrollFrame = sf
        self.exportScrollContent = sc

        local eb = NativeGUI:CreateReadOnlyCopyBox(sc)
        eb:SetPoint("TOPLEFT", sc, "TOPLEFT", 6, -6)
        eb:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -6, -6)
        eb:SetWidth(sf:GetWidth() - 16)
        self.exportEditBox = eb

        local btnClose = NativeGUI:CreateButton(frame, L["Close"], 90, 24, "Default")
        btnClose:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
        btnClose:SetScript("OnClick", function()
            frame:Hide()
        end)
    end

    self.exportFrame:Show()
    self.exportEditBox.fullText = exportStr
    self.exportEditBox:SetText(exportStr)
    self.exportEditBox:SetWidth(self.exportScrollFrame:GetWidth() - 16)
    local height = self.exportEditBox:GetHeight()
    if height < 60 then height = 60 end
    self.exportScrollContent:SetHeight(height + 20)

    C_Timer.After(0.05, function()
        if self.exportEditBox then
            self.exportEditBox:SetFocus()
            self.exportEditBox:HighlightText()
        end
    end)
end

function UI_RaidHistory:ShowPositionChangesCopyWindow(posChanges)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.posCopyFrame then
        local frame = NativeGUI:CreateWindow("DLCRaidHistoryPosCopyFrame", L["Position Changes Log"], "RaidHistoryPosCopy")
        self.posCopyFrame = frame

        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
        desc:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -36)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetText(L["Press Ctrl+C to copy all position changes for this session."])
        self.posCopyDesc = desc

        local sf, sc = NativeGUI:CreateScrollFrame(frame, -85, -50)
        self.posCopyScrollFrame = sf
        self.posCopyScrollContent = sc

        local eb = NativeGUI:CreateReadOnlyCopyBox(sc)
        eb:SetPoint("TOPLEFT", sc, "TOPLEFT", 6, -6)
        eb:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -6, -6)
        eb:SetWidth(sf:GetWidth() - 16)
        self.posCopyEditBox = eb

        local btnClose = NativeGUI:CreateButton(frame, L["Close"], 90, 24, "Default")
        btnClose:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
        btnClose:SetScript("OnClick", function()
            frame:Hide()
        end)
    end

    local textContent = table.concat(posChanges or {}, "\n")
    self.posCopyFrame:Show()
    self.posCopyEditBox.fullText = textContent
    self.posCopyEditBox:SetText(textContent)
    self.posCopyEditBox:SetWidth(self.posCopyScrollFrame:GetWidth() - 16)
    local height = self.posCopyEditBox:GetHeight()
    if height < 60 then height = 60 end
    self.posCopyScrollContent:SetHeight(height + 20)

    C_Timer.After(0.05, function()
        if self.posCopyEditBox then
            self.posCopyEditBox:SetFocus()
            self.posCopyEditBox:HighlightText()
        end
    end)
end

-- ============================================================
-- Section Renderers
-- ============================================================

local function ParseItemTimestamp(item)
    if DesolateLootcouncil.API and DesolateLootcouncil.API.ParseItemTimestamp then
        return DesolateLootcouncil.API:ParseItemTimestamp(item)
    end
    if not item or type(item) ~= "table" then return 0 end
    return tonumber(item.timestamp) or 0
end

local function SetupLootRow(row, item, awardIdx, historyModule, NativeGUI, theme, lootCount, isOfficer)
    NativeGUI = NativeGUI or DesolateLootcouncil:GetModule("UI_NativeGUI")
    -- Alternating stripe
    if lootCount % 2 == 0 then
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 0 })
        row:SetBackdropColor(theme.bg[1] * 1.2, theme.bg[2] * 1.2, theme.bg[3] * 1.2, 0.3)
    else
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 0 })
        row:SetBackdropColor(0, 0, 0, 0)
    end

    -- Icon: Dynamically load from Blizzard Item API (matching ItemManager)
    local itemID = item.itemID or (item.link and select(1, C_Item.GetItemInfoInstant(item.link)))
    local itemTexture = nil
    if itemID then
        local _, itemLink, _, _, _, _, _, _, _, tex = C_Item.GetItemInfo(itemID)
        if not itemLink and Item and Item.CreateFromItemID then
            local itemObj = Item:CreateFromItemID(itemID)
            if not itemObj:IsItemEmpty() then
                itemObj:ContinueOnItemLoad(function()
                    if row.iconTex and row:IsShown() then
                        local _, _, _, _, _, _, _, _, _, loadedTex = C_Item.GetItemInfo(itemID)
                        row.iconTex:SetTexture(loadedTex or C_Item.GetItemIconByID(itemID) or 134400)
                    end
                end)
            end
            itemTexture = C_Item.GetItemIconByID(itemID)
        else
            itemTexture = tex or C_Item.GetItemIconByID(itemID)
        end
    elseif item.link and C_Item and C_Item.GetItemInfoInstant then
        itemTexture = select(5, C_Item.GetItemInfoInstant(item.link))
    end
    row.iconTex:SetTexture(itemTexture or 134400)
    row.iconBtn:SetScript("OnEnter", function()
        if item.link then
            GameTooltip:SetOwner(row.iconBtn, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(item.link)
            GameTooltip:Show()
        end
    end)
    row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Info (item + winner)
    local winnerDisp = DesolateLootcouncil:GetDisplayName(item.winner or "Unknown")
    local colWinner  = NativeGUI and NativeGUI.FormatClassColor and NativeGUI:FormatClassColor(item.winnerClass, winnerDisp) or winnerDisp

    local ts = ParseItemTimestamp(item)
    local timeText = (NativeGUI and NativeGUI.FormatTime and ts > 0 and NativeGUI:FormatTime(ts)) or (ts > 0 and date("%H:%M", ts)) or ""

    if isOfficer then
        row.btnReaward:Show()
        -- Re-award
        row.btnReaward:ClearAllPoints()
        row.btnReaward:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.btnReaward:SetScript("OnClick", function()
            DesolateLootcouncil.API:ReawardItem(awardIdx)
            C_Timer.After(0.1, function()
                historyModule:ShowRaidHistoryWindow(historyModule.selectedIndex)
            end)
        end)

        -- Time
        row.timeLbl:ClearAllPoints()
        row.timeLbl:SetPoint("RIGHT", row.btnReaward, "LEFT", -6, 0)
        row.timeLbl:SetText(timeText)

        -- Vote type
        local vt    = item.voteType or "?"
        local vtCol = { 0.6, 0.6, 0.6 }
        local vc = NativeGUI and NativeGUI.VOTE_COLORS and NativeGUI.VOTE_COLORS[vt]
        if vc then vtCol = { vc.r, vc.g, vc.b } end
        row.vtLbl:Show()
        row.vtLbl:ClearAllPoints()
        row.vtLbl:SetPoint("RIGHT", row.timeLbl, "LEFT", -4, 0)
        row.vtLbl:SetText(vt)
        row.vtLbl:SetTextColor(unpack(vtCol))

        row.infoLbl:ClearAllPoints()
        row.infoLbl:SetPoint("LEFT",  row.iconBtn, "RIGHT", 6, 0)
        row.infoLbl:SetPoint("RIGHT", row.vtLbl,   "LEFT", -6, 0)
        row.infoLbl:SetText((item.link or "???") .. " - " .. colWinner)
    else
        row.btnReaward:Hide()
        row.vtLbl:Hide()

        -- Time
        row.timeLbl:ClearAllPoints()
        row.timeLbl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.timeLbl:SetText(timeText)

        row.infoLbl:ClearAllPoints()
        row.infoLbl:SetPoint("LEFT",  row.iconBtn, "RIGHT", 6, 0)
        row.infoLbl:SetPoint("RIGHT", row.timeLbl, "LEFT", -6, 0)
        row.infoLbl:SetText((item.link or "???") .. " - " .. colWinner)
    end
end

-- ============================================================
-- SECTION RENDERERS
-- ============================================================

local function SetupBossTooltip(row, b, NativeGUI)
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
end

local function SetupAttendeeTooltip(tagWidget, displayName, attendedList, NativeGUI)
    tagWidget:SetScript("OnEnter", function()
        GameTooltip:SetOwner(tagWidget, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(displayName, 1, 1, 1)
        if attendedList and #attendedList > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Characters in attendance:"], 0.8, 0.8, 0.8)
            for _, charEntry in ipairs(attendedList) do
                local charName = charEntry.name or charEntry
                local charClass = charEntry.class
                local isAlt = charEntry.isAlt
                local cIcon = NativeGUI:GetClassIconMarkup(charClass, 12)
                local col = NativeGUI:FormatClassColor(charClass, charName)
                local lineText = cIcon .. " " .. col
                if isAlt then
                    lineText = lineText .. " |cff888888(" .. L["Alt"] .. ")|r"
                end
                GameTooltip:AddLine(lineText, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    tagWidget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function SetupAttendeeTag(nt, rawName, sessionEntry, NativeGUI, db, API)
    local displayName = DesolateLootcouncil:GetDisplayName(rawName)
    local details = sessionEntry.attendeeDetails and sessionEntry.attendeeDetails[rawName]

    if details then
        local mainClass = details.mainClass or (db.MainRoster and db.MainRoster[rawName] and db.MainRoster[rawName].class) or "WARRIOR"
        local icon = NativeGUI:GetClassIconMarkup(mainClass, 13)
        local colName = NativeGUI:FormatClassColor(mainClass, displayName)
        nt.lbl:SetText("- " .. icon .. " " .. colName)

        local attendedList = {}
        if details.attendedChars then
            for charName, charData in pairs(details.attendedChars) do
                if type(charData) == "table" then
                    table.insert(attendedList, {
                        name  = charName,
                        class = charData.class or "WARRIOR",
                        isAlt = charData.isAlt or false
                    })
                else
                    local charClass = API:GetUnitClass(charName) or "WARRIOR"
                    local isAlt = (rawName ~= charName)
                    table.insert(attendedList, {
                        name  = charName,
                        class = charClass,
                        isAlt = isAlt
                    })
                end
            end
        end
        table.sort(attendedList, function(a, b)
            if a.isAlt ~= b.isAlt then return not a.isAlt end
            return a.name < b.name
        end)

        SetupAttendeeTooltip(nt, displayName, attendedList, NativeGUI)
    else
        local class = "WARRIOR"
        local mainName = (db.playerRoster and db.playerRoster.alts and db.playerRoster.alts[rawName]) or rawName
        local rData = db.MainRoster and (db.MainRoster[mainName] or db.MainRoster[rawName] or db.MainRoster[displayName])
        if rData and rData.class then
            class = rData.class
        elseif db.playerRoster and db.playerRoster.classMap then
            class = db.playerRoster.classMap[rawName] or db.playerRoster.classMap[mainName] or class
        end
        local icon = NativeGUI:GetClassIconMarkup(class, 13)
        local colName = NativeGUI:FormatClassColor(class, displayName)
        nt.lbl:SetText("- " .. icon .. " " .. colName)

        SetupAttendeeTooltip(nt, displayName, nil, NativeGUI)
    end
end

function UI_RaidHistory:RenderLootSection(sc, theme, NativeGUI, sessionEntry, isCurrent, layoutState, NextLootRow, AddText, AddHeader)
    local lootCollapsed = AddHeader("loot", SECTION_ICONS.loot, L["Loot Awarded"])
    if lootCollapsed then
        layoutState.yOffset = layoutState.yOffset + 6
        return
    end

    NativeGUI = NativeGUI or DesolateLootcouncil:GetModule("UI_NativeGUI")
    local API = DesolateLootcouncil.API
    local awarded
    local checkTimestamp = false
    local isOfficer = DesolateLootcouncil:AmIOfficerOrLM()
    if isOfficer then
        if isCurrent then
            awarded = API:GetAwardedList()
        else
            if sessionEntry.awarded or sessionEntry.loot then
                awarded = sessionEntry.awarded or sessionEntry.loot
            else
                awarded = API:GetAwardedList()
                checkTimestamp = true
            end
        end
    else
        if isCurrent then
            local db = DesolateLootcouncil.db.profile
            awarded = db.session and db.session.publicAwardLog or {}
        else
            if sessionEntry.publicAwardLog or sessionEntry.publicLoot then
                awarded = sessionEntry.publicAwardLog or sessionEntry.publicLoot
            else
                local db = DesolateLootcouncil.db.profile
                awarded = db.session and db.session.publicAwardLog or {}
                checkTimestamp = true
            end
        end
    end
    local lootCount         = 0
    local sessionDatePrefix = sessionEntry.date and sessionEntry.date:sub(1, 10)

    local itemsToRender = {}
    if type(awarded) == "table" then
        for awardIdx, item in pairs(awarded) do
            local numIdx = tonumber(awardIdx) or 999
            local include = true
            if checkTimestamp then
                local ts = ParseItemTimestamp(item)
                local d = ts > 0 and date("%Y-%m-%d", ts)
                include = (d and sessionDatePrefix and d == sessionDatePrefix) or false
            end

            if include then
                table.insert(itemsToRender, { item = item, origIdx = numIdx })
            end
        end
    end

    -- Always order awarded loot chronologically by timestamp ascending
    table.sort(itemsToRender, function(a, b)
        local tA = ParseItemTimestamp(a.item)
        local tB = ParseItemTimestamp(b.item)
        if tA ~= tB then
            return tA < tB
        end
        return (a.origIdx or 0) < (b.origIdx or 0)
    end)

    for _, entry in ipairs(itemsToRender) do
        lootCount = lootCount + 1
        local row = NextLootRow()
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0,   -layoutState.yOffset)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -layoutState.yOffset)

        SetupLootRow(row, entry.item, entry.origIdx, self, NativeGUI, theme, lootCount, isOfficer)

        layoutState.yOffset = layoutState.yOffset + 32
    end

    if lootCount == 0 then
        AddText(L["No loot awarded in this session."], 14, { 0.5, 0.5, 0.5 })
    end

    layoutState.yOffset = layoutState.yOffset + 6
end

function UI_RaidHistory:RenderBossSection(sc, theme, NativeGUI, sessionEntry, layoutState, NextBossRow, AddText, AddHeader)
    local bossCollapsed = AddHeader("boss", SECTION_ICONS.boss, L["Bosses & Pulls"])
    if bossCollapsed then
        layoutState.yOffset = layoutState.yOffset + 6
        return
    end

    NativeGUI = NativeGUI or DesolateLootcouncil:GetModule("UI_NativeGUI")
    local bossLogs = sessionEntry.bossLogs
    if not bossLogs or #bossLogs == 0 then
        AddText(L["No boss logs recorded for this session."], 14, { 0.5, 0.5, 0.5 })
        layoutState.yOffset = layoutState.yOffset + 6
        return
    end

    local sortedBosses = {}
    for origIdx, b in ipairs(bossLogs) do
        table.insert(sortedBosses, { boss = b, origIdx = origIdx })
    end

    -- Order killed bosses chronologically by timestamp (killedTime) ascending, placing unkilled afterward
    table.sort(sortedBosses, function(a, b)
        local kA = (a.boss.killed and a.boss.killedTime) or nil
        local kB = (b.boss.killed and b.boss.killedTime) or nil
        if kA and kB then
            if kA ~= kB then return kA < kB end
            return a.origIdx < b.origIdx
        elseif kA and not kB then
            return true
        elseif not kA and kB then
            return false
        else
            return a.origIdx < b.origIdx
        end
    end)

    for _, entry in ipairs(sortedBosses) do
        local b = entry.boss
        local row = NextBossRow()
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  14, -layoutState.yOffset)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -layoutState.yOffset)

        -- Icon: boss skull
        row.iconTex:SetTexture("Interface\\Icons\\inv_misc_skull_02")

        -- Construct display text (session pulls)
        local statusStr, statusColor
        if b.killed then
            local timeStr = b.killedTime and date("%H:%M", b.killedTime) or "?"
            statusStr = string.format("Defeated at %s", timeStr)
            statusColor = "|cff20ff20" -- green
        else
            statusStr = "Wiped"
            statusColor = "|cffff3030" -- red
        end

        local API = DesolateLootcouncil.API
        local diffBadge = (API and API.GetDifficultyBadge and API:GetDifficultyBadge(b.difficultyID, b.name))
        local cleanName = (API and API.StripDifficultySuffix and API:StripDifficultySuffix(b.name)) or b.name

        local displayName
        if diffBadge and diffBadge ~= "" then
            displayName = string.format("%s %s - Pulls: %d (%s%s|r)", cleanName, diffBadge, b.pulls or 1, statusColor, statusStr)
        else
            displayName = string.format("%s - Pulls: %d (%s%s|r)", cleanName, b.pulls or 1, statusColor, statusStr)
        end
        row.lbl:SetText(displayName)

        -- Tooltip for the kill roster
        SetupBossTooltip(row, b, NativeGUI)

        layoutState.yOffset = layoutState.yOffset + 20
    end

    layoutState.yOffset = layoutState.yOffset + 6
end

function UI_RaidHistory:RenderAttendanceSection(sc, theme, NativeGUI, sessionEntry, layoutState, NextNameTag, AddText, AddHeader)
    local attendCollapsed = AddHeader("attend", SECTION_ICONS.attend, L["Players Attended"])
    if attendCollapsed then
        layoutState.yOffset = layoutState.yOffset + 6
        return
    end

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
        layoutState.yOffset = layoutState.yOffset + 6
        return
    end

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
                SetupAttendeeTag(nt, rawName, sessionEntry, NativeGUI, db, API)
            end
        end
        layoutState.yOffset = layoutState.yOffset + ROW_H + 2
    end
    layoutState.yOffset = layoutState.yOffset + 4

    layoutState.yOffset = layoutState.yOffset + 6
end

local function IsDecayLogEntry(entry)
    if type(entry) ~= "string" then return false end
    local API = DesolateLootcouncil.API
    if API and API.IsDecayLogMessage then
        return API:IsDecayLogMessage(entry)
    end
    return entry:find("[Decay]", 1, true) ~= nil or entry:find("[Verfall]", 1, true) ~= nil
end

function UI_RaidHistory:RenderPositionChangesSection(sc, NativeGUI, sessionEntry, isCurrent, layoutState, AddText, AddHeader, NextButtonRow)
    local posCollapsed = AddHeader("positions", SECTION_ICONS.positions, L["Position Changes"])
    if posCollapsed then
        layoutState.yOffset = layoutState.yOffset + 6
        return
    end

    local db  = DesolateLootcouncil.db.profile
    local posChanges = {}
    local posKey = sessionEntry.sessionID and tostring(sessionEntry.sessionID)

    local splBucket = posKey and db.SessionPositionLog and db.SessionPositionLog[posKey]
    if splBucket then
        for _, e in ipairs(splBucket) do
            if not IsDecayLogEntry(e) then
                table.insert(posChanges, e)
            end
        end
    end

    if #posChanges > 0 then
        -- Show newest-first, cap inline display at 10
        local startIdx = math.max(1, #posChanges - 9)
        for i = #posChanges, startIdx, -1 do
            AddText(posChanges[i], 14)
        end
        if #posChanges > 10 then
            AddText(string.format(L["... and %d older entries"], #posChanges - 10),
                14, { 0.5, 0.5, 0.5 })
        end

        if NextButtonRow then
            local btnRow = NextButtonRow()
            btnRow:SetPoint("TOPLEFT",  sc, "TOPLEFT",  14, -layoutState.yOffset)
            btnRow:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -layoutState.yOffset)
            btnRow.btn:SetText(L["Copy All Position Changes"])
            btnRow.btn:SetScript("OnClick", function()
                self:ShowPositionChangesCopyWindow(posChanges)
            end)
            layoutState.yOffset = layoutState.yOffset + 30
        end
    elseif not isCurrent and not sessionEntry.sessionID then
        -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Notice for pre-session tracking legacy records
        AddText(L["Position log not available (pre-dates session tracking)."],
            14, { 0.5, 0.5, 0.5 })
    else
        AddText(L["No position changes recorded."], 14, { 0.5, 0.5, 0.5 })
    end

    layoutState.yOffset = layoutState.yOffset + 6
end

local function GetSessionDecaySummary(sessionEntry, db, config)
    local isCurrent = (sessionEntry.sessionID == "CURRENT")
    local decayEnabled = config.enabled
    local defaultPenalty = config.defaultPenalty or 1

    if not decayEnabled or sessionEntry.decayApplied == -1 then
        return { disabled = true }
    end

    if isCurrent then
        return { isCurrent = true }
    end

    -- Check if explicitly stored in sessionEntry
    local absentList = {}
    local penalty = sessionEntry.decayPenalty or defaultPenalty

    if sessionEntry.decayAbsent then
        for p in pairs(sessionEntry.decayAbsent) do
            table.insert(absentList, p)
        end
    end

    -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Fallback: Extract decay from SessionPositionLog for uncompacted legacy sessions
    if #absentList == 0 then
        local posKey = sessionEntry.sessionID and tostring(sessionEntry.sessionID)
        local splBucket = posKey and db.SessionPositionLog and db.SessionPositionLog[posKey]
        local API = DesolateLootcouncil.API
        if splBucket and API and API.ParseDecayLogMessage then
            local seen = {}
            for _, entry in ipairs(splBucket) do
                local pName, pPen = API:ParseDecayLogMessage(entry)
                if pName then
                    if pPen then penalty = tonumber(pPen) or penalty end
                    if not seen[pName] then
                        seen[pName] = true
                        table.insert(absentList, pName)
                    end
                end
            end
        end
    end

    -- Second Fallback: Compare sessionEntry.attendees against MainRoster if decayApplied is set
    if #absentList == 0 and sessionEntry.decayApplied and sessionEntry.decayApplied ~= -1 and sessionEntry.attendees and db.MainRoster then
        for mName in pairs(db.MainRoster) do
            if not sessionEntry.attendees[mName] then
                table.insert(absentList, mName)
            end
        end
    end

    table.sort(absentList)
    return {
        applied = (sessionEntry.decayApplied ~= nil and sessionEntry.decayApplied ~= -1) or (#absentList > 0),
        penalty = penalty,
        absent = absentList
    }
end

function UI_RaidHistory:RenderDecaySection(sc, NativeGUI, sessionEntry, isCurrent, config, layoutState, AddText, AddHeader)
    local decayCollapsed = AddHeader("decay", SECTION_ICONS.decay, L["Decay Applied"])
    if decayCollapsed then
        layoutState.yOffset = layoutState.yOffset + 6
        return
    end

    local db = DesolateLootcouncil.db.profile
    local summary = GetSessionDecaySummary(sessionEntry, db, config)

    if summary.disabled then
        AddText(L["Decay disabled."], 14, { 0.5, 0.5, 0.5 })
    elseif isCurrent or summary.isCurrent then
        AddText(L["No decay applied yet."], 14, { 0.5, 0.5, 0.5 })
    elseif summary.applied and #summary.absent > 0 then
        local formattedNames = {}
        for _, name in ipairs(summary.absent) do
            local class = DesolateLootcouncil.API:GetUnitClass(name)
            local disp = DesolateLootcouncil:GetDisplayName(name)
            table.insert(formattedNames, NativeGUI:FormatClassColor(class, disp))
        end
        local namesStr = table.concat(formattedNames, ", ")
        local decayStr = string.format(L["Decay of %d applied to players: %s"], summary.penalty, namesStr)
        AddText(decayStr, 14, { 0.93, 0.65, 0.37 })
    elseif summary.applied then
        AddText(string.format(L["Decay of %d positions was applied when session ended (no absent players)."], summary.penalty), 14, { 0.5, 0.5, 0.5 })
    else
        AddText(L["No decay applied yet."], 14, { 0.5, 0.5, 0.5 })
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
    if self.pButtonRows then PoolReset(self.pButtonRows) end

    -- Pool cursors
    local hN, tN, nN, lN, bN, btnN = 0, 0, 0, 0, 0, 0

    local sc     = self.scrollContent
    local API    = DesolateLootcouncil.API
    local config = API:GetAttendanceConfig()
    local hist   = API:GetAttendanceHistory()
    local idx    = self.selectedIndex
    local theme  = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if self.btnDelete then self.btnDelete:SetEnabled(idx ~= nil and idx ~= "CURRENT") end
    if self.btnExport then self.btnExport:SetEnabled(idx ~= nil) end

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

    -- ---- Helper: next pooled button row ----
    local function NextButtonRow()
        btnN = btnN + 1
        self.pButtonRows = self.pButtonRows or {}
        return PoolGet(self.pButtonRows, btnN, FactoryButtonRow, sc)
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
            attendeeDetails = config.attendeeDetails or {},
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
    if DesolateLootcouncil:AmIOfficerOrLM() then
        self:RenderPositionChangesSection(sc, NativeGUI, sessionEntry, isCurrent, layoutState, AddText, AddHeader, NextButtonRow)
    end

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
