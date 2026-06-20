local _, AT = ...
if AT.abortLoad then return end

---@class UI_NativeGUI : AceModule
local UI_NativeGUI = DesolateLootcouncil:NewModule("UI_NativeGUI")

UI_NativeGUI.VOTE_COLORS = {
    [1] = { hex = "|cffff8000", r = 1.0,  g = 0.5,  b = 0.0  },
    [2] = { hex = "|cffa335ee", r = 0.64, g = 0.21, b = 0.93 },
    [3] = { hex = "|cff0070dd", r = 0.0,  g = 0.44, b = 0.87 },
    [4] = { hex = "|cff1eff00", r = 0.12, g = 1.0,  b = 0.0  },
    [5] = { hex = "|cff9d9d9d", r = 0.62, g = 0.62, b = 0.62 },

    Bid     = { hex = "|cffff8000", r = 1.0,  g = 0.5,  b = 0.0  },
    Roll    = { hex = "|cffa335ee", r = 0.64, g = 0.21, b = 0.93 },
    OS      = { hex = "|cff0070dd", r = 0.0,  g = 0.44, b = 0.87 },
    Offspec = { hex = "|cff0070dd", r = 0.0,  g = 0.44, b = 0.87 },
    TM      = { hex = "|cff1eff00", r = 0.12, g = 1.0,  b = 0.0  },
    ["T-Mog"] = { hex = "|cff1eff00", r = 0.12, g = 1.0,  b = 0.0  },
    Pass    = { hex = "|cff9d9d9d", r = 0.62, g = 0.62, b = 0.62 },
}

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")

-- ============================================================================
-- Shared Backdrop Definitions (used by both local helpers and public methods)
-- ============================================================================

local BACKDROP_SIMPLE = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local BACKDROP_TILED = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile     = true,
    tileSize = 16,
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- ============================================================================
-- Local UI Creation Helpers (Extracted to keep core methods extremely short)
-- ============================================================================

local function StyleWindowBackdrop(frame, theme)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(unpack(theme.bg))
    frame:SetBackdropBorderColor(unpack(theme.border))
end

--- Collapse a window down to its title bar height and a compact width.
local function CollapseWindow(frame, windowName)
    frame.isCollapsed = true
    -- Only snapshot current size if it's not already collapsed/corrupted
    local currentW = frame:GetWidth() or 0
    local currentH = frame:GetHeight() or 0
    if currentW > 220 then
        frame._expandedWidth = currentW
    end
    if currentH > 42 then
        frame._expandedHeight = currentH
    end

    -- Fallback to default layout size if expanded size is still invalid/missing
    if not frame._expandedWidth or frame._expandedWidth <= 220 then
        local defaultLayout = DesolateLootcouncil.DefaultLayouts and DesolateLootcouncil.DefaultLayouts[windowName]
        frame._expandedWidth = defaultLayout and defaultLayout.width or 400
    end
    if not frame._expandedHeight or frame._expandedHeight <= 42 then
        local defaultLayout = DesolateLootcouncil.DefaultLayouts and DesolateLootcouncil.DefaultLayouts[windowName]
        frame._expandedHeight = defaultLayout and defaultLayout.height or 300
    end

    -- Snapshot which children were visible so we only restore those on expand
    frame._collapseSnapshot = {}
    for _, child in ipairs({ frame:GetChildren() }) do
        frame._collapseSnapshot[child] = child:IsShown()
        if child ~= frame.titleBar and child ~= frame.closeButton then
            child:Hide()
        end
    end

    -- Shrink to title bar only — narrow so it barely takes any screen space
    frame:SetHeight(42)
    frame:SetWidth(220)
    if frame.grabber then frame.grabber:Hide() end

    -- Rotate arrow texture to point right (collapsed)
    if frame.collapseArrow then
        frame.collapseArrow:SetRotation(-math.pi / 2)
    end

    if windowName then
        DesolateLootcouncil:SaveFramePosition(frame, windowName)
    end

    if frame.OnCollapse then
        pcall(frame.OnCollapse, frame)
    end
end

--- Restore a previously collapsed window to its original size.
local function ExpandWindow(frame, windowName)
    frame.isCollapsed = false

    frame:SetHeight(frame._expandedHeight or 400)
    frame:SetWidth(frame._expandedWidth   or 650)

    -- Only restore children that were actually visible before collapse
    local snap = frame._collapseSnapshot or {}
    for _, child in ipairs({ frame:GetChildren() }) do
        if snap[child] then
            child:Show()
        end
    end
    frame._collapseSnapshot = nil

    if frame.grabber then frame.grabber:Show() end

    -- Rotate arrow texture back to point down (expanded)
    if frame.collapseArrow then
        frame.collapseArrow:SetRotation(0)
    end

    if windowName then
        DesolateLootcouncil:SaveFramePosition(frame, windowName)
    end

    if frame.OnExpand then
        pcall(frame.OnExpand, frame)
    end
