local _, AT = ...
if AT.abortLoad then return end

local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme")
UI_Theme:RegisterTheme("Classic", {
    name = "Classic Slate",
    bg = { 0.10, 0.12, 0.16, 0.95 },            -- Dark steel slate blue
    border = { 0.30, 0.40, 0.55, 1.0 },        -- Cool blue border
    buttonBg = { 0.18, 0.20, 0.26, 0.9 },
    buttonHover = { 0.25, 0.30, 0.40, 1.0 },
    textHeader = { 0.60, 0.80, 1.0 },          -- Light blue header text
    textNormal = { 0.90, 0.90, 0.90 },
    accent = { 0.40, 0.60, 0.90 }
})
