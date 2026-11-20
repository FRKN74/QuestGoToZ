local _, ns = ...

local Comfort = {}
ns.Comfort = Comfort

-- =====================================================================
-- 1) Gorev Gunlugu Doluluk Uyarisi & "Birakilabilir" (Gri + Uzak) Tespiti
-- =====================================================================
local lastLogWarnCount = 0

function Comfort:GetQuestLogUsage()
    local okNum, _, numQuests = ns:TrySafeC("C_QuestLog", "GetNumQuestLogEntries")
    local count = (okNum and ns:IsSafeNumber(numQuests)) and numQuests or 0
    local okMax, maxQuests = ns:TrySafeC("C_QuestLog", "GetMaxNumQuestsCanAccept")
    local cap = (okMax and ns:IsSafeNumber(maxQuests) and maxQuests > 0) and maxQuests or 25
    return count, cap
end

function Comfort:CheckQuestLogWarning()
    local db = ns.db or ns.DEFAULTS
    local threshold = db.questLogWarnThreshold or 22
    local count, cap = self:GetQuestLogUsage()
    if count >= threshold then
        if lastLogWarnCount ~= count then
            lastLogWarnCount = count
            ns:Print(string.format(
                "|cffff9933Gorev gunlugu doluyor (%d/%d)!|r Gri ve uzak gorevler [Birakilabilir] olarak isaretlendi.",
                count, cap
            ))
        end
    else
        lastLogWarnCount = 0
    end
end

-- Gri (trivial) VE uzak (>500 m veya baska harita) gorevleri "birakilabilir" isaretler
function Comfort:IsQuestDroppable(questID, dist, isInCurrentZone, isComplete)
    if isComplete or not ns:IsSafeNumber(questID) or questID <= 0 then
        return false
    end
    local okTriv, isTrivial = ns:TrySafeC("C_QuestLog", "IsQuestTrivial", questID)
    if not (okTriv and isTrivial == true) then
        return false
    end
    if not isInCurrentZone or (dist and dist > 500) then
        return true
    end
    return false
end

-- =====================================================================
-- 2) Odul Seciminde En Yuksek Satis Degerine Altin Simgesi (Sadece Bilgi)
-- =====================================================================
local rewardGoldIcons = {}

local function GetOrCreateRewardGoldIcon(btn)
    local icon = rewardGoldIcons[btn]
    if icon then
        return icon
    end
    icon = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetSize(16, 16)
    icon:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
    icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    icon:Hide()
    rewardGoldIcons[btn] = icon
    return icon
end

function Comfort:HighlightBestSellReward()
    -- Once mevcut ikonlari gizle
    for _, ic in pairs(rewardGoldIcons) do
        ic:Hide()
    end

    local db = ns.db or ns.DEFAULTS
    if not db.showRewardHighlight then
        return
    end

    local okNum, numChoices = ns:SafeGlobal("GetNumQuestChoices")
    if not okNum or not ns:IsSafeNumber(numChoices) or numChoices <= 1 then
        return
    end

    local bestIndex = nil
    local bestPrice = 0

    for i = 1, numChoices do
        local okLink, link = ns:SafeGlobal("GetQuestItemLink", "choice", i)
        if okLink and ns:IsSafeString(link) then
            local okInfo, _, _, _, _, _, _, _, _, _, _, sellPrice = ns:TrySafeC("C_Item", "GetItemInfo", link)
            if not okInfo then
                okInfo, _, _, _, _, _, _, _, _, _, _, sellPrice = ns:SafeGlobal("GetItemInfo", link)
            end
            if okInfo and ns:IsSafeNumber(sellPrice) and sellPrice > bestPrice then
                bestPrice = sellPrice
                bestIndex = i
            end
        end
    end

    if bestIndex and bestPrice > 0 then
        local btn = _G["QuestInfoRewardsFrameQuestInfoItem" .. bestIndex]
            or _G["QuestInfoItem" .. bestIndex]
        if type(btn) == "table" and btn.CreateTexture then
            local ic = GetOrCreateRewardGoldIcon(btn)
            ic:Show()
        end
    end
