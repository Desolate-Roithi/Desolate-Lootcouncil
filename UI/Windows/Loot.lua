local _, AT = ...
if AT.abortLoad then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

---@class UI_Loot : AceModule, AceTimer-3.0
local UI_Loot = DesolateLootcouncil:NewModule("UI_Loot", "AceConsole-3.0", "AceTimer-3.0", "AceEvent-3.0")

-- Local helper functions to keep nesting flat
local function OnClearSessionClicked()
    DesolateLootcouncil.API:ClearLootBacklog()
    UI_Loot:ShowLootWindow(nil)
end

local function OnStartBiddingClicked()
    DesolateLootcouncil.API:StartSession(UI_Loot.activeLootTable)
end

local function OnConnectionTooltipEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    local total = GetNumGroupMembers()
    if total == 0 then total = 1 end

    local simCount = DesolateLootcouncil.API and DesolateLootcouncil.API.GetSimulationCount and DesolateLootcouncil.API:GetSimulationCount() or 0
    if simCount > 0 then
        total = total + simCount
    end

    local active = DesolateLootcouncil:GetActiveUserCount()
    if active > total then active = total end

    GameTooltip:AddLine(string.format(L["Addon Connection: [%d] / [%d]"], active, total), 1, 1, 1)

    local missing = (DesolateLootcouncil.GetMissingAddonMembers and DesolateLootcouncil:GetMissingAddonMembers()) or {}
    if #missing > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("|cffff4444" .. L["Missing Addon (%d):"] .. "|r", #missing), 1, 0.5, 0.5)
        for _, name in ipairs(missing) do
            local disp = DesolateLootcouncil:GetDisplayName(name) or name
            GameTooltip:AddLine("  • " .. disp, 0.9, 0.7, 0.7)
        end
    elseif active >= total then
        GameTooltip:AddLine("|cff00ff00" .. L["All group members connected."] .. "|r", 0.5, 1, 0.5)
    end
    GameTooltip:Show()
end

local function OnConnectionTooltipLeave()
    GameTooltip:Hide()
end

local function OnRefreshConnectionsClicked()
    local success = DesolateLootcouncil.API:SendVersionCheck()
    if success then
        DesolateLootcouncil:DLC_Log("Triggering manual connection refresh...")
        UI_Loot.refreshBtn:SetEnabled(false)
        UI_Loot.refreshBtn:SetText(L["Pinging..."])
    end
end

