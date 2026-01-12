---@class UI_Loot : AceModule, AceConsole-3.0
local UI_Loot = DesolateLootcouncil:NewModule("UI_Loot", "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0")

---@class (partial) UI_Loot : AceModule
---@field lootFrame LootFrame
---@field btnStart Button

---@class LootFrame : AceGUIFrame
---@field statusIcon Texture
---@field statusTooltip Button
---@field statusbg Frame

---@class (partial) DLC_Ref_UILoot
---@field db table
---@field NewModule fun(self: DLC_Ref_UILoot, name: string, ...): any
---@field GetModule fun(self: DLC_Ref_UILoot, name: string): any
---@field AmILootMaster fun(self: DLC_Ref_UILoot): boolean
---@field GetPriorityListNames fun(self: DLC_Ref_UILoot): table
---@field GetItemCategory fun(self: DLC_Ref_UILoot, item: any): string
---@field SetItemCategory fun(self: DLC_Ref_UILoot, itemID: number, listIndex: number)
---@field Print fun(self: DLC_Ref_UILoot, msg: string)
---@field UnassignItem fun(self: DLC_Ref_UILoot, itemID: number)
---@field GetActiveUserCount fun(self: DLC_Ref_UILoot): number
---@field RestoreFramePosition fun(self: DLC_Ref_UILoot, frame: any, windowName: string)
---@field SaveFramePosition fun(self: DLC_Ref_UILoot, frame: any, windowName: string)
---@field ApplyCollapseHook fun(self: DLC_Ref_UILoot, widget: any)
---@field DLC_Log fun(self: DLC_Ref_UILoot, msg: any, force?: boolean)

---@type DLC_Ref_UILoot
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_UILoot]]

function UI_Loot:CreateLootFrame()
    ---@type LootFrame
    local frame = AceGUI:Create("Frame") --[[@as LootFrame]]
    frame:SetTitle("Desolate Loot Council   ")
    frame:SetLayout("Flow")
    frame:SetWidth(400)
    frame:SetHeight(500)
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
        if self.btnStart then self.btnStart:Hide() end
    end)

    self.lootFrame = frame

    -- [NEW] Position Persistence
    DesolateLootcouncil:RestoreFramePosition(frame, "Loot")
    local function SavePos(f)
        DesolateLootcouncil:SaveFramePosition(f, "Loot")
    end
    local rawFrame = (frame --[[@as any]]).frame
    rawFrame:HookScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        SavePos(frame)
    end)
    rawFrame:HookScript("OnHide", function() SavePos(frame) end)
    DesolateLootcouncil.Persistence:ApplyCollapseHook(frame, "Loot")
end

