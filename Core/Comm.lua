---@class Comm : AceModule, AceComm-3.0, AceSerializer-3.0, AceEvent-3.0
---@field playerVersions table<string, string>
---@field playerEnchantingSkill table<string, number>
local Comm = DesolateLootcouncil:NewModule("Comm", "AceComm-3.0", "AceSerializer-3.0", "AceEvent-3.0")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]

function Comm:OnEnable()
    -- Register the communication prefix
    self:RegisterComm("DLC_COMM", "OnCommReceived")
    self.playerVersions = {}
    self.playerEnchantingSkill = {}

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

function Comm:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= "DLC_COMM" then return end
    if sender == UnitName("player") then return end -- Ignore self

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
            enchantingSkill = DesolateLootcouncil:GetEnchantingSkillLevel()
        }
        self:SendComm("VERSION_RESP", responseData, sender)

        -- Track sender too if they sent version
        if data and data.version then
            self:UpdatePlayerInfo(sender, data.version, 0)
        end
    elseif command == "VERSION_RESP" then
        -- Store sender's version and enchanting skill
        local ver, skill
        if type(data) == "table" then
            ver = data.version
            skill = data.enchantingSkill
        else
            ver = data
            skill = 0
        end

        self:UpdatePlayerInfo(sender, ver, skill)
    elseif command == "SESSION_START" then
        -- Legacy/Active hook for starting loot session remotely
        ---@type Session
        local Session = DesolateLootcouncil:GetModule("Session")
        if Session and Session.StartSession then
            -- 'data' might be the loot table or wrapped in 'data.data'
            local lootTable = data.data or data
            Session:StartSession(lootTable)
        end
    elseif command == "SESSION_END" then
        ---@type Session
        local Session = DesolateLootcouncil:GetModule("Session")
        if Session and Session.EndSession then Session:EndSession() end
    end
end

function Comm:UpdatePlayerInfo(sender, version, skill)
    self.playerVersions[sender] = version
    self.playerEnchantingSkill[sender] = skill or 0

    -- Sync to Global for Debug module
    if DesolateLootcouncil.activeAddonUsers then
        DesolateLootcouncil.activeAddonUsers[sender] = true
    end
    -- Fire AceEvent DLC_VERSION_UPDATE
    self:SendMessage("DLC_VERSION_UPDATE", sender, version)
end

function Comm:SendVersionCheck()
    -- Broadcast VERSION_REQ
    self.playerVersions = {}        -- Reset locally on new check
    self.playerEnchantingSkill = {} -- Reset skills too

    -- Explicitly add Self
    local myName = UnitName("player")
    self.playerVersions[myName] = DesolateLootcouncil.version
    local mySkill = DesolateLootcouncil:GetEnchantingSkillLevel()
    if mySkill == 0 then mySkill = 300 end -- Test/Default
    self.playerEnchantingSkill[myName] = mySkill

    self:SendComm("VERSION_REQ", { version = DesolateLootcouncil.version })
end

function Comm:GetActiveUserCount()
    local count = 1
    for _ in pairs(self.playerVersions) do
        count = count + 1
    end
    return count
end
