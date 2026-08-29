local _, AT = ...
if AT.abortLoad then return end

--- DLC_API — stateless UI/backend facade.
---
--- This is the ONLY file the UI layer is allowed to import from the backend.
--- It contains no state and no game logic of its own; every method delegates
--- to the appropriate System module.  When the frontend is replaced, only the
--- call-sites in UI/ need to change — the backend remains untouched.
---
---@class DLC_API
local DLC_API = {}
DesolateLootcouncil.API = DLC_API
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

-- ---------------------------------------------------------------------------
-- Internal helpers (not part of the public API surface)
-- ---------------------------------------------------------------------------

local function Session()
    return DesolateLootcouncil:GetModule("Session") --[[@as Session]]
end

local function Roster()
    return DesolateLootcouncil:GetModule("Roster") --[[@as Roster]]
end

local function Loot()
    return DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
end

local function Comm()
    return DesolateLootcouncil:GetModule("Comm") --[[@as Comm]]
end

local function Priority()
    return DesolateLootcouncil:GetModule("Priority") --[[@as Priority]]
end

-- ---------------------------------------------------------------------------
-- QUERIES — read-only, return plain Lua values / view-models
-- ---------------------------------------------------------------------------

--- Returns true if the local player is the current Loot Master.
---@return boolean
function DLC_API:IsLootMaster()
    return DesolateLootcouncil:AmILootMaster()
end

--- Returns true if the item (by link, itemID, or item string) is categorized as a recipe.
---@param item string|number|nil
---@return boolean
function DLC_API:IsRecipe(item)
    if not item then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(item)
    return classID == 9
end

--- Returns the full name of the active Loot Master, or nil.
---@return string|nil
function DLC_API:GetActiveLootMaster()
    return DesolateLootcouncil.activeLootMaster
end

--- Returns the canonical item list for the current client role.
--- LMs receive the authoritative session.bidding array.
--- All other clients receive their synced clientLootList.
---@return table items  Array of item data tables.
function DLC_API:GetBiddingList()
    local s = Session()
    if DesolateLootcouncil:AmILootMaster() then
        return DesolateLootcouncil.db.profile.session.bidding or {}
    end
    return (s and s.clientLootList) or {}
end

--- Returns the awarded-item list from db.profile for history/trade display.
---@return table awarded  Array of award record tables.
function DLC_API:GetAwardedList()
    return DesolateLootcouncil.db.profile.session.awarded or {}
end

--- Returns a set of GUIDs that have already been awarded (keyed by GUID).
--- Used by the Voting window to skip already-distributed items.
---@return table<string, boolean>
function DLC_API:GetAwardedGUIDs()
    local result = {}
    for _, award in ipairs(self:GetAwardedList()) do
        if award.fullItemData and award.fullItemData.sourceGUID then
            result[award.fullItemData.sourceGUID] = true
        end
    end
    return result
end

--- Returns a structured view-model for all votes on a single item.
--- Encapsulates sessionVotes and closedItems so the UI never reads them.
---@param guid string  Item GUID or fallback link key.
---@return table summary  { votes: table, isClosed: boolean }
function DLC_API:GetVoteSummary(guid)
    local s = Session()
    local votes    = (s and s.sessionVotes and s.sessionVotes[guid]) or {}
    local isClosed = (s and s.closedItems  and s.closedItems[guid])  or false
    return { votes = votes, isClosed = isClosed }
end

--- Returns true if the item with the given GUID has been closed by the LM.
---@param guid string
---@return boolean
function DLC_API:IsItemClosed(guid)
    local s = Session()
    return (s and s.closedItems and s.closedItems[guid]) or false
end

--- Returns the pending (unacknowledged) outbound vote for a given item GUID,
--- or nil if no vote is in flight.
---@param guid string
---@return table|nil  { type: number, roll: number } or nil
function DLC_API:GetOutboundVote(guid)
    local s = Session()
    return s and s.outboundVotes and s.outboundVotes[guid]
end

--- Returns the player's confirmed local votes map { [guid] = voteType }.
---@return table<string, number>
function DLC_API:GetLocalVotes()
    local s = Session()
    return (s and s.myLocalVotes) or {}
end

--- Returns the 1-based priority rank of playerName in the named list,
--- following Alt→Main resolution.  Returns 999 if unranked.
---@param playerName string
---@param category   string  Priority list name (e.g. "Tier", "Weapons")
---@return number rank
function DLC_API:GetPlayerRankInList(playerName, category)
    local r = Roster()
    local db = DesolateLootcouncil.db.profile
    if not db.PriorityLists then return 999 end

    local searchName  = (r and r:GetMain(playerName)) or playerName
    local searchScore = DesolateLootcouncil:GetScoreName(searchName)

    for _, list in ipairs(db.PriorityLists) do
        if list.name == category then
            for rank, pName in ipairs(list.players) do
                if DesolateLootcouncil:GetScoreName(pName) == searchScore then
                    return rank
                end
            end
        end
    end
    return 999
end

--- Resolves an alt name to its main character name using the Roster module.
---@param name string
---@return string mainName
function DLC_API:GetMain(name)
    local r = Roster()
    return (r and r:GetMain(name)) or name
end

--- Returns a display-safe name for the given full player name.
---@param name string
---@return string
function DLC_API:GetDisplayName(name)
    return DesolateLootcouncil:GetDisplayName(name)
end

--- Returns the full "Name-Realm" form of a unit token (e.g. "raid1", "player").
---@param unit string
---@return string
function DLC_API:GetFullName(unit)
    return DesolateLootcouncil:GetFullName(unit)
end

--- Returns a normalised score key for cross-realm name comparison.
---@param name string
---@return string|nil
function DLC_API:GetScoreName(name)
    return DesolateLootcouncil:GetScoreName(name)
end

--- Returns a sorted list of disenchanters currently present in the group.
--- Each entry is { name: string, skill: number }.
---@return table[] disenchanters
function DLC_API:GetDisenchanterList()
    local c = Comm()
    if not c or not c.playerEnchantingSkill then return {} end

    local result = {}
    for name, skill in pairs(c.playerEnchantingSkill) do
        if skill > 0 then
            local inGroup = DesolateLootcouncil:IsUnitInRaid(name)
            if not inGroup then
                local shortName = Ambiguate(name, "none")
                inGroup = UnitInRaid(shortName) or UnitInParty(shortName)
            end
            if not inGroup then
                local Sim = DesolateLootcouncil:GetModule("Simulation", true)
                if Sim and Sim:IsSimulated(name) then
                    inGroup = true
                end
            end
            if inGroup then
                table.insert(result, { name = name, skill = skill })
            end
        end
    end
    table.sort(result, function(a, b) return a.skill > b.skill end)
    return result
end

--- Returns the loot backlog (items waiting to be distributed) for the LM window.
---@return table items  Array of item data tables from db.profile.
function DLC_API:GetLootBacklog()
    return DesolateLootcouncil.db.profile.session and DesolateLootcouncil.db.profile.session.loot or {}
end

--- Returns the ordered list of priority list names for dropdowns.
---@return string[] names
function DLC_API:GetPriorityListNames()
    local p = Priority()
    return (p and p:GetPriorityListNames()) or {}
end

--- Returns the raw db.profile reference for ItemManager list rendering.
--- ItemManager reads list.items directly (no mutation via this call).
---@return table db
function DLC_API:GetItemManagerDB()
    return DesolateLootcouncil.db.profile
end

--- Returns the class of a unit or character name via Roster.
---@param unitOrName string
---@return string
function DLC_API:GetUnitClass(unitOrName)
    local r = Roster()
    return (r and r.GetUnitClass and r:GetUnitClass(unitOrName)) or "WARRIOR"
end

--- Returns the main character name for an alt (or the name itself if not an alt).
---@param name string
---@return string
function DLC_API:GetMain(name)
    local r = Roster()
    return (r and r.GetMain and r:GetMain(name)) or name
end

--- Returns full item data cached in the active session for a given GUID.
---@param guid string
---@return table|nil
function DLC_API:GetItemData(guid)
    local s = Session()
    return s and s.GetItemData and s:GetItemData(guid)
end

--- Returns whether a character name is an active simulated player.
---@param name string
---@return boolean
function DLC_API:IsSimulatedPlayer(name)
    local sim = DesolateLootcouncil:GetModule("Simulation", true)
    return (sim and sim.IsSimulatedPlayer and sim:IsSimulatedPlayer(name)) or false
end

--- Returns the count of active simulated players.
---@return number
function DLC_API:GetSimulationCount()
    local sim = DesolateLootcouncil:GetModule("Simulation", true)
    return (sim and sim.GetCount and sim:GetCount()) or 0
end

