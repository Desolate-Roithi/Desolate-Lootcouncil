---@diagnostic disable: duplicate-set-field, undefined-global
---@class DesolateLootcouncil : AceAddon, AceConsole-3.0, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0, AceTimer-3.0
---@field db table
---@field version string
---@field amILM boolean
---@field activeLootMaster string
---@field PriorityLog table
---@field Logic table
---@field Comm Comm
---@field Session Session
---@field Loot Loot
---@field DefaultLayouts table<string, table>
---@field SlashCommands table
---@field SettingsLoader table
---@field Persistence Persistence
---@field Logger table
DesolateLootcouncil = LibStub("AceAddon-3.0"):NewAddon("DesolateLootcouncil", "AceConsole-3.0", "AceEvent-3.0",
    "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0")
_G.DesolateLootcouncil = DesolateLootcouncil
DesolateLootcouncil.version = C_AddOns and C_AddOns.GetAddOnMetadata("Desolate_Lootcouncil", "Version") or "1.0.0"

local defaults = {
    profile = {
        configuredLM = "",
        PriorityLists = {
            { name = "Tier",         players = {}, items = {} },
            { name = "Weapons",      players = {}, items = {} },
            { name = "Rest",         players = {}, items = {} },
            { name = "Collectables", players = {}, items = {} }
        },
        MainRoster = {},
        playerRoster = { alts = {}, decay = {} },
        verboseMode = false,
        debugMode = false,
        session = {
            loot = {},
            bidding = {},
            awarded = {},
            lootedMobs = {},
            isOpen = false
        },
        minLootQuality = 3,     -- Default to Rare
        enableAutoLoot = false, -- Consolidated Logic (LM=Acquire, Raider=Pass)
        DecayConfig = {
            enabled = true,
            defaultPenalty = 1,     -- Configurable (0-3)
            sessionActive = false,
            currentSessionID = nil, -- Timestamp
            lastActivity = nil,     -- Timestamp for stale checks
            currentAttendees = {},  -- Table: [MainName] = true
        },
        AttendanceHistory = {},     -- List of past sessions { date, zone, attendees }
        positions = {},             -- Window positions { [windowName] = { point, relativePoint, xOfs, yOfs } }
    }
}

function DesolateLootcouncil:OnInitialize()
    -- 1. Initialize DB
    self.db = LibStub("AceDB-3.0"):New("DesolateLootDB", defaults, true)
    -- 2. Initialize Active Users
    self.activeAddonUsers = {}
    -- 3. Initialize Simulated Group
    self.simulatedGroup = { [UnitName("player")] = true }

    -- 5. Register with AceConfig
    LibStub("AceConfig-3.0"):RegisterOptionsTable("DesolateLootcouncil", function() return self:GetOptions() end)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DesolateLootcouncil", "Desolate Loot Council")

    -- 6. Validate/Notify
    if self.db.profile.configuredLM == "" then
        self:DLC_Log("Warning: No Loot Master configured. Use /dlc config to set one.")
    end
    self:UpdateLootMasterStatus()

    -- 7. Register Chat Command
    self:RegisterChatCommand("dlc", function(input) self.SlashCommands.Handle(input) end)
    self:RegisterChatCommand("dl", function(input) self.SlashCommands.Handle(input) end)

    -- 8. Welcome Message
    if not self.db.profile.positions then self.db.profile.positions = {} end
    self:DLC_Log("Desolate Lootcouncil " .. self.version .. " Loaded.")
end

function DesolateLootcouncil:OnEnable()
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

local REFRESH_TIMER = nil

function DesolateLootcouncil:GET_ITEM_INFO_RECEIVED()
    if REFRESH_TIMER then
        self:CancelTimer(REFRESH_TIMER)
    end
    REFRESH_TIMER = self:ScheduleTimer(function()
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
        ---@type UI_Loot
        local LootUI = self:GetModule("UI_Loot") --[[@as UI_Loot]]
        if LootUI and LootUI.lootFrame and LootUI.lootFrame:IsShown() then
            LootUI:ShowLootWindow(self.db.profile.session.loot)
        end
        REFRESH_TIMER = nil
    end, 0.5)
end

-- --- Loot Master Logic ---

function DesolateLootcouncil:DetermineLootMaster()
    local myName = UnitName("player")
    if not IsInGroup() then return myName end

    local configuredLM = self.db.profile.configuredLM
    if configuredLM and configuredLM ~= "" then
        if self:IsUnitInRaid(configuredLM) or configuredLM == myName then
            return configuredLM
        end
        self:DLC_Log("Configured LM (" .. configuredLM .. ") not found. Falling back to Group Leader.", true)
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 then return name end
        end
    elseif IsInGroup() then
        if UnitIsGroupLeader("player") then return myName end
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitIsGroupLeader(unit) then return (UnitName(unit)) end
        end
    end
    return myName
