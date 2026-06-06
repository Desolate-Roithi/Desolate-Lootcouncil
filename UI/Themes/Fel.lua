local _, AT = ...
if AT.abortLoad then return end

local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme")
UI_Theme:RegisterTheme("Fel", {
    name = "Emerald Fel",
    bg = { 0.04, 0.06, 0.04, 0.92 },            -- Dark green-black
    border = { 0.15, 0.70, 0.20, 1.0 },        -- Glowing fel-green border
    buttonBg = { 0.08, 0.15, 0.08, 0.9 },
    buttonHover = { 0.15, 0.30, 0.15, 1.0 },
    textHeader = { 0.30, 0.90, 0.30 },          -- Toxic fel green header text
    textNormal = { 0.85, 0.90, 0.85 },
    accent = { 0.20, 0.80, 0.20 }
})
