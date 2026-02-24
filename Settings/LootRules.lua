---@class LootSettings : AceModule
local LootSettings = DesolateLootcouncil:NewModule("LootSettings")

function LootSettings:GetOptions()
    return {
        name = "Loot Rules & Systems",
        type = "group",
        order = 5,
        args = {
            header = {
                type = "header",
                name = "Decay System",
                order = 0,
            },
            desc = {
                type = "description",
                name = "Configure point decay for missed raids.",
                order = 1,
            },
            enableDecay = {
                type = "toggle",
                name = "Enable Decay",
                desc = "Turn the decay system on or off.",
                order = 2,
                get = function(info) return DesolateLootcouncil.db.profile.DecayConfig.enabled end,
                set = function(info, val) DesolateLootcouncil.db.profile.DecayConfig.enabled = val end,
            },
            decayPenalty = {
                type = "range",
                name = "Decay Penalty",
                desc = "Points deducted per missed raid (0-3).",
                min = 0,
                max = 3,
                step = 0.5,
                order = 3,
                get = function(info) return DesolateLootcouncil.db.profile.DecayConfig.defaultPenalty end,
                set = function(info, val) DesolateLootcouncil.db.profile.DecayConfig.defaultPenalty = val end,
            },
        }
    }
end
