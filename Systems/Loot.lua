local _, AT = ...
if AT.abortLoad then return end

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
---@field GetActiveUserCount fun(self: any): number
---@field Print fun(self: any, msg: string)
---@field sessionAutopassActive boolean


---@type DLC_Ref_Loot
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Loot]]
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")
local canaccessvalue = canaccessvalue

local function SafeIsGroupLeader(unit)
    unit = unit or "player"
    local ok, isLeader = pcall(UnitIsGroupLeader, unit)
    if ok and isLeader ~= nil and not (type(issecretvalue) == "function" and issecretvalue(isLeader)) then
        return not not isLeader
    end
    return false
end



function Loot:OnInitialize()
    DesolateLootcouncil.currentSessionLoot = DesolateLootcouncil.currentSessionLoot or {}
end

function Loot:OnEnable()
    if not DesolateLootcouncil.db or not DesolateLootcouncil.db.profile then
        self:ScheduleTimer("OnEnable", 0.1)
        return
    end

    local session = DesolateLootcouncil.db.profile.session
    self.sessionItems = session.sessionItems or {} -- Persisted duplicate check
    session.sessionItems = self.sessionItems

    -- LOOT_OPENED registration removed to prevent corpse clicks from adding duplicates.
    -- All items are added strictly via START_LOOT_ROLL and CHAT_MSG_LOOT.
    self:RegisterEvent("CHAT_MSG_LOOT", "OnLootMessage")
    self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")

    DesolateLootcouncil:DLC_Log(L["Systems/Loot Loaded"])

    -- Clean up stale loot for players logging in the next day.
    -- If they log in outside of a raid, wipe the backlog so it doesn't pop up erroneously.
    if session.loot and #session.loot > 0 then
        if not IsInRaid() and not DesolateLootcouncil.db.profile.debugMode then
            wipe(session.loot)
            DesolateLootcouncil:DLC_Log(L["Wiped stale loot backlog from previous session."])
        elseif DesolateLootcouncil:AmILootMaster() then
            self:ScheduleTimer(function()
                self:SendMessage("DLC_LOOT_WINDOW_UPDATE", session.loot)
            end, 1)
        end
    end
end

-- --- Item Categorization (Delegated to ItemCatalog) --- --

---@param link number|string
function Loot:GetItemIDFromLink(link)
    local Catalog = DesolateLootcouncil:GetModule("ItemCatalog", true)
    if Catalog and Catalog.GetItemIDFromLink then return Catalog:GetItemIDFromLink(link) end
    if not link then return nil end
    if type(link) == "number" then return link end
    local id = string.match(link, "item:(%d+)")
    return tonumber(id) or tonumber(link)
end

function Loot:GetItemCategory(itemID)
    local Catalog = DesolateLootcouncil:GetModule("ItemCatalog", true)
    if Catalog and Catalog.GetItemCategory then return Catalog:GetItemCategory(itemID) end
    return "Junk/Pass"
end

function Loot:SetItemCategory(itemID, targetListIndex)
    local Catalog = DesolateLootcouncil:GetModule("ItemCatalog", true)
    if Catalog and Catalog.SetItemCategory then Catalog:SetItemCategory(itemID, targetListIndex) end
end

function Loot:UnassignItem(itemID)
    local Catalog = DesolateLootcouncil:GetModule("ItemCatalog", true)
    if Catalog and Catalog.UnassignItem then Catalog:UnassignItem(itemID) end
end

function Loot:AddItemToList(rawLink, listIndex)
    local Catalog = DesolateLootcouncil:GetModule("ItemCatalog", true)
    if Catalog and Catalog.AddItemToList then Catalog:AddItemToList(rawLink, listIndex) end
end

function Loot:CategorizeItem(itemLink, fallbackQuality)
    local Catalog = DesolateLootcouncil:GetModule("ItemCatalog", true)
    if Catalog and Catalog.CategorizeItem then return Catalog:CategorizeItem(itemLink, fallbackQuality) end
    return "Junk/Pass"
end