--- Returns the Autopass state for a given player name from Comm.
---@param name string
---@return boolean|nil
function DLC_API:GetPlayerAutopassState(name)
    local c = Comm()
    return c and c.playerAutopassStates and c.playerAutopassStates[name]
end

--- Returns pending voters from the simulation module if active.
---@param guid string
---@param votedPlayers table
---@return table|nil
function DLC_API:GetPendingSimVoters(guid, votedPlayers)
    local sim = DesolateLootcouncil:GetModule("Simulation", true)
    return sim and sim.GetPendingVoters and sim:GetPendingVoters(guid, votedPlayers)
end

--- Returns true if LM handover can safely take place (all items closed or no active bidding items).
---@return boolean
function DLC_API:CanHandover()
    local s = Session()
    if not s or not s.clientLootList or #s.clientLootList == 0 then
        return true
    end
    local bidding = self:GetBiddingList()
    for _, item in ipairs(bidding) do
        local guid = item.sourceGUID or item.link
        if not s.closedItems or not s.closedItems[guid] then
            return false
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- ACTIONS — trigger backend behaviour; return nothing unless noted
-- ---------------------------------------------------------------------------

--- Sends a vote for the given item.
---@param guid     string
---@param voteType number  1=Bid 2=Roll 3=OS 4=TM 5=Pass 0=Cancel
---@param note     string? optional custom note
function DLC_API:SendVote(guid, voteType, note)
    local s = Session()
    if s and s.SendVote then s:SendVote(guid, voteType, note) end
end

--- Cancels (retracts) the player's vote on the given item.
---@param guid string
function DLC_API:CancelVote(guid)
    self:SendVote(guid, 0)
end

--- Starts a new loot session from the given loot table.
---@param lootTable table
function DLC_API:StartSession(lootTable)
    local s = Session()
    if s and s.StartSession then s:StartSession(lootTable) end
end

--- Broadcasts a session-stop command to the raid.
function DLC_API:StopSession()
    local s = Session()
    if s and s.SendStopSession then s:SendStopSession() end
end

--- Removes a single item from the active session by GUID.
---@param guid string
function DLC_API:RemoveSessionItem(guid)
    local s = Session()
    if s and s.RemoveSessionItem then s:RemoveSessionItem(guid) end
end

--- Closes an item for voting (LM action).
---@param guid string
function DLC_API:CloseItem(guid)
    local s = Session()
    if s and s.SendCloseItem then s:SendCloseItem(guid) end
end

--- Reopens / Revotes an item for voting (LM action).
---@param guid string
function DLC_API:RevoteItem(guid)
    local s = Session()
    if s and s.SendReopenItem then
        local duration = (s.sessionDuration and s.sessionDuration > 0 and s.sessionDuration) or 300
        local expiry = GetServerTime() + duration
        s:SendReopenItem(guid, expiry)
    end
end

function DLC_API:CloseAllWindows()
    local UI = DesolateLootcouncil:GetModule("UI", true)
    if UI and UI.CloseAllWindows then UI:CloseAllWindows() end
end

--- Syncs data (priorities/roster) with officers via the Sync module.
function DLC_API:SyncDataWithOfficers()
    local syncMod = DesolateLootcouncil:GetModule("Sync", true)
    if syncMod and syncMod.SyncDataWithOfficers then
        syncMod:SyncDataWithOfficers()
    end
end

--- Syncs the Autopass state to the raid group via Sync.
---@param state boolean
function DLC_API:SendSyncAutopass(state)
    local syncMod = DesolateLootcouncil:GetModule("Sync", true)
    if syncMod and syncMod.SendSyncAutopass then
        syncMod:SendSyncAutopass(state)
    end
end

--- Refreshes themes across all loot and voting windows.
function DLC_API:RefreshLootAndVotingThemes()
    local s = Session()
    if s and s.RefreshLootAndVotingThemes then
        s:RefreshLootAndVotingThemes()
    end
end

--- Marks an item in session awards as traded and logs the event.
---@param item table
function DLC_API:MarkItemTraded(item)
    if not item then return end
    item.traded = true
    DesolateLootcouncil:DLC_Log(string.format(L["Marked %s as traded."], tostring(item.link)))
    if DesolateLootcouncil.db and DesolateLootcouncil.db.profile then
        DesolateLootcouncil.db.profile.historyTimestamp = GetServerTime()
    end
    local UI = DesolateLootcouncil:GetModule("UI", true)
    if UI and UI.SendMessage then
        UI:SendMessage("DLC_HISTORY_UPDATED")
    end
end

--- Records that decay was applied for the active tracking session.
---@param timestamp number?
---@param penalty number?
---@param absentMap table?
function DLC_API:SetSessionDecayApplied(timestamp, penalty, absentMap)
    local r = Roster()
    if r then
        r.decayAppliedForSession = timestamp or GetServerTime()
        r.decayPenaltyForSession = penalty
        r.decayAbsentForSession = absentMap
    end
end

--- Awards the item identified by GUID to a winner with the given vote description.
---@param guid      string
---@param winner    string
---@param voteDesc  string  Human-readable vote type (e.g. "Bid", "Roll", "Disenchant")
function DLC_API:AwardItem(guid, winner, voteDesc)
    local l = Loot()
    if l and l.AwardItem then l:AwardItem(guid, winner, voteDesc) end
end

--- Re-awards the item at the given history index.
---@param index number  1-based index into session.awarded
function DLC_API:ReawardItem(index)
    local l = Loot()
    if l and l.ReawardItem then l:ReawardItem(index) end
end

--- Adds a manual item (by link/name/ID text) to a priority list in the Item Manager.
---@param rawLink  string  Item link, name, or ID as typed by the user
---@param listIndex number  1-based index into PriorityLists
function DLC_API:AddManagedItem(rawLink, listIndex)
    local l = Loot()
    if l and l.AddItemToList then l:AddItemToList(rawLink, listIndex) end
end

function DLC_API:AddManagedItemBatch(items)
    if not items or type(items) ~= "table" then return end
    local listsTouched = {}
    local db = DesolateLootcouncil.db.profile
    
    for _, entry in ipairs(items) do
        local itemID = entry.itemID
        local listIndex = entry.listIndex
        if itemID and listIndex then
            self:AddManagedItem(tostring(itemID), listIndex)
            if db.PriorityLists and db.PriorityLists[listIndex] then
                listsTouched[db.PriorityLists[listIndex].name] = true
            end
        end
    end
    
    for listName in pairs(listsTouched) do
        self:MarkIMDirty(listName)
    end
end

function DLC_API:_GetItemManagerSyncData(isManual)
    if not isManual and IsInRaid() and GetNumGroupMembers() < 10 then
        return nil
    end
    local db = DesolateLootcouncil.db.profile
    if not db.PriorityLists then return nil end
    local syncData = {}
    for _, list in ipairs(db.PriorityLists) do
        syncData[list.name] = list.items
    end
    return syncData
end

--- Broadcasts the current Item Manager lists to the raid (IM_SYNC) as a manual synchronization request.
function DLC_API:SyncItemManagerToRaid()
    local c = Comm()
    if not c then return end
    
    local syncData = self:_GetItemManagerSyncData(true)
    if not syncData then
        return
    end

    c:SendComm("IM_SYNC", { lists = syncData, isManual = true })
end

--- Automatically broadcasts the current Item Manager lists to the raid (IM_SYNC) in active raid context.
function DLC_API:AutoSyncItemManager()
    local c = Comm()
    if not c then return end
    
    local syncData = self:_GetItemManagerSyncData(false)
    if not syncData then return end

    c:SendComm("IM_SYNC", { lists = syncData, isManual = false })
end


--- Sends a version-check ping to all addon users in the group.
---@return boolean success
function DLC_API:PingVersionCheck()
    local c = Comm()
    if c and c.SendVersionCheck then return c:SendVersionCheck() end
    return false
end

--- Adds a manual item to the LM's loot backlog (non-looted drops, test items, etc.).
---@param rawLink string
function DLC_API:AddManualLootItem(rawLink)
    local l = Loot()
    if l and l.AddManualItem then l:AddManualItem(rawLink) end
end

--- Returns the saved category name for a given itemID, or nil.
---@param itemID number
---@return string|nil
function DLC_API:GetItemCategory(itemID)
    local l = Loot()
    return l and l:GetItemCategory(itemID)
end

--- Assigns an itemID to a priority list by index.
---@param itemID    number
---@param listIndex number  1-based index into PriorityLists
function DLC_API:SetItemCategory(itemID, listIndex)
    local l = Loot()
    if l and l.SetItemCategory then l:SetItemCategory(itemID, listIndex) end
end

--- Removes an item from all priority list assignments.
---@param itemID number
function DLC_API:UnassignItem(itemID)
    local l = Loot()
    if l and l.UnassignItem then l:UnassignItem(itemID) end
