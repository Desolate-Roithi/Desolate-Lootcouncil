---@class UI : AceModule, AceConsole-3.0
---@field ShowLootWindow fun(self: UI, lootTable: table)
---@field ShowVotingWindow fun(self: UI, lootTable: table)
local UI = DesolateLootcouncil:NewModule("UI", "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0")

---@class AceGUIWidget
---@field Show fun(self: self)
---@field Hide fun(self: self)
---@field SetWidth fun(self: self, width: number)
---@field SetHeight fun(self: self, height: number)
---@field SetCallback fun(self: self, name: string, callback: function)

---@class AceGUIContainer : AceGUIWidget
---@field ReleaseChildren fun(self: self)
---@field AddChild fun(self: self, child: AceGUIWidget)
---@field SetLayout fun(self: self, layout: string)
---@field SetFullWidth fun(self: self, full: boolean)
---@field SetFullHeight fun(self: self, full: boolean)

---@class AceGUIFrame : AceGUIContainer
---@field SetTitle fun(self: self, title: string)

---@class AceGUIScrollFrame : AceGUIContainer

---@class AceGUISimpleGroup : AceGUIContainer

---@class AceGUIButton : AceGUIWidget
---@field SetText fun(self: self, text: string)
---@field SetWidth fun(self: self, width: number)
---@field SetCallback fun(self: self, name: string, callback: function)
---@field SetFullWidth fun(self: self, full: boolean)

---@class AceGUILabel : AceGUIWidget
---@field SetText fun(self: self, text: string)

---@class AceGUIInteractiveLabel : AceGUILabel

---@class AceGUIDropdown : AceGUIWidget
---@field SetList fun(self: self, list: table)
---@field SetValue fun(self: self, value: any)
---@field SetRelativeWidth fun(self: self, width: number)
---@field SetCallback fun(self: self, name: string, callback: function)

function UI:CreateLootFrame()
    ---@type AceGUIFrame
    local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
    frame:SetTitle("Desolate Loot Council")
    frame:SetLayout("Flow")
    frame:SetWidth(400)
    frame:SetHeight(500)
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
        if self.btnStart then self.btnStart:Hide() end
    end)

    self.lootFrame = frame
end

