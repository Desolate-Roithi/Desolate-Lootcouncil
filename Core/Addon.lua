local addonName, addonTable = ...
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

-- --- Conflict Prevention (Dev vs Prod) ---
-- IsAddOnLoaded() is NOT reliable during main-chunk execution — it only returns
-- true after ADDON_LOADED fires, which is AFTER all main chunks have run.
-- Instead we query AceAddon's internal registry via GetAddon(name, silent).
-- The registry is populated the instant NewAddon("DesolateLootcouncil") succeeds,
-- so whichever version loads SECOND will correctly detect the first and abort.
do
    local existingAddon = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil", true)
    if existingAddon and not _G.DLC_TEST_MODE then
        local other = (addonName == "Desolate_Lootcouncil-Dev") and "Production" or "Dev"
        print(string.format(
            "|cffff0000[Desolate Lootcouncil]|r %s ('%s') is already loaded. Aborting '%s' to prevent DB corruption.",
            other, existingAddon.name or "?", addonName))
        addonTable.abortLoad = true
        return
    end
end

---@diagnostic disable: duplicate-set-field, undefined-global
---@class DesolateLootcouncil : AceAddon, AceConsole-3.0, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0, AceTimer-3.0
---@field db table
---@field version string
---@field amILM boolean
---@field activeLootMaster string
---@field PriorityLog table
---@field Logic table
---@field Comm Comm
---@field Session Session
---@field Loot Loot
---@field DefaultLayouts table<string, table>
---@field SlashCommands table
---@field SettingsLoader table
---@field Persistence Persistence
---@field Logger table
---@field sessionAutopassActive boolean
---@field clientLootList table?
DesolateLootcouncil = LibStub("AceAddon-3.0"):NewAddon("DesolateLootcouncil", "AceConsole-3.0", "AceEvent-3.0",
    "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0")
-- Set global for easier access across files
_G.DesolateLootcouncil = DesolateLootcouncil
DesolateLootcouncil.version = C_AddOns and C_AddOns.GetAddOnMetadata("Desolate_Lootcouncil", "Version") or "1.0.0"

local function SafeIsGroupLeader(unit)
    unit = unit or "player"
    local ok, isLeader = pcall(UnitIsGroupLeader, unit)
    if ok and isLeader ~= nil and not (type(issecretvalue) == "function" and issecretvalue(isLeader)) then
        return not not isLeader
    end
    return false
end

local defaults = {
    global = {
        activeRaidProfile = "",
        activeRaidSessionID = 0,
        activeRaidLastActivity = 0,
        activeRaidLM = "",
    },
    profile = {
        configuredLM       = "",
        catalogTier        = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.CATALOG_TIER) or "midnight-s2",
        PriorityLists      = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.GetDefaultPriorityLists) and DesolateLootcouncil.Constants.GetDefaultPriorityLists() or {},
        MainRoster         = {},
        playerRoster       = { alts = {}, decay = {} },
        imTimestamps       = {},
        priorityTimestamps = {},
        configTimestamp    = 0,
        historyTimestamp   = 0,
        verboseMode        = false,
        debugMode          = false,
        session            = {
            loot = {},
            bidding = {},
            awarded = {},
            lootedMobs = {},
            isOpen = false
        },
        minLootQuality     = 3,   -- Default to Rare
        enableAutoLoot     = false, -- Auto-pass on loot rolls (OFF by default)
        enableAutoTrade    = true, -- Auto-stage items in trade window (ON by default)
        -- Consolidated Logic (LM=Acquire, Raider=Pass)
        DecayConfig        = {
            enabled = true,
            defaultPenalty = 1,     -- Configurable (0-3)
            sessionActive = false,
            currentSessionID = nil, -- Timestamp
            currentSessionLM = nil, -- Name of the Loot Master for the session
            lastActivity = nil,     -- Timestamp for stale checks
            currentAttendees = {},  -- Table: [MainName] = true
            sessionAutopassActive = false,
            sessionAutopassAnswered = false,
        },
        AttendanceHistory  = {},        -- List of past sessions { date, zone, attendees }
        AuditLog           = {},        -- Unified 2.0 Audit Ledger
        auditTimestamp     = 0,
        positions          = {},        -- Window positions { [windowName] = { point, relativePoint, xOfs, yOfs } }
        activeTheme        = "Midnight", -- Default UI Theme (Midnight Void)
        dbCreatedAt        = 0,         -- Sentinel: prevents AceDB from pruning a profile to nil on PLAYER_LOGOUT
    }
}