end

--- Clears the LM's pending loot backlog (raw collection window).
function DLC_API:ClearLootBacklog()
    local l = Loot()
    if l and l.ClearLootBacklog then l:ClearLootBacklog() end
end

--- Returns the seconds remaining on the version-check cooldown, or 0.
---@return number seconds
function DLC_API:GetVersionCheckCooldown()
    local c = Comm()
    return (c and c.GetVersionCheckRemaining) and c:GetVersionCheckRemaining() or 0
end

--- Returns the raw PriorityLists array from db.profile (read-only intent).
---@return table[] lists
function DLC_API:GetPriorityLists()
    return DesolateLootcouncil.db.profile.PriorityLists or {}
end

--- Returns the localized display name for a priority list category.
--- Falls back safely without throwing AceLocale missing entry errors for custom lists.
---@param listName string
---@return string
function DLC_API:GetLocalizedListName(listName)
    if not listName or listName == "" then return "" end
    local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil", true)
    if L then
        local val = rawget(L, listName)
        if val and type(val) == "string" and val ~= "" then
            return val
        end
    end
    return listName
end

--- Returns the DecayConfig settings table.
---@return table config
function DLC_API:GetAttendanceConfig()
    return DesolateLootcouncil.db.profile.DecayConfig or {}
end

--- Returns the MainRoster table.
---@return table roster
function DLC_API:GetMainRoster()
    return DesolateLootcouncil.db.profile.MainRoster or {}
end

--- Starts a new raid session.
function DLC_API:StartRaidSession()
    local r = Roster()
    if r and r.StartRaidSession then r:StartRaidSession() end
end

--- Stops the current raid session.
---@param saveHistory boolean
function DLC_API:StopRaidSession(saveHistory)
    local r = Roster()
    if r and r.StopRaidSession then r:StopRaidSession(saveHistory) end
end

function DLC_API:HasPendingDecay()
    local r = Roster()
    return r and r.HasPendingDecay and r:HasPendingDecay() or false
end

function DLC_API:ApplyDecayForLastSession(skip)
    local r = Roster()
    if r and r.ApplyDecayForLastSession then r:ApplyDecayForLastSession(skip) end
end

function DLC_API:IsLMAbsent()
    local CommMod = DesolateLootcouncil:GetModule("Comm", true)
    return CommMod and CommMod.IsLMAbsent and CommMod:IsLMAbsent() or false
end

function DLC_API:ClaimLMRole()
    local s = Session()
    if s and s.ClaimLMRole then s:ClaimLMRole() end
end

function DLC_API:SendLMHandoverOffer(targetOfficer)
    local Sync = DesolateLootcouncil:GetModule("Sync", true)
    if Sync and Sync.SendLMHandoverOffer then
        Sync:SendLMHandoverOffer(targetOfficer)
    end
end

--- Returns the AttendanceHistory table.
---@return table history
function DLC_API:GetAttendanceHistory()
    return DesolateLootcouncil.db.profile.AttendanceHistory or {}
end

--- Deletes an attendance history entry by index.
---@param index number|string
function DLC_API:DeleteAttendanceHistoryEntry(index)
    local db = DesolateLootcouncil.db.profile
    if db.AttendanceHistory and db.AttendanceHistory[index] then
        table.remove(db.AttendanceHistory, index)
        db.historyTimestamp = GetServerTime()
    end
end

--- Returns a specific PriorityList object from the profile.
---@param listKey number|string
---@return table|nil
function DLC_API:GetPriorityList(listKey)
    local db = DesolateLootcouncil.db.profile
    return db.PriorityLists and db.PriorityLists[listKey]
end

--- Moves a player within a priority list and logs the change.
---@param listKey number|string  Index or key of the priority list
---@param fromIndex number
---@param toIndex number
function DLC_API:MovePlayerInPriorityList(listKey, fromIndex, toIndex)
    local db = DesolateLootcouncil.db.profile
    local list = db.PriorityLists and db.PriorityLists[listKey]
    if not list or not list.players then return end

    local players = list.players
    if fromIndex < 1 or fromIndex > #players or toIndex < 1 or toIndex > #players then return end

    local player = table.remove(players, fromIndex)
    table.insert(players, toIndex, player)

    local msg = string.format("Manual Override: Moved %s from %d to %d in %s.", player, fromIndex, toIndex, list.name or tostring(listKey))
    local p = Priority()
    if p and p.LogPriorityChange then p:LogPriorityChange(msg) end
    if list.name then self:MarkPriorityDirty(list.name) end
end

--- Returns the deterministic 8-digit hex roster hash.
---@return string
function DLC_API:GetRosterHash()
    return DesolateLootcouncil:CalculateRosterHash(DesolateLootcouncil.db.profile.MainRoster)
end

--- Returns true if the player is an officer (alt-aware).
---@param name string
---@return boolean
function DLC_API:IsOfficer(name)
    return DesolateLootcouncil:IsOfficer(name)
end

--- Returns the global addon version.
---@return string version
function DLC_API:GetVersion()
    return DesolateLootcouncil.version or "0.0.0"
end

--- Returns the map of active addon users.
---@return table users
function DLC_API:GetActiveAddonUsers()
    return DesolateLootcouncil.activeAddonUsers or {}
end

--- Returns the map of player versions collected by Comm.
---@return table versions
function DLC_API:GetPlayerVersions()
    local c = Comm()
    return (c and c.playerVersions) or {}
end

--- Seeds the local player's version into Comm's playerVersions table (once).
--- Call this when a UI window that shows connection data first opens.
function DLC_API:SeedSelf()
    local c = Comm()
    if c and c.SeedSelf then c:SeedSelf() end
end

--- Compares two character names for equality.
---@param name1 string
---@param name2 string
---@return boolean
function DLC_API:SmartCompare(name1, name2)
    return DesolateLootcouncil:SmartCompare(name1, name2)
end

--- Broadcasts a version check request.
---@return boolean success
function DLC_API:SendVersionCheck()
    local c = Comm()
    if c and c.SendVersionCheck then return c:SendVersionCheck() end
    return false
end

--- Returns the count of active addon users in the group.
---@return number count
function DLC_API:GetActiveUserCount()
    local c = Comm()
    return c and c.GetActiveUserCount and c:GetActiveUserCount() or 0
end

-- ---------------------------------------------------------------------------
-- SETTINGS & CONFIGURATION API SURFACE
-- ---------------------------------------------------------------------------

--- Returns the configured Loot Master name.
---@return string
function DLC_API:GetConfiguredLM()
    return DesolateLootcouncil.db.profile.configuredLM or ""
end

--- Sets the configured Loot Master name and updates their status.
---@param val string
function DLC_API:SetConfiguredLM(val)
    DesolateLootcouncil.db.profile.configuredLM = val
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
    DesolateLootcouncil:UpdateLootMasterStatus()
end

--- Returns the minimum loot quality threshold.
---@return number
function DLC_API:GetMinLootQuality()
    return DesolateLootcouncil.db.profile.minLootQuality or 3
end

--- Sets the minimum loot quality threshold.
---@param val number
function DLC_API:SetMinLootQuality(val)
    DesolateLootcouncil.db.profile.minLootQuality = val
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
end

--- Returns whether automated rolling/passing is enabled.
---@return boolean
function DLC_API:GetEnableAutoLoot()
    return DesolateLootcouncil.db.profile.enableAutoLoot
end

--- Sets whether automated rolling/passing is enabled.
---@param val boolean
function DLC_API:SetEnableAutoLoot(val)
    DesolateLootcouncil.db.profile.enableAutoLoot = val
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
end

--- Returns whether automated trade staging is enabled.
---@return boolean
function DLC_API:GetEnableAutoTrade()
    return DesolateLootcouncil.db.profile.enableAutoTrade
end

--- Sets whether automated trade staging is enabled.
---@param val boolean
function DLC_API:SetEnableAutoTrade(val)
    DesolateLootcouncil.db.profile.enableAutoTrade = val
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
end

--- Returns whether debug mode is enabled.
---@return boolean
function DLC_API:GetDebugMode()
    return DesolateLootcouncil.db.profile.debugMode
end

--- Sets whether debug mode is enabled.
---@param val boolean
function DLC_API:SetDebugMode(val)
    DesolateLootcouncil.db.profile.debugMode = val
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
end

--- Returns the active UI theme name.
---@return string
function DLC_API:GetActiveTheme()
    return DesolateLootcouncil.db.profile.activeTheme or "Midnight"
end

--- Sets the active UI theme name and triggers a redraw of all open windows.
---@param val string
function DLC_API:SetActiveTheme(val)
    DesolateLootcouncil.db.profile.activeTheme = val
    local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme", true)
    if UI_Theme then UI_Theme:ApplyThemeToAllOpenWindows() end
