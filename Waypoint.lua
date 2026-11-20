local _, ns = ...

local Waypoint = {}
ns.Waypoint = Waypoint

-- Objective Tracker bloklarina karsilik gelen 16x16 "Git" butonlari
-- Blizzard blok tablolarini taint etmemek icin harici tabloda saklanir.
local blockButtons = {}
local activeTrackerBlocks = {}
local hookedModules = {}
local lastKnownComplete = {}

-- Bir gorevin hedef konumunu (mapID, x, y) cozumler.
-- Gorev baska haritadaysa bulundugun haritadaki cikis noktasini (GetNextWaypointForMap) kullanir.
function ns:GetQuestLocation(questID)
    if not self:IsSafeNumber(questID) then
        return nil
    end

    local okTitle, title = self:TrySafeC("C_QuestLog", "GetTitleForQuestID", questID)
    if not okTitle or not self:IsSafeString(title) then
        title = "Gorev #" .. tostring(questID)
    end

    local okComp, isComplete = self:TrySafeC("C_QuestLog", "IsComplete", questID)
    isComplete = (okComp and isComplete == true) or false

    local okPlayerMap, playerMapID = self:SafeC("C_Map", "GetBestMapForUnit", "player")
    if not okPlayerMap or not self:IsSafeNumber(playerMapID) then
        playerMapID = nil
    end

    -- 1. Yontem: C_QuestLog.GetNextWaypoint (gorevin asil hedef haritasi ve koordinati)
    local okNext, mapID, x, y = self:SafeC("C_QuestLog", "GetNextWaypoint", questID)
    if okNext and self:IsSafeNumber(mapID) and self:IsSafeNumber(x) and self:IsSafeNumber(y) and (x > 0 or y > 0) then
        -- Gorev baska haritadaysa bulundugun haritadaki cikis/gecis noktasini al
        if playerMapID and mapID ~= playerMapID then
            local okExit, ex, ey = self:TrySafeC("C_QuestLog", "GetNextWaypointForMap", questID, playerMapID)
            local okTxt, wpText = self:TrySafeC("C_QuestLog", "GetNextWaypointText", questID)
            local finalZone = self:GetMapName(mapID)
            if okExit and self:IsSafeNumber(ex) and self:IsSafeNumber(ey) and (ex > 0 or ey > 0) then
                return {
                    questID = questID,
                    mapID = playerMapID,
                    x = ex,
                    y = ey,
                    finalMapID = mapID,
                    finalZoneName = finalZone,
                    waypointText = (okTxt and self:IsSafeString(wpText) and wpText ~= "") and wpText or nil,
                    isCrossMap = true,
                    title = title,
                    zoneName = finalZone,
                    isComplete = isComplete,
                }
            end
            return {
                questID = questID,
                mapID = mapID,
                x = x,
                y = y,
                finalMapID = mapID,
                finalZoneName = finalZone,
                waypointText = (okTxt and self:IsSafeString(wpText) and wpText ~= "") and wpText or nil,
                isCrossMap = true,
                title = title,
                zoneName = finalZone,
                isComplete = isComplete,
            }
        end

        return {
            questID = questID,
            mapID = mapID,
            x = x,
            y = y,
            finalMapID = mapID,
            isCrossMap = false,
            title = title,
            zoneName = self:GetMapName(mapID),
            isComplete = isComplete,
        }
    end

    -- 2. Yontem: Bulunulan haritada GetNextWaypointForMap / GetQuestsOnMap
    if playerMapID then
        local okForMap, fx, fy = self:TrySafeC("C_QuestLog", "GetNextWaypointForMap", questID, playerMapID)
        if okForMap and self:IsSafeNumber(fx) and self:IsSafeNumber(fy) and (fx > 0 or fy > 0) then
            local okTxt, wpText = self:TrySafeC("C_QuestLog", "GetNextWaypointText", questID)
            return {
                questID = questID,
                mapID = playerMapID,
                x = fx,
                y = fy,
                isCrossMap = (okTxt and self:IsSafeString(wpText) and wpText ~= "") and true or false,
                waypointText = (okTxt and self:IsSafeString(wpText) and wpText ~= "") and wpText or nil,
                title = title,
                zoneName = self:GetMapName(playerMapID),
                isComplete = isComplete,
            }
        end

        local okOnMap, questsOnMap = self:SafeC("C_QuestLog", "GetQuestsOnMap", playerMapID)
        if okOnMap and type(questsOnMap) == "table" then
            for i = 1, #questsOnMap do
                local info = questsOnMap[i]
                if type(info) == "table" and info.questID == questID then
                    if self:IsSafeNumber(info.x) and self:IsSafeNumber(info.y) and (info.x > 0 or info.y > 0) then
                        return {
                            questID = questID,
                            mapID = playerMapID,
                            x = info.x,
                            y = info.y,
                            isCrossMap = false,
                            title = title,
                            zoneName = self:GetMapName(playerMapID),
                            isComplete = isComplete,
                        }
                    end
                end
            end
        end
    end

    return nil
