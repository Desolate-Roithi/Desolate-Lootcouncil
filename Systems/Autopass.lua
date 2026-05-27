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

    -- Hoist a single GetModule call — used for both ID fallback and category lookup.
    local Loot = DesolateLootcouncil:GetModule("Loot")
    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then
        itemID = Loot and Loot:GetItemIDFromLink(link)
    end
    if not itemID then 
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass skipped for RollID %d: Could not get itemID from link.", rollID))
        return 
    end

    local dbCat = Loot and Loot:GetItemCategory(itemID) or "Junk/Pass"
    -- If not officially registered in Item Manager, explicitly ignore it for Autopass
    if dbCat == "Junk/Pass" then 
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass skipped for %s (rollID: %d): Item is not managed in Priority DB.", link, rollID))
        return 
    end

    local rollType = self:DetermineRollAction(rollID, dbCat)
    if rollType then
        if DesolateLootcouncil:AmILootMaster() then
            DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass (LM roll) for %s (rollID: %d, rollType: %d)", link, rollID, rollType))
        else
            DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass (Raider pass) for %s (rollID: %d)", link, rollID))
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
        DesolateLootcouncil:DLC_Log(string.format("DEBUG: Autopass skipped for RollID %d: sessionAutopassActive is false.", rollID))
        return 
    end

    self:ProcessRoll(rollID)
end

function Autopass:ScanAndAutopassActiveLootRolls()
    DesolateLootcouncil:DLC_Log("DEBUG: Scanning active Blizzard loot roll windows for Autopass...")

    if not GroupLootContainer or not GroupLootContainer.rollFrames then
        DesolateLootcouncil:DLC_Log("DEBUG: GroupLootContainer not found or has no rollFrames.")
        return
    end

    -- Security Check: Explicit true required. Protects PUG players from passing accidentally.
    if not DesolateLootcouncil.sessionAutopassActive then 
        DesolateLootcouncil:DLC_Log("DEBUG: Autopass skipped: sessionAutopassActive is false.")
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
