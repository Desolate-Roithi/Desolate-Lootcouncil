local _, AT = ...
if AT.abortLoad then return end

---@class Logger
local Logger = {}

---@param msg string
---@param force? boolean
function Logger.Log(msg, force)
    local db = DesolateLootcouncil.db.profile
    local isDebug = db and db.debugMode
    
    -- Allow logging if:
    -- 1. We are in a group (standard behavior)
    -- 2. OR it's a 'forced' log (like simulation results or config changes)
    -- 3. OR Debug Mode is explicitly enabled
    if IsInGroup() or force or isDebug then
        if isDebug or force then
            DesolateLootcouncil:Print(msg)
        end
    end
end

DesolateLootcouncil.Logger = Logger
