local _, AT = ...
if AT.abortLoad then return end

---@class UI_ItemManager : AceModule
local UI_ItemManager = DesolateLootcouncil:NewModule("UI_ItemManager")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

-- Local helper functions
local OnItemInputEnter = function(edit)
    edit:ClearFocus()
    local text = edit:GetText()
    if text and text ~= "" and UI_ItemManager.tempList then
        DesolateLootcouncil.API:AddManagedItem(text, UI_ItemManager.tempList)
        edit:SetText("")
        UI_ItemManager:RefreshWindow()
    end
end

local OnTargetListChanged = function(value)
    UI_ItemManager.tempList = value
end

local OnAddClicked = function()
    local text = UI_ItemManager.itemEditBox:GetText()
    if text and text ~= "" and UI_ItemManager.tempList then
        DesolateLootcouncil.API:AddManagedItem(text, UI_ItemManager.tempList)
        UI_ItemManager.itemEditBox:SetText("")
        UI_ItemManager:RefreshWindow()
    end
end

local OnSyncRaidClicked = function()
    DesolateLootcouncil.API:SyncItemManagerToRaid()
    DesolateLootcouncil:Print(L["Item Manager lists synced to raid."])
end

local OnViewListChanged = function(value)
    UI_ItemManager.viewListKey = value
    UI_ItemManager:RefreshWindow()
end

local OnRemoveItemClicked = function(list, itemID)
    list.items[itemID] = nil
    DesolateLootcouncil:DLC_Log(string.format(L["Removed item ID: %s"], itemID))
    UI_ItemManager:RefreshWindow()
end

local OnLinkLabelClicked = function(itemLink)
    if itemLink then
        local chatbox = ChatEdit_ChooseBoxForSend()
        ChatEdit_ActivateChat(chatbox)
        chatbox:Insert(itemLink)
    end
end

local OnItemLoadCallback = function()
    if UI_ItemManager.frame and UI_ItemManager.frame:IsShown() then
        UI_ItemManager:RefreshWindow()
    end
end

local OnRowIconLeave = function()
    GameTooltip:Hide()
end

local ShowItemTooltip = function(iconBtn, itemLink, itemID)
    GameTooltip:SetOwner(iconBtn, "ANCHOR_CURSOR")
    if itemLink then
        GameTooltip:SetHyperlink(itemLink)
    else
        GameTooltip:SetItemByID(itemID)
    end
    GameTooltip:Show()
end

local PopulateRow = function(row, itemID, list)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    -- Fetch item information
    local name, itemLink, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
    if not itemLink then
        local itemObj = Item:CreateFromItemID(itemID)
        if not itemObj:IsItemEmpty() then itemObj:ContinueOnItemLoad(OnItemLoadCallback) end
        name = L["Loading..."]
        itemTexture = C_Item.GetItemIconByID(itemID)
    end

    -- Remove Button
    if not row.btnRemove then
        row.btnRemove = NativeGUI:CreateButton(row, L["Remove"], 70, 24, "Stop")
    end
    row.btnRemove:ClearAllPoints()
    row.btnRemove:SetPoint("RIGHT", -8, 0)
    row.btnRemove:Show()
    row.btnRemove:SetScript("OnClick", function() OnRemoveItemClicked(list, itemID) end)

    -- Icon
    if not row.iconBtn then
        row.iconBtn = CreateFrame("Button", nil, row)
        row.iconBtn:SetSize(24, 24)
        row.iconBtn:SetPoint("LEFT", 8, 0)
        row.iconBtn.texture = row.iconBtn:CreateTexture(nil, "BACKGROUND")
        row.iconBtn.texture:SetAllPoints()
    end
    row.iconBtn.texture:SetTexture(itemTexture or 134400)
    row.iconBtn:Show()

    local ShowTip = function() ShowItemTooltip(row.iconBtn, itemLink, itemID) end
    row.iconBtn:SetScript("OnClick", ShowTip)
    row.iconBtn:SetScript("OnEnter", ShowTip)
    row.iconBtn:SetScript("OnLeave", OnRowIconLeave)

    -- Link Label
    if not row.linkLabel then
        row.linkLabel = CreateFrame("Button", nil, row)
        row.linkLabel:SetHeight(20)
        row.linkLabel.text = row.linkLabel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.linkLabel.text:SetPoint("LEFT", 0, 0)
        row.linkLabel.text:SetPoint("RIGHT", 0, 0)
        row.linkLabel.text:SetJustifyH("LEFT")
    end
    row.linkLabel:ClearAllPoints()
    row.linkLabel:SetPoint("LEFT", row.iconBtn, "RIGHT", 8, 0)
    row.linkLabel:SetPoint("RIGHT", row.btnRemove, "LEFT", -10, 0)
    row.linkLabel.text:SetText(itemLink or name)
    row.linkLabel:Show()
    row.linkLabel:SetScript("OnClick", function() OnLinkLabelClicked(itemLink) end)
    row.linkLabel:SetScript("OnEnter", ShowTip)
    row.linkLabel:SetScript("OnLeave", OnRowIconLeave)
end

function UI_ItemManager:ShowItemManagerWindow()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.frame then
        local frame = NativeGUI:CreateWindow("DLCItemManagerFrame", L["Item Manager"], "ItemManager")
        self.frame = frame
        self.rowPool = {}
    end

    self.frame:Show()
    self:RefreshWindow()
