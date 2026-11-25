local _, ns = ...

local ThreatMeter = {}
ns.ThreatMeter = ThreatMeter

local FONT_MAIN = "Fonts\\ARIALN.TTF"
local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"
local BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

local UPDATE_INTERVAL = 0.20
local ROW_HEIGHT = 18
local ROW_GAP = 2
local HEADER_HEIGHT = 24
local MAX_POOL_ROWS = 20

local mainFrame = nil
local rows = {}
local updateTicker = nil
local eventFrame = nil
local testMode = false

-- Onceden uretilmis unit token listeleri (GC uretmez)
local PARTY_UNITS, PARTY_PETS = {}, {}
local RAID_UNITS, RAID_PETS = {}, {}
local PET_OWNER = { pet = "player" }

for i = 1, 4 do
    PARTY_UNITS[i] = "party" .. i
    PARTY_PETS[i] = "partypet" .. i
    PET_OWNER["partypet" .. i] = "party" .. i
end
for i = 1, 40 do
    RAID_UNITS[i] = "raid" .. i
    RAID_PETS[i] = "raidpet" .. i
    PET_OWNER["raidpet" .. i] = "raid" .. i
end

local TARGET_OF = {
    target = "targettarget",
    focus = "focustarget",
}

local function IsReadable(v)
    if type(_G.issecretvalue) == "function" then
        local ok, sec = pcall(_G.issecretvalue, v)
        if not ok or sec then
            return false
        end
    end
    return v ~= nil
end

local function SafeUnitExists(unit)
    local ok, ex = ns:SafeGlobal("UnitExists", unit)
    return ok and IsReadable(ex) and ex == true
end

local function SafeCanAttack(unit)
    local ok, can = ns:SafeGlobal("UnitCanAttack", "player", unit)
    return ok and IsReadable(can) and can == true
end

local function SafeUnitIsDead(unit)
    local ok, dead = ns:SafeGlobal("UnitIsDeadOrGhost", unit)
    return ok and IsReadable(dead) and dead == true
end

local function ResolveThreatMob(sourceKey)
    local src = (sourceKey == "focus") and "focus" or "target"
    if SafeUnitExists(src) and SafeCanAttack(src) and not SafeUnitIsDead(src) then
        return src
    end
    local alt = TARGET_OF[src]
    if alt and SafeUnitExists(alt) and SafeCanAttack(alt) and not SafeUnitIsDead(alt) then
        return alt
    end
    return nil
end

local function GetDungeonInfo()
    local ok, instName, instType = ns:SafeGlobal("GetInstanceInfo")
    if ok and IsReadable(instType) and (instType == "party" or instType == "raid" or instType == "scenario") then
        local safeName = (IsReadable(instName) and type(instName) == "string" and instName ~= "") and instName or "Dungeon"
        return true, safeName
    end
    return false, nil
end

local function IsUnitInPlayerGroup(name)
    if not (IsReadable(name) and type(name) == "string" and name ~= "") then
        return true -- secret ise C_DamageMeter zaten grup kaynagini dondurur
    end
    local shortTarget = name:match("^([^%-]+)") or name
    local function Matches(unit)
        if not SafeUnitExists(unit) then return false end
        local okN, uName = ns:SafeGlobal("UnitName", unit)
        if okN and IsReadable(uName) and type(uName) == "string" then
            local shortU = uName:match("^([^%-]+)") or uName
            if shortU == shortTarget then return true end
        end
        return false
    end
    if Matches("player") then return true end
    local okR, inRaid = ns:SafeGlobal("IsInRaid")
    if okR and IsReadable(inRaid) and inRaid == true then
        for i = 1, 40 do
            if Matches(RAID_UNITS[i]) then return true end
        end
    else
        for i = 1, 4 do
            if Matches(PARTY_UNITS[i]) then return true end
        end
    end
    return false
end

local function GetUnitClassRGB(unit)
    local owner = PET_OWNER[unit] or unit
    local okC, _, classFile = ns:SafeGlobal("UnitClass", owner)
    if okC and IsReadable(classFile) and type(classFile) == "string" then
        local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile]
        if c then
            return c.r, c.g, c.b
        end
    end
    return 0.45, 0.65, 0.85