function UI:ShowLootWindow(lootTable)
    if not DesolateLootcouncil:AmILootMaster() then
        self:Print("Error: Only the Loot Master can open the Loot Window.")
        return
    end

    if not self.lootFrame then
        self:CreateLootFrame()
    end

    self.lootFrame:Show()
    self.lootFrame:ReleaseChildren() -- Clear previous items

    -- 1. Hide the default Status Bar background
    if (self.lootFrame --[[@as any]]).statusbg then
        (self.lootFrame --[[@as any]]).statusbg:Hide()
    end

    -- 2. Clear Session Button (Top)
    ---@type AceGUIButton
    local clearBtn = AceGUI:Create("Button") --[[@as AceGUIButton]]
    clearBtn:SetText("Clear Session")
    clearBtn:SetFullWidth(true)
    clearBtn:SetHeight(25)
    clearBtn:SetCallback("OnClick", function()
        ---@type Loot
        local Loot = DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
        Loot:ClearSession()
        self.lootFrame:Hide()
        if self.btnStart then self.btnStart:Hide() end
    end)
    self.lootFrame:AddChild(clearBtn)

    -- 3. ScrollFrame (Middle)
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    self.lootFrame:AddChild(scroll)

    local count = 0
    if lootTable then
        for i, data in ipairs(lootTable) do
            count = count + 1
            local link = data.link

            -- Row Container
            ---@type AceGUISimpleGroup
            local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            group:SetLayout("Flow")
            group:SetFullWidth(true)

            -- Item Link (Interactive Logic)
            ---@type AceGUIInteractiveLabel
            local itemLabel = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
            itemLabel:SetText(link)
            itemLabel:SetRelativeWidth(0.55) -- User requested 0.55
            itemLabel:SetCallback("OnClick", function()
                local widget = itemLabel --[[@as {frame: table}]]
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            itemLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            itemLabel:SetCallback("OnEnter", function()
                local widget = itemLabel --[[@as {frame: table}]]
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)

            -- Category Dropdown
            ---@type AceGUIDropdown
            local catDropdown = AceGUI:Create("Dropdown") --[[@as AceGUIDropdown]]
            catDropdown:SetRelativeWidth(0.30) -- User requested 0.30 (reduced)
            catDropdown:SetList({
                ["Tier"] = "Tier",
                ["Weapons"] = "Weapons",
                ["Collectables"] = "Collectables",
                ["Rest"] = "Rest",
                ["Junk/Pass"] = "Junk/Pass"
            })
            catDropdown:SetValue(data.category)
            catDropdown:SetCallback("OnValueChanged", function(_, _, value)
                data.category = value
                DesolateLootcouncil:Print("[DLC] Category updated to: " .. value)
            end)

            -- Remove Button
            ---@type AceGUIButton
            local removeBtn = AceGUI:Create("Button") --[[@as AceGUIButton]]
            removeBtn:SetText("X")
            removeBtn:SetWidth(50) -- User requested 50 (increased)
            removeBtn:SetCallback("OnClick", function()
                table.remove(lootTable, i)
                DesolateLootcouncil:Print("[DLC] Removed " .. link .. " from session.")
                self:ShowLootWindow(lootTable) -- Refresh
            end)

            group:AddChild(itemLabel)
            group:AddChild(catDropdown)
            group:AddChild(removeBtn)
            scroll:AddChild(group)
        end
    end

    -- 4. Create Manual Start Button (Pinned to Footer)
    if not self.btnStart then
        local parent = (self.lootFrame --[[@as any]]).frame

        self.btnStart = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        self.btnStart:SetText("Start Bidding")

        -- Keep the FrameLevel fix
        self.btnStart:SetFrameLevel(parent:GetFrameLevel() + 10)

        -- FIX 1: Alignment (Move UP to match Close button)
        -- Changing Y-offset from 12 to 16 usually hits the center line of the footer.
        self.btnStart:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 15, 16)

        -- FIX 2: Width (Stop stretching it)
        -- Instead of anchoring 'Right', we set a fixed width.
        -- This prevents it from looking "too long" or hitting the Close button.
        self.btnStart:SetWidth(200)
        self.btnStart:SetHeight(24) -- Standard WoW button height
    end

    self.btnStart:SetScript("OnClick", function()
        ---@type Distribution
        local Dist = DesolateLootcouncil:GetModule('Distribution') --[[@as Distribution]]
        Dist:StartSession(lootTable)
        self.lootFrame:Hide()
        self.btnStart:Hide()
    end)

    -- Ensure visibility
    self.btnStart:SetFrameLevel((self.lootFrame --[[@as any]]).frame:GetFrameLevel() + 10)
    self.btnStart:Show()

    -- 5. Update Resize Logic
    local function LayoutScroll()
        local windowHeight = (self.lootFrame --[[@as any]]).frame:GetHeight()
        -- Title(30) + ClearBtn(25) + Footer(45) = ~100
        local scrollHeight = windowHeight - 100

        if scrollHeight < 50 then scrollHeight = 50 end

        scroll:SetHeight(scrollHeight)
        self.lootFrame:DoLayout()
    end

    LayoutScroll()
    self.lootFrame:SetCallback("OnResize", LayoutScroll)

    self:Print(string.format("[DLC-UI] Loot Window Populated with %d items", count))
end

function UI:CreateVotingFrame()
    ---@type AceGUIFrame
    local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
    frame:SetTitle("Loot Vote")
    frame:SetLayout("Flow")
    frame:SetWidth(550) -- Wider width as requested
    frame:SetHeight(400)
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)
    self.votingFrame = frame

    -- Ensure vote storage exists
    self.myVotes = self.myVotes or {}
end

