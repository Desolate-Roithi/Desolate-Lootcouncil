local _, AT = ...
if AT.abortLoad then return end

---@class UI_Voting : AceModule
local UI_Voting = DesolateLootcouncil:NewModule("UI_Voting", "AceEvent-3.0")

-- File-scope constants: defined once, shared across all calls to ShowVotingWindow.
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")
local VOTE_TEXT  = { [1] = L["Bid"], [2] = L["Roll"], [3] = L["Offspec"], [4] = L["T-Mog"], [5] = L["Pass"] }
local VOTE_COLOR = setmetatable({}, {
    __index = function(_, key)
        local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
        local vc = NativeGUI and NativeGUI.VOTE_COLORS and NativeGUI.VOTE_COLORS[key]
        return vc and vc.hex or "|cffffffff"
    end
})

local function GetVoteText(guid, voteVal)
    if not voteVal then return "?" end
    local isRecipe = false
    local session = DesolateLootcouncil.db.profile.session
    local bidding = session and session.bidding
    local itemID
    if bidding then
        for _, item in ipairs(bidding) do
            if (item.sourceGUID or item.link) == guid then
                itemID = item.link or item.itemID
                break
            end
        end
    end
    if not itemID then
        local SessionInfo = DesolateLootcouncil:GetModule("Session")
        local clientList = SessionInfo and SessionInfo.clientLootList
        if clientList then
            for _, item in ipairs(clientList) do
                if (item.sourceGUID or item.link) == guid then
                    itemID = item.link or item.itemID
                    break
                end
            end
        end
    end
    if not itemID then
        local cached = UI_Voting.cachedVotingItems
        if cached then
            for _, item in ipairs(cached) do
                if (item.sourceGUID or item.link) == guid then
                    itemID = item.link or item.itemID
                    break
                end
            end
        end
    end
    if itemID and DesolateLootcouncil.API:IsRecipe(itemID) then
        isRecipe = true
    end

    if isRecipe then
        if voteVal == 2 then
            return L["Ready to Craft"]
        elseif voteVal == 3 then
            return L["Unskilled"]
        end
    end
    return VOTE_TEXT[voteVal] or "?"
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

-- Thresholds at which a countdown reminder is sent (seconds remaining)
local VOTE_REMINDER_THRESHOLDS = { 240, 180, 120, 60, 30 }

--- Start a background milestone ticker that fires reminder messages at defined
--- Processes background autopass and countdown reminders for a single item.
---@param item table  The item being processed
---@param now number  The current absolute server timestamp
---@return number|nil lowestThreshold  The crossed reminder threshold, if any
---@return boolean shouldAddPending  True if the player hasn't voted and a threshold was crossed
function UI_Voting:_ProcessMilestoneItem(item, now)
    local API = DesolateLootcouncil.API
    local guid = item.sourceGUID or item.link
    local isClosed = API:IsItemClosed(guid)
    local hasVoted = self.myVotes and self.myVotes[guid]

    if isClosed or not item.expiry or item.expiry <= 0 then
        return nil, false
    end

    local remaining = item.expiry - now

    if not self.announcedMilestones[guid] then
        self.announcedMilestones[guid] = {}
        -- Pre-initialize already-passed thresholds on first track / reload
        for _, threshold in ipairs(VOTE_REMINDER_THRESHOLDS) do
            if remaining < threshold then
                self.announcedMilestones[guid][threshold] = true
            end
        end
    end

    -- Background Autopass evaluation (when window is closed/hidden)
    local isPending = (API:GetOutboundVote(guid) ~= nil)
    if remaining <= -3 and not hasVoted and not isPending then
        API:SendVote(guid, 5, "")
        hasVoted = 5
    end

    for _, threshold in ipairs(VOTE_REMINDER_THRESHOLDS) do
        if remaining > 0 and remaining <= threshold
                and not self.announcedMilestones[guid][threshold] then
            -- Always mark as announced so we never re-fire this threshold
            self.announcedMilestones[guid][threshold] = true

            if not hasVoted then
                return threshold, true
            end
            break -- only the first unannounced threshold per item per tick
        end
    end

    return nil, false