end

-- Aktif UserWaypoint'i temizler
function ns:ClearQuestWaypoint(silent)
    self:SafeC("C_Map", "ClearUserWaypoint")
    self.activeQuestID = nil
    self.activeTarget = nil
    if not silent then
        self:Print("Waypoint temizlendi.")
    end
    self:FireCallback("TARGET_CHANGED", nil)
    Waypoint:RequestTrackerRefresh()
end

-- Goreve tiklandiginda nerede ne yapilacagini sohbete kisaca yazar
function ns:PrintQuestGuidance(loc)
    if type(loc) ~= "table" then
        return
    end
    local zoneName = loc.zoneName or (loc.mapID and self:GetMapName(loc.mapID))
    local whereText = ""
    if zoneName then
        whereText = " [" .. zoneName .. "]"
    end
    if self:IsSafeNumber(loc.x) and self:IsSafeNumber(loc.y) and (loc.x > 0 or loc.y > 0) then
        whereText = whereText .. string.format(" (%.1f, %.1f)", loc.x * 100, loc.y * 100)
    end

    if loc.isCorpse then
        self:Print("Ceset Konumu: |cff88ccff" .. (loc.title or "Ceset") .. "|r" .. whereText)
        return
    end

    if loc.isTrainer then
        self:Print("Class Trainer: |cffff88ff" .. (loc.title or "") .. "|r" .. whereText)
        return
    end

    if loc.isAvailable then
        self:Print("Gorev NPC'si: |cff33ccff" .. (loc.title or "") .. "|r" .. whereText)
        return
    end

    if loc.isComplete then
        self:Print("Teslim edilmeye hazir: |cff33ff66" .. (loc.title or "") .. "|r" .. whereText)
        return
    end

    if loc.isCrossMap then
        local dest = loc.finalZoneName or loc.zoneName or "Baska Harita"
        local exitHint = loc.waypointText and (" -> " .. loc.waypointText) or (" -> " .. dest .. " cikisi")
        self:Print("|cff38a8ff[Baska Harita]|r |cffffff00" .. (loc.title or "") .. "|r" .. exitHint .. whereText)
        return
    end

    self:Print("Yonlendirildi: |cffffff00" .. (loc.title or "") .. "|r" .. whereText)
    if self:IsSafeNumber(loc.questID) then
        local okObj, objectives = self:TrySafeC("C_QuestLog", "GetQuestObjectives", loc.questID)
        if okObj and type(objectives) == "table" then
            local shown = 0
            for i = 1, #objectives do
                local obj = objectives[i]
                if type(obj) == "table" and not obj.finished and self:IsSafeString(obj.text) and obj.text ~= "" then
                    self:Print("  - " .. obj.text)
                    shown = shown + 1
                    if shown >= 3 then
                        break
                    end
                end
            end
        end
    end
end

