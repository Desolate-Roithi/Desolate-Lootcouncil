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
    self:RegisterEvent("CHAT_MSG_SYSTEM", "CHAT_MSG_SYSTEM")
    self:RegisterEvent("TRADE_ACCEPT_UPDATE", "TRADE_ACCEPT_UPDATE")
    self:RegisterEvent("TRADE_CLOSED", "TRADE_CLOSED")
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

local function IsTradeCompleteMessage(msg)
    if not msg then return false end
    if type(issecretvalue) == "function" and issecretvalue(msg) then
        return false
    end
    if type(canaccessvalue) == "function" and not canaccessvalue(msg) then
        return false
    end

    local ok, isMatch = pcall(function()
        if msg == ERR_TRADE_COMPLETE then return true end
        local lower = string.lower(tostring(msg))
        if lower:find("trade complete") or lower:find("handel abgeschlossen") then
            return true
        end
        return false
    end)
    return ok and isMatch == true
end

function Trade:OnUIInfo(event, msgID, msg)
    if not self.itemsInTrade and not self.currentTrade then return end
    if IsTradeCompleteMessage(msg) then
        self:HandleTradeSuccess()
    end
end

function Trade:TRADE_ACCEPT_UPDATE(event, playerAccepted, targetAccepted)
    if tonumber(playerAccepted) == 1 and tonumber(targetAccepted) == 1 then
        self.tradeAccepted = true
    else
        self.tradeAccepted = false
    end
end

local function GetTradePartnerName()
    local name, realm = UnitName("NPC")
    if name and realm and realm ~= "" then
        return name .. "-" .. realm:gsub("%s+", "")
    end
    if name and name ~= "" then
        return name
    end
    local unitName = GetUnitName("NPC", true)
    if unitName and unitName ~= "" then
        return unitName:gsub("%s+", "")
    end
    return nil
end

local function IsTradeTargetMatch(awardWinner, tradePartnerName)
    if not awardWinner or not tradePartnerName then return false end
    if DesolateLootcouncil:SmartCompare(awardWinner, tradePartnerName) then
        return true
    end

    local safeLower = (type(strlower) == "function" and strlower) or string.lower
    local shortWinner = safeLower(Ambiguate(awardWinner, "none"))
    local shortPartner = safeLower(Ambiguate(tradePartnerName, "none"))
    if shortWinner ~= "" and shortWinner == shortPartner then
        return true
    end

    local API = DesolateLootcouncil.API
    local awardMain = (API and API.GetMain and API:GetMain(awardWinner)) or awardWinner
    local partnerMain = (API and API.GetMain and API:GetMain(tradePartnerName)) or tradePartnerName
    if awardMain and partnerMain then
        if DesolateLootcouncil:SmartCompare(awardMain, partnerMain) then
            return true
        end
        local shortAwardMain = safeLower(Ambiguate(awardMain, "none"))
        local shortPartnerMain = safeLower(Ambiguate(partnerMain, "none"))
        if shortAwardMain ~= "" and shortAwardMain == shortPartnerMain then
            return true
        end
    end
    return false
end

function Trade:OnTradeShow()
    if self.clearTimer then
        self.clearTimer:Cancel()
        self.clearTimer = nil
    end
    self:ClearPending()

    -- Get the name of the person we are trading with
    -- "NPC" unit token refers to the trade target while the trade window is open
    local tradeTargetName = GetTradePartnerName()
    if not tradeTargetName then return end
    self.tradeTargetName = tradeTargetName

    if not DesolateLootcouncil:AmILootMaster() then return end
    if DesolateLootcouncil.db.profile.enableAutoTrade == false then return end

    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.awarded then return end

    -- Build list of all untraded items for this player
    local pendingItems = {}
    for _, award in ipairs(session.awarded) do
        if IsTradeTargetMatch(award.winner, tradeTargetName) and not award.traded then
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
    local tooltipData = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
    if not tooltipData or not tooltipData.lines then return false end

    if TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, tooltipData)
    end

    for lineIndex, line in ipairs(tooltipData.lines) do
        if line.leftText then
            local text = line.leftText
            if (ITEM_ACCOUNTBOUND and text == ITEM_ACCOUNTBOUND) or
               (ITEM_ACCOUNTBOUND_UNTIL_EQUIP and text == ITEM_ACCOUNTBOUND_UNTIL_EQUIP) or
               (ITEM_BNETACCOUNTBOUND and text == ITEM_BNETACCOUNTBOUND) then
                return true
            end
            local lowerText = string.lower(text)
            if lowerText:find("warbound") or lowerText:find("account%-bound") or lowerText:find("bnetaccountbound") then
                return true
            end
        end
    end
    return false
end

