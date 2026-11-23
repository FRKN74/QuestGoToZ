local _, ns = ...

local SmartQuest = {}
ns.SmartQuest = SmartQuest

-- =====================================================================
-- OZELLIK 1: Birlikte Yapilabilecek Gorevler (Quest Clusters)
-- =====================================================================
function SmartQuest:CollectCurrentMapQuests(playerMapID, px, py, mapWidth, mapHeight)
    if not playerMapID or not mapWidth then
        return {}
    end

    local byID = {}
    local list = {}

    local function AddQuest(questID, x, y)
        if not ns:IsSafeNumber(questID) or byID[questID] then
            return
        end
        if not ns:IsSafeNumber(x) or not ns:IsSafeNumber(y) or (x <= 0 and y <= 0) then
            return
        end

        local okOn, isOn = ns:TrySafeC("C_QuestLog", "IsOnQuest", questID)
        if okOn and not isOn then
            return
        end

        local dist = ns:ComputeDistanceAndAngle(px, py, x, y, mapWidth, mapHeight)
        if not dist then
            return
        end

        local okTitle, title = ns:TrySafeC("C_QuestLog", "GetTitleForQuestID", questID)
        if not okTitle or not ns:IsSafeString(title) or title == "" then
            title = "Gorev #" .. tostring(questID)
        end

        local okComp, isComp = ns:TrySafeC("C_QuestLog", "IsComplete", questID)
        local isComplete = (okComp and isComp == true) or false

        local entry = {
            questID = questID,
            title = title,
            mapID = playerMapID,
            x = x,
            y = y,
            dist = dist,
            isComplete = isComplete,
        }
        byID[questID] = entry
        table.insert(list, entry)
    end

    -- 1) Haritadaki gorev POI merkezleri
    local okOnMap, questsOnMap = ns:SafeC("C_QuestLog", "GetQuestsOnMap", playerMapID)
    if okOnMap and type(questsOnMap) == "table" then
        for i = 1, #questsOnMap do
            local info = questsOnMap[i]
            if type(info) == "table" then
                AddQuest(info.questID, info.x, info.y)
            end
        end
    end

    -- 2) Gunlukteki diger ayni harita gorevleri (GetNextWaypoint)
    local okNum, numEntries = ns:TrySafeC("C_QuestLog", "GetNumQuestLogEntries")
    if okNum and ns:IsSafeNumber(numEntries) then
        for idx = 1, numEntries do
            local okInfo, info = ns:TrySafeC("C_QuestLog", "GetInfo", idx)
            if okInfo and type(info) == "table" and not info.isHeader and not info.isHidden
                and ns:IsSafeNumber(info.questID) and not byID[info.questID] then
                local okNext, qMapID, qx, qy = ns:TrySafeC("C_QuestLog", "GetNextWaypoint", info.questID)
                if okNext and qMapID == playerMapID then
                    AddQuest(info.questID, qx, qy)
                end
            end
        end
    end

    return list
end

-- Birbirine clusterRadius (varsayilan 100 m) icinde olan gorevleri gruplar
function SmartQuest:ComputeClusters(quests, mapWidth, mapHeight)
    local db = ns.db or ns.DEFAULTS
    local threshold = db.clusterRadius or 100
    local n = #quests
    local visited = {}
    local clusters = {}
    local questClusterSize = {}

    for i = 1, n do
        if not visited[i] then
            local queue = { i }
            visited[i] = true
            local members = {}
            local head = 1

            while head <= #queue do
                local curIdx = queue[head]
                head = head + 1
                local a = quests[curIdx]
                table.insert(members, a)

                for j = 1, n do
                    if not visited[j] then
                        local b = quests[j]
                        local d = ns:ComputeDistanceAndAngle(a.x, a.y, b.x, b.y, mapWidth, mapHeight)
                        if d and d <= threshold then
                            visited[j] = true
                            table.insert(queue, j)
                        end
                    end
                end
            end

            for m = 1, #members do
                questClusterSize[members[m].questID] = #members
            end

            if #members >= 2 then
                table.sort(members, function(x, y)
                    return x.dist < y.dist
                end)
                table.insert(clusters, {
                    count = #members,
                    minDist = members[1].dist,
                    anchor = members[1],
                    members = members,
                })
            end
        end
    end

    table.sort(clusters, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.minDist < b.minDist
    end)

    return clusters, questClusterSize
