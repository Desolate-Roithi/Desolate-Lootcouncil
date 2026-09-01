local _, AT = ...
if AT.abortLoad then return end

---@class Priority : AceModule, AceConsole-3.0, AceTimer-3.0
---@field LogPriorityChange fun(self: Priority, msg: string)
---@field GetReversionIndex fun(self: Priority, listName: string, origIndex: number, timestamp: number): number
---@field RestorePlayerPosition fun(self: Priority, listName: string, playerName: string, index: number)
---@field MovePlayerToBottom fun(self: Priority, listName: string, playerName: string): number|nil
local Priority = DesolateLootcouncil:NewModule("Priority", "AceConsole-3.0", "AceTimer-3.0")

---@class (partial) DLC_Ref_Priority
---@field db table
---@field DLC_Log fun(self: any, msg: any, force?: boolean)
---@field GetMain fun(self: any, name: string): string
---@field GetActiveUserCount fun(self: any): number
---@field GetModule fun(self: any, name: string): any

---@type DLC_Ref_Priority
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Priority]]
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

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
    db.PriorityLists = db.PriorityLists or ((DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.GetDefaultPriorityLists) and DesolateLootcouncil.Constants.GetDefaultPriorityLists() or {})

    -- Season / Raid Tier Catalog Migration Check
    local activeTier = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.CATALOG_TIER) or "midnight-s2"
    if not db.catalogTier then
        -- First time setting up catalog tier: preserve existing data for the current active tier
        db.catalogTier = activeTier
    elseif db.catalogTier ~= activeTier then
        -- New raid tier/season detected: update default priority lists' items only, preserving players!
        local tierName = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.CATALOG_TIER_NAME) or activeTier
        DesolateLootcouncil:DLC_Log("New raid tier detected (" .. tierName .. "). Updating Item Manager catalog items (players preserved)...")
        local defaultLists = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.GetDefaultPriorityLists) and DesolateLootcouncil.Constants.GetDefaultPriorityLists() or {}
        if db.PriorityLists then
            for _, def in ipairs(defaultLists) do
                local found = false
                for _, existing in ipairs(db.PriorityLists) do
                    if existing.name == def.name then
                        found = true
                        existing.items = DesolateLootcouncil.Table.DeepCopy(def.items or {})
                        break
                    end
                end
                if not found then
                    table.insert(db.PriorityLists, def)
                end
            end
        else
            db.PriorityLists = defaultLists
        end
        db.catalogTier = activeTier
    end

    -- Self-healing check: Repair lists corrupted with 1..N item IDs from legacy array-compaction export bug
    if db.PriorityLists then
        local defaultLists = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.GetDefaultPriorityLists) and DesolateLootcouncil.Constants.GetDefaultPriorityLists() or {}
        for _, list in ipairs(db.PriorityLists) do
            if list.items and next(list.items) then
                local isCorruptedSequential = true
                local count = 0
                for id, _ in pairs(list.items) do
                    local num = tonumber(id)
                    count = count + 1
                    if not num or num > 200 then
                        isCorruptedSequential = false
                        break
                    end
                end
                if isCorruptedSequential and count > 0 then
                    for _, def in ipairs(defaultLists) do
                        if def.name == list.name and def.items then
                            list.items = DesolateLootcouncil.Table.DeepCopy(def.items)
                            DesolateLootcouncil:DLC_Log("Self-healed corrupted Item Manager items for list: " .. tostring(list.name))
                            break
                        end
                    end
                end
            end
        end
    end

    -- Audit Log is managed by Systems/Audit.lua and DBMigrator
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

--- Returns the PriorityList object matching the name or index.
---@param listNameOrIndex string|number
---@return table?
function Priority:GetPriorityList(listNameOrIndex)
    if not DesolateLootcouncil.db then return nil end
    local db = DesolateLootcouncil.db.profile
    if not db or not db.PriorityLists then return nil end
    if type(listNameOrIndex) == "number" then
        return db.PriorityLists[listNameOrIndex]
    elseif type(listNameOrIndex) == "string" then
        for _, l in ipairs(db.PriorityLists) do
            if l.name == listNameOrIndex then return l end
        end
    end
    return nil
