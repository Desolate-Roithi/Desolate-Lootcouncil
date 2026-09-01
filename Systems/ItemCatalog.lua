local _, AT = ...
if AT.abortLoad then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

---@class ItemCatalog : AceModule
local ItemCatalog = DesolateLootcouncil:NewModule("ItemCatalog")

---@class (partial) DLC_Ref_ItemCatalog
---@field db table
---@field API table
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_ItemCatalog]]

function ItemCatalog:OnInitialize()
    self.dirtyLists = {}
    DesolateLootcouncil:DLC_Log(L["Systems/ItemCatalog Loaded"])
end

--- Extracts numeric item ID from an item link, string, or number.
---@param link number|string
---@return number|nil
function ItemCatalog:GetItemIDFromLink(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local id = string.match(link, "item:(%d+)")
    return tonumber(id) or tonumber(link)
end

--- Returns the priority list name an item is assigned to, or "Junk/Pass" if unassigned.
---@param itemID number|string
---@return string
function ItemCatalog:GetItemCategory(itemID)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.PriorityLists then return "Junk/Pass" end
    if not itemID then return "Junk/Pass" end

    local searchID = tonumber(itemID)
    if not searchID then return "Junk/Pass" end

    for _, list in ipairs(db.PriorityLists) do
        if list.items then
            for storedID, _ in pairs(list.items) do
                if tonumber(storedID) == searchID then
                    return list.name
                end
            end
        end
    end
    return "Junk/Pass"
end

--- Assigns an item to a target priority list and removes it from all other lists.
---@param itemID number|string
---@param targetListIndex number
function ItemCatalog:SetItemCategory(itemID, targetListIndex)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.PriorityLists then return end

    itemID = tonumber(itemID)
    if not itemID then return end
    if not db.PriorityLists[targetListIndex] then return end

    -- Remove from other lists
    for i, list in ipairs(db.PriorityLists) do
        if list.items and list.items[itemID] then
            if i ~= targetListIndex then
                list.items[itemID] = nil
                self:MarkIMDirty(list.name)
            else
                -- Already assigned here
                return
            end
        end
    end

    -- Add to target list
    local targetList = db.PriorityLists[targetListIndex]
    if not targetList.items then targetList.items = {} end
    targetList.items[itemID] = true
    self:MarkIMDirty(targetList.name)

    DesolateLootcouncil:DLC_Log(string.format(L["Added Item %d to '%s'"], itemID, targetList.name))
    local Audit = DesolateLootcouncil:GetModule("Audit", true)
    if Audit and Audit.Log then
        Audit:Log("CATALOG_OVERRIDE", nil, nil, targetList.name, string.format("Assigned Item %d to %s", itemID, targetList.name))
    end
    if LibStub and LibStub:GetLibrary("AceConfigRegistry-3.0", true) then
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

--- Removes an item from all priority lists.
---@param itemID number|string
function ItemCatalog:UnassignItem(itemID)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.PriorityLists then return end
    local searchID = tonumber(itemID)
    if not searchID then return end

    for _, list in ipairs(db.PriorityLists) do
        if list.items then
            for storedID, _ in pairs(list.items) do
                if tonumber(storedID) == searchID then
                    list.items[storedID] = nil
                    self:MarkIMDirty(list.name)
                end
            end
        end
    end
    DesolateLootcouncil:DLC_Log(L["Item unassigned from all priority lists."])
end

--- Parses item link and assigns item to target list index.
---@param rawLink string|number
---@param listIndex number
function ItemCatalog:AddItemToList(rawLink, listIndex)
    local itemID = self:GetItemIDFromLink(rawLink)
    if itemID then
        self:SetItemCategory(itemID, listIndex)
    end
end

--- Evaluates item category by database lookup or item class heuristics.
---@param itemLink string
---@param fallbackQuality number|nil
---@return string category
function ItemCatalog:CategorizeItem(itemLink, fallbackQuality)
    local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemLink)
    if not itemID then return "Junk/Pass" end

    -- Check configured DB first
    local dbCat = self:GetItemCategory(itemID)
    if dbCat ~= "Junk/Pass" then return dbCat end

    -- Fallback Heuristics
    if classID == 2 then return "Weapons" end -- Weapon
    if classID == 4 then                      -- Armor
        local quality = select(3, C_Item.GetItemInfo(itemLink)) or fallbackQuality
        if quality and quality > 1 then return "Rest" end
    end

    return "Junk/Pass"
end

--- Marks an item manager list cache dirty.
---@param listName string
function ItemCatalog:MarkIMDirty(listName)
    if not listName then return end
    self.dirtyLists = self.dirtyLists or {}
    self.dirtyLists[listName] = true
end

--- Checks and clears the dirty flag for an item manager list.
---@param listName string
---@return boolean
function ItemCatalog:ConsumeIMDirty(listName)
    if not listName then return false end
    if not self.dirtyLists then return false end
    local dirty = self.dirtyLists[listName] == true
    self.dirtyLists[listName] = nil
    return dirty
end
