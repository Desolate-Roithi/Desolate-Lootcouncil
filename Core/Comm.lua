local _, AT = ...
if AT.abortLoad then return end

---@class Comm : AceModule, AceComm-3.0, AceSerializer-3.0, AceEvent-3.0
---@field playerVersions table<string, string>
---@field playerEnchantingSkill table<string, number>
---@field frame any
---@field RefreshWindow fun(self: any)
local Comm = DesolateLootcouncil:NewModule("Comm", "AceComm-3.0", "AceSerializer-3.0", "AceEvent-3.0", "AceTimer-3.0")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]

-- Seconds between allowed version check broadcasts. Also returned to callers so
-- UI can display an accurate countdown without duplicating this magic number.
local VERSION_CHECK_COOLDOWN = 10

function Comm:OnEnable()
    -- Register the communication prefix
    self:RegisterComm("DLC_COMM", "OnCommReceived")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "PruneRosterData")
    self.playerVersions = {}
    self.playerEnchantingSkill = {}
    self.lastVersionCheck = 0
    self.rosterSyncTimer = nil

    DesolateLootcouncil:DLC_Log("Systems/Comm Loaded")
end

function Comm:SendComm(command, data, target)
    local serialized = self:Serialize(command, data)
    if target then
        self:SendCommMessage("DLC_COMM", serialized, "WHISPER", target)
    else
        -- Smart channel selection
        local channel = "GUILD"
        if IsInRaid() then
            channel = "RAID"
        elseif IsInGroup() then
            channel = "PARTY"
        end
        self:SendCommMessage("DLC_COMM", serialized, channel)
    end
end

local CommHandlers = {}

function CommHandlers:VERSION_REQ(data, sender)
    -- Reply with my version and enchanting skill
    local responseData = {
        version = DesolateLootcouncil.version,
    }
    local mySkill = DesolateLootcouncil:GetEnchantingSkillLevel()
    if (mySkill or 0) > 0 then
        responseData.enchantingSkill = mySkill
    end
    self:SendComm("VERSION_RESP", responseData, sender)

    -- Track sender too if they sent version and skill
    if data and data.version then
        self:UpdatePlayerInfo(sender, data.version, data.enchantingSkill or 0)
    end

    -- Autopass Sync Handshake: If the local player is the Loot Master, respond to the player's
    -- version ping by whispering our authoritative Autopass active state directly to them.
    -- This instantly syncs late-joiners, zone transitioners, and reloaded raiders
    -- without waiting for the 30-second heartbeat.
    if DesolateLootcouncil:AmILootMaster() then
        local active = DesolateLootcouncil.sessionAutopassActive or false
        self:SendComm("SYNC_AUTOPASS", { isActive = active, isHeartbeat = true }, sender)
    end
end
CommHandlers.VERSION_CHECK = CommHandlers.VERSION_REQ

function CommHandlers:VERSION_RESP(data, sender)
    -- Store sender's version and enchanting skill
    local ver, skill
    if type(data) == "table" then
        ver = data.version
        skill = data.enchantingSkill
    else
        ver = data
        skill = nil
    end

    self:UpdatePlayerInfo(sender, ver, skill)
end

function CommHandlers:LOOT_SESSION_START(data, sender)
    -- Legacy/Active hook for starting loot session remotely
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.StartSession then
        -- 'data' might be the loot table or wrapped in 'data.data'
        local lootTable = data.data or data
        Session:StartSession(lootTable)
    end
end

function CommHandlers:LOOT_SESSION_END(data, sender)
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.EndSession then Session:EndSession() end
end

local function IsItemManagerDesynced(incomingData)
    local db = DesolateLootcouncil.db.profile
    if not db.PriorityLists then return true end

    -- Count number of lists
    local incomingListsCount = 0
    for _ in pairs(incomingData) do incomingListsCount = incomingListsCount + 1 end
    if #db.PriorityLists ~= incomingListsCount then return true end

    local localLists = {}
    for _, localList in ipairs(db.PriorityLists) do
        localLists[localList.name] = localList
    end

    for listName, items in pairs(incomingData) do
        local localList = localLists[listName]
        if not localList then return true end

        local localCount = 0
        for _ in pairs(localList.items or {}) do localCount = localCount + 1 end
        local incomingCount = 0
        for _ in pairs(items or {}) do incomingCount = incomingCount + 1 end

        if localCount ~= incomingCount then return true end

        for id, val in pairs(items or {}) do
            if not localList.items or localList.items[id] ~= val then
                return true
            end
        end
    end
    return false