end

--- Resets the layout positions of all addon windows.
function DLC_API:ResetWindowLayout()
    if DesolateLootcouncil.Persistence and DesolateLootcouncil.Persistence.ResetPositions then
        DesolateLootcouncil.Persistence:ResetPositions()
        DesolateLootcouncil:Print(L["All window positions have been reset."])
    end
end

--- Reprompts the Loot Master to choose whether to enable autopass for this session.
function DLC_API:RepromptAutopass()
    DesolateLootcouncil:PromptAutopass()
end

--- Whispers the selected data type ("PRIORITY" or "ROSTER") to raid officers.
---@param dataType string
---@param payload table?
function DLC_API:ShareDataWithOfficers(dataType, payload)
    local SyncMod = DesolateLootcouncil:GetModule("Sync", true)
    if SyncMod and SyncMod.ShareDataWithOfficers then
        SyncMod:ShareDataWithOfficers(dataType, payload)
    end
end

-- Roster Options Helpers
--- Sets a player's officer status in the roster.
---@param name string
---@param flag boolean
function DLC_API:SetOfficer(name, flag)
    local r = DesolateLootcouncil:GetModule("Roster", true)
    if r and r.SetOfficer then r:SetOfficer(name, flag) end
end

--- Returns true if the player has officer or LM access.
---@return boolean
function DLC_API:IsOfficerOrLM()
    return DesolateLootcouncil:AmIOfficerOrLM()
end

--- Marks an Item Manager list as dirty by updating its timestamp.
---@param listName string
function DLC_API:MarkIMDirty(listName)
    if not listName or listName == "" then return end
    local db = DesolateLootcouncil.db.profile
    if not db.imTimestamps then db.imTimestamps = {} end
    db.imTimestamps[listName] = GetServerTime()
end

--- Marks a Priority list as dirty by updating its timestamp.
---@param listName string
function DLC_API:MarkPriorityDirty(listName)
    if not listName or listName == "" then return end
    local db = DesolateLootcouncil.db.profile
    if not db.priorityTimestamps then db.priorityTimestamps = {} end
    db.priorityTimestamps[listName] = GetServerTime()
end

--- Adds a main character to the roster.
---@param name string
function DLC_API:AddMain(name)
    local r = DesolateLootcouncil:GetModule("Roster", true)
    if r and r.AddMain then r:AddMain(name) end
end

--- Adds an alt character linked to a main.
---@param name string
---@param main string
function DLC_API:AddAlt(name, main)
    local r = DesolateLootcouncil:GetModule("Roster", true)
    if r and r.AddAlt then r:AddAlt(name, main) end
end

--- Removes a player (main or alt) from the roster.
---@param name string
function DLC_API:RemovePlayer(name)
    local r = DesolateLootcouncil:GetModule("Roster", true)
    if r and r.RemovePlayer then r:RemovePlayer(name) end
end

--- Returns the list of unassigned players awaiting review.
---@return table
function DLC_API:GetUnassignedPlayers()
    local r = DesolateLootcouncil:GetModule("Roster", true)
    return (r and r.GetUnassignedPlayers and r:GetUnassignedPlayers()) or {}
end

--- Assigns an unassigned player as a Main character.
---@param name string
function DLC_API:AssignUnassignedAsMain(name)
    local r = DesolateLootcouncil:GetModule("Roster", true)
    if r and r.AssignAsMain then r:AssignAsMain(name) end
end

--- Assigns an unassigned player as an Alt linked to a Main character.
---@param altName string
---@param mainName string
function DLC_API:AssignUnassignedAsAlt(altName, mainName)
    local r = DesolateLootcouncil:GetModule("Roster", true)
    if r and r.AssignAsAlt then r:AssignAsAlt(altName, mainName) end
end

--- Dismisses an unassigned player from the review queue.
---@param name string
function DLC_API:DismissUnassignedPlayer(name)
    local r = DesolateLootcouncil:GetModule("Roster", true)
    if r and r.DismissUnassignedPlayer then r:DismissUnassignedPlayer(name) end
end

--- Returns the formatted roster list for display in the UI.
---@return string
function DLC_API:GetRosterText()
    local db = DesolateLootcouncil.db.profile
    if not db.MainRoster then return "No Roster Found." end

    local text = ""
    local sortedMains = {}
    for name in pairs(db.MainRoster) do table.insert(sortedMains, name) end
    table.sort(sortedMains)

    for _, main in ipairs(sortedMains) do
        local mainText = main
        local data = db.MainRoster[main]
        if data and data.isOfficer then
            mainText = mainText .. " (Officer)"
        end
        text = text .. mainText
        local alts = {}
        if db.playerRoster and db.playerRoster.alts then
            for alt, parent in pairs(db.playerRoster.alts) do
                if parent == main then
                    table.insert(alts, alt)
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

--- Returns a map of main character names for dropdown values.
---@return table<string, string>
function DLC_API:GetMainRosterList()
    local list = {}
    local db = DesolateLootcouncil.db.profile
    if db.MainRoster then
        for name, data in pairs(db.MainRoster) do
            if data and data.isOfficer then
                list[name] = name .. " (Officer)"
            else
                list[name] = name
            end
        end
    end
    return list
end

--- Returns a map of all characters (mains and alts annotated) for dropdown selection.
---@return table<string, string>
function DLC_API:GetAllPlayersList()
    local list = self:GetMainRosterList()
    local db = DesolateLootcouncil.db.profile
    if db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            list[alt] = alt .. " (Alt of " .. main .. ")"
        end
    end
    return list
end

-- Priority Options Helpers
--- Adds a new empty priority list.
---@param name string
function DLC_API:AddPriorityList(name)
    local p = DesolateLootcouncil:GetModule("Priority", true)
    if p and p.AddPriorityList then p:AddPriorityList(name) end
end

--- Renames an existing priority list by index.
---@param idx number
---@param name string
function DLC_API:RenamePriorityList(idx, name)
    local p = DesolateLootcouncil:GetModule("Priority", true)
    if p and p.RenamePriorityList then p:RenamePriorityList(idx, name) end
end

--- Removes an existing priority list by index.
---@param idx number
function DLC_API:RemovePriorityList(idx)
    local p = DesolateLootcouncil:GetModule("Priority", true)
    if p and p.RemovePriorityList then p:RemovePriorityList(idx) end
end

--- Shuffles all priority lists (starts a new season).
function DLC_API:ShuffleLists()
    local p = DesolateLootcouncil:GetModule("Priority", true)
    if p and p.ShuffleLists then p:ShuffleLists() end
end

--- Syncs missing roster members into existing priority lists.
function DLC_API:SyncMissingPlayers()
    local p = DesolateLootcouncil:GetModule("Priority", true)
    if p and p.SyncMissingPlayers then p:SyncMissingPlayers() end
end

--- Returns the priority history change log lines.
---@return string[]
function DLC_API:GetPriorityLog()
    return DesolateLootcouncil.db.profile.PriorityLog or {}
end

-- Decay / Attendance Options Helpers
--- Returns whether raid attendance decay is enabled.
---@return boolean
function DLC_API:GetDecayEnabled()
    return DesolateLootcouncil.db.profile.DecayConfig.enabled
end

--- Sets whether raid attendance decay is enabled.
---@param val boolean
function DLC_API:SetDecayEnabled(val)
    DesolateLootcouncil.db.profile.DecayConfig.enabled = val
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
end

--- Returns the default decay penalty amount.
---@return number
function DLC_API:GetDecayPenalty()
    return DesolateLootcouncil.db.profile.DecayConfig.defaultPenalty or 1
end

--- Sets the default decay penalty amount.
---@param val number
function DLC_API:SetDecayPenalty(val)
    DesolateLootcouncil.db.profile.DecayConfig.defaultPenalty = val
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
end

-- Profile Options Helpers
--- Returns the list of all profiles.
---@return string[]
function DLC_API:GetProfiles()
    return DesolateLootcouncil.db:GetProfiles()
end

--- Returns the current profile name.
---@return string
function DLC_API:GetCurrentProfile()
    return DesolateLootcouncil.db:GetCurrentProfile()
end

--- Sets the current active profile.
---@param name string
function DLC_API:SetProfile(name)
    DesolateLootcouncil.db:SetProfile(name)
end

--- Resets the current active profile to its default values.
---@param noChildren boolean?
---@param noCallbacks boolean?
function DLC_API:ResetProfile(noChildren, noCallbacks)
    if DesolateLootcouncil.db and DesolateLootcouncil.db.ResetProfile then
        DesolateLootcouncil.db:ResetProfile(noChildren, noCallbacks)
    end
end

--- Copies data from the specified profile to the current profile.
---@param fromProfile string
function DLC_API:CopyProfile(fromProfile)
    DesolateLootcouncil.db:CopyProfile(fromProfile)
