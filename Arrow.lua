local _, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local arrowFrame = nil
local minimapOverlay = nil
local updateTicker = nil

-- C_Minimap.GetViewRadius yoksa kullanilacak yedek yaricaplar (yarda)
local MINIMAP_RADIUS_OUTDOOR = { [0] = 233.33, [1] = 200.0, [2] = 166.67, [3] = 133.33, [4] = 100.0, [5] = 66.67 }
local MINIMAP_RADIUS_INDOOR  = { [0] = 150.0,  [1] = 120.0, [2] = 90.0,   [3] = 60.0,   [4] = 40.0,  [5] = 25.0 }

local function SaveArrowPosition(frame)
    if not ns.db or not frame then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then
        ns.db.arrowPos = {
            point = point,
            relativePoint = relativePoint or point,
            x = math.floor((x or 0) + 0.5),
            y = math.floor((y or 0) + 0.5),
        }
    end
end

function Arrow:ApplyPosition()
    if not arrowFrame or ns:IsInCombat() then
        return
    end
    local pos = (ns.db and ns.db.arrowPos) or ns.DEFAULTS.arrowPos
    arrowFrame:ClearAllPoints()
    arrowFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
end

function Arrow:UpdateLockState()
    if not arrowFrame or ns:IsInCombat() then
        return
    end
    local locked = ns.db and ns.db.locked
    arrowFrame:EnableMouse(not locked)
    arrowFrame:SetMovable(not locked)
end

-- Minimap gorunum yaricapini (yarda) dondurur
local function GetMinimapViewRadius()
    local okRad, rad = ns:TrySafeC("C_Minimap", "GetViewRadius")
    if okRad and ns:IsSafeNumber(rad) and rad > 0 then
        return rad
    end
    local zoom = (Minimap and type(Minimap.GetZoom) == "function") and Minimap:GetZoom() or 0
    local okCvar, indoor = ns:SafeGlobal("GetCVar", "minimapZoom")
    local isIndoor = (okCvar and indoor and tonumber(indoor) == zoom)
    local tbl = isIndoor and MINIMAP_RADIUS_INDOOR or MINIMAP_RADIUS_OUTDOOR
    return tbl[zoom] or 166.67
end

-- Minimap uzerinde hedefe dogru yesil yon cizgisi ve hedef halkasi olusturur
local function CreateMinimapOverlay()
    if minimapOverlay or not Minimap then
        return minimapOverlay
    end

    local f = CreateFrame("Frame", "QuestGoToZMinimapOverlay", Minimap)
    f:SetAllPoints(Minimap)
    f:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
    f:EnableMouse(false)

    -- Koyu alt cizgi (kontrast icin)
    local shadowLine = f:CreateLine(nil, "OVERLAY", nil, 1)
    shadowLine:SetThickness(4.5)
    shadowLine:SetColorTexture(0.0, 0.0, 0.0, 0.45)
    shadowLine:Hide()
    f.shadowLine = shadowLine

    -- Ana parlak yesil yon cizgisi
    local guideLine = f:CreateLine(nil, "OVERLAY", nil, 2)
    guideLine:SetThickness(2.4)
    guideLine:SetColorTexture(0.20, 1.0, 0.48, 0.92)
    guideLine:Hide()
    f.guideLine = guideLine

    -- Cizginin ucundaki hedef halkasi
    local targetRing = f:CreateTexture(nil, "OVERLAY", nil, 3)
    targetRing:SetSize(16, 16)
    targetRing:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    targetRing:SetBlendMode("ADD")
    targetRing:SetVertexColor(0.25, 1.0, 0.55, 0.95)
    targetRing:Hide()
    f.targetRing = targetRing

    -- Merkez hedef noktasi
    local targetDot = f:CreateTexture(nil, "OVERLAY", nil, 4)
    targetDot:SetSize(6, 6)
    targetDot:SetColorTexture(0.30, 1.0, 0.55, 1.0)
    targetDot:Hide()
    f.targetDot = targetDot

    minimapOverlay = f
    return f
