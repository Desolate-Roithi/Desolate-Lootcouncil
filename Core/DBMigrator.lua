local _, AT = ...
if AT.abortLoad then return end

---@class DBMigrator
---@field CURRENT_SCHEMA_VERSION number
---@field SanitizeProfileDatabase fun(self: DBMigrator, db: table): boolean, number
---@field NormalizeMainRoster fun(self: DBMigrator, db: table): number
---@field NormalizeAlts fun(self: DBMigrator, db: table): number
---@field NormalizePriorityLists fun(self: DBMigrator, db: table): number
---@field NormalizeAttendanceHistory fun(self: DBMigrator, db: table): number
local DBMigrator = {
    CURRENT_SCHEMA_VERSION = 200
}

---@class (partial) DBMigratorAddon : AceAddon
---@field db table
---@field DBMigrator DBMigrator
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field NormalizeName fun(self: any, name: string): string

---@type DBMigratorAddon
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
DesolateLootcouncil.DBMigrator = DBMigrator

-- ---------------------------------------------------------------------------
-- One-Time Database Sanitization & Canonical Schema Enforcement
-- ---------------------------------------------------------------------------

--- Purges legacy/stale v1 database keys and normalizes all data to 2.0 standards.
---@param db table profile database
---@return boolean migrated
---@return number prunedKeysCount
function DBMigrator:SanitizeProfileDatabase(db)
    if not db then return false, 0 end
    local version = db.schemaVersion or 0
    if version >= self.CURRENT_SCHEMA_VERSION then
        return false, 0
    end

    local prunedCount = 0

    -- 1. Prune Obsolete v1 Legacy Root Keys
    local obsoleteKeys = {
        "Priority",
        "migrated_priority_v2",
        "migrated_roster_v2",
        "migrated_ranks_v2",
        "legacyLogs",
        "oldDecayLogs",
        "cachedItemDetails",
        "rawLootLog"
    }

    for _, key in ipairs(obsoleteKeys) do
        if db[key] ~= nil then
            db[key] = nil
            prunedCount = prunedCount + 1
        end
    end

    -- 2. Normalize MainRoster
    prunedCount = prunedCount + self:NormalizeMainRoster(db)

    -- 3. Normalize Alts
    prunedCount = prunedCount + self:NormalizeAlts(db)

    -- 4. Normalize Priority Lists
    prunedCount = prunedCount + self:NormalizePriorityLists(db)

    -- 5. Normalize Attendance History
    prunedCount = prunedCount + self:NormalizeAttendanceHistory(db)

    -- 6. Stamp Schema Version 200
    db.schemaVersion = self.CURRENT_SCHEMA_VERSION
    DesolateLootcouncil:DLC_Log(string.format("DBMigrator: Profile database upgraded to schema v%d (pruned %d legacy keys).", self.CURRENT_SCHEMA_VERSION, prunedCount))
    return true, prunedCount
end

--- Normalizes MainRoster into canonical { [Name-Realm] = { isOfficer = bool, addedAt = num } }
---@param db table
---@return number
function DBMigrator:NormalizeMainRoster(db)
    local pruned = 0
    db.MainRoster = db.MainRoster or {}

    -- Check for legacy playerRoster.mains array
    if db.playerRoster and db.playerRoster.mains then
        if type(db.playerRoster.mains) == "table" then
            for _, name in pairs(db.playerRoster.mains) do
                if type(name) == "string" and name ~= "" then
                    local norm = DesolateLootcouncil.NormalizeName and DesolateLootcouncil:NormalizeName(name) or name
                    if not db.MainRoster[norm] then
                        db.MainRoster[norm] = { isOfficer = false, addedAt = time() }
                    end
                end
            end
        end
        db.playerRoster.mains = nil
        pruned = pruned + 1
    end

    -- Normalize existing MainRoster keys
    local sanitized = {}
    for rawName, data in pairs(db.MainRoster) do
        if type(rawName) == "string" and rawName ~= "" then
            local norm = DesolateLootcouncil.NormalizeName and DesolateLootcouncil:NormalizeName(rawName) or rawName
            local entry = (type(data) == "table") and data or { isOfficer = (data == true) }
            entry.isOfficer = entry.isOfficer == true
            entry.addedAt = entry.addedAt or time()
            sanitized[norm] = entry
        else
            pruned = pruned + 1
        end
    end
    db.MainRoster = sanitized
    return pruned
