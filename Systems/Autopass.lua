local _, AT = ...
if AT.abortLoad then return end

---@class Autopass : AceModule, AceEvent-3.0
local Autopass = DesolateLootcouncil:NewModule("Autopass", "AceEvent-3.0")

---@class (partial) DLC_Ref_Autopass
---@field db table
---@field DLC_Log fun(self: any, msg: string, force?: boolean)
---@field AmILootMaster fun(self: any): boolean
---@field GetModule fun(self: any, name: string): any
---@field Print fun(self: any, msg: string)
---@field sessionAutopassActive boolean

---@type DLC_Ref_Autopass
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Autopass]]

function Autopass:OnInitialize()
    self.autoRolledItems = {}
    self.pendingAutopassOrders = {}
end

function Autopass:OnEnable()
    self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")
    self:RegisterEvent("CONFIRM_LOOT_ROLL", "OnConfirmLootRoll")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "SyncAutopassState")
    self:SyncAutopassState()
end

function Autopass:OnConfirmLootRoll(event, rollID, rollType)
    if self.autoRolledItems and self.autoRolledItems[rollID] then
        ConfirmLootRoll(rollID, rollType)
        if StaticPopup_Hide then
            StaticPopup_Hide("CONFIRM_LOOT_ROLL")
        end
    end
end

function Autopass:SyncAutopassState()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if config then
        if not IsInRaid() and not (DesolateLootcouncil.IsTestMode and DesolateLootcouncil:IsTestMode()) and not config.sessionActive then
            config.sessionAutopassActive = false
            config.sessionAutopassAnswered = false
        end
        DesolateLootcouncil.sessionAutopassActive = config.sessionAutopassActive or false
    end
end

--- Determines which roll type (Need=1, Greed=2, Disenchant=3, Transmog=4, Pass=0, or nil to skip) should be used.
---@param rollID number
---@param dbCat  string
---@return number|nil rollType
function Autopass:DetermineRollAction(rollID, dbCat)
    local isLM = DesolateLootcouncil:AmILootMaster()
    if isLM then
        local _, _, _, _, isBoP, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
        if isBoP and dbCat == "Collectables" then
            return nil
        end

        if canNeed then
            return 1
        elseif canGreed then
            return 2
        elseif canTransmog then
            return 4
        elseif canDisenchant then
            return 3
        end
    else
        return 0
    end
    return nil
end

local function ShouldLogAutopassDebug()
    return DesolateLootcouncil.db and DesolateLootcouncil.db.profile and DesolateLootcouncil.db.profile.debugMode == true
end

local function DebugLog(msg)
    if ShouldLogAutopassDebug() then
        local formatted = "|cff00ffff[Autopass Debug]|r " .. msg
        if DesolateLootcouncil.Print then
            DesolateLootcouncil:Print(formatted)
        else
            print(formatted)
        end
    end
end

function Autopass:ProcessRoll(rollID)
    self.autoRolledItems = self.autoRolledItems or {}
    if self.autoRolledItems[rollID] then
        DebugLog(string.format("Skipped RollID %d: Item was already auto-rolled.", rollID))
        return
    end

    local link = GetLootRollItemLink(rollID)
    if not link then
        DebugLog(string.format("Skipped RollID %d: Item link is nil.", rollID))
        return
    end

    -- Hoist a single GetModule call — used for both ID fallback and category lookup.
    local Loot = DesolateLootcouncil:GetModule("Loot")
    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then
        itemID = Loot and Loot:GetItemIDFromLink(link)
    end
    if not itemID then 
        DebugLog(string.format("Skipped %s (RollID %d): Could not extract itemID.", link, rollID))
        return 
    end

    local dbCat = Loot and Loot:GetItemCategory(itemID) or "Junk/Pass"
    -- If not officially registered in Item Manager, explicitly ignore it for Autopass
    if dbCat == "Junk/Pass" then 
        DebugLog(string.format("Skipped %s (RollID %d): Item category is 'Junk/Pass' / not managed in Item Manager.", link, rollID))
        return 
    end

    local rollType = self:DetermineRollAction(rollID, dbCat)
    if rollType then
        if DesolateLootcouncil:AmILootMaster() then
            DebugLog(string.format("Executing LM Autopass for %s (rollID: %d, rollType: %d, category: %s)", link, rollID, rollType, dbCat))
        else
            DebugLog(string.format("Executing Raider Autopass for %s (rollID: %d, rollType: Pass, category: %s)", link, rollID, dbCat))
        end
        self:DoAutoRoll(rollID, rollType)
    else
        DebugLog(string.format("Skipped %s (RollID %d): DetermineRollAction returned nil (e.g. BoP Collectables check).", link, rollID))
    end
