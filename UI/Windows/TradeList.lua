---@class UI_TradeList : AceModule
local UI_TradeList = DesolateLootcouncil:NewModule("UI_TradeList")
local AceGUI = LibStub("AceGUI-3.0")

function UI_TradeList:ShowTradeListWindow()
    if not self.tradeListFrame then
        ---@type AceGUIFrame
        local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
        frame:SetTitle("Pending Trades")
        frame:SetLayout("Flow")
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.tradeListFrame = frame

        -- [NEW] Position Persistence
        DesolateLootcouncil:RestoreFramePosition(frame, "Trade")
        local function SavePos(f)
            DesolateLootcouncil:SaveFramePosition(f, "Trade")
        end
        local rawFrame = (frame --[[@as any]]).frame
        rawFrame:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            SavePos(frame)
        end)
        rawFrame:SetScript("OnHide", function() SavePos(frame) end)
        DesolateLootcouncil.Persistence:ApplyCollapseHook(frame, "Trade")
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
                            DesolateLootcouncil:DLC_Log(item.winner .. " is out of trade range.")
                        end
                        return
                    end
                    -- 3. Failure: Ask user to target manually
                    DesolateLootcouncil:DLC_Log("Could not auto-target " ..
                        item.winner .. ". Please target them manually and click Trade again.", true)
                end)

                -- Remove Button
                ---@type AceGUIButton
                local btnRemove = AceGUI:Create("Button") --[[@as AceGUIButton]]
                btnRemove:SetText("X")
                btnRemove:SetRelativeWidth(0.10)
                btnRemove:SetCallback("OnClick", function()
                    item.traded = true
                    DesolateLootcouncil:DLC_Log("Marked " .. item.link .. " as traded.")
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