end

function SmartQuest:GetCurrentMapClusters()
    local playerMapID, px, py, mapWidth, mapHeight = ns:GetPlayerPosition()
    if not playerMapID or not mapWidth then
        return {}, {}
    end
    local quests = self:CollectCurrentMapQuests(playerMapID, px, py, mapWidth, mapHeight)
    return self:ComputeClusters(quests, mapWidth, mapHeight)
end

-- =====================================================================
-- OZELLIK 2: Siradaki En Iyi Gorev (Puanlama Motoru)
-- =====================================================================
local function GetQuestCompletionRatio(questID, isComplete)
    if isComplete then
        return 1.0
    end
    local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", questID)
    if not okObj or type(objectives) ~= "table" or #objectives == 0 then
        return 0.0
    end
    local sum = 0
    local count = 0
    for i = 1, #objectives do
        local obj = objectives[i]
        if type(obj) == "table" then
            count = count + 1
            if obj.finished then
                sum = sum + 1
            elseif ns:IsSafeNumber(obj.numFulfilled) and ns:IsSafeNumber(obj.numRequired) and obj.numRequired > 0 then
                sum = sum + math.min(1, obj.numFulfilled / obj.numRequired)
            end
        end
    end
    return (count > 0) and (sum / count) or 0.0
end

local lastRequestedMapForAvailable = nil

-- Mevcut haritadaki alinmamis levelling gorevlerini 4 resmi API kaynagindan toplar
function SmartQuest:CollectAvailableLevelingQuests(playerMapID, px, py, mapWidth, mapHeight)
    if not playerMapID or not mapWidth then
        return {}
    end

    if lastRequestedMapForAvailable ~= playerMapID then
        lastRequestedMapForAvailable = playerMapID
        ns:TrySafeC("C_QuestLine", "RequestQuestLinesForMap", playerMapID)
    end

    local byID = {}
    local list = {}

    local function TryAddAvailable(questID, x, y, explicitTitle, forceMain)
        if not ns:IsSafeNumber(questID) or questID <= 0 or byID[questID] then
            return
        end
        if not ns:IsSafeNumber(x) or not ns:IsSafeNumber(y) or (x <= 0 and y <= 0) then
            local okFor, fx, fy = ns:TrySafeC("C_QuestLog", "GetNextWaypointForMap", questID, playerMapID)
            if okFor and ns:IsSafeNumber(fx) and ns:IsSafeNumber(fy) and (fx > 0 or fy > 0) then
                x, y = fx, fy
            else
                return
            end
        end

        local okDone, isDone = ns:TrySafeC("C_QuestLog", "IsQuestFlaggedCompleted", questID)
        if okDone and isDone == true then
            return
        end
        local okOn, isOn = ns:TrySafeC("C_QuestLog", "IsOnQuest", questID)
        if okOn and isOn == true then
            return
        end

        local dist = ns:ComputeDistanceAndAngle(px, py, x, y, mapWidth, mapHeight)
        if not dist then
            return
        end

        local okTriv, isTriv = ns:TrySafeC("C_QuestLog", "IsQuestTrivial", questID)
        local isTrivial = (okTriv and isTriv == true) or false

        local title = explicitTitle
        if not ns:IsSafeString(title) or title == "" then
            local okT, fetched = ns:TrySafeC("C_QuestLog", "GetTitleForQuestID", questID)
            title = (okT and ns:IsSafeString(fetched) and fetched ~= "") and fetched or ("Gorev #" .. tostring(questID))
        end

        local isMain = forceMain or ns:IsMainQuest(questID, nil, playerMapID)
        byID[questID] = true
        table.insert(list, {
            questID = questID,
            title = title,
            mapID = playerMapID,
            x = x,
            y = y,
            dist = dist,
            isComplete = false,
            isAvailable = true,
            isMain = isMain,
            isTrivial = isTrivial,
        })
    end

    -- 1) C_QuestLine.GetAvailableQuestLines (alinabilir gorev veren NPC'ler)
    local okLines, questLines = ns:TrySafeC("C_QuestLine", "GetAvailableQuestLines", playerMapID)
    if okLines and type(questLines) == "table" then
        for i = 1, #questLines do
            local ql = questLines[i]
            if type(ql) == "table" and ns:IsSafeNumber(ql.questID) then
                local isM = (ql.isCampaign == true or ql.isImportant == true)
                TryAddAvailable(ql.questID, ql.x, ql.y, ql.questName, isM)
            end
        end
    end

    -- 2) C_QuestLine.GetForceVisibleQuestsForMap (varsa zorunlu gorunen gorevler)
    local okForce, forceList = ns:TrySafeC("C_QuestLine", "GetForceVisibleQuestsForMap", playerMapID)
    if okForce and type(forceList) == "table" then
        for i = 1, #forceList do
            local qid = forceList[i]
            if ns:IsSafeNumber(qid) then
                local okQL, qlInfo = ns:TrySafeC("C_QuestLine", "GetQuestLineInfo", qid, playerMapID)
                if okQL and type(qlInfo) == "table" then
                    TryAddAvailable(qid, qlInfo.x, qlInfo.y, qlInfo.questName, qlInfo.isCampaign == true)
                else
                    TryAddAvailable(qid, nil, nil, nil, false)
                end
            end
        end
    end

    -- 3) C_QuestLog.GetQuestsOnMap (haritadaki henuz alinmamis POI'ler)
    local okOnMap, questsOnMap = ns:TrySafeC("C_QuestLog", "GetQuestsOnMap", playerMapID)
    if okOnMap and type(questsOnMap) == "table" then
        for i = 1, #questsOnMap do
            local info = questsOnMap[i]
            if type(info) == "table" and ns:IsSafeNumber(info.questID) then
                TryAddAvailable(info.questID, info.x, info.y, nil, false)
            end
        end
    end

    -- 4) C_TaskQuest.GetQuestsForPlayerByMapID (bolge/bonus/dunya gorevleri)
    local okTasks, tasks = ns:TrySafeC("C_TaskQuest", "GetQuestsForPlayerByMapID", playerMapID)
    if okTasks and type(tasks) == "table" then
        for i = 1, #tasks do
            local t = tasks[i]
            if type(t) == "table" then
                local qid = t.questID or t.questId
                if ns:IsSafeNumber(qid) then
                    local okTTitle, tTitle = ns:TrySafeC("C_TaskQuest", "GetQuestInfoByQuestID", qid)
                    TryAddAvailable(qid, t.x, t.y, (okTTitle and ns:IsSafeString(tTitle)) and tTitle or nil, false)
                end
            end
        end
    end

    return list
