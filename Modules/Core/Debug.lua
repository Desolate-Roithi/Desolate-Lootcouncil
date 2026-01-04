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

    local activeLM = DesolateLootcouncil:DetermineLootMaster()

    self:Print("--- Status Report ---")
    self:Print("Configured LM: " .. (DesolateLootcouncil.db.profile.configuredLM or "None"))
    self:Print("Active LM: " .. tostring(activeLM))
    self:Print("Am I LM?: " .. tostring(activeLM == UnitName("player")))
    self:Print("Addon Users Found: " .. userCount)
    self:Print("Current Zone: " .. GetRealZoneText())
    self:Print("---------------------")
end

function Debug:SimulateComm(arg)
    if arg == "vote" then
        self:SimulateVoting()
    else
        DesolateLootcouncil.activeAddonUsers[arg] = true
        self:Print("Simulated PONG from " .. arg)
    end
end

function Debug:SimulateVoting()
    ---@type Distribution
    local Dist = DesolateLootcouncil:GetModule("Distribution")
    if not Dist then return end
    local session = DesolateLootcouncil.db.profile.session.bidding
    if not session or #session == 0 then
        self:Print("No active session items found.")
        return
    end
    local myName = UnitName("player")
    local votedCount = 0
    -- Iterate all known addon users
    for name in pairs(DesolateLootcouncil.activeAddonUsers) do
        -- Skip myself (I vote manually)
        if name ~= myName then
            for _, item in ipairs(session) do
                local roll = math.random(1, 4) -- Random 1-4
                local payload = {
                    command = "VOTE",
                    data = {
                        guid = item.sourceGUID or item.link,
                        vote = roll
                    }
                }
                -- Serialize and Inject into Distribution Module
                local serialized = Dist:Serialize(payload)
                Dist:OnCommReceived("DLC_Loot", serialized, "WHISPER", name)
            end
            votedCount = votedCount + 1
        end
    end
    self:Print("Simulated random votes for " .. votedCount .. " users.")
end
