---@class DesolateLootcouncil : AceAddon, AceConsole-3.0, AceEvent-3.0, AceComm-3.0, AceTimer-3.0
---@field ShowPriorityOverrideWindow fun(self: DesolateLootcouncil, listName: string)
---@field GetItemCategory fun(self: DesolateLootcouncil, item: any): string
---@field LogPriorityChange fun(self: DesolateLootcouncil, msg: string)
---@field UpdateLootMasterStatus fun(self: DesolateLootcouncil)
---@field db { profile: table, RegisterCallback: function }
---@field activeLootMaster string|nil
---@field currentLootMaster string|nil
---@field currentSessionLoot table|nil
---@field amILM boolean
---@field AddItemToList fun(self: DesolateLootcouncil, item: string, listIndex: number)
---@field RemoveItemFromList fun(self: DesolateLootcouncil, listIndex: number, itemID: number)
---@field GetPriorityListNames fun(self: DesolateLootcouncil): table
---@field AddPriorityList fun(self: DesolateLootcouncil, name: string)
---@field RemovePriorityList fun(self: DesolateLootcouncil, index: number)
---@field RenamePriorityList fun(self: DesolateLootcouncil, index: number, newName: string)
---@field MovePlayerToBottom fun(self: DesolateLootcouncil, listName: string, playerName: string)
---@field LogHistory fun(self: DesolateLootcouncil, itemData: table, winner: string, response: string)
---@field ShuffleLists fun(self: DesolateLootcouncil)
---@field SyncMissingPlayers fun(self: DesolateLootcouncil)
---@field ShowHistoryWindow fun(self: DesolateLootcouncil)
---@field ShowPriorityOverrideWindow fun(self: DesolateLootcouncil)
---@field GetItemIDFromLink fun(self: DesolateLootcouncil, link: string): number|nil
---@field GetItemCategory fun(self: DesolateLootcouncil, itemID: number|string): string
---@field SetItemCategory fun(self: DesolateLootcouncil, itemID: number|string, targetListIndex: number)
---@field AddItemToList fun(self: DesolateLootcouncil, link: string, listIndex: number)
---@field RemoveItemFromList fun(self: DesolateLootcouncil, itemID: number|string, listIndex: number)
---@field UnassignItem fun(self: DesolateLootcouncil, itemID: number|string)
---@field AmILootMaster fun(self: DesolateLootcouncil): boolean
---@field DetermineLootMaster fun(self: DesolateLootcouncil): string|nil
---@field Print fun(self: DesolateLootcouncil, ...: any)
---@field NewModule fun(self: DesolateLootcouncil, name: string, ...: any): any
---@field GetModule fun(self: DesolateLootcouncil, name: string): any
---@field activeAddonUsers table
---@field historyFrame AceGUIFrame|nil
---@field priorityOverrideFrame AceGUIFrame|nil
---@field priorityOverrideContent AceGUIFrame|nil
---@field GetPriorityListNames fun(self: DesolateLootcouncil): table
---@field AddPriorityList fun(self: DesolateLootcouncil, name: string)
---@field RemovePriorityList fun(self: DesolateLootcouncil, name: string)
---@field RenamePriorityList fun(self: DesolateLootcouncil, oldName: string, newName: string)
---@field GetItemCategory fun(self: DesolateLootcouncil, itemID: number|string): string
---@field SetItemCategory fun(self: DesolateLootcouncil, itemID: number|string, listIndex: number)
---@field LogHistory fun(self: DesolateLootcouncil, entry: table)
DesolateLootcouncil = LibStub("AceAddon-3.0"):NewAddon("DesolateLootcouncil", "AceConsole-3.0", "AceEvent-3.0",
    "AceComm-3.0", "AceTimer-3.0")
_G.DesolateLootcouncil = DesolateLootcouncil

---@type UI
local UI
---@type Debug
local Debug
---@type Loot
local Loot
---@type Distribution
local Distribution
---@type Trade
local Trade