end

--- Prunes cached autopass orders older than 30 seconds to prevent table bloat.
---@param now? number
function Autopass:PruneStaleOrders(now)
    if not self.pendingAutopassOrders then return end
    local currentTime = now or GetTime()
    for key, order in pairs(self.pendingAutopassOrders) do
        if not order.time or (currentTime - order.time > 30) then
            self.pendingAutopassOrders[key] = nil
        end
    end
end

function Autopass:HandleAutopassOrder(payload, sender)
    if not payload or type(payload) ~= "table" then return end
    local lm = DesolateLootcouncil:DetermineLootMaster() or DesolateLootcouncil.activeLootMaster
    if not DesolateLootcouncil:SmartCompare(sender, lm) then return end

    if payload.lmAllConnected ~= nil then
        DesolateLootcouncil.lmAllConnected = (payload.lmAllConnected == true)
    end

    self.pendingAutopassOrders = self.pendingAutopassOrders or {}
    local entryTime = GetTime()
    self:PruneStaleOrders(entryTime)

    local entry = {
        action = payload.action or 0,
        time = entryTime,
        itemID = payload.itemID,
        link = payload.link,
        rollID = payload.rollID
    }
    if payload.itemID then self.pendingAutopassOrders[payload.itemID] = entry end
    if payload.link then self.pendingAutopassOrders[payload.link] = entry end
    if payload.rollID then self.pendingAutopassOrders[payload.rollID] = entry end

    self.autoRolledItems = self.autoRolledItems or {}

    -- Late Order Override: If the roll is currently open, execute immediately even if backup previously skipped/held
    if payload.rollID and not self.autoRolledItems[payload.rollID] then
        DebugLog(string.format("Executing incoming LM Autopass Order for rollID %d (late order override)", payload.rollID))
        self:DoAutoRoll(payload.rollID, payload.action or 0)
    elseif GroupLootContainer and GroupLootContainer.rollFrames then
        for _, frame in pairs(GroupLootContainer.rollFrames) do
            if frame and frame:IsShown() and frame.rollID and not self.autoRolledItems[frame.rollID] then
                local link = GetLootRollItemLink(frame.rollID)
                local itemID = link and C_Item.GetItemInfoInstant(link)
                if (payload.rollID and frame.rollID == payload.rollID) or
                   (payload.itemID and itemID == payload.itemID) or
                   (payload.link and link and link == payload.link) then
                    DebugLog(string.format("Executing incoming LM Autopass Order for frame rollID %d (late order override)", frame.rollID))
                    self:DoAutoRoll(frame.rollID, payload.action or 0)
                end
            end
        end
    end
end

