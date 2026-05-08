local _, AT = ...
if AT.abortLoad then return end

-- ═══════════════════════════════════════════════════════════════════════════════
-- UI_LuraWidget  —  Lu'Ra Memory Tracker  (Midnight S1 / Encounter 3183)
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- REMOVAL GUIDE  (this feature is tier-specific; to remove cleanly):
-- ─────────────────────────────────────────────────────────────────
--  1. DELETE   UI/Widgets/Lura/LuraWidget.lua   (this file)
--  2. XML      Remove one line from Desolate_Lootcouncil.xml:
--                 <Script file="UI\Widgets\Lura\LuraWidget.lua"/>
--  3. SLASH    Remove the "lura" elseif block from Core/SlashCommands.lua
--                 (search: cmd == "lura")
--  4. TEST     Delete Tests/Unit/LuraWidget_Test.lua  (optional)
--
--  No other files reference this module.  Addon.lua is untouched.
-- ─────────────────────────────────────────────────────────────────
--
-- DESIGN DECISIONS (12.0.1 MIDNIGHT RESTRICTIONS):
-- ────────────────────────────────────────────────
--  1. DO NOT REVERT TO NATIVE RAID MARKER STRINGS ({rt1}-{rt8}).
--     While {rtX} renders fine in chat, 12.0.1 fails to "re-encode" these symbols
--     into icons when captured from chat and reassigned to custom UI elements.
--     Using native strings results in literal "{rtX}" text appearing in the widget.
--  2. USE CUSTOM FILE IDs.
--     We use direct numeric File IDs (e.g., "7549166") to guarantee icon rendering
--     via |T tags on custom frames, bypassing the re-encoding failure.
--  3. PUBLIC CHAT BROADCAST (MACROS).
--     Hidden addon channels (SendAddonMessage) proved unreliable/throttled for
--     this encounter in 12.0.1. We use Secure Action Macros to write directly
--     to RAID/PARTY chat for guaranteed delivery and raider transparency.
-- ─────────────────────────────────────────────────────────────────
--
-- Views
--   RL + Assists  →  Horizontal picker bar  (build & broadcast sequence)
--                    Hidden if pickerEnabled = false in /dlc lura settings
--   All raiders   →  Pentagon radial display  (icons around "BOSS" centre)
--
-- Slash endpoints (registered in Core/SlashCommands.lua)
--   /dlc lura        →  RL/Assist: toggle settings panel
--                        Raider:    toggle display overlay
--   /dlc lura test   →  Force demo sequence (any role, toggles off on repeat)
-- ═══════════════════════════════════════════════════════════════════════════════

---@class UI_LuraWidget : AceModule
local UI_LuraWidget     = DesolateLootcouncil:NewModule("UI_LuraWidget")

---@type DesolateLootcouncil
local DLC               = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")

-- ─────────────────────────────────────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────────────────────────────────────

local LURA_ENCOUNTER_ID = 3183


local PICKER_SYMBOLS  = {
    { label = "Square",   icon = "7549166" },
    { label = "Cross",    icon = "237529" },
    { label = "Circle",   icon = "5976915" },
    { label = "Triangle", icon = "4555562" },
    { label = "Diamond",  icon = "7549139" },
}

-- Explicit icon slot positions relative to display frame centre.
-- Layout (BOSS at 0,0):
--   [5]  [1]     y = +65  (closer in, higher up)
--   [4] BOSS [2]    y = -10
--        [3]         y = -70
local SLOT_POS        = {
    [1] = { 65, 65 },   -- top-right  (moved up + inward)
    [2] = { 85, -10 },  -- right of BOSS
    [3] = { 0, -70 },   -- directly below BOSS
    [4] = { -85, -10 }, -- left of BOSS
    [5] = { -65, 65 },  -- top-left   (moved up + inward)
}
local NUM_OFFSET      = 18
local ICON_SIZE       = 44

-- Demo sequence shown in test mode:  Square → Cross → Circle → Triangle → Diamond
local TEST_SEQUENCE   = { "7549166", "237529", "5976915", "4555562", "7549139" }

-- ─────────────────────────────────────────────────────────────────────────────
-- Module state
-- ─────────────────────────────────────────────────────────────────────────────

