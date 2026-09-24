local _, AT = ...
if AT.abortLoad then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local function SafeGetUnitClass(unit)
    return DesolateLootcouncil:SafeGetUnitClass(unit)
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
        if DesolateLootcouncil.db and DesolateLootcouncil.db.profile then
            if DesolateLootcouncil.db.profile.DecayConfig then
                DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassAnswered = true
            end
            DesolateLootcouncil.db.profile.enableAutoLoot = true
        end
        local Sync = DesolateLootcouncil:GetModule("Sync")
        if Sync and Sync.SendSyncAutopass then Sync:SendSyncAutopass(true) end
    end,
    OnCancel = function()
        DesolateLootcouncil.sessionAutopassAnswered = true
        if DesolateLootcouncil.db and DesolateLootcouncil.db.profile then
            if DesolateLootcouncil.db.profile.DecayConfig then
                DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassAnswered = true
            end
            DesolateLootcouncil.db.profile.enableAutoLoot = false
        end
        local Sync = DesolateLootcouncil:GetModule("Sync")
        if Sync and Sync.SendSyncAutopass then Sync:SendSyncAutopass(false) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["DLC_ACTIVE_SESSION_PROMPT"] = {
    text = "%s",
    button1 = L["Resume Session"],
    button2 = L["End Session"],
    OnAccept = function()
        DesolateLootcouncil:Print(L["Resuming active raid session."])
        if DesolateLootcouncil.sessionAutopassActive then
            local Sync = DesolateLootcouncil:GetModule("Sync")
            if Sync and Sync.SendSyncAutopass then
                Sync:SendSyncAutopass(true)
            end
        else
            DesolateLootcouncil:PromptAutopass(nil, true)
        end
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
        local API = DesolateLootcouncil.API
        if API then
            API:StopRaidSession(true)
            API:StartRaidSession()
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
    button1 = L["Save & Close"],
    button2 = L["Keep Session Open"],
    OnAccept = function()
        local RosterMod = DesolateLootcouncil:GetModule("Roster", true)
        if RosterMod then RosterMod.disbandPopupPending = false end
        local config = DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.DecayConfig
        if config and config.enabled then
            local Attendance = DesolateLootcouncil:GetModule("UI_Attendance", true)
            if Attendance and Attendance.ShowAttendanceWindow then
                Attendance:ShowAttendanceWindow()
                return
            end
        end
        local API = DesolateLootcouncil.API
        if API and API.StopRaidSession then
            API:StopRaidSession(true)
        end
    end,
    OnCancel = function()
        local RosterMod = DesolateLootcouncil:GetModule("Roster", true)
        if RosterMod then RosterMod.disbandPopupPending = false end
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
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterMessage("DLC_VERSION_UPDATE")

    self.scoreMap = {} -- Transient cache for O(1) Smart Recognition
    self:UpdateScoreMap()

    DesolateLootcouncil:DLC_Log("Systems/Roster Loaded")
end

function Roster:OnDisable()
    self:UnregisterEvent("PLAYER_LOGIN")
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")
    self:UnregisterMessage("DLC_VERSION_UPDATE")
end

function Roster:SanitizeMainsAndAlts()
    if not DesolateLootcouncil.db then return end
    local profile = DesolateLootcouncil.db.profile
    if not profile or not profile.MainRoster then return end

    -- 1. Deduplicate MainRoster keys mapping to the same player score
    local seenScores = {}
    for mainKey, data in pairs(profile.MainRoster) do
        local score = DesolateLootcouncil:GetScoreName(mainKey)
        if score then
            if seenScores[score] then
                local existingKey = seenScores[score]
                local existingHasDash = string.find(existingKey, "-") ~= nil
                local currentHasDash = string.find(mainKey, "-") ~= nil
                if currentHasDash and not existingHasDash then
                    if type(profile.MainRoster[existingKey]) == "table" and profile.MainRoster[existingKey].isOfficer then
                        if type(data) == "table" then data.isOfficer = true end
                    end
                    profile.MainRoster[existingKey] = nil
                    seenScores[score] = mainKey
                else
                    if type(data) == "table" and data.isOfficer then
                        if type(profile.MainRoster[existingKey]) == "table" then
                            profile.MainRoster[existingKey].isOfficer = true
                        end
                    end
                    profile.MainRoster[mainKey] = nil
                end
            else
                seenScores[score] = mainKey
            end
        end
    end

    -- 2. Validate Alts
    if profile.playerRoster and profile.playerRoster.alts then
        local safeLower = (type(strlower) == "function" and strlower) or string.lower
        for altName, mainName in pairs(profile.playerRoster.alts) do
            local altScore = DesolateLootcouncil:GetScoreName(altName)
            local mainScore = DesolateLootcouncil:GetScoreName(mainName)
            local isSelf = (safeLower(altName) == safeLower(mainName)) or (altScore and mainScore and altScore == mainScore)
            if isSelf then
                profile.playerRoster.alts[altName] = nil
                if not profile.MainRoster[altName] then
                    profile.MainRoster[altName] = { isOfficer = false, addedAt = GetServerTime() }
                end
                DesolateLootcouncil:DLC_Log(string.format("Sanitized roster: Removed self-referencing alt '%s' and restored as Main.", altName))
            else
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
        DesolateLootcouncil.API:StartRaidSession()
    elseif cmd == "stop" then
        ---@type UI
        local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
        if UI and UI.ShowAttendanceWindow then
            UI:ShowAttendanceWindow()
        else
            DesolateLootcouncil.API:StopRaidSession(true)
        end
    elseif cmd == "kill" then
        local Att = DesolateLootcouncil:GetModule("Attendance", true)
        if Att and Att.SnapshotRoster then Att:SnapshotRoster(true) end
    elseif cmd == "attend" then
        local Att = DesolateLootcouncil:GetModule("Attendance", true)
        if Att and Att.PrintCurrentAttendees then Att:PrintCurrentAttendees() end
    else
        DesolateLootcouncil:DLC_Log("Roster Commands: start, stop, kill, attend", true)
    end
end

function Roster:Printf(msg, ...)
    DesolateLootcouncil:DLC_Log(string.format(msg, ...), true)
end

---------------------------------------------------------------------------
--- Transmits the full roster to all officers immediately upon any mutation.
function Roster:SyncRosterToOfficers()
    if not DesolateLootcouncil:AmILootMaster() then return end
    if not DesolateLootcouncil:IsInRaidOrTest() then return end
    local Sync = DesolateLootcouncil:GetModule("Sync", true)
    if Sync and Sync.ShareDataWithOfficers then
        Sync:ShareDataWithOfficers("ROSTER")
    end
    local Session = DesolateLootcouncil:GetModule("Session", true)
    if Session and Session.SendDLCHeartbeat then
        Session:SendDLCHeartbeat()
    end
end

function Roster:AddMain(name)
    if not DesolateLootcouncil.db then return end
    if not name or name == "" then return end

    local devDB = DesolateLootcouncil.db.profile
    if not devDB then return end
    if not devDB.MainRoster then devDB.MainRoster = {} end
    if not devDB.playerRoster then devDB.playerRoster = { alts = {}, decay = {} } end
    if not devDB.playerRoster.alts then devDB.playerRoster.alts = {} end

    -- Store with full Name-Realm key; SmartCompare handles realm-agnostic lookups
    local normalizedName = name

    -- Duplicate Check
    for existingName in pairs(devDB.MainRoster) do
        if DesolateLootcouncil:SmartCompare(existingName, normalizedName) then
            DesolateLootcouncil:DLC_Log("Error: " .. DesolateLootcouncil:GetDisplayName(normalizedName) .. 
                " already exists in Roster as " .. DesolateLootcouncil:GetDisplayName(existingName), true)
            return false
        end
    end

    -- Clear from alts if previously registered as an alt
    if devDB.playerRoster and devDB.playerRoster.alts then
        for altKey in pairs(devDB.playerRoster.alts) do
            if DesolateLootcouncil:SmartCompare(altKey, normalizedName) then
                devDB.playerRoster.alts[altKey] = nil
            end
        end
    end

    devDB.MainRoster[normalizedName] = { addedAt = time(), isOfficer = false } -- Store main with timestamp
    devDB.rosterTimestamp = GetServerTime()
    self:UpdateScoreMap()
    DesolateLootcouncil:DLC_Log("Added Main: " .. DesolateLootcouncil:GetDisplayName(normalizedName))

    DesolateLootcouncil.API:LogAudit("ROSTER_ADD_MAIN", nil, normalizedName, nil, "Added main character")
    
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    self:SyncRosterToOfficers()
    return true
end

function Roster:IsMain(name)
    if not name or name == "" then return false end
    local devDB = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not devDB or not devDB.MainRoster then return false end
    for rosterName in pairs(devDB.MainRoster) do
        if DesolateLootcouncil:SmartCompare(rosterName, name) then
            return true
        end
    end
    return false
end

function Roster:IsAlt(name)
    if not name or name == "" then return false end
    local devDB = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not devDB or not devDB.playerRoster or not devDB.playerRoster.alts then return false end
    for altName in pairs(devDB.playerRoster.alts) do
        if DesolateLootcouncil:SmartCompare(altName, name) then
            return true
        end
    end
    return false
end

function Roster:SetOfficer(name, flag)
    if not DesolateLootcouncil.db then return end
    if not name or name == "" then return end
    
    local devDB = DesolateLootcouncil.db.profile
    if not devDB then return end
    if not devDB.MainRoster then devDB.MainRoster = {} end
    
    -- Resolve alt to Main; store with full Name-Realm key
    local targetMain = self:GetMain(name) or name
    local normalizedName = targetMain

    for existingName, data in pairs(devDB.MainRoster) do
        if DesolateLootcouncil:SmartCompare(existingName, normalizedName) then
            data.isOfficer = flag == true
            devDB.rosterTimestamp = GetServerTime()
            DesolateLootcouncil.API:LogAudit("OFFICER_FLAG", nil, existingName, nil, flag and "Promoted to Officer" or "Demoted from Officer")
            
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
            self:SyncRosterToOfficers()
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
            DesolateLootcouncil.API:LogAudit("OFFICER_FLAG", nil, normalizedName, nil, "Added new main and promoted to Officer")
            
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
            self:SyncRosterToOfficers()
        end
    end
end

function Roster:AddAlt(altName, mainName)
    if not DesolateLootcouncil.db then return end
    if not altName or not mainName then return end

    -- Store with full Name-Realm keys
    local normalizedAlt = altName
    local normalizedMain = mainName

    -- Use exact key comparison (case-insensitive) — SmartCompare is intentionally
    -- NOT used here because it folds realm-less names onto the local realm, which
    -- would incorrectly block linking e.g. "Hopfy" (no realm) to "Hopfy-Silvermoon".
    local safeLower = (type(strlower) == "function" and strlower) or string.lower
    if safeLower(normalizedAlt) == safeLower(normalizedMain) then
        DesolateLootcouncil:DLC_Log("Error: Cannot add a player as an alt to themselves.")
        return false
    end

    local profile = DesolateLootcouncil.db.profile
    if not profile then return false end
    if not profile.MainRoster then profile.MainRoster = {} end
    if not profile.playerRoster then profile.playerRoster = { alts = {}, decay = {} } end
    if not profile.playerRoster.alts then profile.playerRoster.alts = {} end
    local roster = profile.playerRoster

    -- 1. Check if the 'new alt' was previously a Main with their own alts
    -- We need to re-parent those alts to the NEW main.
    local altScore = DesolateLootcouncil:GetScoreName(normalizedAlt)
    for existingAlt, existingMain in pairs(roster.alts) do
        local existingMainScore = DesolateLootcouncil:GetScoreName(existingMain)
        if safeLower(existingMain) == safeLower(normalizedAlt) or (altScore and existingMainScore and altScore == existingMainScore) then
            roster.alts[existingAlt] = normalizedMain
            DesolateLootcouncil:DLC_Log("Re-linked inherited alt: " .. 
                DesolateLootcouncil:GetDisplayName(existingAlt) .. " -> " .. 
                DesolateLootcouncil:GetDisplayName(normalizedMain))
        end
    end
    -- 2. Perform the standard assignment
    roster.alts[normalizedAlt] = normalizedMain
    -- 3. Remove from Mains list if present (exact or score-aware match)
    if profile.MainRoster then
        for mainKey in pairs(profile.MainRoster) do
            local mainKeyScore = DesolateLootcouncil:GetScoreName(mainKey)
            if safeLower(mainKey) == safeLower(normalizedAlt) or (altScore and mainKeyScore and altScore == mainKeyScore) then
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

    DesolateLootcouncil.API:LogAudit("ALT_LINK", nil, normalizedAlt, nil, string.format("Linked to Main %s", normalizedMain))
        
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    self:SyncRosterToOfficers()
    return true
end

function Roster:RemovePlayer(name)
    if not DesolateLootcouncil.db then return end
    if not name then return end

    local profile = DesolateLootcouncil.db.profile
    if not profile then return end
    if not profile.MainRoster then profile.MainRoster = {} end
    if not profile.playerRoster then profile.playerRoster = { alts = {}, decay = {} } end
    if not profile.playerRoster.alts then profile.playerRoster.alts = {} end

    -- Use raw Name-Realm for lookup; SmartCompare handles matching
    local normalizedName = name

    -- Try delete as Main
    if profile.MainRoster and profile.MainRoster[normalizedName] then
        profile.MainRoster[normalizedName] = nil
        profile.rosterTimestamp = GetServerTime()
        -- Unlink alts
        if profile.playerRoster and profile.playerRoster.alts then
            local normScore = DesolateLootcouncil:GetScoreName(normalizedName)
            local safeLower = (type(strlower) == "function" and strlower) or string.lower
            for alt, main in pairs(profile.playerRoster.alts) do
                local mainScore = DesolateLootcouncil:GetScoreName(main)
                if safeLower(main) == safeLower(normalizedName) or (normScore and mainScore and mainScore == normScore) then
                    profile.playerRoster.alts[alt] = nil
                    DesolateLootcouncil:DLC_Log("Unlinked Alt: " .. DesolateLootcouncil:GetDisplayName(alt))
                end
            end
        end
        self:UpdateScoreMap()
        DesolateLootcouncil:DLC_Log("Removed Main: " .. DesolateLootcouncil:GetDisplayName(normalizedName))
        DesolateLootcouncil.API:LogAudit("ROSTER_REMOVE", nil, normalizedName, nil, "Removed main character")
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
        self:SyncRosterToOfficers()
        return
    end

    -- Try delete as Alt
    if profile.playerRoster.alts[normalizedName] then
        profile.playerRoster.alts[normalizedName] = nil
        profile.rosterTimestamp = GetServerTime()
        self:UpdateScoreMap()
        DesolateLootcouncil:DLC_Log("Removed Alt: " .. DesolateLootcouncil:GetDisplayName(normalizedName))
        DesolateLootcouncil.API:LogAudit("ALT_UNLINK", nil, normalizedName, nil, "Removed alt character")
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
        self:SyncRosterToOfficers()
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
    local safeLower = (type(strlower) == "function" and strlower) or string.lower
    local nameScore = score or DesolateLootcouncil:GetScoreName(name)
    if profile.playerRoster and profile.playerRoster.alts then
        for altName, mainName in pairs(profile.playerRoster.alts) do
            local altScore = DesolateLootcouncil:GetScoreName(altName)
            if safeLower(altName) == safeLower(name) or (nameScore and altScore and nameScore == altScore) then
                return mainName
            end
        end
        for altName, mainName in pairs(profile.playerRoster.alts) do
            if DesolateLootcouncil:SmartCompare(altName, name) then
                return mainName
            end
        end
    end

    if profile.MainRoster then
        for mainName, _ in pairs(profile.MainRoster) do
            local mScore = DesolateLootcouncil:GetScoreName(mainName)
            if safeLower(mainName) == safeLower(name) or (nameScore and mScore and nameScore == mScore) then
                return mainName
            end
        end
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

function Roster:RecordUnassignedPlayer(name, source, class)
    if not DesolateLootcouncil.db or not name or name == "" then return end
    local profile = DesolateLootcouncil.db.profile
    if not profile then return end

    local normalizedName = name
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
            class = class or SafeGetUnitClass(name) or "WARRIOR"
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
        local norm = name
        for k in pairs(profile.unassignedPlayers) do
            if DesolateLootcouncil:SmartCompare(k, norm) then
                profile.unassignedPlayers[k] = nil
                profile.unassignedTimestamp = GetServerTime()
                break
            end
        end
    end
    local ok = self:AddMain(name)
    self:SendMessage("DLC_UNASSIGNED_PLAYERS_UPDATED")

    local Session = DesolateLootcouncil:GetModule("Session", true)
    if Session and Session.SendDLCHeartbeat and DesolateLootcouncil:AmILootMaster() then
        Session:SendDLCHeartbeat()
    end
    return ok
end

function Roster:AssignAsAlt(altName, mainName)
    if not DesolateLootcouncil.db or not altName or not mainName then return false end
    local profile = DesolateLootcouncil.db.profile
    if profile and profile.unassignedPlayers then
        local norm = altName
        for k in pairs(profile.unassignedPlayers) do
            if DesolateLootcouncil:SmartCompare(k, norm) then
                profile.unassignedPlayers[k] = nil
                profile.unassignedTimestamp = GetServerTime()
                break
            end
        end
    end
    local ok = self:AddAlt(altName, mainName)
    self:SendMessage("DLC_UNASSIGNED_PLAYERS_UPDATED")

    local Session = DesolateLootcouncil:GetModule("Session", true)
    if Session and Session.SendDLCHeartbeat and DesolateLootcouncil:AmILootMaster() then
        Session:SendDLCHeartbeat()
    end
    return ok
end

function Roster:DismissUnassignedPlayer(name)
    if not DesolateLootcouncil.db or not name then return end
    local profile = DesolateLootcouncil.db.profile
    if profile and profile.unassignedPlayers then
        local norm = name
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
    self:SyncRosterToOfficers()
end

---------------------------------------------------------------------------
-- EVENT HANDLERS
---------------------------------------------------------------------------

function Roster:ZONE_CHANGED_NEW_AREA()
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.OnZoneChanged then
        Att:OnZoneChanged()
    end
end

function Roster:StartRaidSession(forced)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.StartRaidSession then
        return Att:StartRaidSession(forced)
    end
end

function Roster:StopRaidSession(applyDecay)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.StopRaidSession then
        return Att:StopRaidSession(applyDecay)
    end
end

function Roster:SnapshotRoster(isManual)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.SnapshotRoster then
        return Att:SnapshotRoster(isManual)
    end
end

function Roster:GetUnitClass(unit)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.GetUnitClass then
        return Att:GetUnitClass(unit)
    end
    return DesolateLootcouncil:SafeGetUnitClass(unit)
end
Roster.DefaultGetUnitClass = Roster.GetUnitClass

function Roster:RegisterAttendance(unit, isRaidGroup)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.RegisterAttendance then
        return Att:RegisterAttendance(unit, isRaidGroup)
    end
end

function Roster:DeleteAttendanceHistoryEntry(index)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.DeleteAttendanceHistoryEntry then
        return Att:DeleteAttendanceHistoryEntry(index)
    end
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.AttendanceHistory or not db.AttendanceHistory[index] then return end
    table.remove(db.AttendanceHistory, index)
    if DesolateLootcouncil.API and DesolateLootcouncil.API.MarkHistoryDirty then
        DesolateLootcouncil.API:MarkHistoryDirty()
    end
end

function Roster:ENCOUNTER_START(...)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.OnEncounterStart then
        return Att:OnEncounterStart(...)
    end
end

function Roster:ENCOUNTER_END(...)
    local Att = DesolateLootcouncil:GetModule("Attendance", true)
    if Att and Att.OnEncounterEnd then
        return Att:OnEncounterEnd(...)
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
local disbandCheckTimer = nil  -- Bug 6: tracked so rapid GRU only queues ONE 3s disband check

function Roster:CheckForNewRaidMembers()
    if DesolateLootcouncil:IsLFR() then return end
    if not IsInRaid() or not DesolateLootcouncil:AmILootMaster() then return end
    
    local profile = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not profile then return end

    local members = GetNumGroupMembers()
    for i = 1, members do
        local name = GetRaidRosterInfo(i)
        if name then
            local normalizedName = name
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

--- Returns true if bossLogs contains at least one confirmed kill.
local function HasBossKill(bossLogs)
    if not bossLogs then return false end
    for _, b in ipairs(bossLogs) do
        if b.killed == true then return true end
    end
    return false
end

local function HandleRaidDisband(forceDisband)
    if IsInRaid() and not forceDisband then return end
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if not config then return end

    -- Bug 6: If popup is already pending, do not show it again.
    local RosterMod = DesolateLootcouncil:GetModule("Roster", true)
    if RosterMod and RosterMod.disbandPopupPending then
        ResetAutopassSession()
        return
    end

    if config.sessionActive then
        local myName = UnitName("player")
        local isLM = config.currentSessionLM and config.currentSessionLM ~= "" and DesolateLootcouncil:SmartCompare(config.currentSessionLM, myName)

        -- If the player is a known non-officer in the guild roster, they cannot be the session LM
        if isLM and DesolateLootcouncil.API:IsKnownRosterRaider(myName) then
            isLM = false
        end

        if isLM then
            -- 1. Assigned LM: Only prompt if at least one boss was killed this session
            if not HasBossKill(config.bossLogs) then
                DesolateLootcouncil:DLC_Log("HandleRaidDisband: No boss kills — auto-closing session without prompt.")
                DesolateLootcouncil.API:StopRaidSession(false)
            else
                -- Bug 6: Set pending flag before showing popup so rapid GRU cannot stack
                if RosterMod then RosterMod.disbandPopupPending = true end
                StaticPopup_Show("DLC_DISBAND_CLOSE_SESSION")
            end
        else
            -- 2. Local player is NOT the assigned LM (or no LM assigned)
            if not config.currentSessionLM or config.currentSessionLM == "" then
                -- No LM assigned: Session was never actively used for loot distribution
                DesolateLootcouncil:DLC_Log("HandleRaidDisband: No LM assigned to session — auto-closing without prompt.")
                DesolateLootcouncil.API:StopRaidSession(false)
            elseif DesolateLootcouncil:AmIOfficerOrLM() and not DesolateLootcouncil.API:IsKnownRosterRaider(myName) then
                -- Officers who had synced session from LM:
                -- Autoclose saving history with decay missing so it can be manually applied or updated by LM
                DesolateLootcouncil:DLC_Log("HandleRaidDisband: Officer synced session — auto-closing with decay missing.")
                DesolateLootcouncil.API:StopRaidSession(true, true)
            else
                -- Raiders: Silently purge session state, zero popup
                DesolateLootcouncil.API:CleanRaiderStaleSession()
            end
        end
    end
    ResetAutopassSession()
end
Roster.HandleRaidDisband = HandleRaidDisband

local function BroadcastAutopassState()
    if not DesolateLootcouncil:AmILootMaster() then return end
    local Sync = DesolateLootcouncil:GetModule("Sync")
    if Sync and DesolateLootcouncil.sessionAutopassActive ~= nil then
        Sync:SendSyncAutopass(DesolateLootcouncil.sessionAutopassActive)
    end
end

function Roster:GROUP_ROSTER_UPDATE()
    if DesolateLootcouncil:IsLFR() then return end
    if gruResetTimer then gruResetTimer:Cancel() end
    gruResetTimer = C_Timer.NewTimer(0.5, function()
        gruResetTimer = nil
        if not IsInRaid() then
            -- Bug 6: Cancel any previously queued disband check before scheduling a new one.
            -- This ensures only ONE HandleRaidDisband fires per disband event.
            if disbandCheckTimer then
                disbandCheckTimer:Cancel()
                disbandCheckTimer = nil
            end
            disbandCheckTimer = C_Timer.NewTimer(3.0, function()
                disbandCheckTimer = nil
                HandleRaidDisband()
            end)
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

    -- Clean unassigned players who are now in MainRoster or alts
    if db.unassignedPlayers then
        local unassignedChanged = false
        for unassignedName in pairs(db.unassignedPlayers) do
            local matched = false
            if db.MainRoster then
                for mainName in pairs(db.MainRoster) do
                    if DesolateLootcouncil:SmartCompare(mainName, unassignedName) then
                        matched = true
                        break
                    end
                end
            end
            if not matched and db.playerRoster and db.playerRoster.alts then
                for altName in pairs(db.playerRoster.alts) do
                    if DesolateLootcouncil:SmartCompare(altName, unassignedName) then
                        matched = true
                        break
                    end
                end
            end
            if matched then
                db.unassignedPlayers[unassignedName] = nil
                unassignedChanged = true
            end
        end
        if unassignedChanged then
            self:SendMessage("DLC_UNASSIGNED_PLAYERS_UPDATED")
        end
    end

    self:SendMessage("DLC_ROSTER_UPDATED")
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
    if not db.AttendanceHistory or not db.AttendanceHistory[1] then
        DesolateLootcouncil:Print(L["No attendance history found."])
        return
    end
    local entry = db.AttendanceHistory[1]
    if entry.decayApplied ~= nil and not skip then
        DesolateLootcouncil:Print(L["Decay has already been applied for the last session."])
        return
    end
    if skip then
        entry.decayApplied = -1
        DesolateLootcouncil:Print(L["Decay for last session skipped."])
        return
    end

    local absent = {}
    local roster = db.MainRoster or {}
    local attendedSet = {}
    if entry.attendees then
        for attName in pairs(entry.attendees) do
            attendedSet[attName] = true
            local s = DesolateLootcouncil:GetScoreName(attName)
            if s then attendedSet[s] = true end
            local short = DesolateLootcouncil:GetDisplayName(attName)
            if short then attendedSet[string.lower(short)] = true end
        end
    end
    for name in pairs(roster) do
        local s = DesolateLootcouncil:GetScoreName(name)
        local short = DesolateLootcouncil:GetDisplayName(name)
        local attended = attendedSet[name] or (s and attendedSet[s]) or (short and attendedSet[string.lower(short)])
        if not attended then
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

local function FormatDisplayName(fullName)
    if DesolateLootcouncil and DesolateLootcouncil.Ambiguate then
        return DesolateLootcouncil:Ambiguate(fullName)
    end
    if not fullName or fullName == "" then return "" end
    local charName, realm = tostring(fullName):match("^([^-]+)%-(.+)$")
    if not charName or not realm then return tostring(fullName) end
    local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    local normRealm = realm:gsub("%s+", ""):lower()
    local normMyRealm = myRealm:gsub("%s+", ""):lower()
    if normMyRealm ~= "" and normRealm == normMyRealm then
        return charName
    end
    return tostring(fullName)
end

function Roster:GetRosterText()
    local db = DesolateLootcouncil.db.profile
    if not db.MainRoster then return "No Roster Found." end
    local text = ""
    local sortedMains = {}
    for name in pairs(db.MainRoster) do table.insert(sortedMains, name) end
    table.sort(sortedMains)
    for _, main in ipairs(sortedMains) do
        local displayMain = FormatDisplayName(main)
        local mainText = displayMain
        local data = db.MainRoster[main]
        if data and data.isOfficer then mainText = mainText .. " (Officer)" end
        text = text .. mainText
        local alts = {}
        if db.playerRoster and db.playerRoster.alts then
            for alt, parent in pairs(db.playerRoster.alts) do
                if parent == main then
                    local displayAlt = FormatDisplayName(alt)
                    table.insert(alts, displayAlt)
                end
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
            local displayName = FormatDisplayName(name)
            list[name] = (data and data.isOfficer) and (displayName .. " (Officer)") or displayName
        end
    end
    return list
end

function Roster:GetAllPlayersList()
    local list = self:GetMainRosterList()
    local db = DesolateLootcouncil.db.profile
    if db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            local displayAlt = FormatDisplayName(alt)
            local displayMain = FormatDisplayName(main)
            list[alt] = displayAlt .. " (Alt of " .. displayMain .. ")"
        end
    end
    return list
end

function Roster:RenamePlayer(oldName, newName)
    if not oldName or oldName == "" or not newName or newName == "" then return false end
    if oldName == newName then return false end
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db then return false end

    oldName = DesolateLootcouncil:NormalizeName(oldName)
    newName = DesolateLootcouncil:NormalizeName(newName)

    local Att = DesolateLootcouncil:GetModule("Attendance", true)

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
        DesolateLootcouncil.API:LogAudit("ROSTER_RENAME", nil, newName, nil, string.format("Renamed Main from %s to %s", oldName, newName))
        if Att and Att.SnapshotRoster then Att:SnapshotRoster() end
        return true
    end

    -- Case 2: oldName is an Alt
    if db.playerRoster and db.playerRoster.alts and db.playerRoster.alts[oldName] then
        local main = db.playerRoster.alts[oldName]
        db.playerRoster.alts[newName] = main
        db.playerRoster.alts[oldName] = nil

        DesolateLootcouncil:DLC_Log(string.format("Renamed Alt player '%s' to '%s' (Main: %s).", oldName, newName, main))
        DesolateLootcouncil.API:LogAudit("ROSTER_RENAME", nil, newName, nil, string.format("Renamed Alt from %s to %s (Main: %s)", oldName, newName, main))
        if Att and Att.SnapshotRoster then Att:SnapshotRoster() end
        return true
    end

    return false
end


