---@type UI
local UI = DesolateLootcouncil:GetModule("UI")
local AceGUI = LibStub("AceGUI-3.0")

function UI:CreateLootFrame()
    ---@type AceGUIFrame
    local frame = AceGUI:Create("Frame") --[[@as AceGUIFrame]]
    frame:SetTitle("Desolate Loot Council")
    frame:SetLayout("Flow")
    frame:SetWidth(400)
    frame:SetHeight(500)
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
        if self.btnStart then self.btnStart:Hide() end
    end)

    self.lootFrame = frame
end

function UI:ShowLootWindow(lootTable)
    if not DesolateLootcouncil:AmILootMaster() then
        self:Print("Error: Only the Loot Master can open the Loot Window.")
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

    -- 2. Clear Session Button (Top)
    ---@type AceGUIButton
    local clearBtn = AceGUI:Create("Button") --[[@as AceGUIButton]]
    clearBtn:SetText("Clear Session")
    clearBtn:SetFullWidth(true)
    clearBtn:SetHeight(25)
    clearBtn:SetCallback("OnClick", function()
        ---@type Loot
        local Loot = DesolateLootcouncil:GetModule("Loot") --[[@as Loot]]
        if Loot.ClearLootBacklog then
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

            -- Item Link (Interactive Logic)
            ---@type AceGUIInteractiveLabel
            local itemLabel = AceGUI:Create("InteractiveLabel") --[[@as AceGUIInteractiveLabel]]
            itemLabel:SetText(link)
            itemLabel:SetRelativeWidth(0.55) -- User requested 0.55
            itemLabel:SetCallback("OnClick", function()
                local widget = itemLabel --[[@as {frame: table}]]
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            itemLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            itemLabel:SetCallback("OnEnter", function()
                local widget = itemLabel --[[@as {frame: table}]]
                GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)

            -- Category Dropdown
            ---@type AceGUIDropdown
            local catDropdown = AceGUI:Create("Dropdown") --[[@as AceGUIDropdown]]
            catDropdown:SetRelativeWidth(0.30) -- User requested 0.30 (reduced)
            catDropdown:SetList({
                ["Tier"] = "Tier",
                ["Weapons"] = "Weapons",
                ["Collectables"] = "Collectables",
                ["Rest"] = "Rest",
                ["Junk/Pass"] = "Junk/Pass"
            })
            catDropdown:SetValue(data.category)
            catDropdown:SetCallback("OnValueChanged", function(_, _, value)
                data.category = value
                DesolateLootcouncil:Print("[DLC] Category updated to: " .. value)
            end)

            -- Remove Button
            ---@type AceGUIButton
            local removeBtn = AceGUI:Create("Button") --[[@as AceGUIButton]]
            removeBtn:SetText("X")
            removeBtn:SetWidth(50) -- User requested 50 (increased)
            removeBtn:SetCallback("OnClick", function()
                table.remove(lootTable, i)
                DesolateLootcouncil:Print("[DLC] Removed " .. link .. " from session.")
                self:ShowLootWindow(lootTable) -- Refresh
            end)

            group:AddChild(itemLabel)
            group:AddChild(catDropdown)
            group:AddChild(removeBtn)
            scroll:AddChild(group)
        end
    end

    -- 4. Create Manual Start Button (Pinned to Footer)
    if not self.btnStart then
        local parent = (self.lootFrame --[[@as any]]).frame

        self.btnStart = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        self.btnStart:SetText("Start Bidding")

        -- Keep the FrameLevel fix
        self.btnStart:SetFrameLevel(parent:GetFrameLevel() + 10)

        -- FIX 1: Alignment (Move UP to match Close button)
        -- Changing Y-offset from 12 to 16 usually hits the center line of the footer.
        self.btnStart:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 15, 16)

        -- FIX 2: Width (Stop stretching it)
        -- Instead of anchoring 'Right', we set a fixed width.
        -- This prevents it from looking "too long" or hitting the Close button.
        self.btnStart:SetWidth(200)
        self.btnStart:SetHeight(24) -- Standard WoW button height
    end

    self.btnStart:SetScript("OnClick", function()
        ---@type Distribution
        local Dist = DesolateLootcouncil:GetModule('Distribution') --[[@as Distribution]]
        Dist:StartSession(lootTable)
        self.lootFrame:Hide()
        self.btnStart:Hide()
    end)

    -- Ensure visibility
    self.btnStart:SetFrameLevel((self.lootFrame --[[@as any]]).frame:GetFrameLevel() + 10)
    self.btnStart:Show()

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

    self:Print(string.format("[DLC-UI] Loot Window Populated with %d items", count))
end