local sequence        = {} -- current sequence: up to 5 icon indices
local encounterActive = false
local testMode        = false

local displayFrame         -- pentagon radial display
local pickerFrame          -- RL/assist horizontal bar
local settingsFrame        -- /dlc lura settings panel
local iconSlots       = {} -- [i] = { icon, num, glow }  (display)

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function IsLeaderOrAssist()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- Lazy DB accessor — creates the sub-table on first use (no Addon.lua touch needed)
local function GetCfg()
    if not DLC.db then return { pickerEnabled = true } end
    local p = DLC.db.profile
    if not p.luraWidget then
        p.luraWidget = { pickerEnabled = true }
    end
    return p.luraWidget
end

local function PickerEnabled()
    return GetCfg().pickerEnabled ~= false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Display refresh (both frames share this)
-- ─────────────────────────────────────────────────────────────────────────────

local function RefreshDisplay()
    if not displayFrame then return end
    for i = 1, 5 do
        local slot = iconSlots[i]
        local msg  = sequence[i]
        if msg then
            slot.icon:SetFormattedText("|T%s:%d:%d|t", msg, ICON_SIZE, ICON_SIZE)
            slot.icon:Show()
            slot.num:SetText(tostring(i))
            slot.num:Show()
            slot.glow:Show()
        else
            slot.icon:Hide()
            slot.num:Hide()
            slot.glow:Hide()
        end
    end
    if #sequence > 0 then displayFrame:Show() else displayFrame:Hide() end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Build: Pentagon Radial Display  (all raiders + RL read-only)
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildDisplayFrame()
    local W, H = 260, 220
    displayFrame = CreateFrame("Frame", "DLCLuraDisplay", UIParent, "BackdropTemplate")
    displayFrame:SetSize(W, H)
    displayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    displayFrame:SetMovable(true)
    displayFrame:EnableMouse(true)
    displayFrame:RegisterForDrag("LeftButton")
    displayFrame:SetScript("OnDragStart", displayFrame.StartMoving)
    displayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        DLC:SaveFramePosition(displayFrame, "LuraDisplay")
    end)
    displayFrame:Hide()

    -- Dark background
    local bg = displayFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.72)

    -- Subtle purple border
    local ring = displayFrame:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    ring:SetAllPoints()
    ring:SetColorTexture(0.55, 0.35, 0.85, 0.18)

    -- Centre: red glow behind BOSS label
    local bossBg = displayFrame:CreateTexture(nil, "ARTWORK")
    bossBg:SetSize(58, 30)
    bossBg:SetPoint("CENTER", 0, 0)
    bossBg:SetColorTexture(0.7, 0.1, 0.1, 0.45)

    -- Beam-start direction indicator: yellow "|" above BOSS
    -- Communicates where the boss's frontal beam originates from
    -- "|||r" = "||" (literal |) + "|r" (color reset)
    local beamMarker = displayFrame:CreateFontString(nil, "OVERLAY")
    beamMarker:SetFont("Fonts\\FRIZQT__.TTF", 72, "OUTLINE")
    beamMarker:SetPoint("CENTER", -7, 64)
    beamMarker:SetTextColor(1, 0.85, 0.1, 1)
    beamMarker:SetShadowColor(0, 0, 0, 1)
    beamMarker:SetShadowOffset(1, -1)
    beamMarker:SetText("|cffffdd00|||r")

    -- BOSS label
    local bossLabel = displayFrame:CreateFontString(nil, "OVERLAY")
    bossLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    bossLabel:SetPoint("CENTER", 0, 0)
    bossLabel:SetTextColor(1, 0.2, 0.2, 1)
    bossLabel:SetShadowColor(0.8, 0, 0, 1)
    bossLabel:SetShadowOffset(1, -1)
    bossLabel:SetText("BOSS")

    -- Five icon slots using explicit positions
    for i = 1, 5 do
        local px = SLOT_POS[i][1]
        local py = SLOT_POS[i][2]

        -- Number anchor: push outward from centre
        local sign_x = (px == 0) and 0 or (px > 0 and 1 or -1)
        local sign_y = (py == 0) and 0 or (py > 0 and 1 or -1)
        local nx = px + sign_x * NUM_OFFSET
        local ny = py + sign_y * NUM_OFFSET

        -- Glow ring
        local glow = displayFrame:CreateTexture(nil, "ARTWORK")
        glow:SetSize(ICON_SIZE + 10, ICON_SIZE + 10)
        glow:SetPoint("CENTER", px, py)
        glow:SetColorTexture(0.5, 0.3, 0.9, 0.5)
        glow:Hide()

        -- Icon (FontString using Texture Tags for NSRT compatibility)
        local icon = displayFrame:CreateFontString(nil, "OVERLAY")
        icon:SetFont("Fonts\\FRIZQT__.TTF", 16)
        icon:SetPoint("CENTER", px, py)
        icon:Hide()

        -- Order number
        local num = displayFrame:CreateFontString(nil, "OVERLAY")
        num:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        num:SetPoint("CENTER", nx, ny)
        num:SetTextColor(1, 1, 1, 1)
        num:SetShadowColor(0, 0, 0, 1)
        num:SetShadowOffset(1, -1)
        num:Hide()

        iconSlots[i] = { icon = icon, num = num, glow = glow }
    end

    DLC:RestoreFramePosition(displayFrame, "LuraDisplay")
