local _, ns = ...

local QuestMobs = {}
ns.QuestMobs = QuestMobs

-- Blizzard nameplate tablolarini taint etmemek icin rozetler harici tabloda tutulur
local nameplateBadges = {}
local activeUnits = {} -- [unit] = nameplate

local LINE_TYPE_QUEST_TITLE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle
local LINE_TYPE_QUEST_OBJECTIVE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective

local ICON_LOOT = "Interface\\Cursor\\Pickup" -- Toplama / slottan dusen esya icin el ikonu
local ICON_KILL = "Interface\\Cursor\\Attack" -- Oldurme gorevi icin kilic ikonu

-- Gorev hedefinin esya dusurme/toplama (item/object) mi yoksa oldurme (monster) mi oldugunu belirler
local function IsLootObjective(questID, objectiveText)
    if ns:IsSafeNumber(questID) then
        local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", questID)
        if okObj and type(objectives) == "table" then
            local hasAnyItem = false
            local hasAnyMonster = false
            for i = 1, #objectives do
                local obj = objectives[i]
                if type(obj) == "table" and not obj.finished then
                    local oType = obj.type
                    -- Metin dogrudan eslesiyorsa kesin tipi dondur
                    if ns:IsSafeString(objectiveText) and ns:IsSafeString(obj.text) then
                        local a = string.lower(objectiveText)
                        local b = string.lower(obj.text)
                        if a == b or a:find(b, 1, true) or b:find(a, 1, true) then
                            if oType == "item" or oType == "object" then
                                return true
                            elseif oType == "monster" then
                                return false
                            end
                        end
                    end
                    if oType == "item" or oType == "object" then
                        hasAnyItem = true
                    elseif oType == "monster" then
                        hasAnyMonster = true
                    end
                end
            end
            if hasAnyItem and not hasAnyMonster then
                return true
            elseif hasAnyMonster and not hasAnyItem then
                return false
            end
        end
    end

    -- Yedek: hedef metnine gore ayirt et
    if ns:IsSafeString(objectiveText) then
        local lower = string.lower(objectiveText)
        if lower:find("slain", 1, true) or lower:find("killed", 1, true)
            or lower:find("defeated", 1, true) or lower:find("destroy", 1, true) then
            return false
        end
        return true
    end
    return false
end

-- Bir hedefin metninden ilerleme bilgisini cikarir (orn. "3/8" veya "65%")
local function ExtractProgressText(text)
    if not ns:IsSafeString(text) then
        return nil
    end
    local cur, maxVal = text:match("(%d+)%s*/%s*(%d+)")
    if cur and maxVal then
        local cNum, mNum = tonumber(cur), tonumber(maxVal)
        if cNum and mNum and mNum > 0 then
            if cNum >= mNum then
                return nil, true -- Tamamlanmis
            end
            return cur .. "/" .. maxVal, false
        end
    end
    local pct = text:match("(%d+)%%")
    if pct then
        local pNum = tonumber(pct)
        if pNum and pNum >= 100 then
            return nil, true
        end
        return pct .. "%", false
    end
    return nil, false
end

-- Unit'in aktif (tamamlanmamis) bir gorev hedefi olup olmadigini kontrol eder
local function GetUnitQuestInfo(unit)
    if not ns:IsSafeString(unit) then
        return nil
    end

    local okExists, exists = ns:SafeGlobal("UnitExists", unit)
    if not okExists or not exists then
        return nil
    end

    local okPlayer, isPlayer = ns:SafeGlobal("UnitIsPlayer", unit)
    if okPlayer and isPlayer then
        return nil
    end

    local okDead, isDead = ns:SafeGlobal("UnitIsDead", unit)
    if okDead and isDead then
        return nil
    end

    -- 1) Resmi C_TooltipInfo.GetUnit API'si (Retail / Midnight / Forever)
    local okTip, tipData = ns:TrySafeC("C_TooltipInfo", "GetUnit", unit)
    if okTip and type(tipData) == "table" and type(tipData.lines) == "table" then
        local currentQuestID = nil
        local currentQuestTitle = nil
        local bestResult = nil

        for i = 1, #tipData.lines do
            local line = tipData.lines[i]
            if type(line) == "table" then
                local lType = line.type
                local lText = line.leftText

                if LINE_TYPE_QUEST_TITLE and lType == LINE_TYPE_QUEST_TITLE then
                    currentQuestID = ns:IsSafeNumber(line.id) and line.id or nil
                    currentQuestTitle = ns:IsSafeString(lText) and lText or nil
                elseif (LINE_TYPE_QUEST_OBJECTIVE and lType == LINE_TYPE_QUEST_OBJECTIVE)
                    or (line.completed == false and ns:IsSafeString(lText)) then
                    local isCompleted = (line.completed == true)
                    local progText, progDone = ExtractProgressText(lText)
                    if not isCompleted and not progDone then
                        local isActiveTarget = (ns.activeQuestID ~= nil and currentQuestID ~= nil and currentQuestID == ns.activeQuestID)
                        local info = {
                            questID = currentQuestID,
                            questTitle = currentQuestTitle,
                            objectiveText = ns:IsSafeString(lText) and lText or nil,
                            progress = progText,
                            isLoot = IsLootObjective(currentQuestID, lText),
                            isActiveTarget = isActiveTarget,
                        }
                        if isActiveTarget then
                            return info
                        end
                        if not bestResult then
                            bestResult = info
                        end
                    end
                end
            end
        end

        if bestResult then
            return bestResult
        end
    end

    -- 2) Yedek: C_QuestLog.UnitIsRelatedToActiveQuest varsa kontrol et
    local okRel, isRelated = ns:TrySafeC("C_QuestLog", "UnitIsRelatedToActiveQuest", unit)
    if okRel and isRelated == true then
        return {
            questID = nil,
            questTitle = nil,
            objectiveText = nil,
            progress = nil,
            isActiveTarget = false,
        }
    end

    return nil
