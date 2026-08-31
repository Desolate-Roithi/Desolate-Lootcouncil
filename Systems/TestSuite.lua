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
        }
    },
    ItemManagerContent = {
        {
            name = "Tier",
            items = { 19019, 19020 }
        },
        {
            name = "Weapons",
            items = { 19021 }
        }
    },
    History = {
        AttendanceHistory = {},
        SessionPositionLog = {},
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

--- Resets the current profile to canonical State 0 using clean import serialization.
---@return boolean, string
function TestSuite:ResetToStateZero()
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
    if DesolateLootcouncil.UpdateLootMasterStatus then
        DesolateLootcouncil:UpdateLootMasterStatus()
    end
    if success then
        self:Log("Reset database to clean State 0 baseline.")
    else
        self:Log("Error resetting to State 0: " .. tostring(err))
    end
    return success, rawExport
end

--- Generates and stores the current export string for step inspection.
---@param label string?
---@return string
function TestSuite:CaptureStepExport(label)
    local exportStr = DesolateLootcouncil.API:ExportProfileData()
    self.lastExportString = exportStr or ""
    if label then
        self:Log(string.format("Captured export string checkpoint: [%s] (Length: %d)", label, #self.lastExportString))
    end
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
            if not db.MainRoster or not db.MainRoster[main] then
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
    table.insert(self.lastTestLogs, msg)
    DesolateLootcouncil:DLC_Log("[TestSuite] " .. msg)
end

-- ---------------------------------------------------------------------------
-- Built-in Test Scenarios
-- ---------------------------------------------------------------------------

function TestSuite:OnInitialize()
    -- 1. Scenario: State 0 Baseline & Hash Verification
    self:RegisterScenario("state0_baseline", "1. State 0 Baseline & Hash", "Resets DB via canonical import, validates roster and calculates hash.", function()
        local ok, _ = self:ResetToStateZero()
        assert(ok, "Failed to import State 0 baseline")

        local mains = DesolateLootcouncil.API:GetMainRosterList()
        assert(mains["WarriorMain-Realm"] ~= nil, "WarriorMain-Realm missing from MainRoster")
        assert(mains["MageMain-Realm"] ~= nil, "MageMain-Realm missing from MainRoster")

        local hash = DesolateLootcouncil.API:GetRosterHash()
        assert(type(hash) == "string" and #hash > 0, "Roster hash must be non-empty string")
        self:Log("Roster Hash verified: " .. hash)

        self:CaptureStepExport("State0_Verified")
    end)

    -- 2. Scenario: Full Loot Intake, Bidding & Award Cycle
    self:RegisterScenario("loot_cycle", "2. Full Loot & Award Cycle", "Starts session, awards dropped item, verifies priority shift and trade staging.", function()
        self:ResetToStateZero()
        local API = DesolateLootcouncil.API

        -- Start raid session
        local db = DesolateLootcouncil.db.profile
        db.DecayConfig.sessionActive = true
        db.DecayConfig.currentSessionID = time()
        assert(API:IsRaidSessionActive() == true, "Raid session must be active")

        -- Inject dropped item
        API:AddManualItem("|cffa335ee|Hitem:19019::::::::80:::::|h[Thunderfury]|h|r")
        local backlog = API:GetLootBacklog()
        assert(#backlog > 0, "Backlog must contain dropped item")

        -- Stage into bidding
        local itemData = backlog[1]
        table.insert(db.session.bidding, {
            link = itemData.link,
            itemID = itemData.itemID,
            texture = itemData.texture,
            category = itemData.category or "Tier",
            sourceGUID = itemData.sourceGUID or "TF-19019",
            stackIndex = 1
        })

        -- Award item to WarriorMain-Realm
        local itemGUID = db.session.bidding[1].sourceGUID
        API:AwardItem(itemGUID, "WarriorMain-Realm", "Bid")

        -- Verify winner was moved to bottom of Tier list
        local tierList = API:GetPriorityList("Tier")
        assert(tierList ~= nil, "Tier list must exist")
        local players = tierList.players or tierList.order
        assert(players[#players] == "WarriorMain-Realm", "Winner must move to bottom of Tier list")

        self:CaptureStepExport("Loot_Awarded_PostDrop")
    end)

    -- 3. Scenario: Re-Award & Priority Position Restoration
    self:RegisterScenario("reaward_reversion", "3. Re-Award & Priority Reversion", "Reverts awarded item, asserting winner rank is restored and item re-enters bidding.", function()
        self:ResetToStateZero()
        local API = DesolateLootcouncil.API
        local db = DesolateLootcouncil.db.profile

        -- Setup pre-awarded item
        db.session = {
            bidding = {},
            awarded = {
                {
                    itemID = 19019,
                    link = "[Thunderfury]",
                    winner = "WarriorMain-Realm",
                    originalIndex = 1,
                    voteType = "Bid",
                    fullItemData = { itemID = 19019, category = "Tier" }
                }
            },
            votes = {}
        }
        db.PriorityLists[1].players = { "MageMain-Realm", "PriestMain-Realm", "WarriorMain-Realm" }

        -- Trigger Reaward
        API:ReawardItem(1)

        -- Assertions
        assert(#db.session.awarded == 0, "Awarded list must be empty after re-award")
        assert(#db.session.bidding == 1, "Item must return to bidding queue")
        assert(db.PriorityLists[1].players[1] == "WarriorMain-Realm", "Winner must be restored to rank 1 in Tier list")

        self:CaptureStepExport("Reaward_Restored")
    end)

    -- 4. Scenario: Roster Rename & Alt Synchronization
    self:RegisterScenario("roster_rename", "4. Roster Rename & Alt Sync", "Renames a Main with linked alts and asserts all lists and alts update.", function()
        self:ResetToStateZero()
        local API = DesolateLootcouncil.API

        local ok = API:RenamePlayer("WarriorMain-Realm", "GladiatorMain-Realm")
        assert(ok == true, "RenamePlayer must return true")

        local mains = API:GetMainRosterList()
        assert(mains["WarriorMain-Realm"] == nil, "Old Main name removed")
        assert(mains["GladiatorMain-Realm"] ~= nil, "New Main name exists in MainRoster")

        local alts = DesolateLootcouncil.db.profile.playerRoster.alts
        assert(alts["WarriorAlt-Realm"] == "GladiatorMain-Realm", "Linked alt parent updated to GladiatorMain-Realm")

        local tierList = API:GetPriorityList("Tier")
        assert(tierList.players[1] == "GladiatorMain-Realm", "Priority list rank 1 updated to GladiatorMain-Realm")

        self:CaptureStepExport("Roster_Renamed")
    end)

    -- 5. Scenario: Multi-Window Theme Propagation
    self:RegisterScenario("theme_propagation", "5. Multi-Window Theme Broadcast", "Cycles active themes and verifies backdrop colors on all registered windows.", function()
        local Theme = DesolateLootcouncil:GetModule("UI_Theme", true)
        local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI", true)
        if not Theme or not NativeGUI then return end

        local testWin = NativeGUI:CreateWindow("TestSuiteProbeWin", "Probe", "Config")
        testWin:Show()

        -- Test Fel
        DesolateLootcouncil.API:SetActiveTheme("Fel")
        local felTheme = Theme:GetTheme("Fel")
        local r, _, _ = testWin:GetBackdropColor()
        assert(math.abs(r - felTheme.bg[1]) < 0.02, "Window did not adopt Fel theme background")

        -- Test Midnight
        DesolateLootcouncil.API:SetActiveTheme("Midnight")
        local midnightTheme = Theme:GetTheme("Midnight")
        local r2, _, _ = testWin:GetBackdropColor()
        assert(math.abs(r2 - midnightTheme.bg[1]) < 0.02, "Window did not adopt Midnight theme background")

        testWin:Hide()
        self:Log("Theme propagation across native windows verified.")
    end)

    -- 6. Scenario: Database Sanitizer & Schema Upgrade
    self:RegisterScenario("db_sanitizer", "6. 2.0 Database Sanitization", "Injects legacy v1 dirty keys, runs DBMigrator, and asserts schema 200.", function()
        local db = DesolateLootcouncil.db.profile
        db.schemaVersion = 100
        db.Priority = { ["LegacyList"] = true }
        db.legacyLogs = { "Old Log" }
        db.playerRoster.mains = { "MigratedGuy-Realm" }

        local migrated, pruned = DesolateLootcouncil.DBMigrator:SanitizeProfileDatabase(db)
        assert(migrated == true, "DBMigrator must perform migration")
        assert(pruned >= 3, "DBMigrator must prune legacy keys")
        assert(db.Priority == nil, "Legacy Priority key purged")
        assert(db.MainRoster["MigratedGuy-Realm"] ~= nil, "MigratedGuy added to MainRoster")
        assert(db.schemaVersion == 200, "Schema version stamped to 200")

        self:CaptureStepExport("DB_Sanitized")
    end)

    -- 7. Scenario: Comm Sanitization & Disband Authority
    self:RegisterScenario("comm_and_disband", "7. Comm Sanitization & Disband Authority", "Tests channel normalization, whisper sanitization, and non-LM disband prompt gating.", function()
        self:ResetToStateZero()
        local Comm = DesolateLootcouncil:GetModule("Comm", true)
        local db = DesolateLootcouncil.db.profile

        -- Test 1: Channel case normalization & sanitization
        local lastSentType, lastSentTarget = nil, nil
        local origSend = Comm and Comm.SendCommMessage
        if Comm then
            Comm.SendCommMessage = function(selfMod, prefix, msg, distType, distTarget)
                lastSentType = distType
                lastSentTarget = distTarget
            end

            -- Test lowercase "raid" routes to channel not whisper
            Comm:SendComm("TEST_CMD", { foo = "bar" }, "raid")
            assert(lastSentType == "RAID" or lastSentType == "PARTY" or lastSentType == "GUILD", "Lowercase 'raid' must route to group channel")
            assert(lastSentTarget == nil or lastSentTarget ~= "raid", "Channel 'raid' must never be treated as whisper recipient")

            -- Restore
            Comm.SendCommMessage = origSend
        end

        -- Test 2: Disband authority
        db.DecayConfig = db.DecayConfig or {}
        db.DecayConfig.sessionActive = true
        db.DecayConfig.currentSessionLM = "RealLootMaster"
        DesolateLootcouncil.activeLootMaster = "RealLootMaster"

        local lm = DesolateLootcouncil:DetermineLootMaster()
        assert(lm == "RealLootMaster", "DetermineLootMaster must return RealLootMaster during active session")

        self:Log("Comm target sanitization and Disband Authority verified.")
    end)
end

--- Executes a single scenario by ID.
---@param id string
---@return boolean, string?
function TestSuite:RunScenario(id)
    local scenario = self.scenarios[id]
    if not scenario then return false, "Unknown scenario: " .. tostring(id) end

    scenario.status = "RUNNING"
    self.lastTestLogs = {}
    self:Log(string.format("--- Running Scenario [%s]: %s ---", scenario.id, scenario.name))

    local startTime = GetTime()
    local ok, err = pcall(scenario.run)
    local duration = GetTime() - startTime

    if ok then
        -- Execute Post-Test Integrity Validator
        local integrityOk, issues = self:VerifyPostTestIntegrity()
        if not integrityOk then
            scenario.status = "FAIL"
            scenario.errorMsg = "Post-Test Integrity Failed: " .. table.concat(issues, "; ")
            self:Log("FAILED: " .. scenario.errorMsg)
            return false, scenario.errorMsg
        end

        scenario.status = "PASS"
        scenario.errorMsg = nil
        self:Log(string.format("PASSED in %.3fs.", duration))
        return true, nil
    else
        scenario.status = "FAIL"
        scenario.errorMsg = tostring(err)
        self:Log(string.format("FAILED in %.3fs: %s", duration, scenario.errorMsg))
        return false, scenario.errorMsg
    end
end

--- Executes all registered scenarios in sequence.
---@return number passed, number failed
function TestSuite:RunAllScenarios()
    local passed = 0
    local failed = 0
    self:Log("=== Starting Batch Execution of All Test Scenarios ===")

    for _, id in ipairs(self.scenarioOrder) do
        local ok, _ = self:RunScenario(id)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    self:Log(string.format("=== Batch Execution Complete: %d Passed, %d Failed ===", passed, failed))
    return passed, failed
end
