local addonName, addonTable = ...

-- --- Conflict Prevention (Dev vs Prod) ---
-- IsAddOnLoaded() is NOT reliable during main-chunk execution — it only returns
-- true after ADDON_LOADED fires, which is AFTER all main chunks have run.
-- Instead we query AceAddon's internal registry via GetAddon(name, silent).
-- The registry is populated the instant NewAddon("DesolateLootcouncil") succeeds,
-- so whichever version loads SECOND will correctly detect the first and abort.
do
    local existingAddon = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil", true)
    if existingAddon then
        local other = (addonName == "Desolate_Lootcouncil-Dev") and "Production" or "Dev"
        print(string.format("|cffff0000[Desolate Lootcouncil]|r %s ('%s') is already loaded. Aborting '%s' to prevent DB corruption.",
            other, existingAddon.name or "?", addonName))
        addonTable.abortLoad = true
        return
    end
end

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
---@field sessionAutopassActive boolean
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
        enableAutoLoot  = true,             -- Auto-pass on loot rolls (ON by default) -- Consolidated Logic (LM=Acquire, Raider=Pass)
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
        dbCreatedAt = 0,            -- Sentinel: prevents AceDB from pruning a profile to nil on PLAYER_LOGOUT
    }
}

function DesolateLootcouncil:OnInitialize()
    -- 1. Initialize DB
    self.db = LibStub("AceDB-3.0"):New("DesolateLootDB", defaults, true)

    -- 1a. Stamp the DB sentinel so it's never 0 (equal to its default).
    --     AceDB's removeDefaults() strips keys that equal their default value.
    --     If dbCreatedAt stayed 0 it would match the default and could be pruned,
    --     defeating the purpose of the sentinel. We only stamp it on first creation.
    if self.db.profile.dbCreatedAt == 0 then
        self.db.profile.dbCreatedAt = GetServerTime()
    end

    -- 2. Prevent AceDB from auto-stripping profile data on PLAYER_LOGOUT.
    --    AceDB's logoutHandler calls db:RegisterDefaults(nil) which runs removeDefaults(),
    --    stripping any key that equals its default value. If ALL keys match, the profile
    --    becomes {} and is deleted — wiping imported or cross-character shared data.
    --    OnDatabaseShutdown fires BEFORE RegisterDefaults(nil), so we replace it with a
    --    no-op on this specific DB instance. Profiles are only removed by explicit user action.
    self.db.RegisterCallback(self, "OnDatabaseShutdown", function(_, db)
        db.RegisterDefaults = function() end
    end)

    -- 3. Initialize Active Users
    self.activeAddonUsers = {}
    -- 4. Initialize Simulated Group
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
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateLootMasterStatus")
    self:RegisterEvent("PARTY_LEADER_CHANGED", "UpdateLootMasterStatus")
end

local REFRESH_TIMER = nil

function DesolateLootcouncil:GET_ITEM_INFO_RECEIVED()
    if REFRESH_TIMER then
        self:CancelTimer(REFRESH_TIMER)
    end
    REFRESH_TIMER = self:ScheduleTimer(function()
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")

        local session = self.db and self.db.profile and self.db.profile.session
        if session then
            local repaired = false
            local function repairList(list)
                if not list then return end
                for _, item in ipairs(list) do
                    if item.itemID then
                        local _, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(item.itemID)
                        if link and (item.link == nil or string.find(item.link, "^Item %d+") or string.find(item.link, "Item %[%d+%]")) then
                            item.link = link
                            repaired = true
                        end
                        if icon and item.texture == "Interface\\Icons\\INV_Misc_QuestionMark" then
                            item.texture = icon
                            repaired = true
                        end
                    end
                end
            end
            
            repairList(session.loot)
            repairList(session.bidding)
            repairList(session.awarded)
            
            -- If items were successfully repaired, trigger UI refreshes
            if DesolateLootcouncil.db.profile.session.awarded then
                self:DLC_Log("Item Cache Engine repaired uncached session items.")
            end
            
            -- Global auto-refresh for any open frames to pull the updated UI data
            ---@type UI_Loot
            local LootUI = self:GetModule("UI_Loot") --[[@as UI_Loot]]
            if LootUI and LootUI.lootFrame and LootUI.lootFrame:IsShown() then
                LootUI:ShowLootWindow(session.loot)
            end
            
            ---@type UI_Monitor
            local MonitorUI = self:GetModule("UI_Monitor") --[[@as UI_Monitor]]
            if MonitorUI and MonitorUI.monitorFrame and MonitorUI.monitorFrame:IsShown() then
                MonitorUI:ShowMonitorWindow()
            end
            
            ---@type UI_Voting
            local VotingUI = self:GetModule("UI_Voting") --[[@as UI_Voting]]
            if VotingUI and VotingUI.votingFrame and VotingUI.votingFrame:IsShown() then
                VotingUI:ShowVotingWindow(self:GetModule("Session").clientLootList, true)
            end
            
            ---@type UI_TradeList
            local TradeUI = self:GetModule("UI_TradeList") --[[@as UI_TradeList]]
            if TradeUI and TradeUI.tradeListFrame and TradeUI.tradeListFrame:IsShown() then
                TradeUI:ShowTradeListWindow()
            end
            
            ---@type UI_History
            local HistoryUI = self:GetModule("UI_History") --[[@as UI_History]]
            if HistoryUI and HistoryUI.historyFrame and HistoryUI.historyFrame.frame and HistoryUI.historyFrame.frame:IsShown() then
                HistoryUI:ShowHistoryWindow()
            end
        end

        ---@type UI_ItemManager
        local ItemMgr = self:GetModule("UI_ItemManager") --[[@as UI_ItemManager]]
        if ItemMgr and ItemMgr.frame and (ItemMgr.frame --[[@as any]]).frame:IsShown() then
            ItemMgr:RefreshWindow()
        end

        REFRESH_TIMER = nil
    end, 0.5)
end

-- --- Loot Master Logic ---

function DesolateLootcouncil:DetermineLootMaster()
    local myName = UnitName("player")
    if not IsInGroup() then return myName end

    -- Disable entirely if we are in LFR
    if IsPartyLFG() or HasLFGRestrictions() then
        return nil
    end

    local configuredLM = self.db.profile.configuredLM
    if configuredLM and configuredLM ~= "" then
        if self:IsUnitInRaid(configuredLM) or configuredLM == myName then
             configuredLM = activeLM
        end
        self:DLC_Log("Configured LM (" .. configuredLM .. ") not found. Falling back to Group Leader.")
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
    return nil
end

function DesolateLootcouncil:UpdateLootMasterStatus()
    if not self.db then return end
    local targetLM = self:DetermineLootMaster()
    local myName = UnitName("player")
    self.amILM = (targetLM == myName)
    self:DLC_Log("Role Update: You are " .. (self.amILM and "Loot Master" or "Raider"))

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

-- Bug 3: Raid Assists can view Monitor but not award
function DesolateLootcouncil:AmIRaidAssistOrLM()
    if self.amILM then return true end
    if IsInRaid() then
        -- Check own rank: 0=member, 1=assist, 2=leader
        local myName = UnitName("player")
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name and rank >= 1 then
                local shortName = Ambiguate(name, "none")
                if shortName == myName then return true end
            end
        end
    end
    return false
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
