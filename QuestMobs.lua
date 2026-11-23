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

-- Dungeon / Raid / PvP instance icinde Midnight nameplate kisitlamasi nedeniyle rozetleri kapat
local function IsRestrictedInstance()
    local okInst, inInstance, instType = ns:SafeGlobal("IsInInstance")
    if okInst and ns:IsSafeBoolean(inInstance) and inInstance then
        if not ns:IsSafeString(instType) or instType ~= "none" then
            return true
        end
    end
    return false
end

local function HideAllNameplateBadges()
    for _, badge in pairs(nameplateBadges) do
        badge:Hide()
    end
end

-- Unit'in aktif (tamamlanmamis) bir gorev hedefi olup olmadigini kontrol eder
local function GetUnitQuestInfo(unit)
    if IsRestrictedInstance() or not ns:IsSafeString(unit) then
        return nil
    end

    local okExists, exists = ns:SafeGlobal("UnitExists", unit)
    if not okExists or not ns:IsSafeBoolean(exists) or not exists then
        return nil
    end

    local okPlayer, isPlayer = ns:SafeGlobal("UnitIsPlayer", unit)
    if okPlayer and ns:IsSafeBoolean(isPlayer) and isPlayer then
        return nil
    end

    local okDead, isDead = ns:SafeGlobal("UnitIsDead", unit)
    if okDead and ns:IsSafeBoolean(isDead) and isDead then
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
                local completedSafe = ns:IsSafeBoolean(line.completed) and line.completed or nil

                if LINE_TYPE_QUEST_TITLE and ns:IsSafeNumber(lType) and lType == LINE_TYPE_QUEST_TITLE then
                    currentQuestID = ns:IsSafeNumber(line.id) and line.id or nil
                    currentQuestTitle = ns:IsSafeString(lText) and lText or nil
                elseif (LINE_TYPE_QUEST_OBJECTIVE and ns:IsSafeNumber(lType) and lType == LINE_TYPE_QUEST_OBJECTIVE)
                    or (completedSafe == false and ns:IsSafeString(lText)) then
                    local isCompleted = (completedSafe == true)
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
    if okRel and ns:IsSafeBoolean(isRelated) and isRelated == true then
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
-- Taint onlemek icin Blizzard plate icine degil, UIParent uzerine olusturulur.
local function GetOrCreateBadge(plate)
    local badge = nameplateBadges[plate]
    if badge then
        return badge
    end

    badge = CreateFrame("Frame", nil, UIParent)
    badge:SetSize(36, 30)
    badge:SetPoint("RIGHT", plate, "LEFT", -3, 0)
    badge:SetFrameStrata("LOW")
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
    if (ns.db and ns.db.enableQuestModule == false) or IsRestrictedInstance() then
        HideAllNameplateBadges()
        return
    end
    if not ns:IsSafeString(unit) then
        return
    end

    local okPlate, plate = ns:TrySafeC("C_NamePlate", "GetNamePlateForUnit", unit)
    if not okPlate or not plate then
        return
    end
    if type(plate.IsForbidden) == "function" then
        local okForb, forb = pcall(plate.IsForbidden, plate)
        if not okForb or (ns:IsSafeBoolean(forb) and forb) or not ns:IsSafeBoolean(forb) then
            return
        end
    end
    activeUnits[unit] = plate

    local okInfo, info = pcall(GetUnitQuestInfo, unit)
    if not okInfo then
        info = nil
    end
    if info then
        local badge = GetOrCreateBadge(plate)
        pcall(function()
            badge:ClearAllPoints()
            badge:SetPoint("RIGHT", plate, "LEFT", -3, 0)
        end)
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
    if (ns.db and ns.db.enableQuestModule == false) or IsRestrictedInstance() then
        HideAllNameplateBadges()
        return
    end
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

