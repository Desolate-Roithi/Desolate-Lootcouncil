local _, AT = ...
if AT.abortLoad then return end

---@class DBMigrator
---@field CURRENT_SCHEMA_VERSION number
---@field SanitizeProfileDatabase fun(self: DBMigrator, db: table): boolean, number
---@field NormalizeMainRoster fun(self: DBMigrator, db: table): number
---@field NormalizeAlts fun(self: DBMigrator, db: table): number
---@field NormalizePriorityLists fun(self: DBMigrator, db: table): number
---@field NormalizeAttendanceHistory fun(self: DBMigrator, db: table): number
---@field NormalizeRosterKeys fun(self: DBMigrator, db: table): number
---@field NormalizeLegacyAttendeeDetails fun(self: DBMigrator, db: table): number
local DBMigrator = {
    CURRENT_SCHEMA_VERSION = 201
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

    -- 6. Normalize Audit Log (Migrate legacy PriorityLog)
    prunedCount = prunedCount + self:NormalizeAuditLog(db)

    -- 7. Re-key roster entries to full Name-Realm (schema 201)
    prunedCount = prunedCount + self:NormalizeRosterKeys(db)

    -- 8. Canonicalize attendeeDetails schema (schema 201)
    prunedCount = prunedCount + self:NormalizeLegacyAttendeeDetails(db)

    -- 9. Stamp Schema Version 201
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
        db.PriorityLists = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.GetDefaultPriorityLists) and DesolateLootcouncil.Constants.GetDefaultPriorityLists() or {
            { name = "Tier", players = {}, items = {} },
            { name = "Weapons", players = {}, items = {} },
            { name = "Rest", players = {}, items = {} },
            { name = "Collectables", players = {}, items = {} },
            { name = "Trinkets and Cantrips", players = {}, items = {} },
            { name = "Recipes", players = {}, items = {} }
        }
        return 0
    end

    -- Convert legacy dictionary format to array
    local isDict = false
    for k, _ in pairs(db.PriorityLists) do
        if type(k) == "string" then
            isDict = true
            break
        end
    end

    if isDict then
        local old = db.PriorityLists
        local newLists = {}
        local order = { "Tier", "Weapons", "Rest", "Collectables", "Trinkets and Cantrips", "Recipes" }
        local seen = {}

        -- 1. Insert standard lists first if present
        for _, key in ipairs(order) do
            if old[key] then
                local players = (type(old[key]) == "table" and (old[key].players or old[key])) or {}
                local items = (type(old[key]) == "table" and old[key].items) or {}
                table.insert(newLists, { name = key, players = players, items = items })
                seen[key] = true
            end
        end

        -- 2. Insert any user-defined custom lists dynamically
        for key, val in pairs(old) do
            if type(key) == "string" and not seen[key] then
                local players = (type(val) == "table" and (val.players or val)) or {}
                local items = (type(val) == "table" and val.items) or {}
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

        -- Extract decay info from legacy SessionPositionLog if present
        local posKey = entry.sessionID and tostring(entry.sessionID)
        local splBucket = posKey and db.SessionPositionLog and db.SessionPositionLog[posKey]
        if splBucket and type(splBucket) == "table" then
            if not entry.decayAbsent then entry.decayAbsent = {} end
            for _, logMsg in ipairs(splBucket) do
                if type(logMsg) == "string" and (logMsg:find("[Decay]", 1, true) or logMsg:find("[Verfall]", 1, true)) then
                    local _, pName, pPen = logMsg:match("%[.-%]%s*%[(.-)%]%s*(.-)%s+moved from position #%d+ to #%d+ in .- %(%+(%d+)")
                    if not pName then
                        _, pName, pPen = logMsg:match("%[.-%]%s*%[(.-)%]%s*(.-)%s+wurde von Position #%d+ auf #%d+ in .- %(%+(%d+)")
                    end
                    if not pName then
                        pName, pPen = logMsg:match("%[.-%]%s*(.-)%s+moved from position #%d+ to #%d+ in .- %(%+(%d+)")
                    end
                    if not pName then
                        pName, pPen = logMsg:match("%[.-%]%s*(.-)%s+wurde von Position #%d+ auf #%d+ in .- %(%+(%d+)")
                    end
                    if pName and pName ~= "" then
                        entry.decayAbsent[pName] = true
                        entry.decayApplied = 1
                        if pPen then entry.decayPenalty = tonumber(pPen) or entry.decayPenalty end
                    end
                end
            end
        end
    end

    return pruned