function Loot:ProcessLootSlot(i, session)
    if GetLootSlotType(i) ~= Enum.LootSlotType.Item then return end

    local sourceGUID = GetLootSourceInfo(i)
    local itemLink = GetLootSlotLink(i)
    local texture, itemName, quantity, _, quality = GetLootSlotInfo(i)
    local rawID = C_Item.GetItemInfoInstant(itemLink)
    local itemID = tonumber(rawID)

    if not (sourceGUID and itemLink and itemID) then return end

    local item = Item:CreateFromItemLink(itemLink)
    item:ContinueOnItemLoad(function()
        local category = self:CategorizeItem(itemLink, quality)
        local minQuality = DesolateLootcouncil.db.profile.minLootQuality
        local isImportant = (category == "Tier" or category == "Weapons" or category == "Collectables")

        if not isImportant and (quality or 0) < minQuality then
            DesolateLootcouncil:DLC_Log(string.format(L["Skipped low quality item: %s"], itemLink))
            return
        end

        local uniqueKey = sourceGUID .. "-" .. itemID .. "-" .. i
        if self:AddSessionItem(itemLink, uniqueKey, texture, quantity, category, itemID) then
            session.lootedMobs[sourceGUID] = true
            DesolateLootcouncil:DLC_Log(string.format(L["Added item: %s"], itemName))

            self:SendMessage("DLC_LOOT_WINDOW_UPDATE", session.loot)
        end
    end)
end

function Loot:OnLootOpened()
    if DesolateLootcouncil:IsLFR() then return end
    if not IsInRaid() and not DesolateLootcouncil.db.profile.debugMode then return end
    if not DesolateLootcouncil:AmILootMaster() then return end

    local session = DesolateLootcouncil.db.profile.session
    local numItems = GetNumLootItems()

    DesolateLootcouncil:DLC_Log(string.format(L["--- LOOT SCAN START (%d slots) ---"], numItems))

    for i = 1, numItems do
        self:ProcessLootSlot(i, session)
    end
    DesolateLootcouncil:DLC_Log(L["--- SCAN END ---"])
end

function Loot:OnStartLootRoll(event, rollID)
    if not DesolateLootcouncil:IsInRaidOrTest() then return end
    if not DesolateLootcouncil:AmILootMaster() then return end

    local link = GetLootRollItemLink(rollID)
    if not link then return end

    local itemID = self:GetItemIDFromLink(link)
    if not itemID then return end

    local texture, _, count, quality = GetLootRollItemInfo(rollID)
    local category = self:CategorizeItem(link, quality)
    local minQuality = DesolateLootcouncil.db.profile.minLootQuality or 3

    if quality >= minQuality or category ~= "Junk/Pass" then
        local guid = "BlizRoll-" .. itemID .. "-" .. rollID
        if self:AddSessionItem(link, guid, texture, count or 1, category, itemID) then
            DesolateLootcouncil:DLC_Log(string.format(L["AUTO-ADDED from roll: %s"], link))
            self:SendMessage("DLC_LOOT_WINDOW_UPDATE", DesolateLootcouncil.db.profile.session.loot)
        end
    end
end