end


-- ─────────────────────────────────────────────────────────────────────────────
-- Build: Horizontal Picker Bar  (RL + Assists who have picker enabled)
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildPickerFrame()
    local BTN   = 38 -- slightly smaller buttons
    local GAP   = 5
    local PAD   = 10
    local LBL   = 16                                             -- height above button for order number
    local LW    = (#PICKER_SYMBOLS + 1) * (BTN + GAP) - GAP + 10 -- +1 slot for Clear button
    local FW    = PAD + LW + PAD
    local FH    = LBL + BTN + 36                                 -- label row + icon row + title + buttons

    pickerFrame = CreateFrame("Frame", "DLCLuraPicker", UIParent, "BackdropTemplate")
    pickerFrame:SetSize(FW, FH)
    pickerFrame:SetPoint("TOP", UIParent, "TOP", 0, -160)
    pickerFrame:SetMovable(true)
    pickerFrame:EnableMouse(true)
    pickerFrame:RegisterForDrag("LeftButton")
    pickerFrame:SetScript("OnDragStart", pickerFrame.StartMoving)
    pickerFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        DLC:SaveFramePosition(pickerFrame, "LuraPicker")
    end)
    pickerFrame:Hide()

    pickerFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    pickerFrame:SetBackdropColor(0.06, 0.04, 0.12, 0.88)
    pickerFrame:SetBackdropBorderColor(0.5, 0.3, 0.8, 1)

    local title = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -5)
    title:SetText("|cffaa77ffL'ura|r Picker")

    -- Symbol picker buttons with order-number labels above each
    for i, sym in ipairs(PICKER_SYMBOLS) do
        local bx = PAD + (i - 1) * (BTN + GAP)

        -- Order number label (empty until clicked)
        local lbl = pickerFrame:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        lbl:SetPoint("TOPLEFT", bx, -(16))
        lbl:SetWidth(BTN)
        lbl:SetJustifyH("CENTER")
        lbl:SetTextColor(0.9, 0.7, 1, 1)
        lbl:SetText("")

        -- Button (Secure Macro)
        local btn = CreateFrame("Button", nil, pickerFrame, "SecureActionButtonTemplate")
        btn:SetSize(BTN, BTN)
        btn:SetPoint("TOPLEFT", bx, -(16 + LBL))
        btn.iconIndex = sym.icon

        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", "/ra " .. sym.icon)

        local btnBg = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        btnBg:SetColorTexture(0.1, 0.07, 0.2, 0.9)

        local btnTex = btn:CreateTexture(nil, "ARTWORK")
        btnTex:SetSize(BTN - 4, BTN - 4)
        btnTex:SetPoint("CENTER")
        btnTex:SetTexture(tonumber(sym.icon))

        local hl = btn:CreateTexture(nil, "OVERLAY")
        hl:SetAllPoints()
        hl:SetColorTexture(0.7, 0.5, 1, 0.22)
        hl:Hide()

        btn:SetScript("OnEnter", function(self)
            hl:Show()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(sym.label, 0.8, 0.6, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            hl:Hide()
            GameTooltip:Hide()
        end)
        -- No OnClick script needed; macrotext handles the broadcast natively!
    end

    DLC:RestoreFramePosition(pickerFrame, "LuraPicker")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Build: Settings mini-panel  (/dlc lura for RL/assist)
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildSettingsFrame()
    settingsFrame = CreateFrame("Frame", "DLCLuraSettings", UIParent, "BackdropTemplate")
    settingsFrame:SetSize(240, 100)
    settingsFrame:SetPoint("TOP", UIParent, "TOP", 0, -110)
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:RegisterForDrag("LeftButton")
    settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
    settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing)
    settingsFrame:Hide()

    settingsFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    settingsFrame:SetBackdropColor(0.06, 0.04, 0.12, 0.92)
    settingsFrame:SetBackdropBorderColor(0.5, 0.3, 0.8, 1)

    local hdr = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOP", 0, -10)
    hdr:SetText("|cffaa77ffL'ura Widget|r  Settings")

    local closeBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() settingsFrame:Hide() end)

    -- "Show Picker Bar" checkbox
    local cb = CreateFrame("CheckButton", "DLCLuraPickerToggle", settingsFrame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 16, -36)
    cb:SetScript("OnClick", function(self)
        local cfg = GetCfg()
        cfg.pickerEnabled = self:GetChecked()
        if not cfg.pickerEnabled and pickerFrame and pickerFrame:IsShown() then
            pickerFrame:Hide()
        elseif cfg.pickerEnabled and IsLeaderOrAssist() and pickerFrame then
            if encounterActive or testMode then pickerFrame:Show() end
        end
    end)
    settingsFrame.pickerCheckbox = cb

    local cbLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cbLabel:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cbLabel:SetText("Show Picker Bar")
    cbLabel:SetTextColor(0.85, 0.75, 1, 1)

    local hint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 16, -64)
    hint:SetText("|cff777777Visible to Raid Leader and Assists only|r")