end

-- =====================================================================
-- 3) Elite / Grup Gorevi Kirmizi Rozeti
-- =====================================================================
function Comfort:GetQuestDifficultyTag(questID, suggestedGroup)
    local db = ns.db or ns.DEFAULTS
    if not db.showEliteBadge or not ns:IsSafeNumber(questID) or questID <= 0 then
        return nil
    end

    local okTag, tagInfo = ns:TrySafeC("C_QuestLog", "GetQuestTagInfo", questID)
    if okTag and type(tagInfo) == "table" then
        local tid = tagInfo.tagID
        local tName = ns:IsSafeString(tagInfo.tagName) and tagInfo.tagName or nil
        if Enum and Enum.QuestTag then
            if tid == Enum.QuestTag.Group then
                return "[Grup]"
            elseif tid == Enum.QuestTag.Dungeon or tid == Enum.QuestTag.Heroic then
                return "[Zindan]"
            elseif tid == Enum.QuestTag.Raid or tid == Enum.QuestTag.Raid10 or tid == Enum.QuestTag.Raid25 then
                return "[Raid]"
            end
        end
        if tName then
            local lower = string.lower(tName)
            if lower:find("elite", 1, true) then
                return "[Elite]"
            elseif lower:find("group", 1, true) then
                return "[Grup]"
            elseif lower:find("dungeon", 1, true) then
                return "[Zindan]"
            end
        end
    end

    if ns:IsSafeNumber(suggestedGroup) and suggestedGroup > 0 then
        return string.format("[Grup %d]", suggestedGroup)
    end
    return nil
end

-- =====================================================================
-- 4) Bolge Ilerlemesi (<Bolge>: X/Y gorev tamam)
-- =====================================================================
local notifiedZoneDone = {}

function Comfort:GetZoneProgress(playerMapID, currentZoneName)
    local db = ns.db or ns.DEFAULTS
    if not db.showZoneProgress or not playerMapID then
        return nil
    end

    local done = 0
    local total = 0
    local seen = {}

    local okLines, questLines = ns:TrySafeC("C_QuestLine", "GetAvailableQuestLines", playerMapID)
    if okLines and type(questLines) == "table" then
        for i = 1, #questLines do
            local ql = questLines[i]
            if type(ql) == "table" and ns:IsSafeNumber(ql.questID) and not seen[ql.questID] then
                seen[ql.questID] = true
                total = total + 1
                local okDone, isDone = ns:TrySafeC("C_QuestLog", "IsQuestFlaggedCompleted", ql.questID)
                if okDone and isDone == true then
                    done = done + 1
                end
            end
        end
    end

    -- Gorev gunlugundeki mevcut bolge gorevlerini de dahil et
    local okNum, numEntries = ns:TrySafeC("C_QuestLog", "GetNumQuestLogEntries")
    if okNum and ns:IsSafeNumber(numEntries) then
        local curHeader = nil
        for idx = 1, numEntries do
            local okInfo, info = ns:TrySafeC("C_QuestLog", "GetInfo", idx)
            if okInfo and type(info) == "table" then
                if info.isHeader then
                    curHeader = ns:IsSafeString(info.title) and info.title or curHeader
                elseif not info.isHidden and ns:IsSafeNumber(info.questID) and not seen[info.questID] then
                    local loc = ns:GetQuestLocation(info.questID)
                    local inZone = (loc and loc.mapID == playerMapID) or (curHeader and curHeader == currentZoneName)
                    if inZone then
                        seen[info.questID] = true
                        total = total + 1
                        local okComp, isComp = ns:TrySafeC("C_QuestLog", "IsComplete", info.questID)
                        if okComp and isComp == true then
                            done = done + 1
                        end
                    end
                end
            end
        end
    end

    if total > 0 and done >= total and not notifiedZoneDone[playerMapID] then
        notifiedZoneDone[playerMapID] = true
        ns:Print(string.format("|cff33ff66%s bolgesindeki takip edilen tum gorevler tamamlandi (%d/%d)!|r", currentZoneName or "Bolge", done, total))
    elseif done < total then
        notifiedZoneDone[playerMapID] = nil
    end

    return done, total