end

--- countdown thresholds (4min, 3min, 2min, 1min, 30sec). Safe to call multiple
--- times — a no-op if the ticker is already running.
function UI_Voting:StartMilestoneChecker()
    if self.milestoneTicker then return end

    -- Per-item threshold announcement tracking and global dedup timestamp
    self.announcedMilestones = self.announcedMilestones or {}
    self.lastReminderSentAt  = self.lastReminderSentAt  or 0

    self.milestoneTicker = C_Timer.NewTicker(5, function()
        local items = self.cachedVotingItems
        if not items or #items == 0 then
            if self.milestoneTicker then
                self.milestoneTicker:Cancel()
                self.milestoneTicker = nil
            end
            return
        end

        local now            = GetServerTime()
        local pendingItems   = {}   -- unvoted items crossing a threshold this tick
        local lowestThreshold = nil -- most urgent threshold crossed

        for _, item in ipairs(items) do
            local threshold, shouldAdd = self:_ProcessMilestoneItem(item, now)
            if shouldAdd and threshold then
                lowestThreshold = (not lowestThreshold or threshold < lowestThreshold) and threshold or lowestThreshold
                table.insert(pendingItems, item)
            end
        end

        -- Emit one combined message for this tick, respecting the 30s dedup window
        if #pendingItems > 0 and (now - self.lastReminderSentAt) >= 30 then
            local frameShown = self.votingFrame and self.votingFrame:IsShown() and not self.votingFrame.isCollapsed
            if not frameShown then
                local timeLabel
                if lowestThreshold >= 60 then
                    timeLabel = string.format("|cffff8000%d %s|r",
                        lowestThreshold / 60, L["min"])
                else
                    timeLabel = string.format("|cffff0000%d %s|r",
                        lowestThreshold, L["sec"])
                end

                local links = {}
                for _, item in ipairs(pendingItems) do
                    table.insert(links, item.link or "???")
                end
                DesolateLootcouncil:Print(string.format(
                    L["|cffff8000Vote closing in %s \226\128\148 still need your vote:|r %s"],
                    timeLabel, table.concat(links, ", ")
                ))
                self.lastReminderSentAt = now
            end
        end

        -- Auto show and expand if lowestThreshold is 30s or less
        if lowestThreshold and lowestThreshold <= 30 then
            local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
            if not self.votingFrame then self:CreateVotingFrame() end
            if not self.votingFrame:IsShown() then
                self:ShowVotingWindow()
            end
            if self.votingFrame.isCollapsed then
                NativeGUI:ExpandWindow(self.votingFrame, "Voting")
            end
        end
    end)
end

--- Stop and discard the milestone ticker and its state.
function UI_Voting:StopMilestoneChecker()
    if self.milestoneTicker then
        self.milestoneTicker:Cancel()
        self.milestoneTicker = nil
    end
    self.announcedMilestones = nil
    self.lastReminderSentAt  = nil
end

function UI_Voting:CreateVotingFrame()
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local frame = NativeGUI:CreateWindow("DLCVotingFrame", L["Loot Vote"], "Voting")

    frame.OnCollapse = function()
        if self.scrollFrame then self.scrollFrame:Hide() end
    end
    frame.OnExpand = function()
        self:ShowVotingWindow(nil, true)
    end

    frame:HookScript("OnHide", function()
        if self.votingTicker then self.votingTicker:Cancel() end
        self:CancelAllTimers()

        -- Immediate one-time message if the player closes with unvoted items still open
        local items = self.cachedVotingItems
        if not items or #items == 0 then return end

        local now = GetServerTime()
        local API = DesolateLootcouncil.API
        for _, item in ipairs(items) do
            local guid      = item.sourceGUID or item.link
            local remaining = (item.expiry or 0) - now
            local isClosed  = API:IsItemClosed(guid)
            local isExpired = (item.expiry and item.expiry > 0) and (remaining <= 0)
            if not self.myVotes[guid] and not isClosed and not isExpired then
                DesolateLootcouncil:Print(L["You have outstanding loot votes! Type /dlc vote to reopen."])
                break
            end
        end
        -- Milestone ticker keeps running in the background
    end)

    self.votingFrame = frame
    self.myVotes = self.myVotes or {}
    self.myNotes = self.myNotes or {}
    self.noteExpanded = self.noteExpanded or {}
    self.timerLabels = {}
    self.expirationTimers = {}
    self.rowPool = {}
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
    if not self.cachedVotingItems then return end
    for i, item in ipairs(self.cachedVotingItems) do
        if (item.sourceGUID or item.link) == guid then
            table.remove(self.cachedVotingItems, i)
            -- Clear milestone state for this item so thresholds won't fire for it
            if self.announcedMilestones then
                self.announcedMilestones[guid] = nil
            end
            break
        end
    end
    if #self.cachedVotingItems == 0 then
        if self.votingFrame then self.votingFrame:Hide() end
        self:StopMilestoneChecker()
        return
    end
    self:ShowVotingWindow(nil, true)