end

--- Deletes the specified profile.
---@param name string
function DLC_API:DeleteProfile(name)
    DesolateLootcouncil.db:DeleteProfile(name)
end

local decayPatternsCache = nil

--- Returns a list of matchers and tags for decay log messages across all registered and active locales.
--- Dynamically adapts when new locale translations are added.
---@return table
function DLC_API:GetDecayPatterns()
    if decayPatternsCache then return decayPatternsCache end

    local rawKey = "[Decay] %s moved from position #%d to #%d in %s list (+%d decay for absence)."
    local templates = {}

    -- 1. Active locale
    local currentL = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil", true)
    if currentL and currentL[rawKey] and type(currentL[rawKey]) == "string" then
        templates[currentL[rawKey]] = true
    end
    templates[rawKey] = true

    -- 2. Inspect all registered locales in AceLocale-3.0
    local AceLocale = LibStub("AceLocale-3.0", true)
    if AceLocale and AceLocale.apps and AceLocale.apps["DesolateLootcouncil"] then
        for _, locTable in pairs(AceLocale.apps["DesolateLootcouncil"]) do
            if type(locTable) == "table" and locTable[rawKey] and type(locTable[rawKey]) == "string" then
                templates[locTable[rawKey]] = true
            end
        end
    end

    local list = {}
    for template in pairs(templates) do
        local tag = template:match("^(%b[])") or "[Decay]"

        -- 1. Replace format specifiers with unique tokens
        local p = template
        p = p:gsub("%%s", "___STR___", 1)  -- Player name
        p = p:gsub("%%d", "___NUM___", 1)  -- Position 1
        p = p:gsub("%%d", "___NUM___", 1)  -- Position 2
        p = p:gsub("%%s", "___ANY___", 1)  -- List name
        p = p:gsub("%%d", "___PEN___", 1)  -- Penalty

        -- 2. Escape magic Lua regex characters
        p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

        -- 3. Substitute regex capture patterns
        p = p:gsub("___STR___", "(.-)")
        p = p:gsub("___NUM___", "%%d+")
        p = p:gsub("___ANY___", ".-")
        p = p:gsub("___PEN___", "(%%d+)")

        table.insert(list, {
            tag = tag,
            matchPattern = p,
            template = template
        })
    end

    decayPatternsCache = list
    return decayPatternsCache
end

--- Checks if a log message string represents an automated decay event in any registered language.
---@param str string
---@return boolean
function DLC_API:IsDecayLogMessage(str)
    if type(str) ~= "string" or str == "" then return false end
    local patterns = self:GetDecayPatterns()
    for _, item in ipairs(patterns) do
        if str:find(item.tag, 1, true) then
            return true
        end
    end
    return str:find("[Decay]", 1, true) ~= nil or str:find("[Verfall]", 1, true) ~= nil
end

--- Parses player name and penalty from a decay log message string in any registered language.
---@param str string
---@return string? playerName, number? penalty
function DLC_API:ParseDecayLogMessage(str)
    if type(str) ~= "string" or str == "" then return nil, nil end
    local cleanStr = str:gsub("^%[[^%]]+%]%s*", "")
    local patterns = self:GetDecayPatterns()
    for _, item in ipairs(patterns) do
        local pName, pPen = cleanStr:match(item.matchPattern)
        if pName then
            return pName, tonumber(pPen)
        end
    end
    -- Fallback generic matchers
    local pName, pPen = cleanStr:match("%[Decay%]%s+(.-)%s+moved from position #%d+ to #%d+ in .- %(%+(%d+)")
    if not pName then
        pName, pPen = cleanStr:match("%[Verfall%]%s+(.-)%s+wurde von Position #%d+ auf #%d+ in .- %(%+(%d+)")
    end
    return pName, tonumber(pPen)
end

-- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Migration helper to extract decay data from legacy uncompacted SessionPositionLog strings
local function ExtractDecayFromPositionLog(api, entry, splBucket, decayConfig, mainRoster)
    if not entry or type(entry) ~= "table" or not entry.sessionID then return end
    if entry.decayAbsent and next(entry.decayAbsent) then return end

    local defaultPenalty = (decayConfig and decayConfig.defaultPenalty) or 1

    -- Primary: Extract from SessionPositionLog
    if splBucket and type(splBucket) == "table" then
        local extractedAbsent = {}
        local extractedPenalty = nil
        for _, logStr in ipairs(splBucket) do
            if type(logStr) == "string" then
                local pName, pPen = api:ParseDecayLogMessage(logStr)
                if pName then
                    extractedAbsent[pName] = true
                    if pPen then extractedPenalty = tonumber(pPen) end
                end
            end
        end
        if next(extractedAbsent) then
            entry.decayAbsent = extractedAbsent
            entry.decayPenalty = entry.decayPenalty or extractedPenalty or defaultPenalty
            if not entry.decayApplied or entry.decayApplied == -1 then
                entry.decayApplied = entry.sessionID
            end
            return
        end
    end

    -- Fallback: If decay was applied and attendees exist
    if entry.decayApplied and entry.decayApplied ~= -1 and entry.attendees and mainRoster then
        local fallbackAbsent = {}
        for mName in pairs(mainRoster) do
            if not entry.attendees[mName] then
                fallbackAbsent[mName] = true
            end
        end
        if next(fallbackAbsent) then
            entry.decayAbsent = fallbackAbsent
            entry.decayPenalty = entry.decayPenalty or defaultPenalty
        end
    end
end

-- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] One-time migration to compact legacy history records and prune redundant decay strings
local function ParseItemTimestamp(item)
    if not item or type(item) ~= "table" then return 0 end
    local ts = item.timestamp or item.time or item.awardedAt or item.date
    if type(ts) == "number" then
        return ts
    elseif type(ts) == "string" then
        local num = tonumber(ts)
        if num then return num end
        local y, m, d, h, min, s = ts:match("(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)")
        if y then
            local tTable = { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(h), min = tonumber(min), sec = tonumber(s) }
            local parsed = time(tTable)
            if parsed then return parsed end
        end
        local h2, m2, s2 = ts:match("(%d+):(%d+):(%d+)")
        if h2 then
            return tonumber(h2) * 3600 + tonumber(m2) * 60 + tonumber(s2)
        end
        local h3, m3 = ts:match("(%d+):(%d+)")
        if h3 then
            return tonumber(h3) * 3600 + tonumber(m3) * 60
        end
    end
    return 0
end

function DLC_API:ParseItemTimestamp(item)
    return ParseItemTimestamp(item)
end

local function CompactItemList(items)
    if not items or type(items) ~= "table" then return {} end
    local list = {}
    for k, val in pairs(items) do
        if val == true or val == 1 then
            -- Dictionary format: { [itemID] = true } -> k is itemID
            local numID = tonumber(k)
            if numID then
                table.insert(list, numID)
            end
        elseif type(k) == "number" and (type(val) == "number" or (type(val) == "string" and tonumber(val))) and val ~= false then
            -- Array format: { itemID1, itemID2, ... } -> val is itemID
            local numID = tonumber(val)
            if numID then
                table.insert(list, numID)
            end
        elseif val then
            local numID = tonumber(k) or tonumber(val)
            if numID then
                table.insert(list, numID)
            end
        end
    end
    table.sort(list, function(a, b)
        local numA, numB = tonumber(a), tonumber(b)
        if numA and numB then return numA < numB end
        return tostring(a) < tostring(b)
    end)
    return list
end

local function CleanAwardedItem(item, deepCopyFn)
    if type(item) ~= "table" then return item end
    local ts = item.timestamp or item.time or item.awardedAt or item.date
    if type(ts) == "string" then
        ts = tonumber(ts) or ts
    end
    return {
        link          = item.link,
        texture       = item.texture,
        itemID        = item.itemID,
        winner        = item.winner,
        winnerClass   = item.winnerClass,
        voteType      = item.voteType,
        timestamp     = ts,
        originalIndex = item.originalIndex,
        traded        = item.traded,
        votes         = deepCopyFn(item.votes or {}),
    }
end

