local _, AT = ...
if AT.abortLoad then return end

---@diagnostic disable: undefined-field
---@class UI_PriorityLogHistory : AceModule
local UI_PriorityLogHistory = DesolateLootcouncil:NewModule("UI_PriorityLogHistory")
local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

function UI_PriorityLogHistory:ShowLogWindow()
    if not self.logFrame then
        local frame = AceGUI:Create("Frame") --[[@as any]]
        frame:SetTitle(L["Priority Log History"])
        frame:SetLayout("Fill")
        frame:SetWidth(600)
        frame:SetHeight(400)
        frame:SetCallback("OnClose", function(widget) widget:Hide() end)
        self.logFrame = frame

        -- [NEW] Position Persistence
        DesolateLootcouncil:MakeMovableWithSave(frame, "PriorityHistory")
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
        label:SetText(L["No history logs found."])
        label:SetFullWidth(true)
        scroll:AddChild(label)
    end
end