end

-- Levelling Modu: Alinmamis uygun gorevler + mevcut gorevleri tek listede puanlar
function SmartQuest:EvaluateAllCandidates(excludeQuestID)
    local playerMapID, px, py, mapWidth, mapHeight = ns:GetPlayerPosition()
    if not playerMapID or not mapWidth then
        return {}
    end

    local db = ns.db or ns.DEFAULTS
    local quests = self:CollectCurrentMapQuests(playerMapID, px, py, mapWidth, mapHeight)

    -- Mevcut gorevlerin isMain bilgisini ekle
    for i = 1, #quests do
        quests[i].isMain = ns:IsMainQuest(quests[i].questID, nil, playerMapID)
        quests[i].isAvailable = false
    end

    -- Levelling modu aciksa alinmamis (gri olmayan) gorevleri de adaylara ekle
    if db.levelingMode then
        local avail = self:CollectAvailableLevelingQuests(playerMapID, px, py, mapWidth, mapHeight)
        for i = 1, #avail do
            table.insert(quests, avail[i])
        end
    end

    if #quests == 0 then
        return {}
    end

    local _, clusterSizeMap = self:ComputeClusters(quests, mapWidth, mapHeight)
    local w = db.weights or ns.DEFAULTS.weights
    local wDist = w.distance or 40
    local wClust = w.cluster or 25
    local wXP = w.xp or 20
    local wComp = w.completion or 35

    -- XP normalizasyonu icin mevcut haritadaki maks XP
    local maxXP = 1
    local xpMap = {}
    for i = 1, #quests do
        local qid = quests[i].questID
        local okXP, xpVal = ns:SafeGlobal("GetQuestLogRewardXP", qid)
        local xpNum = (okXP and ns:IsSafeNumber(xpVal) and xpVal > 0) and xpVal or 0
        xpMap[qid] = xpNum
        if xpNum > maxXP then
            maxXP = xpNum
        end
    end

    local scored = {}
    for i = 1, #quests do
        local q = quests[i]
        if q.questID ~= excludeQuestID then
            local distScore = wDist * (1 / (1 + (q.dist / 200)))
            local cSize = clusterSizeMap[q.questID] or 1
            local clusterScore = wClust * math.min(1, (cSize - 1) / 3)
            local xpVal = xpMap[q.questID] or 0
            local xpRatio = (xpVal > 0) and (xpVal / maxXP) or (q.isAvailable and 0.65 or 0)
            local xpScore = wXP * xpRatio
            local compRatio = q.isAvailable and 0.0 or GetQuestCompletionRatio(q.questID, q.isComplete)
            local compScore = wComp * compRatio

            -- Levelling bonuslari: Ana gorevler ve yakindaki alinmamis gorev NPC'leri one cikar;
            -- gri (trivial) gorevler gizlenmez ama en alta iner
            local bonus = 0
            if q.isMain then
                bonus = bonus + 22
            end
            if q.isAvailable and q.dist <= 300 then
                bonus = bonus + 18 -- Yakininda almadigin gorev varsa once al, birlikte yap
            end
            if q.isTrivial then
                bonus = bonus - 25
            end

            local totalScore = distScore + clusterScore + xpScore + compScore + bonus

            local reasons = {}
            if q.isAvailable then
                table.insert(reasons, "Gorevi al")
            elseif q.isComplete then
                table.insert(reasons, "Teslime hazir")
            end
            table.insert(reasons, string.format("%d m", math.floor(q.dist + 0.5)))
            if q.isMain then
                table.insert(reasons, "Ana gorev")
            end
            if cSize >= 2 then
                table.insert(reasons, string.format("%d gorev birlikte", cSize))
            end
            if not q.isAvailable and not q.isComplete and compRatio >= 0.5 then
                table.insert(reasons, string.format("%%%d tamam", math.floor(compRatio * 100 + 0.5)))
            end
            if xpVal > 0 and xpRatio >= 0.65 then
                table.insert(reasons, "Yuksek XP")
            end

            table.insert(scored, {
                questID = q.questID,
                title = q.title,
                mapID = q.mapID,
                x = q.x,
                y = q.y,
                dist = q.dist,
                clusterSize = cSize,
                xp = xpVal,
                completionRatio = compRatio,
                isComplete = q.isComplete,
                isAvailable = q.isAvailable,
                isMain = q.isMain,
                score = totalScore,
                reason = table.concat(reasons, " + "),
            })
        end
    end

    table.sort(scored, function(a, b)
        return a.score > b.score
    end)

    return scored
