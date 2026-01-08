---@class Comm : AceModule, AceComm-3.0, AceSerializer-3.0, AceEvent-3.0
---@field OnCommReceived fun(self: Comm, prefix: string, message: string, distribution: string, sender: string)
---@field SendComm fun(self: Comm, command: string, data: any, target?: string)
---@field playerVersions table<string, string>
---@field SendVersionCheck fun(self: Comm)
---@field GetActiveUserCount fun(self: Comm): number

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
---@type Comm
local Comm = DesolateLootcouncil:NewModule("Comm", "AceComm-3.0", "AceSerializer-3.0", "AceEvent-3.0")

function Comm:OnEnable()
    -- Register the communication prefix
    self:RegisterComm("DLC_COMM", "OnCommReceived")
    self.playerVersions = {}
end

function Comm:SendComm(command, data, target)
    local serialized = self:Serialize(command, data)
    if target then
        self:SendCommMessage("DLC_COMM", serialized, "WHISPER", target)
    else
        -- Smart channel selection
        local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or "GUILD"
        -- If not in group/raid, GUILD is a good fallback for version checks,
        -- but be careful with spam. For now, strict adherence to request:
        -- "Broadcast" implies group context usually.
        -- We'll use the standard group check logic.
        if IsInRaid() then
            channel = "RAID"
        elseif IsInGroup() then
            channel = "PARTY"
        else
            -- Fallback or do nothing? User said "Broadcast".
            -- If solo, maybe nothing happens or print error.
            -- Let's just try GUILD if not in group, useful for guild version checks.
            channel = "GUILD"
        end
        self:SendCommMessage("DLC_COMM", serialized, channel)
    end
end

function Comm:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= "DLC_COMM" then return end

    local success, command, data = self:Deserialize(message)
    if not success then return end

    if command == "VERSION_REQ" then
        -- Reply with my version
        self:SendComm("VERSION_RESP", DesolateLootcouncil.version, sender)
    elseif command == "VERSION_RESP" then
        -- Store sender's version
        self.playerVersions[sender] = data
        -- Sync to Core for Debug module
        if DesolateLootcouncil.activeAddonUsers then
            DesolateLootcouncil.activeAddonUsers[sender] = true
        end
        -- Fire AceEvent DLC_VERSION_UPDATE
        self:SendMessage("DLC_VERSION_UPDATE", sender, data)
    end
end

function Comm:SendVersionCheck()
    -- Broadcast VERSION_REQ
    self.playerVersions = {}          -- Reset locally on new check? Logic implies yes.
    self:SendComm("VERSION_REQ", nil) -- Broadcast
end

function Comm:GetActiveUserCount()
    -- Return count of unique players in playerVersions
    local count = 0
    for _ in pairs(self.playerVersions) do
        count = count + 1
    end
    return count
end
