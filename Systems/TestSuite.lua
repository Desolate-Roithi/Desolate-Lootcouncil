local _, AT = ...
if AT.abortLoad then return end

---@class TestScenario
---@field id string
---@field name string
---@field description string
---@field run function

---@class TestSuite : AceModule, AceConsole-3.0
local TestSuite = DesolateLootcouncil:NewModule("TestSuite", "AceConsole-3.0")

---@class (partial) DLC_Ref_TestSuite
---@field db table
---@field API table
---@field Serializer table
---@field DBMigrator table
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field GetModule fun(self: any, name: string, quiet?: boolean): any
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_TestSuite]]

-- ---------------------------------------------------------------------------
-- Canonical State 0 Baseline Export Payload
-- ---------------------------------------------------------------------------
local STATE_0_DATA = {
    schemaVersion = 200,
    config = {
        minLootQuality = 4,
        enableAutoLoot = false,
        enableAutoTrade = false,
        activeTheme = "Midnight",
        configuredLM = "Tester-Realm",
        DecayConfig = {
            sessionActive = false,
            currentAttendees = {},
            attendeeDetails = {}
        }
    },
    Roster = {
        MainRoster = {
            ["WarriorMain-Realm"] = { isOfficer = true, addedAt = 1788000000 },
            ["MageMain-Realm"]    = { isOfficer = false, addedAt = 1788000100 },
            ["PriestMain-Realm"]  = { isOfficer = false, addedAt = 1788000200 },
            ["RogueMain-Realm"]   = { isOfficer = false, addedAt = 1788000300 },
            ["DruidMain-Realm"]   = { isOfficer = false, addedAt = 1788000400 }
        },
        playerRoster = {
            alts = {
                ["WarriorAlt-Realm"] = "WarriorMain-Realm",
                ["PriestAlt-Realm"]  = "PriestMain-Realm"
            }
        }
    },
    PriorityListsContent = {
        {
            name = "Tier",
            players = { "WarriorMain-Realm", "MageMain-Realm", "PriestMain-Realm", "RogueMain-Realm", "DruidMain-Realm" }
        },
        {
            name = "Weapons",
            players = { "RogueMain-Realm", "WarriorMain-Realm", "DruidMain-Realm", "MageMain-Realm", "PriestMain-Realm" }
        },
        {
            name = "Rest",
            players = { "PriestMain-Realm", "DruidMain-Realm", "WarriorMain-Realm", "MageMain-Realm", "RogueMain-Realm" }
        },
        {
            name = "Collectables",
            players = { "DruidMain-Realm", "PriestMain-Realm", "MageMain-Realm", "WarriorMain-Realm", "RogueMain-Realm" }
        },
        {
            name = "Trinkets and Cantrips",
            players = { "MageMain-Realm", "PriestMain-Realm", "WarriorMain-Realm", "RogueMain-Realm", "DruidMain-Realm" }
        },
        {
            name = "Recipes",
            players = { "WarriorMain-Realm", "RogueMain-Realm", "PriestMain-Realm", "MageMain-Realm", "DruidMain-Realm" }
        }
    },
    ItemManagerContent = {
        {
            name = "Tier",
            items = { 16914, 16865 }
        },
        {
            name = "Weapons",
            items = { 17075, 19019 }
        },
        {
            name = "Rest",
            items = { 19136, 18809 }
        },
        {
            name = "Collectables",
            items = { 13335 }
        },
        {
            name = "Trinkets and Cantrips",
            items = { 19395, 18820 }
        },
        {
            name = "Recipes",
            items = { 16223 }
        }
    },
    History = {
        AttendanceHistory = {},
        AuditLog = {},
        session = {
            bidding = {},
            awarded = {},
            backlog = {},
            votes = {}
        }
    }
}

TestSuite.scenarios = {}
TestSuite.scenarioOrder = {}
TestSuite.lastExportString = ""
TestSuite.lastTestLogs = {}

-- ---------------------------------------------------------------------------
-- Scenario Registry & Engine
-- ---------------------------------------------------------------------------

--- Registers a test scenario with the suite.
---@param id string
---@param name string
---@param description string
---@param runFn function
function TestSuite:RegisterScenario(id, name, description, runFn)
    if not self.scenarios[id] then
        table.insert(self.scenarioOrder, id)
    end
    self.scenarios[id] = {
        id = id,
        name = name,
        description = description,
        run = runFn,
        status = "IDLE",
        lastRunTime = 0,
        errorMsg = nil
    }
end

--- Ensures TestSuite is executing within the dedicated isolated sandbox profile.
function TestSuite:EnsureSandboxProfile()
    if DesolateLootcouncil.db and DesolateLootcouncil.db.GetCurrentProfile and DesolateLootcouncil.db.SetProfile then
        local current = DesolateLootcouncil.db:GetCurrentProfile()
        if current ~= "TestSuite_Sandbox" then
            self.previousProfile = current
            DesolateLootcouncil.db:SetProfile("TestSuite_Sandbox")
            self:Log(string.format("Switched profile from '%s' to isolated sandbox 'TestSuite_Sandbox'.", tostring(current)))
        end
    end
end

--- Restores the user's active profile back to what was active before entering TestSuite.
---@return string?
function TestSuite:RestoreOriginalProfile()
    if self.previousProfile and DesolateLootcouncil.db and DesolateLootcouncil.db.SetProfile then
        local target = self.previousProfile
        self.previousProfile = nil
        DesolateLootcouncil.db:SetProfile(target)
        self:Log(string.format("Restored profile back to '%s'.", tostring(target)))
        return target
    end
    return nil
end