function UI:ShowVotingWindow(lootTable)
    if not self.votingFrame then
        self:CreateVotingFrame()
    end

    -- Sync self.myVotes just in case
    self.myVotes = self.myVotes or {}

    self.votingFrame:Show()
    self.votingFrame:ReleaseChildren()

    -- ScrollFrame
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.votingFrame:AddChild(scroll)

    -- Constants for formatting
    local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "Transmog", [4] = "Pass" }
    local VOTE_COLOR = { [1] = "|cff00ff00", [2] = "|cffffd700", [3] = "|cffeda55f", [4] = "|cffaaaaaa" } -- Transmog changed to orange-ish

    if lootTable then
        for i, data in ipairs(lootTable) do
            local link = data.link
            local guid = data.sourceGUID or link -- Fallback to link if guid missing

            -- Row Group
            ---@type AceGUISimpleGroup
            local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            group:SetLayout("Flow")
            group:SetFullWidth(true)

            -- Item Icon/Link
            ---@type AceGUIInteractiveLabel
            local itemLabel = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
            itemLabel:SetText(link)
            itemLabel:SetRelativeWidth(0.35)
            itemLabel:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            itemLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)

            group:AddChild(itemLabel)

            -- Logic Switch
            local currentVote = self.myVotes[guid]

            if not currentVote then
                -- STATE A: No Vote Yet - Draw Buttons
                local function CastVote(value)
                    self.myVotes[guid] = value

                    -- Send Packet
                    ---@type Distribution
                    local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
                    if Dist and Dist.SendVote then
                        Dist:SendVote(guid, value)
                    else
                        -- Stub safety
                        DesolateLootcouncil:Print("[Debug] Would transmit vote " .. value .. " for " .. guid)
                    end

                    -- Refresh
                    self:ShowVotingWindow(lootTable)
                end

                ---@type AceGUIButton
                local btnBid = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btnBid:SetText("Bid")
                btnBid:SetRelativeWidth(0.15)
                btnBid:SetCallback("OnClick", function() CastVote(1) end)

                ---@type AceGUIButton
                local btnRoll = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btnRoll:SetText("Roll")
                btnRoll:SetRelativeWidth(0.15)
                btnRoll:SetCallback("OnClick", function() CastVote(2) end)

                ---@type AceGUIButton
                local btnTransmog = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btnTransmog:SetText("Transmog")
                btnTransmog:SetRelativeWidth(0.20) -- Increased to 0.20 (Total 1.0)
                btnTransmog:SetCallback("OnClick", function() CastVote(3) end)

                ---@type AceGUIButton
                local btnPass = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btnPass:SetText("Pass")
                btnPass:SetRelativeWidth(0.15)
                btnPass:SetCallback("OnClick", function() CastVote(4) end)

                group:AddChild(btnBid)
                group:AddChild(btnRoll)
                group:AddChild(btnTransmog)
                group:AddChild(btnPass)
            else
                -- STATE B: Already Voted - Show Result & Change Option
                ---@type AceGUILabel
                local resultLabel = AceGUI:Create("Label") --[[@as AceGUILabel]]
                local voteStr = VOTE_TEXT[currentVote] or "?"
                local color = VOTE_COLOR[currentVote] or "|cffffffff"
                resultLabel:SetText("Chosen option: " .. color .. voteStr .. "|r")
                resultLabel:SetRelativeWidth(0.40)

                ---@type AceGUIButton
                local changeBtn = AceGUI:Create("Button") --[[@as AceGUIButton]]
                changeBtn:SetText("Change Vote")
                changeBtn:SetRelativeWidth(0.25)
                changeBtn:SetCallback("OnClick", function()
                    -- 1. Send Retraction Signal (Vote Type 0)
                    ---@type Distribution
                    local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
                    if Dist and Dist.SendVote then
                        Dist:SendVote(guid, 0) -- 0 means "Cancel/Retract"
                    end

                    -- 2. Clear Local State
                    self.myVotes[guid] = nil
                    self:ShowVotingWindow(lootTable)
                end)

                group:AddChild(resultLabel)
                group:AddChild(changeBtn)
            end

            scroll:AddChild(group)
        end
    end
end

