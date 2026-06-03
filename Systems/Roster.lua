local _, AT = ...
if AT.abortLoad then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

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
        local Comm = DesolateLootcouncil:GetModule("Comm")
        if Comm and Comm.SendSyncAutopass then Comm:SendSyncAutopass(true) end
    end,
    OnCancel = function()
        DesolateLootcouncil.sessionAutopassAnswered = true
        DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassAnswered = true
        local Comm = DesolateLootcouncil:GetModule("Comm")
        if Comm and Comm.SendSyncAutopass then Comm:SendSyncAutopass(false) end
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

function Roster:UpdateScoreMap()
    if not DesolateLootcouncil.db then return end
    local profile = DesolateLootcouncil.db.profile
    if not profile or not profile.MainRoster then return end

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
-- RAID SESSIONS vs LOOT SESSIONS:
-- "Raid Sessions" (Tracked here) manage overarching group attendance and 
-- priority decay metrics based on `currentSessionID`.
-- "Loot Sessions" (Managed by `Session.lua`) are per-boss voting events 
-- triggered to facilitate item distribution.
-- ==============================================================================

--- Starts a new tracking session
function Roster:StartRaidSession()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if config.sessionActive then
        self:Printf("Session already active (Started: %s)", date("%c", config.currentSessionID))
        return
    end

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
    config.currentAttendees = {}
    config.attendeeDetails = {}
    config.bossLogs = {}
    config.lastActivity = time()

    -- Wipe previous overarching session's awarded items database to start completely fresh
    local session = DesolateLootcouncil.db.profile.session
    if session then
        session.awarded = {}
    end

    self:Printf("Raid Session STARTED. ID: %d", config.currentSessionID)

    if DesolateLootcouncil:AmILootMaster() then
        -- Priority list propagation is now manual only via the Item Manager UI button.

        StaticPopup_Show("DLC_ENABLE_AUTOPASS")
    end
end

--- Stops the current session and optionally saves history
---@param saveHistory boolean
function Roster:StopRaidSession(saveHistory)
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then
        self:Printf("No active session to stop.")
        return
    end

    if saveHistory then
        -- Commit to global history
        local db = DesolateLootcouncil.db.profile
        if not db.AttendanceHistory then db.AttendanceHistory = {} end

        local entry = {
            date            = date("%Y-%m-%d %H:%M:%S", config.currentSessionID),
            zone            = GetRealZoneText() or "Unknown",
            sessionID       = config.currentSessionID,
            attendees       = {},
            attendeeDetails = {},
            bossLogs        = {}
        }
        -- Deep copy attendees
        for name, _ in pairs(config.currentAttendees) do
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
            for _, b in ipairs(config.bossLogs) do
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
                    roster = bRoster
                })
            end
        end
        table.insert(db.AttendanceHistory, 1, entry) -- Insert at top (Newest)

        -- Commit to individual player history (Legacy/Detail)
        local count = 0
        for mainName, _ in pairs(config.currentAttendees) do
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
    else
        self:Printf("Session ABORTED. No history saved.")
    end

    config.sessionActive = false
    config.currentSessionID = nil
    config.currentAttendees = {}
    config.attendeeDetails = {}
    config.bossLogs = {}

    DesolateLootcouncil.sessionAutopassActive = false
    DesolateLootcouncil.sessionAutopassAnswered = false
    DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassActive = false
    DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassAnswered = false
end

--- Helper to get a unit's class filename robustly
---@param unitName string
---@return string classFilename
function Roster:GetUnitClass(unitName)
    if DesolateLootcouncil:SmartCompare(unitName, "player") then
        local _, classFilename = UnitClass("player")
        return classFilename
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
                local _, fileName = UnitClass("party" .. i)
                return fileName
            end
        end
    end
    -- Fallback: look up in MainRoster
    local main = self:GetMain(unitName) or unitName
    for mName, rData in pairs(DesolateLootcouncil.db.profile.MainRoster) do
        if DesolateLootcouncil:SmartCompare(mName, main) then
            if rData and rData.class and rData.class ~= "" then
                return rData.class
            end
        end
    end
    return "WARRIOR"
end

