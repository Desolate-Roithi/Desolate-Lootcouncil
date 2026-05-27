local _, AT = ...
if AT.abortLoad then return end

---@class UI_Voting : AceModule
local UI_Voting = DesolateLootcouncil:NewModule("UI_Voting", "AceEvent-3.0")
local AceGUI = LibStub("AceGUI-3.0")

-- File-scope constants: defined once, shared across all calls to ShowVotingWindow.
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")
local VOTE_TEXT  = { [1] = L["Bid"], [2] = L["Roll"], [3] = L["Offspec"], [4] = L["T-Mog"], [5] = L["Pass"] }
local VOTE_COLOR = {
    [1] = "|cff00ff00", [2] = "|cffffd700",
    [3] = "|cff00ffff", [4] = "|cffeda55f", [5] = "|cffaaaaaa"
}

-- Module-level tooltip helper: one function shared by all item rows.
local function ShowItemTooltip(widget, link)
    if not link then return end
    GameTooltip:SetOwner((widget --[[@as any]]).frame, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

---@class (partial) DLC_Ref_UIVoting : AceAddon
---@field db table
---@field RestoreFramePosition fun(self: DLC_Ref_UIVoting, frame: any, windowName: string)
---@field SaveFramePosition fun(self: DLC_Ref_UIVoting, frame: any, windowName: string)
---@field Persistence table
---@field activeLootMaster string
---@field amILM boolean

---@type DLC_Ref_UIVoting
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_UIVoting]]

