local _, AT = ...
if AT.abortLoad then return end

---@class UI_Voting : AceModule
local UI_Voting = DesolateLootcouncil:NewModule("UI_Voting")
local AceGUI = LibStub("AceGUI-3.0")

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
    frame:SetTitle("Loot Vote")
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

    -- [NEW] Position Persistence
    DesolateLootcouncil:RestoreFramePosition(frame, "Voting")
    local function SavePos(f)
        DesolateLootcouncil:SaveFramePosition(f, "Voting")
    end
    local rawFrame = (frame --[[@as any]]).frame
    rawFrame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        SavePos(frame)
    end)
    rawFrame:SetScript("OnHide", function() SavePos(frame) end)
    DesolateLootcouncil.Persistence:ApplyCollapseHook(frame, "Voting")

    self.myVotes = self.myVotes or {}
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
    self.cachedVotingItems = {}
    if self.votingFrame then self.votingFrame:Hide() end
end

function UI_Voting:ShowVotingWindow(lootTable, isRefresh)
    if not self.votingFrame then self:CreateVotingFrame() end

    -- Sync Persistence
    ---@type Session
    local SessionModule = DesolateLootcouncil:GetModule("Session") --[[@as Session]]
    if SessionModule and SessionModule.myLocalVotes then
        self.myVotes = SessionModule.myLocalVotes
    end

    -- New Session Data
    if lootTable then
        self.cachedVotingItems = lootTable
        -- Fix: Preserve local votes on append
        self.myVotes = self.myVotes or {}
    end
    -- Bug 3: Build a set of awarded GUIDs so we can skip items already distributed
    local awardedGUIDs = {}
    local session = DesolateLootcouncil.db.profile.session
    if session and session.awarded then
        for _, award in ipairs(session.awarded) do
            if award.fullItemData and award.fullItemData.sourceGUID then
                awardedGUIDs[award.fullItemData.sourceGUID] = true
            end
        end
    end

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
        local closedItems = (SessionModule and SessionModule.closedItems) or {}
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
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)

    -- [NEW] Preserve Scroll Status on Refresh
    if not self.scrollStatus or not isRefresh then
        self.scrollStatus = { scrollvalue = 0 }
    end
    scroll:SetStatusTable(self.scrollStatus)

    self.votingFrame:AddChild(scroll)
    self.scrollContainer = scroll

    local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "Offspec", [4] = "T-Mog", [5] = "Pass" }
    local VOTE_COLOR = {
        [1] = "|cff00ff00",
        [2] = "|cffffd700",
        [3] = "|cff00ffff",
        [4] = "|cffeda55f",
        [5] =
        "|cffaaaaaa"
    }
    local closedItems = (SessionModule and SessionModule.closedItems) or {}
    local now = GetServerTime()

    for _, data in ipairs(items) do
        local guid = data.sourceGUID or data.link

        -- Bug 3: Skip already-awarded items
        if not awardedGUIDs[guid] then
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
            ---@type AceGUISimpleGroup
            local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            group:SetLayout("Flow")
            group:SetFullWidth(true)
            scroll:AddChild(group)

            -- Item Icon (NEW)
            ---@type AceGUIIcon
            local itemIcon = AceGUI:Create("Icon")
            itemIcon:SetImage(data.texture or (data.itemID and C_Item.GetItemIconByID(data.itemID)) or 134400)
            itemIcon:SetImageSize(24, 24)
            itemIcon:SetRelativeWidth(0.05)
            itemIcon:SetCallback("OnClick", function()
                GameTooltip:SetOwner((itemIcon --[[@as any]]).frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(data.link)
                GameTooltip:Show()
            end)
            itemIcon:SetCallback("OnEnter", function()
                GameTooltip:SetOwner((itemIcon --[[@as any]]).frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(data.link)
                GameTooltip:Show()
            end)
            itemIcon:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            group:AddChild(itemIcon)

            -- Link (Bug Fix: resolve via cache to ensure proper coloring/loading)
            ---@type AceGUIInteractiveLabel
            local itemLabel = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
            local _, properLink = C_Item.GetItemInfo(data.link)
            if not properLink then
                local itemObj = Item:CreateFromItemID(data.itemID)
                if not itemObj:IsItemEmpty() then
                    itemObj:ContinueOnItemLoad(function()
                        self:ShowVotingWindow(nil, true) -- Refresh
                    end)
                end
                itemLabel:SetText("Loading...")
            else
                itemLabel:SetText(properLink)
                -- Update Icon too if it was missing
                itemIcon:SetImage(C_Item.GetItemIconByID(data.itemID) or 134400)
            end
            itemLabel:SetRelativeWidth(0.25) -- Reduced from 0.30 to accommodate icon (0.05)
            itemLabel:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(data.link)
                GameTooltip:Show()
            end)
            itemLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            group:AddChild(itemLabel)

            -- Timer Label (Bug Fix: Shrink to prevent wrapping)
            ---@type AceGUILabel
            local timerLbl = AceGUI:Create("Label") --[[@as AceGUILabel]]
            timerLbl:SetText("...")
            timerLbl:SetRelativeWidth(0.06)
            group:AddChild(timerLbl)
            self.timerLabels[guid] = { label = timerLbl, expiry = data.expiry }

            -- Actions (Bug Fix: Expand to handle 5 buttons)
            ---@type AceGUISimpleGroup
            local actionGroup = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            actionGroup:SetLayout("Flow")
            actionGroup:SetRelativeWidth(0.64)
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

                ---@type AceGUILabel
                local res = AceGUI:Create("Label") --[[@as AceGUILabel]]
                res:SetText(votedText)
                res:SetWidth(200)
                actionGroup:AddChild(res)

                ---@type AceGUIButton
                local btn = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btn:SetText("Closed")
                btn:SetWidth(100)
                btn:SetDisabled(true)
                actionGroup:AddChild(btn)
            elseif currentVote then
                -- 2. If Open AND Voted -> Show Change Button
                local vText = VOTE_TEXT[currentVote] or "?"
                local vColor = VOTE_COLOR[currentVote] or "|cffffffff"

                ---@type AceGUILabel
                local res = AceGUI:Create("Label") --[[@as AceGUILabel]]
                res:SetText("Voted: " .. vColor .. vText .. "|r")
                res:SetWidth(200)
                actionGroup:AddChild(res)

                ---@type AceGUIButton
                local change = AceGUI:Create("Button") --[[@as AceGUIButton]]
                change:SetText("Change")
                change:SetWidth(100)
                change:SetCallback("OnClick", function()
                    self.myVotes[guid] = nil
                    if SessionModule and SessionModule.SendVote then SessionModule:SendVote(guid, 0) end
                    self:ShowVotingWindow(nil, true)
                end)
                actionGroup:AddChild(change)
            else
                -- 3. If Open AND No Vote -> Show Options
                local function CastVote(val)
                    self.myVotes[guid] = val
                    if SessionModule and SessionModule.SendVote then SessionModule:SendVote(guid, val) end
                    self:ShowVotingWindow(nil, true)
                end

                local w = 80
                ---@type AceGUIButton
                local b1 = AceGUI:Create("Button") --[[@as AceGUIButton]]
                b1:SetText("Bid")
                b1:SetWidth(w)
                b1:SetCallback("OnClick", function() CastVote(1) end)
                actionGroup:AddChild(b1)

                ---@type AceGUIButton
                local b2 = AceGUI:Create("Button") --[[@as AceGUIButton]]
                b2:SetText("Roll")
                b2:SetWidth(w)
                b2:SetCallback("OnClick", function() CastVote(2) end)
                actionGroup:AddChild(b2)

                ---@type AceGUIButton
                local b3 = AceGUI:Create("Button") --[[@as AceGUIButton]]
                b3:SetText("Offspec")
                b3:SetWidth(w)
                b3:SetCallback("OnClick", function() CastVote(3) end)
                actionGroup:AddChild(b3)

                ---@type AceGUIButton
                local b4 = AceGUI:Create("Button") --[[@as AceGUIButton]]
                b4:SetText("T-Mog")
                b4:SetWidth(w)
                b4:SetCallback("OnClick", function() CastVote(4) end)
                actionGroup:AddChild(b4)

                ---@type AceGUIButton
                local b5 = AceGUI:Create("Button") --[[@as AceGUIButton]]
                b5:SetText("Pass")
                b5:SetWidth(w)
                b5:SetCallback("OnClick", function() CastVote(5) end)
                actionGroup:AddChild(b5)
            end
        end -- end Bug 3 awarded filter
    end

    -- Add a small spacer at the bottom to ensure the last item isn't obscured by the status bar
    ---@type AceGUILabel
    local spacer = AceGUI:Create("Label") --[[@as AceGUILabel]]
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    scroll:AddChild(spacer)

    self.votingFrame:DoLayout()
end
