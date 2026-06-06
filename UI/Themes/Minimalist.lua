local _, AT = ...
if AT.abortLoad then return end

local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme")
UI_Theme:RegisterTheme("Minimalist", {
    name = "Pure Dark (Minimal)",
    bg = { 0.07, 0.07, 0.07, 0.96 },            -- Flat coal black
    border = { 0.20, 0.20, 0.20, 1.0 },        -- Thin flat gray border
    buttonBg = { 0.14, 0.14, 0.14, 0.9 },
    buttonHover = { 0.25, 0.25, 0.25, 1.0 },
    textHeader = { 1.0, 1.0, 1.0 },            -- Pure white header text
    textNormal = { 0.85, 0.85, 0.85 },
    accent = { 0.50, 0.50, 0.50 }
})