--- Register a player (or their Main) as present
---@param unitName string
---@param isEncounterKill boolean|nil
function Roster:RegisterAttendance(unitName, isEncounterKill)
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then return end

    local mainName = self:GetMain(unitName) or unitName

    -- Verification: Does this main exist in our MainRoster?
    if DesolateLootcouncil.db.profile.MainRoster[mainName] then
        if not config.currentAttendees then config.currentAttendees = {} end
        if not config.currentAttendees[mainName] then
            config.currentAttendees[mainName] = true
            DesolateLootcouncil:DLC_Log(string.format("Attendance Registered: %s (Main: %s)", 
                DesolateLootcouncil:GetDisplayName(unitName), 
                DesolateLootcouncil:GetDisplayName(mainName)))
        end

        -- Detailed multi-character tracking
        if not config.attendeeDetails then config.attendeeDetails = {} end
        if not config.attendeeDetails[mainName] then
            config.attendeeDetails[mainName] = {}
        end

        local cleanUnitName = DesolateLootcouncil:GetDisplayName(unitName)
        if not config.attendeeDetails[mainName][cleanUnitName] then
            local class = self:GetUnitClass(unitName)
            config.attendeeDetails[mainName][cleanUnitName] = {
                class = class,
                kills = 0
            }
        end

        if isEncounterKill then
            config.attendeeDetails[mainName][cleanUnitName].kills = config.attendeeDetails[mainName][cleanUnitName].kills + 1
        end
    else
        -- Show both the original unit name and the resolved main so the officer
        -- knows exactly which DB entry is missing.
        local formattedMain = DesolateLootcouncil:GetDisplayName(mainName)
        local formattedUnit = DesolateLootcouncil:GetDisplayName(unitName)
        local hint = (mainName ~= unitName)
            and string.format("'%s' (resolved from alt '%s') is not in the MainRoster", formattedMain, formattedUnit)
            or string.format("'%s' is not in the MainRoster — use /dlc roster add to add them", formattedUnit)
        DesolateLootcouncil:DLC_Log("Attendance Rejected: " .. hint, true)
    end
end

