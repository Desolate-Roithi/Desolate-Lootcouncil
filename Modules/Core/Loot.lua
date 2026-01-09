---@class Loot : AceModule, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0
---@field sessionLoot table
---@field lootedMobs table
---@field sessionItems table
---@field OnLootOpened fun(self: Loot)
---@field OnLootClosed fun(self: Loot)
---@field OnStartLootRoll fun(self: Loot, event: string, rollID: number)
---@field AddSessionItem fun(self: Loot, link: string, itemGUID: string, texture: number|string, quantity: number, category: string, itemID: number): boolean
---@field OnInitialize function
---@field OnEnable function
---@field ClearLootBacklog fun(self: Loot)
---@field AddManualItem fun(self: Loot, rawLink: string)
---@field AddTestItems fun(self: Loot)
---@field CategorizeItem fun(self: Loot, itemLink: string): string
---@field AwardItem fun(self: Loot, itemGUID: string, winner: string, response: string)
---@field ReawardItem fun(self: Loot, awardIndex: number)
---@field EndSession fun(self: Loot)
---@field MarkAsTraded fun(self: Loot, itemGUID: string, winner: string)
---@class (partial) DLC_Ref_Loot
---@field db table
---@field currentSessionLoot table
---@field GetItemCategory fun(self: any, itemID: number): string
---@field AmILootMaster fun(self: any): boolean
---@field GetModule fun(self: any, name: string): any
---@field NewModule fun(self: any, name: string, ...: any): any
---@field Print fun(self: any, msg: string)
---@field GetReversionIndex fun(self: any, listName: string, origIndex: number, timestamp: number): number
---@field RestorePlayerPosition fun(self: any, listName: string, playerName: string, index: number)
---@field MovePlayerToBottom fun(self: any, listName: string, playerName: string): number|nil
---@type DLC_Ref_Loot
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Loot]]
---@type Loot
local DLC = DesolateLootcouncil
local Loot = DesolateLootcouncil:NewModule("Loot", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")

---@diagnostic disable-next-line: lowercase-global
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
    -- Safety Check: Ensure Core has initialized the DB
    if not DesolateLootcouncil.db or not DesolateLootcouncil.db.profile then
        -- Retry logic: If Core hasn't loaded DB yet, wait a bit.
        self:ScheduleTimer("OnEnable", 0.1)
        return
    end
    -- Link local references to the persistent DB tables
    self.sessionLoot = DesolateLootcouncil.db.profile.session.loot
    self.lootedMobs = DesolateLootcouncil.db.profile.session.lootedMobs

    -- Transient lookup for duplicate prevention
    self.sessionItems = {}

    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("LOOT_CLOSED", "OnLootClosed")
    self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")

    DLC:DLC_Log("Loot Module Loaded (Session Persistent)")

    -- Check if we have data to restore
    if self.sessionLoot and #self.sessionLoot > 0 then
        self:ScheduleTimer(function()
            ---@type UI
            local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
            if UI and UI.ShowLootWindow then
                UI:ShowLootWindow(self.sessionLoot)
            end
        end, 1)
    end
end

function Loot:OnStartLootRoll(event, rollID)
    local db = DesolateLootcouncil.db.profile
    if not db.enableAutoLoot then return end

    local isLM = DesolateLootcouncil:AmILootMaster()
    local link = GetLootRollItemLink(rollID)

    if isLM then
        -- Branch 1: LM Auto-Acquire
        -- Get detailed info
        local _, _, _, _, isBoP, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)

        -- Safety Check: BoP Collectables
        local cat = self:CategorizeItem(link)
        if isBoP and cat == "Collectables" then
            DesolateLootcouncil:DLC_Log("Auto-Loot Aborted: " ..
                (link or "Unknown") .. " is a BoP Collectable. Roll manually to ensure safety.", true)
            return -- Abort
        end

        if canNeed then
            RollOnLoot(rollID, 1) -- Need
            DLC:DLC_Log("LM Auto-Acquire: Rolling Need on " .. (link or "Unknown"))
        elseif canGreed then
            RollOnLoot(rollID, 2) -- Greed
            DLC:DLC_Log("LM Auto-Acquire: Rolling Greed on " .. (link or "Unknown"))
        elseif canTransmog then
            RollOnLoot(rollID, 4) -- Transmog
            DLC:DLC_Log("LM Auto-Acquire: Rolling Transmog on " .. (link or "Unknown"))
        elseif canDisenchant then
            RollOnLoot(rollID, 3) -- Disenchant
            DLC:DLC_Log("LM Auto-Acquire: Rolling DE on " .. (link or "Unknown"))
        end
    else
        -- Branch 2: Raider Auto-Pass
        RollOnLoot(rollID, 0) -- Pass
        DLC:DLC_Log("Auto-Pass: " .. (link or "Unknown"))
    end