local function CleanAttendanceEntry(entry, deepCopyFn)
    if type(entry) ~= "table" then return entry end
    local cleaned = deepCopyFn(entry)

    -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Migrate legacy 'loot' field to 'awarded'
    if cleaned.loot and not cleaned.awarded then
        cleaned.awarded = cleaned.loot
        cleaned.loot = nil
    end

    -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Migrate legacy 'bossFights' field to 'bossLogs'
    if cleaned.bossFights and not cleaned.bossLogs then
        cleaned.bossLogs = cleaned.bossFights
        cleaned.bossFights = nil
    end

    if cleaned.awarded and type(cleaned.awarded) == "table" then
        local cleanedAwarded = {}
        for origIdx, item in pairs(cleaned.awarded) do
            local numIdx = tonumber(origIdx) or 999
            local cItem = CleanAwardedItem(item, deepCopyFn)
            cItem.origIdx = numIdx
            table.insert(cleanedAwarded, cItem)
        end
        -- Always order awarded loot chronologically by timestamp ascending
        table.sort(cleanedAwarded, function(a, b)
            local tA = ParseItemTimestamp(a)
            local tB = ParseItemTimestamp(b)
            if tA ~= tB then return tA < tB end
            return (a.origIdx or 0) < (b.origIdx or 0)
        end)
        for _, itm in ipairs(cleanedAwarded) do
            itm.origIdx = nil
        end
        cleaned.awarded = cleanedAwarded
    end

    if cleaned.publicAwardLog and type(cleaned.publicAwardLog) == "table" then
        table.sort(cleaned.publicAwardLog, function(a, b)
            return ParseItemTimestamp(a) < ParseItemTimestamp(b)
        end)
    end

    if cleaned.bossLogs and type(cleaned.bossLogs) == "table" then
        for origIdx, b in pairs(cleaned.bossLogs) do
            b.origIdx = tonumber(origIdx) or 999
            if not b.pulls or b.pulls < 1 then
                b.pulls = 1
            end
        end
        -- Always order killed bosses chronologically by timestamp (killedTime) ascending
        table.sort(cleaned.bossLogs, function(a, b)
            local kA = (a.killed and a.killedTime) or nil
            local kB = (b.killed and b.killedTime) or nil
            if kA and kB then
                if kA ~= kB then return kA < kB end
                return (a.origIdx or 0) < (b.origIdx or 0)
            elseif kA and not kB then
                return true
            elseif not kA and kB then
                return false
            else
                return (a.origIdx or 0) < (b.origIdx or 0)
            end
        end)
        for _, b in ipairs(cleaned.bossLogs) do
            b.origIdx = nil
        end
    end

    return cleaned
end

local function GetItemDatePrefix(item)
    local ts = ParseItemTimestamp(item)
    if ts and ts > 0 then
        -- 86400+ seconds implies a real epoch timestamp
        if ts > 86400 then
            return date("%Y-%m-%d", ts), ts
        end
    end
    return nil, 0
end

local function SplitMultiDateAttendanceEntry(entry, deepCopyFn)
    if not entry or type(entry) ~= "table" then return { entry } end
    local baseDatePrefix = entry.date and entry.date:sub(1, 10)

    -- Collect all distinct date buckets from awarded items and bossLogs
    local datesFound = {}
    local dateOrder = {}
    local function markDate(dStr)
        if dStr and type(dStr) == "string" and #dStr == 10 and not datesFound[dStr] then
            datesFound[dStr] = true
            table.insert(dateOrder, dStr)
        end
    end

    if baseDatePrefix and #baseDatePrefix == 10 then
        markDate(baseDatePrefix)
    end

    local rawAwarded = entry.awarded or entry.loot
    if rawAwarded and type(rawAwarded) == "table" then
        for _, itm in pairs(rawAwarded) do
            local dStr = GetItemDatePrefix(itm)
            if dStr then markDate(dStr) end
        end
    end

    local rawBossLogs = entry.bossLogs or entry.bossFights
    if rawBossLogs and type(rawBossLogs) == "table" then
        for _, b in pairs(rawBossLogs) do
            if b.killed and b.killedTime and b.killedTime > 86400 then
                local dStr = date("%Y-%m-%d", b.killedTime)
                if dStr then markDate(dStr) end
            end
        end
    end

    -- If there is only 1 date or 0 dates, no splitting required
    if #dateOrder <= 1 then
        return { CleanAttendanceEntry(entry, deepCopyFn) }
    end

    -- Sort dates chronologically descending (newest on top)
    table.sort(dateOrder, function(a, b) return a > b end)

    local splitEntries = {}
    for _, dStr in ipairs(dateOrder) do
        local subEntry = deepCopyFn(entry)
        subEntry.loot = nil
        subEntry.bossFights = nil

        -- Filter awarded for this specific date
        local subAwarded = {}
        if rawAwarded and type(rawAwarded) == "table" then
            for _, itm in pairs(rawAwarded) do
                local itmDate = GetItemDatePrefix(itm)
                if (itmDate and itmDate == dStr) or (not itmDate and dStr == baseDatePrefix) then
                    table.insert(subAwarded, deepCopyFn(itm))
                end
            end
        end
        subEntry.awarded = subAwarded

        -- Filter publicAwardLog for this specific date
        local subPubAwarded = {}
        if entry.publicAwardLog and type(entry.publicAwardLog) == "table" then
            for _, itm in pairs(entry.publicAwardLog) do
                local itmDate = GetItemDatePrefix(itm)
                if (itmDate and itmDate == dStr) or (not itmDate and dStr == baseDatePrefix) then
                    table.insert(subPubAwarded, deepCopyFn(itm))
                end
            end
        end
        subEntry.publicAwardLog = subPubAwarded

        -- Filter bossLogs for this specific date
        local subBosses = {}
        if rawBossLogs and type(rawBossLogs) == "table" then
            for _, b in pairs(rawBossLogs) do
                local bDate = (b.killed and b.killedTime and b.killedTime > 86400 and date("%Y-%m-%d", b.killedTime)) or nil
                if (bDate and bDate == dStr) or (not bDate and dStr == baseDatePrefix) then
                    table.insert(subBosses, deepCopyFn(b))
                end
            end
        end
        subEntry.bossLogs = subBosses

        -- Determine earliest timestamp on this day for date/sessionID
        local earliestTs = 0
        for _, itm in ipairs(subAwarded) do
            local ts = ParseItemTimestamp(itm)
            if ts > 86400 and (earliestTs == 0 or ts < earliestTs) then
                earliestTs = ts
            end
        end
        for _, b in ipairs(subBosses) do
            if b.killed and b.killedTime and b.killedTime > 86400 then
                if earliestTs == 0 or b.killedTime < earliestTs then
                    earliestTs = b.killedTime
                end
            end
        end

        if earliestTs > 0 then
            subEntry.date = date("%Y-%m-%d %H:%M:%S", earliestTs)
            if dStr ~= baseDatePrefix then
                subEntry.sessionID = earliestTs
            end
        else
            subEntry.date = dStr .. " 00:00:00"
        end

        -- Only keep split entries that have content
        if #subAwarded > 0 or #subBosses > 0 or dStr == baseDatePrefix then
            table.insert(splitEntries, CleanAttendanceEntry(subEntry, deepCopyFn))
        end
    end

    return splitEntries
end

function DLC_API:SplitMultiDateAttendanceEntry(entry)
    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end
    return SplitMultiDateAttendanceEntry(entry, DeepCopy)
end

--- Compacts raid history by migrating decay information into structured fields on attendance entries
--- and removing redundant decay log strings from SessionPositionLog.
--- Executes only once per profile unless force is true (e.g. on new history import).
---@param targetProfile table? Optional profile table (defaults to DesolateLootcouncil.db.profile)
---@param force boolean? If true, forces compaction even if previously marked as compacted
---@return number prunedCount Number of decay log entries pruned
function DLC_API:CompactRaidHistory(targetProfile, force)
    local p = targetProfile or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile)
    if not p then return 0 end
    if p.historyCompacted and not force then return 0 end

    local prunedCount = 0
    local hist = p.AttendanceHistory
    local spl = p.SessionPositionLog

    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end

    -- 1. Process each attendance history entry to ensure decayAbsent / decayPenalty are populated, multi-date sessions split, and fields normalized
    if hist and type(hist) == "table" then
        local newHist = {}
        for _, entry in ipairs(hist) do
            local posKey = entry and entry.sessionID and tostring(entry.sessionID)
            local splBucket = posKey and spl and spl[posKey]
            ExtractDecayFromPositionLog(self, entry, splBucket, p.DecayConfig, p.MainRoster)
            local splitList = SplitMultiDateAttendanceEntry(entry, DeepCopy)
            for _, subE in ipairs(splitList) do
                table.insert(newHist, subE)
            end
        end
        -- Order attendance entries chronologically by date descending (newest on top)
        table.sort(newHist, function(a, b)
            local sA = tostring(a.date or a.sessionID or "")
            local sB = tostring(b.date or b.sessionID or "")
            return sA > sB
        end)
        p.AttendanceHistory = newHist
    end

    -- 2. Prune all decay strings from SessionPositionLog
    if spl and type(spl) == "table" then
        for posKey, bucket in pairs(spl) do
            if type(bucket) == "table" then
                local filteredBucket = {}
                for _, logStr in ipairs(bucket) do
                    if self:IsDecayLogMessage(logStr) then
                        prunedCount = prunedCount + 1
                    else
                        table.insert(filteredBucket, logStr)
                    end
                end
                if #filteredBucket > 0 then
                    spl[posKey] = filteredBucket
                else
                    spl[posKey] = nil
                end
            end
        end
    end

    -- 3. Also normalize live session awards if present
    if p.session then
        if p.session.awarded and type(p.session.awarded) == "table" then
            table.sort(p.session.awarded, function(a, b)
                return ParseItemTimestamp(a) < ParseItemTimestamp(b)
            end)
        end
        if p.session.publicAwardLog and type(p.session.publicAwardLog) == "table" then
            table.sort(p.session.publicAwardLog, function(a, b)
                return ParseItemTimestamp(a) < ParseItemTimestamp(b)
            end)
        end
    end

    p.historyCompacted = true
    return prunedCount
