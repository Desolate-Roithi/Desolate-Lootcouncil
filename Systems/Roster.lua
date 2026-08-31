local _, AT = ...
if AT.abortLoad then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local function SafeGetUnitClass(unit)
    unit = unit or "player"
    local ok, _, classFilename = pcall(UnitClass, unit)
    if ok and classFilename and not (type(issecretvalue) == "function" and issecretvalue(classFilename)) then
        return classFilename
    end
    return nil
end

---@class Roster : AceModule, AceEvent-3.0, AceConsole-3.0
local Roster = DesolateLootcouncil:NewModule("Roster", "AceEvent-3.0", "AceConsole-3.0")

-- Define autopass popup at file-load time (main chunk) so the dialog exists before
-- OnInitialize / OnEnable fire. If defined inside OnEnable it would not be available
-- when Addon:OnInitialize() calls UpdateLootMasterStatus() on the very first load.
StaticPopupDialogs["DLC_ENABLE_AUTOPASS"] = {
    text = L["Do you want to enable Autopass for this raid session?\n(Raid members will automatically pass on managed loot)"],
    button1 = L["Enable"],
    button2 = L["No"],
    OnAccept = function()
        DesolateLootcouncil.sessionAutopassAnswered = true
        DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassAnswered = true
        DesolateLootcouncil.db.profile.enableAutoLoot = true
        local Sync = DesolateLootcouncil:GetModule("Sync")
        if Sync and Sync.SendSyncAutopass then Sync:SendSyncAutopass(true) end
    end,
    OnCancel = function()
        DesolateLootcouncil.sessionAutopassAnswered = true
        DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassAnswered = true
        local Sync = DesolateLootcouncil:GetModule("Sync")
        if Sync and Sync.SendSyncAutopass then Sync:SendSyncAutopass(false) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["DLC_ACTIVE_SESSION_PROMPT"] = {
    text = "%s",
    button1 = L["Resume Session"],
    button2 = L["End Session"],
    OnAccept = function()
        DesolateLootcouncil:Print(L["Resuming active raid session."])
    end,
    OnCancel = function()
        local Roster = DesolateLootcouncil:GetModule("Roster")
        if Roster then Roster:StopRaidSession(true) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

StaticPopupDialogs["DLC_NEW_DATE_SESSION_PROMPT"] = {
    text = L["An active raid session from %s was found.\nWould you like to save and close the previous session and start a new one for today?"],
    button1 = L["Save & Start New"],
    button2 = L["Keep Previous"],
    OnAccept = function()
        local RosterMod = DesolateLootcouncil:GetModule("Roster")
        if RosterMod then
            RosterMod:StopRaidSession(true)
            RosterMod:StartRaidSession()
        end
    end,
    OnCancel = function()
        DesolateLootcouncil:Print(L["Keeping previous session active."])
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

StaticPopupDialogs["DLC_DISBAND_CLOSE_SESSION"] = {
    text = L["The raid group has disbanded. Would you like to end and save the current raid session?"],
    button1 = L["End & Save Session"],
    button2 = L["Keep Active"],
    OnAccept = function()
        local RosterMod = DesolateLootcouncil:GetModule("Roster")
        if RosterMod then
            RosterMod:StopRaidSession(true)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

---@class (partial) DLC_Ref_Roster
---@field db table
---@field GetModule fun(self: any, name: string): any
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field GetMain fun(self: any, name: string): string
---@field AmILootMaster fun(self: any): boolean
---@field SendVersionCheck fun(self: any)

---@type DLC_Ref_Roster
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Roster]]

function Roster:OnEnable()
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("ENCOUNTER_START")
    self:RegisterEvent("ENCOUNTER_END")
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterMessage("DLC_VERSION_UPDATE")

    self.scoreMap = {} -- Transient cache for O(1) Smart Recognition
    self:UpdateScoreMap()

    DesolateLootcouncil:DLC_Log("Systems/Roster Loaded")
end

function Roster:OnDisable()
    self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    self:UnregisterEvent("ENCOUNTER_START")
    self:UnregisterEvent("ENCOUNTER_END")
    self:UnregisterEvent("PLAYER_LOGIN")
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")
    self:UnregisterMessage("DLC_VERSION_UPDATE")
end

function Roster:SanitizeMainsAndAlts()
    if not DesolateLootcouncil.db then return end
    local profile = DesolateLootcouncil.db.profile
    if not profile or not profile.MainRoster then return end

    if profile.playerRoster and profile.playerRoster.alts then
        for altName in pairs(profile.playerRoster.alts) do
            local altScore = DesolateLootcouncil:GetScoreName(altName)
            if altScore then
                for mainKey in pairs(profile.MainRoster) do
                    if DesolateLootcouncil:GetScoreName(mainKey) == altScore then
                        profile.MainRoster[mainKey] = nil
                        DesolateLootcouncil:DLC_Log(string.format("Sanitized roster: Removed alt '%s' from MainRoster.", mainKey))
                        break
                    end
                end
            end
        end
    end
end

function Roster:UpdateScoreMap()
    if not DesolateLootcouncil.db then return end
    local profile = DesolateLootcouncil.db.profile
    if not profile or not profile.MainRoster then return end

    self:SanitizeMainsAndAlts()

    self.scoreMap = self.scoreMap or {}
    wipe(self.scoreMap)

    -- 1. Index Mains: Map normalized "score name" to the actual Roster Key (Canonical)
    for canonicalName in pairs(profile.MainRoster) do
        local score = DesolateLootcouncil:GetScoreName(canonicalName)
        if score then
            self.scoreMap[score] = canonicalName
        end
    end

    -- 2. Index Alts: Map normalized alt "score name" to the Main's Roster Key (Canonical)
    if profile.playerRoster and profile.playerRoster.alts then
        for altName, mainName in pairs(profile.playerRoster.alts) do
            local altScore = DesolateLootcouncil:GetScoreName(altName)
            if altScore then
                -- Important: We need the canonical case from MainRoster, not just the string in alts table
                local canonicalMain = self:GetMain(mainName)
                self.scoreMap[altScore] = canonicalMain
            end
        end
    end
end

function Roster:HandleSlashCommand(input)
    local args = { strsplit(" ", input) }
    local cmd = args[1]

    if cmd == "start" then
        self:StartRaidSession()
    elseif cmd == "stop" then
        ---@type UI
        local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
        if UI and UI.ShowAttendanceWindow then
            UI:ShowAttendanceWindow()
        else
            self:StopRaidSession(true)
        end
    elseif cmd == "kill" then
        self:SnapshotRoster()
    elseif cmd == "attend" then
        self:PrintCurrentAttendees()
    else
        DesolateLootcouncil:DLC_Log("Roster Commands: start, stop, kill, attend", true)
    end
end

function Roster:Printf(msg, ...)
    DesolateLootcouncil:DLC_Log(string.format(msg, ...), true)
end

-- ==============================================================================
-- RAID SESSIONS & ATTENDANCE (Delegated to Systems/Attendance.lua)
-- ==============================================================================

function Roster:StartRaidSession()
<<<<<<< HEAD
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.StartRaidSession then Att:StartRaidSession() end
=======
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if config.sessionActive then
        local prevDate = config.currentSessionID and date("%Y-%m-%d", config.currentSessionID)
        local todayDate = date("%Y-%m-%d", time())
        if prevDate and prevDate ~= todayDate and DesolateLootcouncil:AmILootMaster() then
            StaticPopup_Show("DLC_NEW_DATE_SESSION_PROMPT", prevDate)
            return
        end
        self:Printf("Session already active (Started: %s). Auto-saving and stopping previous session.", date("%c", config.currentSessionID))
        self:StopRaidSession(true)
    end

    if DesolateLootcouncil:AmILootMaster() and self:HasPendingDecay() then
        local db = DesolateLootcouncil.db.profile
        local entry = db.AttendanceHistory and db.AttendanceHistory[1]
        self.pendingStartRaidSession = true
        StaticPopup_Show("DLC_PENDING_DECAY", (entry and entry.date) or "N/A", (entry and entry.zone) or "Unknown")
        return
    end
    self.pendingStartRaidSession = nil

    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "raid" then
        self:Printf("Sessions can only be started in Raid instances.")
        return
    end

    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    local simActive = Sim and Sim.GetRoster and #Sim:GetRoster() > 0
    if not IsInRaid() and not simActive then
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

    -- Wipe previous overarching session's awarded items database to start completely fresh
    local session = DesolateLootcouncil.db.profile.session
    if session then
        session.awarded = {}
    end

    self:Printf("Raid Session STARTED. ID: %d", config.currentSessionID)

    if DesolateLootcouncil:AmILootMaster() then
        -- Notify LM if any mains are missing from priority lists
        local Priority = DesolateLootcouncil:GetModule("Priority", true)
        if Priority and Priority.NotifyIfPlayersMissing then
            Priority:NotifyIfPlayersMissing()
        end

        DesolateLootcouncil:PromptAutopass()
    end

    -- Trigger immediate config sync to officers on session start
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.SendDLCHeartbeat then
        Session:SendDLCHeartbeat()
    end
>>>>>>> main
end

function Roster:StopRaidSession(saveHistory)
<<<<<<< HEAD
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.StopRaidSession then Att:StopRaidSession(saveHistory) end
=======
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then
        self:Printf("No active session to stop.")
        return
    end

    if saveHistory then
        local isOfficerOrLM = DesolateLootcouncil:AmIOfficerOrLM()
        if isOfficerOrLM then
            -- Commit to global history
            local db = DesolateLootcouncil.db.profile
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
            if session and session.publicAwardLog then
                entry.publicAwardLog = DesolateLootcouncil.Table.DeepCopy(session.publicAwardLog)
                table.sort(entry.publicAwardLog, function(a, b)
                    local tA = (API and API.ParseItemTimestamp and API:ParseItemTimestamp(a)) or (a.timestamp or 0)
                    local tB = (API and API.ParseItemTimestamp and API:ParseItemTimestamp(b)) or (b.timestamp or 0)
                    return tA < tB
                end)
            end
            -- Deep copy attendees
            for name, _ in pairs(config.currentAttendees or {}) do
                entry.attendees[name] = true
            end
            -- Deep copy attendee details
            if config.attendeeDetails then
                for mainName, chars in pairs(config.attendeeDetails) do
                    entry.attendeeDetails[mainName] = {}
                    for charName, charData in pairs(chars) do
                        entry.attendeeDetails[mainName][charName] = {
                            class = charData.class,
                            kills = charData.kills
                        }
                    end
                end
            end
            -- Deep copy boss logs
            if config.bossLogs then
                for origIdx, b in ipairs(config.bossLogs) do
                    local bRoster = nil
                    if b.roster then
                        bRoster = {}
                        for _, p in ipairs(b.roster) do
                            table.insert(bRoster, {
                                name = p.name,
                                main = p.main,
                                class = p.class
                            })
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

            -- Split multi-date entries if awards/kills span multiple days
            local splitEntries = (API and API.SplitMultiDateAttendanceEntry and API:SplitMultiDateAttendanceEntry(entry)) or { entry }
            for _, sEntry in ipairs(splitEntries) do
                table.insert(db.AttendanceHistory, 1, sEntry)
            end
            table.sort(db.AttendanceHistory, function(a, b)
                local sA = tostring(a.date or a.sessionID or "")
                local sB = tostring(b.date or b.sessionID or "")
                return sA > sB
            end)

            -- Commit to individual player history (Legacy/Detail)
            local count = 0
            for mainName, _ in pairs(config.currentAttendees or {}) do
                -- Ensure roster structure exists
                local roster = db.MainRoster
                if not roster[mainName] then roster[mainName] = {} end
                if not roster[mainName].sessionsAttended then roster[mainName].sessionsAttended = {} end

                table.insert(roster[mainName].sessionsAttended, {
                    id = config.currentSessionID,
                    timestamp = time()
                })
                count = count + 1
            end
            self:Printf("Session ENDED. Saved attendance for %d players.", count)
            db.historyTimestamp = GetServerTime()
            db.rosterTimestamp = GetServerTime()

            -- Sync history to officers if we are LM and still in group
            if DesolateLootcouncil:AmILootMaster() and IsInGroup() then
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
    DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassActive = false
    DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassAnswered = false

    -- Trigger immediate config sync to officers on session stop
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.SendDLCHeartbeat then
        Session:SendDLCHeartbeat()
    end

    local UI = DesolateLootcouncil:GetModule("UI", true)
    if UI and UI.CloseAllWindows then
        UI:CloseAllWindows()
    end
>>>>>>> main
end

function Roster:GetUnitClass(unitName)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.GetUnitClass then return Att:GetUnitClass(unitName) end
    return "WARRIOR"
end

function Roster:RegisterAttendance(unitName, isEncounterKill)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.RegisterAttendance then Att:RegisterAttendance(unitName, isEncounterKill) end
end

function Roster:SnapshotRoster(isEncounterKill)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.SnapshotRoster then Att:SnapshotRoster(isEncounterKill) end
end

function Roster:PrintCurrentAttendees()
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.PrintCurrentAttendees then Att:PrintCurrentAttendees() end
end

---------------------------------------------------------------------------
-- ROSTER MANAGEMENT (Migrated from Core)
---------------------------------------------------------------------------

function Roster:AddMain(name)
    if not DesolateLootcouncil.db then return end
    if not name or name == "" then return end

    local devDB = DesolateLootcouncil.db.profile
    if not devDB then return end
    if not devDB.MainRoster then devDB.MainRoster = {} end
    if not devDB.playerRoster then devDB.playerRoster = { alts = {}, decay = {} } end
    if not devDB.playerRoster.alts then devDB.playerRoster.alts = {} end

    -- Normalize for storage: realmless if local realm
    local normalizedName = Ambiguate(name, "none")

    -- Duplicate Check
    for existingName in pairs(devDB.MainRoster) do
        if DesolateLootcouncil:SmartCompare(existingName, normalizedName) then
            DesolateLootcouncil:DLC_Log("Error: " .. DesolateLootcouncil:GetDisplayName(normalizedName) .. 
                " already exists in Roster as " .. DesolateLootcouncil:GetDisplayName(existingName), true)
            return
        end
    end

    devDB.MainRoster[normalizedName] = { addedAt = time(), isOfficer = false } -- Store main with timestamp
    devDB.playerRoster.alts[normalizedName] = nil           -- Ensure not an alt
    devDB.rosterTimestamp = GetServerTime()
    self:UpdateScoreMap()
    DesolateLootcouncil:DLC_Log("Added Main: " .. DesolateLootcouncil:GetDisplayName(normalizedName))
    
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Roster:SetOfficer(name, flag)
    if not DesolateLootcouncil.db then return end
    if not name or name == "" then return end
    
    local devDB = DesolateLootcouncil.db.profile
    if not devDB then return end
    if not devDB.MainRoster then devDB.MainRoster = {} end
    
    -- If this name is an alt, resolve it to their Main
    local targetMain = self:GetMain(name) or name
    local normalizedName = Ambiguate(targetMain, "none")

    for existingName, data in pairs(devDB.MainRoster) do
        if DesolateLootcouncil:SmartCompare(existingName, normalizedName) then
            data.isOfficer = flag == true
            devDB.rosterTimestamp = GetServerTime()
            
            -- Refresh local player officer cache if it is us
            if DesolateLootcouncil:SmartCompare(existingName, "player") then
                DesolateLootcouncil.amIOfficer = DesolateLootcouncil:AmIOfficerOrLM()
            end
            
            -- Fire event
            self:SendMessage("DLC_OFFICER_FLAG_CHANGED", existingName, flag)
            
            local Sync = DesolateLootcouncil:GetModule("Sync", true)
            if Sync and Sync.SendOfficerFlagSync and IsInGroup() and DesolateLootcouncil:AmILootMaster() then
                Sync:SendOfficerFlagSync(existingName, flag)
            end
            
            LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            return
        end
    end
    
    if flag == true then
        -- Only add as a new main if it's NOT registered as an alt
        local isAlt = false
        if devDB.playerRoster and devDB.playerRoster.alts then
            for altKey in pairs(devDB.playerRoster.alts) do
                if DesolateLootcouncil:SmartCompare(altKey, normalizedName) then
                    isAlt = true
                    break
                end
            end
        end

        if not isAlt then
            devDB.MainRoster[normalizedName] = { addedAt = GetServerTime(), isOfficer = true }
            devDB.rosterTimestamp = GetServerTime()
            
            -- Refresh local player officer cache if it is us
            if DesolateLootcouncil:SmartCompare(normalizedName, "player") then
                DesolateLootcouncil.amIOfficer = DesolateLootcouncil:AmIOfficerOrLM()
            end
            
            -- Fire event
            self:SendMessage("DLC_OFFICER_FLAG_CHANGED", normalizedName, flag)
            
            local Sync = DesolateLootcouncil:GetModule("Sync", true)
            if Sync and Sync.SendOfficerFlagSync and IsInGroup() and DesolateLootcouncil:AmILootMaster() then
                Sync:SendOfficerFlagSync(normalizedName, flag)
            end
            
            LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
        end
    end
end

function Roster:AddAlt(altName, mainName)
    if not DesolateLootcouncil.db then return end
    if not altName or not mainName then return end

    -- Normalize for storage
    local normalizedAlt = Ambiguate(altName, "none")
    local normalizedMain = Ambiguate(mainName, "none")

    if DesolateLootcouncil:SmartCompare(normalizedAlt, normalizedMain) then
        DesolateLootcouncil:DLC_Log("Error: Cannot add a player as an alt to themselves.")
        return
    end

    local profile = DesolateLootcouncil.db.profile
    if not profile then return end
    if not profile.MainRoster then profile.MainRoster = {} end
    if not profile.playerRoster then profile.playerRoster = { alts = {}, decay = {} } end
    if not profile.playerRoster.alts then profile.playerRoster.alts = {} end
    local roster = profile.playerRoster

    -- 1. Check if the 'new alt' was previously a Main with their own alts
    -- We need to re-parent those alts to the NEW main.
    for existingAlt, existingMain in pairs(roster.alts) do
        if DesolateLootcouncil:SmartCompare(existingMain, normalizedAlt) then
            roster.alts[existingAlt] = normalizedMain
            DesolateLootcouncil:DLC_Log("Re-linked inherited alt: " .. 
                DesolateLootcouncil:GetDisplayName(existingAlt) .. " -> " .. 
                DesolateLootcouncil:GetDisplayName(normalizedMain))
        end
    end
    -- 2. Perform the standard assignment
    roster.alts[normalizedAlt] = normalizedMain
    -- 3. Remove from Mains list if present (Smart Aware)
    if profile.MainRoster then
        for mainKey in pairs(profile.MainRoster) do
            if DesolateLootcouncil:SmartCompare(mainKey, normalizedAlt) then
                profile.MainRoster[mainKey] = nil
                DesolateLootcouncil:DLC_Log("Converted Main to Alt: " .. DesolateLootcouncil:GetDisplayName(mainKey))
                break
            end
        end
    end

    profile.rosterTimestamp = GetServerTime()
    self:UpdateScoreMap()
    DesolateLootcouncil:DLC_Log("Linked Alt " .. DesolateLootcouncil:GetDisplayName(normalizedAlt) .. 
        " to " .. DesolateLootcouncil:GetDisplayName(normalizedMain))
        
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Roster:RemovePlayer(name)
    if not DesolateLootcouncil.db then return end
    if not name then return end

    local profile = DesolateLootcouncil.db.profile
    if not profile then return end
    if not profile.MainRoster then profile.MainRoster = {} end
    if not profile.playerRoster then profile.playerRoster = { alts = {}, decay = {} } end
    if not profile.playerRoster.alts then profile.playerRoster.alts = {} end

    -- Normalize lookup
    local normalizedName = Ambiguate(name, "none")

    -- Try delete as Main
    if profile.MainRoster and profile.MainRoster[normalizedName] then
        profile.MainRoster[normalizedName] = nil
        profile.rosterTimestamp = GetServerTime()
        -- Unlink alts
        if profile.playerRoster and profile.playerRoster.alts then
            for alt, main in pairs(profile.playerRoster.alts) do
                if DesolateLootcouncil:SmartCompare(main, normalizedName) then
                    profile.playerRoster.alts[alt] = nil
                    DesolateLootcouncil:DLC_Log("Unlinked Alt: " .. DesolateLootcouncil:GetDisplayName(alt))
                end
            end
        end
        self:UpdateScoreMap()
        DesolateLootcouncil:DLC_Log("Removed Main: " .. DesolateLootcouncil:GetDisplayName(normalizedName))
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
        return
    end

    -- Try delete as Alt
    if profile.playerRoster.alts[normalizedName] then
        profile.playerRoster.alts[normalizedName] = nil
        profile.rosterTimestamp = GetServerTime()
        self:UpdateScoreMap()
        DesolateLootcouncil:DLC_Log("Removed Alt: " .. DesolateLootcouncil:GetDisplayName(normalizedName))
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function Roster:GetMain(name)
    if not DesolateLootcouncil.db or not name or name == "" then return name end
    
    -- 1. Fast Path: Use ScoreMap if built
    local score = DesolateLootcouncil:GetScoreName(name)
    if self.scoreMap and self.scoreMap[score] then
        return self.scoreMap[score]
    end

    -- 2. Fallback Path: This handles the initialization phase before the cache is warm
    local profile = DesolateLootcouncil.db.profile
    if profile.playerRoster and profile.playerRoster.alts then
        for altName, mainName in pairs(profile.playerRoster.alts) do
            if DesolateLootcouncil:SmartCompare(altName, name) then
                return mainName
            end
        end
    end

    if profile.MainRoster then
        for mainName, _ in pairs(profile.MainRoster) do
            if DesolateLootcouncil:SmartCompare(mainName, name) then
                return mainName
            end
        end
    end

    return name
end

---------------------------------------------------------------------------
-- UNASSIGNED PLAYERS REVIEW QUEUE
---------------------------------------------------------------------------

function Roster:RecordUnassignedPlayer(name, source)
    if not DesolateLootcouncil.db or not name or name == "" then return end
    local profile = DesolateLootcouncil.db.profile
    if not profile then return end

    local normalizedName = Ambiguate(name, "none")
    local score = DesolateLootcouncil:GetScoreName(normalizedName)

    -- Check if already known as Main or Alt
    if score and self.scoreMap and self.scoreMap[score] then
        return
    end

    if profile.playerRoster and profile.playerRoster.alts then
        for altName in pairs(profile.playerRoster.alts) do
            if DesolateLootcouncil:SmartCompare(altName, normalizedName) then
                return
            end
        end
    end

    if profile.MainRoster then
        for mainName in pairs(profile.MainRoster) do
            if DesolateLootcouncil:SmartCompare(mainName, normalizedName) then
                return
            end
        end
    end

    profile.unassignedPlayers = profile.unassignedPlayers or {}
    if not profile.unassignedPlayers[normalizedName] then
        profile.unassignedPlayers[normalizedName] = {
            firstSeen = GetServerTime(),
            source = source or "Raid",
            class = SafeGetUnitClass(name) or "WARRIOR"
        }
        profile.unassignedTimestamp = GetServerTime()
        DesolateLootcouncil:DLC_Log(string.format("Recorded unassigned player: |cFFFFFF00%s|r (%s). Requires Loot Master assignment.", normalizedName, source or "Raid"))
        self:SendMessage("DLC_UNASSIGNED_PLAYERS_UPDATED")

        local Session = DesolateLootcouncil:GetModule("Session", true)
        if Session and Session.SendDLCHeartbeat and DesolateLootcouncil:AmILootMaster() then
            if not self.unassignedSyncTimer then
                self.unassignedSyncTimer = C_Timer.NewTimer(5.0, function()
                    self.unassignedSyncTimer = nil
                    if Session and Session.SendDLCHeartbeat and DesolateLootcouncil:AmILootMaster() then
                        Session:SendDLCHeartbeat()
                    end
                end)
            end
        end
    end
end

function Roster:GetUnassignedPlayers()
    if not DesolateLootcouncil.db then return {} end
    local profile = DesolateLootcouncil.db.profile
    if not profile or not profile.unassignedPlayers then return {} end

    local list = {}
    for name, data in pairs(profile.unassignedPlayers) do
        table.insert(list, {
            name = name,
            firstSeen = data.firstSeen or 0,
            source = data.source or "Raid",
            class = data.class or SafeGetUnitClass(name) or "WARRIOR"
        })
    end
    table.sort(list, function(a, b)
        if a.firstSeen ~= b.firstSeen then
            return a.firstSeen < b.firstSeen
        end
        return tostring(a.name) < tostring(b.name)
    end)
    return list
end

function Roster:AssignAsMain(name)
    if not DesolateLootcouncil.db or not name then return end
    local profile = DesolateLootcouncil.db.profile
    if profile and profile.unassignedPlayers then
        local norm = Ambiguate(name, "none")
        for k in pairs(profile.unassignedPlayers) do
            if DesolateLootcouncil:SmartCompare(k, norm) then
                profile.unassignedPlayers[k] = nil
                profile.unassignedTimestamp = GetServerTime()
                break
            end
        end
    end
    self:AddMain(name)
    self:SendMessage("DLC_UNASSIGNED_PLAYERS_UPDATED")

    local Session = DesolateLootcouncil:GetModule("Session", true)
    if Session and Session.SendDLCHeartbeat and DesolateLootcouncil:AmILootMaster() then
        Session:SendDLCHeartbeat()
    end
end

function Roster:AssignAsAlt(altName, mainName)
    if not DesolateLootcouncil.db or not altName or not mainName then return end
    local profile = DesolateLootcouncil.db.profile
    if profile and profile.unassignedPlayers then
        local norm = Ambiguate(altName, "none")
        for k in pairs(profile.unassignedPlayers) do
            if DesolateLootcouncil:SmartCompare(k, norm) then
                profile.unassignedPlayers[k] = nil
                profile.unassignedTimestamp = GetServerTime()
                break
            end
        end
    end
    self:AddAlt(altName, mainName)
    self:SendMessage("DLC_UNASSIGNED_PLAYERS_UPDATED")

    local Session = DesolateLootcouncil:GetModule("Session", true)
    if Session and Session.SendDLCHeartbeat and DesolateLootcouncil:AmILootMaster() then
        Session:SendDLCHeartbeat()
    end
end

function Roster:DismissUnassignedPlayer(name)
    if not DesolateLootcouncil.db or not name then return end
    local profile = DesolateLootcouncil.db.profile
    if profile and profile.unassignedPlayers then
        local norm = Ambiguate(name, "none")
        for k in pairs(profile.unassignedPlayers) do
            if DesolateLootcouncil:SmartCompare(k, norm) then
                profile.unassignedPlayers[k] = nil
                profile.unassignedTimestamp = GetServerTime()
                break
            end
        end
    end
    self:SendMessage("DLC_UNASSIGNED_PLAYERS_UPDATED")

    local Session = DesolateLootcouncil:GetModule("Session", true)
    if Session and Session.SendDLCHeartbeat and DesolateLootcouncil:AmILootMaster() then
        Session:SendDLCHeartbeat()
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLERS
---------------------------------------------------------------------------

function Roster:ZONE_CHANGED_NEW_AREA()
    local name, instanceType = GetInstanceInfo()
    local config = DesolateLootcouncil.db.profile.DecayConfig

    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    local simActive = Sim and Sim.GetRoster and #Sim:GetRoster() > 0

    if instanceType == "raid" and (IsInRaid() or simActive) then
        if not config.sessionActive then
            self:Printf("Entered Raid Instance (%s). Starting Session...", name)
            self:StartRaidSession()
        else
            -- We are transitioning between areas inside the same raid instance
            -- (e.g. wing changes, trash → boss, etc.).
            -- DO NOT wipe sessionAutopassActive here — the LM answered the popup
            -- on session start and the value must survive internal zone changes.
            -- If the LM somehow never got the popup (e.g. session was persisted
            -- across a /reload without an autopass answer), re-show it.
            if IsInRaid() and DesolateLootcouncil:AmILootMaster() and not DesolateLootcouncil.sessionAutopassAnswered then
                DesolateLootcouncil:PromptAutopass()
            end
        end
        -- Auto-ping the LM to sync Autopass and IM configs if joining late
        DesolateLootcouncil:SendVersionCheck()
    elseif instanceType ~= "raid" and config.sessionActive then
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Left Raid (%s). Session is still ACTIVE.", name))
    end
end

function Roster:ENCOUNTER_START(event, encounterID, encounterName, difficultyID, groupSize)
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then return end

    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    local simActive = Sim and Sim.GetRoster and #Sim:GetRoster() > 0
    if not IsInRaid() and not simActive then return end

    config.bossLogs = config.bossLogs or {}

    local bossEntry = nil
    for _, b in ipairs(config.bossLogs) do
        local sameEncounter = (b.encounterID == encounterID) or (b.name == encounterName)
        local sameDifficulty = (not b.difficultyID or not difficultyID or b.difficultyID == difficultyID)
        if sameEncounter and sameDifficulty then
            bossEntry = b
            break
        end
    end

    if not bossEntry then
        bossEntry = {
            encounterID = encounterID,
            name = encounterName,
            difficultyID = difficultyID,
            pulls = 0,
            killed = false,
        }
        table.insert(config.bossLogs, bossEntry)
    else
        if difficultyID and not bossEntry.difficultyID then
            bossEntry.difficultyID = difficultyID
        end
    end

    bossEntry.pulls = bossEntry.pulls + 1
    config.lastActivity = time()
    if DesolateLootcouncil.db.global then
        DesolateLootcouncil.db.global.activeRaidLastActivity = config.lastActivity
    end
end

function Roster:ENCOUNTER_END(event, encounterID, encounterName, difficultyID, groupSize, success)
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then return end

    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    local simActive = Sim and Sim.GetRoster and #Sim:GetRoster() > 0
    if not IsInRaid() and not simActive then return end

    config.bossLogs = config.bossLogs or {}

    local bossEntry = nil
    for _, b in ipairs(config.bossLogs) do
        local sameEncounter = (b.encounterID == encounterID) or (b.name == encounterName)
        local sameDifficulty = (not b.difficultyID or not difficultyID or b.difficultyID == difficultyID)
        if sameEncounter and sameDifficulty then
            bossEntry = b
            break
        end
    end

    if not bossEntry then
        bossEntry = {
            encounterID = encounterID,
            name = encounterName,
            difficultyID = difficultyID,
            pulls = 1,
            killed = false,
        }
        table.insert(config.bossLogs, bossEntry)
    else
        if difficultyID and not bossEntry.difficultyID then
            bossEntry.difficultyID = difficultyID
        end
    end

    if success == 1 then
        bossEntry.killed = true
        bossEntry.killedTime = time()

        -- Capture group roster for the kill
        local killRoster = {}
        if IsInGroup() then
            local members = GetNumGroupMembers()
            if members > 0 then
                for i = 1, members do
                    local name = GetRaidRosterInfo(i)
                    if name then
                        local mainName = self:GetMain(name) or name
                        local class = self:GetUnitClass(name) or "WARRIOR"
                        table.insert(killRoster, { name = name, main = mainName, class = class })
                    end
                end
            end
        end

        if Sim then
            local sims = Sim:GetRoster()
            for _, name in ipairs(sims) do
                local mainName = self:GetMain(name) or name
                local class = self:GetUnitClass(name) or "WARRIOR"
                table.insert(killRoster, { name = name, main = mainName, class = class })
            end
        end

        table.sort(killRoster, function(a, b)
            return a.name < b.name
        end)

        bossEntry.roster = killRoster

        self:SnapshotRoster(true)
        self:Printf("Encounter '%s' Defeated. Attendance updated.", encounterName)

        DesolateLootcouncil:SendMessage("DLC_HISTORY_UPDATED")
    end

    config.lastActivity = time()
    if DesolateLootcouncil.db.global then
        DesolateLootcouncil.db.global.activeRaidLastActivity = config.lastActivity
    end
end

function Roster:PLAYER_LOGIN()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    local globalDb = DesolateLootcouncil.db.global
    local isLM = false
    local myName = UnitName("player")

    if globalDb then
        local normPlayer = AT.NormalizeName(myName)

        local activeLM = globalDb.activeRaidLM
        if activeLM and activeLM ~= "" and (AT.NormalizeName(activeLM) == normPlayer or AT.NormalizeName(activeLM) == "player") then
            isLM = true
        else
            local profiles = DesolateLootcouncil.db.sv and DesolateLootcouncil.db.sv.profiles
            local targetProfile = globalDb.activeRaidProfile
            local configuredLM = profiles and targetProfile and profiles[targetProfile] and profiles[targetProfile].configuredLM
            if configuredLM and configuredLM ~= "" and (AT.NormalizeName(configuredLM) == normPlayer or AT.NormalizeName(configuredLM) == "player") then
                isLM = true
            end
        end
    end

    if config.sessionActive and isLM then
        local delta = time() - (config.lastActivity or 0)
        local warningMsg = L["An active raid session was found.\nWould you like to resume this session or end it?"]
        if delta > 43200 then -- 12 hours
            warningMsg = string.format(L["An active raid session was found (inactive for %.1f hours).\nWould you like to resume this session or end it?"], delta / 3600)
        end
        StaticPopup_Show("DLC_ACTIVE_SESSION_PROMPT", warningMsg)
    end
end

local gruResetTimer = nil

function Roster:CheckForNewRaidMembers()
    if not IsInRaid() or not DesolateLootcouncil:AmILootMaster() then return end
    
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config or not config.sessionActive then return end
    
    local profile = DesolateLootcouncil.db.profile
    if not profile then return end

    local members = GetNumGroupMembers()
    for i = 1, members do
        local name = GetRaidRosterInfo(i)
        if name then
            local isAddonUser = false
            if DesolateLootcouncil.activeAddonUsers then
                for user in pairs(DesolateLootcouncil.activeAddonUsers) do
                    if DesolateLootcouncil:SmartCompare(user, name) then
                        isAddonUser = true
                        break
                    end
                end
            end

            if isAddonUser then
                local normalizedName = Ambiguate(name, "none")
                local score = DesolateLootcouncil:GetScoreName(normalizedName)

                -- Check if already known as Main or Alt
                local alreadyKnown = false
                if score and self.scoreMap and self.scoreMap[score] then
                    alreadyKnown = true
                end

                if not alreadyKnown and profile.playerRoster and profile.playerRoster.alts then
                    for altName in pairs(profile.playerRoster.alts) do
                        if DesolateLootcouncil:SmartCompare(altName, normalizedName) then
                            alreadyKnown = true
                            break
                        end
                    end
                end

                if not alreadyKnown and profile.MainRoster then
                    for mainName in pairs(profile.MainRoster) do
                        if DesolateLootcouncil:SmartCompare(mainName, normalizedName) then
                            alreadyKnown = true
                            break
                        end
                    end
                end

                if not alreadyKnown then
                    self:RecordUnassignedPlayer(normalizedName, "Raid")
                end
            end
        end
    end
end

function Roster:DLC_VERSION_UPDATE()
    self:CheckForNewRaidMembers()
end

local function ResetAutopassSession()
    if IsInRaid() then return end
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if config.sessionActive then return end
    
    if DesolateLootcouncil.sessionAutopassActive or config.sessionAutopassActive then
        DesolateLootcouncil.sessionAutopassActive  = false
        DesolateLootcouncil.sessionAutopassAnswered = false
        config.sessionAutopassActive = false
        config.sessionAutopassAnswered = false
        DesolateLootcouncil:DLC_Log("Raid group disbanded. Autopass session reset.", true)
    end
end

local function HandleRaidDisband()
    if IsInRaid() then return end
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config then return end

    if config.sessionActive then
        local isLM = false
        if config.currentSessionLM and config.currentSessionLM ~= "" then
            isLM = DesolateLootcouncil:SmartCompare(config.currentSessionLM, "player")
        elseif DesolateLootcouncil.db.global and DesolateLootcouncil.db.global.activeRaidLM and DesolateLootcouncil.db.global.activeRaidLM ~= "" then
            isLM = DesolateLootcouncil:SmartCompare(DesolateLootcouncil.db.global.activeRaidLM, "player")
        elseif DesolateLootcouncil.activeLootMaster and DesolateLootcouncil.activeLootMaster ~= "" then
            isLM = DesolateLootcouncil:SmartCompare(DesolateLootcouncil.activeLootMaster, "player")
        end

        if isLM then
            -- Prompt LM whether they want to close and save the raid session
            StaticPopup_Show("DLC_DISBAND_CLOSE_SESSION")
        else
            -- Officers & raiders: autoclose session without saving locally (LM syncs saved history when closed)
            local Att = DesolateLootcouncil:GetModule("Attendance", true)
            if Att and Att.StopRaidSession then
                Att:StopRaidSession(false)
            else
                local RosterMod = DesolateLootcouncil:GetModule("Roster", true)
                if RosterMod and RosterMod.StopRaidSession then
                    RosterMod:StopRaidSession(false)
                end
            end
        end
    end
    ResetAutopassSession()
end

local function BroadcastAutopassState()
    if not DesolateLootcouncil:AmILootMaster() then return end
    local Sync = DesolateLootcouncil:GetModule("Sync")
    if Sync and DesolateLootcouncil.sessionAutopassActive ~= nil then
        Sync:SendSyncAutopass(DesolateLootcouncil.sessionAutopassActive)
    end
end

function Roster:GROUP_ROSTER_UPDATE()
    if gruResetTimer then gruResetTimer:Cancel() end
    gruResetTimer = C_Timer.NewTimer(0.5, function()
        gruResetTimer = nil
        if not IsInRaid() then
            -- Double check after 3 seconds to ensure this isn't a brief loading screen or portal blip
            C_Timer.After(3.0, HandleRaidDisband)
            return
        end
        self:CheckForNewRaidMembers()
        -- Sync Autopass to newly joined members or after a group update (if LM)
        BroadcastAutopassState()
    end)
end

--- Applies a received roster sync payload from the Loot Master.
--- Fully replaces MainRoster and alt links, then rebuilds the scoreMap.
---@param syncedRoster table  { mains = {[name]=data}, alts = {[alt]=main} }
function Roster:ReceiveRosterSync(syncedRoster)
    if not syncedRoster or type(syncedRoster) ~= "table" then return end
    local db = DesolateLootcouncil.db.profile
    if not db then return end

    local incomingTs = syncedRoster.timestamp or 0

    -- Overwrite MainRoster
    db.MainRoster = {}
    for name, data in pairs(syncedRoster.mains or {}) do
        db.MainRoster[name] = { addedAt = data.addedAt or 0, isOfficer = data.isOfficer == true }
    end

    -- Overwrite alt links
    if not db.playerRoster then db.playerRoster = { alts = {} } end
    db.playerRoster.alts = {}
    for alt, main in pairs(syncedRoster.alts or {}) do
        db.playerRoster.alts[alt] = main
    end

    db.rosterTimestamp = incomingTs

    -- Clean any alts that are mistakenly in MainRoster
    self:SanitizeMainsAndAlts()

    -- Rebuild cache
    self:UpdateScoreMap()

    local mainCount = 0
    for _ in pairs(db.MainRoster) do mainCount = mainCount + 1 end
    DesolateLootcouncil:DLC_Log(string.format(
        "Roster Sync received from LM. %d mains applied.", mainCount), true)

    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Roster:HasPendingDecay()
    local db = DesolateLootcouncil.db.profile
    if db.AttendanceHistory and db.AttendanceHistory[1] then
        local entry = db.AttendanceHistory[1]
        if entry.decayApplied == nil then
            return true
        end
    end
    return false
end

function Roster:ApplyDecayForLastSession(skip)
    local db = DesolateLootcouncil.db.profile
    if not db.AttendanceHistory or not db.AttendanceHistory[1] then return end
    local entry = db.AttendanceHistory[1]
    if skip then
        entry.decayApplied = -1
        DesolateLootcouncil:Print("Decay for last session skipped.")
        return
    end

    local absent = {}
    local roster = db.MainRoster or {}
    for name in pairs(roster) do
        if not entry.attendees[name] then
            absent[name] = true
        end
    end

    local dbLists = db.PriorityLists or {}
    local penalty = db.DecayConfig and db.DecayConfig.defaultPenalty or 1
    if penalty > 0 then
        for _, listObj in ipairs(dbLists) do
            DesolateLootcouncil.API:CalculateListDecay(listObj, penalty, absent)
        end
        DesolateLootcouncil:Print(string.format("Applied +%d Position Decay to all lists for absent players.", penalty))
    else
        DesolateLootcouncil:Print("Decay penalty is 0. No priorities changed.")
    end

    entry.decayApplied = GetServerTime()
end

--- Deletes an attendance history entry by index.
---@param index number|string
function Roster:DeleteAttendanceEntry(index)
    local db = DesolateLootcouncil.db.profile
    if db.AttendanceHistory and db.AttendanceHistory[index] then
        table.remove(db.AttendanceHistory, index)
        db.historyTimestamp = GetServerTime()
    end
end

--- Returns a colored difficulty badge string (e.g. |cff1eff00[NHC]|r, |cff0070dd[HC]|r, |cffff8000[M]|r, |cff00ccff[LFR]|r)
---@param difficultyID number|string|nil
---@param bossName string|nil
---@return string|nil
function Roster:GetDifficultyBadge(difficultyID, bossName)
    if type(self) ~= "table" then
        bossName = difficultyID
        difficultyID = self
    end
    local diff = tonumber(difficultyID)
    if diff == 14 or difficultyID == "NHC" or difficultyID == "Normal" then
        return "|cff1eff00[NHC]|r"
    elseif diff == 15 or difficultyID == "HC" or difficultyID == "Heroic" then
        return "|cff0070dd[HC]|r"
    elseif diff == 16 or difficultyID == "M" or difficultyID == "Mythic" then
        return "|cffff8000[M]|r"
    elseif diff == 17 or difficultyID == "LFR" or difficultyID == "Looking For Raid" then
        return "|cff00ccff[LFR]|r"
    end

    if bossName and type(bossName) == "string" then
        local lowerName = bossName:lower()
        if lowerName:find("%(heroic%)") or lowerName:find("%[hc%]") or lowerName:find("%(hc%)") then
            return "|cff0070dd[HC]|r"
        elseif lowerName:find("%(mythic%)") or lowerName:find("%[m%]") or lowerName:find("%(m%)") then
            return "|cffff8000[M]|r"
        elseif lowerName:find("%(normal%)") or lowerName:find("%[nhc%]") or lowerName:find("%(nhc%)") then
            return "|cff1eff00[NHC]|r"
        elseif lowerName:find("%(lfr%)") or lowerName:find("%[lfr%]") then
            return "|cff00ccff[LFR]|r"
        end
    end

    return nil
end

--- Strips difficulty suffix patterns from a boss name string
---@param bossName string
---@return string
function Roster:StripDifficultySuffix(bossName)
    local name = (type(self) ~= "table" and self) or bossName
    if not name or type(name) ~= "string" then return name or "" end
    local clean = name:gsub("%s*%(%s*[Hh]eroic%s*%)", "")
    clean = clean:gsub("%s*%(%s*[Nn]ormal%s*%)", "")
    clean = clean:gsub("%s*%(%s*[Mm]ythic%s*%)", "")
    clean = clean:gsub("%s*%(%s*[Nn][Hh][Cc]%s*%)", "")
    clean = clean:gsub("%s*%(%s*[Hh][Cc]%s*%)", "")
    clean = clean:gsub("%s*%(%s*[Mm]%s*%)", "")
    clean = clean:gsub("%s*%(%s*[Ll][Ff][Rr]%s*%)", "")
    clean = clean:gsub("%s*%[%s*[Nn][Hh][Cc]%s*%]", "")
    clean = clean:gsub("%s*%[%s*[Hh][Cc]%s*%]", "")
    clean = clean:gsub("%s*%[%s*[Mm]%s*%]", "")
    clean = clean:gsub("%s*%[%s*[Ll][Ff][Rr]%s*%]", "")
    return clean
end

function Roster:GetRosterText()
    local db = DesolateLootcouncil.db.profile
    if not db.MainRoster then return "No Roster Found." end
    local text = ""
    local sortedMains = {}
    for name in pairs(db.MainRoster) do table.insert(sortedMains, name) end
    table.sort(sortedMains)
    for _, main in ipairs(sortedMains) do
        local mainText = main
        local data = db.MainRoster[main]
        if data and data.isOfficer then mainText = mainText .. " (Officer)" end
        text = text .. mainText
        local alts = {}
        if db.playerRoster and db.playerRoster.alts then
            for alt, parent in pairs(db.playerRoster.alts) do
                if parent == main then table.insert(alts, alt) end
            end
        end
        if #alts > 0 then
            table.sort(alts)
            text = text .. " -> " .. table.concat(alts, ", ")
        end
        text = text .. "\n"
    end
    return text
end

function Roster:GetMainRosterList()
    local list = {}
    local db = DesolateLootcouncil.db.profile
    if db.MainRoster then
        for name, data in pairs(db.MainRoster) do
            list[name] = (data and data.isOfficer) and (name .. " (Officer)") or name
        end
    end
    return list
end

function Roster:GetAllPlayersList()
    local list = self:GetMainRosterList()
    local db = DesolateLootcouncil.db.profile
    if db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            list[alt] = "   └ " .. alt .. " (Alt of " .. main .. ")"
        end
    end
    return list
end

function Roster:DeleteAttendanceHistoryEntry(index)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db then return end
    if type(index) == "number" and db.AttendanceHistory and db.AttendanceHistory[index] then
        table.remove(db.AttendanceHistory, index)
        DesolateLootcouncil:DLC_Log(string.format("Deleted attendance history entry #%d.", index))
    elseif index == "CURRENT" then
        local config = db.DecayConfig
        if config then
            config.sessionActive = false
            config.currentSessionID = nil
        end
        if db.session then
            db.session.awarded = {}
            db.session.bidding = {}
            db.session.backlog = {}
            db.session.publicAwardLog = {}
        end
        DesolateLootcouncil:DLC_Log("Cleared active session attendance and loot.")
    end
end

function Roster:RenamePlayer(oldName, newName)
    if not oldName or oldName == "" or not newName or newName == "" then return false end
    if oldName == newName then return false end
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db then return false end

    oldName = DesolateLootcouncil:NormalizeName(oldName)
    newName = DesolateLootcouncil:NormalizeName(newName)

    -- Case 1: oldName is a Main
    if db.MainRoster and db.MainRoster[oldName] then
        db.MainRoster[newName] = db.MainRoster[oldName]
        db.MainRoster[oldName] = nil

        if db.playerRoster and db.playerRoster.alts then
            for alt, main in pairs(db.playerRoster.alts) do
                if main == oldName then
                    db.playerRoster.alts[alt] = newName
                end
            end
        end

        if db.PriorityLists then
            for _, list in ipairs(db.PriorityLists) do
                local players = list.players or list.order
                if players then
                    for i, name in ipairs(players) do
                        if name == oldName then
                            players[i] = newName
                        end
                    end
                end
            end
        end

        DesolateLootcouncil:DLC_Log(string.format("Renamed Main player '%s' to '%s'.", oldName, newName))
        self:SnapshotRoster()
        return true
    end

    -- Case 2: oldName is an Alt
    if db.playerRoster and db.playerRoster.alts and db.playerRoster.alts[oldName] then
        local main = db.playerRoster.alts[oldName]
        db.playerRoster.alts[newName] = main
        db.playerRoster.alts[oldName] = nil

        DesolateLootcouncil:DLC_Log(string.format("Renamed Alt player '%s' to '%s' (Main: %s).", oldName, newName, main))
        self:SnapshotRoster()
        return true
    end

    return false
end


