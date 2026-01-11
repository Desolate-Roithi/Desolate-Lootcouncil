-- Tests/Unit/SettingsStructure_Test.lua
---@diagnostic disable: undefined-global
dofile("Tests/Unit/TestMock.lua")

-- Mock Modules
DesolateLootcouncil:NewModule("GeneralSettings")
DesolateLootcouncil:NewModule("RosterSettings")
DesolateLootcouncil:NewModule("PrioritySettings")
DesolateLootcouncil:NewModule("ItemSettings")
DesolateLootcouncil:NewModule("LootSettings") -- To verify it's NOT loaded
DesolateLootcouncil:NewModule("UI_Attendance")

-- Mock GetOptions methods
local function MockGetOptions(self) return { type = "group", order = self.mockOrder, name = self.mockName } end

DesolateLootcouncil:GetModule("GeneralSettings").GetGeneralOptions = function() return { order = 1, name = "General" } end
DesolateLootcouncil:GetModule("RosterSettings").GetOptions = function() return { order = 2, name = "Roster" } end
DesolateLootcouncil:GetModule("PrioritySettings").GetOptions = function() return { order = 3, name = "Priority Lists" } end
DesolateLootcouncil:GetModule("UI_Attendance").GetAttendanceOptions = function()
    return {
        order = 4,
        name =
        "Attendance & Decay"
    }
end
DesolateLootcouncil:GetModule("ItemSettings").GetItemOptions = function() return { order = 5, name = "Item Lists" } end
DesolateLootcouncil:GetModule("LootSettings").GetOptions = function() return { order = 99, name = "Loot Rules" } end -- Should not be called

-- Load Loader
LoadModule("Settings/Loader.lua")

-- Test
local options = DesolateLootcouncil.SettingsLoader.GetOptions()
local args = options.args

-- 1. Verify Existence and Absence
Assertions.True(args.general ~= nil, "General Settings should exist")
Assertions.True(args.roster ~= nil, "Roster Settings should exist")
Assertions.True(args.priority ~= nil, "Priority Settings should exist")
Assertions.True(args.attendance ~= nil, "Attendance Settings should exist")
Assertions.True(args.items ~= nil, "Item Settings should exist")

Assertions.True(args.lootRules == nil, "Loot Rules should NOT exist")

-- 2. Verify Order matches User Request
-- Note: Loader collects them, but AceConfig respects the 'order' field inside the table.
-- We mock the return values to simulate what the files actually return.
-- We are verifying that Loader calls the correct functions and puts them in the args table.
-- The ORDER logic is inside the modules (which we just edited), so checking the Loader's result
-- verifies that the Loader is composing the final table correctly.

Assertions.Equal(1, args.general.order, "General Order")
Assertions.Equal(2, args.roster.order, "Roster Order")
Assertions.Equal(3, args.priority.order, "Priority Order")
Assertions.Equal(4, args.attendance.order, "Attendance Order")
Assertions.Equal(5, args.items.order, "Items Order")

-- 3. Verify names
Assertions.Equal("General", args.general.name, "General Name")
Assertions.Equal("Item Lists", args.items.name, "Items Name") -- Renamed from Items

print("Settings Structure Test Passed!")