end

local function CreateTitleBar(frame, titleText, theme, windowName)
    local titleBar = CreateFrame("Button", nil, frame)
    titleBar:SetHeight(38)
    titleBar:SetPoint("TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", -36, -2)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        DesolateLootcouncil:SaveFramePosition(frame, windowName)
    end)

    -- Collapse / Expand on double-click
    titleBar:SetScript("OnDoubleClick", function()
        if frame.isCollapsed then
            ExpandWindow(frame, windowName)
        else
            CollapseWindow(frame, windowName)
        end
    end)

    -- Hover highlight so the user knows the title bar is clickable
    titleBar:SetScript("OnEnter", function()
        titleBar:SetAlpha(0.85)
    end)
    titleBar:SetScript("OnLeave", function()
        titleBar:SetAlpha(1.0)
    end)

    -- Arrow indicator: texture rotated down (expanded) or right (collapsed)
    -- Must be created BEFORE title so title can anchor its RIGHT edge to it
    local arrow = titleBar:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetAtlas("minimal-scrollbar-arrow-bottom")
    arrow:SetVertexColor(theme.textHeader[1], theme.textHeader[2], theme.textHeader[3], 0.5)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 14, 0)
    -- Clamp to stop before the collapse arrow so text never overflows when collapsed
    title:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText(titleText)
    title:SetTextColor(unpack(theme.textHeader))

    frame.titleBar      = titleBar
    frame.titleText     = title
    frame.collapseArrow = arrow
end

local function CreateCloseButton(frame, theme)
    local close = CreateFrame("Button", nil, frame, "BackdropTemplate")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetBackdrop(BACKDROP_SIMPLE)
    close:SetBackdropColor(theme.bg[1] * 1.5, theme.bg[2] * 1.5, theme.bg[3] * 1.5, 0.8)
    close:SetBackdropBorderColor(unpack(theme.border))

    local xText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xText:SetSize(20, 20)
    xText:SetPoint("CENTER", 0, 0)
    xText:SetJustifyH("CENTER")
    xText:SetJustifyV("MIDDLE")
    xText:SetText("X")
    xText:SetTextColor(1, 1, 1, 0.8)

    close:SetScript("OnClick", function() frame:Hide() end)
    close:SetScript("OnEnter", function()
        xText:SetTextColor(1, 0.3, 0.3, 1)
        close:SetBackdropColor(0.3, 0.1, 0.1, 0.9)
    end)
    close:SetScript("OnLeave", function()
        local activeTheme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
        xText:SetTextColor(1, 1, 1, 0.8)
        close:SetBackdropColor(activeTheme.bg[1] * 1.5, activeTheme.bg[2] * 1.5, activeTheme.bg[3] * 1.5, 0.8)
    end)

    frame.closeButton = close
end

local function CreateResizeGrabber(frame, theme, windowName)
    local grabber = CreateFrame("Button", nil, frame)
    grabber:SetSize(16, 16)
    grabber:SetPoint("BOTTOMRIGHT", -2, 2)
    local grabberTex = grabber:CreateTexture(nil, "OVERLAY")
    grabberTex:SetSize(10, 10)
    grabberTex:SetPoint("BOTTOMRIGHT", -4, 4)
    grabberTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grabberTex:SetVertexColor(theme.border[1], theme.border[2], theme.border[3], 0.8)

    grabber:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grabber:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        DesolateLootcouncil:SaveFramePosition(frame, windowName)
        if frame.OnResizeCallback then
            frame.OnResizeCallback(frame)
        end
    end)

    frame.grabber = grabber
    frame.grabberTex = grabberTex
end

local function StyleScrollThumbAndTrack(scrollBar, theme)
    local thumb = scrollBar:GetThumbTexture()

    for i = 1, scrollBar:GetNumRegions() do
        local r = select(i, scrollBar:GetRegions())
        if r and r:GetObjectType() == "Texture" then
            if r ~= scrollBar.trackBg and r ~= thumb then
                r:SetTexture(nil)
                r:SetAlpha(0)
            end
        end
    end

    if not scrollBar.trackBg then
        local trackBg = scrollBar:CreateTexture(nil, "BACKGROUND")
        trackBg:SetAllPoints(scrollBar)
        scrollBar.trackBg = trackBg
    end
    scrollBar.trackBg:SetColorTexture(theme.bg[1] * 1.2, theme.bg[2] * 1.2, theme.bg[3] * 1.2, 0.7)
    scrollBar.trackBg:SetAlpha(0.7)

    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetColorTexture(unpack(theme.border))
        thumb:SetSize(12, 24)
        thumb:SetAlpha(1.0)
    end
