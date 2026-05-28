local _, AT = ...
if AT.abortLoad then return end

---@class UI_NativeGUI : AceModule
local UI_NativeGUI = DesolateLootcouncil:NewModule("UI_NativeGUI")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")

--- Creates a beautiful, persistent, Midnight-themed native WoW window.
---@param name string  global frame name (can be nil)
---@param titleText string  text displayed in the header
---@param width number  default frame width
---@param height number  default frame height
---@param windowName string  key for position saving
---@return Frame frame
function UI_NativeGUI:CreateWindow(name, titleText, width, height, windowName)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
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

    -- Style backdrop
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(unpack(theme.bg))
    frame:SetBackdropBorderColor(unpack(theme.border))

    -- Draggable Title Bar Header
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(38)
    titleBar:SetPoint("TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", -22, -2)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        DesolateLootcouncil:SaveFramePosition(frame, windowName)
    end)

    -- Header Title Typography
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 14, 0)
    title:SetText(titleText)
    title:SetTextColor(unpack(theme.textHeader))

    -- Minimalist top-right Close button "X"
    local close = CreateFrame("Button", nil, frame, "BackdropTemplate")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    close:SetBackdropColor(0.15, 0.1, 0.2, 0.8)
    close:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.8)

    local xText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xText:SetPoint("CENTER")
    xText:SetText("X")
    xText:SetTextColor(1, 1, 1, 0.8)

    close:SetScript("OnClick", function() frame:Hide() end)
    close:SetScript("OnEnter", function()
        xText:SetTextColor(1, 0.3, 0.3, 1)
        close:SetBackdropColor(0.3, 0.1, 0.1, 0.9)
    end)
    close:SetScript("OnLeave", function()
        xText:SetTextColor(1, 1, 1, 0.8)
        close:SetBackdropColor(0.15, 0.1, 0.2, 0.8)
    end)

    -- Elegant Neon Purple Sizing Handle in bottom-right corner
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

    frame.titleText = title
    frame.closeButton = close
    frame.grabber = grabber
    frame.grabberTex = grabberTex

    -- Persistence Integration
    DesolateLootcouncil:RestoreFramePosition(frame, windowName)

    return frame
end

--- Creates a modern, native scroll frame with stripped retro textures and a flat scrollbar thumb.
---@param parent Frame  parent native Frame
---@param topOffset number  Y offset relative to the top of the parent
---@param bottomOffset number  Y offset relative to the bottom of the parent (usually negative)
---@return ScrollFrame scrollFrame, Frame scrollContent
--- Styles a scrollbar dynamically using the active UI theme, replacing retro gold arrows with modern flat vertex-colored ones.
---@param scrollFrame ScrollFrame
function UI_NativeGUI:StyleScrollBar(scrollFrame)
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    local scrollBarName = scrollFrame:GetName() and (scrollFrame:GetName() .. "ScrollBar") or nil
    if scrollBarName then
        local scrollBar = _G[scrollBarName]
        if scrollBar then
            -- Clean and style the track
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -16)
            scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 16)

            for i = 1, scrollBar:GetNumRegions() do
                local r = select(i, scrollBar:GetRegions())
                if r and r:GetObjectType() == "Texture" then
                    r:SetTexture(nil)
                    r:SetAlpha(0)
                end
            end

            -- Modern dark track background matching active theme
            if not scrollBar.trackBg then
                local trackBg = scrollBar:CreateTexture(nil, "BACKGROUND")
                trackBg:SetAllPoints(scrollBar)
                scrollBar.trackBg = trackBg
            end
            scrollBar.trackBg:SetColorTexture(theme.bg[1] * 1.2, theme.bg[2] * 1.2, theme.bg[3] * 1.2, 0.7)

            -- Sleek flat thumb matching active theme border
            local thumb = scrollBar:GetThumbTexture()
            if thumb then
                thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
                thumb:SetColorTexture(unpack(theme.border))
                thumb:SetSize(12, 24)
            end

            -- Strip retro arrow button textures and apply modern atlas arrows
            local upBtn = scrollBar.ScrollUpButton or _G[scrollBarName .. "ScrollUpButton"]
            if upBtn then
                upBtn:ClearAllPoints()
                upBtn:SetPoint("BOTTOM", scrollBar, "TOP", 0, 2)
                upBtn:SetSize(16, 11)

                if upBtn.SetNormalTexture then upBtn:SetNormalTexture("") end
                if upBtn.SetPushedTexture then upBtn:SetPushedTexture("") end
                if upBtn.SetDisabledTexture then upBtn:SetDisabledTexture("") end

                for i = 1, upBtn:GetNumRegions() do
                    local r = select(i, upBtn:GetRegions())
                    if r and r:GetObjectType() == "Texture" then
                        r:SetTexture(nil)
                        r:SetAlpha(0)
                    end
                end

                if not upBtn.customArrow then
                    local customArrow = upBtn:CreateTexture(nil, "OVERLAY")
                    customArrow:SetSize(16, 11)
                    customArrow:SetPoint("CENTER", 0, 0)
                    customArrow:SetAtlas("minimal-scrollbar-arrow-top")
                    upBtn.customArrow = customArrow
                end
                upBtn.customArrow:SetVertexColor(unpack(theme.border))

                -- Sleek micro-interactions on hover
                upBtn:SetScript("OnEnter", function()
                    upBtn.customArrow:SetVertexColor(theme.border[1] * 1.2, theme.border[2] * 1.2, theme.border[3] * 1.2, 1.0)
                end)
                upBtn:SetScript("OnLeave", function()
                    upBtn.customArrow:SetVertexColor(unpack(theme.border))
                end)
            end

            local downBtn = scrollBar.ScrollDownButton or _G[scrollBarName .. "ScrollDownButton"]
            if downBtn then
                downBtn:ClearAllPoints()
                downBtn:SetPoint("TOP", scrollBar, "BOTTOM", 0, -2)
                downBtn:SetSize(16, 11)

                if downBtn.SetNormalTexture then downBtn:SetNormalTexture("") end
                if downBtn.SetPushedTexture then downBtn:SetPushedTexture("") end
                if downBtn.SetDisabledTexture then downBtn:SetDisabledTexture("") end

                for i = 1, downBtn:GetNumRegions() do
                    local r = select(i, downBtn:GetRegions())
                    if r and r:GetObjectType() == "Texture" then
                        r:SetTexture(nil)
                        r:SetAlpha(0)
                    end
                end

                if not downBtn.customArrow then
                    local customArrow = downBtn:CreateTexture(nil, "OVERLAY")
                    customArrow:SetSize(16, 11)
                    customArrow:SetPoint("CENTER", 0, 0)
                    customArrow:SetAtlas("minimal-scrollbar-arrow-bottom")
                    downBtn.customArrow = customArrow
                end
                downBtn.customArrow:SetVertexColor(unpack(theme.border))

                -- Sleek micro-interactions on hover
                downBtn:SetScript("OnEnter", function()
                    downBtn.customArrow:SetVertexColor(theme.border[1] * 1.2, theme.border[2] * 1.2, theme.border[3] * 1.2, 1.0)
                end)
                downBtn:SetScript("OnLeave", function()
                    downBtn.customArrow:SetVertexColor(unpack(theme.border))
                end)
            end
        end
    end
