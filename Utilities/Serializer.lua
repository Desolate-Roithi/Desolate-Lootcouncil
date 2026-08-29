local _, AT = ...
if AT.abortLoad then return end

---@class Serializer
---@field ParseItemTimestamp fun(self: Serializer, item: any): number
---@field CompactItemList fun(self: Serializer, items: table): number[]
---@field CleanAwardedItem fun(self: Serializer, item: table, deepCopyFn?: function): table
---@field CleanAttendanceEntry fun(self: Serializer, entry: table, deepCopyFn?: function): table
---@field SplitMultiDateAttendanceEntry fun(self: Serializer, entry: table, deepCopyFn?: function): table[]
---@field CompactRaidHistory fun(self: Serializer): number
---@field EncodePayload fun(self: Serializer, data: table): string
---@field DecodePayload fun(self: Serializer, importStringRaw: string): string|nil
---@field ExportSingleRaidHistoryEvent fun(self: Serializer, indexOrSession: any): string
---@field ExportProfileData fun(self: Serializer, selection?: table<string, boolean>): string
---@field ImportProfileData fun(self: Serializer, importStringRaw: string, importName?: string, importToCurrent?: boolean): boolean, string
local Serializer = {}

---@class (partial) SerializerAddon : AceAddon
---@field db table
---@field Base64 table
---@field Table table
---@field Constants table
---@field Legacy table
---@field Serializer Serializer
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field Print fun(self: any, msg: string)
---@field Serialize fun(self: any, ...): string
---@field Deserialize fun(self: any, str: string): boolean, any
---@field SendMessage fun(self: any, msg: string, ...: any)

---@type SerializerAddon
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
DesolateLootcouncil.Serializer = Serializer

-- ---------------------------------------------------------------------------
-- Timestamp & Data Formatting Helpers
-- ---------------------------------------------------------------------------

--- Parses timestamp from an awarded item record or date string into numeric epoch seconds.
---@param item table|string|number|nil
---@return number
function Serializer:ParseItemTimestamp(item)
    if not item then return 0 end
    local ts = (type(item) == "table" and (item.timestamp or item.time or item.awardedAt or item.date)) or item
    if type(ts) == "number" then
        return ts
    elseif type(ts) == "string" then
        local num = tonumber(ts)
        if num then return num end
        local y, m, d, h, min, s = ts:match("(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)")
        if y then
            local tTable = { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(h), min = tonumber(min), sec = tonumber(s) }
            local parsed = time(tTable)
            if parsed then return parsed end
        end
        local h2, m2, s2 = ts:match("(%d+):(%d+):(%d+)")
        if h2 then
            return tonumber(h2) * 3600 + tonumber(m2) * 60 + tonumber(s2)
        end
        local h3, m3 = ts:match("(%d+):(%d+)")
        if h3 then
            return tonumber(h3) * 3600 + tonumber(m3) * 60
        end
    end
    return 0
end

--- Transforms an Item Manager sparse item dictionary or array into a sorted compact numeric array for lightweight export.
---@param items table
---@return number[]
function Serializer:CompactItemList(items)
    if not items or type(items) ~= "table" then return {} end
    local list = {}
    local seen = {}
    for k, val in pairs(items) do
        local numID = nil
        if val == true or val == 1 then
            numID = tonumber(k)
        elseif type(k) == "number" and (type(val) == "number" or (type(val) == "string" and tonumber(val))) and val ~= false then
            numID = tonumber(val)
        elseif val then
            numID = tonumber(k) or tonumber(val)
        end
        if numID and not seen[numID] then
            seen[numID] = true
            table.insert(list, numID)
        end
    end
    table.sort(list, function(a, b)
        local numA, numB = tonumber(a), tonumber(b)
        if numA and numB then return numA < numB end
        return tostring(a) < tostring(b)
    end)
    return list
end

--- Clones an awarded item record without the duplicate fullItemData sub-table.
---@param item table
---@param deepCopyFn function?
---@return table
function Serializer:CleanAwardedItem(item, deepCopyFn)
    if type(item) ~= "table" then return item end
    deepCopyFn = deepCopyFn or (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t) return t end
    local ts = item.timestamp or item.time or item.awardedAt or item.date
    if type(ts) == "string" then
        ts = tonumber(ts) or ts
    end
    return {
        link          = item.link,
        texture       = item.texture,
        itemID        = item.itemID,
        winner        = item.winner,
        winnerClass   = item.winnerClass,
        voteType      = item.voteType,
        timestamp     = ts,
        originalIndex = item.originalIndex,
        traded        = item.traded,
        votes         = deepCopyFn(item.votes or {}),
    }
