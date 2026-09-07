local addonName, AT = ...
if AT.abortLoad then return end

---@class MinimapButton : AceModule
local MinimapButton = DesolateLootcouncil:NewModule("MinimapButton")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local MinimapShapes = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function GetMinimapDB()
    if DesolateLootcouncil.db and DesolateLootcouncil.db.profile then
        if not DesolateLootcouncil.db.profile.minimap then
            DesolateLootcouncil.db.profile.minimap = {
                hide = false,
                minimapPos = 220,
            }
        end
        return DesolateLootcouncil.db.profile.minimap
    end
    return nil
end

function MinimapButton:GetPositionAngle()
    local db = GetMinimapDB()
    if db and db.minimapPos then
        return db.minimapPos
    end
    return 220
end

function MinimapButton:SetPositionAngle(angle)
    local db = GetMinimapDB()
    if db then
        db.minimapPos = angle
    end
end

function MinimapButton:IsHidden()
    local db = GetMinimapDB()
    if db and db.hide ~= nil then
        return db.hide
    end
    return false
end

function MinimapButton:SetHidden(hide)
    local db = GetMinimapDB()
    if db then
        db.hide = not not hide
    end
    self:UpdateVisibility()
end

function MinimapButton:UpdatePosition()
    if not self.button or not Minimap then return end

    local angle = math.rad(self:GetPositionAngle())
    local cosAngle = math.cos(angle)
    local sinAngle = math.sin(angle)
    local quadrant = 1
    if cosAngle < 0 then quadrant = quadrant + 1 end
    if sinAngle > 0 then quadrant = quadrant + 2 end

    local shape = "ROUND"
    if type(GetMinimapShape) == "function" then
        local ok, s = pcall(GetMinimapShape)
        if ok and s then
            shape = s
        end
    end

    local quadTable = MinimapShapes[shape] or MinimapShapes["ROUND"]
    local radiusOffset = 10
    local width = (Minimap:GetWidth() / 2) + radiusOffset
    local height = (Minimap:GetHeight() / 2) + radiusOffset

    local posX
    local posY
    if quadTable[quadrant] then
        posX = cosAngle * width
        posY = sinAngle * height
    else
        local diagRadiusW = math.sqrt(2 * (width ^ 2)) - 10
        local diagRadiusH = math.sqrt(2 * (height ^ 2)) - 10
        posX = math.max(-width, math.min(cosAngle * diagRadiusW, width))
        posY = math.max(-height, math.min(sinAngle * diagRadiusH, height))
    end

    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", posX, posY)
end

function MinimapButton:UpdateVisibility()
    if not self.button then return end
    if self:IsHidden() then
        self.button:Hide()
    else
        self.button:Show()
    end
end

local function OnButtonClick(buttonFrame, mouseButton)
    if buttonFrame.wasDragging then
        buttonFrame.wasDragging = false
        return
    end

    if mouseButton == "RightButton" then
        DesolateLootcouncil:OpenConfig()
    elseif mouseButton == "LeftButton" then
        local SlashCommands = DesolateLootcouncil.SlashCommands
        if SlashCommands and SlashCommands.Handle then
            SlashCommands.Handle("vote")
            if DesolateLootcouncil:AmIOfficerOrLM() then
                SlashCommands.Handle("monitor")
            end
        else
            local UI = DesolateLootcouncil:GetModule("UI", true)
            if UI then
                if UI.ShowVotingWindow then
                    local API = DesolateLootcouncil.API
                    local items = API and API:GetBiddingList()
                    if items and #items > 0 then
                        UI:ShowVotingWindow(items)
                    else
                        UI:ShowVotingWindow()
                    end
                end
                if DesolateLootcouncil:AmIOfficerOrLM() and UI.ShowMonitorWindow then
                    UI:ShowMonitorWindow()
                end
            end
        end
    end
end

local function OnButtonEnter(buttonFrame)
    if buttonFrame.isDragging then return end

    GameTooltip:SetOwner(buttonFrame, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(L["Desolate Loot Council"], 0.6, 0.2, 1.0)

    local isOfficerOrLM = DesolateLootcouncil:AmIOfficerOrLM()
    if isOfficerOrLM then
        GameTooltip:AddLine(L["|cffffd700Left-Click:|r Open Voting & Monitor"], 1, 1, 1)
    else
        GameTooltip:AddLine(L["|cffffd700Left-Click:|r Open Voting Window"], 1, 1, 1)
    end
    GameTooltip:AddLine(L["|cffffd700Right-Click:|r Open Settings"], 1, 1, 1)
    GameTooltip:AddLine(L["|cff888888Drag to move|r"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function OnButtonLeave(buttonFrame)
    GameTooltip:Hide()
end

local function OnButtonDragUpdate(buttonFrame)
    if not Minimap then return end
    local minimapX, minimapY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local angle = math.deg(math.atan2(cursorY - minimapY, cursorX - minimapX))
    if angle < 0 then
        angle = angle + 360
    end
    MinimapButton:SetPositionAngle(angle)
    MinimapButton:UpdatePosition()
end

local function OnButtonDragStart(buttonFrame)
    buttonFrame:LockHighlight()
    buttonFrame.isDragging = true
    buttonFrame.wasDragging = true
    buttonFrame:SetScript("OnUpdate", OnButtonDragUpdate)
    GameTooltip:Hide()
end

local function OnButtonDragStop(buttonFrame)
    buttonFrame:UnlockHighlight()
    buttonFrame.isDragging = false
    buttonFrame:SetScript("OnUpdate", nil)
    C_Timer.After(0.05, function()
        buttonFrame.wasDragging = false
    end)
end

function MinimapButton:Initialize()
    if self.button then
        self:UpdatePosition()
        self:UpdateVisibility()
        return
    end

    if not Minimap then return end

    local btn = CreateFrame("Button", "DesolateLootcouncilMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFixedFrameStrata(true)
    btn:SetFixedFrameLevel(true)
    btn:SetFrameLevel(8)

    local background = btn:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
    background:SetPoint("TOPLEFT", 7, -5)
    btn.background = background

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    local iconPath = "Interface\\AddOns\\" .. addonName .. "\\Media\\icon.png"
    icon:SetTexture(iconPath)
    icon:SetPoint("TOPLEFT", 7, -6)
    btn.icon = icon

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
    overlay:SetPoint("TOPLEFT", 0, 0)
    btn.overlay = overlay

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
    highlight:SetPoint("TOPLEFT", 0, 0)
    highlight:SetSize(31, 31)
    btn:SetHighlightTexture(highlight)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnClick", OnButtonClick)
    btn:SetScript("OnEnter", OnButtonEnter)
    btn:SetScript("OnLeave", OnButtonLeave)
    btn:SetScript("OnDragStart", OnButtonDragStart)
    btn:SetScript("OnDragStop", OnButtonDragStop)

    self.button = btn
    self:UpdatePosition()
    self:UpdateVisibility()
end

function MinimapButton:UpdateButtonTooltip()
    if self.button and self.button:IsMouseOver() then
        OnButtonEnter(self.button)
    end
end
