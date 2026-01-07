---@class Priority : AceModule
---@field OnInitialize fun(self: Priority)

---@class (partial) DLC_Ref_Priority
---@field db table
---@field NewModule fun(self: DLC_Ref_Priority, name: string): any
---@field Print fun(self: DLC_Ref_Priority, msg: string)
---@field GetPriorityListNames fun(self: DLC_Ref_Priority): table
---@field AddPriorityList fun(self: DLC_Ref_Priority, name: string)
---@field RemovePriorityList fun(self: DLC_Ref_Priority, index: number)
---@field RenamePriorityList fun(self: DLC_Ref_Priority, index: number, newName: string)
---@field LogPriorityChange fun(self: DLC_Ref_Priority, msg: string)
---@field ShuffleLists fun(self: DLC_Ref_Priority)
---@field SyncMissingPlayers fun(self: DLC_Ref_Priority)
---@field MovePlayerToBottom fun(self: DLC_Ref_Priority, listName: string, playerName: string)
---@field ShowHistoryWindow fun(self: DLC_Ref_Priority)
---@field ShowPriorityOverrideWindow fun(self: DLC_Ref_Priority, listName: string)
---@field historyFrame AceGUIWidget
---@field priorityOverrideFrame AceGUIWidget
---@field priorityOverrideContent AceGUIWidget

---@type DLC_Ref_Priority
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DLC_Ref_Priority]]
local Priority = DesolateLootcouncil:NewModule("Priority") --[[@as Priority]]

