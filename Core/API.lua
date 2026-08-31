local _, AT = ...
if AT.abortLoad then return end

---@class DesolateLootcouncilAPI
--- Public Data Abstraction Layer (DAL) and stateless facade for Desolate Lootcouncil.
--- Wraps subsystem operations to protect internal state and isolate execution paths.
local DLC_API = {}
AT.DLC_API = DLC_API
DesolateLootcouncil.API = DLC_API

local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

-- ---------------------------------------------------------------------------
-- Top-Level Module Resolution Accessors
-- ---------------------------------------------------------------------------
local function Roster() return DesolateLootcouncil:GetModule("Roster", true) end
local function Attendance() return DesolateLootcouncil:GetModule("Attendance", true) or DesolateLootcouncil:GetModule("Roster", true) end
local function Priority() return DesolateLootcouncil:GetModule("Priority", true) end
local function ItemCatalog() return DesolateLootcouncil:GetModule("ItemCatalog", true) or DesolateLootcouncil:GetModule("Loot", true) end
local function ItemManager() return DesolateLootcouncil:GetModule("ItemManager", true) or DesolateLootcouncil:GetModule("ItemCatalog", true) end
local function Voting() return DesolateLootcouncil:GetModule("Voting", true) end
local function Loot() return DesolateLootcouncil:GetModule("Loot", true) end
local function Comm() return DesolateLootcouncil:GetModule("Comm", true) end
local function Sync() return DesolateLootcouncil:GetModule("Sync", true) end
local function UI_Theme() return DesolateLootcouncil:GetModule("UI_Theme", true) end
local function Session() return DesolateLootcouncil:GetModule("Session", true) end
local function Trade() return DesolateLootcouncil:GetModule("Trade", true) end
local function Simulation() return DesolateLootcouncil:GetModule("Simulation", true) end
local function Audit() return DesolateLootcouncil:GetModule("Audit", true) end
local function Serializer() return DesolateLootcouncil.Serializer end
local function Persistence() return DesolateLootcouncil.Persistence end

-- ===========================================================================
-- 1. CORE / DATABASE / ACCESS CONTROL API
-- ===========================================================================

--- Returns the active profile database table.
---@return table
function DLC_API:GetDB()
    return DesolateLootcouncil.db and DesolateLootcouncil.db.profile
end

--- Prints a formatted message to the chat frame.
---@param msg string
function DLC_API:Print(msg)
    DesolateLootcouncil:Print(msg)
end

--- Returns true if the local player has officer or Loot Master permissions.
---@return boolean
function DLC_API:AmIOfficerOrLM()
    return DesolateLootcouncil:AmIOfficerOrLM()
end

--- Alias for AmIOfficerOrLM.
---@return boolean
function DLC_API:IsOfficerOrLM()
    return DesolateLootcouncil:AmIOfficerOrLM()
end

--- Returns true if the player (or local player if name is omitted) is an officer.
---@param name string?
---@return boolean
function DLC_API:IsOfficer(name)
    if not name or name == "" then
        return DesolateLootcouncil:IsOfficer()
    end
    local r = Roster()
    if r and r.IsOfficer then return r:IsOfficer(name) end
    local main = self:GetMain(name) or name
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    return (db and db.MainRoster and db.MainRoster[main] and db.MainRoster[main].isOfficer) or false
end

--- Returns true if the local player is currently the active Loot Master.
---@return boolean
function DLC_API:IsLootMaster()
    return (DesolateLootcouncil.AmILootMaster and DesolateLootcouncil:AmILootMaster()) or DesolateLootcouncil.amILM or false
end

--- Alias for IsLootMaster.
---@return boolean
function DLC_API:AmILootMaster()
    return self:IsLootMaster()
end

--- Returns the configured name of the Loot Master.
---@return string
function DLC_API:GetLootMasterName()
    return (DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.configuredLM) or DesolateLootcouncil.activeLootMaster or ""
end

--- Returns the name of the active Loot Master discovered from group comms.
---@return string?
function DLC_API:GetActiveLootMaster()
    return DesolateLootcouncil.activeLootMaster
end

--- Returns the active Master Looter unit name.
---@return string?
function DLC_API:GetMasterLooter()
    return (DesolateLootcouncil.GetMasterLooter and DesolateLootcouncil:GetMasterLooter()) or DesolateLootcouncil.activeLootMaster or ""
end

--- Returns whether test simulation mode is active.
---@return boolean
function DLC_API:IsTestMode()
    return DesolateLootcouncil.isTestMode or false
end

--- Returns the current addon semantic version string.
---@return string
function DLC_API:GetVersion()
    return DesolateLootcouncil.version or "0.0.0"
end

--- Returns the map of active addon users detected in the group.
---@return table<string, boolean>
function DLC_API:GetActiveAddonUsers()
    return DesolateLootcouncil.activeAddonUsers or {}
end

--- Returns the number of simulated player instances currently active.
---@return number
function DLC_API:GetSimulationCount()
    local sim = Simulation()
    return (sim and sim.GetCount and sim:GetCount()) or 0
end

--- Returns true if a named player is a test simulated entity.
---@param name string
---@return boolean
function DLC_API:IsSimulatedPlayer(name)
    local sim = Simulation()
    return (sim and sim.IsSimulatedPlayer and sim:IsSimulatedPlayer(name)) or false
end

--- Returns an array of simulated voters pending a response for an item.
---@param guid string
---@param votedPlayers table
---@return table|nil
function DLC_API:GetPendingSimVoters(guid, votedPlayers)
    local sim = Simulation()
    return sim and sim.GetPendingVoters and sim:GetPendingVoters(guid, votedPlayers)
end

--- Simulates raider votes on currently active bidding items during test sessions.
---@return number
function DLC_API:SimulateRaiderVotes()
    local sim = Simulation()
    return (sim and sim.SimulateRaiderVotes and sim:SimulateRaiderVotes()) or 0
end

--- Auto-awards the next active bidding item during an interactive simulation.
---@return table|nil item, string|nil winner
function DLC_API:AutoAwardNextSimItem()
    local sim = Simulation()
    if sim and sim.AutoAwardNext then
        return sim:AutoAwardNext()
    end
    return nil, nil
end

--- Completes and verifies the active interactive test session.
function DLC_API:CompleteAndVerifySim()
    local sim = Simulation()
    if sim and sim.CompleteAndVerify then
        sim:CompleteAndVerify()
    end
end

--- Stops and cleans up the active interactive loot test.
function DLC_API:StopInteractiveLootTest()
    local sim = Simulation()
    if sim and sim.StopInteractiveLootTest then
        sim:StopInteractiveLootTest()
    end
end


--- Closes all open addon UI windows.
function DLC_API:CloseAllWindows()
    local UI = DesolateLootcouncil:GetModule("UI", true)
    if UI and UI.CloseAllWindows then UI:CloseAllWindows() end
end

--- Returns true if an item is categorized as a recipe.
---@param item string|number|nil
---@return boolean
function DLC_API:IsRecipe(item)
    if not item then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(item)
    return classID == 9
end

--- Returns localized and unlocalized class token strings for a player or unit.
---@param unitOrName string
---@return string? localizedClass, string? classFileName
function DLC_API:GetUnitClass(unitOrName)
    if not unitOrName or unitOrName == "" then return nil, nil end
    if DesolateLootcouncil.SafeGetUnitClass then return DesolateLootcouncil:SafeGetUnitClass(unitOrName) end
    local loc, file = UnitClass(unitOrName)
    return loc or file or "WARRIOR", file or "WARRIOR"
end

--- Returns a short display name without realm suffix.
---@param name string
---@return string
function DLC_API:GetDisplayName(name)
    if not name or name == "" then return "" end
    return name:match("^([^%-]+)") or name
end

