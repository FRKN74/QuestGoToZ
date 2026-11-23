local _, ns = ...

local PartyFrames = {}
ns.PartyFrames = PartyFrames

local FRAME_WIDTH = 188
local TOP_PADDING = 4
local BOTTOM_RESIZE_PAD = 10
local UNIT_HEIGHT = 38
local UNIT_GAP = 4
local MIN_WIDTH, MAX_WIDTH = 140, 360
local MIN_UNIT_H, MAX_UNIT_H = 28, 72
local UNITS = { "player", "party1", "party2", "party3", "party4" }

local DEFAULT_HEAL_BY_CLASS = {
    PRIEST  = "Flash Heal",
    PALADIN = "Flash of Light",
    DRUID   = "Regrowth",
    SHAMAN  = "Healing Surge",
    MONK    = "Vivify",
    EVOKER  = "Living Flame",
}

local POWER_COLORS = {
    [0] = { 0.16, 0.50, 0.96 }, -- Mana
    [1] = { 0.88, 0.22, 0.22 }, -- Rage
    [2] = { 0.96, 0.52, 0.20 }, -- Focus
    [3] = { 0.96, 0.88, 0.20 }, -- Energy
    [6] = { 0.22, 0.80, 0.96 }, -- Runic Power
}

local containerFrame = nil
local unitButtons = {}
local updateTicker = nil
local currentVisibleCount = 1
local isResizing = false

local function GetPartyDimensions()
    local db = ns.db or ns.DEFAULTS
    local sz = (db and db.partySize) or ns.DEFAULTS.partySize
    local w = (sz and ns:IsSafeNumber(sz.width)) and sz.width or FRAME_WIDTH
    local uh = (sz and ns:IsSafeNumber(sz.unitHeight)) and sz.unitHeight or UNIT_HEIGHT
    w = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.floor(w + 0.5)))
    uh = math.max(MIN_UNIT_H, math.min(MAX_UNIT_H, math.floor(uh + 0.5)))
    return w, uh
end

local function ApplyButtonDimensions(btn, w, uh)
    if not btn then return end
    btn:SetSize(w - 10, uh)
    local mpH = math.max(5, math.min(16, math.floor(uh * 0.22)))
    local hpH = math.max(14, uh - mpH - 6)
    if btn.hpBar then
        btn.hpBar:SetHeight(hpH)
    end
    if btn.mpBar then
        btn.mpBar:SetHeight(mpH)
    end
    local nameSize = math.max(10, math.min(16, math.floor(uh * 0.30)))
    local hpSize = math.max(9, math.min(15, math.floor(uh * 0.27)))
    if btn.nameText then
        btn.nameText:SetFont("Fonts\\ARIALN.TTF", nameSize, "")
    end
    if btn.hpText then
        btn.hpText:SetFont("Fonts\\ARIALN.TTF", hpSize, "")
    end
end

local isSecretFn = _G.issecretvalue
local function IsSecret(v)
    return (type(isSecretFn) == "function") and isSecretFn(v) or false
end

-- Midnight secret-safe dusuk can (<%40) egrisi (C++ tarafinda 0 veya 1 alpha dondurur)
local lowHpAlphaCurve = nil
local function GetLowHpCurve()
    if lowHpAlphaCurve ~= nil then
        return lowHpAlphaCurve
    end
    if type(_G.C_CurveUtil) == "table" and type(_G.C_CurveUtil.CreateCurve) == "function" then
        local ok, curve = pcall(_G.C_CurveUtil.CreateCurve)
        if ok and curve and type(curve.AddPoint) == "function" then
            pcall(curve.AddPoint, curve, 0.0, 1.0)
            pcall(curve.AddPoint, curve, 0.39, 1.0)
            pcall(curve.AddPoint, curve, 0.40, 0.0)
            pcall(curve.AddPoint, curve, 1.0, 0.0)
            lowHpAlphaCurve = curve
            return lowHpAlphaCurve
        end
    end
    lowHpAlphaCurve = false
    return false
end

