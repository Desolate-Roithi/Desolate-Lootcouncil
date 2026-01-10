---@class UI : AceModule, AceConsole-3.0, AceEvent-3.0, AceTimer-3.0
---@field ShowLootWindow fun(self: UI, lootTable: table|nil)
---@field ShowVotingWindow fun(self: UI, lootTable: table|nil, isRefresh: boolean?)
---@field ShowMonitorWindow fun(self: UI)
---@field ShowAwardWindow fun(self: UI, itemData: table|nil)
---@field CloseMasterLootWindow fun(self: UI)
---@field ShowMasterLootWindow fun(self: UI)
---@field ShowHistoryWindow fun(self: UI)
---@field ShowAttendanceWindow fun(self: UI)
---@field ShowTradeListWindow fun(self: UI)
---@field RefreshTradeWindow fun(self: UI)
---@field Print fun(self: UI, msg: any)
---@field UpdateDisenchanters fun(self: UI)
---@field CreateDisenchanterFrame fun(self: UI)
---@field deFrame table|nil
---@field monitorFrame AceGUIFrame|nil
---@field awardFrame AceGUIFrame|nil
---@field attendanceFrame AceGUIFrame|nil
---@field historyFrame AceGUIFrame|nil
---@field selectedHistoryDate string|nil
---@field tradeListFrame AceGUIFrame|nil
---@field lootFrame AceGUIFrame|nil
---@field votingFrame AceGUIFrame|nil
---@field btnStart AceGUIButton|nil
---@field votingTicker any|nil
---@field rowTimers table|nil
---@field cachedVotingItems table|nil
---@field myVotes table|nil
---@field timerLabels table|nil
---@field expirationTimers table|nil
---@field CreateVotingFrame fun(self: UI)
---@field CreateLootFrame fun(self: UI)
---@field CancelAllTimers fun(self: UI)
---@field RemoveVotingItem fun(self: UI, guid: string)
---@field ResetVoting fun(self: UI)
---@field OnEnable fun(self: UI)

---@class (partial) DLC_Ref_UI
---@field db table
---@field NewModule fun(self: DLC_Ref_UI, name: string, ...): any
---@field GetModule fun(self: DLC_Ref_UI, name: string): any
---@field activeLootMaster string
---@field GetActiveUserCount fun(self: DLC_Ref_UI): number
---@field SaveFramePosition fun(self: DLC_Ref_UI, frame: any, windowName: string)
---@field RestoreFramePosition fun(self: DLC_Ref_UI, frame: any, windowName: string)
---@field ApplyCollapseHook fun(self: DLC_Ref_UI, widget: any)
---@field DLC_Log fun(self: DLC_Ref_UI, msg: any, force?: boolean)
---@field GetMain fun(self: DLC_Ref_UI, name: string): string
---@field DefaultLayouts table<string, table>

---@type DLC_Ref_UI
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_UI]]
---@type UI
local UI = DesolateLootcouncil:NewModule("UI", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceGUI = LibStub("AceGUI-3.0")

---@class AceGUIWidget
---@field Show fun(self: self)
---@field Hide fun(self: self)
---@field SetWidth fun(self: self, width: number)
---@field SetHeight fun(self: self, height: number)
---@field SetRelativeWidth fun(self: self, width: number)
---@field SetFullWidth fun(self: self, full: boolean)
---@field SetFullHeight fun(self: self, full: boolean)
---@field SetCallback fun(self: self, name: string, callback: function)
---@field SetLayout fun(self: self, layout: string)
---@field AddChild fun(self: self, child: AceGUIWidget)
---@field ReleaseChildren fun(self: self)
---@field SetTitle fun(self: self, title: string)
---@field SetText fun(self: self, text: string)
---@field SetColor fun(self: self, r: number, g: number, b: number)
---@field SetDisabled fun(self: self, disabled: boolean)
---@field EnableResize fun(self: self, state: boolean)
---@field DoLayout fun(self: self)
---@field SetJustifyH fun(self: self, align: string)
---@field SetFontObject fun(self: self, font: any)
---@field statusbg any
---@field statusIcon any
---@field SetLabel fun(self: self, text: string)
---@field SetSliderValues fun(self: self, min: number, max: number, step: number)
---@field SetValue fun(self: self, value: any)

---@class AceGUIFrame : AceGUIWidget
---@class AceGUIScrollFrame : AceGUIWidget
---@class AceGUISimpleGroup : AceGUIWidget
---@class AceGUIButton : AceGUIWidget
---@class AceGUILabel : AceGUIWidget
---@class AceGUIInteractiveLabel : AceGUIWidget
---@class AceGUIDropdown : AceGUIWidget
---@field SetList fun(self: self, list: table)
---@field SetValue fun(self: self, value: any)
---@field SetLabel fun(self: self, text: string)

---@class (partial) Distribution
---@field sessionDuration number
---@field RemoveSessionItem fun(self: Distribution, guid: string)
---@field SendStopSession fun(self: Distribution)
---@field SendVote fun(self: Distribution, guid: string, vote: any)
---@field SendRemoveItem fun(self: Distribution, guid: string)
---@field ClearVotes fun(self: Distribution)
---@field OnCommReceived fun(self: Distribution, prefix: string, msg: string, dist: string, sender: string)

---@class (partial) Loot
---@field AwardItem fun(self: Loot, itemGUID: string, winner: string, response: string)
---@field ClearLootBacklog fun(self: Loot)

---@class GeneralSettings : AceModule
---@field GetGeneralOptions fun(self: GeneralSettings): table

---@class Roster : AceModule
---@field GetOptions fun(self: Roster): table

function UI:OnEnable()
    self:RegisterMessage("DLC_VERSION_UPDATE", "UpdateDisenchanters")
end

function UI:ResetVoting()
    -- This is called when a session expires or is cleared
    if self.votingFrame then self.votingFrame:Hide() end
    if self.monitorFrame then self.monitorFrame:Hide() end
    if self.awardFrame then self.awardFrame:Hide() end
    self:Print("Voting data cleared.")
end
