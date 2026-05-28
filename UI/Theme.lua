local _, AT = ...
if AT.abortLoad then return end

---@class UI_Theme : AceModule
local UI_Theme = DesolateLootcouncil:NewModule("UI_Theme")

function UI_Theme:OnInitialize()
    local AceGUI = LibStub("AceGUI-3.0", true)
    if AceGUI and not AceGUI._desolateThemed then
        local originalCreate = AceGUI.Create
        AceGUI.Create = function(self, widgetType, ...)
            local widget = originalCreate(self, widgetType, ...)
            if widget then
                UI_Theme:ApplyTheme(widget)
            end
            return widget
        end
        AceGUI._desolateThemed = true
    end
end

local themes = {}

--- Registers a custom UI theme configuration.
---@param key string
---@param themeData table
function UI_Theme:RegisterTheme(key, themeData)
    themes[key] = themeData
end

--- Returns the theme table for a given key, defaulting to Midnight.
---@param themeKey string|nil
---@return table theme
function UI_Theme:GetTheme(themeKey)
    local k = themeKey or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile.activeTheme) or "Midnight"
    local t = themes[k] or themes["Midnight"]
    if not t then
        -- Robust fallback in case themes are not loaded or registered yet (e.g. in bare test context)
        t = {
            name = "Midnight (Void)",
            bg = { 0.05, 0.03, 0.08, 0.90 },
            border = { 0.50, 0.25, 0.80, 1.0 },
            buttonBg = { 0.12, 0.08, 0.20, 0.9 },
            buttonHover = { 0.25, 0.15, 0.45, 1.0 },
            textHeader = { 0.75, 0.50, 1.0 },
            textNormal = { 0.90, 0.90, 0.95 },
            accent = { 0.60, 0.30, 0.90 }
        }
    end
    return t
end

--- Returns the active theme table.
---@return table theme
function UI_Theme:GetActiveTheme()
    return self:GetTheme()
end

