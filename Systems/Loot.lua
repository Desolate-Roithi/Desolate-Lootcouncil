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

    local session = DesolateLootcouncil.db.profile.session
    self.sessionItems = session.sessionItems or {} -- Persisted duplicate check
    session.sessionItems = self.sessionItems

    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")
    self:RegisterEvent("CHAT_MSG_LOOT", "OnLootMessage")

    DesolateLootcouncil:DLC_Log("Systems/Loot Loaded")

    -- Restore UI if session exists — only for the Loot Master (Bug 4)
    -- (reuse 'session' declared above — no second local needed)
    if session.loot and #session.loot > 0 and DesolateLootcouncil:AmILootMaster() then
        self:ScheduleTimer(function()
            ---@type UI_Loot
            local UI = DesolateLootcouncil:GetModule("UI_Loot")
            if UI and UI.ShowLootWindow then
                UI:ShowLootWindow(session.loot)
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

    if IsPartyLFG() or HasLFGRestrictions() then return end

    if isLM then
        local now = GetTime()
        if not self.lastAutopassSync or (now - self.lastAutopassSync) > 30 then
            self.lastAutopassSync = now
            local Comm = DesolateLootcouncil:GetModule("Comm")
            if Comm and DesolateLootcouncil.sessionAutopassActive ~= nil then
                Comm:SendSyncAutopass(DesolateLootcouncil.sessionAutopassActive)
            end
        end
    end

    -- Security Check: Explicit true required. Protects PUG players from passing accidentally.
    if not DesolateLootcouncil.sessionAutopassActive then return end

    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then return end

    local dbCat = self:GetItemCategory(itemID)
    -- If not officially registered in Item Manager, explicitly ignore it for Autopass
    if dbCat == "Junk/Pass" then return end

    if isLM then
        -- LM collects it via Need/Greed to award manually; skip BoP Collectables
        local _, _, _, _, isBoP, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
        if isBoP and dbCat == "Collectables" then
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
        -- Only pass natively
        RollOnLoot(rollID, 0) -- Pass — LM handles distribution
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
                    -- FIX: Include slot index 'i' in uniqueKey to allow multiple identical items from one boss.
                    local uniqueKey = sourceGUID .. "-" .. itemID .. "-" .. i
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

function Loot:OnLootMessage(event, msg)
    if not DesolateLootcouncil:AmILootMaster() then return end

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
            local category = self:CategorizeItem(link)
            local quality = select(3, C_Item.GetItemInfoInstant(link)) or 0
            local minQuality = DesolateLootcouncil.db.profile.minLootQuality or 3

            -- Session Items check logic to avoid double adding
            -- We use a timestamp-based key for Roll/Push wins as they lack a sourceGUID
            local guid = "Roll-" .. itemID .. "-" .. GetServerTime()

            if quality >= minQuality or category ~= "Junk/Pass" then
                if self:AddSessionItem(link, guid, nil, 1, category, itemID) then
                    DesolateLootcouncil:DLC_Log("AUTO-ADDED from self-loot: " .. link)
                    local UI = DesolateLootcouncil:GetModule("UI_Loot")
                    if UI then UI:ShowLootWindow(DesolateLootcouncil.db.profile.session.loot) end
                end
            end
        end
    end
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
    session.sessionItems = self.sessionItems -- Ensure DB persistence
    return true
end

function Loot:ClearLootBacklog()
    local session = DesolateLootcouncil.db.profile.session
    -- Bug 1: ONLY wipe the loot queue, NOT sessionItems.
    -- sessionItems is the dedup store that prevents re-adding the same drop
    -- when the LM opens the loot window a second time (e.g. for crests).
    -- It is only reset on addon load (OnEnable) for the full raid night.
    if session and session.loot then wipe(session.loot) end
    DesolateLootcouncil:DLC_Log("Loot backlog cleared (dedup store preserved).")
end

function Loot:AddManualItem(rawLink)
    local itemID = self:GetItemIDFromLink(rawLink)
    if itemID then
        local category = self:GetItemCategory(itemID)
        if category == "Junk/Pass" then category = self:CategorizeItem(rawLink) end

        -- 1. Try to get full info from the provided string (in case it's a full hyperlink)
        local _, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(rawLink)

        -- 2. Fallback to ID if needed
        if not link then
            _, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
        end

        -- 3. If STILL no link (uncached), use the provided raw string as a placeholder
        --    This will allow the UI to catch it and trigger a refresh.
        if not link then
            link = rawLink
        end

        if not icon then icon = C_Item.GetItemIconByID(itemID) end

        local session = DesolateLootcouncil.db.profile.session
        table.insert(session.loot, {
            link = link,
            itemID = itemID,
            category = category,
            sourceGUID = "Manual-" .. itemID .. "-" .. string.format("%.3f_%d", GetTime(), math.random(1000)),
            stackIndex = 1,
            texture = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        })
        DesolateLootcouncil:DLC_Log("Manually added: " .. link, true)

        local UI = DesolateLootcouncil:GetModule("UI_Loot")
        if UI then UI:ShowLootWindow(session.loot) end
    end
end

-- --- Awarding --- --

--- Announces the award result to the group and whispers the winner.
---@param itemData table
---@param winnerName string
---@param voteType string
function Loot:_BroadcastAward(itemData, winnerName, voteType)
    local winnerDisplay = DesolateLootcouncil:GetDisplayName(winnerName)
    local msg = string.format("Winner of %s is %s! (%s)", itemData.link, winnerDisplay, voteType)

    if IsInRaid() then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            C_ChatInfo.SendChatMessage(msg, "RAID_WARNING")
        else
            C_ChatInfo.SendChatMessage(msg, "RAID")
        end
    else
        DesolateLootcouncil:DLC_Log(msg)
    end

    local isSelf = DesolateLootcouncil:SmartCompare(winnerName, "player")
    if not isSelf then
        C_ChatInfo.SendChatMessage("You have been awarded " .. itemData.link .. "! Trade me.", "WHISPER", nil, winnerName)
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
function Loot:_RecordAward(session, itemData, itemGUID, winnerName, voteType, origIndex)
    if not session.awarded then return false end

    local isSelf = DesolateLootcouncil:SmartCompare(winnerName, "player")
    local _, winnerClass = UnitClassBase(winnerName)
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
        votes         = Session and Session.sessionVotes and DeepCopy(Session.sessionVotes[itemGUID]) or {},
        traded        = isSelf,
    }
    table.insert(session.awarded, entry)

    if Session and Session.SendHistoryUpdate then Session:SendHistoryUpdate(entry) end

    local UI_H = DesolateLootcouncil:GetModule("UI_History")
    if UI_H and UI_H.historyFrame and UI_H.historyFrame.frame and UI_H.historyFrame.frame:IsShown() then
        UI_H:ShowHistoryWindow()
    end

    if Session and Session.SendRemoveItem then Session:SendRemoveItem(itemGUID) end

    return isSelf
end

--- Removes the awarded item from the live bidding list and wipes its vote/close state.
---@param session table
---@param itemGUID string
---@param removeIndex number
function Loot:_CleanupAwardedItem(session, itemGUID, removeIndex)
    table.remove(session.bidding, removeIndex)
    local Session = DesolateLootcouncil:GetModule("Session") --[[@as Session]]
    if Session then
        if Session.sessionVotes then Session.sessionVotes[itemGUID] = nil end
        if Session.closedItems  then Session.closedItems[itemGUID]  = nil end
    end
end

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

    -- 1. Announce to raid / whisper winner
    self:_BroadcastAward(itemData, winnerName, voteType)

    -- 2. Move priority (Bid only)
    local origIndex
    if voteType == "Bid" or voteType == "1" then
        local Priority = DesolateLootcouncil:GetModule("Priority") --[[@as Priority]]
        if Priority and Priority.MovePlayerToBottom then
            origIndex = Priority:MovePlayerToBottom(itemData.category, winnerName)
        end
    end

    -- 3. Record in history and broadcast update
    self:_RecordAward(session, itemData, itemGUID, winnerName, voteType, origIndex)

    -- 4. Remove from live session
    if removeIndex then
        self:_CleanupAwardedItem(session, itemGUID, removeIndex)
    end

    -- 5. Refresh monitor
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
        sourceGUID = "Reaward-" ..
            (awardedItem.itemID or 0) .. "-" .. string.format("%.3f_%d", GetTime(), math.random(1000)),
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
            local newGUID = session.bidding[#session.bidding].sourceGUID

            Session.sessionVotes[newGUID] = DeepCopy(awardedItem.votes)
            local vCount = 0
            for _ in pairs(awardedItem.votes) do vCount = vCount + 1 end
            DesolateLootcouncil:DLC_Log("Restored " .. vCount .. " votes for re-awarded item.")
        end
    end

    table.remove(session.awarded, index)
    DesolateLootcouncil:DLC_Log("Re-awarded item: " .. (awardedItem.link or "???"))

    local newItem = session.bidding[#session.bidding]

    -- Refresh UIs
    local History = DesolateLootcouncil:GetModule("UI_History")
    if History then History:ShowHistoryWindow() end

    -- Open Monitor to show it's back
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
    if Monitor then Monitor:ShowMonitorWindow() end

    -- Broadcast the restored item to the raid so assistants see it again (Follow-up Fix)
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.SendCommMessage then
        local payload = {
            command = "LOOT_SESSION_START",
            data = { {
                link = newItem.link,
                texture = newItem.texture,
                itemID = newItem.itemID,
                sourceGUID = newItem.sourceGUID,
                category = newItem.category
            } },
            duration = 300,
            endTime = GetServerTime() + 300,
            votes = { [newItem.sourceGUID] = DeepCopy(awardedItem.votes or {}) }
        }
        local serialized = Session:Serialize(payload)
        local channel = DesolateLootcouncil:GetBroadcastChannel()
        if channel then
            Session:SendCommMessage("DLC_Loot", serialized, channel)
        end
    end

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