end

local function ShowSettingsFrame()
    if settingsFrame and settingsFrame.pickerCheckbox then
        settingsFrame.pickerCheckbox:SetChecked(PickerEnabled())
    end
    if settingsFrame then settingsFrame:Show() end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Broadcast / Receive  (addon comm)
-- ─────────────────────────────────────────────────────────────────────────────

function UI_LuraWidget:BroadcastSymbol(iconIdx)
    local word = REVERSE_MAP[iconIdx] or ""
    local msg = string.format("{rt%d} %s", iconIdx, word)
    if IsInRaid() then
        SendChatMessage(msg, "RAID")
    elseif IsInGroup() then
        SendChatMessage(msg, "PARTY")
    else
        -- Solo fallback
        if self.chatFrame and self.chatFrame:GetScript("OnEvent") then
            self.chatFrame:GetScript("OnEvent")(self.chatFrame, "CHAT_MSG_RAID", msg)
        end
    end
end

function UI_LuraWidget:BroadcastClear()
    local msg = "lura clear"
    if IsInRaid() then
        SendChatMessage(msg, "RAID")
    elseif IsInGroup() then
        SendChatMessage(msg, "PARTY")
    else
        -- Solo fallback
        if self.chatFrame and self.chatFrame:GetScript("OnEvent") then
            self.chatFrame:GetScript("OnEvent")(self.chatFrame, "CHAT_MSG_RAID", msg)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Encounter lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function UI_LuraWidget:OnEncounterStart(encID)
    if encID ~= LURA_ENCOUNTER_ID then return end
    encounterActive = true
    testMode        = false
    wipe(sequence)
    RefreshDisplay()
    if IsLeaderOrAssist() and PickerEnabled() and pickerFrame then
        pickerFrame:Show()
    end
    self.chatFrame:RegisterEvent("CHAT_MSG_RAID")
    self.chatFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
    self.chatFrame:RegisterEvent("CHAT_MSG_PARTY")
    self.chatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
end