end

local function GetUnitDisplayName(unit, isPet)
    local okN, name = ns:SafeGlobal("UnitName", unit)
    if okN and IsReadable(name) and type(name) == "string" and name ~= "" then
        if isPet then
            return name .. " (Pet)"
        end
        return name
    end
    return unit
end

local function FormatShortNumber(val)
    if not val or val <= 0 then return "0" end
    if val >= 1000000 then
        return string.format("%.2fM", val / 1000000)
    elseif val >= 10000 then
        return string.format("%.1fk", val / 1000)
    elseif val >= 1000 then
        return string.format("%.2fk", val / 1000)
    end
    return tostring(math.floor(val + 0.5))
end

local function StyleFont(fs, size, r, g, b)
    fs:SetFont(FONT_MAIN, size or 11, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    if r then
        fs:SetTextColor(r, g, b)
    end
end

local function CreateHeaderBtn(parent, width, height, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(0.08, 0.12, 0.19, 0.80)
    btn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.18)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    StyleFont(fs, 10, 0.90, 0.94, 1.0)
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetText(label)
    btn.label = fs

    btn:SetScript("OnEnter", function(selfBtn)
        selfBtn:SetBackdropColor(0.16, 0.24, 0.36, 0.95)
        selfBtn:SetBackdropBorderColor(0.45, 0.82, 1.0, 0.75)
    end)
    btn:SetScript("OnLeave", function(selfBtn)
        selfBtn:SetBackdropColor(0.08, 0.12, 0.19, 0.80)
        selfBtn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.18)
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.05, 0.07, 0.11, 0.55)
    row:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.06)

    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture(BAR_TEX)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    row.bar = bar

    local leftText = bar:CreateFontString(nil, "OVERLAY")
    StyleFont(leftText, 11, 1, 1, 1)
    leftText:SetPoint("LEFT", bar, "LEFT", 5, 0)
    leftText:SetPoint("RIGHT", bar, "RIGHT", -84, 0)
    leftText:SetJustifyH("LEFT")
    leftText:SetWordWrap(false)
    row.leftText = leftText

    local rightText = bar:CreateFontString(nil, "OVERLAY")
    StyleFont(rightText, 11, 0.95, 0.97, 1.0)
    rightText:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    rightText:SetJustifyH("RIGHT")
    row.rightText = rightText

    row:Hide()
    rows[index] = row
    return row
end

local function GetPanelAlpha()
    local db = ns.db or ns.DEFAULTS
    local pct = db.panelAlpha or 35
    if pct < 10 then pct = 10 end
    if pct > 95 then pct = 95 end
    return pct / 100
end