end

function UI_Voting:ResetVoting()
    self:StopMilestoneChecker()
    self.myVotes = {}
    self.myNotes = {}
    self.noteExpanded = {}
    self.cachedVotingItems = {}
    if self.votingFrame then self.votingFrame:Hide() end
    if self.rowPool then
        for _, r in ipairs(self.rowPool) do r:Hide() end
    end
end

local function SetupVotingTicker(self, API)
    if self.votingTicker then self.votingTicker:Cancel() end
    self.votingTicker = C_Timer.NewTicker(0.5, function()
        local now = GetServerTime()
        for guid, info in pairs(self.timerLabels) do
            if info.fontString then
                local remaining = (info.expiry or 0) - now
                local isClosed  = API:IsItemClosed(guid)
                local txt = (isClosed or remaining <= 0) and ("|cffff0000" .. L["Closed"] .. "|r") or FormatTime(remaining)
                info.fontString:SetText(txt)
            end
        end
    end)
end

local function RebuildScrollLayout(self, rowCount)
    local totalHeight = 0
    for k = 1, rowCount do
        local r = self.rowPool[k]
        if r and r:IsShown() then
            totalHeight = totalHeight + r:GetHeight() + 10
        end
    end
    if self.scrollContent then
        self.scrollContent:SetHeight(totalHeight)
    end
end

--- Processes the layout, timer tracking, and auto-pass logic for a single voting row.
---@param index number  The sequential row index to display this item at
---@param data table  The item data table
---@param guid string  The unique identifier for the item
---@param now number  The current absolute server timestamp
---@param awardedGUIDs table<string, boolean>  A map of already awarded item GUIDs
---@return boolean laidOut  True if the row was successfully processed and laid out
function UI_Voting:_LayoutVotingRow(index, data, guid, now, awardedGUIDs)
    if awardedGUIDs[guid] then return false end

    local API = DesolateLootcouncil.API
    local currentVote = self.myVotes[guid]
    local isClosed    = API:IsItemClosed(guid)
    local expiry      = data.expiry or 0
    local remaining   = expiry - now
    local isExpired   = (expiry > 0) and (remaining <= 0)
    local shouldAutoPass = (expiry > 0) and (remaining <= -3)
    local isPending   = (API:GetOutboundVote(guid) ~= nil)

    if shouldAutoPass and not currentVote and not isPending and not isClosed then
        -- Automatically send an Auto Pass vote to the Loot Master
        DesolateLootcouncil.API:SendVote(guid, 5, "")
        currentVote = self.myVotes[guid] or { type = 5, note = "", roll = 100 }
    end

    if not isClosed and not isExpired and expiry > 0 and remaining > 0 then
        local t = C_Timer.NewTimer(remaining, function()
            self:ShowVotingWindow(nil, true)
        end)
        table.insert(self.expirationTimers, t)
    end

    self:CreateItemRow(
        index, data, guid,
        currentVote, isClosed, isExpired, isPending
    )
    return true
end

