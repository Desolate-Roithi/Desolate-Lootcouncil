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
end

function Autopass:OnEnable()
    self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "SyncAutopassState")
    self:SyncAutopassState()
end

function Autopass:SyncAutopassState()
    local config = DesolateLootcouncil.db.profile.DecayConfig
    if config then
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

function Autopass:OnStartLootRoll(event, rollID)
    local db = DesolateLootcouncil.db.profile
    if not db.enableAutoLoot then
        DebugLog(string.format("Skipped RollID %d: enableAutoLoot setting is disabled.", rollID))
        return
    end

    local isLM = DesolateLootcouncil:AmILootMaster()

    -- Disable entirely if we are in LFR (Match-made groups)
    if HasLFGRestrictions() then
        DebugLog(string.format("Skipped RollID %d: In LFR group.", rollID))
        return
    end

    if isLM then
        C_Timer.After(1.0, function()
            local Comm = DesolateLootcouncil:GetModule("Comm")
            if Comm and DesolateLootcouncil.sessionAutopassActive ~= nil then
                Comm:SendSyncAutopass(DesolateLootcouncil.sessionAutopassActive)
            end
        end)
    end

    -- Security Check: Explicit true required. Protects PUG players from passing accidentally.
    if not DesolateLootcouncil.sessionAutopassActive then 
        DebugLog(string.format("Skipped RollID %d: sessionAutopassActive is false/disabled by LM.", rollID))
        return 
    end

    self:ProcessRoll(rollID)
end

function Autopass:ScanAndAutopassActiveLootRolls()
    DebugLog("Scanning active Blizzard loot roll windows for Autopass...")

    if not GroupLootContainer or not GroupLootContainer.rollFrames then
        DebugLog("Skipped scan: GroupLootContainer not found or has no rollFrames.")
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
