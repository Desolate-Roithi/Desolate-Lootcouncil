---@class Trade : AceModule, AceEvent-3.0, AceConsole-3.0
---@field currentTrade table
---@field OnTradeShow fun(self: Trade)
---@field AttemptTrade fun(self: Trade, award: table)
---@field OnEnable function
---@field CHAT_MSG_SYSTEM fun(self: Trade, event: string, msg: string)
---@field TRADE_CLOSED fun(self: Trade)
---@field ClearPending fun(self: Trade)
---@class (partial) DLC_Ref_Trade
---@field db table
---@field NewModule fun(self: DLC_Ref_Trade, name: string, ...): any
---@field Print fun(self: DLC_Ref_Trade, msg: string)
---@field GetModule fun(self: DLC_Ref_Trade, name: string): any

---@type DLC_Ref_Trade
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Trade]]
local Trade = DesolateLootcouncil:NewModule("Trade", "AceEvent-3.0", "AceConsole-3.0") --[[@as Trade]]
local DLC = DesolateLootcouncil

function Trade:OnEnable()
    self:RegisterEvent("TRADE_SHOW", "OnTradeShow")
    -- Watch for trade results to clean up Loot Inbox
    self:RegisterEvent("UI_INFO_MESSAGE", "OnUIInfo")
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

    local session = DLC.db.profile.session
    if not session or not session.awarded then return end

    -- Scan History for items won by this player that haven't been traded
    for _, award in ipairs(session.awarded) do
        if award.winner == tradeTargetName and not award.traded then
            -- We found an item that needs to be traded to this person
            self:AttemptTrade(award)
        end
    end
end

function Trade:AttemptTrade(award)
    local targetItemID = award.itemID

    -- Scan Bags
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == targetItemID then
                -- Check if not locked
                if not info.isLocked then
                    -- Put in trade window
                    C_Container.UseContainerItem(bag, slot)

                    DLC:DLC_Log(string.format("Auto-staging %s for %s.", award.link, award.winner))

                    -- Track as current
                    self.currentTrade = self.currentTrade or {}
                    table.insert(self.currentTrade, {
                        link = award.link,
                        winner = award.winner,
                        guid = award.sourceGUID -- Store GUID to find exact entry easily
                    })

                    -- Register System Chat listener if not already
                    self:RegisterEvent("CHAT_MSG_SYSTEM")
                    self:RegisterEvent("TRADE_CLOSED")

                    return
                end
            end
        end
    end
end

function Trade:CHAT_MSG_SYSTEM(event, message)
    if message == ERR_TRADE_COMPLETE then
        -- Trade success!
        if self.currentTrade then
            local session = DLC.db.profile.session
            local changed = false

            for _, pending in ipairs(self.currentTrade) do
                -- Update session manually or via helper
                if session and session.awarded then
                    for _, award in ipairs(session.awarded) do
                        if award.link == pending.link and award.winner == pending.winner and not award.traded then
                            award.traded = true
                            changed = true
                            DLC:DLC_Log(string.format("Trade successful. %s marked as delivered.", pending.link))

                            -- [NEW] Also remove from Loot Inbox (Core/Loot.lua)
                            local Loot = DLC:GetModule("Loot")
                            if Loot and Loot.RemoveSessionItem then
                                Loot:RemoveSessionItem(pending.guid)
                            end
                            break
                        end
                    end
                end
            end

            if changed then
                ---@type UI
                local UI = DLC:GetModule("UI") --[[@as UI]]
                if UI and UI.RefreshTradeWindow then
                    UI:RefreshTradeWindow()
                end
            end
        end
    end
    -- Cleanup
    self:ClearPending()
end

function Trade:TRADE_CLOSED()
    -- Trade window closed (either success or cancel)
    -- If success, CHAT_MSG_SYSTEM fires BEFORE TradeClosed usually,
    -- but we delay clearing slightly or just clear on next tick to be safe?
    -- Actually, if Cancelled, we just wipe pending.
    -- If Success, CHAT_MSG_SYSTEM handled it.
    -- To be safe, we clear pending here too, but maybe give CHAT_MSG_SYSTEM a chance to fire?
    -- Testing shows CHAT_MSG_SYSTEM (Trade complete) fires first.
    self:ClearPending()
end

function Trade:ClearPending()
    self.currentTrade = nil
    self:UnregisterEvent("CHAT_MSG_SYSTEM")
    self:UnregisterEvent("TRADE_CLOSED")
end