end

--- Normalizes playerRoster.alts into canonical { [Alt-Realm] = "Main-Realm" }
---@param db table
---@return number
function DBMigrator:NormalizeAlts(db)
    local pruned = 0
    db.playerRoster = db.playerRoster or {}
    local rawAlts = db.playerRoster.alts or {}
    local sanitizedAlts = {}

    for rawAlt, rawMain in pairs(rawAlts) do
        if type(rawAlt) == "string" and rawAlt ~= "" and type(rawMain) == "string" and rawMain ~= "" then
            local normAlt = DesolateLootcouncil.NormalizeName and DesolateLootcouncil:NormalizeName(rawAlt) or rawAlt
            local normMain = DesolateLootcouncil.NormalizeName and DesolateLootcouncil:NormalizeName(rawMain) or rawMain
            if normAlt ~= normMain then
                sanitizedAlts[normAlt] = normMain
            else
                pruned = pruned + 1
            end
        else
            pruned = pruned + 1
        end
    end

    db.playerRoster.alts = sanitizedAlts
    return pruned
end

--- Normalizes PriorityLists into canonical array of { name = str, players = {}, items = {} }
---@param db table
---@return number
function DBMigrator:NormalizePriorityLists(db)
    local pruned = 0
    if not db.PriorityLists then
        db.PriorityLists = {
            { name = "Tier", players = {}, items = {} },
            { name = "Weapons", players = {}, items = {} },
            { name = "Rest", players = {}, items = {} },
            { name = "Collectables", players = {}, items = {} }
        }
        return 0
    end

    -- Convert legacy dictionary format to array
    if db.PriorityLists.Tier or db.PriorityLists.Weapons then
        local old = db.PriorityLists
        local newLists = {}
        local order = { "Tier", "Weapons", "Rest", "Collectables" }
        for _, key in ipairs(order) do
            if old[key] then
                local players = (type(old[key]) == "table" and (old[key].players or old[key])) or {}
                local items = (type(old[key]) == "table" and old[key].items) or {}
                table.insert(newLists, { name = key, players = players, items = items })
            end
        end
        db.PriorityLists = newLists
        pruned = pruned + 1
    end

    -- Ensure every list object has valid name, players array, items dict
    for _, list in ipairs(db.PriorityLists) do
        list.name = list.name or "List"
        list.players = list.players or list.order or {}
        list.order = nil
        list.items = list.items or {}

        -- Normalize player names in list
        for i, pName in ipairs(list.players) do
            if type(pName) == "string" and DesolateLootcouncil.NormalizeName then
                list.players[i] = DesolateLootcouncil:NormalizeName(pName)
            end
        end
    end

    return pruned
end

--- Normalizes AttendanceHistory entries to 2.0 schema
---@param db table
---@return number
function DBMigrator:NormalizeAttendanceHistory(db)
    local pruned = 0
    if not db.AttendanceHistory or type(db.AttendanceHistory) ~= "table" then
        db.AttendanceHistory = {}
        return 0
    end

    for _, entry in ipairs(db.AttendanceHistory) do
        entry.attendees = entry.attendees or {}
        entry.attendeeDetails = entry.attendeeDetails or {}
        entry.awarded = entry.awarded or entry.loot or {}
        entry.loot = nil
        entry.bossLogs = entry.bossLogs or {}
        entry.decayPenalty = entry.decayPenalty or 1
    end

    return pruned
end
