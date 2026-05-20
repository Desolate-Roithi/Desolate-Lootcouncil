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
    return DesolateLootcouncil.db.profile
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
function DLC_API:SendVote(guid, voteType)
    local s = Session()
    if s and s.SendVote then s:SendVote(guid, voteType) end
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

--- Broadcasts the current Item Manager lists to the raid (IM_SYNC).
function DLC_API:SyncItemManagerToRaid()
    local c = Comm()
    local db = DesolateLootcouncil.db.profile
    if not c or not db.PriorityLists then return end
    local syncData = {}
    for _, list in ipairs(db.PriorityLists) do
        syncData[list.name] = list.items
    end
    c:SendComm("IM_SYNC", syncData)
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