end

local function OverwriteItemManagerLists(data, logMessage)
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists then
        for listName, items in pairs(data) do
            for _, localList in ipairs(db.PriorityLists) do
                if localList.name == listName then
                    localList.items = DesolateLootcouncil.Table.DeepCopy(items)
                    break
                end
            end
        end

        if logMessage then
            DesolateLootcouncil:Print(logMessage)
        end

        -- Refresh UI if open
        local ItemMgr = DesolateLootcouncil:GetModule("UI_ItemManager")
        if ItemMgr and ItemMgr.frame and (ItemMgr.frame --[[@as any]]).frame:IsShown() then
            ItemMgr:RefreshWindow()
        end
    end
end

function CommHandlers:IM_SYNC(payload, sender)
    if not payload or type(payload) ~= "table" then return end

    -- Extract data and manual flag. Backwards compatibility for old clients.
    local data = payload.lists or payload
    local isManual = (payload.isManual == true) or (payload.lists == nil)

    if type(data) ~= "table" then return end

    local inRaid = IsInRaid()
    local currentLM = DesolateLootcouncil:DetermineLootMaster()
    local isSenderLM = DesolateLootcouncil:SmartCompare(sender, currentLM)
    local amILM = DesolateLootcouncil:AmILootMaster()

    local shouldOverwrite = false
    local logMessage = nil

    if isManual then
        -- Manual Sync: Accepted by everyone unconditionally if desynced
        if not DesolateLootcouncil:SmartCompare(sender, "player") then
            if IsItemManagerDesynced(data) then
                shouldOverwrite = true
                logMessage = "|cff00ffff[Item Manager]|r Synced: Manual database update received from '" .. DesolateLootcouncil:GetDisplayName(sender) .. "'."
            end
        end
    else
        -- Automatic Sync: Enforce LM's configuration on raiders, only active in Raids
        if inRaid and isSenderLM and not amILM then
            if IsItemManagerDesynced(data) then
                shouldOverwrite = true
                logMessage = "|cff00ffff[Item Manager]|r Auto-updated your item database to match Loot Master '" .. DesolateLootcouncil:GetDisplayName(sender) .. "' (detected desync)."
            end
        end
    end

    if shouldOverwrite then
        OverwriteItemManagerLists(data, logMessage)
    elseif inRaid and isSenderLM and not amILM then
        DesolateLootcouncil:DLC_Log("Item Manager is already in sync with Loot Master.")
    end
end


function CommHandlers:SYNC_AUTOPASS(data, sender)
    -- Only accept autopass state from the current Loot Master (prevent spoofing).
    if DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then
        local isActive
        local isHeartbeat = false
        if type(data) == "table" then
            isActive = data.isActive
            isHeartbeat = data.isHeartbeat
        else
            isActive = data
        end

        local changed = (DesolateLootcouncil.sessionAutopassActive ~= isActive)
        DesolateLootcouncil.sessionAutopassActive = isActive

        if not isHeartbeat or changed then
            local status = isActive and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
            if changed or not isHeartbeat then
                DesolateLootcouncil:DLC_Log("Loot Master has " .. status .. " Autopass for this session.")
            end

            local Autopass = DesolateLootcouncil:GetModule("Autopass")
            if Autopass and Autopass.ScanAndAutopassActiveLootRolls then
                Autopass:ScanAndAutopassActiveLootRolls()
            end
        end
    else
        DesolateLootcouncil:DLC_Log(string.format("SYNC_AUTOPASS from non-LM '%s' ignored.", tostring(sender)))
    end
end

function CommHandlers:SYNC_PRIORITY(data, sender)
    -- Only accept from the current Loot Master (prevent spoofing)
    if DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then
        local Priority = DesolateLootcouncil:GetModule("Priority")
        if Priority and Priority.ReceivePrioritySync then
            Priority:ReceivePrioritySync(data)
        end
    else
        DesolateLootcouncil:DLC_Log(string.format("SYNC_PRIORITY from non-LM '%s' ignored.", tostring(sender)))
    end
end

