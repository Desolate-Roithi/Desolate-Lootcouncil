local _, AT = ...
if AT.abortLoad then return end

---@class Trade : AceModule, AceEvent-3.0, AceConsole-3.0
local Trade = DesolateLootcouncil:NewModule("Trade", "AceEvent-3.0", "AceConsole-3.0")

---@class (partial) DLC_Ref_Trade
---@field db table
---@field GetModule fun(self: any, name: string): any
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field AmILootMaster fun(self: any): boolean
---@field AmIRaidAssistOrLM fun(self: any): boolean

---@type DLC_Ref_Trade
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Trade]]

function Trade:OnEnable()
    self:RegisterEvent("TRADE_SHOW", "OnTradeShow")
    self:RegisterEvent("UI_INFO_MESSAGE", "OnUIInfo")

    -- StaticPopup_Show is a Lua function, NOT a game event — RegisterEvent does not work here.
    -- hooksecurefunc is the only correct mechanism. Taint risk is negligible:
    -- trade confirmation popups (TRADE_BOP, CONFIRM_LOT_BIND) only fire outside combat,
    -- and our hook is fully guarded by self.currentTrade so it is a no-op for all other popups.
    hooksecurefunc("StaticPopup_Show", function(name)
        if not self.currentTrade then return end
        self:OnStaticPopup(name)
    end)

    DesolateLootcouncil:DLC_Log("Systems/Trade Loaded")
end

function Trade:OnStaticPopup(name)
    -- Check for trade-related confirmation dialogs
    if name == "CONFIRM_LOT_BIND" or name == "TRADE_POTENTIALLY_SOUBOUND_ITEM" or name == "TRADE_BOP" then
        -- Find the visible popup and click "Accept" (button 1)
        local popup = StaticPopup_FindVisible(name)
        if popup then
            StaticPopup_OnClick(popup, 1)
            DesolateLootcouncil:DLC_Log("Bypassed Blizzard trade confirmation: " .. name)
        end
    end
end

function Trade:OnUIInfo(_event, _msgID, msg)
    if msg == ERR_TRADE_COMPLETE then
        self:HandleTradeSuccess()
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
        if DesolateLootcouncil:SmartCompare(award.winner, tradeTargetName) and not award.traded then
            table.insert(pendingItems, award)
        end
    end

    if #pendingItems > 0 then
        -- Delay slightly to ensure the server is ready to accept item movements
        C_Timer.After(0.2, function()
            -- Ensure trade wasn't closed during the delay (prevents accidental self-equipping via UseContainerItem)
            if TradeFrame and TradeFrame:IsShown() then
                self:StageAllItems(pendingItems, tradeTargetName)
            end
        end)
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
                if info and info.itemID == targetItemID and not info.isLocked and not info.isBound then
                    C_Container.UseContainerItem(bag, slot)
                    table.insert(self.currentTrade, {
                        link   = award.link,
                        winner = award.winner,
                        guid   = award.sourceGUID
                    })
                    DesolateLootcouncil:DLC_Log(string.format("Staged %s for %s.", award.link, 
                        DesolateLootcouncil:GetDisplayName(targetName)))
                    staged = true
                end
            end
        end

        if not staged then
            DesolateLootcouncil:DLC_Log(string.format("Could not find %s in bags for %s.", award.link, 
                DesolateLootcouncil:GetDisplayName(targetName)))
        end
    end

    if #self.currentTrade > 0 then
        self:RegisterEvent("CHAT_MSG_SYSTEM")
        self:RegisterEvent("TRADE_CLOSED")
    end
end

function Trade:CHAT_MSG_SYSTEM(_event, message)
    if message == ERR_TRADE_COMPLETE then
        self:HandleTradeSuccess()
    end
end

function Trade:HandleTradeSuccess()
    if not self.currentTrade then
        self:ClearPending()
        return
    end

    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.awarded then
        self:ClearPending()
        return
    end

    local changed = false

    for _, pending in ipairs(self.currentTrade) do
        local winnerScore = DesolateLootcouncil:GetScoreName(pending.winner)
        for _, award in ipairs(session.awarded) do
            if award.link == pending.link and DesolateLootcouncil:GetScoreName(award.winner) == winnerScore and not award.traded then
                award.traded = true
                changed = true
                DesolateLootcouncil:DLC_Log(string.format("Trade complete. %s marked as delivered to %s.", 
                    pending.link, DesolateLootcouncil:GetDisplayName(pending.winner)))
                break
            end
        end
    end

    if changed then
        -- Bug 2 fix: refresh the actual trade list window
        ---@type UI_TradeList
        local UI = DesolateLootcouncil:GetModule("UI_TradeList") --[[@as UI_TradeList]]
        if UI and UI.ShowTradeListWindow and DesolateLootcouncil:AmILootMaster() then
            UI:ShowTradeListWindow()
        end
    end

    self:ClearPending()
end

function Trade:TRADE_CLOSED(...)
    C_Timer.After(0.5, function()
        self:ClearPending()
    end)
end

function Trade:ClearPending()
    self.currentTrade = nil
    self:UnregisterEvent("CHAT_MSG_SYSTEM")
    self:UnregisterEvent("TRADE_CLOSED")
end