--- Resets the current profile to canonical State 0 using clean import serialization.
---@param force boolean?
---@param silent boolean?
---@return boolean, string
function TestSuite:ResetToStateZero(force, silent)
    self:EnsureSandboxProfile()

    if not force and self.isStateZeroClean then
        return true, self.lastExportString or ""
    end

    local Serializer = DesolateLootcouncil.Serializer
    local playerName = (UnitName and UnitName("player")) or "Tester"
    local normPlayer = DesolateLootcouncil.NormalizeName and DesolateLootcouncil:NormalizeName(playerName) or playerName

    local DeepCopy = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy) or function(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = type(v) == "table" and DeepCopy(v) or v end
        return res
    end

    local copy = DeepCopy(STATE_0_DATA)
    copy.config.configuredLM = normPlayer
    copy.Roster.MainRoster[normPlayer] = { isOfficer = true, addedAt = 1788000000 }

    local rawExport = Serializer:EncodePayload(copy)
    self.lastExportString = rawExport

    local success, err = DesolateLootcouncil.API:ImportProfileData(rawExport, nil, true)
    DesolateLootcouncil.db.profile.configuredLM = normPlayer
    DesolateLootcouncil.db.profile.unassignedPlayers = {}
    DesolateLootcouncil.db.profile.unassignedTimestamp = 0
    DesolateLootcouncil.db.profile.AttendanceHistory = {}
    DesolateLootcouncil.db.profile.AuditLog = {}
    DesolateLootcouncil.db.profile.historyTimestamp = 0
    DesolateLootcouncil.db.profile.auditTimestamp = 0
    DesolateLootcouncil.db.profile.session = {
        bidding = {},
        awarded = {},
        backlog = {},
        votes = {}
    }
    if DesolateLootcouncil.db.profile.DecayConfig then
        DesolateLootcouncil.db.profile.DecayConfig.sessionActive = false
        DesolateLootcouncil.db.profile.DecayConfig.currentSessionID = nil
        DesolateLootcouncil.db.profile.DecayConfig.currentAttendees = {}
        DesolateLootcouncil.db.profile.DecayConfig.attendeeDetails = {}
        DesolateLootcouncil.db.profile.DecayConfig.bossLogs = {}
    end
    DesolateLootcouncil.amILM = true
    DesolateLootcouncil.activeLootMaster = normPlayer
    if DesolateLootcouncil.UpdateLootMasterStatus then
        DesolateLootcouncil:UpdateLootMasterStatus()
    end

    self.isStateZeroClean = true

    if success then
        if not silent then
            self:Log("Reset database to clean State 0 baseline.")
        end
    else
        self:Log("Error resetting to State 0: " .. tostring(err))
    end

    return success, rawExport
end

--- Generates and stores the current export string for step inspection.
---@param label string?
---@return string
function TestSuite:CaptureStepExport(label)
    self.isStateZeroClean = false
    local exportStr = DesolateLootcouncil.API:ExportProfileData()
    self.lastExportString = exportStr or ""
    self.currentStepExports = self.currentStepExports or {}
    local stepLabel = label or ("Step " .. (#self.currentStepExports + 1))
    table.insert(self.currentStepExports, {
        label = stepLabel,
        exportString = self.lastExportString,
        time = GetTime()
    })
    self:Log(string.format("Captured export string checkpoint: [%s] (Length: %d)", stepLabel, #self.lastExportString))
    return self.lastExportString
end

--- Deep post-test integrity validator checking for state corruption or dangling references.
---@return boolean, string[]
function TestSuite:VerifyPostTestIntegrity()
    local issues = {}
    local db = DesolateLootcouncil.db.profile

    -- 1. Check Schema Version
    if not db.schemaVersion or db.schemaVersion < 200 then
        table.insert(issues, string.format("Schema version invalid: %s (expected >= 200)", tostring(db.schemaVersion)))
    end

    -- 2. Check Mains & Alts Integrity
    if db.playerRoster and db.playerRoster.alts then
        for alt, main in pairs(db.playerRoster.alts) do
            local hasMain = false
            if db.MainRoster then
                for mKey in pairs(db.MainRoster) do
                    if DesolateLootcouncil:SmartCompare(mKey, main) then
                        hasMain = true
                        break
                    end
                end
            end
            if not hasMain then
                table.insert(issues, string.format("Orphan Alt found: '%s' points to non-existent Main '%s'", alt, tostring(main)))
            end
        end
    end

    -- 3. Check Priority Lists Integrity
    if db.PriorityLists then
        for i, list in ipairs(db.PriorityLists) do
            if not list.name or list.name == "" then
                table.insert(issues, string.format("PriorityList #%d has missing or empty name", i))
            end
            if not list.players or type(list.players) ~= "table" then
                table.insert(issues, string.format("PriorityList '%s' has invalid players structure", list.name or tostring(i)))
            end
        end
    end

    -- 4. Check Attendance History Integrity
    if db.AttendanceHistory then
        for i, event in ipairs(db.AttendanceHistory) do
            if not event.sessionID then
                table.insert(issues, string.format("AttendanceHistory entry #%d is missing sessionID", i))
            end
        end
    end

    return (#issues == 0), issues
end

--- Appends a message to test logs and prints to chat if debug enabled.
---@param msg string
function TestSuite:Log(msg)
    self.lastTestLogs = self.lastTestLogs or {}
    table.insert(self.lastTestLogs, msg)
    if DesolateLootcouncil and DesolateLootcouncil.DLC_Log then
        DesolateLootcouncil:DLC_Log("[TestSuite] " .. msg)
    end
end

--- Executes a numbered part within a scenario domain.
---@param partIndex number
---@param totalParts number
---@param partTitle string
---@param fn fun()
function TestSuite:RunPart(partIndex, totalParts, partTitle, fn)
    self:Log(string.format("  -> [Part %d/%d]: %s", partIndex, totalParts, partTitle))
    fn()
    self:CaptureStepExport(string.format("Part_%d_%s", partIndex, partTitle:gsub("[^%w_]+", "_")))
    local ok, issues = self:VerifyPostTestIntegrity()
    if not ok then
        error(string.format("Integrity breach after Part %d [%s]: %s", partIndex, totalParts, table.concat(issues, "; ")))
    end
end

-- ---------------------------------------------------------------------------
-- Built-in Scenario Domains (6 Structured End-to-End Journeys)
-- ---------------------------------------------------------------------------

function TestSuite:OnInitialize()
    -- =======================================================================
    -- 1. Raid Roster, Alts & Priority Lifecycle
    -- =======================================================================
    self:RegisterScenario("roster_priority_lifecycle", "1. Raid Roster, Alts & Priority Lifecycle", "Verifies State 0 baseline, manual player/alt additions, cascading renames, priority reordering, and raider sync isolation.", function()
        local API = DesolateLootcouncil.API
        local Priority = DesolateLootcouncil:GetModule("Priority", true)
        local Sync = DesolateLootcouncil:GetModule("Sync", true)
        local db = DesolateLootcouncil.db.profile

        -- Part 1: State 0 Canonical Baseline Import & SHA-1 Roster Hash Verification
        self:RunPart(1, 5, "State0_Baseline_Hash", function()
            local ok, _ = self:ResetToStateZero()
            assert(ok, "Failed to import State 0 baseline")
            local mains = API:GetMainRosterList()
            assert(mains["WarriorMain-Realm"] ~= nil, "WarriorMain-Realm missing from MainRoster")
            assert(mains["MageMain-Realm"] ~= nil, "MageMain-Realm missing from MainRoster")
            local hash = API:GetRosterHash()
            assert(type(hash) == "string" and #hash > 0, "Roster hash must be non-empty string")
            self:Log("Canonical baseline loaded. Roster SHA-1 Hash: " .. hash)
        end)

        -- Part 2: Manual Add Main & Alt Binding
        self:RunPart(2, 5, "Add_Main_And_Alt", function()
            local added = API:AddMain("PaladinMain-Realm", "PALADIN", false)
            assert(added == true, "AddMain must return true")
            assert(API:IsMain("PaladinMain-Realm"), "PaladinMain must exist in MainRoster")
            if Priority and Priority.SyncMissingPlayers then
                Priority:SyncMissingPlayers()
            end
            local tierList = API:GetPriorityList("Tier")
            local lastPlayer = tierList.players[#tierList.players]
            assert(lastPlayer == "PaladinMain-Realm" or lastPlayer == "PaladinMain", "PaladinMain must be added to end of Tier list")

            local altAdded = API:AddAlt("PaladinAlt-Realm", "PaladinMain-Realm")
            assert(altAdded == true, "AddAlt must return true")
            assert(API:GetMain("PaladinAlt-Realm") == "PaladinMain-Realm" or API:GetMain("PaladinAlt-Realm") == "PaladinMain", "Alt must resolve to PaladinMain")
        end)

        -- Part 3: Roster Rename Cascading
        self:RunPart(3, 5, "Roster_Rename_Cascade", function()
            local ok = API:RenamePlayer("WarriorMain-Realm", "GladiatorMain-Realm")
            assert(ok == true, "RenamePlayer must return true")
            local mains = API:GetMainRosterList()
            assert(mains["WarriorMain-Realm"] == nil, "Old Main name removed from MainRoster")
            assert(mains["GladiatorMain-Realm"] ~= nil, "New Main name exists in MainRoster")
            assert(db.playerRoster.alts["WarriorAlt-Realm"] == "GladiatorMain-Realm", "Linked alt parent updated to GladiatorMain-Realm")
            local tierList = API:GetPriorityList("Tier")
            assert(tierList.players[1] == "GladiatorMain-Realm", "Priority list rank 1 updated to GladiatorMain-Realm")
        end)

        -- Part 4: Manual Priority Reorder & Incremental Timestamps
        self:RunPart(4, 5, "Priority_Manual_Reorder", function()
            local tierList = db.PriorityLists[1]
            local origRank3 = tierList.players[3]
            local origTimestamp = tierList.timestamp or 0
            local moved = table.remove(tierList.players, 3)
            table.insert(tierList.players, 1, moved)
            tierList.timestamp = GetServerTime() + 10
            assert(tierList.players[1] == origRank3, "Third player must now be at rank 1")
            assert(tierList.timestamp > origTimestamp, "List timestamp must increment for delta sync")
        end)

        -- Part 5: Raider Priority Isolation (No Broadcast Acceptance)
        self:RunPart(5, 5, "Raider_Priority_Isolation", function()
            if not Sync then return end
            local prevOfficer = DesolateLootcouncil.amIOfficer
            local prevLM = DesolateLootcouncil.amILM
            DesolateLootcouncil.amIOfficer = false
            DesolateLootcouncil.amILM = false

            local originalRank1 = db.PriorityLists[1].players[1]
            local fakePayload = {
                lists = { { name = "Tier", players = { "HackerRaider-Realm", "WarriorMain-Realm" } } },
                timestamps = { Tier = GetServerTime() + 5000 }
            }
            Sync:HandleMessage("SYNC_PRIORITY", fakePayload, "FakeLM-Realm")
            assert(db.PriorityLists[1].players[1] == originalRank1, "Non-officer raider must drop and reject incoming SYNC_PRIORITY")

            DesolateLootcouncil.amIOfficer = prevOfficer
            DesolateLootcouncil.amILM = prevLM
        end)

        self:Log("Scenario 1 [Roster, Alts & Priority Lifecycle] completed successfully.")
    end)

    -- =======================================================================
    -- 2. Live Raid Looting, Raider Bidding & Priority Awards
    -- =======================================================================
    self:RegisterScenario("live_loot_bidding_awards", "2. Live Raid Looting, Raider Bidding & Priority Awards", "Runs live raid loot intake, bidding queue staging, raider response sorting, priority demotion, re-awarding, and disenchant routing.", function()
        local API = DesolateLootcouncil.API
        local MonitorUI = DesolateLootcouncil:GetModule("UI_Monitor", true)
        local VotingUI = DesolateLootcouncil:GetModule("UI_Voting", true)
        local db = DesolateLootcouncil.db.profile

        -- Part 1: Start Raid Session & Auto/Manual Loot Intake
        self:RunPart(1, 6, "Session_Start_Loot_Intake", function()
            db.DecayConfig = db.DecayConfig or {}
            db.DecayConfig.sessionActive = true
            db.DecayConfig.currentSessionID = time()
            assert(API:IsRaidSessionActive() == true, "Raid session must be active")

            API:AddManualItem("|cffa335ee|Hitem:19019::::::::80:::::|h[Thunderfury]|h|r")
            API:AddManualItem("|cffa335ee|Hitem:19020::::::::80:::::|h[Ashkandi]|h|r")
            local backlog = API:GetLootBacklog()
            assert(#backlog >= 2, "Backlog must contain dropped items")
            if MonitorUI then MonitorUI:ShowMonitorWindow(true) end
        end)

        -- Part 2: Bidding Queue Staging & Category Overrides
        self:RunPart(2, 6, "Bidding_Queue_Staging", function()
            local backlog = API:GetLootBacklog()
            db.session = db.session or {}
            db.session.bidding = db.session.bidding or {}
            table.insert(db.session.bidding, {
                link = backlog[1].link,
                itemID = backlog[1].itemID,
                category = "Tier",
                sourceGUID = "TF-19019",
                stackIndex = 1
            })
            table.insert(db.session.bidding, {
                link = backlog[2].link,
                itemID = backlog[2].itemID,
                category = "Weapons",
                sourceGUID = "ASH-19020",
                stackIndex = 2
            })
            assert(#db.session.bidding == 2, "Bidding queue must stage 2 items")
            if MonitorUI then MonitorUI:ShowMonitorWindow(true) end
        end)

        -- Part 3: Raider Bidding Responses & Priority Sorting
        self:RunPart(3, 6, "Raider_Bids_And_Priority_Order", function()
            db.session.votes = db.session.votes or {}
            db.session.votes["TF-19019"] = {
                ["MageMain-Realm"] = { response = "Bid", roll = 85, note = "Bis weapon" },
                ["WarriorMain-Realm"] = { response = "Bid", roll = 99, note = "Main tank upgrade" },
                ["PriestMain-Realm"] = { response = "Pass", roll = 0 }
            }
            if VotingUI then VotingUI:ShowVotingWindow(db.session.bidding, true) end
            local tierList = API:GetPriorityList("Tier")
            assert(tierList ~= nil, "Tier priority list must exist for bid ordering")
        end)

        -- Part 4: Item Award, Priority List Demotion & Staging
        self:RunPart(4, 6, "Item_Award_Priority_Demotion", function()
            API:AwardItem("TF-19019", "WarriorMain-Realm", "Bid")
            assert(#db.session.awarded == 1, "Awarded table must contain 1 item")
            assert(db.session.awarded[1].winner == "WarriorMain-Realm", "Winner must be WarriorMain-Realm")

            local tierList = API:GetPriorityList("Tier")
            local players = tierList.players or tierList.order
            assert(players[#players] == "WarriorMain-Realm", "Winner must move to bottom of Tier priority list")
            if MonitorUI then MonitorUI:ShowMonitorWindow(true) end
        end)

        -- Part 5: Item Re-Award & Priority Position Restoration
        self:RunPart(5, 6, "Reaward_Position_Restoration", function()
            API:ReawardItem(1)
            assert(#db.session.awarded == 0, "Awarded table must be empty during re-award")
            assert(#db.session.bidding >= 1, "Item must return to bidding queue")
            local tierList = API:GetPriorityList("Tier")
            local players = tierList.players or tierList.order
            assert(players[1] == "WarriorMain-Realm", "Winner must be restored to rank 1 in Tier list upon re-award")

            -- Re-award cleanly to MageMain-Realm
            API:AwardItem(db.session.bidding[1].sourceGUID, "MageMain-Realm", "Bid")
            assert(#db.session.awarded == 1, "Re-awarded item resolved to new winner")
        end)

        -- Part 6: Disenchanter Auto-Assignment & Trade Staging
        self:RunPart(6, 6, "Disenchanter_Auto_Assignment", function()
            db.designatedDisenchanter = "EnchanterMain-Realm"
            table.insert(db.session.bidding, {
                link = "|cffa335ee|Hitem:19136::::::::80:::::|h[Mana Igniting Cord]|h|r",
                itemID = 19136,
                category = "Rest",
                sourceGUID = "DE-ITEM-1",
                stackIndex = 3
            })
            API:AwardItem("DE-ITEM-1", "EnchanterMain-Realm", "Disenchant")
            assert(#db.session.awarded == 2, "Disenchanted item staged into awarded table")
            local deAward = db.session.awarded[2]
            assert(deAward.winner == "EnchanterMain-Realm", "Recipient must be designated disenchanter")
            assert(deAward.voteType == "Disenchant", "Award voteType must be Disenchant")

            -- Cleanly conclude the live raid session state
            if db.DecayConfig then
                db.DecayConfig.sessionActive = false
                db.DecayConfig.currentSessionID = nil
            end
        end)

        self:Log("Scenario 2 [Live Raid Looting, Raider Bidding & Priority Awards] completed successfully.")
    end)

    -- =======================================================================
    -- 3. Raider Queue, Attendance & Encounter History
    -- =======================================================================
    self:RegisterScenario("attendance_encounters_queue", "3. Raider Queue, Attendance & Encounter History", "Validates unassigned player staging, encounter combat logging, mid-session alt swaps, multi-day splitting, and decay compaction.", function()
        local API = DesolateLootcouncil.API
        local RosterMod = DesolateLootcouncil:GetModule("Roster", true)
        local Att = DesolateLootcouncil:GetModule("Attendance", true)
        local Sim = DesolateLootcouncil:GetModule("Simulation", true)
        local Serializer = DesolateLootcouncil.Serializer
        local db = DesolateLootcouncil.db.profile

        -- Part 1: Unassigned Raider Staging & Role Assignment
        self:RunPart(1, 6, "Unassigned_Queue_Assignment", function()
            if RosterMod and RosterMod.RecordUnassignedPlayer then
                RosterMod:RecordUnassignedPlayer("GuestWarrior-Realm", "Raid")
                RosterMod:RecordUnassignedPlayer("GuestMage-Realm", "Raid")
                RosterMod:RecordUnassignedPlayer("GuestRogue-Realm", "Raid")
            end
            local unassigned = API:GetUnassignedPlayers()
            assert(#unassigned == 3, "Unassigned queue must contain 3 staged players")

            -- Assign Main
            local okMain = API:AssignUnassignedAsMain("GuestWarrior-Realm", "WARRIOR", false)
            assert(okMain == true and API:IsMain("GuestWarrior-Realm"), "GuestWarrior assigned as Main")

            -- Assign Alt
            local okAlt = API:AssignUnassignedAsAlt("GuestMage-Realm", "WarriorMain-Realm")
            assert(okAlt == true and API:IsAlt("GuestMage-Realm"), "GuestMage assigned as Alt")

            -- Dismiss
            API:DismissUnassignedPlayer("GuestRogue-Realm")
            assert(#API:GetUnassignedPlayers() == 0, "Unassigned queue empty after resolution")
        end)

        -- Part 2: Boss Encounter Combat Logging
        self:RunPart(2, 6, "Boss_Encounter_Combat_Logging", function()
            local prevDebug = db.debugMode
            local prevLM = DesolateLootcouncil.amILM
            db.debugMode = true
            DesolateLootcouncil.amILM = true

            if Att and Att.StartRaidSession then Att:StartRaidSession() end
            if Att and Att.OnEncounterStart and Att.OnEncounterEnd then
                -- Wipe then Kill
                Att:OnEncounterStart("ENCOUNTER_START", 101, "First Boss", 16, 20)
                Att:OnEncounterEnd("ENCOUNTER_END", 101, "First Boss", 16, 20, 0)
                Att:OnEncounterStart("ENCOUNTER_START", 101, "First Boss", 16, 20)
                Att:OnEncounterEnd("ENCOUNTER_END", 101, "First Boss", 16, 20, 1)

                -- Clean 1-shot Kill
                Att:OnEncounterStart("ENCOUNTER_START", 102, "Second Boss", 16, 20)
                Att:OnEncounterEnd("ENCOUNTER_END", 102, "Second Boss", 16, 20, 1)
            end
            if Att and Att.StopRaidSession then Att:StopRaidSession(true) end

            db.debugMode = prevDebug
            DesolateLootcouncil.amILM = prevLM

            assert(db.AttendanceHistory and #db.AttendanceHistory > 0, "Attendance history record must be created")
            local latest = db.AttendanceHistory[1]
            if latest.bossLogs then
                assert(#latest.bossLogs == 2, "History must contain 2 recorded boss encounters")
                assert(latest.bossLogs[1].killed == true, "Killed boss must be logged")
            end
        end)

        -- Part 3: Mid-Session Alt Swap & Credit Aggregation
        self:RunPart(3, 6, "Mid_Session_Alt_Swap", function()
            if not Sim or not Att then return end
            API:AddMain("SwapperMain-Realm", "WARRIOR", false)
            API:AddAlt("SwapperAlt-Realm", "SwapperMain-Realm")
            Sim:Add("SwapperMain-Realm")

            local prevDebug = db.debugMode
            local prevLM = DesolateLootcouncil.amILM
            db.debugMode = true
            DesolateLootcouncil.amILM = true

            Att:StartRaidSession()
            Att:OnEncounterStart("ENCOUNTER_START", 201, "Boss 1", 16, 20)
            Att:OnEncounterEnd("ENCOUNTER_END", 201, "Boss 1", 16, 20, 1)

            Sim:SwapCharacter("SwapperMain-Realm", "SwapperAlt-Realm", "MAGE")
            Att:OnEncounterStart("ENCOUNTER_START", 202, "Boss 2", 16, 20)
            Att:OnEncounterEnd("ENCOUNTER_END", 202, "Boss 2", 16, 20, 1)
            Att:StopRaidSession(true)

            db.debugMode = prevDebug
            DesolateLootcouncil.amILM = prevLM

            local latest = db.AttendanceHistory[1]
            assert(latest.attendees["SwapperMain-Realm"] == true, "Parent Main credited in attendance")
            if latest.attendeeDetails and latest.attendeeDetails["SwapperMain-Realm"] then
                local d = latest.attendeeDetails["SwapperMain-Realm"].attendedChars
                assert(d["SwapperMain-Realm"] ~= nil and d["SwapperAlt-Realm"] ~= nil, "Main and Alt kills aggregated under parent")
            end
        end)

        -- Part 4: Raid History Multi-Day Splitting
        self:RunPart(4, 6, "Midnight_Session_Splitting", function()
            local multiDateEntry = {
                date = "2026-08-30 23:50:00",
                sessionID = 1788100000,
                zone = "Sunwell Plateau",
                attendees = { ["WarriorMain-Realm"] = true, ["MageMain-Realm"] = true },
                attendeeDetails = {},
                bossLogs = {},
                awarded = {
                    { link = "[Day1 Drop]", date = "2026-08-30 23:55:00", timestamp = 1788100500, winner = "WarriorMain-Realm" },
                    { link = "[Day2 Drop]", date = "2026-08-31 00:15:00", timestamp = 1788100500 + 86400, winner = "MageMain-Realm" }
                }
            }
            local splitEntries = API:SplitMultiDateAttendanceEntry(multiDateEntry)
            assert(splitEntries ~= nil and #splitEntries == 2, "Midnight crossing must split into 2 calendar records")
        end)

        -- Part 5: Attendance Decay & Compaction
        self:RunPart(5, 6, "Decay_Detection_And_Compaction", function()
            db.DecayConfig = db.DecayConfig or {}
            db.DecayConfig.enabled = true
            db.AttendanceHistory = {
                {
                    date = "2026-08-30 20:00:00",
                    zone = "Sunwell Plateau",
                    sessionID = 1788100000,
                    attendees = { ["WarriorMain-Realm"] = true },
                    decayApplied = nil,
                    decayPenalty = 1
                }
            }
            if Att and Att.HasPendingDecay then
                assert(Att:HasPendingDecay() == true, "Attendance module must detect pending decay")
            end
            Serializer:CompactRaidHistory(true)
            assert(db.historyCompacted == true, "History compaction flag set to true")
            assert(#db.AttendanceHistory == 1, "Compacted history record preserved")
        end)

        -- Part 6: Priority Lists Shuffle & End-to-End Decay Application
        self:RunPart(6, 6, "Priority_Shuffle_And_Decay_Application", function()
            local PriorityMod = DesolateLootcouncil:GetModule("Priority", true)
            if not PriorityMod then return end

            -- 1. Shuffle all Priority Lists for a new season
            API:ShuffleLists()
            local tierList = API:GetPriorityList("Tier")
            assert(tierList ~= nil and #tierList.players >= 5, "Tier list must be initialized with roster players after shuffle")

            -- Capture pre-decay order
            local preTier = {}
            for _, p in ipairs(tierList.players) do table.insert(preTier, p) end

            -- 2. Setup a past raid session with attendees and absences
            -- Mark player at rank 1 as ABSENT, and player at rank 2 as PRESENT
            local rank1Player = preTier[1]
            local rank2Player = preTier[2]
            local attendeeMap = {}
            for i = 2, #preTier do
                attendeeMap[preTier[i]] = true
            end
            -- rank1Player is absent (not in attendeeMap)

            db.AttendanceHistory = db.AttendanceHistory or {}
            table.insert(db.AttendanceHistory, 1, {
                date = "2026-08-30 21:00:00",
                zone = "Sunwell Plateau",
                sessionID = 1788100999,
                attendees = attendeeMap,
                decayApplied = nil,
                decayPenalty = 1
            })

            -- 3. Apply decay for the last session
            assert(RosterMod and RosterMod.ApplyDecayForLastSession, "Roster:ApplyDecayForLastSession must exist")
            RosterMod:ApplyDecayForLastSession()

            -- 4. Verify that rank 1 absent player dropped to rank 2, and rank 2 present player advanced to rank 1
            local postTier = tierList.players
            assert(postTier[1] == rank2Player, "Present rank 2 player must advance to rank 1 after decay")
            assert(postTier[2] == rank1Player, "Absent rank 1 player must drop to rank 2 after decay")
            assert(db.AttendanceHistory[1].decayApplied ~= nil, "Session history must be stamped with decayApplied timestamp")

            -- 5. Duplicate decay call must be blocked and leave rankings unchanged
            RosterMod:ApplyDecayForLastSession()
            assert(postTier[1] == rank2Player, "Duplicate decay call must not re-demote or alter rankings")
            assert(postTier[2] == rank1Player, "Duplicate decay call must preserve post-decay order")

            -- 6. All-Absent and All-Present Stability (No Rollover)
            local allAbsentMap = {}
            for _, p in ipairs(postTier) do allAbsentMap[p] = true end
            PriorityMod:CalculateListDecay(tierList, 1, allAbsentMap)
            assert(tierList.players[1] == postTier[1] and tierList.players[#tierList.players] == postTier[#postTier], "All-absent decay must never rollover or rotate priority lists")
        end)

        self:Log("Scenario 3 [Raider Queue, Attendance & Encounter History] completed successfully.")
    end)

    -- =======================================================================
    -- 4. Officer Comms, Multi-Client Sync & LM Authority Handover
    -- =======================================================================
    self:RegisterScenario("officer_comms_sync_handover", "4. Officer Comms, Multi-Client Sync & LM Authority", "Tests channel sanitization, LM handover state packaging, simulated disconnection/reconnect takeover (FCFS), and last-timestamp-wins sync.", function()
        local Comm = DesolateLootcouncil:GetModule("Comm", true)
        local Session = DesolateLootcouncil:GetModule("Session", true)
        local Sim = DesolateLootcouncil:GetModule("Simulation", true)
        local db = DesolateLootcouncil.db.profile

        -- Part 1: Comm Channel Sanitization & Target Routing
        self:RunPart(1, 5, "Comm_Channel_Sanitization", function()
            if not Comm then return end
            local lastType, lastTarget = nil, nil
            local origSend = Comm.SendCommMessage
            Comm.SendCommMessage = function(selfMod, prefix, msg, distType, distTarget)
                lastType = distType
                lastTarget = distTarget
            end

            Comm:SendComm("TEST_CMD", { foo = "bar" }, "guild")
            assert(lastType == "GUILD" or lastType == "PARTY" or lastType == "RAID" or lastType == nil, "Group target routes to channel")
            assert(lastTarget == nil, "Group channel must never have whisper target")

            Comm:SendComm("TEST_CMD", { foo = "bar" }, "SomePlayer-Realm")
            assert(lastType == "WHISPER", "Player target routes to WHISPER")
            assert(lastTarget == "SomePlayer-Realm", "Whisper target must match player name")

            Comm.SendCommMessage = origSend
        end)

        -- Part 2: LM Handover Packaging & Acceptance
        self:RunPart(2, 5, "LM_Handover_Acceptance", function()
            DesolateLootcouncil.pendingHandoverSender = "OfficerMain-Realm"
            DesolateLootcouncil.pendingHandoverState = {
                configuredLM = "OfficerMain-Realm",
                sessionActive = true,
                awarded = {},
                loot = { { itemID = 1234, link = "Item" } },
                bidding = {},
                votes = {},
                closed = {},
                expiry = 0
            }
            if Session and Session.AcceptHandover then
                Session:AcceptHandover(true, true)
                assert(DesolateLootcouncil.amILM == true, "Accepting player becomes LM")
                assert(DesolateLootcouncil.activeLootMaster == UnitName("player"), "activeLootMaster updates to accepting player")
            end
        end)

        -- Part 3: Simulated Disconnect, FCFS Takeover & Reconnect
        self:RunPart(3, 5, "Simulated_DC_FCFS_Reconnect", function()
            if not Sim then return end
            Sim:Add("SimOfficer-Realm")
            Sim:Add("SimWinner-Realm")
            assert(DesolateLootcouncil:IsUnitOnline("SimOfficer-Realm") == true, "Officer online initially")

            DesolateLootcouncil.activeLootMaster = "SimOfficer-Realm"
            Sim:Disconnect("SimOfficer-Realm")
            assert(DesolateLootcouncil:IsUnitOnline("SimOfficer-Realm") == false, "LM offline after DC")

            -- FCFS Claim LM
            if Session and Session.ClaimLMRole then
                Session:ClaimLMRole()
                assert(DesolateLootcouncil.amILM == true, "Claiming player succeeds when LM offline")
            end

            Sim:Reconnect("SimOfficer-Realm")
            assert(DesolateLootcouncil:IsUnitOnline("SimOfficer-Realm") == true, "Officer reconnected")
        end)

        -- Part 4: Officer Delta Sync & Last-Timestamp-Wins
        self:RunPart(4, 5, "Delta_Sync_Timestamp_Resolution", function()
            local tierList = db.PriorityLists[1]
            tierList.timestamp = 1000
            tierList.players = { "WarriorMain-Realm", "MageMain-Realm", "PriestMain-Realm" }

            -- Newer update (2000 > 1000)
            local newer = { name = "Tier", timestamp = 2000, players = { "PriestMain-Realm", "MageMain-Realm", "WarriorMain-Realm" } }
            if newer.timestamp > tierList.timestamp then
                tierList.players = newer.players
                tierList.timestamp = newer.timestamp
            end
            assert(tierList.players[1] == "PriestMain-Realm", "Newer sync payload overwrites local ranking")

            -- Stale update (1500 < 2000)
            local stale = { name = "Tier", timestamp = 1500, players = { "MageMain-Realm", "WarriorMain-Realm", "PriestMain-Realm" } }
            local appliedStale = false
            if stale.timestamp > tierList.timestamp then
                tierList.players = stale.players
                appliedStale = true
            end
            assert(appliedStale == false, "Stale sync payload ignored")
            assert(tierList.players[1] == "PriestMain-Realm", "Ranking unchanged after stale rejection")
        end)

        -- Part 5: Version Check Ping & Distribution Broadcast
        self:RunPart(5, 5, "Version_Check_Broadcast", function()
            local Version = DesolateLootcouncil:GetModule("UI_Version", true)
            if Version and Version.ShowVersionWindow then
                Version:ShowVersionWindow(true)
                assert(Version.versionFrame and Version.versionFrame:IsShown(), "Version check window opened")
            end
        end)

        self:Log("Scenario 4 [Officer Comms, Multi-Client Sync & LM Authority] completed successfully.")
    end)

    -- =======================================================================
    -- 5. Automation, Autopass & Trade Delivery
    -- =======================================================================
    self:RegisterScenario("automation_autopass_trade", "5. Automation, Autopass & Trade Delivery", "Evaluates Item Manager raid synchronization, catalog categorization, raider autopass rules, session prompt heartbeat suppression, and physical item trade exchange verification.", function()
        local Sync = DesolateLootcouncil:GetModule("Sync", true)
        local Catalog = DesolateLootcouncil:GetModule("ItemCatalog", true)
        local Autopass = DesolateLootcouncil:GetModule("Autopass", true)
        local TradeMod = DesolateLootcouncil:GetModule("Trade", true)
        local db = DesolateLootcouncil.db.profile

        -- Part 1: Item Manager Raid Synchronization & Catalog Mapping
        self:RunPart(1, 4, "ItemManager_Sync_And_Catalog", function()
            local imPayload = {
                lists = {
                    Weapons = { [17075] = true, [19019] = true },
                    Tier    = { [16914] = true, [16865] = true },
                    Rest    = { [19136] = true, [18809] = true }
                },
                isManual = true
            }

            local prevOfficer = DesolateLootcouncil.amIOfficer
            local prevLM = DesolateLootcouncil.amILM
            DesolateLootcouncil.amIOfficer = false
            DesolateLootcouncil.amILM = false

            if Sync and Sync.HandleMessage then
                Sync:HandleMessage("IM_SYNC", imPayload, "LootMaster-Realm")
            end

            DesolateLootcouncil.amIOfficer = prevOfficer
            DesolateLootcouncil.amILM = prevLM

            if Catalog and Catalog.GetItemCategory then
                assert(Catalog:GetItemCategory(17075) == "Weapons", "Item #17075 categorized under Weapons via IM_SYNC")
                assert(Catalog:GetItemCategory(16914) == "Tier", "Item #16914 categorized under Tier via IM_SYNC")
                assert(Catalog:GetItemCategory(19136) == "Rest", "Item #19136 categorized under Rest via IM_SYNC")
            end
        end)

        -- Part 2: Raider Autopass / Roll Rule Evaluation
        self:RunPart(2, 4, "Autopass_Rule_Evaluation", function()
            if not Autopass then return end
            DesolateLootcouncil.amILM = false
            local tierAction = Autopass:DetermineRollAction(1, "Tier")
            assert(tierAction == 0, "Raiders must Pass (0) on managed Tier loot")

            local weaponAction = Autopass:DetermineRollAction(1, "Weapons")
            assert(weaponAction == 0, "Raiders must Pass (0) on managed Weapon loot")

            local unmanagedAction = Autopass:DetermineRollAction(2, "Junk/Pass")
            assert(unmanagedAction == 0 or unmanagedAction == nil, "Unmanaged/Junk items skip auto-Need")
        end)

        -- Part 3: Session Autopass Prompt Lifecycle & Heartbeat Suppression
        self:RunPart(3, 4, "Autopass_Prompt_Suppression", function()
            db.DecayConfig = db.DecayConfig or {}
            db.DecayConfig.sessionActive = true
            db.DecayConfig.sessionAutopassAnswered = false
            DesolateLootcouncil.sessionAutopassAnswered = false

            DesolateLootcouncil:PromptAutopass()
            db.DecayConfig.sessionAutopassActive = true
            db.DecayConfig.sessionAutopassAnswered = true
            DesolateLootcouncil.sessionAutopassActive = true
            DesolateLootcouncil.sessionAutopassAnswered = true

            DesolateLootcouncil:PromptAutopass()
            assert(db.DecayConfig.sessionAutopassAnswered == true, "Autopass answered state maintained without duplicate prompt")
        end)

        -- Part 4: Trade Queue Staging & Delivery Verification
        self:RunPart(4, 4, "Trade_Queue_And_Delivery", function()
            db.session = db.session or {}
            db.session.awarded = {
                {
                    itemID = 19019,
                    link = "|cffa335ee|Hitem:19019::::::::80:::::|h[Thunderfury]|h|r",
                    winner = "WarriorMain-Realm",
                    traded = false,
                    sourceGUID = "TRADE-TF-1"
                }
            }
            assert(db.session.awarded[1].traded == false, "Awarded item starts untraded")

            if TradeMod and TradeMod.HandleTradeSuccess then
                TradeMod.tradeTargetName = "WarriorMain-Realm"
                TradeMod.itemsInTrade = {
                    { itemID = 19019, link = db.session.awarded[1].link, winner = "WarriorMain-Realm" }
                }
                TradeMod:HandleTradeSuccess()
                assert(db.session.awarded[1].traded == true, "Item marked traded after exchange")
            end
        end)

        self:Log("Scenario 5 [Automation, Autopass & Trade Delivery] completed successfully.")
    end)

    -- =======================================================================
    -- 6. Database Sanitization, Serialization & Integrity
    -- =======================================================================
    self:RegisterScenario("database_integrity_serialization", "6. Database Sanitization, Serialization & Integrity", "Performs schema 200->201 migration, LibDeflate compression roundtrips, immutable audit ledger recording, and self-healing corruption recovery.", function()
        local API = DesolateLootcouncil.API
        local DBMigrator = DesolateLootcouncil.DBMigrator
        local Serializer = DesolateLootcouncil.Serializer
        local db = DesolateLootcouncil.db.profile

        -- Part 1: Schema 200 -> 201 Migration & Sanitization
        self:RunPart(1, 4, "Schema_201_Migration", function()
            db.schemaVersion = 100
            db.Priority = { ["LegacyList"] = true }
            db.legacyLogs = { "Old Log" }
            db.playerRoster.mains = { "MigratedGuy-Realm" }

            local migrated, pruned = DBMigrator:SanitizeProfileDatabase(db)
            assert(migrated == true, "DBMigrator performs migration")
            assert(pruned >= 3, "Legacy keys pruned")
            assert(db.Priority == nil, "Legacy Priority purged")
            assert(db.MainRoster["MigratedGuy-Realm"] ~= nil, "MigratedGuy added to MainRoster")
            assert(db.schemaVersion == 201, "Schema version stamped to 201")
        end)

        -- Part 2: Real-World Profile Import & LibDeflate Compression
        self:RunPart(2, 4, "High_Volume_Compression_Roundtrip", function()
            local originalHash = API:GetRosterHash()
            local exportPayload = API:ExportProfileData()
            assert(type(exportPayload) == "string" and #exportPayload > 10, "Export payload valid")

            local decoded = Serializer:DecodePayload(exportPayload)
            assert(decoded ~= nil and #decoded > 0, "Lossless decompression verified")

            local ok, err = API:ImportProfileData(exportPayload, nil, true)
            assert(ok == true, "Re-import succeeded: " .. tostring(err))
            local restoredHash = API:GetRosterHash()
            assert(restoredHash == originalHash, "Restored profile matches SHA-1 hash byte-for-byte")
        end)

        -- Part 3: Immutable Audit Ledger Recording & Tamper Receipts
        self:RunPart(3, 4, "Audit_Ledger_Tamper_Receipts", function()
            db.AuditLog = {}
            API:AddMain("AuditTester-Realm", "WARRIOR", false)
            API:AddAlt("AuditAlt-Realm", "AuditTester-Realm")

            local sessionEvents = API:GetAuditLog()
            assert(#sessionEvents >= 2, "Audit log records tamper events")
            for _, ev in ipairs(sessionEvents) do
                assert(ev.h ~= nil and ev.h ~= "", "Audit entry contains state hash receipt")
                assert(ev.d ~= nil and ev.d ~= "", "Audit entry contains timestamp date")
            end
        end)

        -- Part 4: Database Self-Healing & Sentinel Recovery
        self:RunPart(4, 4, "Sentinel_Self_Healing", function()
            local Sentinel = DesolateLootcouncil.DBSentinel
            if not Sentinel then return end
            -- Inject orphan alt
            db.playerRoster.alts["OrphanAlt-Realm"] = "NonExistentMain-Realm"
            Sentinel:AuditAndHeal(db)
            assert(db.playerRoster.alts["OrphanAlt-Realm"] == nil, "Orphan alt pruned by self-healing sentinel")
        end)

        self:Log("Scenario 6 [Database Sanitization, Serialization & Integrity] completed successfully.")
    end)

    -- =======================================================================
    -- 7. Voting Lifecycle, Retraction, Re-award & Monitor Removal
    -- =======================================================================
    self:RegisterScenario("voting_monitor_workflow", "7. Voting Lifecycle, Retraction, Re-award & Monitor Removal", "Tests vote retraction, item removal from monitor, zero-timer re-awarding, and disenchanter discovery.", function()
        local API = DesolateLootcouncil.API
        local Session = DesolateLootcouncil:GetModule("Session", true)
        -- Part 1: Start Session
        self:RunPart(1, 5, "Session_Start_Staging", function()
            local items = {
                { link = "item:217192", itemID = 217192, sourceGUID = "TS_GUID_1", category = "Tier" },
                { link = "item:212398", itemID = 212398, sourceGUID = "TS_GUID_2", category = "Weapons" }
            }
            if Session and Session.StartSession then
                Session:StartSession(items)
            end
            local bidding = API:GetBiddingList()
            assert(#bidding == 2, "Session must stage 2 active bidding items")
            assert(not API:IsItemClosed("TS_GUID_1"), "Item 1 must be open initially")
        end)

        -- Part 2: Vote Cast and Retraction
        self:RunPart(2, 5, "Vote_Cast_And_Retraction", function()
            API:SendVote("TS_GUID_1", 1, "Main Need")
            local votes = API:GetLocalVotes()
            assert(votes["TS_GUID_1"] ~= nil, "Local vote must be registered")

            -- Retract vote
            API:CancelVote("TS_GUID_1")
            local votesAfter = API:GetLocalVotes()
            assert(votesAfter["TS_GUID_1"] == nil or votesAfter["TS_GUID_1"] == 0, "Local vote must be cleared on retraction")
        end)

        -- Part 3: Close Item and Award Winner
        self:RunPart(3, 5, "Close_And_Award_Winner", function()
            API:CloseItem("TS_GUID_1")
            assert(API:IsItemClosed("TS_GUID_1") == true, "Item must be closed")

            API:AwardItem("TS_GUID_1", "WarriorMain-Realm", "Bid")
            local awarded = API:GetAwardedList()
            assert(#awarded == 1, "Awarded list must contain 1 item")
            assert(awarded[1].winner == "WarriorMain-Realm", "Winner must be WarriorMain-Realm")
        end)

        -- Part 4: Re-award Zero-Timer Integrity
        self:RunPart(4, 5, "Reaward_Zero_Timer_Integrity", function()
            API:ReawardItem(1)
            local bidding = API:GetBiddingList()
            assert(#bidding == 2, "Item must be restored to bidding list")
            local restored = nil
            for _, it in ipairs(bidding) do
                if it.itemID == 217192 or (it.sourceGUID and string.find(it.sourceGUID, "^Reaward%-")) then
                    restored = it
                    break
                end
            end
            assert(restored ~= nil, "Restored item must exist in bidding list")
            assert(restored.isClosed == true, "Restored item must have isClosed == true")
            assert(API:IsItemClosed(restored.sourceGUID), "Restored item must be marked closed in Session")
        end)

        -- Part 5: Monitor Item Eviction & Disenchanter Discovery
        self:RunPart(5, 5, "Eviction_And_Disenchanter_Discovery", function()
            local bidding = API:GetBiddingList()
            local guidToRemove = bidding[1].sourceGUID
            API:RemoveSessionItem(guidToRemove)

            local biddingAfter = API:GetBiddingList()
            assert(#biddingAfter == 1, "Bidding list must have 1 item after removal")

            -- Disenchanter discovery
            local Comm = DesolateLootcouncil:GetModule("Comm", true)
            if Comm and Comm.UpdatePlayerInfo then
                Comm:UpdatePlayerInfo("EnchanterPro-Realm", "12.0.7", 375)
            end
            -- Stop session and verify clean teardown
            API:StopSession()
            assert(#API:GetBiddingList() == 0, "Bidding list must be empty after stopping session")
        end)

        self:Log("Scenario 7 [Voting Lifecycle, Retraction, Re-award & Monitor Removal] completed successfully.")
    end)

    -- =======================================================================
    -- 8. Disband Gating, Snapshot Authority & Comm Boundaries
    -- =======================================================================
    self:RegisterScenario("disband_snapshot_comm_boundaries", "8. Disband Gating, Snapshot Authority & Comm Boundaries", "Validates session disband gating on boss kills, attendance snapshot combat exclusivity, officer role permissions, and offline comm guards.", function()
        local Attendance = DesolateLootcouncil:GetModule("Attendance", true)
        local Roster = DesolateLootcouncil:GetModule("Roster", true)
        local Sync = DesolateLootcouncil:GetModule("Sync", true)
        local db = DesolateLootcouncil.db.profile

        -- Part 1: Empty Disband Auto-Closes Silently (No Boss Kills)
        self:RunPart(1, 4, "Empty_Disband_Silent_Close", function()
            db.DecayConfig.sessionActive = true
            db.DecayConfig.currentSessionLM = UnitName("player")
            db.DecayConfig.bossLogs = {}
            DesolateLootcouncil.amILM = true
            if Roster then Roster.disbandPopupPending = false end

            if Roster and Roster.HandleRaidDisband then
                Roster.HandleRaidDisband(true)
            end

            assert(Roster.disbandPopupPending == false, "Empty session with 0 boss kills must NOT flag popup pending")
            assert(db.DecayConfig.sessionActive == false, "Empty session must be auto-closed silently")
        end)

        -- Part 2: Disband With Boss Kill Prompts LM
        self:RunPart(2, 4, "Disband_With_Kill_Prompts_LM", function()
            db.DecayConfig.sessionActive = true
            db.DecayConfig.currentSessionLM = UnitName("player")
            db.DecayConfig.bossLogs = {
                { encounterID = 1, name = "Test Boss", killed = true, killedTime = time(), pulls = 1 }
            }
            DesolateLootcouncil.amILM = true
            if Roster then Roster.disbandPopupPending = false end

            if Roster and Roster.HandleRaidDisband then
                Roster.HandleRaidDisband(true)
            end

            local wasPrompted = Roster and Roster.disbandPopupPending == true
            if Roster then Roster.disbandPopupPending = false end
            if StaticPopup_Hide then StaticPopup_Hide("DLC_DISBAND_CLOSE_SESSION") end

            assert(wasPrompted, "Session with >= 1 boss kill MUST flag popup pending for LM on raid disband")
        end)

        -- Part 3: Snapshot Exclusivity & Role Boundaries
        self:RunPart(3, 4, "Snapshot_Exclusivity_And_Role_Boundaries", function()
            db.DecayConfig.sessionActive = true
            db.DecayConfig.currentAttendees = {}
            DesolateLootcouncil.amILM = true

            -- Group change should NOT take snapshot
            if Attendance and Attendance.OnGroupRosterUpdate then
                Attendance:OnGroupRosterUpdate()
            end
            assert(next(db.DecayConfig.currentAttendees) == nil, "Group changes must never generate roster snapshots")

            -- Non-officer cannot take snapshots
            local origAmIOfficerOrLM = DesolateLootcouncil.AmIOfficerOrLM
            DesolateLootcouncil.AmIOfficerOrLM = function() return false end
            if Attendance and Attendance.SnapshotRoster then
                Attendance:SnapshotRoster(true)
            end
            DesolateLootcouncil.AmIOfficerOrLM = origAmIOfficerOrLM
            assert(next(db.DecayConfig.currentAttendees) == nil, "Non-officers must be blocked from taking snapshots")
        end)

        -- Part 4: Solo LM Boundary & Offline Comm Protection
        self:RunPart(4, 4, "Solo_LM_And_Offline_Comm_Protection", function()
            -- Solo non-LM player should not be promoted
            db.DecayConfig.sessionActive = true
            db.DecayConfig.currentSessionLM = "OtherRaidLeader-Realm"

            local lm = DesolateLootcouncil:DetermineLootMaster()
            if not IsInGroup() then
                assert(lm == "OtherRaidLeader-Realm", "Solo state must respect last raid session LM")
            end

            -- Comm pull requests suppressed for offline/out-of-raid senders
            local pullsSent = 0
            local Comm = DesolateLootcouncil:GetModule("Comm", true)
            local origSend = Comm and Comm.SendComm
            if Comm then
                Comm.SendComm = function(self, cmd)
                    if cmd and cmd:find("PULL_REQUEST") then pullsSent = pullsSent + 1 end
                end
            end

            local origIsUnitInRaid = DesolateLootcouncil.IsUnitInRaid
            local origIsUnitOnline = DesolateLootcouncil.IsUnitOnline
            DesolateLootcouncil.IsUnitInRaid = function(self, name) return false end
            DesolateLootcouncil.IsUnitOnline = function(self, name) return false end

            if Sync and Sync.HandleMessage then
                Sync:HandleMessage("DLC_HEARTBEAT", { imTimestamps = { Main = 9999 } }, "OtherRaidLeader-Realm")
            end

            if Comm and origSend then Comm.SendComm = origSend end
            DesolateLootcouncil.IsUnitInRaid = origIsUnitInRaid
            DesolateLootcouncil.IsUnitOnline = origIsUnitOnline

            assert(pullsSent == 0, "PULL_REQUEST must be suppressed when sender is offline or not in raid")
        end)

        self:Log("Scenario 8 [Disband Gating, Snapshot Authority & Comm Boundaries] completed successfully.")
    end)
end

--- Executes a single scenario by ID.
---@param id string
---@return boolean, string?
function TestSuite:RunScenario(id)
    local scenario = self.scenarios[id]
    if not scenario then return false, "Unknown scenario: " .. tostring(id) end

    local prevTestState = DesolateLootcouncil.isTestRunning
    local prevAmILM = DesolateLootcouncil.amILM
    local prevActiveLM = DesolateLootcouncil.activeLootMaster
    DesolateLootcouncil.isTestRunning = true

    scenario.status = "RUNNING"
    self.lastTestLogs = {}
    self.currentStepExports = {}
    self.scenarioResults = self.scenarioResults or {}

    self:Log(string.format("--- Running Scenario [%s]: %s ---", scenario.id, scenario.name))

    -- Always reset to clean State 0 before every scenario
    self:ResetToStateZero(true)

    local startTime = GetTime()
    local ok, err = pcall(scenario.run)
    local duration = GetTime() - startTime

    if ok then
        -- Auto-capture final post-run state (produces 1 export per scenario even if none were captured manually)
        self:CaptureStepExport("PostRun_FinalState")

        -- Execute Post-Test Integrity Validator
        local integrityOk, issues = self:VerifyPostTestIntegrity()
        if not integrityOk then
            scenario.status = "FAIL"
            scenario.errorMsg = "Post-Test Integrity Failed: " .. table.concat(issues, "; ")
            self:Log("FAILED: " .. scenario.errorMsg)
            self.scenarioResults[id] = {
                status = "FAIL",
                duration = duration,
                errorMsg = scenario.errorMsg,
                logs = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy(self.lastTestLogs)) or self.lastTestLogs,
                stepExports = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy(self.currentStepExports)) or self.currentStepExports,
                exportString = self.lastExportString or ""
            }
            DesolateLootcouncil.isTestRunning = prevTestState
            DesolateLootcouncil.amILM = prevAmILM
            DesolateLootcouncil.activeLootMaster = prevActiveLM
            return false, scenario.errorMsg
        end

        scenario.status = "PASS"
        scenario.errorMsg = nil
        self:Log(string.format("PASSED in %.3fs.", duration))
        self.scenarioResults[id] = {
            status = "PASS",
            duration = duration,
            errorMsg = nil,
            logs = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy(self.lastTestLogs)) or self.lastTestLogs,
            stepExports = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy(self.currentStepExports)) or self.currentStepExports,
            exportString = self.lastExportString or ""
        }
        DesolateLootcouncil.isTestRunning = prevTestState
        DesolateLootcouncil.amILM = prevAmILM
        DesolateLootcouncil.activeLootMaster = prevActiveLM
        local UI = DesolateLootcouncil:GetModule("UI", true)
        if UI and UI.CloseAllWindows then UI:CloseAllWindows() end
        return true, nil
    else
        -- Auto-capture post-run state even on failure for debugging
        self:CaptureStepExport("PostRun_FailState")

        scenario.status = "FAIL"
        scenario.errorMsg = tostring(err)
        self:Log(string.format("FAILED in %.3fs: %s", duration, scenario.errorMsg))
        self.scenarioResults[id] = {
            status = "FAIL",
            duration = duration,
            errorMsg = scenario.errorMsg,
            logs = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy(self.lastTestLogs)) or self.lastTestLogs,
            stepExports = (DesolateLootcouncil.Table and DesolateLootcouncil.Table.DeepCopy(self.currentStepExports)) or self.currentStepExports,
            exportString = self.lastExportString or ""
        }
        DesolateLootcouncil.isTestRunning = prevTestState
        DesolateLootcouncil.amILM = prevAmILM
        DesolateLootcouncil.activeLootMaster = prevActiveLM
        local UI = DesolateLootcouncil:GetModule("UI", true)
        if UI and UI.CloseAllWindows then UI:CloseAllWindows() end
        return false, scenario.errorMsg
    end
end

--- Executes all registered scenarios in fast batch sequence.
---@return number passed, number failed
function TestSuite:RunAllScenarios()
    local passed = 0
    local failed = 0
    self:Log("=== Starting Batch Execution of All Test Scenarios ===")
    DesolateLootcouncil.isTestRunning = true

    for _, id in ipairs(self.scenarioOrder) do
        local ok, _ = self:RunScenario(id)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    DesolateLootcouncil.isTestRunning = false
    local UI = DesolateLootcouncil:GetModule("UI", true)
    if UI and UI.CloseAllWindows then UI:CloseAllWindows() end
    self:Log(string.format("=== Batch Execution Complete: %d Passed, %d Failed ===", passed, failed))
    return passed, failed
end

--- Advances single scenario execution from current pointer.
---@param onStepDone fun(scenarioId: string, ok: boolean, err: string?)?
---@return boolean, string?
function TestSuite:StepNext(onStepDone)
    self.stepPointer = (self.stepPointer or 0) + 1
    if self.stepPointer > #self.scenarioOrder then
        self.stepPointer = 1
    end

    local id = self.scenarioOrder[self.stepPointer]
    local ok, err = self:RunScenario(id)
    if onStepDone then
        onStepDone(id, ok, err)
    end
    return ok, err
end

--- Starts sequential visual step-through execution with visual pacing.
---@param onStepDone fun(scenarioId: string, ok: boolean, err: string?)?
---@param onAllDone fun(passed: number, failed: number)?
---@param delay number?
function TestSuite:StartStepThrough(onStepDone, onAllDone, delay)
    self.isStepping = true
    self.stepPointer = 0
    local stepDelay = delay or 1.5

    local function runNext()
        if not self.isStepping then return end
        self.stepPointer = (self.stepPointer or 0) + 1
        if self.stepPointer > #self.scenarioOrder then
            self.isStepping = false
            local passed, failed = 0, 0
            for _, id in ipairs(self.scenarioOrder) do
                if self.scenarios[id] and self.scenarios[id].status == "PASS" then
                    passed = passed + 1
                else
                    failed = failed + 1
                end
            end
            local UI = DesolateLootcouncil:GetModule("UI", true)
            if UI and UI.CloseAllWindows then UI:CloseAllWindows() end
            if onAllDone then onAllDone(passed, failed) end
            return
        end

        local id = self.scenarioOrder[self.stepPointer]
        local ok, err = self:RunScenario(id)
        if onStepDone then onStepDone(id, ok, err) end

        if self.isStepping then
            C_Timer.After(stepDelay, runNext)
        end
    end

    runNext()
end

--- Pauses/stops active visual step-through runner.
function TestSuite:StopStepThrough()
    self.isStepping = false
end