--- Styles a frame using the active theme.
---@param widgetOrFrame any  AceGUI widget object, native frame, or button
---@param windowType string? optional visual context hint
function UI_Theme:ApplyTheme(widgetOrFrame, windowType)
    if not widgetOrFrame then return end
    local theme = self:GetActiveTheme()

    -- 1. Resolve underlying WoW frame
    local f = widgetOrFrame.frame or widgetOrFrame
    if not f then return end

    if f.GetObjectType and f:GetObjectType() == "ScrollFrame" then
        local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI", true)
        if NativeGUI and NativeGUI.StyleScrollBar then
            NativeGUI:StyleScrollBar(f)
        end
    end

    -- 2. Secure backdrop support (Dragonflight/Midnight compat)
    if not f.SetBackdrop then
        Mixin(f, BackdropTemplateMixin)
    end

    -- 3. Apply theme backdrop and border
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(unpack(theme.bg))
    f:SetBackdropBorderColor(unpack(theme.border))

    -- 4. Strip legacy Ace3 Frame elements for a clean futuristic gaming look
    if widgetOrFrame.type == "Frame" then
        -- Hide the default Blizzard dialog textures and headers
        for i = 1, f:GetNumRegions() do
            local r = select(i, f:GetRegions())
            if r and r:GetObjectType() == "Texture" then
                r:SetTexture(nil)
                r:SetAlpha(0)
                r:Hide()
            end
        end

        -- Hide sizers, bottom-right Close button, status bar
        for _, child in ipairs({ f:GetChildren() }) do
            local childType = child:GetObjectType()
            if childType == "Button" then
                local text = child:GetText()
                if text == CLOSE or text == "Close" or text == "Schließen" or text == "Loot Monitor" or text == "Loot Vote" then
                    child:Hide()
                elseif child.SetBackdrop then
                    -- This is the status bar
                    child:Hide()
                end
            elseif childType == "Frame" and child ~= widgetOrFrame.content then
                -- Sizers
                child:Hide()
            end
        end

        -- Create beautiful minimalist close button "X" in top right
        if not f._customCloseButton then
            local cb = CreateFrame("Button", nil, f, "BackdropTemplate")
            cb:SetSize(20, 20)
            cb:SetPoint("TOPRIGHT", -12, -12)
            cb:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            cb:SetBackdropColor(0.15, 0.1, 0.2, 0.8)
            cb:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.8)

            local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("CENTER")
            text:SetText("X")
            text:SetTextColor(1, 1, 1, 0.8)

            cb:SetScript("OnClick", function()
                widgetOrFrame:Hide()
            end)
            cb:SetScript("OnEnter", function()
                text:SetTextColor(1, 0.3, 0.3, 1)
                cb:SetBackdropColor(0.3, 0.1, 0.1, 0.9)
            end)
            cb:SetScript("OnLeave", function()
                text:SetTextColor(1, 1, 1, 0.8)
                cb:SetBackdropColor(0.15, 0.1, 0.2, 0.8)
            end)

            f._customCloseButton = cb
        else
            f._customCloseButton:Show()
        end
    end

    -- 5. Style Title text if available
    if widgetOrFrame.titletext then
        widgetOrFrame.titletext:SetTextColor(unpack(theme.textHeader))
        widgetOrFrame.titletext:SetFontObject(GameFontNormalLarge)
        -- Align title text to TOPLEFT for a clean dashboard look!
        widgetOrFrame.titletext:ClearAllPoints()
        widgetOrFrame.titletext:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
    end

    -- 6. Style EditBox widgets to hide retro borders and render clean Obsidian boxes
    if widgetOrFrame.type == "EditBox" then
        local eb = widgetOrFrame.editbox
        if eb then
            if not eb.SetBackdrop then
                Mixin(eb, BackdropTemplateMixin)
            end
            eb:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            eb:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.9)
            eb:SetBackdropBorderColor(unpack(theme.border))

            -- Hide the default Blizzard texture components of the editbox
            for i = 1, eb:GetNumRegions() do
                local r = select(i, eb:GetRegions())
                if r and r:GetObjectType() == "Texture" then
                    local tex = r:GetTexture()
                    if tex and (string.find(tex, "UI%-ChatTextBox") or string.find(tex, "Edge") or string.find(tex, "Background")) then
                        r:SetAlpha(0)
                    end
                end
            end
        end
    end

    -- 7. Detect and style button widgets
    local BUTTON_COLORS = {
        ["Bid"] = { border = { 0.0, 0.8, 0.6, 1.0 }, hover = { 0.0, 0.5, 0.4, 0.5 } },
        ["Roll"] = { border = { 0.0, 0.6, 0.9, 1.0 }, hover = { 0.0, 0.4, 0.6, 0.5 } },
        ["Offspec"] = { border = { 0.6, 0.3, 0.9, 1.0 }, hover = { 0.4, 0.2, 0.6, 0.5 } },
        ["T-Mog"] = { border = { 0.6, 0.6, 0.6, 1.0 }, hover = { 0.4, 0.4, 0.4, 0.5 } },
        ["Pass"] = { border = { 0.3, 0.3, 0.3, 1.0 }, hover = { 0.2, 0.2, 0.2, 0.5 } },
        ["Note"] = { border = { 0.6, 0.3, 0.9, 1.0 }, hover = { 0.4, 0.2, 0.6, 0.5 } },
        ["Stop"] = { border = { 0.8, 0.2, 0.2, 1.0 }, hover = { 0.5, 0.1, 0.1, 0.6 } },
    }

    if widgetOrFrame.type == "Button" or f:GetObjectType() == "Button" then
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            -- Clear standard textures
            if f.SetNormalTexture then f:SetNormalTexture("") end
            if f.SetPushedTexture then f:SetPushedTexture("") end
            if f.SetHighlightTexture then f:SetHighlightTexture("") end
            if f.SetDisabledTexture then f:SetDisabledTexture("") end

            local custom = BUTTON_COLORS[windowType]
            local borderCol = custom and custom.border or theme.border
            local bgCol = theme.buttonBg
            local hoverCol = custom and custom.hover or theme.buttonHover

            f:SetBackdropColor(unpack(bgCol))
            f:SetBackdropBorderColor(unpack(borderCol))

            -- Ensure hover scripts are registered securely
            if not f._themedHover then
                f:HookScript("OnEnter", function(self)
                    self:SetBackdropColor(unpack(hoverCol))
                end)
                f:HookScript("OnLeave", function(self)
                    self:SetBackdropColor(unpack(bgCol))
                end)
                f._themedHover = true
            end
        end
    end

    -- 8. Style Heading widgets
    if widgetOrFrame.type == "Heading" then
        if widgetOrFrame.label then
            widgetOrFrame.label:SetTextColor(unpack(theme.textHeader))
        end
        if widgetOrFrame.left and widgetOrFrame.left.SetTexture then widgetOrFrame.left:SetTexture(nil) end
        if widgetOrFrame.right and widgetOrFrame.right.SetTexture then widgetOrFrame.right:SetTexture(nil) end
    end

    -- 9. Style Dropdown widgets
    if widgetOrFrame.type == "Dropdown" then
        local drop = widgetOrFrame.dropdown
        if drop then
            if not drop.SetBackdrop then
                Mixin(drop, BackdropTemplateMixin)
            end
            drop:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            drop:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.9)
            drop:SetBackdropBorderColor(unpack(theme.border))
        end
    end
end