end

local function HideMinimapGuide()
    if not minimapOverlay then
        return
    end
    minimapOverlay.shadowLine:Hide()
    minimapOverlay.guideLine:Hide()
    minimapOverlay.targetRing:Hide()
    minimapOverlay.targetDot:Hide()
end

-- Minimap uzerinde oyuncudan hedefe yesil cizgi cizer
local function UpdateMinimapGuide(dxYards, dyYards, facing)
    if not minimapOverlay then
        CreateMinimapOverlay()
    end
    if not minimapOverlay or not Minimap or not Minimap:IsShown() then
        HideMinimapGuide()
        return
    end

    local viewRadius = GetMinimapViewRadius()
    local mw = Minimap:GetWidth() or 140
    local mh = Minimap:GetHeight() or 140
    local pixelRadius = math.min(mw, mh) * 0.47
    if viewRadius <= 0 or pixelRadius <= 0 then
        HideMinimapGuide()
        return
    end

    -- Donen minimap (rotateMinimap=1) ayari aciksa vektoru oyuncu acisina gore dondur
    local vx, vy = dxYards, dyYards
    local okRot, rotCvar = ns:SafeGlobal("GetCVar", "rotateMinimap")
    if okRot and rotCvar == "1" and ns:IsSafeNumber(facing) then
        local c = math.cos(-facing)
        local s = math.sin(-facing)
        vx = dxYards * c - dyYards * s
        vy = dxYards * s + dyYards * c
    end

    local scale = pixelRadius / viewRadius
    local mx = vx * scale
    local my = vy * scale
    local pixDist = math.sqrt(mx * mx + my * my)

    -- Hedef minimap disindaysa cizgiyi dairesel minimap kenarina kelepcele
    if pixDist > pixelRadius then
        local ratio = pixelRadius / pixDist
        mx = mx * ratio
        my = my * ratio
    end

    -- Oyuncunun tam ustundeyse cizgiyi gizle
    if pixDist < 4 then
        HideMinimapGuide()
        return
    end

    minimapOverlay.shadowLine:SetStartPoint("CENTER", Minimap, 0, 0)
    minimapOverlay.shadowLine:SetEndPoint("CENTER", Minimap, mx, my)
    minimapOverlay.shadowLine:Show()

    minimapOverlay.guideLine:SetStartPoint("CENTER", Minimap, 0, 0)
    minimapOverlay.guideLine:SetEndPoint("CENTER", Minimap, mx, my)
    minimapOverlay.guideLine:Show()

    minimapOverlay.targetRing:ClearAllPoints()
    minimapOverlay.targetRing:SetPoint("CENTER", Minimap, "CENTER", mx, my)
    minimapOverlay.targetRing:Show()

    minimapOverlay.targetDot:ClearAllPoints()
    minimapOverlay.targetDot:SetPoint("CENTER", Minimap, "CENTER", mx, my)
    minimapOverlay.targetDot:Show()
end

