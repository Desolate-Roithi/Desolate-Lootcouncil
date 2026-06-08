local _, AT = ...
if AT.abortLoad then return end

---@class Trade : AceModule, AceEvent-3.0, AceConsole-3.0
local Trade = DesolateLootcouncil:NewModule("Trade", "AceEvent-3.0", "AceConsole-3.0")

---@class (partial) DLC_Ref_Trade
---@field db table
---@field GetModule fun(self: any, name: string): any
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field AmILootMaster fun(self: any): boolean
---@field AmIOfficerOrLM fun(self: any): boolean

---@type DLC_Ref_Trade
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Trade]]
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function Trade:OnEnable()
    self:RegisterEvent("TRADE_SHOW", "OnTradeShow")
    self:RegisterEvent("UI_INFO_MESSAGE", "OnUIInfo")
    self:RegisterEvent("TRADE_UPDATE", "OnTradeUpdate")
    self:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED", "OnTradeUpdate")

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
    if DesolateLootcouncil.db.profile.enableAutoTrade == false then return end

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

--- Returns true if a bound BoP item is actually tradeable (has active trade time remaining).
---@param bag number
---@param slot number
---@return boolean
function Trade:IsItemTradeableBoP(bag, slot)
    local tooltipData = C_TooltipInfo.GetBagItem(bag, slot)
    if not tooltipData or not tooltipData.lines then return false end

    local rawPattern = BIND_TRADE_TIME_REMAINING
    if not rawPattern then return false end
    -- Escape magic characters and convert %s to a wildcard match
    local pattern = rawPattern:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", ".*")

    for _, line in ipairs(tooltipData.lines) do
        if line.leftText and string.find(line.leftText, pattern) then
            return true
        end
    end
    return false
end

--- Extracts and normalizes item strings by zeroing out transient fields (uniqueID, linkLevel)
--- so that items with identical stats/tertiaries match.
---@param link string|nil
---@return string|nil
function Trade:NormalizeItemLink(link)
    if not link then return nil end
    local itemString = string.match(link, "item:([%-?%d:]+)")
    if not itemString then return nil end

    local parts = { strsplit(":", itemString) }
    if parts[8] then parts[8] = "0" end -- uniqueID
    if parts[9] then parts[9] = "0" end -- linkLevel

    return table.concat(parts, ":")
end

--- Scans bags 0-4 and returns the first unlocked, stageable slot for itemID that matches stats.
--- For BoP items (fresh raid loot) isBound is expected and allowed through if tradeable.
--- Warbound (account-bound) copies are always skipped.
---@param award        table
---@param targetItemID number
---@param isBoP        boolean
---@param usedSlots    table<string, boolean>
---@return number|nil bag, number|nil slot
function Trade:GetStageableSlot(award, targetItemID, isBoP, usedSlots)
    local normalizedAwardLink = self:NormalizeItemLink(award.link)

    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local slotKey = string.format("%d-%d", bag, slot)
            if not usedSlots[slotKey] then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == targetItemID and not info.isLocked then
                    -- 12.0.1 Fix: BoP raid loot is isBound=true but is still tradeable.
                    -- Only block bound items for BoE to prevent staging equipped gear.
                    local boundOk = (not info.isBound or isBoP)

                    -- Check tooltip for tradeable BoP time remaining text if bound and BoP
                    if boundOk and isBoP and info.isBound then
                        boundOk = self:IsItemTradeableBoP(bag, slot)
                    end

                    local warbound = self:IsItemWarbound(bag, slot)
                    if boundOk and not warbound then
                        local itemLink = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
                        if itemLink then
                            local normalizedItemLink = self:NormalizeItemLink(itemLink)
                            if normalizedItemLink == normalizedAwardLink then
                                return bag, slot
                            end
                        else
                            -- Fallback if item link is not cached or in mock environment
                            return bag, slot
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

function Trade:FindAndStageItem(targetItemID, award, targetName, usedSlots)
    if not targetItemID then
        DesolateLootcouncil:DLC_Log(string.format(L["Could not find %s in bags for %s."], award.link or "?",
            DesolateLootcouncil:GetDisplayName(targetName)))
        return false
    end

    -- Resolve bind type once — identical for all copies of the same itemID.
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(targetItemID)
    local isBoP = (bindType == 1)

    local bag, slot = self:GetStageableSlot(award, targetItemID, isBoP, usedSlots)
    if not bag or not slot then
        return false
    end

    C_Container.UseContainerItem(bag, slot)
    local slotKey = string.format("%d-%d", bag, slot)
    usedSlots[slotKey] = true

    table.insert(self.currentTrade, {
        link   = award.link,
        winner = award.winner,
        guid   = award.sourceGUID,
    })
    DesolateLootcouncil:DLC_Log(string.format(L["Staged %s for %s."], award.link,
        DesolateLootcouncil:GetDisplayName(targetName)))
    return true