function Loot:OnLootMessage(event, msg)
    if not DesolateLootcouncil:IsInRaidOrTest() then return end
    if not DesolateLootcouncil:AmILootMaster() then return end
    if not canaccessvalue(msg) then return end

    -- Catch "You receive loot: [Item Link]" or local equivalents using Global strings
    local link = string.match(msg, "|c%x+|Hitem:.-|h%[.-%]|h|r")

    if not link then return end

    -- Extract pure patterns without link/name for robust locale matching
    local lootPatterns = {
        _G["LOOT_ITEM_SELF"],
        _G["LOOT_ITEM_PUSHED_SELF"],
        _G["LOOT_ITEM_SELF_MULTIPLE"],
        _G["LOOT_ITEM_CREATED_SELF"]
    }

    local matched = false
    for _, p in ipairs(lootPatterns) do
        -- Escape magic characters and convert %s to a wildcard match
        local cleanPattern = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", ".+")
        if string.find(msg, cleanPattern) then
            matched = true
            break
        end
    end

    if matched then
        local itemID = C_Item.GetItemInfoInstant(link)
        if itemID then
            local item = Item:CreateFromItemLink(link)
            item:ContinueOnItemLoad(function()
                local quality = select(3, C_Item.GetItemInfo(link)) or 0
                local category = self:CategorizeItem(link, quality)
                local minQuality = DesolateLootcouncil.db.profile.minLootQuality or 3

                if quality >= minQuality or category ~= "Junk/Pass" then
                    local session = DesolateLootcouncil.db.profile.session
                    local foundClaim = false

                    -- Check session.loot
                    if session.loot then
                        for _, entry in ipairs(session.loot) do
                            if entry.itemID == itemID and not entry.msgClaimed then
                                local guid = entry.sourceGUID or ""
                                if string.find(guid, "^BlizRoll%-") or string.find(guid, "^Creature%-") or string.find(guid, "^Vehicle%-") or string.find(guid, "^Manual%-") or string.find(guid, "^Reaward%-") then
                                    entry.msgClaimed = true
                                    foundClaim = true
                                    DesolateLootcouncil:DLC_Log(string.format("Loot message matched and claimed backlog item (loot): %s (GUID: %s)", link, guid))
                                    break
                                end
                            end
                        end
                    end

                    -- Check session.bidding
                    if not foundClaim and session.bidding then
                        for _, entry in ipairs(session.bidding) do
                            if entry.itemID == itemID and not entry.msgClaimed then
                                local guid = entry.sourceGUID or ""
                                if string.find(guid, "^BlizRoll%-") or string.find(guid, "^Creature%-") or string.find(guid, "^Vehicle%-") or string.find(guid, "^Manual%-") or string.find(guid, "^Reaward%-") then
                                    entry.msgClaimed = true
                                    foundClaim = true
                                    DesolateLootcouncil:DLC_Log(string.format("Loot message matched and claimed backlog item (bidding): %s (GUID: %s)", link, guid))
                                    break
                                end
                            end
                        end
                    end

                    -- Check session.awarded
                    if not foundClaim and session.awarded then
                        for _, entry in ipairs(session.awarded) do
                            if entry.itemID == itemID and not entry.msgClaimed then
                                local guid = entry.sourceGUID or ""
                                if string.find(guid, "^BlizRoll%-") or string.find(guid, "^Creature%-") or string.find(guid, "^Vehicle%-") or string.find(guid, "^Manual%-") or string.find(guid, "^Reaward%-") then
                                    entry.msgClaimed = true
                                    foundClaim = true
                                    DesolateLootcouncil:DLC_Log(string.format("Loot message matched and claimed backlog item (awarded): %s (GUID: %s)", link, guid))
                                    break
                                end
                            end
                        end
                    end

                    if foundClaim then
                        return
                    end

                    local guid = "LootMsg-" .. itemID .. "-" .. GetServerTime()
                    if self:AddSessionItem(link, guid, nil, 1, category, itemID) then
                        DesolateLootcouncil:DLC_Log(string.format(L["AUTO-ADDED from self-loot: %s"], link))
                        self:SendMessage("DLC_LOOT_WINDOW_UPDATE", DesolateLootcouncil.db.profile.session.loot)
                    end
                end
            end)
        end
    end
end

function Loot:AddSessionItem(link, itemGUID, texture, quantity, category, itemID)
    self.sessionItems = self.sessionItems or {}
    if self.sessionItems[itemGUID] then return false end
    local session = DesolateLootcouncil.db.profile.session
    session.loot = session.loot or {}
    table.insert(session.loot, {
        link = link,
        itemID = itemID,
        category = category,
        sourceGUID = itemGUID,
        stackIndex = quantity,
        texture = texture
    })
    self.sessionItems[itemGUID] = true
    session.sessionItems = self.sessionItems -- Ensure DB persistence
    return true
end

