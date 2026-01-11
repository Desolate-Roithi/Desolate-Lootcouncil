-- Tests/Unit/Logging_Test.lua
---@diagnostic disable: undefined-global, duplicate-set-field
dofile("Tests/Unit/TestMock.lua")
LoadModule("Utilities/Logger.lua")
LoadModule("Core/Addon.lua")

if DesolateLootcouncil.Print then
end

-- Mock the AceConsole Print injected method
local printCalled = 0
function DesolateLootcouncil:Print(msg)
    printCalled = printCalled + 1
    -- print("AceConsole:Print called with:", msg)
end

print("Running Logging Test...")

DesolateLootcouncil:DLC_Log("Test Message", true)

Assertions.Equal(1, printCalled, "Print should be called exactly once")

print("Logging Test Passed!")
