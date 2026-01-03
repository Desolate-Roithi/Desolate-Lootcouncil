---@type UI
local UI = DesolateLootcouncil:GetModule("UI")
local AceGUI = LibStub("AceGUI-3.0")

function UI:CreateVotingFrame()
    ---@type AceGUIFrame
    local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
    frame:SetTitle("Loot Vote")
    frame:SetLayout("Flow")
    frame:SetWidth(800) -- Updated to 800
    frame:SetHeight(400)
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)
    self.votingFrame = frame
    -- Removed timerLabel from header
    self.myVotes = self.myVotes or {}
end

---@param lootTable table|nil
---@param isRefresh boolean?
function UI:ShowVotingWindow(lootTable, isRefresh)
    if not self.votingFrame then
        self:CreateVotingFrame()
    end

    -- Cache loot items so we can refresh the window
    if lootTable then
        self.cachedVotingItems = lootTable
    end

    local items = self.cachedVotingItems
    if not items then return end

    -- Sync self.myVotes just in case
    self.myVotes = self.myVotes or {}

    if not isRefresh then
        self.votingFrame:Show()
    end

    self.votingFrame:ReleaseChildren()
    self.rowTimers = {} -- Reset timers list

    -- Timer Logic: Single ticker updates all rows
    if self.votingTicker then self.votingTicker:Cancel() end

    local function FormatTime(seconds)
        if seconds < 0 then seconds = 0 end
        local m = math.floor(seconds / 60)
        local s = seconds % 60
        return string.format("%d:%02d", m, s)
    end

    self.votingTicker = C_Timer.NewTicker(1, function()
        local now = GetTime()
        for _, tData in ipairs(self.rowTimers) do
            local remaining = (tData.expiry or 0) - now
            if remaining <= 0 then
                tData.label:SetText("|cffff0000Closed|r")
            else
                tData.label:SetText(FormatTime(math.floor(remaining)))
            end
        end
    end)

    -- ScrollFrame
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.votingFrame:AddChild(scroll)

    -- Constants
    local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "Transmog", [4] = "Pass" }
    local VOTE_COLOR = { [1] = "|cff00ff00", [2] = "|cffffd700", [3] = "|cffeda55f", [4] = "|cffaaaaaa" }

    if items then
        for i, data in ipairs(items) do
            local link = data.link
            local guid = data.sourceGUID or link

            -- Row Group
            ---@type AceGUISimpleGroup
            local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            group:SetLayout("Flow")
            group:SetFullWidth(true)

            -- Col 1: Item Icon/Link (0.4)
            ---@type AceGUIInteractiveLabel
            local itemLabel = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
            itemLabel:SetText(link)
            itemLabel:SetRelativeWidth(0.40)
            itemLabel:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            itemLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            group:AddChild(itemLabel)

            -- Col 2: Timer (0.2)
            ---@type AceGUILabel
            local labelTimer = AceGUI:Create("Label") --[[@as AceGUILabel]]
            labelTimer:SetText("...") -- Will be updated by ticker
            labelTimer:SetRelativeWidth(0.20)
            group:AddChild(labelTimer)

            -- Add to timers list for ticker
            table.insert(self.rowTimers, { label = labelTimer, expiry = data.expiry })

            -- Col 3: Actions (0.4)
            local currentVote = self.myVotes[guid]
            ---@type Distribution
            local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
            local isClosed = Dist and Dist.closedItems and Dist.closedItems[guid]
            local isExpired = (GetTime() > (data.expiry or 0))
            local disable = isClosed or isExpired

            if isClosed or isExpired then
                -- STATE C: Item Closed/Expired
                -- Label: "You voted: [Color]Vote[r]" (0.25)
                local votedText = "No Vote"
                if currentVote then
                    local vText = VOTE_TEXT[currentVote] or "?"
                    local vColor = VOTE_COLOR[currentVote] or "|cffffffff"
                    votedText = "You voted: " .. vColor .. vText .. "|r"
                end

                local res = AceGUI:Create("Label") --[[@as AceGUILabel]]
                res:SetText(votedText)
                res:SetRelativeWidth(0.25)
                group:AddChild(res)

                -- Button: "Voting Closed" (0.15)
                local btnClosed = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btnClosed:SetText("Voting Closed")
                btnClosed:SetRelativeWidth(0.15)
                btnClosed:SetDisabled(true)
                group:AddChild(btnClosed)
            else
                -- STATE A: Active - Draw Buttons
                if currentVote then
                    -- Already voted - show status + change
                    local vText = VOTE_TEXT[currentVote] or "?"
                    local vColor = VOTE_COLOR[currentVote] or "|cffffffff"

                    local res = AceGUI:Create("Label")
                    res:SetText("Voted: " .. vColor .. vText .. "|r")
                    res:SetRelativeWidth(0.20)
                    group:AddChild(res)

                    local change = AceGUI:Create("Button")
                    change:SetText("Change")
                    change:SetRelativeWidth(0.20)
                    change:SetCallback("OnClick", function()
                        if Dist and Dist.SendVote then Dist:SendVote(guid, 0) end
                        self.myVotes[guid] = nil
                        self:ShowVotingWindow(nil, true)
                    end)
                    group:AddChild(change)
                else
                    -- No Vote Yet
                    local function CastVote(value)
                        self.myVotes[guid] = value
                        if Dist and Dist.SendVote then Dist:SendVote(guid, value) end
                        self:ShowVotingWindow(nil, true)
                    end
                    local w = 0.10
                    local btnBid = AceGUI:Create("Button")
                    btnBid:SetText("Bid")
                    btnBid:SetRelativeWidth(w)
                    btnBid:SetCallback("OnClick", function() CastVote(1) end)
                    group:AddChild(btnBid)

                    local btnRoll = AceGUI:Create("Button")
                    btnRoll:SetText("Roll")
                    btnRoll:SetRelativeWidth(w)
                    btnRoll:SetCallback("OnClick", function() CastVote(2) end)
                    group:AddChild(btnRoll)

                    local btnMog = AceGUI:Create("Button")
                    btnMog:SetText("Mog")
                    btnMog:SetRelativeWidth(w)
                    btnMog:SetCallback("OnClick", function() CastVote(3) end)
                    group:AddChild(btnMog)

                    local btnPass = AceGUI:Create("Button")
                    btnPass:SetText("Pass")
                    btnPass:SetRelativeWidth(w)
                    btnPass:SetCallback("OnClick", function() CastVote(4) end)
                    group:AddChild(btnPass)
                end
            end

            scroll:AddChild(group)
        end
    end
end
