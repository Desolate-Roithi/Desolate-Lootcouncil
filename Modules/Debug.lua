---@class Debug : AceModule, AceConsole-3.0
---@field ToggleVerbose fun(self: Debug)
---@field ShowStatus fun(self: Debug)
---@field SimulateComm fun(self: Debug, name: string)
local Debug = DesolateLootcouncil:NewModule("Debug", "AceConsole-3.0")

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DLC-Debug]|r " .. tostring(msg))
end

function Debug:OnEnable()
    -- Passive module: No longer registers chat commands directly.
end

function Debug:ToggleVerbose()
    local profile = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if profile then
        profile.verboseMode = not profile.verboseMode
        self:Print("Verbose Mode: " .. (profile.verboseMode and "ON" or "OFF"))
    end
end

function Debug:ShowStatus()
    local userCount = 0
    for _ in pairs(DesolateLootcouncil.activeAddonUsers) do userCount = userCount + 1 end

    local activeLM = DesolateLootcouncil:GetActiveLM()

    self:Print("--- Status Report ---")
    self:Print("Configured LM: " .. (DesolateLootcouncil.db.profile.configuredLM or "None"))
    self:Print("Active LM: " .. tostring(activeLM))
    self:Print("Am I LM?: " .. tostring(activeLM == UnitName("player")))
    self:Print("Addon Users Found: " .. userCount)
    self:Print("Current Zone: " .. GetRealZoneText())
    self:Print("---------------------")
end

function Debug:SimulateComm(name)
    DesolateLootcouncil.activeAddonUsers[name] = true
    Print("Simulated PONG from " .. name)
end
