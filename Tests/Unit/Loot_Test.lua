-- Tests/Unit/Loot_Test.lua
---@diagnostic disable: undefined-global, missing-fields

-- 1. Load Mocks
dofile("Tests/Unit/TestMock.lua")

-- 2. Load System Under Test


LoadModule("Systems/Loot.lua")
local Loot = DesolateLootcouncil.modules["Loot"] --[[@as Loot]]
Loot:OnEnable()

print("--- Running Loot Unit Tests ---")

local function Test_Categorization()
    -- Mock C_Item results via our TestMock
    -- StartLootRoll -> OnStartLootRoll -> CategorizeItem

    -- Direct test of CategorizeItem heuristics
    -- 1. Weapon (ClassID 2)
    -- Mock GetItemInfoInstant to return 2
    ---@diagnostic disable-next-line: duplicate-set-field
    C_Item.GetItemInfoInstant = function(link)
        if link == "item:123:Weapon" then return 123, "Type", "SubType", 1, 123, 2, 1 end
        if link == "item:456:Tier" then return 456, "Type", "SubType", 1, 456, 4, 1 end -- Armor
        return 0, "", "", 0, 0, 0, 0
    end

    local cat = Loot:CategorizeItem("item:123:Weapon")
    Assertions.Equal("Weapons", cat, "Weapon Detection")

    -- 2. Junk
    cat = Loot:CategorizeItem("item:999:Junk")
    Assertions.Equal("Junk/Pass", cat, "Junk Detection")

    -- 3. Tier (Harder to mock purely with ID, often relies on name matching or specific IDs in PriorityLists)
    -- If we add it to a PriorityList, it should return that list name
    DesolateLootcouncil.db.profile.PriorityLists = {
        { name = "Tier", items = { [456] = true } }
    }
    cat = Loot:CategorizeItem("item:456:Tier")
    Assertions.Equal("Tier", cat, "DB Priority List Match")
end

-- Run
local status, err = pcall(function()
    Test_Categorization()
end)

if status then
    print("ALL LOOT TESTS PASSED")
else
    print("LOOT TEST FAILED: " .. err)
end
