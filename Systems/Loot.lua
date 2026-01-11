---@class Loot : AceModule, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0
local Loot = DesolateLootcouncil:NewModule("Loot", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")

---@class (partial) DLC_Ref_Loot
---@field db table
---@field currentSessionLoot table
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field AmILootMaster fun(self: any): boolean
---@field GetModule fun(self: any, name: string): any
---@field RestorePlayerPosition fun(self: any, listName: string, playerName: string, index: number)
---@field MovePlayerToBottom fun(self: any, listName: string, playerName: string): number|nil
---@field GetReversionIndex fun(self: any, listName: string, origIndex: number, timestamp: number): number
---@field IsUnitInRaid fun(self: any, unitName: string): boolean


---@type DLC_Ref_Loot
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Loot]]

local function DeepCopy(t)
    if type(t) ~= 'table' then return t end
    local res = {}
    for k, v in pairs(t) do
        res[DeepCopy(k)] = DeepCopy(v)
    end
    return res
end

function Loot:OnInitialize()
    DesolateLootcouncil.currentSessionLoot = DesolateLootcouncil.currentSessionLoot or {}
end

function Loot:OnEnable()
    if not DesolateLootcouncil.db or not DesolateLootcouncil.db.profile then
        self:ScheduleTimer("OnEnable", 0.1)
        return
    end

    self.sessionItems = {} -- Transient duplicate check

    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("LOOT_CLOSED", "OnLootClosed")
    self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")

    DesolateLootcouncil:DLC_Log("Systems/Loot Loaded")

    -- Restore UI if session exists
    local session = DesolateLootcouncil.db.profile.session
    if session.loot and #session.loot > 0 then
        self:ScheduleTimer(function()
            ---@type UI_Loot
            local UI = DesolateLootcouncil:GetModule("UI_Loot")
            if UI and UI.ShowLootWindow then
                UI:ShowLootWindow(session.loot)
            else
                -- Fallback to Facade
                local MainUI = DesolateLootcouncil:GetModule("UI")
                if MainUI and MainUI.ShowLootWindow then MainUI:ShowLootWindow(session.loot) end
            end
        end, 1)
    end
end

-- --- Item Categorization (Merged from ItemManager) --- --

---@param link number|string
function Loot:GetItemIDFromLink(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local id = string.match(link, "item:(%d+)")
    return tonumber(id) or tonumber(link)
end

function Loot:GetItemCategory(itemID)
    local db = DesolateLootcouncil.db.profile
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

function Loot:SetItemCategory(itemID, targetListIndex)
    local db = DesolateLootcouncil.db.profile
    if not db or not db.PriorityLists then return end

    itemID = tonumber(itemID)
    if not itemID then return end
    if not db.PriorityLists[targetListIndex] then return end

    -- Remove from others
    for i, list in ipairs(db.PriorityLists) do
        if list.items and list.items[itemID] then
            if i ~= targetListIndex then
                list.items[itemID] = nil
            else
                -- Already here
                return
            end
        end
    end

    -- Add to target
    local targetList = db.PriorityLists[targetListIndex]
    if not targetList.items then targetList.items = {} end
    targetList.items[itemID] = true

    DesolateLootcouncil:DLC_Log(string.format("Added Item %d to '%s'", itemID, targetList.name))
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Loot:UnassignItem(itemID)
    local db = DesolateLootcouncil.db.profile
    if not db or not db.PriorityLists then return end
    local searchID = tonumber(itemID)
    if not searchID then return end
    for _, list in ipairs(db.PriorityLists) do
        if list.items then
            for storedID, _ in pairs(list.items) do
                if tonumber(storedID) == searchID then
                    list.items[storedID] = nil
                end
            end
        end
    end
    DesolateLootcouncil:DLC_Log("Item unassigned from all priority lists.")
end

function Loot:AddItemToList(rawLink, listIndex)
    local itemID = self:GetItemIDFromLink(rawLink)
    if itemID then
        self:SetItemCategory(itemID, listIndex)
    end
end

function Loot:CategorizeItem(itemLink)
    local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemLink)
    if not itemID then return "Junk/Pass" end

    -- Check configured DB first
    local dbCat = self:GetItemCategory(itemID)
    if dbCat ~= "Junk/Pass" then return dbCat end

    -- Fallback Heuristics
    if classID == 2 then return "Weapons" end -- Weapon
    if classID == 4 then                      -- Armor
        local _, _, quality = C_Item.GetItemInfo(itemLink)
        if quality and quality > 1 then return "Rest" end
    end

    return "Junk/Pass"
end

-- --- Event Handlers --- --

