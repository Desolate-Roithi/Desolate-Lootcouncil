---@class Priority : AceModule, AceConsole-3.0, AceTimer-3.0
---@field db table
---@field historyFrame any
---@field priorityOverrideFrame any
---@field priorityOverrideContent any
---@field DLC_Log fun(self: any, msg: any, force?: boolean)
---@field GetMain fun(self: any, name: string): string
---@field SaveFramePosition fun(self: any, frame: any, windowName: string)
---@field RestoreFramePosition fun(self: any, frame: any, windowName: string)
---@field ApplyCollapseHook fun(self: any, widget: any)
---@field DefaultLayouts table<string, table>
---@field Print fun(self: any, msg: string)
---@field GetPriorityListNames fun(self: any): table
---@field AddPriorityList fun(self: any, name: string)
---@field RemovePriorityList fun(self: any, index: number)
---@field RenamePriorityList fun(self: any, index: number, newName: string)
---@field LogPriorityChange fun(self: any, msg: string)
---@field ShuffleLists fun(self: any)
---@field SyncMissingPlayers fun(self: any)
---@field MovePlayerToBottom fun(self: any, listName: string, targetName: string): number|nil
---@field ShowPriorityHistoryWindow fun(self: any)
---@field ShowPriorityOverrideWindow fun(self: any, listName: string)
---@field RestorePlayerPosition fun(self: any, listName: string, playerName: string, index: number)
---@field GetReversionIndex fun(self: any, listName: string, origIndex: number, timestamp: number): number
---@field version string
---@field amILM boolean
---@field activeAddonUsers table<string, boolean>
---@field activeLootMaster string
---@field currentSessionLoot table
---@field PriorityLog table
---@field simulatedGroup table
---@field OnEnable fun(self: any)

local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil") --[[@as DesolateLootcouncil]]
local Priority = DesolateLootcouncil:NewModule("Priority", "AceConsole-3.0", "AceTimer-3.0") --[[@as Priority]]

function Priority:OnEnable()
    -- Ensure list structure exists in DB (Strict Persistence)
    -- Check if DB is ready
    if not DesolateLootcouncil.db or not DesolateLootcouncil.db.profile then
        -- Retry logic: If Core hasn't loaded DB yet, wait a bit.
        self:ScheduleTimer("OnEnable", 0.1)
        return
    end
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
            DesolateLootcouncil:DLC_Log("Migrating Priority Lists to Dynamic Format...")
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
    if not db.PriorityLog then db.PriorityLog = {} end

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

function Priority:GetPriorityListNames()
    if not DesolateLootcouncil.db then return {} end
    local db = DesolateLootcouncil.db.profile
    local names = {}
    if db.PriorityLists then
        for _, list in ipairs(db.PriorityLists) do
            table.insert(names, list.name)
        end
    end
    return names
end

function Priority:AddPriorityList(name)
    if not DesolateLootcouncil.db then return end
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
    local msg = "Added new Priority List: " .. name .. " (Initialized with shuffled roster)"
    DesolateLootcouncil:DLC_Log(msg)
    self:LogPriorityChange(msg)
    self:SyncMissingPlayers() -- Auto-populate (and notifies change internally)
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Priority:RemovePriorityList(index)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists[index] then
        local removed = table.remove(db.PriorityLists, index)
        local msg = "Removed Priority List: " .. removed.name
        DesolateLootcouncil:DLC_Log(msg)
        self:LogPriorityChange(msg)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function Priority:RenamePriorityList(index, newName)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if db.PriorityLists[index] and newName ~= "" then
        db.PriorityLists[index].name = newName
        local msg = "Renamed list to: " .. newName
        DesolateLootcouncil:DLC_Log(msg)
        self:LogPriorityChange(msg)
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

function Priority:LogPriorityChange(msg)
    if not DesolateLootcouncil.db then return end
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

