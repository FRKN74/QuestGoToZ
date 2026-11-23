local addonName, ns = ...

ns.name = addonName
ns.version = "1.3.1"

-- Varsayilan SavedVariables profil ayarlari
ns.DEFAULTS = {
    nearbyRadius = 150,          -- Yakindaki gorevler esigi (metre)
    nearThreshold = 100,         -- Ok yesil renk esigi (< 100 m)
    farThreshold = 300,          -- Ok kirmizi renk esigi (> 300 m)
    arrivalRadius = 30,          -- Hedefe <= 30 m kala parlayan ikon goster
    clusterRadius = 100,         -- Birlikte yapilabilecek gorevler esigi (metre)
    questLogWarnThreshold = 22,  -- Gorev gunlugu doluluk uyari esigi (maks 25)
    soundEnabled = true,         -- Ilk yaklasmada ses bildirimi
    objectiveCompleteSound = true, -- Hedef tamamlaninca kisa ses
    quietMode = false,           -- Sessiz mod (tum sesleri kapatir)
    autoTurnInRedirect = true,   -- Hedefler bitince oku teslim NPC'sine cevir
    autoSelectNearest = true,    -- Gorev tesliminde siradaki en iyi goreve gec
    showClusters = true,         -- Birlikte yapilabilecek gorevleri goster
    showMobTooltip = true,       -- Mouseover tooltip'e gorev satiri ekle
    corpseWaypoint = true,       -- Olunce ceset yonune otomatik waypoint koy
    showRewardHighlight = true,  -- En yuksek satis degerli odule altin ikonu koy
    showEliteBadge = true,       -- Elite / Grup gorevi kirmizi rozeti
    showZoneProgress = true,     -- Bolge ilerlemesi (X/Y tamam)
    showNearestServices = true,  -- En yakin hizmetler (satici, posta, han, ucus)
    bagFullVendorAlert = true,   -- Canta %90 dolunca en yakin saticiyi oner
    showQuestItemButton = true,  -- Gorev esyasi kullan (SecureActionButton)
    showCombatText = true,       -- Metin2 tarzi hasar yazilari (krit/normal/alinan)
    showWorldMapPins = true,     -- Dunya haritasinda (M) gorev pinleri ve yesil daireler
    showQuestLevel = true,       -- Gorev listesinde renkli [Lv] etiketi
    partySync = true,            -- Parti arkadaslariyla canli gorev ilerlemesi senkronu
    enableQuestModule = true,    -- Ana Gorev Modulu (Liste + Ok + Kart + Harita + Mob Rozeti)
    levelingMode = true,         -- Levelling gorevleri ile devam (alinmamis yuksek XP + mevcut)
    showBanner = true,           -- Ust-orta AAP tarzi aktif gorev karti
    showUpgradeArrows = true,    -- Cantada daha yuksek ilvl esya icin yesil yukari ok
    durabilityAlert = true,      -- Zirh dayanikliligi <%30 olunca tamirci uyarisi
    levelUpChecklist = true,     -- Level atlayinca tek satirlik talent/binek/egitmen kontrolu
    tankThreatColors = true,     -- Tank aggro nameplate renkleri (bende=yesil, degil=kirmizi)
    showThreatMeter = true,      -- Bagimsiz Threat Meter penceresi (salt okunur tehdit listesi)
    threatOnlyInCombat = false,  -- Sadece tehdit/savas varken goster
    threatShowPullLine = true,   -- Pull Aggro esik satirini goster
    threatIncludePets = true,    -- Petleri threat listesine dahil et
    threatMode = "pull",         -- "pull" (% Pull Aggro) veya "raw" (Ham Threat)
    threatSource = "target",     -- "target" veya "focus"
    showPartyFrames = true,      -- Solda 5 kisilik grup cercevesi (Can/Mana/Lv/Heal)
    partyShowSolo = true,        -- Tek basina iken de grup cercevesini goster
    partyHealSpell = "",         -- Sag tik heal buyusu (bos = sinif varsayilani)
    partyShiftHealSpell = "",    -- Shift+Sol tik ikincil heal/dispel buyusu
    showQuestList = true,        -- Gorev penceresini goster/gizle
    panelCollapsed = false,      -- Gorev penceresi daraltilmis mi (ac/kapa)
    panelAlpha = 35,             -- Gorev penceresi arka plan opakligi (%10 - %95, dusuk = daha transparan)
    locked = false,              -- Cerceveleri kilitle
    weights = {
        distance = 40,           -- Yakinlik agirligi
        cluster = 25,            -- Birlikte yapilabilirlik agirligi
        xp = 20,                 -- Gorev XP agirligi
        completion = 35,         -- Tamamlanmaya yakinlik agirligi
    },
    colors = {
        near = { r = 0.20, g = 0.90, b = 0.25 }, -- < 100 m (Yesil)
        mid  = { r = 0.95, g = 0.85, b = 0.15 }, -- 100-300 m (Sari)
        far  = { r = 0.95, g = 0.20, b = 0.20 }, -- > 300 m (Kirmizi)
    },
    arrowPos = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -115,
    },
    nearbyPos = {
        point = "TOPRIGHT",
        relativePoint = "TOPRIGHT",
        x = -260,
        y = -220,
    },
    nearbySize = {
        width = 286,
        height = 380,
    },
    questItemPos = {
        point = "BOTTOM",
        relativePoint = "BOTTOM",
        x = 0,
        y = 170,
    },
    bannerPos = {
        point = "TOP",
        relativePoint = "TOP",
        x = 0,
        y = -68,
    },
    partyPos = {
        point = "LEFT",
        relativePoint = "LEFT",
        x = 18,
        y = 40,
    },
    partySize = {
        width = 188,
        unitHeight = 38,
    },
    threatPos = {
        point = "BOTTOMRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = -24,
        y = 140,
    },
    threatSize = {
        width = 248,
        height = 176,
    },
    layoutVersion = 3,
}

