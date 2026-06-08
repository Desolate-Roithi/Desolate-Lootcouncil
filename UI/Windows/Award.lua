local _, AT = ...
if AT.abortLoad then return end

---@class UI_Award : AceModule
local UI_Award = DesolateLootcouncil:NewModule("UI_Award", "AceEvent-3.0")

---@type DesolateLootcouncil
local DesolateLootcouncil = LibStub("AceAddon-3.0"):GetAddon("DesolateLootcouncil")
local L = LibStub("AceLocale-3.0"):GetLocale("DesolateLootcouncil")

local VOTE_TEXT = { [1] = "Bid", [2] = "Roll", [3] = "OS", [4] = "TM", [5] = "Pass" }



function UI_Award:OnInitialize()
    self.awardRowPool = {}
    self.deRowPool = {}
end

function UI_Award:OnEnable()
    self:RegisterMessage("DLC_SESSION_STOPPED", function()
        if self.awardFrame then self.awardFrame:Hide() end
    end)
end

function UI_Award:CreateVoteRow(index, scroll, v, isLM, itemData)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.awardRowPool[index] then
        self.awardRowPool[index] = NativeGUI:CreateRowContainer(scroll, false)
    end
    local row = self.awardRowPool[index]
    row:Show()

    local rowHeight = 32
    row:SetHeight(rowHeight)

    local topOffset = (index - 1) * (rowHeight + 6)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -topOffset)
    row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -12, -topOffset)

    -- Give item button (created/positioned first for relative text anchor)
    if isLM then
        if not row.btnGive then
            local btn = NativeGUI:CreateButton(row, L["Give"], 50, 22, "Bid")
            row.btnGive = btn
        end
        row.btnGive:ClearAllPoints()
        row.btnGive:SetPoint("RIGHT", -12, 0)
        row.btnGive:Show()
        row.btnGive:SetScript("OnClick", function()
            self.awardFrame:Hide()
            local itemLink = itemData and itemData.link
            local isRecipe = itemLink and DesolateLootcouncil.API:IsRecipe(itemLink) or false
            local voteDesc
            if isRecipe then
                if v.type == 2 then
                    voteDesc = "Ready to Craft"
                elseif v.type == 3 then
                    voteDesc = "Unskilled"
                else
                    voteDesc = VOTE_TEXT[v.type] or "Unknown"
                end
            else
                voteDesc = VOTE_TEXT[v.type] or "Unknown"
            end
            DesolateLootcouncil.API:AwardItem(itemData.sourceGUID, v.name, voteDesc)
        end)
    elseif row.btnGive then
        row.btnGive:Hide()
    end

    -- 1. Class Icon
    if not row.classIcon then
        local classIcon = row:CreateTexture(nil, "OVERLAY")
        classIcon:SetSize(16, 16)
        classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        classIcon:SetPoint("LEFT", 12, 0)
        row.classIcon = classIcon
    end
    local Roster = DesolateLootcouncil:GetModule("Roster", true)
    local class = Roster and Roster:GetUnitClass(v.name) or "WARRIOR"
    if _G.CLASS_ICON_TCOORDS then
        local coords = _G.CLASS_ICON_TCOORDS[class]
        if coords then
            row.classIcon:SetTexCoord(unpack(coords))
        else
            row.classIcon:SetTexCoord(0, 1, 0, 1)
        end
    else
        row.classIcon:SetTexCoord(0, 1, 0, 1)
    end
    row.classIcon:Show()

    -- 2. Player Name
    if not row.lblName then
        local lblName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lblName:SetSize(130, 20)
        lblName:SetPoint("LEFT", row.classIcon, "RIGHT", 8, 0)
        lblName:SetJustifyH("LEFT")
        row.lblName = lblName
    end
    local classColor = NativeGUI:GetClassColorHex(class)
    row.lblName:SetText("|c" .. classColor .. DesolateLootcouncil:GetDisplayName(v.name) .. "|r")

    -- 3. Bid Response pill
    if not row.lblResp then
        local lblResp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lblResp:SetSize(50, 20)
        lblResp:SetPoint("LEFT", row.lblName, "RIGHT", 10, 0)
        lblResp:SetJustifyH("LEFT")
        row.lblResp = lblResp
    end
    local vc = NativeGUI.VOTE_COLORS[v.type]
    local color = vc and vc.hex or ""
    local itemLink = itemData and itemData.link
    local isRecipe = itemLink and DesolateLootcouncil.API:IsRecipe(itemLink) or false
    local txt
    if isRecipe then
        if v.type == 2 then
            txt = L["Ready"]
        elseif v.type == 3 then
            txt = L["Unskilled"]
        else
            txt = VOTE_TEXT[v.type] or "?"
        end
    else
        txt = VOTE_TEXT[v.type] or "?"
    end
    row.lblResp:SetText(color .. txt .. "|r")

    -- 4. Rank / Roll value
    if not row.lblRank then
        local lblRank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lblRank:SetSize(75, 20)
        lblRank:SetPoint("LEFT", row.lblResp, "RIGHT", 10, 0)
        lblRank:SetJustifyH("LEFT")
        row.lblRank = lblRank
    end
    local rankText
    if v.type == 1 then
        rankText = (v.rank == 999) and "|cff9d9d9d" .. L["Unranked"] .. "|r" or ("#" .. v.rank)
        if v.rank <= 5 then rankText = "|cffffd700" .. rankText .. "|r" end
    else
        rankText = "Roll: " .. v.roll
    end
    row.lblRank:SetText(rankText)

    -- 5. Voter Custom Note Icon (shown only if a note is present, with hover tooltip)
    if not row.noteBtn then
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(18, 18)
        local tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
        btn.texture = tex
        row.noteBtn = btn
    end
    row.noteBtn:ClearAllPoints()
    row.noteBtn:SetPoint("LEFT", row.lblRank, "RIGHT", 15, 0)

    if v.note and v.note ~= "" then
        row.noteBtn:Show()
        row.noteBtn:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["Voter Note"], 1, 0.85, 0)
            GameTooltip:AddLine(v.note, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.noteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        row.noteBtn:Hide()
        row.noteBtn:SetScript("OnEnter", nil)
        row.noteBtn:SetScript("OnLeave", nil)
    end

    scroll:SetHeight(topOffset + rowHeight + 10)
end

function UI_Award:CreateDisenchanterRow(index, scroll, de, isLM, itemData, numDisenchanters)
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")

    if not self.deRowPool[index] then
        self.deRowPool[index] = NativeGUI:CreateRowContainer(scroll, false)
    end
    local row = self.deRowPool[index]
    row:Show()

    local rowHeight = 32
    row:SetHeight(rowHeight)

    local topOffset = (index - 1) * (rowHeight + 6)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -topOffset)
    
    local rightOffset = (numDisenchanters <= 3) and -4 or -12
    row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", rightOffset, -topOffset)

    if isLM then
        if not row.btnGive then
            local btn = NativeGUI:CreateButton(row, L["Give"], 50, 22, "Bid")
            row.btnGive = btn
        end
        row.btnGive:ClearAllPoints()
        row.btnGive:SetPoint("RIGHT", -12, 0)
        row.btnGive:Show()
        row.btnGive:SetScript("OnClick", function()
            self.awardFrame:Hide()
            DesolateLootcouncil.API:AwardItem(itemData.sourceGUID, de.name, "Disenchant")
        end)
    elseif row.btnGive then
        row.btnGive:Hide()
    end

    -- 1. Class Icon
    if not row.classIcon then
        local classIcon = row:CreateTexture(nil, "OVERLAY")
        classIcon:SetSize(16, 16)
        classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        classIcon:SetPoint("LEFT", 12, 0)
        row.classIcon = classIcon
    end
    local Roster = DesolateLootcouncil:GetModule("Roster", true)
    local class = Roster and Roster:GetUnitClass(de.name) or "WARRIOR"
    if _G.CLASS_ICON_TCOORDS then
        local coords = _G.CLASS_ICON_TCOORDS[class]
        if coords then
            row.classIcon:SetTexCoord(unpack(coords))
        else
            row.classIcon:SetTexCoord(0, 1, 0, 1)
        end
    else
        row.classIcon:SetTexCoord(0, 1, 0, 1)
    end
    row.classIcon:Show()

    -- 2. Player Name
    if not row.lblName then
        local lblName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lblName:SetSize(140, 20)
        lblName:SetPoint("LEFT", row.classIcon, "RIGHT", 8, 0)
        lblName:SetJustifyH("LEFT")
        row.lblName = lblName
    end
    local classColor = NativeGUI:GetClassColorHex(class)
    row.lblName:SetText("|c" .. classColor .. DesolateLootcouncil:GetDisplayName(de.name) .. "|r")

    -- 3. Skill Level
    if not row.lblSkill then
        local lblSkill = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lblSkill:SetJustifyH("LEFT")
        row.lblSkill = lblSkill
    end
    row.lblSkill:ClearAllPoints()
    row.lblSkill:SetPoint("LEFT", row.lblName, "RIGHT", 15, 0)
    row.lblSkill:SetPoint("RIGHT", (isLM and row.btnGive or row), (isLM and "LEFT" or "RIGHT"), -15, 0)
    row.lblSkill:SetText(string.format(L["Lvl %d"], de.skill))

    scroll:SetHeight(topOffset + rowHeight + 10)
