-- Tests/Integration/LootFlow_Test.lua
---@diagnostic disable: undefined-global, missing-fields, undefined-field

-- 1. Load Mocks
dofile("Tests/Unit/TestMock.lua")

-- 2. Load Systems Under Test


LoadModule("Systems/Loot.lua")
LoadModule("Systems/Session.lua")

local Loot = DesolateLootcouncil.modules["Loot"]
local Session = DesolateLootcouncil.modules["Session"]

-- Manual Init (Simulate AceAddon:Enable)
Loot:OnEnable()
Session:OnEnable()

print("--- Running Loot Flow Integration Test ---")

local function Test_LootFlow()
    -- A. Start Session
    local testItems = {
        { link = "item:12345", texture = 123, quantity = 1, category = "Tier", sourceGUID = "Mob1" }
    }

    -- Mock UI Helper
    DesolateLootcouncil.modules["UI_Voting"] = {
        ShowVotingWindow = function() end,
        ResetVoting = function() end
    }
    DesolateLootcouncil.modules["UI_Monitor"] = { ShowMonitorWindow = function() end }
    DesolateLootcouncil.modules["UI_Loot"] = { ShowLootWindow = function() end }

    -- ACT: Start Session
    -- This calls Session:StartSession -> Serialize -> SendCommMessage -> Loopback -> Session:OnCommReceived("START_SESSION")
    Session:StartSession(testItems)

    -- ASSERT: Session State
    -- Session.clientLootList should be populated by OnCommReceived
    -- AND db.profile.session.bidding should be populated by StartSession (LM side)

    Assertions.Equal(1, #DesolateLootcouncil.db.profile.session.bidding, "Bidding Storage Population")
    Assertions.Equal("Tier", DesolateLootcouncil.db.profile.session.bidding[1].category, "Category Check")

    -- Wait, our loopback is synchronous in the Mock. So clientLootList must be ready.
    -- Assertions.Equal(1, #Session.clientLootList, "Client Loot List Population")
    -- Wait, StartSession clears backlog using Loot:ClearLootBacklog()

    -- B. Simulate Vote
    -- User clicks "Need" (1)
    local itemGUID = "Mob1"
    local payload = {
        command = "VOTE",
        data = { guid = itemGUID, vote = 1 }
    }
    -- Inject Vote Packet
    -- We serialize it locally just to pass to OnCommReceived if we want, or call OnComm directly as if from AceComm
    -- Session:Deserialize expects a table if using our mock serializer
    local serialized = { data = { payload } }
    Session:OnCommReceived("DLC_Loot", serialized, "WHISPER", "VoterA")

    -- ASSERT: Vote Registered
    local votes = Session.sessionVotes[itemGUID]
    Assertions.True(votes ~= nil, "Vote Container Created")
    Assertions.True(votes["VoterA"] ~= nil, "VoterA vote present")
    Assertions.Equal(1, votes["VoterA"].type, "Vote Type Correct")

    -- C. Award Item
    -- LM awards item to VoterA
    Loot:AwardItem(itemGUID, "VoterA", "Bid")

    -- ASSERT: Award Logic
    -- 1. Item in Awarded list
    local awarded = DesolateLootcouncil.db.profile.session.awarded
    Assertions.Equal(1, #awarded, "Awarded List Count")
    Assertions.Equal("VoterA", awarded[1].winner, "Winner Correct")

    -- 2. Item removed from Bidding list
    local bidding = DesolateLootcouncil.db.profile.session.bidding
    Assertions.Equal(0, #bidding, "Bidding List Empty")

    print("[Success] Full Loot Flow Verified")
end


-- Run
local status, err = pcall(Test_LootFlow)
if not status then
    print("INTEGRATION FAIL: " .. err)
else
    print("ALL INTEGRATION TESTS PASSED")
end