function DesolateLootcouncil:OnInitialize()
    -- 1. Initialize DB
    self.db = LibStub("AceDB-3.0"):New("DesolateLootDB", defaults, true)

    -- Auto-switch to active raid profile if active session is set globally and we are the LM
    if self.db.global and self.db.global.activeRaidProfile and self.db.global.activeRaidProfile ~= "" then
        local isLM = false
        local myName = UnitName("player")

        local normPlayer = addonTable.NormalizeName(myName)

        local activeLM = self.db.global.activeRaidLM
        if activeLM and activeLM ~= "" and (addonTable.NormalizeName(activeLM) == normPlayer or addonTable.NormalizeName(activeLM) == "player") then
            isLM = true
        else
            local profiles = self.db.sv and self.db.sv.profiles
            local targetProfile = self.db.global.activeRaidProfile
            local configuredLM = profiles and targetProfile and profiles[targetProfile] and
            profiles[targetProfile].configuredLM
            if configuredLM and configuredLM ~= "" and (addonTable.NormalizeName(configuredLM) == normPlayer or addonTable.NormalizeName(configuredLM) == "player") then
                isLM = true
            end
        end

        if isLM then
            local activeProf = self.db.global.activeRaidProfile
            if self.db:GetCurrentProfile() ~= activeProf then
                self.db:SetProfile(activeProf)
                self:DLC_Log(string.format("Auto-switched to active raid profile: '%s'", activeProf))
            end
        end
    end

    -- Register profile change callbacks
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

    -- 1a. Stamp the DB sentinel so it's never 0 (equal to its default).
    --     AceDB's removeDefaults() strips keys that equal their default value.
    --     If dbCreatedAt stayed 0 it would match the default and could be pruned,
    --     defeating the purpose of the sentinel. We only stamp it on first creation.
    if self.db.profile.dbCreatedAt == 0 then
        self.db.profile.dbCreatedAt = GetServerTime()
    end

    -- 2. Prevent AceDB from auto-stripping profile data on PLAYER_LOGOUT.
    --    AceDB's logoutHandler calls db:RegisterDefaults(nil) which runs removeDefaults(),
    --    stripping any key that equals its default value. If ALL keys match, the profile
    --    becomes {} and is deleted — wiping imported or cross-character shared data.
    --    OnDatabaseShutdown fires BEFORE RegisterDefaults(nil), so we replace it with a
    --    no-op on this specific DB instance. Profiles are only removed by explicit user action.
    self.db.RegisterCallback(self, "OnDatabaseShutdown", function(_, db)
        db.RegisterDefaults = function() end
    end)

    -- 3. Initialize Active Users
    self.activeAddonUsers        = {}
    -- 4. Initialize Simulated Group
    self.simulatedGroup          = { [UnitName("player")] = true }

    -- 5. Initialize Autopass state to a known-false default.
    --    CRITICAL: DO NOT change sessionAutopassActive to `nil`. We had a bug where
    --    `nil` broke the deterministic UI logic. Instead, we use a separate flag
    --    `sessionAutopassAnswered` to track if the LM has seen the popup, preventing
    --    endless re-prompts when the LM explicitly clicks "No" (which sets it to false).
    if self.db.profile.DecayConfig and not self.db.profile.DecayConfig.sessionActive then
        self.db.profile.DecayConfig.sessionAutopassActive = false
        self.db.profile.DecayConfig.sessionAutopassAnswered = false
    end
    self.sessionAutopassActive   = self.db.profile.DecayConfig and self.db.profile.DecayConfig.sessionAutopassActive or false
    self.sessionAutopassAnswered = self.db.profile.DecayConfig and self.db.profile.DecayConfig.sessionAutopassAnswered or false
    self.amILM                   = false -- explicit init; starts nil otherwise, breaks wasLM guard in UpdateLootMasterStatus
    self.lastLeader              = nil


    -- 6. Validate/Notify
    if self.db.profile.configuredLM == "" then
        self:DLC_Log(L["Warning: No Loot Master configured. Use /dlc config to set one."])
    end
    self:UpdateLootMasterStatus()

    -- 7. Register Chat Command
    self:RegisterChatCommand("dlc", function(input) self.SlashCommands.Handle(input) end)
    self:RegisterChatCommand("dl", function(input) self.SlashCommands.Handle(input) end)

    -- 8. Welcome Message & 2.0 DB Sanitization
    if not self.db.profile.positions then self.db.profile.positions = {} end
    if self.DBMigrator and self.DBMigrator.SanitizeProfileDatabase then
        self.DBMigrator:SanitizeProfileDatabase(self.db.profile)
    end
    if self.API and self.API.CompactRaidHistory then
        self.API:CompactRaidHistory()
    end
    self:DLC_Log("Desolate Lootcouncil " .. self.version .. " Loaded.")
end