end

-- Nameplate kenari icin hafif, tiklanamaz gorev hedefi rozeti
local function GetOrCreateBadge(plate)
    local badge = nameplateBadges[plate]
    if badge then
        return badge
    end

    badge = CreateFrame("Frame", nil, plate)
    badge:SetSize(36, 30)
    badge:SetPoint("RIGHT", plate, "LEFT", -3, 0)
    badge:SetFrameStrata("MEDIUM")
    badge:SetFrameLevel((plate:GetFrameLevel() or 1) + 10)
    badge:EnableMouse(false)

    -- Arka parlama halkasi (zarif ve kucuk)
    local glow = badge:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(20, 20)
    glow:SetPoint("TOP", badge, "TOP", 0, 1)
    glow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1.0, 0.85, 0.15, 0.75)
    badge.glow = glow

    -- Zarif gorev hedef ikonu (el = toplama/item, kilic = oldurme)
    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetSize(15, 15)
    icon:SetPoint("TOP", badge, "TOP", 0, -1)
    icon:SetTexture(ICON_KILL)
    badge.icon = icon

    -- Altinda acikca gorunen kalan sayi / ilerleme (orn. 3/8)
    local countText = badge:CreateFontString(nil, "OVERLAY", nil, 7)
    countText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    countText:SetPoint("TOP", icon, "BOTTOM", 0, -2)
    countText:SetJustifyH("CENTER")
    badge.countText = countText

    badge:Hide()
    nameplateBadges[plate] = badge
    return badge
end

function QuestMobs:UpdateUnit(unit)
    local okPlate, plate = ns:TrySafeC("C_NamePlate", "GetNamePlateForUnit", unit)
    if not okPlate or not plate then
        return
    end
    activeUnits[unit] = plate

    local info = GetUnitQuestInfo(unit)
    if info then
        local badge = GetOrCreateBadge(plate)
        badge.icon:SetTexture(info.isLoot and ICON_LOOT or ICON_KILL)

        if info.isActiveTarget then
            -- Secili aktif gorevin mobuysa parlak yesil vurgu
            badge.glow:SetVertexColor(0.20, 1.0, 0.40, 0.90)
            badge.countText:SetTextColor(0.30, 1.0, 0.45)
        elseif info.isLoot then
            -- Esya dusen / toplama gorevinde turkuaz-altin vurgu
            badge.glow:SetVertexColor(0.35, 0.85, 1.0, 0.78)
            badge.countText:SetTextColor(0.65, 0.95, 1.0)
        else
            -- Oldurme gorevinde altin sari vurgu
            badge.glow:SetVertexColor(1.0, 0.75, 0.15, 0.78)
            badge.countText:SetTextColor(1.0, 0.88, 0.25)
        end

        if info.progress then
            badge.countText:SetText(info.progress)
            badge.countText:Show()
        else
            badge.countText:SetText(info.isLoot and "LOOT" or "KES")
            badge.countText:Show()
        end

        badge:Show()
    else
        local badge = nameplateBadges[plate]
        if badge then
            badge:Hide()
        end
    end
end

function QuestMobs:RemoveUnit(unit)
    local plate = activeUnits[unit]
    activeUnits[unit] = nil
    if plate and nameplateBadges[plate] then
        nameplateBadges[plate]:Hide()
    end
end

function QuestMobs:RefreshAllNameplates()
    local okAll, plates = ns:TrySafeC("C_NamePlate", "GetNamePlates")
    if okAll and type(plates) == "table" then
        for i = 1, #plates do
            local p = plates[i]
            if type(p) == "table" and ns:IsSafeString(p.namePlateUnitToken) then
                self:UpdateUnit(p.namePlateUnitToken)
            end
        end
    else
        for unit in pairs(activeUnits) do
            self:UpdateUnit(unit)
        end
    end
