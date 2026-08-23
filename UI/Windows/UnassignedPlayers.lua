local _, AT = ...
if AT.abortLoad then return end

---@class UI_UnassignedPlayers : AceModule, AceEvent-3.0
local UI_UnassignedPlayers = DesolateLootcouncil:NewModule("UI_UnassignedPlayers", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function UI_UnassignedPlayers:OnInitialize()
    self.rowPool = {}
    self.selectedMains = {}
end

function UI_UnassignedPlayers:OnEnable()
    self:RegisterMessage("DLC_UNASSIGNED_PLAYERS_UPDATED", function()
        if self.frame and self.frame:IsShown() then
            self:RefreshWindow()
        end
    end)
end

function UI_UnassignedPlayers:ShowUnassignedWindow()
    if not DesolateLootcouncil:AmIOfficerOrLM() then
        if self.frame then self.frame:Hide() end
        return
    end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.frame then
        local frame = NativeGUI:CreateWindow(
            "DLCUnassignedPlayersFrame",
            L["Unassigned Players Review"],
            "UnassignedPlayers"
        )
        frame:SetSize(540, 420)
        self.frame = frame

        -- Scroll Container
        local scroll = CreateFrame("ScrollFrame", "DLCUnassignedScroll", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -50)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 45)
        NativeGUI:StyleScrollBar(scroll)

        local content = CreateFrame("Frame", nil, scroll)
        content:SetWidth(scroll:GetWidth() or 468)
        content:SetHeight(1)
        scroll:SetScrollChild(content)

        scroll:SetScript("OnSizeChanged", function(_, w)
            content:SetWidth(w)
        end)

        self.scroll = scroll
        self.content = content

        -- Footer: Add All as Mains button, Dismiss All, and Sync to Lists
        local btnAddAll = NativeGUI:CreateButton(frame, L["Add All as Mains"], 135, 24, "Bid")
        btnAddAll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
        btnAddAll:SetScript("OnClick", function()
            local unassigned = DesolateLootcouncil.API:GetUnassignedPlayers()
            for _, u in ipairs(unassigned) do
                DesolateLootcouncil.API:AssignUnassignedAsMain(u.name)
            end
            self:RefreshWindow()
        end)
        self.btnAddAll = btnAddAll

        local btnDismissAll = NativeGUI:CreateButton(frame, L["Dismiss All"], 95, 24, "Stop")
        btnDismissAll:SetPoint("LEFT", btnAddAll, "RIGHT", 8, 0)
        btnDismissAll:SetScript("OnClick", function()
            local unassigned = DesolateLootcouncil.API:GetUnassignedPlayers()
            for _, u in ipairs(unassigned) do
                DesolateLootcouncil.API:DismissUnassignedPlayer(u.name)
            end
            self:RefreshWindow()
        end)
        self.btnDismissAll = btnDismissAll

        local btnSyncLists = NativeGUI:CreateButton(frame, L["Sync to Lists"], 120, 24, "Pass")
        btnSyncLists:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
        btnSyncLists:SetScript("OnClick", function()
            DesolateLootcouncil.API:SyncMissingPlayers()
            self:RefreshWindow()
        end)
        self.btnSyncLists = btnSyncLists
    end

    self.frame:Show()
    self:RefreshWindow()
end