--- Returns the full "Name-Realm" string for a unit token.
---@param unit string
---@return string
function DLC_API:GetFullName(unit)
    if not unit or unit == "" then return "" end
    local name, realm = UnitName(unit)
    if not name then return unit end
    if not realm or realm == "" then realm = GetRealmName() end
    return name .. "-" .. realm
end

--- Returns a normalised score key for cross-realm player comparison.
---@param name string
---@return string?
function DLC_API:GetScoreName(name)
    if not name or name == "" then return nil end
    if DesolateLootcouncil.GetScoreName then
        return DesolateLootcouncil:GetScoreName(name)
    end
    local safeLower = (type(strlower) == "function" and strlower) or string.lower
    local lowName = safeLower(name)
    if not string.find(lowName, "-") then
        local realm = (GetRealmName and safeLower(GetRealmName()):gsub("%s+", "")) or ""
        if realm ~= "" then lowName = lowName .. "-" .. realm end
    end
    return lowName:gsub("%s+", "")
end

--- Returns whether debug logging mode is enabled.
---@return boolean
function DLC_API:GetDebugMode()
    return DesolateLootcouncil.db.profile.debugMode
end

--- Enables or disables debug logging mode.
---@param val boolean
function DLC_API:SetDebugMode(val)
    DesolateLootcouncil.db.profile.debugMode = val
    DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
end

--- Returns the active UI theme identifier.
---@return string
function DLC_API:GetActiveTheme()
    return DesolateLootcouncil.db.profile.activeTheme or "Midnight"
end

--- Sets the active UI theme and updates open windows.
---@param val string
function DLC_API:SetActiveTheme(val)
    DesolateLootcouncil.db.profile.activeTheme = val
    local theme = UI_Theme()
    if theme and theme.ApplyThemeToAllOpenWindows then theme:ApplyThemeToAllOpenWindows() end
end

-- ===========================================================================
-- 2. PRIORITY SYSTEM SURFACE
-- ===========================================================================

--- Returns the raw priority lists table.
---@return table
function DLC_API:GetPriorityLists()
    local p = Priority()
    return (p and p.GetPriorityLists and p:GetPriorityLists()) or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile.PriorityLists) or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile.Priority) or {}
end

--- Returns the database profile table used by Priority.
---@return table
function DLC_API:GetPriorityDB()
    return DesolateLootcouncil.db and DesolateLootcouncil.db.profile or {}
end

--- Returns an ordered array of priority list names.
---@return string[]
function DLC_API:GetPriorityListNames()
    local p = Priority()
    return (p and p.GetPriorityListNames and p:GetPriorityListNames()) or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile.Priority and DesolateLootcouncil.db.profile.Priority.names) or {}
end

--- Returns the localized title of a priority list if available.
---@param listName string?
---@return string
function DLC_API:GetLocalizedListName(listName)
    if not listName or listName == "" then return "" end
    local p = Priority()
    return (p and p.GetLocalizedListName and p:GetLocalizedListName(listName)) or listName
end

--- Returns the active priority list object.
---@return table
function DLC_API:GetActivePriorityList()
    local p = Priority()
    return (p and p.GetActivePriorityList and p:GetActivePriorityList()) or {}
end

--- Returns a specific priority list by name or index.
---@param nameOrIdx string|number
---@return table?
function DLC_API:GetPriorityList(nameOrIdx)
    local p = Priority()
    if p and p.GetPriorityList then
        local res = p:GetPriorityList(nameOrIdx)
        if res then return res end
    end
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if db then
        if db.PriorityLists then
            if type(nameOrIdx) == "number" then return db.PriorityLists[nameOrIdx] end
            if type(nameOrIdx) == "string" then
                for _, lst in ipairs(db.PriorityLists) do if lst.name == nameOrIdx then return lst end end
            end
        end
        if db.Priority then
            if type(nameOrIdx) == "number" then return db.Priority.lists and db.Priority.lists[nameOrIdx] end
            if type(nameOrIdx) == "string" then
                if db.Priority[nameOrIdx] then return db.Priority[nameOrIdx] end
                if db.Priority.lists then
                    for _, lst in ipairs(db.Priority.lists) do if lst.name == nameOrIdx then return lst end end
                end
            end
        end
    end
    return nil
end

--- Returns a player's rank index in the specified list.
---@param listName string
---@param playerName string
---@return number?
function DLC_API:GetPriorityRank(listName, playerName)
    local p = Priority()
    return p and p.GetPriorityRank and p:GetPriorityRank(listName, playerName)
end

--- Returns the 1-based priority rank of playerName in the named list (alias for UI).
---@param playerName string
---@param category string
---@return number rank
function DLC_API:GetPlayerRankInList(playerName, category)
    local p = Priority()
    if p and p.GetPlayerRankInList then return p:GetPlayerRankInList(playerName, category) end
    return self:GetPriorityRank(category, playerName) or 999
end

--- Returns the candidate with the highest rank in a list.
---@param listName string
---@param candidates string[]
---@return string? winner, number? rank
function DLC_API:GetPriorityHighest(listName, candidates)
    local p = Priority()
    if p and p.GetPriorityHighest then return p:GetPriorityHighest(listName, candidates) end
    return nil, nil
end

--- Returns the candidate with the highest priority for an item ID.
---@param itemID number
---@param candidateNames string[]
---@return string? winner
function DLC_API:GetPriorityWinner(itemID, candidateNames)
    local p = Priority()
    return p and p.GetWinner and p:GetWinner(itemID, candidateNames)
end

--- Returns the priority list assigned to a given item ID.
---@param itemID number
---@return table?
function DLC_API:GetPriorityListForItem(itemID)
    local p = Priority()
    return p and p.GetListForItem and p:GetListForItem(itemID)
end

--- Moves a player up or down in a priority list.
---@param listName string
---@param player string
---@param direction string "UP"|"DOWN"
function DLC_API:MovePlayerInPriority(listName, player, direction)
    local p = Priority()
    if p and p.MovePlayerInPriority then p:MovePlayerInPriority(listName, player, direction) end
end

--- Moves a player from one index to another in a priority list.
---@param listNameOrIdx string|number
---@param fromIdx number
---@param toIdx number
function DLC_API:MovePlayerInPriorityList(listNameOrIdx, fromIdx, toIdx)
    local p = Priority()
    if p then
        if p.MovePlayerInPriorityList then
            p:MovePlayerInPriorityList(listNameOrIdx, fromIdx, toIdx)
        elseif p.MovePlayerInList then
            p:MovePlayerInList(listNameOrIdx, fromIdx, toIdx)
        end
    end
end

--- Moves a player to the top of a priority list.
---@param listName string
---@param player string
function DLC_API:MovePlayerToTop(listName, player)
    local p = Priority()
    if p and p.MovePlayerToTop then p:MovePlayerToTop(listName, player) end
end

--- Moves a player to the bottom of a priority list.
---@param listName string
---@param player string
function DLC_API:MovePlayerToBottom(listName, player)
    local p = Priority()
    if p and p.MovePlayerToBottom then p:MovePlayerToBottom(listName, player) end
end

--- Adds a player to the end of a priority list.
---@param listName string
---@param player string
function DLC_API:AddPlayerToPriority(listName, player)
    local p = Priority()
    if p and p.AddPlayerToPriority then p:AddPlayerToPriority(listName, player) end
end

--- Removes a player from a priority list.
---@param listName string
---@param player string
function DLC_API:RemovePlayerFromPriority(listName, player)
    local p = Priority()
    if p and p.RemovePlayerFromPriority then p:RemovePlayerFromPriority(listName, player) end
end

--- Adds a new empty priority list.
---@param name string
function DLC_API:AddPriorityList(name)
    local p = Priority()
    if p and p.AddPriorityList then p:AddPriorityList(name) end
