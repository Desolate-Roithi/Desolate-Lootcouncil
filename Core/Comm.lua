local _, AT = ...
if AT.abortLoad then return end

---@class Comm : AceModule, AceComm-3.0, AceSerializer-3.0, AceEvent-3.0
---@field playerVersions table<string, string>
---@field playerEnchantingSkill table<string, number>
---@field frame any
---@field RefreshWindow fun(self: any)
local Comm = DesolateLootcouncil:NewModule("Comm", "AceComm-3.0", "AceSerializer-3.0", "AceEvent-3.0", "AceTimer-3.0")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]

-- Seconds between allowed version check broadcasts. Also returned to callers so
-- UI can display an accurate countdown without duplicating this magic number.
local VERSION_CHECK_COOLDOWN = 10

function Comm:OnInitialize()
    self.playerVersions = {}
    self.playerEnchantingSkill = {}
    self.lastVersionCheck = 0
end

function Comm:OnEnable()
    -- Register the communication prefix
    self:RegisterComm("DLC_COMM", "OnCommReceived")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "PruneRosterData")
    self.playerVersions = self.playerVersions or {}
    self.playerEnchantingSkill = self.playerEnchantingSkill or {}
    self.lastVersionCheck = 0
    self.rosterSyncTimer = nil

    DesolateLootcouncil:DLC_Log("Systems/Comm Loaded")
end

function Comm:SendComm(command, data, target)
    local serialized = self:Serialize(command, data)
    local trimmedTarget = (type(target) == "string") and strtrim(target) or nil
    local upperTarget = trimmedTarget and string.upper(trimmedTarget)

    if upperTarget == "RAID" or upperTarget == "PARTY" or upperTarget == "GUILD" or upperTarget == "INSTANCE_CHAT" then
        if (upperTarget == "RAID" and IsInRaid and IsInRaid()) or (upperTarget == "PARTY" and IsInGroup and IsInGroup()) or (upperTarget == "GUILD" and IsInGuild and IsInGuild()) or upperTarget == "INSTANCE_CHAT" then
            self:SendCommMessage("DLC_COMM", serialized, upperTarget)
        end
    elseif trimmedTarget and trimmedTarget ~= "" and upperTarget ~= "WHISPER" then
        self:SendCommMessage("DLC_COMM", serialized, "WHISPER", trimmedTarget)
    else
        -- Smart channel selection
        local channel = DesolateLootcouncil:GetBroadcastChannel()
        if not channel and (upperTarget == "GUILD" or command == "VERSION_REQ") and IsInGuild and IsInGuild() then
            channel = "GUILD"
        end
        if channel then
            self:SendCommMessage("DLC_COMM", serialized, channel)
        end
    end
end

local CommHandlers = {}