local function EnsureMainFrame()
    if mainFrame then
        return mainFrame
    end

    local f = CreateFrame("Frame", "QuestGoToZThreatMeterFrame", UIParent, "BackdropTemplate")
    f:SetSize(248, 176)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(208, 106, 420, 380)
    elseif f.SetMinResize then
        f:SetMinResize(208, 106)
        f:SetMaxResize(420, 380)
    end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    f:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.03, 0.05, 0.09, GetPanelAlpha())
    f:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.22)

    f:SetScript("OnDragStart", function(selfFrame)
        if ns.db and ns.db.locked then return end
        if ns:IsInCombat() then return end
        selfFrame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        local point, _, relPoint, x, y = selfFrame:GetPoint(1)
        if ns.db and point then
            ns.db.threatPos = {
                point = point,
                relativePoint = relPoint or point,
                x = math.floor((x or 0) + 0.5),
                y = math.floor((y or 0) + 0.5),
            }
        end
    end)

    -- Ust baslik cubugu
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT)

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(header)
    headerBg:SetColorTexture(0.05, 0.08, 0.14, 0.72)

    local headerSep = header:CreateTexture(nil, "ARTWORK")
    headerSep:SetHeight(1)
    headerSep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerSep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerSep:SetColorTexture(1.0, 1.0, 1.0, 0.14)

    local title = header:CreateFontString(nil, "OVERLAY")
    StyleFont(title, 11, 1.0, 0.86, 0.35)
    title:SetPoint("LEFT", header, "LEFT", 6, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -96, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText("Dungeon")
    f.title = title

    local modeBtn = CreateHeaderBtn(header, 44, 16, "DMG", function(_, button)
        if not ns.db then return end
        local cur = ns.db.threatView or "damage"
        if cur == "threat" and button == "RightButton" then
            ns.db.threatMode = (ns.db.threatMode == "raw") and "pull" or "raw"
        else
            if cur == "damage" then
                ns.db.threatView = "heal"
            elseif cur == "heal" then
                ns.db.threatView = "threat"
            else
                ns.db.threatView = "damage"
            end
        end
        ThreatMeter:RefreshHeaderButtons()
        ThreatMeter:Update()
    end)
    modeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    modeBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    f.modeBtn = modeBtn

    local srcBtn = CreateHeaderBtn(header, 40, 16, "Genel", function()
        if not ns.db then return end
        local cur = ns.db.threatView or "damage"
        if cur == "threat" then
            ns.db.threatSource = (ns.db.threatSource == "focus") and "target" or "focus"
        else
            ns.db.damageSegment = (ns.db.damageSegment == "current") and "overall" or "current"
        end
        ThreatMeter:RefreshHeaderButtons()
        ThreatMeter:Update()
    end)
    srcBtn:SetPoint("RIGHT", modeBtn, "LEFT", -3, 0)
    f.srcBtn = srcBtn

    -- Satir alani
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -(HEADER_HEIGHT + 5))
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 10)
    f.body = body

    local emptyText = body:CreateFontString(nil, "OVERLAY")
    StyleFont(emptyText, 11, 0.62, 0.68, 0.78)
    emptyText:SetPoint("CENTER", body, "CENTER", 0, 2)
    emptyText:SetText("Tehdit verisi bekleniyor...")
    f.emptyText = emptyText

    for i = 1, MAX_POOL_ROWS do
        CreateRow(body, i)
    end

    -- Sag-alt yeniden boyutlandirma tutamaci
    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(12, 12)
    resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        if ns.db and ns.db.locked then return end
        if ns:IsInCombat() then return end
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local w, h = f:GetSize()
        if ns.db then
            ns.db.threatSize = {
                width = math.floor((w or 248) + 0.5),
                height = math.floor((h or 176) + 0.5),
            }
        end
        ThreatMeter:Update()
    end)
    f.resizeBtn = resizeBtn

    f:Hide()
    mainFrame = f
    return f
end

function ThreatMeter:RefreshHeaderButtons()
    if not mainFrame or not ns.db then return end
    local view = ns.db.threatView or "damage"
    if view == "damage" then
        mainFrame.modeBtn.label:SetText("DMG")
        mainFrame.modeBtn.label:SetTextColor(1.0, 0.55, 0.30)
        mainFrame.srcBtn.label:SetText((ns.db.damageSegment == "current") and "Anlik" or "Genel")
    elseif view == "heal" then
        mainFrame.modeBtn.label:SetText("HEAL")
        mainFrame.modeBtn.label:SetTextColor(0.35, 1.0, 0.55)
        mainFrame.srcBtn.label:SetText((ns.db.damageSegment == "current") and "Anlik" or "Genel")
    else
        mainFrame.modeBtn.label:SetText((ns.db.threatMode == "raw") and "T:Dgr" or "T:%")
        mainFrame.modeBtn.label:SetTextColor(0.55, 0.85, 1.0)
        mainFrame.srcBtn.label:SetText((ns.db.threatSource == "focus") and "Focus" or "Hedef")
    end
end

function ThreatMeter:ApplyPosition()
    local f = EnsureMainFrame()
    if ns:IsInCombat() then
        ns:RunOutOfCombat("threat_apply_pos", function()
            ThreatMeter:ApplyPosition()
        end)
        return
    end

    local db = ns.db or ns.DEFAULTS
    local pos = db.threatPos or ns.DEFAULTS.threatPos
    local sz = db.threatSize or ns.DEFAULTS.threatSize

    f:ClearAllPoints()
    f:SetPoint(pos.point or "BOTTOMRIGHT", UIParent, pos.relativePoint or "BOTTOMRIGHT", pos.x or -24, pos.y or 140)
    f:SetSize(sz.width or 248, sz.height or 176)
    f:SetBackdropColor(0.03, 0.05, 0.09, GetPanelAlpha())
    if f.resizeBtn then
        f.resizeBtn:SetShown(not db.locked)
    end
    self:RefreshHeaderButtons()