end

local function StyleScrollArrowButton(btn, theme, arrowAtlas)
    if not btn then return end
    btn:ClearAllPoints()
    if btn.GetParent then
        local p = btn:GetParent()
        if p then
            if arrowAtlas == "minimal-scrollbar-arrow-top" then
                btn:SetPoint("BOTTOM", p, "TOP", 0, 2)
            else
                btn:SetPoint("TOP", p, "BOTTOM", 0, -2)
            end
        end
    end
    btn:SetSize(16, 11)

    if btn.SetNormalTexture then btn:SetNormalTexture("") end
    if btn.SetPushedTexture then btn:SetPushedTexture("") end
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end

    for i = 1, btn:GetNumRegions() do
        local r = select(i, btn:GetRegions())
        if r and r:GetObjectType() == "Texture" then
            if r ~= btn.customArrow then
                r:SetTexture(nil)
                r:SetAlpha(0)
            end
        end
    end

    if not btn.customArrow then
        local customArrow = btn:CreateTexture(nil, "OVERLAY")
        customArrow:SetSize(16, 11)
        customArrow:SetPoint("CENTER", 0, 0)
        customArrow:SetAtlas(arrowAtlas)
        btn.customArrow = customArrow
    end
    btn.customArrow:SetVertexColor(unpack(theme.border))
    btn.customArrow:SetAlpha(1.0)

    btn:SetScript("OnEnter", function()
        btn.customArrow:SetVertexColor(theme.border[1] * 1.2, theme.border[2] * 1.2, theme.border[3] * 1.2, 1.0)
    end)
    btn:SetScript("OnLeave", function()
        btn.customArrow:SetVertexColor(unpack(theme.border))
    end)
end

local function StyleDropdownButton(btn, theme)
    btn:SetBackdrop(BACKDROP_SIMPLE)
    btn:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.9)
    btn:SetBackdropBorderColor(unpack(theme.border))
end

local function PopulateDropdownMenu(container, menu, btn, currentList, callback, customSort, theme, itemRows, HideMenu)
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(btn:GetWidth())

    for _, r in ipairs(itemRows) do r:Hide() end

    local keys = {}
    for k in pairs(currentList) do table.insert(keys, k) end
    if customSort then
        table.sort(keys, function(a, b) return customSort(a, b, currentList) end)
    else
        table.sort(keys, function(a, b) return tostring(currentList[a]) < tostring(currentList[b]) end)
    end

    local rowHeight = 20
    local menuHeight = 6
    for idx, key in ipairs(keys) do
        local val = currentList[key]
        if not itemRows[idx] then
            local row = CreateFrame("Button", nil, menu, "BackdropTemplate")
            row:SetHeight(rowHeight)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
            })
            row:SetBackdropColor(0, 0, 0, 0)
            local rText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rText:SetPoint("LEFT", 8, 0)
            rText:SetPoint("RIGHT", -8, 0)
            rText:SetJustifyH("LEFT")
            rText:SetWordWrap(false)
            rText:SetNonSpaceWrap(false)
            row.text = rText

            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(unpack(theme.buttonHover))
            end)
            row:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0, 0, 0, 0)
            end)
            itemRows[idx] = row
        end
        local row = itemRows[idx]
        row:SetWidth(btn:GetWidth() - 4)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(idx - 1) * rowHeight - 3)
        row.text:SetText(tostring(val))
        row:Show()

        row:SetScript("OnClick", function()
            container:SetValue(key)
            HideMenu()
            if callback then callback(key) end
        end)

        menuHeight = menuHeight + rowHeight
    end
    menu:SetHeight(menuHeight)
    menu:Show()
end

-- ============================================================================
-- Core Public API
-- ============================================================================