end

function Loot:OnLootOpened()
    local DLC = DesolateLootcouncil
    local session = DLC.db.profile.session
    local debugMode = DLC.db.profile.debugMode

    -- [NEW] Raid/Debug Check
    if not IsInRaid() and not debugMode then
        DLC:DLC_Log("Loot suppression: Not in raid and debug mode off.")
        return
    end

    local itemsChanged = false
    local numItems = GetNumLootItems()
    DLC:DLC_Log("--- LOOT SCAN START (" .. numItems .. " slots) ---")
    for i = 1, numItems do
        if GetLootSlotType(i) == Enum.LootSlotType.Item then
            local sourceGUID = GetLootSourceInfo(i)
            local itemLink = GetLootSlotLink(i)
            local texture, itemName, quantity, currencyID, quality = GetLootSlotInfo(i)

            -- Force Number type for ID
            local rawID = C_Item.GetItemInfoInstant(itemLink)
            local itemID = tonumber(rawID)

            if sourceGUID and itemLink and itemID then
                -- Categorize early for filtering
                local category = self:CategorizeItem(itemLink)
                local minQuality = DLC.db.profile.minLootQuality

                -- Filter Logic:
                -- Always show Tier, Weapons, Collectables
                local isImportant = (category == "Tier" or category == "Weapons" or category == "Collectables")

                -- Check quality threshold
                if not isImportant and (quality or 0) < minQuality then
                    DLC:DLC_Log("Skipped low quality item: " .. itemLink)
                else
                    -- CONSTRUCT UNIQUE ID
                    local uniqueKey = sourceGUID .. "-" .. itemID

                    if self:AddSessionItem(itemLink, uniqueKey, texture, quantity, category, itemID) then
                        itemsChanged = true
                        session.lootedMobs[sourceGUID] = true
                        DLC:DLC_Log("ADDED: " .. itemName)
                    end
                end
            end
        end
    end
    DLC:DLC_Log("--- SCAN END ---")
    if itemsChanged then
        ---@type UI
        local UI = DLC:GetModule("UI") --[[@as UI]]
        UI:ShowLootWindow(session.loot)
    end
end

function Loot:AddSessionItem(link, itemGUID, texture, quantity, category, itemID)
    -- Critical Check: if self.sessionItems[itemGUID] then return end.
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

function Loot:RemoveSessionItem(itemGUID)
    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.loot then return end

    for i, item in ipairs(session.loot) do
        if item.sourceGUID == itemGUID then
            table.remove(session.loot, i)
            self.sessionItems[itemGUID] = nil -- Allow re-adding if looted again? Or keep it locked?
            -- Usually if removed from inbox, it means we don't want it there.
            break
        end
    end

    -- Refresh UI
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI")
    if UI and UI.ShowLootWindow then
        UI:ShowLootWindow(session.loot)
    end
end

function Loot:OnLootClosed()
    DLC:DLC_Log("Window Closed, items retained")
end