-- Bir mob icin tum tamamlanmamis gorev eslesmelerini dondurur (coklu gorev destegi)
local function GetUnitAllQuestInfos(unit)
    if IsRestrictedInstance() or not ns:IsSafeString(unit) then
        return {}
    end
    local okExists, exists = ns:SafeGlobal("UnitExists", unit)
    if not okExists or not ns:IsSafeBoolean(exists) or not exists then
        return {}
    end
    local okPlayer, isPlayer = ns:SafeGlobal("UnitIsPlayer", unit)
    if okPlayer and ns:IsSafeBoolean(isPlayer) and isPlayer then
        return {}
    end

    local results = {}
    local seenKeys = {}

    local okTip, tipData = ns:TrySafeC("C_TooltipInfo", "GetUnit", unit)
    if okTip and type(tipData) == "table" and type(tipData.lines) == "table" then
        local currentQuestID = nil
        local currentQuestTitle = nil

        for i = 1, #tipData.lines do
            local line = tipData.lines[i]
            if type(line) == "table" then
                local lType = line.type
                local lText = line.leftText
                local completedSafe = ns:IsSafeBoolean(line.completed) and line.completed or nil

                if LINE_TYPE_QUEST_TITLE and ns:IsSafeNumber(lType) and lType == LINE_TYPE_QUEST_TITLE then
                    currentQuestID = ns:IsSafeNumber(line.id) and line.id or nil
                    currentQuestTitle = ns:IsSafeString(lText) and lText or nil
                elseif (LINE_TYPE_QUEST_OBJECTIVE and ns:IsSafeNumber(lType) and lType == LINE_TYPE_QUEST_OBJECTIVE)
                    or (completedSafe == false and ns:IsSafeString(lText)) then
                    local isCompleted = (completedSafe == true)
                    local progText, progDone = ExtractProgressText(lText)
                    if not isCompleted and not progDone then
                        local qName = currentQuestTitle
                        if (not ns:IsSafeString(qName) or qName == "") and ns:IsSafeNumber(currentQuestID) then
                            local okT, fetched = ns:TrySafeC("C_QuestLog", "GetTitleForQuestID", currentQuestID)
                            if okT and ns:IsSafeString(fetched) and fetched ~= "" then
                                qName = fetched
                            end
                        end
                        if ns:IsSafeString(qName) and qName ~= "" then
                            local dedupeKey = tostring(currentQuestID or qName) .. "|" .. tostring(progText or "")
                            if not seenKeys[dedupeKey] then
                                seenKeys[dedupeKey] = true
                                table.insert(results, {
                                    questID = currentQuestID,
                                    questTitle = qName,
                                    progress = progText,
                                    isActiveTarget = (ns.activeQuestID ~= nil and currentQuestID ~= nil and currentQuestID == ns.activeQuestID),
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return results
end

-- Esya adi ile aktif gorev hedeflerini eslestirir (canta esyasi tooltip'i icin)
local function FindQuestsForItemName(itemName)
    if not ns:IsSafeString(itemName) or itemName == "" then
        return {}
    end
    local lowerItem = string.lower(itemName)
    local okNum, numEntries = ns:TrySafeC("C_QuestLog", "GetNumQuestLogEntries")
    if not okNum or not ns:IsSafeNumber(numEntries) then
        return {}
    end

    local matches = {}
    for idx = 1, numEntries do
        local okInfo, info = ns:TrySafeC("C_QuestLog", "GetInfo", idx)
        if okInfo and type(info) == "table" and not info.isHeader and not info.isHidden and ns:IsSafeNumber(info.questID) then
            local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", info.questID)
            if okObj and type(objectives) == "table" then
                for j = 1, #objectives do
                    local obj = objectives[j]
                    if type(obj) == "table" and ns:IsSafeString(obj.text) then
                        if string.lower(obj.text):find(lowerItem, 1, true) then
                            local prog = ExtractProgressText(obj.text)
                            table.insert(matches, {
                                questID = info.questID,
                                title = info.title or ("Gorev #" .. tostring(info.questID)),
                                progress = prog or (obj.finished and "Tamam" or nil),
                            })
                            break
                        end
                    end
                end
            end
        end
    end
    return matches
end

-- Faz 2 & Ozellik 3: Coklu mob tooltip'i + canta esyasi tooltip'i + parti ilerlemesi
-- Midnight'ta kisitli (secret) unit verisi nedeniyle bilgi alinamazsa sessizce satir eklemez.
local function InstallTooltipHook()
    if type(_G.TooltipDataProcessor) ~= "table"
        or type(_G.TooltipDataProcessor.AddTooltipPostCall) ~= "function"
        or not Enum or not Enum.TooltipDataType then
        return
    end

    -- 1) Unit (Mob) tooltip'i: birden fazla goreve lazimsa hepsini alt alta goster
    if Enum.TooltipDataType.Unit then
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
            local infos = GetUnitAllQuestInfos(unit)
            if #infos == 0 then
                return
            end

            for i = 1, #infos do
                local info = infos[i]
                local progPart = (ns:IsSafeString(info.progress) and info.progress ~= "") and (" " .. info.progress) or ""
                local lineText = "Gorev: " .. info.questTitle .. progPart
                if info.isActiveTarget then
                    tooltip:AddLine("|cff33ff66" .. lineText .. "|r", 0.3, 1.0, 0.45)
                else
                    tooltip:AddLine("|cffffd100" .. lineText .. "|r", 1.0, 0.85, 0.25)
                end

                if ns.PartySync and ns:IsSafeNumber(info.questID) then
                    local pp = ns.PartySync:GetPartyProgress(info.questID)
                    if pp then
                        local parts = {}
                        for p = 1, #pp do
                            table.insert(parts, pp[p].name .. ": " .. pp[p].text)
                        end
                        tooltip:AddLine("  Parti: " .. table.concat(parts, ", "), 0.55, 0.82, 1.0)
                    end
                end
            end
        end)
    end

    -- 2) Item (Esya) tooltip'i: cantadaki gorev esyasinin hangi goreve ait oldugunu goster
    if Enum.TooltipDataType.Item then
        pcall(_G.TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip)
            local db = ns.db or ns.DEFAULTS
            if not db.showMobTooltip then
                return
            end
            if tooltip ~= GameTooltip or not tooltip.GetItem then
                return
            end
            local okI, itemName = pcall(tooltip.GetItem, tooltip)
            if not okI or not ns:IsSafeString(itemName) or itemName == "" then
                return
            end
            local matches = FindQuestsForItemName(itemName)
            for i = 1, #matches do
                local m = matches[i]
                local progPart = m.progress and (" (" .. m.progress .. ")") or ""
                tooltip:AddLine("|cffff9922Gorev: " .. m.title .. progPart .. "|r", 1.0, 0.65, 0.20)
            end
        end)
    end