--- Creates a beautiful, persistent, Midnight-themed native WoW window.
---@param name string  global frame name (can be nil)
---@param titleText string  text displayed in the header
---@param width number  default frame width
---@param height number  default frame height
---@param windowName string  key for position saving
---@return Frame frame
--- Creates a standardized frame with standard title, drag, close, and resize handlers.
--- Can be called with either:
---   1. (name, title, windowName) -> Resolves width and height automatically from UI/Layouts.lua
---   2. (name, title, width, height, windowName) -> Traditional fallback signature
---@param name string  global frame name
---@param titleText string  displayed header text
---@param widthOrWindowName number|string  default frame width or layout key
---@param height number?  default frame height (nil if using layout key)
---@param windowName string?  layout key for persistence (nil if using layout key)
---@return Frame frame
function UI_NativeGUI:CreateWindow(name, titleText, widthOrWindowName, height, windowName)
    local w, h, winName
    if type(widthOrWindowName) == "string" then
        winName = widthOrWindowName
        local defaultLayout = DesolateLootcouncil.DefaultLayouts and DesolateLootcouncil.DefaultLayouts[winName]
        w = defaultLayout and defaultLayout.width or 400
        h = defaultLayout and defaultLayout.height or 300
    else
        w = widthOrWindowName or 400
        h = height or 300
        winName = windowName
    end

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(250, 150)
    else
        frame:SetMinResize(250, 150)
    end
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    StyleWindowBackdrop(frame, theme)
    CreateTitleBar(frame, titleText, theme, winName)
    CreateCloseButton(frame, theme)
    CreateResizeGrabber(frame, theme, winName)

    -- Persistence Integration
    DesolateLootcouncil:RestoreFramePosition(frame, winName)

    frame:HookScript("OnShow", function()
        if frame.startCollapsed then
            C_Timer.After(0.05, function()
                if frame.startCollapsed and not frame.isCollapsed then
                    CollapseWindow(frame, winName)
                end
                frame.startCollapsed = nil
            end)
        end
    end)

    return frame
end

--- Hides and clears anchors for all rows in a pool.
---@param rowPool table
function UI_NativeGUI:ResetRowPool(rowPool)
    if not rowPool then return end
    for _, r in ipairs(rowPool) do
        r:Hide()
        r:ClearAllPoints()
    end
end

--- Fetches a row container from the pool or creates it if needed, showing it.
---@param rowPool table
---@param index number
---@param parent Frame
---@param isActive boolean
---@return Frame row
function UI_NativeGUI:AcquireRow(rowPool, index, parent, isActive)
    if not rowPool[index] then
        rowPool[index] = self:CreateRowContainer(parent, isActive)
    end
    local row = rowPool[index]
    row:Show()
    return row
end

--- Applies the flat single-pixel border backdrop (no tile) to a frame.
--- Eliminates the repeated 4-line SetBackdrop({WHITE8X8, edgeSize=1}) pattern.
---@param frame Frame  frame that inherits BackdropTemplate
function UI_NativeGUI:ApplySimpleBackdrop(frame)
    frame:SetBackdrop(BACKDROP_SIMPLE)
end

--- Applies the tiled single-pixel border backdrop with insets to a frame.
--- Eliminates the repeated 8-line SetBackdrop({tile=true, tileSize=16, insets}) pattern.
---@param frame Frame  frame that inherits BackdropTemplate
function UI_NativeGUI:ApplyTiledBackdrop(frame)
    frame:SetBackdrop(BACKDROP_TILED)
end

--- Applies the row background color (+0.03 tint) and active/inactive border to a row frame.
--- Eliminates the 6-line duplicate block in CreateRowContainer and Voting.lua:CreateItemRow.
---@param row    Frame    frame that already has a tiled backdrop applied
---@param theme  table    active theme table
---@param isActive boolean  true → full neon border, false → 30%-muted border
function UI_NativeGUI:StyleRowBackdrop(row, theme, isActive)
    local bgR = theme.bg[1] + 0.03
    local bgG = theme.bg[2] + 0.03
    local bgB = theme.bg[3] + 0.03
    row:SetBackdropColor(bgR, bgG, bgB, 0.95)
    if isActive then
        row:SetBackdropBorderColor(unpack(theme.border))
    else
        row:SetBackdropBorderColor(
            theme.border[1] * 0.3,
            theme.border[2] * 0.3,
            theme.border[3] * 0.3,
            0.4)
    end
end

--- Creates a standard clickable icon button.
---@param parent Frame
---@param size number?
---@param leftOffset number?
---@return Button icon
function UI_NativeGUI:CreateIcon(parent, size, leftOffset)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size or 24, size or 24)
    btn:SetPoint("LEFT", leftOffset or 8, 0)
    local tex = btn:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    btn.texture = tex
    return btn
end