function UI:ShowMonitorWindow()
    if not self.monitorFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Session Monitor")
        frame:SetLayout("Flow")
        frame:SetWidth(600)
        frame:SetHeight(400)
        frame:SetCallback("OnClose", function(widget)
            widget:Hide()
        end)
        self.monitorFrame = frame
    end

    self.monitorFrame:Show()
    self.monitorFrame:ReleaseChildren()

    -- Helper to count votes
    local function GetVoteCounts(guid)
        ---@type Distribution
        local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
        local votes = Dist and Dist.sessionVotes and Dist.sessionVotes[guid]

        local bids, rolls, tm, pass = 0, 0, 0, 0
        if votes then
            for _, voteType in pairs(votes) do
                if voteType == 1 then
                    bids = bids + 1
                elseif voteType == 2 then
                    rolls = rolls + 1
                elseif voteType == 3 then
                    tm = tm + 1
                elseif voteType == 4 then
                    pass = pass + 1
                end
            end
        end
        return string.format("Bids: %d | Rolls: %d | TM: %d | Pass: %d", bids, rolls, tm, pass)
    end

    -- Data Source: Session Bidding List
    local session = DesolateLootcouncil.db.profile.session
    local items = session.bidding

    -- ScrollFrame
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.monitorFrame:AddChild(scroll)

    if items then
        for i, data in ipairs(items) do
            local link = data.link
            local guid = data.sourceGUID or link

            -- Row
            ---@type AceGUISimpleGroup
            local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            group:SetLayout("Flow")
            group:SetFullWidth(true)

            -- 1. Item Link (0.5)
            ---@type AceGUIInteractiveLabel
            local labelLink = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
            labelLink:SetText(link)
            labelLink:SetRelativeWidth(0.50)
            labelLink:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            labelLink:SetCallback("OnLeave", function() GameTooltip:Hide() end)

            -- 2. Counts (0.3)
            ---@type AceGUILabel
            local labelCounts = AceGUI:Create("Label") --[[@as AceGUILabel]]
            labelCounts:SetText(GetVoteCounts(guid))
            labelCounts:SetRelativeWidth(0.30)
            labelCounts:SetColor(1, 1, 1) -- White

            -- 3. Award Button (0.2)
            ---@type AceGUIButton
            local btnAward = AceGUI:Create("Button") --[[@as AceGUIButton]]
            btnAward:SetText("Award")
            btnAward:SetRelativeWidth(0.20)
            btnAward:SetCallback("OnClick", function()
                self:ShowAwardWindow(data)
            end)

            group:AddChild(labelLink)
            group:AddChild(labelCounts)
            group:AddChild(btnAward)
            scroll:AddChild(group)
        end
    end
end

function UI:ShowAwardWindow(itemData)
    if not self.awardFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Award Item")
        frame:SetLayout("Flow")
        frame:SetWidth(400)
        frame:SetHeight(450)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.awardFrame = frame
    end

    self.awardFrame:Show()
    self.awardFrame:ReleaseChildren()

    -- Header: Item Link
    ---@type AceGUILabel
    local header = AceGUI:Create("Label") --[[@as AceGUILabel]]
    header:SetText(itemData.link)
    header:SetFullWidth(true)
    header:SetJustifyH("CENTER")
    header:SetFontObject(GameFontNormalLarge)
    self.awardFrame:AddChild(header)

    -- Data Source: Votes
    ---@type Distribution
    local Dist = DesolateLootcouncil:GetModule("Distribution") --[[@as Distribution]]
    local votes = Dist and Dist.sessionVotes and Dist.sessionVotes[itemData.sourceGUID]

    -- Scroll for Voters
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.awardFrame:AddChild(scroll)

    -- Flatten and Sort Votes
    local voteList = {}
    if votes then
        for voter, voteType in pairs(votes) do
            table.insert(voteList, { name = voter, type = voteType })
        end
        table.sort(voteList, function(a, b)
            if a.type == b.type then return a.name < b.name end
            return a.type < b.type -- 1 (Bid) < 2 (Roll) < 3 (TM) < 4 (Pass)
        end)
    end

    local VOTE_COLOR = { [1] = "|cff00ff00", [2] = "|cffffd700", [3] = "|cffeda55f", [4] = "|cffaaaaaa" }
    local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "Transmog", [4] = "Pass" }

    if #voteList == 0 then
        local lbl = AceGUI:Create("Label") --[[@as AceGUILabel]]
        lbl:SetText("No votes cast yet.")
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    else
        for _, v in ipairs(voteList) do
            ---@type AceGUISimpleGroup
            local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            row:SetLayout("Flow")
            row:SetFullWidth(true)

            -- Name (0.4)
            ---@type AceGUILabel
            local lblName = AceGUI:Create("Label") --[[@as AceGUILabel]]
            lblName:SetText(v.name)
            lblName:SetRelativeWidth(0.40)

            -- Response (0.3)
            ---@type AceGUILabel
            local lblResp = AceGUI:Create("Label") --[[@as AceGUILabel]]
            local color = VOTE_COLOR[v.type] or ""
            local txt = VOTE_TEXT[v.type] or "?"
            lblResp:SetText(color .. txt .. "|r")
            lblResp:SetRelativeWidth(0.30)

            -- Give Button (0.3)
            ---@type AceGUIButton
            local btnGive = AceGUI:Create("Button") --[[@as AceGUIButton]]
            btnGive:SetText("Give")
            btnGive:SetRelativeWidth(0.30)
            btnGive:SetCallback("OnClick", function()
                self.awardFrame:Hide()
                ---@type Loot
                local Loot = DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
                if Loot.AwardItem then
                    local voteDesc = VOTE_TEXT[v.type] or "Unknown"
                    Loot:AwardItem(itemData.sourceGUID, v.name, voteDesc)
                else
                    DesolateLootcouncil:Print("Loot:AwardItem not implemented yet for " .. v.name)
                end
            end)

            row:AddChild(lblName)
            row:AddChild(lblResp)
            row:AddChild(btnGive)
            scroll:AddChild(row)
        end
    end