function PartyFrames:GetActiveHealSpell()
    if ns.db and ns:IsSafeString(ns.db.partyHealSpell) and ns.db.partyHealSpell ~= "" then
        return ns.db.partyHealSpell
    end
    local okCls, _, classFile = ns:SafeGlobal("UnitClass", "player")
    if okCls and ns:IsSafeString(classFile) and DEFAULT_HEAL_BY_CLASS[classFile] then
        return DEFAULT_HEAL_BY_CLASS[classFile]
    end
    return ""
end

function PartyFrames:GetShiftHealSpell()
    if ns.db and ns:IsSafeString(ns.db.partyShiftHealSpell) and ns.db.partyShiftHealSpell ~= "" then
        return ns.db.partyShiftHealSpell
    end
    return ""
end

local function SavePosition(frame)
    if not ns.db or not frame then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then
        ns.db.partyPos = {
            point = point,
            relativePoint = relativePoint or point,
            x = math.floor((x or 0) + 0.5),
            y = math.floor((y or 0) + 0.5),
        }
    end
end

function PartyFrames:ApplyPosition()
    if not containerFrame or ns:IsInCombat() then
        return
    end
    local pos = (ns.db and ns.db.partyPos) or ns.DEFAULTS.partyPos
    containerFrame:ClearAllPoints()
    containerFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    self:ApplyAppearance()
    self:RebuildLayout()
end

function PartyFrames:ApplyAppearance()
    if not containerFrame then
        return
    end
    local db = ns.db or ns.DEFAULTS
    local pct = ns:IsSafeNumber(db.panelAlpha) and db.panelAlpha or 35
    local a = math.max(0.10, math.min(0.92, pct / 100))
    containerFrame:SetBackdropColor(0.03, 0.05, 0.09, a)
    containerFrame:SetBackdropBorderColor(1.0, 1.0, 1.0, math.min(0.28, a * 0.45 + 0.06))
end

function PartyFrames:UpdateLockState()
    if not containerFrame or ns:IsInCombat() then
        return
    end
    local locked = ns.db and ns.db.locked
    containerFrame:SetMovable(not locked)
    if containerFrame.resizeBtn then
        containerFrame.resizeBtn:SetShown(not locked)
    end
end

local function GetUnitClassColor(unit)
    local okCls, _, classFile = ns:SafeGlobal("UnitClass", unit)
    if okCls and ns:IsSafeString(classFile) and type(_G.RAID_CLASS_COLORS) == "table" and _G.RAID_CLASS_COLORS[classFile] then
        local c = _G.RAID_CLASS_COLORS[classFile]
        return c.r or 0.25, c.g or 0.80, c.b or 0.35
    end
    return 0.25, 0.80, 0.35
end

local function GetRoleBadge(unit)
    local okR, role = ns:SafeGlobal("UnitGroupRolesAssigned", unit)
    if okR and ns:IsSafeString(role) then
        if role == "TANK" then
            return "|cff44aaff[T]|r "
        elseif role == "HEALER" then
            return "|cff33ff66[H]|r "
        end
    end
    return ""
end