end

--- Renames a priority list by index.
---@param idx number
---@param name string
function DLC_API:RenamePriorityList(idx, name)
    local p = Priority()
    if p and p.RenamePriorityList then p:RenamePriorityList(idx, name) end
end

--- Removes a priority list by index.
---@param idx number
function DLC_API:RemovePriorityList(idx)
    local p = Priority()
    if p and p.RemovePriorityList then p:RemovePriorityList(idx) end
end

--- Shuffles all priority lists for a new season.
function DLC_API:ShuffleLists()
    local p = Priority()
    if p and p.ShuffleLists then p:ShuffleLists() end
end

--- Syncs unlisted active roster members into existing priority lists.
function DLC_API:SyncMissingPlayers()
    local p = Priority()
    if p and p.SyncMissingPlayers then p:SyncMissingPlayers() end
end

--- Appends an immutable structured audit event into the ledger.
---@param action string
---@param player string|nil
---@param listName string|nil
---@param details string|nil
---@param sessionID number|string|nil
---@return table|nil
function DLC_API:LogAuditEvent(action, player, listName, details, sessionID)
    local a = Audit()
    if a and a.Log then
        return a:Log(action, nil, player, listName, details, sessionID)
    end
    return nil
end

--- Returns filtered audit log entries.
---@param sessionID number|string|nil
---@param actionFilter string|nil
---@return table[]
function DLC_API:GetAuditLog(sessionID, actionFilter)
    local a = Audit()
    if a and a.GetLog then
        return a:GetLog(sessionID, actionFilter)
    end
    return (DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.AuditLog) or {}
end

--- Exports the audit log as a formatted text ledger.
---@param sessionID number|string|nil
---@return string
function DLC_API:ExportAuditLog(sessionID)
    local a = Audit()
    if a and a.ExportLog then
        return a:ExportLog(sessionID)
    end
    return ""
end

--- Logs an audit event to the cryptographic ledger.
---@param action string
---@param listName string?
---@param player string?
---@param itemID number|string?
---@param details string?
---@param sessionID number|string?
function DLC_API:LogAudit(action, listName, player, itemID, details, sessionID)
    local a = Audit()
    if a and a.Log then
        return a:Log(action, listName, player, itemID, details, sessionID)
    end
    return nil
end

--- Broadcasts loot history sync to group/raid officers.
function DLC_API:BroadcastHistorySync()
    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if Comm and Comm.SendHistorySync then
        Comm:SendHistorySync()
    end
end

--- Starts the interactive live loot simulation.
---@return boolean
function DLC_API:StartInteractiveLootTest()
    local sim = Simulation()
    return (sim and sim.StartInteractiveLootTest and sim:StartInteractiveLootTest()) or false
end

--- Returns the priority history audit log lines (Backward compatibility).
---@return table[]
function DLC_API:GetPriorityLog()
    local a = Audit()
    if a and a.GetLog then return a:GetLog(nil, "PRIO") end
    return DesolateLootcouncil.db.profile.AuditLog or DesolateLootcouncil.db.profile.PriorityLog or {}
end

--- Marks a Priority list as modified by updating its timestamp.
---@param listName string
function DLC_API:MarkPriorityDirty(listName)
    if not listName or listName == "" then return end
    local db = DesolateLootcouncil.db.profile
    if not db.priorityTimestamps then db.priorityTimestamps = {} end
    db.priorityTimestamps[listName] = GetServerTime()
end

--- Calculates and applies decay penalties to absent players in a list.
---@param listObj table
---@param penalty number
---@param absentMap table
function DLC_API:CalculateListDecay(listObj, penalty, absentMap)
    local p = Priority()
    if p and p.CalculateListDecay then p:CalculateListDecay(listObj, penalty, absentMap) end
end

--- Returns a list of decay pattern matchers and tags across all registered locales.
---@return table
function DLC_API:GetDecayPatterns()
    local p = Priority()
    if p and p.GetDecayPatterns then return p:GetDecayPatterns() end
    local rawKey = "[Decay] %s moved from position #%d to #%d in %s list (+%d decay for absence)."
    local templates = { [rawKey] = true, ["[Verfall] %s wurde von Position #%d auf #%d in Liste %s verschoben (+%d Verfall wegen Abwesenheit)."] = true }
    local AceLocale = LibStub and ((LibStub.GetLibrary and LibStub:GetLibrary("AceLocale-3.0", true)) or LibStub("AceLocale-3.0", true))
    if AceLocale and AceLocale.apps then
        for _, appLocales in pairs(AceLocale.apps) do
            if type(appLocales) == "table" then
                for _, locTable in pairs(appLocales) do
                    if type(locTable) == "table" and locTable[rawKey] and type(locTable[rawKey]) == "string" then
                        templates[locTable[rawKey]] = true
                    end
                end
            end
        end
    end
    local list = {}
    for template in pairs(templates) do
        local tag = template:match("^(%b[])") or "[Decay]"
        local pat = template:gsub("%%s", "___STR___", 1):gsub("%%d", "___NUM___", 1):gsub("%%d", "___NUM___", 1):gsub("%%s", "___ANY___", 1):gsub("%%d", "___PEN___", 1)
        pat = pat:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        pat = pat:gsub("___STR___", "(.-)"):gsub("___NUM___", "%%d+"):gsub("___ANY___", ".-"):gsub("___PEN___", "(%%d+)")
        table.insert(list, { tag = tag, matchPattern = pat, template = template })
    end
    return list
end

--- Checks if a log message string represents an automated decay event in any language.
---@param str string
---@return boolean
function DLC_API:IsDecayLogMessage(str)
    local msg = (type(str) == "string" and str) or (type(self) == "string" and self)
    if not msg or msg == "" then return false end
    local p = Priority()
    if p and p.IsDecayLogMessage then return p:IsDecayLogMessage(msg) end
    local patterns = DLC_API:GetDecayPatterns()
    for _, item in ipairs(patterns) do
        if msg:find(item.tag, 1, true) then return true end
    end
    return msg:find("[Decay]", 1, true) ~= nil or msg:find("[Verfall]", 1, true) ~= nil
end

--- Parses player name and penalty amount from a decay log message.
---@param str string
---@return string? playerName, number? penalty
function DLC_API:ParseDecayLogMessage(str)
    local msg = (type(str) == "string" and str) or (type(self) == "string" and self)
    if not msg or msg == "" then return nil, nil end
    local p = Priority()
    if p and p.ParseDecayLogMessage then return p:ParseDecayLogMessage(msg) end
    local cleanStr = msg:gsub("^%[[^%]]+%]%s*", "")
    local patterns = DLC_API:GetDecayPatterns()
    for _, item in ipairs(patterns) do
        local pName, pPen = cleanStr:match(item.matchPattern)
        if pName then return pName, tonumber(pPen) end
    end
    local pName, pPen = cleanStr:match("%[Decay%]%s+(.-)%s+moved from position #%d+ to #%d+ in .- %(%+(%d+)")
    if not pName then pName, pPen = cleanStr:match("%[Verfall%]%s+(.-)%s+wurde von Position #%d+ auf #%d+ in .- %(%+(%d+)") end
    return pName, tonumber(pPen)
end

-- ===========================================================================
-- 3. ITEM MANAGER MODULE SURFACE
-- ===========================================================================

--- Returns the table containing all Item Manager lists.
---@return table
function DLC_API:GetIMLists()
    local im = ItemManager()
    return (im and im.GetIMLists and im:GetIMLists()) or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile.ItemManager) or {}
end

--- Returns the database profile table used by Item Manager.
---@return table
function DLC_API:GetItemManagerDB()
    return DesolateLootcouncil.db and DesolateLootcouncil.db.profile or {}
end