end

--- Normalizes AuditLog from legacy PriorityLog, SessionPositionLog, and AttendanceHistory
---@param db table
---@return number
function DBMigrator:NormalizeAuditLog(db)
    local migrated = 0
    db.AuditLog = db.AuditLog or {}

    -- 1. Migrate PriorityLog
    if db.PriorityLog and type(db.PriorityLog) == "table" and #db.PriorityLog > 0 then
        for _, item in ipairs(db.PriorityLog) do
            if type(item) == "table" then
                table.insert(db.AuditLog, {
                    t   = item.time or time(),
                    d   = date("%Y-%m-%d %H:%M:%S", item.time or time()),
                    act = item.type or "PRIO_MOVE",
                    by  = "Legacy",
                    p   = item.player,
                    l   = item.list,
                    det = string.format("Rank %s -> %s", tostring(item.from or ""), tostring(item.to or "")),
                    h   = ""
                })
                migrated = migrated + 1
            elseif type(item) == "string" then
                local dateStr, detStr = item:match("%[(.-)%]%s*(.*)")
                table.insert(db.AuditLog, {
                    t   = time(),
                    d   = dateStr or date("%Y-%m-%d %H:%M:%S"),
                    act = "LEGACY_LOG",
                    by  = "Legacy",
                    det = (detStr and detStr ~= "") and detStr or item,
                    h   = ""
                })
                migrated = migrated + 1
            end
        end
        db.PriorityLog = nil
    end

    -- 2. Migrate non-decay SessionPositionLog entries into AuditLog
    if db.SessionPositionLog and type(db.SessionPositionLog) == "table" then
        for sID, bucket in pairs(db.SessionPositionLog) do
            if type(bucket) == "table" then
                for _, logMsg in ipairs(bucket) do
                    if type(logMsg) == "string" and not (logMsg:find("[Decay]", 1, true) or logMsg:find("[Verfall]", 1, true)) then
                        table.insert(db.AuditLog, {
                            t   = tonumber(sID) or time(),
                            d   = date("%Y-%m-%d %H:%M:%S", tonumber(sID) or time()),
                            act = "POSITION_CHANGE",
                            by  = "Legacy",
                            det = logMsg,
                            sID = tostring(sID),
                            h   = ""
                        })
                        migrated = migrated + 1
                    end
                end
            end
        end
        db.SessionPositionLog = nil
    end

    -- 3. Backfill missing historical entries from AttendanceHistory
    if db.AttendanceHistory and type(db.AttendanceHistory) == "table" then
        local realmName = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
        local function CanonName(n)
            if not n or n == "" or n == "Raid" then return n end
            if not n:find("-") and realmName ~= "" then return n .. "-" .. realmName end
            return n
        end

        local function CountKeys(t)
            if type(t) ~= "table" then return 0 end
            local c = 0
            for _ in pairs(t) do c = c + 1 end
            return c
        end

        local existing = {}
        for _, entry in ipairs(db.AuditLog) do
            if entry.det then
                existing[tostring(entry.det)] = true
            end
            local sig = string.format("%s_%s_%s", tostring(entry.act), tostring(entry.p), tostring(entry.sID or ""))
            existing[sig] = true
        end

        for _, session in ipairs(db.AttendanceHistory) do
            local sID = session.sessionID and tostring(session.sessionID)
            local sessDate = session.date or (session.sessionID and type(session.sessionID) == "number" and date("%Y-%m-%d %H:%M:%S", session.sessionID)) or date("%Y-%m-%d %H:%M:%S")
            local sessTime = tonumber(session.sessionID) or time()

            -- A. Raid Session Event
            local sessDet = string.format("Raid session in %s (%d attendees)", session.zone or "Raid", CountKeys(session.attendees))
            local sessSig = string.format("SESSION_Raid_%s", tostring(sID or ""))
            if not existing[sessSig] and not existing[sessDet] then
                table.insert(db.AuditLog, {
                    t   = sessTime,
                    d   = sessDate,
                    act = "SESSION",
                    by  = "Attendance",
                    p   = "Raid",
                    det = sessDet,
                    sID = sID,
                    h   = ""
                })
                existing[sessSig] = true
                existing[sessDet] = true
                migrated = migrated + 1
            end

            -- B. Boss Encounters
            local bossList = session.bosses or session.bossLog or session.bossKills
            if bossList and type(bossList) == "table" then
                for _, boss in ipairs(bossList) do
                    if type(boss) == "table" and (boss.name or boss.bossName) then
                        local bName = tostring(boss.name or boss.bossName)
                        local bPulls = tonumber(boss.pulls) or 1
                        local bTime = tonumber(boss.time) or sessTime
                        local bDate = (bTime and date("%Y-%m-%d %H:%M:%S", bTime)) or sessDate
                        local bDet = string.format("Defeated %s (%d pull%s)", bName, bPulls, bPulls == 1 and "" or "s")
                        local bSig = string.format("BOSS_%s_%s", bName, tostring(sID or ""))
                        if not existing[bSig] and not existing[bDet] then
                            table.insert(db.AuditLog, {
                                t   = bTime,
                                d   = bDate,
                                act = "BOSS_KILL",
                                by  = "Encounter",
                                p   = "Raid",
                                det = bDet,
                                sID = sID,
                                h   = ""
                            })
                            existing[bSig] = true
                            existing[bDet] = true
                            migrated = migrated + 1
                        end
                    end
                end
            end

            -- C. Decay Penalties
            if session.decayApplied and session.decayApplied ~= -1 then
                local decayTime = tonumber(session.decayApplied) or (sessTime + 3600)
                local decayDate = date("%Y-%m-%d %H:%M:%S", decayTime)
                local penalty = tonumber(session.decayPenalty) or 1

                local absentList = {}
                if session.decayAbsent and type(session.decayAbsent) == "table" then
                    for p in pairs(session.decayAbsent) do table.insert(absentList, p) end
                elseif session.decayPlayers and type(session.decayPlayers) == "table" then
                    for _, p in ipairs(session.decayPlayers) do table.insert(absentList, p) end
                end

                for _, pRaw in ipairs(absentList) do
                    local pName = CanonName(pRaw)
                    local decayDet = string.format("Decay of %d applied for raid absence (%s)", penalty, session.zone or "Raid")
                    local decaySig = string.format("DECAY_%s_%s", tostring(pName), tostring(sID or ""))
                    if not existing[decaySig] and not existing[decayDet .. "_" .. tostring(pName)] then
                        table.insert(db.AuditLog, {
                            t   = decayTime,
                            d   = decayDate,
                            act = "DECAY",
                            by  = "Attendance",
                            p   = pName,
                            det = decayDet,
                            sID = sID,
                            h   = ""
                        })
                        existing[decaySig] = true
                        existing[decayDet .. "_" .. tostring(pName)] = true
                        migrated = migrated + 1
                    end
                end
            end

            -- D. Session Position Changes
            if session.positionChanges and type(session.positionChanges) == "table" then
                for _, posChange in ipairs(session.positionChanges) do
                    local tVal = sessTime
                    local dVal = sessDate
                    local pName, detText
                    if type(posChange) == "table" then
                        tVal = posChange.timestamp or tVal
                        dVal = posChange.date or (tVal and date("%Y-%m-%d %H:%M:%S", tVal)) or dVal
                        pName = CanonName(posChange.player)
                        detText = posChange.details or string.format("Rank %s -> %s", tostring(posChange.from or ""), tostring(posChange.to or ""))
                    elseif type(posChange) == "string" then
                        local datePart, rest = posChange:match("%[(.-)%]%s*(.*)")
                        if datePart and rest then
                            dVal = datePart
                            detText = rest
                        else
                            detText = posChange
                        end
                    end

                    if detText and not existing[detText] and not existing[tostring(posChange)] then
                        table.insert(db.AuditLog, {
                            t   = tVal,
                            d   = dVal,
                            act = "POSITION_CHANGE",
                            by  = "History",
                            p   = pName,
                            det = detText,
                            sID = sID,
                            h   = ""
                        })
                        existing[detText] = true
                        if type(posChange) == "string" then existing[posChange] = true end
                        migrated = migrated + 1
                    end
                end
            end

            -- E. Awarded Items in Session
            if session.awarded and type(session.awarded) == "table" then
                for _, award in ipairs(session.awarded) do
                    if type(award) == "table" and award.winner then
                        local tVal = tonumber(award.timestamp) or sessTime
                        local dVal = (tVal and date("%Y-%m-%d %H:%M:%S", tVal)) or sessDate
                        local itemText = tostring(award.link or award.itemID or "Item")
                        local voteText = tostring(award.voteType or "Bid")
                        local detText = string.format("Awarded %s (%s)", itemText, voteText)
                        local awardSig = string.format("%s_%s_%s", detText, tostring(CanonName(award.winner)), tostring(sID or ""))

                        if not existing[awardSig] and not existing[detText] then
                            table.insert(db.AuditLog, {
                                t   = tVal,
                                d   = dVal,
                                act = "AWARD",
                                by  = "History",
                                p   = CanonName(award.winner),
                                det = detText,
                                sID = sID,
                                h   = ""
                            })
                            existing[awardSig] = true
                            migrated = migrated + 1
                        end
                    end
                end
            end
        end

        table.sort(db.AuditLog, function(a, b)
            local ta = tonumber(a.t) or 0
            local tb = tonumber(b.t) or 0
            if ta ~= tb then return ta < tb end
            return tostring(a.d or "") < tostring(b.d or "")
        end)
    end

    return migrated