function UI_Voting:ShowVotingWindow(lootTable, isRefresh)
    -- Milestone checker is purely data-driven; never touch it here.
    if not self.votingFrame then self:CreateVotingFrame() end

    local API = DesolateLootcouncil.API
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    self.myVotes = API:GetLocalVotes()
    self.myNotes = self.myNotes or {}
    self.noteExpanded = self.noteExpanded or {}

    if lootTable then
        self.cachedVotingItems = lootTable
        self.myVotes = self.myVotes or {}
        -- New session: reset milestone state so all thresholds fire fresh
        self.announcedMilestones = {}
        self.lastReminderSentAt  = 0
        self:StartMilestoneChecker()
        if self.votingFrame.isCollapsed then
            NativeGUI:ExpandWindow(self.votingFrame, "Voting")
        end
    end
    local awardedGUIDs = API:GetAwardedGUIDs()

    local items = self.cachedVotingItems
    if not items then return end

    if not isRefresh then
        self.votingFrame:Show()
    elseif not self.votingFrame:IsShown() then
        return
    end

    if self.votingTicker then self.votingTicker:Cancel() end
    self:CancelAllTimers()
    self.timerLabels = {}

    for _, row in ipairs(self.rowPool) do
        row:Hide()
        row:ClearAllPoints()
    end

    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.votingFrame, -50, -16)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    if self.votingFrame.isCollapsed then
        self.scrollFrame:Hide()
    else
        self.scrollFrame:Show()
        self.scrollContent:Show()
        NativeGUI:StyleScrollBar(self.scrollFrame)
    end

    SetupVotingTicker(self, API)

    local now = GetServerTime()
    local rowCount = 0

    for i = #items, 1, -1 do
        local data = items[i]
        local guid = data.sourceGUID or data.link
        if self:_LayoutVotingRow(rowCount + 1, data, guid, now, awardedGUIDs) then
            rowCount = rowCount + 1
        end
    end

    RebuildScrollLayout(self, rowCount)
end

function UI_Voting:CreateItemIcon(row, data, rowHeight)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local offsetY = (rowHeight == 92) and 24 or 0
    NativeGUI:SetupItemIconButton(row, data, 28, 12, offsetY)
end

function UI_Voting:StyleClosedExpiredState(row, theme, currentVote, guid)
    row.timerLbl:Hide()

    local votedText = L["You voted: |cffaaaaaaAuto Pass|r"]
    if currentVote then
        local voteVal = type(currentVote) == "table" and currentVote.type or currentVote
        local noteText = type(currentVote) == "table" and currentVote.note and currentVote.note ~= "" and (" (" .. currentVote.note .. ")") or ""
        votedText = string.format(L["You voted: %s%s|r%s"], (VOTE_COLOR[voteVal] or "|cffffffff"), GetVoteText(guid, voteVal), noteText)
    end

    row.statusBtn:SetText(L["Closed"])
    row.statusBtn:SetEnabled(false)
    row.statusBtn:SetBackdropColor(unpack(theme.buttonBg))
    row.statusBtn:SetBackdropBorderColor(theme.border[1] * 0.3, theme.border[2] * 0.3, theme.border[3] * 0.3, 0.4)
    row.statusBtn:SetScript("OnClick", nil)
    row.statusBtn:Show()

    row.statusText:SetText(votedText)
    row.statusText:SetPoint("LEFT", row.actionFrame, "LEFT", 0, 0)
    row.statusText:SetPoint("RIGHT", row.statusBtn, "LEFT", -10, 0)
    row.statusText:Show()
end