--- Returns the active Item Manager list table.
---@return table
function DLC_API:GetActiveIMList()
    local im = ItemManager()
    return (im and im.GetActiveIMList and im:GetActiveIMList()) or {}
end

--- Returns an Item Manager list by name.
---@param name string
---@return table?
function DLC_API:GetIMList(name)
    local im = ItemManager()
    return im and im.GetIMList and im:GetIMList(name)
end

--- Adds an item ID to the specified Item Manager list.
---@param listName string
---@param itemID number
function DLC_API:AddItemToIMList(listName, itemID)
    local im = ItemManager()
    if im and im.AddItemToIMList then im:AddItemToIMList(listName, itemID) end
end

--- Removes an item ID from the specified Item Manager list.
---@param listName string
---@param itemID number
function DLC_API:RemoveItemFromIMList(listName, itemID)
    local im = ItemManager()
    if im and im.RemoveItemFromIMList then im:RemoveItemFromIMList(listName, itemID) end
end

--- Adds a new empty Item Manager list.
---@param name string
function DLC_API:AddIMList(name)
    local im = ItemManager()
    if im and im.AddIMList then im:AddIMList(name) end
end

--- Renames an Item Manager list by index.
---@param idx number
---@param name string
function DLC_API:RenameIMList(idx, name)
    local im = ItemManager()
    if im and im.RenameIMList then im:RenameIMList(idx, name) end
end

--- Removes an Item Manager list by index.
---@param idx number
function DLC_API:RemoveIMList(idx)
    local im = ItemManager()
    if im and im.RemoveIMList then im:RemoveIMList(idx) end
end

--- Marks an Item Manager list as modified by updating its timestamp.
---@param listName string
function DLC_API:MarkIMDirty(listName)
    if not listName or listName == "" then return end
    local db = DesolateLootcouncil.db.profile
    if not db.imTimestamps then db.imTimestamps = {} end
    db.imTimestamps[listName] = GetServerTime()
end

--- Returns the priority list name associated with an item ID.
---@param itemID number
---@return string?
function DLC_API:GetItemPriorityList(itemID)
    local im = ItemManager()
    return im and im.GetItemPriorityList and im:GetItemPriorityList(itemID)
end

--- Returns the category name for an itemID (alias for GetItemPriorityList).
---@param itemID number
---@return string?
function DLC_API:GetItemCategory(itemID)
    local cat = ItemCatalog()
    if cat and cat.GetItemCategory then return cat:GetItemCategory(itemID) end
    local im = ItemManager()
    if im and im.GetItemCategory then return im:GetItemCategory(itemID) end
    return self:GetItemPriorityList(itemID)
end

--- Assigns an itemID to a priority list by index.
---@param itemID number
---@param listIndex number|string
function DLC_API:SetItemCategory(itemID, listIndex)
    local cat = ItemCatalog()
    if cat and cat.SetItemCategory then
        cat:SetItemCategory(itemID, listIndex)
        return
    end
    local im = ItemManager()
    if im and im.SetItemCategory then
        im:SetItemCategory(itemID, listIndex)
    elseif im and im.AddItemToIMList then
        local lists = self:GetIMLists()
        local target = type(listIndex) == "number" and lists[listIndex] or self:GetIMList(listIndex)
        if target and target.name then im:AddItemToIMList(target.name, itemID) end
    end
end

--- Removes an item from all priority list assignments.
---@param itemID number
function DLC_API:UnassignItem(itemID)
    local cat = ItemCatalog()
    if cat and cat.UnassignItem then
        cat:UnassignItem(itemID)
        return
    end
    local im = ItemManager()
    if im and im.UnassignItem then
        im:UnassignItem(itemID)
    elseif im and im.RemoveItemFromIMList then
        local lists = self:GetIMLists()
        if type(lists) == "table" then
            for _, list in ipairs(lists) do
                if list.name then im:RemoveItemFromIMList(list.name, itemID) end
            end
        end
    end
end

--- Adds a manual item (by link/name/ID) to a priority list.
---@param rawLink string
---@param listIndex number|string
function DLC_API:AddManagedItem(rawLink, listIndex)
    local im = ItemManager()
    if im and im.AddManagedItem then
        im:AddManagedItem(rawLink, listIndex)
    elseif im and im.AddItemToIMList then
        local lists = self:GetIMLists()
        local targetList = type(listIndex) == "number" and lists[listIndex] or self:GetIMList(listIndex)
        if targetList and targetList.name then
            local itemID = tonumber(rawLink) or (type(rawLink) == "string" and tonumber(rawLink:match("item:(%d+)")))
            if itemID then im:AddItemToIMList(targetList.name, itemID) end
        end
    end
end

--- Adds a batch of items to priority lists.
---@param items table[]
function DLC_API:AddManagedItemBatch(items)
    local im = ItemManager()
    if im and im.AddManagedItemBatch then
        im:AddManagedItemBatch(items)
    elseif type(items) == "table" then
        for _, entry in ipairs(items) do
            if entry.rawLink and entry.listIndex then
                self:AddManagedItem(entry.rawLink, entry.listIndex)
            end
        end
    end
end

--- Returns packaged Item Manager data for synchronization.
---@param isManual boolean?
---@return table|nil
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

--- Manually broadcasts Item Manager lists to the raid group.
function DLC_API:SyncItemManagerToRaid()
    local s = Sync()
    if s and s.SyncItemManagerToRaid then s:SyncItemManagerToRaid() end
end

--- Automatically broadcasts Item Manager lists if appropriate.
function DLC_API:AutoSyncItemManager()
    local s = Sync()
    if s and s.AutoSyncItemManager then s:AutoSyncItemManager() end
end

-- ===========================================================================
-- 4. VOTING & SESSION SURFACE
-- ===========================================================================

--- Returns the active voting session structure.
---@return table?
function DLC_API:GetActiveSession()
    local v = Voting()
    return v and v.GetActiveSession and v:GetActiveSession()
end

--- Starts a new voting session for an item or loot table.
---@param itemLinkOrTable string|table
---@param eligiblePlayers string[]?
function DLC_API:StartSession(itemLinkOrTable, eligiblePlayers)
    local v = Voting()
    if v and v.StartSession then v:StartSession(itemLinkOrTable, eligiblePlayers) end
end

--- Ends the currently active voting session.
function DLC_API:EndSession()
    local v = Voting()
    if v and v.EndSession then v:EndSession() end
end

--- Stops the currently active loot session.
function DLC_API:StopSession()
    local s = Session()
    if s and s.SendStopSession then
        s:SendStopSession()
    elseif DesolateLootcouncil.StopSession then
        DesolateLootcouncil:StopSession()
    else
        self:EndSession()
    end
end

--- Removes an item from the active bidding session.
---@param guid string
function DLC_API:RemoveSessionItem(guid)
    local s = Session()
    if s and s.RemoveSessionItem then
        s:RemoveSessionItem(guid)
    end
end

--- Returns true if bidding on an item has been closed.
---@param guid string
---@return boolean
function DLC_API:IsItemClosed(guid)
    local s = Session()
    if s and s.IsItemClosed then return s:IsItemClosed(guid) end
    return (s and s.closedItems and s.closedItems[guid] == true) or false
end


--- Closes an item for voting (LM action).
---@param guid string
function DLC_API:CloseItem(guid)
    local s = Session()
    if s then
        if s.SendCloseItem then
            s:SendCloseItem(guid)
        elseif s.CloseItem then
            s:CloseItem(guid)
        else
            s.closedItems = s.closedItems or {}
            s.closedItems[guid] = true
        end
    end
end

--- Reopens an item for revoting (LM action).
---@param guid string
function DLC_API:RevoteItem(guid)
    local s = Session()
    if s and s.SendReopenItem then
        local duration = (s.sessionDuration and s.sessionDuration > 0 and s.sessionDuration) or 300
        local expiry = GetServerTime() + duration
        s:SendReopenItem(guid, expiry)
    end
