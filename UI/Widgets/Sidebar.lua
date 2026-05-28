local _, AT = ...
if AT.abortLoad then return end

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

    -- Apply active theme backdrop matching CreateWindow/ApplyTheme style
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(theme.bg[1] * 0.9, theme.bg[2] * 0.9, theme.bg[3] * 0.9, 0.95)
    f:SetBackdropBorderColor(unpack(theme.border))

    -- Add Title
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, -10)
    t:SetText("Disenchanters")
    t:SetTextColor(unpack(theme.border))
    f.titleText = t

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
 
    local disenchanters = DesolateLootcouncil.API:GetDisenchanterList()
 
    if #disenchanters == 0 then
        sidebarFrame.content:SetText("|cff9d9d9dNo data.\nScanning...|r")
    else
        local listString = ""
        for _, de in ipairs(disenchanters) do
            listString = listString .. string.format("%s (|cff00ff00%d|r)\n", DesolateLootcouncil.API:GetDisplayName(de.name), de.skill)
        end
        sidebarFrame.content:SetText(listString)
    end
end
