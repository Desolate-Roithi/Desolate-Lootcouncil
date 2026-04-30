local _, AT = ...
if AT.abortLoad then return end

---@class Roster : AceModule, AceEvent-3.0, AceConsole-3.0
local Roster = DesolateLootcouncil:NewModule("Roster", "AceEvent-3.0", "AceConsole-3.0")

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
    self:RegisterEvent("ENCOUNTER_END")
    self:RegisterEvent("PLAYER_LOGIN")

    self.scoreMap = {} -- Transient cache for O(1) Smart Recognition
    self:UpdateScoreMap()

    -- Define autopass popup once at module load to avoid repeated table allocation.
    StaticPopupDialogs["DLC_ENABLE_AUTOPASS"] = {
        text = "Do you want to enable Autopass for this raid session?\n(Raid members will automatically pass on managed loot)",
        button1 = "Enable",
        button2 = "No",
        OnAccept = function()
            local Comm = DesolateLootcouncil:GetModule("Comm")
            if Comm and Comm.SendSyncAutopass then Comm:SendSyncAutopass(true) end
        end,
        OnCancel = function()
            local Comm = DesolateLootcouncil:GetModule("Comm")
            if Comm and Comm.SendSyncAutopass then Comm:SendSyncAutopass(false) end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    DesolateLootcouncil:DLC_Log("Systems/Roster Loaded")
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

    config.sessionActive = true
    config.currentSessionID = time()
    config.currentAttendees = {}
    config.lastActivity = time()

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
            DesolateLootcouncil:DLC_Log(string.format("Attendance Registered: %s (Main: %s)", 
                DesolateLootcouncil:GetDisplayName(unitName), 
                DesolateLootcouncil:GetDisplayName(mainName)))
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
    if not devDB or not devDB.MainRoster or not devDB.playerRoster then return end

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
    if not profile or not profile.playerRoster or not profile.playerRoster.alts then return end
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
end

function Roster:RemovePlayer(name)
    if not DesolateLootcouncil.db then return end
    if not name then return end

    local profile = DesolateLootcouncil.db.profile

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
        DesolateLootcouncil:DLC_Log("Removed Main: " .. DesolateLootcouncil:GetDisplayName(normalizedName))
        return
    end

    -- Try delete as Alt
    if profile.playerRoster.alts[normalizedName] then
        profile.playerRoster.alts[normalizedName] = nil
        self:UpdateScoreMap()
        DesolateLootcouncil:DLC_Log("Removed Alt: " .. DesolateLootcouncil:GetDisplayName(normalizedName))
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

    if instanceType == "raid" then
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
            if DesolateLootcouncil:AmILootMaster() and not DesolateLootcouncil.sessionAutopassActive then
                StaticPopup_Show("DLC_ENABLE_AUTOPASS")
            end
        end
        -- Auto-ping the LM to sync Autopass and IM configs if joining late
        DesolateLootcouncil:SendVersionCheck()
    elseif instanceType ~= "raid" and config.sessionActive then
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Left Raid (%s). Session is still ACTIVE.", name))
        -- Cleanup Autopass on exit to prevent LFR bleed
        DesolateLootcouncil.sessionAutopassActive = false
    end
end

function Roster:ENCOUNTER_END(event, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 then
        local _, instanceType = GetInstanceInfo()
        if instanceType == "raid" then
            self:SnapshotRoster()
            self:Printf("Encounter '%s' Defeated. Attendance updated.", encounterName)
        end
    end
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
