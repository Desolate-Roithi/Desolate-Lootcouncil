local _, AT = ...
if AT.abortLoad then return end

---@class Debug : AceModule, AceConsole-3.0
---@field ShowStatus fun(self: Debug)
---@field SimulateComm fun(self: Debug, name: string)
---@field OnEnable function
---@field SimulateVoting function
---@field DumpKeys fun(self: Debug)
---@field OpenConfig fun()

---@class (partial) DesolateLootcouncil : AceAddon
---@field Debug Debug
---@field activeAddonUsers table

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]

---@type Debug
local Debug = DesolateLootcouncil:NewModule("Debug", "AceConsole-3.0") --[[@as Debug]]

function Debug:OnEnable()
    -- Passive module: No longer registers chat commands directly (handled by SlashCommands.lua).
    DesolateLootcouncil:DLC_Log("Utilities/Debug Loaded")
end

function Debug:ShowStatus()
    local userCount = 0
    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if Comm and Comm.GetActiveUserCount then
        userCount = Comm:GetActiveUserCount()
    end

    local activeLM = DesolateLootcouncil:DetermineLootMaster()

    DesolateLootcouncil:DLC_Log("--- Status Report ---", true)
    DesolateLootcouncil:DLC_Log("Configured LM: " .. (DesolateLootcouncil.db.profile.configuredLM or "None"), true)
    DesolateLootcouncil:DLC_Log("Active LM: " .. tostring(activeLM), true)
    DesolateLootcouncil:DLC_Log("Am I LM?: " .. tostring(DesolateLootcouncil:AmILootMaster()), true)
    DesolateLootcouncil:DLC_Log("Am I Officer?: " .. tostring(DesolateLootcouncil:AmIOfficerOrLM()), true)
    DesolateLootcouncil:DLC_Log("Autopass Active: " .. tostring(DesolateLootcouncil.sessionAutopassActive), true)
    DesolateLootcouncil:DLC_Log("Addon Users Found: " .. userCount, true)
    DesolateLootcouncil:DLC_Log("Current Zone: " .. (GetRealZoneText() or "Unknown"), true)
    DesolateLootcouncil:DLC_Log("---------------------", true)
end

function Debug:DumpKeys()
    local db = DesolateLootcouncil.db.profile
    if not db then
        DesolateLootcouncil:DLC_Log("No database found.")
        return
    end

    DesolateLootcouncil:DLC_Log("--- DUMPING ROSTER KEYS ---")

    -- Dump Mains
    if db.MainRoster then
        DesolateLootcouncil:DLC_Log("--- Mains ---")
        for k in pairs(db.MainRoster) do
            DesolateLootcouncil:DLC_Log("Key: [" .. tostring(k) .. "]")
        end
    else
        DesolateLootcouncil:DLC_Log("No MainRoster table.")
    end

    -- Dump Alts
    if db.playerRoster and db.playerRoster.alts then
        DesolateLootcouncil:DLC_Log("--- Alts ---")
        for k, v in pairs(db.playerRoster.alts) do
            DesolateLootcouncil:DLC_Log("Alt: [" .. tostring(k) .. "] -> Main: [" .. tostring(v) .. "]")
        end
    else
        DesolateLootcouncil:DLC_Log("No Alts table.")
    end

    DesolateLootcouncil:DLC_Log("--- END DUMP ---", true)
end

-- Expose globally if needed solely for quick access, but not strictly required
DesolateLootcouncil.Debug = Debug