function CommHandlers:SYNC_ROSTER(data, sender)
    -- Only accept from the current Loot Master (prevent spoofing)
    if DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then
        local RosterSys = DesolateLootcouncil:GetModule("Roster")
        if RosterSys and RosterSys.ReceiveRosterSync then
            RosterSys:ReceiveRosterSync(data)
        end
    else
        DesolateLootcouncil:DLC_Log(string.format("SYNC_ROSTER from non-LM '%s' ignored.", tostring(sender)))
    end
end

function CommHandlers:LURA_TEST_START(data, sender)
    local Lura = DesolateLootcouncil:GetModule("UI_LuraWidget", true)
    if Lura and Lura.ActivateGlobalTestMode then Lura:ActivateGlobalTestMode() end
end

function CommHandlers:LURA_TEST_END(data, sender)
    local Lura = DesolateLootcouncil:GetModule("UI_LuraWidget", true)
    if Lura and Lura.DeactivateGlobalTestMode then Lura:DeactivateGlobalTestMode() end
end

function Comm:OnCommReceived(prefix, message, _distribution, sender)
    if prefix ~= "DLC_COMM" then return end
    if DesolateLootcouncil:SmartCompare(sender, "player") then return end -- Ignore self

    local success, command, data = self:Deserialize(message)
    if not success then return end

    -- Handle Deserialization format differences if any (Active used direct object, Legacy used command, data args)
    -- Check if 'command' is actually a table (if serialized as one object)
    if type(command) == "table" and command.type then
        data = command
        command = data.type
    end

    local handler = CommHandlers[command]
    if handler then
        handler(self, data, sender)
    end
end


function Comm:UpdatePlayerInfo(sender, version, skill)
    self.playerVersions[sender] = version
    if skill ~= nil then
        self.playerEnchantingSkill[sender] = skill
    end

    -- Sync to Global for Debug module

    if DesolateLootcouncil.activeAddonUsers then
        DesolateLootcouncil.activeAddonUsers[sender] = true
    end
    -- Fire AceEvent DLC_VERSION_UPDATE
    self:SendMessage("DLC_VERSION_UPDATE", sender, version)
end

function Comm:SendVersionCheck()
    -- 1. Explicitly update self (Always refresh local state even if throttled)
    local myName = UnitName("player")
    self.playerVersions[myName] = DesolateLootcouncil.version
    local mySkill = DesolateLootcouncil:GetEnchantingSkillLevel()
    self.playerEnchantingSkill[myName] = mySkill

    -- 2. Throttling for Broadcast
    local now = GetTime()
    local remaining = self:GetVersionCheckRemaining()
    if remaining > 0 then
        DesolateLootcouncil:DLC_Log(string.format("Version broadcast throttled — %.0fs cooldown remaining.", remaining))
        return false, remaining
    end
    self.lastVersionCheck = now

    local payloadData = {
        version = DesolateLootcouncil.version
    }
    if (mySkill or 0) > 0 then
        payloadData.enchantingSkill = mySkill
    end

    self:SendComm("VERSION_REQ", payloadData)
    return true
end

--- Returns how many seconds remain in the version check cooldown (0 if ready).
--- Safe to call at any time with no side effects.
function Comm:GetVersionCheckRemaining()
    local remaining = VERSION_CHECK_COOLDOWN - (GetTime() - self.lastVersionCheck)
    return remaining > 0 and remaining or 0
end

--- Seeds the local player into playerVersions if not already present.
--- Call this once when a UI window that needs version data first opens.
function Comm:SeedSelf()
    local myName = UnitName("player")
    if not myName or myName == "Unknown Entity" then return end
    if self.playerVersions[myName] then return end -- already seeded
    local myVersion = DesolateLootcouncil.version or "0.0.0"
    local mySkill = DesolateLootcouncil:GetEnchantingSkillLevel()
    self:UpdatePlayerInfo(myName, myVersion, mySkill)
    DesolateLootcouncil:DLC_Log("[Conn] Self-seeded " .. myName .. " as version " .. myVersion)
end

function Comm:GetActiveUserCount()
    local count = 0
    for _ in pairs(self.playerVersions) do
        count = count + 1
    end
    return count
end

function Comm:SendSyncAutopass(isActive, isHeartbeat)
    DesolateLootcouncil.sessionAutopassActive = isActive
    DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassActive = isActive
    
    local payload = isActive
    if isHeartbeat then
        payload = { isActive = isActive, isHeartbeat = true }
    end
    self:SendComm("SYNC_AUTOPASS", payload)
    
    if not isHeartbeat then
        local status = isActive and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
        DesolateLootcouncil:DLC_Log("You have " .. status .. " Autopass for this session.")

        local Autopass = DesolateLootcouncil:GetModule("Autopass")
        if Autopass and Autopass.ScanAndAutopassActiveLootRolls then
            Autopass:ScanAndAutopassActiveLootRolls()
        end
    end
