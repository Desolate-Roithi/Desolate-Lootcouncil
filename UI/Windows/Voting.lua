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

    if not self.scrollFrame then
        local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.votingFrame, -50, -16)
        self.scrollFrame = scrollFrame
        self.scrollContent = scrollContent
    end

    self.scrollFrame:Show()
    self.scrollContent:Show()

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
    row.actionFrame:SetSize(420, 36)
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
        local timer = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timer:SetWidth(45)
        timer:SetJustifyH("CENTER")
        row.timerLbl = timer
    end
    row.timerLbl:ClearAllPoints()
    row.timerLbl:SetPoint("RIGHT", row.actionFrame, "LEFT", -5, 0)
    self.timerLabels[guid] = { fontString = row.timerLbl, expiry = data.expiry }

    -- Restrict item label width further if timer is visible
    row.itemLabel:SetPoint("RIGHT", row.timerLbl, "LEFT", -10, 0)

    local kids = { row.actionFrame:GetChildren() }
    for _, kid in ipairs(kids) do
        kid:Hide()
        kid:ClearAllPoints()
    end

    local regions = { row.actionFrame:GetRegions() }
    for _, reg in ipairs(regions) do
        if reg:GetObjectType() == "FontString" then
            reg:SetText("")
            reg:Hide()
        end
    end

    if isClosed or isExpired then
        local votedText = L["You voted: |cffaaaaaaAuto Pass|r"]
        if currentVote then
            local voteVal = type(currentVote) == "table" and currentVote.type or currentVote
            local noteText = type(currentVote) == "table" and currentVote.note and currentVote.note ~= "" and (" (" .. currentVote.note .. ")") or ""
            votedText = string.format(L["You voted: %s%s|r%s"], (VOTE_COLOR[voteVal] or "|cffffffff"), (VOTE_TEXT[voteVal] or "?"), noteText)
        end

        local btn = NativeGUI:CreateButton(row.actionFrame, L["Closed"], 100, 24, "Pass")
        btn:SetPoint("RIGHT", 0, 0)
        btn:SetEnabled(false)

        local res = row.actionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        res:SetPoint("LEFT", 0, 0)
        res:SetPoint("RIGHT", btn, "LEFT", -10, 0)
        res:SetJustifyH("LEFT")
        res:SetText(votedText)

    elseif isPending then
        local outbound   = DesolateLootcouncil.API:GetOutboundVote(guid)
        local pendingType = outbound and outbound.type
        local vText  = pendingType and VOTE_TEXT[pendingType]  or "?"
        local vColor = pendingType and VOTE_COLOR[pendingType] or "|cffffffff"
        local noteText = self.myNotes[guid] and self.myNotes[guid] ~= "" and (" (" .. self.myNotes[guid] .. ")") or ""

        local syncBtn = NativeGUI:CreateButton(row.actionFrame, L["Syncing..."], 100, 24, "Note")
        syncBtn:SetPoint("RIGHT", 0, 0)
        syncBtn:SetEnabled(false)

        local res = row.actionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        res:SetPoint("LEFT", 0, 0)
        res:SetPoint("RIGHT", syncBtn, "LEFT", -10, 0)
        res:SetJustifyH("LEFT")
        res:SetText(string.format(L["Voted: %s%s|r%s"], vColor, vText, noteText))

    elseif currentVote then
        local voteVal = type(currentVote) == "table" and currentVote.type or currentVote
        local noteText = type(currentVote) == "table" and currentVote.note and currentVote.note ~= "" and (" (" .. currentVote.note .. ")") or ""

        local change = NativeGUI:CreateButton(row.actionFrame, L["Change"], 100, 24, "Pass")
        change:SetPoint("RIGHT", 0, 0)
        change:SetScript("OnClick", function()
            self.myVotes[guid] = nil
            DesolateLootcouncil.API:CancelVote(guid)
            self:ShowVotingWindow(nil, true)
        end)

        local res = row.actionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        res:SetPoint("LEFT", 0, 0)
        res:SetPoint("RIGHT", change, "LEFT", -10, 0)
        res:SetJustifyH("LEFT")
        res:SetText(string.format(L["Voted: %s%s|r%s"], (VOTE_COLOR[voteVal] or "|cffffffff"), (VOTE_TEXT[voteVal] or "?"), noteText))

    else
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

        for idx, bd in ipairs(BUTTONS) do
            local btn = NativeGUI:CreateButton(row.actionFrame, bd[1], w, 24, bd[3])
            btn:SetPoint("LEFT", (idx - 1) * (w + spacing), 0)
            btn:SetScript("OnClick", function() CastVote(bd[2]) end)
        end

        -- Modern Notepad Icon-Based Private Note Button
        local noteBtn = CreateFrame("Button", nil, row.actionFrame, "BackdropTemplate")
        noteBtn:SetSize(24, 24)
        noteBtn:SetPoint("LEFT", 5 * (w + spacing), 0)
        noteBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        noteBtn:SetBackdropColor(unpack(theme.buttonBg))
        noteBtn:SetBackdropBorderColor(0.6, 0.3, 0.9, 1.0)

        local noteTex = noteBtn:CreateTexture(nil, "OVERLAY")
        noteTex:SetSize(16, 16)
        noteTex:SetPoint("CENTER")
        noteTex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
        noteBtn.icon = noteTex

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
        row.noteEdit:SetScript("OnTextChanged", function(sb)
            self.myNotes[guid] = sb:GetText()
        end)
    elseif row.noteBox then
        row.noteBox:Hide()
    end

    if index == #self.cachedVotingItems then
        self.scrollContent:SetHeight(topOffset + rowHeight + 10)
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