end

-- Test simülasyonu (savas disinda konum/gorunum testi icin)
local function BuildTestEntries()
    return {
        { name = "Pull Aggro", isPull = true, raw = 19800, pct = 110, r = 0.72, g = 0.28, b = 0.28 },
        { name = "Tankor (Tank)", isTank = true, isSelf = true, raw = 18000, pct = 100, r = 0.78, g = 0.61, b = 0.43 },
        { name = "Alevmaji", raw = 15400, pct = 86, r = 0.25, g = 0.78, b = 0.92 },
        { name = "Golgeavci", raw = 12800, pct = 71, r = 0.67, g = 0.83, b = 0.45 },
        { name = "Sifaci", raw = 6200, pct = 34, r = 0.95, g = 0.95, b = 0.95 },
    }
end

local function CollectThreatEntries(mob)
    local db = ns.db or ns.DEFAULTS
    local includePets = (db.threatIncludePets ~= false)
    local entries = {}
    local seenSelf = false
    local tankRaw = nil
    local pullRaw = nil

    local function ReadUnit(unit, isPet)
        if not SafeUnitExists(unit) then return end

        local isSelf = false
        if not isPet then
            if unit == "player" then
                isSelf = true
            else
                local okSame, same = ns:SafeGlobal("UnitIsUnit", unit, "player")
                if okSame and IsReadable(same) and same == true then
                    isSelf = true
                end
            end
            if isSelf then
                if seenSelf then return end
                seenSelf = true
            end
        end

        local okT, isTanking, status, scaledPct, rawPct, rawThreat = ns:SafeGlobal("UnitDetailedThreatSituation", unit, mob)
        if not okT then return end

        local rTanking = IsReadable(isTanking) and isTanking or nil
        local rStatus = IsReadable(status) and status or nil
        local rScaled = IsReadable(scaledPct) and scaledPct or nil
        local rRawPct = IsReadable(rawPct) and rawPct or nil
        local rRaw = IsReadable(rawThreat) and rawThreat or nil

        -- Sayilar okunabiliyorsa normal mod
        if rRaw and rRaw > 0 then
            local pctVal = rScaled or rRawPct or (rTanking and 100 or 0)
            if rTanking then
                tankRaw = rRaw
            end
            -- Kendi veya mevcut oyuncunun pull esigini tahmin et
            if not pullRaw and rScaled and rScaled > 5 and rScaled < 100 then
                pullRaw = rRaw * (100 / rScaled)
            end
            local cr, cg, cb = GetUnitClassRGB(unit)
            table.insert(entries, {
                unit = unit,
                name = GetUnitDisplayName(unit, isPet),
                raw = rRaw,
                pct = pctVal,
                isTank = (rTanking == true),
                isSelf = isSelf,
                isPet = isPet,
                r = cr, g = cg, b = cb,
            })
            return
        end

        -- Eger sayilar gizli (secret) ama durum/tanking okunabiliyorsa fallback durum modu
        if rTanking == true or (rStatus and rStatus >= 1) then
            local stateLabel = "Yakin"
            local fakePct = 60
            if rTanking == true or rStatus == 3 then
                stateLabel = "Aggro"
                fakePct = 100
            elseif rStatus == 2 then
                stateLabel = "Tehlikeli"
                fakePct = 85
            end
            local cr, cg, cb = GetUnitClassRGB(unit)
            table.insert(entries, {
                unit = unit,
                name = GetUnitDisplayName(unit, isPet),
                raw = nil,
                pct = fakePct,
                stateLabel = stateLabel,
                isTank = (rTanking == true),
                isSelf = isSelf,
                isPet = isPet,
                r = cr, g = cg, b = cb,
            })
        end
    end

    local okRaid, inRaid = ns:SafeGlobal("IsInRaid")
    if okRaid and IsReadable(inRaid) and inRaid == true then
        local okNum, num = ns:SafeGlobal("GetNumGroupMembers")
        local count = (okNum and IsReadable(num) and num) or 0
        if count > 40 then count = 40 end
        for i = 1, count do
            ReadUnit(RAID_UNITS[i], false)
            if includePets then
                ReadUnit(RAID_PETS[i], true)
            end
        end
    else
        ReadUnit("player", false)
        if includePets then
            ReadUnit("pet", true)
        end
        for i = 1, 4 do
            ReadUnit(PARTY_UNITS[i], false)
            if includePets then
                ReadUnit(PARTY_PETS[i], true)
            end
        end
    end

    table.sort(entries, function(a, b)
        local aVal = a.raw or a.pct or 0
        local bVal = b.raw or b.pct or 0
        if aVal ~= bVal then
            return aVal > bVal
        end
        return (a.name or "") < (b.name or "")
    end)

    -- Pull Aggro referans satiri (istege bagli, sadece ham threat varken)
    if db.threatShowPullLine ~= false and #entries > 0 then
        local refRaw = pullRaw or (tankRaw and (tankRaw * 1.10)) or (entries[1].raw and (entries[1].raw * 1.10))
        if refRaw and refRaw > 0 then
            table.insert(entries, 1, {
                name = "Pull Aggro",
                isPull = true,
                raw = refRaw,
                pct = 100,
                r = 0.72, g = 0.24, b = 0.24,
            })
        end
    end

    return entries