end

-- =====================================================================
-- 5) En Yakin Hizmetler (Satici, Posta, Han, Ucus Noktasi) + %90 Canta Uyarisi
-- =====================================================================
local SERVICES_DB = {
    vendor = {
        { faction = "Alliance", mapID = 52,  name = "Quartermaster Lewis (Sentinel Hill)", x = 0.569, y = 0.472 },
        { faction = "Alliance", mapID = 37,  name = "Brog Hamfist (Goldshire)",            x = 0.440, y = 0.659 },
        { faction = "Alliance", mapID = 84,  name = "Thurman Mullby (Stormwind)",          x = 0.583, y = 0.616 },
        { faction = "Alliance", mapID = 27,  name = "Frast Dokner (Kharanos)",             x = 0.468, y = 0.524 },
        { faction = "Alliance", mapID = 87,  name = "Outfitter Eric (Ironforge)",          x = 0.432, y = 0.292 },
        { faction = "Alliance", mapID = 49,  name = "Kara Adams (Lakeshire)",              x = 0.295, y = 0.462 },
        { faction = "Alliance", mapID = 47,  name = "Morg Gnarltree (Darkshire)",          x = 0.739, y = 0.486 },
        { faction = "Alliance", mapID = 57,  name = "Shalomon (Dolanaar)",                 x = 0.560, y = 0.522 },
        { faction = "Alliance", mapID = 89,  name = "Mydrannul (Darnassus)",               x = 0.706, y = 0.453 },
        { faction = "Horde",    mapID = 1,   name = "Trayexyr (Razor Hill)",               x = 0.526, y = 0.415 },
        { faction = "Horde",    mapID = 85,  name = "Trak'gen (Orgrimmar)",                x = 0.484, y = 0.752 },
        { faction = "Horde",    mapID = 10,  name = "Tari'qa (Crossroads)",                x = 0.517, y = 0.301 },
        { faction = "Horde",    mapID = 7,   name = "Moorat Longstride (Bloodhoof)",       x = 0.465, y = 0.606 },
        { faction = "Horde",    mapID = 88,  name = "Kurm Stonehoof (Thunder Bluff)",      x = 0.454, y = 0.586 },
        { faction = "Horde",    mapID = 18,  name = "Abigail Shiel (Brill)",               x = 0.610, y = 0.524 },
        { faction = "Horde",    mapID = 90,  name = "Ronald Burch (Undercity)",            x = 0.624, y = 0.434 },
        { faction = "Horde",    mapID = 110, name = "Sathren Highdawn (Silvermoon)",       x = 0.542, y = 0.710 },
    },
    mailbox = {
        { faction = "Alliance", mapID = 52,  name = "Posta Kutusu (Sentinel Hill)",        x = 0.529, y = 0.533 },
        { faction = "Alliance", mapID = 37,  name = "Posta Kutusu (Goldshire)",            x = 0.436, y = 0.658 },
        { faction = "Alliance", mapID = 84,  name = "Posta Kutusu (Stormwind Trade)",      x = 0.618, y = 0.728 },
        { faction = "Alliance", mapID = 27,  name = "Posta Kutusu (Kharanos)",             x = 0.473, y = 0.525 },
        { faction = "Alliance", mapID = 87,  name = "Posta Kutusu (Ironforge)",            x = 0.332, y = 0.650 },
        { faction = "Alliance", mapID = 49,  name = "Posta Kutusu (Lakeshire)",            x = 0.267, y = 0.449 },
        { faction = "Alliance", mapID = 47,  name = "Posta Kutusu (Darkshire)",            x = 0.740, y = 0.453 },
        { faction = "Alliance", mapID = 57,  name = "Posta Kutusu (Dolanaar)",             x = 0.556, y = 0.595 },
        { faction = "Alliance", mapID = 89,  name = "Posta Kutusu (Darnassus)",            x = 0.674, y = 0.160 },
        { faction = "Horde",    mapID = 1,   name = "Posta Kutusu (Razor Hill)",           x = 0.516, y = 0.415 },
        { faction = "Horde",    mapID = 85,  name = "Posta Kutusu (Orgrimmar)",            x = 0.506, y = 0.706 },
        { faction = "Horde",    mapID = 10,  name = "Posta Kutusu (Crossroads)",           x = 0.518, y = 0.299 },
        { faction = "Horde",    mapID = 7,   name = "Posta Kutusu (Bloodhoof)",            x = 0.467, y = 0.608 },
        { faction = "Horde",    mapID = 88,  name = "Posta Kutusu (Thunder Bluff)",        x = 0.455, y = 0.588 },
        { faction = "Horde",    mapID = 18,  name = "Posta Kutusu (Brill)",                x = 0.614, y = 0.520 },
        { faction = "Horde",    mapID = 90,  name = "Posta Kutusu (Undercity)",            x = 0.677, y = 0.382 },
        { faction = "Horde",    mapID = 110, name = "Posta Kutusu (Silvermoon)",           x = 0.794, y = 0.576 },
    },
    innkeeper = {
        { faction = "Alliance", mapID = 52,  name = "Innkeeper Heather (Sentinel Hill)",   x = 0.529, y = 0.536 },
        { faction = "Alliance", mapID = 37,  name = "Innkeeper Farley (Goldshire)",        x = 0.438, y = 0.658 },
        { faction = "Alliance", mapID = 84,  name = "Innkeeper Allison (Stormwind)",       x = 0.604, y = 0.752 },
        { faction = "Alliance", mapID = 27,  name = "Innkeeper Belm (Kharanos)",           x = 0.474, y = 0.525 },
        { faction = "Alliance", mapID = 87,  name = "Innkeeper Firebrew (Ironforge)",      x = 0.186, y = 0.514 },
        { faction = "Alliance", mapID = 49,  name = "Innkeeper Brianna (Lakeshire)",       x = 0.264, y = 0.415 },
        { faction = "Alliance", mapID = 47,  name = "Innkeeper Trelayne (Darkshire)",      x = 0.738, y = 0.444 },
        { faction = "Alliance", mapID = 57,  name = "Innkeeper Keldamyr (Dolanaar)",       x = 0.556, y = 0.598 },
        { faction = "Alliance", mapID = 89,  name = "Innkeeper Saelienne (Darnassus)",     x = 0.674, y = 0.156 },
        { faction = "Horde",    mapID = 1,   name = "Innkeeper Grosk (Razor Hill)",        x = 0.515, y = 0.416 },
        { faction = "Horde",    mapID = 85,  name = "Innkeeper Gryshka (Orgrimmar)",       x = 0.535, y = 0.786 },
        { faction = "Horde",    mapID = 10,  name = "Innkeeper Boorand (Crossroads)",      x = 0.520, y = 0.299 },
        { faction = "Horde",    mapID = 7,   name = "Innkeeper Kauth (Bloodhoof)",         x = 0.466, y = 0.610 },
        { faction = "Horde",    mapID = 88,  name = "Innkeeper Pala (Thunder Bluff)",      x = 0.458, y = 0.646 },
        { faction = "Horde",    mapID = 18,  name = "Innkeeper Renee (Brill)",             x = 0.617, y = 0.520 },
        { faction = "Horde",    mapID = 90,  name = "Innkeeper Norman (Undercity)",        x = 0.676, y = 0.382 },
        { faction = "Horde",    mapID = 110, name = "Innkeeper Velandra (Silvermoon)",     x = 0.795, y = 0.577 },
    },
    flight = {
        { faction = "Alliance", mapID = 52,  name = "Thor (Sentinel Hill Ucus)",           x = 0.565, y = 0.526 },
        { faction = "Alliance", mapID = 84,  name = "Dungar Longdrink (Stormwind Ucus)",   x = 0.709, y = 0.725 },
        { faction = "Alliance", mapID = 87,  name = "Gryth Thurden (Ironforge Ucus)",      x = 0.556, y = 0.478 },
        { faction = "Alliance", mapID = 49,  name = "Ariena Stormfeather (Lakeshire Ucus)", x = 0.306, y = 0.594 },
        { faction = "Alliance", mapID = 47,  name = "Felicia Maline (Darkshire Ucus)",     x = 0.775, y = 0.443 },
        { faction = "Alliance", mapID = 89,  name = "Vesprystus (Rut'theran Ucus)",        x = 0.554, y = 0.884 },
        { faction = "Horde",    mapID = 85,  name = "Doras (Orgrimmar Ucus)",              x = 0.494, y = 0.592 },
        { faction = "Horde",    mapID = 10,  name = "Devrak (Crossroads Ucus)",            x = 0.515, y = 0.303 },
        { faction = "Horde",    mapID = 88,  name = "Tal (Thunder Bluff Ucus)",            x = 0.470, y = 0.498 },
        { faction = "Horde",    mapID = 90,  name = "Michael Garrett (Undercity Ucus)",    x = 0.633, y = 0.485 },
        { faction = "Horde",    mapID = 110, name = "Skymaster Brightdawn (Silvermoon)",   x = 0.544, y = 0.508 },
    },
}

