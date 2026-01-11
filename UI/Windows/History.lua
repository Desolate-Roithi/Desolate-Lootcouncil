---@class UI_History : AceModule
local UI_History = DesolateLootcouncil:NewModule("UI_History")
local AceGUI = LibStub("AceGUI-3.0")

function UI_History:ShowHistoryWindow()
    if not self.historyFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Session History")
        frame:SetLayout("Flow")
        frame:SetWidth(500)
        frame:SetHeight(400)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)

        self.historyFrame = frame

        -- Position Persistence
        DesolateLootcouncil:RestoreFramePosition(frame, "History")
        local function SavePos(f)
            DesolateLootcouncil:SaveFramePosition(f, "History")
        end
        local rawFrame = (frame --[[@as any]]).frame
        rawFrame:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            SavePos(frame)
        end)
        rawFrame:SetScript("OnHide", function() SavePos(frame) end)
        DesolateLootcouncil.Persistence:ApplyCollapseHook(frame)
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

        DesolateLootcouncil:DLC_Log("Removed " .. countRemoved .. " entries for " .. self.selectedHistoryDate)
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
