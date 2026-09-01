local _, AT = ...
if AT.abortLoad then return end

---@class Audit : AceModule, AceConsole-3.0
local Audit = DesolateLootcouncil:NewModule("Audit", "AceConsole-3.0")

---@class (partial) DLC_Ref_Audit
---@field db table
---@field API table
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field AmILootMaster fun(self: any): boolean
---@field GetModule fun(self: any, name: string, silent?: boolean): any
---@field GetDisplayName fun(self: any, name: string): string

---@type DLC_Ref_Audit
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Audit]]
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local MAX_AUDIT_LOG_ENTRIES = 5000

function Audit:OnInitialize()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if db and not db.AuditLog then
        db.AuditLog = {}
    end
end

--- Appends an immutable structured audit entry into the ledger.
---@param action string Short action identifier (e.g. "AWARD", "PRIO_MOVE", "ROSTER_ADD", etc.)
---@param actor string|nil Name of the officer/player performing the action
---@param player string|nil Subject player name
---@param listName string|nil Target priority list name
---@param details string|nil Human-readable description
---@param sessionID number|string|nil Active session ID (optional)
---@return table|nil entry The created audit entry
function Audit:Log(action, actor, player, listName, details, sessionID)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db then return nil end

    if not db.AuditLog then db.AuditLog = {} end

    local now = time()
    local dateStr = date("%Y-%m-%d %H:%M:%S", now)
    local author = actor or (UnitName and UnitName("player")) or "Unknown"

    -- Calculate or reuse instantaneous state hash receipt
    local API = DesolateLootcouncil.API
    local stateHash = (API and API.GetRosterHash and API:GetRosterHash()) or "00000000"

    -- Resolve active session ID if not explicitly passed
    local sID = sessionID
    if not sID and db.DecayConfig and db.DecayConfig.sessionActive then
        sID = db.DecayConfig.currentSessionID
    end

    local entry = {
        t   = now,
        d   = dateStr,
        act = tostring(action or "UNKNOWN"),
        by  = tostring(author),
        p   = player and tostring(player) or nil,
        l   = listName and tostring(listName) or nil,
        det = details and tostring(details) or nil,
        sID = sID and tostring(sID) or nil,
        h   = stateHash
    }

    table.insert(db.AuditLog, entry)

    -- Prune oldest entries if buffer exceeds cap
    while #db.AuditLog > MAX_AUDIT_LOG_ENTRIES do
        table.remove(db.AuditLog, 1)
    end

    return entry
end

--- Retrieves filtered audit log records.
---@param sessionID string|number|nil Filter by session ID
---@param actionFilter string|nil Filter by action code
---@return table[]
function Audit:GetLog(sessionID, actionFilter)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.AuditLog then return {} end

    local sIDStr = sessionID and tostring(sessionID)
    local actStr = actionFilter and string.upper(tostring(actionFilter))

    if not sIDStr and not actStr then
        return db.AuditLog
    end

    local filtered = {}
    for _, entry in ipairs(db.AuditLog) do
        local matchSession = (not sIDStr) or (entry.sID and tostring(entry.sID) == sIDStr)
        local matchAction  = (not actStr)  or (entry.act and string.upper(tostring(entry.act)) == actStr)
        if matchSession and matchAction then
            table.insert(filtered, entry)
        end
    end
    return filtered
end

--- Formats the audit ledger into readable text lines for export or display.
---@param sessionID string|number|nil
---@return string
function Audit:ExportLog(sessionID)
    local logEntries = self:GetLog(sessionID)
    if not logEntries or #logEntries == 0 then
        return L["No audit log entries recorded."]
    end

    local lines = {}
    table.insert(lines, "=== Desolate LootCouncil Audit Ledger ===")
    if sessionID then
        table.insert(lines, string.format("Session Filter: %s", tostring(sessionID)))
    end
    table.insert(lines, string.format("Generated: %s", date("%Y-%m-%d %H:%M:%S", time())))
    table.insert(lines, "--------------------------------------------------")

    for i = #logEntries, 1, -1 do
        local e = logEntries[i]
        local playerTag = e.p and string.format(" | Player: %s", DesolateLootcouncil:GetDisplayName(e.p)) or ""
        local listTag   = e.l and string.format(" | List: %s", e.l) or ""
        local detTag    = e.det and string.format(" | %s", e.det) or ""
        local hashTag   = (e.h and e.h ~= "") and string.format(" [Hash:%s]", e.h) or ""

        local line = string.format("[%s] %s by %s%s%s%s%s",
            e.d or tostring(e.t or ""),
            e.act or "EVENT",
            DesolateLootcouncil:GetDisplayName(e.by or "System"),
            playerTag,
            listTag,
            detTag,
            hashTag
        )
        table.insert(lines, line)
    end

    return table.concat(lines, "\n")
end

DesolateLootcouncil.Audit = Audit
