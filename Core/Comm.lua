local _, AT = ...
if AT.abortLoad then return end

---@class Comm : AceModule, AceComm-3.0, AceSerializer-3.0, AceEvent-3.0
---@field playerVersions table<string, string>
---@field playerEnchantingSkill table<string, number>
---@field frame any
---@field RefreshWindow fun(self: any)
local Comm = DesolateLootcouncil:NewModule("Comm", "AceComm-3.0", "AceSerializer-3.0", "AceEvent-3.0")

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

    if command == "VERSION_REQ" or command == "VERSION_CHECK" then
        -- Reply with my version and enchanting skill
        local responseData = {
            version = DesolateLootcouncil.version,
        }
        local mySkill = DesolateLootcouncil:GetEnchantingSkillLevel()
        if (mySkill or 0) > 0 then
            responseData.enchantingSkill = mySkill
        end
        self:SendComm("VERSION_RESP", responseData, sender)

        -- [OPTIMIZATION] Avoid Individual Whispers for bulk data on every ping.
        -- We only reply with version. SYNC_AUTOPASS and IM_SYNC are now broadcast 
        -- independently when they change or when a session starts.

        -- Track sender too if they sent version and skill
        if data and data.version then
            self:UpdatePlayerInfo(sender, data.version, data.enchantingSkill or 0)
        end
    elseif command == "VERSION_RESP" then
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
    elseif command == "LOOT_SESSION_START" then
        -- Legacy/Active hook for starting loot session remotely
        ---@type Session
        local Session = DesolateLootcouncil:GetModule("Session")
        if Session and Session.StartSession then
            -- 'data' might be the loot table or wrapped in 'data.data'
            local lootTable = data.data or data
            Session:StartSession(lootTable)
        end
    elseif command == "LOOT_SESSION_END" then
        ---@type Session
        local Session = DesolateLootcouncil:GetModule("Session")
        if Session and Session.EndSession then Session:EndSession() end
    elseif command == "IM_SYNC" then
        -- Sync Item Manager lists (items only, not players)
        if data and type(data) == "table" then
            local db = DesolateLootcouncil.db.profile
            if db.PriorityLists then
                local count = 0
                for listName, items in pairs(data) do
                    for _, localList in ipairs(db.PriorityLists) do
                        if localList.name == listName then
                            localList.items = items
                            count = count + 1
                            break
                        end
                    end
                end
                DesolateLootcouncil:DLC_Log(string.format("Item Manager Synced: Updated %d item lists.", count))

                -- Refresh UI if open
                local ItemMgr = DesolateLootcouncil:GetModule("UI_ItemManager")
                if ItemMgr and ItemMgr.frame and (ItemMgr.frame --[[@as any]]).frame:IsShown() then
                    ItemMgr:RefreshWindow()
                end
            end
        end
    elseif command == "SYNC_AUTOPASS" then
        DesolateLootcouncil.sessionAutopassActive = data
        local status = data and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
        DesolateLootcouncil:DLC_Log("Loot Master has " .. status .. " Autopass for this session.")
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

function Comm:GetActiveUserCount()
    local count = 0
    for _ in pairs(self.playerVersions) do
        count = count + 1
    end
    return count
end

function Comm:SendSyncAutopass(isActive)
    DesolateLootcouncil.sessionAutopassActive = isActive
    self:SendComm("SYNC_AUTOPASS", isActive)
    local status = isActive and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
    DesolateLootcouncil:DLC_Log("You have " .. status .. " Autopass for this session.")
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