end

local function RenderAwardHeader(self, itemData)
    local catText = itemData.category and (" (" .. itemData.category .. ")") or ""
    local _, properLink, quality = C_Item.GetItemInfo(itemData.link)
    if not quality then
        local _, _, itemQuality = C_Item.GetItemInfoInstant(itemData.link)
        quality = itemQuality
    end

    if not self.awardHeaderContainer then
        local container = CreateFrame("Frame", nil, self.awardFrame)
        container:SetHeight(36)
        container:SetPoint("TOPLEFT", self.awardFrame, "TOPLEFT", 16, -35)
        container:SetPoint("TOPRIGHT", self.awardFrame, "TOPRIGHT", -36, -35)
        self.awardHeaderContainer = container

        -- White border for premium glow
        local border = CreateFrame("Frame", nil, container, "BackdropTemplate")
        border:SetSize(30, 30)
        border:SetPoint("LEFT", 0, 0)
        border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        container.iconBorder = border

        local icon = container:CreateTexture(nil, "OVERLAY")
        icon:SetSize(28, 28)
        icon:SetPoint("CENTER", border, "CENTER")
        container.icon = icon

        local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        text:SetPoint("LEFT", border, "RIGHT", 10, 0)
        text:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        container.text = text
    end

    local iconTexture = C_Item.GetItemIconByID(itemData.itemID) or 134400
    self.awardHeaderContainer.icon:SetTexture(iconTexture)
    self.awardHeaderContainer.text:SetText((properLink or itemData.link) .. "|cffaaaaaa" .. catText .. "|r")

    -- Quality color border
    local r, g, b
    if C_Item.GetItemQualityColor and quality then
        r, g, b = C_Item.GetItemQualityColor(quality)
    end
    if r then
        self.awardHeaderContainer.iconBorder:SetBackdropBorderColor(r, g, b, 1)
    else
        self.awardHeaderContainer.iconBorder:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end