-- Resmi SecureUnitButtonTemplate: Sol tik = Hedef, Sag tik = Heal, Shift+Sol = Ikincil Heal
local function CreateUnitButton(parent, unit, index)
    local btn = CreateFrame("Button", "QuestGoToZPartyUnit" .. index, parent, "SecureUnitButtonTemplate,BackdropTemplate")
    btn:SetSize(FRAME_WIDTH - 10, UNIT_HEIGHT)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -(TOP_PADDING + (index - 1) * (UNIT_HEIGHT + UNIT_GAP)))
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("type1", "target")

    -- Modern 1 px ince kenarlikli transparan kart
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(0.03, 0.05, 0.09, 0.55)
    btn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.14)

    -- Secili (target) uye icin belirgin 2 px parlak YESIL dis cerceve
    local selBorder = CreateFrame("Frame", nil, btn)
    selBorder:SetAllPoints(btn)
    selBorder:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
    selBorder:EnableMouse(false)
    local t = 2
    local sr, sg, sb, sa = 0.20, 1.0, 0.38, 1.0
    local sTop = selBorder:CreateTexture(nil, "OVERLAY")
    sTop:SetPoint("TOPLEFT", selBorder, "TOPLEFT", 0, 0)
    sTop:SetPoint("TOPRIGHT", selBorder, "TOPRIGHT", 0, 0)
    sTop:SetHeight(t)
    sTop:SetColorTexture(sr, sg, sb, sa)
    local sBot = selBorder:CreateTexture(nil, "OVERLAY")
    sBot:SetPoint("BOTTOMLEFT", selBorder, "BOTTOMLEFT", 0, 0)
    sBot:SetPoint("BOTTOMRIGHT", selBorder, "BOTTOMRIGHT", 0, 0)
    sBot:SetHeight(t)
    sBot:SetColorTexture(sr, sg, sb, sa)
    local sLeft = selBorder:CreateTexture(nil, "OVERLAY")
    sLeft:SetPoint("TOPLEFT", selBorder, "TOPLEFT", 0, -t)
    sLeft:SetPoint("BOTTOMLEFT", selBorder, "BOTTOMLEFT", 0, t)
    sLeft:SetWidth(t)
    sLeft:SetColorTexture(sr, sg, sb, sa)
    local sRight = selBorder:CreateTexture(nil, "OVERLAY")
    sRight:SetPoint("TOPRIGHT", selBorder, "TOPRIGHT", 0, -t)
    sRight:SetPoint("BOTTOMRIGHT", selBorder, "BOTTOMRIGHT", 0, t)
    sRight:SetWidth(t)
    sRight:SetColorTexture(sr, sg, sb, sa)
    selBorder:Hide()
    btn.selBorder = selBorder

    -- Cani az (<%40) uyeler icin kirmizi yanip sonen uyari katmani (GPU AnimationGroup)
    local lowHpHolder = CreateFrame("Frame", nil, btn)
    lowHpHolder:SetAllPoints(btn)
    lowHpHolder:SetFrameLevel((btn:GetFrameLevel() or 1) + 4)
    lowHpHolder:EnableMouse(false)

    local lowBg = lowHpHolder:CreateTexture(nil, "OVERLAY")
    lowBg:SetAllPoints(lowHpHolder)
    lowBg:SetColorTexture(1.0, 0.08, 0.08, 0.45)

    local lowAnim = lowBg:CreateAnimationGroup()
    lowAnim:SetLooping("REPEAT")
    local a1 = lowAnim:CreateAnimation("Alpha")
    a1:SetFromAlpha(0.10)
    a1:SetToAlpha(0.85)
    a1:SetDuration(0.40)
    a1:SetOrder(1)
    local a2 = lowAnim:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.85)
    a2:SetToAlpha(0.10)
    a2:SetDuration(0.40)
    a2:SetOrder(2)
    lowAnim:Play()

    lowHpHolder:Hide()
    btn.lowHpHolder = lowHpHolder

    -- Can bari (ustte 23 px)
    local hpBar = CreateFrame("StatusBar", nil, btn)
    hpBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    hpBar:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
    hpBar:SetHeight(23)
    hpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    hpBar:SetMinMaxValues(0, 1)
    hpBar:SetValue(1)

    local hpBg = hpBar:CreateTexture(nil, "BACKGROUND")
    hpBg:SetAllPoints()
    hpBg:SetColorTexture(0.06, 0.08, 0.12, 0.72)

    local nameText = hpBar:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\ARIALN.TTF", 11, "")
    nameText:SetShadowColor(0, 0, 0, 1.0)
    nameText:SetShadowOffset(1, -1)
    nameText:SetPoint("LEFT", hpBar, "LEFT", 4, 0)
    nameText:SetPoint("RIGHT", hpBar, "RIGHT", -40, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    btn.nameText = nameText

    local hpText = hpBar:CreateFontString(nil, "OVERLAY")
    hpText:SetFont("Fonts\\ARIALN.TTF", 10, "")
    hpText:SetShadowColor(0, 0, 0, 1.0)
    hpText:SetShadowOffset(1, -1)
    hpText:SetPoint("RIGHT", hpBar, "RIGHT", -4, 0)
    hpText:SetJustifyH("RIGHT")
    btn.hpText = hpText
    btn.hpBar = hpBar

    -- Mana / Guc bari (altta 8 px)
    local mpBar = CreateFrame("StatusBar", nil, btn)
    mpBar:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, -2)
    mpBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, -2)
    mpBar:SetHeight(8)
    mpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    mpBar:SetMinMaxValues(0, 1)
    mpBar:SetValue(1)

    local mpBg = mpBar:CreateTexture(nil, "BACKGROUND")
    mpBg:SetAllPoints()
    mpBg:SetColorTexture(0.04, 0.06, 0.10, 0.80)
    btn.mpBar = mpBar

    -- Hover vurgusu
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)

    btn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        local okN, uName = ns:SafeGlobal("UnitName", unit)
        local okL, uLvl = ns:SafeGlobal("UnitLevel", unit)
        local lvlPart = (okL and ns:IsSafeNumber(uLvl) and uLvl > 0) and (" (Lv " .. uLvl .. ")") or ""
        GameTooltip:SetText(((okN and ns:IsSafeString(uName)) and uName or unit) .. lvlPart, 1, 0.85, 0.2)
        GameTooltip:AddLine("Sol tik: Hedef al", 0.85, 0.88, 0.94)
        local heal = PartyFrames:GetActiveHealSpell()
        if heal ~= "" then
            GameTooltip:AddLine("Sag tik: " .. heal, 0.30, 1.0, 0.45)
        end
        local sHeal = PartyFrames:GetShiftHealSpell()
        if sHeal ~= "" then
            GameTooltip:AddLine("Shift + Sol tik: " .. sHeal, 0.45, 0.85, 1.0)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    btn.unit = unit
    btn:Hide()
    return btn
