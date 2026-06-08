local _, AT = ...
if AT.abortLoad then return end

---@class Sync : AceModule, AceTimer-3.0
local Sync = DesolateLootcouncil:NewModule("Sync", "AceTimer-3.0")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]

local SyncHandlers = {}

function Sync:OnInitialize()
    DesolateLootcouncil:DLC_Log("Systems/Sync Loaded")
end

function Sync:HandleMessage(command, data, sender)
    local handler = SyncHandlers[command]
    if handler then
        handler(self, data, sender)
    end
end

function Sync:SendOfficerFlagSync(name, flag)
    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if Comm then
        Comm:SendComm("SYNC_OFFICER_FLAG", { name = name, flag = flag })
    end
end

function Sync:SendSyncAutopass(isActive, isHeartbeat)
    DesolateLootcouncil.sessionAutopassActive = isActive
    DesolateLootcouncil.db.profile.DecayConfig.sessionAutopassActive = isActive
    
    local payload = isActive
    if isHeartbeat then
        payload = { isActive = isActive, isHeartbeat = true }
    end
    
    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if Comm then
        Comm:SendComm("SYNC_AUTOPASS", payload)
    end
    
    if not isHeartbeat then
        local status = isActive and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
        DesolateLootcouncil:DLC_Log("You have " .. status .. " Autopass for this session.")

        local Autopass = DesolateLootcouncil:GetModule("Autopass")
        if Autopass and Autopass.ScanAndAutopassActiveLootRolls then
            Autopass:ScanAndAutopassActiveLootRolls()
        end
    end
end

