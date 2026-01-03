---@type UI
local UI = DesolateLootcouncil:GetModule("UI")
local AceGUI = LibStub("AceGUI-3.0")

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
                linkLabel:SetRelativeWidth(0.50)
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
                winnerLabel:SetRelativeWidth(0.25)

                -- Trade Button
                ---@type AceGUIButton
                local btnTrade = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btnTrade:SetText("Trade")
                btnTrade:SetRelativeWidth(0.20)
                btnTrade:SetCallback("OnClick", function()
                    local unitID = GetUnitIDForName(item.winner)

                    -- Scenario A: Found in group
                    if unitID and CheckInteractDistance(unitID, 2) then
                        InitiateTrade(unitID)
                        return
                    end

                    -- Scenario B: Fallback
                    TargetUnit(item.winner)
                    if UnitName("target") == item.winner and CheckInteractDistance("target", 2) then
                        InitiateTrade("target")
                        DesolateLootcouncil:Print("[DLC] Trading via target (UnitID not found).")
                    else
                        DesolateLootcouncil:Print("[DLC] " .. item.winner .. " is out of range or offline.")
                    end
                end)

                row:AddChild(icon)
                row:AddChild(linkLabel)
                row:AddChild(winnerLabel)
                row:AddChild(btnTrade)
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