local SERVICE_LABELS = {
    vendor    = "Satici",
    mailbox   = "Posta",
    innkeeper = "Han",
    flight    = "Ucus",
}

local function FindNearestInList(list, playerMapID, px, py, mapWidth, mapHeight, playerFaction, pCont, pWorld)
    local best = nil
    local bestDist = math.huge
    local fallback = nil

    for i = 1, #list do
        local item = list[i]
        if item.faction == "Neutral" or not playerFaction or item.faction == playerFaction then
            if not fallback then
                fallback = item
            end
            local dist = nil
            if playerMapID and mapWidth and item.mapID == playerMapID then
                dist = ns:ComputeDistanceAndAngle(px, py, item.x, item.y, mapWidth, mapHeight)
            elseif pCont and pWorld and type(_G.CreateVector2D) == "function" then
                local okT, tCont, tWorld = ns:TrySafeC("C_Map", "GetWorldPosFromMapPos", item.mapID, _G.CreateVector2D(item.x, item.y))
                if okT and tCont and tCont == pCont and tWorld then
                    local dx = (tWorld.x or 0) - (pWorld.x or 0)
                    local dy = (tWorld.y or 0) - (pWorld.y or 0)
                    dist = math.sqrt(dx * dx + dy * dy) * 0.9144
                end
            end
            if dist and dist < bestDist then
                bestDist = dist
                best = item
            end
        end
    end

    local chosen = best or fallback
    if not chosen then
        return nil
    end
    return chosen, (best and bestDist < math.huge) and bestDist or nil