function DesolateLootcouncil:OnProfileChanged(event, db, newProfile)
    if self.db.profile.dbCreatedAt == 0 then
        self.db.profile.dbCreatedAt = GetServerTime()
    end
    if not self.db.profile.positions then
        self.db.profile.positions = {}
    end

    if self.DBMigrator and self.DBMigrator.SanitizeProfileDatabase then
        self.DBMigrator:SanitizeProfileDatabase(self.db.profile)
    end

    if self.API and self.API.CompactRaidHistory then
        self.API:CompactRaidHistory()
    end

    if self.db.profile.DecayConfig and not self.db.profile.DecayConfig.sessionActive then
        self.db.profile.DecayConfig.sessionAutopassActive = false
        self.db.profile.DecayConfig.sessionAutopassAnswered = false
    end
    self.sessionAutopassActive   = self.db.profile.DecayConfig and self.db.profile.DecayConfig.sessionAutopassActive or false
    self.sessionAutopassAnswered = self.db.profile.DecayConfig and self.db.profile.DecayConfig.sessionAutopassAnswered or false

    local Roster                 = self:GetModule("Roster", true)
    if Roster and Roster.UpdateScoreMap then
        Roster:UpdateScoreMap()
    end

    local session = self.db.profile.session
    if session then
        self:_RepairItemCache(session)
    end
    self:_RefreshOpenWindows(session)

    local Session = self:GetModule("Session", true)
    if Session and Session.RestoreSession then
        Session:RestoreSession()
    end

    self:UpdateLootMasterStatus()

    self:DLC_Log(string.format("Profile changed: Roster and Session states rehydrated."))
end

function DesolateLootcouncil:OnEnable()
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateLootMasterStatus")
    self:RegisterEvent("PARTY_LEADER_CHANGED", "UpdateLootMasterStatus")
    -- Correct LM state after a reload/login while already in a group.
    -- PLAYER_ENTERING_WORLD fires before the group is fully restored, so we
    -- schedule a short delay to let GROUP_ROSTER_UPDATE settle first.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(2, function() self:UpdateLootMasterStatus() end)
    end)
    self:RegisterMessage("DLC_OFFICER_FLAG_CHANGED", function()
        self.amIOfficer = self:AmIOfficerOrLM()
    end)

end

function DesolateLootcouncil:_RepairItemCache(session)
    if not session then return false end
    local repaired = false
    local function repairList(list)
        if not list then return end
        for _, item in ipairs(list) do
            if item.itemID then
                local ok, _, link, _, _, _, _, _, _, _, icon = pcall(C_Item.GetItemInfo, item.itemID)
                if not ok or not link or link == "" then link = nil end
                local isPlaceholder = not item.link or not string.find(item.link, "|Hitem") or
                    string.find(item.link, "^Item %d+") or string.find(item.link, "Item %[%d+%] ")
                if link and isPlaceholder then
                    item.link = link
                    repaired = true
                end
                if icon and item.texture == "Interface\\Icons\\INV_Misc_QuestionMark" then
                    item.texture = icon
                    repaired = true
                end
            end
        end
    end

    repairList(session.loot)
    repairList(session.bidding)
    repairList(session.awarded)

    if repaired then
        self:DLC_Log("Item Cache Engine repaired uncached session items.")
    end
    return repaired
end

function DesolateLootcouncil:_RefreshOpenWindows(session)
    if session then
        -- Global auto-refresh for any open frames to pull the updated UI data
        ---@type UI_Loot
        local LootUI = self:GetModule("UI_Loot") --[[@as UI_Loot]]
        if LootUI and LootUI.lootFrame and LootUI.lootFrame:IsShown() then
            LootUI:ShowLootWindow(session.loot)
        end

        ---@type UI_Monitor
        local MonitorUI = self:GetModule("UI_Monitor") --[[@as UI_Monitor]]
        if MonitorUI and MonitorUI.monitorFrame and MonitorUI.monitorFrame:IsShown() then
            MonitorUI:ShowMonitorWindow(true)
        end

        ---@type UI_Voting
        local VotingUI = self:GetModule("UI_Voting") --[[@as UI_Voting]]
        if VotingUI and VotingUI.votingFrame and VotingUI.votingFrame:IsShown() then
            VotingUI:ShowVotingWindow(self:GetModule("Session").clientLootList, true)
        end

        ---@type UI_TradeList
        local TradeUI = self:GetModule("UI_TradeList") --[[@as UI_TradeList]]
        if TradeUI and TradeUI.tradeListFrame and TradeUI.tradeListFrame:IsShown() then
            TradeUI:ShowTradeListWindow()
        end

        ---@type UI_History
        local HistoryUI = self:GetModule("UI_History") --[[@as UI_History]]
        if HistoryUI and HistoryUI.sessionFrame and HistoryUI.sessionFrame:IsShown() then
            HistoryUI:ShowHistoryWindow()
        end
    end

    ---@type UI_PriorityLogHistory
    local PriorityLogUI = self:GetModule("UI_PriorityLogHistory", true)
    if PriorityLogUI and PriorityLogUI.logFrame and PriorityLogUI.logFrame:IsShown() then
        PriorityLogUI:RefreshView()
    end

    ---@type UI_RaidHistory
    local RaidHistUI = self:GetModule("UI_RaidHistory", true)
    if RaidHistUI and RaidHistUI.frame and RaidHistUI.frame:IsShown() then
        RaidHistUI:RefreshHistoryWindow()
    end

    ---@type UI_ItemManager
    local ItemMgr = self:GetModule("UI_ItemManager") --[[@as UI_ItemManager]]
    if ItemMgr and ItemMgr.frame and ItemMgr.frame:IsShown() then
        ItemMgr:RefreshWindow()
    end
