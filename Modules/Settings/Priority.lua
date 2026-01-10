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
---@field ShowPriorityHistoryWindow fun(self: DLC_Ref_PrioritySettings)
---@field Print fun(self: DLC_Ref_PrioritySettings, msg: string)

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
---@field priorityListDropdown integer|nil

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

    -- Override Button (Future Feature)
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
        name = "New List Name",
        desc = "Enter a name for the new priority list.",
        order = 2,
        set = function(_, val) self.newListInput = val end,
        get = function() return self.newListInput end,
    }
    args.btnAddList = {
        type = "execute",
        name = "Create List",
        order = 3,
        func = function()
            if self.newListInput and self.newListInput ~= "" then
                DesolateLootcouncil:AddPriorityList(self.newListInput)
                self.newListInput = ""
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end
        end,
    }

    -- MANAGE EXISTING LISTS
    args.headerManage = { type = "header", name = "Manage Existing Lists", order = 10 }

    args.selectList = {
        type = "select",
        name = "Select List to Edit",
        order = 11,
        values = function()
            local names = DesolateLootcouncil:GetPriorityListNames()
            local t = {}
            for i, n in ipairs(names) do t[i] = n end -- Map Index -> Name
            return t
        end,
        set = function(_, val) self.priorityListDropdown = val end,
        get = function() return self.priorityListDropdown end,
    }

    args.inputRename = {
        type = "input",
        name = "Rename List",
        order = 12,
        disabled = function() return not self.priorityListDropdown end,
        get = function() return "" end, -- Action-only input
        set = function(_, val)
            if self.priorityListDropdown and val ~= "" then
                DesolateLootcouncil:RenamePriorityList(self.priorityListDropdown, val)
                self.priorityListDropdown = nil -- Reset selection
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end
        end,
    }

    args.btnDelete = {
        type = "execute",
        name = "Delete List",
        order = 13,
        confirm = true,
        disabled = function() return not self.priorityListDropdown end,
        func = function()
            if self.priorityListDropdown then
                DesolateLootcouncil:RemovePriorityList(self.priorityListDropdown)
                self.priorityListDropdown = nil -- Reset selection
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
            end
        end,
    }

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
            func = function() DesolateLootcouncil:ShowPriorityHistoryWindow() end,
        },
        headerViews = { type = "header", name = "Priority List Views", order = 20 },
    }

    -- Inject dynamic list views
    local names = DesolateLootcouncil:GetPriorityListNames()
    for i, name in ipairs(names) do
        args["view" .. i] = self:GenerateListOptions(name, 20 + i)
    end

    return args
end

function PrioritySettings:GetOptions()
    return {
        name = "Priority Lists",
        type = "group",
        order = 3,
        childGroups = "tab",
        args = {
            config = {
                name = "Configuration",
                type = "group",
                order = 1,
                args = self:GetPriorityListConfig(),
            },
            management = {
                name = "Management & Views",
                type = "group",
                order = 2,
                args = self:GetManagementArgs(),
            },
        }
    }
end