end

--- Returns true if LM handover can safely take place.
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

--- Refreshes themes across all loot and voting windows.
function DLC_API:RefreshLootAndVotingThemes()
    local s = Session()
    if s and s.RefreshLootAndVotingThemes then
        s:RefreshLootAndVotingThemes()
    end
end

--- Returns true if a voting session is actively running.
---@return boolean
function DLC_API:IsSessionActive()
    local s = Session()
    if s and s.IsActive then return s:IsActive() end
    local v = Voting()
    return (v and v.GetActiveSession and v:GetActiveSession() ~= nil) or false
end

--- Returns true if a raid attendance session is currently active.
---@return boolean
function DLC_API:IsRaidSessionActive()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    return (db and db.DecayConfig and db.DecayConfig.sessionActive == true) or false
end

--- Returns the item link for the active session.
---@return string?
function DLC_API:GetSessionItem()
    local v = Voting()
    return v and v.GetSessionItem and v:GetSessionItem()
end

--- Alias for GetSessionItem.
---@return string?
function DLC_API:GetActiveSessionItem()
    return self:GetSessionItem()
end

--- Returns the number of seconds remaining on the session timer.
---@return number seconds
function DLC_API:GetSessionTimeRemaining()
    local s = Session()
    return (s and s.GetTimeRemaining and s:GetTimeRemaining()) or 0
end

--- Returns the candidate players for the active session.
---@return string[]
function DLC_API:GetSessionCandidates()
    local v = Voting()
    return (v and v.GetSessionCandidates and v:GetSessionCandidates()) or {}
end

--- Returns the votes table for the active session.
---@return table
function DLC_API:GetVotes()
    local v = Voting()
    return (v and v.GetVotes and v:GetVotes()) or {}
end

--- Alias for GetVotes.
---@return table
function DLC_API:GetSessionVotes()
    return self:GetVotes()
end

--- Casts a vote for a candidate in the active session.
---@param voter string
---@param candidate string
---@param voteType string
---@param notes string?
function DLC_API:CastVote(voter, candidate, voteType, notes)
    local v = Voting()
    if v and v.CastVote then v:CastVote(voter, candidate, voteType, notes) end
end

--- Sends a vote for a specific item.
---@param guid string
---@param vote number|string
---@param note string?
function DLC_API:SendVote(guid, vote, note)
    local s = Session()
    if s and s.SendVote then s:SendVote(guid, vote, note); return end
    local v = Voting()
    if v and v.SendVote then v:SendVote(guid, vote, note)
    elseif v and v.CastVote then v:CastVote(UnitName("player"), guid, vote, note) end
end

--- Returns the pending outbound vote record for an item.
---@param guid string
---@return table?
function DLC_API:GetOutboundVote(guid)
    local v = Voting()
    return v and v.GetOutboundVote and v:GetOutboundVote(guid)
end

--- Cancels the local vote for an item.
---@param guid string
function DLC_API:CancelVote(guid)
    local s = Session()
    if s then
        if s.myLocalVotes then s.myLocalVotes[guid] = nil end
        if s.outboundVotes then s.outboundVotes[guid] = nil end
        if s.SendVote then s:SendVote(guid, 0, "") end
    end
    local v = Voting()
    if v then
        if v.myVotes then v.myVotes[guid] = nil end
        if v.CancelVote then v:CancelVote(guid) end
    end
    local UI_Voting = DesolateLootcouncil:GetModule("UI_Voting", true)
    if UI_Voting then
        if UI_Voting.myVotes then UI_Voting.myVotes[guid] = nil end
        if UI_Voting.votingFrame and UI_Voting.votingFrame:IsShown() then
            UI_Voting:ShowVotingWindow(nil, true)
        end
    end
end

--- Returns the local player's confirmed votes.
---@param guid string?
---@return table
function DLC_API:GetLocalVotes(guid)
    local s = Session()
    if s and s.myLocalVotes then
        if guid then return s.myLocalVotes[guid] or {} end
        return s.myLocalVotes
    end
    local v = Voting()
    return (v and v.GetLocalVotes and v:GetLocalVotes(guid)) or {}
end

--- Returns vote count and details for a candidate.
---@param candidate string
---@return table?
function DLC_API:GetCandidateVoteInfo(candidate)
    local v = Voting()
    return v and v.GetCandidateVoteInfo and v:GetCandidateVoteInfo(candidate)
end

--- Returns true if the voter has cast a vote in the current session.
---@param voter string
---@return boolean
function DLC_API:HasVoted(voter)
    local v = Voting()
    return (v and v.HasVoted and v:HasVoted(voter)) or false
end

--- Checks if all council members have submitted votes.
---@return boolean
function DLC_API:HaveAllCouncilMembersVoted()
    local s = Session()
    return (s and s.AllVoted and s:AllVoted()) or false
end

--- Returns the list of council members eligible to vote.
---@return string[]
function DLC_API:GetCouncilMembers()
    local v = Voting()
    return (v and v.GetCouncilMembers and v:GetCouncilMembers()) or {}
end

--- Returns the canonical item list for the current client role.
---@return table items
function DLC_API:GetBiddingList()
    local s = Session()
    if DesolateLootcouncil:AmILootMaster() then
        return (DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.session and DesolateLootcouncil.db.profile.session.bidding) or {}
    end
    return (s and s.clientLootList) or {}
end

--- Returns the awarded items list from db.profile.
---@return table awarded
function DLC_API:GetAwardedList()
    return (DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.session and DesolateLootcouncil.db.profile.session.awarded) or {}
end

--- Returns a set of GUIDs that have already been awarded.
---@return table<string, boolean>
function DLC_API:GetAwardedGUIDs()
    local result = {}
    for _, award in ipairs(self:GetAwardedList()) do
        if award.link then result[award.link] = true end
        if award.sourceGUID then result[award.sourceGUID] = true end
        if award.fullItemData and award.fullItemData.sourceGUID then
            result[award.fullItemData.sourceGUID] = true
        end
        if award.fullItemData and award.fullItemData.link then
            result[award.fullItemData.link] = true
        end
    end
    return result
end