end

-- Stage ALL pending items for a player in one trade window open
function Trade:StageAllItems(pendingItems, targetName)
    self.currentTrade = {}
    local usedSlots = {}

    -- Register cleanup events unconditionally so currentTrade is always cleared,
    -- even if all items fail to stage (e.g. not in bags, uncached, wrong bind type).
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("TRADE_CLOSED")

    local stagedCount = 0
    for _, award in ipairs(pendingItems) do
        if stagedCount >= 6 then
            DesolateLootcouncil:DLC_Log(L["Trade window full. Remaining items will be staged in the next trade."], true)
            break
        end

        local targetItemID = award.itemID
        local staged = self:FindAndStageItem(targetItemID, award, targetName, usedSlots)

        if staged then
            stagedCount = stagedCount + 1
        else
            DesolateLootcouncil:DLC_Log(string.format(L["Could not find %s in bags for %s."], award.link,
                DesolateLootcouncil:GetDisplayName(targetName)))
        end
    end
end

function Trade:ScanTradeSlots()
    if not TradeFrame or not TradeFrame:IsShown() then return end

    self.itemsInTrade = {}
    for slot = 1, 6 do
        local numItems = select(3, GetTradePlayerItemInfo(slot))
        local itemID = select(8, GetTradePlayerItemInfo(slot))
        local link = GetTradePlayerItemLink(slot)
        if itemID and link then
            table.insert(self.itemsInTrade, {
                itemID = itemID,
                link = link,
                quantity = numItems or 1,
            })
        end
    end
end

function Trade:OnTradeUpdate()
    self:ScanTradeSlots()
end

function Trade:CHAT_MSG_SYSTEM(_event, message)
    if message == ERR_TRADE_COMPLETE then
        self:HandleTradeSuccess()
    end
end

function Trade:HandleTradeSuccess()
    local tradedItems = self.itemsInTrade or self.currentTrade
    if not tradedItems then
        self:ClearPending()
        return
    end

    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.awarded then
        self:ClearPending()
        return
    end

    local changed = false

    for _, pending in ipairs(tradedItems) do
        local normalizedPendingLink = self:NormalizeItemLink(pending.link)
        local winnerScore = DesolateLootcouncil:GetScoreName(pending.winner or UnitName("NPC"))

        for _, award in ipairs(session.awarded) do
            if not award.traded and DesolateLootcouncil:GetScoreName(award.winner) == winnerScore then
                local normalizedAwardLink = self:NormalizeItemLink(award.link)
                if normalizedAwardLink == normalizedPendingLink then
                    award.traded = true
                    changed = true
                    DesolateLootcouncil:DLC_Log(string.format(L["Trade complete. %s marked as delivered to %s."],
                        award.link, DesolateLootcouncil:GetDisplayName(award.winner)))
                    
                    self.pendingTradeConfirms = self.pendingTradeConfirms or {}
                    table.insert(self.pendingTradeConfirms, {
                        itemID    = award.itemID,
                        winner    = award.winner,
                        timestamp = award.timestamp
                    })
                    break
                end
            end
        end
    end

    if changed then
        -- refresh the actual trade list window
        ---@type UI_TradeList
        local UI = DesolateLootcouncil:GetModule("UI_TradeList") --[[@as UI_TradeList]]
        if UI and UI.ShowTradeListWindow and DesolateLootcouncil:AmILootMaster() then
            UI:ShowTradeListWindow()
        end
        self:SendMessage("DLC_HISTORY_UPDATED")
    end
end

function Trade:TRADE_CLOSED(...)
    if self.tradeTimer then
        self.tradeTimer:Cancel()
        self.tradeTimer = nil
    end

    if self.pendingTradeConfirms and #self.pendingTradeConfirms > 0 then
        local Sync = DesolateLootcouncil:GetModule("Sync")
        if Sync and Sync.ShareDataWithOfficers then
            Sync:ShareDataWithOfficers("TRADE_CONFIRMED", self.pendingTradeConfirms)
        end
        wipe(self.pendingTradeConfirms)
    end

    C_Timer.After(0.5, function()
        self:ClearPending()
    end)
end

function Trade:ClearPending()
    self.currentTrade = nil
    self.itemsInTrade = nil
    self:UnregisterEvent("CHAT_MSG_SYSTEM")
    self:UnregisterEvent("TRADE_CLOSED")
end