end

-- ---------------------------------------------------------------------------
-- Schema 201: Name-Realm Key Enforcement
-- ---------------------------------------------------------------------------

--- Re-keys MainRoster and playerRoster.alts entries that lack a realm suffix
--- to use the canonical Name-Realm format.
--- Uses the current player's realm name; safe to call at any time.
---@param db table
---@return number migratedCount
function DBMigrator:NormalizeRosterKeys(db)
    local migrated = 0
    local realmName = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    if realmName == "" then
        local _, r = UnitName("player")
        realmName = r or ""
    end
    realmName = realmName:gsub("%s+", "")

    if realmName == "" then
        DesolateLootcouncil:DLC_Log("DBMigrator: NormalizeRosterKeys skipped — realm unavailable.")
        return 0
    end

    local function addRealm(name)
        if not name or name == "" then return name end
        if name:find("-", 1, true) then return name end
        return name .. "-" .. realmName
    end

    -- Re-key MainRoster
    if db.MainRoster then
        local toAdd = {}
        local toRemove = {}
        for key, data in pairs(db.MainRoster) do
            if not key:find("-", 1, true) then
                local newKey = key .. "-" .. realmName
                toAdd[newKey] = data
                toRemove[key] = true
                migrated = migrated + 1
            end
        end
        for key in pairs(toRemove) do db.MainRoster[key] = nil end
        for key, data in pairs(toAdd) do db.MainRoster[key] = data end
    end

    -- Re-key alts table (both key and value)
    if db.playerRoster and db.playerRoster.alts then
        local newAlts = {}
        for altKey, mainVal in pairs(db.playerRoster.alts) do
            local newAlt  = addRealm(altKey)
            local newMain = addRealm(mainVal)
            newAlts[newAlt] = newMain
            if newAlt ~= altKey or newMain ~= mainVal then
                migrated = migrated + 1
            end
        end
        db.playerRoster.alts = newAlts
    end

    -- Re-key unassignedPlayers
    if db.unassignedPlayers then
        local newUp = {}
        for key, data in pairs(db.unassignedPlayers) do
            local newKey = addRealm(key)
            newUp[newKey] = data
            if newKey ~= key then migrated = migrated + 1 end
        end
        db.unassignedPlayers = newUp
    end

    if migrated > 0 then
        DesolateLootcouncil:DLC_Log(string.format("DBMigrator: NormalizeRosterKeys re-keyed %d entries to Name-Realm format.", migrated))
    end
    return migrated
