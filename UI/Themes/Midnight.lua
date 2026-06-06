local _, AT = ...
if AT.abortLoad then return end

local UI_Theme = DesolateLootcouncil:GetModule("UI_Theme")
UI_Theme:RegisterTheme("Midnight", {
    name = "Midnight (Void)",
    bg = { 0.05, 0.03, 0.08, 0.90 },            -- Deep void obsidian-purple
    border = { 0.50, 0.25, 0.80, 1.0 },        -- Glowing neon purple border
    buttonBg = { 0.12, 0.08, 0.20, 0.9 },
    buttonHover = { 0.25, 0.15, 0.45, 1.0 },
    textHeader = { 0.75, 0.50, 1.0 },          -- Glowing light purple header text
    textNormal = { 0.90, 0.90, 0.95 },
    accent = { 0.60, 0.30, 0.90 }
})
