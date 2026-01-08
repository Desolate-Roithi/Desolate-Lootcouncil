---@type UI
---@class (partial) DLC_Ref_UIUtility
---@field db table
---@field GetModule fun(self: DLC_Ref_UIUtility, name: string): any
---@field Print fun(self: DLC_Ref_UIUtility, msg: string)

---@type DLC_Ref_UIUtility
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_UIUtility]]
---@type UI
local UI = DesolateLootcouncil:GetModule("UI") --[[@as UI]]
local AceGUI = LibStub("AceGUI-3.0")

function UI:ShowHistoryWindow()
    if not self.historyFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Session History")
        frame:SetLayout("Flow")
        frame:SetWidth(500)
        frame:SetHeight(400)
        -- Fix 'anchor family connection' error
        local blizzardFrame = (frame --[[@as any]]).frame
        blizzardFrame:ClearAllPoints()
        blizzardFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.historyFrame = frame
    end

    self.historyFrame:Show()
    self.historyFrame:ReleaseChildren()

    local session = DesolateLootcouncil.db.profile.session
    local awarded = session.awarded or {}

    -- 1. Date Processing
    local dates = {}
    local dateMap = {}
    for _, item in ipairs(awarded) do
        local d = date("%Y-%m-%d", item.timestamp or time())
        if not dateMap[d] then
            dateMap[d] = true
            table.insert(dates, d)
        end
    end
    -- Sort Newest -> Oldest
    table.sort(dates, function(a, b) return a > b end)

    -- Default Selection
    if not self.selectedHistoryDate and #dates > 0 then
        self.selectedHistoryDate = dates[1]
    end
    -- Safety Check: If selected date no longer exists (deleted), reset
    if self.selectedHistoryDate and not dateMap[self.selectedHistoryDate] then
        if #dates > 0 then
            self.selectedHistoryDate = dates[1]
        else
            self.selectedHistoryDate = nil
        end
    end

    -- 2. UI Controls (Top Bar)
    ---@type AceGUISimpleGroup
    local controlGroup = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
    controlGroup:SetLayout("Flow")
    controlGroup:SetFullWidth(true)
    self.historyFrame:AddChild(controlGroup)

    -- Dropdown
    ---@type AceGUIDropdown
    local dateDropdown = AceGUI:Create("Dropdown") --[[@as AceGUIDropdown]]
    dateDropdown:SetLabel("Select Date")
    dateDropdown:SetRelativeWidth(0.5)

    local dropdownList = {}
    for _, d in ipairs(dates) do
        dropdownList[d] = d
    end
    dateDropdown:SetList(dropdownList)

    if self.selectedHistoryDate then
        dateDropdown:SetValue(self.selectedHistoryDate)
    end

    dateDropdown:SetCallback("OnValueChanged", function(widget, event, key)
        self.selectedHistoryDate = key
        self:ShowHistoryWindow()
    end)
    controlGroup:AddChild(dateDropdown)

    -- Delete Button
    ---@type AceGUIButton
    local btnDelete = AceGUI:Create("Button") --[[@as AceGUIButton]]
    btnDelete:SetText("Delete Date")
    btnDelete:SetRelativeWidth(0.3)
    btnDelete:SetCallback("OnClick", function()
        if not self.selectedHistoryDate then return end

        -- Filter Loop (Backwards safe removal)
        local countRemoved = 0
        for i = #awarded, 1, -1 do
            local item = awarded[i]
            local d = date("%Y-%m-%d", item.timestamp or time())
            if d == self.selectedHistoryDate then
                table.remove(awarded, i)
                countRemoved = countRemoved + 1
            end
        end

        DesolateLootcouncil:Print("Removed " .. countRemoved .. " entries for " .. self.selectedHistoryDate)
        self.selectedHistoryDate = nil -- Reset selection to force refresh logic
        self:ShowHistoryWindow()
    end)
    controlGroup:AddChild(btnDelete)

    -- 3. Scroll List
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.historyFrame:AddChild(scroll)

    local hasItems = false
    if self.selectedHistoryDate then
        -- Iterate backwards for display? Or forwards. Usually history is newest top.
        -- Let's do Newest Top (Backwards iteration matches standard "newest added is last" if list is append-only)
        -- Assuming 'awarded' is appended to, index 1 is oldest.
        for i = #awarded, 1, -1 do
            local item = awarded[i]
            local d = date("%Y-%m-%d", item.timestamp or time())

            if d == self.selectedHistoryDate then
                hasItems = true
                ---@type AceGUISimpleGroup
                local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
                row:SetLayout("Flow")
                row:SetFullWidth(true)

                -- Icon
                ---@type AceGUILabel
                local icon = AceGUI:Create("Label") --[[@as AceGUILabel]]
                icon:SetText(" ")
                icon:SetImage(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                icon:SetImageSize(16, 16)
                icon:SetWidth(24)

                -- Link -> Winner
                ---@type AceGUIInteractiveLabel
                local text = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
                local class = item.winnerClass
                local classColor = class and RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr or "ffffffff"

                text:SetText((item.link or "???") .. " -> |c" .. classColor .. (item.winner or "Unknown") .. "|r")
                text:SetRelativeWidth(0.50)
                text:SetCallback("OnEnter", function(widget)
                    if item.link then
                        GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                        GameTooltip:SetHyperlink(item.link)
                        GameTooltip:Show()
                    end
                end)
                text:SetCallback("OnLeave", function() GameTooltip:Hide() end)

                -- Type
                ---@type AceGUILabel
                local info = AceGUI:Create("Label") --[[@as AceGUILabel]]
                info:SetText("(" .. (item.voteType or "?") .. ")")
                info:SetRelativeWidth(0.20)
                info:SetColor(0.7, 0.7, 0.7)

                -- Re-award Button
                ---@type AceGUIButton
                local btnReaward = AceGUI:Create("Button")
                btnReaward:SetText("Re-award")
                btnReaward:SetRelativeWidth(0.20)
                btnReaward:SetCallback("OnClick", function()
                    ---@type Loot
                    local Loot = DesolateLootcouncil:GetModule("Loot")
                    if Loot and Loot.ReawardItem then
                        -- Need exact index logic, assuming 'i' matches 'awardIndex'
                        Loot:ReawardItem(i)
                    end
                end)

                row:AddChild(icon)
                row:AddChild(text)
                row:AddChild(info)
                row:AddChild(btnReaward)
                scroll:AddChild(row)
            end
        end
    end

    if not hasItems then
        local lbl = AceGUI:Create("Label") --[[@as AceGUILabel]]
        lbl:SetText("No entries for this date.")
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    end
end

function UI:RefreshTradeWindow()
    if self.historyFrame and self.historyFrame:IsShown() then
        self:ShowHistoryWindow()
    end
    if self.tradeListFrame and self.tradeListFrame:IsShown() then
        self:ShowTradeListWindow()
    end
end

function UI:ShowTradeListWindow()
    if not self.tradeListFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Pending Trades")
        frame:SetLayout("Flow")
        frame:SetWidth(450)
        frame:SetHeight(350)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.tradeListFrame = frame
    end

    self.tradeListFrame:Show()
    self.tradeListFrame:ReleaseChildren()

    local session = DesolateLootcouncil.db.profile.session
    local awarded = session.awarded

    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    self.tradeListFrame:AddChild(scroll)

    -- Smart Trade Helper
    local function GetUnitIDForName(playerName)
        for i = 1, 40 do
            local unit = "raid" .. i
            if GetUnitName(unit, true) == playerName then return unit end
        end
        for i = 1, 4 do
            local unit = "party" .. i
            if GetUnitName(unit, true) == playerName then return unit end
        end
        return nil
    end

    local pendingCount = 0

    if awarded then
        for _, item in ipairs(awarded) do
            if not item.traded then
                pendingCount = pendingCount + 1

                ---@type AceGUISimpleGroup
                local row = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
                row:SetLayout("Flow")
                row:SetFullWidth(true)

                -- Icon
                ---@type AceGUILabel
                local icon = AceGUI:Create("Label") --[[@as AceGUILabel]]
                icon:SetText(" ")
                icon:SetImage(item.texture)
                icon:SetImageSize(16, 16)
                icon:SetWidth(24)

                -- Link
                ---@type AceGUIInteractiveLabel
                local linkLabel = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
                linkLabel:SetText(item.link)
                linkLabel:SetRelativeWidth(0.45)
                linkLabel:SetCallback("OnEnter", function(widget)
                    GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                    GameTooltip:SetHyperlink(item.link)
                    GameTooltip:Show()
                end)
                linkLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)

                -- Winner
                ---@type AceGUILabel
                local winnerLabel = AceGUI:Create("Label") --[[@as AceGUILabel]]
                local class = item.winnerClass
                local classColor = class and RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr or "ffffffff"
                winnerLabel:SetText("|c" .. classColor .. item.winner .. "|r")
                winnerLabel:SetRelativeWidth(0.20)

                -- Trade Button
                ---@type AceGUIButton
                local btnTrade = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btnTrade:SetText("Trade")
                btnTrade:SetRelativeWidth(0.15)
                btnTrade:SetCallback("OnClick", function()
                    local unitID = GetUnitIDForName(item.winner)
                    -- 1. Try to find UnitID (Raid/Party)
                    if unitID and CheckInteractDistance(unitID, 2) then
                        InitiateTrade(unitID)
                        return
                    end
                    -- 2. Check if player already targets them manually
                    if UnitName("target") == item.winner then
                        if CheckInteractDistance("target", 2) then
                            InitiateTrade("target")
                        else
                            DesolateLootcouncil:Print("[DLC] " .. item.winner .. " is out of trade range.")
                        end
                        return
                    end
                    -- 3. Failure: Ask user to target manually
                    DesolateLootcouncil:Print("[DLC] Could not auto-target " ..
                        item.winner .. ". Please target them manually and click Trade again.")
                end)

                -- Remove Button
                ---@type AceGUIButton
                local btnRemove = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btnRemove:SetText("X")
                btnRemove:SetRelativeWidth(0.10)
                btnRemove:SetCallback("OnClick", function()
                    item.traded = true
                    DesolateLootcouncil:Print("[DLC] Marked " .. item.link .. " as traded.")
                    self:ShowTradeListWindow()
                end)

                row:AddChild(icon)
                row:AddChild(linkLabel)
                row:AddChild(winnerLabel)
                row:AddChild(btnTrade)
                row:AddChild(btnRemove)
                scroll:AddChild(row)
            end
        end
    end

    if pendingCount == 0 then
        local lbl = AceGUI:Create("Label") --[[@as AceGUILabel]]
        lbl:SetText("No pending trades.")
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    end
end