end

function UI_NativeGUI:CreateScrollFrame(parent, topOffset, bottomOffset)
    local frameName = parent:GetName() and (parent:GetName() .. "Scroll") or nil
    local scrollFrame = CreateFrame("ScrollFrame", frameName, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, topOffset)
    -- BOTTOMRIGHT: positive Y = upward from parent's bottom edge (inside window).
    -- Callers pass negative values like -16 meaning "16px padding from bottom",
    -- so we negate to convert to the correct upward offset.
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
        ["Bid"] = { border = { 0.0, 0.8, 0.6, 1.0 }, hover = { 0.0, 0.5, 0.4, 0.5 } },
        ["Roll"] = { border = { 0.0, 0.6, 0.9, 1.0 }, hover = { 0.0, 0.4, 0.6, 0.5 } },
        ["Offspec"] = { border = { 0.6, 0.3, 0.9, 1.0 }, hover = { 0.4, 0.2, 0.6, 0.5 } },
        ["T-Mog"] = { border = { 0.6, 0.6, 0.6, 1.0 }, hover = { 0.4, 0.4, 0.4, 0.5 } },
        ["Pass"] = { border = { 0.3, 0.3, 0.3, 1.0 }, hover = { 0.2, 0.2, 0.2, 0.5 } },
        ["Note"] = { border = { 0.6, 0.3, 0.9, 1.0 }, hover = { 0.4, 0.2, 0.6, 0.5 } },
        ["Stop"] = { border = { 0.8, 0.2, 0.2, 1.0 }, hover = { 0.5, 0.1, 0.1, 0.6 } },
    }

    local activeTheme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    local custom = BUTTON_COLORS[buttonType]
    local borderCol = custom and custom.border or activeTheme.border
    local bgCol = activeTheme.buttonBg
    local hoverCol = custom and custom.hover or activeTheme.buttonHover

    btn:SetBackdropColor(unpack(bgCol))
    btn:SetBackdropBorderColor(unpack(borderCol))

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(hoverCol))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(bgCol))
    end)

    return btn
end

--- Creates a native Obsidian container panel with optional neon purple active border.
---@param parent Frame  parent scroll child frame
---@param isActive boolean  whether this represents an active/open voting row
---@return Frame rowContainer
function UI_NativeGUI:CreateRowContainer(parent, isActive)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    local bgR = theme.bg[1] + 0.03
    local bgG = theme.bg[2] + 0.03
    local bgB = theme.bg[3] + 0.03
    row:SetBackdropColor(bgR, bgG, bgB, 0.95)

    if isActive then
        row:SetBackdropBorderColor(unpack(theme.border))
    else
        row:SetBackdropBorderColor(theme.border[1] * 0.3, theme.border[2] * 0.3, theme.border[3] * 0.3, 0.4)
    end

    return row
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
function UI_NativeGUI:CreateDropdown(parent, labelText, width, list, defaultValue, callback)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 42)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 2, 0)
    label:SetText(labelText or "")

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", 0, -16)
    btn:SetPoint("BOTTOMRIGHT", 0, 2)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    btn:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.9)
    btn:SetBackdropBorderColor(unpack(theme.border))

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -22, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetNonSpaceWrap(false)
    -- Do NOT call btn:SetFontString(fs) — WoW resets anchor points on SetText
    -- Track fs directly and use fs:SetText() for safe clipping

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
            menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            menu:SetWidth(btn:GetWidth())
            
            for _, r in ipairs(itemRows) do r:Hide() end

            local keys = {}
            for k in pairs(currentList) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(currentList[a]) < tostring(currentList[b]) end)

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
                    currentValue = key
                    fs:SetText(tostring(val))
                    HideMenu()
                    if callback then callback(key) end
                end)

                menuHeight = menuHeight + rowHeight
            end
            menu:SetHeight(menuHeight)
            menu:Show()
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