end

-- Ozellik 3: Mouseover tooltip'e "Gorev: <gorev adi> <ilerleme>/<hedef>" satiri ekler
-- Midnight'ta kisitli (secret) unit verisi nedeniyle bilgi alinamazsa sessizce satir eklemez.
local function InstallTooltipHook()
    if type(_G.TooltipDataProcessor) == "table"
        and type(_G.TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        pcall(_G.TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tooltip)
            local db = ns.db or ns.DEFAULTS
            if not db.showMobTooltip then
                return
            end
            if tooltip ~= GameTooltip or not tooltip.GetUnit then
                return
            end
            local okU, _, unit = pcall(tooltip.GetUnit, tooltip)
            if not okU or not ns:IsSafeString(unit) then
                return
            end
            local info = GetUnitQuestInfo(unit)
            if not info then
                return
            end

            local qName = info.questTitle
            if not ns:IsSafeString(qName) or qName == "" then
                if ns:IsSafeNumber(info.questID) then
                    local okT, fetched = ns:TrySafeC("C_QuestLog", "GetTitleForQuestID", info.questID)
                    if okT and ns:IsSafeString(fetched) and fetched ~= "" then
                        qName = fetched
                    end
                end
            end
            if not ns:IsSafeString(qName) or qName == "" then
                return
            end

            local progPart = (ns:IsSafeString(info.progress) and info.progress ~= "") and (" " .. info.progress) or ""
            local lineText = "Gorev: " .. qName .. progPart
            if info.isActiveTarget then
                tooltip:AddLine("|cff33ff66" .. lineText .. "|r", 0.3, 1.0, 0.45)
            else
                tooltip:AddLine("|cffffd100" .. lineText .. "|r", 1.0, 0.85, 0.25)
            end
        end)
    end
end

-- =====================================================================
-- Envanterdeki (Cantalar) Gorev Esyalari Icin Turuncu Border Vurgusu
-- =====================================================================
local bagBorders = {}
local bagHooksInstalled = false

local function GetOrCreateBagBorder(itemButton)
    local border = bagBorders[itemButton]
    if border then
        return border
    end

    local f = CreateFrame("Frame", nil, itemButton)
    f:SetAllPoints(itemButton)
    f:SetFrameLevel((itemButton:GetFrameLevel() or 1) + 6)
    f:EnableMouse(false)

    local thickness = 2.5
    local r, g, b, a = 1.0, 0.50, 0.0, 1.0 -- Canli turuncu border

    local top = f:CreateTexture(nil, "OVERLAY", nil, 6)
    top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    top:SetHeight(thickness)
    top:SetColorTexture(r, g, b, a)

    local bottom = f:CreateTexture(nil, "OVERLAY", nil, 6)
    bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(thickness)
    bottom:SetColorTexture(r, g, b, a)

    local left = f:CreateTexture(nil, "OVERLAY", nil, 6)
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -thickness)
    left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, thickness)
    left:SetWidth(thickness)
    left:SetColorTexture(r, g, b, a)

    local right = f:CreateTexture(nil, "OVERLAY", nil, 6)
    right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -thickness)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, thickness)
    right:SetWidth(thickness)
    right:SetColorTexture(r, g, b, a)

    -- Hafif turuncu ic parlama
    local glow = f:CreateTexture(nil, "OVERLAY", nil, 5)
    glow:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    glow:SetColorTexture(1.0, 0.48, 0.0, 0.16)

    f:Hide()
    bagBorders[itemButton] = f
    return f
end

local function IsBagSlotQuestItem(bagID, slotID)
    if not ns:IsSafeNumber(bagID) or not ns:IsSafeNumber(slotID) then
        return false
    end

    -- 1) C_Container.GetContainerItemQuestInfo (gorev esyasi veya gorev baslatan esya)
    local okQ, qInfo = ns:TrySafeC("C_Container", "GetContainerItemQuestInfo", bagID, slotID)
    if okQ and type(qInfo) == "table" then
        if qInfo.isQuestItem == true or (ns:IsSafeNumber(qInfo.questID) and qInfo.questID > 0) then
            return true
        end
    end

    -- 2) Item sinifi Quest (classID == 12) kontrolu
    local okID, itemID = ns:TrySafeC("C_Container", "GetContainerItemID", bagID, slotID)
    if okID and ns:IsSafeNumber(itemID) then
        local okInst, _, _, _, _, _, classID = ns:TrySafeC("C_Item", "GetItemInfoInstant", itemID)
        if not okInst then
            okInst, _, _, _, _, _, classID = ns:SafeGlobal("GetItemInfoInstant", itemID)
        end
        if okInst and ns:IsSafeNumber(classID) and classID == 12 then
            return true
        end
    end

    return false