end

function SmartQuest:EvaluateBestQuest(excludeQuestID)
    local scored = self:EvaluateAllCandidates(excludeQuestID)
    return scored[1]
end

function SmartQuest:SelectBestQuest(excludeQuestID, silent)
    local best = self:EvaluateBestQuest(excludeQuestID)
    if not best then
        if not silent then
            ns:Print("Bu haritada puanlanabilecek gorev bulunamadi.")
        end
        return false, nil
    end

    local ok
    if best.isAvailable then
        ok = ns:SetQuestWaypointWithLoc({
            questID = best.questID,
            mapID = best.mapID,
            x = best.x,
            y = best.y,
            title = best.title,
            zoneName = ns:GetMapName(best.mapID),
            isComplete = false,
            isAvailable = true,
        }, true)
    else
        ok = ns:SetQuestWaypoint(best.questID, true)
    end

    if ok and not silent then
        local tag = best.isAvailable and "|cff33ccff[AL!]|r " or (best.isComplete and "|cff33ff66[Teslim]|r " or "")
        ns:Print(string.format(
            "Levelling siradaki: %s|cffffff00%s|r |cff88ddff(%s)|r",
            tag,
            best.title,
            best.reason
        ))
    end
    return ok, best
end

-- =====================================================================
-- OZELLIK 4: Ceset Yonu (C_DeathInfo.GetCorpseMapPosition)
-- =====================================================================
local function TrySetCorpseWaypoint()
    local db = ns.db or ns.DEFAULTS
    if not db.corpseWaypoint then
        return
    end

    local okDead, isDeadOrGhost = ns:SafeGlobal("UnitIsDeadOrGhost", "player")
    if not (okDead and isDeadOrGhost) then
        return
    end

    local okMap, mapID = ns:SafeC("C_Map", "GetBestMapForUnit", "player")
    if not okMap or not ns:IsSafeNumber(mapID) then
        return
    end

    local okPos, pos = ns:TrySafeC("C_DeathInfo", "GetCorpseMapPosition", mapID)
    if not okPos or not pos then
        return
    end

    local cx, cy
    if type(pos.GetXY) == "function" then
        local okXY, x, y = pcall(pos.GetXY, pos)
        if okXY then
            cx, cy = x, y
        end
    else
        cx, cy = pos.x, pos.y
    end

    if not ns:IsSafeNumber(cx) or not ns:IsSafeNumber(cy) or (cx <= 0 and cy <= 0) then
        return
    end

    local zoneName = ns:GetMapName(mapID) or "Harita"
    ns:SetQuestWaypointWithLoc({
        questID = -999999,
        mapID = mapID,
        x = cx,
        y = cy,
        title = "Ceset Konumu",
        zoneName = zoneName,
        isComplete = false,
        isAvailable = false,
        isCorpse = true,
    }, true)
    ns:Print(string.format("Ceset yonune waypoint koyuldu: |cff88ccff%s (%.1f, %.1f)|r", zoneName, cx * 100, cy * 100))