function Loot:AddManualItem(rawLink)
    if not rawLink or rawLink == "" then return end
    local itemID = self:GetItemIDFromLink(rawLink) or (C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(rawLink))
    if not itemID then return end

    local category = self:GetItemCategory(itemID)
    if not category or category == "Junk/Pass" then
        category = self:CategorizeItem(rawLink, 4) or "Tier"
    end
    local guid = "Manual-" .. itemID .. "-" .. string.format("%.3f_%d", GetTime(), math.random(1000, 9999))
    self:AddSessionItem(rawLink, guid, nil, 1, category, itemID)
    local session = DesolateLootcouncil.db.profile.session
    self:SendMessage("DLC_LOOT_WINDOW_UPDATE", session.loot)
end

function Loot:ClearLootBacklog()
    local session = DesolateLootcouncil.db.profile.session
    -- Bug 1: ONLY wipe the loot queue, NOT sessionItems.
    -- sessionItems is the dedup store that prevents re-adding the same drop
    -- when the LM opens the loot window a second time (e.g. for crests).
    -- It is only reset on addon load (OnEnable) for the full raid night.
    if session and session.loot then wipe(session.loot) end
    DesolateLootcouncil:DLC_Log(L["Loot backlog cleared (dedup store preserved)."])
end

-- --- Awarding --- --

--- Announces the award result to the group and whispers the winner.
---@param itemData table
---@param winnerName string
---@param voteType string
function Loot:BroadcastAward(itemData, winnerName, voteType)
    if not itemData then return end
    local itemLink = itemData.link or (itemData.itemID and select(2, C_Item.GetItemInfo(itemData.itemID))) or "Unknown Item"
    local winnerDisplay = DesolateLootcouncil:GetDisplayName(winnerName) or winnerName or "Unknown"
    local voteDesc = voteType or "Award"
    local msg = string.format(L["Winner of %s is %s! (%s)"], itemLink, winnerDisplay, voteDesc)

    local sendFunc = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local canRaidWarning = SafeIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))

    if IsInRaid() then
        if canRaidWarning and sendFunc then
            local ok = pcall(sendFunc, msg, "RAID_WARNING")
            if not ok then
                pcall(sendFunc, msg, "RAID")
            end
        elseif sendFunc then
            pcall(sendFunc, msg, "RAID")
        end
    elseif IsInGroup() then
        if sendFunc then
            pcall(sendFunc, msg, "PARTY")
        end
    else
        DesolateLootcouncil:Print(msg)
    end

    local isSelf = DesolateLootcouncil:SmartCompare(winnerName, "player")
    if not isSelf and DesolateLootcouncil:IsUnitOnline(winnerName) and sendFunc then
        local whisperMsg = string.format(L["You have been awarded %s! Trade me."], itemLink)
        pcall(sendFunc, whisperMsg, "WHISPER", nil, winnerName)
    end
end

--- Appends an award entry to session history and notifies peers.
---@param session table   profile.session table
---@param itemData table
---@param itemGUID string
---@param winnerName string
---@param voteType string
---@param origIndex number|nil   pre-award priority index (for re-award restoration)
---@return boolean isSelf
function Loot:RecordAward(session, itemData, itemGUID, winnerName, voteType, origIndex)
    if not session.awarded then return false end

    local isSelf = DesolateLootcouncil:SmartCompare(winnerName, "player")
    local R = DesolateLootcouncil:GetModule("Roster")
    local winnerClass = R and R:GetUnitClass(winnerName) or "WARRIOR"
    local Session = DesolateLootcouncil:GetModule("Session") --[[@as Session]]

    local entry = {
        link          = itemData.link,
        texture       = itemData.texture,
        itemID        = itemData.itemID,
        winner        = winnerName,
        winnerClass   = winnerClass,
        voteType      = voteType,
        timestamp     = GetServerTime(),
        originalIndex = origIndex,
        fullItemData  = itemData,
        votes         = Session and Session.sessionVotes and DesolateLootcouncil.Table.DeepCopy(Session.sessionVotes[itemGUID]) or {},
        traded        = isSelf,
    }
    table.insert(session.awarded, entry)

    DesolateLootcouncil.API:LogAudit("AWARD", nil, winnerName, itemData.category, string.format("Awarded %s (%s)", tostring(itemData.link or itemData.itemID), tostring(voteType)))

    if Session and Session.SendHistoryUpdate then Session:SendHistoryUpdate(entry) end

    local API = DesolateLootcouncil.API
    if API and API.SendComm then
        API:SendComm("OFFICER_AWARD_SYNC", { entry = entry })
    end

    self:SendMessage("DLC_HISTORY_UPDATED", entry)

    if Session and Session.SendRemoveItem then Session:SendRemoveItem(itemGUID) end

    return isSelf
