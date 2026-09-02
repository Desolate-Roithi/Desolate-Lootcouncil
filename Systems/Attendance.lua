local _, AT = ...
if AT.abortLoad then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

---@class Attendance : AceModule, AceEvent-3.0, AceTimer-3.0
local Attendance = DesolateLootcouncil:NewModule("Attendance", "AceEvent-3.0", "AceTimer-3.0")

---@class (partial) DLC_Ref_Attendance
---@field db table
---@field API table
---@field Table table
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field AmILootMaster fun(self: any): boolean
---@field AmIOfficerOrLM fun(self: any): boolean
---@field GetDisplayName fun(self: any, name: string): string
---@field SmartCompare fun(self: any, a: string, b: string): boolean
---@field PromptAutopass fun(self: any)
---@field GetModule fun(self: any, name: string, quiet?: boolean): any
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Attendance]]

local function SafeGetUnitClass(unit)
    local ok, _, classFilename = pcall(UnitClass, unit)
    return (ok and classFilename) or "WARRIOR"
end

function Attendance:OnInitialize()
    self.pullCounts = {}
    self.currentEncounter = nil
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterUpdate")
    DesolateLootcouncil:DLC_Log(L["Systems/Attendance Loaded"])
end

function Attendance:Printf(msg, ...)
    DesolateLootcouncil:DLC_Log(string.format(msg, ...), true)
end

--- Returns true if a raid attendance tracking session is currently active.
---@return boolean
function Attendance:IsSessionActive()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    return (db and db.DecayConfig and db.DecayConfig.sessionActive == true) or false
end

--- Returns the current attendance decay/session config table.
---@return table
function Attendance:GetAttendanceConfig()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db then return {} end
    if not db.DecayConfig then db.DecayConfig = {} end
    return db.DecayConfig
end

--- Starts a new raid attendance tracking session.
function Attendance:StartRaidSession()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db then return end
    if not db.DecayConfig then db.DecayConfig = {} end
    local config = db.DecayConfig

    if config.sessionActive then
        local prevDate = config.currentSessionID and date("%Y-%m-%d", config.currentSessionID)
        local todayDate = date("%Y-%m-%d", time())
        if prevDate and prevDate ~= todayDate and DesolateLootcouncil:AmILootMaster() then
            if StaticPopup_Show then StaticPopup_Show("DLC_NEW_DATE_SESSION_PROMPT", prevDate) end
            return
        end
        self:Printf("Session already active (Started: %s). Auto-saving and stopping previous session.", date("%c", config.currentSessionID))
        self:StopRaidSession(true)
    end

    if DesolateLootcouncil:AmILootMaster() and self:HasPendingDecay() then
        local entry = db.AttendanceHistory and db.AttendanceHistory[1]
        self.pendingStartRaidSession = true
        if StaticPopup_Show then StaticPopup_Show("DLC_PENDING_DECAY", (entry and entry.date) or "N/A", (entry and entry.zone) or "Unknown") end
        return
    end
    self.pendingStartRaidSession = nil

    if DesolateLootcouncil:IsLFR() then
        return
    end

    if not DesolateLootcouncil.API:AmIOfficerOrLM() then
        self:Printf("Only Officers or the Loot Master can start a raid session.")
        return
    end

    local _, instanceType = GetInstanceInfo()
    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    local simActive = Sim and Sim.GetRoster and #Sim:GetRoster() > 0

    if instanceType ~= "raid" and not simActive and not db.debugMode then
        self:Printf("Sessions can only be started in Raid instances.")
        return
    end

    if not IsInRaid() and not simActive and not db.debugMode then
        self:Printf("Sessions can only be started while in a Raid group.")
        return
    end

    config.sessionActive = true
    config.currentSessionID = time()
    config.currentSessionLM = UnitName("player")
    config.currentAttendees = {}
    config.attendeeDetails = {}
    config.bossLogs = {}
    config.lastActivity = time()

    local globalDb = DesolateLootcouncil.db.global
    if globalDb then
        globalDb.activeRaidProfile = DesolateLootcouncil.db:GetCurrentProfile()
        globalDb.activeRaidSessionID = config.currentSessionID
        globalDb.activeRaidLastActivity = config.lastActivity
        globalDb.activeRaidLM = UnitName("player")
    end

    local session = DesolateLootcouncil.db.profile.session
    if session then
        session.awarded = {}
    end

    self:Printf("Raid Session STARTED. ID: %d", config.currentSessionID)

    if DesolateLootcouncil:AmILootMaster() then
        local Priority = DesolateLootcouncil:GetModule("Priority", true)
        if Priority and Priority.NotifyIfPlayersMissing then
            Priority:NotifyIfPlayersMissing()
        end
        if DesolateLootcouncil.PromptAutopass then
            DesolateLootcouncil:PromptAutopass()
        end
    end

    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
    local SessionMod = DesolateLootcouncil:GetModule("Session", true)
    if SessionMod and SessionMod.SendDLCHeartbeat then
        SessionMod:SendDLCHeartbeat()
    end

    DesolateLootcouncil.API:LogAudit("SESSION_START", nil, nil, nil, string.format("Raid session started (ID: %s)", tostring(config.currentSessionID)), config.currentSessionID)
