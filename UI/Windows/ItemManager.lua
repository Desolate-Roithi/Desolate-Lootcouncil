local _, AT = ...
if AT.abortLoad then return end

---@class UI_ItemManager : AceModule
local UI_ItemManager = DesolateLootcouncil:NewModule("UI_ItemManager")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function UI_ItemManager:ShowItemManagerWindow()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.frame then
        local frame = NativeGUI:CreateWindow("DLCItemManagerFrame", L["Item Manager"], 600, 500, "ItemManager")
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
        eb:SetScript("OnEnterPressed", function(edit)
            edit:ClearFocus()
            local text = edit:GetText()
            if text and text ~= "" and self.tempList then
                DesolateLootcouncil.API:AddManagedItem(text, self.tempList)
                edit:SetText("")
                self:RefreshWindow()
            end
        end)
        self.itemInput = container
        self.itemEditBox = eb
    end

    -- 2. Target list dropdown
    self.tempList = self.tempList or 1
    if not self.listDrop then
        local dropContainer = NativeGUI:CreateDropdown(self.frame, L["Target List"], 140, listNames, self.tempList, function(value)
            self.tempList = value
        end)
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
        btn:SetScript("OnClick", function()
            local text = self.itemEditBox:GetText()
            if text and text ~= "" and self.tempList then
                DesolateLootcouncil.API:AddManagedItem(text, self.tempList)
                self.itemEditBox:SetText("")
                self:RefreshWindow()
            end
        end)
        self.btnAdd = btn
    end

    -- 4. Sync Raid Button (LM/Assist Only)
    if DesolateLootcouncil:AmIRaidAssistOrLM() then
        if not self.btnSync then
            local btn = NativeGUI:CreateButton(self.frame, L["Sync Raid"], 90, 24, "Bid")
            btn:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -16, -58)
            btn:SetScript("OnClick", function()
                DesolateLootcouncil.API:SyncItemManagerToRaid()
                DesolateLootcouncil:Print(L["Item Manager lists synced to raid."])
            end)
            self.btnSync = btn
        end
        self.btnSync:Show()
    elseif self.btnSync then
        self.btnSync:Hide()
    end

    -- 5. Select list to view dropdown
    self.viewListKey = self.viewListKey or 1
    if not self.viewDrop then
        local dropContainer = NativeGUI:CreateDropdown(self.frame, L["Select List to View"], 220, listNames, self.viewListKey, function(value)
            self.viewListKey = value
            self:RefreshWindow()
        end)
        dropContainer:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -84)
        self.viewDrop = dropContainer
    else
        self.viewDrop:SetList(listNames)
        self.viewDrop:SetValue(self.viewListKey)
    end

    for _, r in ipairs(self.rowPool) do
        r:Hide()
        r:ClearAllPoints()
    end

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.frame, -125, -16)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    self.scrollFrame:Show()
    self.scrollContent:Show()

    local topOffset = 0
    local rowHeight = 32
    local count = 0

    if db.PriorityLists and self.viewListKey then
        local list = db.PriorityLists[self.viewListKey]
        if list and list.items then
            -- Gather and sort itemIDs so list is deterministic
            local sortedIDs = {}
            for id in pairs(list.items) do table.insert(sortedIDs, id) end
            table.sort(sortedIDs)

            for _, itemID in ipairs(sortedIDs) do
                count = count + 1
                local name, itemLink, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)

                if not itemLink then
                    local itemObj = Item:CreateFromItemID(itemID)
                    if not itemObj:IsItemEmpty() then
                        itemObj:ContinueOnItemLoad(function()
                            if self.frame and self.frame:IsShown() then
                                self:RefreshWindow()
                            end
                        end)
                    end
                    name = L["Loading..."]
                    itemTexture = C_Item.GetItemIconByID(itemID)
                end

                if not self.rowPool[count] then
                    self.rowPool[count] = NativeGUI:CreateRowContainer(self.scrollContent, false)
                end
                local row = self.rowPool[count]
                row:Show()
                row:SetHeight(rowHeight)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
                row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

                -- Remove Button
                if not row.btnRemove then
                    local btn = NativeGUI:CreateButton(row, L["Remove"], 70, 24, "Stop")
                    row.btnRemove = btn
                end
                row.btnRemove:ClearAllPoints()
                row.btnRemove:SetPoint("RIGHT", -8, 0)
                row.btnRemove:Show()
                row.btnRemove:SetScript("OnClick", function()
                    list.items[itemID] = nil
                    DesolateLootcouncil:DLC_Log(string.format(L["Removed item ID: %s"], itemID))
                    self:RefreshWindow()
                end)

                -- Icon
                if not row.iconBtn then
                    local btn = CreateFrame("Button", nil, row)
                    btn:SetSize(24, 24)
                    btn:SetPoint("LEFT", 8, 0)
                    local tex = btn:CreateTexture(nil, "BACKGROUND")
                    tex:SetAllPoints()
                    btn.texture = tex
                    row.iconBtn = btn
                end
                row.iconBtn.texture:SetTexture(itemTexture or 134400)
                row.iconBtn:Show()

                local function ShowTip()
                    GameTooltip:SetOwner(row.iconBtn, "ANCHOR_CURSOR")
                    if itemLink then GameTooltip:SetHyperlink(itemLink) else GameTooltip:SetItemByID(itemID) end
                    GameTooltip:Show()
                end
                row.iconBtn:SetScript("OnClick", ShowTip)
                row.iconBtn:SetScript("OnEnter", ShowTip)
                row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                -- Link Label (sandwiched dynamically)
                if not row.linkLabel then
                    local btn = CreateFrame("Button", nil, row)
                    btn:SetHeight(20)
                    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    txt:SetPoint("LEFT", 0, 0)
                    txt:SetPoint("RIGHT", 0, 0)
                    txt:SetJustifyH("LEFT")
                    btn.text = txt
                    row.linkLabel = btn
                end
                row.linkLabel:ClearAllPoints()
                row.linkLabel:SetPoint("LEFT", row.iconBtn, "RIGHT", 8, 0)
                row.linkLabel:SetPoint("RIGHT", row.btnRemove, "LEFT", -10, 0)
                row.linkLabel.text:SetText(itemLink or name)
                row.linkLabel:Show()
                row.linkLabel:SetScript("OnClick", function()
                    if itemLink then
                        local chatbox = ChatEdit_ChooseBoxForSend()
                        ChatEdit_ActivateChat(chatbox)
                        chatbox:Insert(itemLink)
                    end
                end)
                row.linkLabel:SetScript("OnEnter", ShowTip)
                row.linkLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)

                topOffset = topOffset + rowHeight + 8
            end
        end
    end

    if count == 0 then
        if not self.emptyLabel then
            self.emptyLabel = self.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            self.emptyLabel:SetPoint("TOPLEFT", 10, -10)
        end
        self.emptyLabel:SetText(L["No assigned items."])
        self.emptyLabel:Show()
        self.scrollContent:SetHeight(40)
    else
        if self.emptyLabel then self.emptyLabel:Hide() end
        self.scrollContent:SetHeight(topOffset + 10)
    end
end
