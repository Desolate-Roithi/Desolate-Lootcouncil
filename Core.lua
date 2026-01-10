---@class DesolateLootcouncil : AceAddon, AceConsole-3.0, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0, AceTimer-3.0
---@field db table
---@field version string
---@field amILM boolean
---@field activeAddonUsers table<string, boolean>
---@field activeLootMaster string
---@field currentSessionLoot table
---@field PriorityLog table
---@field simulatedGroup table
---@field DefaultLayouts table<string, table>
---@field optionsFrame table
---@field OnInitialize fun(self: DesolateLootcouncil)
---@field OnEnable fun(self: DesolateLootcouncil)
---@field GET_ITEM_INFO_RECEIVED fun(self: DesolateLootcouncil)
---@field ChatCommand fun(self: DesolateLootcouncil, input: string)
---@field RestorePlayerPosition fun(self: DesolateLootcouncil, listName: string, playerName: string, index: number)
---@field GetReversionIndex fun(self: DesolateLootcouncil, listName: string, origIndex: number, timestamp: number): number
---@field AddManualItem fun(self: DesolateLootcouncil, itemLink: string)
---@field GetPlayerVersion fun(self: DesolateLootcouncil, name: string): string
---@field DLC_Log fun(self: DesolateLootcouncil, msg: any, force?: boolean)
---@field RegisterChatCommand fun(self: any, cmd: string, func: string|function)
---@field RegisterEvent fun(self: any, event: string, func?: string|function)
---@field ScheduleTimer fun(self: any, func: function, delay: number, ...: any): any
---@field CancelTimer fun(self: any, timer: any)
---@field GetModule fun(self: DesolateLootcouncil, name: string, silent?: boolean): any
---@field NewModule fun(self: DesolateLootcouncil, name: string, ...): any
---@field Print fun(self: DesolateLootcouncil, msg: any)
---@field IsUnitInRaid fun(self: DesolateLootcouncil, unitName: string): boolean
---@field SaveFramePosition fun(self: DesolateLootcouncil, frame: any, windowName: string)
---@field RestoreFramePosition fun(self: DesolateLootcouncil, frame: any, windowName: string)
---@field OpenConfig fun(self: DesolateLootcouncil)
---@field ToggleWindowCollapse fun(self: DesolateLootcouncil, frame: any)
---@field ApplyCollapseHook fun(self: DesolateLootcouncil, widget: any)
---@field GetMain fun(self: DesolateLootcouncil, name: string): string
---@field GetEnchantingSkillLevel fun(self: DesolateLootcouncil, name?: string): number
---@field ShowPriorityOverrideWindow fun(self: DesolateLootcouncil, listName: string)
---@field GetItemCategory fun(self: DesolateLootcouncil, item: any): string
---@field SetItemCategory fun(self: DesolateLootcouncil, itemID: number|string, listIndex: number)
---@field LogPriorityChange fun(self: DesolateLootcouncil, msg: string)
---@field UpdateLootMasterStatus fun(self: DesolateLootcouncil, event?: string)
---@field DetermineLootMaster fun(self: DesolateLootcouncil): string
---@field GetPriorityListNames fun(self: DesolateLootcouncil): table
---@field AddPriorityList fun(self: DesolateLootcouncil, name: string)
---@field RemovePriorityList fun(self: DesolateLootcouncil, index: number)
---@field RenamePriorityList fun(self: DesolateLootcouncil, index: number, newName: string)
---@field MovePlayerToBottom fun(self: DesolateLootcouncil, listName: string, playerName: string)
---@field ShuffleLists fun(self: DesolateLootcouncil)
---@field SyncMissingPlayers fun(self: DesolateLootcouncil)
---@field ShowHistoryWindow fun(self: DesolateLootcouncil)
---@field ShowPriorityHistoryWindow fun(self: DesolateLootcouncil)
---@field AmILootMaster fun(self: DesolateLootcouncil): boolean
---@field AddMain fun(self: DesolateLootcouncil, name: string)
---@field AddAlt fun(self: DesolateLootcouncil, altName: string, mainName: string)
---@field RemovePlayer fun(self: DesolateLootcouncil, name: string)
---@field SendVersionCheck fun(self: DesolateLootcouncil)
---@field GetActiveUserCount fun(self: DesolateLootcouncil): number
---@field AddItemToList fun(self: DesolateLootcouncil, link: string, listIndex: number)
---@field RemoveItemFromList fun(self: DesolateLootcouncil, listIndex: number, itemID: number)
---@field GetOptions fun(self: DesolateLootcouncil): table

