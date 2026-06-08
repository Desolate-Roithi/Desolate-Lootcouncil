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
    StaticPopup_Show("DLC_ENABLE_AUTOPASS")
end

--- Whispers the selected data type ("PRIORITY" or "ROSTER") to raid officers.
---@param dataType string
---@param payload table?
function DLC_API:ShareDataWithOfficers(dataType, payload)
    local CommMod = DesolateLootcouncil:GetModule("Comm", true)
    if CommMod and CommMod.ShareDataWithOfficers then
        CommMod:ShareDataWithOfficers(dataType, payload)
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

--- Generates a serialized profile export string based on selected category options.
---@param selection table<string, boolean>
---@return string
function DLC_API:ExportProfileData(selection)
    local p = DesolateLootcouncil.db.profile
    local data = {}

    if selection["Config"] then
        data.config = {
            minLootQuality = p.minLootQuality,
            enableAutoLoot = p.enableAutoLoot,
            DecayConfig = p.DecayConfig,
        }
    end
    if selection["Roster"] then
        data.Roster = {
            MainRoster = p.MainRoster,
            playerRoster = p.playerRoster
        }
    end
    if selection["PriorityLists"] then
        data.PriorityListsStructure = {}
        if p.PriorityLists then
            for idx, list in ipairs(p.PriorityLists) do
                table.insert(data.PriorityListsStructure, { name = list.name })
            end
        end
    end
    if selection["PriorityContent"] then
        data.PriorityListsContent = p.PriorityLists
    end
    if selection["IM"] then
        data.ItemManagerContent = {}
        if p.PriorityLists then
            for idx, list in ipairs(p.PriorityLists) do
                table.insert(data.ItemManagerContent, {
                    name = list.name,
                    items = list.items
                })
            end
        end
    end
    if selection["History"] then
        data.History = {
            session = p.session,
            AttendanceHistory = p.AttendanceHistory,
            PriorityLog = p.PriorityLog
        }
    end

    local serialized = DesolateLootcouncil:Serialize(data)
    local encoded = DesolateLootcouncil.Base64 and DesolateLootcouncil.Base64:Encode(serialized) or serialized
    return encoded
end

--- Imports profile data from a serialized string and switches to the new profile.
---@param importStringRaw string
---@param importName string
---@return boolean success, string errorMsg
function DLC_API:ImportProfileData(importStringRaw, importName)
    if not importStringRaw or importStringRaw == "" then
        return false, "Import Error: String is empty."
    end
    if not importName or importName == "" then
        return false, "Import Error: Please specify a name for the new profile."
    end

    local decoded = importStringRaw
    if DesolateLootcouncil.Base64 and not string.find(decoded, "^{") then
        decoded = DesolateLootcouncil.Base64:Decode(importStringRaw)
    end

    local success, data = DesolateLootcouncil:Deserialize(decoded)
    if not success then
        return false, "Import Error: Invalid string format / Decode failed."
    end

    DesolateLootcouncil.db:SetProfile(importName)

    local p = DesolateLootcouncil.db.profile
    if data.config then
        for k, v in pairs(data.config) do p[k] = v end
    end
    if data.Roster then
        p.MainRoster = data.Roster.MainRoster
        p.playerRoster = data.Roster.playerRoster
    end
    if data.PriorityListsContent then
        for idx, list in ipairs(data.PriorityListsContent) do
            if list.items then
                local normalizedItems = {}
                for id, val in pairs(list.items) do
                    normalizedItems[tonumber(id) or id] = val
                end
                list.items = normalizedItems
            end
        end
        p.PriorityLists = data.PriorityListsContent
    elseif data.PriorityListsStructure then
        local newLists = {}
        for idx, l in ipairs(data.PriorityListsStructure) do
            table.insert(newLists, { name = l.name, players = {}, items = {} })
        end
        p.PriorityLists = newLists
    end
    if data.ItemManagerContent then
        p.PriorityLists = p.PriorityLists or {}
        for idx, incoming in ipairs(data.ItemManagerContent) do
            local listObj = nil
            for key, localList in ipairs(p.PriorityLists) do
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
                for id, val in pairs(incoming.items) do
                    normalizedItems[tonumber(id) or id] = val
                end
                listObj.items = normalizedItems
            else
                listObj.items = {}
            end

            self:MarkIMDirty(listObj.name)
        end
    end
    if data.History then
        if data.History.session then p.session = data.History.session end
        if data.History.AttendanceHistory then p.AttendanceHistory = data.History.AttendanceHistory end
        if data.History.PriorityLog then p.PriorityLog = data.History.PriorityLog end
    end

    return true, ""
end

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



