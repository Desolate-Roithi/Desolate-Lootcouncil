local _, AT = ...
if AT.abortLoad then return end

---@class UI_PriorityLogHistory : AceModule
local UI_PriorityLogHistory = DesolateLootcouncil:NewModule("UI_PriorityLogHistory", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local ACTION_CATEGORIES = {
    ALL = {
        label = L["All Events"],
        match = function(_act) return true end
    },
    AWARDS = {
        label = L["Loot Awards"],
        match = function(act) return act == "AWARD" or act == "REAWARD" end
    },
    MANUAL = {
        label = L["Priority Shifts"],
        match = function(act)
            return act == "TO_BOTTOM" or act == "RESTORE" or act == "PRIO_REORDER"
                or act == "PRIO_CHANGE" or act == "PRIO_MOVE" or act == "POSITION_CHANGE"
                or act == "PRIORITY_MANUAL_MOVE" or act == "PRIORITY_MOVE_BOTTOM" or act == "PRIORITY_RESTORE"
        end
    },
    DECAY = {
        label = L["Decay Penalties"],
        match = function(act) return act == "DECAY" or act == "PRIORITY_DECAY" end
    },
    ROSTER = {
        label = L["Roster Changes"],
        match = function(act)
            return type(act) == "string" and (act:find("ROSTER_", 1, true) ~= nil or act:find("ALT_", 1, true) ~= nil)
        end
    },
    SESSION = {
        label = L["Raid Sessions"],
        match = function(act)
            return type(act) == "string" and act:find("SESSION_", 1, true) ~= nil
        end
    },
    CATALOG = {
        label = L["Catalog Changes"],
        match = function(act) return act == "CATALOG_OVERRIDE" end
    }
}

local function GetActionBadgeText(act)
    if act == "AWARD" then
        return "|cffff8000[AWARD]|r"
    elseif act == "REAWARD" then
        return "|cffa335ee[REAWARD]|r"
    elseif act == "DECAY" or act == "PRIORITY_DECAY" then
        return "|cffff4444[DECAY]|r"
    elseif act == "TO_BOTTOM" or act == "PRIORITY_MOVE_BOTTOM" then
        return "|cffffaa00[BOTTOM]|r"
    elseif act == "RESTORE" or act == "PRIORITY_RESTORE" then
        return "|cff00ff00[RESTORE]|r"
    elseif act == "PRIO_REORDER" or act == "PRIO_CHANGE" or act == "PRIO_MOVE" or act == "POSITION_CHANGE" or act == "PRIORITY_MANUAL_MOVE" then
        return "|cffffff00[MOVE]|r"
    elseif type(act) == "string" and (act:find("ROSTER_", 1, true) or act:find("ALT_", 1, true)) then
        return "|cff0070dd[ROSTER]|r"
    elseif type(act) == "string" and act:find("SESSION_", 1, true) then
        return "|cff1eff00[SESSION]|r"
    elseif act == "CATALOG_OVERRIDE" then
        return "|cff00ccff[CATALOG]|r"
    else
        return string.format("|cff9d9d9d[%s]|r", tostring(act or "EVENT"))
    end
end

local function RenderAuditRow(self, e, row, topOffset, rowHeight, NativeGUI)
    row:SetHeight(rowHeight)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT",  self.scrollContent, "TOPLEFT",  0,   -topOffset)
    row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

    -- 1. Date / Timestamp
    if not row.dateLabel then
        row.dateLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.dateLabel:SetPoint("LEFT", 8, 0)
        row.dateLabel:SetWidth(125)
        row.dateLabel:SetJustifyH("LEFT")
        row.dateLabel:SetTextColor(0.65, 0.65, 0.65, 1)
    end
    row.dateLabel:SetText(e.d or tostring(e.t or ""))
    row.dateLabel:Show()

    -- 2. Action Badge
    if not row.badgeLabel then
        row.badgeLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.badgeLabel:SetPoint("LEFT", row.dateLabel, "RIGHT", 4, 0)
        row.badgeLabel:SetWidth(72)
        row.badgeLabel:SetJustifyH("LEFT")
    end
    row.badgeLabel:SetText(GetActionBadgeText(e.act))
    row.badgeLabel:Show()

    -- 3. Hash Receipt (right-anchored)
    if not row.hashBtn then
        local hashBtn = CreateFrame("Button", nil, row)
        hashBtn:SetSize(70, 20)
        hashBtn:SetPoint("RIGHT", -8, 0)
        hashBtn.text = hashBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hashBtn.text:SetAllPoints()
        hashBtn.text:SetJustifyH("RIGHT")
        row.hashBtn = hashBtn
    end
    local shortHash = (e.h and e.h ~= "") and string.sub(e.h, 1, 8) or "--------"
    row.hashBtn.text:SetText(string.format("|cff666666#%s|r", shortHash))
    row.hashBtn:Show()
    row.hashBtn:SetScript("OnEnter", function(btn)
        if e.h and e.h ~= "" then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Audit & Priority Ledger"], 1, 0.8, 0)
            GameTooltip:AddLine(string.format("Cryptographic State Hash:\n|cff00ff00%s|r", e.h), 1, 1, 1, true)
            if e.by then
                GameTooltip:AddLine(string.format("Author: |cffffffff%s|r", DesolateLootcouncil:GetDisplayName(e.by)), 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end
    end)
    row.hashBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 4. Main Event Description (stretches between badge and hash)
    if not row.descLabel then
        row.descLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.descLabel:SetPoint("LEFT", row.badgeLabel, "RIGHT", 6, 0)
        row.descLabel:SetPoint("RIGHT", row.hashBtn, "LEFT", -6, 0)
        row.descLabel:SetJustifyH("LEFT")
        row.descLabel:SetWordWrap(false)
    end

    local playerTag = e.p and string.format("|cffffffff%s|r", DesolateLootcouncil:GetDisplayName(e.p)) or ""
    local listTag   = e.l and string.format(" |cff888888(%s)|r", e.l) or ""
    local detTag    = e.det and string.format(" - %s", e.det) or ""
    local actorTag  = e.by and string.format(" |cff555555[by %s]|r", DesolateLootcouncil:GetDisplayName(e.by)) or ""

    row.descLabel:SetText(string.format("%s%s%s%s", playerTag, listTag, detTag, actorTag))
    row.descLabel:Show()
end

local function GetSessionDropdownItems()
    local items = {
        ALL = L["All Sessions"]
    }
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if db and db.AttendanceHistory then
        for i, sess in ipairs(db.AttendanceHistory) do
            local sID = sess.sessionID and tostring(sess.sessionID)
            if sID then
                local dateShort = sess.date and sess.date:sub(1, 10) or string.format("Session #%d", i)
                local zoneShort = sess.zone and string.format(" (%s)", sess.zone:sub(1, 12)) or ""
                items[sID] = string.format("%s%s", dateShort, zoneShort)
            end
        end
    end
    if db and db.DecayConfig and db.DecayConfig.sessionActive and db.DecayConfig.currentSessionID then
        local curID = tostring(db.DecayConfig.currentSessionID)
        items[curID] = L["Current Session"]
    end
    return items
end

--- Refreshes the active rows in the Ledger window based on active filters and search query.
function UI_PriorityLogHistory:RefreshView()
    if not self.logFrame or not self.logFrame:IsShown() then return end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    NativeGUI:ResetRowPool(self.rowPool)

    if self.sessionDropdown and self.sessionDropdown.SetList then
        local sessionItems = GetSessionDropdownItems()
        self.sessionDropdown:SetList(sessionItems)
        if self.currentSessionID and not sessionItems[self.currentSessionID] then
            self.currentSessionID = nil
            self.sessionDropdown:SetValue("ALL")
        end
    end

    local API = DesolateLootcouncil.API
    local allEntries = API and API.GetAuditLog and API:GetAuditLog(self.currentSessionID) or {}

    local categoryFilter = self.selectedCategory or "ALL"
    local categoryDef = ACTION_CATEGORIES[categoryFilter] or ACTION_CATEGORIES.ALL
    local query = self.searchQuery and string.lower(self.searchQuery) or ""

    local filteredEntries = {}
    for i = #allEntries, 1, -1 do
        local e = allEntries[i]
        if categoryDef.match(e.act) then
            local matchesQuery = true
            if query ~= "" then
                local pStr = e.p and string.lower(e.p) or ""
                local detStr = e.det and string.lower(e.det) or ""
                local lStr = e.l and string.lower(e.l) or ""
                local byStr = e.by and string.lower(e.by) or ""
                local actStr = e.act and string.lower(e.act) or ""
                matchesQuery = (pStr:find(query, 1, true) ~= nil)
                    or (detStr:find(query, 1, true) ~= nil)
                    or (lStr:find(query, 1, true) ~= nil)
                    or (byStr:find(query, 1, true) ~= nil)
                    or (actStr:find(query, 1, true) ~= nil)
            end
            if matchesQuery then
                table.insert(filteredEntries, e)
            end
        end
    end

    local count = 0
    local topOffset = 0
    local rowHeight = 24

    for _, entry in ipairs(filteredEntries) do
        count = count + 1
        local row = NativeGUI:AcquireRow(self.rowPool, count, self.scrollContent, false)
        RenderAuditRow(self, entry, row, topOffset, rowHeight, NativeGUI)
        topOffset = topOffset + rowHeight + 2
    end

    self.scrollContent:SetHeight(math.max(topOffset + 20, 60))

    if count == 0 then
        if not self.emptyLabel then
            self.emptyLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            self.emptyLabel:SetPoint("CENTER", self.scrollFrame, "CENTER", 0, 0)
        end
        self.emptyLabel:SetText(L["No history logs found."])
        self.emptyLabel:Show()
    else
        if self.emptyLabel then self.emptyLabel:Hide() end
    end
end

--- Displays the Audit and Priority Ledger with optional session filtering.
---@param sessionID number|string|nil Optional session ID to filter events for a specific raid night
function UI_PriorityLogHistory:ShowLogWindow(sessionID)
    if not DesolateLootcouncil:AmIOfficerOrLM() then
        if self.logFrame then self.logFrame:Hide() end
        return
    end

    self.currentSessionID = sessionID and tostring(sessionID) or nil
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    local titleText = sessionID 
        and string.format("%s (Session: %s)", L["Audit & Priority Ledger"], tostring(sessionID))
        or L["Audit & Priority Ledger"]

    if not self.logFrame then
        local frame = NativeGUI:CreateWindow("DLCPriorityHistoryFrame", titleText, "PriorityHistory")
        frame:SetSize(800, 520)
        self.logFrame = frame
        self.rowPool = {}

        -- Top Control Bar
        local controlBar = CreateFrame("Frame", nil, frame)
        controlBar:SetHeight(32)
        controlBar:SetPoint("TOPLEFT", 12, -42)
        controlBar:SetPoint("TOPRIGHT", -12, -42)
        self.controlBar = controlBar

        -- 1. Category Filter Dropdown
        local categoryItems = {
            ALL     = L["All Events"],
            AWARDS  = L["Loot Awards"],
            MANUAL  = L["Priority Shifts"],
            DECAY   = L["Decay Penalties"],
            ROSTER  = L["Roster Changes"],
            SESSION = L["Raid Sessions"],
            CATALOG = L["Catalog Changes"]
        }
        local catContainer, _ = NativeGUI:CreateDropdown(
            controlBar,
            "",
            135,
            categoryItems,
            "ALL",
            function(key)
                self.selectedCategory = key
                self:RefreshView()
            end
        )
        catContainer:SetPoint("LEFT", controlBar, "LEFT", 0, 7)
        self.categoryDropdown = catContainer

        -- 2. Session Filter Dropdown
        local sessionItems = GetSessionDropdownItems()
        local sessContainer, _ = NativeGUI:CreateDropdown(
            controlBar,
            "",
            145,
            sessionItems,
            self.currentSessionID or "ALL",
            function(key)
                self.currentSessionID = (key == "ALL" and nil) or key
                self:RefreshView()
            end
        )
        sessContainer:SetPoint("LEFT", catContainer, "RIGHT", 6, 0)
        self.sessionDropdown = sessContainer

        -- 3. Search Box
        local searchContainer = CreateFrame("Frame", nil, controlBar, "BackdropTemplate")
        searchContainer:SetSize(170, 26)
        searchContainer:SetPoint("LEFT", sessContainer, "RIGHT", 8, -7)
        local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
        searchContainer:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1
        })
        searchContainer:SetBackdropColor(unpack(theme.bg))
        searchContainer:SetBackdropBorderColor(unpack(theme.border))

        local searchEdit = CreateFrame("EditBox", nil, searchContainer)
        searchEdit:SetPoint("TOPLEFT", 6, -2)
        searchEdit:SetPoint("BOTTOMRIGHT", -6, 2)
        searchEdit:SetAutoFocus(false)
        searchEdit:SetFontObject("GameFontHighlightSmall")
        searchEdit:SetScript("OnEscapePressed", function(edit)
            edit:SetText("")
            edit:ClearFocus()
            self.searchQuery = ""
            self:RefreshView()
        end)
        searchEdit:SetScript("OnTextChanged", function(edit)
            self.searchQuery = edit:GetText() or ""
            self:RefreshView()
        end)
        self.searchEdit = searchEdit

        local searchPlaceholder = searchContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        searchPlaceholder:SetPoint("LEFT", 8, 0)
        searchPlaceholder:SetText(L["Search:"])
        searchEdit:SetScript("OnEditFocusGained", function() searchPlaceholder:Hide() end)
        searchEdit:SetScript("OnEditFocusLost", function()
            if not self.searchQuery or self.searchQuery == "" then
                searchPlaceholder:Show()
            end
        end)

        -- 4. Copy Ledger Export Button
        local copyBtn = NativeGUI:CreateButton(controlBar, L["Copy Audit Ledger"], 140, 26, "Bid")
        copyBtn:SetPoint("RIGHT", controlBar, "RIGHT", 0, -7)
        copyBtn:SetScript("OnClick", function()
            local API = DesolateLootcouncil.API
            local fullText = API and API.ExportAuditLog and API:ExportAuditLog(self.currentSessionID) or ""
            if fullText and fullText ~= "" then
                self:ShowCopyWindow(fullText)
            end
        end)
        self.copyBtn = copyBtn

        -- ScrollFrame
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(frame, -80, -14)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    if self.logFrame.title then
        self.logFrame.title:SetText(titleText)
    end

    self.logFrame:Show()
    self.scrollFrame:Show()
    self.scrollContent:Show()

    self:RefreshView()
end

--- Displays a multiline copy window with selectable text for external tools and ledger export.
---@param text string
function UI_PriorityLogHistory:ShowCopyWindow(text)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.exportFrame then
        local frame = NativeGUI:CreateWindow("DLCPriorityHistoryExportFrame", L["Audit & Priority Ledger"], "PriorityHistoryExport")
        self.exportFrame = frame
        frame:SetSize(720, 480)

        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
        desc:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -36)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetText(L["Press Ctrl+C to copy the audit ledger export below."])
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
            self.exportFrame:Hide()
        end)
    end

    self.exportEditBox:SetText(text or "")
    self.exportEditBox:HighlightText()
    self.exportEditBox:SetFocus()

    self.exportScrollContent:SetHeight(math.max(self.exportEditBox:GetHeight() + 20, 100))
    self.exportFrame:Show()
    self.exportFrame:Raise()
end

function UI_PriorityLogHistory:OnEnable()
    self:RegisterMessage("DLC_HISTORY_UPDATED", function()
        self:RefreshView()
    end)
end

-- Backward compatibility alias
UI_PriorityLogHistory.ShowLogHistoryWindow = UI_PriorityLogHistory.ShowLogWindow