end

local function CreatePartyContainer()
    if containerFrame then
        return containerFrame
    end

    local f = CreateFrame("Frame", "QuestGoToZPartyFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_WIDTH, TOP_PADDING + BOTTOM_RESIZE_PAD + UNIT_HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_WIDTH, TOP_PADDING + BOTTOM_RESIZE_PAD + MIN_UNIT_H, MAX_WIDTH, TOP_PADDING + BOTTOM_RESIZE_PAD + 5 * MAX_UNIT_H + 4 * UNIT_GAP)
    elseif f.SetMinResize then
        f:SetMinResize(MIN_WIDTH, TOP_PADDING + BOTTOM_RESIZE_PAD + MIN_UNIT_H)
        f:SetMaxResize(MAX_WIDTH, TOP_PADDING + BOTTOM_RESIZE_PAD + 5 * MAX_UNIT_H + 4 * UNIT_GAP)
    end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.03, 0.05, 0.09, 0.35)
    f:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.18)

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(selfFrame)
        if ns:IsInCombat() or (ns.db and ns.db.locked) then
            return
        end
        selfFrame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        if ns:IsInCombat() then
            return
        end
        selfFrame:StopMovingOrSizing()
        SavePosition(selfFrame)
    end)

    -- Canli boyutlandirma: suruklerken tum uye kartlari anlik buyuyup kuculur
    f:SetScript("OnSizeChanged", function(selfFrame, newW, newH)
        if not isResizing or ns:IsInCombat() then
            return
        end
        local cnt = math.max(1, currentVisibleCount)
        local w = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.floor((newW or FRAME_WIDTH) + 0.5)))
        local availH = (newH or 50) - TOP_PADDING - BOTTOM_RESIZE_PAD - (cnt - 1) * UNIT_GAP
        local uh = math.max(MIN_UNIT_H, math.min(MAX_UNIT_H, math.floor((availH / cnt) + 0.5)))
        local shownIdx = 0
        for i = 1, #unitButtons do
            local btn = unitButtons[i]
            if btn and btn:IsShown() then
                shownIdx = shownIdx + 1
                ApplyButtonDimensions(btn, w, uh)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", selfFrame, "TOPLEFT", 5, -(TOP_PADDING + (shownIdx - 1) * (uh + UNIT_GAP)))
            end
        end
    end)

    for i = 1, #UNITS do
        unitButtons[i] = CreateUnitButton(f, UNITS[i], i)
    end

    -- Sag-alt yeniden boyutlandirma tutamaci (Gorev listesi ile ayni)
    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(12, 12)
    resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    resizeBtn:SetFrameLevel((f:GetFrameLevel() or 1) + 10)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        if ns:IsInCombat() or (ns.db and ns.db.locked) then return end
        isResizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        if not isResizing then return end
        isResizing = false
        f:StopMovingOrSizing()
        if ns:IsInCombat() then return end
        local newW, newH = f:GetSize()
        local cnt = math.max(1, currentVisibleCount)
        local w = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.floor((newW or FRAME_WIDTH) + 0.5)))
        local availH = (newH or 50) - TOP_PADDING - BOTTOM_RESIZE_PAD - (cnt - 1) * UNIT_GAP
        local uh = math.max(MIN_UNIT_H, math.min(MAX_UNIT_H, math.floor((availH / cnt) + 0.5)))
        if ns.db then
            ns.db.partySize = { width = w, unitHeight = uh }
        end
        PartyFrames:RebuildLayout()
    end)
    f.resizeBtn = resizeBtn

    containerFrame = f
    PartyFrames:ApplyPosition()
    PartyFrames:UpdateLockState()
    f:Hide()
    return f
