local _, AT = ...
if AT.abortLoad then return end

---@class Table
local Table = {}

-- Performs a deep copy of a table structure
function Table.DeepCopy(orig)
    local origType = type(orig)
    local copy
    if origType == 'table' then
        copy = {}
        for origKey, origValue in next, orig, nil do
            copy[Table.DeepCopy(origKey)] = Table.DeepCopy(origValue)
        end
        setmetatable(copy, Table.DeepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

--- Comparator for table.sort: numeric ascending if both values can be interpreted as numbers,
--- lexicographic string comparison otherwise.
---@param a any
---@param b any
---@return boolean
function Table.NumericSort(a, b)
    local numA = tonumber(a)
    local numB = tonumber(b)
    if numA and numB then
        return numA < numB
    end
    return tostring(a) < tostring(b)
end

DesolateLootcouncil.Table = Table