--- Sets up or creates an item icon button on a row with default tooltips.
---@param row Frame
---@param data table
---@param size number?
---@param offsetX number?
---@param offsetY number?
---@return Button icon
function UI_NativeGUI:SetupItemIconButton(row, data, size, offsetX, offsetY)
    if not row.itemIcon then
        row.itemIcon = self:CreateIcon(row, size, offsetX)
    end
    row.itemIcon:SetSize(size or 24, size or 24)
    row.itemIcon:ClearAllPoints()
    row.itemIcon:SetPoint("LEFT", offsetX or 8, offsetY or 0)

    local texture = data.texture or (data.itemID and C_Item.GetItemIconByID(data.itemID)) or 134400
    row.itemIcon.texture:SetTexture(texture)

    local function ShowTip()
        GameTooltip:SetOwner(row.itemIcon, "ANCHOR_CURSOR")
        if data.link then
            GameTooltip:SetHyperlink(data.link)
        elseif data.itemID then
            GameTooltip:SetItemByID(data.itemID)
        end
        GameTooltip:Show()
    end

    row.itemIcon:SetScript("OnClick", ShowTip)
    row.itemIcon:SetScript("OnEnter", ShowTip)
    row.itemIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row.itemIcon
end

--- Creates a clickable link label button.
---@param parent Frame
---@param font string?
---@return Button linkLabel
function UI_NativeGUI:CreateLinkLabel(parent, font)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(20)
    local txt = btn:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    txt:SetPoint("LEFT", 0, 0)
    txt:SetPoint("RIGHT", 0, 0)
    txt:SetJustifyH("LEFT")
    btn.text = txt
    return btn
end

--- Styles a scrollbar dynamically using the active UI theme, replacing retro gold arrows with modern flat vertex-colored ones.
---@param scrollFrame ScrollFrame
function UI_NativeGUI:StyleScrollBar(scrollFrame)
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    local scrollBarName = scrollFrame:GetName() and (scrollFrame:GetName() .. "ScrollBar") or nil
    if scrollBarName then
        local scrollBar = _G[scrollBarName]
        if scrollBar then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -16)
            scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 16)

            StyleScrollThumbAndTrack(scrollBar, theme)

            local upBtn = scrollBar.ScrollUpButton or _G[scrollBarName .. "ScrollUpButton"]
            StyleScrollArrowButton(upBtn, theme, "minimal-scrollbar-arrow-top")

            local downBtn = scrollBar.ScrollDownButton or _G[scrollBarName .. "ScrollDownButton"]
            StyleScrollArrowButton(downBtn, theme, "minimal-scrollbar-arrow-bottom")
        end
    end
end

function UI_NativeGUI:CreateScrollFrame(parent, topOffset, bottomOffset)
    local frameName = parent:GetName() and (parent:GetName() .. "Scroll") or nil
    local scrollFrame = CreateFrame("ScrollFrame", frameName, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, topOffset)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -36, -bottomOffset)

    -- Hide ugly default scrollbar textures and apply modern styling
    self:StyleScrollBar(scrollFrame)

    -- Scroll child container
    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(scrollFrame:GetWidth() or 200, 1)
    scrollFrame:SetScrollChild(scrollContent)

    -- Intercept SetHeight on scrollContent to automatically trigger UpdateScrollChildRect
    local origSetHeight = scrollContent.SetHeight
    scrollContent.SetHeight = function(self, h)
        if origSetHeight then
            origSetHeight(self, h)
        end
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
    end

    -- Keep scroll content width perfectly synced on parent frame resize
    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        scrollContent:SetWidth(w)
        if self.UpdateScrollChildRect then
            self:UpdateScrollChildRect()
        end
    end)

    return scrollFrame, scrollContent
end

