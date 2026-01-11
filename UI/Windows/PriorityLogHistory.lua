---@class UI_PriorityLogHistory : AceModule
local UI_PriorityLogHistory = DesolateLootcouncil:NewModule("UI_PriorityLogHistory")
local AceGUI = LibStub("AceGUI-3.0")

function UI_PriorityLogHistory:ShowLogWindow()
    if not self.logFrame then
        local frame = AceGUI:Create("Frame")
        frame:SetTitle("Priority Log History")
        frame:SetLayout("Fill")
        frame:SetWidth(600)
        frame:SetHeight(400)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.logFrame = frame

        DesolateLootcouncil:RestoreFramePosition(frame, "PriorityHistory")
        local function SavePos(f) DesolateLootcouncil:SaveFramePosition(f, "PriorityHistory") end

        -- AceGUI "Frame" container exposes the raw frame via .frame
        local rawFrame = frame.frame
        rawFrame:HookScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            SavePos(frame)
        end)
        rawFrame:HookScript("OnHide", function(f) SavePos(frame) end)
        DesolateLootcouncil.Persistence:ApplyCollapseHook(frame, "PriorityHistory")
    end

    self.logFrame:Show()
    self.logFrame:ReleaseChildren()

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    self.logFrame:AddChild(scroll)

    local db = DesolateLootcouncil.db.profile
    local history = db.History or {}

    -- Show Newest First
    for i = #history, 1, -1 do
        local label = AceGUI:Create("Label")
        label:SetText(history[i])
        label:SetFullWidth(true)
        scroll:AddChild(label)
    end

    if #history == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("No history logs found.")
        label:SetFullWidth(true)
        scroll:AddChild(label)
    end
end
