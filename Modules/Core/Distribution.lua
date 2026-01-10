---@class Distribution : AceModule, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0, AceConsole-3.0
---@field StartSession fun(self: Distribution, lootTable: table)
---@field SendStopSession fun(self: Distribution)
---@field SendCloseItem fun(self: Distribution, itemGUID: string)
---@field SendRemoveItem fun(self: Distribution, guid: string)
---@field RemoveSessionItem fun(self: Distribution, guid: string)
---@field OnCommReceived fun(self: Distribution, prefix: string, message: string, distribution: string, sender: string)
---@field SendSyncLM fun(self: Distribution, targetLM: string)
---@field SendVote fun(self: Distribution, itemGUID: string, voteType: any)
---@field ClearVotes fun(self: Distribution)
---@field OnEnable fun(self: Distribution)
---@field ResetVoting fun(self: Distribution)
---@field sessionExpiry number?
---@field sessionVotes table
---@field myLocalVotes table
---@field clientLootList table
---@field closedItems table
---@field SaveSessionState fun(self: Distribution)
---@field RestoreSession fun(self: Distribution)

---@class (partial) DLC_Ref_Distribution
---@field db table
---@field NewModule fun(self: DLC_Ref_Distribution, name: string, ...): any
---@field AmILootMaster fun(self: DLC_Ref_Distribution): boolean
---@field Print fun(self: DLC_Ref_Distribution, msg: string)
---@field GetModule fun(self: DLC_Ref_Distribution, name: string): any
---@field DetermineLootMaster fun(self: DLC_Ref_Distribution): string
---@field activeAddonUsers table
---@field activeLootMaster string
---@field amILM boolean

---@type DLC_Ref_Distribution
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Distribution]]
local Dist = DesolateLootcouncil:NewModule("Distribution", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0",
    "AceConsole-3.0") --[[@as Distribution]]

---@class DistributionPayload
---@field command string
---@field data table
---@field duration number?
---@field endTime number?

function Dist:OnEnable()
    self:RegisterComm("DLC_Loot", "OnCommReceived")
    -- Attempt Rehydration
    C_Timer.After(1, function() self:RestoreSession() end)
end

function Dist:SaveSessionState()
    local session = DesolateLootcouncil.db.profile.session
    session.activeState = {
        lootList = self.clientLootList,
        votes = self.sessionVotes,
        myVotes = self.myLocalVotes,
        closed = self.closedItems,
        expiry = self.sessionExpiry -- Absolute timestamp
    }
end

function Dist:RestoreSession()
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
            ---@type UI
            local UI = DesolateLootcouncil:GetModule("UI")
            if UI then
                UI:ShowVotingWindow(self.clientLootList)
                -- If LM, show Monitor
                if DesolateLootcouncil:AmILootMaster() then
                    UI:ShowMonitorWindow()
                end
            end
        else
            -- Scenario B: Expired
            DesolateLootcouncil:DLC_Log("Session expired while offline.")
            wipe(session.activeState) -- Clear
            -- Clean UI
            ---@type UI
            local UI = DesolateLootcouncil:GetModule("UI")
            if UI and UI.ResetVoting then UI:ResetVoting() end
        end
    end
end