function CommHandlers:VERSION_REQ(data, sender)
    -- Reply with my version and enchanting skill
    local responseData = {
        version = DesolateLootcouncil.version,
        autopassActive = DesolateLootcouncil.sessionAutopassActive,
    }
    local mySkill = DesolateLootcouncil:GetEnchantingSkillLevel()
    if (mySkill or 0) > 0 then
        responseData.enchantingSkill = mySkill
    end
    local channel = DesolateLootcouncil:GetBroadcastChannel()
    if channel == "RAID" then
        local jitter = math.random(1, 60) / 100
        C_Timer.After(jitter, function()
            self:SendComm("VERSION_RESP", responseData, "RAID")
        end)
    else
        self:SendComm("VERSION_RESP", responseData, sender)
    end

    -- Track sender too if they sent version and skill
    if data and data.version then
        self:UpdatePlayerInfo(sender, data.version, data.enchantingSkill or 0, data.autopassActive)
    end

    -- Autopass Sync Handshake: If the local player is the Loot Master, respond to the player's
    -- version ping by whispering our authoritative Autopass active state directly to them.
    -- This instantly syncs late-joiners, zone transitioners, and reloaded raiders
    -- without waiting for the 30-second heartbeat.
    if DesolateLootcouncil:AmILootMaster() then
        local active = DesolateLootcouncil.sessionAutopassActive or false
        self:SendComm("SYNC_AUTOPASS", { isActive = active, isHeartbeat = true }, sender)
        
        -- Sync authoritative Item Manager priority lists to the raider
        local db = DesolateLootcouncil.db.profile
        local lists = {}
        for _, listObj in ipairs(db.PriorityLists or {}) do
            if listObj.name and listObj.items then
                lists[listObj.name] = listObj.items
            end
        end
        self:SendComm("IM_SYNC", { lists = lists, isManual = true }, sender)

        -- History Bulk Sync for late-joining / reloading officers
        if DesolateLootcouncil:IsOfficer(sender) then
            local SessionMod = DesolateLootcouncil:GetModule("Session")
            SessionMod.officerSyncedThisSession = SessionMod.officerSyncedThisSession or {}
            if not SessionMod.officerSyncedThisSession[sender] then
                SessionMod.officerSyncedThisSession[sender] = true
                self:ScheduleTimer(function()
                    local awardedList = db.session and db.session.awarded or {}
                    local bulk = {}
                    local startIdx = math.max(1, #awardedList - 49)
                    for i = startIdx, #awardedList do
                        local entry = awardedList[i]
                        table.insert(bulk, {
                            link        = entry.link,
                            texture     = entry.texture,
                            itemID      = entry.itemID,
                            winner      = entry.winner,
                            winnerClass = entry.winnerClass,
                            voteType    = entry.voteType,
                            timestamp   = entry.timestamp,
                            traded      = entry.traded
                        })
                    end
                    if #bulk > 0 then
                        self:SendComm("HISTORY_BULK_SYNC", bulk, sender)
                    end
                end, 2)
            end
        end
    end

    -- Handshake correction: if the local player is the Group Leader (the authority for nominating LM),
    -- whisper the current active LM directly to the sender.
    local isLeader = DesolateLootcouncil:SmartCompare(DesolateLootcouncil:GetGroupLeader(), "player")
    if isLeader then
        local SessionMod = DesolateLootcouncil:GetModule("Session", true)
        if SessionMod then
            local targetLM = DesolateLootcouncil.activeLootMaster or DesolateLootcouncil:DetermineLootMaster()
            if targetLM then
                local lmPayload = { command = "SYNC_LM", data = { lm = targetLM } }
                self:SendCommMessage("DLC_Loot", SessionMod:Serialize(lmPayload), "WHISPER", sender)
            end
        end
    end
end
CommHandlers.VERSION_CHECK = CommHandlers.VERSION_REQ

function CommHandlers:VERSION_RESP(data, sender)
    -- Store sender's version and enchanting skill
    local ver, skill, autopassActive
    if type(data) == "table" then
        ver = data.version
        skill = data.enchantingSkill
        autopassActive = data.autopassActive
    else
        ver = data
        skill = nil
        autopassActive = nil
    end

    self:UpdatePlayerInfo(sender, ver, skill, autopassActive)
end

function CommHandlers:SYNC_AUTOPASS_ACK(data, sender)
    local active
    if type(data) == "table" then
        active = data.isActive
    else
        active = data
    end
    self:UpdatePlayerInfo(sender, nil, nil, active)
end

function CommHandlers:LOOT_SESSION_START(data, sender)
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.StartSession then
        -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Support data wrapped in data.data or bare lootTable
        local lootTable = data.data or data
        Session:StartSession(lootTable)
    end
end

function CommHandlers:LOOT_SESSION_END(data, sender)
    ---@type Session
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.EndSession then Session:EndSession() end
end

function Comm:OnCommReceived(prefix, message, _distribution, sender)
    if prefix ~= "DLC_COMM" then return end
    if DesolateLootcouncil:SmartCompare(sender, "player") then return end -- Ignore self

    local currentLM = DesolateLootcouncil:DetermineLootMaster()
    if currentLM and currentLM ~= "" and DesolateLootcouncil:SmartCompare(sender, currentLM) then
        self.lastLMMsgTime = GetServerTime()
    end

    local success, command, data = self:Deserialize(message)
    if not success then return end

    -- [LEGACY_COMPAT: v1.x -> Deprecate in v2.0] Handle deserialization format differences (Active used direct object, Legacy used command, data args)
    if type(command) == "table" and command.type then
        data = command
        command = data.type
    end

    local handler = CommHandlers[command]
    if handler then
        handler(self, data, sender)
    else
        local Sync = DesolateLootcouncil:GetModule("Sync", true)
        if Sync and Sync.HandleMessage then
            Sync:HandleMessage(command, data, sender)
        end
    end
end

function Comm:IsLMAbsent()
    if not IsInGroup() then return false end
    if DesolateLootcouncil:AmILootMaster() then return false end
    local now = GetServerTime()
    if not self.lastLMMsgTime then
        self.groupJoinedTime = self.groupJoinedTime or now
        return (now - self.groupJoinedTime > 60)
    end
    return (now - self.lastLMMsgTime > 60)
end


function Comm:UpdatePlayerInfo(sender, version, skill, autopassActive)
    if not sender or sender == "" then return end
    self.playerVersions = self.playerVersions or {}
    self.playerEnchantingSkill = self.playerEnchantingSkill or {}
    self.playerAutopassStates = self.playerAutopassStates or {}

    if version ~= nil then
        self.playerVersions[sender] = version
    end
    if skill ~= nil then
        self.playerEnchantingSkill[sender] = skill
    end
    if autopassActive ~= nil then
        self.playerAutopassStates[sender] = autopassActive
    end

    local shortName = tostring(sender):match("^([^-]+)")
    if shortName and shortName ~= "" and shortName ~= sender then
        if version ~= nil then self.playerVersions[shortName] = version end
        if skill ~= nil then self.playerEnchantingSkill[shortName] = skill end
        if autopassActive ~= nil then self.playerAutopassStates[shortName] = autopassActive end
    end

    local score = DesolateLootcouncil:GetScoreName(sender)
    if score and score ~= "" and score ~= sender and score ~= shortName then
        if version ~= nil then self.playerVersions[score] = version end
    end

    -- Sync to Global for Debug module
    if DesolateLootcouncil.activeAddonUsers then
        DesolateLootcouncil.activeAddonUsers[sender] = true
    end
    -- Fire AceEvent DLC_VERSION_UPDATE
    self:SendMessage("DLC_VERSION_UPDATE", sender, version)
end

function Comm:SendVersionCheck()
    self.playerVersions = self.playerVersions or {}
    self.playerEnchantingSkill = self.playerEnchantingSkill or {}
    self.playerAutopassStates = self.playerAutopassStates or {}

    -- 1. Explicitly update self (Always refresh local state even if throttled)
    local myName = UnitName("player")
    self.playerVersions = self.playerVersions or {}
    self.playerEnchantingSkill = self.playerEnchantingSkill or {}
    self.playerAutopassStates = self.playerAutopassStates or {}
    self.playerVersions[myName] = DesolateLootcouncil.version
    local mySkill = (DesolateLootcouncil.GetEnchantingSkillLevel and DesolateLootcouncil:GetEnchantingSkillLevel()) or 0
    self.playerEnchantingSkill[myName] = mySkill
    self.playerAutopassStates[myName] = DesolateLootcouncil.sessionAutopassActive

    -- 2. Throttling for Broadcast
    local now = GetTime()
    local remaining = self:GetVersionCheckRemaining()
    if remaining > 0 then
        DesolateLootcouncil:DLC_Log(string.format("Version broadcast throttled — %.0fs cooldown remaining.", remaining))
        return false, remaining
    end
    self.lastVersionCheck = now

    local payloadData = {
        version = DesolateLootcouncil.version,
        autopassActive = DesolateLootcouncil.sessionAutopassActive,
    }
    if (mySkill or 0) > 0 then
        payloadData.enchantingSkill = mySkill
    end

    self:SendComm("VERSION_REQ", payloadData)
    return true
end

--- Returns how many seconds remain in the version check cooldown (0 if ready).
--- Safe to call at any time with no side effects.
function Comm:GetVersionCheckRemaining()
    local last = self.lastVersionCheck or 0
    local remaining = VERSION_CHECK_COOLDOWN - (GetTime() - last)
    return remaining > 0 and remaining or 0
end

--- Seeds the local player into playerVersions if not already present.
--- Call this once when a UI window that needs version data first opens.
function Comm:SeedSelf()
    self.playerVersions = self.playerVersions or {}
    self.playerEnchantingSkill = self.playerEnchantingSkill or {}
    self.playerAutopassStates = self.playerAutopassStates or {}

    local myName = UnitName("player")
    if not myName or myName == "Unknown Entity" then return end
    if self.playerVersions[myName] then return end -- already seeded
    local myFullName = DesolateLootcouncil.GetFullName and DesolateLootcouncil:GetFullName("player")
    local myVersion = DesolateLootcouncil.version or "0.0.0"
    local mySkill = (DesolateLootcouncil.GetEnchantingSkillLevel and DesolateLootcouncil:GetEnchantingSkillLevel()) or 0
    self:UpdatePlayerInfo(myName, myVersion, mySkill)
    if myFullName and myFullName ~= myName then
        self:UpdatePlayerInfo(myFullName, myVersion, mySkill)
    end
    DesolateLootcouncil:DLC_Log("[Conn] Self-seeded " .. myName .. " as version " .. myVersion)
end

function Comm:IsPlayerActive(name)
    if not name then return false end
    if self.playerVersions and self.playerVersions[name] then return true end

    local shortName = tostring(name):match("^([^-]+)")
    if shortName and self.playerVersions and self.playerVersions[shortName] then return true end

    if self.lastKnownHasAddon and (self.lastKnownHasAddon[name] or (shortName and self.lastKnownHasAddon[shortName])) then
        return true
    end

    if self.playerVersions then
        for verName in pairs(self.playerVersions) do
            if DesolateLootcouncil:SmartCompare(name, verName) then
                return true
            end
        end
    end
    return false
end

function Comm:IsUnitConnected(unit)
    if UnitIsConnected then
        return UnitIsConnected(unit) ~= false
    end
    return true
end

function Comm:GetGroupConnectionStatus()
    self.lastKnownHasAddon = self.lastKnownHasAddon or {}

    local myName = (GetUnitName and GetUnitName("player", true)) or (UnitName and UnitName("player")) or "Unknown"
    local myVersion = DesolateLootcouncil.version or "2.1.0"
    if myName and myName ~= "Unknown" then
        self.lastKnownHasAddon[myName] = true
    end

    local total = 1
    if IsInGroup() then
        total = GetNumGroupMembers()
        if total == 0 then total = 1 end
    end

    local active = 0
    local missing = {}
    local outdated = {}
    local highestVersion = myVersion
    local members = {}

    local function inspectUnit(unit)
        if UnitExists and not UnitExists(unit) then return end
        local name = (GetUnitName and GetUnitName(unit, true)) or (UnitName and UnitName(unit))
        if not name or name == "" then return end

        local isLocalPlayer = (UnitIsUnit and UnitIsUnit(unit, "player")) or DesolateLootcouncil:SmartCompare(name, "player")
        local isOnline = self:IsUnitConnected(unit)

        local ver
        local hasAddon = false

        if isLocalPlayer then
            hasAddon = true
            ver = myVersion
            self.lastKnownHasAddon[name] = true
        else
            ver = self.playerVersions and self.playerVersions[name]
            if not ver and self.playerVersions then
                local short = name:match("^([^-]+)")
                if short and self.playerVersions[short] then
                    ver = self.playerVersions[short]
                else
                    for pName, pVer in pairs(self.playerVersions) do
                        if DesolateLootcouncil:SmartCompare(name, pName) then
                            ver = pVer
                            break
                        end
                    end
                end
            end

            if ver then
                hasAddon = true
                self.lastKnownHasAddon[name] = true
                local short = name:match("^([^-]+)")
                if short then self.lastKnownHasAddon[short] = true end
            elseif not isOnline and (self.lastKnownHasAddon[name] or (name:match("^([^-]+)") and self.lastKnownHasAddon[name:match("^([^-]+)")])) then
                -- Player went offline with addon installed; retain status so temporary disconnect doesn't block raid
                hasAddon = true
            end
        end

        if hasAddon then
            active = active + 1
            if ver and AT and AT.CompareSemVer and AT.CompareSemVer(ver, highestVersion) then
                highestVersion = ver
            end
        else
            table.insert(missing, name)
        end

        members[name] = {
            name = name,
            version = ver,
            hasAddon = hasAddon,
            isOnline = isOnline,
        }
    end

    if IsInRaid() then
        for i = 1, total do
            inspectUnit("raid" .. i)
        end
    else
        inspectUnit("player")
        if IsInGroup() then
            for i = 1, (total - 1) do
                inspectUnit("party" .. i)
            end
        end
    end

    local API = DesolateLootcouncil.API
    local simRoster = (API and API.GetSimulationRoster and API:GetSimulationRoster()) or {}
    if #simRoster > 0 then
        local Sim = DesolateLootcouncil:GetModule("Simulation", true)
        for _, simName in ipairs(simRoster) do
            if not members[simName] then
                local isOnline = true
                if Sim and Sim.IsOffline and Sim:IsOffline(simName) then
                    isOnline = false
                end
                local ver = (self.playerVersions and self.playerVersions[simName]) or myVersion
                members[simName] = {
                    name = simName,
                    version = ver,
                    hasAddon = true,
                    isOnline = isOnline,
                }
                active = active + 1
                total = total + 1
                if ver and AT and AT.CompareSemVer and AT.CompareSemVer(ver, highestVersion) then
                    highestVersion = ver
                end
            end
        end
    end

    if active > total then active = total end

    if AT and AT.CompareSemVer then
        for _, member in pairs(members) do
            if member.version and AT.CompareSemVer(highestVersion, member.version) then
                table.insert(outdated, member.name)
            end
        end
    end

    local allConnected = (active >= total and #missing == 0)

    return {
        total = total,
        active = active,
        allConnected = allConnected,
        missing = missing,
        outdated = outdated,
        highestVersion = highestVersion,
        members = members
    }
end

function Comm:GetActiveUserCount()
    return self:GetGroupConnectionStatus().active
end

function Comm:GetPlayerAutopassState(name)
    if not name or name == "" then return nil end
    if DesolateLootcouncil:SmartCompare(name, "player") then
        return DesolateLootcouncil.sessionAutopassActive
    end
    self.playerAutopassStates = self.playerAutopassStates or {}
    if self.playerAutopassStates[name] ~= nil then
        return self.playerAutopassStates[name]
    end
    local short = tostring(name):match("^([^-]+)")
    if short and self.playerAutopassStates[short] ~= nil then
        return self.playerAutopassStates[short]
    end
    for pName, state in pairs(self.playerAutopassStates) do
        if DesolateLootcouncil:SmartCompare(name, pName) then
            return state
        end
    end
    local Sim = DesolateLootcouncil:GetModule("Simulation", true)
    if Sim and Sim.IsSimulated and Sim:IsSimulated(name) then
        return DesolateLootcouncil.sessionAutopassActive or false
    end
    return nil
end





function Comm:PruneRosterData()
    if not IsInGroup() then
        self.lastLMMsgTime = nil
        self.groupJoinedTime = nil
    end

    local toRemove = {}
    for name in pairs(self.playerVersions) do
        if not DesolateLootcouncil:IsUnitInRaid(name) and not DesolateLootcouncil:SmartCompare(name, "player") then
            table.insert(toRemove, name)
        end
    end
    
    if #toRemove > 0 then
        for _, name in ipairs(toRemove) do
            self.playerVersions[name] = nil
            self.playerEnchantingSkill[name] = nil
            if DesolateLootcouncil.activeAddonUsers then
                DesolateLootcouncil.activeAddonUsers[name] = nil
            end
        end
        -- Notify UI that data has changed (pruned)
        self:SendMessage("DLC_VERSION_UPDATE")
    end
end