end

function DesolateLootcouncil:UpdateLootMasterStatus()
    if not self.db then return end
    local targetLM = self:DetermineLootMaster()
    local myName = UnitName("player")
    self.amILM = (targetLM == myName)
    self:DLC_Log("Role Update: You are " .. (self.amILM and "Loot Master" or "Raider"), true)

    if self.amILM and IsInGroup() then
        ---@type Session
        local Session = self:GetModule("Session") --[[@as Session]]
        if Session and Session.SendSyncLM then
            Session:SendSyncLM(targetLM)
        end
    end
end

function DesolateLootcouncil:AmILootMaster()
    return self.amILM
end

-- --- Version Logic ---

function DesolateLootcouncil:SendVersionCheck()
    ---@type Comm
    local Comm = self:GetModule("Comm") --[[@as Comm]]
    if Comm and Comm.SendVersionCheck then Comm:SendVersionCheck() end
end

function DesolateLootcouncil:GetActiveUserCount()
    ---@type Comm
    local Comm = self:GetModule("Comm") --[[@as Comm]]
    if Comm and Comm.GetActiveUserCount then return Comm:GetActiveUserCount() end
    return 0
end

function DesolateLootcouncil:OpenConfig()
    -- Set default size for AceConfig specifically before opening
    local layouts = self.DefaultLayouts
    if layouts and layouts["Config"] then
        LibStub("AceConfigDialog-3.0"):SetDefaultSize("DesolateLootcouncil", layouts["Config"].width,
            layouts["Config"].height)
    end

    local frame = LibStub("AceConfigDialog-3.0"):Open("DesolateLootcouncil")
    if frame then
        self:RestoreFramePosition(frame, "Config")
        local savePos = function(f) self:SaveFramePosition(f, "Config") end
        local rawFrame = (frame --[[@as any]]).frame
        if rawFrame then
            rawFrame:HookScript("OnDragStop", function(f)
                f:StopMovingOrSizing()
                savePos(frame)
            end)
            rawFrame:HookScript("OnHide", function() savePos(frame) end)
        end

        if self.Persistence and self.Persistence.ApplyCollapseHook then
            self.Persistence:ApplyCollapseHook(frame, "Config")
        end
    end
end

-- --- Chat Command (Proxy for Modules) ---

-- ChatCommand logic moved to Core/SlashCommands.lua



function DesolateLootcouncil:DLC_Log(msg, force)
    if self.Logger then self.Logger.Log(msg, force) end
end

-- Persistence via Utility
function DesolateLootcouncil:SaveFramePosition(frame, windowName)
    if self.Persistence then self.Persistence:SaveFramePosition(frame, windowName) end
end

function DesolateLootcouncil:RestoreFramePosition(frame, windowName)
    if self.Persistence then self.Persistence:RestoreFramePosition(frame, windowName) end
end

--- Global Helper: Is unit in raid/party OR simulated?
function DesolateLootcouncil:IsUnitInRaid(unitName)
    ---@type Simulation
    local Sim = self:GetModule("Simulation") --[[@as Simulation]]
    if Sim and Sim.IsSimulated and Sim:IsSimulated(unitName) then return true end

    if IsInRaid() then
        return UnitInRaid(unitName) ~= nil
    elseif IsInGroup() then
        return UnitInParty(unitName) ~= nil or UnitIsUnit(unitName, "player")
    end
    return UnitIsUnit(unitName, "player")
end

function DesolateLootcouncil:GetOptions()
    if self.SettingsLoader then return self.SettingsLoader.GetOptions() end
    return { type = "group", args = {} }
end

--- Returns the player's enchanting skill level.
--- Returns nil if the player does not have Enchanting.
--- Returns the highest expansion skill level learned.
---@return number|nil
function DesolateLootcouncil:GetEnchantingSkillLevel()
    local prof1, prof2 = GetProfessions()
    local function IsEnchanting(id)
        if not id then return false end
        local name = GetProfessionInfo(id)
        return name == "Enchanting" or name == "Verzauberkunst"
    end

    if not IsEnchanting(prof1) and not IsEnchanting(prof2) then
        return nil
    end

    local highestRank = 0
    local found = false

    local ok, childInfos = pcall(C_TradeSkillUI.GetChildProfessionInfos)
    if ok and childInfos then
        for _, info in ipairs(childInfos) do
            if info.skillLevel then
                highestRank = math.max(highestRank, info.skillLevel)
                found = true
            end
        end
    end

    if not found then
        local function GetLegacyRank(id)
            if not id then return 0 end
            local name, _, rank = GetProfessionInfo(id)
            if name == "Enchanting" or name == "Verzauberkunst" then return rank end
            return 0
        end
        highestRank = math.max(GetLegacyRank(prof1), GetLegacyRank(prof2))
    end

    return highestRank
end
