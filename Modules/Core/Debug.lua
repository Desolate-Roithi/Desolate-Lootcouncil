---@class Debug : AceModule, AceConsole-3.0
---@field ToggleVerbose fun(self: Debug)
---@field ShowStatus fun(self: Debug)
---@field SimulateComm fun(self: Debug, name: string)
---@field OnEnable function
---@field SimulateVoting function
---@field DumpKeys fun(self: Debug)


---@class (partial) DLC_Ref_Debug
---@field db table
---@field activeAddonUsers table
---@field DetermineLootMaster fun(self: DLC_Ref_Debug): string
---@field NewModule fun(self: DLC_Ref_Debug, name: string, ...): any
---@field GetModule fun(self: DLC_Ref_Debug, name: string): any

---@type DLC_Ref_Debug
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
---@type Debug
local Debug = DesolateLootcouncil:NewModule("Debug", "AceConsole-3.0") --[[@as Debug]]

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
    local userCount = 1
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

function Debug:DumpKeys()
    local db = DesolateLootcouncil.db.profile
    if not db.playerRoster or not db.playerRoster.alts then
        self:Print("No Alts database found.")
        return
    end

    self:Print("[DLC] --- DUMPING ALT ROSTER ---")
    local count = 0
    for k, v in pairs(db.playerRoster.alts) do
        self:Print("[DLC] Alt: [" .. tostring(k) .. "] -> Main: [" .. tostring(v) .. "]")
        count = count + 1
    end
    self:Print("[DLC] --- END DUMP (" .. count .. " entries) ---")
end