end

--- Removes the awarded item from the live bidding list and wipes its vote/close state.
---@param session table
---@param itemGUID string
---@param removeIndex number
function Loot:CleanupAwardedItem(session, itemGUID, removeIndex)
    if removeIndex and session.bidding and session.bidding[removeIndex] then
        table.remove(session.bidding, removeIndex)
    elseif session.bidding then
        for i = #session.bidding, 1, -1 do
            local item = session.bidding[i]
            if item.sourceGUID == itemGUID or item.link == itemGUID or (item.sourceGUID and itemGUID and tostring(item.sourceGUID) == tostring(itemGUID)) or (item.itemID and itemGUID and tostring(item.itemID) == tostring(itemGUID)) then
                table.remove(session.bidding, i)
            end
        end
    end

    local Session = DesolateLootcouncil:GetModule("Session") --[[@as Session]]
    if Session then
        if Session.sessionVotes then Session.sessionVotes[itemGUID] = nil end
        if Session.closedItems then Session.closedItems[itemGUID] = nil end

        -- Purge from clientLootList on the LM so heartbeat doesn't resurrect it
        if Session.clientLootList then
            for i = #Session.clientLootList, 1, -1 do
                local item = Session.clientLootList[i]
                if item.sourceGUID == itemGUID or item.link == itemGUID or (item.sourceGUID and itemGUID and tostring(item.sourceGUID) == tostring(itemGUID)) or (item.itemID and itemGUID and tostring(item.itemID) == tostring(itemGUID)) then
                    table.remove(Session.clientLootList, i)
                end
            end
        end

        -- Invalidate session heartbeat payload cache immediately
        Session.sessionPayloadCache = nil
    end
end

function Loot:AwardItem(itemGUID, winnerName, voteType)
    local session = DesolateLootcouncil.db.profile.session
    local itemData, removeIndex

    if type(itemGUID) == "table" then
        itemData = itemGUID
        itemGUID = itemData.sourceGUID or itemData.link
    end

    if not itemData and session and session.bidding then
        for i, item in ipairs(session.bidding) do
            if (itemGUID and item.sourceGUID and item.sourceGUID == itemGUID)
                or (itemGUID and item.link and (item.link == itemGUID or item.link:find(itemGUID, 1, true) or itemGUID:find(item.link, 1, true)))
                or (item.itemID and itemGUID and (tostring(item.itemID) == tostring(itemGUID) or tostring(itemGUID):find("item:" .. tostring(item.itemID)))) then
                itemData = item; removeIndex = i; break
            end
        end
    end

    if not itemData then
        local Session = DesolateLootcouncil:GetModule("Session", true)
        if Session and Session.clientLootList then
            for i, item in ipairs(Session.clientLootList) do
                if (itemGUID and item.sourceGUID and item.sourceGUID == itemGUID)
                    or (itemGUID and item.link and (item.link == itemGUID or item.link:find(itemGUID, 1, true) or itemGUID:find(item.link, 1, true)))
                    or (item.itemID and itemGUID and (tostring(item.itemID) == tostring(itemGUID) or tostring(itemGUID):find("item:" .. tostring(item.itemID)))) then
                    itemData = item; break
                end
            end
        end
    end

    if not itemData and itemGUID then
        local link = type(itemGUID) == "string" and itemGUID or nil
        local itemID = (link and tonumber(link:match("item:(%d+)"))) or tonumber(itemGUID) or 0
        itemData = {
            link = link,
            itemID = itemID,
            sourceGUID = type(itemGUID) == "string" and itemGUID or nil,
            category = self:GetItemCategory(itemID) or "Junk/Pass",
        }
    end

    if not itemData then return end

    -- 1. Announce to raid / whisper winner
    self:BroadcastAward(itemData, winnerName, voteType)

    -- 2. Move priority (Bid only)
    local origIndex
    if voteType == "Bid" or voteType == "1" then
        local API = DesolateLootcouncil.API
        if API and API.MovePlayerToBottom then
            origIndex = API:MovePlayerToBottom(itemData.category, winnerName)
        end
    end

    -- 3. Record in history and broadcast update
    self:RecordAward(session, itemData, itemGUID, winnerName, voteType, origIndex)

    -- 4. Remove from live session
    self:CleanupAwardedItem(session, itemGUID, removeIndex)

    -- 5. Refresh monitor
    local API = DesolateLootcouncil.API
    if API and API.ShowMonitorWindow then API:ShowMonitorWindow() end

    -- 6. Refresh Voting
    if API and API.RemoveVotingItem then
        API:RemoveVotingItem(itemGUID)
    end

    local db = DesolateLootcouncil.db
    if db and db.profile and db.profile.DecayConfig then
        db.profile.DecayConfig.lastActivity = time()
        if db.global then
            db.global.activeRaidLastActivity = time()
        end
    end