end

function Priority:AddPriorityList(name)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if not name or name == "" then return end

    -- Check duplicate
    for _, list in ipairs(db.PriorityLists) do
        if list.name == name then return end
    end

    -- Create new list populated with existing list's order or roster
    local newList = {}
    if #db.PriorityLists > 0 and db.PriorityLists[1].players and #db.PriorityLists[1].players > 0 then
        for _, p in ipairs(db.PriorityLists[1].players) do
            table.insert(newList, p)
        end
    elseif db.MainRoster then
        for rName, _ in pairs(db.MainRoster) do
            table.insert(newList, rName)
        end
        DesolateLootcouncil.Math.ShuffleTable(newList)
    end

    table.insert(db.PriorityLists, { name = name, players = newList, items = {} })
    DesolateLootcouncil.API:MarkPriorityDirty(name)
    local msg = string.format(L["Added new Priority List: %s"], name)
    DesolateLootcouncil:DLC_Log(msg)
    self:LogPriorityChange(msg)
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Priority:RemovePriorityList(index)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists[index] then
        local removed = table.remove(db.PriorityLists, index)
        DesolateLootcouncil.API:MarkPriorityDirty(removed.name)
        local msg = string.format(L["Removed Priority List: %s"], removed.name)
        DesolateLootcouncil:DLC_Log(msg)
        self:LogPriorityChange(msg)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function Priority:RenamePriorityList(index, newName)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists[index] and newName ~= "" then
        local oldName = db.PriorityLists[index].name
        db.PriorityLists[index].name = newName
        DesolateLootcouncil.API:MarkPriorityDirty(newName)
        if oldName then DesolateLootcouncil.API:MarkPriorityDirty(oldName) end
        local msg = string.format(L["Renamed list to: %s"], newName)
        DesolateLootcouncil:DLC_Log(msg)
        self:LogPriorityChange(msg)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function Priority:LogPriorityChange(msg)
    local Audit = DesolateLootcouncil:GetModule("Audit", true)
    if Audit and Audit.Log then
        Audit:Log("PRIO_CHANGE", nil, nil, nil, msg)
    end
end

