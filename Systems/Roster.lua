---@class Roster : AceModule, AceEvent-3.0, AceConsole-3.0
local Roster = DesolateLootcouncil:NewModule("Roster", "AceEvent-3.0", "AceConsole-3.0")

---@class (partial) DLC_Ref_Roster
---@field db table
---@field GetModule fun(self: any, name: string): any
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field GetMain fun(self: any, name: string): string

---@type DLC_Ref_Roster
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Roster]]

function Roster:OnEnable()
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("ENCOUNTER_END")
    self:RegisterEvent("PLAYER_LOGIN")

    DesolateLootcouncil:DLC_Log("Systems/Roster Loaded")
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

--- Starts a new tracking session
function Roster:StartRaidSession()
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
function Roster:RegisterAttendance(unitName)
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config.sessionActive then return end

    local mainName = self:GetMain(unitName) or unitName

    -- Verification: Does this main exist in our MainRoster?
    if DesolateLootcouncil.db.profile.MainRoster[mainName] then
        if not config.currentAttendees[mainName] then
            config.currentAttendees[mainName] = true
        end
    else
        DesolateLootcouncil:DLC_Log("Attendance Rejected: " .. unitName .. " (Not in Roster)", true)
    end
end

--- Captures current group members (or simulates if persistent group set)
function Roster:SnapshotRoster()
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
        self:Printf("[DLC] Attended: %s", name)
    end
end

---------------------------------------------------------------------------
-- ROSTER MANAGEMENT (Migrated from Core)
---------------------------------------------------------------------------

function Roster:AddMain(name)
    if not DesolateLootcouncil.db then return end
    if not name or name == "" then return end

    local devDB = DesolateLootcouncil.db.profile
    if not devDB or not devDB.MainRoster or not devDB.playerRoster then return end

    devDB.MainRoster[name] = { addedAt = time() } -- Store main with timestamp
    devDB.playerRoster.alts[name] = nil           -- Ensure not an alt
    DesolateLootcouncil:DLC_Log("Added Main: " .. name)
end

function Roster:AddAlt(altName, mainName)
    if not DesolateLootcouncil.db then return end
    if not altName or not mainName then return end

    if altName == mainName then
        DesolateLootcouncil:DLC_Log("Error: Cannot add a player as an alt to themselves.")
        return
    end

    local profile = DesolateLootcouncil.db.profile
    if not profile or not profile.playerRoster or not profile.playerRoster.alts then return end
    local roster = profile.playerRoster

    -- 1. Check if the 'new alt' was previously a Main with their own alts
    -- We need to re-parent those alts to the NEW main.
    for existingAlt, existingMain in pairs(roster.alts) do
        if existingMain == altName then
            roster.alts[existingAlt] = mainName
            DesolateLootcouncil:DLC_Log("Re-linked inherited alt: " .. existingAlt .. " -> " .. mainName)
        end
    end
    -- 2. Perform the standard assignment
    roster.alts[altName] = mainName
    -- 3. Remove from Mains list if present
    if profile.MainRoster and profile.MainRoster[altName] then
        profile.MainRoster[altName] = nil
        DesolateLootcouncil:DLC_Log("Converted Main to Alt: " .. altName)
    end

    DesolateLootcouncil:DLC_Log("Linked Alt " .. altName .. " to " .. mainName)
end

function Roster:RemovePlayer(name)
    if not DesolateLootcouncil.db then return end
    if not name then return end

    local profile = DesolateLootcouncil.db.profile

    -- Try delete as Main
    if profile.MainRoster and profile.MainRoster[name] then
        profile.MainRoster[name] = nil
        -- Unlink alts
        if profile.playerRoster and profile.playerRoster.alts then
            for alt, main in pairs(profile.playerRoster.alts) do
                if main == name then
                    profile.playerRoster.alts[alt] = nil
                    DesolateLootcouncil:DLC_Log("Unlinked Alt: " .. alt)
                end
            end
        end
        DesolateLootcouncil:DLC_Log("Removed Main: " .. name)
        return
    end

    -- Try delete as Alt
    if profile.playerRoster.alts[name] then
        profile.playerRoster.alts[name] = nil
        DesolateLootcouncil:DLC_Log("Removed Alt: " .. name)
    end
end

function Roster:GetMain(name)
    if not DesolateLootcouncil.db or not name then return name end
    local profile = DesolateLootcouncil.db.profile
    local alts = profile.playerRoster and profile.playerRoster.alts
    local mains = profile.MainRoster
    local realm = GetRealmName():gsub("%s+", "") -- Remove spaces for safety
    local full = string.find(name, "-") and name or (name .. "-" .. realm)
    local short = Ambiguate(name, "none")

    -- 1. Try to find if 'name' is an Alt
    local resolvedMain = nil
    if alts then
        resolvedMain = alts[name] or alts[full] or alts[short]
    end

    -- If found in alts, that's our candidate. Otherwise, input name is the candidate.
    local candidate = resolvedMain or name

    -- 2. Validate 'candidate' against MainRoster to get the Canonical Key
    if mains then
        if mains[candidate] then return candidate end

        -- Try variations for the candidate
        local cFull = string.find(candidate, "-") and candidate or (candidate .. "-" .. realm)
        local cShort = Ambiguate(candidate, "none")

        if mains[cFull] then return cFull end
        if mains[cShort] then return cShort end
    end

    return candidate
end

---------------------------------------------------------------------------
-- EVENT HANDLERS
---------------------------------------------------------------------------

function Roster:ZONE_CHANGED_NEW_AREA()
    local name, type = GetInstanceInfo()
    local config = DesolateLootcouncil.db.profile.DecayConfig

    if type == "raid" and not config.sessionActive then
        self:Printf("Entered Raid Instance (%s). Starting Session...", name)
        self:StartRaidSession()
    elseif type ~= "raid" and config.sessionActive then
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Left Raid (%s). Session is still ACTIVE.", name))
    end
end

function Roster:ENCOUNTER_END(event, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 then
        self:SnapshotRoster()
        self:Printf("Encounter '%s' Defeated. Attendance updated.", encounterName)
    end
end

function Roster:PLAYER_LOGIN()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if config.sessionActive then
        local delta = time() - (config.lastActivity or 0)
        if delta > 3600 then -- 1 hour stale
            DesolateLootcouncil:DLC_Log(string.format("DEBUG: Stale Session Detected (Inactive for %.1f hours). Stop?",
                delta / 3600))
        end
    end
end