end

function DesolateLootcouncil:GET_ITEM_INFO_RECEIVED()
    if self.refreshTimer then
        self:CancelTimer(self.refreshTimer)
    end
    self.refreshTimer = self:ScheduleTimer(function()
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")

        local session = self.db and self.db.profile and self.db.profile.session
        if session then
            self:_RepairItemCache(session)
        end
        self:_RefreshOpenWindows(session)

        self.refreshTimer = nil
    end, 0.5)
end

-- --- Loot Master Logic ---

function DesolateLootcouncil:GetGroupLeader()
    if not IsInGroup() then return UnitName("player") end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name and rank == 2 then return name end
        end
    else
        if SafeIsGroupLeader("player") then
            return UnitName("player")
        end
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if SafeIsGroupLeader(unit) then
                local pName, pRealm = UnitName(unit)
                if pRealm and pRealm ~= "" then return pName .. "-" .. pRealm:gsub("%s+", "") end
                return pName
            end
        end
    end
    return nil
end

function DesolateLootcouncil:DetermineLootMaster()
    local myName = UnitName("player")

    -- Disable entirely if we are in LFR (Match-made groups)
    if HasLFGRestrictions() then
        return nil
    end

    if not IsInGroup() then
        -- If an active raid session exists, respect its recorded LM
        local decayConfig = self.db and self.db.profile and self.db.profile.DecayConfig
        if decayConfig and decayConfig.sessionActive and decayConfig.currentSessionLM and decayConfig.currentSessionLM ~= "" then
            return decayConfig.currentSessionLM
        end
        if self.activeLootMaster and self.activeLootMaster ~= "" then
            return self.activeLootMaster
        end
        return myName
    end

    -- 1. Use the active, synced Loot Master if valid and present
    if self.activeLootMaster and self.activeLootMaster ~= "" then
        if self:IsUnitInRaid(self.activeLootMaster) or self:SmartCompare(self.activeLootMaster, "player") then
            return self.activeLootMaster
        elseif IsInGroup() then
            -- LM left or became invalid; clear it to allow fallback
            self.activeLootMaster = nil
        else
            -- Not in group: retain activeLootMaster reference during session disband
            return self.activeLootMaster
        end
    end

    -- 2. Authority Check: Only the Raid/Party Leader can nominate an LM via Config.
    local isLeader = false
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 and self:SmartCompare(name, "player") then
                isLeader = true
                break
            end
        end
    elseif IsInGroup() then
        isLeader = SafeIsGroupLeader("player")
    end

    if isLeader then
        local configuredLM = self.db.profile.configuredLM
        if configuredLM and configuredLM ~= "" then
            if self:IsUnitInRaid(configuredLM) or self:SmartCompare(configuredLM, "player") then
                return configuredLM
            end
            self:DLC_Log("Configured LM (" .. configuredLM .. ") not found. Falling back to yourself (Leader).")
        end
        return myName
    end

    -- 3. Raider Fallback: Always default to the actual Group Leader if no LM is synced.
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 then return name end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if SafeIsGroupLeader(unit) then
                local pName, pRealm = UnitName(unit)
                if pRealm and pRealm ~= "" then return pName .. "-" .. pRealm:gsub("%s+", "") end
                return pName
            end
        end
    end

    -- 4. Session Fallback: If a raid session is active, respect its recorded LM
    local decayConfig = self.db and self.db.profile and self.db.profile.DecayConfig
    if decayConfig and decayConfig.sessionActive and decayConfig.currentSessionLM and decayConfig.currentSessionLM ~= "" then
        return decayConfig.currentSessionLM
    end

    return myName
end