end

--- Normalizes attendance entry fields (awarded, bossLogs), sorting items and boss logs chronologically.
---@param entry table
---@param deepCopyFn function?
---@return table
function Serializer:CleanAttendanceEntry(entry, deepCopyFn)
    if type(entry) ~= "table" then return entry end
    deepCopyFn = deepCopyFn or (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t) return t end
    local cleaned = deepCopyFn(entry)

    if cleaned.loot and not cleaned.awarded then
        cleaned.awarded = cleaned.loot
        cleaned.loot = nil
    end
    if cleaned.bossFights and not cleaned.bossLogs then
        cleaned.bossLogs = cleaned.bossFights
        cleaned.bossFights = nil
    end

    if cleaned.awarded and type(cleaned.awarded) == "table" then
        local cleanedAwarded = {}
        for origIdx, item in pairs(cleaned.awarded) do
            local numIdx = tonumber(origIdx) or 999
            local cItem = self:CleanAwardedItem(item, deepCopyFn)
            cItem.origIdx = numIdx
            table.insert(cleanedAwarded, cItem)
        end
        table.sort(cleanedAwarded, function(a, b)
            local tA = self:ParseItemTimestamp(a)
            local tB = self:ParseItemTimestamp(b)
            if tA ~= tB then return tA < tB end
            return (a.origIdx or 0) < (b.origIdx or 0)
        end)
        for _, itm in ipairs(cleanedAwarded) do
            itm.origIdx = nil
        end
        cleaned.awarded = cleanedAwarded
    end

    if cleaned.publicAwardLog and type(cleaned.publicAwardLog) == "table" then
        table.sort(cleaned.publicAwardLog, function(a, b)
            return self:ParseItemTimestamp(a) < self:ParseItemTimestamp(b)
        end)
    end

    if cleaned.bossLogs and type(cleaned.bossLogs) == "table" then
        for origIdx, b in pairs(cleaned.bossLogs) do
            b.origIdx = tonumber(origIdx) or 999
            if not b.pulls or b.pulls < 1 then
                b.pulls = 1
            end
        end
        table.sort(cleaned.bossLogs, function(a, b)
            local kA = (a.killed and a.killedTime) or nil
            local kB = (b.killed and b.killedTime) or nil
            if kA and kB then
                if kA ~= kB then return kA < kB end
                return (a.origIdx or 0) < (b.origIdx or 0)
            elseif kA and not kB then
                return true
            elseif not kA and kB then
                return false
            else
                return (a.origIdx or 0) < (b.origIdx or 0)
            end
        end)
        for _, b in ipairs(cleaned.bossLogs) do
            b.origIdx = nil
        end
    end

    return cleaned
end

--- Delegates multi-date attendance splitting to Legacy module if available.
---@param entry table
---@param deepCopyFn function?
---@return table[]
function Serializer:SplitMultiDateAttendanceEntry(entry, deepCopyFn)
    deepCopyFn = deepCopyFn or (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t) return t end
    if DesolateLootcouncil.Legacy and DesolateLootcouncil.Legacy.CleanAndSplitAttendanceHistory then
        local selfRef = self
        local parseFn = function(itm) return selfRef:ParseItemTimestamp(itm) end
        local cleanFn = function(e, dcf) return selfRef:CleanAttendanceEntry(e, dcf) end
        return DesolateLootcouncil.Legacy:CleanAndSplitAttendanceHistory(entry, deepCopyFn, parseFn, cleanFn)
    end
    return { self:CleanAttendanceEntry(entry, deepCopyFn) }
end

