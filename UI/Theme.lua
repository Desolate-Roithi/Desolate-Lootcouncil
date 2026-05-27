local _, AT = ...
if AT.abortLoad then return end

---@class UI_Theme : AceModule
local UI_Theme = DesolateLootcouncil:NewModule("UI_Theme")

local themes = {
    ["Midnight"] = {
        name = "Midnight (Void)",
        bg = { 0.05, 0.03, 0.08, 0.90 },            -- Deep void obsidian-purple
        border = { 0.50, 0.25, 0.80, 1.0 },        -- Glowing neon purple border
        buttonBg = { 0.12, 0.08, 0.20, 0.9 },
        buttonHover = { 0.25, 0.15, 0.45, 1.0 },
        textHeader = { 0.75, 0.50, 1.0 },          -- Glowing light purple header text
        textNormal = { 0.90, 0.90, 0.95 },
        accent = { 0.60, 0.30, 0.90 }
    },
    ["Classic"] = {
        name = "Classic Slate",
        bg = { 0.10, 0.12, 0.16, 0.95 },            -- Dark steel slate blue
        border = { 0.30, 0.40, 0.55, 1.0 },        -- Cool blue border
        buttonBg = { 0.18, 0.20, 0.26, 0.9 },
        buttonHover = { 0.25, 0.30, 0.40, 1.0 },
        textHeader = { 0.60, 0.80, 1.0 },          -- Light blue header text
        textNormal = { 0.90, 0.90, 0.90 },
        accent = { 0.40, 0.60, 0.90 }
    },
    ["Minimalist"] = {
        name = "Pure Dark (Minimal)",
        bg = { 0.07, 0.07, 0.07, 0.96 },            -- Flat coal black
        border = { 0.20, 0.20, 0.20, 1.0 },        -- Thin flat gray border
        buttonBg = { 0.14, 0.14, 0.14, 0.9 },
        buttonHover = { 0.25, 0.25, 0.25, 1.0 },
        textHeader = { 1.0, 1.0, 1.0 },            -- Pure white header text
        textNormal = { 0.85, 0.85, 0.85 },
        accent = { 0.50, 0.50, 0.50 }
    },
    ["Fel"] = {
        name = "Emerald Fel",
        bg = { 0.04, 0.06, 0.04, 0.92 },            -- Dark green-black
        border = { 0.15, 0.70, 0.20, 1.0 },        -- Glowing fel-green border
        buttonBg = { 0.08, 0.15, 0.08, 0.9 },
        buttonHover = { 0.15, 0.30, 0.15, 1.0 },
        textHeader = { 0.30, 0.90, 0.30 },          -- Toxic fel green header text
        textNormal = { 0.85, 0.90, 0.85 },
        accent = { 0.20, 0.80, 0.20 }
    }
}

--- Returns the theme table for a given key, defaulting to Midnight.
---@param themeKey string|nil
---@return table theme
function UI_Theme:GetTheme(themeKey)
    local k = themeKey or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile.activeTheme) or "Midnight"
    return themes[k] or themes["Midnight"]
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

    -- 2. Apply glassmorphism / styled backdrops to containers
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = true, tileSize = 16, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        f:SetBackdropColor(unpack(theme.bg))
        f:SetBackdropBorderColor(unpack(theme.border))
    end

    -- 3. Style Title text if available
    if widgetOrFrame.titletext then
        widgetOrFrame.titletext:SetTextColor(unpack(theme.textHeader))
    end

    -- 4. Detect and style button widgets
    if widgetOrFrame.type == "Button" or f:GetObjectType() == "Button" then
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            f:SetBackdropColor(unpack(theme.buttonBg))
            f:SetBackdropBorderColor(unpack(theme.border))

            -- Ensure hover scripts are registered securely
            if not f._themedHover then
                f:HookScript("OnEnter", function(self)
                    local active = UI_Theme:GetActiveTheme()
                    self:SetBackdropColor(unpack(active.buttonHover))
                end)
                f:HookScript("OnLeave", function(self)
                    local active = UI_Theme:GetActiveTheme()
                    self:SetBackdropColor(unpack(active.buttonBg))
                end)
                f._themedHover = true
            end
        end
    end
end

--- Re-applies active theme to all open addon UI windows.
function UI_Theme:ApplyThemeToAllOpenWindows()
    local session = DesolateLootcouncil:GetModule("Session", true)
    local clientLootList = session and session.clientLootList

    local LootUI = DesolateLootcouncil:GetModule("UI_Loot", true)
    if LootUI and LootUI.lootFrame and LootUI.lootFrame:IsShown() then
        LootUI:ShowLootWindow(DesolateLootcouncil.db.profile.session.loot)
    end

    local MonitorUI = DesolateLootcouncil:GetModule("UI_Monitor", true)
    if MonitorUI and MonitorUI.monitorFrame and MonitorUI.monitorFrame:IsShown() then
        MonitorUI:ShowMonitorWindow(true)
    end

    local VotingUI = DesolateLootcouncil:GetModule("UI_Voting", true)
    if VotingUI and VotingUI.votingFrame and VotingUI.votingFrame:IsShown() then
        VotingUI:ShowVotingWindow(clientLootList, true)
    end

    local TradeUI = DesolateLootcouncil:GetModule("UI_TradeList", true)
    if TradeUI and TradeUI.tradeListFrame and TradeUI.tradeListFrame:IsShown() then
        TradeUI:ShowTradeListWindow()
    end

    local HistoryUI = DesolateLootcouncil:GetModule("UI_History", true)
    if HistoryUI and HistoryUI.historyFrame and HistoryUI.historyFrame.frame and HistoryUI.historyFrame.frame:IsShown() then
        HistoryUI:ShowHistoryWindow()
    end
end
