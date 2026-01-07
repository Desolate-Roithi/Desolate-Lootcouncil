---@class UI : AceModule
local UI = DesolateLootcouncil:GetModule("UI")

function UI:ShowPriorityOverrideWindow(listKey)
    if self.priorityOverrideFrame then
        self.priorityOverrideFrame:Hide()
    end

    local db = DesolateLootcouncil.db.profile
    local list = db.PriorityLists[listKey]
    if not list then return end

    local frame = CreateFrame("Frame", "DLCPriorityOverride", UIParent, "BackdropTemplate")
    frame:SetSize(350, 500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Override: " .. listKey)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    local scrollFrame = CreateFrame("ScrollFrame", "DLCPriorityScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(300, 1)
    scrollFrame:SetScrollChild(content)

    self.priorityOverrideFrame = frame
    self.priorityOverrideContent = content

    local function RefreshList()
        content:Hide() -- Hide during update
        local children = { content:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide(); child:SetParent(nil)
        end

        local currentList = db.PriorityLists[listKey]
        local rowHeight = 25

        for i, name in ipairs(currentList) do
            local row = CreateFrame("Button", nil, content, "BackdropTemplate")
            row:SetSize(280, rowHeight)
            row:SetPoint("TOPLEFT", 10, -(i - 1) * rowHeight)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            row:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            row:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetPoint("LEFT", 10, 0)
            text:SetText(string.format("%d. %s", i, name))

            -- Drag Logic
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function(self)
                self:SetFrameStrata("TOOLTIP")
                self:StartMoving()
                self.isDragging = true
                self:SetBackdropColor(0.2, 0.5, 0.8, 0.8)
            end)

            row:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                self.isDragging = false
                self:SetFrameStrata("HIGH")
                self:ClearAllPoints()

                -- Detect new position
                local _, y = self:GetCenter()
                local contentY = content:GetTop()
                local relativeY = contentY - y
                local newIndex = math.floor(relativeY / rowHeight) + 1
                newIndex = math.max(1, math.min(newIndex, #currentList))

                if newIndex ~= i then
                    local player = table.remove(currentList, i)
                    table.insert(currentList, newIndex, player)
                    DesolateLootcouncil:Print(string.format("Moved %s to rank #%d in %s list.", player, newIndex, listKey))
                end

                RefreshList() -- Redraw everything
            end)

            row:SetScript("OnEnter",
                function(self) if not self.isDragging then self:SetBackdropColor(0.3, 0.3, 0.3, 0.8) end end)
            row:SetScript("OnLeave",
                function(self) if not self.isDragging then self:SetBackdropColor(0.1, 0.1, 0.1, 0.5) end end)
        end

        content:SetHeight(#currentList * rowHeight + 10)
        content:Show()
    end

    RefreshList()
    frame:Show()
end
