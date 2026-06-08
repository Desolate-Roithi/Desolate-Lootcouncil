local _, AT = ...
if AT.abortLoad then return end

---@class UI_EJLootImport : AceModule
local UI_EJLootImport = DesolateLootcouncil:NewModule("UI_EJLootImport", "AceEvent-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local function GetDefaultListIndex(itemID)
    local savedList = DesolateLootcouncil.API:GetItemCategory(itemID)
    if savedList then
        local db = DesolateLootcouncil.db.profile
        for idx, list in ipairs(db.PriorityLists or {}) do
            if list.name == savedList then
                return idx
            end
        end
    end
    return 0
end

local function HookEncounterJournal()
    if not EncounterJournal then return end

    hooksecurefunc("EncounterJournal_DisplayInstance", function(instanceID, noButton)
        UI_EJLootImport:UpdateEJButtons()
    end)

    hooksecurefunc("EncounterJournal_DisplayEncounter", function(encounterID, noButton)
        UI_EJLootImport:UpdateEJButtons()
    end)

    hooksecurefunc("EncounterJournal_SetTab", function(tabType)
        UI_EJLootImport:UpdateEJButtons()
    end)

    UI_EJLootImport:CreateEJButton()
end

function UI_EJLootImport:OnEnable()
    self:RegisterMessage("DLC_OFFICER_FLAG_CHANGED", function()
        self:UpdateEJButtons()
    end)

    if C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
        HookEncounterJournal()
    else
        self:RegisterEvent("ADDON_LOADED", function(_, name)
            if name == "Blizzard_EncounterJournal" then
                HookEncounterJournal()
            end
        end)
    end
end

local function OnEJAddTooltipEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(L["Add all loot from this boss/raid to the import staging area."], 1, 1, 1)
    GameTooltip:AddLine(L["Officer only."], 1, 0, 0)
    GameTooltip:Show()
end

local function OnEJAddTooltipLeave()
    GameTooltip:Hide()
end

function UI_EJLootImport:CreateEJButton()
    if self.ejButton then return end
    if not EncounterJournal or not EncounterJournal.encounter or not EncounterJournal.encounter.info or not EncounterJournal.encounter.info.LootContainer then return end

    local LootContainer = EncounterJournal.encounter.info.LootContainer
    local btn = CreateFrame("Button", "DLC_EJAddAllToIMButton", LootContainer, "UIPanelButtonTemplate")
    btn:SetSize(50, 50)
    btn:SetText(L["DLC"])
    btn:SetPoint("TOPRIGHT", LootContainer, "TOPRIGHT", 52, 60)
    btn:SetScript("OnClick", function()
        if not DesolateLootcouncil:AmIOfficerOrLM() then return end
        self:OpenStagingWindow()
    end)
    btn:SetFrameLevel(LootContainer:GetFrameLevel() + 10)
    btn:SetScript("OnEnter", OnEJAddTooltipEnter)
    btn:SetScript("OnLeave", OnEJAddTooltipLeave)
    self.ejButton = btn
    self:UpdateEJButtons()
end

function UI_EJLootImport:UpdateEJButtons()
    if not self.ejButton then
        self:CreateEJButton()
    end
    if not self.ejButton then return end

    local show = EncounterJournal and EncounterJournal.encounter and EncounterJournal.encounter.info and
        EncounterJournal.encounter.info.LootContainer:IsShown()
    local isOfficer = DesolateLootcouncil:AmIOfficerOrLM()
    if show and isOfficer then
        self.ejButton:Show()
    else
        self.ejButton:Hide()
    end
end

function UI_EJLootImport:OpenStagingWindow()
    local numLoot = EJ_GetNumLoot()
    if not numLoot or numLoot == 0 then
        DesolateLootcouncil:Print(L["No loot found for this boss."])
        return
    end

    local items = {}
    local seen = {}
    for i = 1, numLoot do
        local itemInfo = C_EncounterJournal.GetLootInfoByIndex(i)
        if itemInfo and itemInfo.itemID then
            if not seen[itemInfo.itemID] then
                seen[itemInfo.itemID] = true
                table.insert(items, {
                    itemID = itemInfo.itemID,
                    link = itemInfo.link or ("item:" .. itemInfo.itemID),
                    icon = itemInfo.icon or 134400,
                    name = itemInfo.name or "Unknown Item"
                })
            end
        end
    end

    self:ShowStagingWindow(items)
end

function UI_EJLootImport:ShowStagingWindow(items)
    if not DesolateLootcouncil:AmIOfficerOrLM() then return end

    self.itemsStaged = items
    for _, item in ipairs(self.itemsStaged) do
        item.listIndex = GetDefaultListIndex(item.itemID)
    end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.frame then
        local frame = NativeGUI:CreateWindow("DLCEJLootStagingFrame", L["DLC Loot Import"], "EJLootImport")
        frame:SetSize(520, 400)
        self.frame = frame

        DesolateLootcouncil:MakeMovableWithSave(frame, "EJLootImport")

        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(frame, -50, -46)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent

        local footer = CreateFrame("Frame", nil, frame)
        footer:SetHeight(38)
        footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 6)
        footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 6)
        self.footer = footer

        local cancelBtn = NativeGUI:CreateButton(footer, L["Cancel"], 90, 24, "Pass")
        cancelBtn:SetPoint("BOTTOMLEFT", 0, 0)
        cancelBtn:SetScript("OnClick", function() frame:Hide() end)
        self.cancelBtn = cancelBtn

        local addBtn = NativeGUI:CreateButton(footer, L["Add to IM"], 110, 24, "Bid")
        addBtn:SetPoint("BOTTOMRIGHT", 0, 0)
        addBtn:SetScript("OnClick", function() self:CommitImport() end)
        self.addBtn = addBtn

        local summaryLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summaryLabel:SetPoint("LEFT", cancelBtn, "RIGHT", 10, 0)
        summaryLabel:SetPoint("RIGHT", addBtn, "LEFT", -10, 0)
        summaryLabel:SetJustifyH("CENTER")
        summaryLabel:SetTextColor(0.8, 0.8, 0.8)
        self.summaryLabel = summaryLabel

        self.rowPool = {}
    end

    self.frame:Show()
    self:RefreshStagingWindow()