end

local function ClearCorpseWaypointIfActive()
    if ns.activeTarget and ns.activeTarget.isCorpse then
        ns:ClearQuestWaypoint(true)
        ns:Print("Hayata donuldu; ceset waypoint'i temizlendi.")
    end
end

ns:RegisterCallback("PLAYER_DEAD", function()
    -- Ceset konumu bazi durumlarda 0.5 sn sonra hazir olur
    ns:TrySafeC("C_Timer", "After", 0.5, function()
        TrySetCorpseWaypoint()
    end)
end)

ns:RegisterCallback("PLAYER_UNGHOST", function()
    ClearCorpseWaypointIfActive()
end)

ns:RegisterCallback("PLAYER_ALIVE", function()
    local okDead, isDeadOrGhost = ns:SafeGlobal("UnitIsDeadOrGhost", "player")
    if okDead and not isDeadOrGhost then
        ClearCorpseWaypointIfActive()
    end
end)

ns:RegisterCallback("PLAYER_LOGIN", function()
    ns:TrySafeC("C_Timer", "After", 1.0, function()
        TrySetCorpseWaypoint()
    end)
    SmartQuest:InitBanner()
end)

-- =====================================================================
-- AAP / APR Tarzi Ust-Orta Modern Transparan Aktif Gorev Karti (< Geri / > Ileri)
-- =====================================================================
local bannerFrame = nil
local bannerTicker = nil
local targetHistory = {} -- Geri donulebilecek onceki hedefler (max 15)