-- Karakterin altinda sade, kutusuz, 3D derinlikli yon oku olusturur
local function CreateArrowFrame()
    if arrowFrame then
        return arrowFrame
    end

    local f = CreateFrame("Frame", "QuestGoToZArrowFrame", UIParent)
    f:SetSize(74, 78)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(selfFrame)
        if ns:IsInCombat() or (ns.db and ns.db.locked) then
            return
        end
        selfFrame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        SaveArrowPosition(selfFrame)
    end)

    -- Sag tik ile waypoint'i hizlica temizle
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            if ns:IsInCombat() then
                ns:Print("Combat sirasinda UI degisikligi engellendi.")
                return
            end
            ns:ClearQuestWaypoint(false)
        end
    end)

    -- Hover tooltip: gorev adi + hedef ilerlemesi (ekrani kalabaliklastirmadan)
    f:SetScript("OnEnter", function(selfFrame)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(selfFrame, "ANCHOR_TOP")
        local target = ns.activeTarget
        if target then
            local statusTag = target.isCorpse and " |cff88ccff(Ceset)|r"
                or (target.isTrainer and " |cffff88ff(Hizmet/Trainer)|r"
                or (target.isAvailable and " |cff33ccff(Alinabilir)|r"
                or (target.isComplete and " |cff33ff66(Teslim Hazir)|r" or "")))
            GameTooltip:SetText((target.title or "Gorev") .. statusTag, 1, 0.85, 0.2)
            local zoneName = target.zoneName or (target.mapID and ns:GetMapName(target.mapID))
            if zoneName then
                GameTooltip:AddLine("Bolge: " .. zoneName, 0.75, 0.85, 1.0)
            end

            if not target.isAvailable and not target.isComplete and ns:IsSafeNumber(target.questID) then
                local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", target.questID)
                if okObj and type(objectives) == "table" then
                    for i = 1, math.min(#objectives, 4) do
                        local obj = objectives[i]
                        if type(obj) == "table" and ns:IsSafeString(obj.text) and obj.text ~= "" then
                            if obj.finished then
                                GameTooltip:AddLine("- " .. obj.text, 0.35, 1.0, 0.4)
                            else
                                GameTooltip:AddLine("- " .. obj.text, 0.9, 0.9, 0.9)
                            end
                        end
                    end
                end
            end
        else
            GameTooltip:SetText("QuestGoToZ Yon Oku", 0.3, 0.85, 1.0)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Sol tik + surukle: Tasi | Sag tik: Temizle", 0.65, 0.72, 0.82)
        GameTooltip:Show()
    end)

    f:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- 1) 3D perspektif hissi veren hafif zemin halkasi (eliptik / yassi)
    local baseRing = f:CreateTexture(nil, "BACKGROUND")
    baseRing:SetSize(64, 24)
    baseRing:SetPoint("CENTER", f, "CENTER", 0, -6)
    baseRing:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    baseRing:SetBlendMode("ADD")
    baseRing:SetAlpha(0.30)
    f.baseRing = baseRing

    -- 2) 3D derinlik icin alt golge oku (hafif asagi kaydirilmis)
    local shadowTex = f:CreateTexture(nil, "BORDER")
    shadowTex:SetSize(58, 58)
    shadowTex:SetPoint("CENTER", f, "CENTER", 0, 2)
    shadowTex:SetTexture("Interface\\Minimap\\MinimapArrow")
    shadowTex:SetDesaturated(true)
    shadowTex:SetVertexColor(0.0, 0.0, 0.0, 0.65)
    f.shadowTex = shadowTex

    -- 3) Ana parlak yon oku (yukari hafif yukseltilmis 3D kabartma)
    local arrowTex = f:CreateTexture(nil, "ARTWORK")
    arrowTex:SetSize(56, 56)
    arrowTex:SetPoint("CENTER", f, "CENTER", 0, 7)
    arrowTex:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrowTex:SetDesaturated(true)
    f.arrowTex = arrowTex

    -- 4) Ust isik/parlama katmani (her zeminde net okunurluk)
    local glowTex = f:CreateTexture(nil, "OVERLAY")
    glowTex:SetSize(56, 56)
    glowTex:SetPoint("CENTER", f, "CENTER", 0, 7)
    glowTex:SetTexture("Interface\\Minimap\\MinimapArrow")
    glowTex:SetDesaturated(true)
    glowTex:SetBlendMode("ADD")
    glowTex:SetAlpha(0.28)
    f.glowTex = glowTex

    -- 4b) Hedefe <= 30 m kala donen ok yerine parlayan varis ikonu (Ozellik 7)
    local arrivalGlow = f:CreateTexture(nil, "ARTWORK")
    arrivalGlow:SetSize(52, 52)
    arrivalGlow:SetPoint("CENTER", f, "CENTER", 0, 7)
    arrivalGlow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    arrivalGlow:SetBlendMode("ADD")
    arrivalGlow:SetVertexColor(0.25, 1.0, 0.55, 0.90)
    arrivalGlow:Hide()
    f.arrivalGlow = arrivalGlow

    local arrivalIcon = f:CreateTexture(nil, "OVERLAY")
    arrivalIcon:SetSize(30, 30)
    arrivalIcon:SetPoint("CENTER", f, "CENTER", 0, 7)
    arrivalIcon:SetTexture("Interface\\COMMON\\Indicator-Green")
    arrivalIcon:Hide()
    f.arrivalIcon = arrivalIcon

    local ag = arrivalGlow:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local p1 = ag:CreateAnimation("Alpha")
    p1:SetFromAlpha(0.35)
    p1:SetToAlpha(0.95)
    p1:SetDuration(0.55)
    p1:SetOrder(1)
    local p2 = ag:CreateAnimation("Alpha")
    p2:SetFromAlpha(0.95)
    p2:SetToAlpha(0.35)
    p2:SetDuration(0.55)
    p2:SetOrder(2)
    f.arrivalAnim = ag

    -- 5) Sade, kalın konturlu mesafe yazisi (kutusuz)
    local distText = f:CreateFontString(nil, "OVERLAY")
    distText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    distText:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    distText:SetJustifyH("CENTER")
    distText:SetText("")
    f.distText = distText

    arrowFrame = f
    Arrow:ApplyPosition()
    Arrow:UpdateLockState()
    f:Hide()
    return f