end

-- =====================================================================
-- Envanterdeki (Cantalar) Gorev Esyalari Icin Turuncu Border Vurgusu
-- Taint/ADDON_ACTION_BLOCKED onlemek icin Secure canta butonlarinin icine
-- child eklenmez; UIParent tabanli ayri bir overlay uzerinde konumlandirilir.
-- =====================================================================
local bagOverlayRoot = nil
local bagBorders = {}
local bagHooksInstalled = false

local function GetBagOverlayRoot()
    if not bagOverlayRoot then
        bagOverlayRoot = CreateFrame("Frame", "QuestGoToZBagOverlayRoot", UIParent)
        bagOverlayRoot:SetAllPoints(UIParent)
        bagOverlayRoot:SetFrameStrata("HIGH")
        bagOverlayRoot:EnableMouse(false)
    end
    return bagOverlayRoot
end

local function GetOrCreateBagBorder(itemButton)
    local border = bagBorders[itemButton]
    if border then
        return border
    end

    local f = CreateFrame("Frame", nil, GetBagOverlayRoot())
    f:SetAllPoints(itemButton)
    f:SetFrameStrata("HIGH")
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

-- Yalnizca ustunde AKTIF gorevi bulunan gorev esyalarini tespit etmek icin onbellek
local activeQuestIDs = {}
local activeSpecialItemIDs = {}
local activeObjectiveTexts = {}

local function RebuildActiveQuestItemCache()
    wipe(activeQuestIDs)
    wipe(activeSpecialItemIDs)
    wipe(activeObjectiveTexts)

    local okNum, numEntries = ns:TrySafeC("C_QuestLog", "GetNumQuestLogEntries")
    if not okNum or not ns:IsSafeNumber(numEntries) then
        return
    end

    for idx = 1, numEntries do
        local okInfo, info = ns:TrySafeC("C_QuestLog", "GetInfo", idx)
        if okInfo and type(info) == "table" and not info.isHeader and not info.isHidden and ns:IsSafeNumber(info.questID) then
            local qid = info.questID
            activeQuestIDs[qid] = true

            -- Goreve bagli kullanilabilir ozel gorev esyasi (GetQuestLogSpecialItemInfo)
            local okSpec, link = ns:SafeGlobal("GetQuestLogSpecialItemInfo", idx)
            if okSpec and ns:IsSafeString(link) then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID then
                    activeSpecialItemIDs[itemID] = true
                end
            end

            -- Aktif gorev hedeflerindeki esya adlarini topla
            local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", qid)
            if okObj and type(objectives) == "table" then
                for j = 1, #objectives do
                    local obj = objectives[j]
                    if type(obj) == "table" and ns:IsSafeString(obj.text) and obj.text ~= "" then
                        table.insert(activeObjectiveTexts, string.lower(obj.text))
                    end
                end
            end
        end
    end
end

