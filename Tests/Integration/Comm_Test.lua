-- Tests/Integration/Comm_Test.lua
---@diagnostic disable: undefined-global, missing-fields, undefined-field

-- 1. Load Mocks
dofile("Tests/Unit/TestMock.lua")

-- 2. Load Unit
LoadModule("Core/Comm.lua")
local Comm = DesolateLootcouncil.modules["Comm"] --[[@as Comm]]
Comm:OnEnable()

print("--- Running Comm Integration Tests ---")

local function Test_VersionHandshake()
    -- 1. Reset
    Comm.playerVersions = {}

    -- 2. Inject Incoming VERSION_REQ
    -- Scenario: Sender A sends REQ
    local payload = { type = "VERSION_REQ", version = "1.0" } -- Comm.lua line 43 checks for .type if table
    -- Serialize
    local serialized = { data = { payload } }               -- Comm:Deserialize returns true, unpack(data.data)

    Comm:OnCommReceived("DLC_COMM", serialized, "GUILD", "SenderA")

    -- ASSERT: Response Sent?
    -- Currently TestMock SendCommMessage routes to Loopback if "DLC_Loot", but Comm usage is "DLC_COMM"
    -- TestMock needs to support generic routing or we verify side effects.

    -- Side Effect: If Sender A included version in REQ, we track it?
    -- Comm.lua line 57 checks if data.version exists.
    -- Our payload was { type="VERSION_REQ", version="1.0" } which becomes 'command' (line 45) and 'data' (line 44).
    -- So yes, it should track SenderA.

    Assertions.Equal("1.0", Comm.playerVersions["SenderA"], "SenderA Version Tracked (REQ Side Effect)")

    -- 3. Inject Incoming VERSION_RESP
    -- Scenario: Sender B replies "2.0"
    local respPayload = { type = "VERSION_RESP", version = "2.0", enchantingSkill = 100 }
    local serializedResp = { data = { respPayload } }

    Comm:OnCommReceived("DLC_COMM", serializedResp, "GUILD", "SenderB")

    Assertions.Equal("2.0", Comm.playerVersions["SenderB"], "SenderB Version Tracked")
    Assertions.Equal(100, Comm.playerEnchantingSkill["SenderB"], "SenderB Skill Tracked")
end

-- Run
local status, err = pcall(Test_VersionHandshake)

if status then
    print("ALL COMM TESTS PASSED")
else
    print("COMM TEST FAILED: " .. err)
end
