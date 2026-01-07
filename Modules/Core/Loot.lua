---@class Loot : AceModule, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0
---@field sessionLoot table
---@field lootedMobs table
---@field OnLootOpened fun(self: Loot)
---@field OnLootClosed fun(self: Loot)
---@field OnInitialize function
---@field OnEnable function
---@field ClearLootBacklog fun(self: Loot)
---@field AddManualItem fun(self: Loot, rawLink: string)
---@field AddTestItems fun(self: Loot)
---@field CategorizeItem fun(self: Loot, itemLink: string): string
---@field AwardItem fun(self: Loot, itemGUID: string, winner: string, response: string)
---@field EndSession fun(self: Loot)
---@field MarkAsTraded fun(self: Loot, itemGUID: string, winner: string)
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
---@type Loot
local Loot = DesolateLootcouncil:NewModule("Loot", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
local DLC = DesolateLootcouncil


function Loot:OnInitialize()
    DesolateLootcouncil.currentSessionLoot = DesolateLootcouncil.currentSessionLoot or {}
end

function Loot:OnEnable()
    -- Safety Check: Ensure Core has initialized the DB
    if not DesolateLootcouncil.db or not DesolateLootcouncil.db.profile then
        self:Print("Error: Database not ready. Loot module disabled.")
        return
    end
    -- Link local references to the persistent DB tables
    self.sessionLoot = DesolateLootcouncil.db.profile.session.loot
    self.lootedMobs = DesolateLootcouncil.db.profile.session.lootedMobs

    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("LOOT_CLOSED", "OnLootClosed")

    self:Print("[DLC] Loot Module Loaded (Session Persistent)")

    -- Check if we have data to restore
    if self.sessionLoot and #self.sessionLoot > 0 then
        -- Only restore if it was previously open or just always offer it?
        -- For now, let's just print that we have data.
        -- If the user wants it to auto-open, we can implement that,
        -- but usually they might just click the minimap button or slash command.
        -- However, for development speed, let's restore it if it has data.

        -- We wait a moment for UI to be ready?
        self:ScheduleTimer(function()
            ---@type UI
            local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
            if UI and UI.ShowLootWindow then
                UI:ShowLootWindow(self.sessionLoot)
            end
        end, 1)
    end
end

function Loot:OnLootOpened()
    local DLC = DesolateLootcouncil
    local session = DLC.db.profile.session

    local itemsChanged = false
    local numItems = GetNumLootItems()
    DLC:Print("--- LOOT SCAN START (" .. numItems .. " slots) ---")
    for i = 1, numItems do
        if GetLootSlotType(i) == Enum.LootSlotType.Item then
            local sourceGUID = GetLootSourceInfo(i)
            local itemLink = GetLootSlotLink(i)
            local texture, itemName, quantity, currencyID, quality = GetLootSlotInfo(i)

            -- Force Number type for ID (Safe split to avoid bad argument #2 error)
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
                    DLC:Print("[DLC] Skipped low quality item: " .. itemLink)
                    -- Skip to next iteration (using a goto simulates 'continue' or just wrap in if)
                else
                    -- EXTRACT UNIQUE SPAWN ID (The last hex segment of the GUID)
                    -- Pattern: match the hyphen followed by hex digits at the end of the string
                    local spawnUID = sourceGUID:match("%-(%x+)$") or sourceGUID

                    for k = 1, (quantity or 1) do
                        local alreadyExists = false

                        for _, existing in ipairs(session.loot) do
                            -- Compare the Spawn Suffixes, NOT the full GUIDs
                            local existingSpawnUID = existing.sourceGUID:match("%-(%x+)$") or existing.sourceGUID

                            if existingSpawnUID == spawnUID and
                                existing.itemID == itemID and
                                existing.stackIndex == k then
                                alreadyExists = true
                                break
                            end
                        end
                        if not alreadyExists then
                            table.insert(session.loot, {
                                link = itemLink,
                                itemID = itemID,
                                category = category,
                                sourceGUID = sourceGUID, -- Keep full GUID for reference
                                stackIndex = k,
                                texture = texture
                            })

                            itemsChanged = true
                            session.lootedMobs[sourceGUID] = true

                            DLC:Print("ADDED: " .. itemName .. " (" .. k .. ")")
                            DLC:Print("   UID: " .. tostring(spawnUID))
                        end
                    end
                end
            end
        end
    end
    DLC:Print("--- SCAN END ---")
    if itemsChanged then
        ---@type UI
        local UI = DLC:GetModule("UI") --[[@as UI]]
        UI:ShowLootWindow(session.loot)
    end
end

function Loot:OnLootClosed()
    self:Print("[DLC-Loot] Window Closed, items retained")
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

    self:Print("[DLC] Loot backlog cleared.")
end

function Loot:AddManualItem(rawLink)
    -- 1. Sanitize: Ensure we have a valid link string
    if not rawLink then return end

    -- 2. Robust ID Extraction
    -- Try Instant API first
    local itemID = C_Item.GetItemInfoInstant(rawLink)

    -- Fallback: Regex (Item String)
    if not itemID then
        itemID = string.match(rawLink, "item:(%d+)")
    end

    -- Fallback: Plain Number
    if not itemID then
        itemID = tonumber(rawLink)
    end

    -- Final conversion
    itemID = tonumber(itemID)

    if itemID then
        -- 3. Categorize (Use new Safe Backend)
        local category = DesolateLootcouncil:GetItemCategory(itemID)

        -- Override with default "Rest" if backend returns nothing?
        -- Actually GetItemCategory returns "Junk/Pass".
        -- If we want to default to "Rest" for epics etc, we can check CategorizeItem?
        -- But GetItemCategory checks the *Saved Variables*.
        if category == "Junk/Pass" then
            category = self:CategorizeItem(rawLink) -- Use algorithmic fallback
        end

        -- 4. Get Display Info (Async Safe)
        local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)

        -- Fallback if not cached
        if not link then
            link = "Item " .. itemID
            -- Trigger a silent load?
            local _ = C_Item.GetItemInfo(itemID)
        end
        if not icon then
            icon = C_Item.GetItemIconByID(itemID) -- Try icon by ID
        end

        -- 5. Add to Database
        local session = DesolateLootcouncil.db.profile.session
        table.insert(session.loot, {
            link = link,
            itemID = itemID,
            category = category,
            sourceGUID = "Manual-" .. itemID .. "-" .. math.random(100), -- Unique marker
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
    -- Clear previous data to avoid duplicates
    self:ClearLootBacklog()
    DesolateLootcouncil:Print("Generating Test Items with Categories...")
    -- Define items with explicit categories
    local testData = {
        { id = "item:19019::::::", cat = "Weapons" },     -- Thunderfury
        { id = "item:16909::::::", cat = "Tier" },        -- Helm of Wrath (T2)
        { id = "item:16811::::::", cat = "Tier" },        -- Bracers of Might (T1)
        { id = "item:17076::::::", cat = "Weapons" },     -- Bonereaver's Edge
        { id = "item:5498::::::",  cat = "Collectables" } -- Small Blue Pouch (Generic Item)
    }
    for _, data in ipairs(testData) do
        -- Retrieve item info
        local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(data.id)

        if link then
            table.insert(DesolateLootcouncil.db.profile.session.loot, {
                link = link,
                itemID = tonumber(data.id:match("item:(%d+)")), -- Extract ID
                texture = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                sourceGUID = "Test-" .. math.random(10000, 99999),
                owner = UnitName("player"),
                category = data.cat -- Use the hardcoded category
            })
        else
            -- Fallback if item info isn't cached yet
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
    DesolateLootcouncil:Print("Test items added. Opening Loot Window...")
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI and UI.ShowLootWindow then
        UI:ShowLootWindow(DesolateLootcouncil.db.profile.session.loot)
    end
end

function Loot:CategorizeItem(itemLink)
    local itemID, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemLink)
    if not itemID then return "Junk/Pass" end

    -- Check configured lists
    -- Using safe access in case db isn't fully ready (methods usually safe if called after OnEnable)
    local lists = DLC.db.profile.lootLists
    if lists then
        if lists.tier[itemID] then return "Tier" end
        if lists.weapons[itemID] then return "Weapons" end
        if lists.collectables[itemID] then return "Collectables" end
    end

    -- Fallback (API)
    if classID == 2 then return "Weapons" end -- Weapon
    if classID == 4 then                      -- Armor
        -- Quality check: 0=Poor, 1=Common, 2=Uncommon, 3=Rare, 4=Epic, 5=Legendary
        local _, _, quality = C_Item.GetItemInfo(itemLink)
        if quality and quality > 1 then
            return "Rest"
        end
    end

    return "Junk/Pass"
end

function Loot:AwardItem(itemGUID, winnerName, voteType)
    -- Find the item data in session.bidding
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
    local VOTE_TEXT = { [1] = "Bis", [2] = "Major", [3] = "Minor", [4] = "Unknown" } -- Mapping for display if voteType is ID
    -- If voteType is string (e.g. from buttons), use it, otherwise map it
    local displayVote = tonumber(voteType) and (VOTE_TEXT[tonumber(voteType)] or "Vote") or voteType

    -- 1. Announcement
    local msg = string.format("[DLC] Winner of %s is %s! (%s)", link, winnerName, displayVote)
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
        self:Print(msg)
    end

    -- 2. Whisper Winner (Conditional)
    local isSelf = (winnerName == UnitName("player"))
    local whisperMsg = string.format("[DLC] You have been awarded %s! Trade me to receive it.", link)

    if not isSelf then
        C_ChatInfo.SendChatMessage(whisperMsg, "WHISPER", nil, winnerName)
    else
        self:Print("[DLC] Awarding to self (" .. link .. ").")
    end

    -- 3. Distribution Stub
    self:Print("[DLC] Master Looter would now give item to " .. winnerName)
    -- Future: GiveMasterLoot(slot, index)

    -- 3.1 Apply Penalty if Bid
    if voteType == "Bid" or voteType == "1" then
        DesolateLootcouncil:MovePlayerToBottom(itemData.category, winnerName)
    end

    -- 4. Store History & Cleanup
    if session.awarded then
        local _, winnerClass = UnitClassBase(winnerName)
        table.insert(session.awarded, {
            link = itemData.link,
            texture = itemData.texture,
            itemID = itemData.itemID,
            winner = winnerName,
            winnerClass = winnerClass, -- Store for reliable coloring
            voteType = displayVote,
            timestamp = GetServerTime(),
            traded = isSelf -- Auto-trade if self
        })

        -- Tell all raiders to remove this item
        ---@type Distribution
        local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
        if Dist and Dist.SendRemoveItem then
            Dist:SendRemoveItem(itemGUID)
        end
    end

    -- Remove from Bidding
    if removeIndex then
        table.remove(session.bidding, removeIndex)

        -- Safe removal from vote cache if module is loaded
        ---@type Distribution
        local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
        if Dist and Dist.sessionVotes then
            Dist.sessionVotes[itemGUID] = nil
        end
    end

    -- 5. Refresh UI
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI.ShowMonitorWindow then UI:ShowMonitorWindow() end
    if UI.ShowAwardWindow then UI:ShowAwardWindow(nil) end -- Close award window? or refresh
    -- Close award window actually, since item is gone
    if UI.awardFrame then UI.awardFrame:Hide() end

    self:Print("[DLC] Item awarded successfully.")

    -- Clear Votes function call (if needed globally)
    -- But since we just removed one item, maybe we don't clear ALL votes?
    -- The original code called ClearVotes here which wipes everything.
    -- session.bidding is the *list* of items. If we remove one, the others remain.
    -- Wiping ALL votes might be incorrect if multiple items are being voted on simultaneously?
    -- Taking the Safe path: The user requested ClearVotes() in EndSession(), but in MarkAsTraded (single item),
    -- we probably shouldn't wipe everything unless it's the last item?
    -- For now, respecting previous logic but fixing the scope.

    ---@type Distribution
    local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
    if Dist and Dist.ClearVotes then
        -- Dist:ClearVotes() -- Commented out to prevent wiping other items' votes during a multi-item session
    end

    -- Update UI
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI then
        -- Refresh Monitor with remaining items
        UI:ShowMonitorWindow()
    end
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
    self:Print("Bidding session ended. Items cleared from monitor.")
end

function Loot:MarkAsTraded(itemLink, winnerName)
    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.awarded then return end

    for _, award in ipairs(session.awarded) do
        -- Check for matching link and winner, AND not already traded
        if award.link == itemLink and award.winner == winnerName and not award.traded then
            award.traded = true
            self:Print(string.format("[DLC] Trade confirmed. %s marked as delivered.", itemLink))
            return -- Mark only one instance if multiple exist (oldest first due to loop order)
        end
    end
end

function Loot:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DLC]|r " .. tostring(msg))
end