--- Creates a clean, flat button with glowing colored borders and filled hovers based on type.
---@param parent Frame  parent frame
---@param text string  button label text
---@param width number  button width
---@param height number  button height
---@param buttonType string  "Bid", "Roll", "Offspec", "T-Mog", "Pass", "Note", or "Stop"
---@return Button button
function UI_NativeGUI:CreateButton(parent, text, width, height, buttonType)
    if type(text) == "function" then
        text = text()
    end
    text = tostring(text or "")
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)

    local fs = btn:GetFontString() or btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:ClearAllPoints()
    fs:SetPoint("CENTER")
    fs:SetTextColor(1, 1, 1, 0.9)
    btn:SetFontString(fs)
    btn:SetText(text)
    fs:SetText(text)

    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local BUTTON_COLORS = {
        ["Bid"]     = { border = { 1.0, 0.5, 0.0, 1.0 }, hover = { 0.7, 0.35, 0.0, 0.8 } },
        ["Roll"]    = { border = { 0.64, 0.21, 0.93, 1.0 }, hover = { 0.45, 0.15, 0.65, 0.8 } },
        ["Offspec"] = { border = { 0.0, 0.44, 0.87, 1.0 }, hover = { 0.0, 0.3, 0.6, 0.8 } },
        ["T-Mog"]   = { border = { 0.12, 1.0, 0.0, 1.0 }, hover = { 0.08, 0.7, 0.0, 0.8 } },
        ["Pass"]    = { border = { 1.0, 1.0, 1.0, 1.0 }, hover = { 0.7, 0.7, 0.7, 0.8 } },
        ["Note"]    = { border = { 0.6, 0.3, 0.9, 1.0 }, hover = { 0.4, 0.2, 0.6, 0.8 } },
        ["Stop"]    = { border = { 0.8, 0.2, 0.2, 1.0 }, hover = { 0.5, 0.1, 0.1, 0.9 } },
    }

    local activeTheme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    local custom = BUTTON_COLORS[buttonType]
    local borderCol = custom and custom.border or activeTheme.border
    local bgCol = activeTheme.buttonBg
    local hoverCol = custom and custom.hover or activeTheme.buttonHover

    btn.buttonType = buttonType
    btn.themeBg = bgCol
    btn.themeHover = hoverCol
    btn.themeBorder = borderCol

    btn:SetBackdropColor(unpack(bgCol))
    btn:SetBackdropBorderColor(unpack(borderCol))

    btn:SetScript("OnEnter", function(self)
        if self.themeHover then
            self:SetBackdropColor(unpack(self.themeHover))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.themeBg then
            self:SetBackdropColor(unpack(self.themeBg))
        end
    end)

    return btn
end

--- Creates a native Obsidian container panel with optional neon purple active border.
---@param parent Frame  parent scroll child frame
---@param isActive boolean  whether this represents an active/open voting row
---@return Frame rowContainer
function UI_NativeGUI:CreateRowContainer(parent, isActive)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:ApplyTiledBackdrop(row)

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    self:StyleRowBackdrop(row, theme, isActive)

    return row
end

local activeEditBox = nil
local lastActiveEditBox = nil
local lastActiveTime = 0

local function HandleEditBoxInsertLink(text)
    local target = activeEditBox
    local needsFocus = false

    if not target or not target:HasFocus() then
        if lastActiveEditBox and lastActiveEditBox:IsVisible() and (GetTime() - lastActiveTime < 0.2) then
            target = lastActiveEditBox
            needsFocus = true
        end
    end

    if target and target:IsVisible() then
        target:Insert(text)
        if needsFocus then
            target:SetFocus()
        end
        return true
    end
    return false
end

-- Hook HandleModifiedItemClick to ensure Shift-Clicks always insert links into custom inputs.
-- luacheck: globals HandleModifiedItemClick IsModifiedClick
if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if IsModifiedClick("CHATLINK") then
            HandleEditBoxInsertLink(link)
        end
    end)
end

--- Creates a custom native text input EditBox with a styled background and title label.
---@param parent Frame  parent container
---@param labelText string  label displayed above the input field
---@return Frame containerFrame, EditBox editBox
function UI_NativeGUI:CreateEditBox(parent, labelText)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(42)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 2, 0)
    label:SetText(labelText)

    local eb = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    eb:SetPoint("TOPLEFT", 0, -16)
    eb:SetPoint("BOTTOMRIGHT", 0, 2)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetAutoFocus(false)
    eb:SetTextInsets(8, 8, 0, 0)
    eb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    eb:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.9)
    eb:SetBackdropBorderColor(unpack(theme.border))

    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    eb:HookScript("OnEditFocusGained", function(selfEdit)
        activeEditBox = selfEdit
    end)
    eb:HookScript("OnEditFocusLost", function(selfEdit)
        if activeEditBox == selfEdit then
            activeEditBox = nil
        end
        lastActiveEditBox = selfEdit
        lastActiveTime = GetTime()
    end)

    container.editbox = eb
    return container, eb
end