function Loot:OnStartLootRoll(event, rollID)
    local db = DesolateLootcouncil.db.profile
    if not db.enableAutoLoot then return end

    local isLM = DesolateLootcouncil:AmILootMaster()
    local link = GetLootRollItemLink(rollID)

    if isLM then
        local _, _, _, _, isBoP, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
        local cat = self:CategorizeItem(link)
        if isBoP and cat == "Collectables" then
            return
        end

        if canNeed then
            RollOnLoot(rollID, 1)
        elseif canGreed then
            RollOnLoot(rollID, 2)
        elseif canTransmog then
            RollOnLoot(rollID, 4)
        elseif canDisenchant then
            RollOnLoot(rollID, 3)
        end
    else
        RollOnLoot(rollID, 0) -- Pass
    end
end

function Loot:OnLootOpened()
    if not IsInRaid() and not DesolateLootcouncil.db.profile.debugMode then return end

    local session = DesolateLootcouncil.db.profile.session
    local itemsChanged = false
    local numItems = GetNumLootItems()

    DesolateLootcouncil:DLC_Log("--- LOOT SCAN START (" .. numItems .. " slots) ---")

    for i = 1, numItems do
        if GetLootSlotType(i) == Enum.LootSlotType.Item then
            local sourceGUID = GetLootSourceInfo(i)
            local itemLink = GetLootSlotLink(i)
            local texture, itemName, quantity, _, quality = GetLootSlotInfo(i)
            local rawID = C_Item.GetItemInfoInstant(itemLink)
            local itemID = tonumber(rawID)

            if sourceGUID and itemLink and itemID then
                local category = self:CategorizeItem(itemLink)
                local minQuality = DesolateLootcouncil.db.profile.minLootQuality
                local isImportant = (category == "Tier" or category == "Weapons" or category == "Collectables")

                if not isImportant and (quality or 0) < minQuality then
                    DesolateLootcouncil:DLC_Log("Skipped low quality item: " .. itemLink)
                else
                    local uniqueKey = sourceGUID .. "-" .. itemID
                    if self:AddSessionItem(itemLink, uniqueKey, texture, quantity, category, itemID) then
                        itemsChanged = true
                        session.lootedMobs[sourceGUID] = true
                        DesolateLootcouncil:DLC_Log("ADDED: " .. itemName)
                    end
                end
            end
        end
    end
    DesolateLootcouncil:DLC_Log("--- SCAN END ---")

    if itemsChanged then
        local UI = DesolateLootcouncil:GetModule("UI_Loot")
        if UI then UI:ShowLootWindow(session.loot) end
    end
end

function Loot:OnLootClosed()
    -- No-op
end

function Loot:AddSessionItem(link, itemGUID, texture, quantity, category, itemID)
    if self.sessionItems[itemGUID] then return false end
    local session = DesolateLootcouncil.db.profile.session
    table.insert(session.loot, {
        link = link,
        itemID = itemID,
        category = category,
        sourceGUID = itemGUID,
        stackIndex = quantity,
        texture = texture
    })
    self.sessionItems[itemGUID] = true
    return true
end

function Loot:ClearLootBacklog()
    local session = DesolateLootcouncil.db.profile.session
    if session and session.loot then wipe(session.loot) end
    if self.sessionItems then wipe(self.sessionItems) end
    DesolateLootcouncil:DLC_Log("Loot backlog cleared.")
end

function Loot:AddManualItem(rawLink)
    local itemID = self:GetItemIDFromLink(rawLink)
    if itemID then
        local category = self:GetItemCategory(itemID)
        if category == "Junk/Pass" then category = self:CategorizeItem(rawLink) end

        local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
        if not link then link = "Item " .. itemID end
        if not icon then icon = C_Item.GetItemIconByID(itemID) end

        local session = DesolateLootcouncil.db.profile.session
        table.insert(session.loot, {
            link = link,
            itemID = itemID,
            category = category,
            sourceGUID = "Manual-" .. itemID .. "-" .. math.random(100),
            stackIndex = 1,
            texture = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            isManual = true
        })
        DesolateLootcouncil:DLC_Log("Manually added: " .. link, true)

        local UI = DesolateLootcouncil:GetModule("UI_Loot")
        if UI then UI:ShowLootWindow(session.loot) end
    end
end

-- --- Awarding --- --

