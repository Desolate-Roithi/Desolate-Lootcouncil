---@class PrioritySettings : AceModule
local PrioritySettings = DesolateLootcouncil:NewModule("PrioritySettings")

function PrioritySettings:GetOptions()
    return {
        name = "Priority Lists",
        type = "group",
        order = 4,
        args = {
            header = {
                type = "header",
                name = "List Configuration",
                order = 0,
            },
            createList = {
                type = "input",
                name = "Create New List",
                desc = "Enter name for new priority list",
                order = 1,
                set = function(info, val) DesolateLootcouncil:AddPriorityList(val) end,
            },
            manageLists = {
                type = "description",
                name = "Use the buttons below to manage existing lists.",
                order = 2,
            },
            -- Dynamic list of management options would go here
            -- For now, just a reset helper
            resetLists = {
                type = "execute",
                name = "Reset to Defaults",
                order = 10,
                func = function()
                    -- Reset logic to be implemented or tied to global reset
                    DesolateLootcouncil:Print("Manual edit of lists via Lua recommended for complex changes currently.")
                end
            }
        }
    }
end
