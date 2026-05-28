local _, AT = ...
if AT.abortLoad then return end

---@class UI_Voting : AceModule
local UI_Voting = DesolateLootcouncil:NewModule("UI_Voting", "AceEvent-3.0")

-- File-scope constants: defined once, shared across all calls to ShowVotingWindow.
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")
local VOTE_TEXT  = { [1] = L["Bid"], [2] = L["Roll"], [3] = L["Offspec"], [4] = L["T-Mog"], [5] = L["Pass"] }
local VOTE_COLOR = {
    [1] = "|cff00ff00", [2] = "|cffffd700",
    [3] = "|cff00ffff", [4] = "|cffeda55f", [5] = "|cffaaaaaa"
}

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
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local frame = NativeGUI:CreateWindow("DLCVotingFrame", L["Loot Vote"], 800, 450, "Voting")

    frame:HookScript("OnHide", function()
        if self.votingTicker then self.votingTicker:Cancel() end
        self:CancelAllTimers()
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
    if self.cachedVotingItems then
        for i, item in ipairs(self.cachedVotingItems) do
            if (item.sourceGUID or item.link) == guid then
                table.remove(self.cachedVotingItems, i)
                break
            end
        end
    end
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
    if self.rowPool then
        for _, r in ipairs(self.rowPool) do r:Hide() end
    end
end

function UI_Voting:ShowVotingWindow(lootTable, isRefresh)
    if not self.votingFrame then self:CreateVotingFrame() end

    local API = DesolateLootcouncil.API

    self.myVotes = API:GetLocalVotes()
    self.myNotes = self.myNotes or {}
    self.noteExpanded = self.noteExpanded or {}

    if lootTable then
        self.cachedVotingItems = lootTable
        self.myVotes = self.myVotes or {}
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

    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    if not self.scrollFrame then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.votingFrame, -50, -16)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    self.scrollFrame:Show()
    self.scrollContent:Show()
    NativeGUI:StyleScrollBar(self.scrollFrame)

    self.votingTicker = C_Timer.NewTicker(0.5, function()
        local now = GetServerTime()
        for guid, info in pairs(self.timerLabels) do
            if info.fontString then
                local remaining = (info.expiry or 0) - now
                local isClosed  = API:IsItemClosed(guid)

                if isClosed or remaining <= 0 then
                    info.fontString:SetText("|cffff0000" .. L["Closed"] .. "|r")
                else
                    info.fontString:SetText(FormatTime(remaining))
                end
            end
        end
    end)

    local now = GetServerTime()
    local rowCount = 0

    for i = #items, 1, -1 do
        local data = items[i]
        local guid = data.sourceGUID or data.link
        if not awardedGUIDs[guid] then
            local currentVote = self.myVotes[guid]
            local isClosed    = API:IsItemClosed(guid)
            local remaining   = (data.expiry or 0) - now
            local isExpired   = (remaining <= 0)
            local isPending   = (API:GetOutboundVote(guid) ~= nil)

            if isExpired and not currentVote and not isPending and not isClosed then
                -- Automatically send an Auto Pass vote to the Loot Master
                self.myVotes[guid] = 5
                DesolateLootcouncil.API:SendVote(guid, 5, "")
                currentVote = 5
            end

            if not isClosed and not isExpired and remaining > 0 then
                local t = C_Timer.NewTimer(remaining, function()
                    self:ShowVotingWindow(nil, true)
                end)
                table.insert(self.expirationTimers, t)
            end

            rowCount = rowCount + 1
            self:CreateItemRow(
                rowCount, data, guid,
                currentVote, isClosed, isExpired, isPending
            )
        end
    end

    -- Set total scroll content height based on the total height of all displayed rows
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

    local topOffset = 0
    for k = 1, index - 1 do
        local prevRow = self.rowPool[k]
        if prevRow and prevRow:IsShown() then
            topOffset = topOffset + prevRow:GetHeight() + 10
        end
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -topOffset)
    row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", -12, -topOffset)

    if not row.itemIcon then
        local icon = CreateFrame("Button", nil, row)
        icon:SetSize(28, 28)
        
        local tex = icon:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        icon.texture = tex
        
        row.itemIcon = icon
    end
    row.itemIcon:ClearAllPoints()
    row.itemIcon:SetPoint("LEFT", 12, (rowHeight == 92) and 24 or 0)
    row.itemIcon.texture:SetTexture(data.texture or (data.itemID and C_Item.GetItemIconByID(data.itemID)) or 134400)

    local function ShowTip()
        GameTooltip:SetOwner(row.itemIcon, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(data.link)
        GameTooltip:Show()
    end
    row.itemIcon:SetScript("OnClick", ShowTip)
    row.itemIcon:SetScript("OnEnter", ShowTip)
    row.itemIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
        row.timerLbl:Hide()

        local votedText = L["You voted: |cffaaaaaaAuto Pass|r"]
        if currentVote then
            local voteVal = type(currentVote) == "table" and currentVote.type or currentVote
            local noteText = type(currentVote) == "table" and currentVote.note and currentVote.note ~= "" and (" (" .. currentVote.note .. ")") or ""
            votedText = string.format(L["You voted: %s%s|r%s"], (VOTE_COLOR[voteVal] or "|cffffffff"), (VOTE_TEXT[voteVal] or "?"), noteText)
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

    elseif isPending then
        row.timerLbl:Show()

        local outbound   = DesolateLootcouncil.API:GetOutboundVote(guid)
        local pendingType = outbound and outbound.type
        local vText  = pendingType and VOTE_TEXT[pendingType]  or "?"
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

    elseif currentVote then
        row.timerLbl:Show()

        local voteVal = type(currentVote) == "table" and currentVote.type or currentVote
        local noteText = type(currentVote) == "table" and currentVote.note and currentVote.note ~= "" and (" (" .. currentVote.note .. ")") or ""

        row.statusBtn:SetText(L["Change"])
        row.statusBtn:SetEnabled(true)
        local btnTheme = row.statusBtn.themeBorder or theme.border
        row.statusBtn:SetBackdropColor(unpack(theme.buttonBg))
        row.statusBtn:SetBackdropBorderColor(unpack(btnTheme))
        row.statusBtn:SetScript("OnClick", function()
            self.myVotes[guid] = nil
            DesolateLootcouncil.API:CancelVote(guid)
            self:ShowVotingWindow(nil, true)
        end)
        row.statusBtn:Show()

        row.statusText:SetText(string.format(L["Voted: %s%s|r"] .. "%s", (VOTE_COLOR[voteVal] or "|cffffffff"), (VOTE_TEXT[voteVal] or "?"), noteText))
        row.statusText:SetPoint("LEFT", row.timerLbl, "RIGHT", 8, 0)
        row.statusText:SetPoint("RIGHT", row.statusBtn, "LEFT", -10, 0)
        row.statusText:Show()

    else
        row.timerLbl:Show()

        local function CastVote(val)
            self.myVotes[guid] = val
            local note = self.myNotes[guid] or ""
            DesolateLootcouncil.API:SendVote(guid, val, note)
            self:ShowVotingWindow(nil, true)
        end

        local w = 60
        local spacing = 4
        local BUTTONS = {
            { VOTE_TEXT[1], 1, "Bid" }, { VOTE_TEXT[2], 2, "Roll" },
            { VOTE_TEXT[3], 3, "Offspec" }, { VOTE_TEXT[4], 4, "T-Mog" }, { VOTE_TEXT[5], 5, "Pass" }
        }

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
            if not btn then
                btn = NativeGUI:CreateButton(row.actionFrame, bd[1], w, 24, bd[3])
                row.votingButtons[idx] = btn
            end
            btn:Show()
            btn:ClearAllPoints()
            btn:SetPoint("RIGHT", -24 - spacing - (5 - idx) * (w + spacing), 0)
            btn:SetScript("OnClick", function() CastVote(bd[2]) end)
        end
    end

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