-- Aktif hedef durumu
ns.activeQuestID = nil
ns.activeTarget = nil

-- Hata mesajlarini throttle etmek icin (chat spam onleme)
local lastErrorTime = {}
local ERROR_THROTTLE_SEC = 30

-- Combat sonrasi calistirilacak UI isleri
local pendingCombatActions = {}

-- Modul arasi callback sistemi
local callbacks = {}

function ns:RegisterCallback(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then
        return
    end
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end

function ns:FireCallback(event, ...)
    local list = callbacks[event]
    if not list then
        return
    end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            self:PrintError("cb_" .. event, "Callback hatasi (" .. event .. "): " .. tostring(err))
        end
    end
end

function ns:Print(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[QuestGoToZ]|r " .. tostring(msg))
    end
end

function ns:PrintError(key, msg)
    local now = (type(GetTime) == "function") and GetTime() or 0
    if key and lastErrorTime[key] and (now - lastErrorTime[key]) < ERROR_THROTTLE_SEC then
        return
    end
    if key then
        lastErrorTime[key] = now
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[QuestGoToZ Hata]|r " .. tostring(msg))
    end
end

-- Midnight/Forever'da secret value veya nil donuslerine karsi sayi dogrulama
function ns:IsSafeNumber(val)
    if type(val) ~= "number" then
        return false
    end
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(val) then
        return false
    end
    if val ~= val then -- NaN kontrolu
        return false
    end
    return true
end

function ns:IsSafeString(val)
    if type(val) ~= "string" then
        return false
    end
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(val) then
        return false
    end
    return true
end

function ns:IsSafeBoolean(val)
    if type(val) ~= "boolean" then
        return false
    end
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(val) then
        return false
    end
    return true
end

local function DispatchPcallResult(self, errKey, label, ok, ...)
    if not ok then
        local err = ...
        self:PrintError(errKey, label .. " hatasi: " .. tostring(err))
        return false
    end
    return true, ...
end

-- Her C_* API cagrisi icin varlik kontrolu + pcall sarmalayici
-- Donus: ok (boolean), ... (API donus degerleri)
function ns:SafeC(nsName, fnName, ...)
    local tbl = _G[nsName]
    if type(tbl) ~= "table" then
        self:PrintError("missing_ns_" .. tostring(nsName), tostring(nsName) .. " API tablosu bulunamadi.")
        return false
    end
    local fn = tbl[fnName]
    if type(fn) ~= "function" then
        self:PrintError("missing_fn_" .. tostring(nsName) .. "_" .. tostring(fnName), tostring(nsName) .. "." .. tostring(fnName) .. " mevcut degil.")
        return false
    end
    return DispatchPcallResult(
        self,
        "err_" .. tostring(nsName) .. "_" .. tostring(fnName),
        tostring(nsName) .. "." .. tostring(fnName),
        pcall(fn, ...)
    )
end

-- Opsiyonel C_* kontrolu: fonksiyon yoksa chat'e hata basmadan false doner
function ns:TrySafeC(nsName, fnName, ...)
    local tbl = _G[nsName]
    if type(tbl) ~= "table" then
        return false
    end
    local fn = tbl[fnName]
    if type(fn) ~= "function" then
        return false
    end
    return DispatchPcallResult(
        self,
        "err_" .. tostring(nsName) .. "_" .. tostring(fnName),
        tostring(nsName) .. "." .. tostring(fnName),
        pcall(fn, ...)
    )
end

-- Global WoW fonksiyonlari icin guvenli cagri
function ns:SafeGlobal(fnName, ...)
    local fn = _G[fnName]
    if type(fn) ~= "function" then
        return false
    end
    return DispatchPcallResult(
        self,
        "err_global_" .. tostring(fnName),
        tostring(fnName),
        pcall(fn, ...)
    )
end

-- Combat lockdown kontrolu + combat cikisina erteleme
function ns:IsInCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

function ns:RunOutOfCombat(key, fn)
    if type(fn) ~= "function" then
        return
    end
    if self:IsInCombat() then
        pendingCombatActions[key] = fn
        return
    end
    local ok, err = pcall(fn)
    if not ok then
        self:PrintError("ooc_" .. tostring(key), "UI guncelleme hatasi: " .. tostring(err))
    end
end

-- Sessiz mod destekli guvenli ses calici
function ns:PlayAddonSound(soundID)
    if self.db and self.db.quietMode then
        return
    end
    if not self:IsSafeNumber(soundID) then
        return
    end
    self:SafeGlobal("PlaySound", soundID)
end

-- Tablo derin kopyalama / SavedVariables tamamlama
local function CopyDefaults(src, dst)
    if type(src) ~= "table" then
        return dst
    end
    if type(dst) ~= "table" then
        dst = {}
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function BuildPresetProfile(presetName)
    local p = CopyDefaults(ns.DEFAULTS, {})
    if presetName == "Hizli Leveling" then
        p.clusterRadius = 120
        p.autoSelectNearest = true
        p.autoTurnInRedirect = true
        p.weights.distance = 45
        p.weights.cluster = 35
        p.weights.xp = 25
        p.weights.completion = 40
    elseif presetName == "Sade" then
        p.showClusters = false
        p.showNearestServices = false
        p.bagFullVendorAlert = false
        p.quietMode = true
    end
    return p
end

function ns:InitDB()
    if type(QuestGoToZDB) ~= "table" then
        QuestGoToZDB = {}
    end

    -- Eski tek-profil yapisindan profilli yapiya kayipsiz gecis
    if type(QuestGoToZDB.profiles) ~= "table" then
        local legacy = {}
        for k, v in pairs(QuestGoToZDB) do
            if k ~= "profiles" and k ~= "activeProfile" then
                legacy[k] = v
            end
        end
        QuestGoToZDB.profiles = {
            ["Varsayilan"] = CopyDefaults(self.DEFAULTS, legacy),
            ["Hizli Leveling"] = BuildPresetProfile("Hizli Leveling"),
            ["Sade"] = BuildPresetProfile("Sade"),
        }
        QuestGoToZDB.activeProfile = "Varsayilan"
    end

    if not QuestGoToZDB.profiles["Varsayilan"] then
        QuestGoToZDB.profiles["Varsayilan"] = CopyDefaults(self.DEFAULTS, {})
    end

    local activeName = QuestGoToZDB.activeProfile
    if not self:IsSafeString(activeName) or type(QuestGoToZDB.profiles[activeName]) ~= "table" then
        activeName = "Varsayilan"
        QuestGoToZDB.activeProfile = activeName
    end

    local active = QuestGoToZDB.profiles[activeName]
    local prevVersion = active.layoutVersion or 1
    active = CopyDefaults(self.DEFAULTS, active)
    if prevVersion < 2 then
        active.arrowPos = CopyDefaults(self.DEFAULTS.arrowPos, {})
    end
    active.layoutVersion = self.DEFAULTS.layoutVersion
    QuestGoToZDB.profiles[activeName] = active

    self.db = active
    self.activeProfileName = activeName
end

function ns:GetProfileNames()
    local names = {}
    if type(QuestGoToZDB) == "table" and type(QuestGoToZDB.profiles) == "table" then
        for name in pairs(QuestGoToZDB.profiles) do
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function ns:SwitchProfile(profileName)
    if not self:IsSafeString(profileName) or type(QuestGoToZDB) ~= "table" or type(QuestGoToZDB.profiles) ~= "table" then
        return false
    end
    if type(QuestGoToZDB.profiles[profileName]) ~= "table" then
        return false
    end
    QuestGoToZDB.activeProfile = profileName
    QuestGoToZDB.profiles[profileName] = CopyDefaults(self.DEFAULTS, QuestGoToZDB.profiles[profileName])
    self.db = QuestGoToZDB.profiles[profileName]
    self.activeProfileName = profileName
    if self.Arrow then self.Arrow:ApplyPosition() end
    if self.Nearby then self.Nearby:ApplyPosition() end
    if self.Comfort then self.Comfort:ApplyQuestItemPosition() end
    if self.SmartQuest then self.SmartQuest:ApplyBannerPosition() end
    if self.PartyFrames then self.PartyFrames:ApplyPosition() end
    self:FireCallback("CONFIG_CHANGED")
    self:Print("Profil degistirildi: |cffffff00" .. profileName .. "|r")
    return true
end

function ns:CreateProfile(profileName)
    if not self:IsSafeString(profileName) then
        return false
    end
    profileName = strtrim and strtrim(profileName) or profileName:match("^%s*(.-)%s*$")
    if profileName == "" or type(QuestGoToZDB) ~= "table" or type(QuestGoToZDB.profiles) ~= "table" then
        return false
    end
    if QuestGoToZDB.profiles[profileName] then
        return self:SwitchProfile(profileName)
    end
    QuestGoToZDB.profiles[profileName] = CopyDefaults(self.db or self.DEFAULTS, {})
    return self:SwitchProfile(profileName)
end

function ns:DeleteProfile(profileName)
    if profileName == "Varsayilan" or type(QuestGoToZDB) ~= "table" or type(QuestGoToZDB.profiles) ~= "table" then
        return false
    end
    if not QuestGoToZDB.profiles[profileName] then
        return false
    end
    QuestGoToZDB.profiles[profileName] = nil
    if self.activeProfileName == profileName then
        self:SwitchProfile("Varsayilan")
    end
    return true
end

-- Oyuncunun guncel harita ID, koordinat (0-1) ve harita boyutunu (yarda) dondurur.
-- Instance vb. alanlarda C_Map.GetPlayerMapPosition nil donerse sessizce nil doner.
function ns:GetPlayerPosition()
    local okMap, mapID = self:SafeC("C_Map", "GetBestMapForUnit", "player")
    if not okMap or not self:IsSafeNumber(mapID) then
        return nil
    end

    local okPos, pos = self:SafeC("C_Map", "GetPlayerMapPosition", mapID, "player")
    if not okPos or not pos then
        return nil
    end

    local px, py
    if type(pos.GetXY) == "function" then
        local okXY, x, y = pcall(pos.GetXY, pos)
        if okXY then
            px, py = x, y
        end
    else
        px, py = pos.x, pos.y
    end

    if not self:IsSafeNumber(px) or not self:IsSafeNumber(py) then
        return nil
    end

    local okSize, width, height = self:SafeC("C_Map", "GetMapWorldSize", mapID)
    if not okSize or not self:IsSafeNumber(width) or not self:IsSafeNumber(height) or width <= 0 or height <= 0 then
        return mapID, px, py, nil, nil
    end

    return mapID, px, py, width, height
end

-- Harita adini cache'leyerek dondurur (ornegin "Westfall")
local mapNameCache = {}
function ns:GetMapName(mapID)
    if not self:IsSafeNumber(mapID) then
        return nil
    end
    if mapNameCache[mapID] then
        return mapNameCache[mapID]
    end
    local okInfo, info = self:TrySafeC("C_Map", "GetMapInfo", mapID)
    if okInfo and type(info) == "table" and self:IsSafeString(info.name) and info.name ~= "" then
        mapNameCache[mapID] = info.name
        return info.name
    end
    return nil
end

-- Bir gorevin Ana Gorev (Campaign / Main Story / Important) mi yoksa Yan Gorev mi oldugunu dondurur
function ns:IsMainQuest(questID, questInfo, mapID)
    if not self:IsSafeNumber(questID) or questID <= 0 then
        return false
    end

    -- 1) C_QuestLog.GetInfo icindeki dogrudan alanlar
    if type(questInfo) == "table" then
        if self:IsSafeNumber(questInfo.campaignID) and questInfo.campaignID > 0 then
            return true
        end
        if questInfo.isStory == true then
            return true
        end
    end

    -- 2) C_CampaignInfo.GetCampaignID(questID)
    local okCamp, campID = self:TrySafeC("C_CampaignInfo", "GetCampaignID", questID)
    if okCamp and self:IsSafeNumber(campID) and campID > 0 then
        return true
    end

    -- 3) C_QuestLog.IsImportantQuest(questID)
    local okImp, isImp = self:TrySafeC("C_QuestLog", "IsImportantQuest", questID)
    if okImp and isImp == true then
        return true
    end

    -- 4) C_QuestLine.GetQuestLineInfo(questID, mapID)
    if self:IsSafeNumber(mapID) then
        local okQL, qlInfo = self:TrySafeC("C_QuestLine", "GetQuestLineInfo", questID, mapID)
        if okQL and type(qlInfo) == "table" and (qlInfo.isCampaign == true or qlInfo.isImportant == true) then
            return true
        end
    end

    return false
