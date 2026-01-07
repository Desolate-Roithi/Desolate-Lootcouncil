---@class (partial) DLC_Ref_ItemManager
---@field db table
---@field NewModule fun(self: DLC_Ref_ItemManager, name: string): any
---@field Print fun(self: DLC_Ref_ItemManager, msg: string)
---@field GetItemIDFromLink fun(self: DLC_Ref_ItemManager, itemLink: string): number?
---@field GetItemCategory fun(self: DLC_Ref_ItemManager, item: any): string
---@field SetItemCategory fun(self: DLC_Ref_ItemManager, itemID: number, listIndex: number)
---@field AddItemToList fun(self: DLC_Ref_ItemManager, item: string, listIndex: number)
---@field RemoveItemFromList fun(self: DLC_Ref_ItemManager, listIndex: number, itemID: number)
---@field UnassignItem fun(self: DLC_Ref_ItemManager, itemID: number)

---@type DLC_Ref_ItemManager
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_ItemManager]]
local ItemManager = DesolateLootcouncil:NewModule("ItemManager") --[[@as ItemManager]]

---@class ItemManager : AceModule
---@field OnInitialize function

function ItemManager:OnInitialize()
    -- Nothing special to init, db is accessed dynamically
end

---@param link number|string
function DesolateLootcouncil:GetItemIDFromLink(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local id = string.match(link, "item:(%d+)")
    return tonumber(id) or tonumber(link)
end

-- The "Brute Force" Lookup Function (Backend API)
function DesolateLootcouncil:GetItemCategory(itemID)
    local db = self.db.profile
    if not db or not db.PriorityLists then return "Junk/Pass" end
    if not itemID then return "Junk/Pass" end

    local searchID = tonumber(itemID)
    if not searchID then return "Junk/Pass" end

    -- Iterate lists
    for _, list in ipairs(db.PriorityLists) do
        if list.items then
            -- Brute Force Check (Handle String keys in DB)
            for storedID, _ in pairs(list.items) do
                if tonumber(storedID) == searchID then
                    return list.name
                end
            end
        end
    end
    return "Junk/Pass"
end

-- The "Smart" Assignment Function (Backend API)
function DesolateLootcouncil:SetItemCategory(itemID, targetListIndex)
    local db = self.db.profile
    if not db or not db.PriorityLists then return end

    -- Validate inputs
    itemID = tonumber(itemID)
    if not itemID then return end
    if not db.PriorityLists[targetListIndex] then return end

    -- 1. Search & Clean (Conflict Resolution)
    -- Iterate through all lists. If item found elsewhere, remove it.
    for i, list in ipairs(db.PriorityLists) do
        if list.items and list.items[itemID] then
            if i ~= targetListIndex then
                list.items[itemID] = nil
                self:Print(string.format("Moved Item %d from '%s' to '%s'", itemID, list.name,
                    db.PriorityLists[targetListIndex].name))
            else
                -- Already in the target list, nothing to do
                self:Print("Item already exists in this list.")
                return
            end
        end
    end

    -- 2. Assign to Target
    local targetList = db.PriorityLists[targetListIndex]
    if not targetList.items then targetList.items = {} end
    targetList.items[itemID] = true

    -- 3. Persist & Notify
    self:Print(string.format("Added Item %d to '%s'", itemID, targetList.name))
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

---@param listIndex number
---@param itemInput number|string
function DesolateLootcouncil:AddItemToList(listIndex, itemInput)
    local itemID = self:GetItemIDFromLink(itemInput)
    if not itemID then
        self:Print("Invalid Item. Please provide a Link or Item ID.")
        return
    end

    -- Use the API
    self:SetItemCategory(itemID, listIndex)
end

function DesolateLootcouncil:RemoveItemFromList(listIndex, itemID)
    local db = self.db.profile
    if not db.PriorityLists[listIndex] then return end

    if db.PriorityLists[listIndex].items then
        db.PriorityLists[listIndex].items[itemID] = nil
        self:Print(string.format("Removed Item %d from '%s'", itemID, db.PriorityLists[listIndex].name))
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

-- Remove item from ALL lists (Junk/Pass logic)
function DesolateLootcouncil:UnassignItem(itemID)
    local db = self.db.profile
    if not db or not db.PriorityLists then return end

    local searchID = tonumber(itemID)
    if not searchID then return end

    local found = false
    for _, list in ipairs(db.PriorityLists) do
        if list.items then
            -- Safe remove considering string keys
            for storedID, _ in pairs(list.items) do
                if tonumber(storedID) == searchID then
                    list.items[storedID] = nil
                    found = true
                end
            end
        end
    end

    if found then
        -- Don't print if not found to reduce spam, or maybe print confirmaton only if found.
        self:Print("[DLC] Item unassigned from all priority lists.")
    end
end