--- Returns true if a bound BoP item is actually tradeable (has active trade time remaining).
---@param bag number
---@param slot number
---@param customTooltipData? table
---@return boolean
function Trade:IsItemTradeableBoP(bag, slot, customTooltipData)
    local tooltipData = customTooltipData or (C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot))
    if not tooltipData or not tooltipData.lines then return false end

    if not customTooltipData and TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, tooltipData)
    end

    local tradeTimeType = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.TradeTimeRemaining) or 36

    local rawPattern = BIND_TRADE_TIME_REMAINING
    local pattern = rawPattern and rawPattern:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", ".*")

    for lineIndex, line in ipairs(tooltipData.lines) do
        if line.type == tradeTimeType then
            return true
        end
        if line.leftText then
            if pattern and string.find(line.leftText, pattern) then
                return true
            end
            local lowerText = string.lower(line.leftText)
            if string.find(lowerText, "tradeable") or string.find(lowerText, "handeln") or string.find(lowerText, "trade time") then
                return true
            end
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
--- Also collects failure reason diagnostics for user-facing LM reporting.
---@param award        table
---@param targetItemID number
---@param usedSlots    table<string, boolean>
---@return number|nil bag, number|nil slot, string|nil failureReason
function Trade:GetStageableSlot(award, targetItemID, usedSlots)
    local normalizedAwardLink = self:NormalizeItemLink(award.link)
    local failureReason = "not_in_bags"
    local candidates = {}

    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == targetItemID then
                local slotKey = string.format("%d-%d", bag, slot)
                if usedSlots[slotKey] then
                    if failureReason == "not_in_bags" then
                        failureReason = "already_staged"
                    end
                elseif info.isLocked then
                    failureReason = "locked"
                elseif self:IsItemWarbound(bag, slot) then
                    failureReason = "warbound"
                elseif info.isBound and not self:IsItemTradeableBoP(bag, slot) then
                    failureReason = "bound_untradeable"
                else
                    -- Valid tradeable candidate
                    local itemLink = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
                    local isExactMatch = not (itemLink and normalizedAwardLink and self:NormalizeItemLink(itemLink) ~= normalizedAwardLink)

                    if isExactMatch then
                        return bag, slot, nil
                    end

                    table.insert(candidates, { bag = bag, slot = slot })
                    failureReason = "link_mismatch"
                end
            end
        end
    end

    -- If no exact match was found, but there's a unique eligible tradeable candidate of that itemID
    if #candidates == 1 then
        return candidates[1].bag, candidates[1].slot, nil
    end

    return nil, nil, failureReason
end

function Trade:FindAndStageItem(targetItemID, award, targetName, usedSlots)
    if not targetItemID then
        local failMsg = string.format(L["Could not stage item for %s: missing itemID."],
            DesolateLootcouncil:GetDisplayName(targetName))
        DesolateLootcouncil:Print(failMsg)
        DesolateLootcouncil:DLC_Log(failMsg, true)
        return false, "missing_id"
    end

    local bag, slot, failureReason = self:GetStageableSlot(award, targetItemID, usedSlots)
    if not bag or not slot then
        local itemText = award.link or tostring(targetItemID)
        local targetText = DesolateLootcouncil:GetDisplayName(targetName)
        local reasonStr = L["Item not found in bags."]
        if failureReason == "bound_untradeable" then
            reasonStr = L["Item is soulbound and cannot be traded (trade timer expired or not tradeable)."]
        elseif failureReason == "warbound" then
            reasonStr = L["Item is Warbound (account-bound) and cannot be traded."]
        elseif failureReason == "locked" then
            reasonStr = L["Item bag slot is locked."]
        elseif failureReason == "already_staged" then
            reasonStr = L["All matching copies in bags are already staged."]
        elseif failureReason == "link_mismatch" then
            reasonStr = L["Multiple copies found with non-matching stats/tertiaries."]
        end

        local warningMsg = string.format(L["Trade warning: Could not stage %s for %s (%s)."],
            itemText, targetText, reasonStr)
        DesolateLootcouncil:Print(warningMsg)
        DesolateLootcouncil:DLC_Log(warningMsg, true)
        return false, failureReason
    end

    C_Container.UseContainerItem(bag, slot)
    local slotKey = string.format("%d-%d", bag, slot)
    usedSlots[slotKey] = true

    table.insert(self.currentTrade, {
        link   = award.link,
        winner = award.winner,
        guid   = award.sourceGUID,
    })
    local stagedMsg = string.format(L["Staged %s for %s."], award.link,
        DesolateLootcouncil:GetDisplayName(targetName))
    DesolateLootcouncil:DLC_Log(stagedMsg)
    return true
end

-- Stage ALL pending items for a player in one trade window open
function Trade:StageAllItems(pendingItems, targetName)
    self.currentTrade = {}
    local usedSlots = {}

    local stagedCount = 0
    for awardIndex, award in ipairs(pendingItems) do
        if stagedCount >= 6 then
            local fullMsg = L["Trade window full. Remaining items will be staged in the next trade."]
            DesolateLootcouncil:Print(fullMsg)
            DesolateLootcouncil:DLC_Log(fullMsg, true)
            break
        end

        local targetItemID = award.itemID
        local staged = self:FindAndStageItem(targetItemID, award, targetName, usedSlots)

        if staged then
            stagedCount = stagedCount + 1
        end
    end
