local _, AT = ...
if AT.abortLoad then return end

---@class UI_PriorityOverride : AceModule
---@field priorityOverrideFrame Frame
---@field priorityOverrideContent Frame
local UI_PriorityOverride = DesolateLootcouncil:NewModule("UI_PriorityOverride")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function UI_PriorityOverride:ShowPriorityOverrideWindow(listKey)
    if self.priorityOverrideFrame then
        self.priorityOverrideFrame:Hide()
    end

    local list = DesolateLootcouncil.API:GetPriorityList(listKey)
    if not list then return end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()

    -- Create Midnight-styled native window
    local frame = NativeGUI:CreateWindow(
        "DLCPriorityOverride",
        string.format(L["Override: %s"], (list.name or listKey)),
        320, 500,
        "PriorityOverride"
    )
    frame:SetPoint("CENTER")

    -- Drag-and-drop priority list scroll area
    local scrollFrame = CreateFrame("ScrollFrame", "DLCPriorityScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)

    -- Style scrollbar
    NativeGUI:StyleScrollBar(scrollFrame)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() or 260)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    -- Sync content width on resize
    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(w)
    end)

    self.priorityOverrideFrame = frame
    self.priorityOverrideContent = content

    local function RefreshList()
        content:Hide()
        local children = { content:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide(); child:SetParent(nil)
        end

        local currentList = list.players
        if not currentList then currentList = {} end

        local rowHeight = 28

        for i, name in ipairs(currentList) do
            local row = CreateFrame("Button", nil, content, "BackdropTemplate")
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowHeight)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })

            local bgR = theme.bg[1] + 0.04
            local bgG = theme.bg[2] + 0.04
            local bgB = theme.bg[3] + 0.04
            row:SetBackdropColor(bgR, bgG, bgB, 0.9)
            row:SetBackdropBorderColor(
                theme.border[1] * 0.25,
                theme.border[2] * 0.25,
                theme.border[3] * 0.25,
                0.5
            )

            -- Rank number (accent-coloured)
            local rankLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rankLabel:SetPoint("LEFT", 8, 0)
            rankLabel:SetText(string.format("%d.", i))
            rankLabel:SetTextColor(unpack(theme.accent))
            rankLabel:SetWidth(28)
            rankLabel:SetJustifyH("RIGHT")

            -- Player name
            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameLabel:SetPoint("LEFT", rankLabel, "RIGHT", 6, 0)
            nameLabel:SetPoint("RIGHT", -8, 0)
            nameLabel:SetJustifyH("LEFT")
            
            local R = DesolateLootcouncil:GetModule("Roster")
            local class = R and R:GetUnitClass(name)
            nameLabel:SetText(NativeGUI:FormatClassColor(class, DesolateLootcouncil:GetDisplayName(name)))

            -- Drag grip icon (subtle == indicator on the right)
            local grip = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            grip:SetPoint("RIGHT", -8, 0)
            grip:SetText("==")
            grip:SetTextColor(theme.border[1], theme.border[2], theme.border[3], 0.5)

            -- Drag Logic
            row:SetMovable(true)
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function(self)
                self:SetFrameStrata("TOOLTIP")

                local _, cy = GetCursorPosition()
                local scale = self:GetEffectiveScale()
                local _, center = self:GetCenter()
                if center then
                    self.dragOffset = (center * scale) - cy
                else
                    self.dragOffset = 0
                end

                self:StartMoving()
                self.isDragging = true
                -- Highlight with accent while dragging
                self:SetBackdropColor(theme.border[1] * 0.3, theme.border[2] * 0.3, theme.border[3] * 0.3, 0.9)
                self:SetBackdropBorderColor(unpack(theme.border))
            end)

            row:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                self.isDragging = false
                self:SetFrameStrata("HIGH")
                self:ClearAllPoints()

                local _, cursorY = GetCursorPosition()
                local scale = self:GetEffectiveScale()
                local targetCenterRaw = cursorY + (self.dragOffset or 0)
                local targetY = targetCenterRaw / scale

                local contentTop = content:GetTop() or 0
                local relativeY = contentTop - targetY
                local newIndex = math.floor(relativeY / rowHeight) + 1
                newIndex = math.max(1, math.min(newIndex, #currentList))

                if newIndex ~= i then
                    DesolateLootcouncil.API:MovePlayerInPriorityList(listKey, i, newIndex)
                end
                C_Timer.After(0.01, function() RefreshList() end)
            end)

            row:SetScript("OnEnter", function(self)
                if not self.isDragging then
                    self:SetBackdropColor(unpack(theme.buttonHover))
                    self:SetBackdropBorderColor(theme.border[1] * 0.6, theme.border[2] * 0.6, theme.border[3] * 0.6, 0.8)
                    grip:SetTextColor(unpack(theme.border))
                end
            end)
            row:SetScript("OnLeave", function(self)
                if not self.isDragging then
                    self:SetBackdropColor(bgR, bgG, bgB, 0.9)
                    self:SetBackdropBorderColor(
                        theme.border[1] * 0.25,
                        theme.border[2] * 0.25,
                        theme.border[3] * 0.25,
                        0.5
                    )
                    grip:SetTextColor(theme.border[1], theme.border[2], theme.border[3], 0.5)
                end
            end)
        end

        content:SetHeight(#currentList * rowHeight + 10)
        content:Show()
    end

    RefreshList()
    frame:Show()
end
