local _, ns = ...

local CombatText = {}
ns.CombatText = CombatText

local POOL_SIZE = 24
local pool = {}
local nextIndex = 1
local playerGUID = nil
local lastCLEUIncomingTime = 0
local lastCLEUHealTime = 0
local origHitPoints = setmetatable({}, { __mode = "k" })
local hookedHitObjs = setmetatable({}, { __mode = "k" })
local repositioningHit = false

-- Blizzard'in sol ustteki karakter portresi uzerindeki hasar/can gostergesini
-- gizlemek yerine ekranin ortasindaki karakterin ALTINA tasi (Midnight %100 secret-safe!)
local function GetPortraitHitTargets()
    local list = {}
    local pf = _G.PlayerFrame
    if type(pf) == "table" then
        local content = pf.PlayerFrameContent
        local main = content and content.PlayerFrameContentMain
        local hitInd = main and main.HitIndicator
        if hitInd then
            table.insert(list, hitInd)
            if hitInd.HitText then
                table.insert(list, hitInd.HitText)
            end
        end
    end
    if _G.PlayerHitIndicator then
        local dup = false
        for i = 1, #list do
            if list[i] == _G.PlayerHitIndicator then dup = true; break end
        end
        if not dup then
            table.insert(list, _G.PlayerHitIndicator)
        end
    end
    return list
end

local function ApplyPortraitHitIndicatorState()
    if ns:IsInCombat() then
        ns:RunOutOfCombat("combattext_hit_pos", ApplyPortraitHitIndicatorState)
        return
    end

    local db = ns.db or ns.DEFAULTS
    local moveUnderChar = (db and db.showCombatText) and true or false
    local targets = GetPortraitHitTargets()

    repositioningHit = true
    for i = 1, #targets do
        local obj = targets[i]
        if type(obj) == "table" then
            if type(obj.SetAlpha) == "function" then
                pcall(obj.SetAlpha, obj, 1)
            end
            if not origHitPoints[obj] and type(obj.GetPoint) == "function" then
                local okP, p, rel, rp, x, y = pcall(obj.GetPoint, obj, 1)
                if okP and p then
                    origHitPoints[obj] = { p, rel, rp, x or 0, y or 0 }
                end
            end

            if moveUnderChar then
                if type(obj.ClearAllPoints) == "function" and type(obj.SetPoint) == "function" then
                    pcall(obj.ClearAllPoints, obj)
                    pcall(obj.SetPoint, obj, "CENTER", UIParent, "CENTER", 0, -105)
                end
                if not hookedHitObjs[obj] and type(obj.SetPoint) == "function" then
                    hookedHitObjs[obj] = true
                    hooksecurefunc(obj, "SetPoint", function(selfObj)
                        if repositioningHit or ns:IsInCombat() then return end
                        local curDb = ns.db or ns.DEFAULTS
                        if not (curDb and curDb.showCombatText) then return end
                        repositioningHit = true
                        pcall(selfObj.ClearAllPoints, selfObj)
                        pcall(selfObj.SetPoint, selfObj, "CENTER", UIParent, "CENTER", 0, -105)
                        repositioningHit = false
                    end)
                end
            else
                local orig = origHitPoints[obj]
                if orig and type(obj.ClearAllPoints) == "function" and type(obj.SetPoint) == "function" then
                    pcall(obj.ClearAllPoints, obj)
                    pcall(obj.SetPoint, obj, orig[1], orig[2], orig[3], orig[4], orig[5])
                end
            end
        end
    end
    repositioningHit = false
end

local CRIT_ICON_TEX = "Interface\\Icons\\Ability_CriticalStrike"
local INCOMING_CRIT_ICON_TEX = "Interface\\Icons\\Ability_Warrior_Rampage"

local function FormatDamageNumber(num)
    if not ns:IsSafeNumber(num) then
        return "0"
    end
    local n = math.floor(num + 0.5)
    if n >= 1000000 then
        return string.format("%.2fM", n / 1000000)
    end
    local s = tostring(n)
    -- Binlik ayiraci (ornegin 1420 -> 1.420)
    local formatted = s:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
    return formatted
