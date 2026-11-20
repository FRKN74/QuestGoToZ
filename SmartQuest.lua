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

function SmartQuest:EvaluateBestQuest(excludeQuestID)
    local playerMapID, px, py, mapWidth, mapHeight = ns:GetPlayerPosition()
    if not playerMapID or not mapWidth then
        return nil
    end

    local quests = self:CollectCurrentMapQuests(playerMapID, px, py, mapWidth, mapHeight)
    if #quests == 0 then
        return nil
    end

    local _, clusterSizeMap = self:ComputeClusters(quests, mapWidth, mapHeight)
    local db = ns.db or ns.DEFAULTS
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

    local best = nil
    for i = 1, #quests do
        local q = quests[i]
        if q.questID ~= excludeQuestID then
            local distScore = wDist * (1 / (1 + (q.dist / 200)))
            local cSize = clusterSizeMap[q.questID] or 1
            local clusterScore = wClust * math.min(1, (cSize - 1) / 3)
            local xpScore = wXP * ((xpMap[q.questID] or 0) / maxXP)
            local compRatio = GetQuestCompletionRatio(q.questID, q.isComplete)
            local compScore = wComp * compRatio

            local totalScore = distScore + clusterScore + xpScore + compScore

            local reasons = {}
            table.insert(reasons, string.format("%d m", math.floor(q.dist + 0.5)))
            if cSize >= 2 then
                table.insert(reasons, string.format("%d gorev birlikte", cSize))
            end
            if q.isComplete then
                table.insert(reasons, "teslime hazir")
            elseif compRatio >= 0.5 then
                table.insert(reasons, string.format("%%%d tamam", math.floor(compRatio * 100 + 0.5)))
            end
            if (xpMap[q.questID] or 0) > 0 and xpScore >= (wXP * 0.65) then
                table.insert(reasons, "yuksek XP")
            end

            if not best or totalScore > best.score then
                best = {
                    questID = q.questID,
                    title = q.title,
                    dist = q.dist,
                    clusterSize = cSize,
                    xp = xpMap[q.questID] or 0,
                    completionRatio = compRatio,
                    isComplete = q.isComplete,
                    score = totalScore,
                    reason = table.concat(reasons, " + "),
                }
            end
        end
    end

    return best
end

function SmartQuest:SelectBestQuest(excludeQuestID, silent)
    local best = self:EvaluateBestQuest(excludeQuestID)
    if not best then
        if not silent then
            ns:Print("Bu haritada puanlanabilecek gorev bulunamadi.")
        end
        return false, nil
    end

    local ok = ns:SetQuestWaypoint(best.questID, true)
    if ok and not silent then
        ns:Print(string.format(
            "Siradaki en iyi gorev: |cffffff00%s|r |cff88ddff(%s)|r",
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
end)
