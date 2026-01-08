---@class DesolateLootcouncil : AceAddon, AceConsole-3.0, AceEvent-3.0, AceComm-3.0, AceTimer-3.0
---@field ShowPriorityOverrideWindow fun(self: DesolateLootcouncil, listName: string)
---@field GetItemCategory fun(self: DesolateLootcouncil, item: any): string
---@field SetItemCategory fun(self: DesolateLootcouncil, itemID: number|string, listIndex: number)
---@field LogPriorityChange fun(self: DesolateLootcouncil, msg: string)
---@field UpdateLootMasterStatus fun(self: DesolateLootcouncil, event?: string)
---@field DetermineLootMaster fun(self: DesolateLootcouncil): string
---@field amILM boolean
---@field GetPriorityListNames fun(self: DesolateLootcouncil): table
---@field AddPriorityList fun(self: DesolateLootcouncil, name: string)
---@field RemovePriorityList fun(self: DesolateLootcouncil, index: number)
---@field RenamePriorityList fun(self: DesolateLootcouncil, index: number, newName: string)
---@field MovePlayerToBottom fun(self: DesolateLootcouncil, listName: string, playerName: string)
---@field ShuffleLists fun(self: DesolateLootcouncil)
---@field SyncMissingPlayers fun(self: DesolateLootcouncil)
---@field ShowHistoryWindow fun(self: DesolateLootcouncil)
---@field AmILootMaster fun(self: DesolateLootcouncil): boolean
---@field AddMain fun(self: DesolateLootcouncil, name: string)
---@field AddAlt fun(self: DesolateLootcouncil, altName: string, mainName: string)
---@field RemovePlayer fun(self: DesolateLootcouncil, name: string)
---@field SendVersionCheck fun(self: DesolateLootcouncil)
---@field GetActiveUserCount fun(self: DesolateLootcouncil): number
---@field activeAddonUsers table
---@field AddItemToList fun(self: DesolateLootcouncil, link: string, listIndex: number)
---@field RemoveItemFromList fun(self: DesolateLootcouncil, listIndex: number, itemID: number)
---@field GetOptions fun(self: DesolateLootcouncil): table
---@field version string
---@field db table
---@field optionsFrame table
---@field currentSessionLoot table
---@field OnInitialize fun(self: DesolateLootcouncil)
---@field OnEnable fun(self: DesolateLootcouncil)
---@field GET_ITEM_INFO_RECEIVED fun(self: DesolateLootcouncil)
---@field ChatCommand fun(self: DesolateLootcouncil, input: string)
---@field PriorityLog table
---@field RestorePlayerPosition fun(self: DesolateLootcouncil, listName: string, playerName: string, index: number)
---@field GetReversionIndex fun(self: DesolateLootcouncil, listName: string, origIndex: number, timestamp: number): number
---@field AddManualItem fun(self: DesolateLootcouncil, itemLink: string)
---@field GetPlayerVersion fun(self: DesolateLootcouncil, name: string): string
---@field activeLootMaster string
---@field RegisterChatCommand fun(self: any, cmd: string, func: string|function)
---@field RegisterEvent fun(self: any, event: string, func?: string|function)
---@field ScheduleTimer fun(self: any, func: function, delay: number, ...: any): any
---@field CancelTimer fun(self: any, timer: any)
---@field GetModule fun(self: any, name: string, silent?: boolean): any
---@field Print fun(self: any, msg: string)

---@type DesolateLootcouncil
DesolateLootcouncil = LibStub("AceAddon-3.0"):NewAddon("DesolateLootcouncil", "AceConsole-3.0", "AceEvent-3.0",
    "AceComm-3.0", "AceTimer-3.0")
_G.DesolateLootcouncil = DesolateLootcouncil
DesolateLootcouncil.version = C_AddOns and C_AddOns.GetAddOnMetadata("Desolate_Lootcouncil", "Version") or "1.0.0"

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
            { name = "Tier",         players = {}, items = {} },
            { name = "Weapons",      players = {}, items = {} },
            { name = "Rest",         players = {}, items = {} },
            { name = "Collectables", players = {}, items = {} }
        },
        MainRoster = {},
        playerRoster = { alts = {}, decay = {} }, -- mains moved to MainRoster
        verboseMode = false,
        session = {
            loot = {},
            bidding = {},       -- Items currently being voted on (Safe Space)
            awarded = {},       -- Persistent history of awarded items
            lootedMobs = {},
            isOpen = false      -- Track if the window was open
        },
        minLootQuality = 3,     -- Default to Rare
        enableAutoLoot = false, -- Consolidated Logic (LM=Acquire, Raider=Pass)
    }
}