end

local function CreateSlot(index)
    local f = CreateFrame("Frame", "QuestGoToZCombatText" .. index, UIParent)
    f:SetSize(220, 46)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)

    -- Ana hasar yazisi (kalin siyah dis cizgili, Metin2 tarzi belirgin)
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 22, "THICKOUTLINE")
    text:SetShadowColor(0, 0, 0, 1.0)
    text:SetShadowOffset(2, -2)
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    f.text = text

    -- Kritiklerde sol altta gorunen ikon + parlama
    local iconGlow = f:CreateTexture(nil, "ARTWORK")
    iconGlow:SetSize(28, 28)
    iconGlow:SetPoint("BOTTOMRIGHT", text, "BOTTOMLEFT", -2, -3)
    iconGlow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    iconGlow:SetBlendMode("ADD")
    iconGlow:SetVertexColor(1.0, 0.55, 0.05, 0.95)
    iconGlow:Hide()
    f.iconGlow = iconGlow

    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", iconGlow, "CENTER", 0, 0)
    icon:SetTexture(CRIT_ICON_TEX)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    f.icon = icon

    -- GPU hizlandirmali animasyon (OnUpdate olmadan 0 FPS maliyeti)
    local ag = f:CreateAnimationGroup()

    local popUp = ag:CreateAnimation("Scale")
    popUp:SetOrder(1)
    popUp:SetDuration(0.11)
    if popUp.SetScaleFrom then
        popUp:SetScaleFrom(0.55, 0.55)
        popUp:SetScaleTo(1.30, 1.30)
    else
        popUp:SetScale(1.30, 1.30)
    end
    f.popUp = popUp

    local popSettle = ag:CreateAnimation("Scale")
    popSettle:SetOrder(2)
    popSettle:SetDuration(0.10)
    if popSettle.SetScaleFrom then
        popSettle:SetScaleFrom(1.30, 1.30)
        popSettle:SetScaleTo(1.0, 1.0)
    else
        popSettle:SetScale(0.77, 0.77)
    end
    f.popSettle = popSettle

    local move = ag:CreateAnimation("Translation")
    move:SetOrder(1)
    move:SetDuration(1.05)
    move:SetOffset(0, 92)
    f.move = move

    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetOrder(1)
    fadeOut:SetStartDelay(0.65)
    fadeOut:SetDuration(0.40)
    fadeOut:SetFromAlpha(1.0)
    fadeOut:SetToAlpha(0.0)
    f.fadeOut = fadeOut

    ag:SetScript("OnFinished", function()
        f:Hide()
    end)
    f.anim = ag

    f:Hide()
    return f
end

local function InitPool()
    if #pool > 0 then
        return
    end
    for i = 1, POOL_SIZE do
        pool[i] = CreateSlot(i)
    end
end