-- Verilen hedef konumu (loc) icin UserWaypoint + SuperTrack ayarlar
function ns:SetQuestWaypointWithLoc(loc, silent)
    if type(loc) ~= "table" or not self:IsSafeNumber(loc.mapID)
        or not self:IsSafeNumber(loc.x) or not self:IsSafeNumber(loc.y) then
        return false
    end

    -- Aktif gorev ise Blizzard'in kendi gorev supertrack'ini de ac
    if not loc.isAvailable and not loc.isTrainer and not loc.isCorpse and self:IsSafeNumber(loc.questID) and loc.questID > 0 then
        self:TrySafeC("C_SuperTrack", "SetSuperTrackedQuestID", loc.questID)
    end

    local okCan, canSet = self:SafeC("C_Map", "CanSetUserWaypointOnMap", loc.mapID)
    if okCan and canSet then
        if type(_G.UiMapPoint) == "table" and type(_G.UiMapPoint.CreateFromCoordinates) == "function" then
            local okPt, mapPoint = pcall(_G.UiMapPoint.CreateFromCoordinates, loc.mapID, loc.x, loc.y)
            if okPt and mapPoint then
                local okSet = self:SafeC("C_Map", "SetUserWaypoint", mapPoint)
                if okSet then
                    self:SafeC("C_SuperTrack", "SetSuperTrackedUserWaypoint", true)
                end
            else
                self:PrintError("uimap_point", "UiMapPoint.CreateFromCoordinates hatasi: " .. tostring(mapPoint))
            end
        else
            self:PrintError("uimap_missing", "UiMapPoint.CreateFromCoordinates bulunamadi.")
        end
    elseif not silent then
        self:Print("Bu haritada oyun ici waypoint koyulamiyor; yalnizca mesafe oku ve minimap cizgisi gosterilecek.")
    end

    self.activeQuestID = loc.questID
    self.activeTarget = loc
    if self:IsSafeNumber(loc.questID) then
        lastKnownComplete[loc.questID] = loc.isComplete and true or false
    end

    if not silent then
        self:PrintQuestGuidance(loc)
    end

    self:FireCallback("TARGET_CHANGED", loc)
    Waypoint:RequestTrackerRefresh()
    return true
end

-- Belirtilen gorev icin UserWaypoint + SuperTrack ayarlar
function ns:SetQuestWaypoint(questID, silent)
    if not self:IsSafeNumber(questID) then
        return false
    end

    local loc = self:GetQuestLocation(questID)
    if not loc then
        if not silent then
            self:Print("Bu gorev icin konum bilgisi bulunamadi.")
        end
        return false
    end

    return self:SetQuestWaypointWithLoc(loc, silent)
end

-- Ayni goreve tekrar basilirsa temizler, farkli goreve basilirsa waypoint koyar
function ns:ToggleQuestWaypoint(questID, fallbackLoc)
    if not self:IsSafeNumber(questID) then
        return
    end
    if self.activeQuestID == questID then
        self:ClearQuestWaypoint(false)
    else
        if fallbackLoc and (fallbackLoc.isAvailable or fallbackLoc.isTrainer) then
            self:SetQuestWaypointWithLoc(fallbackLoc, false)
        elseif not self:SetQuestWaypoint(questID, false) and fallbackLoc then
            self:SetQuestWaypointWithLoc(fallbackLoc, false)
        end
    end
end

-- Bulunulan haritadaki siradaki en iyi gorevi puanlayarak secer (Ozellik 2 & 5)
function ns:SelectNearestQuest(excludeQuestID)
    local db = self.db or self.DEFAULTS
    if not db.autoSelectNearest then
        return false
    end
    if self.SmartQuest and type(self.SmartQuest.SelectBestQuest) == "function" then
        local ok = self.SmartQuest:SelectBestQuest(excludeQuestID, false)
        return ok
    end
    return false
end

