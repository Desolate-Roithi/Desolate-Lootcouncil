DesolateLootcouncil = LibStub("AceAddon-3.0"):NewAddon("DesolateLootcouncil", "AceConsole-3.0", "AceEvent-3.0",
    "AceComm-3.0", "AceTimer-3.0")

local defaults = {
    profile = {
        configuredLM = "", -- Name-Realm of the loot master
        lootLists = { tier = {}, weapons = {}, rest = {}, collectables = {} },
        playerRoster = { mains = {}, alts = {}, decay = {} },
        verboseMode = false,
        session = {
            loot = {},
            bidding = {},   -- Items currently being voted on (Safe Space)
            awarded = {},   -- Persistent history of awarded items
            lootedMobs = {},
            isOpen = false  -- Track if the window was open
        },
        minLootQuality = 3, -- Default to Rare
    }
}

local options = {
    name = "Desolate Lootcouncil",
    handler = DesolateLootcouncil,
    type = "group",
    args = {
        lootMaster = {
            type = "input",
            name = "Loot Master Name",
            desc = "The Name-Realm of the loot master",
            get = function(info) return DesolateLootcouncil.db.profile.configuredLM end,
            set = function(info, val)
                DesolateLootcouncil.db.profile.configuredLM = val
                DesolateLootcouncil:UpdateLootMasterStatus()
            end,
        },
        minQuality = {
            type = "select",
            name = "Minimum Loot Quality",
            desc = "Items below this quality will be ignored (unless they are Tier/Weapons/Collectables)",
            values = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" },
            get = function(info) return DesolateLootcouncil.db.profile.minLootQuality end,
            set = function(info, val) DesolateLootcouncil.db.profile.minLootQuality = val end,
        },
    },
}

local COMM_PREFIX = "DLC_Ver"
DesolateLootcouncil.activeAddonUsers = {}

function DesolateLootcouncil:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("DesolateLootDB", defaults, true)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("DesolateLootcouncil", options)
    self.LibAddonConfig = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DesolateLootcouncil", "Desolate Lootcouncil")
    self:Printf("Addon Initialized")
end

function DesolateLootcouncil:GetActiveLM()
    local configured = self.db.profile.configuredLM
    if configured and configured ~= "" and (UnitInParty(configured) or UnitInRaid(configured)) then
        return configured
    end

    -- Fallback: Group Leader
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 then -- rank 2 is leader
                return name
            end
        end
    elseif IsInGroup() then
        if UnitIsGroupLeader("player") then return UnitName("player") end
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitIsGroupLeader(unit) then
                return UnitName(unit)
            end
        end
    end

    return UnitName("player") -- Fallback if not in group or solo
end

DesolateLootcouncil.activeLootMaster = nil

function DesolateLootcouncil:AmILootMaster()
    local target = self.activeLootMaster or self.db.profile.lootMaster
    if not target or target == "" then target = UnitName("player") end
    return UnitName("player") == target
end

-- Sync Loot Master to the raid (If I am the leader)
function DesolateLootcouncil:SyncLM()
    if IsInGroup() and UnitIsGroupLeader("player") then
        local targetLM = self.db.profile.configuredLM
        if not targetLM or targetLM == "" then targetLM = UnitName("player") end

        -- Broadcast via Distribution Module
        local Dist = self:GetModule("Distribution")
        if Dist and Dist.SendSyncLM then
            Dist:SendSyncLM(targetLM)
        end
    end
end

function DesolateLootcouncil:UpdateLootMasterStatus(event)
    if self.db.profile.verboseMode and event then
        self:Print("Event Triggered: " .. tostring(event))
    end

    -- Trigger Sync if leader
    self:SyncLM()

    local lm = self.activeLootMaster or self.db.profile.configuredLM or UnitName("player")
    self.currentLootMaster = lm
    self:Print("Loot Master is currently: " .. tostring(lm))

    -- Update AMILM status for local checks (optimization)
    self.amILM = (lm == UnitName("player"))

    -- Also trigger a version check when things update
    self:ScheduleTimer("SendVersionCheck", 2) -- Slight delay/throttle
end

function DesolateLootcouncil:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateLootMasterStatus")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateLootMasterStatus")
    self:RegisterEvent("PARTY_LEADER_CHANGED", "UpdateLootMasterStatus")

    self:RegisterComm(COMM_PREFIX, "OnCommReceived")

    if self.db.profile.verboseMode then
        self:Print("Debug Mode is ON (Persistent)")
    end

    -- Delay initial check
    self:ScheduleTimer("UpdateLootMasterStatus", 2, "OnEnable")
end

function DesolateLootcouncil:SendVersionCheck()
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
    if channel then
        self:SendCommMessage(COMM_PREFIX, "PING", channel)
    end
end

function DesolateLootcouncil:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= COMM_PREFIX then return end

    if message == "PING" then
        self:SendCommMessage(COMM_PREFIX, "PONG", "WHISPER", sender)
    elseif message == "PONG" then
        self.activeAddonUsers[sender] = true
        -- Debug
        -- self:Printf("User %s is using the addon.", sender)
    end
end

function DesolateLootcouncil:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DLC]|r " .. tostring(msg))
end