--- Compacts raid history in SavedVariables, pruning redundant decay strings and splitting multi-date sessions.
---@param arg1 any
---@param arg2 any
---@return number prunedCount
function Serializer:CompactRaidHistory(arg1, arg2)
    local p = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not p then return 0 end
    local force = (arg1 == true) or (arg2 == true)
    if (p.historyCompacted == true) and not force then return 0 end

    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end

    local PriorityMod = DesolateLootcouncil:GetModule("Priority", true)
    local getPatternsFn = PriorityMod and PriorityMod.GetDecayPatterns and function() return PriorityMod:GetDecayPatterns() end
    local parseDecayFn = PriorityMod and PriorityMod.ParseDecayLogMessage and function(msg) return PriorityMod:ParseDecayLogMessage(msg) end
    local isDecayFn = (PriorityMod and PriorityMod.IsDecayLogMessage and function(msg) return PriorityMod:IsDecayLogMessage(msg) end) or function(msg)
        return msg:find("[Decay]", 1, true) ~= nil or msg:find("[Verfall]", 1, true) ~= nil
    end

    local prunedCount = 0
    if p.AttendanceHistory and type(p.AttendanceHistory) == "table" then
        local newAttendance = {}
        for _, entry in ipairs(p.AttendanceHistory) do
            if entry and type(entry) == "table" then
                if (not entry.decayApplied or entry.decayApplied == -1 or entry.decayApplied == 0) and p.SessionPositionLog and DesolateLootcouncil.Legacy then
                    local extractedDecay = DesolateLootcouncil.Legacy:ExtractDecayFromPositionLog(entry, getPatternsFn, parseDecayFn)
                    if extractedDecay and extractedDecay > 0 then
                        entry.decayApplied = extractedDecay
                    end
                end

                local splitEntries = self:SplitMultiDateAttendanceEntry(entry, DeepCopy)
                for _, sEntry in ipairs(splitEntries) do
                    table.insert(newAttendance, sEntry)
                end
            end
        end
        p.AttendanceHistory = newAttendance
    end

    if p.SessionPositionLog and type(p.SessionPositionLog) == "table" then
        for sessionID, logBucket in pairs(p.SessionPositionLog) do
            if type(logBucket) == "table" then
                local filteredBucket = {}
                for _, logMsg in ipairs(logBucket) do
                    if type(logMsg) == "string" and isDecayFn(logMsg) then
                        prunedCount = prunedCount + 1
                    else
                        table.insert(filteredBucket, logMsg)
                    end
                end
                if #filteredBucket == 0 then
                    p.SessionPositionLog[sessionID] = nil
                else
                    p.SessionPositionLog[sessionID] = filteredBucket
                end
            end
        end
    end

    p.historyCompacted = true
    p.raidHistoryCompacted = true
    return prunedCount
end

-- ---------------------------------------------------------------------------
-- Stream Encoding & Decoding (LibDeflate / Base64)
-- ---------------------------------------------------------------------------

--- Serializes table data and applies LibDeflate compression producing !DLC1: strings.
---@param data table
---@return string
function Serializer:EncodePayload(data)
    local serialized = DesolateLootcouncil:Serialize(data)
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if LibDeflate and type(serialized) == "string" then
        local compressed = LibDeflate:CompressDeflate(serialized, { level = 7 })
        if compressed then
            local encoded = LibDeflate:EncodeForPrint(compressed)
            if encoded then
                return "!DLC1:" .. encoded
            end
        end
    end
    local encoded = DesolateLootcouncil.Base64 and DesolateLootcouncil.Base64:Encode(serialized) or serialized
    return encoded
end

--- Decompresses !DLC1: LibDeflate payloads or decodes legacy Base64/raw strings.
---@param importStringRaw string
---@return string|nil
function Serializer:DecodePayload(importStringRaw)
    if not importStringRaw or importStringRaw == "" then return nil end
    local cleanStr = importStringRaw:gsub("^%s+", ""):gsub("%s+$", "")
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)

    if cleanStr:sub(1, 6) == "!DLC1:" and LibDeflate then
        local payloadStr = cleanStr:sub(7):gsub("%s+", "")
        local decodedBytes = LibDeflate:DecodeForPrint(payloadStr)
        if decodedBytes then
            local decompressed = LibDeflate:DecompressDeflate(decodedBytes)
            if decompressed then
                return decompressed
            end
        end
        return nil
    end

    -- Strict 2.0 Policy: Uncompressed/v1 legacy export strings are no longer supported
    return nil
end

-- ---------------------------------------------------------------------------
-- Profile & Event Export / Import
-- ---------------------------------------------------------------------------

