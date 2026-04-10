local _, AT = ...
if AT.abortLoad then return end

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
---@field AmIRaidAssistOrLM fun(self: any): boolean
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
end

function Session:OnTimerTick()
    -- Approach B: No client polling/batching queues needed!
    -- Session Heartbeat & Full Sync (Late Joiners & Consistency) — LM only
    local now = GetServerTime()
    if DesolateLootcouncil:AmILootMaster() and self.clientLootList and #self.clientLootList > 0 then
        -- Item-list Heartbeat (every 30s — late joiners & reloaders)
        if now - self.lastHeartbeat > 30 then
            self.lastHeartbeat = now
            self:SendSessionHeartbeat()
        end
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
            command     = "LOOT_SESSION_START",
            data        = payloadData,
            duration    = self.sessionDuration or 300,
            endTime     = self.sessionExpiry,
            closedItems = self.closedItems,
            votes       = self.sessionVotes,
            isHeartbeat = true
        }
        self.sessionPayloadCache = self:Serialize(payload)
        DesolateLootcouncil:DLC_Log("Session Heartbeat: rebuilt payload cache.")
    else
        DesolateLootcouncil:DLC_Log("Session Heartbeat: using cached payload.")
    end

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if channel then
        self:SendCommMessage("DLC_Loot", self.sessionPayloadCache, channel)
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

        if state.activeLM and state.activeLM ~= "" then
            DesolateLootcouncil.activeLootMaster = state.activeLM
            DesolateLootcouncil.amILM = DesolateLootcouncil:SmartCompare(state.activeLM, "player")
        end

        local isLM = DesolateLootcouncil:SmartCompare(state.activeLM, "player")

        if not isLM and isExpiredOver12h then
            DesolateLootcouncil:DLC_Log("Session > 12h old. Auto-closing for non-LM.")
            wipe(session.activeState)
            ---@type UI_Voting
            local UI = DesolateLootcouncil:GetModule("UI_Voting")
            if UI and UI.ResetVoting then UI:ResetVoting() end
            return
        end

        if isLM then
            local decayConfig = DesolateLootcouncil.db.profile.DecayConfig
            local inactiveFor1h = decayConfig and decayConfig.lastActivity and (now - decayConfig.lastActivity > 3600)
            local notInGroup = not IsInGroup()

            if isExpiredOver12h or (inactiveFor1h and notInGroup) then
                StaticPopupDialogs["DLC_CLOSE_SESSION"] = {
                    text = "A previous Loot Session is still active. Do you want to close it?",
                    button1 = "Yes (Close Session)",
                    button2 = "No (Keep Active)",
                    OnAccept = function()
                        self:SendStopSession()
                    end,
                    OnCancel = function()
                        self:PerformRestore(state, now, expiry)
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
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

        if state.activeLM and state.activeLM ~= "" then
            DesolateLootcouncil.activeLootMaster = state.activeLM
            DesolateLootcouncil.amILM = DesolateLootcouncil:SmartCompare(state.activeLM, "player")
        end

        DesolateLootcouncil:DLC_Log("Restored active session (" ..
            #self.clientLootList .. " items, LM: " .. DesolateLootcouncil:GetDisplayName(state.activeLM or "?") .. ").")

        ---@type UI_Voting
        local UI = DesolateLootcouncil:GetModule("UI_Voting")
        if UI then
            UI:ShowVotingWindow(self.clientLootList)
            -- Show Monitor for LM and Assists
            if DesolateLootcouncil:AmIRaidAssistOrLM() then
                ---@type UI_Monitor
                local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
                if Monitor then Monitor:ShowMonitorWindow(true) end
            end
        end
    else
        -- Scenario B: Expired
        DesolateLootcouncil:DLC_Log("Session expired while offline.")
        wipe(session.activeState)
        ---@type UI_Voting
        local UI = DesolateLootcouncil:GetModule("UI_Voting")
        if UI and UI.ResetVoting then UI:ResetVoting() end
    end
end

function Session:StartSession(lootTable)
    if not DesolateLootcouncil:AmILootMaster() then return end

    if not lootTable or #lootTable == 0 then
        DesolateLootcouncil:DLC_Log("No items to distribute!")
        return
    end

    local session = DesolateLootcouncil.db.profile.session
    -- 1. Migrate Data (Deep Copy to Bidding Storage)
    local cleanList = {}
    local itemCount = 0

    for _, item in ipairs(lootTable) do
        if item.category ~= "Junk/Pass" then
            table.insert(cleanList, {
                link = item.link,
                itemID = item.itemID,
                texture = item.texture,
                category = item.category,
                sourceGUID = item.sourceGUID,
                stackIndex = item.stackIndex
            })
            itemCount = itemCount + 1
        end
    end

    ---@type Loot
    local Loot = DesolateLootcouncil:GetModule("Loot")
    ---@type UI_Loot
    local UI = DesolateLootcouncil:GetModule("UI_Loot")

    if itemCount == 0 then
        Loot:ClearLootBacklog()
        if UI and UI.lootFrame then UI.lootFrame:Hide() end
        DesolateLootcouncil:DLC_Log("Session contained only junk. Loot cleared locally; no broadcast sent.")
        return
    end

    -- Copy clean list to persistent storage
    local duration = DesolateLootcouncil.db.profile.sessionDuration or 300
    local endTime = GetServerTime() + duration
    self.sessionDuration = duration
    self.sessionExpiry = endTime

    for _, item in ipairs(cleanList) do
        item.expiry = endTime -- Per-item expiry (Absolute)
        table.insert(session.bidding, item)
    end

    -- Invalidate heartbeat cache; the item list just changed.
    self.sessionPayloadCache = nil

    DesolateLootcouncil:DLC_Log("Loot moved to Bidding Storage. Collection cleared.")

    -- 2. Clear Collection (Wipe session.loot so we can keep looting new mobs)
    Loot:ClearLootBacklog()
    if UI and UI.lootFrame then UI.lootFrame:Hide() end

    -- 3. Prepare Payload (ONLY NEW ITEMS)
    local payloadData = {}
    for _, item in ipairs(cleanList) do
        table.insert(payloadData, {
            link = item.link,
            texture = item.texture,
            itemID = item.itemID,
            sourceGUID = item.sourceGUID,
            category = item.category -- Required for dynamic button generation
        })
    end

    -- 4. Serialize
    local payload = {
        command = "LOOT_SESSION_START",
        data = payloadData,
        duration = duration,
        endTime = endTime
    }
    local serialized = self:Serialize(payload)

    DesolateLootcouncil:DLC_Log("Sent packet size: " .. #serialized .. " bytes")

    -- 5. Broadcasting
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")

    if not channel then
        channel = "WHISPER"
        DesolateLootcouncil:DLC_Log("Not in group, simulating broadcast to self.")

        -- Ensure the Comm module knows about "Self" even if we skipped a Version Check
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

    -- Re-broadcast Item Manager & Autopass State to ensure all raiders have it active
    local Comm = DesolateLootcouncil:GetModule("Comm")
    if Comm then
        if DesolateLootcouncil.sessionAutopassActive ~= nil then
            Comm:SendSyncAutopass(DesolateLootcouncil.sessionAutopassActive)
        end
        -- IM_SYNC broadcast removed. Priority lists now strictly sync on manual button press.
    end

    -- Open Monitor Window for LM
    -- Note: Do NOT wrap in pcall — silent failure is worse than a visible error here.
    ---@type UI_Monitor
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
    if Monitor then Monitor:ShowMonitorWindow() end

    -- Trigger Refresh if Voting Window is open (for overlapping sessions)
    ---@type UI_Voting
    local Voting = DesolateLootcouncil:GetModule("UI_Voting")
    if Voting then Voting:ShowVotingWindow(cleanList) end
end

function Session:SendStopSession()
    DesolateLootcouncil:DLC_Log("[DEBUG] SendStopSession Trace Start")
    -- 1. Broadcast "LOOT_SESSION_END"
    local payload = { command = "LOOT_SESSION_END" }
    local serialized = self:Serialize(payload)

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
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

    -- 3. Close Monitor
    ---@type UI_Monitor
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
    if Monitor and Monitor.monitorFrame then Monitor.monitorFrame:Hide() end

    ---@type UI_Voting
    local Voting = DesolateLootcouncil:GetModule("UI_Voting")
    if Voting and Voting.ResetVoting then Voting:ResetVoting() end

    -- Clear Saved State
    wipe(DesolateLootcouncil.db.profile.session.activeState)

    DesolateLootcouncil:DLC_Log("Session Stopped. Broadcast sent.")
end

function Session:SendCloseItem(itemGUID)
    -- 1. Broadcast to Raid
    local payload = { command = "CLOSE_ITEM", data = { guid = itemGUID } }
    local serialized = self:Serialize(payload)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if not channel then
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end

    -- 2. Local Instant Update (Fix "Everyone Voted" lag)
    self.closedItems = self.closedItems or {}
    self.closedItems[itemGUID] = true
    self:SaveSessionState()

    ---@type UI_Voting
    local Voting = DesolateLootcouncil:GetModule("UI_Voting")
    if Voting and Voting.votingFrame and Voting.votingFrame:IsShown() and Voting.ShowVotingWindow then
        Voting:ShowVotingWindow(nil, true)
    end

    DesolateLootcouncil:DLC_Log("Voting closed for item: " .. string.sub(itemGUID, -8))
    self.sessionPayloadCache = nil -- Invalidate heartbeat cache; closed state changed
end

function Session:SendRemoveItem(guid)
    local payload = { command = "REMOVE_ITEM", data = { guid = guid } }
    local serialized = self:Serialize(payload)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if not channel then
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end
end

-- Bug 4: Broadcast an awarded history entry to all players
function Session:SendHistoryUpdate(entry)
    -- Avoid serializing fullItemData (too large/circular refs); only send display fields
    local safeEntry = {
        link        = entry.link,
        texture     = entry.texture,
        itemID      = entry.itemID,
        winner      = entry.winner,
        winnerClass = entry.winnerClass,
        voteType    = entry.voteType,
        timestamp   = entry.timestamp,
    }
    local payload = { command = "HISTORY_UPDATE", data = safeEntry }
    local serialized = self:Serialize(payload)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if channel then
        self:SendCommMessage("DLC_Loot", serialized, channel)
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
    ---@type UI_Monitor
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
    if Monitor and Monitor.ShowMonitorWindow and Monitor.monitorFrame and Monitor.monitorFrame:IsShown() then
        Monitor:ShowMonitorWindow(true)
    end

    -- 5. Refresh Trade List (if open)
    ---@type UI_TradeList
    local TradeListUI = DesolateLootcouncil:GetModule("UI_TradeList")
    if TradeListUI and TradeListUI.ShowTradeListWindow and TradeListUI.tradeListFrame and TradeListUI.tradeListFrame:IsShown() then
        TradeListUI:ShowTradeListWindow()
    end

    DesolateLootcouncil:DLC_Log("Removed item from session and pending trades.")
end

function Session:HandleStartSession(payload)
    local newItems = payload.data
    local count = newItems and #newItems or 0
    local duration = payload.duration or 300
    local expiry = payload.endTime or (GetServerTime() + duration)
    local isHeartbeat = payload.isHeartbeat == true

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
        if payload.votes and DesolateLootcouncil:AmIRaidAssistOrLM() then
            self.sessionVotes = self.sessionVotes or {}
            for guid, players in pairs(payload.votes) do
                self.sessionVotes[guid] = self.sessionVotes[guid] or {}
                for player, voteData in pairs(players) do
                    self.sessionVotes[guid][player] = voteData
                end
            end
        end
        if DesolateLootcouncil:AmIRaidAssistOrLM() then
            ---@type UI_Monitor
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
            if Monitor and Monitor.monitorFrame and Monitor.monitorFrame:IsShown() then
                Monitor:ShowMonitorWindow(true)
            end
        end
        self:SaveSessionState()
        return
    end

    -- Full session start (or late-joiner receiving heartbeat for the first time)
    if newItems then
        for _, item in ipairs(newItems) do
            item.expiry = expiry
            -- Avoid duplicates when reconnecting mid-session
            local alreadyHave = false
            for _, existing in ipairs(self.clientLootList) do
                if (existing.sourceGUID or existing.link) == (item.sourceGUID or item.link) then
                    alreadyHave = true
                    break
                end
            end
            if not alreadyHave then
                table.insert(self.clientLootList, item)
            end
        end
    end

    DesolateLootcouncil:DLC_Log("Added " .. count .. " items to the session.")

    ---@type UI_Voting
    local Voting = DesolateLootcouncil:GetModule("UI_Voting")
    if Voting then Voting:ShowVotingWindow(self.clientLootList) end

    -- Restricted auto-pop to LM only
    if DesolateLootcouncil:AmILootMaster() then
        ---@type UI_Monitor
        local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
        if Monitor then Monitor:ShowMonitorWindow() end
    end

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

        ---@type UI_Voting
        local Voting = DesolateLootcouncil:GetModule("UI_Voting")
        if Voting and Voting.votingFrame and Voting.votingFrame:IsShown() then
            if Voting.RemoveVotingItem then
                Voting:RemoveVotingItem(guid)
            else
                Voting:ShowVotingWindow(self.clientLootList, true)
            end
        end

        if DesolateLootcouncil:AmIRaidAssistOrLM() then
            ---@type UI_Monitor
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
            if Monitor and Monitor.monitorFrame and Monitor.monitorFrame:IsShown() then
                Monitor:ShowMonitorWindow(true)
            end
        end
    end
end

function Session:HandleCloseItem(payload)
    local guid = payload.data and payload.data.guid
    if guid then
        self.closedItems = self.closedItems or {}
        self.closedItems[guid] = true
        DesolateLootcouncil:DLC_Log("Voting closed for item: " .. string.sub(guid, -8))

        ---@type UI_Voting
        local Voting = DesolateLootcouncil:GetModule("UI_Voting")
        if Voting and Voting.votingFrame and Voting.votingFrame:IsShown() and Voting.ShowVotingWindow then
            Voting:ShowVotingWindow(nil, true)
        end

        if DesolateLootcouncil:AmIRaidAssistOrLM() then
            ---@type UI_Monitor
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
            if Monitor and Monitor.monitorFrame and Monitor.monitorFrame:IsShown() then
                Monitor:ShowMonitorWindow(true)
            end
        end
    end
end

function Session:HandleHistoryUpdate(payload)
    -- Bug 4: All players (not just LM) store the history entry
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

            -- Auto-refresh History window if open
            local UI_H = DesolateLootcouncil:GetModule("UI_History")
            if UI_H and UI_H.historyFrame and UI_H.historyFrame.frame and UI_H.historyFrame.frame:IsShown() then
                UI_H:ShowHistoryWindow()
            end
        end
    end
end

function Session:HandleVote(payload, sender)
    -- Both LM and Assists track the incoming votes directly from the broadcast
    if DesolateLootcouncil:AmIRaidAssistOrLM() then
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
            self.sessionVotes[data.guid][sender] = { type = data.vote, roll = serverRoll }

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

function Session:HandleSyncVotes(payload)
    if payload.data and type(payload.data) == "table" then
        self.sessionVotes = payload.data.votes or payload.data -- Compatibility
        self.closedItems  = payload.data.closed or self.closedItems or {}

        local myScore = DesolateLootcouncil:GetScoreName("player")
        local confirmed = payload.data.confirmedVoters or {}

        for guid, _ in pairs(self.outboundVotes) do
            local foundInVotes = false
            if self.sessionVotes[guid] then
                for voterName in pairs(self.sessionVotes[guid]) do
                    if DesolateLootcouncil:GetScoreName(voterName) == myScore then
                        foundInVotes = true
                        break
                    end
                end
            end

            local foundInConfirmed = false
            if not foundInVotes and confirmed[guid] then
                for voterName in pairs(confirmed[guid]) do
                    if DesolateLootcouncil:GetScoreName(voterName) == myScore then
                        foundInConfirmed = true
                        break
                    end
                end
            end

            if foundInConfirmed or foundInVotes then
                self.outboundVotes[guid] = nil
            end
        end

        -- Update UI if open
        if DesolateLootcouncil:AmIRaidAssistOrLM() then
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

function Session:HandleSyncLM(payload)
    local lm = payload.data and payload.data.lm
    if lm then
        DesolateLootcouncil.activeLootMaster = lm
        DesolateLootcouncil.amILM = DesolateLootcouncil:SmartCompare(lm, "player")
    end
end

function Session:OnCommReceived(prefix, message, _distribution, sender)
    if prefix ~= "DLC_Loot" then return end

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
        self:HandleStartSession(payload)
    elseif payload.command == "LOOT_SESSION_END" then
        self:EndSession()
    elseif payload.command == "HISTORY_UPDATE" then
        self:HandleHistoryUpdate(payload)
    elseif payload.command == "SYNC_LM" then
        self:HandleSyncLM(payload)
    end
end

function Session:SendSyncLM(targetLM)
    local payload = { command = "SYNC_LM", data = { lm = targetLM } }
    local serialized = self:Serialize(payload)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if channel then
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end
end

function Session:SendSyncVotes()
    -- This function is no longer required due to Approach B's pub/sub architecture.
    -- Use SendSessionHeartbeat() for full state resync instead.
end

function Session:SendVote(itemGUID, voteType)
    self.myLocalVotes = self.myLocalVotes or {}

    if voteType == 0 then
        self.myLocalVotes[itemGUID] = nil
    else
        self.myLocalVotes[itemGUID] = voteType
    end
    self:SaveSessionState()

    -- Instantly Fake the UI update for the raider
    local Voting = DesolateLootcouncil:GetModule("UI_Voting")
    if Voting then Voting:ShowVotingWindow(nil, true) end

    -- Broadcast to RAID channel (Approach B)
    local roll = math.random(1, 100)
    local payload = {
        command = "VOTE",
        data = { guid = itemGUID, vote = voteType, roll = roll }
    }

    -- Local snap (Monitor/Voting UI consistency)
    -- Normalize local name to ensure consistency with network distribution
    local myName = DesolateLootcouncil:GetFullName("player")
    self:HandleVote(payload, myName)

    local serialized = self:Serialize(payload)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
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

    ---@type UI_Voting
    local Voting = DesolateLootcouncil:GetModule("UI_Voting")
    if Voting then
        if Voting.ResetVoting then Voting:ResetVoting() end
        if Voting.votingFrame then Voting.votingFrame:Hide() end
    end

    -- Close the monitor window properly for assistants (Follow-up Fix)
    ---@type UI_Monitor
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
    if Monitor and Monitor.monitorFrame then Monitor.monitorFrame:Hide() end

    DesolateLootcouncil:DLC_Log("The Loot Session was ended.", true)
end

function Session:ClearVotes()
    self.sessionVotes = {}
    self.myLocalVotes = {}
    self.closedItems = {}
    wipe(DesolateLootcouncil.db.profile.session.activeState)
    DesolateLootcouncil:DLC_Log("Session data cleared.")
end