function Sync:ShareDataWithOfficers(dataType, payload)
    if not DesolateLootcouncil:AmILootMaster() then
        DesolateLootcouncil:DLC_Log("ShareDataWithOfficers: You are not the Loot Master.")
        return
    end

    local command, finalPayload
    if dataType == "PRIORITY" then
        command = "SYNC_PRIORITY"
        local db = DesolateLootcouncil.db.profile
        local lists = {}
        for idx, listObj in ipairs(db.PriorityLists or {}) do
            local playersCopy = {}
            for i, p in ipairs(listObj.players or {}) do playersCopy[i] = p end
            local itemsCopy = {}
            for id, val in pairs(listObj.items or {}) do itemsCopy[id] = val end
            table.insert(lists, { name = listObj.name, players = playersCopy, items = itemsCopy })
        end
        finalPayload = lists
    elseif dataType == "ROSTER" then
        command = "SYNC_ROSTER"
        local db = DesolateLootcouncil.db.profile
        local mainsCopy = {}
        for name, data in pairs(db.MainRoster or {}) do
            mainsCopy[name] = { addedAt = data.addedAt or 0, isOfficer = data.isOfficer == true }
        end
        local altsCopy = {}
        for alt, main in pairs((db.playerRoster or {}).alts or {}) do
            altsCopy[alt] = main
        end
        finalPayload = { mains = mainsCopy, alts = altsCopy }
    elseif dataType == "TRADE_CONFIRMED" then
        command = "TRADE_CONFIRMED"
        finalPayload = payload
    elseif dataType == "HISTORY_BULK_SYNC" then
        command = "HISTORY_BULK_SYNC"
        finalPayload = payload
    elseif dataType == "HISTORY_UPDATE_OFFICER" then
        command = "HISTORY_UPDATE_OFFICER"
        finalPayload = payload
    elseif dataType == "LM_HANDOVER_OFFER" then
        command = "LM_HANDOVER_OFFER"
        finalPayload = payload
    else
        DesolateLootcouncil:DLC_Log("ShareDataWithOfficers: Unknown dataType '" .. tostring(dataType) .. "'.")
        return
    end

    local targets = {}
    local db = DesolateLootcouncil.db.profile
    for name, data in pairs(db.MainRoster or {}) do
        if data.isOfficer and not DesolateLootcouncil:SmartCompare(name, "player") then
            if DesolateLootcouncil:IsUnitInRaid(name) then
                table.insert(targets, name)
            end
        end
    end

    if #targets == 0 then
        DesolateLootcouncil:DLC_Log("ShareDataWithOfficers: No officers found to share with.")
        return
    end

    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if Comm then
        for idx, target in ipairs(targets) do
            local serialized = Comm:Serialize(command, finalPayload)
            Comm:SendCommMessage("DLC_COMM", serialized, "WHISPER", target)
        end
    end

    DesolateLootcouncil:DLC_Log(string.format(
        "Shared %s data with %d officer(s).", dataType, #targets))
end

function Sync:SendLMHandoverOffer(targetOfficer)
    local db = DesolateLootcouncil.db.profile
    local state = {
        awarded = db.session and db.session.awarded or {},
        loot = db.session and db.session.loot or {},
        PriorityLists = db.PriorityLists or {},
        MainRoster = db.MainRoster or {},
        configuredLM = targetOfficer
    }
    
    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if Comm then
        Comm:SendComm("LM_HANDOVER_OFFER", state, targetOfficer)
    end
    
    DesolateLootcouncil.pendingHandoverTarget = targetOfficer
    if self.handoverTimeoutTimer then
        self:CancelTimer(self.handoverTimeoutTimer)
    end
    self.handoverTimeoutTimer = self:ScheduleTimer(function()
        if DesolateLootcouncil.pendingHandoverTarget == targetOfficer then
            DesolateLootcouncil.pendingHandoverTarget = nil
            DesolateLootcouncil:Print(string.format("Handover to %s timed out.", targetOfficer))
        end
    end, 30)
end

-- ============================================================================
-- Sync Handlers
-- ============================================================================

local function IsItemManagerDesynced(incomingData)
    local db = DesolateLootcouncil.db.profile
    if not db.PriorityLists then return true end

    local incomingListsCount = 0
    for key in pairs(incomingData) do
        incomingListsCount = incomingListsCount + 1
    end
    if #db.PriorityLists ~= incomingListsCount then return true end

    local localLists = {}
    for idx, localList in ipairs(db.PriorityLists) do
        localLists[localList.name] = localList
    end

    for listName, items in pairs(incomingData) do
        local localList = localLists[listName]
        if not localList then return true end

        local localCount = 0
        for id in pairs(localList.items or {}) do
            localCount = localCount + 1
        end
        local incomingCount = 0
        for id in pairs(items or {}) do
            incomingCount = incomingCount + 1
        end

        if localCount ~= incomingCount then return true end

        local normalizedLocal = {}
        for localId, localVal in pairs(localList.items or {}) do
            normalizedLocal[tonumber(localId) or localId] = localVal
        end

        for id, val in pairs(items or {}) do
            local numId = tonumber(id) or id
            if normalizedLocal[numId] ~= val then
                return true
            end
        end
    end
    return false
end

local function OverwriteItemManagerLists(data, logMessage)
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists then
        for listName, items in pairs(data) do
            for idx, localList in ipairs(db.PriorityLists) do
                if localList.name == listName then
                    localList.items = {}
                    for id, val in pairs(items or {}) do
                        localList.items[tonumber(id) or id] = val
                    end
                    DesolateLootcouncil.API:MarkIMDirty(localList.name)
                    break
                end
            end
        end

        if logMessage then
            DesolateLootcouncil:Print(logMessage)
        end

        local ItemMgr = DesolateLootcouncil:GetModule("UI_ItemManager")
        if ItemMgr and ItemMgr.frame and (ItemMgr.frame --[[@as any]]).frame:IsShown() then
            ItemMgr:RefreshWindow()
        end
    end
end

function SyncHandlers:IM_SYNC(payload, sender)
    if not payload or type(payload) ~= "table" then return end

    local data = payload.lists or payload
    local isManual = (payload.isManual == true) or (payload.lists == nil)

    if type(data) ~= "table" then return end

    local inRaid = IsInRaid()
    local currentLM = DesolateLootcouncil:DetermineLootMaster()
    local isSenderLM = DesolateLootcouncil:SmartCompare(sender, currentLM)
    local amILM = DesolateLootcouncil:AmILootMaster()

    local shouldOverwrite = false
    local logMessage = nil

    if isManual then
        if not DesolateLootcouncil:SmartCompare(sender, "player") then
            if IsItemManagerDesynced(data) then
                shouldOverwrite = true
                logMessage = "|cff00ffff[Item Manager]|r Synced: Manual database update received from '" .. DesolateLootcouncil:GetDisplayName(sender) .. "'."
            end
        end
    else
        if inRaid and isSenderLM and not amILM then
            if IsItemManagerDesynced(data) then
                shouldOverwrite = true
                logMessage = "|cff00ffff[Item Manager]|r Auto-updated your item database to match Loot Master '" .. DesolateLootcouncil:GetDisplayName(sender) .. "' (detected desync)."
            end
        end
    end

    if shouldOverwrite then
        if not isManual and not DesolateLootcouncil.db.profile.debugMode then
            logMessage = nil
        end
        OverwriteItemManagerLists(data, logMessage)
    elseif inRaid and isSenderLM and not amILM then
        DesolateLootcouncil:DLC_Log("Item Manager is already in sync with Loot Master.")
    end

    if isSenderLM and type(payload) == "table" and payload.timestamps then
        local db = DesolateLootcouncil.db.profile
        db.imTimestamps = db.imTimestamps or {}
        for listName, ts in pairs(payload.timestamps) do
            db.imTimestamps[listName] = ts
        end
    end
end

function SyncHandlers:SYNC_AUTOPASS(data, sender)
    if DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then
        local isActive
        local isHeartbeat = false
        if type(data) == "table" then
            isActive = data.isActive
            isHeartbeat = data.isHeartbeat
        else
            isActive = data
        end

        local changed = (DesolateLootcouncil.sessionAutopassActive ~= isActive)
        DesolateLootcouncil.sessionAutopassActive = isActive

        if not isHeartbeat or changed then
            local status = isActive and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
            if changed or not isHeartbeat then
                DesolateLootcouncil:DLC_Log("Loot Master has " .. status .. " Autopass for this session.")
            end

            local Autopass = DesolateLootcouncil:GetModule("Autopass")
            if Autopass and Autopass.ScanAndAutopassActiveLootRolls then
                Autopass:ScanAndAutopassActiveLootRolls()
            end
        end
    else
        DesolateLootcouncil:DLC_Log(string.format("SYNC_AUTOPASS from non-LM '%s' ignored.", tostring(sender)))
    end
end

function SyncHandlers:SYNC_PRIORITY(payload, sender)
    if not IsInGroup() then return end
    if not DesolateLootcouncil:AmIOfficerOrLM() then return end
    if DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then
        local data = payload.lists or payload
        local Priority = DesolateLootcouncil:GetModule("Priority")
        if Priority and Priority.ReceivePrioritySync then
            Priority:ReceivePrioritySync(data)
        end

        if type(payload) == "table" and payload.timestamps then
            local db = DesolateLootcouncil.db.profile
            db.priorityTimestamps = db.priorityTimestamps or {}
            for listName, ts in pairs(payload.timestamps) do
                db.priorityTimestamps[listName] = ts
            end
        end
    else
        DesolateLootcouncil:DLC_Log(string.format("SYNC_PRIORITY from non-LM '%s' ignored.", tostring(sender)))
    end
end

function SyncHandlers:SYNC_ROSTER(data, sender)
    if not IsInGroup() then return end
    if not DesolateLootcouncil:AmIOfficerOrLM() then return end
    if DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then
        local RosterSys = DesolateLootcouncil:GetModule("Roster")
        if RosterSys and RosterSys.ReceiveRosterSync then
            RosterSys:ReceiveRosterSync(data)
        end
    else
        DesolateLootcouncil:DLC_Log(string.format("SYNC_ROSTER from non-LM '%s' ignored.", tostring(sender)))
    end
end

function SyncHandlers:SYNC_OFFICER_FLAG(data, sender)
    if not IsInGroup() then return end
    if not DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then
        DesolateLootcouncil:DLC_Log(string.format("SYNC_OFFICER_FLAG from non-LM '%s' ignored.", tostring(sender)))
        return
    end
    if not data or not data.name then return end
    
    local RosterSys = DesolateLootcouncil:GetModule("Roster", true)
    if RosterSys then
        RosterSys:SetOfficer(data.name, data.flag)
    end
end

function SyncHandlers:DLC_HEARTBEAT(data, sender)
    if not IsInGroup() then return end
    if not DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then return end
    if not data then return end

    local db = DesolateLootcouncil.db.profile
    local Comm = DesolateLootcouncil:GetModule("Comm", true)

    if data.imTimestamps and Comm then
        db.imTimestamps = db.imTimestamps or {}
        for listName, incomingTs in pairs(data.imTimestamps) do
            local localTs = db.imTimestamps[listName] or 0
            if incomingTs > localTs then
                Comm:SendComm("IM_PULL_REQUEST", { listName = listName }, sender)
            end
        end
    end

    if data.priorityTimestamps and DesolateLootcouncil:AmIOfficerOrLM() and Comm then
        db.priorityTimestamps = db.priorityTimestamps or {}
        for listName, incomingTs in pairs(data.priorityTimestamps) do
            local localTs = db.priorityTimestamps[listName] or 0
            if incomingTs > localTs then
                Comm:SendComm("PRIORITY_PULL_REQUEST", { listName = listName }, sender)
            end
        end
    end
end

function SyncHandlers:IM_PULL_REQUEST(data, sender)
    if not IsInGroup() then return end
    if not DesolateLootcouncil:AmILootMaster() then return end
    if not data or not data.listName then return end

    local db = DesolateLootcouncil.db.profile
    local listObj = nil
    for idx, list in ipairs(db.PriorityLists or {}) do
        if list.name == data.listName then
            listObj = list
            break
        end
    end

    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if listObj and Comm then
        local syncData = { [data.listName] = listObj.items }
        local ts = db.imTimestamps and db.imTimestamps[data.listName] or GetServerTime()
        Comm:SendComm("IM_SYNC", { lists = syncData, isManual = false, timestamps = { [data.listName] = ts } }, sender)
    end
end

function SyncHandlers:PRIORITY_PULL_REQUEST(data, sender)
    if not IsInGroup() then return end
    if not DesolateLootcouncil:AmILootMaster() then return end
    if not data or not data.listName then return end

    local db = DesolateLootcouncil.db.profile
    local rosterEntry = db.MainRoster and db.MainRoster[sender]
    if not rosterEntry or not rosterEntry.isOfficer then
        DesolateLootcouncil:DLC_Log(string.format("PRIORITY_PULL_REQUEST from non-officer '%s' ignored.", tostring(sender)))
        return
    end

    local listObj = nil
    for idx, list in ipairs(db.PriorityLists or {}) do
        if list.name == data.listName then
            listObj = list
            break
        end
    end

    local Comm = DesolateLootcouncil:GetModule("Comm", true)
    if listObj and Comm then
        local playersCopy = {}
        for i, p in ipairs(listObj.players or {}) do playersCopy[i] = p end
        local itemsCopy = {}
        for id, val in pairs(listObj.items or {}) do itemsCopy[id] = val end

        local singleListPayload = {
            { name = listObj.name, players = playersCopy, items = itemsCopy }
        }
        local ts = db.priorityTimestamps and db.priorityTimestamps[data.listName] or GetServerTime()
        Comm:SendComm("SYNC_PRIORITY", { lists = singleListPayload, timestamps = { [data.listName] = ts } }, sender)
    end
end

function SyncHandlers:HISTORY_UPDATE_PUBLIC(data, sender)
    if not DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then return end
    if not data or not data.link then return end
    local db = DesolateLootcouncil.db.profile
    db.session = db.session or {}
    db.session.publicAwardLog = db.session.publicAwardLog or {}

    table.insert(db.session.publicAwardLog, {
        link = data.link,
        winner = data.winner,
        timestamp = data.timestamp
    })

    local Session = DesolateLootcouncil:GetModule("Session")
    if Session then
        Session:SendMessage("DLC_HISTORY_UPDATED", data)
    end
end

function SyncHandlers:HISTORY_UPDATE_OFFICER(data, sender)
    if not IsInGroup() then return end
    if not DesolateLootcouncil:AmIOfficerOrLM() then return end
    if not DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then return end
    if not data or not data.link then return end

    if not DesolateLootcouncil:AmILootMaster() then
        local db = DesolateLootcouncil.db.profile
        db.session = db.session or {}
        db.session.awarded = db.session.awarded or {}

        table.insert(db.session.awarded, {
            link        = data.link,
            texture     = data.texture,
            itemID      = data.itemID,
            winner      = data.winner,
            winnerClass = data.winnerClass,
            voteType    = data.voteType,
            timestamp   = data.timestamp,
            traded      = false
        })

        local Session = DesolateLootcouncil:GetModule("Session")
        if Session then
            Session:SendMessage("DLC_HISTORY_UPDATED", data)
        end
    end
end

function SyncHandlers:TRADE_CONFIRMED(data, sender)
    if not IsInGroup() then return end
    if not DesolateLootcouncil:AmIOfficerOrLM() then return end
    if not DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then return end
    if not data or type(data) ~= "table" then return end

    local db = DesolateLootcouncil.db.profile
    if not db.session or not db.session.awarded then return end

    local changed = false
    for idx, confirm in ipairs(data) do
        local winnerScore = DesolateLootcouncil:GetScoreName(confirm.winner)
        for key, award in ipairs(db.session.awarded) do
            if not award.traded and award.itemID == confirm.itemID and award.timestamp == confirm.timestamp and DesolateLootcouncil:GetScoreName(award.winner) == winnerScore then
                award.traded = true
                changed = true
                break
            end
        end
    end

    if changed then
        local Session = DesolateLootcouncil:GetModule("Session")
        if Session then
            Session:SendMessage("DLC_HISTORY_UPDATED")
        end
    end
end

function SyncHandlers:HISTORY_BULK_SYNC(data, sender)
    if not IsInGroup() then return end
    if not DesolateLootcouncil:AmIOfficerOrLM() then return end
    if not DesolateLootcouncil:SmartCompare(sender, DesolateLootcouncil:DetermineLootMaster()) then return end
    if not data or type(data) ~= "table" then return end

    local db = DesolateLootcouncil.db.profile
    db.session = db.session or {}
    db.session.awarded = db.session.awarded or {}

    for idx, entry in ipairs(data) do
        local isDup = false
        for key, existing in ipairs(db.session.awarded) do
            if existing.link == entry.link and existing.timestamp == entry.timestamp then
                isDup = true
                break
            end
        end
        if not isDup then
            table.insert(db.session.awarded, {
                link        = entry.link,
                texture     = entry.texture,
                itemID      = entry.itemID,
                winner      = entry.winner,
                winnerClass = entry.winnerClass,
                voteType    = entry.voteType,
                timestamp   = entry.timestamp,
                traded      = entry.traded == true
            })
        end
    end

    local Session = DesolateLootcouncil:GetModule("Session")
    if Session then
        Session:SendMessage("DLC_HISTORY_UPDATED")
    end
end

function SyncHandlers:LURA_TEST_START(data, sender)
    local Lura = DesolateLootcouncil:GetModule("UI_LuraWidget", true)
    if Lura and Lura.ActivateGlobalTestMode then Lura:ActivateGlobalTestMode() end
end

function SyncHandlers:LURA_TEST_END(data, sender)
    local Lura = DesolateLootcouncil:GetModule("UI_LuraWidget", true)
    if Lura and Lura.DeactivateGlobalTestMode then Lura:DeactivateGlobalTestMode() end
end

function SyncHandlers:LM_HANDOVER_OFFER(state, sender)
    if not IsInGroup() then return end
    
    local isAuthorized = false
    local currentLM = DesolateLootcouncil.activeLootMaster
    local currentRL = DesolateLootcouncil:GetGroupLeader()
    if DesolateLootcouncil:SmartCompare(sender, currentLM) or DesolateLootcouncil:SmartCompare(sender, currentRL) then
        isAuthorized = true
    end
    if not isAuthorized then
        DesolateLootcouncil:DLC_Log(string.format("Ignored LM_HANDOVER_OFFER from unauthorized sender: %s", sender))
        return
    end

    DesolateLootcouncil.pendingHandoverState = state
    DesolateLootcouncil.pendingHandoverSender = sender

    local amILeader = DesolateLootcouncil:SmartCompare(currentRL, "player")
    if amILeader then
        local Session = DesolateLootcouncil:GetModule("Session")
        if Session and Session.AcceptHandover then
            Session:AcceptHandover(true)
        end
    else
        StaticPopup_Show("DLC_CONFIRM_LM_HANDOVER", DesolateLootcouncil:GetDisplayName(sender))
    end
end

function SyncHandlers:LM_HANDOVER_ACCEPTED(data, sender)
    if not IsInGroup() then return end
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.HandleHandoverAccepted then
        Session:HandleHandoverAccepted(sender)
    end
end

function SyncHandlers:LM_HANDOVER_DECLINED(data, sender)
    if not IsInGroup() then return end
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.HandleHandoverDeclined then
        Session:HandleHandoverDeclined(sender)
    end
end

function SyncHandlers:LM_UPDATE_CONFIGURED(payload, sender)
    if not IsInGroup() then return end
    local Session = DesolateLootcouncil:GetModule("Session")
    if Session and Session.HandleUpdateConfigured then
        Session:HandleUpdateConfigured(payload, sender)
    end
end