---@type DesolateLootcouncil
DesolateLootcouncil = LibStub("AceAddon-3.0"):NewAddon("DesolateLootcouncil", "AceConsole-3.0", "AceEvent-3.0",
    "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0")
_G.DesolateLootcouncil = DesolateLootcouncil
DesolateLootcouncil.version = C_AddOns and C_AddOns.GetAddOnMetadata("Desolate_Lootcouncil", "Version") or "1.0.0"

-- 0. Hardcode Initial State (Silences startup spam before DB loads)
local INITIAL_DEBUG_MODE = false

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
        debugMode = false,
        session = {
            loot = {},
            bidding = {},       -- Items currently being voted on (Safe Space)
            awarded = {},       -- Persistent history of awarded items
            lootedMobs = {},
            isOpen = false      -- Track if the window was open
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

-- ... existing code ...


function DesolateLootcouncil:OnInitialize()
    -- 1. Initialize DB (Fixed Name to match TOC)
    self.db = LibStub("AceDB-3.0"):New("DesolateLootDB", defaults, true)
    -- 2. Initialize Active Users (Prevents Debug Crash)
    self.activeAddonUsers = {}
    -- 3. Initialize Simulated Group (Defaults to Self)
    self.simulatedGroup = { [UnitName("player")] = true }

    -- 5. Register with AceConfig
    -- Register as a function to ensure dynamic rebuilding of tables (items, lists) on NotifyChange
    LibStub("AceConfig-3.0"):RegisterOptionsTable("DesolateLootcouncil", function() return self:GetOptions() end)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DesolateLootcouncil", "Desolate Loot Council")

    -- 6. Validate/Notify
    if self.db.profile.configuredLM == "" then
        self:DLC_Log("Warning: No Loot Master configured. Use /dlc config to set one.")
    end
    self:UpdateLootMasterStatus()

    -- 7. Register Chat Command
    self:RegisterChatCommand("dlc", "ChatCommand")
    self:RegisterChatCommand("dl", "ChatCommand")

    -- 8. Welcome Message (Silenced if debugMode is OFF)
    if not self.db.profile.positions then self.db.profile.positions = {} end
    self:DLC_Log("Desolate Lootcouncil " .. self.version .. " Loaded.")
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
        -- Check if they are actually here (Smart lookup handles Sims + Real Players)
        if self:IsUnitInRaid(configuredLM) or configuredLM == myName then
            return configuredLM
        end
        -- If configured LM is offline/missing, fall through to Group Leader
        self:DLC_Log("Configured LM (" .. configuredLM .. ") not found. Falling back to Group Leader.", true)
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

    self:DLC_Log("Role Update: You are " .. (self.amILM and "Loot Master" or "Raider"), true)

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
    self:DLC_Log("Added Main: " .. name)
end

function DesolateLootcouncil:AddAlt(altName, mainName)
    if not self.db then return end
    if not altName or not mainName then return end

    if altName == mainName then
        self:DLC_Log("Error: Cannot add a player as an alt to themselves.")
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
            self:DLC_Log("Re-linked inherited alt: " .. existingAlt .. " -> " .. mainName)
        end
    end
    -- 2. Perform the standard assignment
    roster.alts[altName] = mainName
    -- 3. Remove from Mains list if present
    if profile.MainRoster and profile.MainRoster[altName] then
        profile.MainRoster[altName] = nil
        self:DLC_Log("Converted Main to Alt: " .. altName)
    end

    self:DLC_Log("Linked Alt " .. altName .. " to " .. mainName)
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
                    self:DLC_Log("Unlinked Alt: " .. alt)
                end
            end
        end
        self:DLC_Log("Removed Main: " .. name)
        return
    end

    -- Try delete as Alt
    if profile.playerRoster.alts[name] then
        profile.playerRoster.alts[name] = nil
        self:DLC_Log("Removed Alt: " .. name)
    end
end

function DesolateLootcouncil:GetMain(name)
    if not self.db or not name then return name end
    local profile = self.db.profile
    local alts = profile.playerRoster and profile.playerRoster.alts
    local mains = profile.MainRoster
    local realm = GetRealmName():gsub("%s+", "") -- Remove spaces for safety
    local full = string.find(name, "-") and name or (name .. "-" .. realm)
    local short = Ambiguate(name, "none")

    -- 1. Try to find if 'name' is an Alt
    local resolvedMain = nil
    if alts then
        resolvedMain = alts[name] or alts[full] or alts[short]
    end

    -- If found in alts, that's our candidate. Otherwise, input name is the candidate.
    local candidate = resolvedMain or name

    -- 2. Validate 'candidate' against MainRoster to get the Canonical Key
    if mains then
        if mains[candidate] then return candidate end

        -- Try variations for the candidate
        local cFull = string.find(candidate, "-") and candidate or (candidate .. "-" .. realm)
        local cShort = Ambiguate(candidate, "none")

        if mains[cFull] then return cFull end
        if mains[cShort] then return cShort end
    end

    return candidate
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
        self:DLC_Log("Invalid item: " .. tostring(input))
        return
    end

    if not list.items then list.items = {} end
    list.items[itemID] = true
    self:DLC_Log("Added item " .. itemID .. " to list " .. list.name)
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function DesolateLootcouncil:RemoveItemFromList(listIdx, itemID)
    if not self.db then return end
    local db = self.db.profile
    local list = db.PriorityLists[listIdx]
    if list and list.items then
        list.items[itemID] = nil
        self:DLC_Log("Removed item " .. itemID .. " from " .. list.name)
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
        self:DLC_Log("Set category for item " .. itemID .. " to " .. targetList.name)
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
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.GetPriorityListNames then
        return Priority:GetPriorityListNames()
    end
    return {}
end

function DesolateLootcouncil:AddPriorityList(name)
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.AddPriorityList then
        Priority:AddPriorityList(name)
    end
end

function DesolateLootcouncil:RemovePriorityList(index)
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.RemovePriorityList then
        Priority:RemovePriorityList(index)
    end
end

function DesolateLootcouncil:RenamePriorityList(index, newName)
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.RenamePriorityList then
        Priority:RenamePriorityList(index, newName)
    end
end

function DesolateLootcouncil:LogPriorityChange(msg)
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.LogPriorityChange then
        Priority:LogPriorityChange(msg)
    end
end

function DesolateLootcouncil:ShuffleLists()
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.ShuffleLists then
        Priority:ShuffleLists()
    end
end

function DesolateLootcouncil:SyncMissingPlayers()
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.SyncMissingPlayers then
        Priority:SyncMissingPlayers()
    end
end

function DesolateLootcouncil:MovePlayerToBottom(listName, playerName)
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.MovePlayerToBottom then
        return Priority:MovePlayerToBottom(listName, playerName)
    end
end

function DesolateLootcouncil:RestorePlayerPosition(listName, playerName, index)
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.RestorePlayerPosition then
        Priority:RestorePlayerPosition(listName, playerName, index)
    end
end

function DesolateLootcouncil:GetReversionIndex(listName, origIndex, timestamp)
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.GetReversionIndex then
        return Priority:GetReversionIndex(listName, origIndex, timestamp)
    end
    return origIndex
end

function DesolateLootcouncil:ShowPriorityHistoryWindow()
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.ShowPriorityHistoryWindow then
        Priority:ShowPriorityHistoryWindow()
    end
end

function DesolateLootcouncil:ShowHistoryWindow()
    ---@type UI
    local UI = self:GetModule("UI")
    if UI and UI.ShowHistoryWindow then
        UI:ShowHistoryWindow()
    end
end

function DesolateLootcouncil:ShowPriorityOverrideWindow(listName)
    ---@type Priority
    local Priority = self:GetModule("Priority")
    if Priority and Priority.ShowPriorityOverrideWindow then
        Priority:ShowPriorityOverrideWindow(listName)
    end
end

function DesolateLootcouncil:OpenConfig()
    local frame = LibStub("AceConfigDialog-3.0"):Open("DesolateLootcouncil")
    if frame then
        self:RestoreFramePosition(frame, "Config")
        local savePos = function(f)
            DesolateLootcouncil:SaveFramePosition(f, "Config")
        end
        frame.frame:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            savePos(f)
        end)
        frame.frame:SetScript("OnHide", savePos)
        self:ApplyCollapseHook(frame)
    end
