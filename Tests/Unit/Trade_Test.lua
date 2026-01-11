-- Tests/Unit/Trade_Test.lua
---@diagnostic disable: undefined-global, missing-fields, undefined-field

-- 1. Load Mocks
dofile("Tests/Unit/TestMock.lua")

-- 2. Load System Under Test
LoadModule("Systems/Trade.lua")
local Trade = DesolateLootcouncil.modules["Trade"] --[[@as Trade]]
Trade:OnEnable()

print("--- Running Trade Unit Tests ---")

local function Test_AutoTradeLookup()
    -- Setup Session with pending award
    DesolateLootcouncil.db.profile.session = {
        awarded = {
            {
                link = "item:12345",
                itemID = 12345,
                winner = "TradeTarget",
                sourceGUID = "Mob1",
                traded = false
            }
        }
    }

    -- Verify no current trade
    Assertions.True(Trade.currentTrade == nil, "Initial No Trade")

    -- Mock ERR_TRADE_COMPLETE constant if needed
    ERR_TRADE_COMPLETE = "Trade Complete."

    -- ACT: Open Trade Window
    -- Mock expects "NPC" -> "TradeTarget" (Added in TestMock)
    Trade:OnTradeShow()

    -- ASSERT: Trade Staged
    -- TestMock C_Container has item 12345 in Bag 0 Slot 1
    Assertions.True(Trade.currentTrade ~= nil, "Trade Staged")
    Assertions.Equal(1, #Trade.currentTrade, "One Item Staged")
    Assertions.Equal("TradeTarget", Trade.currentTrade[1].winner, "Winner Match")
end

local function Test_TradeCompletion()
    -- Setup Staged Trade
    Trade.currentTrade = {
        { link = "item:12345", winner = "TradeTarget", guid = "Mob1" }
    }

    -- Mock Session Award
    DesolateLootcouncil.db.profile.session = {
        awarded = {
            {
                link = "item:12345",
                itemID = 12345,
                winner = "TradeTarget",
                sourceGUID = "Mob1",
                traded = false
            }
        }
    }

    -- ACT: Trade Complete
    Trade:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM", "Trade Complete.")

    -- ASSERT: Marked Traded
    local award = DesolateLootcouncil.db.profile.session.awarded[1]
    Assertions.True(award.traded, "Item Marked Traded")
    Assertions.True(Trade.currentTrade == nil, "Pending Cleared")
end

-- Run
local status, err = pcall(function()
    Test_AutoTradeLookup()
    Test_TradeCompletion()
end)

if status then
    print("ALL TRADE TESTS PASSED")
else
    print("TRADE TEST FAILED: " .. err)
end
