---@class UI : AceModule, AceConsole-3.0
---@field ShowLootWindow fun(self: UI, lootTable: table|nil)
---@field ShowVotingWindow fun(self: UI, lootTable: table|nil, isRefresh: boolean?)
---@field ShowMonitorWindow fun(self: UI)
---@field ShowAwardWindow fun(self: UI, itemData: table)
---@field CloseMasterLootWindow fun(self: UI)
---@field ShowMasterLootWindow fun(self: UI)
---@field ShowHistoryWindow fun(self: UI)
---@field ShowTradeListWindow fun(self: UI)
---@field RefreshTradeWindow fun(self: UI)
---@field Print fun(self: UI, msg: any)
---@field monitorFrame AceGUIFrame|nil
---@field awardFrame AceGUIFrame|nil
---@field historyFrame AceGUIFrame|nil
---@field tradeListFrame AceGUIFrame|nil
---@field lootFrame AceGUIFrame|nil
---@field votingFrame AceGUIFrame|nil
---@field btnStart AceGUIButton|nil
---@field votingTicker any|nil
---@field rowTimers table|nil
---@field cachedVotingItems table|nil
---@field myVotes table|nil
local UI = DesolateLootcouncil:NewModule("UI", "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0")

---@class AceGUIWidget
---@field Show fun(self: self)
---@field Hide fun(self: self)
---@field SetWidth fun(self: self, width: number)
---@field SetHeight fun(self: self, height: number)
---@field SetCallback fun(self: self, name: string, callback: function)

---@class AceGUIContainer : AceGUIWidget
---@field ReleaseChildren fun(self: self)
---@field AddChild fun(self: self, child: AceGUIWidget)
---@field SetLayout fun(self: self, layout: string)
---@field SetFullWidth fun(self: self, full: boolean)
---@field SetFullHeight fun(self: self, full: boolean)

---@class AceGUIFrame : AceGUIContainer
---@field SetTitle fun(self: self, title: string)

---@class AceGUIScrollFrame : AceGUIContainer

---@class AceGUISimpleGroup : AceGUIContainer

---@class AceGUIButton : AceGUIWidget
---@field SetText fun(self: self, text: string)
---@field SetWidth fun(self: self, width: number)
---@field SetCallback fun(self: self, name: string, callback: function)
---@field SetFullWidth fun(self: self, full: boolean)

---@class AceGUILabel : AceGUIWidget
---@field SetText fun(self: self, text: string)
---@field SetColor fun(self: self, r: number, g: number, b: number)
---@field SetImage fun(self: self, image: string|number)
---@field SetImageSize fun(self: self, width: number, height: number)
---@field SetFullWidth fun(self: self, full: boolean)
---@field SetJustifyH fun(self: self, align: string)
---@field SetFontObject fun(self: self, font: any)

---@class AceGUIInteractiveLabel : AceGUILabel

---@class AceGUIDropdown : AceGUIWidget
---@field SetList fun(self: self, list: table)
---@field SetValue fun(self: self, value: any)
---@field SetRelativeWidth fun(self: self, width: number)
---@field SetCallback fun(self: self, name: string, callback: function)

function UI:OnEnable()
    -- Empty for now
end