function UI_Voting:StylePendingState(row, theme, guid)
    row.timerLbl:Show()

    local outbound   = DesolateLootcouncil.API:GetOutboundVote(guid)
    local pendingType = outbound and outbound.type
    local vText  = pendingType and GetVoteText(guid, pendingType)  or "?"
    local vColor = pendingType and VOTE_COLOR[pendingType] or "|cffffffff"
    local noteText = self.myNotes[guid] and self.myNotes[guid] ~= "" and (" (" .. self.myNotes[guid] .. ")") or ""

    row.statusBtn:SetText(L["Syncing..."])
    row.statusBtn:SetEnabled(false)
    row.statusBtn:SetBackdropColor(unpack(theme.buttonBg))
    row.statusBtn:SetBackdropBorderColor(theme.border[1] * 0.3, theme.border[2] * 0.3, theme.border[3] * 0.3, 0.4)
    row.statusBtn:SetScript("OnClick", nil)
    row.statusBtn:Show()

    row.statusText:SetText(string.format(L["Voted: %s%s|r"] .. "%s", vColor, vText, noteText))
    row.statusText:SetPoint("LEFT", row.timerLbl, "RIGHT", 8, 0)
    row.statusText:SetPoint("RIGHT", row.statusBtn, "LEFT", -10, 0)
    row.statusText:Show()
end

function UI_Voting:StyleVotedChangeState(row, theme, guid, currentVote)
    row.timerLbl:Show()

    local voteVal = type(currentVote) == "table" and currentVote.type or currentVote
    local noteText = type(currentVote) == "table" and currentVote.note and currentVote.note ~= "" and (" (" .. currentVote.note .. ")") or ""

    row.statusBtn:SetText(L["Change"])
    row.statusBtn:SetEnabled(true)
    local btnTheme = row.statusBtn.themeBorder or theme.border
    row.statusBtn:SetBackdropColor(unpack(theme.buttonBg))
    row.statusBtn:SetBackdropBorderColor(unpack(btnTheme))
    row.statusBtn:SetScript("OnClick", function()
        DesolateLootcouncil.API:CancelVote(guid)
    end)
    row.statusBtn:Show()

    row.statusText:SetText(string.format(L["Voted: %s%s|r"] .. "%s", (VOTE_COLOR[voteVal] or "|cffffffff"), GetVoteText(guid, voteVal), noteText))
    row.statusText:SetPoint("LEFT", row.timerLbl, "RIGHT", 8, 0)
    row.statusText:SetPoint("RIGHT", row.statusBtn, "LEFT", -10, 0)
    row.statusText:Show()
end

