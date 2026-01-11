---@class Priority : AceModule, AceConsole-3.0, AceTimer-3.0
local Priority = DesolateLootcouncil:NewModule("Priority", "AceConsole-3.0", "AceTimer-3.0")

---@class (partial) DLC_Ref_Priority
---@field db table
---@field DLC_Log fun(self: any, msg: any, force?: boolean)
---@field GetMain fun(self: any, name: string): string
---@field GetActiveUserCount fun(self: any): number
---@field GetModule fun(self: any, name: string): any

---@type DLC_Ref_Priority
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Priority]]

function Priority:OnEnable()
    -- Ensure list structure exists in DB (Strict Persistence)
    -- Check if DB is ready
    if not DesolateLootcouncil.db or not DesolateLootcouncil.db.profile then
        -- Retry logic: If Core hasn't loaded DB yet, wait a bit.
        self:ScheduleTimer("OnEnable", 0.1)
        return
    end
    local db = DesolateLootcouncil.db.profile

    -- Crucial: Use OR to preserve existing data (fixes wipe on reload)
    db.PriorityLists = db.PriorityLists or {
        { name = "Tier",         players = {}, items = {}, buttons = { "Main Spec", "Off Spec", "Transmog", "Pass" } },
        { name = "Weapons",      players = {}, items = {}, buttons = { "BiS", "Major Sidegrade", "Minor Sidegrade", "Pass" } },
        { name = "Rest",         players = {}, items = {}, buttons = { "Main Spec", "Off Spec", "Pass" } },
        { name = "Collectables", players = {}, items = {}, buttons = { "Need", "Greed", "Pass" } }
    }

    if db.PriorityLists then
        -- DATA MIGRATION: Convert Key-Value to Array of Objects
        -- Check if it's the old format (Table with string keys)
        local isOldFormat = false
        if db.PriorityLists.Tier or db.PriorityLists.Weapons then
            isOldFormat = true
        end

        if isOldFormat then
            DesolateLootcouncil:DLC_Log("Migrating Priority Lists to Dynamic Format...")
            local old = db.PriorityLists
            local new = {}

            -- Preserve Order: Tier, Weapons, Rest, Collectables
            local order = { "Tier", "Weapons", "Rest", "Collectables" }
            for _, key in ipairs(order) do
                if old[key] then
                    table.insert(new, { name = key, players = old[key] })
                end
            end

            -- Rescue any other keys? (Unlikely, but let's stick to standard 4 for now)
            db.PriorityLists = new
        end
    end

    -- History Log Initialization
    if not db.History then db.History = {} end
    if not db.PriorityLog then db.PriorityLog = {} end

    -- DATA MIGRATION: Old names to New names + Timestamps
    if db.playerRoster and db.playerRoster.mains then
        if not db.MainRoster then db.MainRoster = {} end
        for name, _ in pairs(db.playerRoster.mains) do
            if not db.MainRoster[name] then
                db.MainRoster[name] = { addedAt = time() }
            end
        end
        db.playerRoster.mains = nil
    end

    -- Handle existing MainRoster if it's still using the old boolean format
    if db.MainRoster then
        for name, value in pairs(db.MainRoster) do
            if type(value) == "boolean" then
                db.MainRoster[name] = { addedAt = time() }
            end
        end
    end
end

-- Shuffle Helper (Fisher-Yates)
local function ShuffleTable(t)
    local n = #t
    for i = n, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- --- Globally Attached Functions ---

function Priority:GetPriorityListNames()
    if not DesolateLootcouncil.db then return {} end
    local db = DesolateLootcouncil.db.profile
    local names = {}
    if db.PriorityLists then
        for _, list in ipairs(db.PriorityLists) do
            table.insert(names, list.name)
        end
    end
    return names
end

function Priority:AddPriorityList(name)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if not name or name == "" then return end

    -- Check duplicate
    for _, list in ipairs(db.PriorityLists) do
        if list.name == name then return end
    end

    -- Create new list populated with SHUFFLED roster
    local newList = {}
    if db.MainRoster then
        for rName, _ in pairs(db.MainRoster) do
            table.insert(newList, rName)
        end
    end
    ShuffleTable(newList)

    table.insert(db.PriorityLists, { name = name, players = newList, items = {} })
    local msg = "Added new Priority List: " .. name .. " (Initialized with shuffled roster)"
    DesolateLootcouncil:DLC_Log(msg)
    self:LogPriorityChange(msg)
    self:SyncMissingPlayers() -- Auto-populate (and notifies change internally)
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Priority:RemovePriorityList(index)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists[index] then
        local removed = table.remove(db.PriorityLists, index)
        local msg = "Removed Priority List: " .. removed.name
        DesolateLootcouncil:DLC_Log(msg)
        self:LogPriorityChange(msg)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function Priority:RenamePriorityList(index, newName)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists[index] and newName ~= "" then
        db.PriorityLists[index].name = newName
        local msg = "Renamed list to: " .. newName
        DesolateLootcouncil:DLC_Log(msg)
        self:LogPriorityChange(msg)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function Priority:LogPriorityChange(msg)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if not db.History then db.History = {} end
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    local entry = string.format("[%s] %s", timestamp, msg)
    table.insert(db.History, entry)
    -- Cap history log? (Optional, but good practice). Let's keep last 100 entries.
    if #db.History > 100 then
        table.remove(db.History, 1)
    end
end

function Priority:ShuffleLists()
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    -- CLEAR HISTORY on season reset
    db.History = {}
    self:LogPriorityChange("Season Started - All lists shuffled and history cleared.")

    local mains = {}
    -- Retrieve the existing MainRoster directly from DB
    if db.MainRoster then
        for name, _ in pairs(db.MainRoster) do
            table.insert(mains, name)
        end
    end

    -- Iterate Dynamic Lists
    for _, listObj in ipairs(db.PriorityLists) do
        -- Deep copy roster to the specific list
        local newList = {}
        for _, name in ipairs(mains) do
            table.insert(newList, name)
        end
        -- Shuffle independently
        ShuffleTable(newList)
        -- Write directly to SavedVariables for immediate persistence
        listObj.players = newList
    end

    DesolateLootcouncil:DLC_Log("All " ..
        #db.PriorityLists .. " Priority Lists have been shuffled and initialized for the new season.")
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Priority:SyncMissingPlayers()
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if not db.MainRoster or not db.PriorityLists then return end

    local addedCount = 0
    local removedCount = 0

    for _, listObj in ipairs(db.PriorityLists) do
        local currentList = listObj.players
        local currentSet = {}
        for _, name in ipairs(currentList) do
            currentSet[name] = true
        end

        -- 1. Add Missing
        local missing = {}
        for name, data in pairs(db.MainRoster) do
            if not currentSet[name] then
                table.insert(missing, { name = name, addedAt = data.addedAt or 0 })
            end
        end

        table.sort(missing, function(a, b) return a.addedAt < b.addedAt end)

        for _, player in ipairs(missing) do
            table.insert(currentList, player.name)
            addedCount = addedCount + 1
            self:LogPriorityChange(string.format("Synced %s to bottom of %s list.", player.name, listObj.name))
        end

        -- 2. Remove Stale
        for i = #currentList, 1, -1 do
            local name = currentList[i]
            if not db.MainRoster[name] then
                table.remove(currentList, i)
                removedCount = removedCount + 1
                self:LogPriorityChange(string.format("Removed %s from %s list (Not in Roster).", name, listObj.name))
            end
        end
    end

    if addedCount > 0 or removedCount > 0 then
        DesolateLootcouncil:DLC_Log(string.format("Synced Lists: +%d / -%d players.",
            addedCount, removedCount), true)
    else
        DesolateLootcouncil:DLC_Log("Lists synced. No changes.", true)
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

---@param listName string
---@param playerName string
---@return number|nil
function Priority:MovePlayerToBottom(listName, playerName)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if not db.PriorityLists then return end

    -- Smart Lookup: Check if Alt
    local targetName = DesolateLootcouncil:GetModule("Roster"):GetMain(playerName)

    local targetList = nil
    for _, list in ipairs(db.PriorityLists) do
        if list.name == listName then
            targetList = list
            break
        end
    end

    if not targetList then return end

    local players = targetList.players
    local foundIndex = nil

    -- Find player (targetName)
    for i, name in ipairs(players) do
        if name == targetName then
            foundIndex = i
            break
        end
    end

    if foundIndex then
        table.remove(players, foundIndex)
        table.insert(players, targetName)

        local msg = string.format("Priority Update: %s moved to bottom of %s (Item Awarded).", targetName, listName)
        DesolateLootcouncil:DLC_Log(msg)
        self:LogPriorityChange(string.format("Awarded item to %s (%s). Priority Reset.", targetName, listName))

        -- Structured Logging
        if not db.PriorityLog then db.PriorityLog = {} end
        table.insert(db.PriorityLog, {
            time = time(),
            type = "TO_BOTTOM",
            ---@type any
            list = listName,
            ---@type any
            player = targetName,
            from = foundIndex,
            to = #players
        })

        return foundIndex
    end
    return nil
end

function Priority:RestorePlayerPosition(listName, playerName, index)
    if not DesolateLootcouncil.db then
        return
    end
    local db = DesolateLootcouncil.db.profile

    local targetList = nil
    for _, list in ipairs(db.PriorityLists) do
        if list.name == listName then
            targetList = list; break
        end
    end
    if not targetList then
        return
    end

    local players = targetList.players
    -- Find current (Alt-Aware)
    local currentIdx = nil
    local targetMain = DesolateLootcouncil:GetModule("Roster"):GetMain(playerName)

    for i, p in ipairs(players) do
        local entryMain = DesolateLootcouncil:GetModule("Roster"):GetMain(p)
        if entryMain == targetMain then
            currentIdx = i
            break
        end
    end

    if not currentIdx then
        DesolateLootcouncil:DLC_Log(string.format("Warning: Could not find %s (Main: %s) in %s.", playerName, targetMain,
            listName))
    end

    if currentIdx then
        -- 1. Conditional Logic: Skip if already at correct position
        if currentIdx == index then
            DesolateLootcouncil:DLC_Log(string.format("%s is already at the correct position (%d).", playerName, index),
                true)
            return
        end

        -- 2. Capture Indices for logging
        local savedIndex = index
        local currentIndex = currentIdx

        table.remove(players, currentIndex)

        -- 3. Clamp index (Safety)
        if savedIndex < 1 then savedIndex = 1 end
        if savedIndex > #players + 1 then savedIndex = #players + 1 end

        table.insert(players, savedIndex, playerName)

        -- 4. Generate & Output Log Message (Sanitized)
        local sIndex = tonumber(savedIndex) or -1
        local cIndex = tonumber(currentIndex) or -1
        local pName = tostring(playerName or "Unknown")
        local lName = tostring(listName or "Unknown List")

        local logMsg = string.format("Reverting %s to position %d from position %d in %s.",
            pName, sIndex, cIndex, lName)
        DesolateLootcouncil:DLC_Log(logMsg, true)
        self:LogPriorityChange(logMsg)

        -- 5. Structured Logging
        table.insert(db.PriorityLog, {
            time = time(),
            type = "RESTORE",
            list = listName,
            player = playerName,
            from = currentIndex,
            to = savedIndex
        })
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

---@param listName string
---@param origIndex number
---@param timestamp number
---@return number
function Priority:GetReversionIndex(listName, origIndex, timestamp)
    local db = DesolateLootcouncil.db.profile
    if not db.PriorityLog then return origIndex end

    local simulated = origIndex

    -- Iterate all events AFTER the timestamp
    -- PriorityLog is append-only, so just iterate
    for _, log in ipairs(db.PriorityLog) do
        if log.list == listName and log.time > timestamp then
            -- Someone moved FROM log.from TO log.to
            local f = log.from
            local t = log.to

            -- If someone Above me moves Down below me -> I go Up
            if f < simulated and t >= simulated then
                simulated = simulated - 1
                -- If someone Below me moves Up above me -> I go Down (Rare/Manual)
            elseif f > simulated and t <= simulated then
                simulated = simulated + 1
            end
        end
    end
    return simulated
end