end

local function RenderVoteList(self, voteList, isLM, itemData, NativeGUI)
    if not self.awardScroll then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.awardFrame, -75, -16)
        self.awardScroll = scrollFrame
        self.awardScrollContent = scrollContent
    end
    self.awardScroll:Show()
    self.awardScrollContent:Show()
    self.awardScrollContent:SetHeight(1)

    local scrollHeight = 0
    if #voteList == 0 then
        if not self.awardEmptyLabel then
            local lbl = self.awardScrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("TOPLEFT", 10, -10)
            self.awardEmptyLabel = lbl
        end
        self.awardEmptyLabel:SetText(L["No active votes."])
        self.awardEmptyLabel:Show()
        scrollHeight = scrollHeight + 30
    else
        if self.awardEmptyLabel then self.awardEmptyLabel:Hide() end
        for idx, v in ipairs(voteList) do
            self:CreateVoteRow(idx, self.awardScrollContent, v, isLM, itemData)
            scrollHeight = scrollHeight + 38
        end
    end
    self.awardScrollContent:SetHeight(scrollHeight + 10)
end

local function RenderDisenchantersDock(self, disenchanters, isLM, itemData, N, H, NativeGUI)
    local theme = DesolateLootcouncil:GetModule("UI_Theme"):GetActiveTheme()
    if H > 0 then
        if not self.deContainer then
            local deContainer = CreateFrame("Frame", nil, self.awardFrame)
            deContainer:SetPoint("BOTTOMLEFT", self.awardFrame, "BOTTOMLEFT", 16, 12)
            deContainer:SetPoint("BOTTOMRIGHT", self.awardFrame, "BOTTOMRIGHT", -36, 12)
            self.deContainer = deContainer

            local deHeaderButton = CreateFrame("Button", nil, deContainer)
            deHeaderButton:SetSize(180, 20)
            deHeaderButton:SetPoint("TOPLEFT", 0, 0)
            deHeaderButton:SetScript("OnDoubleClick", function()
                self.deCollapsed = not self.deCollapsed
                self:ShowAwardWindow(self.activeItemData)
            end)
            self.deHeaderButton = deHeaderButton

            local arrow = deHeaderButton:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(12, 12)
            arrow:SetPoint("LEFT", 0, 0)
            arrow:SetAtlas("minimal-scrollbar-arrow-bottom")
            arrow:SetVertexColor(theme.textHeader[1], theme.textHeader[2], theme.textHeader[3], 0.6)
            self.deCollapseArrow = arrow

            local deHeader = deHeaderButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            deHeader:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
            deHeader:SetText(L["Disenchanters"])
            deHeader:SetTextColor(unpack(theme.textHeader))
            self.deHeaderLabel = deHeader

            local scrollFrame = CreateFrame("ScrollFrame", "DLCAwardDeScroll", deContainer, "UIPanelScrollFrameTemplate")
            scrollFrame:SetPoint("TOPLEFT", deContainer, "TOPLEFT", 0, -20)

            local scrollContent = CreateFrame("Frame", nil, scrollFrame)
            scrollContent:SetSize(scrollFrame:GetWidth() or 200, 1)
            scrollFrame:SetScrollChild(scrollContent)

            scrollFrame:SetScript("OnSizeChanged", function(s, w)
                scrollContent:SetWidth(w)
                if s.UpdateScrollChildRect then s:UpdateScrollChildRect() end
            end)

            NativeGUI:StyleScrollBar(scrollFrame)

            self.deScrollFrame = scrollFrame
            self.deScrollContent = scrollContent
        end
        self.deContainer:SetHeight(H)
        self.deContainer:Show()

        -- Always ensure the text and arrow colors match the active theme
        if self.deHeaderLabel then
            self.deHeaderLabel:SetTextColor(unpack(theme.textHeader))
        end
        if self.deCollapseArrow then
            self.deCollapseArrow:Show()
            self.deCollapseArrow:SetVertexColor(theme.textHeader[1], theme.textHeader[2], theme.textHeader[3], 0.6)
        end

        if self.deCollapsed then
            if self.deCollapseArrow then
                self.deCollapseArrow:SetRotation(math.pi / 2)
            end
            if self.deScrollFrame then self.deScrollFrame:Hide() end
            for _, row in ipairs(self.deRowPool) do row:Hide() end
        else
            if self.deCollapseArrow then
                self.deCollapseArrow:SetRotation(0)
            end
            self.deScrollFrame:Show()
            self.deScrollContent:Show()

            local scrollBar = _G["DLCAwardDeScrollScrollBar"]
            if scrollBar then
                if N <= 3 then
                    scrollBar:Hide()
                    self.deScrollFrame:ClearAllPoints()
                    self.deScrollFrame:SetPoint("TOPLEFT", self.deContainer, "TOPLEFT", 0, -20)
                    self.deScrollFrame:SetPoint("BOTTOMRIGHT", self.deContainer, "BOTTOMRIGHT", 0, 0)
                else
                    scrollBar:Show()
                    self.deScrollFrame:ClearAllPoints()
                    self.deScrollFrame:SetPoint("TOPLEFT", self.deContainer, "TOPLEFT", 0, -20)
                    self.deScrollFrame:SetPoint("BOTTOMRIGHT", self.deContainer, "BOTTOMRIGHT", -20, 0)
                end
            end

            for _, row in ipairs(self.deRowPool) do row:Hide() end

            local deScrollHeight = 0
            for idx, de in ipairs(disenchanters) do
                self:CreateDisenchanterRow(idx, self.deScrollContent, de, isLM, itemData, N)
                deScrollHeight = deScrollHeight + 38
            end
            self.deScrollContent:SetHeight(deScrollHeight)
        end
    else
        if self.deContainer then
            self.deContainer:Hide()
        end
    end