end

function Trade:ScanTradeSlots()
    if not TradeFrame or not TradeFrame:IsShown() then return end

    self.itemsInTrade = {}
    local partnerName = self.tradeTargetName or GetTradePartnerName()
    for slot = 1, 6 do
        local numItems = select(3, GetTradePlayerItemInfo(slot))
        local itemID = select(8, GetTradePlayerItemInfo(slot))
        local link = GetTradePlayerItemLink(slot)
        if itemID and link then
            table.insert(self.itemsInTrade, {
                itemID = itemID,
                link = link,
                quantity = numItems or 1,
                winner = partnerName,
            })
        end
    end
end

function Trade:OnTradeUpdate()
    self:ScanTradeSlots()
end

function Trade:CHAT_MSG_SYSTEM(event, message)
    if not self.itemsInTrade and not self.currentTrade then return end
    if IsTradeCompleteMessage(message) then
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

    local partnerName = self.tradeTargetName or GetTradePartnerName()
    local changed = false

    for _, pending in ipairs(tradedItems) do
        local normalizedPendingLink = self:NormalizeItemLink(pending.link)
        local pendingID = pending.itemID or (pending.link and select(1, C_Item.GetItemInfoInstant(pending.link)))
        local targetWinner = pending.winner or partnerName

        for _, award in ipairs(session.awarded) do
            if not award.traded and IsTradeTargetMatch(award.winner, targetWinner) then
                local normalizedAwardLink = self:NormalizeItemLink(award.link)
                local awardID = award.itemID or (award.link and select(1, C_Item.GetItemInfoInstant(award.link)))
                local linkMatch = (normalizedAwardLink and normalizedPendingLink and normalizedAwardLink == normalizedPendingLink)
                local idMatch = (awardID and pendingID and awardID == pendingID)

                if linkMatch or idMatch then
                    award.traded = true
                    changed = true
                    DesolateLootcouncil.API:LogAudit("TRADE", nil, award.winner, award.fullItemData and award.fullItemData.category, string.format("Traded %s to %s", tostring(award.link or award.itemID), tostring(award.winner)))
                    DesolateLootcouncil:DLC_Log(string.format(L["Trade complete. %s marked as delivered to %s."],
                        award.link, DesolateLootcouncil:GetDisplayName(award.winner)))
                    break
                end
            end
        end
    end

    if changed then
        local db = DesolateLootcouncil.db.profile
        db.historyTimestamp = GetServerTime()

        -- refresh the actual trade list window
        local API = DesolateLootcouncil.API
        if API and API.ShowTradeListWindow and DesolateLootcouncil:AmILootMaster() then
            API:ShowTradeListWindow()
        end
        self:SendMessage("DLC_HISTORY_UPDATED")

        if API and API.SendDLCHeartbeat and DesolateLootcouncil:AmILootMaster() then
            API:SendDLCHeartbeat()
        end
    end
end

function Trade:TRADE_CLOSED(...)
    if self.tradeTimer then
        self.tradeTimer:Cancel()
        self.tradeTimer = nil
    end

    if self.tradeAccepted then
        self:HandleTradeSuccess()
    end

    self.clearTimer = C_Timer.After(5.0, function()
        self.clearTimer = nil
        self:ClearPending()
    end)
end

function Trade:ClearPending()
    self.currentTrade = nil
    self.itemsInTrade = nil
    self.tradeTargetName = nil
    self.tradeAccepted = false
end

--- Manually marks an item as delivered in the session trade list.
---@param item table
function Trade:MarkItemTraded(item)
    if not item then return end
    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.awarded then return end

    local targetGUID = item.sourceGUID or item.link
    local targetWinner = item.winner
    local targetID = item.itemID or (item.link and select(1, C_Item.GetItemInfoInstant(item.link)))

    for _, award in ipairs(session.awarded) do
        local awardGUID = award.sourceGUID or award.link
        local awardID = award.itemID or (award.link and select(1, C_Item.GetItemInfoInstant(award.link)))
        local guidMatch = (targetGUID and awardGUID and targetGUID == awardGUID)
        local idMatch = (targetID and awardID and targetID == awardID and (not targetWinner or award.winner == targetWinner))

        if (guidMatch or idMatch) and not award.traded then
            award.traded = true
            local db = DesolateLootcouncil.db.profile
            db.historyTimestamp = GetServerTime()
            DesolateLootcouncil.API:LogAudit("TRADE", nil, award.winner, award.fullItemData and award.fullItemData.category, string.format("Traded %s to %s", tostring(award.link or award.itemID), tostring(award.winner)))
            self:SendMessage("DLC_HISTORY_UPDATED")
            DesolateLootcouncil:DLC_Log(string.format(L["Trade complete. %s marked as delivered to %s."],
                award.link or ("item:" .. tostring(targetID)), DesolateLootcouncil:GetDisplayName(award.winner or "Unknown")), true)
            break
        end
    end
end