function Priority:OnInitialize()
    -- Ensure list structure exists in DB (Strict Persistence)
    local db = DesolateLootcouncil.db.profile

    -- Crucial: Use OR to preserve existing data (fixes wipe on reload)
    db.PriorityLists = db.PriorityLists or {
        { name = "Tier",         players = {}, items = {}, buttons = { "Main Spec", "Off Spec", "Transmog", "Pass" } },
        { name = "Weapons",      players = {}, items = {}, buttons = { "BiS", "Major Sidegrade", "Minor Sidegrade", "Pass" } },
        { name = "Rest",         players = {}, items = {}, buttons = { "Main Spec", "Off Spec", "Pass" } },
        { name = "Collectables", players = {}, items = {}, buttons = { "Need", "Greed", "Pass" } }
    }

    if db.PriorityLists then
        -- DATA MIGRATION: Convert Key-Value to Array of Objects
        -- Check if it's the old format (Table with string keys)
        local isOldFormat = false
        if db.PriorityLists.Tier or db.PriorityLists.Weapons then
            isOldFormat = true
        end

        if isOldFormat then
            DesolateLootcouncil:Print("Migrating Priority Lists to Dynamic Format...")
            local old = db.PriorityLists
            local new = {}

            -- Preserve Order: Tier, Weapons, Rest, Collectables
            local order = { "Tier", "Weapons", "Rest", "Collectables" }
            for _, key in ipairs(order) do
                if old[key] then
                    table.insert(new, { name = key, players = old[key] })
                end
            end

            -- Rescue any other keys? (Unlikely, but let's stick to standard 4 for now)
            db.PriorityLists = new
        end
    end

    -- History Log Initialization
    if not db.History then db.History = {} end

    -- DATA MIGRATION: Old names to New names + Timestamps
    if db.playerRoster and db.playerRoster.mains then
        if not db.MainRoster then db.MainRoster = {} end
        for name, _ in pairs(db.playerRoster.mains) do
            if not db.MainRoster[name] then
                db.MainRoster[name] = { addedAt = time() }
            end
        end
        db.playerRoster.mains = nil
    end

    -- Handle existing MainRoster if it's still using the old boolean format
    if db.MainRoster then
        for name, value in pairs(db.MainRoster) do
            if type(value) == "boolean" then
                db.MainRoster[name] = { addedAt = time() }
            end
        end
    end
end

-- Shuffle Helper (Fisher-Yates)
local function ShuffleTable(t)
    local n = #t
    for i = n, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- --- Globally Attached Functions ---

function DesolateLootcouncil:GetPriorityListNames()
    local db = DesolateLootcouncil.db.profile
    local names = {}
    if db.PriorityLists then
        for _, list in ipairs(db.PriorityLists) do
            table.insert(names, list.name)
        end
    end
    return names
end

function DesolateLootcouncil:AddPriorityList(name)
    local db = DesolateLootcouncil.db.profile
    if not name or name == "" then return end

    -- Check duplicate
    for _, list in ipairs(db.PriorityLists) do
        if list.name == name then return end
    end

    -- Create new list populated with SHUFFLED roster
    local newList = {}
    if db.MainRoster then
        for rName, _ in pairs(db.MainRoster) do
            table.insert(newList, rName)
        end
    end
    ShuffleTable(newList)

    table.insert(db.PriorityLists, { name = name, players = newList, items = {} })
    self:Print("Added new Priority List: " .. name .. " (Initialized with shuffled roster)")
    self:SyncMissingPlayers() -- Auto-populate (and notifies change internally)
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function DesolateLootcouncil:RemovePriorityList(index)
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists[index] then
        local removed = table.remove(db.PriorityLists, index)
        self:Print("Removed Priority List: " .. removed.name)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function DesolateLootcouncil:RenamePriorityList(index, newName)
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists[index] and newName ~= "" then
        db.PriorityLists[index].name = newName
        self:Print("Renamed list to: " .. newName)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function DesolateLootcouncil:LogPriorityChange(msg)
    local db = DesolateLootcouncil.db.profile
    if not db.History then db.History = {} end
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    local entry = string.format("[%s] %s", timestamp, msg)
    table.insert(db.History, entry)
    -- Cap history log? (Optional, but good practice). Let's keep last 100 entries.
    if #db.History > 100 then
        table.remove(db.History, 1)
    end
end

function DesolateLootcouncil:ShuffleLists()
    local db = DesolateLootcouncil.db.profile
    -- CLEAR HISTORY on season reset
    db.History = {}
    self:LogPriorityChange("Season Started - All lists shuffled and history cleared.")

    local mains = {}
    -- Retrieve the existing MainRoster directly from DB
    if db.MainRoster then
        for name, _ in pairs(db.MainRoster) do
            table.insert(mains, name)
        end
    end

    -- Iterate Dynamic Lists
    for _, listObj in ipairs(db.PriorityLists) do
        -- Deep copy roster to the specific list
        local newList = {}
        for _, name in ipairs(mains) do
            table.insert(newList, name)
        end
        -- Shuffle independently
        ShuffleTable(newList)
        -- Write directly to SavedVariables for immediate persistence
        listObj.players = newList
    end

    self:Print("All " .. #db.PriorityLists .. " Priority Lists have been shuffled and initialized for the new season.")
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function DesolateLootcouncil:SyncMissingPlayers()
    local db = DesolateLootcouncil.db.profile
    if not db.MainRoster or not db.PriorityLists then return end

    local addedCount = 0

    for _, listObj in ipairs(db.PriorityLists) do
        local currentList = listObj.players
        local currentSet = {}
        for _, name in ipairs(currentList) do
            currentSet[name] = true
        end

        local missing = {}
        for name, data in pairs(db.MainRoster) do
            if not currentSet[name] then
                table.insert(missing, { name = name, addedAt = data.addedAt or 0 })
            end
        end

        -- Sort missing by addedAt (Oldest -> Top, Newest -> Bottom)
        table.sort(missing, function(a, b) return a.addedAt < b.addedAt end)

        for _, player in ipairs(missing) do
            table.insert(currentList, player.name)
            addedCount = addedCount + 1
            self:LogPriorityChange(string.format("Synced %s to bottom of %s list.", player.name, listObj.name))
        end
    end

    if addedCount > 0 then
        self:Print(string.format("Synced missing players to bottom of lists (%d additions).",
            addedCount / #db.PriorityLists))
    else
        self:Print("No missing players found to sync.")
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function DesolateLootcouncil:MovePlayerToBottom(listName, playerName)
    local db = DesolateLootcouncil.db.profile
    if not db.PriorityLists then return end

    -- Helper: Smart Exact Lookup (Local Duplicate)
    local function GetLinkedMain(name)
        local db = DesolateLootcouncil.db.profile
        if not db or not db.playerRoster or not db.playerRoster.alts then return nil end

        -- 1. Exact Match
        if db.playerRoster.alts[name] then return db.playerRoster.alts[name] end

        -- 2. Realm Append
        local realm = GetRealmName()
        local full = name .. "-" .. realm
        if db.playerRoster.alts[full] then return db.playerRoster.alts[full] end

        return nil
    end

    -- Smart Lookup: Check if Alt
    local linkedMain = GetLinkedMain(playerName)
    local targetName = linkedMain or playerName

    local targetList = nil
    for _, list in ipairs(db.PriorityLists) do
        if list.name == listName then
            targetList = list
            break
        end
    end

    if not targetList then return end

    local players = targetList.players
    local foundIndex = nil

    -- Find player (targetName)
    for i, name in ipairs(players) do
        if name == targetName then
            foundIndex = i
            break
        end
    end

    if foundIndex then
        table.remove(players, foundIndex)
        table.insert(players, targetName)

        local msg = string.format("[DLC] Priority Update: %s moved to bottom of %s (Item Awarded).", targetName, listName)
        self:Print(msg)
        self:LogPriorityChange(string.format("Awarded item to %s (%s). Priority Reset.", targetName, listName))
    end
end

function DesolateLootcouncil:ShowHistoryWindow()
    if self.historyFrame then
        self.historyFrame:Hide()
    end

    local db = DesolateLootcouncil.db.profile
    if not db.History then db.History = {} end

    local frame = CreateFrame("Frame", "DLCHistoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(600, 400)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Priority List History")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    -- Scroll Area
    local scrollFrame = CreateFrame("ScrollFrame", "DLCHistoryScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)

    local content = CreateFrame("EditBox", nil, scrollFrame)
    content:SetMultiLine(true)
    content:SetSize(550, 400)
    content:SetFontObject("GameFontHighlight")
    content:SetAutoFocus(false)
    scrollFrame:SetScrollChild(content)

    -- Populate Text (Newest at Bottom)
    local fullText = ""
    for _, line in ipairs(db.History) do
        fullText = fullText .. line .. "\n"
    end
    if fullText == "" then fullText = "No history available." end

    content:SetText(fullText)

    self.historyFrame = frame
    frame:Show()
end

function DesolateLootcouncil:ShowPriorityOverrideWindow(listName)
    if self.priorityOverrideFrame then
        self.priorityOverrideFrame:Hide()
    end

    local db = DesolateLootcouncil.db.profile
    if not db or not db.PriorityLists then return end

    -- Dynamic Lookup
    local targetListObj = nil
    for _, obj in ipairs(db.PriorityLists) do
        if obj.name == listName then
            targetListObj = obj
            break
        end
    end

    if not targetListObj then return end
    local list = targetListObj.players

    local frame = CreateFrame("Frame", "DLCPriorityOverride", UIParent, "BackdropTemplate")
    frame:SetSize(350, 500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Override: " .. listName)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    local scrollFrame = CreateFrame("ScrollFrame", "DLCPriorityScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(300, 1)
    scrollFrame:SetScrollChild(content)

    self.priorityOverrideFrame = frame
    self.priorityOverrideContent = content

    local function RefreshList()
        content:Hide() -- Hide during update
        local children = { content:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide(); child:SetParent(nil)
        end

        local currentList = targetListObj.players
        local rowHeight = 25

        for i, name in ipairs(currentList) do
            local row = CreateFrame("Button", nil, content, "BackdropTemplate")
            row:SetSize(280, rowHeight)
            row:SetPoint("TOPLEFT", 10, -(i - 1) * rowHeight)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            row:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            row:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetPoint("LEFT", 10, 0)
            text:SetText(string.format("%d. %s", i, name))

            -- Drag Logic
            row:SetMovable(true)
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function(self)
                self:SetFrameStrata("TOOLTIP")
                self:StartMoving()
                self.isDragging = true
                self:SetBackdropColor(0.2, 0.5, 0.8, 0.8)
            end)

            row:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                self.isDragging = false
                self:SetFrameStrata("HIGH")

                -- Detect new position BEFORE clearing points
                local _, y = self:GetCenter()
                self:ClearAllPoints()

                if not y then return end -- Safety check

                local contentY = content:GetTop()
                if not contentY then return end -- Safety check

                local relativeY = contentY - y
                local newIndex = math.floor(relativeY / rowHeight) + 1
                newIndex = math.max(1, math.min(newIndex, #currentList))

                if newIndex ~= i then
                    local player = table.remove(currentList, i)
                    table.insert(currentList, newIndex, player)
                    local msg = string.format("Manually moved %s from Rank %d to %d in %s list.", player, i, newIndex,
                        listName)
                    DesolateLootcouncil:Print(msg)
                    DesolateLootcouncil:LogPriorityChange(msg)
                end

                RefreshList() -- Redraw everything
            end)

            row:SetScript("OnEnter",
                function(self) if not self.isDragging then self:SetBackdropColor(0.3, 0.3, 0.3, 0.8) end end)
            row:SetScript("OnLeave",
                function(self) if not self.isDragging then self:SetBackdropColor(0.1, 0.1, 0.1, 0.5) end end)
        end

        content:SetHeight(#currentList * rowHeight + 10)
        content:Show()
    end

    RefreshList()
    frame:Show()
end