function Priority:ShuffleLists()
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    self:LogPriorityChange("Season Started - All lists shuffled.")

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
        DesolateLootcouncil.Math.ShuffleTable(newList)
        -- Write directly to SavedVariables for immediate persistence
        listObj.players = newList
        DesolateLootcouncil.API:MarkPriorityDirty(listObj.name)
    end

    DesolateLootcouncil:DLC_Log("All " ..
        #db.PriorityLists .. " Priority Lists have been shuffled and initialized for the new season.")
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Priority:GetMissingPlayers()
    if not DesolateLootcouncil.db then return {} end
    local db = DesolateLootcouncil.db.profile
    if not db.MainRoster or not db.PriorityLists then return {} end

    local missingOverall = {}
    local missingSet = {}

    for _, listObj in ipairs(db.PriorityLists) do
        local currentScoredSet = {}
        for _, pName in ipairs(listObj.players or {}) do
            local score = DesolateLootcouncil:GetScoreName(pName)
            if score then currentScoredSet[score] = true end
        end

        for name in pairs(db.MainRoster) do
            local nameScore = DesolateLootcouncil:GetScoreName(name)
            if nameScore and not currentScoredSet[nameScore] then
                if not missingSet[name] then
                    missingSet[name] = true
                    table.insert(missingOverall, name)
                end
            end
        end
    end

    table.sort(missingOverall)
    return missingOverall
end

function Priority:NotifyIfPlayersMissing()
    if not DesolateLootcouncil:AmILootMaster() then return end
    local missing = self:GetMissingPlayers()
    if #missing > 0 then
        local namesStr = table.concat(missing, ", ")
        local msg = string.format(L["Notice: %d player(s) in Main roster are missing from priority lists (%s). Click 'Sync Missing Players' in Priority settings to append them."], #missing, namesStr)
        DesolateLootcouncil:DLC_Log(msg, true)
    end
end

function Priority:SyncMissingPlayers()
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if not db.MainRoster or not db.PriorityLists then return end

    local addedCount = 0
    local removedCount = 0

    for _, listObj in ipairs(db.PriorityLists) do
        local currentList = listObj.players or listObj.order or {}
        local listChanged = false

        -- 1. Add Missing (O(N+M) using Scored Sets)
        local currentScoredSet = {}
        for _, pName in ipairs(currentList) do
            local score = DesolateLootcouncil:GetScoreName(pName)
            if score then currentScoredSet[score] = true end
        end

        local missing = {}
        for name, data in pairs(db.MainRoster) do
            local nameScore = DesolateLootcouncil:GetScoreName(name)
            if nameScore and not currentScoredSet[nameScore] then
                table.insert(missing, { name = name, addedAt = data.addedAt or 0 })
            end
        end

        table.sort(missing, function(a, b)
            if a.addedAt ~= b.addedAt then
                return a.addedAt < b.addedAt
            end
            return tostring(a.name) < tostring(b.name)
        end)

        for _, player in ipairs(missing) do
            table.insert(currentList, player.name)
            addedCount = addedCount + 1
            listChanged = true
            self:LogPriorityChange(string.format("Synced %s to bottom of %s list.",
                DesolateLootcouncil:GetDisplayName(player.name), listObj.name))
        end

        -- 2. Remove Stale (Check against db.MainRoster directly to ensure Alts are removed)
        for i = #currentList, 1, -1 do
            local pName = currentList[i]
            local isMain = false
            for mName, _ in pairs(db.MainRoster) do
                if DesolateLootcouncil:SmartCompare(mName, pName) then
                    isMain = true
                    break
                end
            end

            if not isMain then
                table.remove(currentList, i)
                removedCount = removedCount + 1
                listChanged = true
                self:LogPriorityChange(string.format("Removed %s from %s list (Not a Main).",
                    Ambiguate(pName, "none"), listObj.name))
            end
        end

        if listChanged then
            DesolateLootcouncil.API:MarkPriorityDirty(listObj.name)
        end
    end

    if addedCount > 0 or removedCount > 0 then
        DesolateLootcouncil:DLC_Log("Synced Lists: All missing players removed/added")
    else
        DesolateLootcouncil:DLC_Log("Lists synced. No changes.")
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

    -- Smart Lookup: Check if Alt (nil-guarded; Roster may not be enabled at cold load)
    local RosterSys = DesolateLootcouncil:GetModule("Roster")
    local targetName = RosterSys and RosterSys:GetMain(playerName) or playerName

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
        if DesolateLootcouncil:SmartCompare(name, targetName) then
            foundIndex = i
            break
        end
    end

    if foundIndex then
        table.remove(players, foundIndex)
        table.insert(players, targetName)
        DesolateLootcouncil.API:MarkPriorityDirty(listName)

        local msg = string.format("Priority Update: %s moved to bottom of %s (Item Awarded).",
            DesolateLootcouncil:GetDisplayName(targetName), listName)
        DesolateLootcouncil:DLC_Log(msg)
        self:LogPriorityChange(string.format("Awarded item to %s (%s). Priority Reset.",
            DesolateLootcouncil:GetDisplayName(targetName), listName))

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

        local Audit = DesolateLootcouncil:GetModule("Audit", true)
        if Audit and Audit.Log then
            Audit:Log("TO_BOTTOM", nil, targetName, listName, string.format("Rank %d -> %d", foundIndex, #players))
        end

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
    -- Find current (Alt-Aware, nil-guarded)
    local currentIdx = nil
    local RosterSys = DesolateLootcouncil:GetModule("Roster")
    local targetMain = RosterSys and RosterSys:GetMain(playerName) or playerName

    for i, p in ipairs(players) do
        if DesolateLootcouncil:SmartCompare(p, targetMain) then
            currentIdx = i
            break
        end
    end

    if not currentIdx then
        DesolateLootcouncil:DLC_Log(string.format("Warning: Could not find %s (Main: %s) in %s.",
            DesolateLootcouncil:GetDisplayName(playerName),
            DesolateLootcouncil:GetDisplayName(targetMain),
            listName))
    end

    if currentIdx then
        -- 1. Conditional Logic: Skip if already at correct position
        if currentIdx == index then
            DesolateLootcouncil:DLC_Log(string.format("%s is already at the correct position (%d).",
                DesolateLootcouncil:GetDisplayName(playerName), index), true)
            return
        end

        -- 2. Capture Indices for logging
        local savedIndex = index
        local currentIndex = currentIdx

        table.remove(players, currentIndex)

        -- 3. Clamp index (Safety)
        if savedIndex < 1 then savedIndex = 1 end
        if savedIndex > #players + 1 then savedIndex = #players + 1 end

        table.insert(players, savedIndex, targetMain)
        DesolateLootcouncil.API:MarkPriorityDirty(listName)

        -- 4. Generate & Output Log Message (Sanitized)
        local sIndex = tonumber(savedIndex) or -1
        local cIndex = tonumber(currentIndex) or -1
        local pName = tostring(targetMain or "Unknown")
        local lName = tostring(listName or "Unknown List")

        local logMsg = string.format("Reverting %s to position %d from position %d in %s.",
            DesolateLootcouncil:GetDisplayName(pName), sIndex, cIndex, lName)
        DesolateLootcouncil:DLC_Log(logMsg, true)
        self:LogPriorityChange(logMsg)

        -- 5. Structured Logging
        if not db.PriorityLog then db.PriorityLog = {} end
        table.insert(db.PriorityLog, {
            time = time(),
            type = "RESTORE",
            list = listName,
            player = targetMain,
            from = currentIndex,
            to = savedIndex
        })

        local Audit = DesolateLootcouncil:GetModule("Audit", true)
        if Audit and Audit.Log then
            Audit:Log("RESTORE", nil, targetMain, listName, string.format("Rank %d -> %d", currentIndex, savedIndex))
        end

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
        if log.list == listName and log.time >= timestamp then
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

--- Applies a received priority sync payload from the Loot Master.
--- Only the player list and item list are overwritten; all other list
--- fields (name, buttons) are preserved so local UI config is intact.
---@param syncedLists table  Array of { name, players, items } from the LM
function Priority:ReceivePrioritySync(syncedLists)
    if not syncedLists or type(syncedLists) ~= "table" then return end
    local db = DesolateLootcouncil.db.profile
    if not db then return end
    if not db.PriorityLists then db.PriorityLists = {} end

    local updated = 0
    for _, incoming in ipairs(syncedLists) do
        local found = false
        for _, localList in ipairs(db.PriorityLists) do
            if localList.name == incoming.name then
                -- Deep copy players
                localList.players = DesolateLootcouncil.Table.DeepCopy(incoming.players or {})
                -- Deep copy items
                localList.items = DesolateLootcouncil.Table.DeepCopy(incoming.items or {})
                updated = updated + 1
                found = true
                break
            end
        end

        if not found then
            table.insert(db.PriorityLists, {
                name = incoming.name,
                players = DesolateLootcouncil.Table.DeepCopy(incoming.players or {}),
                items = DesolateLootcouncil.Table.DeepCopy(incoming.items or {})
            })
            updated = updated + 1
        end
    end

    DesolateLootcouncil:DLC_Log(string.format(
        "Priority Sync received from LM. Updated %d list(s).", updated))
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

--- Bottom-to-top bubble-down algorithm for a single priority list.
--- Absent players are each moved `penalty` positions toward the bottom.
--- Processing back-to-front prevents earlier shifts from corrupting later indices.
---@param listObj table   A PriorityList object { name, players, ... }
---@param penalty  number Positions to decay each absent player
---@param absentMap table  Map of absent player names { [playerName] = true }
function Priority:CalculateListDecay(listObj, penalty, absentMap)
    if not listObj then return end
    if type(listObj) == "string" or type(listObj) == "number" then
        listObj = self:GetPriorityList(listObj)
    end
    if not listObj or type(listObj) ~= "table" then return end
    local listName = listObj.name or "Unknown"
    local players = listObj.players or listObj.order or {}
    penalty = tonumber(penalty) or 1
    absentMap = absentMap or {}

    if penalty <= 0 or #players <= 1 then return end

    -- Check if there is any attendance divergence (at least 1 absent and at least 1 present)
    local hasAbsent = false
    local hasPresent = false
    for _, name in ipairs(players) do
        if absentMap[name] then
            hasAbsent = true
        else
            hasPresent = true
        end
    end

    -- If no players were absent or all players were absent, relative priority does not change
    if not hasAbsent or not hasPresent then
        DesolateLootcouncil:DLC_Log("Decay skipped for [" .. listName .. "]: No relative attendance differences.")
        return
    end

    -- Record initial positions for audit logging
    local initialPos = {}
    for pos, name in ipairs(players) do
        initialPos[name] = pos
    end

    -- Shallow-copy current list
    local newList = {}
    for _, name in ipairs(players) do
        table.insert(newList, name)
    end

    DesolateLootcouncil:DLC_Log("Processing Decay for Category: [" .. listName .. "] with " .. #newList .. " entries, penalty: " .. penalty)

    -- Stable step-wise decay:
    -- Each absent player drops past up to `penalty` PRESENT players immediately behind them.
    -- Absent players never pass other absent players, preventing circular rollover.
    for _ = 1, penalty do
        for i = #newList - 1, 1, -1 do
            local currentName = newList[i]
            local nextName = newList[i + 1]
            if absentMap[currentName] and not absentMap[nextName] then
                newList[i] = nextName
                newList[i + 1] = currentName
            end
        end
    end

    -- Audit and log changes for any player whose rank shifted
    local Audit = DesolateLootcouncil:GetModule("Audit", true)
    for newPos, name in ipairs(newList) do
        local oldPos = initialPos[name]
        if oldPos and oldPos ~= newPos then
            local displayName = DesolateLootcouncil:GetDisplayName(name)
            local stateStr = absentMap[name] and "absence decay" or "attendance advancement"
            local logMsg = string.format(
                L["[Decay] %s moved from position #%d to #%d in %s list (+%d decay for absence)."],
                displayName, oldPos, newPos, listName, penalty
            )
            DesolateLootcouncil:DLC_Log(logMsg)
            self:LogPriorityChange(logMsg)

            if Audit and Audit.Log then
                Audit:Log("DECAY", nil, name, listName, string.format("Moved %d -> %d (%s)", oldPos, newPos, stateStr))
            end
        end
    end

    -- Diagnostic logging (top 5 slots)
    if #newList > 0 then
        DesolateLootcouncil:DLC_Log(" >> Sort Winner Rank 1: " .. DesolateLootcouncil:GetDisplayName(newList[1]))
    end
    DesolateLootcouncil:DLC_Log(" --- Final Standings for [" .. listName .. "] ---")
    for k = 1, math.min(5, #newList) do
        local stateStr = absentMap[newList[k]] and "(Absent)" or "(Present)"
        DesolateLootcouncil:DLC_Log("#" .. k .. ": " .. DesolateLootcouncil:GetDisplayName(newList[k]) .. " " .. stateStr)
    end

    -- Write the sorted result back into the DB object in-place
    listObj.players = newList
    DesolateLootcouncil.API:MarkPriorityDirty(listName)
end

-- ---------------------------------------------------------------------------
-- Manual Priority Moves & Decay Pattern Parsing
-- ---------------------------------------------------------------------------

--- Moves a player within a priority list and logs the change.
---@param listKey number|string  Index or key of the priority list
---@param fromIndex number
---@param toIndex number
function Priority:MovePlayerInList(listKey, fromIndex, toIndex)
    local list = self:GetPriorityList(listKey)
    if not list then return end
    local players = list.players or list.order
    if not players then return end

    if fromIndex < 1 or fromIndex > #players or toIndex < 1 or toIndex > #players then return end

    local player = table.remove(players, fromIndex)
    table.insert(players, toIndex, player)

    local msg = string.format("Manual Override: Moved %s from %d to %d in %s.", player, fromIndex, toIndex, list.name or tostring(listKey))
    self:LogPriorityChange(msg)

    local Audit = DesolateLootcouncil:GetModule("Audit", true)
    if Audit and Audit.Log then
        Audit:Log("PRIO_REORDER", nil, player, list.name or tostring(listKey), string.format("Rank %d -> %d", fromIndex, toIndex))
    end

    if list.name and DesolateLootcouncil.API and DesolateLootcouncil.API.MarkPriorityDirty then
        DesolateLootcouncil.API:MarkPriorityDirty(list.name)
    end
end
Priority.MovePlayerInPriorityList = Priority.MovePlayerInList

--- Returns a list of matchers and tags for decay log messages across all registered and active locales.
---@return table
function Priority:GetDecayPatterns()
    local rawKey = "[Decay] %s moved from position #%d to #%d in %s list (+%d decay for absence)."
    local templates = {}

    local currentL = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil", true)
    if currentL and currentL[rawKey] and type(currentL[rawKey]) == "string" then
        templates[currentL[rawKey]] = true
    end
    templates[rawKey] = true

    local AceLocale = LibStub("AceLocale-3.0", true)
    if AceLocale and AceLocale.apps then
        for _, appLocales in pairs(AceLocale.apps) do
            if type(appLocales) == "table" then
                for _, locTable in pairs(appLocales) do
                    if type(locTable) == "table" and locTable[rawKey] and type(locTable[rawKey]) == "string" then
                        templates[locTable[rawKey]] = true
                    end
                end
            end
        end
    end

    local list = {}
    for template in pairs(templates) do
        local tag = template:match("^(%b[])") or "[Decay]"

        local p = template
        p = p:gsub("%%s", "___STR___", 1)
        p = p:gsub("%%d", "___NUM___", 1)
        p = p:gsub("%%d", "___NUM___", 1)
        p = p:gsub("%%s", "___ANY___", 1)
        p = p:gsub("%%d", "___PEN___", 1)

        p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

        p = p:gsub("___STR___", "(.-)")
        p = p:gsub("___NUM___", "%%d+")
        p = p:gsub("___ANY___", ".-")
        p = p:gsub("___PEN___", "(%%d+)")

        table.insert(list, {
            tag = tag,
            matchPattern = p,
            template = template
        })
    end

    return list
end

--- Checks if a log message string represents an automated decay event in any registered language.
---@param str string
---@return boolean
function Priority:IsDecayLogMessage(str)
    if type(str) ~= "string" or str == "" then return false end
    local patterns = self:GetDecayPatterns()
    for _, item in ipairs(patterns) do
        if str:find(item.tag, 1, true) then
            return true
        end
    end
    return str:find("[Decay]", 1, true) ~= nil or str:find("[Verfall]", 1, true) ~= nil
end

--- Parses player name and penalty from a decay log message string in any registered language.
---@param str string
---@return string? playerName, number? penalty
function Priority:ParseDecayLogMessage(str)
    if type(str) ~= "string" or str == "" then return nil, nil end
    local cleanStr = str:gsub("^%[[^%]]+%]%s*", "")
    local patterns = self:GetDecayPatterns()
    for _, item in ipairs(patterns) do
        local pName, pPen = cleanStr:match(item.matchPattern)
        if pName then
            return pName, tonumber(pPen)
        end
    end
    local pName, pPen = cleanStr:match("%[Decay%]%s+(.-)%s+moved from position #%d+ to #%d+ in .- %(%+(%d+)")
    if not pName then
        pName, pPen = cleanStr:match("%[Verfall%]%s+(.-)%s+wurde von Position #%d+ auf #%d+ in .- %(%+(%d+)")
    end
    return pName, tonumber(pPen)
end