-- Yalnizca ustunde aktif olarak bulunan bir goreve ait esya ise true doner
local function IsBagSlotQuestItem(bagID, slotID)
    if not ns:IsSafeNumber(bagID) or not ns:IsSafeNumber(slotID) then
        return false
    end

    local okID, itemID = ns:TrySafeC("C_Container", "GetContainerItemID", bagID, slotID)
    if not okID or not ns:IsSafeNumber(itemID) then
        return false
    end

    -- 1) Ustundeki aktif gorevin ozel kullanilabilir esyasi mi?
    if activeSpecialItemIDs[itemID] then
        return true
    end

    -- 2) C_Container.GetContainerItemQuestInfo ile bagli questID ustunde aktif mi?
    local okQ, qInfo = ns:TrySafeC("C_Container", "GetContainerItemQuestInfo", bagID, slotID)
    if okQ and type(qInfo) == "table" and ns:IsSafeNumber(qInfo.questID) and qInfo.questID > 0 then
        if activeQuestIDs[qInfo.questID] then
            return true
        end
    end

    -- 3) Esya adi ustundeki aktif gorevlerin hedeflerinden birinde geciyor mu?
    if #activeObjectiveTexts > 0 then
        local itemName = nil
        local okN, fetched = ns:TrySafeC("C_Item", "GetItemNameByID", itemID)
        if okN and ns:IsSafeString(fetched) and fetched ~= "" then
            itemName = fetched
        else
            local okI, name2 = ns:SafeGlobal("GetItemInfo", itemID)
            if okI and ns:IsSafeString(name2) and name2 ~= "" then
                itemName = name2
            end
        end
        if itemName then
            local lowerName = string.lower(itemName)
            for i = 1, #activeObjectiveTexts do
                if activeObjectiveTexts[i]:find(lowerName, 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

-- Cantadaki daha yuksek ilvl giyilebilir esyalar icin yesil yukari ok (UIParent overlay)
local upgradeArrows = {}

local EQUIP_LOC_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_RANGED = { 16 },
    INVTYPE_RANGEDRIGHT = { 16 },
}

local function GetOrCreateUpgradeArrow(itemButton)
    local arr = upgradeArrows[itemButton]
    if arr then
        return arr
    end
    local f = CreateFrame("Frame", nil, GetBagOverlayRoot())
    f:SetSize(14, 14)
    f:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", -1, -1)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)

    local tex = f:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    tex:SetDesaturated(true)
    tex:SetVertexColor(0.20, 1.0, 0.35, 1.0)
    f.tex = tex

    f:Hide()
    upgradeArrows[itemButton] = f
    return f
end

local function GetSafeItemLevel(link)
    if not ns:IsSafeString(link) then
        return nil
    end
    local okD, ilvl = ns:TrySafeC("C_Item", "GetDetailedItemLevelInfo", link)
    if okD and ns:IsSafeNumber(ilvl) and ilvl > 0 then
        return ilvl
    end
    local okG, _, _, _, baseIlvl = ns:SafeGlobal("GetItemInfo", link)
    if okG and ns:IsSafeNumber(baseIlvl) and baseIlvl > 0 then
        return baseIlvl
    end
    return nil
end

local function IsBagSlotEquipmentUpgrade(bagID, slotID)
    local db = ns.db or ns.DEFAULTS
    if not db.showUpgradeArrows then
        return false
    end
    if not ns:IsSafeNumber(bagID) or not ns:IsSafeNumber(slotID) then
        return false
    end

    local okLink, link = ns:TrySafeC("C_Container", "GetContainerItemLink", bagID, slotID)
    if not okLink or not ns:IsSafeString(link) then
        return false
    end

    local okEq, isEq = ns:TrySafeC("C_Item", "IsEquippableItem", link)
    if not okEq then
        okEq, isEq = ns:SafeGlobal("IsEquippableItem", link)
    end
    if not (okEq and isEq == true) then
        return false
    end

    local okInfo, _, _, _, _, minLevel, _, _, _, equipLoc, _, _, classID = ns:TrySafeC("C_Item", "GetItemInfo", link)
    if not okInfo then
        okInfo, _, _, _, _, minLevel, _, _, _, equipLoc, _, _, classID = ns:SafeGlobal("GetItemInfo", link)
    end
    if not okInfo or not ns:IsSafeString(equipLoc) then
        return false
    end
    if classID ~= 2 and classID ~= 4 then -- Sadece Weapon (2) ve Armor (4)
        return false
    end

    local slots = EQUIP_LOC_SLOTS[equipLoc]
    if not slots then
        return false
    end

    local okLvl, playerLvl = ns:SafeGlobal("UnitLevel", "player")
    if okLvl and ns:IsSafeNumber(playerLvl) and ns:IsSafeNumber(minLevel) and minLevel > playerLvl then
        return false
    end

    local bagIlvl = GetSafeItemLevel(link)
    if not bagIlvl then
        return false
    end

    -- Giyili slottaki en dusuk ilvl ile karsilastir
    local lowestEquipped = math.huge
    for i = 1, #slots do
        local okEL, eqLink = ns:SafeGlobal("GetInventoryItemLink", "player", slots[i])
        if okEL and ns:IsSafeString(eqLink) then
            local eqIlvl = GetSafeItemLevel(eqLink) or 0
            if eqIlvl < lowestEquipped then
                lowestEquipped = eqIlvl
            end
        else
            lowestEquipped = 0
        end
    end

    return bagIlvl > lowestEquipped