--- Creates a flat, taint-free dropdown button and selection popup frame.
---@param parent Frame  parent frame
---@param labelText string  label shown above dropdown
---@param width number  dropdown button width
---@param list table  key-value table of items
---@param defaultValue any  initial key value
---@param callback fun(key: any)  triggered on value changed
---@return Frame container, Button dropdownBtn
function UI_NativeGUI:CreateDropdown(parent, labelText, width, list, defaultValue, callback, customSort)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 42)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 2, 0)
    label:SetText(labelText or "")

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", 0, -16)
    btn:SetPoint("BOTTOMRIGHT", 0, 2)

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    StyleDropdownButton(btn, theme)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -22, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetNonSpaceWrap(false)

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(14, 8)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetAtlas("dropdown-hover-arrow")
    arrow:SetVertexColor(unpack(theme.border))

    local currentValue = defaultValue
    local currentList = list or {}

    local function GetDisplayValue(val)
        return currentList[val] or tostring(val or "")
    end

    fs:SetText(GetDisplayValue(currentValue))

    -- Floating Menu Frame (escapes layout hierarchy to prevent clipping)
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:Hide()
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(theme.bg[1] * 0.9, theme.bg[2] * 0.9, theme.bg[3] * 0.9, 0.95)
    menu:SetBackdropBorderColor(unpack(theme.border))

    local itemRows = {}

    local function HideMenu()
        menu:Hide()
    end

    local function ToggleMenu()
        if menu:IsShown() then
            HideMenu()
        else
            PopulateDropdownMenu(container, menu, btn, currentList, callback, customSort, theme, itemRows, HideMenu)
        end
    end

    btn:SetScript("OnClick", ToggleMenu)

    -- Auto close helper when clicking outside
    local clickDetector = CreateFrame("Frame", nil, menu)
    clickDetector:SetAllPoints(UIParent)
    clickDetector:SetFrameStrata("BACKGROUND")
    clickDetector:EnableMouse(true)
    clickDetector:SetScript("OnMouseDown", HideMenu)

    container.SetValue = function(_, val)
        currentValue = val
        fs:SetText(GetDisplayValue(val))
    end
    container.SetList = function(_, newList)
        currentList = newList or {}
        fs:SetText(GetDisplayValue(currentValue))
    end
    container.SetSort = function(_, newSort)
        customSort = newSort
    end
    container.GetValue = function()
        return currentValue
    end

    return container, btn
end

--- Creates a clean native checkbox.
---@param parent Frame  parent frame
---@param labelText string  description label on the right
---@param defaultChecked boolean  initial checked state
---@param callback fun(checked: boolean)  triggered on state toggle
---@return CheckButton checkbox
function UI_NativeGUI:CreateCheckBox(parent, labelText, defaultChecked, callback)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(20, 20)
    cb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    cb:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.9)
    cb:SetBackdropBorderColor(unpack(theme.border))

    local checkedTexture = cb:CreateTexture(nil, "OVERLAY")
    checkedTexture:SetSize(12, 12)
    checkedTexture:SetPoint("CENTER")
    checkedTexture:SetColorTexture(theme.border[1], theme.border[2], theme.border[3], 1.0)
    cb.checkedTexture = checkedTexture

    local isChecked = defaultChecked or false
    if isChecked then checkedTexture:Show() else checkedTexture:Hide() end

    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    label:SetText(labelText or "")
    cb.label = label

    cb:SetScript("OnClick", function()
        isChecked = not isChecked
        if isChecked then checkedTexture:Show() else checkedTexture:Hide() end
        if callback then callback(isChecked) end
    end)

    cb.SetChecked = function(_, checked)
        isChecked = checked or false
        if isChecked then checkedTexture:Show() else checkedTexture:Hide() end
    end
    cb.GetChecked = function()
        return isChecked
    end

    return cb
end

--- Creates a modern, tactile stepper widget instead of sliders.
---@param parent Frame  parent frame
---@param labelText string  stepper label title
---@param width number  stepper width
---@param minVal number  minimum bound
---@param maxVal number  maximum bound
---@param step number  increment size
---@param defaultVal number  initial value
---@param callback fun(value: number)  triggered on change
---@return Frame stepperContainer
function UI_NativeGUI:CreateStepper(parent, labelText, width, minVal, maxVal, step, defaultVal, callback)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 36)

    local val = defaultVal or 1

    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", 0, 0)

    local function UpdateText()
        lbl:SetText(string.format("%s: %s", labelText or "", tostring(val)))
    end
    UpdateText()

    local btnMinus = CreateFrame("Button", nil, container, "BackdropTemplate")
    btnMinus:SetSize(20, 20)
    btnMinus:SetPoint("RIGHT", -26, 0)
    btnMinus:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    btnMinus:SetBackdropColor(unpack(theme.buttonBg))
    btnMinus:SetBackdropBorderColor(unpack(theme.border))

    local minusText = btnMinus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    minusText:SetPoint("CENTER")
    minusText:SetText("-")
    minusText:SetTextColor(1, 1, 1, 0.9)

    local btnPlus = CreateFrame("Button", nil, container, "BackdropTemplate")
    btnPlus:SetSize(20, 20)
    btnPlus:SetPoint("RIGHT", 0, 0)
    btnPlus:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btnPlus:SetBackdropColor(unpack(theme.buttonBg))
    btnPlus:SetBackdropBorderColor(unpack(theme.border))

    local plusText = btnPlus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    plusText:SetPoint("CENTER")
    plusText:SetText("+")
    plusText:SetTextColor(1, 1, 1, 0.9)

    btnMinus:SetScript("OnClick", function()
        val = val - (step or 1)
        if minVal and val < minVal then val = minVal end
        UpdateText()
        if callback then callback(val) end
    end)

    btnPlus:SetScript("OnClick", function()
        val = val + (step or 1)
        if maxVal and val > maxVal then val = maxVal end
        UpdateText()
        if callback then callback(val) end
    end)

    container.SetValue = function(_, newVal)
        val = newVal or 1
        UpdateText()
    end
    container.GetValue = function()
        return val
    end

    return container