local defaults = {
    profile = {
        configuredLM = "", -- Name-Realm of the loot master
        PriorityLists = {
            { name = "Tier",         players = {} },
            { name = "Weapons",      players = {} },
            { name = "Rest",         players = {} },
            { name = "Collectables", players = {} }
        },
        MainRoster = {},
        playerRoster = { alts = {}, decay = {} }, -- mains moved to MainRoster
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







local COMM_PREFIX = "DLC_Ver"
DesolateLootcouncil.activeAddonUsers = {}

function DesolateLootcouncil:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("DesolateLootDB", defaults, true)

    -- Define Options HERE (Safe, because all modules are now loaded)
    -- Define Options HERE (Safe, because all modules are now loaded)
    -- Options are registered as a FUNCTION to support dynamic content (args)
    local function GetOptions()
        return {
            name = "Desolate Lootcouncil",
            handler = self,
            type = "group",
            args = {
                general = (self:GetModule("GeneralSettings") --[[@as GeneralSettings]]):GetGeneralOptions(),
                roster = (self:GetModule("Roster") --[[@as Roster]]):GetOptions(),
                priority = (self:GetModule("PrioritySettings") --[[@as PrioritySettings]]):GetOptions(),
                items = (self:GetModule("ItemSettings") --[[@as ItemSettings]]):GetItemOptions(),
            },
        }
    end

    LibStub("AceConfig-3.0"):RegisterOptionsTable("DesolateLootcouncil", GetOptions)
    self.LibAddonConfig = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DesolateLootcouncil", "Desolate Lootcouncil")

    self:RegisterChatCommand("dlc", "ChatCommand")

    self:Printf("Addon Initialized")
    self:Print("Loot Master is currently: " .. self:DetermineLootMaster())
    -- Initial LM Check
    self:ScheduleTimer("UpdateLootMasterStatus", 2)
end

function DesolateLootcouncil:DetermineLootMaster()
    -- Scenario A: Solo
    if not IsInGroup() then
        return (UnitName("player"))
    end

    local db = self.db
    if not db then return "Unknown" end
    local profile = db.profile

    -- Scenario B: Group Leader
    if UnitIsGroupLeader("player") then
        local candidate = profile and profile.configuredLM
        local finalLM = UnitName("player") -- Default to Leader (Self)

        -- Validation: Check if candidate is actually in the group
        if candidate and candidate ~= "" then
            if UnitInParty(candidate) or UnitInRaid(candidate) or candidate == UnitName("player") then
                finalLM = candidate
            end
        end

        return finalLM
    end

    -- Scenario C: Regular Member
    if self.activeLootMaster then
        return self.activeLootMaster
    end

    -- Fallback: If sync missing, default to current Group Leader
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 then -- rank 2 is leader
                return name
            end
        end
    elseif IsInGroup() then
        -- Check party members
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitIsGroupLeader(unit) then
                return (UnitName(unit))
            end
        end
    end

    return "Unknown"
end

DesolateLootcouncil.activeLootMaster = nil

function DesolateLootcouncil:AmILootMaster()
    -- 1. Get the authoritative name
    local masterName = self:DetermineLootMaster()

    -- 2. Compare with self
    return UnitName("player") == masterName
end

-- Sync Loot Master to the raid (If I am the leader)
function DesolateLootcouncil:SyncLM()
    if IsInGroup() and UnitIsGroupLeader("player") then
        local finalLM = self:DetermineLootMaster()

        -- Broadcast via Distribution Module
        ---@type Distribution
        local Dist = self:GetModule("Distribution") --[[@as Distribution]]
        if Dist and Dist.SendSyncLM then
            Dist:SendSyncLM(finalLM)
        end
    end
end

function DesolateLootcouncil:UpdateLootMasterStatus(event)
    if self.db.profile.verboseMode and event then
        self:Print("Event Triggered: " .. tostring(event))
    end

    -- 1. Recalculate LM (This covers all scenarios: Solo, Leader, Member)
    local lm = self:DetermineLootMaster()

    -- 2. If Leader, Force Sync (This ensures the network knows the decision)
    if IsInGroup() and UnitIsGroupLeader("player") then
        self:SyncLM()
    end

    -- 3. Update Local State
    self.currentLootMaster = lm
    self.amILM = (lm == UnitName("player"))

    self:Print("Loot Master is currently: " .. tostring(lm))

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
        if self.db.profile.verboseMode then
            self:Print("Version Check: " .. sender .. " has the addon.")
        end
    end
end

function DesolateLootcouncil:ChatCommand(input)
    -- Default to Config if empty
    if not input or input:trim() == "" then
        LibStub("AceConfigDialog-3.0"):Open("DesolateLootcouncil")
        return
    end
    local args = { strsplit(" ", input) }
    local cmd = string.lower(args[1])
    -- 1. CONFIG
    if cmd == "config" or cmd == "options" then
        LibStub("AceConfigDialog-3.0"):Open("DesolateLootcouncil")
        -- 2. TEST (Generates items - LM Only)
    elseif cmd == "test" then
        if self:AmILootMaster() then
            ---@type Loot
            local Loot = self:GetModule("Loot") --[[@as Loot]]
            if Loot and Loot.AddTestItems then
                Loot:AddTestItems()
            else
                self:Print("Error: AddTestItems function not found in Loot module.")
            end
        else
            self:Print("Error: You are not the Loot Master.")
        end
        -- 3. LOOT (The 'Inbox' for new drops - LM Only)
    elseif cmd == "loot" then
        if self:AmILootMaster() then
            ---@type UI
            local UI = self:GetModule("UI") --[[@as UI]]
            if UI and UI.ShowLootWindow then
                -- Explicitly pass the initial loot table
                UI:ShowLootWindow(self.db.profile.session.loot)
            else
                self:Print("Error: ShowLootWindow function not found in UI module.")
            end
        else
            self:Print("Error: You are not the Loot Master.")
        end
        -- 4. MONITOR / MASTER (The 'Work in Progress' Voting Window - LM Only)
    elseif cmd == "monitor" or cmd == "master" then
        if self:AmILootMaster() then
            ---@type UI
            local UI = self:GetModule("UI") --[[@as UI]]
            if UI and UI.ShowMonitorWindow then
                UI:ShowMonitorWindow()
            else
                self:Print("Error: Monitor window function not found in UI module.")
            end
        else
            self:Print("Error: You are not the Loot Master.")
        end
        -- 5. HISTORY (Public)
    elseif cmd == "history" then
        ---@type UI
        local UI = self:GetModule("UI") --[[@as UI]]
        if UI and UI.ShowHistoryWindow then
            UI:ShowHistoryWindow()
        else
            self:Print("Error: ShowHistoryWindow function not found.")
        end
        -- 6. TRADE (Pending Trades - LM Only)
        -- 6. TRADE (Pending Trades - LM Only)
    elseif cmd == "trade" then
        if self:AmILootMaster() then
            ---@type UI
            local UI = self:GetModule("UI") --[[@as UI]]
            if UI and UI.ShowTradeListWindow then
                UI:ShowTradeListWindow()
            else
                self:Print("Error: ShowTradeListWindow function not found.")
            end
        else
            self:Print("Error: You are not the Loot Master.")
        end

        -- 7. DEBUG / DEV TOOLS
    elseif cmd == "status" then
        ---@type Debug
        local Debug = self:GetModule("Debug") --[[@as Debug]]
        if Debug and Debug.ShowStatus then Debug:ShowStatus() end
    elseif cmd == "verbose" then
        ---@type Debug
        local Debug = self:GetModule("Debug") --[[@as Debug]]
        if Debug and Debug.ToggleVerbose then Debug:ToggleVerbose() end
    elseif cmd == "sim" then
        local arg = args[2]
        if arg then
            ---@type Debug
            local Debug = self:GetModule("Debug") --[[@as Debug]]
            if Debug and Debug.SimulateComm then Debug:SimulateComm(arg) end
        else
            self:Print("Usage: /dlc sim [playername] or [start]")
        end
    elseif cmd == "dump" then
        ---@type Debug
        local Debug = self:GetModule("Debug")
        if Debug and Debug.DumpKeys then Debug:DumpKeys() end
    elseif cmd == "add" then
        local arg = args[2]
        if arg then
            ---@type Loot
            local Loot = self:GetModule("Loot") --[[@as Loot]]
            if Loot and Loot.AddManualItem then Loot:AddManualItem(arg) end
        else
            self:Print("Usage: /dlc add [ItemLink]")
        end
    else
        self:Print("Available Commands:")
        self:Print(" /dlc config - Open settings")
        self:Print(" /dlc test - Generate test items (LM Only)")
        self:Print(" /dlc loot - Open Loot Drop Window (LM Only)")
        self:Print(" /dlc monitor - Open Master Looter Interface (LM Only)")
        self:Print(" /dlc trade - Open Pending Trades (LM Only)")
        self:Print(" /dlc history - Open Award History (Public)")
        self:Print(" /dlc status - Show Debug Status (Public)")
    end
end

function DesolateLootcouncil:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DLC]|r " .. tostring(msg))
end