function UI_UnassignedPlayers:RenderRow(index, uData, mainNames, NativeGUI)
    self.rowPool = self.rowPool or {}
    if not self.rowPool[index] then
        self.rowPool[index] = NativeGUI:CreateRowContainer(self.content, false)
    end
    local row = self.rowPool[index]
    row:Show()

    local rowHeight = 34
    row:SetHeight(rowHeight)
    local topOffset = (index - 1) * (rowHeight + 6)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -topOffset)
    row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -topOffset)

    -- Dismiss Button ("X")
    if not row.btnDismiss then
        local btn = NativeGUI:CreateButton(row, "X", 26, 22, "Stop")
        row.btnDismiss = btn
    end
    row.btnDismiss:ClearAllPoints()
    row.btnDismiss:SetPoint("RIGHT", -6, 0)
    row.btnDismiss:Show()
    row.btnDismiss:SetScript("OnClick", function()
        DesolateLootcouncil.API:DismissUnassignedPlayer(uData.name)
        self:RefreshWindow()
    end)

    -- Link to Main Button
    if not row.btnLinkAlt then
        local btn = NativeGUI:CreateButton(row, L["Link to Main"], 85, 22, "Pass")
        row.btnLinkAlt = btn
    end
    row.btnLinkAlt:SetText(L["Link to Main"])
    row.btnLinkAlt:ClearAllPoints()
    row.btnLinkAlt:SetPoint("RIGHT", row.btnDismiss, "LEFT", -6, 0)
    row.btnLinkAlt:Show()
    row.btnLinkAlt:SetScript("OnClick", function()
        local selectedMain = self.selectedMains[uData.name] or mainNames[1]
        if selectedMain and selectedMain ~= "" then
            DesolateLootcouncil.API:AssignUnassignedAsAlt(uData.name, selectedMain)
            self:RefreshWindow()
        else
            DesolateLootcouncil:Print(L["Please select a Main character first."])
        end
    end)

    -- Target Main Dropdown
    if not row.mainDrop then
        local drop = NativeGUI:CreateDropdown(row, nil, 120, mainNames, 1, function(val)
            self.selectedMains[uData.name] = mainNames[val] or val
        end)
        row.mainDrop = drop
    else
        row.mainDrop:SetList(mainNames)
        local curSel = self.selectedMains[uData.name]
        local foundIdx = 1
        for idx, m in ipairs(mainNames) do
            if m == curSel then foundIdx = idx; break end
        end
        row.mainDrop:SetValue(foundIdx)
    end
    row.mainDrop:ClearAllPoints()
    row.mainDrop:SetPoint("RIGHT", row.btnLinkAlt, "LEFT", -6, 7)
    row.mainDrop:Show()

    -- Add as Main Button
    if not row.btnAddMain then
        local btn = NativeGUI:CreateButton(row, L["Add as Main"], 85, 22, "Bid")
        row.btnAddMain = btn
    end
    row.btnAddMain:SetText(L["Add as Main"])
    row.btnAddMain:ClearAllPoints()
    row.btnAddMain:SetPoint("RIGHT", row.btnLinkAlt, "LEFT", -134, 0)
    row.btnAddMain:Show()
    row.btnAddMain:SetScript("OnClick", function()
        DesolateLootcouncil.API:AssignUnassignedAsMain(uData.name)
        self:RefreshWindow()
    end)

    -- Class Icon
    if not row.classIcon then
        local classIcon = row:CreateTexture(nil, "OVERLAY")
        classIcon:SetSize(16, 16)
        classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        classIcon:SetPoint("LEFT", 8, 0)
        row.classIcon = classIcon
    end
    local class = uData.class or DesolateLootcouncil.API:GetUnitClass(uData.name)
    if _G.CLASS_ICON_TCOORDS then
        local coords = _G.CLASS_ICON_TCOORDS[class]
        if coords then
            row.classIcon:SetTexCoord(unpack(coords))
        else
            row.classIcon:SetTexCoord(0, 1, 0, 1)
        end
    else
        row.classIcon:SetTexCoord(0, 1, 0, 1)
    end
    row.classIcon:Show()

    -- Player Name Label
    if not row.lblName then
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", row.classIcon, "RIGHT", 6, 0)
        lbl:SetJustifyH("LEFT")
        row.lblName = lbl
    end
    row.lblName:SetPoint("RIGHT", row.btnAddMain, "LEFT", -6, 0)
    local displayName = DesolateLootcouncil:GetDisplayName(uData.name)
    local sourceTag = string.format("|cff808080(%s)|r", uData.source or "Raid")
    row.lblName:SetText(NativeGUI:FormatClassColor(class, displayName) .. " " .. sourceTag)
    row.lblName:Show()

    return topOffset + rowHeight + 6
end

function UI_UnassignedPlayers:RefreshWindow()
    if not self.frame or not self.content then return end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local unassigned = DesolateLootcouncil.API:GetUnassignedPlayers()
    local mainListMap = DesolateLootcouncil.API:GetMainRosterList()
    local mainNames = {}
    for name in pairs(mainListMap) do
        table.insert(mainNames, name)
    end
    table.sort(mainNames)

    for _, r in ipairs(self.rowPool or {}) do
        r:Hide()
    end

    if #unassigned == 0 then
        if not self.emptyLabel then
            local lbl = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("CENTER", self.content, "CENTER", 0, -40)
            lbl:SetText(L["No unassigned players found.\nAll detected players are properly mapped."])
            lbl:SetTextColor(0.6, 0.6, 0.6, 1)
            self.emptyLabel = lbl
        end
        self.emptyLabel:Show()
        self.content:SetHeight(120)
        if self.btnAddAll then self.btnAddAll:SetEnabled(false) end
        if self.btnDismissAll then self.btnDismissAll:SetEnabled(false) end
        return
    end

    if self.emptyLabel then self.emptyLabel:Hide() end
    if self.btnAddAll then self.btnAddAll:SetEnabled(true) end
    if self.btnDismissAll then self.btnDismissAll:SetEnabled(true) end

    local totalHeight = 0
    for i, uData in ipairs(unassigned) do
        totalHeight = self:RenderRow(i, uData, mainNames, NativeGUI)
    end

    self.content:SetHeight(math.max(totalHeight + 10, 100))
end