end

--- Shares the given data type with all raid assistants and the raid leader
--- via private whisper. Only call this as the Loot Master.
---@param dataType string  "PRIORITY" or "ROSTER"
function Comm:ShareDataWithAssists(dataType)
    if not DesolateLootcouncil:AmILootMaster() then
        DesolateLootcouncil:DLC_Log("ShareDataWithAssists: You are not the Loot Master.")
        return
    end

    local command, payload
    if dataType == "PRIORITY" then
        command = "SYNC_PRIORITY"
        local db = DesolateLootcouncil.db.profile
        -- Build a compact copy: only name + players + items (no circular refs)
        local lists = {}
        for _, listObj in ipairs(db.PriorityLists or {}) do
            local playersCopy = {}
            for i, p in ipairs(listObj.players or {}) do playersCopy[i] = p end
            local itemsCopy = {}
            for id, val in pairs(listObj.items or {}) do itemsCopy[id] = val end
            table.insert(lists, { name = listObj.name, players = playersCopy, items = itemsCopy })
        end
        payload = lists
    elseif dataType == "ROSTER" then
        command = "SYNC_ROSTER"
        local db = DesolateLootcouncil.db.profile
        local mainsCopy = {}
        for name, data in pairs(db.MainRoster or {}) do
            mainsCopy[name] = { addedAt = data.addedAt or 0 }
        end
        local altsCopy = {}
        for alt, main in pairs((db.playerRoster or {}).alts or {}) do
            altsCopy[alt] = main
        end
        payload = { mains = mainsCopy, alts = altsCopy }
    else
        DesolateLootcouncil:DLC_Log("ShareDataWithAssists: Unknown dataType '" .. tostring(dataType) .. "'.")
        return
    end

    -- Collect targets: only assists (rank 1) and leaders (rank 2)
    local targets = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name and rank >= 1 and not DesolateLootcouncil:SmartCompare(name, "player") then
                table.insert(targets, name)
            end
        end
    end

    if #targets == 0 then
        DesolateLootcouncil:DLC_Log("ShareDataWithAssists: No assists or leaders found to share with.", true)
        return
    end

    for _, target in ipairs(targets) do
        local serialized = self:Serialize(command, payload)
        self:SendCommMessage("DLC_COMM", serialized, "WHISPER", target)
    end

    DesolateLootcouncil:DLC_Log(string.format(
        "Shared %s data with %d assist(s).", dataType, #targets), true)
end

function Comm:PruneRosterData()
    local toRemove = {}
    for name in pairs(self.playerVersions) do
        if not DesolateLootcouncil:IsUnitInRaid(name) and not DesolateLootcouncil:SmartCompare(name, "player") then
            table.insert(toRemove, name)
        end
    end
    
    if #toRemove > 0 then
        for _, name in ipairs(toRemove) do
            self.playerVersions[name] = nil
            self.playerEnchantingSkill[name] = nil
            if DesolateLootcouncil.activeAddonUsers then
                DesolateLootcouncil.activeAddonUsers[name] = nil
            end
        end
        -- Notify UI that data has changed (pruned)
        self:SendMessage("DLC_VERSION_UPDATE")
    end

    -- Handshake: Batch detection of new members to prevent outgoing Whisper spam disconnects for the LM
    if DesolateLootcouncil:AmILootMaster() then
        local prefix = IsInRaid() and "raid" or (IsInGroup() and "party")
        if prefix then
            local unrecordedFound = false
            for i = 1, GetNumGroupMembers() do
                local name = GetUnitName(prefix..i, true)
                if name and not self.playerVersions[name] and not DesolateLootcouncil:SmartCompare(name, "player") then
                    unrecordedFound = true
                    break
                end
            end

            if unrecordedFound and not self.rosterSyncTimer then
                -- Wait 5 seconds for raid forming to settle, then broadcast ONE raid-wide Request
                self.rosterSyncTimer = self:ScheduleTimer(function()
                    self.rosterSyncTimer = nil
                    self:SendVersionCheck()
                end, 5)
            end
        end
    end
end
