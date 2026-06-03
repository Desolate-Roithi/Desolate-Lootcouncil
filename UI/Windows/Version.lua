local _, AT = ...
if AT.abortLoad then return end

---@class UI_Version : AceModule, AceTimer-3.0
local UI_Version = DesolateLootcouncil:NewModule("UI_Version", "AceEvent-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local function ParseSemVer(v)
    if not v or v == "" then return 0, 0, 0, "" end
    local major, minor, patch, suffix = v:match("(%d+)%.(%d+)%.(%d+)%-?(.*)")
    if not major then return 0, 0, 0, "" end
    return tonumber(major), tonumber(minor), tonumber(patch), (suffix or "")
end

local function CompareSemVer(v1, v2)
    local M1, m1, p1, s1 = ParseSemVer(v1)
    local M2, m2, p2, s2 = ParseSemVer(v2)

    if M1 ~= M2 then return M1 > M2 end
    if m1 ~= m2 then return m1 > m2 end
    if p1 ~= p2 then return p1 > p2 end

    if s1 == "" and s2 ~= "" then return true end
    if s1 ~= "" and s2 == "" then return false end

    if s1 ~= "" and s2 ~= "" then
        return s1:lower() > s2:lower()
    end
    return false
end

-- Helper functions to keep nesting flat
local function OnVersionTimerTick()
    if not UI_Version.versionFrame or not UI_Version.versionFrame:IsShown() then return end
    local remaining = DesolateLootcouncil.API:GetVersionCheckCooldown()
    if remaining > 0 then
        UI_Version.btnRefresh:SetText(string.format(L["Wait %.0fs"], remaining))
        UI_Version.btnRefresh:SetEnabled(false)
    else
        UI_Version.btnRefresh:SetText(L["Refresh / Ping"])
        UI_Version.btnRefresh:SetEnabled(true)
    end
end

local function OnVersionRefreshClicked(isTest)
    local ok = DesolateLootcouncil.API:SendVersionCheck()
    if not ok then return end

    UI_Version.btnRefresh:SetEnabled(false)
    UI_Version.btnRefresh:SetText(L["Pinging..."])
    
    C_Timer.After(1.5, function()
        if UI_Version.versionFrame then
            UI_Version:UpdateVersionList(isTest)
        end
    end)
end

local function OnVersionFrameHide()
    if UI_Version.refreshTimer then
        UI_Version:CancelTimer(UI_Version.refreshTimer)
        UI_Version.refreshTimer = nil
    end
end

function UI_Version:ShowVersionWindow(isTest)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.versionFrame then
        local frame = NativeGUI:CreateWindow("DLCVersionFrame", L["Desolate Loot Council - Versions"], "Version")
        self.versionFrame = frame
        self.rowPool = {}

        local btnRefresh = NativeGUI:CreateButton(frame, L["Refresh / Ping"], 180, 24, "Pass")
        btnRefresh:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
        self.btnRefresh = btnRefresh

        -- Repeating timer to handle button state and countdown text
        self.refreshTimer = self:ScheduleRepeatingTimer(OnVersionTimerTick, 1)

        btnRefresh:SetScript("OnClick", function() OnVersionRefreshClicked(isTest) end)

        frame:HookScript("OnHide", OnVersionFrameHide)
    end

    self.versionFrame:Show()
    self:UpdateVersionList(isTest)
end

function UI_Version:OnEnable()
    self:RegisterMessage("DLC_VERSION_UPDATE", function()
        if self.versionFrame and self.versionFrame:IsShown() then
            self:UpdateVersionList()
        end
    end)
end

function UI_Version:UpdateVersionList(isTest)
    if not self.versionFrame then return end
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    NativeGUI:ResetRowPool(self.rowPool)

    if not self.scrollFrame then
        -- Leave space for footer button (bottomOffset = -46)
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.versionFrame, -75, -46)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    self.scrollFrame:Show()
    self.scrollContent:Show()

    if not self.initialPingSent then
        local remaining = DesolateLootcouncil.API:GetVersionCheckCooldown()
        if remaining <= 0 then
            DesolateLootcouncil.API:SendVersionCheck()
            self.initialPingSent = true
        end
    end

    local roster = {}
    local rosterMap = {}

    local function AddEntry(name, class, version)
        if not rosterMap[name] then
            local entry = { name = name, class = class, version = version }
            table.insert(roster, entry)
            rosterMap[name] = entry
        end
    end

    AddEntry(UnitName("player"), select(2, UnitClass("player")), DesolateLootcouncil.API:GetVersion())

    if IsInRaid() then
        for i = 1, 40 do
            local name, _, _, _, _, fileName = GetRaidRosterInfo(i)
            if name then
                AddEntry(name, fileName, nil)
            end
        end
    elseif IsInGroup() then
        local members = GetNumGroupMembers()
        if members > 0 then
            for i = 1, members - 1 do
                local unit = "party" .. i
                if UnitExists(unit) then
                    local name = UnitName(unit)
                    local filename = select(2, UnitClass(unit))
                    AddEntry(name, filename, nil)
                end
            end
        end
    end

    local activeUsers = DesolateLootcouncil.API:GetActiveAddonUsers()
    if activeUsers then
        for name, _ in pairs(activeUsers) do
            if not rosterMap[name] then
                local class = DesolateLootcouncil:GetModule("Roster"):GetUnitClass(name)
                AddEntry(name, class, nil)
            end
        end
    end

    local playerVersions = DesolateLootcouncil.API:GetPlayerVersions()
    local highestVerStr = "0.0.0"
    
    for _, entry in ipairs(roster) do
        if not DesolateLootcouncil.API:SmartCompare(entry.name, "player") then
            local ver = playerVersions and playerVersions[entry.name]
            entry.version = ver
        end
    end

    if isTest then
        AddEntry("OutdatedPlayer", "WARRIOR", "0.0.1")
        AddEntry("MissingPlayer", "MAGE", nil)
        AddEntry("FuturePlayer", "ROGUE", "9.9.9")
    end

    for _, entry in ipairs(roster) do
        if entry.version then
            if CompareSemVer(entry.version, highestVerStr) then
                highestVerStr = entry.version
            end
        end
    end

    -- Header Info label
    if not self.headerLabel then
        self.headerLabel = self.versionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        self.headerLabel:SetPoint("TOPLEFT", 16, -42)
    end
    self.headerLabel:SetText(string.format(L["Highest Found Version: %s"], highestVerStr))
    self.headerLabel:Show()

    table.sort(roster, function(a, b) return a.name < b.name end)

    local topOffset = 0
    local rowHeight = 24

    for idx, entry in ipairs(roster) do
        if not self.rowPool[idx] then
            self.rowPool[idx] = NativeGUI:CreateRowContainer(self.scrollContent, false)
        end
        local row = self.rowPool[idx]
        row:Show()
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
        row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

        -- Class-colored player name
        if not row.nameText then
            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 8, 0)
        end
        local displayName = DesolateLootcouncil:GetDisplayName(entry.name)
        row.nameText:SetText(NativeGUI:FormatClassColor(entry.class, displayName))
        row.nameText:SetTextColor(1, 1, 1)

        -- Version status text
        if not row.verText then
            row.verText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.verText:SetPoint("RIGHT", -8, 0)
        end

        local ver = entry.version
        if not ver then
            row.verText:SetText(L["Not Installed / Missing"])
            row.verText:SetTextColor(0.5, 0.5, 0.5)
        else
            if not CompareSemVer(highestVerStr, ver) then
                row.verText:SetText(string.format(L["%s (Current)"], ver))
                row.verText:SetTextColor(0, 1, 0)
            else
                row.verText:SetText(string.format(L["%s (Outdated)"], ver))
                row.verText:SetTextColor(1, 0, 0)
            end
        end

        topOffset = topOffset + rowHeight + 4
    end

    self.scrollContent:SetHeight(topOffset + 10)
end