end

local function RenderEntries(f, headerTitle, entries)
    local db = ns.db or ns.DEFAULTS
    local isRawMode = (db.threatMode == "raw")

    f.title:SetText(headerTitle or "Threat")

    local bodyH = f.body:GetHeight() or 120
    local maxVisible = math.floor((bodyH + ROW_GAP) / (ROW_HEIGHT + ROW_GAP))
    if maxVisible < 1 then maxVisible = 1 end
    if maxVisible > MAX_POOL_ROWS then maxVisible = MAX_POOL_ROWS end

    if #entries == 0 then
        for i = 1, MAX_POOL_ROWS do
            rows[i]:Hide()
        end
        f.emptyText:Show()
        return
    end
    f.emptyText:Hide()

    -- Kendi satirin gorunen alanin disindaysa en alt satira sabitle
    local displayList = {}
    local selfShown = false
    local selfEntry = nil
    for i = 1, #entries do
        if entries[i].isSelf then
            selfEntry = entries[i]
        end
        if i <= maxVisible then
            displayList[i] = entries[i]
            if entries[i].isSelf then
                selfShown = true
            end
        end
    end
    if selfEntry and not selfShown and maxVisible >= 2 then
        displayList[maxVisible] = selfEntry
    end

    local maxRaw = 1
    for i = 1, #displayList do
        if displayList[i].raw and displayList[i].raw > maxRaw then
            maxRaw = displayList[i].raw
        end
    end

    for i = 1, MAX_POOL_ROWS do
        local row = rows[i]
        local e = displayList[i]
        if e then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -((i - 1) * (ROW_HEIGHT + ROW_GAP)))
            row:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, -((i - 1) * (ROW_HEIGHT + ROW_GAP)))

            local barPct = 0
            if e.stateLabel then
                barPct = e.pct or 50
            elseif isRawMode and e.raw then
                barPct = math.min(100, (e.raw / maxRaw) * 100)
            else
                barPct = math.min(100, math.max(0, e.pct or 0))
            end

            row.bar:SetMinMaxValues(0, 100)
            row.bar:SetValue(barPct)
            row.bar:SetStatusBarColor(e.r or 0.4, e.g or 0.6, e.b or 0.8, e.isPull and 0.45 or 0.82)

            local prefix = ""
            if e.isPull then
                prefix = "-- "
            elseif e.isTank then
                prefix = "[T] "
            end
            row.leftText:SetText(prefix .. (e.name or "?"))

            if e.stateLabel then
                row.rightText:SetText(e.stateLabel)
            elseif e.isPull then
                row.rightText:SetText(isRawMode and FormatShortNumber(e.raw) or "100%")
            elseif isRawMode then
                row.rightText:SetText(FormatShortNumber(e.raw))
            else
                if e.raw then
                    row.rightText:SetText(string.format("%s  %.0f%%", FormatShortNumber(e.raw), e.pct or 0))
                else
                    row.rightText:SetText(string.format("%.0f%%", e.pct or 0))
                end
            end

            -- Kendi satirina ince parlak kenarlik vurgusu
            if e.isSelf then
                row:SetBackdropBorderColor(1.0, 0.90, 0.35, 0.85)
                row.leftText:SetTextColor(1.0, 0.96, 0.72)
            elseif e.isPull then
                row:SetBackdropBorderColor(0.95, 0.35, 0.35, 0.55)
                row.leftText:SetTextColor(1.0, 0.65, 0.65)
            else
                row:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.08)
                row.leftText:SetTextColor(0.96, 0.98, 1.0)
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

