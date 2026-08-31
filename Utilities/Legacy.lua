local _, AT = ...
if AT.abortLoad then return end

-- Utilities/Legacy.lua
-- Superseded by Core/DBMigrator.lua (schema v200 migrations) and Utilities/Serializer.lua.
-- Retained for add-on namespace backward-safety.

local Legacy = {}
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
DesolateLootcouncil.Legacy = Legacy