function UI_Loot:ShowLootWindow(lootTable)
    if not DesolateLootcouncil:AmILootMaster() then
        self:Print("Error: Only the Loot Master can open the Loot Window.")
        return
    end

    -- NEW: Auto-close if empty
    if not lootTable or #lootTable == 0 then
        if self.lootFrame then self.lootFrame:Hide() end
        return
    end

    if not self.lootFrame then
        self:CreateLootFrame()
    end

    self.lootFrame:Show()
    self.lootFrame:ReleaseChildren() -- Clear previous items

    -- 1. Hide the default Status Bar background
    if (self.lootFrame --[[@as any]]).statusbg then
        (self.lootFrame --[[@as any]]).statusbg:Hide()
    end

    -- 1.5 Addon Status Indicator Light (Top Right)
    local parent = (self.lootFrame --[[@as any]]).frame
    if not self.lootFrame.statusIcon then
        local icon = parent:CreateTexture(nil, "OVERLAY")
        icon:SetSize(12, 12)
        icon:SetPoint("TOP", parent, "TOP", 78, -2) -- Move to corner
        icon:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        icon:SetDrawLayer("OVERLAY", 7)             -- Force on top
        self.lootFrame.statusIcon = icon

        -- Tooltip Frame (Invisible Hit Rect)
        local ttFrame = CreateFrame("Button", nil, parent)
        ttFrame:SetAllPoints(icon)
        ttFrame:SetFrameLevel(parent:GetFrameLevel() + 20) -- Ensure above collapse-handle button
        ttFrame.isTitleOverlay = true                      -- Protect from collapse-hider logic
        self.lootFrame.statusTooltip = ttFrame

        ttFrame:SetScript("OnEnter", function()
            GameTooltip:SetOwner(ttFrame, "ANCHOR_BOTTOMLEFT")
            local active = DesolateLootcouncil:GetActiveUserCount()
            local total = GetNumGroupMembers()
            if total == 0 then
                total = 1; active = 1
            end -- Solo Logic
            GameTooltip:AddLine(string.format("Addon Connection: [%d] / [%d]", active, total), 1, 1, 1)
            GameTooltip:Show()
        end)
        ttFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Update Light Color
    local activeCount = DesolateLootcouncil:GetActiveUserCount()
    local totalCount = GetNumGroupMembers()
    if totalCount == 0 then
        totalCount = 1; activeCount = 1
    end                     -- Solo safety

    local r, g, b = 1, 0, 0 -- Red (Default/None)
    if activeCount >= totalCount then
        r, g, b = 0, 1, 0   -- Green (Full)
    elseif activeCount > 1 then
        r, g, b = 1, 1, 0   -- Yellow (Partial)
    end
    self.lootFrame.statusIcon:SetVertexColor(r, g, b)
    self.lootFrame.statusIcon:Show()
    if self.lootFrame.statusTooltip then self.lootFrame.statusTooltip:Show() end

    -- 2. Clear Session Button (Top)
    ---@type AceGUIButton
    local clearBtn = AceGUI:Create("Button") --[[@as AceGUIButton]]
    clearBtn:SetText("Clear Session")
    clearBtn:SetFullWidth(true)
    clearBtn:SetHeight(25)
    clearBtn:SetCallback("OnClick", function()
        ---@type Loot
        local Loot = DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
        if Loot and Loot.ClearLootBacklog then
            Loot:ClearLootBacklog()
            self:ShowLootWindow(nil) -- Refresh to empty
        end
    end)
    self.lootFrame:AddChild(clearBtn)

    -- 3. ScrollFrame (Middle)
    ---@type AceGUIScrollFrame
    local scroll = AceGUI:Create("ScrollFrame") --[[@as AceGUIScrollFrame]]
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    self.lootFrame:AddChild(scroll)

    local count = 0
    if lootTable then
        for i, data in ipairs(lootTable) do
            count = count + 1
            local link = data.link

            -- Row Container
            ---@type AceGUISimpleGroup
            local group = AceGUI:Create("SimpleGroup") --[[@as AceGUISimpleGroup]]
            group:SetLayout("Flow")
            group:SetFullWidth(true)
            scroll:AddChild(group) -- [FIX] Attach first, populate second

            -- Item Link (Interactive Logic)
            ---@type AceGUIInteractiveLabel
            local itemLabel = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]

            -- FIX TRUNCATION: Use GetItemInfo to ensure we have a full link/name
            local DisplayName = link

            -- FIX CRASH: Ensure itemID exists
            if not data.itemID and data.link then
                data.itemID = tonumber(data.link:match("item:(%d+)"))
            end

            if data.itemID then
                local itemName, itemLink = C_Item.GetItemInfo(data.itemID)
                if itemLink then DisplayName = itemLink end
            end

            itemLabel:SetText(DisplayName)
            itemLabel:SetRelativeWidth(0.55) -- User requested 0.55
            itemLabel:SetCallback("OnClick", function()
                GameTooltip:SetOwner((itemLabel --[[@as any]]).frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            itemLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            itemLabel:SetCallback("OnEnter", function()
                GameTooltip:SetOwner((itemLabel --[[@as any]]).frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)

            -- Category Dropdown
            ---@type AceGUIDropdown
            local catDropdown = AceGUI:Create("Dropdown") --[[@as AceGUIDropdown]]
            catDropdown:SetRelativeWidth(0.30) -- User requested 0.30 (reduced)

            -- Dynamic Categories
            local catList = {}
            local Priority = DesolateLootcouncil:GetModule("Priority")
            local prioNames = Priority and Priority:GetPriorityListNames() or {}
            local listIndexMap = {} -- Map Name -> Index for SetItemCategory

            -- Re-fetch names *and* map them to indices cause SetItemCategory needs Index?
            -- Actually SetItemCategory(item, listIndex).
            -- But our dropdown returns values. Values are names in current implementation?
            -- let's check earlier code: `catList[pName] = pName`.
            -- `SetItemCategory` takes `targetListIndex`.
            -- I need to map Name -> Index.

            local db = DesolateLootcouncil.db.profile
            if db.PriorityLists then
                for i, list in ipairs(db.PriorityLists) do
                    catList[list.name] = list.name
                    listIndexMap[list.name] = i
                end
            end

            -- Add Standard Options
            catList["Junk/Pass"] = "Junk/Pass"

            catDropdown:SetList(catList)

            -- INITIAL VALUE: Check Saved Persistence First
            local Loot = DesolateLootcouncil:GetModule("Loot")
            local savedCat = Loot and Loot:GetItemCategory(data.itemID)
            if savedCat == "Junk/Pass" then
                -- If nothing saved, fall back to Session category
                savedCat = data.category or "Junk/Pass"
            end
            catDropdown:SetValue(savedCat)

            catDropdown:SetCallback("OnValueChanged", function(_, _, value)
                data.category = value

                -- PERSIST CHANGE TO BACKEND
                local idx = listIndexMap[value]
                if idx then
                    if Loot then Loot:SetItemCategory(data.itemID, idx) end
                    DesolateLootcouncil:DLC_Log("Category updated to: " .. value)
                elseif value == "Junk/Pass" then
                    -- Unassign from backend, but KEEP in session (as requested)
                    if Loot then Loot:UnassignItem(data.itemID) end
                    -- No UI refresh needed as we just changed the backend state
                end
            end)

            -- Remove Button
            ---@type AceGUIButton
            local removeBtn = AceGUI:Create("Button") --[[@as AceGUIButton]]
            removeBtn:SetText("X")
            removeBtn:SetWidth(50) -- User requested 50 (increased)
            removeBtn:SetCallback("OnClick", function()
                table.remove(lootTable, i)
                DesolateLootcouncil:DLC_Log("Removed " .. link .. " from session.")
                self:ShowLootWindow(lootTable) -- Refresh
            end)

            group:AddChild(itemLabel)
            group:AddChild(catDropdown)
            group:AddChild(removeBtn)
        end
    end

    -- 4. Create Manual Start Button (Pinned to Footer)
    if not self.btnStart then
        local parent = (self.lootFrame --[[@as any]]).frame

        ---@type Button
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetText("Start Bidding")

        -- Keep the FrameLevel fix
        btn:SetFrameLevel(parent:GetFrameLevel() + 10)

        -- FIX 1: Alignment (Move UP to match Close button)
        btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 15, 16)

        -- FIX 2: Width
        btn:SetWidth(200)
        btn:SetHeight(24)

        self.btnStart = btn
    end

    local startBtn = self.btnStart --[[@as Button]]
    startBtn:SetScript("OnClick", function()
        ---@type Session
        local Session = DesolateLootcouncil:GetModule('Session') --[[@as Session]]
        Session:StartSession(lootTable)
        self.lootFrame:Hide()
        startBtn:Hide()
    end)

    -- Ensure visibility
    startBtn:SetFrameLevel((self.lootFrame --[[@as any]]).frame:GetFrameLevel() + 10)
    startBtn:Show()

    -- 5. Update Resize Logic
    local function LayoutScroll()
        local windowHeight = (self.lootFrame --[[@as any]]).frame:GetHeight()
        -- Title(30) + ClearBtn(25) + Footer(45) = ~100
        local scrollHeight = windowHeight - 100

        if scrollHeight < 50 then scrollHeight = 50 end

        scroll:SetHeight(scrollHeight)
        self.lootFrame:DoLayout()
    end

    LayoutScroll()
    self.lootFrame:SetCallback("OnResize", LayoutScroll)

    DesolateLootcouncil:DLC_Log(string.format("Loot Window Populated with %d items", count))
end
