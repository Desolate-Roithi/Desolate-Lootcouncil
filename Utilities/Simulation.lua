local _, AT = ...
if AT.abortLoad then return end

---@class Simulation : AceModule, AceConsole-3.0
---@field activeSims table
---@field HandleSlashCommand fun(self: Simulation, input: string)
---@field GetCount fun(self: Simulation): number
---@field OnEnable fun(self: Simulation)
---@field Add fun(self: Simulation, name: string)
---@field Remove fun(self: Simulation, name: string)
---@field Clear fun(self: Simulation)
---@field IsSimulated fun(self: Simulation, unitName: string): boolean
---@field GetRoster fun(self: Simulation): table
---@field SimulateVote fun(self: Simulation)
---@field RunTest fun(self: Simulation, count: number|string)

---@class (partial) DLC_Ref_Sim_Util
---@field db table
---@field NewModule fun(self: DLC_Ref_Sim_Util, name: string, ...): any
---@field GetModule fun(self: DLC_Ref_Sim_Util, name: string): any
---@field DLC_Log fun(self: DLC_Ref_Sim_Util, msg: string, force?: boolean)
---@field activeAddonUsers table
---@field AmILootMaster fun(self: DLC_Ref_Sim_Util): boolean

---@type DLC_Ref_Sim_Util
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Sim_Util]]
local Simulation = DesolateLootcouncil:NewModule("Simulation", "AceConsole-3.0") --[[@as Simulation]]
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

-- State
Simulation.activeSims = {}
Simulation.offlineSims = {}

function Simulation:OnEnable()
    -- Nothing to init specifically
    DesolateLootcouncil:DLC_Log("Utilities/Simulation Loaded")
end

function Simulation:Add(name, enchantingSkill)
    if not name or name == "" then return end

    if self.activeSims[name] then
        DesolateLootcouncil:DLC_Log("Simulated Player '" .. name .. "' is already active.", true)
        return
    end

    self.activeSims[name] = true
    if self.offlineSims then self.offlineSims[name] = nil end

    -- Ensure temp Roster Entry exists to prevent "Unknown" errors
    local db = DesolateLootcouncil.db.profile
    if db and db.playerRoster then
        if not db.playerRoster.alts then db.playerRoster.alts = {} end
        -- Only add if not already known, to preserve real data if testing with real names
        if not db.MainRoster[name] and not db.playerRoster.alts[name] then
            -- Treat as a Main for simplicity in sims
            if not db.MainRoster then db.MainRoster = {} end
            db.MainRoster[name] = { addedAt = time(), class = "WARRIOR", rank = "Sim" }
        end
    end

    local Comm = DesolateLootcouncil:GetModule("Comm")
    if Comm then
        local version = DesolateLootcouncil.version .. "-SIM"
        local skill = tonumber(enchantingSkill)
        Comm:UpdatePlayerInfo(name, version, skill)
    end

    local skillMsg = enchantingSkill and (" with Enchanting " .. enchantingSkill) or ""
    DesolateLootcouncil:DLC_Log("Simulated Player Added: " .. name .. skillMsg, true)
end

function Simulation:Remove(name)
    if self.activeSims[name] then
        self.activeSims[name] = nil
        if self.offlineSims then self.offlineSims[name] = nil end
        local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
        if db and db.MainRoster and db.MainRoster[name] and db.MainRoster[name].rank == "Sim" then
            db.MainRoster[name] = nil
        end
        DesolateLootcouncil:DLC_Log("Simulated Player Removed: " .. name, true)
    else
        DesolateLootcouncil:DLC_Log("Simulated Player '" .. name .. "' not found.", true)
    end
end

function Simulation:Disconnect(name)
    if not name or name == "" then return end
    self.offlineSims = self.offlineSims or {}
    self.offlineSims[name] = true
    DesolateLootcouncil:DLC_Log("Simulated Player Disconnected (Offline): " .. name, true)
    
    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if Comm then
        Comm:SendMessage("DLC_VERSION_UPDATE")
    end
end