end

-- --- Chat Command ---

function DesolateLootcouncil:ChatCommand(input)
    -- Default to Config if empty
    if not input or input:trim() == "" then
        self:OpenConfig()
        return
    end
    local args = { strsplit(" ", input) }
    local cmd = string.lower(args[1])
    -- 1. CONFIG
    if cmd == "config" or cmd == "options" then
        self:OpenConfig()
        -- 1.5 SHOW / VOTE
    elseif cmd == "show" or cmd == "vote" then
        local session = self.db.profile.session
        if session and session.bidding and #session.bidding > 0 then
            ---@type UI
            local UI = self:GetModule("UI")
            if UI and UI.ShowVotingWindow then
                UI:ShowVotingWindow(session.bidding)
                self:DLC_Log("Re-opening Voting Window for active session.")
            end
        else
            self:DLC_Log("No active session to show.")
        end
        -- 2. TEST (Generates items - LM Only)
    elseif cmd == "test" then
        if self:AmILootMaster() then
            ---@type Loot
            local Loot = self:GetModule("Loot") --[[@as Loot]]
            if Loot and Loot.AddTestItems then
                Loot:AddTestItems()
            else
                self:DLC_Log("Error: AddTestItems function not found in Loot module.")
            end
        else
            self:DLC_Log("Error: You are not the Loot Master.")
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
                self:DLC_Log("Error: ShowLootWindow function not found in UI module.")
            end
        else
            self:DLC_Log("Error: You are not the Loot Master.")
        end
        -- 4. MONITOR / MASTER (The 'Work in Progress' Voting Window - LM Only)
    elseif cmd == "monitor" or cmd == "master" then
        if self:AmILootMaster() then
            ---@type UI
            local UI = self:GetModule("UI") --[[@as UI]]
            if UI and UI.ShowMonitorWindow then
                UI:ShowMonitorWindow()
            else
                self:DLC_Log("Error: Monitor window function not found in UI module.")
            end
        else
            self:DLC_Log("Error: You are not the Loot Master.")
        end
        -- 5. HISTORY (Public)
    elseif cmd == "history" then
        ---@type UI
        local UI = self:GetModule("UI") --[[@as UI]]
        if UI and UI.ShowHistoryWindow then
            UI:ShowHistoryWindow()
        else
            self:DLC_Log("Error: ShowHistoryWindow function not found.")
        end
        -- 6. TRADE (Pending Trades - LM Only)
    elseif cmd == "trade" then
        if self:AmILootMaster() then
            ---@type UI
            local UI = self:GetModule("UI") --[[@as UI]]
            if UI and UI.ShowTradeListWindow then
                UI:ShowTradeListWindow()
            else
                self:DLC_Log("Error: ShowTradeListWindow function not found.")
            end
        else
            self:DLC_Log("Error: You are not the Loot Master.")
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
            self:DLC_Log("Usage: /dlc add [ItemLink]")
        end
    elseif cmd == "reset" then
        -- Reset Active Users (Manual Sync Trigger)
        self.activeAddonUsers = {}
        self:SendVersionCheck()
        self:DLC_Log("Reset addon user list and sent ping.")
    elseif cmd == "version" then
        local isTest = (args[2] == "test")
        ---@type VersionUI
        local VersionUI = self:GetModule("VersionUI") --[[@as VersionUI]]
        if VersionUI and VersionUI.ShowVersionWindow then
            VersionUI:ShowVersionWindow(isTest)
        else
            self:DLC_Log("Error: VersionUI module not found.")
        end
    elseif cmd == "session" then
        ---@type Session
        local Session = self:GetModule("Session")
        if Session then
            -- Pass the rest of the arguments to the module
            local input = table.concat(args, " ", 2)
            Session:HandleSlashCommand(input)
        end
    elseif cmd == "sim" then
        ---@type Simulation
        local Sim = self:GetModule("Simulation")
        if Sim then
            local input = table.concat(args, " ", 2)
            Sim:HandleSlashCommand(input)
        end
    else
        self:DLC_Log("Available Commands:", true)
        self:DLC_Log(" /dlc - Open settings", true)
        self:DLC_Log(" /dlc history - Open Award History (Public)", true)
        self:DLC_Log(" /dlc version - Check Raid Addon Versions", true)
        self:DLC_Log(" /dlc vote - Open Loot vote window", true)
        self:DLC_Log(" /dlc add - Add Item to List", true)
        self:DLC_Log(" /dlc loot - Open Loot Drop Window (LM Only)", true)
        self:DLC_Log(" /dlc monitor - Open Master Looter Interface (LM Only)", true)
        self:DLC_Log(" /dlc trade - Open Pending Trades (LM Only)", true)
    end