-- kind: "normal" | "crit" | "incoming" | "incoming_crit" | "heal" | "heal_crit"
function CombatText:Spawn(amount, kind)
    local db = ns.db or ns.DEFAULTS
    if not db.showCombatText then
        return
    end
    if not ns:IsSafeNumber(amount) or amount <= 0 then
        return
    end
    if #pool == 0 then
        InitPool()
    end

    local slot = pool[nextIndex]
    nextIndex = (nextIndex % POOL_SIZE) + 1

    slot.anim:Stop()
    slot:SetAlpha(1.0)
    slot:ClearAllPoints()

    local formatted = FormatDamageNumber(amount)

    if kind == "crit" then
        -- Metin2 tarzi dev turuncu-altin kritik + sol altta kritik ikonu
        local rx = math.random(55, 130)
        local ry = math.random(35, 85)
        slot:SetPoint("CENTER", UIParent, "CENTER", rx, ry)
        slot.text:SetFont("Fonts\\FRIZQT__.TTF", 32, "THICKOUTLINE")
        slot.text:SetTextColor(1.0, 0.74, 0.08)
        slot.text:SetText(formatted .. "!")
        slot.icon:SetTexture(CRIT_ICON_TEX)
        slot.iconGlow:SetVertexColor(1.0, 0.55, 0.05, 0.95)
        slot.iconGlow:Show()
        slot.icon:Show()
        slot.move:SetDuration(1.18)
        slot.move:SetOffset(math.random(-14, 18), 115)
        slot.fadeOut:SetStartDelay(0.75)
        slot.fadeOut:SetDuration(0.43)
    elseif kind == "incoming" or kind == "incoming_crit" then
        -- Alinan hasar: ekranin ortasindaki karakterin altinda (hafif sol) KIRMIZI
        local isCritIn = (kind == "incoming_crit")
        local rx = math.random(-72, -16)
        local ry = math.random(-118, -82)
        slot:SetPoint("CENTER", UIParent, "CENTER", rx, ry)
        slot.text:SetFont("Fonts\\FRIZQT__.TTF", isCritIn and 26 or 20, "THICKOUTLINE")
        slot.text:SetTextColor(1.0, 0.18, 0.18)
        slot.text:SetText("-" .. formatted .. (isCritIn and "!" or ""))
        if isCritIn then
            slot.icon:SetTexture(INCOMING_CRIT_ICON_TEX)
            slot.iconGlow:SetVertexColor(1.0, 0.12, 0.12, 0.95)
            slot.iconGlow:Show()
            slot.icon:Show()
        else
            slot.iconGlow:Hide()
            slot.icon:Hide()
        end
        slot.move:SetDuration(0.95)
        slot.move:SetOffset(math.random(-14, -2), -56)
        slot.fadeOut:SetStartDelay(0.55)
        slot.fadeOut:SetDuration(0.40)
    elseif kind == "heal" or kind == "heal_crit" then
        -- Alinan can (heal): ekranin ortasindaki karakterin altinda (hafif sag) YESIL
        local isCritHeal = (kind == "heal_crit")
        local rx = math.random(16, 72)
        local ry = math.random(-118, -82)
        slot:SetPoint("CENTER", UIParent, "CENTER", rx, ry)
        slot.text:SetFont("Fonts\\FRIZQT__.TTF", isCritHeal and 25 or 19, "THICKOUTLINE")
        slot.text:SetTextColor(0.22, 0.96, 0.42)
        slot.text:SetText("+" .. formatted .. (isCritHeal and "!" or ""))
        slot.iconGlow:Hide()
        slot.icon:Hide()
        slot.move:SetDuration(0.95)
        slot.move:SetOffset(math.random(2, 14), -48)
        slot.fadeOut:SetStartDelay(0.55)
        slot.fadeOut:SetDuration(0.40)
    else
        -- Normal vurulan hasar: sag-ustte parlak acik altin/beyaz
        local rx = math.random(50, 120)
        local ry = math.random(10, 55)
        slot:SetPoint("CENTER", UIParent, "CENTER", rx, ry)
        slot.text:SetFont("Fonts\\FRIZQT__.TTF", 22, "THICKOUTLINE")
        slot.text:SetTextColor(1.0, 0.96, 0.78)
        slot.text:SetText(formatted)
        slot.iconGlow:Hide()
        slot.icon:Hide()
        slot.move:SetDuration(0.92)
        slot.move:SetOffset(math.random(-12, 16), 88)
        slot.fadeOut:SetStartDelay(0.55)
        slot.fadeOut:SetDuration(0.37)
    end

    slot:Show()
    slot.anim:Play()
end

