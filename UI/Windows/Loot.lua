local _, AT = ...
if AT.abortLoad then return end

---@class UI_Loot : AceModule, AceTimer-3.0
local UI_Loot = DesolateLootcouncil:NewModule("UI_Loot", "AceConsole-3.0", "AceTimer-3.0", "AceEvent-3.0")

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
        local frame = NativeGUI:CreateWindow("DLCLootFrame", "Desolate Loot Council", 400, 500, "Loot")
        self.lootFrame = frame
        self.rowPool = {}

        -- Top buttons: Clear & Refresh
        local clearBtn = NativeGUI:CreateButton(frame, "Clear Session", 175, 24, "Pass")
        clearBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
        clearBtn:SetScript("OnClick", function()
            DesolateLootcouncil.API:ClearLootBacklog()
            self:ShowLootWindow(nil)
        end)
        self.clearBtn = clearBtn

        local refreshBtn = NativeGUI:CreateButton(frame, "Refresh Connections", 175, 24, "Pass")
        refreshBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -42)
        self.refreshBtn = refreshBtn

        -- Pinned footer: Start Bidding
        local startBtn = NativeGUI:CreateButton(frame, "Start Bidding", 200, 24, "Bid")
        startBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
        startBtn:SetScript("OnClick", function()
            DesolateLootcouncil.API:StartSession(self.activeLootTable)
        end)
        self.startBtn = startBtn

        -- Connection indicator light
        local light = frame:CreateTexture(nil, "OVERLAY")
        light:SetSize(12, 12)
        light:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -45, -16)
        light:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        self.statusLight = light

        local ttFrame = CreateFrame("Button", nil, frame)
        ttFrame:SetAllPoints(light)
        ttFrame:SetFrameLevel(frame:GetFrameLevel() + 20)
        ttFrame:SetScript("OnEnter", function()
            GameTooltip:SetOwner(ttFrame, "ANCHOR_BOTTOMLEFT")
            local active = DesolateLootcouncil:GetActiveUserCount()
            local total = GetNumGroupMembers()
            if total == 0 then total = 1; active = 1 end
            GameTooltip:AddLine(string.format("Addon Connection: [%d] / [%d]", active, total), 1, 1, 1)
            GameTooltip:Show()
        end)
        ttFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        refreshBtn:SetScript("OnClick", function()
            local success = DesolateLootcouncil.API:PingVersionCheck()
            if success then
                DesolateLootcouncil:DLC_Log("Triggering manual connection refresh...")
                refreshBtn:SetEnabled(false)
                refreshBtn:SetText("Pinging...")
            end
        end)

        self.refreshTimer = self:ScheduleRepeatingTimer(function()
            if not self.lootFrame:IsShown() then return end
            local rem = DesolateLootcouncil.API:GetVersionCheckCooldown()
            if rem > 0 then
                refreshBtn:SetText(string.format("Refresh (%.0fs)", rem))
                refreshBtn:SetEnabled(false)
            else
                refreshBtn:SetText("Refresh Connections")
                refreshBtn:SetEnabled(true)
            end

            -- Update indicator light
            local activeC = DesolateLootcouncil:GetActiveUserCount()
            local totalC = GetNumGroupMembers()
            if totalC == 0 then totalC = 1; activeC = 1 end
            local ra, ga, ba = 1, 0, 0
            if activeC >= totalC then ra, ga, ba = 0, 1, 0
            elseif activeC > 1 then ra, ga, ba = 1, 1, 0 end
            self.statusLight:SetVertexColor(ra, ga, ba)
        end, 1)

        frame:HookScript("OnHide", function()
            if self.refreshTimer then
                self:CancelTimer(self.refreshTimer)
                self.refreshTimer = nil
            end
        end)
    end

    self.activeLootTable = lootTable
    self.lootFrame:Show()

    for _, r in ipairs(self.rowPool) do
        r:Hide()
        r:ClearAllPoints()
    end

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.lootFrame, -75, -46)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    self.scrollFrame:Show()
    self.scrollContent:Show()

    local catList = {}
    local listIndexMap = {}
    for idx, list in ipairs(DesolateLootcouncil.API:GetPriorityLists()) do
        catList[list.name] = list.name
        listIndexMap[list.name] = idx
    end
    catList["Junk/Pass"] = "Junk/Pass"

    local topOffset = 0
    local rowHeight = 44
    local count = 0

    for i = #lootTable, 1, -1 do
        count = count + 1
        local data = lootTable[i]
        local link = data.link
        local guid = data.sourceGUID or link

        if not self.rowPool[count] then
            self.rowPool[count] = NativeGUI:CreateRowContainer(self.scrollContent, false)
        end
        local row = self.rowPool[count]
        row:Show()
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
        row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

        -- Icon
        if not row.itemIcon then
            local icon = CreateFrame("Button", nil, row)
            icon:SetSize(28, 28)
            icon:SetPoint("LEFT", 8, 0)
            local tex = icon:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints()
            icon.texture = tex
            row.itemIcon = icon
        end
        row.itemIcon.texture:SetTexture(data.texture or (data.itemID and C_Item.GetItemIconByID(data.itemID)) or 134400)

        local function ShowTip()
            GameTooltip:SetOwner(row.itemIcon, "ANCHOR_CURSOR")
            if data.link then GameTooltip:SetHyperlink(data.link) else GameTooltip:SetItemByID(data.itemID) end
            GameTooltip:Show()
        end
        row.itemIcon:SetScript("OnClick", ShowTip)
        row.itemIcon:SetScript("OnEnter", ShowTip)
        row.itemIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Remove Button (X) (created early for right anchoring)
        if not row.removeBtn then
            local btn = NativeGUI:CreateButton(row, "X", 26, 24, "Stop")
            row.removeBtn = btn
        end
        row.removeBtn:ClearAllPoints()
        row.removeBtn:SetPoint("RIGHT", -8, 0)
        row.removeBtn:Show()
        row.removeBtn:SetScript("OnClick", function()
            for idx = #lootTable, 1, -1 do
                local entry = lootTable[idx]
                if (entry.sourceGUID or entry.link) == guid then
                    table.remove(lootTable, idx)
                    break
                end
            end
            DesolateLootcouncil:DLC_Log("Removed " .. (link or "item") .. " from session.")
            self:ShowLootWindow(lootTable)
        end)

        -- Category Dropdown
        if not row.catDrop then
            -- We create a custom native dropdown
            local dropContainer, dropBtn = NativeGUI:CreateDropdown(row, nil, 110, catList, nil, function(value)
                data.category = value
                local idx = listIndexMap[value]
                if idx then
                    DesolateLootcouncil.API:SetItemCategory(data.itemID, idx)
                    DesolateLootcouncil:DLC_Log("Category updated to: " .. value)
                elseif value == "Junk/Pass" then
                    DesolateLootcouncil.API:UnassignItem(data.itemID)
                end
            end)
            row.catDrop = dropContainer
            row.catDropBtn = dropBtn
        end
        row.catDrop:ClearAllPoints()
        row.catDrop:SetPoint("RIGHT", row.removeBtn, "LEFT", -6, 12) -- Y offset compensates for dropdown container label layout
        row.catDrop:Show()

        local savedCat = DesolateLootcouncil.API:GetItemCategory(data.itemID) or data.category or "Junk/Pass"
        data.category = savedCat
        row.catDrop:SetValue(savedCat)

        -- Link Label (sandwiched dynamically in-between LEFT and RIGHT anchors)
        if not row.itemLabel then
            local btn = CreateFrame("Button", nil, row)
            btn:SetHeight(20)
            local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            txt:SetPoint("LEFT", 0, 0)
            txt:SetPoint("RIGHT", 0, 0)
            txt:SetJustifyH("LEFT")
            btn.text = txt
            row.itemLabel = btn
        end
        row.itemLabel:ClearAllPoints()
        row.itemLabel:SetPoint("LEFT", row.itemIcon, "RIGHT", 8, 0)
        row.itemLabel:SetPoint("RIGHT", row.catDrop, "LEFT", -10, 0)
        row.itemLabel:Show()

        local _, properLink = C_Item.GetItemInfo(data.link or data.itemID)
        if not properLink then
            local itemObj = Item:CreateFromItemID(data.itemID)
            if not itemObj:IsItemEmpty() then
                itemObj:ContinueOnItemLoad(function()
                    if self.lootFrame and self.lootFrame:IsShown() then
                        self:ShowLootWindow(lootTable)
                    end
                end)
            end
            row.itemLabel.text:SetText(L["Loading..."])
        else
            row.itemLabel.text:SetText(properLink)
            row.itemIcon.texture:SetTexture(C_Item.GetItemIconByID(data.itemID) or 134400)
        end
        row.itemLabel:SetScript("OnClick", ShowTip)
        row.itemLabel:SetScript("OnEnter", ShowTip)
        row.itemLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)

        topOffset = topOffset + rowHeight + 8
    end

    self.scrollContent:SetHeight(topOffset + 10)
    DesolateLootcouncil:DLC_Log(string.format("Loot Window Populated with %d items", count))
end

function UI_Loot:OnEnable()
    self:RegisterMessage("DLC_LOOT_WINDOW_UPDATE", "OnLootWindowUpdate")
end

function UI_Loot:OnLootWindowUpdate(eventName, lootTable)
    self:ShowLootWindow(lootTable)
end