end

-- Tum SecureAttribute ve Show/Hide islemleri YALNIZCA savas disinda yapilir
function PartyFrames:RebuildLayout()
    if not containerFrame then
        return
    end

    ns:RunOutOfCombat("party_frames_rebuild", function()
        local db = ns.db or ns.DEFAULTS
        if not db.showPartyFrames then
            containerFrame:Hide()
            return
        end

        local okGrp, inGroup = ns:SafeGlobal("IsInGroup")
        local isGrouped = (okGrp and ns:IsSafeBoolean(inGroup) and inGroup) or false
        if not isGrouped and not db.partyShowSolo then
            containerFrame:Hide()
            return
        end

        local healSpell = PartyFrames:GetActiveHealSpell()
        local shiftSpell = PartyFrames:GetShiftHealSpell()
        local w, uh = GetPartyDimensions()
        local visibleCount = 0

        for i = 1, #UNITS do
            local unit = UNITS[i]
            local btn = unitButtons[i]
            local okEx, exists = ns:SafeGlobal("UnitExists", unit)
            if okEx and ns:IsSafeBoolean(exists) and exists then
                visibleCount = visibleCount + 1
                btn:SetAttribute("unit", unit)
                btn:SetAttribute("type1", "target")
                if healSpell ~= "" then
                    btn:SetAttribute("type2", "spell")
                    btn:SetAttribute("spell2", healSpell)
                else
                    btn:SetAttribute("type2", nil)
                    btn:SetAttribute("spell2", nil)
                end
                if shiftSpell ~= "" then
                    btn:SetAttribute("shift-type1", "spell")
                    btn:SetAttribute("shift-spell1", shiftSpell)
                else
                    btn:SetAttribute("shift-type1", nil)
                    btn:SetAttribute("shift-spell1", nil)
                end
                ApplyButtonDimensions(btn, w, uh)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 5, -(TOP_PADDING + (visibleCount - 1) * (uh + UNIT_GAP)))
                btn:Show()
            else
                btn:Hide()
            end
        end

        local count = math.max(1, visibleCount)
        currentVisibleCount = count
        local h = TOP_PADDING + BOTTOM_RESIZE_PAD + count * uh + (count - 1) * UNIT_GAP
        containerFrame:SetSize(w, h)
        containerFrame:Show()
        PartyFrames:ApplyAppearance()
        PartyFrames:UpdateBars()
    end)
end