function DesolateLootcouncil:UpdateLootMasterStatus()
    if not self.db then return end

    local oldLM = self.activeLootMaster
    local oldLeader = self.lastLeader

    local leader = self:GetGroupLeader()
    if leader and not self:SmartCompare(leader, self.lastLeader) then
        local wasLeader = self.lastLeader and self:SmartCompare(self.lastLeader, "player")
        local isNowLeader = self:SmartCompare(leader, "player")
        if wasLeader and not isNowLeader then
            local Session = self:GetModule("Session", true)
            local hasActiveSession = Session and Session.clientLootList and #Session.clientLootList > 0
            if self.amILM and hasActiveSession then
                local SyncMod = self:GetModule("Sync", true)
                if SyncMod then
                    self:DLC_Log(string.format("Leadership passed to %s. Initiating automatic Loot Master handover.",
                        leader))
                    SyncMod:SendLMHandoverOffer(leader)
                end
            end
        end
        self.activeLootMaster = nil
        self.lastLeader = leader
    end

    -- Switch profile if a raid session is active globally and we are the leader/LM of the group
    if IsInGroup() and self.db.global and self.db.global.activeRaidProfile and self.db.global.activeRaidProfile ~= "" then
        local amILeader = self:SmartCompare(self:GetGroupLeader(), "player")
        if amILeader then
            local activeProf = self.db.global.activeRaidProfile
            if self.db:GetCurrentProfile() ~= activeProf then
                self:DLC_Log(string.format("Auto-switching profile to active raid profile: '%s' (LM Relog)", activeProf))
                self.db:SetProfile(activeProf)
                return
            end
        end
    end

    local targetLM = self:DetermineLootMaster()
    local wasLM = self.amILM

    local lmLeft = false
    if oldLM and oldLM ~= "" and IsInGroup() then
        if not self:IsUnitInRaid(oldLM) and not self:SmartCompare(oldLM, "player") then
            self.activeLootMaster = targetLM
            lmLeft = true
        end
    end

    self.amILM = (targetLM and self:SmartCompare(targetLM, "player")) or false
    self.amIOfficer = self:AmIOfficerOrLM()

    if lmLeft and self.amIOfficer then
        if oldLeader and self:SmartCompare(oldLM, oldLeader) then
            self:Print(string.format(L["Raid Leader %s has left the group. %s is now the group leader and Loot Master."],
                self:GetDisplayName(oldLM), self:GetDisplayName(targetLM)))
        else
            self:Print(string.format(L["Loot Master %s has left the group. Leadership falls back to %s."],
                self:GetDisplayName(oldLM), self:GetDisplayName(targetLM)))
        end
    end

    -- If we just BECAME the LM, reset the prompt flag so we can decide for ourselves
    if self.amILM and not wasLM then
        self.sessionAutopassAnswered = false
        if self.db.profile.DecayConfig then
            self.db.profile.DecayConfig.sessionAutopassAnswered = false
        end
        local Session = self:GetModule("Session", true)
        local pendingChoice = Session and Session.pendingHandoverChoice
        if not pendingChoice and IsInRaid() and self.db.profile.DecayConfig and self.db.profile.DecayConfig.sessionActive then
            self:PromptAutopass()
        end
    end

    -- If we are the active LM and the session is active, update the global activeRaidLM to our name
    if self.amILM and self.db.profile.DecayConfig and self.db.profile.DecayConfig.sessionActive then
        if self.db.global and self.db.global.activeRaidLM ~= UnitName("player") then
            self.db.global.activeRaidLM = UnitName("player")
            self:DLC_Log(string.format("Updated active raid LM to: %s", UnitName("player")))
        end
    end

    self:DLC_Log(string.format(L["Role Update: You are %s (LM: %s)"], self.amILM and L["Loot Master"] or L["Raider"],
        tostring(self:GetDisplayName(targetLM))))

    -- Always broadcast LM identity when in a group, regardless of our own role.
    -- This ensures late-joiners are corrected even before the session heartbeat fires (30s).
    -- Raiders also call this on GROUP_ROSTER_UPDATE — only the actual LM executes the send
    -- because SendSyncLM is a no-op when not in a channel (solo) and the channel is RAID.
    if IsInGroup() then
        ---@type Session
        local Session = self:GetModule("Session") --[[@as Session]]
        local amILeader = self:SmartCompare(self:GetGroupLeader(), "player")
        if (self.amILM or amILeader) and Session and Session.SendSyncLM then
            Session:SendSyncLM(targetLM)
        end
    end
end

function DesolateLootcouncil:AmILootMaster()
    return self.amILM
end

function DesolateLootcouncil:IsOfficer(name)
    local targetName = name or UnitName("player")
    if not targetName or targetName == "" then return false end
    if self:SmartCompare(targetName, "player") and self.amILM then return true end

    local db = self.db and self.db.profile
    if not db then return false end

    -- Check if name is an alt, resolve to Main
    local mainName = targetName
    if db.playerRoster and db.playerRoster.alts then
        local score = self:GetScoreName(name)
        for alt, main in pairs(db.playerRoster.alts) do
            if self:GetScoreName(alt) == score then
                mainName = main
                break
            end
        end
    end

    local mainScore = self:GetScoreName(mainName)
    if db.MainRoster then
        for rName, data in pairs(db.MainRoster) do
            if self:GetScoreName(rName) == mainScore then
                return type(data) == "table" and data.isOfficer == true
            end
        end
    end

    return false