function Priority:ShuffleLists()
    if not DesolateLootcouncil.db then return end
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

    DesolateLootcouncil:DLC_Log("All " ..
        #db.PriorityLists .. " Priority Lists have been shuffled and initialized for the new season.")
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

function Priority:SyncMissingPlayers()
    if not DesolateLootcouncil.db then return end
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
        DesolateLootcouncil:DLC_Log(string.format("Synced missing players to bottom of lists (%d additions).",
            addedCount / #db.PriorityLists), true)
    else
        DesolateLootcouncil:DLC_Log("No missing players found to sync.", true)
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
end

---@param listName string
---@param playerName string
---@return number|nil
function Priority:MovePlayerToBottom(listName, playerName)
    if not DesolateLootcouncil.db then return end
    local db = DesolateLootcouncil.db.profile
    if not db.PriorityLists then return end

    -- Helper: Smart Exact Lookup (Local Duplicate)
    local function GetLinkedMain(name)
        if not DesolateLootcouncil.db then return nil end
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

        local msg = string.format("Priority Update: %s moved to bottom of %s (Item Awarded).", targetName, listName)
        DesolateLootcouncil:DLC_Log(msg)
        self:LogPriorityChange(string.format("Awarded item to %s (%s). Priority Reset.", targetName, listName))

        -- Structured Logging
        if not db.PriorityLog then db.PriorityLog = {} end
        table.insert(db.PriorityLog, {
            time = time(),
            type = "TO_BOTTOM",
            ---@type any
            list = listName,
            ---@type any
            player = targetName,
            from = foundIndex,
            to = #players
        })

        return foundIndex
    end
    return nil
end

function Priority:RestorePlayerPosition(listName, playerName, index)
    if not DesolateLootcouncil.db then
        return
    end
    local db = DesolateLootcouncil.db.profile

    local targetList = nil
    for _, list in ipairs(db.PriorityLists) do
        if list.name == listName then
            targetList = list; break
        end
    end
    if not targetList then
        return
    end

    local players = targetList.players
    -- Find current (Alt-Aware)
    local currentIdx = nil
    local targetMain = DesolateLootcouncil:GetMain(playerName)

    for i, p in ipairs(players) do
        local entryMain = DesolateLootcouncil:GetMain(p)
        if entryMain == targetMain then
            currentIdx = i
            break
        end
    end

    if not currentIdx then
        DesolateLootcouncil:DLC_Log(string.format("Warning: Could not find %s (Main: %s) in %s.", playerName, targetMain,
            listName))
    end

    if currentIdx then
        -- 1. Conditional Logic: Skip if already at correct position
        if currentIdx == index then
            DesolateLootcouncil:DLC_Log(string.format("%s is already at the correct position (%d).", playerName, index),
                true)
            return
        end

        -- 2. Capture Indices for logging
        local savedIndex = index
        local currentIndex = currentIdx

        table.remove(players, currentIndex)

        -- 3. Clamp index (Safety)
        if savedIndex < 1 then savedIndex = 1 end
        if savedIndex > #players + 1 then savedIndex = #players + 1 end

        table.insert(players, savedIndex, playerName)

        -- 4. Generate & Output Log Message (Sanitized)
        local sIndex = tonumber(savedIndex) or -1
        local cIndex = tonumber(currentIndex) or -1
        local pName = tostring(playerName or "Unknown")
        local lName = tostring(listName or "Unknown List")

        local logMsg = string.format("Reverting %s to position %d from position %d in %s.",
            pName, sIndex, cIndex, lName)
        DesolateLootcouncil:DLC_Log(logMsg, true)
        self:LogPriorityChange(logMsg)

        -- 5. Structured Logging
        table.insert(db.PriorityLog, {
            time = time(),
            type = "RESTORE",
            list = listName,
            player = playerName,
            from = currentIndex,
            to = savedIndex
        })
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DesolateLootcouncil")
    end
end

---@param listName string
---@param origIndex number
---@param timestamp number
---@return number
function Priority:GetReversionIndex(listName, origIndex, timestamp)
    local db = DesolateLootcouncil.db.profile
    if not db.PriorityLog then return origIndex end

    local simulated = origIndex

    -- Iterate all events AFTER the timestamp
    -- PriorityLog is append-only, so just iterate
    for _, log in ipairs(db.PriorityLog) do
        if log.list == listName and log.time > timestamp then
            -- Someone moved FROM log.from TO log.to
            local f = log.from
            local t = log.to

            -- If someone Above me moves Down below me -> I go Up
            if f < simulated and t >= simulated then
                simulated = simulated - 1
                -- If someone Below me moves Up above me -> I go Down (Rare/Manual)
            elseif f > simulated and t <= simulated then
                simulated = simulated + 1
            end
        end
    end
    return simulated
end

function Priority:ShowPriorityHistoryWindow()
    if self.historyFrame then
        self.historyFrame:Hide()
    end

    local db = DesolateLootcouncil.db.profile
    if not db.History then db.History = {} end

    local frame = CreateFrame("Frame", "DLCHistoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(600, 400)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    local function SavePos(f)
        DesolateLootcouncil:SaveFramePosition(f, "PriorityHistory")
    end
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        SavePos(f)
    end)
    frame:SetScript("OnHide", SavePos)
    DesolateLootcouncil:RestoreFramePosition(frame, "PriorityHistory")

    -- [NEW] Title Bar for Double-Click Collapse
    local titleBar = CreateFrame("Frame", "DLCHistoryTitleBar", frame)
    titleBar:SetPoint("TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", -32, -8) -- Leave space for close button
    titleBar:SetHeight(25)
    titleBar:EnableMouse(true)
    DesolateLootcouncil:ApplyCollapseHook({ frame = frame, titleBar = titleBar })

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

function Priority:ShowPriorityOverrideWindow(listName)
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
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    local function SavePos(f)
        DesolateLootcouncil:SaveFramePosition(f, "PriorityOverride")
    end
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        SavePos(f)
    end)
    frame:SetScript("OnHide", SavePos)
    DesolateLootcouncil:RestoreFramePosition(frame, "PriorityOverride")

    -- [NEW] Title Bar for Double-Click Collapse
    local titleBar = CreateFrame("Frame", "DLCPriorityTitleBar", frame)
    titleBar:SetPoint("TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", -32, -8)
    titleBar:SetHeight(25)
    titleBar:EnableMouse(true)
    DesolateLootcouncil:ApplyCollapseHook({ frame = frame, titleBar = titleBar })

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
                    DesolateLootcouncil:DLC_Log(msg)
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