end

local YARD_TO_METER = 0.9144

-- Iki harita koordinati arasindaki metre mesafesini ve hedef acisini (radyan, Kuzey=0, CCW) hesaplar
function ns:ComputeDistanceAndAngle(px, py, tx, ty, mapWidth, mapHeight)
    if not (self:IsSafeNumber(px) and self:IsSafeNumber(py)
        and self:IsSafeNumber(tx) and self:IsSafeNumber(ty)
        and self:IsSafeNumber(mapWidth) and self:IsSafeNumber(mapHeight)
        and mapWidth > 0 and mapHeight > 0) then
        return nil, nil
    end

    local dx = (tx - px) * mapWidth   -- Dogu +X (yarda)
    local dy = (py - ty) * mapHeight  -- Kuzey +Y (harita Y asagi artar, yarda)
    local distYards = math.sqrt(dx * dx + dy * dy)
    local distMeters = distYards * YARD_TO_METER
    local targetAngle = math.atan2(-dx, dy) -- Kuzey=0, Bati=+pi/2, Dogu=-pi/2 (WoW GetPlayerFacing uyumlu)
    return distMeters, targetAngle
end

-- Mesafeye gore ayarlanabilir renk dondurur (r, g, b)
function ns:GetColorForDistance(dist)
    local db = self.db or self.DEFAULTS
    local colors = db.colors or self.DEFAULTS.colors
    local nearT = db.nearThreshold or 100
    local farT = db.farThreshold or 300

    if not self:IsSafeNumber(dist) then
        local c = colors.mid
        return c.r, c.g, c.b
    end

    if dist > farT then
        local c = colors.far
        return c.r, c.g, c.b
    elseif dist >= nearT then
        local c = colors.mid
        return c.r, c.g, c.b
    else
        local c = colors.near
        return c.r, c.g, c.b
    end
end

-- Ana event cercevesi
local eventFrame = CreateFrame("Frame", "QuestGoToZEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_REMOVED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
eventFrame:RegisterEvent("USER_WAYPOINT_UPDATED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_UNGHOST")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
pcall(eventFrame.RegisterEvent, eventFrame, "QUESTLINE_UPDATE")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then
            ns:InitDB()
            ns:FireCallback("DB_READY")
        end
    elseif event == "PLAYER_LOGIN" then
        ns:FireCallback("PLAYER_LOGIN")
        ns:Print("Yuklendi (v" .. ns.version .. "). Ayarlar icin: |cffffff00/qgt|r")
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat bittiginde ertelenen UI guncellemelerini calistir
        local queue = pendingCombatActions
        pendingCombatActions = {}
        for key, fn in pairs(queue) do
            local ok, err = pcall(fn)
            if not ok then
                ns:PrintError("ooc_flush_" .. tostring(key), "Combat sonrasi UI hatasi: " .. tostring(err))
            end
        end
        ns:FireCallback("COMBAT_ENDED")
    else
        ns:FireCallback(event, ...)
    end
end)