-- Objective Tracker bloklari icin 16x16 "Git" butonu olusturma
local function CreateTrackerButton(block)
    local btn = CreateFrame("Button", nil, block)
    btn:SetSize(16, 16)
    btn:SetMotionScriptsWhileDisabled(true)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Minimap\\MinimapArrow")
    btn.icon = icon

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    btn:SetScript("OnClick", function(selfBtn)
        if ns:IsInCombat() then
            ns:Print("Combat sirasinda UI degisikligi engellendi.")
            return
        end
        if selfBtn.questID then
            ns:ToggleQuestWaypoint(selfBtn.questID)
        end
    end)

    btn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        if not selfBtn.hasLocation then
            GameTooltip:SetText("Konum bilgisi yok", 1, 0.35, 0.35)
        elseif ns.activeQuestID == selfBtn.questID then
            GameTooltip:SetText("QuestGoToZ: Waypoint'i kaldir", 0.3, 1, 0.4)
            GameTooltip:AddLine("Tekrar tiklayarak isareti temizleyin.", 0.8, 0.8, 0.8, true)
        else
            local title = selfBtn.isComplete and "QuestGoToZ: Teslim NPC'sine git" or "QuestGoToZ: Git"
            GameTooltip:SetText(title, 1, 0.85, 0.2)
            GameTooltip:AddLine("Bu goreve waypoint koymak icin tiklayin.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    return btn
end

-- Tek bir Objective Tracker blogunu gunceller
local function UpdateBlockButton(block)
    if type(block) ~= "table" or not block.IsShown then
        return
    end
    local questID = block.id
    if not ns:IsSafeNumber(questID) then
        return
    end

    local btn = blockButtons[block]
    if not btn then
        btn = CreateTrackerButton(block)
        blockButtons[block] = btn
    end

    activeTrackerBlocks[block] = true
    btn.questID = questID

    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", block, "TOPRIGHT", 18, -2)

    local loc = ns:GetQuestLocation(questID)
    if loc then
        btn.hasLocation = true
        btn.isComplete = loc.isComplete
        btn:Enable()
        btn.icon:SetDesaturated(false)
        if ns.activeQuestID == questID then
            btn.icon:SetVertexColor(0.2, 1.0, 0.3, 1.0)
        elseif loc.isComplete then
            btn.icon:SetVertexColor(0.3, 0.85, 1.0, 1.0)
        else
            btn.icon:SetVertexColor(1.0, 0.85, 0.2, 1.0)
        end
    else
        btn.hasLocation = false
        btn.isComplete = false
        btn:Disable()
        btn.icon:SetDesaturated(true)
        btn.icon:SetVertexColor(0.5, 0.5, 0.5, 0.65)
    end

    btn:Show()
end

-- Retail 11.0+ / Midnight (usedBlocks[template][id] = block) ve duz (usedBlocks[id] = block) yapilarini tarar
local function ScanModuleBlocks(module)
    if type(module) ~= "table" or type(module.usedBlocks) ~= "table" then
        return
    end
    for _, v in pairs(module.usedBlocks) do
        if type(v) == "table" then
            if v.IsShown and v.id then
                if v:IsShown() then
                    UpdateBlockButton(v)
                end
            else
                for _, block in pairs(v) do
                    if type(block) == "table" and block.IsShown and block:IsShown() and block.id then
                        UpdateBlockButton(block)
                    end
                end
            end
        end
    end
end

local TRACKER_MODULE_NAMES = {
    "QuestObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "WorldQuestObjectiveTracker",
    "BonusObjectiveTracker",
}

function Waypoint:RefreshTrackerButtons()
    if ns:IsInCombat() then
        ns:RunOutOfCombat("refresh_tracker_buttons", function()
            Waypoint:RefreshTrackerButtons()
        end)
        return
    end

    wipe(activeTrackerBlocks)

    for i = 1, #TRACKER_MODULE_NAMES do
        local modName = TRACKER_MODULE_NAMES[i]
        local mod = _G[modName]
        if type(mod) == "table" then
            local ok, err = pcall(ScanModuleBlocks, mod)
            if not ok then
                ns:PrintError("scan_" .. modName, modName .. " tarama hatasi: " .. tostring(err))
            end
        end
    end

    -- Artik gorunmeyen veya kullanilmayan blok butonlarini gizle
    for block, btn in pairs(blockButtons) do
        if not activeTrackerBlocks[block] then
            btn:Hide()
        end
    end
end

function Waypoint:RequestTrackerRefresh()
    ns:RunOutOfCombat("refresh_tracker_buttons", function()
        Waypoint:RefreshTrackerButtons()
    end)
end

-- Objective Tracker yeniden cizildiginde hooksecurefunc ile butonlari yeniden konumlandir
local function HookTrackerModule(modName)
    if hookedModules[modName] then
        return
    end
    local mod = _G[modName]
    if type(mod) ~= "table" then
        return
    end
    if type(mod.Update) == "function" then
        hooksecurefunc(mod, "Update", function()
            Waypoint:RequestTrackerRefresh()
        end)
        hookedModules[modName] = true
    end
end

function Waypoint:InstallTrackerHooks()
    for i = 1, #TRACKER_MODULE_NAMES do
        HookTrackerModule(TRACKER_MODULE_NAMES[i])
    end

    if type(_G.ObjectiveTrackerFrame) == "table" and type(_G.ObjectiveTrackerFrame.Update) == "function" and not hookedModules["ObjectiveTrackerFrame"] then
        hooksecurefunc(_G.ObjectiveTrackerFrame, "Update", function()
            Waypoint:RequestTrackerRefresh()
        end)
        hookedModules["ObjectiveTrackerFrame"] = true
    end

    -- Eski/alternatif tracker fonksiyonu icin guvenli yedek kanca
    if type(_G.ObjectiveTracker_Update) == "function" and not hookedModules["ObjectiveTracker_Update"] then
        hooksecurefunc("ObjectiveTracker_Update", function()
            Waypoint:RequestTrackerRefresh()
        end)
        hookedModules["ObjectiveTracker_Update"] = true
    end
end

-- Aktif gorev durumunu (ornegin tamamlanip teslim NPC'sine donmesini) kontrol et
local function CheckActiveQuestUpdate()
    if not ns.activeQuestID then
        return
    end

    local okOn, isOnQuest = ns:TrySafeC("C_QuestLog", "IsOnQuest", ns.activeQuestID)
    if ns.activeTarget and (ns.activeTarget.isTrainer or ns.activeTarget.isCorpse) then
        return
    end
    if ns.activeTarget and ns.activeTarget.isAvailable then
        if okOn and isOnQuest then
            ns:SetQuestWaypoint(ns.activeQuestID, true)
        end
        return
    end

    if okOn and not isOnQuest then
        ns:ClearQuestWaypoint(true)
        return
    end

    local loc = ns:GetQuestLocation(ns.activeQuestID)
    if not loc then
        return
    end

    local prevComplete = lastKnownComplete[ns.activeQuestID]
    ns.activeTarget = loc

    -- Gorev yeni tamamlandiysa ses cal + ayar aciksa oku teslim NPC konumuna cevir (Ozellik 5 & 7)
    if loc.isComplete and not prevComplete then
        lastKnownComplete[ns.activeQuestID] = true
        local db = ns.db or ns.DEFAULTS
        if db.objectiveCompleteSound then
            local soundID = (type(_G.SOUNDKIT) == "table" and (_G.SOUNDKIT.READY_CHECK or _G.SOUNDKIT.IG_QUEST_LIST_COMPLETE)) or 8960
            ns:PlayAddonSound(soundID)
        end
        if db.autoTurnInRedirect then
            ns:Print("Gorev tamamlandi! Ok teslim NPC'sine cevrildi: |cff33ff66" .. loc.title .. "|r")
            ns:SetQuestWaypoint(ns.activeQuestID, true)
        else
            ns:FireCallback("TARGET_UPDATED", loc)
        end
    else
        ns:FireCallback("TARGET_UPDATED", loc)
    end
end

ns:RegisterCallback("PLAYER_LOGIN", function()
    Waypoint:InstallTrackerHooks()
    Waypoint:RequestTrackerRefresh()
end)

-- =====================================================================
-- Dunya Haritasi (M): Questie Tarzi Gorev Pinleri (Tamamlanan Yesil Daire + Devam Eden + Alinabilir !)
-- =====================================================================
local worldMapOverlay = nil
local worldMapPins = {}
local worldMapHooked = false

local function GetQuestPinKind(questID)
    local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", questID)
    if okObj and type(objectives) == "table" then
        for i = 1, #objectives do
            local obj = objectives[i]
            if type(obj) == "table" and not obj.finished then
                if obj.type == "item" or obj.type == "object" then
                    return "loot"
                end
            end
        end
    end
    return "kill"
end

local function GetOrCreateWorldMapPin(index)
    local pin = worldMapPins[index]
    if pin then
        return pin
    end
    pin = CreateFrame("Button", nil, worldMapOverlay)
    pin:SetSize(24, 24)
    pin:RegisterForClicks("LeftButtonUp")

    -- Ic yari saydam daire dolgusu (tamamlanan yesil daire icin)
    local fill = pin:CreateTexture(nil, "BACKGROUND")
    fill:SetSize(20, 20)
    fill:SetPoint("CENTER", pin, "CENTER", 0, 0)
    fill:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    fill:SetVertexColor(0.12, 0.92, 0.32, 0.42)
    pin.fill = fill

    -- Parlak dis halka
    local ring = pin:CreateTexture(nil, "OVERLAY", nil, 1)
    ring:SetSize(28, 28)
    ring:SetPoint("CENTER", pin, "CENTER", 0, 0)
    ring:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    ring:SetBlendMode("ADD")
    pin.ring = ring

    -- Ikinci net cember (tamamlanan yesil daire)
    local ring2 = pin:CreateTexture(nil, "OVERLAY", nil, 2)
    ring2:SetSize(24, 24)
    ring2:SetPoint("CENTER", pin, "CENTER", 0, 0)
    ring2:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    pin.ring2 = ring2

    -- Merkez ikon (alinabilir ! veya devam eden kilic/el)
    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.icon = icon

    pin:SetScript("OnClick", function(selfPin)
        if ns:IsInCombat() or not selfPin.pinData then
            return
        end
        local d = selfPin.pinData
        ns:ToggleQuestWaypoint(d.questID, {
            questID = d.questID,
            mapID = d.mapID,
            x = d.x,
            y = d.y,
            title = d.title,
            zoneName = ns:GetMapName(d.mapID),
            isComplete = (d.pinType == "completed"),
            isAvailable = (d.pinType == "available"),
        })
    end)

    pin:SetScript("OnEnter", function(selfPin)
        if not GameTooltip or not selfPin.pinData then
            return
        end
        local d = selfPin.pinData
        GameTooltip:SetOwner(selfPin, "ANCHOR_RIGHT")
        GameTooltip:SetText(d.title or ("Gorev #" .. tostring(d.questID)), 1, 0.85, 0.2)
        if d.pinType == "completed" then
            GameTooltip:AddLine("Tamamlandi (Teslim NPC'si)", 0.25, 1.0, 0.40)
        elseif d.pinType == "available" then
            GameTooltip:AddLine("Alinabilir Gorev (!)", 0.30, 0.85, 1.0)
        else
            GameTooltip:AddLine("Devam Eden Gorev", 1.0, 0.85, 0.25)
            local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", d.questID)
            if okObj and type(objectives) == "table" then
                for i = 1, math.min(#objectives, 4) do
                    local obj = objectives[i]
                    if type(obj) == "table" and ns:IsSafeString(obj.text) and obj.text ~= "" then
                        if obj.finished then
                            GameTooltip:AddLine("- " .. obj.text, 0.35, 1.0, 0.4)
                        else
                            GameTooltip:AddLine("- " .. obj.text, 0.92, 0.92, 0.92)
                        end
                    end
                end
            end
        end
        -- Parti ilerlemesi varsa goster
        if ns.PartySync and d.questID and d.questID > 0 then
            local pp = ns.PartySync:GetPartyProgress(d.questID)
            if pp then
                local parts = {}
                for i = 1, #pp do
                    table.insert(parts, pp[i].name .. ": " .. pp[i].text)
                end
                GameTooltip:AddLine("Parti: " .. table.concat(parts, ", "), 0.55, 0.82, 1.0, true)
            end
        end
        GameTooltip:AddLine(string.format("Konum: %.1f, %.1f  |  Tikla: Yonlendir", d.x * 100, d.y * 100), 0.72, 0.80, 0.90)
        GameTooltip:Show()
    end)

    pin:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    pin:Hide()
    worldMapPins[index] = pin
    return pin
end

function Waypoint:RefreshWorldMapCompletedCircles()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end
    local db = ns.db or ns.DEFAULTS
    if not db.showWorldMapPins then
        for i = 1, #worldMapPins do
            worldMapPins[i]:Hide()
        end
        return
    end
    if type(WorldMapFrame.GetCanvas) ~= "function" or type(WorldMapFrame.GetMapID) ~= "function" then
        return
    end

    local canvas = WorldMapFrame:GetCanvas()
    local mapID = WorldMapFrame:GetMapID()
    if not canvas or not ns:IsSafeNumber(mapID) then
        return
    end

    if not worldMapOverlay then
        worldMapOverlay = CreateFrame("Frame", "QuestGoToZWorldMapOverlay", canvas)
        worldMapOverlay:SetAllPoints(canvas)
        worldMapOverlay:SetFrameLevel((canvas:GetFrameLevel() or 1) + 25)
        worldMapOverlay:EnableMouse(false)
    elseif worldMapOverlay:GetParent() ~= canvas then
        worldMapOverlay:SetParent(canvas)
        worldMapOverlay:SetAllPoints(canvas)
        worldMapOverlay:SetFrameLevel((canvas:GetFrameLevel() or 1) + 25)
    end

    local cw = canvas:GetWidth() or 0
    local ch = canvas:GetHeight() or 0
    if cw <= 0 or ch <= 0 then
        return
    end

    local seen = {}
    local points = {}

    local function AddPin(questID, x, y, pinType, explicitTitle)
        if not ns:IsSafeNumber(questID) or seen[questID] then
            return
        end
        if not ns:IsSafeNumber(x) or not ns:IsSafeNumber(y) or (x <= 0 and y <= 0) then
            return
        end
        seen[questID] = true
        local title = explicitTitle
        if not ns:IsSafeString(title) or title == "" then
            local okT, fetched = ns:TrySafeC("C_QuestLog", "GetTitleForQuestID", questID)
            title = (okT and ns:IsSafeString(fetched) and fetched ~= "") and fetched or ("Gorev #" .. tostring(questID))
        end
        table.insert(points, {
            questID = questID,
            mapID = mapID,
            x = x,
            y = y,
            pinType = pinType,
            title = title,
        })
    end

    -- 1) Haritadaki aktif ve tamamlanmis gorevler
    local okOnMap, questsOnMap = ns:TrySafeC("C_QuestLog", "GetQuestsOnMap", mapID)
    if okOnMap and type(questsOnMap) == "table" then
        for i = 1, #questsOnMap do
            local info = questsOnMap[i]
            if type(info) == "table" and ns:IsSafeNumber(info.questID) then
                local okComp, isComp = ns:TrySafeC("C_QuestLog", "IsComplete", info.questID)
                local okOn, isOn = ns:TrySafeC("C_QuestLog", "IsOnQuest", info.questID)
                if okComp and isComp == true then
                    AddPin(info.questID, info.x, info.y, "completed", nil)
                elseif okOn and isOn == true then
                    AddPin(info.questID, info.x, info.y, "active", nil)
                else
                    AddPin(info.questID, info.x, info.y, "available", nil)
                end
            end
        end
    end

    -- 2) Gunlukteki tamamlanmis gorevler (POI'de cikmadiysa)
    local okNum, numEntries = ns:TrySafeC("C_QuestLog", "GetNumQuestLogEntries")
    if okNum and ns:IsSafeNumber(numEntries) then
        for idx = 1, numEntries do
            local okInfo, info = ns:TrySafeC("C_QuestLog", "GetInfo", idx)
            if okInfo and type(info) == "table" and not info.isHeader and not info.isHidden and ns:IsSafeNumber(info.questID) then
                local qid = info.questID
                if not seen[qid] then
                    local okComp, isComp = ns:TrySafeC("C_QuestLog", "IsComplete", qid)
                    if okComp and isComp == true then
                        local okFor, fx, fy = ns:TrySafeC("C_QuestLog", "GetNextWaypointForMap", qid, mapID)
                        if okFor and ns:IsSafeNumber(fx) and ns:IsSafeNumber(fy) and (fx > 0 or fy > 0) then
                            AddPin(qid, fx, fy, "completed", info.title)
                        else
                            local okNext, qMapID, nx, ny = ns:TrySafeC("C_QuestLog", "GetNextWaypoint", qid)
                            if okNext and qMapID == mapID then
                                AddPin(qid, nx, ny, "completed", info.title)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3) Haritadaki alinabilir gorevler (!)
    local okLines, questLines = ns:TrySafeC("C_QuestLine", "GetAvailableQuestLines", mapID)
    if okLines and type(questLines) == "table" then
        for i = 1, #questLines do
            local ql = questLines[i]
            if type(ql) == "table" and not ql.isHidden and ns:IsSafeNumber(ql.questID) and not seen[ql.questID] then
                local okDone, isDone = ns:TrySafeC("C_QuestLog", "IsQuestFlaggedCompleted", ql.questID)
                local okOn, isOn = ns:TrySafeC("C_QuestLog", "IsOnQuest", ql.questID)
                if not (okDone and isDone == true) and not (okOn and isOn == true) then
                    AddPin(ql.questID, ql.x, ql.y, "available", ql.questName)
                end
            end
        end
    end

    for i = 1, #points do
        local pt = points[i]
        local pin = GetOrCreateWorldMapPin(i)
        pin.pinData = pt
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", pt.x * cw, -pt.y * ch)

        if pt.pinType == "completed" then
            -- Tamamlanmis gorev: parlak YESIL DAIRE
            pin:SetSize(28, 28)
            pin.fill:SetVertexColor(0.12, 0.92, 0.32, 0.42)
            pin.fill:Show()
            pin.ring:SetVertexColor(0.15, 1.0, 0.35, 1.0)
            pin.ring:Show()
            pin.ring2:SetVertexColor(0.20, 1.0, 0.40, 0.95)
            pin.ring2:Show()
            pin.icon:Hide()
        elseif pt.pinType == "available" then
            -- Alinabilir gorev: parlak ! ikonu
            pin:SetSize(20, 20)
            pin.fill:Hide()
            pin.ring:SetSize(22, 22)
            pin.ring:SetVertexColor(1.0, 0.82, 0.15, 0.65)
            pin.ring:Show()
            pin.ring2:Hide()
            pin.icon:SetSize(16, 16)
            pin.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            pin.icon:Show()
        else
            -- Devam eden gorev: kilic veya el ikonu
            pin:SetSize(20, 20)
            pin.fill:Hide()
            pin.ring:SetSize(22, 22)
            pin.ring:SetVertexColor(1.0, 0.78, 0.18, 0.55)
            pin.ring:Show()
            pin.ring2:Hide()
            pin.icon:SetSize(14, 14)
            local kind = GetQuestPinKind(pt.questID)
            pin.icon:SetTexture(kind == "loot" and "Interface\\Cursor\\Pickup" or "Interface\\Cursor\\Attack")
            pin.icon:Show()
        end

        pin:Show()
    end

    for i = #points + 1, #worldMapPins do
        worldMapPins[i].pinData = nil
        worldMapPins[i]:Hide()
    end
end

local function InstallWorldMapHooks()
    if worldMapHooked or not WorldMapFrame then
        return
    end
    worldMapHooked = true

    WorldMapFrame:HookScript("OnShow", function()
        Waypoint:RefreshWorldMapCompletedCircles()
    end)

    if type(WorldMapFrame.SetMapID) == "function" then
        hooksecurefunc(WorldMapFrame, "SetMapID", function()
            Waypoint:RefreshWorldMapCompletedCircles()
        end)
    end
    if type(WorldMapFrame.OnMapChanged) == "function" then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
            Waypoint:RefreshWorldMapCompletedCircles()
        end)
    end
