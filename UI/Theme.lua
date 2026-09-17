local _, AT = ...
if AT.abortLoad then return end

---@class UI_Theme : AceModule
local UI_Theme = DesolateLootcouncil:NewModule("UI_Theme")

function UI_Theme:OnInitialize()
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

UI_Theme.BUTTON_COLORS = {
    ["Bid"]     = { border = { 1.0, 0.5, 0.0, 1.0 }, hover = { 0.7, 0.35, 0.0, 0.8 } },
    ["Roll"]    = { border = { 0.64, 0.21, 0.93, 1.0 }, hover = { 0.45, 0.15, 0.65, 0.8 } },
    ["Offspec"] = { border = { 0.0, 0.44, 0.87, 1.0 }, hover = { 0.0, 0.3, 0.6, 0.8 } },
    ["T-Mog"]   = { border = { 0.12, 1.0, 0.0, 1.0 }, hover = { 0.08, 0.7, 0.0, 0.8 } },
    ["Pass"]    = { border = { 0.62, 0.62, 0.62, 1.0 }, hover = { 0.7, 0.7, 0.7, 0.8 } },
    ["Note"]    = { border = { 0.6, 0.3, 0.9, 1.0 }, hover = { 0.4, 0.2, 0.6, 0.8 } },
    ["Stop"]    = { border = { 0.8, 0.2, 0.2, 1.0 }, hover = { 0.5, 0.1, 0.1, 0.9 } },
    ["Action"]  = { border = { 0.6, 0.3, 0.9, 1.0 }, hover = { 0.4, 0.2, 0.6, 0.8 } },
}

function UI_Theme:GetButtonColors()
    return self.BUTTON_COLORS
end

--- Styles a native frame dynamically using the active UI theme.
---@param frame Frame
function UI_Theme:StyleNativeWindow(frame)
    if not frame then return end
    local theme = self:GetActiveTheme()
    local btnColors = self.BUTTON_COLORS

    local function StyleElement(f)
        if not f then return end

        if f == frame then
            f:SetBackdropColor(unpack(theme.bg))
            f:SetBackdropBorderColor(unpack(theme.border))
        end

        if f.titleText then
            f.titleText:SetTextColor(unpack(theme.textHeader))
        end

        if f.closeButton then
            f.closeButton:SetBackdropColor(theme.bg[1] * 1.5, theme.bg[2] * 1.5, theme.bg[3] * 1.5, 0.8)
            f.closeButton:SetBackdropBorderColor(unpack(theme.border))
        end

        if f.grabberTex then
            f.grabberTex:SetVertexColor(theme.border[1], theme.border[2], theme.border[3], 0.8)
        end

        if f.GetObjectType and f:GetObjectType() == "Button" and f.buttonType then
            local custom = btnColors[f.buttonType]
            local borderCol = custom and custom.border or theme.border
            local bgCol = theme.buttonBg
            local hoverCol = custom and custom.hover or theme.buttonHover

            f.themeBg = bgCol
            f.themeHover = hoverCol
            f.themeBorder = borderCol

            f:SetBackdropColor(unpack(bgCol))
            f:SetBackdropBorderColor(unpack(borderCol))
        end

        if f.GetChildren then
            for _, child in ipairs({ f:GetChildren() }) do
                StyleElement(child)
            end
        end
    end

    StyleElement(frame)
end

--- Re-applies active theme to all open addon UI windows.
function UI_Theme:ApplyThemeToAllOpenWindows()
    local clientLootList = DesolateLootcouncil.API and DesolateLootcouncil.API.GetBiddingList and DesolateLootcouncil.API:GetBiddingList()

    -- 1. Universal Native Window Styling
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI", true)
    if NativeGUI and NativeGUI.registeredWindows then
        for winFrame in pairs(NativeGUI.registeredWindows) do
            if winFrame and winFrame.IsShown and winFrame:IsShown() then
                self:StyleNativeWindow(winFrame)
            end
        end
    end

    -- 2. Module-specific dynamic re-renders
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

    -- Item Manager Window
    local ItemManagerUI = DesolateLootcouncil:GetModule("UI_ItemManager", true)
    if ItemManagerUI and ItemManagerUI.frame and ItemManagerUI.frame:IsShown() then
        self:StyleNativeWindow(ItemManagerUI.frame)
        if ItemManagerUI.RefreshWindow then ItemManagerUI:RefreshWindow() end
    end

    -- Raid History Window
    local RaidHistoryUI = DesolateLootcouncil:GetModule("UI_RaidHistory", true)
    if RaidHistoryUI and RaidHistoryUI.frame and RaidHistoryUI.frame:IsShown() then
        self:StyleNativeWindow(RaidHistoryUI.frame)
        if RaidHistoryUI.Refresh then RaidHistoryUI:Refresh() end
    end

    -- Loot Window
    local LootUI = DesolateLootcouncil:GetModule("UI_Loot", true)
    if LootUI and LootUI.lootFrame and LootUI.lootFrame:IsShown() then
        self:StyleNativeWindow(LootUI.lootFrame)
        LootUI:ShowLootWindow(DesolateLootcouncil.API:GetLootBacklog())
    end

    -- Monitor Window
    local MonitorUI = DesolateLootcouncil:GetModule("UI_Monitor", true)
    if MonitorUI and MonitorUI.monitorFrame and MonitorUI.monitorFrame:IsShown() then
        self:StyleNativeWindow(MonitorUI.monitorFrame)
        local theme = self:GetActiveTheme()
        if MonitorUI.deBtn then
            MonitorUI:UpdateDisenchantersButtonState()
        end
        if MonitorUI.deFrame then
            MonitorUI.deFrame:SetBackdropColor(theme.bg[1] * 0.9, theme.bg[2] * 0.9, theme.bg[3] * 0.9, 0.95)
            MonitorUI.deFrame:SetBackdropBorderColor(unpack(theme.border))
            if MonitorUI.deFrame.titleText then
                MonitorUI.deFrame.titleText:SetTextColor(unpack(theme.border))
            end
        end
        MonitorUI:ShowMonitorWindow(true)
    end

    -- Award Window
    local AwardUI = DesolateLootcouncil:GetModule("UI_Award", true)
    if AwardUI and AwardUI.awardFrame and AwardUI.awardFrame:IsShown() then
        self:StyleNativeWindow(AwardUI.awardFrame)
        AwardUI:ShowAwardWindow(AwardUI.activeItemData)
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

    -- Session History Window
    local HistoryUI = DesolateLootcouncil:GetModule("UI_History", true)
    if HistoryUI and HistoryUI.historyFrame then
        local hf = HistoryUI.historyFrame.frame or HistoryUI.historyFrame
        if hf and hf.IsShown and hf:IsShown() then
            self:StyleNativeWindow(hf)
            if HistoryUI.ShowHistoryWindow then HistoryUI:ShowHistoryWindow() end
        end
    end

    -- Priority Override Window
    local OverrideUI = DesolateLootcouncil:GetModule("UI_PriorityOverride", true)
    if OverrideUI and OverrideUI.priorityOverrideFrame and OverrideUI.priorityOverrideFrame:IsShown() then
        self:StyleNativeWindow(OverrideUI.priorityOverrideFrame)
    end
end