function DesolateLootcouncil:OnInitialize()
    -- 1. Initialize DB (Fixed Name to match TOC)
    self.db = LibStub("AceDB-3.0"):New("DesolateLootDB", defaults, true)
    -- 2. Initialize Active Users (Prevents Debug Crash)
    self.activeAddonUsers = {}

    -- 5. Register with AceConfig
    -- Register as a function to ensure dynamic rebuilding of tables (items, lists) on NotifyChange
    LibStub("AceConfig-3.0"):RegisterOptionsTable("DesolateLootcouncil", function() return self:GetOptions() end)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DesolateLootcouncil", "Desolate Loot Council")

    -- 6. Validate/Notify
    if self.db.profile.configuredLM == "" then
        self:Print("Warning: No Loot Master configured. Use /dlc config to set one.")
    end
    self:UpdateLootMasterStatus()

    -- 7. Register Chat Command
    self:RegisterChatCommand("dlc", "ChatCommand")
    self:RegisterChatCommand("dl", "ChatCommand")

    -- 8. Welcome Message
    self:Print("Desolate Lootcouncil " .. self.version .. " Loaded.")
end

function DesolateLootcouncil:OnEnable()
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

-- Refresh Debounce
local REFRESH_TIMER = nil

function DesolateLootcouncil:GET_ITEM_INFO_RECEIVED()
    -- Debounce to prevent lag spikes during mass item loading
    if REFRESH_TIMER then
        self:CancelTimer(REFRESH_TIMER)
    end
    REFRESH_TIMER = self:ScheduleTimer(function()
        -- 1. Refresh Settings to update item names
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")

        -- 2. Refresh Loot Window if open
        ---@type UI
        local UI = self:GetModule("UI") --[[@as UI]]
        if UI and UI.lootFrame and UI.lootFrame:IsShown() then
            UI:ShowLootWindow(self.db.profile.session.loot)
        end

        REFRESH_TIMER = nil
    end, 0.5) -- 0.5s delay
end

-- --- Loot Master Logic ---

