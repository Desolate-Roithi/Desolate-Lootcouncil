local _, AT = ...
if AT.abortLoad then return end

---@class Math
local Math = {}

-- Shuffle Helper (Fisher-Yates)
function Math.ShuffleTable(t)
    local n = #t
    for i = n, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

DesolateLootcouncil.Math = Math