local function FormatTime(seconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

function UI_Voting:CreateVotingFrame()
    ---@type AceGUIFrame
    local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
    frame:SetTitle(L["Loot Vote"])
    frame:SetLayout("Fill")
    frame:EnableResize(false)
    frame:SetWidth(800)
    frame:SetHeight(450)
    frame:SetCallback("OnClose", function(widget)
        if self.votingTicker then self.votingTicker:Cancel() end
        self:CancelAllTimers()
        widget:Hide()
    end)
    self.votingFrame = frame

    -- Style the frame with the active theme
    local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme", true)
    if UI_Theme then
        UI_Theme:ApplyTheme(frame)
    end

    -- Position Persistence
    DesolateLootcouncil:MakeMovableWithSave(frame, "Voting")

    self.myVotes = self.myVotes or {}
    self.myNotes = self.myNotes or {}
    self.noteExpanded = self.noteExpanded or {}
    self.timerLabels = {}
    self.expirationTimers = {} -- Store expiration triggers
end

function UI_Voting:CancelAllTimers()
    if self.expirationTimers then
        for _, t in ipairs(self.expirationTimers) do
            if t then t:Cancel() end
        end
    end
    self.expirationTimers = {}
end

function UI_Voting:RemoveVotingItem(guid)
    -- 1. Remove from Data
    if self.cachedVotingItems then
        for i, item in ipairs(self.cachedVotingItems) do
            if (item.sourceGUID or item.link) == guid then
                table.remove(self.cachedVotingItems, i)
                break
            end
        end
    end
    -- 2. Full Refresh
    if self.cachedVotingItems and #self.cachedVotingItems == 0 then
        if self.votingFrame then self.votingFrame:Hide() end
        return
    end
    self:ShowVotingWindow(nil, true)
end

function UI_Voting:ResetVoting()
    self.myVotes = {}
    self.myNotes = {}
    self.noteExpanded = {}
    self.cachedVotingItems = {}
    if self.votingFrame then self.votingFrame:Hide() end
end

function UI_Voting:ShowVotingWindow(lootTable, isRefresh)
    if not self.votingFrame then self:CreateVotingFrame() end

    local API = DesolateLootcouncil.API

    -- Sync confirmed votes from Session
    self.myVotes = API:GetLocalVotes()
    self.myNotes = self.myNotes or {}
    self.noteExpanded = self.noteExpanded or {}

    -- New Session Data
    if lootTable then
        self.cachedVotingItems = lootTable
        self.myVotes = self.myVotes or {}
    end
    -- Build a set of awarded GUIDs so we can skip items already distributed
    local awardedGUIDs = API:GetAwardedGUIDs()

    local items = self.cachedVotingItems
    if not items then return end

    if not isRefresh then
        self.votingFrame:Show()
        -- Ensure window is maximized if it was previously collapsed
        local frame = (self.votingFrame --[[@as any]]).frame
        if frame then
            frame.startCollapsed = nil -- Cancel initial hook timer
            if frame.isCollapsed then
                DesolateLootcouncil.Persistence:ToggleWindowCollapse(self.votingFrame)
            end
        end
    elseif not (self.votingFrame.frame and self.votingFrame.frame:IsShown()) then
        return -- Don't force pop up if the user manually hid it
    end

    self.votingFrame:ReleaseChildren()
    self.timerLabels = {}

    -- Cancel old timers
    if self.votingTicker then self.votingTicker:Cancel() end
    self:CancelAllTimers()

    -- 1. Ticker (Visual Only)
    self.votingTicker = C_Timer.NewTicker(0.5, function()
        local now = GetServerTime()
        for guid, info in pairs(self.timerLabels) do
            if info.label and info.label.frame and info.label.SetText then
                local remaining = (info.expiry or 0) - now
                local isClosed  = API:IsItemClosed(guid)

                if isClosed or remaining <= 0 then
                    info.label:SetText("|cffff0000" .. L["Closed"] .. "|r")
                else
                    info.label:SetText(FormatTime(remaining))
                end
            end
        end
    end)

    -- 2. Build Layout
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)

    -- Style the ScrollFrame background using active theme
    local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme", true)
    if UI_Theme then
        UI_Theme:ApplyTheme(scroll)
    end

    -- Preserve Scroll Status on Refresh
    if not self.scrollStatus or not isRefresh then
        self.scrollStatus = { scrollvalue = 0 }
    end
    scroll:SetStatusTable(self.scrollStatus)

    self.votingFrame:AddChild(scroll)
    self.scrollContainer = scroll

    local now = GetServerTime()

    for i = #items, 1, -1 do
        local data = items[i]
        local guid = data.sourceGUID or data.link
        if not awardedGUIDs[guid] then
            local currentVote = self.myVotes[guid]
            local isClosed    = API:IsItemClosed(guid)
            local remaining   = (data.expiry or 0) - now
            local isExpired   = (remaining <= 0)
            local isPending   = (API:GetOutboundVote(guid) ~= nil)

            -- Schedule a forced refresh exactly when the item expires
            if not isClosed and not isExpired and remaining > 0 then
                local t = C_Timer.NewTimer(remaining, function()
                    self:ShowVotingWindow(nil, true)
                end)
                table.insert(self.expirationTimers, t)
            end

            self:CreateItemRow(
                scroll, data, guid,
                currentVote, isClosed, isExpired, isPending
            )
        end
    end

    -- Add a small spacer at the bottom
    ---@type AceGUILabel
    local spacer = AceGUI:Create("Label") --[[@as AceGUILabel]]
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    scroll:AddChild(spacer)

    self.votingFrame:DoLayout()
end

