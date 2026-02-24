---@class UI_Sidebar : AceModule
local UI_Sidebar = DesolateLootcouncil:NewModule("UI_Sidebar")

---@class (partial) DLC_Ref_UISidebar
---@field db table
---@field GetModule fun(self: DLC_Ref_UISidebar, name: string): any
---@field Print fun(self: DLC_Ref_UISidebar, msg: string)

---@type DLC_Ref_UISidebar
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_UISidebar]]

function UI_Sidebar:AttachTo(parentFrame)
    if not parentFrame then return nil end
    local monitorRawFrame = parentFrame.frame or parentFrame

    local f = CreateFrame("Frame", nil, monitorRawFrame, "BackdropTemplate")
    f:SetSize(160, 300)
    -- Anchor to the RIGHT SIDE of the Monitor
    f:SetPoint("TOPLEFT", monitorRawFrame, "TOPRIGHT", 5, 0)

    -- Add Backdrop (Black background)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0, 0, 0, 1)

    -- Add Title
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, -10)
    t:SetText("Disenchanters")

    -- Add Content FontString (Left Aligned)
    local c = f:CreateFontString(nil, "OVERLAY", "GameFontWhiteSmall")
    c:SetPoint("TOPLEFT", 10, -30)
    c:SetJustifyH("LEFT")
    f.content = c -- Store reference to update text later

    f.content:SetText("|cff9d9d9dNo data.\nScanning...|r")

    return f
end

function UI_Sidebar:UpdateDisenchanters(sidebarFrame)
    if not sidebarFrame or not sidebarFrame.content then return end

    local Comm = DesolateLootcouncil:GetModule("Comm")
    local disenchanters = {}

    if Comm and Comm.playerEnchantingSkill then
        for name, skill in pairs(Comm.playerEnchantingSkill) do
            if skill then
                table.insert(disenchanters, { name = name, skill = skill })
            end
        end

        table.sort(disenchanters, function(a, b) return a.skill > b.skill end)
    end

    if #disenchanters == 0 then
        sidebarFrame.content:SetText("|cff9d9d9dNo data.\nScanning...|r")
    else
        local listString = ""
        for _, de in ipairs(disenchanters) do
            listString = listString .. string.format("%s (|cff00ff00%d|r)\n", de.name, de.skill)
        end
        sidebarFrame.content:SetText(listString)
    end
end