function Simulation:Reconnect(name)
    if not name or name == "" then return end
    self.offlineSims = self.offlineSims or {}
    self.offlineSims[name] = nil
    DesolateLootcouncil:DLC_Log("Simulated Player Reconnected (Online): " .. name, true)

    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if Comm then
        Comm:SendMessage("DLC_VERSION_UPDATE")
    end
end

function Simulation:IsOffline(name)
    return self.offlineSims and self.offlineSims[name] == true
end

function Simulation:SwapCharacter(oldName, newName, class)
    if not oldName or not newName or oldName == "" or newName == "" then return end
    
    self:Remove(oldName)
    self:Add(newName)
    if class then
        local db = DesolateLootcouncil.db.profile
        if db and db.MainRoster and db.MainRoster[newName] then
            db.MainRoster[newName].class = class
        end
    end
    DesolateLootcouncil:DLC_Log(string.format("Simulated Player Swapped from %s to %s.", oldName, newName), true)

    local RosterSys = DesolateLootcouncil:GetModule("Roster", true)
    if RosterSys and RosterSys.GROUP_ROSTER_UPDATE then
        RosterSys:GROUP_ROSTER_UPDATE()
    end
end

function Simulation:Clear()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if db and db.MainRoster then
        for name, data in pairs(db.MainRoster) do
            if type(data) == "table" and data.rank == "Sim" then
                db.MainRoster[name] = nil
            end
        end
    end
    self.activeSims = {}
    self.offlineSims = {}
    DesolateLootcouncil:DLC_Log("All simulated players cleared.", true)
end

function Simulation:GetCount()
    local count = 0
    for _ in pairs(self.activeSims) do count = count + 1 end
    return count
end

function Simulation:IsSimulated(unitName)
    return self.activeSims[unitName] == true
end

function Simulation:GetRoster()
    local list = {}
    for name, _ in pairs(self.activeSims) do
        table.insert(list, name)
    end
    return list
end

function Simulation:GetPendingVoters(guid, votedPlayers)
    -- If the caller already resolved voted scores, use that directly.
    -- Otherwise fall back to reading Session.sessionVotes ourselves.
    local votedScores = votedPlayers
    if not votedScores then
        ---@type Session
        local Session = DesolateLootcouncil:GetModule("Session")
        if not Session or not Session.sessionVotes then return nil end

        local votes = Session.sessionVotes[guid] or {}
        votedScores = {}
        for voterName in pairs(votes) do
            local score = DesolateLootcouncil:GetScoreName(voterName)
            if score then
                votedScores[score] = true
            end
        end
    end

    local pending = {}
    for name, _ in pairs(self.activeSims) do
        local simScore = DesolateLootcouncil:GetScoreName(name)
        if simScore and not votedScores[simScore] then
            table.insert(pending, name .. " (Sim)")
        end
    end
    return #pending > 0 and pending or nil
end

