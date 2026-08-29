local _, AT = ...
if AT.abortLoad then return end

---@class Legacy
---@field MigratePriorityLists fun(self: Legacy, db: table): boolean
---@field MigrateMainRoster fun(self: Legacy, db: table): boolean
---@field ExtractDecayFromPositionLog fun(self: Legacy, entry: table, getPatternsFn: function, parseDecayFn: function): number
---@field CleanAndSplitAttendanceHistory fun(self: Legacy, entry: table, deepCopyFn: function, parseTsFn: function, cleanFn: function): table[]
---@field DecodeLegacyPayload fun(self: Legacy, cleanStr: string): string|nil
---@field NormalizeImportedItems fun(self: Legacy, incomingItems: table, defaultLists: table, listName: string, deepCopyFn: function): table
local Legacy = {}

---@class (partial) LegacyAddon : AceAddon
---@field db table
---@field Base64 table
---@field Table table
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field Legacy Legacy

---@type LegacyAddon
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
DesolateLootcouncil.Legacy = Legacy

-- ---------------------------------------------------------------------------
-- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Priority Lists & Roster Migrations
-- ---------------------------------------------------------------------------

--- Converts legacy key-value dictionary lists (e.g. db.PriorityLists.Tier) to dynamic array-of-objects.
---@param db table profile database table
---@return boolean migrated
function Legacy:MigratePriorityLists(db)
    if not db or not db.PriorityLists or db.migrated_priority_v2 then return false end

    local isOldFormat = false
    if db.PriorityLists.Tier or db.PriorityLists.Weapons then
        isOldFormat = true
    end

    if isOldFormat then
        DesolateLootcouncil:DLC_Log("Migrating Priority Lists to Dynamic Format...")
        local old = db.PriorityLists
        local new = {}
        local order = { "Tier", "Weapons", "Rest", "Collectables" }
        for _, key in ipairs(order) do
            if old[key] then
                table.insert(new, { name = key, players = old[key] })
            end
        end
        db.PriorityLists = new
        db.migrated_priority_v2 = true
        return true
    end

    db.migrated_priority_v2 = true
    return false
end

--- Converts old playerRoster.mains and legacy boolean flags to timestamped MainRoster records.
---@param db table profile database table
---@return boolean migrated
function Legacy:MigrateMainRoster(db)
    if not db then return false end
    local migrated = false

    if db.playerRoster and db.playerRoster.mains then
        if not db.MainRoster then db.MainRoster = {} end
        for name, _ in pairs(db.playerRoster.mains) do
            if not db.MainRoster[name] then
                db.MainRoster[name] = { addedAt = time() }
                migrated = true
            end
        end
        db.playerRoster.mains = nil
    end

    if db.MainRoster then
        for name, value in pairs(db.MainRoster) do
            if type(value) == "boolean" then
                db.MainRoster[name] = { addedAt = time() }
                migrated = true
            end
        end
    end

    return migrated
end

-- ---------------------------------------------------------------------------
-- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] History & Decay Legacy Extraction
-- ---------------------------------------------------------------------------

--- Extracts decay amount and absent players from uncompacted SessionPositionLog strings for legacy sessions.
---@param entry table attendance history record
---@param getPatternsFn function returns list of localized decay regex patterns
---@param parseDecayFn function parses a single log message for decay info
---@return number decayAmount
function Legacy:ExtractDecayFromPositionLog(entry, getPatternsFn, parseDecayFn)
    if not entry or not entry.sessionID then return 0 end
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.SessionPositionLog then return 0 end

    local posBucket = db.SessionPositionLog[tostring(entry.sessionID)]
    if not posBucket or type(posBucket) ~= "table" then return 0 end

    local patterns = (getPatternsFn and getPatternsFn()) or {}
    local totalDecay = 0
    for _, logMsg in ipairs(posBucket) do
        if type(logMsg) == "string" then
            local isDecay = false
            for _, pat in ipairs(patterns) do
                local tag = type(pat) == "table" and pat.tag or pat
                if logMsg:find(tag, 1, true) then
                    isDecay = true
                    break
                end
            end
            if not isDecay and (logMsg:find("[Decay]", 1, true) or logMsg:find("[Verfall]", 1, true)) then
                isDecay = true
            end
            if isDecay then
                local pName, amount
                if parseDecayFn then
                    pName, amount = parseDecayFn(logMsg)
                end
                if not pName then
                    local cleanStr = logMsg:gsub("^%[[^%]]+%]%s*", "")
                    pName, amount = cleanStr:match("%[Decay%]%s+(.-)%s+moved from position #%d+ to #%d+ in .- %(%+(%d+)")
                    if not pName then
                        pName, amount = cleanStr:match("%[Verfall%]%s+(.-)%s+wurde von Position #%d+ auf #%d+ in .- %(%+(%d+)")
                    end
                    amount = tonumber(amount)
                end
                if pName then
                    if not entry.decayAbsent then entry.decayAbsent = {} end
                    entry.decayAbsent[pName] = true
                    if amount and amount > 0 then
                        entry.decayPenalty = amount
                        totalDecay = amount
                    end
                end
            end
        end
    end
    return totalDecay
end