--- Generates a compressed export string for a single raid event and its corresponding session position logs.
---@param indexOrSession number|string|table
---@return string
function Serializer:ExportSingleRaidHistoryEvent(indexOrSession)
    self:CompactRaidHistory()
    local p = DesolateLootcouncil.db.profile
    local entry = nil

    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end

    if type(indexOrSession) == "table" then
        entry = DeepCopy(indexOrSession)
    elseif indexOrSession == "CURRENT" then
        local RosterMod = DesolateLootcouncil:GetModule("Roster", true)
        local config = (RosterMod and RosterMod.GetAttendanceConfig and RosterMod:GetAttendanceConfig()) or (p and p.DecayConfig) or {}
        local session = p.session or {}
        local attendees = {}
        if config.currentAttendees then
            for name, val in pairs(config.currentAttendees) do
                if val then attendees[name] = true end
            end
        end
        local currentLoot = {}
        if session.awarded then
            for _, item in ipairs(session.awarded) do
                table.insert(currentLoot, self:CleanAwardedItem(item, DeepCopy))
            end
        end
        entry = {
            sessionID = config.currentSessionID or GetServerTime(),
            date = date("%Y-%m-%d"),
            zone = (session and session.zone) or (GetRealZoneText and GetRealZoneText()) or "Current Raid",
            attendees = attendees,
            awarded = currentLoot,
            bossLogs = DeepCopy(config.bossLogs or {}),
            decayApplied = -1,
        }
    elseif type(indexOrSession) == "number" and p.AttendanceHistory and p.AttendanceHistory[indexOrSession] then
        entry = DeepCopy(p.AttendanceHistory[indexOrSession])
    end

    if not entry then return "" end

    local cleanedEntry = self:CleanAttendanceEntry(entry, DeepCopy)
    local posKey = cleanedEntry.sessionID and tostring(cleanedEntry.sessionID)
    local splBucket = posKey and p.SessionPositionLog and p.SessionPositionLog[posKey]

    local data = {
        SingleRaidEvent = true,
        History = {
            AttendanceHistory = { cleanedEntry },
            SessionPositionLog = splBucket and { [posKey] = DeepCopy(splBucket) } or nil,
        }
    }

    return self:EncodePayload(data)
end

--- Generates a compressed profile export string based on selected category options.
---@param selection table<string, boolean>|nil
---@return string
function Serializer:ExportProfileData(selection)
    self:CompactRaidHistory()
    local p = DesolateLootcouncil.db.profile
    local data = {}
    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end

    local exportAll = (not selection) or selection["All"]
    data.schemaVersion = p.schemaVersion or 200

    if exportAll or (selection and selection["Config"]) then
        data.config = {
            minLootQuality  = p.minLootQuality,
            enableAutoLoot  = p.enableAutoLoot,
            enableAutoTrade = p.enableAutoTrade,
            activeTheme     = p.activeTheme,
            DecayConfig     = DeepCopy(p.DecayConfig),
        }
    end
    if exportAll or (selection and selection["Roster"]) then
        local playerRoster = DeepCopy(p.playerRoster)
        if playerRoster and playerRoster.decay and not next(playerRoster.decay) then
            playerRoster.decay = nil
        end
        data.Roster = {
            MainRoster   = DeepCopy(p.MainRoster),
            playerRoster = playerRoster,
        }
    end
    if exportAll or (selection and (selection["PriorityRankings"] or selection["PriorityLists"] or selection["PriorityContent"])) then
        data.PriorityLists = {}
        if p.PriorityLists then
            for _, list in ipairs(p.PriorityLists) do
                table.insert(data.PriorityLists, {
                    name    = list.name,
                    players = DeepCopy(list.players or {})
                })
            end
        end
    elseif selection and selection["PriorityStructure"] then
        data.PriorityListsStructure = {}
        if p.PriorityLists then
            for _, list in ipairs(p.PriorityLists) do
                table.insert(data.PriorityListsStructure, {
                    name    = list.name,
                    players = {}
                })
            end
        end
    end
    if exportAll or (selection and selection["IM"]) then
        data.ItemManagerContent = {}
        if p.PriorityLists then
            for _, list in ipairs(p.PriorityLists) do
                table.insert(data.ItemManagerContent, {
                    name  = list.name,
                    items = self:CompactItemList(list.items)
                })
            end
        end
    end
    if exportAll or (selection and selection["History"]) then
        local cleanedAttendance = {}
        if p.AttendanceHistory and type(p.AttendanceHistory) == "table" then
            for _, att in ipairs(p.AttendanceHistory) do
                table.insert(cleanedAttendance, self:CleanAttendanceEntry(att, DeepCopy))
            end
        end

        local cleanedSession = DeepCopy(p.session)
        if cleanedSession and cleanedSession.awarded and type(cleanedSession.awarded) == "table" then
            local cleanedSessionAwarded = {}
            for _, item in ipairs(cleanedSession.awarded) do
                table.insert(cleanedSessionAwarded, self:CleanAwardedItem(item, DeepCopy))
            end
            cleanedSession.awarded = cleanedSessionAwarded
        end

        data.History = {
            session            = cleanedSession,
            AttendanceHistory  = cleanedAttendance,
            PriorityLog        = DeepCopy(p.PriorityLog),
            SessionPositionLog = DeepCopy(p.SessionPositionLog),
        }
    end

    return self:EncodePayload(data)