-- Midnight resmi C_DamageMeter (16001 secret-safe) DMG / HEAL render
local function GetClassColorByFilename(classFile)
    if IsReadable(classFile) and type(classFile) == "string" and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile] then
        local c = _G.RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 0.45, 0.65, 0.85
end

local function FormatMeterVal(val)
    if val == nil then return "0" end
    if type(_G.AbbreviateNumbers) == "function" then
        local ok, s = pcall(_G.AbbreviateNumbers, val)
        if ok and s ~= nil then
            return s
        end
    end
    if IsReadable(val) and type(val) == "number" then
        return FormatShortNumber(val)
    end
    return ""
end

local function BuildDamageTestRows(f, isHeal)
    local samples = isHeal and {
        { name = "1. Sifaci", tot = "342k", ps = "12.8k/s", pct = 100, isSelf = true, r = 0.95, g = 0.95, b = 0.95 },
        { name = "2. Paladin", tot = "128k", ps = "4.8k/s", pct = 37, r = 0.96, g = 0.55, b = 0.73 },
        { name = "3. Tankor", tot = "86k", ps = "3.2k/s", pct = 25, r = 0.78, g = 0.61, b = 0.43 },
    } or {
        { name = "1. Alevmaji", tot = "482k", ps = "18.4k/s", pct = 100, r = 0.25, g = 0.78, b = 0.92 },
        { name = "2. Golgeavci", tot = "429k", ps = "16.3k/s", pct = 89, isSelf = true, r = 0.67, g = 0.83, b = 0.45 },
        { name = "3. Savasci", tot = "395k", ps = "15.1k/s", pct = 82, r = 0.78, g = 0.61, b = 0.43 },
        { name = "4. Tankor", tot = "240k", ps = "9.1k/s", pct = 50, r = 0.77, g = 0.12, b = 0.23 },
        { name = "5. Sifaci", tot = "68k", ps = "2.6k/s", pct = 14, r = 0.95, g = 0.95, b = 0.95 },
    }

    f.title:SetText(isHeal and "Test: Heal (Genel)" or "Test: Hasar (Genel)")
    f.emptyText:Hide()
    local bodyH = f.body:GetHeight() or 120
    local maxVisible = math.max(1, math.min(MAX_POOL_ROWS, math.floor((bodyH + ROW_GAP) / (ROW_HEIGHT + ROW_GAP))))

    for i = 1, MAX_POOL_ROWS do
        local row = rows[i]
        local e = (i <= maxVisible) and samples[i] or nil
        if e then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -((i - 1) * (ROW_HEIGHT + ROW_GAP)))
            row:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, -((i - 1) * (ROW_HEIGHT + ROW_GAP)))
            row.bar:SetMinMaxValues(0, 100)
            row.bar:SetValue(e.pct)
            row.bar:SetStatusBarColor(e.r, e.g, e.b, 0.84)
            row.leftText:SetText(e.name)
            row.rightText:SetText(e.tot .. " (" .. e.ps .. ")")
            if e.isSelf then
                row:SetBackdropBorderColor(1.0, 0.90, 0.35, 0.85)
                row.leftText:SetTextColor(1.0, 0.96, 0.72)
            else
                row:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.08)
                row.leftText:SetTextColor(0.96, 0.98, 1.0)
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

