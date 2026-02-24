---@class Persistence
---@field DefaultLayouts table<string, table>
---@field RestoreFramePosition fun(self: Persistence, frame: any, windowName: string)
---@field SaveFramePosition fun(self: Persistence, frame: any, windowName: string)
---@field ApplyCollapseHook fun(self: Persistence, widget: any, windowName?: string)
---@field ToggleWindowCollapse fun(self: Persistence, widget: any)
local Persistence = {}

---@class (partial) PersistenceAddon : AceAddon
---@field db table
---@field DefaultLayouts table<string, table>
---@field Persistence Persistence
---@field Print fun(self: PersistenceAddon, msg: string)
---@field DLC_Log fun(self: PersistenceAddon, msg: string, force?: boolean)

---@type PersistenceAddon
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")

Persistence.DefaultLayouts = {}

function Persistence:SaveFramePosition(frame, windowName)
    local db = DesolateLootcouncil.db.profile
    if not db.positions then db.positions = {} end
    if not frame then return end

    -- Unwrap AceGUI widget if passed accidentally
    local target = frame
    if frame.frame and type(frame.frame) == "table" and frame.frame.GetPoint then
        target = frame.frame
    end

    local h = target:GetHeight()
    -- If collapsed, save the height it was BEFORE collapsing
    if target.isCollapsed and target.savedHeight then
        h = target.savedHeight
    end

    local point, relativeTo, relativePoint, xOfs, yOfs = target:GetPoint()
    local width = target:GetWidth()

    db.positions[windowName] = {
        point = point,
        relativePoint = relativePoint,
        x = xOfs,
        y = yOfs,
        width = width,
        height = h,
        isCollapsed = target.isCollapsed or false
    }
end

function Persistence:RestoreFramePosition(frame, windowName)
    local db = DesolateLootcouncil.db.profile
    if not db.positions then db.positions = {} end

    local saved = db.positions[windowName]
    local default = (DesolateLootcouncil.DefaultLayouts and DesolateLootcouncil.DefaultLayouts[windowName])
        or self.DefaultLayouts[windowName]

    local config = saved or default

    if config then
        -- Unwrap if AceGUI
        local target = frame
        if frame.frame and type(frame.frame) == "table" and frame.frame.GetPoint then
            target = frame.frame
        end

        target:ClearAllPoints()
        target:SetPoint(config.point or "CENTER", UIParent, config.relativePoint or "CENTER", config.x or 0,
            config.y or 0)

        -- Force size application
        if config.width then
            if frame.SetWidth then frame:SetWidth(config.width) end
            target:SetWidth(config.width)
        end
        if config.height then
            if frame.SetHeight then frame:SetHeight(config.height) end
            target:SetHeight(config.height)
        end

        -- Store the collapsed state to apply AFTER the window is fully initialized
        if config.isCollapsed then
            target.startCollapsed = true
        end
    else
        -- Fallback if no default exists
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function Persistence:ToggleWindowCollapse(widget)
    local frame = widget.frame or widget
    if not frame.isCollapsed then
        -- Collapse
        frame.savedHeight = frame:GetHeight()
        frame:SetHeight(30)

        -- Helper to detect if an element is part of the header area
        local function IsInHeader(obj)
            -- Check explicit references first
            if obj == widget.titletext or obj == widget.titlebg or obj == widget.statusIcon or obj.isTitleOverlay then return true end

            -- Check all anchor points
            for i = 1, obj:GetNumPoints() do
                local point, relativeTo, relativePoint, x, y = obj:GetPoint(i)

                -- Keep elements anchored TO our protected parts
                if relativeTo == widget.titletext or relativeTo == widget.titlebg or relativeTo == widget.statusIcon then return true end

                -- Central Header ornaments (anchored to TOP and within title bar height)
                -- We EXCLUDE TOPLEFT/TOPRIGHT to hide side rails
                if relativePoint == "TOP" and (y or 0) > -25 then
                    return true
                end
            end

            return false
        end

        -- 1. Hide the main content container (AceGUI standard)
        if widget.content then
            widget.content:Hide()
            widget.content.tempHidden = true
        end
        if frame.content and frame.content ~= widget.content then
            frame.content:Hide()
            frame.content.tempHidden = true
        end

        -- 2. Handle child frames (Buttons, status icons, etc.)
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if not IsInHeader(child) then
                if child:IsShown() then
                    child:Hide()
                    child.tempHidden = true
                end
            else
                child:Show()
                child.tempHidden = nil
            end
        end

        -- 3. Handle regions (Textures/Borders)
        local regions = { frame:GetRegions() }
        for _, region in ipairs(regions) do
            if not IsInHeader(region) then
                if region:IsShown() then
                    region:Hide()
                    region.tempHidden = true
                end
            else
                region:Show()
                region.tempHidden = nil
            end
        end

        frame.isCollapsed = true
    else
        -- Expand
        frame:SetHeight(frame.savedHeight or 400)

        if widget.content and widget.content.tempHidden then
            widget.content:Show()
            widget.content.tempHidden = nil
        end
        if frame.content and frame.content.tempHidden then
            frame.content:Show()
            frame.content.tempHidden = nil
        end

        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if child.tempHidden then
                child:Show()
                child.tempHidden = nil
            end
        end

        local regions = { frame:GetRegions() }
        for _, region in ipairs(regions) do
            if region.tempHidden then
                region:Show()
                region.tempHidden = nil
            end
        end

        frame.isCollapsed = false
    end
end

function Persistence:ApplyCollapseHook(widget, windowName)
    local frame = widget.frame or widget
    -- Invisible button covering the title bar
    local titleBtn = CreateFrame("Button", nil, frame)
    titleBtn.isTitleOverlay = true
    titleBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0) -- Leave space for Close [X]
    titleBtn:SetHeight(24)
    titleBtn:SetFrameLevel(frame:GetFrameLevel() + 5)        -- Low enough to be behind text but capture clicks
    titleBtn:EnableMouse(true)
    titleBtn:RegisterForClicks("LeftButtonUp")

    frame:SetMovable(true)

    -- 1. Handle Double Click (Collapse)
    titleBtn:SetScript("OnDoubleClick", function()
        self:ToggleWindowCollapse(widget)
        self:SaveFramePosition(frame, windowName or widget.type or "Window")
    end)

    -- 2. Handle Dragging (Passthrough)
    titleBtn:SetScript("OnMouseDown", function()
        if not frame.isCollapsed then frame:StartMoving() end
    end)
    titleBtn:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        self:SaveFramePosition(frame, windowName or widget.type or "Window")
    end)

    -- Apply initial collapsed state if requested
    if frame.startCollapsed then
        C_Timer.After(0.1, function()
            if frame.startCollapsed then
                self:ToggleWindowCollapse(widget)
                frame.startCollapsed = nil
            end
        end)
    end
end

function Persistence:ResetPositions()
    local db = DesolateLootcouncil.db.profile
    db.positions = {}
    DesolateLootcouncil:Print("Window positions reset to defaults. Please reload UI or re-open windows.")
end

DesolateLootcouncil.Persistence = Persistence
