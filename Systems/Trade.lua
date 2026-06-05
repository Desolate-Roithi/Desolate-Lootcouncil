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
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

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

    DesolateLootcouncil:DLC_Log(L["Systems/Trade Loaded"])
end

function Trade:OnStaticPopup(name)
    -- Check for trade-related confirmation dialogs
    local isTradePopup = (name == "LOOT_BIND" or name == "TRADE_POTENTIALLY_SOULBOUND_ITEM" or name == "TRADE_BOP" or name == "END_BOUND_TRADEABLE" or name == "TRADE_POTENTIAL_REMOVE_TRANSMOG")
    if isTradePopup then
        -- Find the visible popup and click "Accept" (button 1)
        local popup = StaticPopup_FindVisible(name)
        if popup then
            StaticPopup_OnClick(popup, 1)
            DesolateLootcouncil:DLC_Log(string.format(L["Bypassed Blizzard trade confirmation: %s"], name))
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

    if not DesolateLootcouncil:AmILootMaster() then return end

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
        self.tradeTimer = C_Timer.NewTimer(0.2, function()
            self.tradeTimer = nil
            -- Ensure trade wasn't closed during the delay (prevents accidental self-equipping via UseContainerItem)
            if TradeFrame and TradeFrame:IsShown() then
                self:StageAllItems(pendingItems, tradeTargetName)
            end
        end)
    end
end

--- Returns true if the item in the given bag slot is account-bound (warbound).
--- Checks C_TooltipInfo for the standard Blizzard account-bound constants.
---@param bag  number
---@param slot number
---@return boolean
function Trade:IsItemWarbound(bag, slot)
    local tooltipData = C_TooltipInfo.GetBagItem(bag, slot)
    if not tooltipData or not tooltipData.lines then return false end
    for _, line in ipairs(tooltipData.lines) do
        if line.leftText and (
            line.leftText == ITEM_ACCOUNTBOUND or
            line.leftText == ITEM_ACCOUNTBOUND_UNTIL_EQUIP or
            line.leftText == ITEM_BNETACCOUNTBOUND
        ) then
            return true
        end
    end
    return false
end

--- Scans bags 0-4 and returns the first unlocked, stageable slot for itemID.
--- For BoP items (fresh raid loot) isBound is expected and allowed through.
--- Warbound (account-bound) copies are always skipped.
---@param targetItemID number
---@param isBoP        boolean
---@return number|nil bag, number|nil slot
function Trade:GetStageableSlot(targetItemID, isBoP)
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == targetItemID and not info.isLocked then
                -- 12.0.1 Fix: BoP raid loot is isBound=true but is still tradeable.
                -- Only block bound items for BoE to prevent staging equipped gear.
                local boundOk  = (not info.isBound or isBoP)
                local warbound = self:IsItemWarbound(bag, slot)
                if boundOk and not warbound then
                    return bag, slot
                end

                DesolateLootcouncil:DLC_Log(string.format(
                    "DEBUG: Skipped slot [%d,%d] — isWarbound=%s isBound=%s isBoP=%s",
                    bag, slot,
                    tostring(warbound),
                    tostring(info.isBound),
                    tostring(isBoP)), true)
            end
        end
    end
    return nil, nil
end

function Trade:FindAndStageItem(targetItemID, award, targetName)
    if not targetItemID then
        DesolateLootcouncil:DLC_Log(string.format(L["Could not find %s in bags for %s."], award.link or "?",
            DesolateLootcouncil:GetDisplayName(targetName)))
        return false
    end

    -- Resolve bind type once — identical for all copies of the same itemID.
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(targetItemID)
    local isBoP = (bindType == 1)

    local bag, slot = self:GetStageableSlot(targetItemID, isBoP)
    if not bag then
        return false
    end

    C_Container.UseContainerItem(bag, slot)
    table.insert(self.currentTrade, {
        link   = award.link,
        winner = award.winner,
        guid   = award.sourceGUID,
    })
    DesolateLootcouncil:DLC_Log(string.format(L["Staged %s for %s."], award.link,
        DesolateLootcouncil:GetDisplayName(targetName)))
    return true
end

-- Bug 2: Stage ALL pending items for a player in one trade window open
function Trade:StageAllItems(pendingItems, targetName)
    self.currentTrade = {}

    -- Register cleanup events unconditionally so currentTrade is always cleared,
    -- even if all items fail to stage (e.g. not in bags, uncached, wrong bind type).
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("TRADE_CLOSED")

    for _, award in ipairs(pendingItems) do
        local targetItemID = award.itemID
        local staged = self:FindAndStageItem(targetItemID, award, targetName)

        if not staged then
            DesolateLootcouncil:DLC_Log(string.format(L["Could not find %s in bags for %s."], award.link,
                DesolateLootcouncil:GetDisplayName(targetName)))
        end
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
                DesolateLootcouncil:DLC_Log(string.format(L["Trade complete. %s marked as delivered to %s."], 
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
    if self.tradeTimer then
        self.tradeTimer:Cancel()
        self.tradeTimer = nil
    end

    C_Timer.After(0.5, function()
        self:ClearPending()
    end)
end

function Trade:ClearPending()
    self.currentTrade = nil
    self:UnregisterEvent("CHAT_MSG_SYSTEM")
    self:UnregisterEvent("TRADE_CLOSED")
end