end

--- Imports profile data from a serialized string and switches to the new profile or merges into active.
---@param importStringRaw string
---@param importName string|nil
---@param importToCurrent boolean|nil
---@return boolean success, string message
function Serializer:ImportProfileData(importStringRaw, importName, importToCurrent)
    if not importStringRaw or importStringRaw == "" then
        return false, "Import Error: String is empty."
    end
    if not importToCurrent then
        if not importName or importName == "" then
            return false, "Import Error: Please specify a name for the new profile."
        end
    end

    local decoded = self:DecodePayload(importStringRaw)
    if not decoded then
        return false, "Import Error: Invalid string format / Decode failed."
    end

    local success, data = DesolateLootcouncil:Deserialize(decoded)
    if not success or type(data) ~= "table" then
        return false, "Import Error: Invalid string format / Decode failed."
    end

    if not importToCurrent then
        if DesolateLootcouncil.db and DesolateLootcouncil.db.SetProfile then
            DesolateLootcouncil.db:SetProfile(importName)
        end
    end

    local p = DesolateLootcouncil.db.profile
    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end

    p.schemaVersion = data.schemaVersion or 200

    -- 1. Config
    if data.config then
        if data.config.minLootQuality ~= nil then p.minLootQuality = data.config.minLootQuality end
        if data.config.enableAutoLoot ~= nil then p.enableAutoLoot = data.config.enableAutoLoot end
        if data.config.enableAutoTrade ~= nil then p.enableAutoTrade = data.config.enableAutoTrade end
        if data.config.activeTheme ~= nil then
            p.activeTheme = data.config.activeTheme
            local Theme = DesolateLootcouncil:GetModule("UI_Theme", true)
            if Theme and Theme.SetTheme then Theme:SetTheme(p.activeTheme) end
        end
        if data.config.DecayConfig then
            p.DecayConfig = DeepCopy(data.config.DecayConfig)
        end
        p.configTimestamp = GetServerTime()
    end

    -- 2. Roster
    if data.Roster then
        p.MainRoster = DeepCopy(data.Roster.MainRoster or {})
        p.playerRoster = DeepCopy(data.Roster.playerRoster or { alts = {}, decay = {} })
        p.rosterTimestamp = GetServerTime()

        local RosterMod = DesolateLootcouncil:GetModule("Roster", true)
        if RosterMod then
            if RosterMod.SanitizeMainsAndAlts then RosterMod:SanitizeMainsAndAlts() end
            if RosterMod.UpdateScoreMap then RosterMod:UpdateScoreMap() end
        end
        if DesolateLootcouncil.SendMessage then
            DesolateLootcouncil:SendMessage("DLC_ROSTER_UPDATED")
        end
    end

    -- 3. Priority Lists (Rankings or Empty Structure)
    local incomingLists = data.PriorityLists or data.PriorityListsContent or data.PriorityListsStructure
    if incomingLists then
        p.PriorityLists = p.PriorityLists or {}
        p.priorityTimestamps = p.priorityTimestamps or {}

        for _, incoming in ipairs(incomingLists) do
            local listObj = nil
            for _, localList in ipairs(p.PriorityLists) do
                if localList.name == incoming.name then
                    listObj = localList
                    break
                end
            end
            if not listObj then
                listObj = { name = incoming.name, players = {}, items = {} }
                table.insert(p.PriorityLists, listObj)
            end

            if incoming.players then
                listObj.players = DeepCopy(incoming.players)
            elseif data.PriorityListsStructure then
                listObj.players = {}
            end

            if incoming.items and not data.ItemManagerContent and not data.IM then
                if DesolateLootcouncil.Legacy and DesolateLootcouncil.Legacy.NormalizeImportedItems then
                    local defaultLists = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.GetDefaultPriorityLists) and DesolateLootcouncil.Constants.GetDefaultPriorityLists() or {}
                    listObj.items = DesolateLootcouncil.Legacy:NormalizeImportedItems(incoming.items, defaultLists, listObj.name, DeepCopy)
                end
            end

            if DesolateLootcouncil.API and DesolateLootcouncil.API.MarkPriorityDirty then
                DesolateLootcouncil.API:MarkPriorityDirty(listObj.name)
            end
        end

        if DesolateLootcouncil.SendMessage then
            DesolateLootcouncil:SendMessage("DLC_PRIORITY_UPDATED")
        end
    end

    -- 4. Item Manager Content
    local incomingIM = data.ItemManagerContent or data.IM
    if incomingIM then
        p.PriorityLists = p.PriorityLists or {}
        p.imTimestamps = p.imTimestamps or {}

        for _, incoming in ipairs(incomingIM) do
            local listObj = nil
            for _, localList in ipairs(p.PriorityLists) do
                if localList.name == incoming.name then
                    listObj = localList
                    break
                end
            end
            if not listObj then
                listObj = { name = incoming.name, players = {}, items = {} }
                table.insert(p.PriorityLists, listObj)
            end

            if incoming.items then
                if DesolateLootcouncil.Legacy and DesolateLootcouncil.Legacy.NormalizeImportedItems then
                    local defaultLists = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.GetDefaultPriorityLists) and DesolateLootcouncil.Constants.GetDefaultPriorityLists() or {}
                    listObj.items = DesolateLootcouncil.Legacy:NormalizeImportedItems(incoming.items, defaultLists, listObj.name, DeepCopy)
                else
                    listObj.items = DeepCopy(incoming.items)
                end
            else
                listObj.items = {}
            end

            if DesolateLootcouncil.API and DesolateLootcouncil.API.MarkIMDirty then
                DesolateLootcouncil.API:MarkIMDirty(listObj.name)
            end
        end

        if DesolateLootcouncil.SendMessage then
            DesolateLootcouncil:SendMessage("DLC_IM_UPDATED")
        end
    end

    -- 5. History
    if data.History then
        if data.History.session then
            p.session = DeepCopy(data.History.session)
            if p.session.awarded and type(p.session.awarded) == "table" then
                table.sort(p.session.awarded, function(a, b)
                    return self:ParseItemTimestamp(a) < self:ParseItemTimestamp(b)
                end)
            end
            if p.session.publicAwardLog and type(p.session.publicAwardLog) == "table" then
                table.sort(p.session.publicAwardLog, function(a, b)
                    return self:ParseItemTimestamp(a) < self:ParseItemTimestamp(b)
                end)
            end
        end

        if data.History.AttendanceHistory then
            local incomingAttendance = DeepCopy(data.History.AttendanceHistory)
            local cleanedIncomingAttendance = {}
            for _, att in ipairs(incomingAttendance) do
                local splitEntries = self:SplitMultiDateAttendanceEntry(att, DeepCopy)
                for _, sEntry in ipairs(splitEntries) do
                    table.insert(cleanedIncomingAttendance, sEntry)
                end
            end

            if importToCurrent and p.AttendanceHistory then
                for _, newAtt in ipairs(cleanedIncomingAttendance) do
                    local found = false
                    for idx, existing in ipairs(p.AttendanceHistory) do
                        if existing.sessionID and newAtt.sessionID and existing.sessionID == newAtt.sessionID then
                            p.AttendanceHistory[idx] = newAtt
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(p.AttendanceHistory, newAtt)
                    end
                end
            else
                p.AttendanceHistory = cleanedIncomingAttendance
            end
        end

        if data.History.PriorityLog then
            p.PriorityLog = DeepCopy(data.History.PriorityLog)
        end
        if data.History.SessionPositionLog then
            if importToCurrent and p.SessionPositionLog then
                for sID, logBucket in pairs(data.History.SessionPositionLog) do
                    p.SessionPositionLog[sID] = DeepCopy(logBucket)
                end
            else
                p.SessionPositionLog = DeepCopy(data.History.SessionPositionLog)
            end
        end

        p.historyTimestamp = GetServerTime()
        self:CompactRaidHistory()

        if DesolateLootcouncil.SendMessage then
            DesolateLootcouncil:SendMessage("DLC_HISTORY_UPDATED")
        end
    end

    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    return true, "Import successful."
end