--- Splits multi-date attendance entries into separate single-date records.
---@param entry table attendance history record
---@param deepCopyFn function deep-copy utility
---@param parseTsFn function timestamp parsing utility
---@param cleanFn function clean attendance entry utility
---@return table[] splitEntries
function Legacy:CleanAndSplitAttendanceHistory(entry, deepCopyFn, parseTsFn, cleanFn)
    if not entry or type(entry) ~= "table" then return { entry } end

    local function getItemDatePrefix(item)
        local ts = parseTsFn(item)
        if ts and ts > 86400 then
            return date("%Y-%m-%d", ts), ts
        end
        return nil, 0
    end

    local baseDatePrefix = entry.date and entry.date:sub(1, 10)
    local datesFound = {}
    local dateOrder = {}

    local function markDate(dStr)
        if dStr and type(dStr) == "string" and #dStr == 10 and not datesFound[dStr] then
            datesFound[dStr] = true
            table.insert(dateOrder, dStr)
        end
    end

    if baseDatePrefix and #baseDatePrefix == 10 then
        markDate(baseDatePrefix)
    end

    local rawAwarded = entry.awarded or entry.loot
    if rawAwarded and type(rawAwarded) == "table" then
        for _, itm in pairs(rawAwarded) do
            local dStr = getItemDatePrefix(itm)
            if dStr then markDate(dStr) end
        end
    end

    local rawBossLogs = entry.bossLogs or entry.bossFights
    if rawBossLogs and type(rawBossLogs) == "table" then
        for _, b in pairs(rawBossLogs) do
            if b.killed and b.killedTime and b.killedTime > 86400 then
                local dStr = date("%Y-%m-%d", b.killedTime)
                if dStr then markDate(dStr) end
            end
        end
    end

    if #dateOrder <= 1 then
        return { cleanFn(entry, deepCopyFn) }
    end

    table.sort(dateOrder, function(a, b) return a > b end)

    local buckets = {}
    for _, dStr in ipairs(dateOrder) do
        buckets[dStr] = {
            sessionID    = entry.sessionID,
            date         = dStr,
            zone         = entry.zone or "Raid",
            attendees    = deepCopyFn(entry.attendees or {}),
            decayApplied = entry.decayApplied,
            decayPenalty = entry.decayPenalty,
            decayAbsent  = deepCopyFn(entry.decayAbsent),
            awarded      = {},
            bossLogs     = {},
        }
    end

    local fallbackBucket = buckets[dateOrder[1]]

    if rawAwarded and type(rawAwarded) == "table" then
        for origIdx, itm in pairs(rawAwarded) do
            local dStr = getItemDatePrefix(itm)
            local targetBucket = (dStr and buckets[dStr]) or fallbackBucket
            local itemCopy = deepCopyFn(itm)
            itemCopy.origIdx = tonumber(origIdx) or 999
            table.insert(targetBucket.awarded, itemCopy)
        end
    end

    if rawBossLogs and type(rawBossLogs) == "table" then
        for origIdx, b in pairs(rawBossLogs) do
            local dStr = (b.killed and b.killedTime and b.killedTime > 86400) and date("%Y-%m-%d", b.killedTime) or nil
            local targetBucket = (dStr and buckets[dStr]) or fallbackBucket
            local bossCopy = deepCopyFn(b)
            bossCopy.origIdx = tonumber(origIdx) or 999
            table.insert(targetBucket.bossLogs, bossCopy)
        end
    end

    local result = {}
    for idx, dStr in ipairs(dateOrder) do
        local bkt = buckets[dStr]
        bkt.date = (entry.date and #entry.date > 10) and (dStr .. entry.date:sub(11)) or dStr
        if idx > 1 then
            bkt.sessionID = tonumber(tostring(entry.sessionID) .. tostring(idx)) or (entry.sessionID + idx)
        end
        table.insert(result, cleanFn(bkt, deepCopyFn))
    end

    return result
end

-- ---------------------------------------------------------------------------
-- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Legacy Payloads & Item Import
-- ---------------------------------------------------------------------------

--- Decodes legacy uncompressed Base64 export strings.
---@param cleanStr string
---@return string|nil
function Legacy:DecodeLegacyPayload(cleanStr)
    if not cleanStr or cleanStr == "" then return nil end
    if DesolateLootcouncil.Base64 and not string.find(cleanStr, "^{") and cleanStr:sub(1, 2) ~= "^S" then
        return DesolateLootcouncil.Base64:Decode(cleanStr:gsub("%s+", ""))
    end
    return cleanStr
end

--- Normalizes imported item lists from legacy dictionary or corrupted sequential formats.
---@param incomingItems table
---@param defaultLists table
---@param listName string
---@param deepCopyFn function
---@return table normalizedItems
function Legacy:NormalizeImportedItems(incomingItems, defaultLists, listName, deepCopyFn)
    if not incomingItems or type(incomingItems) ~= "table" then return {} end

    local normalized = {}
    local isCorruptedSequential = true
    local count = 0

    for k, val in pairs(incomingItems) do
        local itemID
        if type(k) == "number" and (type(val) == "number" or (type(val) == "string" and tonumber(val))) and val ~= true and val ~= false then
            itemID = tonumber(val)
        elseif val == true or val == 1 then
            itemID = tonumber(k) or k
        else
            itemID = tonumber(k) or tonumber(val) or k
        end

        if itemID then
            normalized[itemID] = true
            count = count + 1
            if type(itemID) ~= "number" or itemID > 200 then
                isCorruptedSequential = false
            end
        end
    end

    -- Auto-heal corrupted 1..N sequential exports back to default catalog
    if isCorruptedSequential and count > 0 and defaultLists then
        for _, def in ipairs(defaultLists) do
            if def.name == listName and def.items then
                return deepCopyFn(def.items)
            end
        end
    end

    return normalized
end
