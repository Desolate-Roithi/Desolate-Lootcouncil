---@class Logger
local Logger = {}

---@param msg string
---@param force? boolean
function Logger.Log(msg, force)
    local db = DesolateLootcouncil.db.profile
    if (db and db.debugMode) or force then
        DesolateLootcouncil:Print(msg)
    end
end

DesolateLootcouncil.Logger = Logger
