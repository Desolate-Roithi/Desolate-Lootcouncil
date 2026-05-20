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

function Autopass:ProcessRoll(rollID)
    if self.autoRolledItems[rollID] then return end

    local link = GetLootRollItemLink(rollID)
    if not link then return end

    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then 
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass skipped for RollID %d: Could not get itemID from link.", rollID), true)
        return 
    end

    local Loot = DesolateLootcouncil:GetModule("Loot")
    local dbCat = Loot and Loot:GetItemCategory(itemID) or "Junk/Pass"
    -- If not officially registered in Item Manager, explicitly ignore it for Autopass
    if dbCat == "Junk/Pass" then 
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass skipped for %s (rollID: %d): Item is not managed in Priority DB.", link, rollID), true)
        return 
    end

    local rollType = self:DetermineRollAction(rollID, dbCat)
    if rollType then
        if DesolateLootcouncil:AmILootMaster() then
            DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass (LM roll) for %s (rollID: %d, rollType: %d)", link, rollID, rollType), true)
        else
            DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass (Raider pass) for %s (rollID: %d)", link, rollID), true)
        end
        self:DoAutoRoll(rollID, rollType)
    end
end

function Autopass:OnStartLootRoll(event, rollID)
    local db = DesolateLootcouncil.db.profile
    if not db.enableAutoLoot then return end

    local isLM = DesolateLootcouncil:AmILootMaster()

    -- Disable entirely if we are in LFR (Match-made groups)
    if HasLFGRestrictions() then
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
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass skipped for RollID %d: sessionAutopassActive is false.", rollID), true)
        return 
    end

    self:ProcessRoll(rollID)
end

function Autopass:ScanAndAutopassActiveLootRolls()
    DesolateLootcouncil:DLC_Log("Scanning active Blizzard loot roll windows for Autopass...", true)

    if not GroupLootContainer or not GroupLootContainer.rollFrames then
        DesolateLootcouncil:DLC_Log("DEBUG: GroupLootContainer not found or has no rollFrames.", true)
        return
    end

    -- Security Check: Explicit true required. Protects PUG players from passing accidentally.
    if not DesolateLootcouncil.sessionAutopassActive then 
        DesolateLootcouncil:DLC_Log("DEBUG: Autopass skipped: sessionAutopassActive is false.", true)
        return 
    end

    for _, frame in pairs(GroupLootContainer.rollFrames) do
        if frame and frame:IsShown() and frame.rollID then
            self:ProcessRoll(frame.rollID)
        end
    end
end

function Autopass:DoAutoRoll(rollID, rollType)
    -- autoRolledItems is actively read in ProcessRoll to act as a double-roll
    -- prevention guard (e.g., if START_LOOT_ROLL fires twice for the same
    -- rollID). Do not remove without replacing with equivalent protection.
    self.autoRolledItems[rollID] = rollType

    -- Delay execution to ensure Blizzard UI handles START_LOOT_ROLL first (increased to 0.15 for high latency)
    C_Timer.After(0.25, function()
        RollOnLoot(rollID, rollType)

        -- Retry safeguard if the roll hasn't registered due to severe server lag
        C_Timer.After(1.0, function()
            RollOnLoot(rollID, rollType)
        end)
    end)
end