local function PushHistory(loc)
    if type(loc) ~= "table" or not ns:IsSafeNumber(loc.questID) then
        return
    end
    local last = targetHistory[#targetHistory]
    if last and last.questID == loc.questID then
        return
    end
    table.insert(targetHistory, {
        questID = loc.questID,
        mapID = loc.mapID,
        x = loc.x,
        y = loc.y,
        title = loc.title,
        zoneName = loc.zoneName,
        isComplete = loc.isComplete,
        isAvailable = loc.isAvailable,
        isTrainer = loc.isTrainer,
        isCorpse = loc.isCorpse,
    })
    if #targetHistory > 15 then
        table.remove(targetHistory, 1)
    end
end

function SmartQuest:StepNextQuest()
    local scored = self:EvaluateAllCandidates(nil)
    if #scored == 0 then
        ns:Print("Bu haritada gecilecek baska gorev bulunamadi.")
        return false
    end

    if ns.activeTarget then
        PushHistory(ns.activeTarget)
    end

    -- Mevcut aktif gorevin listedeki sirasini bulup bir sonrakine gec
    local nextIdx = 1
    if ns.activeQuestID then
        for i = 1, #scored do
            if scored[i].questID == ns.activeQuestID then
                nextIdx = (i % #scored) + 1
                break
            end
        end
    end

    local pick = scored[nextIdx]
    if pick.isAvailable then
        ns:SetQuestWaypointWithLoc({
            questID = pick.questID,
            mapID = pick.mapID,
            x = pick.x,
            y = pick.y,
            title = pick.title,
            zoneName = ns:GetMapName(pick.mapID),
            isComplete = false,
            isAvailable = true,
        }, true)
    else
        ns:SetQuestWaypoint(pick.questID, true)
    end
    self:UpdateBanner()
    return true
end

function SmartQuest:StepPrevQuest()
    -- 1) Gecmis yiginindan onceki hedefe don
    while #targetHistory > 0 do
        local prev = table.remove(targetHistory)
        if prev and prev.questID ~= ns.activeQuestID then
            if prev.isAvailable or prev.isTrainer or prev.isCorpse then
                ns:SetQuestWaypointWithLoc(prev, true)
                self:UpdateBanner()
                return true
            else
                if ns:SetQuestWaypoint(prev.questID, true) then
                    self:UpdateBanner()
                    return true
                end
            end
        end
    end

    -- 2) Gecmis bossa aday listesinde bir onceki goreve don
    local scored = self:EvaluateAllCandidates(nil)
    if #scored == 0 then
        ns:Print("Geri donulecek onceki gorev bulunamadi.")
        return false
    end
    local prevIdx = #scored
    if ns.activeQuestID then
        for i = 1, #scored do
            if scored[i].questID == ns.activeQuestID then
                prevIdx = ((i - 2) % #scored) + 1
                break
            end
        end
    end
    local pick = scored[prevIdx]
    if pick.isAvailable then
        ns:SetQuestWaypointWithLoc({
            questID = pick.questID,
            mapID = pick.mapID,
            x = pick.x,
            y = pick.y,
            title = pick.title,
            zoneName = ns:GetMapName(pick.mapID),
            isComplete = false,
            isAvailable = true,
        }, true)
    else
        ns:SetQuestWaypoint(pick.questID, true)
    end
    self:UpdateBanner()
    return true
end

local function SaveBannerPos(frame)
    if not ns.db or not frame then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then
        ns.db.bannerPos = {
            point = point,
            relativePoint = relativePoint or point,
            x = math.floor((x or 0) + 0.5),
            y = math.floor((y or 0) + 0.5),
        }
    end
end

function SmartQuest:ApplyBannerPosition()
    if not bannerFrame or ns:IsInCombat() then
        return
    end
    local pos = (ns.db and ns.db.bannerPos) or ns.DEFAULTS.bannerPos
    bannerFrame:ClearAllPoints()
    bannerFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
end

local function CreateNavPill(parent, label, width, tooltipText, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 18)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1.0, 1.0, 1.0, 0.10)
    b.bg = bg
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.40, 0.80, 1.0, 0.25)
    local txt = b:CreateFontString(nil, "OVERLAY")
    txt:SetFont("Fonts\\ARIALN.TTF", 11, "")
    txt:SetShadowColor(0, 0, 0, 1.0)
    txt:SetShadowOffset(1, -1)
    txt:SetAllPoints()
    txt:SetText(label)
    txt:SetTextColor(0.92, 0.96, 1.0)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tooltipText, 1, 0.85, 0.2)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return b
end

