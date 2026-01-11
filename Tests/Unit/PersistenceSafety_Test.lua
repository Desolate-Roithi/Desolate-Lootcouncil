-- Tests/Unit/PersistenceSafety_Test.lua
dofile("Tests/Unit/TestMock.lua")

-- Mock DB Persistence
DesolateLootcouncil.db.profile.positions = {}
LoadModule("Utilities/Persistence.lua")
DesolateLootcouncil.Persistence.DefaultLayouts["TestWindow"] = { point = "CENTER", x = 10, y = 10, width = 100, height = 100 }

-- Test 1: Raw Frame Save/Restore
local rawFrame = CreateFrame("Frame")
function rawFrame:GetPoint() return "TOPLEFT", nil, "TOPLEFT", 50, 50 end

function rawFrame:GetWidth() return 200 end

function rawFrame:GetHeight() return 200 end

DesolateLootcouncil.Persistence:SaveFramePosition(rawFrame, "TestWindow")
local saved = DesolateLootcouncil.db.profile.positions["TestWindow"]
Assertions.Equal(50, saved.x, "Raw Frame X Saved")
Assertions.Equal(200, saved.width, "Raw Frame Width Saved")

DesolateLootcouncil.Persistence:RestoreFramePosition(rawFrame, "TestWindow")
-- (Mock SetPoint doesn't update internal state in this simple mock, but we verify no crash)

-- Test 2: AceGUI Widget Save/Restore (The Bug Fix)
local aceWidget = {
    frame = rawFrame, -- Contains raw frame
    SetWidth = function(self, w) self.width = w end,
    SetHeight = function(self, h) self.height = h end
}
-- Call Save passing the WIDGET (simulating the bug condition)
-- Should verify it unwraps and saves the rawFrame's properties (200x200), not crashing
local status, err = pcall(function()
    DesolateLootcouncil.Persistence:SaveFramePosition(aceWidget, "TestWindow_Ace")
end)
Assertions.True(status, "SaveFramePosition should not crash with AceGUI widget")

local savedAce = DesolateLootcouncil.db.profile.positions["TestWindow_Ace"]
Assertions.Equal(200, savedAce.width, "AceGUI properties saved via unwrapped frame")

-- Test 3: Restore AceGUI
DesolateLootcouncil.Persistence:RestoreFramePosition(aceWidget, "TestWindow")
-- Should use widget:SetWidth
Assertions.Equal(200, aceWidget.width, "AceGUI SetWidth called on Restore")

print("Persistence Safety Test Passed!")