--- Returns a structured view-model for all votes on a single item.
---@param guid string
---@return table?
function DLC_API:GetSessionItemVotes(guid)
    local s = Session()
    if not s or not s.sessionVotes then return nil end
    local votes = s.sessionVotes[guid]
    local closed = s.closedItems and s.closedItems[guid]
    return { guid = guid, isClosed = closed or false, votes = votes or {}, voteCount = votes and #votes or 0 }
end

--- Returns vote summary view-model for an item (alias for GetSessionItemVotes).
---@param guid string
---@return table?
function DLC_API:GetVoteSummary(guid)
    return self:GetSessionItemVotes(guid)
end


--- Returns item data table for a given GUID from bidding or client loot.
---@param guid string
---@return table?
function DLC_API:GetItemData(guid)
    if not guid then return nil end
    local s = Session()
    if s and s.GetItemData then
        local item = s:GetItemData(guid)
        if item then return item end
    end
    if DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.session then
        local bidding = DesolateLootcouncil.db.profile.session.bidding
        if bidding then
            for _, item in ipairs(bidding) do
                if (item.sourceGUID or item.link or item.guid) == guid or item.itemID == tonumber(guid) then
                    return item
                end
            end
        end
    end
    if s and s.clientLootList then
        for _, item in ipairs(s.clientLootList) do
            if (item.sourceGUID or item.link or item.guid) == guid or item.itemID == tonumber(guid) then
                return item
            end
        end
    end
    return nil
end


-- ===========================================================================
-- 5. LOOT & AWARD SURFACE
-- ===========================================================================

--- Awards an item to a winning player and updates priority and history.
---@param item string
---@param winner string
---@param reason string?
---@param extraInfo table?
function DLC_API:AwardItem(item, winner, reason, extraInfo)
    local l = Loot()
    if l and l.AwardItem then l:AwardItem(item, winner, reason, extraInfo) end
end

--- Returns the full award history.
---@return table
function DLC_API:GetAwardHistory()
    local l = Loot()
    return (l and l.GetAwardHistory and l:GetAwardHistory()) or {}
end

--- Returns award history filtered by criteria.
---@param filter table?
---@return table
function DLC_API:GetLootHistory(filter)
    local l = Loot()
    if l and l.GetHistory then return l:GetHistory(filter) end
    return self:GetAwardHistory()
end

--- Clears the award history log.
function DLC_API:ClearAwardHistory()
    local l = Loot()
    if l and l.ClearAwardHistory then l:ClearAwardHistory() end
end

--- Returns the N most recent awards.
---@param limit number
---@return table
function DLC_API:GetRecentAwards(limit)
    local l = Loot()
    return (l and l.GetRecentAwards and l:GetRecentAwards(limit)) or {}
end

--- Returns all awards won by a specific player.
---@param playerName string
---@return table
function DLC_API:GetPlayerAwards(playerName)
    local l = Loot()
    return (l and l.GetPlayerAwards and l:GetPlayerAwards(playerName)) or {}
end

--- Clears the backlog of loot items pending distribution.
function DLC_API:ClearLootBacklog()
    local l = Loot()
    if l and l.ClearLootBacklog then
        l:ClearLootBacklog()
    elseif DesolateLootcouncil.ClearLootBacklog then
        DesolateLootcouncil:ClearLootBacklog()
    elseif DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.session then
        DesolateLootcouncil.db.profile.session.backlog = {}
    end
end

--- Returns the backlog of unauctioned loot items.
---@return table
function DLC_API:GetLootBacklog()
    local session = DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.session
    if not session then return {} end
    if session.loot and #session.loot > 0 then
        return session.loot
    end
    return session.backlog or {}
end

--- Adds a manual item to the LM's loot backlog.
---@param rawLink string
function DLC_API:AddManualLootItem(rawLink)
    local l = Loot()
    if l and l.AddManualItem then
        l:AddManualItem(rawLink)
    elseif DesolateLootcouncil.AddManualLootItem then
        DesolateLootcouncil:AddManualLootItem(rawLink)
    end
end

--- Alias for AddManualLootItem.
---@param rawLink string
function DLC_API:AddManualItem(rawLink)
    self:AddManualLootItem(rawLink)
end

--- Marks an item as traded.
---@param item table|string
function DLC_API:MarkItemTraded(item)
    local t = Trade()
    if t and t.MarkItemTraded then
        t:MarkItemTraded(item)
    elseif DesolateLootcouncil.MarkItemTraded then
        DesolateLootcouncil:MarkItemTraded(item)
    end
end

--- Re-awards a previously awarded item from history.
---@param awardIdx number
function DLC_API:ReawardItem(awardIdx)
    local l = Loot()
    if l and l.ReawardItem then
        l:ReawardItem(awardIdx)
    elseif DesolateLootcouncil.ReawardItem then
        DesolateLootcouncil:ReawardItem(awardIdx)
    end
end

--- Deletes an attendance history entry by index.
---@param index number|string
function DLC_API:DeleteAttendanceHistoryEntry(index)
    local r = Roster()
    if r and r.DeleteAttendanceHistoryEntry then
        r:DeleteAttendanceHistoryEntry(index)
        return
    end
    if DesolateLootcouncil.DeleteAttendanceHistoryEntry then
        DesolateLootcouncil:DeleteAttendanceHistoryEntry(index)
    end
end

--- Renames a main or alt player across the roster, alts, and priority lists.
---@param oldName string
---@param newName string
---@return boolean
function DLC_API:RenamePlayer(oldName, newName)
    local r = Roster()
    if r and r.RenamePlayer then
        return r:RenamePlayer(oldName, newName)
    end
    return false
end

--- Returns the list of registered disenchanters.
---@return table
function DLC_API:GetDisenchanterList()
    local list = {}
    local seen = {}
    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if Comm and Comm.playerEnchantingSkill then
        for name, skill in pairs(Comm.playerEnchantingSkill) do
            local numSkill = tonumber(skill)
            if numSkill and numSkill > 0 then
                local shortName = Ambiguate(name, "none")
                if not seen[shortName] then
                    seen[shortName] = true
                    table.insert(list, { name = name, skill = numSkill })
                end
            end
        end
    end

    local mySkill = (DesolateLootcouncil.GetEnchantingSkillLevel and DesolateLootcouncil:GetEnchantingSkillLevel()) or 0
    if mySkill > 0 then
        local myName = DesolateLootcouncil:GetFullName("player")
        local shortMy = Ambiguate(myName, "none")
        if not seen[shortMy] then
            seen[shortMy] = true
            table.insert(list, { name = myName, skill = mySkill })
        end
    end

    table.sort(list, function(a, b) return a.skill > b.skill end)
    return list
end

-- ===========================================================================
-- 6. ROSTER MODULE SURFACE
-- ===========================================================================

--- Returns the full roster structure.
---@return table
function DLC_API:GetRoster()
    local r = Roster()
    return (r and r.GetRoster and r:GetRoster()) or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile.MainRoster) or {}
end

--- Returns the map of main characters.
---@return table<string, table>
function DLC_API:GetMainRoster()
    local r = Roster()
    return (r and r.GetMainRoster and r:GetMainRoster()) or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile.MainRoster) or {}
end

--- Returns the map of alt characters.
---@return table<string, string>
function DLC_API:GetAltRoster()
    local r = Roster()
    return (r and r.GetAltRoster and r:GetAltRoster()) or (DesolateLootcouncil.db and DesolateLootcouncil.db.profile.playerRoster and DesolateLootcouncil.db.profile.playerRoster.alts) or {}
end

--- Resolves an alt character name to its registered main.
---@param altName string
---@return string?
function DLC_API:GetMain(altName)
    local r = Roster()
    return r and r.GetMain and r:GetMain(altName)
end

--- Alias for GetMain.
---@param altName string
---@return string?
function DLC_API:GetMainForAlt(altName)
    return self:GetMain(altName)
end

--- Returns all alts linked to a main character.
---@param mainName string
---@return string[]
function DLC_API:GetAlts(mainName)
    local r = Roster()
    return (r and r.GetAlts and r:GetAlts(mainName)) or {}
end

--- Returns true if the character is registered as a main.
---@param name string
---@return boolean
function DLC_API:IsMain(name)
    local r = Roster()
    return (r and r.IsMain and r:IsMain(name)) or false
end

--- Returns true if the character is registered as an alt.
---@param name string
---@return boolean
function DLC_API:IsAlt(name)
    local r = Roster()
    return (r and r.IsAlt and r:IsAlt(name)) or false
end

--- Returns true if the named player is in the current raid group.
---@param playerName string
---@return boolean
function DLC_API:IsPlayerInRaid(playerName)
    local r = Roster()
    return (r and r.IsInRaid and r:IsInRaid(playerName)) or false
end

--- Adds a main character to the roster.
---@param name string
---@return boolean
function DLC_API:AddMain(name)
    local r = Roster()
    if r and r.AddMain then return r:AddMain(name) end
    return false
end

--- Adds an alt character linked to a main.
---@param name string
---@param main string
---@return boolean
function DLC_API:AddAlt(name, main)
    local r = Roster()
    if r and r.AddAlt then return r:AddAlt(name, main) end
    return false
end

--- Removes a player from the roster.
---@param name string
function DLC_API:RemovePlayer(name)
    local r = Roster()
    if r and r.RemovePlayer then r:RemovePlayer(name) end