end

-- ---------------------------------------------------------------------------
-- Schema 201: attendeeDetails Canonical Schema
-- ---------------------------------------------------------------------------

--- Converts legacy flat attendeeDetails entries to canonical schema:
---   Legacy:    attendeeDetails[main] = { [charName] = { class, kills } }
---   Canonical: attendeeDetails[main] = { mainClass, attendedChars = { [charName] = { class, kills, isAlt } } }
--- Also appends realm suffix to charName keys that lack one.
---@param db table
---@return number migratedCount
function DBMigrator:NormalizeLegacyAttendeeDetails(db)
    local migrated = 0
    local realmName = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    if realmName == "" then
        local _, r = UnitName("player")
        realmName = r or ""
    end
    realmName = realmName:gsub("%s+", "")

    local function addRealm(name)
        if not name or name == "" then return name end
        if name:find("-", 1, true) then return name end
        return (realmName ~= "") and (name .. "-" .. realmName) or name
    end

    for _, entry in ipairs(db.AttendanceHistory or {}) do
        if type(entry.attendeeDetails) == "table" then
            local newDetails = {}
            for mainName, mainEntry in pairs(entry.attendeeDetails) do
                local canonicalMain = addRealm(mainName)
                if type(mainEntry) == "table" and not mainEntry.attendedChars then
                    -- Legacy flat format
                    local chars = {}
                    for charName, charData in pairs(mainEntry) do
                        if type(charData) == "table" then
                            local canonicalChar = addRealm(charName)
                            chars[canonicalChar] = {
                                class = charData.class or "WARRIOR",
                                kills = charData.kills or 0,
                                isAlt = (canonicalChar ~= canonicalMain),
                            }
                        end
                    end
                    local mainClass = (db.MainRoster and db.MainRoster[canonicalMain]
                        and db.MainRoster[canonicalMain].class) or "WARRIOR"
                    newDetails[canonicalMain] = {
                        mainClass     = mainClass,
                        attendedChars = chars,
                    }
                    migrated = migrated + 1
                elseif type(mainEntry) == "table" and mainEntry.attendedChars then
                    -- Already canonical; still ensure outer key has realm
                    local reKeyedChars = {}
                    for charName, charData in pairs(mainEntry.attendedChars) do
                        reKeyedChars[addRealm(charName)] = charData
                    end
                    mainEntry.attendedChars = reKeyedChars
                    newDetails[canonicalMain] = mainEntry
                end
            end
            entry.attendeeDetails = newDetails
        end
    end

    if migrated > 0 then
        DesolateLootcouncil:DLC_Log(string.format("DBMigrator: NormalizeLegacyAttendeeDetails converted %d flat entries to canonical schema.", migrated))
    end
    return migrated
end