local function OnCombatLogEvent()
    local db = ns.db or ns.DEFAULTS
    if not db.showCombatText then
        return
    end

    if not playerGUID then
        local okG, g = ns:SafeGlobal("UnitGUID", "player")
        if okG and ns:IsSafeString(g) then
            playerGUID = g
        else
            return
        end
    end

    local okInfo, _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, arg12, _, _, arg15, _, _, arg18, _, _, arg21 =
        ns:SafeGlobal("CombatLogGetCurrentEventInfo")
    if not okInfo or not ns:IsSafeString(subevent) then
        return
    end

    local amount, isCrit
    if subevent == "SWING_DAMAGE" then
        amount = arg12
        isCrit = (arg18 == true)
    elseif subevent == "RANGE_DAMAGE" or subevent == "SPELL_DAMAGE"
        or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "DAMAGE_SHIELD" then
        amount = arg15
        isCrit = (arg21 == true)
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        -- Alinan can (heal): sadece oyuncuya gelen iyilestirme
        if ns:IsSafeString(destGUID) and destGUID == playerGUID and ns:IsSafeNumber(arg15) and arg15 > 0 then
            lastCLEUHealTime = (type(GetTime) == "function") and GetTime() or 0
            CombatText:Spawn(arg15, (arg18 == true) and "heal_crit" or "heal")
        end
        return
    else
        return
    end

    if not ns:IsSafeNumber(amount) or amount <= 0 then
        return
    end

    -- 1) Oyuncunun (veya petinin) vurdugu hasar
    local isFromPlayer = (ns:IsSafeString(sourceGUID) and sourceGUID == playerGUID)
    if not isFromPlayer and ns:IsSafeString(sourceGUID) then
        local okPet, petGUID = ns:SafeGlobal("UnitGUID", "pet")
        if okPet and ns:IsSafeString(petGUID) and sourceGUID == petGUID then
            isFromPlayer = true
        end
    end

    if isFromPlayer and (not ns:IsSafeString(destGUID) or destGUID ~= playerGUID) then
        CombatText:Spawn(amount, isCrit and "crit" or "normal")
        return
    end

    -- 2) Oyuncunun aldigi hasar (kirmizi)
    if ns:IsSafeString(destGUID) and destGUID == playerGUID then
        lastCLEUIncomingTime = (type(GetTime) == "function") and GetTime() or 0
        CombatText:Spawn(amount, isCrit and "incoming_crit" or "incoming")
    end
end

-- Yedek alinan hasar ve can yakalayici (CLEU gelmezse UNIT_COMBAT ile gosterir)
local function OnUnitCombat(unit, action, descriptor, amount)
    local db = ns.db or ns.DEFAULTS
    if not db.showCombatText or unit ~= "player" then
        return
    end
    if not ns:IsSafeNumber(amount) or amount <= 0 then
        return
    end
    local now = (type(GetTime) == "function") and GetTime() or 0
    local isCrit = (ns:IsSafeString(descriptor) and descriptor == "CRITICAL")

    if action == "WOUND" then
        if (now - lastCLEUIncomingTime) < 0.08 then
            return
        end
        CombatText:Spawn(amount, isCrit and "incoming_crit" or "incoming")
    elseif action == "HEAL" then
        if (now - lastCLEUHealTime) < 0.08 then
            return
        end
        CombatText:Spawn(amount, isCrit and "heal_crit" or "heal")
    end
end

-- /frkn testdmg ile savas disinda hemen onizleme yapma
function CombatText:RunTest()
    self:Spawn(1245, "normal")
    ns:TrySafeC("C_Timer", "After", 0.25, function()
        CombatText:Spawn(3890, "crit")
    end)
    ns:TrySafeC("C_Timer", "After", 0.50, function()
        CombatText:Spawn(640, "incoming")
    end)
    ns:TrySafeC("C_Timer", "After", 0.70, function()
        CombatText:Spawn(950, "heal")
    end)
    ns:TrySafeC("C_Timer", "After", 0.95, function()
        CombatText:Spawn(1520, "incoming_crit")
    end)
    ns:TrySafeC("C_Timer", "After", 1.15, function()
        CombatText:Spawn(2150, "heal_crit")
    end)
end

local combatEventFrame = CreateFrame("Frame", "QuestGoToZCombatTextEventFrame")
combatEventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatEventFrame:RegisterEvent("UNIT_COMBAT")
combatEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
combatEventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent()
    elseif event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ApplyPortraitHitIndicatorState()
    end
end)

ns:RegisterCallback("PLAYER_LOGIN", function()
    InitPool()
    ApplyPortraitHitIndicatorState()
    local okG, g = ns:SafeGlobal("UnitGUID", "player")
    if okG and ns:IsSafeString(g) then
        playerGUID = g
    end
end)

ns:RegisterCallback("CONFIG_CHANGED", function()
    ApplyPortraitHitIndicatorState()
end)
