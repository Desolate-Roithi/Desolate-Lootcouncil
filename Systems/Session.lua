---@class Session : AceModule, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0, AceConsole-3.0
local Session = DesolateLootcouncil:NewModule("Session", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0",
    "AceConsole-3.0")

---@class (partial) DLC_Ref_Session
---@field db table
---@field DetermineLootMaster fun(self: any): string
---@field AmILootMaster fun(self: any): boolean
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field GetModule fun(self: any, name: string): any
---@field GetEnchantingSkillLevel fun(self: any): number
---@field activeLootMaster string
---@field amILM boolean

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
end

function Session:SaveSessionState()
    local session = DesolateLootcouncil.db.profile.session
    session.activeState = {
        lootList = self.clientLootList,
        votes = self.sessionVotes,
        myVotes = self.myLocalVotes,
        closed = self.closedItems,
        expiry = self.sessionExpiry -- Absolute timestamp
    }
end

function Session:RestoreSession()
    local session = DesolateLootcouncil.db.profile.session
    local state = session.activeState

    if state and state.lootList and #state.lootList > 0 then
        local now = GetServerTime()
        local expiry = state.expiry or 0

        if now < expiry then
            -- Scenario A: Active
            self.clientLootList = state.lootList
            self.sessionVotes = state.votes or {}
            self.myLocalVotes = state.myVotes or {}
            self.closedItems = state.closed or {}
            self.sessionExpiry = expiry

            DesolateLootcouncil:DLC_Log("Restored active session (" .. #self.clientLootList .. " items).")

            -- Re-open UI
            ---@type UI_Voting
            local UI = DesolateLootcouncil:GetModule("UI_Voting")
            if UI then
                UI:ShowVotingWindow(self.clientLootList)
                -- If LM, show Monitor
                if DesolateLootcouncil:AmILootMaster() then
                    ---@type UI_Monitor
                    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
                    if Monitor then Monitor:ShowMonitorWindow() end
                end
            end
        else
            -- Scenario B: Expired
            DesolateLootcouncil:DLC_Log("Session expired while offline.")
            wipe(session.activeState) -- Clear
            -- Clean UI
            ---@type UI_Voting
            local UI = DesolateLootcouncil:GetModule("UI_Voting")
            if UI and UI.ResetVoting then UI:ResetVoting() end
        end
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
    for _, item in ipairs(cleanList) do
        item.expiry = endTime -- Per-item expiry (Absolute)
        table.insert(session.bidding, item)
    end

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
        command = "START_SESSION",
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

    -- Open Monitor Window for LM
    ---@type UI_Monitor
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
    if Monitor then Monitor:ShowMonitorWindow() end

    -- Trigger Refresh if Voting Window is open (for overlapping sessions)
    ---@type UI_Voting
    local Voting = DesolateLootcouncil:GetModule("UI_Voting")
    if Voting then Voting:ShowVotingWindow(session.bidding) end
end

function Session:SendStopSession()
    -- 1. Broadcast "STOP_SESSION"
    local payload = { command = "STOP_SESSION" }
    local serialized = self:Serialize(payload)

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if not channel then
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end

    -- 2. Local Cleanup (LM Side)
    self.sessionVotes = {}
    self.closedItems = {}
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
    if Voting and Voting.ShowVotingWindow then
        Voting:ShowVotingWindow(nil, true)
    end

    DesolateLootcouncil:DLC_Log("Voting closed for item: " .. string.sub(itemGUID, -8))
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

function Session:RemoveSessionItem(guid)
    -- 1. Tell clients to REMOVE the item (not just close)
    self:SendRemoveItem(guid)

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

    -- 3. Refresh Monitor
    ---@type UI_Monitor
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
    if Monitor and Monitor.ShowMonitorWindow then Monitor:ShowMonitorWindow() end

    DesolateLootcouncil:DLC_Log("Removed item from session.")
end

function Session:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= "DLC_Loot" then return end

    local success, payload = self:Deserialize(message)
    if not success then return end

    ---@cast payload DistributionPayload

    if payload.command == "START_SESSION" then
        local newItems = payload.data
        local count = newItems and #newItems or 0
        local duration = payload.duration or 300
        local expiry = payload.endTime or (GetServerTime() + duration)

        self.clientLootList = self.clientLootList or {}
        self.myLocalVotes = {}

        if newItems then
            for _, item in ipairs(newItems) do
                item.expiry = expiry
                table.insert(self.clientLootList, item)
            end
        end

        DesolateLootcouncil:DLC_Log("Added " .. count .. " items to the session.")

        ---@type UI_Voting
        local Voting = DesolateLootcouncil:GetModule("UI_Voting")
        if Voting then Voting:ShowVotingWindow(self.clientLootList) end

        self.sessionExpiry = expiry
        self:SaveSessionState()
    elseif payload.command == "STOP_SESSION" then
        self:EndSession()
    elseif payload.command == "REMOVE_ITEM" then
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
            if Voting then
                if Voting.RemoveVotingItem then
                    Voting:RemoveVotingItem(guid)
                else
                    Voting:ShowVotingWindow(self.clientLootList, true)
                end
            end
        end
    elseif payload.command == "CLOSE_ITEM" then
        local guid = payload.data and payload.data.guid
        if guid then
            self.closedItems = self.closedItems or {}
            self.closedItems[guid] = true
            DesolateLootcouncil:DLC_Log("Voting closed for item: " .. string.sub(guid, -8))

            ---@type UI_Voting
            local Voting = DesolateLootcouncil:GetModule("UI_Voting")
            if Voting and Voting.ShowVotingWindow then
                Voting:ShowVotingWindow(nil, true)
            end
        end
    elseif payload.command == "VOTE" then
        local myName = UnitName("player")
        if DesolateLootcouncil:DetermineLootMaster() == myName then
            local data = payload.data
            self.sessionVotes = self.sessionVotes or {}
            self.sessionVotes[data.guid] = self.sessionVotes[data.guid] or {}

            if data.vote == 0 then
                self.sessionVotes[data.guid][sender] = nil
                DesolateLootcouncil:DLC_Log("Vote retracted by " .. sender)
            else
                local serverRoll = math.random(1, 100)
                self.sessionVotes[data.guid][sender] = { type = data.vote, roll = serverRoll }

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

            ---@type UI_Monitor
            local Monitor = DesolateLootcouncil:GetModule("UI_Monitor")
            if Monitor then Monitor:ShowMonitorWindow() end

            self:SaveSessionState()
        end
    elseif payload.command == "SYNC_LM" then
        local lm = payload.data and payload.data.lm
        if lm then
            DesolateLootcouncil.activeLootMaster = lm
            DesolateLootcouncil.amILM = (lm == UnitName("player"))
        end
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

function Session:SendVote(itemGUID, voteType)
    local payload = {
        command = "VOTE",
        data = { guid = itemGUID, vote = voteType }
    }
    local serialized = self:Serialize(payload)
    local target = DesolateLootcouncil:DetermineLootMaster()

    self.myLocalVotes = self.myLocalVotes or {}
    if voteType == 0 then
        self.myLocalVotes[itemGUID] = nil
    else
        self.myLocalVotes[itemGUID] = voteType
    end
    self:SaveSessionState()

    if target and target ~= "Unknown" then
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", target)
    else
        DesolateLootcouncil:DLC_Log("Error: Could not determine Loot Master to vote.")
    end
end

function Session:EndSession()
    self.clientLootList = {}
    self.sessionVotes = {}
    wipe(DesolateLootcouncil.db.profile.session.activeState)

    ---@type UI_Voting
    local Voting = DesolateLootcouncil:GetModule("UI_Voting")
    if Voting then
        if Voting.ResetVoting then Voting:ResetVoting() end
        if Voting.votingFrame then Voting.votingFrame:Hide() end
    end
    DesolateLootcouncil:DLC_Log("The Loot Session was ended.", true)
end

function Session:ClearVotes()
    self.sessionVotes = {}
    self.myLocalVotes = {}
    self.closedItems = {}
    wipe(DesolateLootcouncil.db.profile.session.activeState)
    DesolateLootcouncil:DLC_Log("Session data cleared.")
end
