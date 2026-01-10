---@class GeneralSettings : AceModule
---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]
local GeneralSettings = DesolateLootcouncil:NewModule("GeneralSettings") --[[@as GeneralSettings]]

function GeneralSettings:GetGeneralOptions()
    return {
        name = "General",
        type = "group",
        order = 1,
        args = {
            lootMaster = {
                type = "input",
                name = "Loot Master Name",
                order = 1,
                get = function() return DesolateLootcouncil.db.profile.configuredLM end,
                set = function(_, val)
                    DesolateLootcouncil.db.profile.configuredLM = val
                    DesolateLootcouncil:UpdateLootMasterStatus()
                end,
            },
            minQuality = {
                type = "select",
                name = "Min Loot Quality",
                order = 2,
                values = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" },
                get = function() return DesolateLootcouncil.db.profile.minLootQuality end,
                set = function(_, val) DesolateLootcouncil.db.profile.minLootQuality = val end,
            },
            enableAutoLoot = {
                type = "toggle",
                name = "Enable Automated Looting",
                desc =
                "LM: Auto-acquires items (Need > Greed > Transmog > DE). Aborts on BoP Collectables. Raiders: Auto-Pass.",
                order = 3,
                width = "full",
                get = function() return DesolateLootcouncil.db.profile.enableAutoLoot end,
                set = function(_, val) DesolateLootcouncil.db.profile.enableAutoLoot = val end,
            },
            debugMode = {
                type = "toggle",
                name = "Enable Debug Mode",
                desc = "Enables detailed logging for developers and advanced users.",
                order = 4,
                width = "full",
                get = function() return DesolateLootcouncil.db.profile.debugMode end,
                set = function(_, val) DesolateLootcouncil.db.profile.debugMode = val end,
            },
            resetLayouts = {
                type = "execute",
                name = "Reset Window Layouts",
                order = 5,
                func = function()
                    wipe(DesolateLootcouncil.db.profile.positions)

                    -- 1. Reset AceGUI Frames in UI Module
                    local UI = DesolateLootcouncil:GetModule("UI", true)
                    if UI then
                        if UI.monitorFrame then DesolateLootcouncil:RestoreFramePosition(UI.monitorFrame, "Monitor") end
                        if UI.awardFrame then DesolateLootcouncil:RestoreFramePosition(UI.awardFrame, "Award") end
                        if UI.attendanceFrame then
                            DesolateLootcouncil:RestoreFramePosition(UI.attendanceFrame,
                                "Attendance")
                        end
                        if UI.historyFrame then DesolateLootcouncil:RestoreFramePosition(UI.historyFrame, "History") end
                        if UI.tradeListFrame then DesolateLootcouncil:RestoreFramePosition(UI.tradeListFrame, "Trade") end
                        if UI.lootFrame then DesolateLootcouncil:RestoreFramePosition(UI.lootFrame, "Loot") end
                        if UI.votingFrame then DesolateLootcouncil:RestoreFramePosition(UI.votingFrame, "Voting") end
                    end

                    -- 2. Reset Version UI
                    local VersionUI = DesolateLootcouncil:GetModule("VersionUI", true)
                    if VersionUI and VersionUI.versionFrame then
                        DesolateLootcouncil:RestoreFramePosition(VersionUI.versionFrame, "Version")
                    end

                    -- 3. Reset Priority Frames
                    local Priority = DesolateLootcouncil:GetModule("Priority", true)
                    if Priority then
                        if Priority.historyFrame then
                            DesolateLootcouncil:RestoreFramePosition(Priority.historyFrame,
                                "PriorityHistory")
                        end
                        if Priority.priorityOverrideFrame then
                            DesolateLootcouncil:RestoreFramePosition(
                                Priority.priorityOverrideFrame, "PriorityOverride")
                        end
                    end

                    -- 4. Reset Config Frame if open
                    local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
                    if AceConfigDialog and AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames["DesolateLootcouncil"] then
                        DesolateLootcouncil:RestoreFramePosition(AceConfigDialog.OpenFrames["DesolateLootcouncil"],
                            "Config")
                    end

                    DesolateLootcouncil:DLC_Log("All window layouts reset to defaults.", true)
                end,
            },
        }
    }
end