local function RenderDamageMeter(f, viewKey, dungeonName)
    local db = ns.db or ns.DEFAULTS
    local isHeal = (viewKey == "heal")
    local isCurrent = (db.damageSegment == "current")

    if testMode then
        f:Show()
        BuildDamageTestRows(f, isHeal)
        return
    end

    local dm = _G.C_DamageMeter
    local dmEnum = _G.Enum and _G.Enum.DamageMeterType
    local sessEnum = _G.Enum and _G.Enum.DamageMeterSessionType
    if not (dm and type(dm.GetCombatSessionFromType) == "function" and dmEnum and sessEnum) then
        f.title:SetText(dungeonName or (isHeal and "Heal" or "Hasar"))
        for i = 1, MAX_POOL_ROWS do rows[i]:Hide() end
        f.emptyText:SetText("C_DamageMeter API bulunamadi.")
        f.emptyText:Show()
        f:Show()
        return
    end

    local sessionType = isCurrent and sessEnum.Current or sessEnum.Overall
    local meterType = isHeal and dmEnum.HealingDone or dmEnum.DamageDone
    local ok, session = pcall(dm.GetCombatSessionFromType, sessionType, meterType)
    local rawSources = (ok and type(session) == "table" and type(session.combatSources) == "table") and session.combatSources or nil

    -- Sadece gruptaki oyuncularin verilerini filtrele
    local sources = {}
    if rawSources then
        for idx = 1, #rawSources do
            local s = rawSources[idx]
            if s and IsUnitInPlayerGroup(s.name) then
                table.insert(sources, s)
            end
        end
    end

    f.title:SetText(dungeonName or (isHeal and "Heal" or "Hasar"))

    if #sources == 0 then
        if db.threatOnlyInCombat and not ns:IsInCombat() then
            f:Hide()
            return
        end
        for i = 1, MAX_POOL_ROWS do rows[i]:Hide() end
        f.emptyText:SetText(isHeal and "Grup heal verisi bekleniyor..." or "Grup hasar verisi bekleniyor...")
        f.emptyText:Show()
        f:Show()
        return
    end

    f:Show()
    f.emptyText:Hide()

    local bodyH = f.body:GetHeight() or 120
    local maxVisible = math.max(1, math.min(MAX_POOL_ROWS, math.floor((bodyH + ROW_GAP) / (ROW_HEIGHT + ROW_GAP))))
    local maxAmt = (sources[1] and sources[1].totalAmount) or 1

    for i = 1, MAX_POOL_ROWS do
        local row = rows[i]
        local src = (i <= maxVisible) and sources[i] or nil
        if src then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -((i - 1) * (ROW_HEIGHT + ROW_GAP)))
            row:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, -((i - 1) * (ROW_HEIGHT + ROW_GAP)))

            -- Secret-safe bar degerleri dogrudan C++ StatusBar'a verilir
            pcall(row.bar.SetMinMaxValues, row.bar, 0, maxAmt)
            pcall(row.bar.SetValue, row.bar, src.totalAmount or 0)

            local cr, cg, cb = GetClassColorByFilename(src.classFilename)
            row.bar:SetStatusBarColor(cr, cg, cb, 0.84)

            if IsReadable(src.name) and type(src.name) == "string" then
                row.leftText:SetText(string.format("%d. %s", i, src.name))
            elseif src.name ~= nil then
                pcall(row.leftText.SetText, row.leftText, src.name)
            else
                row.leftText:SetText(tostring(i) .. ".")
            end

            local totStr = FormatMeterVal(src.totalAmount)
            local psStr = FormatMeterVal(src.amountPerSecond)
            local okFmt = pcall(row.rightText.SetFormattedText, row.rightText, "%s (%s/s)", totStr, psStr)
            if not okFmt then
                pcall(row.rightText.SetText, row.rightText, totStr)
            end

            local isSelf = (IsReadable(src.isLocalPlayer) and src.isLocalPlayer == true)
            if isSelf then
                row:SetBackdropBorderColor(1.0, 0.90, 0.35, 0.85)
                row.leftText:SetTextColor(1.0, 0.96, 0.72)
            else
                row:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.08)
                row.leftText:SetTextColor(0.96, 0.98, 1.0)
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

