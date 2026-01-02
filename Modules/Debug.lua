---@class Debug : AceModule, AceConsole-3.0
local Debug = DesolateLootcouncil:NewModule("Debug", "AceConsole-3.0")

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DLC-Debug]|r " .. tostring(msg))
end

function Debug:OnEnable()
    self:RegisterChatCommand("dlc", "HandleCommand")
end

function Debug:HandleCommand(input)
    if not input or input:trim() == "" then
        -- Future: Open Options Menu
        self:Print("Opening Options... (Placeholder)")
        -- LibStub("AceConfigDialog-3.0"):Open("DesolateLootcouncil")
        return
    end

    -- Parse Command and Arguments
    local cmd, arg = input:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or input:lower()

    if cmd == "loot" then
        -- Handle "/dlc loot" or "/dlc loot open"
        local session = DesolateLootcouncil.db.profile.session
        if session and session.loot then
            ---@type UI
            local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
            UI:ShowLootWindow(session.loot)
            self:Print("Loot Window Opened.")
        else
            self:Print("No active loot session found.")
        end
    elseif cmd == "add" and arg then
        -- Handle "/dlc add [Link]"
        ---@type Loot
        local Loot = DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
        Loot:AddManualItem(arg)
    elseif cmd == "start" then
        local session = DesolateLootcouncil.db.profile.session
        if session and session.loot then
            ---@type Distribution
            local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
            Dist:StartSession(session.loot)
        else
            self:Print("No items in session to start.")
        end
    elseif cmd == "test" then
        ---@type Loot
        local Loot = DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
        Loot:AddTestItems()
    elseif cmd == "status" then
        self:ShowStatus()
    elseif cmd == "sim" and arg then
        if arg == "start" then
            self:Print("Simulating Incoming Loot Session...")
            ---@type Distribution
            local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
            local dummyPayload = {
                command = "START_SESSION",
                data = {
                    { link = "[Thunderfury, Blessed Blade of the Windseeker]", itemID = 19019, texture = 135339, category = "Weapons" },
                    { link = "[Warglaive of Azzinoth]",                        itemID = 32837, texture = 135274, category = "Weapons" }
                }
            }
            local serialized = Dist:Serialize(dummyPayload)
            Dist:OnCommReceived("DLC_Loot", serialized, "WHISPER", UnitName("player"))
        else
            self:SimulateComm(arg)
        end
    elseif cmd == "verbose" then
        local profile = DesolateLootcouncil.db and DesolateLootcouncil.db.profile
        if profile then
            profile.verboseMode = not profile.verboseMode
            self:Print("Verbose Mode: " .. (profile.verboseMode and "ON" or "OFF"))
        end
    else
        self:Print("Commands: /dlc loot, /dlc add [Link], /dlc status")
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
