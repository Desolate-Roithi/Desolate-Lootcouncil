local _, AT = ...
if AT.abortLoad then return end

---@class UI_ItemManager : AceModule
local UI_ItemManager = DesolateLootcouncil:NewModule("UI_ItemManager")
local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

---@class (partial) DLC_Ref_ItemManager
---@field db table
---@field GetModule fun(self: DLC_Ref_ItemManager, name: string): any

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]

function UI_ItemManager:ShowItemManagerWindow()
    if not self.frame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame")
        frame:SetTitle(L["Item Manager"])
        frame:SetLayout("Flow")
        frame:SetWidth(600)
        frame:SetHeight(500)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.frame = frame

        -- Persistence
        DesolateLootcouncil:MakeMovableWithSave(frame, "ItemManager")
    end

    self.frame:Show()
    self:RefreshWindow()
end

function UI_ItemManager:BuildHeaderGroup(db, listNames)
    local headerGroup = AceGUI:Create("SimpleGroup")
    headerGroup:SetLayout("Flow")
    headerGroup:SetFullWidth(true)
    self.frame:AddChild(headerGroup)

    local input = AceGUI:Create("EditBox")
    input:SetLabel(L["Item Name/Link/ID"])
    input:SetRelativeWidth(0.40)
    input:DisableButton(true)
    input:SetCallback("OnEnterPressed", function(widget, event, text)
        if text and text ~= "" and self.tempList then
            local Loot = DesolateLootcouncil:GetModule("Loot")
            if Loot then
                Loot:AddItemToList(text, self.tempList)
                input:SetText("")
                self:RefreshWindow()
            end
        end
    end)
    headerGroup:AddChild(input)

    local listDropdown = AceGUI:Create("Dropdown")
    listDropdown:SetLabel(L["Target List"])
    listDropdown:SetRelativeWidth(0.25)
    listDropdown:SetList(listNames)

    self.tempList = self.tempList or 1
    listDropdown:SetValue(self.tempList)
    listDropdown:SetCallback("OnValueChanged", function(widget, event, value)
        self.tempList = value
    end)
    headerGroup:AddChild(listDropdown)

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText(L["Add"])
    addBtn:SetRelativeWidth(0.15)
    addBtn:SetCallback("OnClick", function()
        local text = input:GetText()
        if text and text ~= "" and self.tempList then
            local Loot = DesolateLootcouncil:GetModule("Loot")
            if Loot then
                Loot:AddItemToList(text, self.tempList)
                input:SetText("")
                self:RefreshWindow()
            end
        end
    end)
    headerGroup:AddChild(addBtn)

    if DesolateLootcouncil:AmIRaidAssistOrLM() then
        local syncBtn = AceGUI:Create("Button")
        syncBtn:SetText(L["Sync Raid"])
        syncBtn:SetRelativeWidth(0.2)
        syncBtn:SetCallback("OnClick", function()
            local syncData = {}
            for _, list in ipairs(db.PriorityLists) do
                syncData[list.name] = list.items
            end
            local Comm = DesolateLootcouncil:GetModule("Comm")
            if Comm then
                Comm:SendComm("IM_SYNC", syncData)
                DesolateLootcouncil:Print(L["Item Manager lists synced to raid."])
            end
        end)
        headerGroup:AddChild(syncBtn)
    end
end

function UI_ItemManager:BuildItemRow(scroll, list, itemID)
    local name, itemLink, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)

    if not itemLink then
        local itemObj = Item:CreateFromItemID(itemID)
        if not itemObj:IsItemEmpty() then
            itemObj:ContinueOnItemLoad(function()
                if self.frame and (self.frame --[[@as any]]).frame:IsShown() then
                    self:RefreshWindow()
                end
            end)
        end
        name = L["Loading..."]
        itemTexture = C_Item.GetItemIconByID(itemID)
    end

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    scroll:AddChild(row)

    local iconLabel = AceGUI:Create("InteractiveLabel")
    iconLabel:SetImage(itemTexture)
    iconLabel:SetImageSize(24, 24)
    iconLabel:SetWidth(40)
    iconLabel:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
        if itemLink then GameTooltip:SetHyperlink(itemLink) else GameTooltip:SetItemByID(itemID) end
        GameTooltip:Show()
    end)
    iconLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    row:AddChild(iconLabel)

    local nameLabel = AceGUI:Create("InteractiveLabel")
    nameLabel:SetText(itemLink or name)
    nameLabel:SetRelativeWidth(0.70)
    nameLabel:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
        if itemLink then GameTooltip:SetHyperlink(itemLink) else GameTooltip:SetItemByID(itemID) end
        GameTooltip:Show()
    end)
    nameLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    nameLabel:SetCallback("OnClick", function()
        if itemLink then
            local editBox = ChatEdit_ChooseBoxForSend()
            ChatEdit_ActivateChat(editBox)
            editBox:Insert(itemLink)
        end
    end)
    row:AddChild(nameLabel)

    local btnRemove = AceGUI:Create("Button")
    btnRemove:SetText(L["Remove"])
    btnRemove:SetRelativeWidth(0.15)
    btnRemove:SetHeight(24)
    btnRemove:SetCallback("OnClick", function()
        list.items[itemID] = nil
        DesolateLootcouncil:DLC_Log(string.format(L["Removed item ID: %s"], itemID))
        self:RefreshWindow()
    end)
    row:AddChild(btnRemove)
end

function UI_ItemManager:RefreshWindow()
    if not self.frame then return end
    self.frame:ReleaseChildren()

    local db = DesolateLootcouncil.db.profile
    local listNames = {}
    local Priority = DesolateLootcouncil:GetModule("Priority")
    local pNames = Priority and Priority:GetPriorityListNames() or {}
    for i, name in ipairs(pNames) do listNames[i] = name end

    self:BuildHeaderGroup(db, listNames)

    local sep = AceGUI:Create("Heading")
    sep:SetText(L["Assigned Items"])
    sep:SetFullWidth(true)
    self.frame:AddChild(sep)

    local viewDropdown = AceGUI:Create("Dropdown")
    viewDropdown:SetLabel(L["Select List to View"])
    viewDropdown:SetList(listNames)
    self.viewListKey = self.viewListKey or 1
    viewDropdown:SetValue(self.viewListKey)
    viewDropdown:SetCallback("OnValueChanged", function(widget, event, value)
        self.viewListKey = value
        self:RefreshWindow()
    end)
    viewDropdown:SetFullWidth(true)
    self.frame:AddChild(viewDropdown)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.frame:AddChild(scroll)

    if db.PriorityLists and self.viewListKey then
        local list = db.PriorityLists[self.viewListKey]
        if list and list.items then
            for itemID, _ in pairs(list.items) do
                self:BuildItemRow(scroll, list, itemID)
            end
        end
    end
end
