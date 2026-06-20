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

--- Parses a semantic version string into numeric components.
---@param v string
---@return number major, number minor, number patch, string suffix
function AT.ParseSemVer(v)
    if not v or v == "" then return 0, 0, 0, "" end
    local major, minor, patch, suffix = v:match("(%d+)%.(%d+)%.(%d+)%-?(.*)")
    if not major then return 0, 0, 0, "" end
    suffix = suffix or ""
    if suffix == "SIM" then suffix = "" end
    return tonumber(major), tonumber(minor), tonumber(patch), suffix
end

--- Compares two semantic version strings. Returns true if v1 > v2.
---@param v1 string
---@param v2 string
---@return boolean
function AT.CompareSemVer(v1, v2)
    local M1, m1, p1, s1 = AT.ParseSemVer(v1)
    local M2, m2, p2, s2 = AT.ParseSemVer(v2)
    if M1 ~= M2 then return M1 > M2 end
    if m1 ~= m2 then return m1 > m2 end
    if p1 ~= p2 then return p1 > p2 end
    if s1 == "" and s2 ~= "" then return true end
    if s1 ~= "" and s2 == "" then return false end
    if s1 ~= "" and s2 ~= "" then return s1:lower() > s2:lower() end
    return false
end

--- Strips realm suffix and lowercases a character name for stable comparison.
--- Equivalent to the local Normalize() helpers previously copy-pasted in
--- Core/Addon.lua:OnInitialize and Systems/Roster.lua:PLAYER_LOGIN.
---@param name string|nil
---@return string normalized lowercase realmless name, or "" if nil
function AT.NormalizeName(name)
    if not name then return "" end
    return string.lower(string.match(name, "^([^-]+)") or name)
end

DesolateLootcouncil.Math = Math