end

function DesolateLootcouncil:Print(msg)
    self:DLC_Log(msg, true)
end

function DesolateLootcouncil:DLC_Log(msg, forceShow)
    -- 1. STRICT FILTER: If not forced AND debug is off, STOP immediately.
    local debugMode = false
    if self.db and self.db.profile then
        debugMode = self.db.profile.debugMode
    else
        debugMode = INITIAL_DEBUG_MODE
    end

    if not forceShow and not debugMode then return end

    -- 2. CLEANUP: Remove any existing [DLC] prefix to prevent doubles.
    local cleanMsg = tostring(msg):gsub("^%[DLC%]%s*", "")

    -- 3. PRINT: Add the single prefix and print.
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DLC]|r " .. cleanMsg)
end

function DesolateLootcouncil:SaveFramePosition(frame, windowName)
    local actualFrame = frame.frame or frame
    local point, _, relativePoint, xOfs, yOfs = actualFrame:GetPoint()

    if not self.db.profile.positions then self.db.profile.positions = {} end

    self.db.profile.positions[windowName] = {
        point = point,
        relativePoint = relativePoint,
        x = xOfs,
        y = yOfs,
        width = actualFrame:GetWidth(),
        height = actualFrame:GetHeight(),
    }
    self:DLC_Log("Saved Layout: " .. windowName)
