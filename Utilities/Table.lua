local _, AT = ...
if AT.abortLoad then return end

---@class Table
local Table = {}

-- Performs a deep copy of a table structure
function Table.DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Table.DeepCopy(orig_key)] = Table.DeepCopy(orig_value)
        end
        setmetatable(copy, Table.DeepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

DesolateLootcouncil.Table = Table