end

local function UpdateBagButton(itemButton, explicitBagID)
    if type(itemButton) ~= "table" or not itemButton.IsShown or not itemButton:IsShown() then
        local b = bagBorders[itemButton]
        if b then b:Hide() end
        local a = upgradeArrows[itemButton]
        if a then a:Hide() end
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

    if not (ns.db and ns.db.enableQuestModule == false) and IsBagSlotQuestItem(bagID, slotID) then
        local border = GetOrCreateBagBorder(itemButton)
        border:Show()
    else
        local border = bagBorders[itemButton]
        if border then
            border:Hide()
        end
    end

    if IsBagSlotEquipmentUpgrade(bagID, slotID) then
        local arr = GetOrCreateUpgradeArrow(itemButton)
        arr:Show()
    else
        local arr = upgradeArrows[itemButton]
        if arr then
            arr:Hide()
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

local function HideAllBagBorders()
    for _, border in pairs(bagBorders) do
        border:Hide()
    end
    for _, arr in pairs(upgradeArrows) do
        arr:Hide()
    end
end

function QuestMobs:RefreshBagHighlights()
    if ns:IsInCombat() then
        ns:RunOutOfCombat("refresh_bag_highlights", function()
            QuestMobs:RefreshBagHighlights()
        end)
        return
    end

    HideAllBagBorders()
    RebuildActiveQuestItemCache()

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

    if type(_G.ContainerFrameCombinedBags) == "table" then
        if type(_G.ContainerFrameCombinedBags.UpdateItems) == "function" then
            hooksecurefunc(_G.ContainerFrameCombinedBags, "UpdateItems", function()
                QuestMobs:RefreshBagHighlights()
            end)
        end
        if type(_G.ContainerFrameCombinedBags.HookScript) == "function" then
            _G.ContainerFrameCombinedBags:HookScript("OnHide", function()
                HideAllBagBorders()
            end)
        end
    end
    if type(_G.ContainerFrame_Update) == "function" then
        hooksecurefunc("ContainerFrame_Update", function()
            QuestMobs:RefreshBagHighlights()
        end)
    end
    if type(_G.ContainerFrameContainer) == "table" and type(_G.ContainerFrameContainer.ContainerFrames) == "table" then
        for _, cf in ipairs(_G.ContainerFrameContainer.ContainerFrames) do
            if type(cf.UpdateItems) == "function" then
                hooksecurefunc(cf, "UpdateItems", function()
                    QuestMobs:RefreshBagHighlights()
                end)
            end
            if type(cf.HookScript) == "function" then
                cf:HookScript("OnHide", function()
                    QuestMobs:RefreshBagHighlights()
                end)
            end
        end
    end
end

-- =====================================================================
-- Tank Aggro Nameplate Can Bari Renkleri (Bende=Yesil, Kayiyor=Turuncu, Degil=Kirmizi)
-- Midnight secret/forbidden korumali: kisitliysa sessizce atlar, 0 hata.
-- =====================================================================
local threatHookInstalled = false