function Loot:ClearLootBacklog()
    -- This clears the "Loot Window" waiting list
    local session = DesolateLootcouncil.db.profile.session
    if session and session.loot then
        wipe(session.loot)
    end
    -- Also clear local reference just in case
    if self.sessionLoot then wipe(self.sessionLoot) end
    if self.lootedMobs then wipe(self.lootedMobs) end
    if self.sessionItems then wipe(self.sessionItems) end

    DLC:DLC_Log("Loot backlog cleared.")
end

function Loot:AddManualItem(rawLink)
    -- 1. Sanitize
    if not rawLink then return end

    -- 2. Robust ID Extraction
    local itemID = C_Item.GetItemInfoInstant(rawLink)
    if not itemID then
        itemID = string.match(rawLink, "item:(%d+)")
    end
    if not itemID then
        itemID = tonumber(rawLink)
    end
    itemID = tonumber(itemID)

    if itemID then
        -- 3. Categorize
        local category = DesolateLootcouncil:GetItemCategory(itemID)
        if category == "Junk/Pass" then
            category = self:CategorizeItem(rawLink)
        end

        -- 4. Get Display Info
        local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
        if not link then
            link = "Item " .. itemID
            local _ = C_Item.GetItemInfo(itemID)
        end
        if not icon then
            icon = C_Item.GetItemIconByID(itemID)
        end

        -- 5. Add to Database
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
        -- 6. Refresh UI
        self:Print("Manually added: " .. link)
        ---@type UI
        local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
        if UI and UI.ShowLootWindow then
            UI:ShowLootWindow(session.loot)
        end
    else
        self:Print("Error: Could not identify item ID from input: " .. tostring(rawLink))
    end
end

function Loot:AddTestItems()
    if not DesolateLootcouncil:AmILootMaster() then
        DesolateLootcouncil:Print("Error: You must be the Loot Master to generate test items.")
        return
    end
    self:ClearLootBacklog()
    DesolateLootcouncil:DLC_Log("Generating Test Items with Categories...")
    -- Define items with explicit categories
    local testData = {
        { id = "item:19019::::::", cat = "Weapons" },     -- Thunderfury
        { id = "item:16909::::::", cat = "Tier" },        -- Helm of Wrath (T2)
        { id = "item:16811::::::", cat = "Tier" },        -- Bracers of Might (T1)
        { id = "item:17076::::::", cat = "Weapons" },     -- Bonereaver's Edge
        { id = "item:5498::::::",  cat = "Collectables" } -- Small Blue Pouch (Generic Item)
    }
    for _, data in ipairs(testData) do
        local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(data.id)

        if link then
            table.insert(DesolateLootcouncil.db.profile.session.loot, {
                link = link,
                itemID = tonumber(data.id:match("item:(%d+)")),
                texture = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                sourceGUID = "Test-" .. math.random(10000, 99999),
                owner = UnitName("player"),
                category = data.cat
            })
        else
            table.insert(DesolateLootcouncil.db.profile.session.loot, {
                link = "[Loading: " .. data.id .. "]",
                itemID = tonumber(data.id:match("item:(%d+)")), -- Extract ID for safety
                texture = "Interface\\Icons\\INV_Misc_QuestionMark",
                sourceGUID = "Test-" .. math.random(10000, 99999),
                owner = UnitName("player"),
                category = data.cat
            })
        end
    end
    DesolateLootcouncil:DLC_Log("Test items added. Opening Loot Window...")
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI and UI.ShowLootWindow then
        UI:ShowLootWindow(DesolateLootcouncil.db.profile.session.loot)
    end
end

function Loot:CategorizeItem(itemLink)
    local itemID, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemLink)
    if not itemID then return "Junk/Pass" end

    -- Check configured lists (Safe access)
    local lists = DLC.db.profile.lootLists
    if lists then
        if lists.tier[itemID] then return "Tier" end
        if lists.weapons[itemID] then return "Weapons" end
        if lists.collectables[itemID] then return "Collectables" end
    end

    -- Fallback (API)
    if classID == 2 then return "Weapons" end -- Weapon
    if classID == 4 then                      -- Armor
        -- Quality check
        local _, _, quality = C_Item.GetItemInfo(itemLink)
        if quality and quality > 1 then
            return "Rest"
        end
    end

    return "Junk/Pass"