end

function Comfort:GetNearestServices(playerMapID, px, py, mapWidth, mapHeight)
    local db = ns.db or ns.DEFAULTS
    if not db.showNearestServices then
        return {}
    end

    local okFac, playerFaction = ns:SafeGlobal("UnitFactionGroup", "player")
    playerFaction = (okFac and ns:IsSafeString(playerFaction)) and playerFaction or nil

    local pCont, pWorld = nil, nil
    if playerMapID and ns:IsSafeNumber(px) and ns:IsSafeNumber(py) and type(_G.CreateVector2D) == "function" then
        local okP, cont, wPos = ns:TrySafeC("C_Map", "GetWorldPosFromMapPos", playerMapID, _G.CreateVector2D(px, py))
        if okP and cont and wPos then
            pCont, pWorld = cont, wPos
        end
    end

    local order = { "vendor", "mailbox", "innkeeper", "flight" }
    local result = {}
    for idx = 1, #order do
        local key = order[idx]
        local chosen, dist = FindNearestInList(SERVICES_DB[key], playerMapID, px, py, mapWidth, mapHeight, playerFaction, pCont, pWorld)
        if chosen then
            local zoneName = ns:GetMapName(chosen.mapID) or "Harita"
            table.insert(result, {
                questID = -(800000 + idx * 1000 + chosen.mapID),
                title = "[" .. SERVICE_LABELS[key] .. "] " .. chosen.name,
                groupType = "service",
                serviceKey = key,
                isComplete = false,
                isAvailable = false,
                isTrainer = true, -- Waypoint temizlenmeden hedefe yonlendirilsin
                mapID = chosen.mapID,
                x = chosen.x,
                y = chosen.y,
                dist = dist,
                hasLocation = true,
                isNearby = false,
                zoneName = zoneName,
                isInCurrentZone = (playerMapID == chosen.mapID),
            })
        end
    end
    return result