end

local function EncodePayload(data)
    local serialized = DesolateLootcouncil:Serialize(data)
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if LibDeflate and type(serialized) == "string" then
        local compressed = LibDeflate:CompressDeflate(serialized, { level = 7 })
        if compressed then
            local encoded = LibDeflate:EncodeForPrint(compressed)
            if encoded then
                return "!DLC1:" .. encoded
            end
        end
    end
    local encoded = DesolateLootcouncil.Base64 and DesolateLootcouncil.Base64:Encode(serialized) or serialized
    return encoded
end

local function DecodePayload(importStringRaw)
    if not importStringRaw or importStringRaw == "" then return nil end
    local cleanStr = importStringRaw:gsub("^%s+", ""):gsub("%s+$", "")
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)

    if cleanStr:sub(1, 6) == "!DLC1:" and LibDeflate then
        local payloadStr = cleanStr:sub(7):gsub("%s+", "")
        local decodedBytes = LibDeflate:DecodeForPrint(payloadStr)
        if decodedBytes then
            local decompressed = LibDeflate:DecompressDeflate(decodedBytes)
            if decompressed then
                return decompressed
            end
        end
        return nil
    end

    -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Fallback uncompressed Base64 / raw string import support
    if DesolateLootcouncil.Base64 and not string.find(cleanStr, "^{") and cleanStr:sub(1, 2) ~= "^S" then
        return DesolateLootcouncil.Base64:Decode(cleanStr:gsub("%s+", ""))
    end
    return cleanStr
end

--- Generates a serialized export string for a single raid history event.
---@param indexOrSession number|string|table  1-based index in AttendanceHistory, "CURRENT", or a session entry table
---@return string
function DLC_API:ExportSingleRaidHistoryEvent(indexOrSession)
    self:CompactRaidHistory()
    local p = DesolateLootcouncil.db.profile
    local entry = nil

    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end

    if type(indexOrSession) == "table" then
        entry = DeepCopy(indexOrSession)
    elseif indexOrSession == "CURRENT" then
        local config = self:GetAttendanceConfig()
        local session = p.session or {}
        local attendees = {}
        if config.currentAttendees then
            for name, val in pairs(config.currentAttendees) do
                if val then attendees[name] = true end
            end
        end
        local currentLoot = {}
        if session.awarded then
            for _, item in ipairs(session.awarded) do
                table.insert(currentLoot, CleanAwardedItem(item, DeepCopy))
            end
        end
        entry = {
            sessionID = config.currentSessionID or GetServerTime(),
            date = date("%Y-%m-%d"),
            zone = (session and session.zone) or (GetRealZoneText and GetRealZoneText()) or "Current Raid",
            attendees = attendees,
            awarded = currentLoot,
            bossLogs = DeepCopy(config.bossLogs or {}),
            decayApplied = -1,
        }
    elseif type(indexOrSession) == "number" and p.AttendanceHistory and p.AttendanceHistory[indexOrSession] then
        entry = DeepCopy(p.AttendanceHistory[indexOrSession])
    end

    if not entry then
        return ""
    end

    local cleanedEntry = CleanAttendanceEntry(entry, DeepCopy)
    local posKey = cleanedEntry.sessionID and tostring(cleanedEntry.sessionID)
    local splBucket = posKey and p.SessionPositionLog and p.SessionPositionLog[posKey]

    local data = {
        SingleRaidEvent = true,
        History = {
            AttendanceHistory = { cleanedEntry },
            SessionPositionLog = splBucket and { [posKey] = DeepCopy(splBucket) } or nil,
        }
    }

    return EncodePayload(data)
end

--- Generates a serialized profile export string based on selected category options.
---@param selection table<string, boolean>
---@return string
function DLC_API:ExportProfileData(selection)
    self:CompactRaidHistory()
    local p = DesolateLootcouncil.db.profile
    local data = {}
    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end

    local exportAll = (not selection) or selection["All"]

    if exportAll or (selection and selection["Config"]) then
        data.config = {
            minLootQuality  = p.minLootQuality,
            enableAutoLoot  = p.enableAutoLoot,
            enableAutoTrade = p.enableAutoTrade,
            activeTheme     = p.activeTheme,
            DecayConfig     = DeepCopy(p.DecayConfig),
        }
    end
    if exportAll or (selection and selection["Roster"]) then
        local playerRoster = DeepCopy(p.playerRoster)
        if playerRoster and playerRoster.decay and not next(playerRoster.decay) then
            playerRoster.decay = nil
        end
        data.Roster = {
            MainRoster   = DeepCopy(p.MainRoster),
            playerRoster = playerRoster,
        }
    end
    if exportAll or (selection and (selection["PriorityRankings"] or selection["PriorityLists"] or selection["PriorityContent"])) then
        data.PriorityLists = {}
        if p.PriorityLists then
            for _, list in ipairs(p.PriorityLists) do
                table.insert(data.PriorityLists, {
                    name    = list.name,
                    players = DeepCopy(list.players or {})
                })
            end
        end
    elseif selection and selection["PriorityStructure"] then
        data.PriorityListsStructure = {}
        if p.PriorityLists then
            for _, list in ipairs(p.PriorityLists) do
                table.insert(data.PriorityListsStructure, {
                    name    = list.name,
                    players = {}
                })
            end
        end
    end
    if exportAll or (selection and selection["IM"]) then
        data.ItemManagerContent = {}
        if p.PriorityLists then
            for _, list in ipairs(p.PriorityLists) do
                table.insert(data.ItemManagerContent, {
                    name  = list.name,
                    items = CompactItemList(list.items)
                })
            end
        end
    end
    if exportAll or (selection and selection["History"]) then
        local cleanedAttendance = {}
        if p.AttendanceHistory and type(p.AttendanceHistory) == "table" then
            for _, att in ipairs(p.AttendanceHistory) do
                table.insert(cleanedAttendance, CleanAttendanceEntry(att, DeepCopy))
            end
        end

        local cleanedSession = DeepCopy(p.session)
        if cleanedSession and cleanedSession.awarded and type(cleanedSession.awarded) == "table" then
            local cleanedSessionAwarded = {}
            for _, item in ipairs(cleanedSession.awarded) do
                table.insert(cleanedSessionAwarded, CleanAwardedItem(item, DeepCopy))
            end
            cleanedSession.awarded = cleanedSessionAwarded
        end

        data.History = {
            session            = cleanedSession,
            AttendanceHistory  = cleanedAttendance,
            PriorityLog        = DeepCopy(p.PriorityLog),
            SessionPositionLog = DeepCopy(p.SessionPositionLog),
        }
    end

    return EncodePayload(data)
end

