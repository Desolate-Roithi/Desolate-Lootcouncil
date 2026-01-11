-- Tests/Unit/PriorityOverride_Test.lua
---@diagnostic disable: undefined-global, missing-fields, undefined-field, duplicate-set-field
dofile("Tests/Unit/TestMock.lua")

-- Mock DB
DesolateLootcouncil.db.profile.PriorityLists = {
    { name = "TestList", players = { "PlayerA", "PlayerB", "PlayerC" } }
}

-- Load Module (Simulating TOC load)
LoadModule("UI/Windows/PriorityOverride.lua")
local PriorityOverride = DesolateLootcouncil:GetModule("UI_PriorityOverride")

-- Patch CreateFrame to include missing methods for this test
local originalCreateFrame = CreateFrame
CreateFrame = function(type, name, parent, template)
    local f = originalCreateFrame(type, name, parent, template)
    f.SetFrameStrata = function() end
    f.SetToplevel = function() end
    f.SetFrameStrata = function() end
    f.SetToplevel = function() end
    f.StartMoving = function() end
    f.StopMovingOrSizing = function() end
    f.GetEffectiveScale = function() return 1 end
    f.SetBackdrop = function() end
    f.SetBackdropColor = function() end
    f.SetBackdropBorderColor = function() end
    f.SetScrollChild = function() end
    f.IsShown = function() return true end
    f.Show = function() end
    f.Hide = function() end
    f.scripts = {}
    f.SetScript = function(self, scriptName, func) self.scripts[scriptName] = func end
    f.GetScript = function(self, scriptName) return self.scripts[scriptName] end
    f.GetTop = function() return 500 end
    f.GetBottom = function() return 480 end
    f.GetLeft = function() return 100 end
    f.GetRight = function() return 200 end
    f.SetParent = function() end

    -- Child Tracking Mock
    f.children = {}
    f.GetChildren = function(self)
        return unpack(self.children)
    end

    if parent and parent.children then
        table.insert(parent.children, f)
    end

    f.CreateFontString = function()
        return { SetPoint = function() end, SetText = function() end }
    end
    -- Mock GetCursorPosition global if needed (TestMock might not have it?)
    return f
end
-- Also mock GetCursorPosition global
function GetCursorPosition() return 100, 100 end

-- Mock Priority Module for Logging
local MockPriority = { LogPriorityChange = function() end }
local originalGetModule = DesolateLootcouncil.GetModule
DesolateLootcouncil.GetModule = function(self, name)
    if name == "Priority" then return MockPriority end
    return originalGetModule(self, name)
end

-- The Persistence mocks are now in TestMock.lua
-- We only override RestoreFramePosition here to track it for this specific test
DesolateLootcouncil.RestoreFramePosition = function(self, f, key)
    if key == "PriorityOverride" then f.restored = true end
end

-- Test 1: Show Window
PriorityOverride:ShowPriorityOverrideWindow(1)
Assertions.True(PriorityOverride.priorityOverrideFrame, "Frame should be created")
Assertions.True(PriorityOverride.priorityOverrideFrame.restored, "RestoreFramePosition should be called on show")

-- Test 2: Simulate Drag Stop behavior
-- Find the first visible child (active row)
local row
for _, child in ipairs({ PriorityOverride.priorityOverrideContent:GetChildren() }) do
    if child:IsShown() then
        row = child; break
    end
end
if not row then error("No visible row found for testing") end

-- Mock C_Timer (used for deferred refresh)
C_Timer = { After = function(t, cb) cb() end }

-- Test Drag
local script = row:GetScript("OnDragStop")
-- We expect no crash
local status, err = pcall(script, row)
if not status then print("Error in OnDragStop:", err) end
Assertions.True(status, "OnDragStop should not crash")

print("Priority Override Bug Fix Test Passed!")