--- Captures current group members (or simulates if persistent group set)
---@param isEncounterKill boolean|nil
function Roster:SnapshotRoster(isEncounterKill)
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then
        self:Printf("Error: No active session. Start one with /dlc session start")
        return
    end

    config.lastActivity = time()

    -- 1. Snapshot Real Group
    if IsInGroup() then
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

    -- 2. Snapshot Simulated Players
    ---@type Simulation
    local Sim = DesolateLootcouncil:GetModule("Simulation")
    if Sim then
        local sims = Sim:GetRoster()
        for _, name in ipairs(sims) do
            self:RegisterAttendance(name, isEncounterKill)
        end
        if #sims > 0 then
            DesolateLootcouncil:DLC_Log("Included " .. #sims .. " simulated players in roster snapshot.")
        end
    end

    self:Printf("Roster Snapshot Taken.")
end

function Roster:PrintCurrentAttendees()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then
        self:Printf("No active session.")
        return
    end

    if next(config.currentAttendees) == nil then
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

    devDB.MainRoster[normalizedName] = { addedAt = time() } -- Store main with timestamp
    devDB.playerRoster.alts[normalizedName] = nil           -- Ensure not an alt
    self:UpdateScoreMap()
    DesolateLootcouncil:DLC_Log("Added Main: " .. DesolateLootcouncil:GetDisplayName(normalizedName))
    
    local Priority = DesolateLootcouncil:GetModule("Priority")
    if Priority and Priority.SyncMissingPlayers then
        Priority:SyncMissingPlayers()
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
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

    self:UpdateScoreMap()
    DesolateLootcouncil:DLC_Log("Linked Alt " .. DesolateLootcouncil:GetDisplayName(normalizedAlt) .. 
        " to " .. DesolateLootcouncil:GetDisplayName(normalizedMain))
        
    local Priority = DesolateLootcouncil:GetModule("Priority")
    if Priority and Priority.SyncMissingPlayers then
        Priority:SyncMissingPlayers()
    end
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
                StaticPopup_Show("DLC_ENABLE_AUTOPASS")
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
        if b.encounterID == encounterID then
            bossEntry = b
            break
        end
    end

    if not bossEntry then
        bossEntry = {
            encounterID = encounterID,
            name = encounterName,
            pulls = 0,
            killed = false,
        }
        table.insert(config.bossLogs, bossEntry)
    end

    bossEntry.pulls = bossEntry.pulls + 1
    config.lastActivity = time()
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
        if b.encounterID == encounterID then
            bossEntry = b
            break
        end
    end

    if not bossEntry then
        bossEntry = {
            encounterID = encounterID,
            name = encounterName,
            pulls = 1,
            killed = false,
        }
        table.insert(config.bossLogs, bossEntry)
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
end

function Roster:PLAYER_LOGIN()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if config.sessionActive then
        local delta = time() - (config.lastActivity or 0)
        if delta > 3600 then -- 1 hour stale
            DesolateLootcouncil:DLC_Log(string.format(
                "[DLC] Stale session detected (inactive for %.1f hours). Use '/dlc session stop' to end it.",
                delta / 3600), true)
        end
    end
    
    if not IsInRaid() then
        DesolateLootcouncil.sessionAutopassActive = false
        DesolateLootcouncil.sessionAutopassAnswered = false
        DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassActive = false
        DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassAnswered = false
    end
end

local gruResetTimer = nil

function Roster:CheckForNewRaidMembers()
    if not IsInGroup() or not DesolateLootcouncil:AmILootMaster() then return end
    
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config or not config.sessionActive then return end
    
    local addedAny = false
    local members = GetNumGroupMembers()
    for i = 1, members do
        local name = GetRaidRosterInfo(i)
        if name then
            if DesolateLootcouncil.activeAddonUsers and DesolateLootcouncil.activeAddonUsers[name] then
                local normalizedName = Ambiguate(name, "none")
                local score = DesolateLootcouncil:GetScoreName(normalizedName)
                if score and not self.scoreMap[score] then
                    self:AddMain(normalizedName)
                    DesolateLootcouncil:DLC_Log(string.format("New player |cFFFFFF00%s|r appended to priority lists. Please check if this is an Alt.", normalizedName), true)
                    addedAny = true
                end
            end
        end
    end
    if addedAny then
        local Priority = DesolateLootcouncil:GetModule("Priority")
        if Priority and Priority.SyncMissingPlayers then
            Priority:SyncMissingPlayers()
        end
    end
end

function Roster:DLC_VERSION_UPDATE()
    self:CheckForNewRaidMembers()
end

local function ResetAutopassSession()
    if IsInRaid() then return end
    if DesolateLootcouncil.sessionAutopassActive or DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassActive then
        DesolateLootcouncil.sessionAutopassActive  = false
        DesolateLootcouncil.sessionAutopassAnswered = false
        DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassActive = false
        DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassAnswered = false
        DesolateLootcouncil:DLC_Log("Raid group disbanded. Autopass session reset.", true)
    end
end

function Roster:GROUP_ROSTER_UPDATE()
    if gruResetTimer then gruResetTimer:Cancel() end
    gruResetTimer = C_Timer.NewTimer(0.5, function()
        gruResetTimer = nil
        if not IsInRaid() then
            -- Double check after 5 seconds to ensure this isn't a brief loading screen or portal blip
            C_Timer.After(5.0, ResetAutopassSession)
        else
            self:CheckForNewRaidMembers()
            -- Sync Autopass to newly joined members or after a group update (if LM)
            if DesolateLootcouncil:AmILootMaster() then
                local Comm = DesolateLootcouncil:GetModule("Comm")
                if Comm and DesolateLootcouncil.sessionAutopassActive ~= nil then
                    Comm:SendSyncAutopass(DesolateLootcouncil.sessionAutopassActive)
                end
            end
        end
    end)
end

--- Applies a received roster sync payload from the Loot Master.
--- Fully replaces MainRoster and alt links, then rebuilds the scoreMap.
---@param syncedRoster table  { mains = {[name]=data}, alts = {[alt]=main} }
function Roster:ReceiveRosterSync(syncedRoster)
    if not syncedRoster or type(syncedRoster) ~= "table" then return end
    local db = DesolateLootcouncil.db.profile

    -- Overwrite MainRoster
    db.MainRoster = {}
    for name, data in pairs(syncedRoster.mains or {}) do
        db.MainRoster[name] = { addedAt = data.addedAt or 0 }
    end

    -- Overwrite alt links
    if not db.playerRoster then db.playerRoster = { alts = {} } end
    db.playerRoster.alts = {}
    for alt, main in pairs(syncedRoster.alts or {}) do
        db.playerRoster.alts[alt] = main
    end

    -- Rebuild cache
    self:UpdateScoreMap()

    local mainCount = 0
    for _ in pairs(db.MainRoster) do mainCount = mainCount + 1 end
    DesolateLootcouncil:DLC_Log(string.format(
        "Roster Sync received from LM. %d mains applied.", mainCount), true)

    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end