function UI_Voting:StyleActiveVoteState(row, theme, guid, data)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    row.timerLbl:Show()

    local function CastVote(val)
        local note = self.myNotes[guid] or ""
        DesolateLootcouncil.API:SendVote(guid, val, note)
    end

    local itemID = data and (data.link or data.itemID)
    local isRecipe = itemID and DesolateLootcouncil.API:IsRecipe(itemID) or false

    local BUTTONS
    local w = 60
    local spacing = 4
    if isRecipe then
        w = 100
        BUTTONS = {
            { L["Ready to Craft"], 2, "Roll", L["Roll to receive this recipe because you have the profession and required skill to craft it."] },
            { L["Unskilled"], 3, "Offspec", L["Roll for this recipe even though you do not meet the skill or profession requirements yet."] },
            { L["Pass"], 5, "Pass", L["Pass on this recipe."] }
        }
    else
        BUTTONS = {
            { VOTE_TEXT[1], 1, "Bid", L["Bid priority points on this item."] },
            { VOTE_TEXT[2], 2, "Roll", L["Roll for main spec usage."] },
            { VOTE_TEXT[3], 3, "Offspec", L["Roll for offspec usage."] },
            { VOTE_TEXT[4], 4, "T-Mog", L["Roll for transmogrification collection."] },
            { VOTE_TEXT[5], 5, "Pass", L["Pass on this item."] }
        }
    end

    -- Modern Notepad Icon-Based Private Note Button
    if not row.actionFrame.noteBtn then
        local noteBtn = CreateFrame("Button", nil, row.actionFrame, "BackdropTemplate")
        noteBtn:SetSize(24, 24)
        noteBtn:SetPoint("RIGHT", 0, 0)
        noteBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })

        local noteTex = noteBtn:CreateTexture(nil, "OVERLAY")
        noteTex:SetSize(16, 16)
        noteTex:SetPoint("CENTER")
        noteTex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
        noteBtn.icon = noteTex

        row.actionFrame.noteBtn = noteBtn
    end
    local noteBtn = row.actionFrame.noteBtn
    noteBtn:Show()
    noteBtn:SetBackdropColor(unpack(theme.buttonBg))
    noteBtn:SetBackdropBorderColor(unpack(theme.border))

    noteBtn:SetScript("OnEnter", function()
        noteBtn:SetBackdropColor(unpack(theme.buttonHover))
        GameTooltip:SetOwner(noteBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Add Private Note"], 1, 1, 1)
        GameTooltip:Show()
    end)
    noteBtn:SetScript("OnLeave", function()
        noteBtn:SetBackdropColor(unpack(theme.buttonBg))
        GameTooltip:Hide()
    end)
    noteBtn:SetScript("OnClick", function()
        self.noteExpanded[guid] = not self.noteExpanded[guid]
        self:ShowVotingWindow(nil, true)
    end)

    row.votingButtons = row.votingButtons or {}
    for idx, bd in ipairs(BUTTONS) do
        local btn = row.votingButtons[idx]
        if btn and (btn.buttonType ~= bd[3] or math.abs(btn:GetWidth() - w) > 1) then
            btn:Hide()
            btn:SetParent(nil)
            btn = nil
            row.votingButtons[idx] = nil
        end
        if not btn then
            btn = NativeGUI:CreateButton(row.actionFrame, bd[1], w, 24, bd[3])
            row.votingButtons[idx] = btn
        end
        btn:Show()
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", -24 - spacing - (#BUTTONS - idx) * (w + spacing), 0)
        btn:SetScript("OnClick", function() CastVote(bd[2]) end)
        btn:SetScript("OnEnter", function(selfBtn)
            if selfBtn.themeHover then
                selfBtn:SetBackdropColor(unpack(selfBtn.themeHover))
            end
            if not bd[4] then return end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:SetText(bd[4], 1, 1, 1, nil, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(selfBtn)
            if selfBtn.themeBg then
                selfBtn:SetBackdropColor(unpack(selfBtn.themeBg))
            end
            GameTooltip:Hide()
        end)
    end
end

function UI_Voting:StyleNoteBox(row, theme, guid, isClosed, isExpired, isPending, currentVote)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    if not isClosed and not isExpired and not isPending and not currentVote and self.noteExpanded[guid] then
        if not row.noteBox then
            local noteBox, edit = NativeGUI:CreateEditBox(row, L["Add note to Loot Master..."])
            row.noteBox = noteBox
            row.noteEdit = edit
        end
        row.noteBox:ClearAllPoints()
        row.noteBox:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -45)
        row.noteBox:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -12, 5)
        row.noteBox:Show()
        row.noteEdit:SetText(self.myNotes[guid] or "")
        -- Dynamically update EditBox theme colors to prevent stale theme borders/backgrounds
        row.noteEdit:SetBackdropColor(theme.bg[1] * 0.4, theme.bg[2] * 0.4, theme.bg[3] * 0.4, 0.9)
        row.noteEdit:SetBackdropBorderColor(unpack(theme.border))
        row.noteEdit:SetScript("OnTextChanged", function(sb)
            self.myNotes[guid] = sb:GetText()
        end)
    elseif row.noteBox then
        row.noteBox:Hide()
    end
end

local function PositionRow(self, index, row, scrollContent)
    local topOffset = 0
    for k = 1, index - 1 do
        local prevRow = self.rowPool[k]
        if prevRow and prevRow:IsShown() then
            topOffset = topOffset + prevRow:GetHeight() + 10
        end
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -topOffset)
    row:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -12, -topOffset)
end

