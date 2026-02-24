---@class Simulation : AceModule, AceConsole-3.0
---@field activeSims table
---@field HandleSlashCommand fun(self: Simulation, input: string)
---@field GetCount fun(self: Simulation): number
---@field OnEnable fun(self: Simulation)
---@field Add fun(self: Simulation, name: string)
---@field Remove fun(self: Simulation, name: string)
---@field Clear fun(self: Simulation)
---@field IsSimulated fun(self: Simulation, unitName: string): boolean
---@field GetRoster fun(self: Simulation): table
---@field SimulateVote fun(self: Simulation)
---@field RunTest fun(self: Simulation, count: number|string)

---@class (partial) DLC_Ref_Sim_Util
---@field db table
---@field NewModule fun(self: DLC_Ref_Sim_Util, name: string, ...): any
---@field GetModule fun(self: DLC_Ref_Sim_Util, name: string): any
---@field DLC_Log fun(self: DLC_Ref_Sim_Util, msg: string, force?: boolean)
---@field activeAddonUsers table
---@field AmILootMaster fun(self: DLC_Ref_Sim_Util): boolean

---@type DLC_Ref_Sim_Util
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Sim_Util]]
local Simulation = DesolateLootcouncil:NewModule("Simulation", "AceConsole-3.0") --[[@as Simulation]]

-- State
Simulation.activeSims = {}

function Simulation:OnEnable()
    -- Nothing to init specifically
    DesolateLootcouncil:DLC_Log("Utilities/Simulation Loaded")
end

function Simulation:Add(name)
    if not name or name == "" then return end

    if self.activeSims[name] then
        DesolateLootcouncil:DLC_Log("Simulated Player '" .. name .. "' is already active.", true)
        return
    end

    self.activeSims[name] = true

    -- Ensure temp Roster Entry exists to prevent "Unknown" errors
    local db = DesolateLootcouncil.db.profile
    if db and db.playerRoster then
        if not db.playerRoster.alts then db.playerRoster.alts = {} end
        -- Only add if not already known, to preserve real data if testing with real names
        if not db.MainRoster[name] and not db.playerRoster.alts[name] then
            -- Treat as a Main for simplicity in sims
            if not db.MainRoster then db.MainRoster = {} end
            db.MainRoster[name] = { addedAt = time(), class = "WARRIOR", rank = "Sim" }
        end
    end

    DesolateLootcouncil:DLC_Log("Simulated Player Added: " .. name, true)
end

function Simulation:Remove(name)
    if self.activeSims[name] then
        self.activeSims[name] = nil
        DesolateLootcouncil:DLC_Log("Simulated Player Removed: " .. name, true)
    else
        DesolateLootcouncil:DLC_Log("Simulated Player '" .. name .. "' not found.", true)
    end
end

function Simulation:Clear()
    self.activeSims = {}
    DesolateLootcouncil:DLC_Log("All simulated players cleared.", true)
end

function Simulation:GetCount()
    local count = 0
    for _ in pairs(self.activeSims) do count = count + 1 end
    return count
end

function Simulation:IsSimulated(unitName)
    return self.activeSims[unitName] == true
end

function Simulation:GetRoster()
    local list = {}
    for name, _ in pairs(self.activeSims) do
        table.insert(list, name)
    end
    return list
end

function Simulation:GetPendingVoters(guid)
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session")
    if not Session or not Session.sessionVotes then return nil end

    local votes = Session.sessionVotes[guid] or {}
    local pending = {}
    for name, _ in pairs(self.activeSims) do
        if not votes[name] then
            table.insert(pending, name .. " (Sim)")
        end
    end
    return #pending > 0 and pending or nil
end

function Simulation:SimulateVote()
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session") --[[@as Session]]
    if not Session then return end

    local session = DesolateLootcouncil.db.profile.session
    if not session or not session.bidding or #session.bidding == 0 then
        DesolateLootcouncil:DLC_Log("No active session items found to vote on.", true)
        return
    end

    local votedCount = 0
    -- Iterate active SIMS only
    for name, _ in pairs(self.activeSims) do
        for _, item in ipairs(session.bidding) do
            local roll = math.random(1, 4) -- Random 1-4
            local payload = {
                command = "VOTE",
                data = {
                    guid = item.sourceGUID or item.link,
                    vote = roll
                }
            }
            -- Serialize and Inject into Session Module
            local serialized = Session:Serialize(payload)
            if Session.OnCommReceived then
                Session:OnCommReceived("DLC_Loot", serialized, "WHISPER", name)
            end
        end
        votedCount = votedCount + 1
    end
    DesolateLootcouncil:DLC_Log("Simulated random votes cast for " .. votedCount .. " simulated players.", true)
end

function Simulation:RunTest(count)
    if not DesolateLootcouncil:AmILootMaster() then
        DesolateLootcouncil:DLC_Log("Error: You must be Loot Master to start a test.")
        return
    end

    local numItems = tonumber(count) or 3
    if numItems > 10 then numItems = 10 end

    -- Dummy Data
    local dummyItems = {
        "item:19019", -- Thunderfury
        "item:18832", -- Brutality Blade
        "item:16914", -- Bloodfang Hood
        "item:19352", -- Chromatically Tempered Sword
        "item:19375"  -- Mish'undare
    }

    local items = {}
    for i = 1, numItems do
        local link = dummyItems[math.random(#dummyItems)]
        local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
        if not name then
            -- Fallback if item info not cached
            name = "Test Item " .. i
            link = "[" .. name .. "]"
            icon = 134400 -- Question Mark
        end

        table.insert(items, {
            link = link,
            texture = icon,
            quantity = 1,
            isTest = true
        })
    end
end

-- Slash Command Handler
function Simulation:HandleSlashCommand(input)
    local args = { strsplit(" ", input) }
    local cmd = args[1]

    if cmd == "add" then
        if args[2] then self:Add(args[2]) end
    elseif cmd == "remove" then
        if args[2] then self:Remove(args[2]) end
    elseif cmd == "clear" then
        self:Clear()
    elseif cmd == "vote" then
        self:SimulateVote()
    elseif cmd == "list" then
        local roster = self:GetRoster()
        if #roster == 0 then
            DesolateLootcouncil:DLC_Log("No active simulations.", true)
        else
            DesolateLootcouncil:DLC_Log("Active Sims: " .. table.concat(roster, ", "), true)
        end
    else
        DesolateLootcouncil:DLC_Log(
            "Sim Usage: /dlc sim [add <name> | remove <name> | clear | vote | list]", true)
    end
end

DesolateLootcouncil.Simulation = Simulation