end

local function HideAllGuidesSafely()
    HideMinimapGuide()
    if arrowFrame and arrowFrame:IsShown() and not ns:IsInCombat() then
        arrowFrame:Hide()
    end
end

function Arrow:UpdateOnce()
    if not arrowFrame then
        return
    end

    local target = ns.activeTarget
    if not target then
        HideAllGuidesSafely()
        return
    end

    -- Oyuncu konumu: instance vb. alanlarda nil donerse sessizce gizle
    local playerMapID, px, py, mapWidth, mapHeight = ns:GetPlayerPosition()
    if not playerMapID or not mapWidth then
        HideAllGuidesSafely()
        return
    end

    -- Oyuncu bakis acisi: instance vb. alanlarda nil donerse sessizce gizle
    local okFacing, facing = ns:SafeGlobal("GetPlayerFacing")
    if not okFacing or not ns:IsSafeNumber(facing) then
        HideAllGuidesSafely()
        return
    end

    local dxYards, dyYards, dist, targetAngle
    local tx, ty = target.x, target.y

    if target.mapID ~= playerMapID then
        local resolvedSameMap = false
        if not target.isAvailable and not target.isTrainer and ns:IsSafeNumber(target.questID) and target.questID > 0 then
            local refreshed = ns:GetQuestLocation(target.questID)
            if refreshed and refreshed.mapID == playerMapID then
                target = refreshed
                ns.activeTarget = refreshed
                tx, ty = refreshed.x, refreshed.y
                resolvedSameMap = true
            end
        end

        if not resolvedSameMap then
            -- Farkli haritada ama ayni kitadaysa GetWorldPosFromMapPos ile yon ve mesafe hesapla
            if type(_G.CreateVector2D) == "function" and ns:IsSafeNumber(target.mapID)
                and ns:IsSafeNumber(tx) and ns:IsSafeNumber(ty) then
                local okP, pCont, pWorld = ns:TrySafeC("C_Map", "GetWorldPosFromMapPos", playerMapID, _G.CreateVector2D(px, py))
                local okT, tCont, tWorld = ns:TrySafeC("C_Map", "GetWorldPosFromMapPos", target.mapID, _G.CreateVector2D(tx, ty))
                if okP and okT and pCont and tCont and pCont == tCont and pWorld and tWorld then
                    local dNorth = (tWorld.x or 0) - (pWorld.x or 0)
                    local dWest = (tWorld.y or 0) - (pWorld.y or 0)
                    dxYards = -dWest
                    dyYards = dNorth
                    dist = math.sqrt(dxYards * dxYards + dyYards * dyYards) * 0.9144
                    targetAngle = math.atan2(-dxYards, dyYards)
                end
            end
            if not dist or not targetAngle then
                HideAllGuidesSafely()
                return
            end
        end
    end

    if not dist or not targetAngle then
        dist, targetAngle = ns:ComputeDistanceAndAngle(px, py, tx, ty, mapWidth, mapHeight)
        if not dist or not targetAngle then
            HideAllGuidesSafely()
            return
        end
        dxYards = (tx - px) * mapWidth
        dyYards = (py - ty) * mapHeight
    end

    -- Minimap uzerinde hedefe yesil cizgiyi guncelle (combat disi/ici guvenli)
    UpdateMinimapGuide(dxYards, dyYards, facing)

    -- Okun gorunurlugunu yalnizca combat disinda ac
    if not arrowFrame:IsShown() then
        if ns:IsInCombat() then
            return
        end
        arrowFrame:Show()
    end

    -- Renk: Ceset ise buz-mavi, degilse mesafeye gore kirmizi/sari/yesil
    local r, g, b
    if target.isCorpse then
        r, g, b = 0.55, 0.85, 1.0
    else
        r, g, b = ns:GetColorForDistance(dist)
    end

    local db = ns.db or ns.DEFAULTS
    local arrivalRadius = db.arrivalRadius or 30

    if dist <= arrivalRadius then
        -- Ozellik 7: <= 30 m kala donen ok yerine parlayan varis ikonu
        arrowFrame.shadowTex:Hide()
        arrowFrame.arrowTex:Hide()
        arrowFrame.glowTex:Hide()
        arrowFrame.arrivalGlow:SetVertexColor(r, g, b, 0.90)
        arrowFrame.arrivalGlow:Show()
        arrowFrame.arrivalIcon:SetTexture(target.isCorpse and "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" or "Interface\\COMMON\\Indicator-Green")
        arrowFrame.arrivalIcon:Show()
        if arrowFrame.arrivalAnim and not arrowFrame.arrivalAnim:IsPlaying() then
            arrowFrame.arrivalAnim:Play()
        end
    else
        if arrowFrame.arrivalAnim and arrowFrame.arrivalAnim:IsPlaying() then
            arrowFrame.arrivalAnim:Stop()
        end
        arrowFrame.arrivalGlow:Hide()
        arrowFrame.arrivalIcon:Hide()
        arrowFrame.shadowTex:Show()
        arrowFrame.arrowTex:Show()
        arrowFrame.glowTex:Show()

        local relAngle = targetAngle - facing
        arrowFrame.shadowTex:SetRotation(relAngle)
        arrowFrame.arrowTex:SetRotation(relAngle)
        arrowFrame.glowTex:SetRotation(relAngle)
        arrowFrame.arrowTex:SetVertexColor(r, g, b, 1.0)
        arrowFrame.glowTex:SetVertexColor(r, g, b, 0.30)
    end

    arrowFrame.baseRing:SetVertexColor(r, g, b, 0.35)
    if dist >= 1000 then
        arrowFrame.distText:SetText(string.format("%.1f km", dist / 1000))
    else
        arrowFrame.distText:SetText(string.format("%d m", math.floor(dist + 0.5)))
    end
    arrowFrame.distText:SetTextColor(r, g, b)
end

function Arrow:StartTicker()
    if updateTicker then
        return
    end
    local ok, ticker = ns:SafeC("C_Timer", "NewTicker", 0.05, function()
        Arrow:UpdateOnce()
    end)
    if ok and ticker then
        updateTicker = ticker
    end
end

ns:RegisterCallback("PLAYER_LOGIN", function()
    CreateArrowFrame()
    CreateMinimapOverlay()
    Arrow:StartTicker()
end)

ns:RegisterCallback("TARGET_CHANGED", function()
    Arrow:UpdateOnce()
end)

ns:RegisterCallback("TARGET_UPDATED", function()
    Arrow:UpdateOnce()
end)

ns:RegisterCallback("CONFIG_CHANGED", function()
    Arrow:UpdateLockState()
    Arrow:UpdateOnce()
end)