function ThreatMeter:Update()
    local db = ns.db or ns.DEFAULTS
    if not db.showThreatMeter then
        if mainFrame then mainFrame:Hide() end
        return
    end

    local inDungeon, dungeonName = GetDungeonInfo()
    if not testMode and not inDungeon then
        if mainFrame then mainFrame:Hide() end
        return
    end

    local f = EnsureMainFrame()
    f:SetBackdropColor(0.03, 0.05, 0.09, GetPanelAlpha())

    local view = db.threatView or "damage"
    if view == "damage" or view == "heal" then
        RenderDamageMeter(f, view, dungeonName)
        return
    end

    if testMode then
        f:Show()
        RenderEntries(f, "Test: Threat Ornegi", BuildTestEntries())
        return
    end

    local mob = ResolveThreatMob(db.threatSource)
    if not mob then
        if db.threatOnlyInCombat then
            f:Hide()
        else
            f:Show()
            f.emptyText:SetText("Tehdit verisi bekleniyor...")
            RenderEntries(f, dungeonName or "Threat", {})
        end
        return
    end

    local entries = CollectThreatEntries(mob)
    if #entries == 0 and db.threatOnlyInCombat then
        f:Hide()
        return
    end

    local mobName = GetUnitDisplayName(mob, false)
    f:Show()
    RenderEntries(f, (dungeonName and (dungeonName .. " - " .. mobName)) or mobName, entries)
end

local function StopRuntime()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    testMode = false
    if mainFrame then
        mainFrame:Hide()
    end
end

local function StartRuntime()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function()
            ThreatMeter:Update()
        end)
    end
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    pcall(eventFrame.RegisterEvent, eventFrame, "DAMAGE_METER_COMBAT_SESSION_UPDATED")
    pcall(eventFrame.RegisterEvent, eventFrame, "DAMAGE_METER_CURRENT_SESSION_UPDATED")

    if not updateTicker and _G.C_Timer and type(_G.C_Timer.NewTicker) == "function" then
        updateTicker = _G.C_Timer.NewTicker(UPDATE_INTERVAL, function()
            if ns.db and ns.db.showThreatMeter then
                if testMode or ns:IsInCombat() or not ns.db.threatOnlyInCombat then
                    ThreatMeter:Update()
                end
            end
        end)
    end
end

function ThreatMeter:RefreshState()
    local db = ns.db or ns.DEFAULTS
    if not db.showThreatMeter then
        StopRuntime()
        return
    end
    EnsureMainFrame()
    self:ApplyPosition()
    StartRuntime()
    self:Update()
end

function ThreatMeter:SetView(viewKey)
    if not ns.db then return end
    ns.db.showThreatMeter = true
    ns.db.threatView = viewKey
    self:RefreshState()
    self:RefreshHeaderButtons()
    self:Update()
    ns:Print("Meter modu: " .. string.upper(viewKey))
end

function ThreatMeter:Toggle()
    if not ns.db then return end
    ns.db.showThreatMeter = not ns.db.showThreatMeter
    ns:FireCallback("CONFIG_CHANGED")
    ns:Print("Threat Meter: " .. (ns.db.showThreatMeter and "ACIK" or "KAPALI"))
end

function ThreatMeter:ToggleTest()
    if not ns.db then return end
    if not ns.db.showThreatMeter then
        ns.db.showThreatMeter = true
        self:RefreshState()
    end
    testMode = not testMode
    self:RefreshHeaderButtons()
    self:Update()
    ns:Print("Threat Meter Test: " .. (testMode and "ACIK" or "KAPALI"))
end

ns:RegisterCallback("PLAYER_LOGIN", function()
    ThreatMeter:RefreshState()
end)

ns:RegisterCallback("CONFIG_CHANGED", function()
    ThreatMeter:RefreshState()
end)