end

--- Copies the original votes back onto the new item GUID so the Monitor
--- and award window reflect the previous voting state after a re-award.
--- Note: Reaward generates a NEW sourceGUID ("Reaward-..."), so votes are
--- keyed to the new GUID — the old key is intentionally abandoned.
---@param session table
---@param awardedItem table   the history entry being reverted
function Loot:RestoreVotesForReaward(session, awardedItem)
    if not awardedItem.votes then return end
    local Session = DesolateLootcouncil:GetModule("Session")
    if not Session then return end

    if not Session.sessionVotes then Session.sessionVotes = {} end
    local newGUID = session.bidding[#session.bidding].sourceGUID
    Session.sessionVotes[newGUID] = DesolateLootcouncil.Table.DeepCopy(awardedItem.votes)

    local vCount = 0
    for _ in pairs(awardedItem.votes) do vCount = vCount + 1 end
    DesolateLootcouncil:DLC_Log(string.format(L["Restored %d votes for re-awarded item."], vCount))
end

function Loot:ReawardItem(index)
    local session = DesolateLootcouncil.db.profile.session
    if not session.awarded or not session.awarded[index] then return end

    local awardedItem = session.awarded[index]

    -- 1. Push item back onto the live bidding list (generate a new GUID to avoid
    -- conflicts with the original loot-bag entry, which may have already been consumed)
    local newGUID = "Reaward-" .. (awardedItem.itemID or 0) .. "-" .. string.format("%.3f_%d", GetTime(), math.random(1000))
    local newItemData = (awardedItem.fullItemData and DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy(awardedItem.fullItemData)) or {}
    newItemData.link       = newItemData.link or awardedItem.link
    newItemData.itemID     = newItemData.itemID or awardedItem.itemID
    newItemData.texture    = newItemData.texture or awardedItem.texture
    newItemData.category   = newItemData.category or (awardedItem.fullItemData and awardedItem.fullItemData.category) or "Re-awarded"
    newItemData.stackIndex = newItemData.stackIndex or 1
    newItemData.sourceGUID = newGUID
    newItemData.isClosed   = true
    session.bidding = session.bidding or {}
    table.insert(session.bidding, newItemData)

    -- 2. Restore priority position so the original winner isn't penalised
    if awardedItem.originalIndex and awardedItem.winner then
        local Priority = DesolateLootcouncil:GetModule("Priority") --[[@as Priority]]
        if Priority and Priority.RestorePlayerPosition then
            local cat = awardedItem.fullItemData and awardedItem.fullItemData.category
            if cat then
                Priority:RestorePlayerPosition(cat, awardedItem.winner, awardedItem.originalIndex)
            end
        end
    end

    -- 3. Re-attach the original votes to the new GUID
    self:RestoreVotesForReaward(session, awardedItem)

    -- 4. Remove the history entry and log
    table.remove(session.awarded, index)
    local newItem = session.bidding[#session.bidding]
    local API = DesolateLootcouncil.API
    if API and API.SendComm then
        API:SendComm("OFFICER_REOPEN_SYNC", {
            link = awardedItem.link,
            itemID = awardedItem.itemID,
            timestamp = awardedItem.timestamp,
            itemData = newItem,
            newGUID = newGUID
        })
    end
    DesolateLootcouncil:DLC_Log(string.format(L["Re-awarded item: %s"], (awardedItem.link or "???")))

    DesolateLootcouncil.API:LogAudit("REAWARD", nil, awardedItem.winner, awardedItem.fullItemData and awardedItem.fullItemData.category, string.format("Re-awarded %s (Winner restored)", tostring(awardedItem.link or awardedItem.itemID)))

    -- 5. Broadcast the restored item so assistants see it in their Monitor
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session then
        Session.clientLootList = Session.clientLootList or {}
        table.insert(Session.clientLootList, newItem)
        if not Session.closedItems then Session.closedItems = {} end
        Session.closedItems[newGUID] = true
        Session.sessionPayloadCache = nil -- Invalidate heartbeat payload cache
        if Session.SaveSessionState then
            Session:SaveSessionState()
        end

        if Session.SendCommMessage then
            local payload = {
                command  = "LOOT_SESSION_START",
                data     = { {
                    link       = newItem.link,
                    texture    = newItem.texture,
                    itemID     = newItem.itemID,
                    sourceGUID = newItem.sourceGUID,
                    category   = newItem.category,
                    isClosed   = true,
                } },
                duration = 0,
                endTime  = 0,
                votes    = newItem.sourceGUID and { [newItem.sourceGUID] = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy(awardedItem.votes or {})) or {} } or {},
            }
            local serialized = Session:Serialize(payload)
            local channel = DesolateLootcouncil:GetBroadcastChannel()
            if channel then
                Session:SendCommMessage("DLC_Loot", serialized, channel)
            end
        end
    end

    -- 6. Broadcast history update (automatically refreshes UI_History, UI_RaidHistory, and UI_TradeList if shown)
    self:SendMessage("DLC_HISTORY_UPDATED")
    self:SendMessage("DLC_SESSION_STARTED", session.bidding, DesolateLootcouncil:AmIOfficerOrLM())

    local API = DesolateLootcouncil.API
    if API and API.ShowMonitorWindow then API:ShowMonitorWindow(true) end

    DesolateLootcouncil:Print(L["Item reverted to monitor window."])

    local db = DesolateLootcouncil.db
    if db and db.profile and db.profile.DecayConfig then
        db.profile.DecayConfig.lastActivity = time()
        if db.global then
            db.global.activeRaidLastActivity = time()
        end
    end
end

function Loot:AddTestItems()
    local testItems = {
        "item:217192:::::::20:257::::::", -- Tier (Slumbering Coil Curio)
        "item:212398:::::::20:257::::::", -- Weapons (Caustic Keeper-Crusher)
        "item:219315:::::::20:257::::::", -- Trinkets and Cantrips (Spymaster's Web)
        "item:219300:::::::20:257::::::", -- Rest (Reckless Spirit Breastplate)
        "item:13335:::::::20:257::::::",  -- Collectables (Deathcharger's Reins)
        "item:223120:::::::20:257::::::", -- Recipe (Formula: Radiant Power)
    }
    for _, itemLink in ipairs(testItems) do
        self:AddManualItem(itemLink)
    end
    DesolateLootcouncil:DLC_Log(L["Added test items to session."])
end

function Loot:ScanDisenchanters()
    local API = DesolateLootcouncil.API
    if API and API.SendVersionCheck then
        API:SendVersionCheck()
        DesolateLootcouncil:DLC_Log(L["Triggered disenchanter scan via version check."])
    end
end