--- Private helper: renders one full item row into the scroll container.
function UI_Voting:CreateItemRow(scroll, data, guid, currentVote, isClosed, isExpired, isPending)
    local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme", true)

    -- Container for the entire row (holds both the main row and expanded note input)
    ---@type AceGUISimpleGroup
    local rowGroup = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    rowGroup:SetLayout("List")
    rowGroup:SetFullWidth(true)
    scroll:AddChild(rowGroup)

    -- Top Part: Icon, Link, Timer, and Action Buttons
    ---@type AceGUISimpleGroup
    local mainRow = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    mainRow:SetLayout("Flow")
    mainRow:SetFullWidth(true)
    rowGroup:AddChild(mainRow)

    -- Icon
    ---@type AceGUIIcon
    local itemIcon = AceGUI:Create("Icon")
    itemIcon:SetImage(data.texture or (data.itemID and C_Item.GetItemIconByID(data.itemID)) or 134400)
    itemIcon:SetImageSize(24, 24)
    itemIcon:SetRelativeWidth(0.05)
    itemIcon:SetCallback("OnClick",  function() ShowItemTooltip(itemIcon, data.link) end)
    itemIcon:SetCallback("OnEnter",  function() ShowItemTooltip(itemIcon, data.link) end)
    itemIcon:SetCallback("OnLeave",  function() GameTooltip:Hide() end)
    mainRow:AddChild(itemIcon)

    -- Item link label
    ---@type AceGUIInteractiveLabel
    local itemLabel = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
    local _, properLink = C_Item.GetItemInfo(data.link)
    if not properLink then
        local itemObj = Item:CreateFromItemID(data.itemID)
        if not itemObj:IsItemEmpty() then
            itemObj:ContinueOnItemLoad(function() self:ShowVotingWindow(nil, true) end)
        end
        itemLabel:SetText(L["Loading..."])
    else
        itemLabel:SetText(properLink)
        itemIcon:SetImage(C_Item.GetItemIconByID(data.itemID) or 134400)
    end
    itemLabel:SetRelativeWidth(0.25)
    itemLabel:SetCallback("OnEnter", function(w) ShowItemTooltip(w, data.link) end)
    itemLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    mainRow:AddChild(itemLabel)

    -- Timer label
    ---@type AceGUILabel
    local timerLbl = AceGUI:Create("Label") --[[@as AceGUILabel]]
    timerLbl:SetText("...")
    timerLbl:SetRelativeWidth(0.06)
    mainRow:AddChild(timerLbl)
    self.timerLabels[guid] = { label = timerLbl, expiry = data.expiry }

    -- Action group
    ---@type AceGUISimpleGroup
    local actionGroup = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    actionGroup:SetLayout("Flow")
    actionGroup:SetRelativeWidth(0.64)
    mainRow:AddChild(actionGroup)

    if isClosed or isExpired then
        -- STATE 4: Closed / Expired
        local votedText = L["You voted: |cffaaaaaaAuto Pass|r"]
        if currentVote then
            local voteVal = type(currentVote) == "table" and currentVote.type or currentVote
            local noteText = type(currentVote) == "table" and currentVote.note and currentVote.note ~= "" and (" (" .. currentVote.note .. ")") or ""
            votedText = string.format(L["You voted: %s%s|r%s"], (VOTE_COLOR[voteVal] or "|cffffffff"), (VOTE_TEXT[voteVal] or "?"), noteText)
        end
        local res = AceGUI:Create("Label") --[[@as AceGUILabel]]
        res:SetText(votedText) ; res:SetWidth(280)
        actionGroup:AddChild(res)
        
        local btn = AceGUI:Create("Button") --[[@as AceGUIButton]]
        btn:SetText(L["Closed"]) ; btn:SetWidth(100) ; btn:SetDisabled(true)
        actionGroup:AddChild(btn)
        if UI_Theme then UI_Theme:ApplyTheme(btn) end

    elseif isPending then
        -- STATE 2: Vote sent, awaiting ACK
        local outbound   = DesolateLootcouncil.API:GetOutboundVote(guid)
        local pendingType = outbound and outbound.type
        local vText  = pendingType and VOTE_TEXT[pendingType]  or "?"
        local vColor = pendingType and VOTE_COLOR[pendingType] or "|cffffffff"
        local noteText = self.myNotes[guid] and self.myNotes[guid] ~= "" and (" (" .. self.myNotes[guid] .. ")") or ""
        local res = AceGUI:Create("Label") --[[@as AceGUILabel]]
        res:SetText(string.format(L["Voted: %s%s|r%s"], vColor, vText, noteText)) ; res:SetWidth(280)
        actionGroup:AddChild(res)
        
        local syncBtn = AceGUI:Create("Button") --[[@as AceGUIButton]]
        syncBtn:SetText(L["Syncing..."]) ; syncBtn:SetWidth(100) ; syncBtn:SetDisabled(true)
        actionGroup:AddChild(syncBtn)
        if UI_Theme then UI_Theme:ApplyTheme(syncBtn) end

    elseif currentVote then
        -- STATE 3: Voted & confirmed
        local voteVal = type(currentVote) == "table" and currentVote.type or currentVote
        local noteText = type(currentVote) == "table" and currentVote.note and currentVote.note ~= "" and (" (" .. currentVote.note .. ")") or ""
        local res = AceGUI:Create("Label") --[[@as AceGUILabel]]
        res:SetText(string.format(L["Voted: %s%s|r%s"], (VOTE_COLOR[voteVal] or "|cffffffff"), (VOTE_TEXT[voteVal] or "?"), noteText))
        res:SetWidth(280)
        actionGroup:AddChild(res)
        
        local change = AceGUI:Create("Button") --[[@as AceGUIButton]]
        change:SetText(L["Change"]) ; change:SetWidth(100)
        change:SetCallback("OnClick", function()
            self.myVotes[guid] = nil
            DesolateLootcouncil.API:CancelVote(guid)
            self:ShowVotingWindow(nil, true)
        end)
        actionGroup:AddChild(change)
        if UI_Theme then UI_Theme:ApplyTheme(change) end

    else
        -- STATE 1: Open, no vote yet
        local function CastVote(val)
            self.myVotes[guid] = val
            local note = self.myNotes[guid] or ""
            DesolateLootcouncil.API:SendVote(guid, val, note)
            self:ShowVotingWindow(nil, true)
        end
        local w = 68
        local BUTTONS = {
            { VOTE_TEXT[1], 1 }, { VOTE_TEXT[2], 2 },
            { VOTE_TEXT[3], 3 }, { VOTE_TEXT[4], 4 }, { VOTE_TEXT[5], 5 }
        }
        for _, bd in ipairs(BUTTONS) do
            local btn = AceGUI:Create("Button") --[[@as AceGUIButton]]
            btn:SetText(bd[1]) ; btn:SetWidth(w)
            btn:SetCallback("OnClick", function() CastVote(bd[2]) end)
            actionGroup:AddChild(btn)
            if UI_Theme then UI_Theme:ApplyTheme(btn) end
        end

        -- Clickable Note Toggle Button (Note icon context)
        local noteBtn = AceGUI:Create("Button") --[[@as AceGUIButton]]
        noteBtn:SetText(self.noteExpanded[guid] and "[-] Note" or "[+] Note")
        noteBtn:SetWidth(60)
        noteBtn:SetCallback("OnClick", function()
            self.noteExpanded[guid] = not self.noteExpanded[guid]
            self:ShowVotingWindow(nil, true)
        end)
        actionGroup:AddChild(noteBtn)
        if UI_Theme then UI_Theme:ApplyTheme(noteBtn) end
    end

    -- Render Expanded Inline Note Input Field directly below row
    if not isClosed and not isExpired and not isPending and not currentVote and self.noteExpanded[guid] then
        ---@type AceGUIEditBox
        local noteEdit = AceGUI:Create("EditBox") --[[@as AceGUIEditBox]]
        noteEdit:SetLabel(L["Add note to Loot Master..."])
        noteEdit:SetText(self.myNotes[guid] or "")
        noteEdit:SetFullWidth(true)
        noteEdit:SetCallback("OnTextChanged", function(_, _, text)
            self.myNotes[guid] = text
        end)
        rowGroup:AddChild(noteEdit)
        if UI_Theme then
            UI_Theme:ApplyTheme(noteEdit)
        end
    end
end

function UI_Voting:OnEnable()
    self:RegisterMessage("DLC_SESSION_STARTED", "OnSessionStarted")
    self:RegisterMessage("DLC_SESSION_STOPPED", "OnSessionStopped")
    self:RegisterMessage("DLC_SESSION_RESTORED", "OnSessionRestored")
    self:RegisterMessage("DLC_ITEM_CLOSED", "OnItemClosed")
    self:RegisterMessage("DLC_ITEM_REMOVED", "OnItemRemoved")
end

function UI_Voting:OnSessionStarted(eventName, cleanList, isLM)
    self:ShowVotingWindow(cleanList)
end

function UI_Voting:OnSessionStopped()
    self:ResetVoting()
end

function UI_Voting:OnSessionRestored(eventName, clientLootList, isLM)
    self:ShowVotingWindow(clientLootList)
end

function UI_Voting:OnItemClosed(eventName, guid)
    self:ShowVotingWindow(nil, true)
end

function UI_Voting:OnItemRemoved(eventName, guid)
    self:RemoveVotingItem(guid)
end