function Simulation:CreateSimulatedVotePayload(item, roll)
    local actualRoll = roll
    if not actualRoll then
        actualRoll = math.random(1, 5)
        local itemID = item.link or item.itemID
        local isRecipe = itemID and DesolateLootcouncil.API:IsRecipe(itemID) or false
        if isRecipe then
            local recipeVotes = { 2, 3, 5 }
            actualRoll = recipeVotes[math.random(#recipeVotes)]
        end
    end
    return {
        command = "VOTE",
        data = {
            guid = item.sourceGUID or item.link,
            vote = actualRoll
        }
    }
end

function Simulation:SimulateVote()
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session") --[[@as Session]]
    if not Session then return end

    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.bidding or #session.bidding == 0 then
        DesolateLootcouncil:DLC_Log("No active session items found to vote on.", true)
        return
    end

    local votedCount = 0
    -- Iterate active SIMS only
    for name, _ in pairs(self.activeSims) do
        for _, item in ipairs(session.bidding) do
            local payload = self:CreateSimulatedVotePayload(item)
            -- Serialize and Inject into Session Module
            local serialized = Session:Serialize(payload)
            if Session.OnCommReceived then
                Session:OnCommReceived("DLC_Loot", serialized, "WHISPER", name)
            end
        end
        votedCount = votedCount + 1
    end
    DesolateLootcouncil:DLC_Log("Simulated random votes cast for " .. votedCount .. " simulated players.", true)
end

--- Starts a live interactive loot distribution test with full voting and monitor integration.
---@param mode? string Optional role persona ("LM", "Officer", or "Raider")
---@return boolean success
function Simulation:StartInteractiveLootTest(mode)
    local rawMode = mode or self.simRole or "LM"
    local lowerMode = string.lower(tostring(rawMode))
    local selectedRole = "LM"
    if lowerMode == "officer" then
        selectedRole = "Officer"
    elseif lowerMode == "raider" or lowerMode == "player" then
        selectedRole = "Raider"
    end
    self.simRole = selectedRole

    self:Clear()

    -- 1. Ensure Player or Simulated LM has active identity
    local myName = (UnitName and UnitName("player")) or "Player"
    local rawRealm = GetRealmName and GetRealmName()
    local realm = (rawRealm and rawRealm ~= "") and rawRealm or "Thrall"
    local simLM = "Klacku-" .. realm

    if selectedRole == "LM" then
        DesolateLootcouncil.amILM = true
        DesolateLootcouncil.amIOfficer = true
        DesolateLootcouncil.activeLootMaster = myName
    elseif selectedRole == "Officer" then
        DesolateLootcouncil.amILM = false
        DesolateLootcouncil.amIOfficer = true
        DesolateLootcouncil.activeLootMaster = simLM
    elseif selectedRole == "Raider" then
        DesolateLootcouncil.amILM = false
        DesolateLootcouncil.amIOfficer = false
        DesolateLootcouncil.activeLootMaster = simLM
    end

    -- 2. Populate simulated raiders dynamically from priority lists / roster
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    local addedCount = 0

    if db and db.PriorityLists and #db.PriorityLists > 0 and db.PriorityLists[1].players then
        for idx, pName in ipairs(db.PriorityLists[1].players) do
            if not DesolateLootcouncil:SmartCompare(pName, myName) then
                local skill = 0
                if idx == 4 then skill = 300 elseif idx == 6 then skill = 275 end
                self:Add(pName, skill)
                addedCount = addedCount + 1
            end
        end
    end

    if addedCount < 5 then
        local defaultSims = {
            { name = "WarriorMain-Realm", skill = 0 },
            { name = "MageMain-Realm",    skill = 0 },
            { name = "PriestMain-Realm",  skill = 275 },
            { name = "RogueMain-Realm",   skill = 0 },
            { name = "DruidMain-Realm",   skill = 0 },
            { name = "Klacku-" .. realm,  skill = 0 },
            { name = "Roithi-" .. realm,  skill = 0 },
            { name = "Schench-" .. realm, skill = 300 },
            { name = "Sydneyfox-" .. realm, skill = 0 },
            { name = "Dekaylite-" .. realm, skill = 0 },
            { name = "Laetiii-" .. realm,   skill = 0 },
            { name = "Nxtu-" .. realm,      skill = 0 },
        }
        for _, simDef in ipairs(defaultSims) do
            if not self.activeSims[simDef.name] and not DesolateLootcouncil:SmartCompare(simDef.name, myName) then
                self:Add(simDef.name, simDef.skill)
                addedCount = addedCount + 1
            end
        end
    end

    if DesolateLootcouncil.API and DesolateLootcouncil.API.SyncMissingPlayers then
        DesolateLootcouncil.API:SyncMissingPlayers()
    end

    -- 3. Staged test items covering major priority categories
    local testDefs = {
        { id = 217192, cat = "Tier" },
        { id = 212398, cat = "Weapons" },
        { id = 219315, cat = "Trinkets and Cantrips" },
        { id = 219300, cat = "Rest" },
        { id = 13335,  cat = "Collectables" },
        { id = 223120, cat = "Recipes" },
    }

    local duration = tonumber(DesolateLootcouncil.db.profile.sessionDuration) or 300
    local endTime = GetServerTime() + duration

    local items = {}
    for i, def in ipairs(testDefs) do
        local uniqueID = "InteractiveTest_" .. string.format("%.3f", GetTime()) .. "_" .. i
        local fetchedLink = (C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(def.id)))
        local link = fetchedLink or string.format("item:%d", def.id)
        local blizzTexture = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(def.id))
            or (C_Item and C_Item.GetItemInfoInstant and select(5, C_Item.GetItemInfoInstant(def.id)))
        table.insert(items, {
            link = link,
            itemID = def.id,
            texture = blizzTexture,
            category = def.cat,
            sourceGUID = uniqueID,
            quantity = 1,
            expiry = endTime,
            isTest = true
        })
    end

    -- 4. Cleanly reset all prior session state to avoid stale votes / test residue
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session then
        local prof = DesolateLootcouncil.db.profile
        prof.session = prof.session or {}
        prof.session.bidding = {}
        prof.session.awarded = {}
        prof.session.activeState = {}
        Session.clientLootList = {}
        Session.sessionVotes = {}
        Session.closedItems = {}
        Session.myLocalVotes = {}
        Session.outboundVotes = {}
        Session.sessionPayloadCache = nil

        local VotingMod = DesolateLootcouncil:GetModule("UI_Voting", true)
        if VotingMod and VotingMod.ResetVoting then
            VotingMod:ResetVoting()
        end

        if selectedRole == "LM" then
            if Session.StartSession then
                Session:StartSession(items)
                DesolateLootcouncil:DLC_Log("Interactive Live Test Session started as Loot Master with " .. #items .. " items.", true)
            end
        else
            -- Officer / Raider mode: Simulate receiving LOOT_SESSION_START broadcast from simulated LM
            local activeSimLM = DesolateLootcouncil.activeLootMaster or simLM
            local payloadData = {}
            for _, item in ipairs(items) do
                table.insert(payloadData, {
                    link       = item.link,
                    texture    = item.texture,
                    itemID     = item.itemID,
                    sourceGUID = item.sourceGUID,
                    category   = item.category,
                })
            end

            local payload = {
                command        = "LOOT_SESSION_START",
                data           = payloadData,
                duration       = duration,
                endTime        = endTime,
                autopassActive = DesolateLootcouncil.sessionAutopassActive,
                activeLM       = activeSimLM,
            }

            Session:HandleStartSession(payload, activeSimLM)
            prof.session.bidding = Session.clientLootList
            Session:SaveSessionState()

            DesolateLootcouncil:DLC_Log(string.format("Interactive Live Test Session started as %s via simulated LM broadcast with %d items.", selectedRole, #items), true)
        end
    end

    -- 5. Open Interactive Windows according to role
    local Voting = DesolateLootcouncil:GetModule("UI_Voting", true)
    if Voting and Voting.ShowVotingWindow then
        Voting:ShowVotingWindow(items)
    end
    if selectedRole == "LM" or selectedRole == "Officer" then
        local Monitor = DesolateLootcouncil:GetModule("UI_Monitor", true)
        if Monitor and Monitor.ShowMonitorWindow then
            Monitor:ShowMonitorWindow()
        end
    end

    -- 6. Open Floating Interactive Test Bar
    local TestBar = DesolateLootcouncil:GetModule("UI_InteractiveTestBar", true)
    if TestBar and TestBar.ShowBar then
        TestBar:ShowBar(selectedRole)
    end

    return true
end

--- Switches the active simulation role on the fly between LM, Officer, and Raider.
---@param newRole string "LM", "Officer", or "Raider"
function Simulation:SetSimRole(newRole)
    local rawMode = newRole or "LM"
    local lowerMode = string.lower(tostring(rawMode))
    local selectedRole = "LM"
    if lowerMode == "officer" then
        selectedRole = "Officer"
    elseif lowerMode == "raider" or lowerMode == "player" then
        selectedRole = "Raider"
    end
    self.simRole = selectedRole

    local myName = (UnitName and UnitName("player")) or "Player"
    local rawRealm = GetRealmName and GetRealmName()
    local realm = (rawRealm and rawRealm ~= "") and rawRealm or "Thrall"
    local simLM = "Klacku-" .. realm

    if selectedRole == "LM" then
        DesolateLootcouncil.amILM = true
        DesolateLootcouncil.amIOfficer = true
        DesolateLootcouncil.activeLootMaster = myName
    elseif selectedRole == "Officer" then
        DesolateLootcouncil.amILM = false
        DesolateLootcouncil.amIOfficer = true
        DesolateLootcouncil.activeLootMaster = simLM
    elseif selectedRole == "Raider" then
        DesolateLootcouncil.amILM = false
        DesolateLootcouncil.amIOfficer = false
        DesolateLootcouncil.activeLootMaster = simLM
    end

    local TestBar = DesolateLootcouncil:GetModule("UI_InteractiveTestBar", true)
    if TestBar and TestBar.UpdateRoleDisplay then
        TestBar:UpdateRoleDisplay(selectedRole)
    end

    local Voting = DesolateLootcouncil:GetModule("UI_Voting", true)
    if Voting and Voting.votingFrame and Voting.votingFrame:IsShown() and Voting.ShowVotingWindow then
        Voting:ShowVotingWindow()
    end
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor", true)
    if Monitor and Monitor.monitorFrame and Monitor.monitorFrame:IsShown() and Monitor.ShowMonitorWindow then
        Monitor:ShowMonitorWindow(true)
    end

    DesolateLootcouncil:Print(string.format(L["Interactive simulation role switched to: |cffffd700%s|r."], selectedRole))
end

--- Returns the active simulation role ("LM", "Officer", or "Raider").
---@return string
function Simulation:GetSimRole()
    return self.simRole or "LM"
end

--- Simulates realistic raider votes for all active items in the bidding queue.
---@return number castCount
function Simulation:SimulateRaiderVotes()
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session")
    if not Session then return 0 end

    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.bidding or #session.bidding == 0 then
        return 0
    end

    local API = DesolateLootcouncil.API
    local awardedGUIDs = (API and API.GetAwardedGUIDs and API:GetAwardedGUIDs()) or {}
    Session.sessionVotes = Session.sessionVotes or {}
    Session.closedItems = Session.closedItems or {}

    local castCount = 0
    local voteOptions = { 1, 2, 2, 3, 4, 5 } -- Weighted distribution: Bid, Roll, Roll, OS, TM, Pass

    -- In simulation, total voters = player (1) + all simulated raiders
    local totalMembers = 1 + self:GetCount()

    for _, item in ipairs(session.bidding) do
        local guid = item.sourceGUID or item.link
        local isClosed = Session.closedItems[guid] or (API and API.IsItemClosed and API:IsItemClosed(guid))

        -- Skip items that are already awarded or closed
        if not awardedGUIDs[guid] and not isClosed then
            Session.sessionVotes[guid] = Session.sessionVotes[guid] or {}
            local isRecipe = item.itemID and DesolateLootcouncil.API:IsRecipe(item.itemID) or false

            for simName, _ in pairs(self.activeSims) do
                local normName = DesolateLootcouncil:NormalizeName(simName)

                -- Only vote if this simulated raider hasn't voted yet on this item
                if not Session.sessionVotes[guid][normName] then
                    local chosenVote = voteOptions[math.random(#voteOptions)]
                    if isRecipe then
                        chosenVote = (math.random(1, 2) == 1) and 2 or 5
                    end
                    local serverRoll = math.random(1, 100)
                    Session.sessionVotes[guid][normName] = { type = chosenVote, roll = serverRoll, note = "" }
                    castCount = castCount + 1
                end
            end

            -- Check if all raiders have voted; if so, close the item
            local voteCount = 0
            for _ in pairs(Session.sessionVotes[guid]) do voteCount = voteCount + 1 end
            if voteCount >= totalMembers then
                if Session.SendCloseItem then
                    Session:SendCloseItem(guid)
                else
                    Session.closedItems[guid] = true
                    Session:SendMessage("DLC_ITEM_CLOSED", guid)
                end
            end
        end
    end

    if castCount > 0 then
        -- Batch save and single UI redraw
        if Session.SaveSessionState then Session:SaveSessionState() end
        local Voting = DesolateLootcouncil:GetModule("UI_Voting", true)
        if Voting and Voting.ShowVotingWindow then Voting:ShowVotingWindow(nil, true) end
        local Monitor = DesolateLootcouncil:GetModule("UI_Monitor", true)
        if Monitor and Monitor.ShowMonitorWindow then Monitor:ShowMonitorWindow(true) end
        DesolateLootcouncil:DLC_Log(string.format("Cast %d simulated votes.", castCount), true)
    else
        DesolateLootcouncil:DLC_Log("All open items already have simulated votes.", true)
    end

    return castCount
end

--- Automatically awards the next item in the bidding queue to its top eligible bidder.
---@return table|nil awardedItem, string|nil winnerName
function Simulation:AutoAwardNext()
    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.bidding or #session.bidding == 0 then return nil, nil end

    local itemData = session.bidding[1]
    local guid = itemData.sourceGUID or itemData.link
    local Session = DesolateLootcouncil:GetModule("Session")
    local votes = (Session and Session.sessionVotes and Session.sessionVotes[guid]) or {}

    -- Find top bidder or roller
    local winner = nil
    local bestVote = 99
    for voter, vData in pairs(votes) do
        local vVal = type(vData) == "table" and (vData.type or vData.vote) or tonumber(vData) or 5
        if vVal < bestVote and vVal <= 4 then
            bestVote = vVal
            winner = voter
        end
    end

    -- If no active bids, assign to a simulated raider
    if not winner then
        local firstSim = next(self.activeSims)
        if firstSim then
            winner = firstSim
            bestVote = 2 -- Default to Roll
        end
    end
    winner = winner or (UnitName and UnitName("player")) or "SimWinner"

    local voteText = (bestVote == 1 and "Bid") or (bestVote == 2 and "Roll") or (bestVote == 3 and "Offspec") or (bestVote == 4 and "T-Mog") or "Pass"

    local Loot = DesolateLootcouncil:GetModule("Loot")
    if Loot and Loot.AwardItem then
        Loot:AwardItem(guid, winner, voteText, 1)
    end

    return itemData, winner
end

--- Adds sample test items to the loot backlog for inspection and testing.
---@param itemsList table?
---@return number addedCount
function Simulation:AddBacklogTestItems(itemsList)
    local LootMod = DesolateLootcouncil:GetModule("Loot", true)
    local prof = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not prof then return 0 end
    prof.session = prof.session or {}
    prof.session.loot = prof.session.loot or {}

    local defs = itemsList or {
        { id = 217192 },
        { id = 212398 },
        { id = 219315 },
        { id = 219300 },
    }

    local addedCount = 0
    for i, def in ipairs(defs) do
        local uniqueID = "SimBacklog_" .. string.format("%.3f", GetTime()) .. "_" .. math.random(1000, 9999) .. "_" .. i
        local fetchedLink = (C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(def.id)))
        local link = fetchedLink or string.format("|cffa335ee|Hitem:%d::::::::80:::::|h[Test Item %d]|h|r", def.id, def.id)
        local texture = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(def.id))
            or (C_Item and C_Item.GetItemInfoInstant and select(5, C_Item.GetItemInfoInstant(def.id)))
            or 134400

        if LootMod and LootMod.AddSessionItem then
            if LootMod:AddSessionItem(link, uniqueID, texture, 1, def.cat, def.id) then
                addedCount = addedCount + 1
            end
        else
            table.insert(prof.session.loot, {
                link = link,
                itemID = def.id,
                category = def.cat,
                sourceGUID = uniqueID,
                stackIndex = 1,
                texture = texture
            })
            addedCount = addedCount + 1
        end
    end

    if LootMod then
        LootMod:SendMessage("DLC_LOOT_WINDOW_UPDATE", prof.session.loot)
    end

    return addedCount
end


--- Completes any remaining items in the bidding queue, records all awards, and generates verification results.
---@return table results
function Simulation:CompleteAndVerify()
    local session = DesolateLootcouncil.db.profile.session
    local awardedCount = 0

    while session.bidding and #session.bidding > 0 do
        local _, winner = self:AutoAwardNext()
        if winner then awardedCount = awardedCount + 1 end
    end

    -- Flag keepAuditorOpen so DLC_SESSION_STOPPED does not close the Auditor
    DesolateLootcouncil.keepAuditorOpen = true

    -- Stop test session
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.SendStopSession then
        Session:SendStopSession()
    end

    -- Hide test bar
    local TestBar = DesolateLootcouncil:GetModule("UI_InteractiveTestBar", true)
    if TestBar and TestBar.HideBar then
        TestBar:HideBar()
    end

    -- Open Audit Log to view receipts (pass true for isTestInspection so it opens even in Raider mode)
    local AuditUI = DesolateLootcouncil:GetModule("UI_PriorityLogHistory", true)
    if AuditUI and AuditUI.ShowLogWindow then
        AuditUI:ShowLogWindow(nil, true)
        if AuditUI.logFrame then
            AuditUI.logFrame:Show()
            if AuditUI.logFrame.Raise then
                pcall(function() AuditUI.logFrame:Raise() end)
            end
            if not AuditUI.logFrame.keepAuditorHooked then
                AuditUI.logFrame.keepAuditorHooked = true
                AuditUI.logFrame:HookScript("OnHide", function()
                    DesolateLootcouncil.keepAuditorOpen = nil
                end)
            end
        end
    end

    DesolateLootcouncil.keepAuditorOpen = nil

    DesolateLootcouncil:Print(string.format(L["Interactive Test Session completed. Total awards: %d."], #session.awarded))

    return {
        success = true,
        awardsCount = #session.awarded
    }
end

function Simulation:StopInteractiveLootTest()
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.SendStopSession then
        Session:SendStopSession()
    end
    local Voting = DesolateLootcouncil:GetModule("UI_Voting", true)
    if Voting and Voting.ResetVoting then
        Voting:ResetVoting()
    end
    local Monitor = DesolateLootcouncil:GetModule("UI_Monitor", true)
    if Monitor and Monitor.monitorFrame then
        Monitor.monitorFrame:Hide()
    end
    local TestBar = DesolateLootcouncil:GetModule("UI_InteractiveTestBar", true)
    if TestBar and TestBar.HideBar then
        TestBar:HideBar()
    end
    DesolateLootcouncil:Print(L["Interactive Test Session cancelled."])
end

-- Slash Command Handler
function Simulation:HandleSlashCommand(input)
    local args = { strsplit(" ", input) }
    local cmd = args[1]

    if cmd == "add" then
        if args[2] then self:Add(args[2], args[3]) end
    elseif cmd == "remove" then
        if args[2] then self:Remove(args[2]) end
    elseif cmd == "dc" then
        if args[2] then self:Disconnect(args[2]) end
    elseif cmd == "rc" then
        if args[2] then self:Reconnect(args[2]) end
    elseif cmd == "swap" then
        if args[2] and args[3] then self:SwapCharacter(args[2], args[3], args[4]) end
    elseif cmd == "clear" then
        self:Clear()
    elseif cmd == "vote" then
        self:SimulateVote()
    elseif cmd == "list" then
        local roster = self:GetRoster()
        if #roster == 0 then
            DesolateLootcouncil:DLC_Log("No active simulations.", true)
        else
            DesolateLootcouncil:DLC_Log("Active Sims: " .. table.concat(roster, ", "), true)
        end
    else
        DesolateLootcouncil:DLC_Log(
            "Sim Usage: /dlc sim [add <name> <optional:skill> | remove <name> | dc <name> | rc <name> | swap <old> <new> | clear | vote | list]", true)
    end
end

DesolateLootcouncil.Simulation = Simulation