end

function Loot:AwardItem(itemGUID, winnerName, voteType)
    local session = DesolateLootcouncil.db.profile.session
    local itemData = nil
    local removeIndex = nil

    if session and session.bidding then
        for i, item in ipairs(session.bidding) do
            if item.sourceGUID == itemGUID then
                itemData = item
                removeIndex = i
                break
            end
        end
    end

    if not itemData then
        self:Print("Error: Could not find item to award.")
        return
    end

    local link = itemData.link
    local VOTE_TEXT = { [1] = "Bis", [2] = "Major", [3] = "Minor", [4] = "Unknown" }
    local displayVote = tonumber(voteType) and (VOTE_TEXT[tonumber(voteType)] or "Vote") or voteType

    -- 1. Announcement
    local msg = string.format("Winner of %s is %s! (%s)", link, winnerName, displayVote)
    if IsInRaid() then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            ---@diagnostic disable-next-line: deprecated
            SendChatMessage(msg, "RAID_WARNING")
        else
            ---@diagnostic disable-next-line: deprecated
            SendChatMessage(msg, "RAID")
        end
    elseif IsInGroup() then
        ---@diagnostic disable-next-line: deprecated
        SendChatMessage(msg, "PARTY")
    else
        DesolateLootcouncil:DLC_Log(msg)
    end

    -- 2. Whisper Winner (Conditional)
    local isSelf = (winnerName == UnitName("player"))
    local whisperMsg = string.format("You have been awarded %s! Trade me to receive it.", link)

    if not isSelf then
        C_ChatInfo.SendChatMessage(whisperMsg, "WHISPER", nil, winnerName)
    else
        DesolateLootcouncil:DLC_Log("Awarding to self (" .. link .. ").")
    end

    -- 3. Distribution Stub
    DesolateLootcouncil:DLC_Log("Master Looter would now give item to " .. winnerName)

    -- 3.1 Apply Penalty if Bid & Capture Original Index
    local origIndex = nil
    if voteType == "Bid" or voteType == "1" then
        origIndex = DesolateLootcouncil:MovePlayerToBottom(itemData.category, winnerName)
    end

    -- 4. Store History & Cleanup
    if session.awarded then
        local _, winnerClass = UnitClassBase(winnerName)

        -- Get Distribution module EARLY for snapshot
        ---@type Distribution
        local DLC_Dist = DesolateLootcouncil:GetModule("Distribution")

        table.insert(session.awarded, {
            link = itemData.link,
            texture = itemData.texture,
            itemID = itemData.itemID,
            winner = winnerName,
            winnerClass = winnerClass,
            voteType = displayVote,
            timestamp = GetServerTime(),
            originalIndex = origIndex,                                                                      -- Captured from MovePlayerToBottom
            fullItemData = itemData,                                                                        -- Store full item snapshot for re-awarding
            votes = DLC_Dist and DLC_Dist.sessionVotes and DeepCopy(DLC_Dist.sessionVotes[itemGUID]) or {}, -- Store votes
            traded = isSelf
        })

        -- Tell all raiders to remove this item
        if DLC_Dist and DLC_Dist.SendRemoveItem then
            DLC_Dist:SendRemoveItem(itemGUID)
        end
    end

    -- Remove from Bidding
    if removeIndex then
        table.remove(session.bidding, removeIndex)

        ---@type Distribution
        local DLC_Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
        if DLC_Dist and DLC_Dist.sessionVotes then
            DLC_Dist.sessionVotes[itemGUID] = nil
        end
    end

    -- 5. Refresh UI
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI.ShowMonitorWindow then UI:ShowMonitorWindow() end
    if UI.awardFrame then UI.awardFrame:Hide() end

    DesolateLootcouncil:DLC_Log("Item awarded successfully.")
