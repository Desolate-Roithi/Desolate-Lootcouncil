local _, AT = ...
if AT.abortLoad then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

---@class Session : AceModule, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0, AceConsole-3.0
local Session = DesolateLootcouncil:NewModule("Session", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0",
    "AceConsole-3.0", "AceTimer-3.0")

---@class (partial) DLC_Ref_Session
---@field db table
---@field DetermineLootMaster fun(self: any): string
---@field AmILootMaster fun(self: any): boolean
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field GetModule fun(self: any, name: string): any
---@field GetEnchantingSkillLevel fun(self: any): number
---@field AmIOfficerOrLM fun(self: any): boolean
---@field activeLootMaster string
---@field amILM boolean
---@field sessionAutopassActive boolean?
---@field clientLootList table?

---@type DLC_Ref_Session
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Session]]

---@class DistributionPayload
---@field command string
---@field data table
---@field duration number?
---@field endTime number?

function Session:OnEnable()
    self:RegisterComm("DLC_Loot", "OnCommReceived")
    -- Attempt Rehydration
    C_Timer.After(1, function() self:RestoreSession() end)
    DesolateLootcouncil:DLC_Log("Systems/Session Loaded")

    self.outboundVotes = {}
    self.lastHeartbeat = 0
    self.sessionPayloadCache = nil -- Pre-serialized LOOT_SESSION_START string for heartbeat
    self:ScheduleRepeatingTimer("OnTimerTick", 1)

    -- Define session-restore popup once at module load.
    -- OnCancel reads self.pendingRestore set by RestoreSession to avoid capturing
    -- ephemeral local variables inside a repeated closure allocation.
    StaticPopupDialogs["DLC_CLOSE_SESSION"] = {
        text = L["A previous Loot Session is still active. Do you want to close it?"],
        button1 = L["Yes (Close Session)"],
        button2 = L["No (Keep Active)"],
        OnAccept = function()
            Session:SendStopSession()
        end,
        OnCancel = function()
            local p = Session.pendingRestore
            if p then
                Session:PerformRestore(p.state, p.now, p.expiry)
                Session.pendingRestore = nil
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["DLC_CLAIM_LM"] = {
        text = L["No Loot Master has been detected in the group for 60+ seconds. Do you want to claim the Loot Master role?"],
        button1 = L["Yes (Claim LM)"],
        button2 = L["Cancel"],
        OnAccept = function()
            Session:ClaimLMRole()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["DLC_HANDOVER_RL_ACTIVE"] = {
        text = L["%s is handing you the Loot Master role. Do you want to continue the running raid session, or start a new one?"],
        button1 = L["Continue Session"],
        button2 = L["Start New Session"],
        OnAccept = function()
            Session:AcceptHandover(false, true)
        end,
        OnCancel = function(_, _, reason)
            if reason == "clicked" then
                Session:AcceptHandover(false, false)
            else
                Session:DeclineHandover()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
    }

    StaticPopupDialogs["DLC_HANDOVER_OFFICER_ACTIVE"] = {
        text = L["%s is handing you the Loot Master role. Do you want to continue the running raid session, start a new one, or decline the handover?"],
        button1 = L["Continue Session"],
        button2 = L["Start New Session"],
        button3 = L["Decline Handover"],
        OnAccept = function()
            Session:AcceptHandover(false, true)
        end,
        OnCancel = function(_, _, reason)
            if reason == "clicked" then
                Session:AcceptHandover(false, false)
            else
                Session:DeclineHandover()
            end
        end,
        OnAlt = function()
            Session:DeclineHandover()
        end,
        timeout = 60,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["DLC_HANDOVER_OFFICER_INACTIVE"] = {
        text = L["%s is offering you the Loot Master role. Accept or decline?"],
        button1 = L["Accept LM"],
        button2 = L["Decline Handover"],
        OnAccept = function()
            Session:AcceptHandover(false, false)
        end,
        OnCancel = function(_, _, reason)
            Session:DeclineHandover()
        end,
        timeout = 60,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["DLC_CONFIRM_FORCE_HANDOVER"] = {
        text = L["The active Loot Master is %s. Handover of active sessions should ideally be initiated by the active LM. Force handover anyway?"],
        button1 = L["Yes (Force)"],
        button2 = L["No"],
        OnAccept = function()
            local target = DesolateLootcouncil.pendingForceTarget
            if target then
                DesolateLootcouncil.API:SendLMHandoverOffer(target)
            end
            DesolateLootcouncil.pendingForceTarget = nil
        end,
        OnCancel = function()
            DesolateLootcouncil.pendingForceTarget = nil
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["DLC_PENDING_DECAY"] = {
        text = L["The last raid session (%s, %s) has pending decay. Apply decay now before starting a new session?"],
        button1 = L["Apply Decay"],
        button2 = L["Skip"],
        button3 = L["Review First"],
        OnAccept = function()
            local RosterSys = DesolateLootcouncil:GetModule("Roster")
            if RosterSys and RosterSys.ApplyDecayForLastSession then
                RosterSys:ApplyDecayForLastSession()
            end
        end,
        OnCancel = function(_, _, reason)
            if reason == "clicked" then
                local RosterSys = DesolateLootcouncil:GetModule("Roster")
                if RosterSys and RosterSys.ApplyDecayForLastSession then
                    RosterSys:ApplyDecayForLastSession(true)
                end
            end
        end,
        OnAlt = function()
            local Attendance = DesolateLootcouncil:GetModule("UI_Attendance", true)
            if Attendance and Attendance.ShowAttendanceWindow then
                Attendance:ShowAttendanceWindow()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
    }
end

function Session:OnTimerTick()
    -- Approach B: No client polling/batching queues needed!
    -- Session Heartbeat & Full Sync (Late Joiners & Consistency) — LM only
    local now = GetServerTime()
    if DesolateLootcouncil:AmILootMaster() then
        -- Periodic Autopass Heartbeat (every 30s)
        self.lastAutopassHeartbeat = self.lastAutopassHeartbeat or 0
        if now - self.lastAutopassHeartbeat > 30 then
            self.lastAutopassHeartbeat = now
            local Sync = DesolateLootcouncil:GetModule("Sync")
            if Sync and DesolateLootcouncil.sessionAutopassActive ~= nil then
                Sync:SendSyncAutopass(DesolateLootcouncil.sessionAutopassActive, true)
            end
        end

        -- Periodic DLC Heartbeat (every 30s)
        self.lastDLCHeartbeat = self.lastDLCHeartbeat or 0
        if now - self.lastDLCHeartbeat > 30 then
            self.lastDLCHeartbeat = now
            self:SendDLCHeartbeat()
        end

        if self.clientLootList and #self.clientLootList > 0 then
            -- Item-list Heartbeat (every 30s — late joiners & reloaders)
            if now - self.lastHeartbeat > 30 then
                self.lastHeartbeat = now
                self:SendSessionHeartbeat()
            end
        end
    end
end

function Session:SendDLCHeartbeat()
    if not IsInGroup() then return end
    local db = DesolateLootcouncil.db.profile
    local officers = {}
    local officerMains = {}
    if db.MainRoster then
        for name, data in pairs(db.MainRoster) do
            if data.isOfficer then
                table.insert(officers, name)
                officerMains[DesolateLootcouncil:GetScoreName(name)] = true
            end
        end
    end
    if db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            local mainScore = DesolateLootcouncil:GetScoreName(main)
            if officerMains[mainScore] then
                table.insert(officers, alt)
            end
        end
    end
    local payload = {
        imTimestamps = db.imTimestamps or {},
        priorityTimestamps = db.priorityTimestamps or {},
        officers = officers,
        configTimestamp = db.configTimestamp or 0,
        historyTimestamp = db.historyTimestamp or 0,
        rosterTimestamp = db.rosterTimestamp or 0,
    }
    local Comm = DesolateLootcouncil:GetModule("Comm")
    if Comm then
        Comm:SendComm("DLC_HEARTBEAT", payload)
    end
end

-- ==============================================================================
-- LOOT SESSIONS vs RAID SESSIONS:
-- "Raid Sessions" are overarching attendance/configuration tracking sessions managed by `Roster.lua`.
-- "Loot Sessions" are short-lived voting events triggered per-item/boss by `Session.lua`.
-- ==============================================================================

-- Build (or reuse) the cached LOOT_SESSION_START serialization and broadcast it.
-- isHeartbeat=true signals receivers NOT to rebuild their full UI if already hydrated,
-- but closedItems is always included so late-joiners get correct state immediately.
function Session:SendSessionHeartbeat()
    if not self.sessionPayloadCache then
        local payloadData = {}
        for _, item in ipairs(self.clientLootList or {}) do
            table.insert(payloadData, {
                link       = item.link,
                texture    = item.texture,
                itemID     = item.itemID,
                sourceGUID = item.sourceGUID,
                category   = item.category
            })
        end
        -- Snapshot closedItems for the heartbeat, capped at 30 entries.
        -- The live self.closedItems is untouched; items beyond this cap are
        -- already awarded and irrelevant to any late-joiner entering now.
        local payload = {
            command        = "LOOT_SESSION_START",
            data           = payloadData,
            duration       = self.sessionDuration or 300,
            endTime        = self.sessionExpiry,
            closedItems    = self.closedItems,
            votes          = self.sessionVotes,
            isHeartbeat    = true,
            autopassActive = DesolateLootcouncil.sessionAutopassActive,
            activeLM       = DesolateLootcouncil.activeLootMaster, -- Include LM identity for late-joiner correction
        }
        self.sessionPayloadCache = self:Serialize(payload)
        DesolateLootcouncil:DLC_Log("Session Heartbeat: rebuilt payload cache.")
    else
        DesolateLootcouncil:DLC_Log("Session Heartbeat: using cached payload.")
    end

    local channel = DesolateLootcouncil:GetBroadcastChannel()
    if channel then
        self:SendCommMessage("DLC_Loot", self.sessionPayloadCache, channel)
    end

    -- Auto-Sync Item Manager lists automatically on heartbeat
    local API = DesolateLootcouncil.API
    if API and API.AutoSyncItemManager then
        API:AutoSyncItemManager()
    end
end

function Session:SaveSessionState()
    local session = DesolateLootcouncil.db.profile.session
    session.activeState = {
        lootList = self.clientLootList,
        votes    = self.sessionVotes,
        myVotes  = self.myLocalVotes,
        closed   = self.closedItems,
        expiry   = self.sessionExpiry,                  -- Absolute timestamp
        activeLM = DesolateLootcouncil.activeLootMaster -- Bug 6: persist LM identity
    }
end

function Session:RestoreSession()
    local session = DesolateLootcouncil.db.profile.session
    local state = session.activeState

    if state and state.lootList and #state.lootList > 0 then
        local now = GetServerTime()
        local expiry = state.expiry or 0
        local sessionStarted = (expiry > 300) and (expiry - 300) or expiry
        local isExpiredOver12h = now > (sessionStarted + 43200)

        local isLM = DesolateLootcouncil:SmartCompare(state.activeLM, "player") or (IsInGroup() and UnitIsGroupLeader("player"))
        if isLM then
            DesolateLootcouncil.activeLootMaster = UnitName("player")
            DesolateLootcouncil.amILM = true
            state.activeLM = UnitName("player")
        elseif state.activeLM and state.activeLM ~= "" then
            DesolateLootcouncil.activeLootMaster = state.activeLM
            DesolateLootcouncil.amILM = DesolateLootcouncil:SmartCompare(state.activeLM, "player")
        end

        if not isLM and isExpiredOver12h then
            DesolateLootcouncil:DLC_Log("Session > 12h old. Auto-closing for non-LM.")
            wipe(session.activeState)
            self:SendMessage("DLC_SESSION_STOPPED")
            return
        end

        if isLM then
            local decayConfig = DesolateLootcouncil.db.profile.DecayConfig
            local inactiveFor1h = decayConfig and decayConfig.lastActivity and (now - decayConfig.lastActivity > 3600)
            local notInGroup = not IsInGroup()

            if isExpiredOver12h or (inactiveFor1h and notInGroup) then
                -- Store restore context so the module-level popup handler can read it.
                self.pendingRestore = { state = state, now = now, expiry = expiry }
                StaticPopup_Show("DLC_CLOSE_SESSION")
                return
            end
        end

        self:PerformRestore(state, now, expiry)
    end
end

function Session:PerformRestore(state, now, expiry)
    local session = DesolateLootcouncil.db.profile.session
    if now < expiry then
        -- Scenario A: Active
        self.clientLootList = state.lootList
        self.sessionVotes   = state.votes or {}
        self.myLocalVotes   = state.myVotes or {}
        self.closedItems    = state.closed or {}
        self.sessionExpiry  = expiry

        local isLM = DesolateLootcouncil:SmartCompare(state.activeLM, "player") or (IsInGroup() and UnitIsGroupLeader("player"))
        if isLM then
            DesolateLootcouncil.activeLootMaster = UnitName("player")
            DesolateLootcouncil.amILM = true
            state.activeLM = UnitName("player")
        elseif state.activeLM and state.activeLM ~= "" then
            DesolateLootcouncil.activeLootMaster = state.activeLM
            DesolateLootcouncil.amILM = DesolateLootcouncil:SmartCompare(state.activeLM, "player")
        end

        DesolateLootcouncil:DLC_Log("Restored active session (" ..
            #self.clientLootList .. " items, LM: " .. DesolateLootcouncil:GetDisplayName(state.activeLM or "?") .. ").")

        self:SendMessage("DLC_SESSION_RESTORED", self.clientLootList, DesolateLootcouncil:AmIOfficerOrLM())
    else
        -- Scenario B: Expired
        DesolateLootcouncil:DLC_Log("Session expired while offline.")
        wipe(session.activeState)
        self:SendMessage("DLC_SESSION_STOPPED")
    end
end

--- Filters junk from a raw loot table, stamps per-item expiry, and persists the
--- clean list into session.bidding.  Returns the clean list, its item count, the
--- session duration, and the absolute end-time so callers never recompute them.
---@param lootTable table
---@return table cleanList, number itemCount, number duration, number endTime
function Session:FilterBiddingLoot(lootTable)
    local session  = DesolateLootcouncil.db.profile.session
    local duration = DesolateLootcouncil.db.profile.sessionDuration or 300
    local endTime  = GetServerTime() + duration

    self.sessionDuration     = duration
    self.sessionExpiry       = endTime
    self.sessionPayloadCache = nil  -- Invalidate heartbeat cache; item list changed.

    local cleanList = {}
    local itemCount = 0

    for _, item in ipairs(lootTable) do
        if item.category ~= "Junk/Pass" then
            local entry = {
                link       = item.link,
                itemID     = item.itemID,
                texture    = item.texture,
                category   = item.category,
                sourceGUID = item.sourceGUID,
                stackIndex = item.stackIndex,
                expiry     = endTime,  -- Per-item absolute expiry
            }
            table.insert(cleanList, entry)
            table.insert(session.bidding, entry)
            itemCount = itemCount + 1
        end
    end

    DesolateLootcouncil:DLC_Log("Loot moved to Bidding Storage. Collection cleared.")
    return cleanList, itemCount, duration, endTime
end

--- Serialises the session-start payload and broadcasts it to the group channel
--- (or whispers to self when running solo / in simulation mode).
---@param cleanList table
---@param itemCount number
---@param duration  number
---@param endTime   number
function Session:BroadcastSessionStart(cleanList, itemCount, duration, endTime)
    -- Build a lean payload — only fields the receiving client needs.
    local payloadData = {}
    for _, item in ipairs(cleanList) do
        table.insert(payloadData, {
            link       = item.link,
            texture    = item.texture,
            itemID     = item.itemID,
            sourceGUID = item.sourceGUID,
            category   = item.category,  -- Required for dynamic button generation
        })
    end

    local payload = {
        command        = "LOOT_SESSION_START",
        data           = payloadData,
        duration       = duration,
        endTime        = endTime,
        autopassActive = DesolateLootcouncil.sessionAutopassActive,
        activeLM       = DesolateLootcouncil.activeLootMaster,
    }
    local serialized = self:Serialize(payload)
    DesolateLootcouncil:DLC_Log("Sent packet size: " .. #serialized .. " bytes")

    local channel = DesolateLootcouncil:GetBroadcastChannel()

    if not channel then
        -- Solo / simulation: whisper to self so OnCommReceived fires normally.
        channel = "WHISPER"
        DesolateLootcouncil:DLC_Log("Not in group, simulating broadcast to self.")

        local Comm = DesolateLootcouncil:GetModule("Comm")
        if Comm then
            local myName = UnitName("player")
            if not Comm.playerEnchantingSkill then Comm.playerEnchantingSkill = {} end
            Comm.playerEnchantingSkill[myName] = DesolateLootcouncil:GetEnchantingSkillLevel()
        end

        self:SendCommMessage("DLC_Loot", serialized, channel, UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end

    DesolateLootcouncil:DLC_Log("Broadcasting Bidding Session to " .. channel .. " (" .. itemCount .. " items)...")

    -- Re-broadcast Autopass state so raiders activate it immediately on session start.
    -- IM_SYNC broadcast removed. Priority lists sync strictly on manual button press.
    local Sync = DesolateLootcouncil:GetModule("Sync")
    if Sync and DesolateLootcouncil.sessionAutopassActive ~= nil then
        Sync:SendSyncAutopass(DesolateLootcouncil.sessionAutopassActive)
    end
end

--- Opens the Loot Monitor for the LM and refreshes the Voting window if already
--- visible (handles overlapping sessions gracefully).
---@param cleanList table
function Session:OpenActiveSessionUIs(cleanList)
    self:SendMessage("DLC_SESSION_STARTED", cleanList, DesolateLootcouncil:AmIOfficerOrLM())
end

function Session:StartSession(lootTable)
    if not DesolateLootcouncil:AmILootMaster() then return end

    local RosterSys = DesolateLootcouncil:GetModule("Roster")
    if RosterSys and RosterSys.HasPendingDecay and RosterSys:HasPendingDecay() then
        local db = DesolateLootcouncil.db.profile
        local entry = db.AttendanceHistory[1]
        StaticPopup_Show("DLC_PENDING_DECAY", entry.date or "N/A", entry.zone or "Unknown")
        return
    end

    -- Wipe previous session's awarded items database to start completely fresh ONLY if not in an active raid session
    local session = DesolateLootcouncil.db.profile.session
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if session and not (config and config.sessionActive) then
        session.awarded = {}
    end
    local Loot = DesolateLootcouncil:GetModule("Loot")
    if Loot and Loot.ScanDisenchanters then
        Loot:ScanDisenchanters()
    end

    if not lootTable or #lootTable == 0 then
        DesolateLootcouncil:DLC_Log("No items to distribute!")
        return
    end

    -- 1. Filter junk, stamp expiry, persist to bidding storage.
    local cleanList, itemCount, duration, endTime = self:FilterBiddingLoot(lootTable)

    if itemCount == 0 then
        Loot:ClearLootBacklog()
        self:SendMessage("DLC_LOOT_WINDOW_UPDATE", nil)
        DesolateLootcouncil:DLC_Log("Session contained only junk. Loot cleared locally; no broadcast sent.")
        return
    end

    -- 2. Wipe raw collection so we can keep looting new mobs.
    Loot:ClearLootBacklog()
    self:SendMessage("DLC_LOOT_WINDOW_UPDATE", nil)

    if self.clientLootList and #self.clientLootList > 0 then
        for _, newItem in ipairs(cleanList) do
            local isDuplicate = false
            for _, existingItem in ipairs(self.clientLootList) do
                if existingItem.sourceGUID == newItem.sourceGUID then
                    isDuplicate = true
                    break
                end
            end
            if not isDuplicate then
                table.insert(self.clientLootList, newItem)
            end
        end
    else
        self.clientLootList = cleanList
    end

    self:BroadcastSessionStart(cleanList, itemCount, duration, endTime)

    -- Auto-Sync Item Manager lists automatically when starting a session
    local API = DesolateLootcouncil.API
    if API and API.AutoSyncItemManager then
        API:AutoSyncItemManager()
    end

    -- 4. Open LM windows.
    self:OpenActiveSessionUIs(self.clientLootList)
end

function Session:SendStopSession()
    -- 1. Broadcast "LOOT_SESSION_END"
    local payload = { command = "LOOT_SESSION_END" }
    local serialized = self:Serialize(payload)

    local channel = DesolateLootcouncil:GetBroadcastChannel()
    if not channel then
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
        -- Bug 4: Double-pulse for reliability in busy raids
        C_Timer.After(0.5, function()
            self:SendCommMessage("DLC_Loot", serialized, channel)
        end)
    end

    -- 2. Local Cleanup (LM Side)
    self.sessionVotes        = {}
    self.closedItems         = {}
    self.clientLootList      = {} -- B9: Clear so heartbeat timer stops on dead session
    self.sessionPayloadCache = nil
    -- Clear the Bidding storage so Monitor empties
    wipe(DesolateLootcouncil.db.profile.session.bidding)

    -- 3. Close Monitor & Reset Voting
    self:SendMessage("DLC_SESSION_STOPPED")

    -- Clear Saved State
    wipe(DesolateLootcouncil.db.profile.session.activeState)

    DesolateLootcouncil:DLC_Log("Session Stopped. Broadcast sent.")
end

function Session:SendCloseItem(itemGUID)
    -- 1. Broadcast to Raid
    local payload = { command = "CLOSE_ITEM", data = { guid = itemGUID } }
    local serialized = self:Serialize(payload)
    local channel = DesolateLootcouncil:GetBroadcastChannel()
    if not channel then
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end

    -- 2. Local Instant Update (Fix "Everyone Voted" lag)
    self.closedItems = self.closedItems or {}
    self.closedItems[itemGUID] = true
    self:SaveSessionState()

    self:SendMessage("DLC_ITEM_CLOSED", itemGUID)

    DesolateLootcouncil:DLC_Log("Voting closed for item: " .. string.sub(itemGUID, -8))
    self.sessionPayloadCache = nil -- Invalidate heartbeat cache; closed state changed
end

function Session:SendRemoveItem(guid)
    local payload = { command = "REMOVE_ITEM", data = { guid = guid } }
    local serialized = self:Serialize(payload)
    local channel = DesolateLootcouncil:GetBroadcastChannel()
    if not channel then
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end
end

-- Bug 4: Broadcast an awarded history entry to all players (split public/officer)
function Session:SendHistoryUpdate(entry)
    local publicEntry = {
        link      = entry.link,
        winner    = entry.winner,
        timestamp = entry.timestamp,
    }
    local officerEntry = {
        link        = entry.link,
        texture     = entry.texture,
        itemID      = entry.itemID,
        winner      = entry.winner,
        winnerClass = entry.winnerClass,
        voteType    = entry.voteType,
        timestamp   = entry.timestamp,
    }

    -- Populate publicAwardLog locally for the LM
    local db = DesolateLootcouncil.db.profile
    db.session = db.session or {}
    db.session.publicAwardLog = db.session.publicAwardLog or {}
    table.insert(db.session.publicAwardLog, publicEntry)

    local Comm = DesolateLootcouncil:GetModule("Comm")
    if Comm then
        Comm:SendComm("HISTORY_UPDATE_PUBLIC", publicEntry)
    end
    local Sync = DesolateLootcouncil:GetModule("Sync")
    if Sync and Sync.ShareDataWithOfficers then
        Sync:ShareDataWithOfficers("HISTORY_UPDATE_OFFICER", officerEntry)
    end
end

function Session:RemoveSessionItem(guid)
    -- 1. Tell clients to REMOVE the item (not just close)
    self:SendRemoveItem(guid)
    self.sessionPayloadCache = nil -- Invalidate heartbeat cache; item list changed

    -- 2. Remove from local Bidding storage (Monitor List)
    local session = DesolateLootcouncil.db.profile.session
    if session and session.bidding then
        for i, item in ipairs(session.bidding) do
            if (item.sourceGUID or item.link) == guid then
                table.remove(session.bidding, i)
                break
            end
        end
    end

    -- 3. Remove from Awarded list (Trade List) if it was already dealt out
    if session and session.awarded then
        for i = #session.awarded, 1, -1 do
            local item = session.awarded[i]
            if (item.sourceGUID or item.link) == guid then
                table.remove(session.awarded, i)
                -- Break isn't strictly necessary here, but good practice if guid is unique per item instance
                break
            end
        end
    end

    -- 4. Refresh Monitor
    self:SendMessage("DLC_ITEM_REMOVED", guid)

    -- 5. Refresh Trade List (if open)
    ---@type UI_TradeList
    local TradeListUI = DesolateLootcouncil:GetModule("UI_TradeList")
    if TradeListUI and TradeListUI.ShowTradeListWindow and TradeListUI.tradeListFrame and TradeListUI.tradeListFrame:IsShown() then
        TradeListUI:ShowTradeListWindow()
    end

    DesolateLootcouncil:DLC_Log("Removed item from session and pending trades.")
end

local function IsAuthorizedSessionSender(sender)
    -- 1. Sender is the current known LM
    local currentLM = DesolateLootcouncil.activeLootMaster
    if currentLM and currentLM ~= "" then
        if DesolateLootcouncil:SmartCompare(sender, currentLM) then return true end
    end
    -- 2. Sender is the group leader
    local groupLeader = DesolateLootcouncil:GetGroupLeader()
    if groupLeader and DesolateLootcouncil:SmartCompare(sender, groupLeader) then
        return true
    end

    -- 3. If we are the group leader, also check if the sender is the defined LM in our own config
    local amILeader = false
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 and DesolateLootcouncil:SmartCompare(name, "player") then
                amILeader = true
                break
            end
        end
    elseif IsInGroup() then
        amILeader = UnitIsGroupLeader("player")
    else
        amILeader = true
    end

    if amILeader then
        local configuredLM = DesolateLootcouncil.db.profile.configuredLM
        if configuredLM and configuredLM ~= "" and DesolateLootcouncil:SmartCompare(sender, configuredLM) then
            return true
        end
    end

    -- 4. Solo / test mode: accept self-packets
    if not IsInGroup() and DesolateLootcouncil:SmartCompare(sender, "player") then
        return true
    end

    return false
end

--- Handles automatic pass roll evaluations.
---@param payload table
---@param isHeartbeat boolean
function Session:_ApplyAutopassState(payload, isHeartbeat)
    if payload.autopassActive ~= nil then
        local changed = (DesolateLootcouncil.sessionAutopassActive ~= payload.autopassActive)
        DesolateLootcouncil.sessionAutopassActive = payload.autopassActive

        if not isHeartbeat or changed then
            local Autopass = DesolateLootcouncil:GetModule("Autopass")
            if Autopass and Autopass.ScanAndAutopassActiveLootRolls then
                Autopass:ScanAndAutopassActiveLootRolls()
            end
        end
    end
end

--- Authenticates and updates the Loot Master identity.
---@param payload table
---@param sender string
function Session:_ApplyLMLateJoinerIdentity(payload, sender)
    if payload.activeLM and payload.activeLM ~= "" and IsAuthorizedSessionSender(sender) then
        DesolateLootcouncil.activeLootMaster = payload.activeLM
        DesolateLootcouncil.amILM = DesolateLootcouncil:SmartCompare(payload.activeLM, "player")
        DesolateLootcouncil:DLC_Log(string.format("LM identity from session payload: %s (amILM=%s)",
            DesolateLootcouncil:GetDisplayName(payload.activeLM), tostring(DesolateLootcouncil.amILM)))
    elseif payload.activeLM and payload.activeLM ~= "" then
        DesolateLootcouncil:DLC_Log(string.format(
            "WARN: Ignored activeLM '%s' from unauthorized sender '%s'.",
            DesolateLootcouncil:GetDisplayName(payload.activeLM), tostring(sender)))
    end
end

local function IsItemAlreadyInList(list, item)
    for _, existing in ipairs(list) do
        if (existing.sourceGUID or existing.link) == (item.sourceGUID or item.link) then
            return true
        end
    end
    return false
end

--- Filters duplicates and populates local loot lists.
---@param newItems table
---@param expiry number
---@return number hydratedCount
function Session:_HydrateSessionItems(newItems, expiry)
    local hydratedCount = 0
    if not newItems then return hydratedCount end
    for _, item in ipairs(newItems) do
        item.expiry = expiry
        if not IsItemAlreadyInList(self.clientLootList, item) then
            table.insert(self.clientLootList, item)
            hydratedCount = hydratedCount + 1
        end
    end
    return hydratedCount
end

function Session:HandleStartSession(payload, sender)
    local newItems = payload.data
    local duration = payload.duration or 300
    local expiry = payload.endTime or (GetServerTime() + duration)
    local isHeartbeat = payload.isHeartbeat == true

    self:_ApplyAutopassState(payload, isHeartbeat)
    self:_ApplyLMLateJoinerIdentity(payload, sender)

    self.clientLootList = self.clientLootList or {}
    self.myLocalVotes = self.myLocalVotes or {}

    if isHeartbeat and #self.clientLootList > 0 then
        -- Already hydrated; refresh expiry and closed state, update Monitor silently.
        self.sessionExpiry = expiry
        -- Merge closed items from heartbeat — prevents stale "Open" display
        if payload.closedItems then
            self.closedItems = self.closedItems or {}
            for guid, v in pairs(payload.closedItems) do
                self.closedItems[guid] = v
            end
        end

        -- Merge active votes from heartbeat — ensures late-joiner Assistants stay synced
        if payload.votes and DesolateLootcouncil:AmIOfficerOrLM() then
            self.sessionVotes = self.sessionVotes or {}
            for guid, players in pairs(payload.votes) do
                self.sessionVotes[guid] = self.sessionVotes[guid] or {}
                for player, voteData in pairs(players) do
                    self.sessionVotes[guid][player] = voteData
                end
            end
        end
        if DesolateLootcouncil:AmIOfficerOrLM() then
            ---@type UI_Monitor
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
            if Monitor and Monitor.monitorFrame and Monitor.monitorFrame:IsShown() then
                Monitor:ShowMonitorWindow(true)
            end
        end
        self:SaveSessionState()
        return
    end

    -- Receiver client does not wipe awarded history on session start (LM side manages lifecycle)

    -- Full session start (or late-joiner receiving heartbeat for the first time)
    local hydratedCount = self:_HydrateSessionItems(newItems, expiry)
    DesolateLootcouncil:DLC_Log("Added " .. hydratedCount .. " items to the session.")

    self:SendMessage("DLC_SESSION_STARTED", self.clientLootList, DesolateLootcouncil:AmIOfficerOrLM())

    -- Apply closed state from heartbeat for late-joiners
    if payload.closedItems then
        self.closedItems = self.closedItems or {}
        for guid, v in pairs(payload.closedItems) do
            self.closedItems[guid] = v
        end
    end

    self.sessionExpiry = expiry
    self:SaveSessionState()
end

function Session:HandleRemoveItem(payload)
    local guid = payload.data and payload.data.guid
    if guid and self.clientLootList then
        for i, item in ipairs(self.clientLootList) do
            if (item.sourceGUID or item.link) == guid then
                table.remove(self.clientLootList, i)
                break
            end
        end

        self:SendMessage("DLC_ITEM_REMOVED", guid)
    end
end

function Session:HandleCloseItem(payload)
    local guid = payload.data and payload.data.guid
    if guid then
        self.closedItems = self.closedItems or {}
        self.closedItems[guid] = true
        DesolateLootcouncil:DLC_Log("Voting closed for item: " .. string.sub(guid, -8))

        self:SendMessage("DLC_ITEM_CLOSED", guid)
    end
end

function Session:HandleHistoryUpdate(payload)
    -- Gate: Only LM or Assists store history. LM already stored it locally during award,
    -- so this handler only inserts it for Assistants who are not LM. Normal Raiders do not store history.
    if not DesolateLootcouncil:AmIOfficerOrLM() then return end

    local data = payload.data
    if data and data.link then
        local session = DesolateLootcouncil.db.profile.session
        if not session.awarded then session.awarded = {} end

        -- Avoid duplicate entries (LM already stored it locally)
        if not DesolateLootcouncil:AmILootMaster() then
            table.insert(session.awarded, {
                link        = data.link,
                texture     = data.texture,
                itemID      = data.itemID,
                winner      = data.winner,
                winnerClass = data.winnerClass,
                voteType    = data.voteType,
                timestamp   = data.timestamp,
                traded      = false
            })

            self:SendMessage("DLC_HISTORY_UPDATED", data)
        end
    end
end

function Session:HandleVote(payload, sender)
    -- Both LM and Assists track the incoming votes directly from the broadcast
    if DesolateLootcouncil:AmIOfficerOrLM() then
        local data = payload.data
        if not data or not data.guid then return end

        self.sessionVotes = self.sessionVotes or {}
        self.sessionVotes[data.guid] = self.sessionVotes[data.guid] or {}

        if data.vote == 0 then
            self.sessionVotes[data.guid][sender] = nil
            DesolateLootcouncil:DLC_Log("Vote retracted by " .. DesolateLootcouncil:GetDisplayName(sender))
        else
            -- Use authoritative roll from sender if available, or fallback to local generation
            local serverRoll = data.roll or math.random(1, 100)
            self.sessionVotes[data.guid][sender] = { type = data.vote, roll = serverRoll, note = data.note or "" }

            -- Only the actual LM is allowed to trigger auto-closes
            if DesolateLootcouncil:AmILootMaster() then
                local voteCount = 0
                for _ in pairs(self.sessionVotes[data.guid]) do voteCount = voteCount + 1 end

                local totalMembers = GetNumGroupMembers()
                if totalMembers == 0 then totalMembers = 1 end

                ---@type Simulation
                local Sim = DesolateLootcouncil:GetModule("Simulation")
                if Sim then totalMembers = totalMembers + Sim:GetCount() end

                if voteCount >= totalMembers then
                    self:SendCloseItem(data.guid)
                end
            end
        end

        self:SaveSessionState()

        -- Auto-update Monitor for tracking (Assist or LM)
        ---@type UI_Monitor
        local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
        if Monitor and Monitor.monitorFrame and Monitor.monitorFrame:IsShown() then
            Monitor:ShowMonitorWindow(true)
        end
        self.sessionPayloadCache = nil -- Invalidate heartbeat cache; item list changed
    end
end

local function HasPlayerVotedInList(votesList, guid, playerScore)
    local guidVotes = votesList and votesList[guid]
    if not guidVotes then return false end
    for voterName in pairs(guidVotes) do
        if DesolateLootcouncil:GetScoreName(voterName) == playerScore then
            return true
        end
    end
    return false
end

function Session:HandleSyncVotes(payload)
    if payload.data and type(payload.data) == "table" then
        self.sessionVotes = payload.data.votes or payload.data -- Compatibility
        self.closedItems  = payload.data.closed or self.closedItems or {}

        local myScore     = DesolateLootcouncil:GetScoreName("player")
        local confirmed   = payload.data.confirmedVoters or {}

        for guid, _ in pairs(self.outboundVotes) do
            local foundInVotes = HasPlayerVotedInList(self.sessionVotes, guid, myScore)
            local foundInConfirmed = not foundInVotes and HasPlayerVotedInList(confirmed, guid, myScore)

            if foundInConfirmed or foundInVotes then
                self.outboundVotes[guid] = nil
            end
        end

        -- Update UI if open
        if DesolateLootcouncil:AmIOfficerOrLM() then
            ---@type UI_Monitor
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
            if Monitor and Monitor.monitorFrame and Monitor.monitorFrame:IsShown() then
                Monitor:ShowMonitorWindow(true)
            end
        end

        -- PROBLEM 13: Refresh Voting UI to clear "Syncing..." status
        ---@type UI_Voting
        local Voting = DesolateLootcouncil:GetModule("UI_Voting")
        if Voting and Voting.votingFrame and Voting.votingFrame:IsShown() then
            Voting:ShowVotingWindow(nil, true)
        end
    end
end

function Session:HandleSyncLM(payload, sender)
    local lm = payload.data and payload.data.lm
    if not lm or not sender then return end

    -- Authority Check: Only accept SYNC_LM from the current Group Leader
    local isAuthorized = false
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name and rank == 2 and DesolateLootcouncil:SmartCompare(name, sender) then
                isAuthorized = true
                break
            end
        end
    elseif IsInGroup() then
        -- In a party, check if the sender is the leader
        isAuthorized = UnitIsGroupLeader(sender)
    else
        -- Solo: accept self-syncs
        isAuthorized = DesolateLootcouncil:SmartCompare(sender, "player")
    end

    if isAuthorized then
        DesolateLootcouncil.activeLootMaster = lm
        DesolateLootcouncil.amILM = DesolateLootcouncil:SmartCompare(lm, "player")
        DesolateLootcouncil:DLC_Log(string.format("Loot Master identity synced from Leader (%s): %s",
            DesolateLootcouncil:GetDisplayName(sender), DesolateLootcouncil:GetDisplayName(lm)))
    else
        DesolateLootcouncil:DLC_Log(string.format("Ignored SYNC_LM from non-leader: %s", tostring(sender)))
    end
end

function Session:OnCommReceived(prefix, message, _distribution, sender)
    if prefix ~= "DLC_Loot" then return end

    local CommMod = DesolateLootcouncil:GetModule("Comm", true)
    if CommMod then
        local currentLM = DesolateLootcouncil:DetermineLootMaster()
        if currentLM and currentLM ~= "" and DesolateLootcouncil:SmartCompare(sender, currentLM) then
            CommMod.lastLMMsgTime = GetServerTime()
        end
    end

    local success, payload = self:Deserialize(message)
    if not success or type(payload) ~= "table" then return end

    if payload.command == "VOTE" then
        local normalizedSender = DesolateLootcouncil:NormalizeName(sender)
        self:HandleVote(payload, normalizedSender)
    elseif payload.command == "SYNC_VOTES" then
        self:HandleSyncVotes(payload)
    elseif payload.command == "REMOVE_ITEM" then
        self:HandleRemoveItem(payload)
    elseif payload.command == "CLOSE_ITEM" then
        self:HandleCloseItem(payload)
    elseif payload.command == "LOOT_SESSION_START" then
        self:HandleStartSession(payload, sender)
    elseif payload.command == "LOOT_SESSION_END" then
        self:EndSession()
    elseif payload.command == "HISTORY_UPDATE" then
        self:HandleHistoryUpdate(payload)
    elseif payload.command == "SYNC_LM" then
        self:HandleSyncLM(payload, sender)
    end
end

function Session:SendSyncLM(targetLM)
    local payload = { command = "SYNC_LM", data = { lm = targetLM } }
    local serialized = self:Serialize(payload)
    local channel = DesolateLootcouncil:GetBroadcastChannel()
    if channel then
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end
end



function Session:SendVote(itemGUID, voteType, note)
    self.myLocalVotes = self.myLocalVotes or {}

    local roll
    if type(self.myLocalVotes[itemGUID]) == "table" and self.myLocalVotes[itemGUID].roll then
        roll = self.myLocalVotes[itemGUID].roll
    else
        roll = math.random(1, 100)
    end

    if voteType == 0 then
        self.myLocalVotes[itemGUID] = nil
    else
        self.myLocalVotes[itemGUID] = { type = voteType, note = note or "", roll = roll }
    end
    self:SaveSessionState()

    -- Instantly Fake the UI update for the raider
    local Voting = DesolateLootcouncil:GetModule("UI_Voting")
    if Voting then Voting:ShowVotingWindow(nil, true) end

    -- Broadcast to RAID channel (Approach B)
    local payload = {
        command = "VOTE",
        data = { guid = itemGUID, vote = voteType, roll = roll, note = note or "" }
    }

    -- Local snap (Monitor/Voting UI consistency)
    -- Normalize local name to ensure consistency with network distribution
    local myName = DesolateLootcouncil:GetFullName("player")
    self:HandleVote(payload, myName)

    local serialized = self:Serialize(payload)
    local channel = DesolateLootcouncil:GetBroadcastChannel()
    if channel then
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end
end

function Session:EndSession()
    self.clientLootList      = {}
    self.sessionVotes        = {}
    self.closedItems         = {}
    self.sessionPayloadCache = nil -- B10: Invalidate cache; session is dead
    wipe(DesolateLootcouncil.db.profile.session.activeState)

    self:SendMessage("DLC_SESSION_STOPPED")

    DesolateLootcouncil:DLC_Log("The Loot Session was ended.", true)
end

function Session:ClearVotes()
    self.sessionVotes = {}
    self.myLocalVotes = {}
    self.closedItems = {}
    wipe(DesolateLootcouncil.db.profile.session.activeState)
    DesolateLootcouncil:DLC_Log("Session data cleared.")
end

function Session:ClaimLMRole()
    if not IsInGroup() then return end
    if not DesolateLootcouncil:AmIOfficerOrLM() then return end
    if DesolateLootcouncil:AmILootMaster() then return end

    DesolateLootcouncil.db.profile.configuredLM = UnitName("player")
    DesolateLootcouncil.activeLootMaster = UnitName("player")
    DesolateLootcouncil.amILM = true
    DesolateLootcouncil.amIOfficer = true

    DesolateLootcouncil:Print("You have claimed the Loot Master role.")

    self:SendSyncLM(UnitName("player"))

    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")

    local RosterSys = DesolateLootcouncil:GetModule("Roster")
    if RosterSys and RosterSys.HasPendingDecay and RosterSys:HasPendingDecay() then
        local db = DesolateLootcouncil.db.profile
        local entry = db.AttendanceHistory[1]
        StaticPopup_Show("DLC_PENDING_DECAY", entry.date or "N/A", entry.zone or "Unknown")
    end
end

function Session:AcceptHandover(silent, continueSession)
    local state = DesolateLootcouncil.pendingHandoverState
    local sender = DesolateLootcouncil.pendingHandoverSender
    if not state or not sender then return end

    if continueSession == nil then
        return
    end

    local db = DesolateLootcouncil.db.profile

    -- Guard: If there is no open loot session in the incoming handover state, and we want to continue, abort.
    if continueSession and (not state.loot or #state.loot == 0) then
        DesolateLootcouncil:DLC_Log("AcceptHandover: Handover payload contains no active session.")
        DesolateLootcouncil.pendingHandoverState = nil
        DesolateLootcouncil.pendingHandoverSender = nil
        Session.pendingHandoverChoice = nil
        return
    end

    db.session = db.session or {}
    db.DecayConfig.sessionActive = state.sessionActive == true
    if continueSession then
        db.session.awarded = state.awarded or {}
        db.session.loot = state.loot or {}
        self.clientLootList = state.loot
        self.sessionVotes = state.votes or {}
        self.closedItems = state.closed or {}
        self.sessionExpiry = state.expiry or 0
        self:SaveSessionState()

        -- Restore Autopass state if continuing
        DesolateLootcouncil.sessionAutopassActive = state.sessionAutopassActive == true
        DesolateLootcouncil.sessionAutopassAnswered = state.sessionAutopassAnswered == true
        db.DecayConfig.sessionAutopassActive = state.sessionAutopassActive == true
        db.DecayConfig.sessionAutopassAnswered = state.sessionAutopassAnswered == true
    else
        self:SendStopSession()
        
        -- Reset Autopass state if starting new session
        DesolateLootcouncil.sessionAutopassActive = false
        DesolateLootcouncil.sessionAutopassAnswered = false
        db.DecayConfig.sessionAutopassActive = false
        db.DecayConfig.sessionAutopassAnswered = false
    end

    local amILeader = DesolateLootcouncil:SmartCompare(DesolateLootcouncil:GetGroupLeader(), "player")
    local isSenderRL = DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:GetGroupLeader())

    local myName = UnitName("player")
    if amILeader or isSenderRL then
        db.configuredLM = ""
    else
        db.configuredLM = myName
    end
    DesolateLootcouncil.activeLootMaster = myName
    DesolateLootcouncil.amILM = true
    DesolateLootcouncil.amIOfficer = true

    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")

    local CommMod = DesolateLootcouncil:GetModule("Comm")
    if CommMod then
        CommMod:SendComm("LM_HANDOVER_ACCEPTED", { newLM = myName, continueSession = continueSession }, sender)
    end

    -- Direct RL Sync Backup: Send configuration update to RL if we are officer accepting
    if not amILeader and not isSenderRL then
        local rl = DesolateLootcouncil:GetGroupLeader()
        if rl and CommMod then
            CommMod:SendComm("LM_UPDATE_CONFIGURED", { configuredLM = myName }, rl)
        end
    end

    self:SendSyncLM(myName)

    if silent then
        if continueSession then
            DesolateLootcouncil:Print(L["Raid leadership received. Loot Master session restored."])
        else
            DesolateLootcouncil:Print(L["Raid leadership received. Started new Loot Master session."])
        end
    else
        if continueSession then
            DesolateLootcouncil:Print(string.format(L["Accepted Loot Master handover from %s (restored session)."], DesolateLootcouncil:GetDisplayName(sender)))
        else
            DesolateLootcouncil:Print(string.format(L["Accepted Loot Master handover from %s (started new session)."], DesolateLootcouncil:GetDisplayName(sender)))
        end
    end

    -- Pull updates immediately after accepting handover if incoming timestamps are newer
    if CommMod then
        -- Check Roster
        local localRosterTs = db.rosterTimestamp or 0
        local incomingRosterTs = state.rosterTimestamp or 0
        if incomingRosterTs > localRosterTs then
            CommMod:SendComm("ROSTER_PULL_REQUEST", {}, sender)
        end
        -- Check Priority Lists
        if state.priorityTimestamps then
            db.priorityTimestamps = db.priorityTimestamps or {}
            for listName, incomingTs in pairs(state.priorityTimestamps) do
                local localTs = db.priorityTimestamps[listName] or 0
                if incomingTs > localTs then
                    CommMod:SendComm("PRIORITY_PULL_REQUEST", { listName = listName }, sender)
                end
            end
        end
        -- Check IM lists
        if state.imTimestamps then
            db.imTimestamps = db.imTimestamps or {}
            for listName, incomingTs in pairs(state.imTimestamps) do
                local localTs = db.imTimestamps[listName] or 0
                if incomingTs > localTs then
                    CommMod:SendComm("IM_PULL_REQUEST", { listName = listName }, sender)
                end
            end
        end
        -- Check Config
        local localConfigTs = db.configTimestamp or 0
        local incomingConfigTs = state.configTimestamp or 0
        if incomingConfigTs > localConfigTs then
            CommMod:SendComm("CONFIG_PULL_REQUEST", {}, sender)
        end
        -- Check History
        local localHistoryTs = db.historyTimestamp or 0
        local incomingHistoryTs = state.historyTimestamp or 0
        if incomingHistoryTs > localHistoryTs then
            CommMod:SendComm("HISTORY_PULL_REQUEST", {}, sender)
        end
    end

    DesolateLootcouncil.pendingHandoverState = nil
    DesolateLootcouncil.pendingHandoverSender = nil
    Session.pendingHandoverChoice = nil

    -- Re-evaluate status to reflect roles and layout changes
    DesolateLootcouncil:UpdateLootMasterStatus()

    -- Reprompt for Autopass if starting new session
    if not continueSession and db.DecayConfig.sessionActive then
        StaticPopup_Show("DLC_ENABLE_AUTOPASS")
    end

    local RosterSys = DesolateLootcouncil:GetModule("Roster")
    if RosterSys and RosterSys.HasPendingDecay and RosterSys:HasPendingDecay() then
        local entry = db.AttendanceHistory[1]
        StaticPopup_Show("DLC_PENDING_DECAY", entry.date or "N/A", entry.zone or "Unknown")
    end

    if continueSession then
        self:SendMessage("DLC_SESSION_RESTORED", self.clientLootList, DesolateLootcouncil:AmIOfficerOrLM())
    end
end

function Session:DeclineHandover()
    local sender = DesolateLootcouncil.pendingHandoverSender
    if sender then
        local CommMod = DesolateLootcouncil:GetModule("Comm")
        if CommMod then
            CommMod:SendComm("LM_HANDOVER_DECLINED", { reason = "declined" }, sender)
        end
        DesolateLootcouncil:Print(string.format(L["Declined Loot Master handover from %s."], DesolateLootcouncil:GetDisplayName(sender)))
    end
    DesolateLootcouncil.pendingHandoverState = nil
    DesolateLootcouncil.pendingHandoverSender = nil
    Session.pendingHandoverChoice = nil
    DesolateLootcouncil:UpdateLootMasterStatus()
end

local function SafePromoteToLeader(name)
    if not name then return end
    local cleanName = Ambiguate(name, "none")
    PromoteToLeader(cleanName)
end

function Session:HandleHandoverAccepted(sender)
    if not DesolateLootcouncil.pendingHandoverTarget or not DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil.pendingHandoverTarget) then
        return
    end

    local newLM = sender
    local db = DesolateLootcouncil.db.profile
    db.configuredLM = newLM
    DesolateLootcouncil.activeLootMaster = newLM
    DesolateLootcouncil.amILM = false
    DesolateLootcouncil.amIOfficer = DesolateLootcouncil:AmIOfficerOrLM()

    DesolateLootcouncil:Print(string.format("Handover accepted by %s. You are no longer the Loot Master.", newLM))

    local amILeader = DesolateLootcouncil:SmartCompare(DesolateLootcouncil:GetGroupLeader(), "player")
    if amILeader then
        SafePromoteToLeader(newLM)
    else
        local rl = DesolateLootcouncil:GetGroupLeader()
        if rl and not DesolateLootcouncil:SmartCompare(rl, "player") then
            local CommMod = DesolateLootcouncil:GetModule("Comm")
            if CommMod then
                CommMod:SendComm("LM_UPDATE_CONFIGURED", { configuredLM = newLM }, rl)
            end
        end
    end

    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor", true)
    if Monitor and Monitor.CloseMasterLootWindow then
        Monitor:CloseMasterLootWindow()
    end

    DesolateLootcouncil.pendingHandoverTarget = nil
    local CommMod = DesolateLootcouncil:GetModule("Comm", true)
    if CommMod and CommMod.handoverTimeoutTimer then
        CommMod:CancelTimer(CommMod.handoverTimeoutTimer)
        CommMod.handoverTimeoutTimer = nil
    end
    local SyncMod = DesolateLootcouncil:GetModule("Sync", true)
    if SyncMod and SyncMod.handoverTimeoutTimer then
        SyncMod:CancelTimer(SyncMod.handoverTimeoutTimer)
        SyncMod.handoverTimeoutTimer = nil
    end

    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Session:HandleHandoverDeclined(sender)
    if not DesolateLootcouncil.pendingHandoverTarget or not DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil.pendingHandoverTarget) then
        return
    end

    DesolateLootcouncil:Print(string.format("Handover declined by %s.", sender))
    DesolateLootcouncil.pendingHandoverTarget = nil
    local CommMod = DesolateLootcouncil:GetModule("Comm", true)
    if CommMod and CommMod.handoverTimeoutTimer then
        CommMod:CancelTimer(CommMod.handoverTimeoutTimer)
        CommMod.handoverTimeoutTimer = nil
    end
    local SyncMod = DesolateLootcouncil:GetModule("Sync", true)
    if SyncMod and SyncMod.handoverTimeoutTimer then
        SyncMod:CancelTimer(SyncMod.handoverTimeoutTimer)
        SyncMod.handoverTimeoutTimer = nil
    end
end

function Session:HandleUpdateConfigured(payload, sender)
    local amILeader = DesolateLootcouncil:SmartCompare(DesolateLootcouncil:GetGroupLeader(), "player")
    if not amILeader then return end

    -- SECURE SENDER CHECK: Only accept LM configuration updates from the current active LM!
    local currentLM = DesolateLootcouncil.activeLootMaster
    if not DesolateLootcouncil:SmartCompare(sender, currentLM) then
        DesolateLootcouncil:DLC_Log(string.format("Ignored LM_UPDATE_CONFIGURED from unauthorized sender: %s", tostring(sender)))
        return
    end

    local newLM = payload.configuredLM
    if newLM and newLM ~= "" then
        DesolateLootcouncil.db.profile.configuredLM = newLM
        DesolateLootcouncil.activeLootMaster = newLM
        DesolateLootcouncil:UpdateLootMasterStatus()
        DesolateLootcouncil:Print(string.format("Configured Loot Master updated to %s by request from previous LM.", newLM))
    end
end
