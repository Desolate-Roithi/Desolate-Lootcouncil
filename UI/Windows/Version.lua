---@class UI_Version : AceModule
local UI_Version = DesolateLootcouncil:NewModule("UI_Version", "AceEvent-3.0")
local AceGUI = LibStub("AceGUI-3.0")

---@class (partial) DLC_Ref_Version
---@field db table
---@field version string
---@field activeAddonUsers table
---@field GetModule fun(self: DLC_Ref_Version, name: string): any
---@field RestoreFramePosition fun(self: DLC_Ref_Version, frame: any, windowName: string)
---@field SaveFramePosition fun(self: DLC_Ref_Version, frame: any, windowName: string)
---@field ApplyCollapseHook fun(self: DLC_Ref_Version, widget: any)
---@field Persistence Persistence

---@type DLC_Ref_Version
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Version]]

-- Helper: Parse version string "1.0.0" into number 100 for comparison
-- Helper: Parse "1.0.0-Beta" -> 1, 0, 0, "Beta"
local function ParseSemVer(v)
    if not v then return 0, 0, 0, "" end
    local major, minor, patch, suffix = v:match("(%d+)%.(%d+)%.(%d+)%-?(.*)")
    if not major then return 0, 0, 0, "" end
    return tonumber(major), tonumber(minor), tonumber(patch), (suffix or "")
end

-- Return true if v1 > v2
local function CompareSemVer(v1, v2)
    local M1, m1, p1, s1 = ParseSemVer(v1)
    local M2, m2, p2, s2 = ParseSemVer(v2)

    if M1 ~= M2 then return M1 > M2 end
    if m1 ~= m2 then return m1 > m2 end
    if p1 ~= p2 then return p1 > p2 end

    -- Core equal. Check suffixes.
    -- Release (empty suffix) > Pre-release (any suffix)
    if s1 == "" and s2 ~= "" then return true end
    if s1 ~= "" and s2 == "" then return false end

    -- Both have suffixes? Alphabetical (Beta > Alpha)
    if s1 ~= "" and s2 ~= "" then
        return s1:lower() > s2:lower()
    end

    -- Equal
    return false
end

function UI_Version:ShowVersionWindow(isTest)
    if not self.versionFrame then
        -- 1. Create Frame
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Desolate Loot Council - Versions")
        frame:SetCallback("OnClose", function(widget)
            AceGUI:Release(widget)
            self.versionFrame = nil
            self.scrollFrame = nil
        end)
        frame:SetLayout("Fill")
        frame:SetWidth(300)
        frame:SetHeight(350)
        self.versionFrame = frame

        -- [NEW] Position Persistence
        DesolateLootcouncil:RestoreFramePosition(frame, "Version")
        local function SavePos(f)
            DesolateLootcouncil:SaveFramePosition(f, "Version")
        end
        local rawFrame = (frame --[[@as any]]).frame
        rawFrame:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            SavePos(frame)
        end)
        rawFrame:SetScript("OnHide", function() SavePos(frame) end)
        DesolateLootcouncil.Persistence:ApplyCollapseHook(frame, "Version")

        -- 2. Container (Scroll)
        ---@type AceGUIScrollFrame
        local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
        scroll:SetLayout("List")
        frame:AddChild(scroll)
        self.scrollFrame = scroll
    end

    self.versionFrame:Show()
    self:UpdateVersionList(isTest)
end