function Loot:AwardItem(itemGUID, winnerName, voteType)
    local session = DesolateLootcouncil.db.profile.session
    local itemData, removeIndex

    if session and session.bidding then
        for i, item in ipairs(session.bidding) do
            if item.sourceGUID == itemGUID then
                itemData = item; removeIndex = i; break
            end
        end
    end

    if not itemData then return end

    local link = itemData.link
    local msg = string.format("Winner of %s is %s! (%s)", link, winnerName, voteType)

    if IsInRaid() then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            SendChatMessage(msg, "RAID_WARNING")
        else
            SendChatMessage(msg, "RAID")
        end
    else
        DesolateLootcouncil:DLC_Log(msg)
    end

    if winnerName ~= UnitName("player") then
        C_ChatInfo.SendChatMessage("You have been awarded " .. link .. "! Trade me.", "WHISPER", nil, winnerName)
    end

    local origIndex
    if voteType == "Bid" or voteType == "1" then
        ---@type Priority
        local Priority = DesolateLootcouncil:GetModule("Priority") --[[@as Priority]]
        if Priority and Priority.MovePlayerToBottom then
            origIndex = Priority:MovePlayerToBottom(itemData.category, winnerName)
        end
    end

    if session.awarded then
        local _, winnerClass = UnitClassBase(winnerName)
        ---@type Session
        local Session = DesolateLootcouncil:GetModule("Session")

        table.insert(session.awarded, {
            link = itemData.link,
            texture = itemData.texture,
            itemID = itemData.itemID,
            winner = winnerName,
            winnerClass = winnerClass,
            voteType = voteType,
            timestamp = GetServerTime(),
            originalIndex = origIndex,
            fullItemData = itemData,
            votes = Session and Session.sessionVotes and DeepCopy(Session.sessionVotes[itemGUID]) or {},
            traded = (winnerName == UnitName("player"))
        })

        if Session and Session.SendRemoveItem then
            Session:SendRemoveItem(itemGUID)
        end
    end

    if removeIndex then
        table.remove(session.bidding, removeIndex)
        ---@type Session
        local Session = DesolateLootcouncil:GetModule("Session") --[[@as Session]]
        if Session and Session.sessionVotes then
            Session.sessionVotes[itemGUID] = nil
        end
    end

    local UI = DesolateLootcouncil:GetModule("UI_Monitor")
    if UI then UI:ShowMonitorWindow() end
end

function Loot:ReawardItem(index)
    local session = DesolateLootcouncil.db.profile.session
    if not session.awarded or not session.awarded[index] then return end

    local awardedItem = session.awarded[index]
    -- Restore to Bidding
    table.insert(session.bidding, awardedItem.fullItemData or {
        link = awardedItem.link,
        itemID = awardedItem.itemID,
        texture = awardedItem.texture,
        category = "Re-awarded",
        sourceGUID = "Reaward-" .. (awardedItem.itemID or 0) .. "-" .. math.random(100),
        stackIndex = 1
    })

    -- Revert Priority
    if awardedItem.originalIndex and awardedItem.winner then
        ---@type Priority
        local Priority = DesolateLootcouncil:GetModule("Priority") --[[@as Priority]]
        if Priority and Priority.RestorePlayerPosition then
            local cat = awardedItem.fullItemData and awardedItem.fullItemData.category
            if cat then
                Priority:RestorePlayerPosition(cat, awardedItem.winner, awardedItem.originalIndex)
            end
        end
    end

    -- [FIX] Restore Votes to Session
    if awardedItem.votes then
        local Session = DesolateLootcouncil:GetModule("Session")
        if Session then
            if not Session.sessionVotes then Session.sessionVotes = {} end
            -- Map by GUID (which we generated on restore or original)
            -- Ideally we use the ORIGINAL sourceGUID if possible, but Reaward generates a new one.
            -- Wait, if we generate a NEW GUID, the old votes won't map!
            -- We must use the OLD GUID if we want votes to match, OR we update the votes key.
            -- The Reaward logic below generates a NEW GUID: "Reaward-..."
            -- Let's use that NEW GUID for the vote key.

            -- Update bidding item to use the Reaward GUID
            local newItem = session.bidding[#session.bidding]
            local newGUID = newItem.sourceGUID

            Session.sessionVotes[newGUID] = DeepCopy(awardedItem.votes)
            local vCount = 0
            for _ in pairs(awardedItem.votes) do vCount = vCount + 1 end
            DesolateLootcouncil:DLC_Log("Restored " .. vCount .. " votes for re-awarded item.")
        end
    end

    table.remove(session.awarded, index)
    DesolateLootcouncil:DLC_Log("Re-awarded item: " .. (awardedItem.link or "???"))

    -- Refresh UIs
    local History = DesolateLootcouncil:GetModule("UI_History")
    if History then History:ShowHistoryWindow() end

    -- Open Monitor to show it's back
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
    if Monitor then Monitor:ShowMonitorWindow() end

    DesolateLootcouncil:Print("Item reverted to bidding session.")
end

function Loot:AddTestItems()
    local testItems = {
        "item:16914:::::::20:257::::::", -- Tier (Netherwind Belt)
        "item:17075:::::::20:257::::::", -- Weapons (Vis'kag)
        "item:19136:::::::20:257::::::", -- Rest (Mana Igniting Cord)
        "item:13335:::::::20:257::::::", -- Collectables (Deathcharger's Reins)
        "item:19019:::::::20:257::::::", -- Extra (Thunderfury)
    }
    for _, itemLink in ipairs(testItems) do
        self:AddManualItem(itemLink)
    end
    DesolateLootcouncil:DLC_Log("Added test items to session.")
end

function Loot:ScanDisenchanters()
    local Comm = DesolateLootcouncil:GetModule("Comm")
    if Comm and Comm.SendVersionCheck then
        Comm:SendVersionCheck()
        DesolateLootcouncil:DLC_Log("Triggered disenchanter scan via version check.")
    end
end
