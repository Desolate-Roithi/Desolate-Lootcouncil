local _, AT = ...
if AT.abortLoad then return end

---@class UI_Settings : AceModule
local UI_Settings = DesolateLootcouncil:NewModule("UI_Settings")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

StaticPopupDialogs["DLC_SETTINGS_CONFIRM"] = {
    text = "",
    button1 = "Yes",
    button2 = "No",
    OnAccept = nil,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function UI_Settings:ShowSettingsWindow()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.settingsFrame then
        local frame = NativeGUI:CreateWindow("DLCSettingsFrame", L["Desolate Loot Council Settings"], "Config")
        self.settingsFrame = frame

        -- Left Sidebar tab container
        local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        sidebar:SetWidth(150)
        sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -45)
        sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
        sidebar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
        sidebar:SetBackdropColor(theme.bg[1] * 0.6, theme.bg[2] * 0.6, theme.bg[3] * 0.6, 0.5)
        sidebar:SetBackdropBorderColor(theme.border[1] * 0.4, theme.border[2] * 0.4, theme.border[3] * 0.4, 0.5)
        self.sidebar = sidebar

        -- Right scroll area
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(frame, -45, -12)
        scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, 0)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 12)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent

        self.tabButtons = {}
    end

    self.settingsFrame:Show()
    self:RenderTabs()
end

function UI_Settings:RenderTabs()
    local options = DesolateLootcouncil.SettingsLoader.GetOptions()
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()

    -- Clean up old tab buttons
    for _, btn in ipairs(self.tabButtons) do btn:Hide() end
    wipe(self.tabButtons)

    local sortedTabs = {}
    for key, data in pairs(options.args) do
        local isAdminTab = (key == "roster" or key == "priority" or key == "attendance" or key == "items")
        if not isAdminTab or DesolateLootcouncil:AmIRaidAssistOrLM() then
            table.insert(sortedTabs, { key = key, data = data, order = data.order or 99 })
        end
    end
    table.sort(sortedTabs, function(a, b) return a.order < b.order end)

    local activeTabExists = false
    for _, tab in ipairs(sortedTabs) do
        if tab.key == self.activeTab then
            activeTabExists = true
            break
        end
    end
    if (not self.activeTab or not activeTabExists) and #sortedTabs > 0 then
        self.activeTab = sortedTabs[1].key
    end

    local tabHeight = 28
    for idx, tabInfo in ipairs(sortedTabs) do
        local btn = CreateFrame("Button", nil, self.sidebar, "BackdropTemplate")
        btn:SetSize(138, tabHeight)
        btn:SetPoint("TOPLEFT", self.sidebar, "TOPLEFT", 6, -(idx - 1) * (tabHeight + 4) - 6)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 10, 0)
        fs:SetText(tabInfo.data.name or tabInfo.key)
        btn:SetFontString(fs)

        local isCurrent = (self.activeTab == tabInfo.key)
        if isCurrent then
            btn:SetBackdropColor(theme.bg[1] + 0.1, theme.bg[2] + 0.1, theme.bg[3] + 0.1, 0.95)
            btn:SetBackdropBorderColor(unpack(theme.border))
            fs:SetTextColor(theme.textHeader[1], theme.textHeader[2], theme.textHeader[3])
        else
            btn:SetBackdropColor(0, 0, 0, 0)
            btn:SetBackdropBorderColor(0, 0, 0, 0)
            fs:SetTextColor(0.8, 0.8, 0.8, 0.8)
        end

        btn:SetScript("OnEnter", function()
            if self.activeTab ~= tabInfo.key then
                btn:SetBackdropColor(unpack(theme.buttonHover))
                btn:SetBackdropBorderColor(theme.border[1] * 0.5, theme.border[2] * 0.5, theme.border[3] * 0.5, 0.5)
            end
        end)
        btn:SetScript("OnLeave", function()
            if self.activeTab ~= tabInfo.key then
                btn:SetBackdropColor(0, 0, 0, 0)
                btn:SetBackdropBorderColor(0, 0, 0, 0)
            end
        end)

        btn:SetScript("OnClick", function()
            self.activeTab = tabInfo.key
            self:RenderTabs()
        end)

        table.insert(self.tabButtons, btn)
        btn:Show()
    end

    self:RenderActiveSettings(options.args[self.activeTab])