local function StyleRowStatus(self, row, theme, guid, currentVote, isClosed, isExpired, isPending, data)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    -- Setup reusable status elements to prevent memory leaks
    if not row.statusBtn then
        row.statusBtn = NativeGUI:CreateButton(row.actionFrame, "", 100, 24, "Pass")
    end
    row.statusBtn:Hide()
    row.statusBtn:ClearAllPoints()
    row.statusBtn:SetPoint("RIGHT", 0, 0)

    if not row.statusText then
        local fs = row.actionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        row.statusText = fs
    end
    row.statusText:Hide()
    row.statusText:ClearAllPoints()

    -- Explicitly hide active voting buttons to prevent overlapping layouts
    if row.actionFrame.noteBtn then row.actionFrame.noteBtn:Hide() end
    if row.votingButtons then
        for _, btn in ipairs(row.votingButtons) do btn:Hide() end
    end

    if isClosed or isExpired then
        self:StyleClosedExpiredState(row, theme, currentVote, guid)
    elseif isPending then
        self:StylePendingState(row, theme, guid)
    elseif currentVote then
        self:StyleVotedChangeState(row, theme, guid, currentVote)
    else
        self:StyleActiveVoteState(row, theme, guid, data)
    end
end

function UI_Voting:CreateItemRow(index, data, guid, currentVote, isClosed, isExpired, isPending)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local isActive = not isClosed and not isExpired and not currentVote

    if not self.rowPool[index] then
        self.rowPool[index] = NativeGUI:CreateRowContainer(self.scrollContent, isActive)
    end
    local row = self.rowPool[index]
    row:Show()

    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    -- Dynamically update backdrop color in case theme changed
    local bgR = theme.bg[1] + 0.03
    local bgG = theme.bg[2] + 0.03
    local bgB = theme.bg[3] + 0.03
    row:SetBackdropColor(bgR, bgG, bgB, 0.95)

    if isActive then
        row:SetBackdropBorderColor(unpack(theme.border))
    else
        row:SetBackdropBorderColor(theme.border[1] * 0.3, theme.border[2] * 0.3, theme.border[3] * 0.3, 0.4)
    end

    local rowHeight = (not isClosed and not isExpired and not isPending and not currentVote and self.noteExpanded[guid]) and 92 or 44
    row:SetHeight(rowHeight)

    PositionRow(self, index, row, self.scrollContent)

    self:CreateItemIcon(row, data, rowHeight)

    if not row.actionFrame then
        row.actionFrame = CreateFrame("Frame", nil, row)
    end
    row.actionFrame:ClearAllPoints()
    row.actionFrame:SetSize(393, 36)
    row.actionFrame:SetPoint("RIGHT", row, "RIGHT", -12, (rowHeight == 92) and 24 or 0)

    if not row.itemLabel then
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetJustifyH("LEFT")
        row.itemLabel = lbl
    end
    row.itemLabel:ClearAllPoints()
    row.itemLabel:SetPoint("LEFT", row.itemIcon, "RIGHT", 10, 0)
    row.itemLabel:SetPoint("RIGHT", row.actionFrame, "LEFT", -15, 0)

    local _, properLink = C_Item.GetItemInfo(data.link)
    if not properLink then
        local itemObj = Item:CreateFromItemID(data.itemID)
        if not itemObj:IsItemEmpty() then
            itemObj:ContinueOnItemLoad(function() self:ShowVotingWindow(nil, true) end)
        end
        row.itemLabel:SetText(L["Loading..."])
    else
        row.itemLabel:SetText(properLink)
    end

    if not row.timerLbl then
        local timer = row.actionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timer:SetWidth(45)
        timer:SetJustifyH("CENTER")
        row.timerLbl = timer
    end
    row.timerLbl:ClearAllPoints()
    row.timerLbl:SetPoint("LEFT", row.actionFrame, "LEFT", 0, 0)
    self.timerLabels[guid] = { fontString = row.timerLbl, expiry = data.expiry }

    StyleRowStatus(self, row, theme, guid, currentVote, isClosed, isExpired, isPending, data)

    self:StyleNoteBox(row, theme, guid, isClosed, isExpired, isPending, currentVote)
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

if _G.DLC_TEST_MODE then
    UI_Voting.GetVoteText = function(self, guid, voteVal)
        if type(self) == "string" then
            -- Shift arguments if called via dot syntax: Voting.GetVoteText(guid, voteVal)
            return GetVoteText(self, guid)
        end
        return GetVoteText(guid, voteVal)
    end
end
