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

                    DesolateLootcouncil:DLC_Log(string.format("Auto-staging %s for %s.", award.link, award.winner))

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
            local session = DesolateLootcouncil.db.profile.session
            local changed = false

            for _, pending in ipairs(self.currentTrade) do
                -- Update session manually or via helper
                if session and session.awarded then
                    for _, award in ipairs(session.awarded) do
                        if award.link == pending.link and award.winner == pending.winner and not award.traded then
                            award.traded = true
                            changed = true
                            DesolateLootcouncil:DLC_Log(string.format("Trade successful. %s marked as delivered.",
                                pending.link))

                            -- [NEW] Also remove from Loot Inbox (Core/Loot.lua -> Systems/Loot.lua)
                            local Loot = DesolateLootcouncil:GetModule("Loot")
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
                local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
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
    self:ClearPending()
end

function Trade:ClearPending()
    self.currentTrade = nil
    self:UnregisterEvent("CHAT_MSG_SYSTEM")
    self:UnregisterEvent("TRADE_CLOSED")
end
