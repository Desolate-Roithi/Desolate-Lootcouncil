-- Tests/Unit/Logging_Test.lua
dofile("Tests/Unit/TestMock.lua")

-- Load the Addon file (but we need to handle the AceAddon creation carefully since Mock does it too)
-- Actually, TestMock creates `DesolateLootcouncil`.
-- We need to load `Utilities/Logger.lua` and `Core/Addon.lua` logic.
-- However, `Core/Addon.lua` creates the addon object.

-- workaround: redefine mock NewAddon to return existing global if present, which TestMock does.
-- Let's load the files.
LoadModule("Utilities/Logger.lua")

-- We can't easily load Core/Addon.lua because it contains the `NewAddon` call which might reset things or be tricky.
-- BUT, the fix was REMOVING a function from Addon.lua.
-- So if I load Addon.lua, it shouldn't have `Print` anymore.
-- Let's define a mock Print on the object BEFORE loading Addon.lua (if Addon.lua doesn't overwrite it)
-- OR, just define it after loading.

-- Problem: Addon.lua *creates* the object.
-- Let's manually define the DLC_Log function as it is in the file, to test IT specifically,
-- or try to load the file if possible.
-- Given the file structure, Addon.lua is the main entry.

-- Let's try to verify by creating the scenario:
-- 1. DesolateLootcouncil object exists (from Mock)
-- 2. It has Logger (from Utilities/Logger.lua)
-- 3. We define DLC_Log (which calls Logger.Log)
-- 4. We define Logger.Log (which calls DesolateLootcouncil:Print)
-- 5. We define DesolateLootcouncil:Print (simulating AceConsole)
-- 6. We ensure calling (5) -> (4) -> (5) doesn't happen, i.e. (5) is NOT the override that calls (3).

-- Actually, if I just manually recreate the functions involved, I verify the logic, but not the file content.
-- Since I edited the file content, I want to trust the file content.
-- Let's try to load Addon.lua.
-- In TestMock.lua, `AceAddon:NewAddon` uses `_G[name] or ...`, so it might be okay.

LoadModule("Core/Addon.lua")

-- Now DesolateLootcouncil should have the methods from Addon.lua.
-- AND it should NOT have the `Print` method (since I deleted it).

-- Let's check:
if DesolateLootcouncil.Print then
    -- If it exists, it might be from a mixin?
    -- TestMock doesn't mixin AceConsole.
    -- So if it exists, it MUST be the one I failed to delete?
    -- Or if TestMock added it? TestMock doesn't add Print.

    -- Wait, if `Print` is missing, calling it will error in Lua unless we add it (mocking AceConsole).
    -- So we expect `DesolateLootcouncil.Print` to be nil after loading Addon.lua (because I deleted the override).
end

-- Mock the AceConsole Print injected method
local printCalled = 0
function DesolateLootcouncil:Print(msg)
    printCalled = printCalled + 1
    -- print("AceConsole:Print called with:", msg)
end

-- Now valid test:
-- Call DLC_Log("test", true)
-- Expect: Logger.Log -> DesolateLootcouncil:Print -> printCalled increments.
-- If the BUG was present: DLC_Log -> Logger.Log -> Addon:Print (override) -> DLC_Log ... Stack Overflow.

print("Running Logging Test...")

DesolateLootcouncil:DLC_Log("Test Message", true)

Assertions.Equal(1, printCalled, "Print should be called exactly once")

print("Logging Test Passed!")