function Dist:StartSession(lootTable)
    if not DesolateLootcouncil:AmILootMaster() then
        return -- Silent fail or print error
    end

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
    local Loot = DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]

    if itemCount == 0 then
        -- Handle case where all items are junk
        Loot:ClearLootBacklog()
        if UI.lootFrame then UI.lootFrame:Hide() end
        DesolateLootcouncil:DLC_Log("Session contained only junk. Loot cleared locally; no broadcast sent.")
        return
    end

    -- Proceed with valid items
    -- [CHANGED] Do NOT wipe session.bidding to allow overlapping sessions
    -- wipe(session.bidding)

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
    if UI.lootFrame then UI.lootFrame:Hide() end

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

    -- Debug: Packet Size
    DesolateLootcouncil:DLC_Log("Sent packet size: " .. #serialized .. " bytes")

    -- 5. Broadcasting
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")

    -- Debug Fallback (Broadcast to self for testing if solo)
    if not channel then
        channel = "WHISPER"
        DesolateLootcouncil:DLC_Log("Not in group, simulating broadcast to self.")

        -- [SOLO SIMULATION FIX]
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
    UI:ShowMonitorWindow()
    -- Trigger Refresh if Voting Window is open (for overlapping sessions)
    UI:ShowVotingWindow(session.bidding)
end

function Dist:SendStopSession()
    -- 1. Broadcast "STOP_SESSION"
    local payload = { command = "STOP_SESSION" }
    local serialized = self:Serialize(payload)

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if not channel then
        -- Fallback for testing
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
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI.monitorFrame then UI.monitorFrame:Hide() end
    if UI.ResetVoting then UI:ResetVoting() end

    -- Clear Saved State
    wipe(DesolateLootcouncil.db.profile.session.activeState)

    DesolateLootcouncil:DLC_Log("Session Stopped. Broadcast sent.")
end

function Dist:SendCloseItem(itemGUID)
    -- 1. Broadcast to Raid
    local payload = { command = "CLOSE_ITEM", data = { guid = itemGUID } }
    local serialized = self:Serialize(payload)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if not channel then
        -- Fallback
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end

    -- 2. Local Instant Update (Fix "Everyone Voted" lag)
    self.closedItems = self.closedItems or {}
    self.closedItems[itemGUID] = true
    self:SaveSessionState()

    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI and UI.ShowVotingWindow then
        UI:ShowVotingWindow(nil, true)
    end

    DesolateLootcouncil:DLC_Log("Voting closed for item: " .. string.sub(itemGUID, -8))
end

function Dist:SendRemoveItem(guid)
    local payload = { command = "REMOVE_ITEM", data = { guid = guid } }
    local serialized = self:Serialize(payload)
    -- Broadcast to raid/party
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if not channel then
        -- Fallback
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end
end

function Dist:RemoveSessionItem(guid)
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
    ---@type UI
    local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
    if UI.ShowMonitorWindow then UI:ShowMonitorWindow() end

    DesolateLootcouncil:DLC_Log("Removed item from session.")
end

function Dist:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= "DLC_Loot" then return end

    local success, payload = self:Deserialize(message)
    if not success then
        DesolateLootcouncil:DLC_Log("Error deserializing message from " .. sender)
        return
    end

    ---@cast payload DistributionPayload

    if payload.command == "START_SESSION" then
        local newItems = payload.data
        local count = newItems and #newItems or 0
        local duration = payload.duration or 300
        local expiry = payload.endTime or (GetServerTime() + duration)

        -- Initialize accumulator
        self.clientLootList = self.clientLootList or {}
        self.myLocalVotes = {} -- Reset local votes on new start (Scope Safety)

        if newItems then
            for _, item in ipairs(newItems) do
                item.expiry = expiry
                table.insert(self.clientLootList, item)
            end
        end

        DesolateLootcouncil:DLC_Log("Added " .. count .. " items to the session.")

        ---@type UI
        local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
        UI:ShowVotingWindow(self.clientLootList)

        -- Save State
        self.sessionExpiry = expiry
        self:SaveSessionState()
    elseif payload.command == "STOP_SESSION" then
        -- Clear Client Data
        self.clientLootList = {}
        self.sessionVotes = {}
        wipe(DesolateLootcouncil.db.profile.session.activeState)

        -- Close/Reset UI
        ---@type UI
        local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
        if UI.ResetVoting then
            UI:ResetVoting()
        elseif UI.votingFrame then
            UI.votingFrame:Hide()
        end
        DesolateLootcouncil:DLC_Log("The Loot Session was ended by the Master.", true)
    elseif payload.command == "REMOVE_ITEM" then
        local guid = payload.data and payload.data.guid
        if guid and self.clientLootList then
            -- Find and remove the item from the local list
            for i, item in ipairs(self.clientLootList) do
                if (item.sourceGUID or item.link) == guid then
                    table.remove(self.clientLootList, i)
                    break
                end
            end
            -- Refresh UI
            -- Refresh UI
            ---@type UI
            local UI = DesolateLootcouncil:GetModule("UI")
            if UI.RemoveVotingItem then
                UI:RemoveVotingItem(guid)
            elseif UI.ShowVotingWindow then
                -- Fallback
                UI:ShowVotingWindow(self.clientLootList, true)
            end
        end
    elseif payload.command == "CLOSE_ITEM" then
        local guid = payload.data and payload.data.guid
        if guid then
            self.closedItems = self.closedItems or {}
            self.closedItems[guid] = true
            DesolateLootcouncil:DLC_Log("Voting closed for item: " .. string.sub(guid, -8))

            -- Refresh UI
            ---@type UI
            local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
            if UI and UI.ShowVotingWindow then
                UI:ShowVotingWindow(nil, true) -- Pass true to indicate refresh
            end
        end
    elseif payload.command == "VOTE" then
        local myName = UnitName("player")
        if DesolateLootcouncil:DetermineLootMaster() == myName then
            local data = payload.data
            self.sessionVotes = self.sessionVotes or {}
            self.sessionVotes[data.guid] = self.sessionVotes[data.guid] or {}

            if data.vote == 0 then
                -- CASE: Retract Vote
                -- Remove the player's entry entirely
                self.sessionVotes[data.guid][sender] = nil
                DesolateLootcouncil:DLC_Log("Vote retracted by " ..
                    sender .. " for item " .. string.sub(data.guid, -8))
            else
                -- CASE: New Vote
                local serverRoll = math.random(1, 100)
                DesolateLootcouncil:DLC_Log("Generated Roll: " .. serverRoll .. " for " .. sender)
                self.sessionVotes[data.guid][sender] = { type = data.vote, roll = serverRoll }

                -- Support both legacy integer and new string votes
                local voteName = tostring(data.vote)
                if type(data.vote) == "number" then
                    local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "Transmog", [4] = "Pass" }
                    voteName = VOTE_TEXT[data.vote] or voteName
                end

                DesolateLootcouncil:DLC_Log("Received Vote: " .. voteName .. " from " .. sender)

                -- Auto-Close Check
                if DesolateLootcouncil:AmILootMaster() then
                    local voteCount = 0
                    for _ in pairs(self.sessionVotes[data.guid]) do voteCount = voteCount + 1 end

                    local totalMembers = GetNumGroupMembers()
                    if totalMembers == 0 then totalMembers = 1 end -- Self

                    -- [FIX] Combine Real Group + Active Sims
                    ---@type Simulation
                    local Sim = DesolateLootcouncil:GetModule("Simulation")
                    if Sim then
                        totalMembers = totalMembers + Sim:GetCount()
                    end

                    -- Only close if everyone (Real + Sim) has voted
                    if voteCount >= totalMembers then
                        self:SendCloseItem(data.guid)
                    end
                end
            end

            -- Refresh Monitor
            local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
            UI:ShowMonitorWindow()

            -- Save State (Critical Fix)
            self:SaveSessionState()
        end
    elseif payload.command == "SYNC_LM" then
        local lm = payload.data and payload.data.lm
        if lm then
            DesolateLootcouncil.activeLootMaster = lm
            DesolateLootcouncil:DLC_Log("Loot Master synced to: " .. lm)

            -- Update local cache
            DesolateLootcouncil.amILM = (lm == UnitName("player"))
        end
    end