end

ns:RegisterCallback("PLAYER_LOGIN", function()
    InstallWorldMapHooks()
end)

ns:RegisterCallback("QUEST_LOG_UPDATE", function()
    CheckActiveQuestUpdate()
    Waypoint:RequestTrackerRefresh()
    Waypoint:RefreshWorldMapCompletedCircles()
end)

ns:RegisterCallback("QUEST_WATCH_LIST_CHANGED", function()
    Waypoint:RequestTrackerRefresh()
end)

ns:RegisterCallback("ZONE_CHANGED_NEW_AREA", function()
    -- Baska haritaya gecildiginde aktif gorevin yeni haritadaki cikis/hedef noktasini guncelle
    if ns.activeQuestID and ns.activeTarget and not ns.activeTarget.isTrainer and not ns.activeTarget.isCorpse and not ns.activeTarget.isAvailable then
        ns:SetQuestWaypoint(ns.activeQuestID, true)
    else
        CheckActiveQuestUpdate()
    end
    Waypoint:RequestTrackerRefresh()
    Waypoint:RefreshWorldMapCompletedCircles()
end)

ns:RegisterCallback("QUEST_ACCEPTED", function(questID)
    Waypoint:RequestTrackerRefresh()
    -- Gorev kabulunde sonraki en yakin gorevi otomatik sec (ayarla acilip kapanabilir)
    if ns.db and ns.db.autoSelectNearest then
        ns:TrySafeC("C_Timer", "After", 0.4, function()
            ns:SelectNearestQuest(nil)
        end)
    end
end)

ns:RegisterCallback("QUEST_TURNED_IN", function(questID)
    if ns.activeQuestID == questID then
        ns:ClearQuestWaypoint(true)
    end
    lastKnownComplete[questID] = nil
    Waypoint:RequestTrackerRefresh()
    Waypoint:RefreshWorldMapCompletedCircles()
    -- Gorev tesliminde sonraki en yakin gorevi otomatik sec
    if ns.db and ns.db.autoSelectNearest then
        ns:TrySafeC("C_Timer", "After", 0.4, function()
            ns:SelectNearestQuest(questID)
        end)
    end
end)

ns:RegisterCallback("QUEST_REMOVED", function(questID)
    if ns.activeQuestID == questID then
        ns:ClearQuestWaypoint(true)
    end
    lastKnownComplete[questID] = nil
    Waypoint:RequestTrackerRefresh()
    Waypoint:RefreshWorldMapCompletedCircles()
end)
