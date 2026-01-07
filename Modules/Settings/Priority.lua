---@class (partial) DLC_Ref_PrioritySettings
---@field db table
---@field NewModule fun(self: DLC_Ref_PrioritySettings, name: string): any
---@field ShowPriorityOverrideWindow fun(self: DLC_Ref_PrioritySettings, listName: string)
---@field AddPriorityList fun(self: DLC_Ref_PrioritySettings, name: string)
---@field GetPriorityListNames fun(self: DLC_Ref_PrioritySettings): table
---@field RenamePriorityList fun(self: DLC_Ref_PrioritySettings, index: number, newName: string)
---@field RemovePriorityList fun(self: DLC_Ref_PrioritySettings, index: number)
---@field ShuffleLists fun(self: DLC_Ref_PrioritySettings)
---@field SyncMissingPlayers fun(self: DLC_Ref_PrioritySettings)
---@field ShowHistoryWindow fun(self: DLC_Ref_PrioritySettings)

---@type DLC_Ref_PrioritySettings
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_PrioritySettings]]
local PrioritySettings = DesolateLootcouncil:NewModule("PrioritySettings") --[[@as PrioritySettings]]

---@class PrioritySettings : AceModule
---@field GetOptions function
---@field GetPriorityListConfig function
---@field GetManagementArgs function
---@field GenerateListOptions function
---@field toggles table
---@field OnEnable function
---@field newListInput string
---@field priorityListDropdown string|integer

-- Volatile storage for UI toggle states (Reset on login)
PrioritySettings.toggles = {
    Tier = false,
    Weapons = false,
    Rest = false,
    Collectables = false
}

function PrioritySettings:OnEnable()
    -- Ensure we start with everything hidden
    self.toggles = {
        Tier = false,
        Weapons = false,
        Rest = false,
        Collectables = false
    }
end

local function GetListDisplayText(listName)
    local db = DesolateLootcouncil.db.profile
    if not db then return "Loading..." end

    -- Find by name
    local list = nil
    if db.PriorityLists then
        for _, obj in ipairs(db.PriorityLists) do
            if obj.name == listName then
                list = obj.players
                break
            end
        end
    end

    if not list or #list == 0 then return "List is empty. Click Shuffle to start." end

    local text = ""
    for i, name in ipairs(list) do
        text = text .. "Rank #" .. i .. ": |cffffd700" .. name .. "|r\n"
    end
    return text
end

function PrioritySettings:GenerateListOptions(listName, orderOffset)
    local args = {}

    -- Toggle Button
    args.btnToggle = {
        type = "execute",
        name = function() return self.toggles[listName] and "Hide Content" or "Show Content" end,
        order = 1,
        func = function() self.toggles[listName] = not self.toggles[listName] end,
    }

    -- Override Button
    args.btnOverride = {
        type = "execute",
        name = "Manual Override (Drag & Drop)",
        order = 2,
        func = function() DesolateLootcouncil:ShowPriorityOverrideWindow(listName) end,
    }

    -- Display Content
    args.display = {
        type = "description",
        name = function() return GetListDisplayText(listName) end,
        order = 3,
        hidden = function() return not self.toggles[listName] end,
        fontSize = "medium",
    }

    return {
        type = "group",
        name = listName,
        inline = true,
        order = orderOffset,
        args = args,
    }
end

-- Generator for Configuration Tab
function PrioritySettings:GetPriorityListConfig()
    local args = {}

    -- ADD NEW LIST
    args.headerAdd = { type = "header", name = "Create New List", order = 1 }
    args.inputNewList = {
        type = "input",
        name = "List Name",
        desc = "Enter a name for the new priority list.",
        order = 2,
        set = function(_, val) self.newListInput = val end,
        get = function() return self.newListInput end,
    }
    args.btnAddList = {
        type = "execute",
        name = "Add List",
        order = 3,
        func = function()
            if self.newListInput and self.newListInput ~= "" then
                DesolateLootcouncil:AddPriorityList(self.newListInput)
                self.newListInput = ""
            end
        end,
    }

    -- MANAGE EXISTING LISTS
    args.headerManage = { type = "header", name = "Manage Existing Lists", order = 10 }

    local listNames = DesolateLootcouncil:GetPriorityListNames()
    for i, name in ipairs(listNames) do
        local groupArgs = {}

        -- Rename Input
        groupArgs.inputRename = {
            type = "input",
            name = "Rename To:",
            order = 1,
            set = function(_, val) DesolateLootcouncil:RenamePriorityList(i, val) end,
            get = function() return "" end, -- Dont persist text in input
            width = "half",
        }

        -- Delete Button
        groupArgs.btnDelete = {
            type = "execute",
            name = "Delete List",
            order = 2,
            confirm = true,
            confirmText = "Are you sure you want to delete this list? This cannot be undone.",
            func = function() DesolateLootcouncil:RemovePriorityList(i) end,
            width = "half",
        }

        args["group" .. i] = {
            type = "group",
            name = name,
            inline = true,
            order = 10 + i,
            args = groupArgs,
        }
    end

    return args
end

-- Generator for Management Tab
function PrioritySettings:GetManagementArgs()
    local args = {
        intro = {
            type = "description",
            name =
            "Manage seasonal Priority Lists. Use the 'Sync' button to add new roster members without re-shuffling.",
            order = 0,
        },
        headerSeason = { type = "header", name = "Season Management", order = 10 },
        btnShuffle = {
            type = "execute",
            name = "Shuffle / Start Season",
            desc = "CRITICAL: This will reset and shuffle ALL priority lists based on the current Master Roster.",
            order = 11,
            confirm = true,
            confirmText = "Reset and Shuffle all lists? This cannot be undone.",
            func = function() DesolateLootcouncil:ShuffleLists() end,
        },
        btnSync = {
            type = "execute",
            name = "Sync Missing Players",
            desc = "Find players in Roster missing from Lists and append them to the bottom.",
            order = 12,
            func = function() DesolateLootcouncil:SyncMissingPlayers() end,
        },
        btnHistory = {
            type = "execute",
            name = "View History Log",
            order = 13,
            func = function() DesolateLootcouncil:ShowHistoryWindow() end,
        },
        headerLists = { type = "header", name = "Priority Lists", order = 20 },
    }

    -- Iterate dynamic lists
    local names = DesolateLootcouncil:GetPriorityListNames()
    for i, name in ipairs(names) do
        args["list" .. i] = self:GenerateListOptions(name, 20 + i)
    end

    return args
end

function PrioritySettings:GetOptions()
    return {
        name = "Player Priority",
        type = "group",
        order = 3,
        childGroups = "tab", -- Split into Tabs
        args = {
            tabManage = {
                type = "group",
                name = "Management",
                order = 1,
                -- Use a function wrapper to ensure dynamic rebuilding
                args = self:GetManagementArgs(),
            },
            tabConfig = {
                type = "group",
                name = "Configuration",
                order = 2,
                -- Use a function wrapper to ensure dynamic rebuilding
                args = self:GetPriorityListConfig(),
            },
        },
    }
end