end

--- Stops the current tracking session and optionally commits it to AttendanceHistory.
---@param saveHistory boolean|nil
function Attendance:StopRaidSession(saveHistory)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.DecayConfig or not db.DecayConfig.sessionActive then
        self:Printf("No active session to stop.")
        return
    end
    local config = db.DecayConfig

    if saveHistory then
        local isOfficerOrLM = DesolateLootcouncil:AmIOfficerOrLM()
        if isOfficerOrLM then
            if not db.AttendanceHistory then db.AttendanceHistory = {} end

            local entry = {
                date            = date("%Y-%m-%d %H:%M:%S", config.currentSessionID),
                zone            = GetRealZoneText() or "Unknown",
                sessionID       = config.currentSessionID,
                attendees       = {},
                attendeeDetails = {},
                bossLogs        = {},
                awarded         = {},
                decayApplied    = self.decayAppliedForSession or (not config.enabled and -1 or nil),
                decayPenalty    = self.decayPenaltyForSession or (config.defaultPenalty or 1),
                decayAbsent     = self.decayAbsentForSession and DesolateLootcouncil.Table.DeepCopy(self.decayAbsentForSession) or nil
            }
            self.decayAppliedForSession = nil
            self.decayPenaltyForSession = nil
            self.decayAbsentForSession = nil

            local session = db.session
            local API = DesolateLootcouncil.API
            if session and session.awarded then
                entry.awarded = DesolateLootcouncil.Table.DeepCopy(session.awarded)
                table.sort(entry.awarded, function(a, b)
                    local tA = (API and API.ParseItemTimestamp and API:ParseItemTimestamp(a)) or (a.timestamp or 0)
                    local tB = (API and API.ParseItemTimestamp and API:ParseItemTimestamp(b)) or (b.timestamp or 0)
                    return tA < tB
                end)
            end

            for name, _ in pairs(config.currentAttendees or {}) do
                entry.attendees[name] = true
            end

            if config.attendeeDetails then
                for mainName, mainEntry in pairs(config.attendeeDetails) do
                    entry.attendeeDetails[mainName] = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy(mainEntry)) or mainEntry
                end
            end

            if config.bossLogs then
                for origIdx, b in ipairs(config.bossLogs) do
                    local bRoster = nil
                    if b.roster then
                        bRoster = {}
                        for _, p in ipairs(b.roster) do
                            table.insert(bRoster, { name = p.name, main = p.main, class = p.class })
                        end
                    end
                    table.insert(entry.bossLogs, {
                        encounterID = b.encounterID,
                        name = b.name,
                        pulls = b.pulls,
                        killed = b.killed,
                        killedTime = b.killedTime,
                        roster = bRoster,
                        origIdx = origIdx
                    })
                end
                table.sort(entry.bossLogs, function(a, b)
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
                for _, bLog in ipairs(entry.bossLogs) do
                    bLog.origIdx = nil
                end
            end

            local splitEntries = (API and API.SplitMultiDateAttendanceEntry and API:SplitMultiDateAttendanceEntry(entry)) or { entry }
            for _, sEntry in ipairs(splitEntries) do
                table.insert(db.AttendanceHistory, 1, sEntry)
            end
            table.sort(db.AttendanceHistory, function(a, b)
                local sA = tostring(a.date or a.sessionID or "")
                local sB = tostring(b.date or b.sessionID or "")
                return sA > sB
            end)

            local count = 0
            for mainName, _ in pairs(config.currentAttendees or {}) do
                local roster = db.MainRoster
                if roster and roster[mainName] then
                    roster[mainName].sessionsAttended = roster[mainName].sessionsAttended or {}
                    table.insert(roster[mainName].sessionsAttended, {
                        id = config.currentSessionID,
                        timestamp = time()
                    })
                    count = count + 1
                end
            end
            self:Printf("Session ENDED. Saved attendance for %d players.", count)
            db.historyTimestamp = GetServerTime()
            db.rosterTimestamp = GetServerTime()

            DesolateLootcouncil.API:LogAudit("SESSION_STOP", nil, nil, nil, string.format("Raid session ended (Saved: %d attendees)", count), config.currentSessionID)

            -- Bug 5: Use IsInRaid() rather than IsInGroup() here.
            -- IsInGroup() can still return true for a brief window after the raid
            -- disbands, causing SYNC_HISTORY to be sent to an already-gone RAID
            -- channel and producing "not in group" errors sub-second after save.
            if DesolateLootcouncil:AmILootMaster() and IsInRaid() then
                local Comm = DesolateLootcouncil:GetModule("Comm", true)
                if Comm then
                    local payload = {
                        AttendanceHistory = db.AttendanceHistory or {},
                        awarded = db.session and db.session.awarded or {},
                        historyTimestamp = db.historyTimestamp or 0
                    }
                    Comm:SendComm("SYNC_HISTORY", payload)
                end
            end
        else
            self:Printf("Session ENDED. (Non-officer: history managed by LM).")
        end
    else
        self:Printf("Session ABORTED. No history saved.")
    end

    config.sessionActive = false
    config.currentSessionID = nil
    config.currentSessionLM = nil
    config.currentAttendees = {}
    config.attendeeDetails = {}
    config.bossLogs = {}

    local globalDb = DesolateLootcouncil.db.global
    if globalDb then
        globalDb.activeRaidProfile = ""
        globalDb.activeRaidSessionID = 0
        globalDb.activeRaidLastActivity = 0
        globalDb.activeRaidLM = ""
    end

    DesolateLootcouncil.sessionAutopassActive = false
    DesolateLootcouncil.sessionAutopassAnswered = false
    if db.DecayConfig then
        db.DecayConfig.sessionAutopassActive = false
        db.DecayConfig.sessionAutopassAnswered = false
    end

    db.configTimestamp = GetServerTime()
    -- Bug 5: Only send heartbeat if still in a group.
    -- SendDLCHeartbeat has an IsInGroup guard internally, but during the disband
    -- frame-lag window that guard can pass incorrectly. A strict explicit check here
    -- is the definitive gate.
    if IsInGroup() then
        local SessionMod = DesolateLootcouncil:GetModule("Session", true)
        if SessionMod and SessionMod.SendDLCHeartbeat then
            SessionMod:SendDLCHeartbeat()
        end
    end

    local UI = DesolateLootcouncil:GetModule("UI", true)
    if UI and UI.CloseAllWindows then
        UI:CloseAllWindows()
    end
end

--- Returns a unit's class filename robustly.
---@param unitName string
---@return string classFilename
function Attendance:GetUnitClass(unitName)
    if DesolateLootcouncil:SmartCompare(unitName, "player") then
        return SafeGetUnitClass("player")
    end
    if IsInRaid() and GetRaidRosterInfo then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, fileName = GetRaidRosterInfo(i)
            if name and DesolateLootcouncil:SmartCompare(name, unitName) then
                return fileName
            end
        end
    elseif IsInGroup() and GetNumSubgroupMembers then
        for i = 1, GetNumSubgroupMembers() do
            local name = GetUnitName("party" .. i, true)
            if name and DesolateLootcouncil:SmartCompare(name, unitName) then
                return SafeGetUnitClass("party" .. i)
            end
        end
    end

    local Roster = DesolateLootcouncil:GetModule("Roster", true)
    local main = (Roster and Roster.GetMain and Roster:GetMain(unitName)) or unitName
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if db and db.MainRoster then
        for mName, rData in pairs(db.MainRoster) do
            if DesolateLootcouncil:SmartCompare(mName, main) then
                if rData and rData.class and rData.class ~= "" then
                    return rData.class
                end
            end
        end
    end
    return "WARRIOR"
end

--- Registers attendance for a character (and resolved Main).
---@param unitName string
---@param isEncounterKill boolean|nil
function Attendance:RegisterAttendance(unitName, isEncounterKill)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    local config = db and db.DecayConfig
    if not config or not config.sessionActive or not unitName or unitName == "" then return end

    local normUnit = DesolateLootcouncil:NormalizeName(unitName)
    local Roster = DesolateLootcouncil:GetModule("Roster", true)
    local mainName = (Roster and Roster.GetMain and Roster:GetMain(normUnit)) or (Roster and Roster.GetMain and Roster:GetMain(unitName)) or normUnit
    mainName = DesolateLootcouncil:NormalizeName(mainName)

    if db.MainRoster and (db.MainRoster[mainName] or db.MainRoster[normUnit] or db.MainRoster[unitName]) then
        -- Canonical key from MainRoster
        local canonicalMain = mainName
        if not db.MainRoster[canonicalMain] then
            if db.MainRoster[normUnit] then
                canonicalMain = normUnit
            elseif db.MainRoster[unitName] then
                canonicalMain = unitName
            end
        end

        config.currentAttendees = config.currentAttendees or {}
        if not config.currentAttendees[canonicalMain] then
            config.currentAttendees[canonicalMain] = true
            DesolateLootcouncil:DLC_Log(string.format("Attendance Registered: %s (Main: %s)", 
                DesolateLootcouncil:GetDisplayName(normUnit), 
                DesolateLootcouncil:GetDisplayName(canonicalMain)))
        end

        config.attendeeDetails = config.attendeeDetails or {}
        config.attendeeDetails[canonicalMain] = config.attendeeDetails[canonicalMain] or {
            mainClass     = self:GetUnitClass(canonicalMain),
            attendedChars = {}
        }
        local chars = config.attendeeDetails[canonicalMain].attendedChars

        -- Store with full canonical Name-Realm key
        if not chars[normUnit] then
            chars[normUnit] = {
                class = self:GetUnitClass(normUnit),
                kills = 0,
                isAlt = not DesolateLootcouncil:SmartCompare(normUnit, canonicalMain)
            }
        end

        if isEncounterKill then
            chars[normUnit].kills = chars[normUnit].kills + 1
        end
    else
        local formattedMain = DesolateLootcouncil:GetDisplayName(mainName)
        local formattedUnit = DesolateLootcouncil:GetDisplayName(unitName)
        local hint = not DesolateLootcouncil:SmartCompare(mainName, unitName)
            and string.format("'%s' (resolved from alt '%s') is not in the MainRoster", formattedMain, formattedUnit)
            or string.format("'%s' is not in the MainRoster — use /dlc roster add to add them", formattedUnit)
        -- Demoted to non-forced: per-player rejection detail is surfaced via the Unassigned Players window.
        DesolateLootcouncil:DLC_Log("Attendance Rejected: " .. hint)
        -- Queue into the Unassigned Players window so the LM can act via /dlc unassigned.
        if Roster and Roster.RecordUnassignedPlayer then
            Roster:RecordUnassignedPlayer(normUnit, "Attendance")
        end
    end
end

--- Takes a snapshot of real and simulated raid group members.
--- Only Officers or the Loot Master in Raid instances perform attendance tracking.
---@param isEncounterKill boolean|nil
function Attendance:SnapshotRoster(isEncounterKill)
    if DesolateLootcouncil:IsLFR() then return end
    if not DesolateLootcouncil.API:AmIOfficerOrLM() then return end

    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    local simActive = Sim and Sim.GetRoster and #Sim:GetRoster() > 0
    local isBypass = simActive or (db and db.debugMode) or DesolateLootcouncil.isTestRunning
    if not IsInRaid() and not isBypass then return end

    local config = db and db.DecayConfig
    if not config or not config.sessionActive then return end

    config.lastActivity = time()

    -- Capture the current unassigned count before processing raids so we can
    -- detect how many NEW players were added by this snapshot.
    local unassignedBefore = 0
    if db and db.unassignedPlayers then
        for _ in pairs(db.unassignedPlayers) do
            unassignedBefore = unassignedBefore + 1
        end
    end

    if IsInRaid() then
        local members = GetNumGroupMembers()
        if members > 0 then
            for i = 1, members do
                local name = GetRaidRosterInfo(i)
                if name then
                    self:RegisterAttendance(name, isEncounterKill)
                end
            end
        end
    end

    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    if Sim and Sim.GetRoster then
        local sims = Sim:GetRoster()
        for _, name in ipairs(sims) do
            self:RegisterAttendance(name, isEncounterKill)
        end
    end

    -- Single summary message if new unassigned players were detected this snapshot.
    -- We deliberately do NOT print per-player messages to avoid chat spam.
    -- The LM can use /dlc unassigned to review and assign them.
    local unassignedAfter = 0
    if db and db.unassignedPlayers then
        for _ in pairs(db.unassignedPlayers) do
            unassignedAfter = unassignedAfter + 1
        end
    end
    local newUnassigned = unassignedAfter - unassignedBefore
    if newUnassigned > 0 then
        self:Printf("%d player(s) in this raid are not in the roster. Use /dlc unassigned to review.", newUnassigned)
    end

    -- Bug 2: Log to DLC_Log only — do NOT print to chat (Printf causes spam on every GRU).
    DesolateLootcouncil:DLC_Log("Roster Snapshot Taken." .. (isEncounterKill and " (Boss Kill)" or ""))
end

--- Prints current attendees to chat.
function Attendance:PrintCurrentAttendees()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    local config = db and db.DecayConfig
    if not config or not config.sessionActive then
        self:Printf("No active session.")
        return
    end

    if not config.currentAttendees or next(config.currentAttendees) == nil then
        self:Printf("[DLC] No attendees recorded for this session.")
        return
    end

    local keys = {}
    for k in pairs(config.currentAttendees) do table.insert(keys, k) end
    table.sort(keys)

    self:Printf("--- Current Attendees (%d) ---", #keys)
    for _, name in ipairs(keys) do
        self:Printf("[DLC] Attended: %s", DesolateLootcouncil:GetDisplayName(name))
    end
end

--- Deletes an attendance history entry.
---@param index number|string
---@return boolean success
function Attendance:DeleteAttendanceHistoryEntry(index)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db then return false end

    if index == "CURRENT" then
        if db.DecayConfig and db.DecayConfig.sessionActive then
            self:StopRaidSession(false)
            return true
        end
        return false
    end

    local numIdx = tonumber(index)
    if not numIdx or not db.AttendanceHistory or not db.AttendanceHistory[numIdx] then
        return false
    end

    table.remove(db.AttendanceHistory, numIdx)
    db.historyTimestamp = GetServerTime()
    return true
end

--- Checks if there is pending decay to apply from the last session.
---@return boolean
function Attendance:HasPendingDecay()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.DecayConfig or not db.DecayConfig.enabled then return false end
    if not db.AttendanceHistory or #db.AttendanceHistory == 0 then return false end

    local lastSession = db.AttendanceHistory[1]
    if not lastSession or lastSession.decayApplied ~= nil then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Encounter Tracking Handlers
-- ---------------------------------------------------------------------------

function Attendance:OnZoneChanged()
    if DesolateLootcouncil:IsLFR() then return end
    if not DesolateLootcouncil.API:AmIOfficerOrLM() then return end
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    local isBypass = (db and db.debugMode) or DesolateLootcouncil.isTestRunning
    if not IsInRaid() and not isBypass then return end
    if self:IsSessionActive() then
        self:SnapshotRoster(false)
    end
end

function Attendance:OnGroupRosterUpdate()
    -- Bug 2: GROUP_ROSTER_UPDATE must NOT trigger a roster snapshot.
    -- Snapshots are only valid after boss kills (ENCOUNTER_END success=1).
    -- Recording attendance on group-join/leave causes incorrect attendee lists
    -- and chat spam. This handler is intentionally left as a no-op.
end

function Attendance:OnEncounterStart(event, encounterID, encounterName, difficultyID, groupSize)
    if difficultyID == 7 or difficultyID == 17 or DesolateLootcouncil:IsLFR() then return end
    if not DesolateLootcouncil.API:AmIOfficerOrLM() then return end
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    local simActive = Sim and Sim.GetRoster and #Sim:GetRoster() > 0
    local isBypass = simActive or (db and db.debugMode) or DesolateLootcouncil.isTestRunning
    if not IsInRaid() and not isBypass then return end
    if not self:IsSessionActive() then return end

    self.pullCounts = self.pullCounts or {}
    self.currentEncounter = encounterID
    self.pullCounts[encounterID] = (self.pullCounts[encounterID] or 0) + 1
    self:SnapshotRoster(false)
    DesolateLootcouncil:DLC_Log(string.format("Encounter START: %s (ID: %d, Pull #%d)", tostring(encounterName), encounterID, self.pullCounts[encounterID]))
end

function Attendance:OnEncounterEnd(event, encounterID, encounterName, difficultyID, groupSize, success)
    if difficultyID == 7 or difficultyID == 17 or DesolateLootcouncil:IsLFR() then return end
    if not DesolateLootcouncil.API:AmIOfficerOrLM() then return end
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    local simActive = Sim and Sim.GetRoster and #Sim:GetRoster() > 0
    local isBypass = simActive or (db and db.debugMode) or DesolateLootcouncil.isTestRunning
    if not IsInRaid() and not isBypass then return end
    if not self:IsSessionActive() then return end

    local isKill = (success == 1)
    if isKill then
        self:SnapshotRoster(true)
        if db and db.DecayConfig and db.DecayConfig.bossLogs then
            self.pullCounts = self.pullCounts or {}
            table.insert(db.DecayConfig.bossLogs, {
                encounterID = encounterID,
                name = encounterName,
                pulls = self.pullCounts[encounterID] or 1,
                killed = true,
                killedTime = time()
            })
        end
    end
    self.currentEncounter = nil
    DesolateLootcouncil:DLC_Log(string.format("Encounter END: %s (Success: %s)", tostring(encounterName), tostring(isKill)))
end
