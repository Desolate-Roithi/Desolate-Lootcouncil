local _, AT = ...
if AT.abortLoad then return end

---@class Trade : AceModule, AceEvent-3.0, AceConsole-3.0
local Trade = DesolateLootcouncil:NewModule("Trade", "AceEvent-3.0", "AceConsole-3.0")

---@class (partial) DLC_Ref_Trade
---@field db table
---@field GetModule fun(self: any, name: string): any
---@field DLC_Log fun(self: any, msg: string, force?: boolean)

---@type DLC_Ref_Trade
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Trade]]

function Trade:OnEnable()
    self:RegisterEvent("TRADE_SHOW", "OnTradeShow")
    self:RegisterEvent("UI_INFO_MESSAGE", "OnUIInfo")
    DesolateLootcouncil:DLC_Log("Systems/Trade Loaded")
end

function Trade:OnUIInfo(event, msgID, msg)
    if msg == ERR_TRADE_COMPLETE then
        -- This handles the case where we don't have currentTrade set (manual trade)
        -- We'll scan the inbox and history to see if anything was just traded.
        -- But first, let's see if CHAT_MSG_SYSTEM already handled it.
    end
end

function Trade:OnTradeShow()
    -- Get the name of the person we are trading with
    -- "NPC" unit token refers to the trade target while the trade window is open
    local tradeTargetName = UnitName("NPC")
    if not tradeTargetName then return end

    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.awarded then return end

    -- Build list of all untraded items for this player
    local pendingItems = {}
    for _, award in ipairs(session.awarded) do
        if award.winner == tradeTargetName and not award.traded then
            table.insert(pendingItems, award)
        end
    end

    if #pendingItems > 0 then
        self:StageAllItems(pendingItems, tradeTargetName)
    end
end

-- Bug 2: Stage ALL pending items for a player in one trade window open
function Trade:StageAllItems(pendingItems, targetName)
    self.currentTrade = {}

    for _, award in ipairs(pendingItems) do
        local targetItemID = award.itemID
        local staged = false

        for bag = 0, 4 do
            if staged then break end
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                if staged then break end
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == targetItemID and not info.isLocked then
                    C_Container.UseContainerItem(bag, slot)
                    table.insert(self.currentTrade, {
                        link   = award.link,
                        winner = award.winner,
                        guid   = award.sourceGUID
                    })
                    DesolateLootcouncil:DLC_Log(string.format("Staged %s for %s.", award.link, targetName))
                    staged = true
                end
            end
        end

        if not staged then
            DesolateLootcouncil:DLC_Log(string.format("Could not find %s in bags for %s.", award.link, targetName))
        end
    end

    if #self.currentTrade > 0 then
        self:RegisterEvent("CHAT_MSG_SYSTEM")
        self:RegisterEvent("TRADE_CLOSED")
    end
end

function Trade:CHAT_MSG_SYSTEM(event, message)
    if message == ERR_TRADE_COMPLETE then
        if self.currentTrade then
            local session = DesolateLootcouncil.db.profile.session
            local changed = false

            for _, pending in ipairs(self.currentTrade) do
                if session and session.awarded then
                    for _, award in ipairs(session.awarded) do
                        if award.link == pending.link and award.winner == pending.winner and not award.traded then
                            award.traded = true
                            changed = true
                            DesolateLootcouncil:DLC_Log(string.format("Trade complete. %s marked as delivered to %s.",
                                pending.link, pending.winner))
                            break
                        end
                    end
                end
            end

            if changed then
                -- Bug 2 fix: refresh the actual trade list window
                ---@type UI_TradeList
                local UI = DesolateLootcouncil:GetModule("UI_TradeList") --[[@as UI_TradeList]]
                if UI and UI.ShowTradeListWindow then
                    UI:ShowTradeListWindow()
                end
            end
        end
    end
    self:ClearPending()
end

function Trade:TRADE_CLOSED()
    self:ClearPending()
end

function Trade:ClearPending()
    self.currentTrade = nil
    self:UnregisterEvent("CHAT_MSG_SYSTEM")
    self:UnregisterEvent("TRADE_CLOSED")
end