end

-- Canta %90 dolunca en yakin saticiyi oner
local bagAlertSent = false

function Comfort:CheckBagFullVendorAlert()
    local db = ns.db or ns.DEFAULTS
    if not db.bagFullVendorAlert then
        bagAlertSent = false
        return
    end

    local totalSlots = 0
    local freeSlots = 0
    for bag = 0, 4 do
        local okNum, numS = ns:TrySafeC("C_Container", "GetContainerNumSlots", bag)
        local okFree, freeS = ns:TrySafeC("C_Container", "GetContainerNumFreeSlots", bag)
        if okNum and ns:IsSafeNumber(numS) and numS > 0 then
            totalSlots = totalSlots + numS
            freeSlots = freeSlots + ((okFree and ns:IsSafeNumber(freeS)) and freeS or 0)
        end
    end

    if totalSlots <= 0 then
        return
    end

    local usedRatio = (totalSlots - freeSlots) / totalSlots
    if usedRatio >= 0.90 then
        if not bagAlertSent then
            bagAlertSent = true
            local playerMapID, px, py, mapWidth, mapHeight = ns:GetPlayerPosition()
            local services = self:GetNearestServices(playerMapID, px, py, mapWidth, mapHeight)
            local vendor = services[1]
            if vendor then
                local distStr = vendor.dist and string.format(" (%d m)", math.floor(vendor.dist + 0.5)) or ""
                ns:Print(string.format("|cffffaa22Cantan %%90+ doldu (%d bos yer)!|r En yakin satici: |cffffff00%s|r%s", freeSlots, vendor.title, distStr))
            else
                ns:Print(string.format("|cffffaa22Cantan %%90+ doldu (%d bos yer)!|r", freeSlots))
            end
        end
    else
        bagAlertSent = false
    end
end

-- =====================================================================
-- 6) Gorev Esyasi Kullan Butonu (SecureActionButtonTemplate - Sadece OOC Ayar)
-- =====================================================================
local questItemBtn = nil

local function SaveQuestItemPos(frame)
    if not ns.db or not frame then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then
        ns.db.questItemPos = {
            point = point,
            relativePoint = relativePoint or point,
            x = math.floor((x or 0) + 0.5),
            y = math.floor((y or 0) + 0.5),
        }
    end
end

function Comfort:ApplyQuestItemPosition()
    if not questItemBtn or ns:IsInCombat() then
        return
    end
    local pos = (ns.db and ns.db.questItemPos) or ns.DEFAULTS.questItemPos
    questItemBtn:ClearAllPoints()
    questItemBtn:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
end