end

local function UpdateBagButton(itemButton, explicitBagID)
    if type(itemButton) ~= "table" or not itemButton.IsShown or not itemButton:IsShown() then
        local b = bagBorders[itemButton]
        if b then b:Hide() end
        return
    end

    local bagID = explicitBagID
    if not ns:IsSafeNumber(bagID) and type(itemButton.GetBagID) == "function" then
        local okB, bID = pcall(itemButton.GetBagID, itemButton)
        if okB and ns:IsSafeNumber(bID) then
            bagID = bID
        end
    end

    local slotID = nil
    if type(itemButton.GetID) == "function" then
        local okS, sID = pcall(itemButton.GetID, itemButton)
        if okS and ns:IsSafeNumber(sID) then
            slotID = sID
        end
    end

    if IsBagSlotQuestItem(bagID, slotID) then
        local border = GetOrCreateBagBorder(itemButton)
        border:Show()
    else
        local border = bagBorders[itemButton]
        if border then
            border:Hide()
        end
    end
end

local function ScanContainerFrame(frame)
    if type(frame) ~= "table" or not frame.IsShown or not frame:IsShown() then
        return
    end
    if type(frame.EnumerateValidItems) == "function" then
        for _, itemButton in frame:EnumerateValidItems() do
            UpdateBagButton(itemButton, nil)
        end
        return
    end
    -- Eski stil ayri canta butonlari (ContainerFrameXItemY)
    local frameName = (type(frame.GetName) == "function") and frame:GetName()
    local bagID = (type(frame.GetID) == "function") and frame:GetID()
    if ns:IsSafeString(frameName) and ns:IsSafeNumber(bagID) then
        for slot = 1, 36 do
            local btn = _G[frameName .. "Item" .. slot]
            if btn then
                UpdateBagButton(btn, bagID)
            end
        end
    end
end

function QuestMobs:RefreshBagHighlights()
    if type(_G.ContainerFrameCombinedBags) == "table" then
        pcall(ScanContainerFrame, _G.ContainerFrameCombinedBags)
    end
    if type(_G.ContainerFrameContainer) == "table" and type(_G.ContainerFrameContainer.ContainerFrames) == "table" then
        for _, cf in ipairs(_G.ContainerFrameContainer.ContainerFrames) do
            pcall(ScanContainerFrame, cf)
        end
    end
    for i = 1, 6 do
        local cf = _G["ContainerFrame" .. i]
        if type(cf) == "table" then
            pcall(ScanContainerFrame, cf)
        end
    end
end

local function InstallBagHooks()
    if bagHooksInstalled then
        return
    end
    bagHooksInstalled = true

    if type(_G.ContainerFrameCombinedBags) == "table" and type(_G.ContainerFrameCombinedBags.UpdateItems) == "function" then
        hooksecurefunc(_G.ContainerFrameCombinedBags, "UpdateItems", function()
            QuestMobs:RefreshBagHighlights()
        end)
    end
    if type(_G.ContainerFrame_Update) == "function" then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            pcall(ScanContainerFrame, frame)
        end)
    end
    if type(_G.ContainerFrameContainer) == "table" and type(_G.ContainerFrameContainer.ContainerFrames) == "table" then
        for _, cf in ipairs(_G.ContainerFrameContainer.ContainerFrames) do
            if type(cf.UpdateItems) == "function" then
                hooksecurefunc(cf, "UpdateItems", function(selfFrame)
                    pcall(ScanContainerFrame, selfFrame)
                end)
            end
        end
    end
end

-- Nameplate ve canta olaylari icin ayri hafif event cercevesi
local plateEventFrame = CreateFrame("Frame", "QuestGoToZMobEventFrame")
plateEventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
plateEventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
plateEventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
plateEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
plateEventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        QuestMobs:UpdateUnit(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        QuestMobs:RemoveUnit(unit)
    elseif event == "UNIT_QUEST_LOG_CHANGED" and unit == "player" then
        QuestMobs:RefreshAllNameplates()
        QuestMobs:RefreshBagHighlights()
    elseif event == "BAG_UPDATE_DELAYED" then
        QuestMobs:RefreshBagHighlights()
    end
end)

ns:RegisterCallback("PLAYER_LOGIN", function()
    InstallTooltipHook()
    InstallBagHooks()
    QuestMobs:RefreshAllNameplates()
    QuestMobs:RefreshBagHighlights()
end)

ns:RegisterCallback("QUEST_LOG_UPDATE", function()
    QuestMobs:RefreshAllNameplates()
    QuestMobs:RefreshBagHighlights()
end)

ns:RegisterCallback("TARGET_CHANGED", function()
    QuestMobs:RefreshAllNameplates()
end)