function UI_Version:UpdateVersionList(isTest)
    if not self.scrollFrame then return end
    self.scrollFrame:ReleaseChildren()
    local scroll = self.scrollFrame --[[@as AceGUIScrollFrame]]

    -- 3. Gather Data
    local roster = {}
    local rosterMap = {}

    -- Helper to add unique
    local function AddEntry(name, class, version)
        if not rosterMap[name] then
            local entry = { name = name, class = class, version = version }
            table.insert(roster, entry)
            rosterMap[name] = entry
        end
    end

    -- Add Self
    AddEntry(UnitName("player"), select(2, UnitClassBase("player")), DesolateLootcouncil.version)

    -- Add Group Members
    if IsInRaid() then
        for i = 1, 40 do
            local name = GetRaidRosterInfo(i)
            if name then
                local filename = select(2, UnitClassBase(name))
                AddEntry(name, filename, nil)
            end
        end
    elseif IsInGroup() then
        local members = GetNumGroupMembers()
        if members > 0 then
            -- Loop including player
            for i = 1, members - 1 do
                local unit = "party" .. i
                if UnitExists(unit) then
                    local name = UnitName(unit)
                    local filename = select(2, UnitClassBase(unit))
                    AddEntry(name, filename, nil)
                end
            end
        end
    end

    -- Merge Active Addon Users (Sim / Out of Group)
    if DesolateLootcouncil.activeAddonUsers then
        for name, _ in pairs(DesolateLootcouncil.activeAddonUsers) do
            if not rosterMap[name] then
                -- Try to guess class or unknown
                local class = "PRIEST"   -- Default/Unknown color
                if UnitExists(name) then -- Might be visible but not in group?
                    class = select(2, UnitClassBase(name))
                end
                AddEntry(name, class, nil)
            end
        end
    end

    -- Fetch Versions from Comm
    ---@type Comm
    local Comm = DesolateLootcouncil:GetModule("Comm") --[[@as Comm]]
    local highestVerStr = "0.0.0"

    if Comm then
        -- Refresh logic happens on button click usually, ensuring versions are fresh requires a ping.
        -- We won't ping here to avoid loops, purely read.

        -- Map existing data
        for _, entry in ipairs(roster) do
            if entry.name == UnitName("player") then
                -- Already set
            else
                -- Fix: Use direct table access as GetPlayerVersion is missing
                local ver = Comm.playerVersions and Comm.playerVersions[entry.name]
                entry.version = ver
            end
        end
    end

    -- Test Data Injection
    if isTest then
        AddEntry("OutdatedPlayer", "WARRIOR", "0.0.1")
        AddEntry("MissingPlayer", "MAGE", nil)
        AddEntry("FuturePlayer", "ROGUE", "9.9.9")
    end

    -- 4. Calculate Highest
    for _, entry in ipairs(roster) do
        if entry.version then
            -- If entry.version > highestVerStr
            if CompareSemVer(entry.version, highestVerStr) then
                highestVerStr = entry.version
            end
        end
    end

    -- 5. Render
    ---@type AceGUILabel
    local header = AceGUI:Create("Label") --[[@as AceGUILabel]]
    header:SetText("Highest Found Version: " .. highestVerStr)
    header:SetFontObject(GameFontNormalLarge)
    scroll:AddChild(header)

    ---@type AceGUILabel
    local spacer = AceGUI:Create("Label") --[[@as AceGUILabel]]
    spacer:SetText(" ")
    scroll:AddChild(spacer)

    table.sort(roster, function(a, b) return a.name < b.name end)

    for _, entry in ipairs(roster) do
        ---@type AceGUISimpleGroup
        local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
        group:SetLayout("Flow")
        group:SetFullWidth(true)

        ---@type AceGUILabel
        local nameLabel = AceGUI:Create("Label") --[[@as AceGUILabel]]
        local color = entry.class and RAID_CLASS_COLORS[entry.class] or { r = 1, g = 1, b = 1 }
        nameLabel:SetText(entry.name)
        if RAID_CLASS_COLORS[entry.class] then
            nameLabel:SetColor(color.r, color.g, color.b)
        else
            nameLabel:SetColor(0.7, 0.7, 0.7) -- Grey for unknown
        end
        nameLabel:SetWidth(150)
        group:AddChild(nameLabel)

        ---@type AceGUILabel
        local verLabel = AceGUI:Create("Label") --[[@as AceGUILabel]]
        local ver = entry.version

        -- Override for Sim Data if present in activeAddonUsers but no version sent
        if not ver and DesolateLootcouncil.activeAddonUsers[entry.name] and not isTest then
            -- Determine if we treat "Active but no version" as something special?
            -- For now, consistent with logic:
        end

        if not ver then
            verLabel:SetText("Not Installed / Missing")
            verLabel:SetColor(0.5, 0.5, 0.5) -- Gray
        else
            -- Check if ver >= highest (Current)
            -- Equivalent to: NOT (highest > ver)
            if not CompareSemVer(highestVerStr, ver) then
                verLabel:SetText(ver .. " (Current)")
                verLabel:SetColor(0, 1, 0) -- Green
            else
                verLabel:SetText(ver .. " (Outdated)")
                verLabel:SetColor(1, 0, 0) -- Red
            end
        end
        verLabel:SetWidth(200)
        group:AddChild(verLabel)

        scroll:AddChild(group)
    end

    ---@type AceGUIButton
    local btnRefresh = AceGUI:Create("Button") --[[@as AceGUIButton]]
    btnRefresh:SetText("Refresh / Ping")
    btnRefresh:SetWidth(150)
    btnRefresh:SetCallback("OnClick", function()
        ---@type Comm
        local C = DesolateLootcouncil:GetModule("Comm")
        if C then C:SendVersionCheck() end
        -- Update UI
        self:UpdateVersionList(isTest)
    end)
    scroll:AddChild(btnRefresh)
end