local function CreateQuestItemButton()
    if questItemBtn then
        return questItemBtn
    end

    local btn = CreateFrame("Button", "QuestGoToZQuestItemBtn", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
    btn:SetSize(48, 48)
    btn:SetFrameStrata("MEDIUM")
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("RightButton")
    btn:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0.05, 0.08, 0.12, 0.75)
    btn:SetBackdropBorderColor(1.0, 0.65, 0.15, 0.90)

    btn:SetScript("OnDragStart", function(selfBtn)
        if ns:IsInCombat() or (ns.db and ns.db.locked) then
            return
        end
        selfBtn:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(selfBtn)
        selfBtn:StopMovingOrSizing()
        SaveQuestItemPos(selfBtn)
    end)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    label:SetTextColor(1.0, 0.85, 0.25)
    btn.label = label

    btn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip or not selfBtn.itemID then
            return
        end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        pcall(GameTooltip.SetItemByID, GameTooltip, selfBtn.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Sol tik: Kullan | Sag tik + surukle: Tasi", 0.7, 0.8, 0.9)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    questItemBtn = btn
    Comfort:ApplyQuestItemPosition()
    btn:Hide()
    return btn
end

-- Kullanilabilir aktif gorev esyasini bulur (once aktif gorevin, yoksa gunlukteki ilk esya)
local function FindUsableQuestItem()
    local okNum, numEntries = ns:TrySafeC("C_QuestLog", "GetNumQuestLogEntries")
    if not okNum or not ns:IsSafeNumber(numEntries) then
        return nil
    end

    local fallback = nil
    for idx = 1, numEntries do
        local okInfo, info = ns:TrySafeC("C_QuestLog", "GetInfo", idx)
        if okInfo and type(info) == "table" and not info.isHeader and not info.isHidden and ns:IsSafeNumber(info.questID) then
            local okSpec, link, icon = ns:SafeGlobal("GetQuestLogSpecialItemInfo", idx)
            if okSpec and ns:IsSafeString(link) then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID then
                    local entry = {
                        itemID = itemID,
                        icon = icon,
                        title = info.title or "Gorev Esyasi",
                        questID = info.questID,
                    }
                    if ns.activeQuestID and info.questID == ns.activeQuestID then
                        return entry
                    end
                    if not fallback then
                        fallback = entry
                    end
                end
            end
        end
    end
    return fallback
end

function Comfort:RefreshQuestItemButton()
    if not questItemBtn then
        return
    end
    -- SecureActionButton ayarlari ASLA savasta degistirilmez
    ns:RunOutOfCombat("refresh_quest_item_btn", function()
        local db = ns.db or ns.DEFAULTS
        if not db.showQuestItemButton then
            questItemBtn:Hide()
            return
        end

        local item = FindUsableQuestItem()
        if item then
            questItemBtn.itemID = item.itemID
            questItemBtn.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            questItemBtn.label:SetText("Gorev Esyasi")
            questItemBtn:SetAttribute("type", "item")
            questItemBtn:SetAttribute("item", "item:" .. tostring(item.itemID))
            questItemBtn:Show()
        else
            questItemBtn.itemID = nil
            questItemBtn:Hide()
        end
    end)
end

-- Event baglantilari
ns:RegisterCallback("PLAYER_LOGIN", function()
    CreateQuestItemButton()
    Comfort:RefreshQuestItemButton()
    Comfort:CheckQuestLogWarning()
    Comfort:CheckBagFullVendorAlert()

    if type(_G.QuestInfo_Display) == "function" then
        hooksecurefunc("QuestInfo_Display", function()
            Comfort:HighlightBestSellReward()
        end)
    end
end)

ns:RegisterCallback("QUEST_COMPLETE", function()
    Comfort:HighlightBestSellReward()
end)

ns:RegisterCallback("QUEST_LOG_UPDATE", function()
    Comfort:CheckQuestLogWarning()
    Comfort:RefreshQuestItemButton()
end)

ns:RegisterCallback("TARGET_CHANGED", function()
    Comfort:RefreshQuestItemButton()
end)

ns:RegisterCallback("BAG_UPDATE_DELAYED", function()
    Comfort:CheckBagFullVendorAlert()
    Comfort:RefreshQuestItemButton()
end)

ns:RegisterCallback("CONFIG_CHANGED", function()
    Comfort:RefreshQuestItemButton()
    Comfort:CheckBagFullVendorAlert()
end)