--- Imports profile data from a serialized string and switches to the new profile.
---@param importStringRaw string
---@param importName string
---@param importToCurrent boolean?
---@return boolean success, string errorMsg
function DLC_API:ImportProfileData(importStringRaw, importName, importToCurrent)
    if not importStringRaw or importStringRaw == "" then
        return false, "Import Error: String is empty."
    end
    if not importToCurrent then
        if not importName or importName == "" then
            return false, "Import Error: Please specify a name for the new profile."
        end
    end

    local decoded = DecodePayload(importStringRaw)
    if not decoded then
        return false, "Import Error: Invalid string format / Decode failed."
    end

    local success, data = DesolateLootcouncil:Deserialize(decoded)
    if not success or type(data) ~= "table" then
        return false, "Import Error: Invalid string format / Decode failed."
    end

    if not importToCurrent then
        if DesolateLootcouncil.db and DesolateLootcouncil.db.SetProfile then
            DesolateLootcouncil.db:SetProfile(importName)
        end
    end

    local p = DesolateLootcouncil.db.profile
    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end

    -- 1. Config
    if data.config then
        if data.config.minLootQuality ~= nil then p.minLootQuality = data.config.minLootQuality end
        if data.config.enableAutoLoot ~= nil then p.enableAutoLoot = data.config.enableAutoLoot end
        if data.config.enableAutoTrade ~= nil then p.enableAutoTrade = data.config.enableAutoTrade end
        if data.config.activeTheme ~= nil then
            p.activeTheme = data.config.activeTheme
            local Theme = DesolateLootcouncil:GetModule("UI_Theme", true)
            if Theme and Theme.SetTheme then Theme:SetTheme(p.activeTheme) end
        end
        if data.config.DecayConfig then
            p.DecayConfig = DeepCopy(data.config.DecayConfig)
        end
        p.configTimestamp = GetServerTime()
    end

    -- 2. Roster
    if data.Roster then
        p.MainRoster = DeepCopy(data.Roster.MainRoster or {})
        p.playerRoster = DeepCopy(data.Roster.playerRoster or { alts = {}, decay = {} })
        p.rosterTimestamp = GetServerTime()

        local Roster = DesolateLootcouncil:GetModule("Roster", true)
        if Roster then
            if Roster.SanitizeMainsAndAlts then Roster:SanitizeMainsAndAlts() end
            if Roster.UpdateScoreMap then Roster:UpdateScoreMap() end
        end
        if DesolateLootcouncil.SendMessage then
            DesolateLootcouncil:SendMessage("DLC_ROSTER_UPDATED")
        end
    end

    -- 3. Priority Lists (Rankings or Empty Structure)
    local incomingLists = data.PriorityLists or data.PriorityListsContent or data.PriorityListsStructure
    if incomingLists then
        p.PriorityLists = p.PriorityLists or {}
        p.priorityTimestamps = p.priorityTimestamps or {}

        for _, incoming in ipairs(incomingLists) do
            local listObj = nil
            for _, localList in ipairs(p.PriorityLists) do
                if localList.name == incoming.name then
                    listObj = localList
                    break
                end
            end
            if not listObj then
                listObj = { name = incoming.name, players = {}, items = {} }
                table.insert(p.PriorityLists, listObj)
            end

            -- Update players if provided, or clear if structure only
            if incoming.players then
                listObj.players = DeepCopy(incoming.players)
            elseif data.PriorityListsStructure then
                listObj.players = {}
            end

            -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Legacy fallback: If old export had items embedded directly in PriorityLists
            if incoming.items and not data.ItemManagerContent and not data.IM then
                local normalizedItems = {}
                for k, val in pairs(incoming.items) do
                    if type(k) == "number" and (type(val) == "number" or (type(val) == "string" and tonumber(val))) and val ~= true and val ~= false then
                        normalizedItems[tonumber(val)] = true
                    elseif val == true or val == 1 then
                        normalizedItems[tonumber(k) or k] = true
                    else
                        normalizedItems[tonumber(k) or k] = val
                    end
                end
                listObj.items = normalizedItems
            end

            self:MarkPriorityDirty(listObj.name)
        end

        if DesolateLootcouncil.SendMessage then
            DesolateLootcouncil:SendMessage("DLC_PRIORITY_UPDATED")
        end
    end

    -- 4. Item Manager Content
    local incomingIM = data.ItemManagerContent or data.IM
    if incomingIM then
        p.PriorityLists = p.PriorityLists or {}
        p.imTimestamps = p.imTimestamps or {}

        for _, incoming in ipairs(incomingIM) do
            local listObj = nil
            for _, localList in ipairs(p.PriorityLists) do
                if localList.name == incoming.name then
                    listObj = localList
                    break
                end
            end
            if not listObj then
                listObj = { name = incoming.name, players = {}, items = {} }
                table.insert(p.PriorityLists, listObj)
            end

            if incoming.items then
                local normalizedItems = {}
                local isCorruptedSequential = true
                local count = 0

                for k, val in pairs(incoming.items) do
                    local itemID = nil
                    if type(k) == "number" and (type(val) == "number" or (type(val) == "string" and tonumber(val))) and val ~= true and val ~= false then
                        -- Array format: items = { 1001, 1002, ... }
                        itemID = tonumber(val)
                    elseif val == true or val == 1 then
                        -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Dictionary format: items = { [1001] = true }
                        itemID = tonumber(k) or k
                    else
                        itemID = tonumber(k) or tonumber(val) or k
                    end

                    if itemID then
                        normalizedItems[itemID] = true
                        count = count + 1
                        if type(itemID) ~= "number" or itemID > 200 then
                            isCorruptedSequential = false
                        end
                    end
                end

                -- Detect legacy corrupted 1..N sequential exports and restore valid defaults
                if isCorruptedSequential and count > 0 then
                    local defaultLists = (DesolateLootcouncil.Constants and DesolateLootcouncil.Constants.GetDefaultPriorityLists) and DesolateLootcouncil.Constants.GetDefaultPriorityLists() or {}
                    for _, def in ipairs(defaultLists) do
                        if def.name == listObj.name and def.items then
                            normalizedItems = DeepCopy(def.items)
                            break
                        end
                    end
                end

                listObj.items = normalizedItems
            else
                listObj.items = {}
            end

            self:MarkIMDirty(listObj.name)
        end

        if DesolateLootcouncil.SendMessage then
            DesolateLootcouncil:SendMessage("DLC_IM_UPDATED")
        end
    end

    -- 5. History
    if data.History then
        if data.History.session then
            p.session = DeepCopy(data.History.session)
            -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Sort live session awards chronologically on import
            if p.session.awarded and type(p.session.awarded) == "table" then
                table.sort(p.session.awarded, function(a, b)
                    return ParseItemTimestamp(a) < ParseItemTimestamp(b)
                end)
            end
            if p.session.publicAwardLog and type(p.session.publicAwardLog) == "table" then
                table.sort(p.session.publicAwardLog, function(a, b)
                    return ParseItemTimestamp(a) < ParseItemTimestamp(b)
                end)
            end
        end
        if data.History.AttendanceHistory then
            -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Clean, split multi-date, and sort history entries on import
            local cleanedList = {}
            for _, att in ipairs(data.History.AttendanceHistory) do
                local splitList = SplitMultiDateAttendanceEntry(att, DeepCopy)
                for _, subE in ipairs(splitList) do
                    table.insert(cleanedList, subE)
                end
            end

            if data.SingleRaidEvent and importToCurrent then
                p.AttendanceHistory = p.AttendanceHistory or {}
                for _, incomingEntry in ipairs(cleanedList) do
                    local updated = false
                    if incomingEntry.sessionID then
                        for idx, localEntry in ipairs(p.AttendanceHistory) do
                            if localEntry.sessionID == incomingEntry.sessionID then
                                p.AttendanceHistory[idx] = DeepCopy(incomingEntry)
                                updated = true
                                break
                            end
                        end
                    end
                    if not updated then
                        table.insert(p.AttendanceHistory, 1, DeepCopy(incomingEntry))
                    end
                end
            else
                p.AttendanceHistory = cleanedList
            end

            -- Ensure AttendanceHistory is always sorted descending by date/ID
            table.sort(p.AttendanceHistory, function(a, b)
                local sA = tostring(a.date or a.sessionID or "")
                local sB = tostring(b.date or b.sessionID or "")
                return sA > sB
            end)
        end
        if data.History.PriorityLog then p.PriorityLog = DeepCopy(data.History.PriorityLog) end
        if data.History.SessionPositionLog then
            if data.SingleRaidEvent and importToCurrent then
                p.SessionPositionLog = p.SessionPositionLog or {}
                for key, bucket in pairs(data.History.SessionPositionLog) do
                    p.SessionPositionLog[key] = DeepCopy(bucket)
                end
            else
                p.SessionPositionLog = DeepCopy(data.History.SessionPositionLog)
            end
        end
        p.historyTimestamp = GetServerTime()

        if DesolateLootcouncil.SendMessage then
            DesolateLootcouncil:SendMessage("DLC_HISTORY_UPDATED")
        end
        self:CompactRaidHistory(p, true)
    end

    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    return true, ""
end

--- Calculates and applies decay to a priority list.
---@param listObj table
--- Calculates and applies decay to a priority list.
---@param listObj table
---@param penalty number
---@param absentMap table
function DLC_API:CalculateListDecay(listObj, penalty, absentMap)
    local p = Priority()
    if p and p.CalculateListDecay then
        p:CalculateListDecay(listObj, penalty, absentMap)
    end
end

--- Returns a colored difficulty badge string (e.g. |cff1eff00[NHC]|r, |cff0070dd[HC]|r, |cffff8000[M]|r, |cff00ccff[LFR]|r)
---@param difficultyID number|string|nil
---@param bossName string|nil
---@return string|nil
function DLC_API:GetDifficultyBadge(difficultyID, bossName)
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
function DLC_API:StripDifficultySuffix(bossName)
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
    return clean:match("^%s*(.-)%s*$") or clean
end