end

function UI:ShowHistoryWindow()
    if not self.historyFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Session History")
        frame:SetLayout("Flow")
        frame:SetWidth(400)
        frame:SetHeight(300)
        -- Fix 'anchor family connection' error by clearing points first
        -- We use the underlying Blizzard frame (.frame) to ensure a clean state
        local blizzardFrame = (frame --[[@as any]]).frame
        blizzardFrame:ClearAllPoints()
        blizzardFrame:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.historyFrame = frame
    end

    self.historyFrame:Show()
    self.historyFrame:ReleaseChildren()

    local session = DesolateLootcouncil.db.profile.session
    local awarded = session.awarded

    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.historyFrame:AddChild(scroll)

    if awarded then
        for _, item in ipairs(awarded) do
            ---@type AceGUISimpleGroup
            local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            row:SetLayout("Flow")
            row:SetFullWidth(true)

            -- Icon (Using Label with Image)
            ---@type AceGUILabel
            local icon = AceGUI:Create("Label") --[[@as AceGUILabel]]
            icon:SetText(" ")
            icon:SetImage(item.texture)
            icon:SetImageSize(16, 16)
            icon:SetWidth(24)

            -- Text: Link -> Winner (Colorized)
            ---@type AceGUIInteractiveLabel
            local text = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
            local class = item.winnerClass
            local classColor = class and RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr or "ffffffff"

            text:SetText(item.link .. " -> |c" .. classColor .. item.winner .. "|r")
            text:SetRelativeWidth(0.60)
            text:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(item.link)
                GameTooltip:Show()
            end)
            text:SetCallback("OnLeave", function() GameTooltip:Hide() end)

            -- Info: Type
            ---@type AceGUILabel
            local info = AceGUI:Create("Label") --[[@as AceGUILabel]]
            info:SetText("(" .. (item.voteType or "?") .. ")")
            info:SetRelativeWidth(0.30)
            info:SetColor(0.7, 0.7, 0.7)

            row:AddChild(icon)
            row:AddChild(text)
            row:AddChild(info)
            scroll:AddChild(row)
        end
    end

    -- Auto-scroll to bottom (hacky but effective for AceGUI)
    -- We schedule it for next frame to ensure layout is done
    C_Timer.After(0.1, function()
        local status = (scroll --[[@as any]]).localstatus
        if status then
            status.scrollvalue = 10000 -- Force to bottom
            scroll:SetScroll(10000)    -- Trigger update
        end
    end)
end

function UI:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DLC-UI]|r " .. tostring(msg))
end