function DesolateLootcouncil:DetermineLootMaster()
    local myName = UnitName("player")

    -- 1. Solo Check: If not in a group, YOU are always LM.
    if not IsInGroup() then
        return myName
    end

    -- 2. Configured Check
    local configuredLM = self.db.profile.configuredLM
    if configuredLM and configuredLM ~= "" then
        -- Check if they are actually here
        if UnitInRaid(configuredLM) or UnitInParty(configuredLM) or configuredLM == myName then
            return configuredLM
        end
        -- If configured LM is offline/missing, fall through to Group Leader
        self:Print("Configured LM (" .. configuredLM .. ") not found. Falling back to Group Leader.")
    end

    -- 3. Fallback: Group Leader
    -- Find the leader
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 then -- 2 is Leader
                return name
            end
        end
    elseif IsInGroup() then
        if UnitIsGroupLeader("player") then
            return myName
        end
        -- Iterate party members to find leader (or returns nil if player isn't leader?)
        -- Actually, UnitIsGroupLeader("partyN") works.
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitIsGroupLeader(unit) then
                return (UnitName(unit))
            end
        end
    end

    -- Ultimate Fallback
    return myName
end

function DesolateLootcouncil:UpdateLootMasterStatus()
    if not self.db then return end

    local targetLM = self:DetermineLootMaster()
    local myName = UnitName("player")

    self.amILM = (targetLM == myName)

    self:Print("[DLC] Role Update: You are " .. (self.amILM and "LOOT MASTER" or "Raider"))

    -- Communication: Sync functionality if I am the LM
    if self.amILM and IsInGroup() then
        ---@type Distribution
        local Dist = self:GetModule("Distribution") --[[@as Distribution]]
        if Dist and Dist.SendSyncLM then
            Dist:SendSyncLM(targetLM)
        end
    end
end

function DesolateLootcouncil:AmILootMaster()
    return self.amILM
end

-- --- Roster Management Logic ---

function DesolateLootcouncil:AddMain(name)
    if not self.db then return end
    if not name or name == "" then return end

    local devDB = self.db.profile
    if not devDB or not devDB.MainRoster or not devDB.playerRoster then return end

    devDB.MainRoster[name] = { addedAt = time() } -- Store main with timestamp
    devDB.playerRoster.alts[name] = nil           -- Ensure not an alt
    self:Print("Added Main: " .. name)
end

function DesolateLootcouncil:AddAlt(altName, mainName)
    if not self.db then return end
    if not altName or not mainName then return end

    if altName == mainName then
        self:Print("Error: Cannot add a player as an alt to themselves.")
        return
    end

    local profile = self.db.profile
    if not profile or not profile.playerRoster or not profile.playerRoster.alts then return end
    local roster = profile.playerRoster

    -- 1. Check if the 'new alt' was previously a Main with their own alts
    -- We need to re-parent those alts to the NEW main.
    for existingAlt, existingMain in pairs(roster.alts) do
        if existingMain == altName then
            roster.alts[existingAlt] = mainName
            self:Print("Re-linked inherited alt: " .. existingAlt .. " -> " .. mainName)
        end
    end
    -- 2. Perform the standard assignment
    roster.alts[altName] = mainName
    -- 3. Remove from Mains list if present
    if profile.MainRoster and profile.MainRoster[altName] then
        profile.MainRoster[altName] = nil
        self:Print("Converted Main to Alt: " .. altName)
    end

    self:Print("Linked Alt " .. altName .. " to " .. mainName)
end

function DesolateLootcouncil:RemovePlayer(name)
    if not self.db then return end
    if not name then return end

    local profile = self.db.profile

    -- Try delete as Main
    if profile.MainRoster and profile.MainRoster[name] then
        profile.MainRoster[name] = nil
        -- Unlink alts
        if profile.playerRoster and profile.playerRoster.alts then
            for alt, main in pairs(profile.playerRoster.alts) do
                if main == name then
                    profile.playerRoster.alts[alt] = nil
                    self:Print("Unlinked Alt: " .. alt)
                end
            end
        end
        self:Print("Removed Main: " .. name)
        return
    end

    -- Try delete as Alt
    if profile.playerRoster.alts[name] then
        profile.playerRoster.alts[name] = nil
        self:Print("Removed Alt: " .. name)
    end
end

-- --- Priority List & Item Management Logic ---

function DesolateLootcouncil:AddPriorityList(name)
    if not self.db then return end
    local db = self.db.profile
    if not name or name == "" then return end

    -- Check duplicate
    for _, list in ipairs(db.PriorityLists) do
        if list.name == name then return end
    end

    -- Create new list populated with SHUFFLED roster (Basic Implementation)
    local newList = {}
    if db.MainRoster then
        for rName, _ in pairs(db.MainRoster) do
            table.insert(newList, rName)
        end
    end

    -- Simple shuffle
    for i = #newList, 2, -1 do
        local j = math.random(i)
        newList[i], newList[j] = newList[j], newList[i]
    end

    table.insert(db.PriorityLists, { name = name, players = newList, items = {} })
    self:Print("Added new Priority List: " .. name)
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function DesolateLootcouncil:RemovePriorityList(index)
    if not self.db then return end
    local db = self.db.profile
    if db.PriorityLists[index] then
        local removed = table.remove(db.PriorityLists, index)
        self:Print("Removed Priority List: " .. removed.name)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function DesolateLootcouncil:RenamePriorityList(index, newName)
    if not self.db then return end
    local db = self.db.profile
    if db.PriorityLists[index] and newName ~= "" then
        db.PriorityLists[index].name = newName
        self:Print("Renamed list to: " .. newName)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

-- Item Manager Impl

function DesolateLootcouncil:AddItemToList(input, listIdx)
    if not self.db or not input then return end
    local db = self.db.profile
    local list = db.PriorityLists[listIdx]
    if not list then return end

    -- Extract ItemID
    local itemID = C_Item.GetItemInfoInstant(input)
    if not itemID then
        itemID = tonumber(input) or tonumber(input:match("item:(%d+)"))
    end

    if not itemID then
        self:Print("Invalid item: " .. tostring(input))
        return
    end

    if not list.items then list.items = {} end
    list.items[itemID] = true
    self:Print("Added item " .. itemID .. " to list " .. list.name)
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function DesolateLootcouncil:RemoveItemFromList(listIdx, itemID)
    if not self.db then return end
    local db = self.db.profile
    local list = db.PriorityLists[listIdx]
    if list and list.items then
        list.items[itemID] = nil
        self:Print("Removed item " .. itemID .. " from " .. list.name)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function DesolateLootcouncil:SetItemCategory(itemID, targetListIndex)
    if not self.db then return end
    local db = self.db.profile
    local lists = db.PriorityLists

    itemID = tonumber(itemID)
    if not itemID then return end

    -- 1. Remove from all other lists
    for i, list in ipairs(lists) do
        if list.items then
            list.items[itemID] = nil
        end
    end

    -- 2. Add to target list
    local targetList = lists[targetListIndex]
    if targetList then
        if not targetList.items then targetList.items = {} end
        targetList.items[itemID] = true
        self:Print("Set category for item " .. itemID .. " to " .. targetList.name)
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function DesolateLootcouncil:GetItemCategory(itemID)
    if not self.db then return "Junk/Pass" end
    local db = self.db.profile
    if not db.PriorityLists then return "Junk/Pass" end

    itemID = tonumber(itemID)
    if not itemID then return "Junk/Pass" end

    for _, list in ipairs(db.PriorityLists) do
        if list.items and list.items[itemID] then
            return list.name
        end
    end
    return "Junk/Pass"
end

-- --- Version Logic ---

function DesolateLootcouncil:SendVersionCheck()
    ---@type Comm
    local Comm = self:GetModule("Comm") --[[@as Comm]]
    if Comm and Comm.SendVersionCheck then
        Comm:SendVersionCheck()
    end
end

function DesolateLootcouncil:GetActiveUserCount()
    ---@type Comm
    local Comm = self:GetModule("Comm") --[[@as Comm]]
    if Comm and Comm.GetActiveUserCount then
        return Comm:GetActiveUserCount()
    end
    return 0
end

-- --- Missing Utility Methods (Restored) ---

function DesolateLootcouncil:GetPriorityListNames()
    if not self.db then return {} end
    local names = {}
    if self.db.profile.PriorityLists then
        for _, list in ipairs(self.db.profile.PriorityLists) do
            table.insert(names, list.name)
        end
    end
    return names
end

function DesolateLootcouncil:ShuffleLists()
    if not self.db then return end
    local db = self.db.profile
    if not db.PriorityLists then return end

    -- Master list of all players (MainRoster)
    local masterList = {}
    if db.MainRoster then
        for name in pairs(db.MainRoster) do
            table.insert(masterList, name)
        end
    end

    for _, listObj in ipairs(db.PriorityLists) do
        -- Clone master list
        local currentList = {}
        for _, name in ipairs(masterList) do
            table.insert(currentList, name)
        end

        -- Shuffle
        for i = #currentList, 2, -1 do
            local j = math.random(i)
            currentList[i], currentList[j] = currentList[j], currentList[i]
        end
        listObj.players = currentList
        self:Print("Shuffled List: " .. listObj.name)
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function DesolateLootcouncil:SyncMissingPlayers()
    if not self.db then return end
    local db = self.db.profile
    if not db.PriorityLists then return end

    local masterList = {}
    if db.MainRoster then
        for name in pairs(db.MainRoster) do
            masterList[name] = true
        end
    end

    for _, listObj in ipairs(db.PriorityLists) do
        local currentSet = {}
        for _, p in ipairs(listObj.players) do
            currentSet[p] = true
        end

        for name in pairs(masterList) do
            if not currentSet[name] then
                table.insert(listObj.players, name)
                self:Print("Added missing " .. name .. " to " .. listObj.name)
            end
        end
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function DesolateLootcouncil:ShowHistoryWindow()
    ---@type UI
    local UI = self:GetModule("UI")
    if UI and UI.ShowHistoryWindow then
        UI:ShowHistoryWindow()
    end
end

function DesolateLootcouncil:ShowPriorityOverrideWindow(listName)
    -- Placeholder for now or check if UI module implements it
    self:Print("Priority Override Window not implemented yet.")
end

function DesolateLootcouncil:LogPriorityChange(msg)
    -- Placeholder
end

-- --- Chat Command ---

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
    elseif cmd == "reset" then
        -- Reset Active Users (Manual Sync Trigger)
        self.activeAddonUsers = {}
        self:SendVersionCheck()
        self:Print("Reset addon user list and sent ping.")
    elseif cmd == "version" then
        local isTest = (args[2] == "test")
        ---@type VersionUI
        local VersionUI = self:GetModule("VersionUI") --[[@as VersionUI]]
        if VersionUI and VersionUI.ShowVersionWindow then
            VersionUI:ShowVersionWindow(isTest)
        else
            self:Print("Error: VersionUI module not found.")
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
        self:Print(" /dlc version - Check Raid Addon Versions")
    end
end

function DesolateLootcouncil:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DLC]|r " .. tostring(msg))
end

function DesolateLootcouncil:GetOptions()
    local options = {
        type = "group",
        name = "Desolate Loot Council",
        handler = DesolateLootcouncil,
        args = {}
    }

    local GeneralSettings = self:GetModule("GeneralSettings")
    if GeneralSettings and GeneralSettings.GetGeneralOptions then
        options.args.general = GeneralSettings:GetGeneralOptions()
    end

    local ItemSettings = self:GetModule("ItemSettings")
    if ItemSettings and ItemSettings.GetItemOptions then
        options.args.items = ItemSettings:GetItemOptions()
    end

    local Roster = self:GetModule("Roster")
    if Roster and Roster.GetOptions then
        options.args.roster = Roster:GetOptions()
    end

    local PrioritySettings = self:GetModule("PrioritySettings")
    if PrioritySettings and PrioritySettings.GetOptions then
        options.args.priority = PrioritySettings:GetOptions()
    end

    return options
end
