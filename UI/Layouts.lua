local _, AT = ...
if AT.abortLoad then return end

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]

DesolateLootcouncil.DefaultLayouts = {
    ["Config"] = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
        width = 800,
        height = 600
    },
    ["Loot"] = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 250,
        width = 400,
        height = 500
    },
    ["Monitor"] = {
        point = "TOPRIGHT",
        relativePoint = "CENTER",
        x = 900,
        y = 400,
        width = 650,
        height = 400
    },
    ["Trade"] = {
        point = "TOPRIGHT",
        relativePoint = "CENTER",
        x = 250,
        y = 400,
        width = 400,
        height = 350
    },
    ["Voting"] = {
        point = "LEFT",
        relativePoint = "CENTER",
        x = -1000,
        y = 250,
        width = 800,
        height = 350
    },
    ["SessionHistory"] = {
        point = "TOPRIGHT",
        relativePoint = "CENTER",
        x = 900,
        y = -0,
        width = 400,
        height = 300
    },
    ["PriorityOverride"] = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 550,
        y = 100,
        width = 300,
        height = 400
    },
    ["Version"] = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
        width = 370,
        height = 400
    },
    ["Attendance"] = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
        width = 640,
        height = 480
    },
    ["Award"] = {
        point = "TOPRIGHT",
        relativePoint = "CENTER",
        x = 250,
        y = 400,
        width = 500,
        height = 350
    },
    ["PriorityHistory"] = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 700,
        y = 100,
        width = 600,
        height = 400
    },
    ["ItemManager"] = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
        width = 600,
        height = 500
    },
    ["RaidHistory"] = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
        width = 680,
        height = 520
    },
}