end

function UI_EJLootImport:RefreshStagingWindow()
    if not self.frame or not self.frame:IsShown() then return end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    NativeGUI:ResetRowPool(self.rowPool)

    local topOffset = 0
    local rowHeight = 36
    local visibleCount = 0

    local listOptions = {}
    listOptions[0] = L["— Skip —"]
    for idx, list in ipairs(DesolateLootcouncil.API:GetPriorityLists()) do
        listOptions[idx] = list.name
    end

    local listsTouched = {}
    local importCount = 0

    for i, item in ipairs(self.itemsStaged) do
        visibleCount = visibleCount + 1

        local row = NativeGUI:AcquireRow(self.rowPool, visibleCount, self.scrollContent, false)
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
        row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)
        row.itemData = item

        NativeGUI:SetupItemIconButton(row, item, 24, 8, 0)

        if not row.btnRemove then
            row.btnRemove = NativeGUI:CreateButton(row, "X", 24, 20, "Stop")
        end
        row.btnRemove:ClearAllPoints()
        row.btnRemove:SetPoint("RIGHT", -8, 0)
        row.btnRemove:Show()
        row.btnRemove:SetScript("OnClick", function()
            table.remove(self.itemsStaged, i)
            self:RefreshStagingWindow()
        end)

        if not row.dropList then
            row.dropList, row.dropListBtn = NativeGUI:CreateDropdown(row, nil, 130, listOptions, nil, function(val)
                if row.itemData then
                    row.itemData.listIndex = val
                end
                self:RefreshStagingWindow()
            end)
        end
        row.dropList:SetList(listOptions)
        row.dropList:ClearAllPoints()
        row.dropList:SetPoint("RIGHT", row.btnRemove, "LEFT", -6, 4)
        row.dropList:Show()
        row.dropList:SetValue(item.listIndex or 0)

        if not row.linkLabel then
            row.linkLabel = NativeGUI:CreateLinkLabel(row)
        end
        row.linkLabel:ClearAllPoints()
        row.linkLabel:SetPoint("LEFT", row.itemIcon, "RIGHT", 8, 0)
        row.linkLabel:SetPoint("RIGHT", row.dropList, "LEFT", -10, 0)
        row.linkLabel:Show()

        local _, properLink = C_Item.GetItemInfo(item.link or item.itemID)
        if not properLink then
            row.linkLabel.text:SetText(item.name or L["Loading..."])
            row.itemIcon.texture:SetTexture(item.icon or 134400)
            local itemObj = Item:CreateFromItemID(item.itemID)
            if not itemObj:IsItemEmpty() then
                itemObj:ContinueOnItemLoad(function()
                    if self.frame and self.frame:IsShown() then
                        self:RefreshStagingWindow()
                    end
                end)
            end
        else
            row.linkLabel.text:SetText(properLink)
            row.itemIcon.texture:SetTexture(C_Item.GetItemIconByID(item.itemID) or 134400)
        end

        row.linkLabel:SetScript("OnClick", function() row.itemIcon:GetScript("OnClick")(row.itemIcon) end)
        row.linkLabel:SetScript("OnEnter", function() row.itemIcon:GetScript("OnEnter")(row.itemIcon) end)
        row.linkLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if item.listIndex and item.listIndex > 0 then
            importCount = importCount + 1
            listsTouched[item.listIndex] = true
        end

        topOffset = topOffset + rowHeight + 6
    end

    self.scrollContent:SetHeight(topOffset + 10)

    local uniqueListsCount = 0
    for _ in pairs(listsTouched) do
        uniqueListsCount = uniqueListsCount + 1
    end
    self.summaryLabel:SetText(string.format(L["%d items staged across %d lists"], importCount, uniqueListsCount))

    self.addBtn:SetEnabled(importCount > 0)
end

function UI_EJLootImport:CommitImport()
    local importBatch = {}
    for _, item in ipairs(self.itemsStaged) do
        if item.listIndex and item.listIndex > 0 then
            table.insert(importBatch, { itemID = item.itemID, listIndex = item.listIndex })
        end
    end

    if #importBatch > 0 then
        DesolateLootcouncil.API:AddManagedItemBatch(importBatch)
        DesolateLootcouncil:Print(string.format("Successfully imported %d items to Item Manager.", #importBatch))
    end

    self.frame:Hide()
end