end

function Loot:ReawardItem(awardIndex)
    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.awarded or not session.awarded[awardIndex] then
        return
    end

    local award = session.awarded[awardIndex]
    local itemData = award.fullItemData
    if not itemData then
        return
    end
    local itemGUID = itemData.sourceGUID

    -- 1. Restore to Bidding List
    session.bidding = session.bidding or {}
    table.insert(session.bidding, itemData)

    -- 2. Restore Votes
    ---@type Distribution
    local Dist = DesolateLootcouncil:GetModule("Distribution")
    if Dist then
        Dist.sessionVotes = Dist.sessionVotes or {}
        -- [FIX] Try multiple keys for compatibility with older history entries
        local snapshot = award.votes or award.receivedVotes or award.votesSnapshot or {}

        -- Diagnostic Logging
        local voteCount = 0
        for _ in pairs(snapshot) do voteCount = voteCount + 1 end
        DLC:DLC_Log(string.format("Restoring %d votes for item %s", voteCount, itemData.link or "???"))

        -- [NEW] Strict Task: Log the entire history item structure if it's empty
        if voteCount == 0 then
            DLC:DLC_Log("History Item has 0 votes. Raw structure follows:")
            for k, v in pairs(award) do
                DLC:DLC_Log(string.format("  Key: %s = %s", tostring(k), type(v)))
            end
        end

        Dist.sessionVotes[itemGUID] = snapshot

        -- Force Persistence immediately so reload doesn't wipe it again
        if Dist.SaveSessionState then
            Dist:SaveSessionState()
        end
    end

    -- 3. Revert Priority Position (if applicable)
    if award.originalIndex and (award.voteType == "Bid" or award.voteType == "Bis" or award.voteType == "1") then
        -- Methods are attached to the Addon object (Global API pattern in Priority.lua)
        if DesolateLootcouncil.GetReversionIndex and DesolateLootcouncil.RestorePlayerPosition then
            -- Calculate drift based on subsequent events
            local currentTarget = DesolateLootcouncil:GetReversionIndex(itemData.category, award.originalIndex,
                award.timestamp or 0)
            DesolateLootcouncil:RestorePlayerPosition(itemData.category, award.winner, currentTarget)
        end
    end

    -- 4. Remove from History
    table.remove(session.awarded, awardIndex)

    -- 5. Refresh UI
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI")
    if UI.ShowMonitorWindow then UI:ShowMonitorWindow() end
    if UI.ShowHistoryWindow then UI:ShowHistoryWindow() end -- Refresh history list

    DesolateLootcouncil:DLC_Log("RE-AWARDING: " .. (itemData.link or "Item") .. ". Monitor restored.")
end

function Loot:EndSession()
    -- This Ends the Active Bidding session
    local session = DesolateLootcouncil.db.profile.session
    if session and session.bidding then
        wipe(session.bidding)
    end

    -- Clear Votes
    ---@type Distribution
    local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
    if Dist and Dist.ClearVotes then
        Dist:ClearVotes()
    end

    -- 3. Close UI
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI and UI.CloseMasterLootWindow then
        UI:CloseMasterLootWindow()
    end

    -- 4. Notify
    DesolateLootcouncil:DLC_Log("Bidding session ended. Items cleared from monitor.", true)
end

function Loot:MarkAsTraded(itemLink, winnerName)
    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.awarded then return end

    for _, award in ipairs(session.awarded) do
        if award.link == itemLink and award.winner == winnerName and not award.traded then
            award.traded = true
            DesolateLootcouncil:DLC_Log(string.format("Trade confirmed. %s marked as delivered.", itemLink), true)
            return
        end
    end
end

function Loot:Print(msg)
    DesolateLootcouncil:DLC_Log(msg)
end