end

--- Sets a player's officer status flag.
---@param name string
---@param flag boolean
function DLC_API:SetOfficer(name, flag)
    local r = Roster()
    if r and r.SetOfficer then r:SetOfficer(name, flag) end
end

--- Returns the list of unassigned players awaiting review.
---@return table
function DLC_API:GetUnassignedPlayers()
    local r = Roster()
    return (r and r.GetUnassignedPlayers and r:GetUnassignedPlayers()) or {}
end

--- Assigns an unassigned player as a Main.
---@param name string
---@return boolean
function DLC_API:AssignUnassignedAsMain(name)
    local r = Roster()
    if r and r.AssignAsMain then return r:AssignAsMain(name) end
    return false
end

--- Assigns an unassigned player as an Alt linked to a Main.
---@param altName string
---@param mainName string
---@return boolean
function DLC_API:AssignUnassignedAsAlt(altName, mainName)
    local r = Roster()
    if r and r.AssignAsAlt then return r:AssignAsAlt(altName, mainName) end
    return false
end

--- Dismisses an unassigned player from the review queue.
---@param name string
function DLC_API:DismissUnassignedPlayer(name)
    local r = Roster()
    if r and r.DismissUnassignedPlayer then r:DismissUnassignedPlayer(name) end
end


--- Formats a character name for clean UI display:
--- Strips the realm tag if the character is on the local player's realm,
--- but preserves '-OtherRealm' if cross-realm.
---@param fullName string|nil
---@return string
function DLC_API:Ambiguate(fullName)
    if DesolateLootcouncil and DesolateLootcouncil.Ambiguate then
        return DesolateLootcouncil:Ambiguate(fullName)
    end
    if not fullName or fullName == "" then return "" end
    local charName, realm = tostring(fullName):match("^([^-]+)%-(.+)$")
    if not charName or not realm then return tostring(fullName) end
    local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    local normRealm = realm:gsub("%s+", ""):lower()
    local normMyRealm = myRealm:gsub("%s+", ""):lower()
    if normMyRealm ~= "" and normRealm == normMyRealm then
        return charName
    end
    return tostring(fullName)
end

--- Returns formatted roster summary text.
---@return string
function DLC_API:GetRosterText()
    local r = Roster()
    if r and r.GetRosterText then return r:GetRosterText() end
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if not db or not db.MainRoster then return "No Roster Found." end

    local text = ""
    local sortedMains = {}
    for name in pairs(db.MainRoster) do table.insert(sortedMains, name) end
    table.sort(sortedMains)

    for _, main in ipairs(sortedMains) do
        local displayMain = self:Ambiguate(main)
        local mainText = displayMain
        local data = db.MainRoster[main]
        if data and data.isOfficer then
            mainText = mainText .. " (Officer)"
        end
        text = text .. mainText
        local alts = {}
        if db.playerRoster and db.playerRoster.alts then
            for alt, parent in pairs(db.playerRoster.alts) do
                if parent == main then
                    local displayAlt = self:Ambiguate(alt)
                    table.insert(alts, displayAlt)
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
    local r = Roster()
    if r and r.GetMainRosterList then return r:GetMainRosterList() end
    local list = {}
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if db and db.MainRoster then
        for name, data in pairs(db.MainRoster) do
            local displayName = self:Ambiguate(name)
            if data and data.isOfficer then
                list[name] = displayName .. " (Officer)"
            else
                list[name] = displayName
            end
        end
    end
    return list
end

--- Returns a map of all characters (mains and annotated alts).
---@return table<string, string>
function DLC_API:GetAllPlayersList()
    local r = Roster()
    if r and r.GetAllPlayersList then return r:GetAllPlayersList() end
    local list = self:GetMainRosterList()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if db and db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            local displayAlt = self:Ambiguate(alt)
            local displayMain = self:Ambiguate(main)
            list[alt] = displayAlt .. " (Alt of " .. displayMain .. ")"
        end
    end
    return list
end

--- Returns the deterministic 8-digit hex roster hash.
---@return string
function DLC_API:GetRosterHash()
    local r = Roster()
    if r and r.GetRosterHash then return r:GetRosterHash() end
    if DesolateLootcouncil.CalculateRosterHash and DesolateLootcouncil.db and DesolateLootcouncil.db.profile then
        return DesolateLootcouncil:CalculateRosterHash(DesolateLootcouncil.db.profile.MainRoster)
    end
    return ""
end

--- Returns a colored difficulty badge string.
---@param difficultyID number|string|nil
---@param bossName string|nil
---@return string|nil
function DLC_API:GetDifficultyBadge(difficultyID, bossName)
    local r = Roster()
    return r and r.GetDifficultyBadge and r:GetDifficultyBadge(difficultyID, bossName)
end

--- Strips difficulty suffix patterns from a boss name.
---@param bossName string
---@return string
function DLC_API:StripDifficultySuffix(bossName)
    local r = Roster()
    if r and r.StripDifficultySuffix then return r:StripDifficultySuffix(bossName) end
    return (type(self) ~= "table" and self) or bossName or ""
end

--- Returns the DecayConfig settings table.
---@return table
function DLC_API:GetAttendanceConfig()
    return (DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.DecayConfig) or {}
end

--- Returns the AttendanceHistory table.
---@return table
function DLC_API:GetAttendanceHistory()
    return (DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.AttendanceHistory) or {}
end

--- Starts a new raid attendance tracking session.
function DLC_API:StartRaidSession()
    local a = Attendance()
    if a and a.StartRaidSession then a:StartRaidSession() end
end

--- Stops the current raid tracking session.
---@param saveHistory boolean?
function DLC_API:StopRaidSession(saveHistory)
    local a = Attendance()
    if a and a.StopRaidSession then a:StopRaidSession(saveHistory) end
end

--- Returns true if there is an unapplied decay session pending.
---@return boolean
function DLC_API:HasPendingDecay()
    local a = Attendance()
    return (a and a.HasPendingDecay and a:HasPendingDecay()) or false
end

--- Applies or skips decay for the last tracked raid session.
---@param skip boolean?
function DLC_API:ApplyDecayForLastSession(skip)
    local a = Attendance()
    if a and a.ApplyDecayForLastSession then a:ApplyDecayForLastSession(skip) end
end

--- Records decay application metadata for the session.
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

-- ===========================================================================
-- 7. COMM & SYNC SURFACE
-- ===========================================================================

--- Broadcasts a sync message across addon comms.
---@param dataType string
---@param payload table
function DLC_API:BroadcastSync(dataType, payload)
    local c = Comm()
    if c and c.BroadcastSync then c:BroadcastSync(dataType, payload) end
end

--- Broadcasts a version check request.
---@return boolean success
function DLC_API:SendVersionCheck()
    local c = Comm()
    return (c and c.SendVersionCheck and c:SendVersionCheck()) or false
end

--- Pings a manual version check request.
---@return boolean success
function DLC_API:PingVersionCheck()
    local c = Comm()
    if c and c.PingVersionCheck then return c:PingVersionCheck() end
    return self:SendVersionCheck()
end

--- Returns cooldown seconds remaining before next version ping.
---@return number seconds
function DLC_API:GetVersionCheckCooldown()
    local c = Comm()
    return (c and c.GetVersionCheckCooldown and c:GetVersionCheckCooldown()) or 0
end

--- Broadcasts the autopass state to other clients.
---@param active boolean
function DLC_API:SendSyncAutopass(active)
    local c = Comm()
    if c and c.SendSyncAutopass then c:SendSyncAutopass(active) end
end

--- Returns the known autopass state for a player.
---@param name string
---@return boolean?
function DLC_API:GetPlayerAutopassState(name)
    local c = Comm()
    return c and c.GetPlayerAutopassState and c:GetPlayerAutopassState(name)