function Autopass:OnStartLootRoll(event, rollID)
    local db = DesolateLootcouncil.db.profile
    if not db.enableAutoLoot and not DesolateLootcouncil.sessionAutopassActive then
        DebugLog(string.format("Skipped RollID %d: enableAutoLoot setting is disabled.", rollID))
        return
    end

    local isLM = DesolateLootcouncil:AmILootMaster()

    -- Disable entirely if we are not in a valid raid group or test mode
    if not DesolateLootcouncil:IsInRaidOrTest() then
        DebugLog(string.format("Skipped RollID %d: Not in raid or test group.", rollID))
        return
    end

    self.autoRolledItems = self.autoRolledItems or {}
    if self.autoRolledItems[rollID] then
        DebugLog(string.format("Skipped RollID %d: Already auto-rolled.", rollID))
        return
    end

    local link = GetLootRollItemLink(rollID)
    local Loot = DesolateLootcouncil:GetModule("Loot", true)
    local itemID = link and (C_Item.GetItemInfoInstant(link) or (Loot and Loot.GetItemIDFromLink and Loot:GetItemIDFromLink(link)))
    local ItemCatalog = DesolateLootcouncil:GetModule("ItemCatalog", true)
    local dbCat = (ItemCatalog and ItemCatalog.GetItemCategory and ItemCatalog:GetItemCategory(itemID or link)) or (Loot and itemID and Loot.GetItemCategory and Loot:GetItemCategory(itemID)) or "Junk/Pass"

    -- 1. Check if we already received an authoritative LM Autopass Order for this item (network latency caching)
    self.pendingAutopassOrders = self.pendingAutopassOrders or {}
    self:PruneStaleOrders()
    local pending = (itemID and self.pendingAutopassOrders[itemID]) or (link and self.pendingAutopassOrders[link]) or self.pendingAutopassOrders[rollID]
    if pending and (GetTime() - (pending.time or 0) < 10) then
        DebugLog(string.format("Executing cached LM Autopass Order for %s (rollID %d)", tostring(link), rollID))
        self:DoAutoRoll(rollID, pending.action or 0)
        return
    end

    -- 2. If Loot Master: evaluate conditions, autoroll Need/Greed, and broadcast order
    if isLM then
        local status = DesolateLootcouncil.API and DesolateLootcouncil.API.GetGroupConnectionStatus and DesolateLootcouncil.API:GetGroupConnectionStatus()
        if not status or not status.allConnected then
            DebugLog(string.format("LM skipped autopass for rollID %d: Group not 100%% connected (%d/%d active).", rollID, status and status.active or 0, status and status.total or 0))
            return
        end

        if dbCat == "Junk/Pass" then
            DebugLog(string.format("LM skipped autopass for %s (rollID %d): Item is Junk/Pass.", tostring(link), rollID))
            return
        end

        -- Broadcast AUTOPASS_ORDER package directly to raid channel
        local Session = DesolateLootcouncil:GetModule("Session", true)
        if Session and Session.SendCommMessage then
            local payload = {
                command = "AUTOPASS_ORDER",
                rollID = rollID,
                itemID = itemID,
                link = link,
                category = dbCat,
                action = 0,
                lmAllConnected = true,
            }
            local serialized = Session:Serialize(payload)
            local channel = DesolateLootcouncil:GetBroadcastChannel() or "RAID"
            Session:SendCommMessage("DLC_Loot", serialized, channel)
            DebugLog(string.format("LM broadcast AUTOPASS_ORDER for %s to channel %s", tostring(link), channel))
        end

        -- LM autorolls Need/Greed for itself to collect the loot
        local rollType = self:DetermineRollAction(rollID, dbCat)
        if rollType then
            DebugLog(string.format("LM executing autoroll for %s (rollID %d, rollType %d)", tostring(link), rollID, rollType))
            self:DoAutoRoll(rollID, rollType)
        end
        return
    end

    -- 3. If Raider: wait brief grace period (0.8s) for LM's order. If order hasn't arrived, evaluate backup.
    C_Timer.After(0.8, function()
        if self.autoRolledItems[rollID] then return end

        -- Check if order arrived during grace period
        local order = (itemID and self.pendingAutopassOrders[itemID]) or (link and self.pendingAutopassOrders[link]) or self.pendingAutopassOrders[rollID]
        if order and (GetTime() - (order.time or 0) < 10) then
            DebugLog(string.format("Executing newly arrived LM order for %s (rollID %d)", tostring(link), rollID))
            self:DoAutoRoll(rollID, order.action or 0)
            return
        end

        -- Raider Backup Check: verify LM connection status from heartbeat and local IM catalog
        local lmAllConn = DesolateLootcouncil.lmAllConnected
        if lmAllConn == nil then
            if DesolateLootcouncil.sessionAutopassActive and DesolateLootcouncil:IsLMAddonUser() then
                lmAllConn = true
            else
                lmAllConn = DesolateLootcouncil:DoAllGroupMembersHaveAddon()
            end
        end

        if not lmAllConn then
            DebugLog(string.format("Raider backup skipped rollID %d: Group not reported all connected.", rollID))
            return
        end

        local cat = (Loot and itemID and Loot:GetItemCategory(itemID)) or "Junk/Pass"
        if cat == "Junk/Pass" then
            DebugLog(string.format("Raider backup skipped rollID %d: Item is Junk/Pass in local IM.", rollID))
            return
        end

        DebugLog(string.format("Raider backup executing autopass for %s (rollID %d)", tostring(link), rollID))
        self:DoAutoRoll(rollID, 0)
    end)