end

function DesolateLootcouncil:CalculateRosterHash(mainRoster)
    if not mainRoster then return "00000000" end
    local names = {}
    for name in pairs(mainRoster) do
        local score = self:GetScoreName(name) or name
        table.insert(names, score)
    end
    table.sort(names)
    local str = table.concat(names, ",")

    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) % 4294967296
    end
    return string.format("%08x", hash)
end

function DesolateLootcouncil:CheckProfileAutoSwitch(incomingRosterHash)
    if not incomingRosterHash or incomingRosterHash == "00000000" or incomingRosterHash == "" then
        return true
    end

    local currentHash = self:CalculateRosterHash(self.db.profile.MainRoster)
    if currentHash == incomingRosterHash then
        return true
    end

    -- Scan other profiles for a match
    local profiles = self.db.sv and self.db.sv.profiles
    if profiles then
        for profName, profData in pairs(profiles) do
            if profData and profData.MainRoster then
                local profHash = self:CalculateRosterHash(profData.MainRoster)
                if profHash == incomingRosterHash then
                    self.db:SetProfile(profName)
                    self:Print(string.format(L["Auto-switched profile to '%s' (matched Loot Master raid roster)."], profName))
                    return true
                end
            end
        end
    end

    return false
end

function DesolateLootcouncil:AmIOfficerOrLM()
    -- Tier 1: Solo mode — player is always LM when not in any group.
    if self.amILM then return true end

    -- Tier 2: In a group — LM identity must be resolved and the LM must be present.
    -- If no LM is synced yet (e.g. joining raid before version check handshake),
    -- fall back to false rather than granting access based on stale data.
    if IsInGroup() and (not self.activeLootMaster or self.activeLootMaster == "") then
        return false -- LM not yet identified; deny access until handshake completes
    end

    -- Tier 3: Roster flag lookup
    local myName = UnitName("player")
    return self:IsOfficer(myName)
end

-- Backward compatibility stub calling AmIOfficerOrLM()
function DesolateLootcouncil:AmIRaidAssistOrLM()
    return self:AmIOfficerOrLM()
end

-- --- Version Logic ---

function DesolateLootcouncil:SendVersionCheck()
    ---@type Comm
    local Comm = self:GetModule("Comm") --[[@as Comm]]
    if Comm and Comm.SendVersionCheck then Comm:SendVersionCheck() end
end

function DesolateLootcouncil:GetActiveUserCount()
    ---@type Comm
    local Comm = self:GetModule("Comm") --[[@as Comm]]
    if Comm and Comm.GetActiveUserCount then return Comm:GetActiveUserCount() end
    return 0
end

function DesolateLootcouncil:OpenConfig(initialTab)
    local UI = self:GetModule("UI", true)
    if UI and UI.ShowSettingsWindow then
        UI:ShowSettingsWindow(initialTab)
    end
end

-- --- Chat Command (Proxy for Modules) ---

-- ChatCommand logic moved to Core/SlashCommands.lua



function DesolateLootcouncil:DLC_Log(msg, force)
    if self.Logger then self.Logger.Log(msg, force) end
end

-- Persistence via Utility
function DesolateLootcouncil:SaveFramePosition(frame, windowName)
    if self.Persistence then self.Persistence:SaveFramePosition(frame, windowName) end
end

function DesolateLootcouncil:RestoreFramePosition(frame, windowName)
    if self.Persistence then self.Persistence:RestoreFramePosition(frame, windowName) end
end

function DesolateLootcouncil:MakeMovableWithSave(frame, windowName)
    if self.Persistence then self.Persistence:MakeMovableWithSave(frame, windowName) end
end

--- Global Helper: Is unit in raid/party OR simulated?
function DesolateLootcouncil:IsUnitInRaid(unitName)
    ---@type Simulation
    local Sim = self:GetModule("Simulation") --[[@as Simulation]]
    if Sim and Sim.IsSimulated and Sim:IsSimulated(unitName) then return true end

    if IsInRaid() then
        return UnitInRaid(unitName) ~= nil
    elseif IsInGroup() then
        return UnitIsUnit(unitName, "player") or UnitInParty(unitName) ~= nil
    end
    return UnitIsUnit(unitName, "player")
end