-- Midnight Secret-Safe Bar Guncellemesi (0 Lua aritmetigi / 0 secret boolean testi)
function PartyFrames:UpdateBars()
    if not containerFrame or not containerFrame:IsShown() then
        return
    end

    for i = 1, #unitButtons do
        local btn = unitButtons[i]
        if btn:IsShown() then
            local unit = btn.unit
            local okEx, exists = ns:SafeGlobal("UnitExists", unit)
            if okEx and ns:IsSafeBoolean(exists) and exists then
                -- Isim + Level + Rol
                local okName, name = ns:SafeGlobal("UnitName", unit)
                local okLvl, lvl = ns:SafeGlobal("UnitLevel", unit)
                local lvlStr = (okLvl and ns:IsSafeNumber(lvl) and lvl > 0) and ("|cffc8d2e6[" .. lvl .. "]|r ") or ""
                local roleStr = GetRoleBadge(unit)
                local safeName = (okName and ns:IsSafeString(name)) and name or unit
                btn.nameText:SetText(lvlStr .. roleStr .. safeName)

                local r, g, b = GetUnitClassColor(unit)
                btn.hpBar:SetStatusBarColor(r, g, b, 0.90)

                -- Olu / Offline kontrolu (yalnizca safe boolean ise)
                local okDead, isDead = ns:SafeGlobal("UnitIsDeadOrGhost", unit)
                local deadSafe = (okDead and ns:IsSafeBoolean(isDead) and isDead) or false
                local okConn, isConn = ns:SafeGlobal("UnitIsConnected", unit)
                local offlineSafe = (okConn and ns:IsSafeBoolean(isConn) and not isConn) or false

                if offlineSafe then
                    pcall(btn.hpBar.SetMinMaxValues, btn.hpBar, 0, 1)
                    pcall(btn.hpBar.SetValue, btn.hpBar, 0)
                    btn.hpText:SetText("|cff888888OFF|r")
                    if btn.lowHpHolder then btn.lowHpHolder:Hide() end
                elseif deadSafe then
                    pcall(btn.hpBar.SetMinMaxValues, btn.hpBar, 0, 1)
                    pcall(btn.hpBar.SetValue, btn.hpBar, 0)
                    btn.hpText:SetText("|cffff4444OLU|r")
                    if btn.lowHpHolder then btn.lowHpHolder:Hide() end
                else
                    -- Can bari: Secret number'i dogrudan C++ StatusBar'a ver (0 hata!)
                    local okMaxHp, maxHp = ns:SafeGlobal("UnitHealthMax", unit)
                    local okHp, hp = ns:SafeGlobal("UnitHealth", unit)
                    if okMaxHp and okHp and maxHp ~= nil and hp ~= nil then
                        pcall(btn.hpBar.SetMinMaxValues, btn.hpBar, 0, maxHp)
                        pcall(btn.hpBar.SetValue, btn.hpBar, hp)
                    end

                    -- Cani az (<%40) uyeleri kirmizi yanip sonerek vurgula (Midnight secret-safe!)
                    if btn.lowHpHolder then
                        if ns:IsSafeNumber(hp) and ns:IsSafeNumber(maxHp) and maxHp > 0 then
                            if (hp / maxHp) < 0.40 then
                                btn.lowHpHolder:SetAlpha(1.0)
                                btn.lowHpHolder:Show()
                            else
                                btn.lowHpHolder:Hide()
                            end
                        elseif type(_G.UnitHealthPercent) == "function" then
                            local curve = GetLowHpCurve()
                            if curve then
                                local okC, alphaVal = pcall(_G.UnitHealthPercent, unit, true, curve)
                                if okC and alphaVal ~= nil then
                                    btn.lowHpHolder:Show()
                                    pcall(btn.lowHpHolder.SetAlpha, btn.lowHpHolder, alphaVal)
                                else
                                    btn.lowHpHolder:Hide()
                                end
                            else
                                btn.lowHpHolder:Hide()
                            end
                        else
                            btn.lowHpHolder:Hide()
                        end
                    end

                    -- Can yuzdesi yazisi (once Midnight UnitHealthPercent, yoksa safe number hesabi)
                    local pctSet = false
                    if type(_G.UnitHealthPercent) == "function" then
                        local scaleCurve = _G.CurveConstants and _G.CurveConstants.ScaleTo100
                        local okP, pctVal = pcall(_G.UnitHealthPercent, unit, true, scaleCurve)
                        if okP and pctVal ~= nil then
                            local okFmt = pcall(btn.hpText.SetFormattedText, btn.hpText, "%.0f%%", pctVal)
                            if okFmt then
                                pctSet = true
                            end
                        end
                    end
                    if not pctSet then
                        if ns:IsSafeNumber(hp) and ns:IsSafeNumber(maxHp) and maxHp > 0 then
                            btn.hpText:SetText(string.format("%d%%", math.floor((hp / maxHp) * 100 + 0.5)))
                        else
                            btn.hpText:SetText("")
                        end
                    end
                end

                -- Mana / Guc bari: Secret number'i dogrudan C++ StatusBar'a ver (0 hata!)
                local okPType, pType = ns:SafeGlobal("UnitPowerType", unit)
                local pCol = (okPType and ns:IsSafeNumber(pType) and POWER_COLORS[pType]) or POWER_COLORS[0]
                btn.mpBar:SetStatusBarColor(pCol[1], pCol[2], pCol[3], 0.90)

                local okMaxPow, maxPow = ns:SafeGlobal("UnitPowerMax", unit)
                local okPow, pow = ns:SafeGlobal("UnitPower", unit)
                if okMaxPow and okPow and maxPow ~= nil and pow ~= nil then
                    pcall(btn.mpBar.SetMinMaxValues, btn.mpBar, 0, maxPow)
                    pcall(btn.mpBar.SetValue, btn.mpBar, pow)
                end

                -- Secili (target) uye vurgusu: etrafi parlak YESIL
                if btn.selBorder then
                    local okT, isTarget = ns:SafeGlobal("UnitIsUnit", unit, "target")
                    if okT and ns:IsSafeBoolean(isTarget) and isTarget then
                        btn.selBorder:Show()
                    else
                        btn.selBorder:Hide()
                    end
                end

                -- Menzil soluklastirmasi: Midnight resmi SetAlphaFromBoolean (0 secret boolean hatasi!)
                if unit ~= "player" then
                    local okRng, inRange = ns:SafeGlobal("UnitInRange", unit)
                    if okRng and type(btn.SetAlphaFromBoolean) == "function" and (IsSecret(inRange) or inRange ~= nil) then
                        pcall(btn.SetAlphaFromBoolean, btn, inRange, 1.0, 0.45)
                    elseif okRng and ns:IsSafeBoolean(inRange) then
                        btn:SetAlpha(inRange and 1.0 or 0.45)
                    else
                        btn:SetAlpha(1.0)
                    end
                else
                    btn:SetAlpha(1.0)
                end
            end
        end
    end