--- Styles a row container to have a modern, isolated panel appearance.
---@param rowWidget any  AceGUI SimpleGroup or native Frame
---@param isActive boolean  whether the row is active/open for voting
function UI_Theme:StyleRow(rowWidget, isActive)
    if not rowWidget then return end
    local f = rowWidget.frame or rowWidget
    if not f then return end
    local theme = self:GetActiveTheme()

    if not f.SetBackdrop then
        Mixin(f, BackdropTemplateMixin)
    end

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })

    -- Row background: slightly lighter dark-obsidian than the main frame
    local bgR = theme.bg[1] + 0.03
    local bgG = theme.bg[2] + 0.03
    local bgB = theme.bg[3] + 0.03
    f:SetBackdropColor(bgR, bgG, bgB, 0.95)

    if isActive then
        -- Glowing neon accent border
        f:SetBackdropBorderColor(unpack(theme.border))
    else
        -- Muted/dark border
        f:SetBackdropBorderColor(theme.border[1] * 0.3, theme.border[2] * 0.3, theme.border[3] * 0.3, 0.4)
    end
end

--- Styles a native frame dynamically using the active UI theme.
---@param frame Frame
function UI_Theme:StyleNativeWindow(frame)
    if not frame then return end
    local theme = self:GetActiveTheme()
    frame:SetBackdropColor(unpack(theme.bg))
    frame:SetBackdropBorderColor(unpack(theme.border))

    if frame.titleText then
        frame.titleText:SetTextColor(unpack(theme.textHeader))
    end

    if frame.closeButton then
        frame.closeButton:SetBackdropBorderColor(unpack(theme.border))
    end

    if frame.grabberTex then
        frame.grabberTex:SetVertexColor(theme.border[1], theme.border[2], theme.border[3], 0.8)
    end
end

--- Re-applies active theme to all open addon UI windows.
function UI_Theme:ApplyThemeToAllOpenWindows()
    local session = DesolateLootcouncil:GetModule("Session", true)
    local clientLootList = session and session.clientLootList

    -- Settings Window
    local SettingsUI = DesolateLootcouncil:GetModule("UI_Settings", true)
    if SettingsUI and SettingsUI.settingsFrame and SettingsUI.settingsFrame:IsShown() then
        self:StyleNativeWindow(SettingsUI.settingsFrame)
        if SettingsUI.sidebar then
            local theme = self:GetActiveTheme()
            SettingsUI.sidebar:SetBackdropColor(theme.bg[1] * 0.6, theme.bg[2] * 0.6, theme.bg[3] * 0.6, 0.5)
            SettingsUI.sidebar:SetBackdropBorderColor(theme.border[1] * 0.4, theme.border[2] * 0.4, theme.border[3] * 0.4, 0.5)
        end
        SettingsUI:RenderTabs()
    end

    -- Loot Window
    local LootUI = DesolateLootcouncil:GetModule("UI_Loot", true)
    if LootUI and LootUI.lootFrame and LootUI.lootFrame:IsShown() then
        self:StyleNativeWindow(LootUI.lootFrame)
        LootUI:ShowLootWindow(DesolateLootcouncil.db.profile.session.loot)
    end

    -- Monitor Window
    local MonitorUI = DesolateLootcouncil:GetModule("UI_Monitor", true)
    if MonitorUI and MonitorUI.monitorFrame and MonitorUI.monitorFrame:IsShown() then
        self:StyleNativeWindow(MonitorUI.monitorFrame)
        if MonitorUI.awardFrame then
            self:StyleNativeWindow(MonitorUI.awardFrame)
        end
        MonitorUI:ShowMonitorWindow(true)
    end

    -- Voting Window
    local VotingUI = DesolateLootcouncil:GetModule("UI_Voting", true)
    if VotingUI and VotingUI.votingFrame and VotingUI.votingFrame:IsShown() then
        self:StyleNativeWindow(VotingUI.votingFrame)
        VotingUI:ShowVotingWindow(clientLootList, true)
    end

    -- Trade Window
    local TradeUI = DesolateLootcouncil:GetModule("UI_TradeList", true)
    if TradeUI and TradeUI.tradeListFrame and TradeUI.tradeListFrame:IsShown() then
        self:StyleNativeWindow(TradeUI.tradeListFrame)
        TradeUI:ShowTradeListWindow()
    end

    -- History Window
    local HistoryUI = DesolateLootcouncil:GetModule("UI_History", true)
    if HistoryUI and HistoryUI.historyFrame and HistoryUI.historyFrame.frame and HistoryUI.historyFrame.frame:IsShown() then
        self:StyleNativeWindow(HistoryUI.historyFrame.frame)
        HistoryUI:ShowHistoryWindow()
    end
end
