-- Tests/Unit/TestMock.lua
-- A simple mocking framework to simulate WoW and AceAddon environment

---@diagnostic disable: undefined-global
-- Mock Global WoW Functions
StaticPopupDialogs = {}
function StaticPopup_Show(name) end

function GetRealmName() return "TestRealm" end

function time() return os.time() end

function date(fmt) return os.date(fmt) or "Date" end

function GetServerTime() return os.time() end

function LoadModule(path)
    local f = io.open(path, "r")
    if not f then error("Could not open " .. path) end
    local content = f:read("*all")
    f:close()

    local chunk, err
    if _VERSION == "Lua 5.1" then
        chunk, err = loadstring(content)
    else
        chunk, err = load(content)
    end

    if not chunk then error("Syntax Error in " .. path .. ": " .. err) end
    chunk()
end

function wipe(t)
    if not t then return end
    for k in pairs(t) do t[k] = nil end
    return t
end

---@diagnostic enable: undefined-global

function GetNumGroupMembers() return 5 end

function UnitName(u)
    if u == "player" then return "SimPlayer" end
    if u == "NPC" then return "TradeTarget" end
    return "Unknown"
end

function UnitClassBase(u) return "WARRIOR", "WARRIOR" end

function CreateFrame(type, name, parent, template)
    return {
        GetName = function() return name or "Frame" end,
        SetPoint = function() end,
        ClearAllPoints = function() end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        SetWidth = function() end,
        SetHeight = function() end,
        GetWidth = function() return 100 end,
        GetHeight = function() return 100 end,
        Hide = function() end,
        Show = function() end,
        SetScript = function() end,
        EnableMouse = function() end,
        SetMovable = function() end,
        RegisterForDrag = function() end,
    }
end

C_Container = {
    GetContainerNumSlots = function(bag) return 16 end,
    GetContainerItemInfo = function(bag, slot)
        -- Mock specific item in Bag 0 Slot 1
        if bag == 0 and slot == 1 then
            return { itemID = 12345, isLocked = false, iconFileID = 123 }
        end
        return nil
    end,
    UseContainerItem = function(bag, slot)
        -- print("Used Container Item", bag, slot)
    end
}

function IsInRaid() return true end

function UnitIsGroupLeader() return true end

function UnitIsGroupAssistant() return false end

function SendChatMessage(msg, channel)
    -- print("[CHAT]", channel, msg)
end

function C_Item() end

C_Item = {
    GetItemInfo = function(Link) return "TestItem", Link, 4, 1, 1, "Type", "SubType", 1, "Loc", 12345, 1 end,
    GetItemInfoInstant = function(Link) return 12345, "Type", "SubType", 1, 12345, 4, 1 end
}

C_Timer = {
    After = function(duration, callback)
        if callback then callback() end
    end
}

C_ChatInfo = {
    SendChatMessage = function(msg, channel, lang, target)
        -- print("[C_CHAT]", channel, target, msg)
    end,
    RegisterAddonMessagePrefix = function(prefix) return true end
}

function Ambiguate(name, context)
    if not name then return nil end
    return string.match(name, "^([^-]+)") or name
end

-- Mock LibStub and AceAddon
LibStub = {
    libs = {},
    GetLibrary = function(self, lib) return self.libs[lib] or {} end
}
setmetatable(LibStub, {
    __call = function(_, lib) return LibStub:GetLibrary(lib) end
})

-- Mock AceAddon-3.0
local AceAddon = {}
function AceAddon:GetAddon(name)
    return _G[name]
end

function AceAddon:NewAddon(name, ...)
    local addon = _G[name] or { name = name, modules = {} }

    -- Mixins
    function addon:NewModule(modName, ...)
        ---@class MockModule
        ---@field name string
        ---@field commHandler function|string
        local module = { name = modName }
        -- Apply Mixins
        function module:RegisterEvent(event, method) end

        function module:UnregisterEvent(event) end

        function module:SendMessage(message, ...) end

        -- Initialize for lint safety
        module.commHandler = nil

        function module:RegisterComm(prefix, method)
            self.commHandler = method
        end

        function module:Serialize(...)
            return { data = { ... } } -- Wrap in table to simulate "Serialized Object"
        end

        function module:Deserialize(data)
            -- Return success, unpack data
            if type(data) == "table" and data.data then
                return true, unpack(data.data)
            end
            return true, data
        end

        function module:SendCommMessage(prefix, data, channel, target)
            -- Loopback Router
            -- Find module that registered this prefix
            -- For this test, we assume DesolateLootcouncil modules
            for _, m in pairs(DesolateLootcouncil.modules) do
                ---@diagnostic disable-next-line: cast-type-mismatch
                ---@cast m MockModule
                if m.commHandler and prefix == "DLC_Loot" and (m.name == "Session" or m.name == "Loot") then
                    -- Dispatch
                    if type(m.commHandler) == "string" then
                        m[m.commHandler](m, prefix, data, channel, "SimPlayer")
                    else
                        m.commHandler(m, prefix, data, channel, "SimPlayer")
                    end
                end
            end
        end

        function module:ScheduleTimer(func, delay)
            if type(func) == "string" and self[func] then
                self[func](self)
            elseif type(func) == "function" then
                func()
            end
        end

        DesolateLootcouncil.modules[modName] = module
        return module
    end

    function addon:GetModule(modName)
        return self.modules[modName]
    end

    _G[name] = addon
    return addon
end

LibStub.libs["AceAddon-3.0"] = AceAddon

-- Mock AceConfigRegistry
LibStub.libs["AceConfigRegistry-3.0"] = {
    NotifyChange = function() end
}

-- Global Addon Stub
DesolateLootcouncil = AceAddon:NewAddon("DesolateLootcouncil")
DesolateLootcouncil.db = {
    profile = {
        PriorityLists = {},
        MainRoster = {},
        playerRoster = { alts = {} },
        History = {},
        PriorityLog = {},
        session = { bidding = {}, loot = {}, activeState = {}, awarded = {} }
    }
}

-- [NEW] Module Stubs for Refactored Code
local RosterStub = DesolateLootcouncil:NewModule("Roster")
function RosterStub:GetMain(name) return name end

function RosterStub:IsUnitInRaid(name) return true end

local PriorityStub = DesolateLootcouncil:NewModule("Priority")
function PriorityStub:MovePlayerToBottom(list, p) return 1 end

---@diagnostic disable: duplicate-set-field
DesolateLootcouncil.DLC_Log = function(self, msg)
    -- print("[LOG]", msg)
end
DesolateLootcouncil.AmILootMaster = function() return true end
DesolateLootcouncil.DetermineLootMaster = function() return "SimPlayer" end
DesolateLootcouncil.GetEnchantingSkillLevel = function(self) return 300 end
---@diagnostic enable: duplicate-set-field

-- Simple Assertion Framework
Assertions = {}
function Assertions.Equal(expected, actual, msg)
    if expected ~= actual then
        error(string.format("FAIL: %s - Expected: %s, Got: %s", msg or "", tostring(expected), tostring(actual)))
    else
        -- print(string.format("PASS: %s", msg or ""))
    end
end

function Assertions.True(condition, msg)
    if not condition then
        error(string.format("FAIL: %s - Expected True", msg or ""))
    end
end