local function CreateQuestBanner()
    if bannerFrame then
        return bannerFrame
    end

    local f = CreateFrame("Button", "QuestGoToZBannerFrame", UIParent, "BackdropTemplate")
    f:SetSize(376, 58)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")

    -- Modern 1 px ince kenarlikli cam-transparan tasarim
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.03, 0.05, 0.09, 0.42)
    f:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.16)

    -- Sol kenarda ince 2 px durum vurgu cizgisi
    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(2)
    accent:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    accent:SetColorTexture(1.0, 0.80, 0.15, 0.95)
    f.accent = accent

    -- Sag ustte: < (Geri) ve > (Siradaki) butonlari
    local nextBtn = CreateNavPill(f, ">", 22, "Siradaki goreve gec", function()
        if ns:IsInCombat() then
            ns:Print("Savas sirasinda UI degisikligi engellendi.")
            return
        end
        SmartQuest:StepNextQuest()
    end)
    nextBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    nextBtn.bg:SetColorTexture(0.18, 0.55, 0.30, 0.45)
    f.nextBtn = nextBtn

    local prevBtn = CreateNavPill(f, "<", 22, "Onceki goreve geri don", function()
        if ns:IsInCombat() then
            ns:Print("Savas sirasinda UI degisikligi engellendi.")
            return
        end
        SmartQuest:StepPrevQuest()
    end)
    prevBtn:SetPoint("RIGHT", nextBtn, "LEFT", -3, 0)
    f.prevBtn = prevBtn

    -- Mesafe yazisi
    local distText = f:CreateFontString(nil, "OVERLAY")
    distText:SetFont("Fonts\\ARIALN.TTF", 12, "")
    distText:SetShadowColor(0, 0, 0, 1.0)
    distText:SetShadowOffset(1, -1)
    distText:SetPoint("RIGHT", prevBtn, "LEFT", -8, 0)
    distText:SetJustifyH("RIGHT")
    f.distText = distText

    -- Ust satir: Eylem etiketi + Gorev adi
    local titleText = f:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Fonts\\ARIALN.TTF", 13, "")
    titleText:SetShadowColor(0, 0, 0, 1.0)
    titleText:SetShadowOffset(1, -1)
    titleText:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -7)
    titleText:SetPoint("RIGHT", distText, "LEFT", -8, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    f.titleText = titleText

    -- Ince 1 px yatay ayirici
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -27)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -27)
    sep:SetColorTexture(1.0, 1.0, 1.0, 0.10)

    -- Alt satir: Ne yapacagin / Hedef ilerlemesi
    local subText = f:CreateFontString(nil, "OVERLAY")
    subText:SetFont("Fonts\\ARIALN.TTF", 11, "")
    subText:SetShadowColor(0, 0, 0, 1.0)
    subText:SetShadowOffset(1, -1)
    subText:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -32)
    subText:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    subText:SetJustifyH("LEFT")
    subText:SetWordWrap(true)
    subText:SetMaxLines(2)
    subText:SetTextColor(0.86, 0.90, 0.96)
    f.subText = subText

    f:SetScript("OnDragStart", function(selfFrame)
        if ns:IsInCombat() or (ns.db and ns.db.locked) then
            return
        end
        selfFrame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        SaveBannerPos(selfFrame)
    end)

    -- Karta sol tiklayinca (henuz hedef secilmediyse) en iyi gorevi secer; sag tikla hedefi temizler
    f:SetScript("OnClick", function(_, button)
        if ns:IsInCombat() then
            return
        end
        if button == "RightButton" then
            ns:ClearQuestWaypoint(false)
        elseif not ns.activeTarget then
            SmartQuest:SelectBestQuest(nil, false)
        end
    end)

    f:SetScript("OnEnter", function(selfFrame)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfFrame, "ANCHOR_BOTTOM")
        GameTooltip:SetText("QuestGoToZ Aktif Hedef", 1, 0.85, 0.2)
        GameTooltip:AddLine("< / > : Onceki veya siradaki goreve gec", 0.78, 0.90, 1.0)
        GameTooltip:AddLine("Sol tik + surukle: Tasi | Sag tik: Hedefi temizle", 0.72, 0.80, 0.90)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    bannerFrame = f
    SmartQuest:ApplyBannerPosition()
    f:Hide()
    return f
end