end

function Autopass:ScanAndAutopassActiveLootRolls()
    DebugLog("Scanning active Blizzard loot roll windows for Autopass...")

    if not DesolateLootcouncil:IsInRaidOrTest() then
        DebugLog("Skipped scan: Not in raid or test group.")
        return
    end

    if not GroupLootContainer or not GroupLootContainer.rollFrames then
        DebugLog("Skipped scan: GroupLootContainer not found or has no rollFrames.")
        return
    end

    local isLM = DesolateLootcouncil:AmILootMaster()

    -- Security Check: Loot Master must have the addon. Protects PUG players from passing.
    if not isLM and not DesolateLootcouncil:IsLMAddonUser() then
        DebugLog("Skipped scan: Loot Master is not using the addon.")
        return
    end

    -- Security Check: Explicit true required. Protects PUG players from passing accidentally.
    if not DesolateLootcouncil.sessionAutopassActive then 
        DebugLog("Skipped scan: sessionAutopassActive is false/disabled by LM.")
        return 
    end

    for _, frame in pairs(GroupLootContainer.rollFrames) do
        if frame and frame:IsShown() and frame.rollID then
            self:ProcessRoll(frame.rollID)
        end
    end
end

function Autopass:HideGroupLootFrameWithRollID(rollID)
    if not rollID or not GroupLootContainer then return end

    local function removeFrame(frame)
        if _G.GroupLootContainer_RemoveFrame then
            -- pcall guards against protected-frame errors if Blizzard changes
            -- GroupLootContainer internals between patches.
            local ok, err = pcall(_G.GroupLootContainer_RemoveFrame, GroupLootContainer, frame)
            if not ok then
                DesolateLootcouncil:DLC_Log("DEBUG: GroupLootContainer_RemoveFrame failed: " .. tostring(err))
                if frame.Hide then frame:Hide() end
            end
        elseif frame.Hide then
            frame:Hide()
        end
    end

    if GroupLootContainer.rollFrames then
        for _, frame in pairs(GroupLootContainer.rollFrames) do
            if frame and frame:IsShown() and frame.rollID == rollID then
                removeFrame(frame)
                break
            end
        end
    else
        for i = 1, 4 do
            local frame = _G["GroupLootFrame" .. i]
            if frame and frame:IsShown() and frame.rollID == rollID then
                removeFrame(frame)
                break
            end
        end
    end
end

function Autopass:DoAutoRoll(rollID, rollType)
    -- autoRolledItems is actively read in ProcessRoll to act as a double-roll
    -- prevention guard (e.g., if START_LOOT_ROLL fires twice for the same
    -- rollID). Do not remove without replacing with equivalent protection.
    self.autoRolledItems[rollID] = rollType

    C_Timer.After(0.05, function()
        RollOnLoot(rollID, rollType)
        -- RunNextFrame defers the dismiss until Blizzard has processed the roll
        -- result, matching RC's own pattern for frame cleanup.
        RunNextFrame(function()
            self:HideGroupLootFrameWithRollID(rollID)
        end)
    end)
end