local function OnTimerTick()
    if not UI_Loot.lootFrame:IsShown() then return end
    local rem = DesolateLootcouncil.API:GetVersionCheckCooldown()
    if rem > 0 then
        UI_Loot.refreshBtn:SetText(string.format(L["Refresh (%.0fs)"], rem))
        UI_Loot.refreshBtn:SetEnabled(false)
    else
        UI_Loot.refreshBtn:SetText(L["Refresh Connections"])
        UI_Loot.refreshBtn:SetEnabled(true)
    end

    -- Update indicator light
    local status = DesolateLootcouncil.API and DesolateLootcouncil.API.GetGroupConnectionStatus and DesolateLootcouncil.API:GetGroupConnectionStatus()
    local ra, ga, ba = 1, 0, 0 -- Red: missing addon

    local hasOutdated = (status and status.outdated and #status.outdated > 0)

    local playerVersions = DesolateLootcouncil.API and DesolateLootcouncil.API.GetPlayerVersions and DesolateLootcouncil.API:GetPlayerVersions()
    if playerVersions then
        local rosterVersions = {}
        local myName = UnitName("player")
        local myVer = DesolateLootcouncil.version or "1.0.0"
        if myName then
            rosterVersions[myName] = playerVersions[myName] or myVer
        end

        if IsInRaid() then
            local members = GetNumGroupMembers()
            if members and members > 0 then
                for i = 1, members do
                    local name = GetRaidRosterInfo(i)
                    if name and playerVersions[name] then
                        rosterVersions[name] = playerVersions[name]
                    end
                end
            end
        elseif IsInGroup() then
            local members = GetNumGroupMembers()
            if members > 0 then
                for i = 1, members - 1 do
                    local unit = "party" .. i
                    if UnitExists(unit) then
                        local name = UnitName(unit)
                        if name and playerVersions[name] then
                            rosterVersions[name] = playerVersions[name]
                        end
                    end
                end
            end
        end

        local sims = DesolateLootcouncil.API and DesolateLootcouncil.API.GetSimulationRoster and DesolateLootcouncil.API:GetSimulationRoster()
        if sims then
            for _, name in ipairs(sims) do
                if playerVersions[name] then
                    rosterVersions[name] = playerVersions[name]
                end
            end
        end

        local highestVerStr = (status and status.highestVersion) or myVer
        for _, ver in pairs(rosterVersions) do
            if ver and AT and AT.CompareSemVer and AT.CompareSemVer(ver, highestVerStr) then
                highestVerStr = ver
            end
        end
        for _, ver in pairs(rosterVersions) do
            if ver and AT and AT.CompareSemVer and AT.CompareSemVer(highestVerStr, ver) then
                hasOutdated = true
                break
            end
        end
    end

    local activeC = DesolateLootcouncil.GetActiveUserCount and DesolateLootcouncil:GetActiveUserCount() or (status and status.active or 1)
    local totalC = GetNumGroupMembers()
    if totalC == 0 then totalC = 1 end
    local simCount = (DesolateLootcouncil.API and DesolateLootcouncil.API.GetSimulationCount and DesolateLootcouncil.API:GetSimulationCount()) or 0
    if simCount > 0 then totalC = totalC + simCount end

    if activeC >= totalC then
        if hasOutdated then
            ra, ga, ba = 1, 1, 0 -- Yellow: some are out of date
        else
            ra, ga, ba = 0, 1, 0 -- Green: all up-to-date
        end
    end
    UI_Loot.statusLight:SetVertexColor(ra, ga, ba)
end

local function OnLootFrameHide()
    if UI_Loot.refreshTimer then
        UI_Loot:CancelTimer(UI_Loot.refreshTimer)
        UI_Loot.refreshTimer = nil
    end
end

local function OnRemoveLootClicked(lootTable, guid, link)
    for idx = #lootTable, 1, -1 do
        local entry = lootTable[idx]
        if (entry.sourceGUID or entry.link) == guid then
            table.remove(lootTable, idx)
            break
        end
    end
    DesolateLootcouncil:DLC_Log("Removed " .. (link or "item") .. " from session.")
    UI_Loot:ShowLootWindow(lootTable)
end

local function OnCategorySelected(row, value)
    if row.catCallback then row.catCallback(value) end
end

local function OnCategoryCallback(data, listIndexMap, value)
    data.category = value
    data.manualCategory = true
    local idx = listIndexMap[value]
    if idx then
        DesolateLootcouncil.API:SetItemCategory(data.itemID, idx)
        DesolateLootcouncil:DLC_Log("Category updated to: " .. value)
    elseif value == "Junk/Pass" then
        DesolateLootcouncil.API:UnassignItem(data.itemID)
    end
end

local function OnLootItemLoadCallback(lootTable)
    if UI_Loot.lootFrame and UI_Loot.lootFrame:IsShown() then
        UI_Loot:ShowLootWindow(lootTable)
    end
end

function UI_Loot:ShowLootWindow(lootTable)
    if self.refreshTimer then
        self:CancelTimer(self.refreshTimer)
        self.refreshTimer = nil
    end

    if not DesolateLootcouncil.API:IsLootMaster() then
        if self.lootFrame then self.lootFrame:Hide() end
        self:Print("Error: Only the Loot Master can open the Loot Window.")
        return
    end

    if not lootTable or #lootTable == 0 then
        if self.lootFrame then self.lootFrame:Hide() end
        return
    end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.lootFrame then
        local frame = NativeGUI:CreateWindow("DLCLootFrame", "Desolate Loot Council", "Loot")
        self.lootFrame = frame
        self.rowPool = {}

        -- Top buttons: Clear & Refresh
        local clearBtn = NativeGUI:CreateButton(frame, "Clear Session", 175, 24, "Pass")
        clearBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
        clearBtn:SetScript("OnClick", OnClearSessionClicked)
        self.clearBtn = clearBtn

        local refreshBtn = NativeGUI:CreateButton(frame, L["Refresh Connections"], 175, 24, "Pass")
        refreshBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -42)
        self.refreshBtn = refreshBtn

        -- Pinned footer: Start Bidding
        local startBtn = NativeGUI:CreateButton(frame, "Start Bidding", 200, 24, "Bid")
        startBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
        startBtn:SetScript("OnClick", OnStartBiddingClicked)
        self.startBtn = startBtn

        -- Connection indicator light
        local light = frame:CreateTexture(nil, "OVERLAY")
        light:SetSize(12, 12)
        light:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -55, -16)
        light:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        self.statusLight = light

        local ttFrame = CreateFrame("Button", nil, frame)
        ttFrame:SetAllPoints(light)
        ttFrame:SetFrameLevel(frame:GetFrameLevel() + 20)
        ttFrame:SetScript("OnEnter", OnConnectionTooltipEnter)
        ttFrame:SetScript("OnLeave", OnConnectionTooltipLeave)

        refreshBtn:SetScript("OnClick", OnRefreshConnectionsClicked)

        frame:HookScript("OnHide", OnLootFrameHide)

        frame.OnCollapse = function()
            if self.clearBtn then self.clearBtn:Hide() end
            if self.refreshBtn then self.refreshBtn:Hide() end
            if self.startBtn then self.startBtn:Hide() end
            if self.scrollFrame then self.scrollFrame:Hide() end
        end
        frame.OnExpand = function()
            self:ShowLootWindow(self.activeLootTable)
        end
    end

    self.activeLootTable = lootTable
    self.lootFrame:Show()

    if not self.refreshTimer then
        -- Seed local player once so the connection light counts us immediately
        DesolateLootcouncil.API:SeedSelf()
        self.refreshTimer = self:ScheduleRepeatingTimer(OnTimerTick, 1)
        OnTimerTick()
    end

    NativeGUI:ResetRowPool(self.rowPool)

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.lootFrame, -75, -46)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    if self.lootFrame.isCollapsed then
        if self.clearBtn then self.clearBtn:Hide() end
        if self.refreshBtn then self.refreshBtn:Hide() end
        if self.startBtn then self.startBtn:Hide() end
        if self.scrollFrame then self.scrollFrame:Hide() end
    else
        if self.clearBtn then self.clearBtn:Show() end
        if self.refreshBtn then self.refreshBtn:Show() end
        if self.startBtn then self.startBtn:Show() end
        if self.scrollFrame then self.scrollFrame:Show() end
        self.scrollContent:Show()
    end

    local catList = {}
    local listIndexMap = {}
    for idx, list in ipairs(DesolateLootcouncil.API:GetPriorityLists()) do
        catList[list.name] = DesolateLootcouncil.API:GetLocalizedListName(list.name)
        listIndexMap[list.name] = idx
    end
    catList["Junk/Pass"] = L["Junk/Pass"] or "Junk/Pass"

    local topOffset = 0
    local rowHeight = 44
    local count = 0

    for i = #lootTable, 1, -1 do
        count = count + 1
        local data = lootTable[i]
        local link = data.link
        local guid = data.sourceGUID or link

        local row = NativeGUI:AcquireRow(self.rowPool, count, self.scrollContent, false)
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
        row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

        -- Icon
        NativeGUI:SetupItemIconButton(row, data, 28, 8, 0)

        -- Remove Button (X) (created early for right anchoring)
        if not row.removeBtn then
            row.removeBtn = NativeGUI:CreateButton(row, "X", 26, 24, "Stop")
        end
        row.removeBtn:ClearAllPoints()
        row.removeBtn:SetPoint("RIGHT", -8, 0)
        row.removeBtn:Show()
        row.removeBtn:SetScript("OnClick", function() OnRemoveLootClicked(lootTable, guid, link) end)

        -- Category Dropdown
        row.catCallback = function(value) OnCategoryCallback(data, listIndexMap, value) end

        if not row.catDrop then
            -- We create a custom native dropdown
            row.catDrop, row.catDropBtn = NativeGUI:CreateDropdown(row, nil, 110, catList, nil,
                function(value) OnCategorySelected(row, value) end)
        end
        row.catDrop:ClearAllPoints()
        row.catDrop:SetPoint("RIGHT", row.removeBtn, "LEFT", -6, 7) -- Y offset compensates for dropdown container label layout
        row.catDrop:Show()

        local savedCat = data.category
        if not data.manualCategory then
            local dbCat = DesolateLootcouncil.API:GetItemCategory(data.itemID)
            if dbCat and dbCat ~= "Junk/Pass" then
                savedCat = dbCat
            else
                savedCat = "Junk/Pass"
            end
        end
        savedCat = savedCat or "Junk/Pass"
        data.category = savedCat
        row.catDrop:SetValue(savedCat)

        -- Link Label (sandwiched dynamically in-between LEFT and RIGHT anchors)
        if not row.itemLabel then
            row.itemLabel = NativeGUI:CreateLinkLabel(row)
        end
        row.itemLabel:ClearAllPoints()
        row.itemLabel:SetPoint("LEFT", row.itemIcon, "RIGHT", 8, 0)
        row.itemLabel:SetPoint("RIGHT", row.catDrop, "LEFT", -10, 0)
        row.itemLabel:Show()

        local _, properLink = C_Item.GetItemInfo(data.link or data.itemID)
        if not properLink then
            local itemObj = Item:CreateFromItemID(data.itemID)
            local function LoadCb() OnLootItemLoadCallback(lootTable) end
            if not itemObj:IsItemEmpty() then itemObj:ContinueOnItemLoad(LoadCb) end
            row.itemLabel.text:SetText(L["Loading..."])
        else
            row.itemLabel.text:SetText(properLink)
            row.itemIcon.texture:SetTexture(C_Item.GetItemIconByID(data.itemID) or 134400)
        end
        row.itemLabel:SetScript("OnClick", function() row.itemIcon:GetScript("OnClick")(row.itemIcon) end)
        row.itemLabel:SetScript("OnEnter", function() row.itemIcon:GetScript("OnEnter")(row.itemIcon) end)
        row.itemLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)

        topOffset = topOffset + rowHeight + 8
    end

    self.scrollContent:SetHeight(topOffset + 10)
    DesolateLootcouncil:DLC_Log(string.format("Loot Window Populated with %d items", count))
end

function UI_Loot:OnEnable()
    self:RegisterMessage("DLC_LOOT_WINDOW_UPDATE", "OnLootWindowUpdate")
    self:RegisterMessage("DLC_SESSION_STOPPED", function()
        if self.lootFrame then self.lootFrame:Hide() end
    end)
end

function UI_Loot:OnLootWindowUpdate(eventName, lootTable)
    self:ShowLootWindow(lootTable)
end

if _G.DLC_TEST_MODE then
    UI_Loot.ParseSemVer = AT.ParseSemVer
    UI_Loot.CompareSemVer = AT.CompareSemVer
    UI_Loot.OnTimerTick = OnTimerTick
end