function SmartQuest:UpdateBanner()
    if not bannerFrame then
        return
    end
    local db = ns.db or ns.DEFAULTS
    if db.enableQuestModule == false or not db.showBanner then
        if not ns:IsInCombat() and bannerFrame:IsShown() then
            bannerFrame:Hide()
        end
        return
    end

    local alpha = math.max(0.12, math.min(0.90, ((db.panelAlpha or 35) / 100) + 0.12))
    bannerFrame:SetBackdropColor(0.03, 0.05, 0.09, alpha)

    local target = ns.activeTarget
    local preview = nil
    if not target then
        preview = self:EvaluateBestQuest(nil)
    end

    if not target and not preview then
        if not ns:IsInCombat() and bannerFrame:IsShown() then
            bannerFrame:Hide()
        end
        return
    end

    if not bannerFrame:IsShown() then
        if ns:IsInCombat() then
            return
        end
        bannerFrame:Show()
    end

    local playerMapID, px, py, mapWidth, mapHeight = ns:GetPlayerPosition()
    local cur = target or preview

    -- Durum etiketi ve vurgu rengi
    local tagText
    if cur.isCorpse then
        tagText = "|cff88ccff[CESET]|r "
        bannerFrame.accent:SetColorTexture(0.45, 0.80, 1.0, 0.95)
    elseif cur.isTrainer then
        tagText = "|cffff88ff[HIZMET]|r "
        bannerFrame.accent:SetColorTexture(0.85, 0.45, 1.0, 0.95)
    elseif cur.isAvailable then
        tagText = "|cff33ccff[AL!]|r "
        bannerFrame.accent:SetColorTexture(0.20, 0.78, 1.0, 0.95)
    elseif cur.isComplete then
        tagText = "|cff33ff66[TESLIM]|r "
        bannerFrame.accent:SetColorTexture(0.20, 0.95, 0.42, 0.95)
    else
        tagText = cur.isMain and "|cffff9e22[ANA]|r " or "|cffffd100[YAP]|r "
        bannerFrame.accent:SetColorTexture(cur.isMain and 1.0 or 1.0, cur.isMain and 0.58 or 0.82, cur.isMain and 0.10 or 0.18, 0.95)
    end

    local titleSuffix = (not target) and " |cff88aacc(Tikla: Sec)|r" or ""
    bannerFrame.titleText:SetText(tagText .. (cur.title or "Gorev") .. titleSuffix)

    -- Mesafe hesabi
    local dist = nil
    if playerMapID and mapWidth and cur.mapID == playerMapID and ns:IsSafeNumber(cur.x) and ns:IsSafeNumber(cur.y) then
        dist = ns:ComputeDistanceAndAngle(px, py, cur.x, cur.y, mapWidth, mapHeight)
    elseif cur.dist then
        dist = cur.dist
    end

    if dist then
        local r, g, b = ns:GetColorForDistance(dist)
        if dist >= 1000 then
            bannerFrame.distText:SetText(string.format("%.1f km", dist / 1000))
        else
            bannerFrame.distText:SetText(string.format("%d m", math.floor(dist + 0.5)))
        end
        bannerFrame.distText:SetTextColor(r, g, b)
    else
        bannerFrame.distText:SetText("")
    end

    -- Alt metin: kalan hedefler veya yonlendirme ozeti
    if cur.isCorpse then
        bannerFrame.subText:SetText("Ceset konumuna git ve hayata don.")
    elseif cur.isAvailable then
        local reasonPart = (preview and preview.reason) and (" (" .. preview.reason .. ")") or ""
        bannerFrame.subText:SetText("Gorev veren NPC'ye git ve gorevi al." .. reasonPart)
    elseif cur.isComplete then
        local zName = cur.finalZoneName or cur.zoneName or ""
        bannerFrame.subText:SetText("Tamamlandi! Teslim NPC'sine git" .. (zName ~= "" and (" - " .. zName) or "."))
    elseif cur.isCrossMap then
        local hint = cur.waypointText or ("Cikis noktasindan " .. (cur.finalZoneName or "hedef bolgeye") .. " gec.")
        bannerFrame.subText:SetText(hint)
    elseif ns:IsSafeNumber(cur.questID) and cur.questID > 0 then
        local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", cur.questID)
        local parts = {}
        if okObj and type(objectives) == "table" then
            for i = 1, #objectives do
                local obj = objectives[i]
                if type(obj) == "table" and not obj.finished and ns:IsSafeString(obj.text) and obj.text ~= "" then
                    table.insert(parts, obj.text)
                    if #parts >= 2 then break end
                end
            end
        end
        if #parts > 0 then
            bannerFrame.subText:SetText(table.concat(parts, "  |  "))
        else
            bannerFrame.subText:SetText((preview and preview.reason) or "Hedef noktaya git.")
        end
    else
        bannerFrame.subText:SetText("Hedef noktaya git.")
    end
end

function SmartQuest:ToggleBanner()
    if not ns.db then return end
    ns.db.showBanner = not ns.db.showBanner
    self:UpdateBanner()
    ns:FireCallback("CONFIG_CHANGED")
end

function SmartQuest:InitBanner()
    CreateQuestBanner()
    self:UpdateBanner()
    if not bannerTicker then
        local ok, t = ns:SafeC("C_Timer", "NewTicker", 0.5, function()
            SmartQuest:UpdateBanner()
        end)
        if ok and t then
            bannerTicker = t
        end
    end
end

ns:RegisterCallback("TARGET_CHANGED", function()
    SmartQuest:UpdateBanner()
end)

ns:RegisterCallback("QUEST_LOG_UPDATE", function()
    SmartQuest:UpdateBanner()
end)

ns:RegisterCallback("CONFIG_CHANGED", function()
    SmartQuest:UpdateBanner()
end)