function DesolateLootcouncil:IsUnitOnline(unitName)
    if not unitName or unitName == "" then return false end

    local Sim = self:GetModule("Simulation", true)
    if Sim and Sim.IsSimulated and Sim:IsSimulated(unitName) then
        if Sim.IsOffline and Sim:IsOffline(unitName) then
            return false
        end
        return true
    end

    if self:SmartCompare(unitName, "player") then
        return true
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank, subgroup, level, class, fileName, zone, online = GetRaidRosterInfo(i) -- luacheck: ignore rank subgroup level class fileName zone
            if name and self:SmartCompare(name, unitName) then
                return online == true or online == 1
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name and self:SmartCompare(name, unitName) then
                return UnitIsConnected(unit) == true or UnitIsConnected(unit) == 1
            end
        end
    end
    return false
end

--- Returns a consistent Name-Realm string for a unit.
--- If no realm is present, appends the local realm.
---@param unit string
---@return string
function DesolateLootcouncil:GetFullName(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if not realm or realm == "" then realm = GetRealmName() end
    return name .. "-" .. realm:gsub("%s+", "")
end

--- Normalizes a "Name" or "Name-Realm" string to "Name-Realm".
---@param name string
---@return string
function DesolateLootcouncil:NormalizeName(name)
    if not name or name == "" then return name end
    if string.find(name, "-") then return name:gsub("%s+", "") end
    return name .. "-" .. GetRealmName():gsub("%s+", "")
end

--- Returns a canonical lowercase "Name-Realm" string for internal logic.
---@param name string|nil
---@return string|nil
function DesolateLootcouncil:GetScoreName(name)
    if not name or name == "" then return nil end

    local safeLower = (type(strlower) == "function" and strlower) or string.lower

    -- Local cache for common 'player' lookup to avoid UnitName calls in loops
    if name == "player" then
        local pName, pRealm = UnitName("player")
        pRealm = (pRealm and pRealm ~= "") and pRealm or GetRealmName()
        if pName then
            local currentScore = safeLower(pName .. "-" .. pRealm):gsub("%s+", "")
            self.cachedPlayerScore = currentScore
            return currentScore
        end
        return self.cachedPlayerScore
    end

    local lowName = safeLower(name)
    if not string.find(lowName, "-") then
        local realm = safeLower(GetRealmName()):gsub("%s+", "")
        lowName = lowName .. "-" .. realm
    end
    -- Also remove any spaces from the realm part if it was already there
    return lowName:gsub("%s+", "")
end

--- Specialized fast path for normalizing unit tokens (raid1, target, etc)
--- avoiding mid-level GetFullName overhead.
---@param unit string
---@return string|nil
function DesolateLootcouncil:GetUnitScore(unit)
    if not unit then return nil end
    if unit == "player" then return self:GetScoreName("player") end

    local safeLower = (type(strlower) == "function" and strlower) or string.lower
    local name, realm = UnitName(unit)
    if not name then return nil end

    realm = (realm and realm ~= "") and realm or GetRealmName()
    return safeLower(name .. "-" .. realm):gsub("%s+", "")
end

--- Returns the name exactly as it appears in the Roster, or simplified for UI.
---@param name string|nil
---@return string|nil
function DesolateLootcouncil:GetDisplayName(name)
    if not name or name == "" then return nil end
    local Roster = self:GetModule("Roster")
    local main = Roster and Roster:GetMain(name) or name

    local profile = self.db.profile
    -- 1. Check if the Main is in the MainRoster (to get the exact casing/format)
    if profile.MainRoster then
        for rosterName, _ in pairs(profile.MainRoster) do
            if self:SmartCompare(rosterName, main) then
                return rosterName
            end
        end
    end

    -- 2. Fallback: Ambiguate the input
    return Ambiguate(name, "none")
end

--- Formats a character name for clean UI display:
--- Strips the realm tag if the character is on the local player's realm,
--- but preserves '-OtherRealm' if cross-realm.
---@param fullName string|nil
---@return string
function DesolateLootcouncil:Ambiguate(fullName)
    if not fullName or fullName == "" then return "" end
    local charName, realm = tostring(fullName):match("^([^-]+)%-(.+)$")
    if not charName or not realm then
        return tostring(fullName)
    end

    local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    local normRealm = realm:gsub("%s+", ""):lower()
    local normMyRealm = myRealm:gsub("%s+", ""):lower()

    if normMyRealm ~= "" and normRealm == normMyRealm then
        return charName
    end

    return tostring(fullName)
end
addonTable.Ambiguate = function(fullName)
    return DesolateLootcouncil:Ambiguate(fullName)
end

--- Efficiently compares two names for case-insensitive and realm-aware equivalence.
---@param n1 string|nil
---@param n2 string|nil
---@return boolean
function DesolateLootcouncil:SmartCompare(n1, n2)
    if not n1 or not n2 then return false end
    if n1 == n2 then return true end
    local s1 = self:GetScoreName(n1)
    local s2 = self:GetScoreName(n2)
    if s1 and s2 and s1 == s2 then return true end

    -- Cross-realm fallback: If one or both lack a realm or belong to different connected realms, match by short character name
    local safeLower = (type(strlower) == "function" and strlower) or string.lower
    local short1 = safeLower(Ambiguate(n1, "none"))
    local short2 = safeLower(Ambiguate(n2, "none"))
    return (short1 ~= "" and short1 == short2)
end

function DesolateLootcouncil:GetOptions()
    if self.SettingsLoader then return self.SettingsLoader.GetOptions() end
    return { type = "group", args = {} }
end

--- Returns the player's enchanting skill level.
--- Returns nil if the player does not have Enchanting.
--- Returns the highest expansion skill level learned.
---@return number|nil
function DesolateLootcouncil:GetEnchantingSkillLevel()
    -- Resolve the locale-appropriate profession name at runtime.
    -- Spell 7411 is the Enchanting skill spell, available in all locales.
    local ENCHANTING_NAME = C_Spell.GetSpellName(7411) or "Enchanting"

    local prof1, prof2 = GetProfessions()
    local function IsEnchanting(id)
        if not id then return false end
        local name = GetProfessionInfo(id)
        return name == ENCHANTING_NAME
    end

    if not IsEnchanting(prof1) and not IsEnchanting(prof2) then
        return nil
    end

    local highestRank = 0
    local found = false

    local ok, childInfos = pcall(C_TradeSkillUI.GetChildProfessionInfos)
    if ok and childInfos then
        for _, info in ipairs(childInfos) do
            if info.skillLevel then
                highestRank = math.max(highestRank, info.skillLevel)
                found = true
            end
        end
    end

    if not found then
        -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Fallback profession rank lookup when C_TradeSkillUI is not populated
        local function GetLegacyRank(id)
            if not id then return 0 end
            local name, _, rank = GetProfessionInfo(id)
            if name == ENCHANTING_NAME then return rank end
            return 0
        end
        highestRank = math.max(GetLegacyRank(prof1), GetLegacyRank(prof2))
    end

    return highestRank
end

--- Returns the appropriate broadcast channel for the current group state.
--- @return string|nil  "RAID", "PARTY", or nil when not in a group.
function DesolateLootcouncil:GetBroadcastChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

function DesolateLootcouncil:GetMissingAddonMembers()
    if not IsInGroup() then return {} end

    -- Check if simulation is active
    local Sim = self:GetModule("Simulation", true)
    local simActive = Sim and Sim.GetRoster and #Sim:GetRoster() > 0
    if simActive then return {} end

    local prefix = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    local Comm = self:GetModule("Comm", true)
    local playerVersions = (Comm and Comm.playerVersions) or {}

    local missing = {}
    for i = 1, count do
        local name = GetUnitName(prefix .. i, true)
        if name then
            local found = false
            for verName in pairs(playerVersions) do
                if self:SmartCompare(name, verName) then
                    found = true
                    break
                end
            end
            if not found and not self:SmartCompare(name, "player") then
                table.insert(missing, self:GetDisplayName(name) or name)
            end
        end
    end
    return missing
end

function DesolateLootcouncil:DoAllGroupMembersHaveAddon()
    local missing = self:GetMissingAddonMembers()
    return #missing == 0
end

function DesolateLootcouncil:IsLMAddonUser()
    local lm = self:DetermineLootMaster() or self.activeLootMaster
    if not lm or lm == "" then return false end
    if self:SmartCompare(lm, "player") then return true end
    local activeUsers = self.activeAddonUsers or {}
    if activeUsers[lm] then return true end
    for user in pairs(activeUsers) do
        if self:SmartCompare(user, lm) then
            return true
        end
    end
    if self.sessionAutopassActive then return true end
    return false
end

function DesolateLootcouncil:PromptAutopass(isRetry)
    if not self:AmILootMaster() then return end

    if not IsInGroup() or self:DoAllGroupMembersHaveAddon() then
        -- Only show the UI popup during a live session, not during automated test runs
        if not self.isTestRunning and StaticPopup_Show then
            StaticPopup_Show("DLC_ENABLE_AUTOPASS")
        end
        return
    end

    if not isRetry then
        local Comm = self:GetModule("Comm", true)
        if Comm and Comm.SendVersionCheck then
            Comm:SendVersionCheck()
        end
        C_Timer.After(2.0, function()
            self:PromptAutopass(true)
        end)
        return
    end

    local missing = self:GetMissingAddonMembers()
    local missingStr = table.concat(missing, ", ")
    self:Print(string.format(L["Autopass is disabled because the following members do not have the addon: %s"], missingStr))
    local Sync = self:GetModule("Sync", true)
    if Sync and Sync.SendSyncAutopass then
        Sync:SendSyncAutopass(false)
    end
    self.sessionAutopassAnswered = true
    if self.db and self.db.profile and self.db.profile.DecayConfig then
        self.db.profile.DecayConfig.sessionAutopassAnswered = true
    end
end