end

function DesolateLootcouncil:ToggleWindowCollapse(widget)
    local frame = widget.frame or widget
    if not frame.isCollapsed then
        -- Collapse
        frame.savedHeight = frame:GetHeight()
        frame:SetHeight(30)

        -- Helper to detect if an element is part of the header area
        local function IsInHeader(obj)
            -- Check explicit references first
            if obj == widget.titletext or obj == widget.titlebg or obj == widget.statusIcon or obj.isTitleOverlay then return true end

            -- Check all anchor points
            for i = 1, obj:GetNumPoints() do
                local point, relativeTo, relativePoint, x, y = obj:GetPoint(i)

                -- Keep elements anchored TO our protected parts
                if relativeTo == widget.titletext or relativeTo == widget.titlebg or relativeTo == widget.statusIcon then return true end

                -- Central Header ornaments (anchored to TOP and within title bar height)
                -- We EXCLUDE TOPLEFT/TOPRIGHT to hide side rails
                if relativePoint == "TOP" and (y or 0) > -25 then
                    return true
                end
            end

            return false
        end

        -- 1. Hide the main content container (AceGUI standard)
        if widget.content then
            widget.content:Hide()
            widget.content.tempHidden = true
        end
        if frame.content and frame.content ~= widget.content then
            frame.content:Hide()
            frame.content.tempHidden = true
        end

        -- 2. Handle child frames (Buttons, status icons, etc.)
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if not IsInHeader(child) then
                if child:IsShown() then
                    child:Hide()
                    child.tempHidden = true
                end
            else
                child:Show()
                child.tempHidden = nil
            end
        end

        -- 3. Handle regions (Textures/Borders)
        local regions = { frame:GetRegions() }
        for _, region in ipairs(regions) do
            if not IsInHeader(region) then
                if region:IsShown() then
                    region:Hide()
                    region.tempHidden = true
                end
            else
                region:Show()
                region.tempHidden = nil
            end
        end

        frame.isCollapsed = true
    else
        -- Expand
        frame:SetHeight(frame.savedHeight or 400)

        if widget.content and widget.content.tempHidden then
            widget.content:Show()
            widget.content.tempHidden = nil
        end
        if frame.content and frame.content.tempHidden then
            frame.content:Show()
            frame.content.tempHidden = nil
        end

        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if child.tempHidden then
                child:Show()
                child.tempHidden = nil
            end
        end

        local regions = { frame:GetRegions() }
        for _, region in ipairs(regions) do
            if region.tempHidden then
                region:Show()
                region.tempHidden = nil
            end
        end

        frame.isCollapsed = false
    end