end

function UI_Settings:RenderActiveSettings(tabData)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()

    -- Clean old widgets
    local kids = { self.scrollContent:GetChildren() }
    for _, kid in ipairs(kids) do
        kid:Hide()
        kid:ClearAllPoints()
    end

    if not tabData then return end

    -- Dynamic content width: fill the scroll panel properly
    local contentW = math.max(self.scrollContent:GetWidth() or 430, 200)
    local colPad = 4    -- left margin
    local colGap = 8    -- gap between columns
    -- Available inner width after left pad and right margin
    local innerW = contentW - colPad - 12
    -- Column widths for the 3-column grid
    local colW1 = math.floor((innerW - 2 * colGap) / 3)     -- 1 span
    local colW2 = math.floor((innerW - colGap) * 2 / 3 + colGap / 3) -- 2 span
    local colW3 = innerW                                     -- full width

    local sortedArgs = {}
    local function FlattenArgs(args, targetList, path)
        local sorted = {}
        for key, data in pairs(args) do
            table.insert(sorted, { key = key, data = data, order = data.order or 99 })
        end
        table.sort(sorted, function(a, b) return a.order < b.order end)

        for _, item in ipairs(sorted) do
            local currentPath = {}
            if path then
                for _, p in ipairs(path) do table.insert(currentPath, p) end
            end
            table.insert(currentPath, item.key)

            local d = item.data

            local isHidden = false
            if type(d.hidden) == "function" then
                isHidden = d.hidden()
            elseif type(d.hidden) == "boolean" then
                isHidden = d.hidden
            end

            if not isHidden then
                if d.type == "group" then
                    -- Inline group header
                    table.insert(targetList, {
                        type = "group_header",
                        key = item.key,
                        name = d.name or "",
                        order = d.order or 99,
                        path = currentPath,
                        data = d,
                    })
                    -- Flatten nested args
                    if d.args then
                        FlattenArgs(d.args, targetList, currentPath)
                    end
                else
                    table.insert(targetList, {
                        type = d.type,
                        key = item.key,
                        data = d,
                        order = d.order or 99,
                        path = currentPath,
                    })
                end
            end
        end
    end

    if tabData.args then
        FlattenArgs(tabData.args, sortedArgs)
    end

    local rows = {}
    local currentRow = nil
    local currentSpan = 0

    for _, argInfo in ipairs(sortedArgs) do
        local d = argInfo.data

        local isColumn = false
        if d.width ~= "full" and (d.type == "toggle" or d.type == "select" or d.type == "range" or d.type == "input" or d.type == "execute") then
            isColumn = true
        end

        local colSpan = 3
        if isColumn then
            if d.width == "double" then
                colSpan = 2
            elseif d.width == "half" or d.width == "normal" or not d.width then
                colSpan = 1
            end
        end

        if colSpan == 3 and not (d.type == "toggle" or d.type == "select" or d.type == "range" or d.type == "input" or d.type == "execute") then
            currentRow = nil
            currentSpan = 0
            table.insert(rows, { type = "full", data = argInfo })
        else
            if not currentRow or currentSpan + colSpan > 3 then
                currentRow = { type = "columns", items = {} }
                table.insert(rows, currentRow)
                currentSpan = 0
            end
            table.insert(currentRow.items, { arg = argInfo, span = colSpan })
            currentSpan = currentSpan + colSpan
        end
    end

    local topOffset = 0

    for _, row in ipairs(rows) do
        if row.type == "full" then
            local argInfo = row.data
            local d = argInfo.data
            local info = argInfo.path

            if argInfo.type == "group_header" then
                -- Section Sub-Header Strip
                local headerFrame = CreateFrame("Frame", nil, self.scrollContent, "BackdropTemplate")
                headerFrame:SetHeight(24)
                headerFrame:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
                headerFrame:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)
                headerFrame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                })
                headerFrame:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.4)

                local title = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                title:SetPoint("LEFT", 8, 0)
                title:SetText(argInfo.name or "")
                title:SetTextColor(unpack(theme.textHeader))

                topOffset = topOffset + 30

            elseif d.type == "header" then
                -- Section Header Strip
                local headerFrame = CreateFrame("Frame", nil, self.scrollContent, "BackdropTemplate")
                headerFrame:SetHeight(24)
                headerFrame:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
                headerFrame:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)
                headerFrame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                })
                headerFrame:SetBackdropColor(theme.bg[1] + 0.05, theme.bg[2] + 0.05, theme.bg[3] + 0.05, 0.9)

                local title = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                title:SetPoint("LEFT", 8, 0)
                title:SetText(d.name or "")
                title:SetTextColor(unpack(theme.textHeader))

                topOffset = topOffset + 30

            elseif d.type == "description" then
                -- Simple Text block
                local container = CreateFrame("Frame", nil, self.scrollContent)
                container:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", colPad, -topOffset)
                container:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

                local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                label:SetAllPoints(container)
                label:SetJustifyH("LEFT")
                
                local textStr = (type(d.name) == "function") and d.name() or (d.name or "")
                label:SetText(textStr)
                
                local textHeight = label:GetStringHeight()
                if textHeight == 0 then textHeight = 12 end
                container:SetHeight(textHeight)
                
                topOffset = topOffset + textHeight + 10

            elseif d.type == "multiselect" then
                -- Multiselect rendered as a 2-column set of checkboxes side-by-side
                local values = (type(d.values) == "function") and d.values(info) or d.values or {}
                
                local container = CreateFrame("Frame", nil, self.scrollContent)
                container:SetSize(innerW, 18)
                container:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", colPad, -topOffset)

                local multiselectLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                multiselectLabel:SetAllPoints(container)
                multiselectLabel:SetJustifyH("LEFT")
                multiselectLabel:SetText(d.name or "")
                
                topOffset = topOffset + 22

                local sortedKeys = {}
                for k in pairs(values) do table.insert(sortedKeys, k) end
                table.sort(sortedKeys)

                local colWidth = math.floor((innerW - colGap) / 2)
                local multiRowHeight = 24
                local currentCol = 0

                for _, valKey in ipairs(sortedKeys) do
                    local valName = values[valKey]
                    local isChecked = d.get and d.get(info, valKey) or false
                    local cb = NativeGUI:CreateCheckBox(self.scrollContent, valName, isChecked, function(checked)
                        if d.set then d.set(info, valKey, checked) end
                    end)

                    local left = currentCol * (colWidth + colGap) + colPad
                    cb:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", left, -topOffset)

                    currentCol = currentCol + 1
                    if currentCol == 2 then
                        currentCol = 0
                        topOffset = topOffset + multiRowHeight
                    end
                end

                if currentCol > 0 then
                    topOffset = topOffset + multiRowHeight
                end
                topOffset = topOffset + 6
            end
        else
            -- Columns row (packs 3 columns / total span 3)
            local rowHasLabel = false
            for _, item in ipairs(row.items) do
                local d = item.arg.data
                if d.type == "input" or d.type == "select" or d.type == "range" then
                    rowHasLabel = true
                    break
                end
            end

            local totalSpan = 0
            for _, item in ipairs(row.items) do
                totalSpan = totalSpan + item.span
            end

            local currentL = colPad
            local currentRowHeight = 0

            for _, item in ipairs(row.items) do
                local argInfo = item.arg
                local key = argInfo.key
                local d = argInfo.data
                local info = argInfo.path

                local itemW
                if item.span == 3 then
                    itemW = colW3
                elseif totalSpan == 2 then
                    -- Two items sharing the full row: each gets half
                    itemW = math.floor((innerW - colGap) / 2)
                elseif totalSpan == 1 then
                    -- Single item: give it double-column width (50% wider than 1-col)
                    itemW = colW2
                else
                    if item.span == 2 then
                        itemW = colW2
                    else
                        itemW = colW1
                    end
                end

                local itemL = currentL
                currentL = currentL + itemW + colGap

                local offsetY = 0
                if rowHasLabel and (d.type == "toggle" or d.type == "execute") then
                    offsetY = 16
                end

                local itemHeight = 0

                if d.type == "toggle" then
                    -- Checkbox
                    local defaultVal = d.get and d.get(info) or false
                    local cb = NativeGUI:CreateCheckBox(self.scrollContent, d.name, defaultVal, function(checked)
                        if d.set then d.set(info, checked) end
                        C_Timer.After(0.05, function() self:RenderTabs() end)
                    end)
                    cb:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", itemL, -topOffset - offsetY)
                    itemHeight = 24 + offsetY

                elseif d.type == "select" then
                    -- Dropdown / Stepper
                    local currentVal = d.get and d.get(info)
                    local values = (type(d.values) == "function") and d.values(info) or d.values or {}

                    if key == "defaultPenalty" or key == "decayPenalty" then
                        local stepper = NativeGUI:CreateStepper(self.scrollContent, d.name, itemW, 0, 3, 1, tonumber(currentVal) or 1, function(val)
                            if d.set then d.set(info, val) end
                        end)
                        stepper:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", itemL, -topOffset)
                        itemHeight = 36
                    else
                        local dropContainer, _ = NativeGUI:CreateDropdown(self.scrollContent, d.name, itemW, values, currentVal, function(itemKey)
                            if d.set then d.set(info, itemKey) end
                            C_Timer.After(0.05, function() self:RenderTabs() end)
                        end)
                        dropContainer:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", itemL, -topOffset)
                        itemHeight = 42
                    end

                elseif d.type == "range" then
                    -- Stepper
                    local minVal = d.min or 0
                    local maxVal = d.max or 3
                    local step = d.step or 1
                    local currentVal = d.get and d.get(info) or minVal
                    local stepper = NativeGUI:CreateStepper(self.scrollContent, d.name, itemW, minVal, maxVal, step, tonumber(currentVal) or minVal, function(val)
                        if d.set then d.set(info, val) end
                    end)
                    stepper:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", itemL, -topOffset)
                    itemHeight = 36

                elseif d.type == "input" then
                    -- Text Box
                    local currentVal = d.get and d.get(info) or ""
                    local container, eb = NativeGUI:CreateEditBox(self.scrollContent, d.name)
                    container:SetWidth(itemW)
                    container:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", itemL, -topOffset)
                    eb:SetText(tostring(currentVal))

                    eb:SetScript("OnEnterPressed", function(selfEdit)
                        selfEdit:ClearFocus()
                        if d.set then d.set(info, selfEdit:GetText()) end
                        C_Timer.After(0.05, function() UI_Settings:RenderTabs() end)
                    end)
                    itemHeight = 42

                elseif d.type == "execute" then
                    -- Button
                    local btn = NativeGUI:CreateButton(self.scrollContent, d.name or "", itemW, 24, "Pass")
                    btn:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", itemL, -topOffset - offsetY)

                    btn:SetScript("OnClick", function()
                        if d.confirm then
                            StaticPopupDialogs["DLC_SETTINGS_CONFIRM"].text = d.confirmText or L["Are you sure you want to perform this action?"]
                            StaticPopupDialogs["DLC_SETTINGS_CONFIRM"].OnAccept = function()
                                if d.func then d.func() end
                                self:RenderTabs()
                            end
                            StaticPopup_Show("DLC_SETTINGS_CONFIRM")
                        else
                            if d.func then d.func() end
                            self:RenderTabs()
                        end
                    end)
                    itemHeight = 24 + offsetY
                end

                if itemHeight > currentRowHeight then
                    currentRowHeight = itemHeight
                end
            end

            topOffset = topOffset + currentRowHeight + 10
        end
    end

    self.scrollContent:SetHeight(topOffset + 20)
end

