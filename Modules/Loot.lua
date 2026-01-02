---@class Loot : AceModule, AceEvent-3.0, AceTimer-3.0
local Loot = DesolateLootcouncil:NewModule("Loot", "AceEvent-3.0", "AceTimer-3.0")
local DLC = DesolateLootcouncil


function Loot:OnInitialize()
    DesolateLootcouncil.currentSessionLoot = DesolateLootcouncil.currentSessionLoot or {}
end

function Loot:OnEnable()
    -- Link local references to the persistent DB tables
    self.sessionLoot = DLC.db.profile.session.loot
    self.lootedMobs = DLC.db.profile.session.lootedMobs

    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("LOOT_CLOSED", "OnLootClosed")

    self:Print("[DLC] Loot Module Loaded (Session Persistent)")

    -- Check if we have data to restore
    if #self.sessionLoot > 0 then
        -- Only restore if it was previously open or just always offer it?
        -- For now, let's just print that we have data.
        -- If the user wants it to auto-open, we can implement that,
        -- but usually they might just click the minimap button or slash command.
        -- However, for development speed, let's restore it if it has data.

        -- We wait a moment for UI to be ready?
        self:ScheduleTimer(function()
            ---@type UI
            local UI = DLC:GetModule("UI") --[[@as UI]]
            UI:ShowLootWindow(self.sessionLoot)
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

function Loot:ClearSession()
    -- Wipe the table contents so the reference remains valid
    wipe(self.sessionLoot)
    wipe(self.lootedMobs)

    self:Print("[DLC] Loot Session Cleared")
end

function Loot:AddManualItem(rawLink)
    -- 1. Sanitize: Ensure we have a valid link string
    if not rawLink then return end
    -- 2. Use Instant API (Synchronous - No server wait)
    -- properties: itemID, type, subtype, equipLoc, icon, classID, subclassID
    local itemID, _, _, _, icon, classID, subClassID = C_Item.GetItemInfoInstant(rawLink)
    if itemID then
        -- 3. Categorize
        local category = self:CategorizeItem(rawLink)

        -- 4. Add to Database
        local session = DesolateLootcouncil.db.profile.session
        table.insert(session.loot, {
            link = rawLink,
            itemID = itemID,
            category = category,
            sourceGUID = "Manual-Add", -- Unique marker
            stackIndex = 1,
            texture = icon,            -- Use the icon ID directly
            isManual = true
        })
        -- 5. Refresh UI
        self:Print("Manually added: " .. rawLink)
        ---@type UI
        local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
        UI:ShowLootWindow(session.loot)
    else
        self:Print("Error: Could not parse item link. Try linking it from your bags.")
    end
end

function Loot:AddTestItems()
    -- Define items with Hardcoded Names to ensure instant, correct display
    local testItems = {
        { id = 19019, cat = "Weapons",      name = "Thunderfury, Blessed Blade of the Windseeker" },
        { id = 16963, cat = "Tier",         name = "Dragonstalker's Helm" },
        { id = 16811, cat = "Collectables", name = "Bracers of Might" },
        { id = 1210,  cat = "Rest",         name = "Shadowgem" },
        { id = 192,   cat = "Junk/Pass",    name = "Martin's Thunderbrew" },
    }

    local session = DesolateLootcouncil.db.profile.session
    self:Print("Generating Test Items...")

    for i, data in ipairs(testItems) do
        -- 1. Get Texture (Instant API is always reliable for icons)
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(data.id)

        -- 2. Construct Link using the HARDCODED name
        -- This ensures the UI shows "Thunderfury" immediately, not "Item 19019"
        local link = "|cffa335ee|Hitem:" .. data.id .. "::::::::1:::::::|h[" .. data.name .. "]|h|r"

        -- 3. (Optional) Try to upgrade to a real link if available, but the hardcoded one is fine for UI testing
        local _, realLink = C_Item.GetItemInfo(data.id)
        if realLink then link = realLink end

        table.insert(session.loot, {
            link = link,
            itemID = data.id,
            category = data.cat,
            sourceGUID = "Test-Generated-" .. i,
            stackIndex = 1,
            texture = icon
        })
    end

    -- Refresh the UI
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    UI:ShowLootWindow(session.loot)
    self:Print("Test items added to session.")
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

    -- 1. Announcement
    local msg = string.format("[DLC] Winner of %s is %s!", link, winnerName)
    if IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        ---@diagnostic disable-next-line: deprecated
        SendChatMessage(msg, "RAID_WARNING")
    elseif IsInGroup() then
        ---@diagnostic disable-next-line: deprecated
        SendChatMessage(msg, "PARTY")
    else
        self:Print(msg)
    end

    -- 2. Distribution Stub
    self:Print("[DLC] Master Looter would now give item to " .. winnerName)
    -- Future: GiveMasterLoot(slot, index)

    -- 3. Store History & Cleanup
    if session.awarded then
        local _, winnerClass = UnitClass(winnerName)
        table.insert(session.awarded, {
            link = itemData.link,
            texture = itemData.texture,
            itemID = itemData.itemID,
            winner = winnerName,
            winnerClass = winnerClass, -- Store for reliable coloring
            voteType = voteType,
            timestamp = GetServerTime()
        })
    end

    -- Remove from Bidding
    if removeIndex then
        table.remove(session.bidding, removeIndex)
    end

    -- Clear Votes
    ---@type Distribution
    local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
    if Dist and Dist.sessionVotes then
        Dist.sessionVotes[itemGUID] = nil
    end

    -- 4. UI Refresh
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI then
        if UI.awardFrame then UI.awardFrame:Hide() end
        UI:ShowMonitorWindow() -- Refresh the monitor list
        if UI.ShowHistoryWindow then
            UI:ShowHistoryWindow()
        end
    end
end

function Loot:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DLC]|r " .. tostring(msg))
end
