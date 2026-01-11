-- Tests/Unit/Priority_Test.lua
---@diagnostic disable: undefined-global, undefined-field

-- 1. Load Mocks
dofile("Tests/Unit/TestMock.lua")

-- 2. Load System Under Test
-- We need to manually load the file.
-- In a real environment, the TOC handles this.
-- We execute the file content in this environment.
LoadModule("Systems/Priority.lua")

-- Retrieve the module instance created by the file logic
local Priority = DesolateLootcouncil.modules["Priority"]
if not Priority then error("Priority Module not loaded") end

-- 3. Helpers
local function SetupDB()
    DesolateLootcouncil.db.profile = {
        PriorityLists = {
            { name = "TestList", players = { "A", "B", "C", "D", "E" } },
        },
        MainRoster = { ["A"] = {}, ["B"] = {}, ["C"] = {}, ["D"] = {}, ["E"] = {} },
        playerRoster = { alts = {} },
        PriorityLog = {}
    }
end

-- 4. Tests

print("--- Running Priority Unit Tests ---")

-- TEST: GetReversionIndex
-- Logic: If I was at pos 5, and someone moved from 2 to 10 (passed me), I should go up to 4?
-- Wait, the logic is: "If someone Above me (f < simulated) moves Down below me (t >= simulated) -> I go Up (-1)"
local function Test_GetReversionIndex()
    SetupDB()
    local logName = "GetReversionIndex"

    -- Scenario 1: No changes
    local idx = Priority:GetReversionIndex("TestList", 5, 0)
    Assertions.Equal(5, idx, logName .. "_NoChanges")

    -- Scenario 2: Person above invokes decay (moves to bottom)
    -- Initial: [A, B, C, D, E] (I am E at 5)
    -- B (2) moves to Bottom (5).
    -- New State: [A, C, D, E, B]. I am now at 4.
    -- Log: From 2 To 5.
    DesolateLootcouncil.db.profile.PriorityLog = {
        { list = "TestList", time = 100, from = 2, to = 5 }
    }
    idx = Priority:GetReversionIndex("TestList", 5, 50) -- Time 50 is before 100
    Assertions.Equal(4, idx, logName .. "_DecayAbove")

    -- Scenario 3: Person below me moves?
    -- Initial: [A, B, C, D, E] (I am B at 2)
    -- D (4) moves to Bottom (5).
    -- New: [A, B, C, E, D]. I stay at 2.
    -- Log: From 4 To 5.
    DesolateLootcouncil.db.profile.PriorityLog = {
        { list = "TestList", time = 100, from = 4, to = 5 }
    }
    idx = Priority:GetReversionIndex("TestList", 2, 50)
    Assertions.Equal(2, idx, logName .. "_DecayBelow")
end

-- TEST: MovePlayerToBottom
local function Test_MovePlayerToBottom()
    SetupDB()
    local logName = "MovePlayerToBottom"

    -- Initial: A, B, C, D, E
    -- Move B (2) to Bottom
    local oldIdx = Priority:MovePlayerToBottom("TestList", "B")

    Assertions.Equal(2, oldIdx, logName .. "_ReturnIndex")

    local list = DesolateLootcouncil.db.profile.PriorityLists[1].players
    Assertions.Equal("A", list[1], logName .. "_Pos1")
    Assertions.Equal("C", list[2], logName .. "_Pos2")
    Assertions.Equal("B", list[5], logName .. "_Pos5")
end

-- TEST: RestorePlayerPosition
local function Test_RestorePlayerPosition()
    SetupDB()
    local logName = "RestorePlayerPosition"
    local list = DesolateLootcouncil.db.profile.PriorityLists[1].players

    -- Initial: A, B, C, D, E
    -- Move B to Bottom: A, C, D, E, B
    Priority:MovePlayerToBottom("TestList", "B")

    -- Restore B to 2
    Priority:RestorePlayerPosition("TestList", "B", 2)

    Assertions.Equal("B", list[2], logName .. "_Restored")
    Assertions.Equal("C", list[3], logName .. "_Shifted")
end


-- Run
local status, err = pcall(function()
    Test_GetReversionIndex()
    Test_MovePlayerToBottom()
    Test_RestorePlayerPosition()
end)

if status then
    print("ALL TESTS PASSED")
else
    print("TEST FAILED: " .. err)
end
