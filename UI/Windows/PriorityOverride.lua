---@class UI_PriorityOverride : AceModule
local UI_PriorityOverride = DesolateLootcouncil:NewModule("UI_PriorityOverride")

function UI_PriorityOverride:ShowPriorityOverrideWindow(listKey)
    if self.priorityOverrideFrame then
        self.priorityOverrideFrame:Hide()
    end

    local db = DesolateLootcouncil.db.profile
    local list = db.PriorityLists[listKey]
    if not list then return end

    local frame = CreateFrame("Frame", "DLCPriorityOverride", UIParent, "BackdropTemplate")
    frame:SetWidth(350)
    frame:SetHeight(500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    -- Persistence
    DesolateLootcouncil:RestoreFramePosition(frame, "PriorityOverride")
    DesolateLootcouncil.Persistence:ApplyCollapseHook(frame, "PriorityOverride")

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
    title:SetText("Override: " .. (list.name or listKey))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    local scrollFrame = CreateFrame("ScrollFrame", "DLCPriorityScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(300)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    self.priorityOverrideFrame = frame
    self.priorityOverrideContent = content

    local function RefreshList()
        content:Hide() -- Hide during update
        local children = { content:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide(); child:SetParent(nil)
        end

        local currentList = db.PriorityLists[listKey].players
        -- Safety check
        if not currentList then currentList = {} end

        local rowHeight = 25

        for i, name in ipairs(currentList) do
            local row = CreateFrame("Button", nil, content, "BackdropTemplate")
            row:SetWidth(280)
            row:SetHeight(rowHeight)
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
            row:SetMovable(true) -- FIX: Required for StartMoving
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function(self)
                self:SetFrameStrata("TOOLTIP")

                -- Calculate Drag Offset (Where did we grab the row?)
                local cx, cy = GetCursorPosition()
                local scale = self:GetEffectiveScale()
                local _, center = self:GetCenter()
                if center then
                    self.dragOffset = (center * scale) - cy
                else
                    self.dragOffset = 0
                end

                self:StartMoving()
                self.isDragging = true
                self:SetBackdropColor(0.2, 0.5, 0.8, 0.8)
            end)

            row:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                self.isDragging = false
                self:SetFrameStrata("HIGH")
                self:ClearAllPoints()

                -- Use Cursor Position + Offset for reliable "Center" target
                local cursorX, cursorY = GetCursorPosition()
                local scale = self:GetEffectiveScale()

                -- Apply offset to get back to the visual center of the row (in raw pixels)
                -- dragOffset was calculated as (center * scale) - cursorY
                local targetCenterRaw = cursorY + (self.dragOffset or 0)

                -- Convert back to UI coordinates
                local targetY = targetCenterRaw / scale

                local contentTop = content:GetTop() or 0
                -- Distance from the top of the list to the row center
                local relativeY = contentTop - targetY

                -- Calculate index: Each row is 'rowHeight' pixels.
                -- +1 because Lua is 1-indexed (0-25px = Index 1)
                -- We use implicit rounding by math.floor for the bucket
                local newIndex = math.floor(relativeY / rowHeight) + 1

                -- Clamp to valid range
                newIndex = math.max(1, math.min(newIndex, #currentList))

                if newIndex ~= i then
                    local player = table.remove(currentList, i)
                    table.insert(currentList, newIndex, player)

                    local msg = string.format("Manual Override: Moved %s from %d to %d in %s.", player, i, newIndex,
                        list.name or listKey)
                    local Priority = DesolateLootcouncil:GetModule("Priority")
                    if Priority then Priority:LogPriorityChange(msg) end

                    -- Defer refresh to prevent event collisions or double-processing
                    C_Timer.After(0.01, function() RefreshList() end)
                else
                    -- Just snap back visually if no change, no full refresh needed but safer
                    C_Timer.After(0.01, function() RefreshList() end)
                end
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
