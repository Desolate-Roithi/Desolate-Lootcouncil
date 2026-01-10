---@class Session : AceModule, AceEvent-3.0, AceConsole-3.0
local Session = DesolateLootcouncil:NewModule("Session", "AceEvent-3.0", "AceConsole-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil", true) -- Optional if you have locales

function Session:OnEnable()
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("ENCOUNTER_END")
    self:RegisterEvent("PLAYER_LOGIN")

    self:RegisterChatCommand("dlc_session", "HandleSlashCommand")
end

function Session:HandleSlashCommand(input)
    local cmd, arg = self:GetArgs(input, 2)
    if cmd == "start" then
        self:StartRaidSession()
    elseif cmd == "stop" then
        -- Hook: Open Attendance UI instead of immediate stop, unless force is used?
        -- Actually, just open UI. The UI has the "End" button.
        ---@type UI
        local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
        if UI and UI.ShowAttendanceWindow then
            UI:ShowAttendanceWindow()
        else
            -- Fallback if UI fails
            self:StopRaidSession(true)
        end
    elseif cmd == "kill" then
        self:SnapshotRoster()
    elseif cmd == "attend" then
        self:PrintCurrentAttendees()
    else
        DesolateLootcouncil:DLC_Log("Session Commands: start, stop, kill, attend", true)
    end
end

function Session:Printf(msg, ...)
    DesolateLootcouncil:DLC_Log(string.format(msg, ...), true)
end

--- Starts a new tracking session
function Session:StartRaidSession()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if config.sessionActive then
        self:Printf("Session already active (Started: %s)", date("%c", config.currentSessionID))
        return
    end

    config.sessionActive = true
    config.currentSessionID = time()
    config.currentAttendees = {}
    config.lastActivity = time()

    self:Printf("Raid Session STARTED. ID: %d", config.currentSessionID)
end

--- Stops the current session and optionally saves history
---@param saveHistory boolean
function Session:StopRaidSession(saveHistory)
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
            date = date("%Y-%m-%d %H:%M:%S", config.currentSessionID),
            zone = GetRealZoneText() or "Unknown",
            attendees = {}
        }
        -- Deep copy attendees
        for name, _ in pairs(config.currentAttendees) do
            entry.attendees[name] = true
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
end

--- Register a player (or their Main) as present
---@param unitName string
function Session:RegisterAttendance(unitName)
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then return end

    local mainName = DesolateLootcouncil:GetMain(unitName) or unitName

    -- Verification: Does this main exist in our MainRoster?
    if DesolateLootcouncil.db.profile.MainRoster[mainName] then
        if not config.currentAttendees[mainName] then
            config.currentAttendees[mainName] = true
            -- DesolateLootcouncil:DLC_Log("Attendance registered: " .. mainName)
        end
    else
        DesolateLootcouncil:DLC_Log("Attendance Rejected: " .. unitName .. " (Not in Roster)", true)
    end
end

--- Captures current group members (or simulates if persistent group set)
function Session:SnapshotRoster()
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
                    self:RegisterAttendance(name)
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
            self:RegisterAttendance(name)
        end
        if #sims > 0 then
            DesolateLootcouncil:DLC_Log("Included " .. #sims .. " simulated players in roster snapshot.", true)
        end
    end

    self:Printf("Roster Snapshot Taken.")
end

function Session:PrintCurrentAttendees()
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
        self:Printf("[DLC] Attended: %s", name)
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLERS
---------------------------------------------------------------------------

function Session:ZONE_CHANGED_NEW_AREA()
    local name, type, difficulty, difficultyName, maxPlayers, playerDifficulty, isDynamicInstance, mapID, instanceGroupSize =
        GetInstanceInfo()
    local config = DesolateLootcouncil.db.profile.DecayConfig

    if type == "raid" and not config.sessionActive then
        self:Printf("Entered Raid Instance (%s). Starting Session...", name)
        self:StartRaidSession()
    elseif type ~= "raid" and config.sessionActive then
        -- We left the raid.
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Left Raid (%s). Session is still ACTIVE.", name))
    end
end

function Session:ENCOUNTER_END(event, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 then
        self:SnapshotRoster()
        self:Printf("Encounter '%s' Defeated. Attendance updated.", encounterName)
    end
end

function Session:PLAYER_LOGIN()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if config.sessionActive then
        local delta = time() - (config.lastActivity or 0)
        if delta > 3600 then -- 1 hour stale
            DesolateLootcouncil:DLC_Log(string.format("DEBUG: Stale Session Detected (Inactive for %.1f hours). Stop?",
                delta / 3600))
        end
    end
end
