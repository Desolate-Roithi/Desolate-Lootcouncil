-- Tests/Unit/ModuleConflict_Test.lua
---@diagnostic disable: undefined-global
dofile("Tests/Unit/TestMock.lua")

-- Mock global DesolateLootcouncil to be ready for module creation
-- TestMock already creates DesolateLootcouncil

print("Loading Settings/Roster.lua...")
LoadModule("Settings/Roster.lua")

print("Loading Systems/Roster.lua...")
LoadModule("Systems/Roster.lua")

-- Verify existence of both modules
local RosterSettings = DesolateLootcouncil:GetModule("RosterSettings")
local RosterSystem = DesolateLootcouncil:GetModule("Roster")

Assertions.True(RosterSettings ~= nil, "RosterSettings module should exist")
Assertions.True(RosterSystem ~= nil, "Roster (System) module should exist")

Assertions.Equal("RosterSettings", RosterSettings.name, "RosterSettings name check")
Assertions.Equal("Roster", RosterSystem.name, "Roster System name check")

print("Module Conflict Test Passed!")
