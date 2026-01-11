-- Tests/Unit/Persistence_Test.lua
---@diagnostic disable: undefined-global, missing-fields, undefined-field

-- 1. Load Mocks
dofile("Tests/Unit/TestMock.lua")

-- 2. Load System Under Test
LoadModule("Utilities/Persistence.lua")
local Persistence = DesolateLootcouncil.Persistence

print("--- Running Persistence Unit Tests ---")

local function Test_SaveRestore()
    -- Helpers
    DesolateLootcouncil.db.profile.positions = {}

    -- Mock Frame
    -- CreateFrame is in TestMock (returns table with SetPoint stub)
    local frame = CreateFrame("Frame", "TestFrame")

    -- Add Spy Logic to Frame
    frame.pointsSet = false
    frame.SetPoint = function(self, point, relTo, relPoint, x, y)
        self.pointsSet = { point = point, relativePoint = relPoint, x = x, y = y }
    end
    frame.GetPoint = function()
        return "TOPLEFT", nil, "TOPLEFT", 100, 200
    end
    frame.GetWidth = function() return 300 end
    frame.GetHeight = function() return 400 end

    -- 1. Test Save
    Persistence:SaveFramePosition(frame, "TestWindow")

    local saved = DesolateLootcouncil.db.profile.positions["TestWindow"]
    Assertions.True(saved ~= nil, "Position Saved")
    Assertions.Equal(100, saved.x, "X Saved")
    Assertions.Equal(200, saved.y, "Y Saved")
    Assertions.Equal(300, saved.width, "Width Saved")

    -- 2. Test Restore
    -- Reset Frame Spy
    frame.pointsSet = nil

    Persistence:RestoreFramePosition(frame, "TestWindow")

    Assertions.True(frame.pointsSet ~= nil, "Points Applied")
    -- Note: TestMock CreateFrame stub returns CENTER/CENTER/0/0, but our overridden GetPoint returns TOPLEFT
    -- But RestoreFramePosition utilizes the DB values (which we just saved as 100/200)
    Assertions.Equal(100, frame.pointsSet.x, "X Restored")
end

-- Run
local status, err = pcall(function()
    Test_SaveRestore()
end)

if status then
    print("ALL PERSISTENCE TESTS PASSED")
else
    print("PERSISTENCE TEST FAILED: " .. err)
end
