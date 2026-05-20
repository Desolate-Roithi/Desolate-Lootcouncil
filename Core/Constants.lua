local _, AT = ...
if AT.abortLoad then return end

---@class Constants
local Constants = {}

Constants.VERSION = C_AddOns.GetAddOnMetadata("Desolate_Lootcouncil", "Version")
Constants.DB_VERSION = "2.0"

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

DesolateLootcouncil.Constants = Constants