end

function Dist:SendSyncLM(targetLM)
    local payload = {
        command = "SYNC_LM",
        data = { lm = targetLM }
    }
    local serialized = self:Serialize(payload)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if channel then
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end
end

function Dist:SendVote(itemGUID, voteType)
    local payload = {
        command = "VOTE",
        data = {
            guid = itemGUID,
            vote = voteType
        }
    }
    local serialized = self:Serialize(payload)

    -- Target Logic: Always Whisper the Determined Loot Master
    local target = DesolateLootcouncil:DetermineLootMaster()

    -- Save Local Vote (Critical Fix: Sync myLocalVotes and Persist)
    self.myLocalVotes = self.myLocalVotes or {}
    if voteType == 0 then
        self.myLocalVotes[itemGUID] = nil -- Retract means nil, so UI treats it as "Not Voted"
    else
        self.myLocalVotes[itemGUID] = voteType
    end
    self:SaveSessionState()

    if target and target ~= "Unknown" then
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", target)
        DesolateLootcouncil:DLC_Log("Sent Vote " .. voteType .. " to " .. target)
    else
        DesolateLootcouncil:DLC_Log("Error: Could not determine Loot Master to vote.")
    end
end

function Dist:ClearVotes()
    self.sessionVotes = {}
    self.myLocalVotes = {}
    self.closedItems = {}
    wipe(DesolateLootcouncil.db.profile.session.activeState)
    DesolateLootcouncil:DLC_Log("Session data cleared (Votes & Closed Status).")
end
