-- Tests/Unit/RosterSettingsUI_Test.lua
dofile("Tests/Unit/TestMock.lua")

-- Mock Roster System
local MockRoster = {
    AddMainCalled = nil,
    AddAltCalled = nil,
    RemovePlayerCalled = nil,

    AddMain = function(self, name) self.AddMainCalled = name end,
    AddAlt = function(self, name, main) self.AddAltCalled = { name = name, main = main } end,
    RemovePlayer = function(self, name) self.RemovePlayerCalled = name end,
    OnEnable = function() end
}

-- Override GetModule to return our MockRoster
local OriginalGetModule = DesolateLootcouncil.GetModule
function DesolateLootcouncil:GetModule(name)
    if name == "Roster" then return MockRoster end
    return OriginalGetModule(self, name)
end

-- Load Roster Settings
LoadModule("Settings/Roster.lua")
local RosterSettings = DesolateLootcouncil:GetModule("RosterSettings", true)
if RosterSettings.OnInitialize then RosterSettings:OnInitialize() end

local options = RosterSettings:GetOptions()
local args = options.args

-- 1. Verify Structure
Assertions.True(args.manageGroup ~= nil, "Manage Group should exist")
Assertions.True(args.removeGroup ~= nil, "Remove Group should exist")
Assertions.True(args.displayGroup ~= nil, "Display Group should exist")

local manageArgs = args.manageGroup.args
Assertions.True(manageArgs.addPlayer ~= nil, "Add Player input should exist")
Assertions.True(manageArgs.isAlt ~= nil, "Is Alt toggle should exist")
Assertions.True(manageArgs.targetMain ~= nil, "Target Main select should exist")
Assertions.True(manageArgs.saveBtn ~= nil, "Save Button should exist")

-- 2. Verify Add Main Logic
manageArgs.addPlayer.set(nil, "NewMain")
manageArgs.isAlt.set(nil, false)
manageArgs.saveBtn.func()
Assertions.Equal("NewMain", MockRoster.AddMainCalled, "Should call AddMain with correct name")

-- 3. Verify Add Alt Logic
manageArgs.addPlayer.set(nil, "NewAlt")
manageArgs.isAlt.set(nil, true)
-- Mock getting main roster list for validation if needed, but select just sets tempMain
manageArgs.targetMain.set(nil, "NewMain")
manageArgs.saveBtn.func()
Assertions.Equal("NewAlt", MockRoster.AddAltCalled.name, "Should call AddAlt with correct alt name")
Assertions.Equal("NewMain", MockRoster.AddAltCalled.main, "Should call AddAlt with correct main name")

-- 4. Verify Remove Logic
local removeArgs = args.removeGroup.args
removeArgs.removeSelect.set(nil, "PlayerToRemove")
removeArgs.removeBtn.func()
Assertions.Equal("PlayerToRemove", MockRoster.RemovePlayerCalled, "Should call RemovePlayer with correct name")

print("Roster Settings UI Test Passed!")