end

function PartyFrames:Toggle()
    if ns:IsInCombat() or not ns.db then
        ns:Print("Savas sirasinda grup cercevesi acilip kapatilamaz.")
        return
    end
    ns.db.showPartyFrames = not ns.db.showPartyFrames
    self:RebuildLayout()
    ns:FireCallback("CONFIG_CHANGED")
end

local partyEventFrame = CreateFrame("Frame", "QuestGoToZPartyEventFrame")
partyEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
partyEventFrame:RegisterEvent("UNIT_HEALTH")
partyEventFrame:RegisterEvent("UNIT_MAXHEALTH")
partyEventFrame:RegisterEvent("UNIT_POWER_UPDATE")
partyEventFrame:RegisterEvent("UNIT_MAXPOWER")
partyEventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
partyEventFrame:RegisterEvent("UNIT_CONNECTION")
partyEventFrame:RegisterEvent("UNIT_LEVEL")
partyEventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
partyEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
partyEventFrame:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" then
        PartyFrames:RebuildLayout()
    else
        pcall(PartyFrames.UpdateBars, PartyFrames)
    end
end)

ns:RegisterCallback("PLAYER_LOGIN", function()
    CreatePartyContainer()
    PartyFrames:RebuildLayout()
    if not updateTicker then
        local ok, t = ns:SafeC("C_Timer", "NewTicker", 0.25, function()
            pcall(PartyFrames.UpdateBars, PartyFrames)
        end)
        if ok and t then
            updateTicker = t
        end
    end
end)

ns:RegisterCallback("CONFIG_CHANGED", function()
    PartyFrames:UpdateLockState()
    PartyFrames:ApplyAppearance()
    PartyFrames:RebuildLayout()
end)
