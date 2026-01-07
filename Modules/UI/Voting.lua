---@type UI
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
local AceGUI = LibStub("AceGUI-3.0")


local function FormatTime(seconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

function UI:CreateVotingFrame()
    ---@type AceGUIWidget
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Loot Vote")
    frame:SetLayout("Flow")
    frame:EnableResize(false)
    frame:SetWidth(800)
    frame:SetHeight(450)
    frame:SetCallback("OnClose", function(widget)
        if self.votingTicker then self.votingTicker:Cancel() end
        self:CancelAllTimers()
        widget:Hide()
    end)
    self.votingFrame = frame
    self.myVotes = self.myVotes or {}
    self.timerLabels = {}
    self.expirationTimers = {} -- Store expiration triggers
end

function UI:CancelAllTimers()
    if self.expirationTimers then
        for _, t in ipairs(self.expirationTimers) do
            if t then t:Cancel() end
        end
    end
    self.expirationTimers = {}
end

function UI:RemoveVotingItem(guid)
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

function UI:ShowVotingWindow(lootTable, isRefresh)
    if not self.votingFrame then self:CreateVotingFrame() end

    -- New Session Data
    if lootTable then
        self.cachedVotingItems = lootTable
        self.myVotes = {}
    end
    local items = self.cachedVotingItems
    if not items then return end

    self.votingFrame:Show()
    self.votingFrame:ReleaseChildren()
    self.timerLabels = {}

    -- Cancel old timers
    if self.votingTicker then self.votingTicker:Cancel() end
    self:CancelAllTimers()

    -- 1. Ticker (Visual Only)
    self.votingTicker = C_Timer.NewTicker(0.5, function()
        local now = GetTime()
        ---@type Distribution
        local Dist = DesolateLootcouncil:GetModule("Distribution")
        local closedItems = (Dist and Dist.closedItems) or {}
        for guid, info in pairs(self.timerLabels) do
            if info.label and info.label.frame and info.label.SetText then
                local remaining = (info.expiry or 0) - now
                local isClosed = closedItems[guid]

                if isClosed or remaining <= 0 then
                    info.label:SetText("|cffff0000Closed|r")
                else
                    info.label:SetText(FormatTime(remaining))
                end
            end
        end
    end)

    -- 2. Build Layout
    ---@type AceGUIWidget
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.votingFrame:AddChild(scroll)

    local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "T-Mog", [4] = "Pass" }
    local VOTE_COLOR = { [1] = "|cff00ff00", [2] = "|cffffd700", [3] = "|cffeda55f", [4] = "|cffaaaaaa" }
    ---@type Distribution
    local Dist = DesolateLootcouncil:GetModule("Distribution")
    local closedItems = (Dist and Dist.closedItems) or {}
    local now = GetTime()

    for _, data in ipairs(items) do
        local guid = data.sourceGUID or data.link
        local currentVote = self.myVotes[guid]
        local isClosed = closedItems[guid]
        local remaining = (data.expiry or 0) - now
        local isExpired = (remaining <= 0)

        -- EXPIRATION TRIGGER:
        -- If not closed/expired yet, schedule a forced refresh exactly when it happens.
        if not isClosed and not isExpired and remaining > 0 then
            local t = C_Timer.NewTimer(remaining, function()
                self:ShowVotingWindow(nil, true)
            end)
            table.insert(self.expirationTimers, t)
        end

        -- Row
        ---@type AceGUIWidget
        local group = AceGUI:Create("SimpleGroup")
        group:SetLayout("Flow")
        group:SetFullWidth(true)
        scroll:AddChild(group)

        -- Link
        ---@type AceGUIWidget
        local itemLabel = AceGUI:Create("InteractiveLabel")
        itemLabel:SetText(data.link)
        itemLabel:SetRelativeWidth(0.35)
        itemLabel:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(data.link)
            GameTooltip:Show()
        end)
        itemLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        group:AddChild(itemLabel)

        -- Timer Label
        ---@type AceGUIWidget
        local timerLbl = AceGUI:Create("Label")
        timerLbl:SetText("...")
        timerLbl:SetRelativeWidth(0.15)
        group:AddChild(timerLbl)
        self.timerLabels[guid] = { label = timerLbl, expiry = data.expiry }

        -- Actions
        ---@type AceGUIWidget
        local actionGroup = AceGUI:Create("SimpleGroup")
        actionGroup:SetLayout("Flow")
        actionGroup:SetRelativeWidth(0.50)
        group:AddChild(actionGroup)

        if isClosed or isExpired then
            -- 1. PRIORITY: Check Closed/Expired FIRST
            -- Show what they voted (or Auto Pass), but DISABLE changes
            local votedText = "You voted: |cffaaaaaaAuto Pass|r"
            if currentVote then
                local vText = VOTE_TEXT[currentVote] or "?"
                local vColor = VOTE_COLOR[currentVote] or "|cffffffff"
                votedText = "You voted: " .. vColor .. vText .. "|r"
            end

            ---@type AceGUIWidget
            local res = AceGUI:Create("Label")
            res:SetText(votedText)
            res:SetWidth(200)
            actionGroup:AddChild(res)

            ---@type AceGUIWidget
            local btn = AceGUI:Create("Button")
            btn:SetText("Closed")
            btn:SetWidth(100)
            btn:SetDisabled(true)
            actionGroup:AddChild(btn)
        elseif currentVote then
            -- 2. If Open AND Voted -> Show Change Button
            local vText = VOTE_TEXT[currentVote] or "?"
            local vColor = VOTE_COLOR[currentVote] or "|cffffffff"

            ---@type AceGUIWidget
            local res = AceGUI:Create("Label")
            res:SetText("Voted: " .. vColor .. vText .. "|r")
            res:SetWidth(200)
            actionGroup:AddChild(res)

            ---@type AceGUIWidget
            local change = AceGUI:Create("Button")
            change:SetText("Change")
            change:SetWidth(100)
            change:SetCallback("OnClick", function()
                self.myVotes[guid] = nil
                if Dist and Dist.SendVote then Dist:SendVote(guid, 0) end
                self:ShowVotingWindow(nil, true)
            end)
            actionGroup:AddChild(change)
        else
            -- 3. If Open AND No Vote -> Show Options
            local function CastVote(val)
                self.myVotes[guid] = val
                if Dist and Dist.SendVote then Dist:SendVote(guid, val) end
                self:ShowVotingWindow(nil, true)
            end

            local w = 75
            ---@type AceGUIWidget
            local b1 = AceGUI:Create("Button")
            b1:SetText("Bid")
            b1:SetWidth(w)
            b1:SetCallback("OnClick", function() CastVote(1) end)
            actionGroup:AddChild(b1)

            ---@type AceGUIWidget
            local b2 = AceGUI:Create("Button")
            b2:SetText("Roll")
            b2:SetWidth(w)
            b2:SetCallback("OnClick", function() CastVote(2) end)
            actionGroup:AddChild(b2)

            ---@type AceGUIWidget
            local b3 = AceGUI:Create("Button")
            b3:SetText("T-Mog")
            b3:SetWidth(w)
            b3:SetCallback("OnClick", function() CastVote(3) end)
            actionGroup:AddChild(b3)

            ---@type AceGUIWidget
            local b4 = AceGUI:Create("Button")
            b4:SetText("Pass")
            b4:SetWidth(w)
            b4:SetCallback("OnClick", function() CastVote(4) end)
            actionGroup:AddChild(b4)
        end
    end
end