local function ApplyTankThreatColor(unitFrame)
    local db = ns.db or ns.DEFAULTS
    if not db.tankThreatColors or type(unitFrame) ~= "table" then
        return
    end

    if type(unitFrame.IsForbidden) == "function" then
        local okF, forb = pcall(unitFrame.IsForbidden, unitFrame)
        if not okF or not ns:IsSafeBoolean(forb) or forb then
            return
        end
    end

    local unit = unitFrame.displayedUnit or unitFrame.unit
    if not ns:IsSafeString(unit) or not unit:match("^nameplate") then
        return
    end

    local hb = unitFrame.healthBar
    if type(hb) ~= "table" or type(hb.SetStatusBarColor) ~= "function" then
        return
    end

    local okP, isPlayer = ns:SafeGlobal("UnitIsPlayer", unit)
    if okP and ns:IsSafeBoolean(isPlayer) and isPlayer then
        return
    end

    local okAtk, canAttack = ns:SafeGlobal("UnitCanAttack", "player", unit)
    if not (okAtk and ns:IsSafeBoolean(canAttack) and canAttack) then
        return
    end

    local okCmb, inCombat = ns:SafeGlobal("UnitAffectingCombat", unit)
    if not (okCmb and ns:IsSafeBoolean(inCombat) and inCombat) then
        return
    end

    local okT, status = ns:SafeGlobal("UnitThreatSituation", "player", unit)
    if not okT then
        return
    end

    -- Midnight'ta status secret number donerse sessizce atla
    if status ~= nil and not ns:IsSafeNumber(status) then
        return
    end

    if status == 3 then
        -- Aggro kesin sende: YESIL
        pcall(hb.SetStatusBarColor, hb, 0.15, 0.92, 0.32)
    elseif status == 2 then
        -- Aggro sende ama kaybetmek uzeresin: TURUNCU/SARI
        pcall(hb.SetStatusBarColor, hb, 1.0, 0.72, 0.12)
    else
        -- Savasta ama aggro sende DEGIL (nil, 0 veya 1): PARLAK KIRMIZI
        pcall(hb.SetStatusBarColor, hb, 1.0, 0.14, 0.14)
    end
end

function QuestMobs:RefreshThreatColors()
    local db = ns.db or ns.DEFAULTS
    if not db.tankThreatColors then
        return
    end
    local okAll, plates = ns:TrySafeC("C_NamePlate", "GetNamePlates")
    if okAll and type(plates) == "table" then
        for i = 1, #plates do
            local p = plates[i]
            if type(p) == "table" then
                local okF, forb = true, false
                if type(p.IsForbidden) == "function" then
                    okF, forb = pcall(p.IsForbidden, p)
                end
                if okF and ns:IsSafeBoolean(forb) and not forb and type(p.UnitFrame) == "table" then
                    pcall(ApplyTankThreatColor, p.UnitFrame)
                end
            end
        end
    end
end

local function InstallThreatHooks()
    if threatHookInstalled then
        return
    end
    threatHookInstalled = true

    if type(_G.CompactUnitFrame_UpdateHealthColor) == "function" then
        hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
            pcall(ApplyTankThreatColor, frame)
        end)
    end
end

-- Nameplate ve canta olaylari icin ayri hafif event cercevesi
local plateEventFrame = CreateFrame("Frame", "QuestGoToZMobEventFrame")
plateEventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
plateEventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
plateEventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
plateEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
plateEventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
plateEventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
plateEventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        QuestMobs:UpdateUnit(unit)
        QuestMobs:RefreshThreatColors()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        QuestMobs:RemoveUnit(unit)
    elseif event == "UNIT_QUEST_LOG_CHANGED" and unit == "player" then
        QuestMobs:RefreshAllNameplates()
        QuestMobs:RefreshBagHighlights()
    elseif event == "BAG_UPDATE_DELAYED" then
        QuestMobs:RefreshBagHighlights()
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
        QuestMobs:RefreshThreatColors()
    end
end)

ns:RegisterCallback("PLAYER_LOGIN", function()
    InstallTooltipHook()
    InstallBagHooks()
    InstallThreatHooks()
    QuestMobs:RefreshAllNameplates()
    QuestMobs:RefreshBagHighlights()
    QuestMobs:RefreshThreatColors()
end)

ns:RegisterCallback("QUEST_LOG_UPDATE", function()
    QuestMobs:RefreshAllNameplates()
    QuestMobs:RefreshBagHighlights()
end)

ns:RegisterCallback("ZONE_CHANGED_NEW_AREA", function()
    if IsRestrictedInstance() then
        HideAllNameplateBadges()
    else
        QuestMobs:RefreshAllNameplates()
    end
end)

ns:RegisterCallback("TARGET_CHANGED", function()
    QuestMobs:RefreshAllNameplates()
end)

ns:RegisterCallback("CONFIG_CHANGED", function()
    QuestMobs:RefreshAllNameplates()
    QuestMobs:RefreshBagHighlights()
    QuestMobs:RefreshThreatColors()
end)
