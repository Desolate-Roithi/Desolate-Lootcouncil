local _, AT = ...
if AT.abortLoad then return end

---@class Constants
local Constants = {}

Constants.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata) and C_AddOns.GetAddOnMetadata("Desolate_Lootcouncil", "Version") or "1.2.0"
Constants.DB_VERSION = "2.0"
Constants.CATALOG_TIER = "midnight-s2"
Constants.CATALOG_TIER_NAME = "Midnight Season 2"

Constants.COLORS = {
    GOLD = "ffffd700",
    GREY = "ff808080",
    WHITE = "ffffffff",
}

Constants.TEXTURES = {
    -- Add textures here
}


Constants.EVENTS = {
    SESSION_STARTED = "DLC_SESSION_STARTED",
    SESSION_STOPPED = "DLC_SESSION_STOPPED",
    SESSION_RESTORED = "DLC_SESSION_RESTORED",
    ITEM_CLOSED = "DLC_ITEM_CLOSED",
    ITEM_REMOVED = "DLC_ITEM_REMOVED",
    HISTORY_UPDATED = "DLC_HISTORY_UPDATED",
    LOOT_WINDOW_UPDATE = "DLC_LOOT_WINDOW_UPDATE",
}

Constants.DEFAULT_PRIORITY_LISTS = {
    {
        name = "Tier",
        players = {},
        items = {
            [270928] = true, [270913] = true, [270921] = true, [270929] = true,
            [270914] = true, [270922] = true, [270915] = true, [270923] = true,
            [270916] = true, [270924] = true, [270909] = true, [270917] = true,
            [270925] = true, [270910] = true, [270918] = true, [270926] = true,
            [270911] = true, [270919] = true, [270927] = true, [270912] = true,
            [270920] = true
        }
    },
    {
        name = "Weapons",
        players = {},
        items = {
            [268200] = true, [268208] = true, [268201] = true, [271092] = true,
            [268202] = true, [271093] = true, [268203] = true, [268211] = true,
            [268196] = true, [268204] = true, [268263] = true, [268262] = true,
            [268197] = true, [268205] = true, [268213] = true, [270930] = true,
            [268198] = true, [268206] = true, [268214] = true, [268264] = true,
            [268199] = true, [268207] = true, [268215] = true, [268209] = true,
            [268210] = true
        }
    },
    {
        name = "Rest",
        players = {},
        items = {
            [268222] = true, [268238] = true, [268254] = true, [268223] = true,
            [268239] = true, [268255] = true, [268224] = true, [268240] = true,
            [268256] = true, [268225] = true, [268241] = true, [268257] = true,
            [268226] = true, [268242] = true, [268258] = true, [268227] = true,
            [268243] = true, [268259] = true, [268228] = true, [268244] = true,
            [268260] = true, [268229] = true, [268245] = true, [268261] = true,
            [268230] = true, [268246] = true, [268231] = true, [268247] = true,
            [268216] = true, [268232] = true, [268248] = true, [268217] = true,
            [268233] = true, [268249] = true, [268218] = true, [268234] = true,
            [268250] = true, [268266] = true, [268219] = true, [268235] = true,
            [268251] = true, [268220] = true, [268236] = true, [268252] = true,
            [268237] = true, [268253] = true
        }
    },
    {
        name = "Collectables",
        players = {},
        items = {
            [268221] = true
        }
    },
    {
        name = "Trinkets and Cantrips",
        players = {},
        items = {
            [270161] = true, [271874] = true, [270162] = true, [271875] = true,
            [270163] = true, [271876] = true, [268265] = true, [270164] = true,
            [270165] = true, [270173] = true, [270166] = true, [270174] = true,
            [270170] = true, [270167] = true, [270175] = true, [270171] = true,
            [270160] = true, [270168] = true, [271878] = true, [270169] = true
        }
    },
    {
        name = "Recipes",
        players = {},
        items = {
            [273070] = true
        }
    }
}

function Constants.GetDefaultPriorityLists()
    local copy = {}
    for idx, list in ipairs(Constants.DEFAULT_PRIORITY_LISTS) do
        local listCopy = {
            name = list.name,
            players = {},
            items = {}
        }
        if list.items then
            for id, val in pairs(list.items) do
                listCopy.items[id] = val
            end
        end
        copy[idx] = listCopy
    end
    return copy
end

DesolateLootcouncil.Constants = Constants