end

function DesolateLootcouncil:ApplyCollapseHook(widget)
    local frame = widget.frame or widget
    -- Invisible button covering the title bar
    local titleBtn = CreateFrame("Button", nil, frame)
    titleBtn.isTitleOverlay = true
    titleBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0) -- Leave space for Close [X]
    titleBtn:SetHeight(24)
    titleBtn:SetFrameLevel(frame:GetFrameLevel() + 5)        -- Low enough to be behind text but capture clicks
    titleBtn:EnableMouse(true)
    titleBtn:RegisterForClicks("LeftButtonUp")

    frame:SetMovable(true)

    -- 1. Handle Double Click (Collapse)
    titleBtn:SetScript("OnDoubleClick", function()
        DesolateLootcouncil:ToggleWindowCollapse(widget)
    end)

    -- 2. Handle Dragging (Passthrough)
    titleBtn:SetScript("OnMouseDown", function()
        if not frame.isCollapsed then frame:StartMoving() end
    end)
    titleBtn:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        DesolateLootcouncil:SaveFramePosition(frame, widget.type or "Window")
    end)
end

function DesolateLootcouncil:RestoreFramePosition(frame, windowName)
    local actualFrame = frame.frame or frame
    if not self.db.profile.positions then self.db.profile.positions = {} end
    local pos = self.db.profile.positions[windowName]
    local def = self.DefaultLayouts and self.DefaultLayouts[windowName]

    actualFrame:ClearAllPoints()

    if pos and pos.point then
        -- Use UIParent as the base
        actualFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x, pos.y)
        if pos.width and pos.height then
            if frame.SetWidth then frame:SetWidth(pos.width) else actualFrame:SetWidth(pos.width) end
            if frame.SetHeight then frame:SetHeight(pos.height) else actualFrame:SetHeight(pos.height) end
        end
    elseif def then
        -- Use centralized DefaultLayouts
        actualFrame:SetPoint(def.point, UIParent, def.relativePoint or def.point, def.x, def.y)
        if def.width and def.height then
            if frame.SetWidth then frame:SetWidth(def.width) else actualFrame:SetWidth(def.width) end
            if frame.SetHeight then frame:SetHeight(def.height) else actualFrame:SetHeight(def.height) end
        end
    end
end

--- Global Helper: Is unit in raid/party OR simulated?
function DesolateLootcouncil:IsUnitInRaid(unitName)
    ---@type Simulation
    local Sim = self:GetModule("Simulation")
    if Sim and Sim:IsSimulated(unitName) then
        return true
    end
    -- Standard Checks
    return UnitInRaid(unitName) or UnitInParty(unitName)
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

    local UI = self:GetModule("UI")
    if UI and UI.GetAttendanceOptions then
        options.args.attendance = UI:GetAttendanceOptions()
    end

    return options
end

function DesolateLootcouncil:GetEnchantingSkillLevel()
    local prof1, prof2 = GetProfessions()
    local profs = { prof1, prof2 }
    for _, index in pairs(profs) do
        if index then
            local name, _, rank = GetProfessionInfo(index)
            if name and (name == "Enchanting" or string.find(name, "Enchanting")) then
                return rank
            end
        end
    end
    return 0
end