function UI_LuraWidget:OnEncounterEnd()
    if not encounterActive then return end
    encounterActive = false
    C_Timer.After(4, function()
        if encounterActive or testMode then return end
        wipe(sequence)
        RefreshDisplay()
        if displayFrame then displayFrame:Hide() end
        if pickerFrame then pickerFrame:Hide() end
        if self.chatFrame then
            self.chatFrame:UnregisterEvent("CHAT_MSG_RAID")
            self.chatFrame:UnregisterEvent("CHAT_MSG_RAID_LEADER")
            self.chatFrame:UnregisterEvent("CHAT_MSG_PARTY")
            self.chatFrame:UnregisterEvent("CHAT_MSG_PARTY_LEADER")
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Test mode  (/dlc lura test)
-- ─────────────────────────────────────────────────────────────────────────────

function UI_LuraWidget:ActivateTestMode()
    testMode = true
    wipe(sequence)
    for _, v in ipairs(TEST_SEQUENCE) do table.insert(sequence, v) end
    RefreshDisplay()
    -- Show picker in test mode always (solo testing — not in a group)
    if PickerEnabled() and pickerFrame then
        pickerFrame:Show()
    end
    -- Must register chat events during test mode so the addon hears its own broadcasts!
    if self.chatFrame then
        self.chatFrame:RegisterEvent("CHAT_MSG_RAID")
        self.chatFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
        self.chatFrame:RegisterEvent("CHAT_MSG_PARTY")
        self.chatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
    end
    DLC:Print("|cffaa77ffLura Widget:|r Test mode ON — demo sequence displayed.")
end

function UI_LuraWidget:DeactivateTestMode()
    testMode = false
    wipe(sequence)
    RefreshDisplay()
    if not encounterActive then
        if displayFrame then displayFrame:Hide() end
        if pickerFrame then pickerFrame:Hide() end
        if self.chatFrame then
            self.chatFrame:UnregisterEvent("CHAT_MSG_RAID")
            self.chatFrame:UnregisterEvent("CHAT_MSG_RAID_LEADER")
            self.chatFrame:UnregisterEvent("CHAT_MSG_PARTY")
            self.chatFrame:UnregisterEvent("CHAT_MSG_PARTY_LEADER")
        end
    end
    DLC:Print("|cffaa77ffLura Widget:|r Test mode OFF.")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Slash handler  (registered via Core/SlashCommands.lua — see removal guide)
-- ─────────────────────────────────────────────────────────────────────────────

function UI_LuraWidget:HandleSlash(arg)
    if arg == "test" then
        if testMode then self:DeactivateTestMode() else self:ActivateTestMode() end
        return
    end
    -- /dlc lura (no arg): always show settings panel
    -- Raiders see a note that picker is RL/assist only; everyone can toggle display
    if settingsFrame and settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        ShowSettingsFrame()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Addon comm handler
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- Event frames (encounter + chat) — all local to this file
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildEventFrame()
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("ENCOUNTER_START")
    ef:RegisterEvent("ENCOUNTER_END")
    ef:SetScript("OnEvent", function(_, event, ...)
        if event == "ENCOUNTER_START" then
            UI_LuraWidget:OnEncounterStart(...)
        elseif event == "ENCOUNTER_END" then
            UI_LuraWidget:OnEncounterEnd()
        end
    end)
end

local function BuildChatFrame()
    local cf = CreateFrame("Frame")
    -- Events are registered dynamically in OnEncounterStart to avoid overhead
    cf:SetScript("OnEvent", function(_, _, msg)
        -- Bypass 12.0.1 Secret restrictions by reading token opaquely.
        if #sequence >= 5 then
            wipe(sequence)
        end

        table.insert(sequence, msg)
        RefreshDisplay()

        if UI_LuraWidget.hideTimer then UI_LuraWidget.hideTimer:Cancel() end
        UI_LuraWidget.hideTimer = C_Timer.NewTimer(15, function()
            wipe(sequence)
            RefreshDisplay()
        end)
    end)
    return cf
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OnInitialize
-- ─────────────────────────────────────────────────────────────────────────────

function UI_LuraWidget:OnInitialize()
    BuildDisplayFrame()
    BuildPickerFrame()
    BuildSettingsFrame()
    self.chatFrame = BuildChatFrame()
    BuildEventFrame()
    DLC:DLC_Log("LuraWidget: initialized (encounter " .. LURA_ENCOUNTER_ID .. ")")
end
