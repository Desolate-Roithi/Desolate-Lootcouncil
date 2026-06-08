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
        
        -- History Bulk Sync for late-joining / reloading officers
        local db = DesolateLootcouncil.db.profile
        local rosterEntry = db.MainRoster and db.MainRoster[sender]
        if rosterEntry and rosterEntry.isOfficer then
            local SessionMod = DesolateLootcouncil:GetModule("Session")
            SessionMod.officerSyncedThisSession = SessionMod.officerSyncedThisSession or {}
            if not SessionMod.officerSyncedThisSession[sender] then
                SessionMod.officerSyncedThisSession[sender] = true
                self:ScheduleTimer(function()
                    local awardedList = db.session and db.session.awarded or {}
                    local bulk = {}
                    local startIdx = math.max(1, #awardedList - 49)
                    for i = startIdx, #awardedList do
                        local entry = awardedList[i]
                        table.insert(bulk, {
                            link        = entry.link,
                            texture     = entry.texture,
                            itemID      = entry.itemID,
                            winner      = entry.winner,
                            winnerClass = entry.winnerClass,
                            voteType    = entry.voteType,
                            timestamp   = entry.timestamp,
                            traded      = entry.traded
                        })
                    end
                    if #bulk > 0 then
                        self:SendComm("HISTORY_BULK_SYNC", bulk, sender)
                    end
                end, 2)
            end
        end
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

function Comm:OnCommReceived(prefix, message, _distribution, sender)
    if prefix ~= "DLC_COMM" then return end
    if DesolateLootcouncil:SmartCompare(sender, "player") then return end -- Ignore self

    local currentLM = DesolateLootcouncil:DetermineLootMaster()
    if currentLM and currentLM ~= "" and DesolateLootcouncil:SmartCompare(sender, currentLM) then
        self.lastLMMsgTime = GetServerTime()
    end

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
    else
        local Sync = DesolateLootcouncil:GetModule("Sync", true)
        if Sync and Sync.HandleMessage then
            Sync:HandleMessage(command, data, sender)
        end
    end
end

function Comm:IsLMAbsent()
    if not IsInGroup() then return false end
    if DesolateLootcouncil:AmILootMaster() then return false end
    local now = GetServerTime()
    if not self.lastLMMsgTime then
        self.groupJoinedTime = self.groupJoinedTime or now
        return (now - self.groupJoinedTime > 60)
    end
    return (now - self.lastLMMsgTime > 60)
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





function Comm:PruneRosterData()
    if not IsInGroup() then
        self.lastLMMsgTime = nil
        self.groupJoinedTime = nil
    end

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