end

--- Returns the count of active addon users in the group.
---@return number count
function DLC_API:GetActiveUserCount()
    local c = Comm()
    return (c and c.GetActiveUserCount and c:GetActiveUserCount()) or 0
end

--- Returns connection status info for all known addon users.
---@return table
function DLC_API:GetConnectionStatuses()
    local c = Comm()
    return (c and c.GetStatuses and c:GetStatuses()) or {}
end

--- Returns the map of discovered player versions from comms.
---@return table<string, string>
function DLC_API:GetPlayerVersions()
    local c = Comm()
    return (c and c.playerVersions) or {}
end

--- Seeds the local player's version into Comm's playerVersions table.
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

--- Whispers the selected data type to raid officers.
---@param dataType string
---@param payload table?
function DLC_API:ShareDataWithOfficers(dataType, payload)
    local s = Sync()
    if s and s.ShareDataWithOfficers then s:ShareDataWithOfficers(dataType, payload) end
end

--- Syncs data (priorities/roster) with officers via the Sync module.
function DLC_API:SyncDataWithOfficers()
    local syncMod = Sync()
    if syncMod and syncMod.SyncDataWithOfficers then
        syncMod:SyncDataWithOfficers()
    end
end

--- Returns true if the active Loot Master appears absent/disconnected.
---@return boolean
function DLC_API:IsLMAbsent()
    if DesolateLootcouncil.IsLMAbsent then return DesolateLootcouncil:IsLMAbsent() end
    return false
end

--- Claims the Loot Master role for the local player.
function DLC_API:ClaimLMRole()
    if DesolateLootcouncil.ClaimLMRole then DesolateLootcouncil:ClaimLMRole() end
end

--- Sends an LM handover offer to a target officer.
---@param targetOfficer string
function DLC_API:SendLMHandoverOffer(targetOfficer)
    local c = Comm()
    if c and c.SendLMHandoverOffer then c:SendLMHandoverOffer(targetOfficer) end
end

-- ===========================================================================
-- 8. CONFIGURATION & PROFILE OPTIONS
-- ===========================================================================

--- Returns the configured Loot Master name.
---@return string
function DLC_API:GetConfiguredLM()
    return DesolateLootcouncil.db.profile.configuredLM or ""
end

--- Sets the configured Loot Master name.
---@param val string
function DLC_API:SetConfiguredLM(val)
    if DesolateLootcouncil.db and DesolateLootcouncil.db.profile then
        DesolateLootcouncil.db.profile.configuredLM = val
        DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
    end
    if DesolateLootcouncil.UpdateLootMasterStatus then
        DesolateLootcouncil:UpdateLootMasterStatus()
    end
end

--- Returns the minimum loot quality threshold.
---@return number
function DLC_API:GetMinLootQuality()
    return (DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.minLootQuality) or 3
end

--- Sets the minimum loot quality threshold.
---@param val number
function DLC_API:SetMinLootQuality(val)
    if DesolateLootcouncil.db and DesolateLootcouncil.db.profile then
        DesolateLootcouncil.db.profile.minLootQuality = val
        DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
    end
end

--- Returns whether automated rolling/passing is enabled.
---@return boolean
function DLC_API:GetEnableAutoLoot()
    return (DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.enableAutoLoot) or false
end

--- Sets whether automated rolling/passing is enabled.
---@param val boolean
function DLC_API:SetEnableAutoLoot(val)
    if DesolateLootcouncil.db and DesolateLootcouncil.db.profile then
        DesolateLootcouncil.db.profile.enableAutoLoot = val
        DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
    end
end

--- Returns whether automated trade staging is enabled.
---@return boolean
function DLC_API:GetEnableAutoTrade()
    return (DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.enableAutoTrade) or false
end

--- Sets whether automated trade staging is enabled.
---@param val boolean
function DLC_API:SetEnableAutoTrade(val)
    if DesolateLootcouncil.db and DesolateLootcouncil.db.profile then
        DesolateLootcouncil.db.profile.enableAutoTrade = val
        DesolateLootcouncil.db.profile.configTimestamp = GetServerTime()
    end
end

--- Returns whether raid attendance decay is enabled.
---@return boolean
function DLC_API:GetDecayEnabled()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    return (db and db.DecayConfig and db.DecayConfig.enabled) or false
end

--- Sets whether raid attendance decay is enabled.
---@param val boolean
function DLC_API:SetDecayEnabled(val)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if db then
        if not db.DecayConfig then db.DecayConfig = {} end
        db.DecayConfig.enabled = val
        db.configTimestamp = GetServerTime()
    end
end

--- Returns the default decay penalty amount.
---@return number
function DLC_API:GetDecayPenalty()
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    return (db and db.DecayConfig and db.DecayConfig.defaultPenalty) or 1
end

--- Sets the default decay penalty amount.
---@param val number
function DLC_API:SetDecayPenalty(val)
    local db = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if db then
        if not db.DecayConfig then db.DecayConfig = {} end
        db.DecayConfig.defaultPenalty = val
        db.configTimestamp = GetServerTime()
    end
end

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

--- Resets the layout positions of all addon windows.
function DLC_API:ResetWindowLayout()
    local p = Persistence()
    if p and p.ResetPositions then
        p:ResetPositions()
        DesolateLootcouncil:Print(L["All window positions have been reset."])
    end
end

--- Reprompts the Loot Master to choose whether to enable autopass for this session.
function DLC_API:RepromptAutopass()
    DesolateLootcouncil:PromptAutopass()
end

-- ===========================================================================
-- 9. SERIALIZER SURFACE (Delegated to Serializer)
-- ===========================================================================

--- Parses timestamp from an awarded item record or date string into numeric epoch seconds.
---@param item table|string|number|nil
---@return number
function DLC_API:ParseItemTimestamp(item)
    local s = Serializer()
    return (s and s.ParseItemTimestamp and s:ParseItemTimestamp(item)) or 0
end

--- Exports a single raid history session or current live session as a compressed !DLC1: string.
---@param indexOrSession number|string|table
---@return string
function DLC_API:ExportSingleRaidHistoryEvent(indexOrSession)
    local s = Serializer()
    return (s and s.ExportSingleRaidHistoryEvent and s:ExportSingleRaidHistoryEvent(indexOrSession)) or ""
end

--- Compacts history records, strips duplicates, and splits multi-date sessions.
---@param arg1 any
---@param arg2 any
---@return number prunedCount
function DLC_API:CompactRaidHistory(arg1, arg2)
    local s = Serializer()
    return (s and s.CompactRaidHistory and s:CompactRaidHistory(arg1, arg2)) or 0
end

--- Exports profile data as a compressed !DLC1: string.
---@param selection table<string, boolean>|nil
---@return string
function DLC_API:ExportProfileData(selection)
    local s = Serializer()
    return (s and s.ExportProfileData and s:ExportProfileData(selection)) or ""
end

--- Splits a multi-date attendance session entry into individual single-date sessions.
---@param sessionEntry table
---@return table[]
function DLC_API:SplitMultiDateAttendanceEntry(sessionEntry)
    local s = Serializer()
    return (s and s.SplitMultiDateAttendanceEntry and s:SplitMultiDateAttendanceEntry(sessionEntry)) or { sessionEntry }
end

--- Imports profile data from a compressed or legacy Base64 string.
---@param importStringRaw string
---@param importName string|nil
---@param importToCurrent boolean|nil
---@return boolean success, string message
function DLC_API:ImportProfileData(importStringRaw, importName, importToCurrent)
    local s = Serializer()
    if s and s.ImportProfileData then
        return s:ImportProfileData(importStringRaw, importName, importToCurrent)
    end
    return false, "Serializer module not found."
end