end

--- Creates a styled label FontString.
---@param parent Frame  parent frame
---@param text string  text label
---@param fontObject string?  font template name (e.g. GameFontHighlight)
---@return FontString label
function UI_NativeGUI:CreateLabel(parent, text, fontObject)
    local lbl = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    lbl:SetText(text or "")
    return lbl
end

local CLASS_COORDS = {
    WARRIOR     = {0, 0.25, 0, 0.25},
    MAGE        = {0.25, 0.5, 0, 0.25},
    ROGUE       = {0.5, 0.75, 0, 0.25},
    DRUID       = {0.75, 1, 0, 0.25},
    HUNTER      = {0, 0.25, 0.25, 0.5},
    SHAMAN      = {0.25, 0.5, 0.25, 0.5},
    PRIEST      = {0.5, 0.75, 0.25, 0.5},
    WARLOCK     = {0.75, 1, 0.25, 0.5},
    PALADIN     = {0, 0.25, 0.5, 0.75},
    DEATHKNIGHT = {0.25, 0.5, 0.5, 0.75},
    MONK        = {0.5, 0.75, 0.5, 0.75},
    DEMONHUNTER = {0.75, 1, 0.5, 0.75},
    EVOKER      = {0, 0.25, 0.75, 1.0},
}

--- Returns the robust class color hex string (8 characters, with leading alpha 'ff').
---@param class string|nil
---@return string hex
function UI_NativeGUI:GetClassColorHex(class)
    if not class then return "ffffffff" end
    local num = tonumber(class)
    if num and GetClassInfo then
        local _, englishName = GetClassInfo(num)
        class = englishName
    end
    if not class then return "ffffffff" end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class:upper()]
    if c then
        if c.colorStr then
            if c.colorStr:len() == 8 then
                return c.colorStr
            else
                return "ff" .. c.colorStr
            end
        else
            return string.format("ff%02x%02x%02x", c.r*255, c.g*255, c.b*255)
        end
    end
    return "ffffffff"
end

--- Returns a class-colored string wrapped in |cff...|r tags.
---@param class string|nil
---@param text string
---@return string wrappedText
function UI_NativeGUI:FormatClassColor(class, text)
    local hex = self:GetClassColorHex(class)
    return "|c" .. hex .. text .. "|r"
end

--- Returns a class icon in |T...|t markup form.
---@param class string|nil
---@param size number?
---@return string markup
function UI_NativeGUI:GetClassIconMarkup(class, size)
    if not class then return "" end
    local num = tonumber(class)
    if num and GetClassInfo then
        local _, englishName = GetClassInfo(num)
        class = englishName
    end
    if not class then return "" end
    size = size or 14
    local coords = CLASS_COORDS[class:upper()]
    if coords then
        local l, r, t, b = coords[1]*256, coords[2]*256, coords[3]*256, coords[4]*256
        return string.format("|TInterface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes:%d:%d:0:0:256:256:%d:%d:%d:%d|t", size, size, l, r, t, b)
    end
    return ""
end

--- Formats a timestamp into a short time string.
---@param ts number|nil
---@param fmt string?
---@return string formattedTime
function UI_NativeGUI:FormatTime(ts, fmt)
    if not ts then return "" end
    return date(fmt or "%H:%M", ts)
end

function UI_NativeGUI:ExpandWindow(frame, windowName)
    ExpandWindow(frame, windowName)
end

function UI_NativeGUI:CollapseWindow(frame, windowName)
    CollapseWindow(frame, windowName)
end
