---@class Debug : AceModule, AceConsole-3.0
---@field ToggleVerbose fun(self: Debug)
---@field ShowStatus fun(self: Debug)
---@field SimulateComm fun(self: Debug, name: string)
---@field OnEnable function
---@field SimulateVoting function
---@field DumpKeys fun(self: Debug)
---@field OpenConfig fun()

---@class (partial) DLC_Ref_Debug_Util
---@field db table
---@field activeAddonUsers table
---@field DetermineLootMaster fun(self: DLC_Ref_Debug_Util): string
---@field NewModule fun(self: DLC_Ref_Debug_Util, name: string, ...): any
---@field GetModule fun(self: DLC_Ref_Debug_Util, name: string): any
---@field DLC_Log fun(self: DLC_Ref_Debug_Util, msg: string, force?: boolean)

---@type DLC_Ref_Debug_Util
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Debug_Util]]

---@type Debug
local Debug = DesolateLootcouncil:NewModule("Debug", "AceConsole-3.0") --[[@as Debug]]

-- Helper for Config workaround if needed, or just utility
function Debug.OpenConfig()
    -- Double-call workaround for AceConfig bug
    local registry = LibStub("AceConfigDialog-3.0", true)
    if registry then
        registry:Open("DesolateLootcouncil")
        registry:Open("DesolateLootcouncil")
    end
end

function Debug:OnEnable()
    -- Passive module: No longer registers chat commands directly (handled by SlashCommands.lua).
    DesolateLootcouncil:DLC_Log("Utilities/Debug Loaded")
end

function Debug:ToggleVerbose()
    local profile = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
    if profile then
        profile.verboseMode = not profile.verboseMode
        DesolateLootcouncil:DLC_Log("Verbose Mode: " .. (profile.verboseMode and "ON" or "OFF"), true)
    end
end

function Debug:ShowStatus()
    local userCount = 1
    if DesolateLootcouncil.activeAddonUsers then
        for _ in pairs(DesolateLootcouncil.activeAddonUsers) do userCount = userCount + 1 end
    end

    local activeLM = DesolateLootcouncil:DetermineLootMaster()

    DesolateLootcouncil:DLC_Log("--- Status Report ---", true)
    DesolateLootcouncil:DLC_Log("Configured LM: " .. (DesolateLootcouncil.db.profile.configuredLM or "None"), true)
    DesolateLootcouncil:DLC_Log("Active LM: " .. tostring(activeLM), true)
    DesolateLootcouncil:DLC_Log("Am I LM?: " .. tostring(activeLM == UnitName("player")), true)
    DesolateLootcouncil:DLC_Log("Addon Users Found: " .. userCount, true)
    DesolateLootcouncil:DLC_Log("Current Zone: " .. (GetRealZoneText() or "Unknown"), true)
    DesolateLootcouncil:DLC_Log("---------------------", true)
end

function Debug:SimulateComm(arg)
    if arg == "vote" then
        self:SimulateVoting()
    else
        DesolateLootcouncil.activeAddonUsers[arg] = true
        DesolateLootcouncil:DLC_Log("Simulated PONG from " .. arg)
    end
end

function Debug:SimulateVoting()
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session") --[[@as Session]]
    if not Session then return end

    local session = DesolateLootcouncil.db.profile.session
    local bidding = session and session.bidding

    if not bidding or #bidding == 0 then
        DesolateLootcouncil:DLC_Log("No active session items found.")
        return
    end

    local myName = UnitName("player")
    local votedCount = 0
    -- Iterate all known addon users
    if DesolateLootcouncil.activeAddonUsers then
        for name in pairs(DesolateLootcouncil.activeAddonUsers) do
            -- Skip myself (I vote manually)
            if name ~= myName then
                for _, item in ipairs(bidding) do
                    local roll = math.random(1, 4) -- Random 1-4
                    local payload = {
                        command = "VOTE",
                        data = {
                            guid = item.sourceGUID or item.link,
                            vote = roll
                        }
                    }
                    -- Serialize and Inject into Distribution Module (Wait, Session module)
                    -- Session module handles OnCommReceived with "DLC_Loot" prefix?
                    -- Systems/Session.lua registers "DLC_Loot".
                    local serialized = Session:Serialize(payload)
                    Session:OnCommReceived("DLC_Loot", serialized, "WHISPER", name)
                end
                votedCount = votedCount + 1
            end
        end
    end
    DesolateLootcouncil:DLC_Log("Simulated random votes for " .. votedCount .. " users.")
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
        for k, v in pairs(db.MainRoster) do
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

    DesolateLootcouncil:DLC_Log("--- END DUMP ---")
end

-- Expose globally if needed solely for quick access, but not strictly required
DesolateLootcouncil.Debug = Debug
