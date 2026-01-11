-- Tests/Unit/RefinedSettings_Test.lua
dofile("Tests/Unit/TestMock.lua")

-- Mock DB
DesolateLootcouncil.db = {
    profile = {
        debugMode = false,
        minLootQuality = 2
    }
}

-- Load General Settings
LoadModule("Settings/General.lua")
local General = DesolateLootcouncil:GetModule("GeneralSettings", true)
local options = General:GetGeneralOptions()

-- 1. Verify General Options Structure
local args = options.args
Assertions.True(args.debugMode ~= nil, "Debug Mode should exist")
Assertions.True(args.configuredLM ~= nil, "Loot Master input should exist")
Assertions.True(args.minLootQuality ~= nil, "Min Loot Quality should exist")
Assertions.True(args.enableAutoLoot ~= nil, "Auto Loot toggle should exist")
Assertions.True(args.resetLayout ~= nil, "Reset Layout button should exist")

-- 2. Verify Order
Assertions.Equal(1, args.configuredLM.order, "Loot Master Order")
Assertions.Equal(2, args.minLootQuality.order, "Min Quality Order")
Assertions.Equal(3, args.enableAutoLoot.order, "Auto Loot Order")
Assertions.Equal(4, args.debugMode.order, "Debug Mode Order")
Assertions.Equal(5, args.resetLayout.order, "Reset Layout Order")

-- 3. Verify minLootQuality options
local qualityValues = args.minLootQuality.values
Assertions.Equal("Poor (Grey)", qualityValues[0], "Check Poor Quality")
Assertions.Equal("Common (White)", qualityValues[1], "Check Common Quality")
Assertions.Equal("Legendary (Orange)", qualityValues[5], "Check Legendary Quality")

print("Refined Settings (General Layout) Test Passed!")
Assertions.True(qualityValues[2] ~= nil, "Uncommon (2) quality should exist")
Assertions.True(qualityValues[5] ~= nil, "Legendary (5) quality should exist")

-- Load Debug Module
LoadModule("Utilities/Debug.lua")
local Debug = DesolateLootcouncil:GetModule("Debug", true)

-- Verify ToggleVerbose is gone
Assertions.True(Debug.ToggleVerbose == nil, "ToggleVerbose should be removed from Debug module")

print("Refined Settings Test Passed!")