end

function UI_ItemManager:RefreshWindow()
    if not self.frame then return end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local db = DesolateLootcouncil.API:GetItemManagerDB()
    local pNames = DesolateLootcouncil.API:GetPriorityListNames()
    local listNames = {}
    for i, name in ipairs(pNames) do listNames[i] = name end

    -- 1. EditBox Search/Input
    if not self.itemInput then
        local container, eb = NativeGUI:CreateEditBox(self.frame, L["Item Name/Link/ID"])
        container:SetWidth(180)
        container:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -42)
        eb:SetScript("OnEnterPressed", OnItemInputEnter)
        self.itemInput = container
        self.itemEditBox = eb
    end

    -- 2. Target list dropdown
    self.tempList = self.tempList or 1
    if not self.listDrop then
        local dropContainer = NativeGUI:CreateDropdown(self.frame, L["Target List"], 140, listNames, self.tempList, OnTargetListChanged)
        dropContainer:SetPoint("TOPLEFT", self.itemInput, "TOPRIGHT", 8, 0)
        self.listDrop = dropContainer
    else
        self.listDrop:SetList(listNames)
        self.listDrop:SetValue(self.tempList)
    end

    -- 3. Add button
    if not self.btnAdd then
        local btn = NativeGUI:CreateButton(self.frame, L["Add"], 60, 24, "Pass")
        btn:SetPoint("LEFT", self.listDrop, "RIGHT", 8, -8)
        btn:SetScript("OnClick", OnAddClicked)
        self.btnAdd = btn
    end

    -- 4. Sync Raid Button (LM/Assist Only)
    if DesolateLootcouncil:AmIRaidAssistOrLM() then
        if not self.btnSync then
            local btn = NativeGUI:CreateButton(self.frame, L["Sync Raid"], 90, 24, "Bid")
            btn:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -16, -58)
            btn:SetScript("OnClick", OnSyncRaidClicked)
            self.btnSync = btn
        end
        self.btnSync:Show()
    elseif self.btnSync then
        self.btnSync:Hide()
    end

    -- 5. Select list to view dropdown
    self.viewListKey = self.viewListKey or 1
    if not self.viewDrop then
        local dropContainer = NativeGUI:CreateDropdown(self.frame, L["Select List to View"], 220, listNames, self.viewListKey, OnViewListChanged)
        dropContainer:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -84)
        self.viewDrop = dropContainer
    else
        self.viewDrop:SetList(listNames)
        self.viewDrop:SetValue(self.viewListKey)
    end

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.frame, -125, -16)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent

        local scrollbar = _G[scrollFrame:GetName() .. "ScrollBar"]
        local function OnScroll() self:UpdateScrollList() end
        if scrollbar then
            scrollbar:HookScript("OnValueChanged", OnScroll)
        end
    end

    self.scrollFrame:Show()
    self.scrollContent:Show()

    -- Gather and sort itemIDs so list is deterministic
    self.sortedIDs = {}
    local list = (db.PriorityLists and self.viewListKey) and db.PriorityLists[self.viewListKey]
    local items = list and list.items
    if items then
        for id in pairs(items) do
            table.insert(self.sortedIDs, id)
        end
        table.sort(self.sortedIDs)
    end

    self:UpdateScrollList()
end

function UI_ItemManager:UpdateScrollList()
    if not self.frame or not self.frame:IsShown() then return end

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local db = DesolateLootcouncil.API:GetItemManagerDB()
    local list = (db.PriorityLists and self.viewListKey) and db.PriorityLists[self.viewListKey]

    local totalItems = self.sortedIDs and #self.sortedIDs or 0
    if totalItems == 0 then
        NativeGUI:ResetRowPool(self.rowPool)
        if not self.emptyLabel then
            self.emptyLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            self.emptyLabel:SetPoint("TOPLEFT", 10, -10)
        end
        self.emptyLabel:SetText(L["No assigned items."])
        self.emptyLabel:Show()
        self.scrollContent:SetHeight(40)
        return
    end

    if self.emptyLabel then self.emptyLabel:Hide() end

    local rowHeight = 32
    local rowSpacing = 8
    local rowStride = rowHeight + rowSpacing
    local viewHeight = self.scrollFrame:GetHeight() or 350
    local maxVisible = math.ceil(viewHeight / rowStride) + 1

    local scrollContent = self.scrollContent
    local scrollFrame = self.scrollFrame

    local totalHeight = totalItems * rowStride - rowSpacing
    scrollContent:SetHeight(math.max(1, totalHeight))

    local offset = scrollFrame:GetVerticalScroll()
    local startIndex = math.floor(offset / rowStride) + 1
    if startIndex < 1 then startIndex = 1 end
    local endIndex = startIndex + maxVisible - 1
    if endIndex > totalItems then endIndex = totalItems end

    -- Hide all rows first, we only show/position the ones we need
    for _, row in ipairs(self.rowPool) do
        row:Hide()
    end

    local count = 0
    for i = startIndex, endIndex do
        count = count + 1
        local itemID = self.sortedIDs[i]

        local row = NativeGUI:AcquireRow(self.rowPool, count, scrollContent, false)
        row:SetHeight(rowHeight)
        row:ClearAllPoints()

        local topOffset = -((i - 1) * rowStride)
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, topOffset)
        row:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -12, topOffset)

        PopulateRow(row, itemID, list)
    end
end
