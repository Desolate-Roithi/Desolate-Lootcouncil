---@class Distribution : AceModule, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0
local Dist = DesolateLootcouncil:NewModule("Distribution", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0")

---@class DistributionPayload
---@field command string
---@field data table
---@field duration number?

function Dist:OnEnable()
    self:RegisterComm("DLC_Loot", "OnCommReceived")
end

function Dist:StartSession(lootTable)
    if not DesolateLootcouncil:AmILootMaster() then
        return -- Silent fail or print error
    end

    if not lootTable or #lootTable == 0 then
        DesolateLootcouncil:Print("[DLC] No items to distribute!")
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
        DesolateLootcouncil:Print("[DLC] Session contained only junk. Loot cleared locally; no broadcast sent.")
        return
    end

    -- Proceed with valid items
    -- [CHANGED] Do NOT wipe session.bidding to allow overlapping sessions
    -- wipe(session.bidding)

    -- Copy clean list to persistent storage
    local duration = DesolateLootcouncil.db.profile.sessionDuration or 300
    for _, item in ipairs(cleanList) do
        item.expiry = GetTime() + duration -- Per-item expiry
        table.insert(session.bidding, item)
    end

    DesolateLootcouncil:Print("[DLC] Loot moved to Bidding Storage. Collection cleared.")

    -- 2. Clear Collection (Wipe session.loot so we can keep looting new mobs)
    Loot:ClearLootBacklog()
    if UI.lootFrame then UI.lootFrame:Hide() end

    -- 3. Prepare Payload from BIDDING storage
    local payloadData = {}
    for _, item in ipairs(session.bidding) do
        table.insert(payloadData, {
            link = item.link,
            texture = item.texture,
            itemID = item.itemID,
            sourceGUID = item.sourceGUID
        })
    end

    -- 4. Serialize
    local payload = {
        command = "START_SESSION",
        data = payloadData,
        duration = 300 -- 5 minutes default
    }
    local serialized = self:Serialize(payload)

    -- Debug: Packet Size
    DesolateLootcouncil:Print("[DLC] Sent packet size: " .. #serialized .. " bytes")

    -- 5. Broadcasting
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")

    -- Debug Fallback (Broadcast to self for testing if solo)
    if not channel then
        channel = "WHISPER"
        DesolateLootcouncil:Print("[DLC] Not in group, simulating broadcast to self.")
        self:SendCommMessage("DLC_Loot", serialized, channel, UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end

    DesolateLootcouncil:Print("[DLC] Broadcasting Bidding Session to " .. channel .. " (" .. itemCount .. " items)...")

    -- Open Monitor Window for LM
    UI:ShowMonitorWindow()
    -- Trigger Refresh if Voting Window is open (for overlapping sessions)
    UI:ShowVotingWindow(nil, true)
end

function Dist:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= "DLC_Loot" then return end

    local success, payload = self:Deserialize(message)
    if not success then
        DesolateLootcouncil:Print("[DLC] Error deserializing message from " .. sender)
        return
    end

    ---@cast payload DistributionPayload

    if payload.command == "START_SESSION" then
        local items = payload.data
        local count = items and #items or 0
        local duration = payload.duration or 300

        -- Store State
        self.sessionExpiry = GetTime() + duration
        self.closedItems = {} -- Reset closed items

        DesolateLootcouncil:Print("[DLC] Received Loot Session from " .. sender .. " with " .. count .. " items.")
        DesolateLootcouncil:Print("[DLC] Voting Session Started! Window Opened (Expires in " ..
            math.floor(duration / 60) .. "m).")

        ---@type UI
        local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
        UI:ShowVotingWindow(items)
    elseif payload.command == "CLOSE_ITEM" then
        local guid = payload.data and payload.data.guid
        if guid then
            self.closedItems = self.closedItems or {}
            self.closedItems[guid] = true
            DesolateLootcouncil:Print("[DLC] Voting closed for item: " .. string.sub(guid, -8))

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
                DesolateLootcouncil:Print("[DLC] Vote retracted by " ..
                    sender .. " for item " .. string.sub(data.guid, -8))
            else
                -- CASE: New Vote
                self.sessionVotes[data.guid][sender] = data.vote

                local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "Transmog", [4] = "Pass" }
                local voteName = VOTE_TEXT[data.vote] or ("Unknown(" .. tostring(data.vote) .. ")")
                DesolateLootcouncil:Print("[DLC] Received Vote: " .. voteName .. " from " .. sender)

                -- Auto-Close Check
                if DesolateLootcouncil:AmILootMaster() then
                    local voteCount = 0
                    for _ in pairs(self.sessionVotes[data.guid]) do voteCount = voteCount + 1 end

                    local totalMembers = GetNumGroupMembers()
                    if totalMembers == 0 then totalMembers = 1 end -- Self test

                    if voteCount >= totalMembers then
                        self:SendCloseItem(data.guid)
                    end
                end
            end

            -- Refresh Monitor
            local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
            UI:ShowMonitorWindow()
        end
    elseif payload.command == "SYNC_LM" then
        local lm = payload.data and payload.data.lm
        if lm then
            DesolateLootcouncil.activeLootMaster = lm
            DesolateLootcouncil:Print("Loot Master synced to: " .. lm)

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

function Dist:SendCloseItem(itemGUID)
    local payload = {
        command = "CLOSE_ITEM",
        data = { guid = itemGUID }
    }
    local serialized = self:Serialize(payload)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")

    -- Fallback for self-test
    if not channel then
        channel = "WHISPER"
        self:SendCommMessage("DLC_Loot", serialized, channel, UnitName("player"))
    else
        self:SendCommMessage("DLC_Loot", serialized, channel)
    end
    DesolateLootcouncil:Print("[DLC] Closed voting for item " .. string.sub(itemGUID, -8))
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

    if target and target ~= "Unknown" then
        self:SendCommMessage("DLC_Loot", serialized, "WHISPER", target)
        DesolateLootcouncil:Print("[DLC] Sent Vote " .. voteType .. " to " .. target)
    else
        DesolateLootcouncil:Print("Error: Could not determine Loot Master to vote.")
    end
end

function Dist:ClearVotes()
    self.sessionVotes = {}
    self.closedItems = {}
    DesolateLootcouncil:Print("[DLC] Session data cleared (Votes & Closed Status).")
end
