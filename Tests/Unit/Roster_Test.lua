-- Tests/Unit/Roster_Test.lua
---@diagnostic disable: undefined-global, missing-fields

-- 1. Load Mocks
dofile("Tests/Unit/TestMock.lua")

-- 2. Load System Under Test


LoadModule("Systems/Roster.lua")
local Roster = DesolateLootcouncil.modules["Roster"] --[[@as Roster]]
-- Simulate OnEnable
DesolateLootcouncil.db.profile.DecayConfig = { sessionActive = false }
Roster:OnEnable()

print("--- Running Roster Unit Tests ---")

local function Test_StartStopSession()
    DesolateLootcouncil.db.profile.DecayConfig = { sessionActive = false }

    Roster:StartRaidSession()
    Assertions.True(DesolateLootcouncil.db.profile.DecayConfig.sessionActive, "Session Active")
    Assertions.True(DesolateLootcouncil.db.profile.DecayConfig.currentSessionID ~= nil, "Session ID Created")

    Roster:StopRaidSession(false)
    Assertions.True(not DesolateLootcouncil.db.profile.DecayConfig.sessionActive, "Session Stopped")
end

local function Test_Attendance()
    DesolateLootcouncil.db.profile.DecayConfig = { sessionActive = false }
    Roster:StartRaidSession()

    -- Mock Main Roster
    DesolateLootcouncil.db.profile.MainRoster = { ["MainA"] = {}, ["MainB"] = {} }

    -- 1. Register Valid
    Roster:RegisterAttendance("MainA")
    Assertions.True(DesolateLootcouncil.db.profile.DecayConfig.currentAttendees["MainA"], "MainA Registered")

    -- 2. Register Invalid
    Roster:RegisterAttendance("RandomPug")
    local attendees = DesolateLootcouncil.db.profile.DecayConfig.currentAttendees
    Assertions.True(attendees["RandomPug"] == nil, "RandomPug Rejected")

    Roster:StopRaidSession(false)
end

-- Run
local status, err = pcall(function()
    Test_StartStopSession()
    Test_Attendance()
end)

if status then
    print("ALL ROSTER TESTS PASSED")
else
    print("ROSTER TEST FAILED: " .. err)
end