end

function UI_Award:ShowAwardWindow(itemData)
    if not itemData then
        if self.awardFrame then self.awardFrame:Hide() end
        return
    end

    if not self.awardFrame or not self.awardFrame:IsShown() or (self.activeItemData and self.activeItemData.link ~= itemData.link) then
        self.deCollapsed = true
    end

    self.activeItemData = itemData
    local NativeGUI = DesolateLootcouncil:GetModule("UI_NativeGUI")
    local isLM = DesolateLootcouncil.API:IsLootMaster()

    if not self.awardFrame then
        local frame = NativeGUI:CreateWindow("DLCAwardFrame", L["Award Item"], "Award")
        self.awardFrame = frame
    end

    if not self.awardScroll then
        local scrollFrame, scrollContent = NativeGUI:CreateScrollFrame(self.awardFrame, -75, -16)
        self.awardScroll = scrollFrame
        self.awardScrollContent = scrollContent
    end

    self.awardFrame:Show()

    -- Reset pools
    for _, r in ipairs(self.awardRowPool) do r:Hide() end
    for _, r in ipairs(self.deRowPool) do r:Hide() end

    -- Render Custom Header
    RenderAwardHeader(self, itemData)

    local API  = DesolateLootcouncil.API
    local guid = itemData.sourceGUID or itemData.link
    local summary = API:GetVoteSummary(guid)
    local votes   = summary.votes

    local disenchanters = API:GetDisenchanterList()
    local N = #disenchanters
    local H = 0
    if N > 0 then
        if self.deCollapsed == nil then
            self.deCollapsed = true
        end
        if self.deCollapsed then
            H = 20
        else
            local numDisplay = math.min(N, 3)
            local contentHeight = numDisplay * 32 + (numDisplay - 1) * 6
            H = 18 + 8 + contentHeight
        end
    end

    -- Dynamically push votes list upwards if the bottom disenchant dock is visible
    self.awardScroll:ClearAllPoints()
    self.awardScroll:SetPoint("TOPLEFT", self.awardFrame, "TOPLEFT", 16, -75)
    if H > 0 then
        self.awardScroll:SetPoint("BOTTOMRIGHT", self.awardFrame, "BOTTOMRIGHT", -36, H + 24)
    else
        self.awardScroll:SetPoint("BOTTOMRIGHT", self.awardFrame, "BOTTOMRIGHT", -36, 16)
    end

    local voteList = {}
    if votes then
        for voter, voteData in pairs(votes) do
            local vType = type(voteData) == "table" and voteData.type or voteData
            local vRoll = (type(voteData) == "table" and voteData.roll) or 0
            local vNote = (type(voteData) == "table" and voteData.note) or ""

            if vType ~= 5 then
                local rank = API:GetPlayerRankInList(voter, itemData.category)
                table.insert(voteList, { name = voter, type = vType, roll = vRoll, rank = rank, note = vNote })
            end
        end

        table.sort(voteList, function(a, b)
            if a.type ~= b.type then return a.type < b.type end
            if a.type == 1 then
                if a.rank ~= b.rank then return a.rank < b.rank end
                return a.roll > b.roll
            end
            return a.roll > b.roll
        end)
    end

    -- Render Votes List with actual values
    RenderVoteList(self, voteList, isLM, itemData, NativeGUI)

    -- Render Bottom Dock
    RenderDisenchantersDock(self, disenchanters, isLM, itemData, N, H, NativeGUI)
end

