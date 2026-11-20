local _, ns = ...

local Nearby = {}
ns.Nearby = Nearby

local MAX_VISIBLE_HEIGHT = 295
local ROW_HEIGHT = 22
local GROUP_HEADER_HEIGHT = 20
local HEADER_HEIGHT = 24
local STATUS_BAR_HEIGHT = 42
local FRAME_WIDTH = 276
local CONTENT_WIDTH = FRAME_WIDTH - 16

local nearbyFrame = nil
local statusBarFrame = nil
local profSlots = {}
local scrollFrame = nil
local scrollChild = nil
local slotPool = {}
local scanTicker = nil
local notifiedQuests = {}
local lastRequestedQuestLineMap = nil

-- Katlanabilir grup durumlari (anahtar -> boolean)
local collapsedGroups = {}

local function SaveNearbyPosition(frame)
    if not ns.db or not frame then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then
        ns.db.nearbyPos = {
            point = point,
            relativePoint = relativePoint or point,
            x = math.floor((x or 0) + 0.5),
            y = math.floor((y or 0) + 0.5),
        }
    end
end

function Nearby:ApplyPosition()
    if not nearbyFrame or ns:IsInCombat() then
        return
    end
    local pos = (ns.db and ns.db.nearbyPos) or ns.DEFAULTS.nearbyPos
    local sz = (ns.db and ns.db.nearbySize) or ns.DEFAULTS.nearbySize
    nearbyFrame:ClearAllPoints()
    nearbyFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    nearbyFrame:SetSize(sz.width or FRAME_WIDTH, sz.height or 360)
    self:SyncContentWidth()
end

function Nearby:SyncContentWidth()
    if not nearbyFrame then
        return
    end
    local w = math.max(180, (nearbyFrame:GetWidth() or FRAME_WIDTH) - 16)
    CONTENT_WIDTH = w
    if scrollChild then
        scrollChild:SetWidth(w)
    end
    for i = 1, #slotPool do
        slotPool[i]:SetWidth(w)
    end
    self:UpdateStatusBar()
end

function Nearby:UpdateLockState()
    if not nearbyFrame or ns:IsInCombat() then
        return
    end
    local locked = ns.db and ns.db.locked
    nearbyFrame:EnableMouse(not locked)
    nearbyFrame:SetMovable(not locked)
    if nearbyFrame.resizeBtn then
        if locked then
            nearbyFrame.resizeBtn:Hide()
        else
            nearbyFrame.resizeBtn:Show()
        end
    end
end

-- Tek seferlik kisa ses + vurgu animasyonu (sessiz mod destekli)
local function TriggerFirstApproachAlert(row)
    local db = ns.db or ns.DEFAULTS
    if db.soundEnabled then
        local soundID = (type(_G.SOUNDKIT) == "table" and (_G.SOUNDKIT.MAP_PING or _G.SOUNDKIT.IG_QUEST_LIST_OPEN)) or 3175
        ns:PlayAddonSound(soundID)
    end
    if row and row.pulseAnim then
        row.pulseAnim:Stop()
        row.pulseAnim:Play()
    end
end

local function ShowQuestTooltip(anchor, row)
    if not GameTooltip or not row or not row.questID then
        return
    end
    GameTooltip:SetOwner(anchor, "ANCHOR_LEFT")
    GameTooltip:SetText(row.questTitle or ("Gorev #" .. tostring(row.questID)), 1, 0.85, 0.2)

    if row.zoneName and row.zoneName ~= "" then
        GameTooltip:AddLine("Bolge: " .. row.zoneName, 0.75, 0.85, 1.0)
    end

    if row.groupType == "trainer" then
        GameTooltip:AddLine("Durum: Sinifina en yakin Class Trainer", 0.90, 0.55, 1.0)
    elseif row.groupType == "completed" then
        GameTooltip:AddLine("Durum: Tamamlandi (Teslim NPC'sine git)", 0.3, 1.0, 0.4)
    elseif row.groupType == "available" then
        GameTooltip:AddLine("Durum: Alinmamis (Gorev veren NPC)", 0.25, 0.85, 1.0)
    else
        GameTooltip:AddLine("Durum: Yapilmakta olan gorev", 1.0, 0.85, 0.25)
    end

    if row.fallbackLoc and ns:IsSafeNumber(row.fallbackLoc.x) and ns:IsSafeNumber(row.fallbackLoc.y)
        and (row.fallbackLoc.x > 0 or row.fallbackLoc.y > 0) then
        GameTooltip:AddLine(string.format("Konum: %.1f, %.1f", row.fallbackLoc.x * 100, row.fallbackLoc.y * 100), 0.75, 0.85, 1.0)
    end

    if row.groupType == "active" then
        local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", row.questID)
        if okObj and type(objectives) == "table" and #objectives > 0 then
            GameTooltip:AddLine(" ")
            for i = 1, math.min(#objectives, 5) do
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

    GameTooltip:AddLine(" ")
    if row.hasLocation then
        GameTooltip:AddLine("Sol ok veya satira tikla: Haritada yonlendir", 0.7, 0.8, 0.9)
    else
        GameTooltip:AddLine("Bu gorev icin konum bilgisi bulunamadi.", 1.0, 0.4, 0.4)
    end
    GameTooltip:Show()
end

local function CreateSlot(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.05)
    row.bg = bg

    local flash = row:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints()
    flash:SetColorTexture(1.0, 0.85, 0.2, 0.0)
    row.flash = flash

    local ag = flash:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0.0)
    a1:SetToAlpha(0.75)
    a1:SetDuration(0.25)
    a1:SetOrder(1)

    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.75)
    a2:SetToAlpha(0.0)
    a2:SetDuration(0.55)
    a2:SetOrder(2)
    row.pulseAnim = ag

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 0.7, 1.0, 0.18)
    row.highlightTex = highlight

    -- En solda saga dogru bakan mini yonlendirme oku butonu
    local goBtn = CreateFrame("Button", nil, row)
    goBtn:SetSize(16, 16)
    goBtn:SetPoint("LEFT", row, "LEFT", 3, 0)
    goBtn:SetMotionScriptsWhileDisabled(true)

    local goIcon = goBtn:CreateTexture(nil, "ARTWORK")
    goIcon:SetAllPoints()
    goIcon:SetTexture("Interface\\Minimap\\MinimapArrow")
    goIcon:SetDesaturated(true)
    goIcon:SetRotation(-math.pi / 2) -- Saga bakan mini ok
    goBtn.icon = goIcon

    local goHl = goBtn:CreateTexture(nil, "HIGHLIGHT")
    goHl:SetAllPoints()
    goHl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    goHl:SetBlendMode("ADD")

    goBtn:SetScript("OnClick", function()
        if ns:IsInCombat() then
            ns:Print("Combat sirasinda UI degisikligi engellendi.")
            return
        end
        if row.questID then
            ns:ToggleQuestWaypoint(row.questID, row.fallbackLoc)
        end
    end)

    goBtn:SetScript("OnEnter", function(selfBtn)
        ShowQuestTooltip(selfBtn, row)
    end)

    goBtn:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    row.goBtn = goBtn

    local titleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleText:SetPoint("LEFT", row, "LEFT", 22, 0)
    titleText:SetPoint("RIGHT", row, "RIGHT", -56, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    row.titleText = titleText

    local distText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    distText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    distText:SetJustifyH("RIGHT")
    row.distText = distText

    row:SetScript("OnClick", function(selfRow)
        if selfRow.isGroupHeader then
            if selfRow.groupKey then
                collapsedGroups[selfRow.groupKey] = not collapsedGroups[selfRow.groupKey]
                Nearby:ScanOnce()
            end
            return
        end
        if ns:IsInCombat() then
            ns:Print("Combat sirasinda UI degisikligi engellendi.")
            return
        end
        if selfRow.questID then
            ns:ToggleQuestWaypoint(selfRow.questID, selfRow.fallbackLoc)
        end
    end)

    row:SetScript("OnEnter", function(selfRow)
        if selfRow.isGroupHeader then
            return
        end
        ShowQuestTooltip(selfRow, selfRow)
    end)

    row:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    row:Hide()
    return row
end

local function GetSlot(index)
    if not slotPool[index] then
        slotPool[index] = CreateSlot(scrollChild)
    end
    return slotPool[index]
end

local function FormatShortNumber(n)
    if not ns:IsSafeNumber(n) then
        return "0"
    end
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(math.floor(n + 0.5))
end

local function CreateStatusBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -(HEADER_HEIGHT + 2))
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -(HEADER_HEIGHT + 2))
    bar:SetHeight(STATUS_BAR_HEIGHT)

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.02, 0.04, 0.08, 0.36)

    -- 1. Satir: Level + XP Progress Bar
    local lvlText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lvlText:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -3)
    lvlText:SetWidth(40)
    lvlText:SetJustifyH("LEFT")
    lvlText:SetTextColor(1.0, 0.85, 0.20)
    bar.lvlText = lvlText

    local xpBar = CreateFrame("StatusBar", nil, bar)
    xpBar:SetPoint("TOPLEFT", bar, "TOPLEFT", 46, -3)
    xpBar:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, -3)
    xpBar:SetHeight(14)
    xpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    xpBar:SetMinMaxValues(0, 1)
    xpBar:SetValue(0)
    xpBar:SetStatusBarColor(0.45, 0.25, 0.85, 0.95)
    xpBar:EnableMouse(true)

    local xpBg = xpBar:CreateTexture(nil, "BACKGROUND")
    xpBg:SetAllPoints()
    xpBg:SetColorTexture(0.10, 0.12, 0.18, 0.90)

    local xpText = xpBar:CreateFontString(nil, "OVERLAY")
    xpText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    xpText:SetPoint("CENTER", xpBar, "CENTER", 0, 0)
    xpText:SetTextColor(1, 1, 1)
    bar.xpText = xpText
    bar.xpBar = xpBar

    xpBar:SetScript("OnEnter", function(selfBar)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(selfBar, "ANCHOR_LEFT")
        local okLvl, lvl = ns:SafeGlobal("UnitLevel", "player")
        local okXp, curXp = ns:SafeGlobal("UnitXP", "player")
        local okMax, maxXp = ns:SafeGlobal("UnitXPMax", "player")
        local okRest, restXp = ns:SafeGlobal("GetXPExhaustion")

        GameTooltip:SetText("Seviye " .. tostring(okLvl and lvl or "?"), 1, 0.85, 0.2)
        if okXp and okMax and ns:IsSafeNumber(curXp) and ns:IsSafeNumber(maxXp) and maxXp > 0 then
            local pct = (curXp / maxXp) * 100
            local rem = math.max(0, maxXp - curXp)
            GameTooltip:AddLine(string.format("XP: %s / %s (%.1f%%)", FormatShortNumber(curXp), FormatShortNumber(maxXp), pct), 0.9, 0.9, 0.9)
            GameTooltip:AddLine("Sonraki seviye icin kalan: " .. FormatShortNumber(rem) .. " XP", 0.75, 0.85, 1.0)
            if okRest and ns:IsSafeNumber(restXp) and restXp > 0 then
                GameTooltip:AddLine("Dinlenmis (Rested): +" .. FormatShortNumber(restXp) .. " XP", 0.35, 0.75, 1.0)
            end
        else
            GameTooltip:AddLine("Maksimum seviye", 0.3, 1.0, 0.4)
        end
        GameTooltip:Show()
    end)

    xpBar:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- 2. Satir: Meslekler
    local profRow = CreateFrame("Frame", nil, bar)
    profRow:SetPoint("TOPLEFT", bar, "TOPLEFT", 3, -21)
    profRow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -3, 2)
    bar.profRow = profRow

    local noProfText = profRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noProfText:SetPoint("LEFT", profRow, "LEFT", 2, 0)
    noProfText:SetText("Meslek ogrenilmemis")
    noProfText:Hide()
    bar.noProfText = noProfText

    for i = 1, 5 do
        local pBtn = CreateFrame("Button", nil, profRow)
        pBtn:SetHeight(16)
        pBtn:EnableMouse(true)

        local icon = pBtn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", pBtn, "LEFT", 0, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pBtn.icon = icon

        local text = pBtn:CreateFontString(nil, "OVERLAY")
        text:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        text:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        text:SetPoint("RIGHT", pBtn, "RIGHT", -2, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        pBtn.text = text

        pBtn:SetScript("OnEnter", function(selfBtn)
            if not GameTooltip or not selfBtn.profName then
                return
            end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_LEFT")
            GameTooltip:SetText(selfBtn.profName, 1, 0.85, 0.2)
            local sl = selfBtn.skillLevel or 0
            local sm = selfBtn.maxSkillLevel or 0
            if sm > 0 then
                local pct = (sl / sm) * 100
                GameTooltip:AddLine(string.format("Seviye: %d / %d (%.0f%%)", sl, sm, pct), 0.35, 1.0, 0.45)
            else
                GameTooltip:AddLine("Seviye: " .. tostring(sl), 0.9, 0.9, 0.9)
            end
            GameTooltip:Show()
        end)

        pBtn:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)

        pBtn:Hide()
        profSlots[i] = pBtn
    end

    statusBarFrame = bar
    return bar
end

function Nearby:UpdateStatusBar()
    if not statusBarFrame then
        return
    end

    -- Level & XP
    local okLvl, lvl = ns:SafeGlobal("UnitLevel", "player")
    local okXp, curXp = ns:SafeGlobal("UnitXP", "player")
    local okMax, maxXp = ns:SafeGlobal("UnitXPMax", "player")
    local okRest, restXp = ns:SafeGlobal("GetXPExhaustion")

    statusBarFrame.lvlText:SetText("Lv " .. tostring((okLvl and ns:IsSafeNumber(lvl)) and lvl or "?"))

    if okXp and okMax and ns:IsSafeNumber(curXp) and ns:IsSafeNumber(maxXp) and maxXp > 0 then
        local pct = (curXp / maxXp) * 100
        statusBarFrame.xpBar:SetMinMaxValues(0, maxXp)
        statusBarFrame.xpBar:SetValue(curXp)
        if okRest and ns:IsSafeNumber(restXp) and restXp > 0 then
            statusBarFrame.xpBar:SetStatusBarColor(0.18, 0.55, 0.95, 0.95)
        else
            statusBarFrame.xpBar:SetStatusBarColor(0.52, 0.26, 0.86, 0.95)
        end
        statusBarFrame.xpText:SetText(string.format("%.0f%% (%s/%s)", pct, FormatShortNumber(curXp), FormatShortNumber(maxXp)))
    else
        statusBarFrame.xpBar:SetMinMaxValues(0, 1)
        statusBarFrame.xpBar:SetValue(1)
        statusBarFrame.xpBar:SetStatusBarColor(0.20, 0.72, 0.35, 0.90)
        statusBarFrame.xpText:SetText("MAX SEVIYE")
    end

    -- Meslekler (GetProfessions + GetProfessionInfo)
    local profs = {}
    local okP, p1, p2, arch, fish, cook = ns:SafeGlobal("GetProfessions")
    if okP then
        local indices = { p1, p2, cook, fish, arch }
        for i = 1, #indices do
            local idx = indices[i]
            if ns:IsSafeNumber(idx) then
                local okInfo, name, icon, skillLevel, maxSkillLevel = ns:SafeGlobal("GetProfessionInfo", idx)
                if okInfo and ns:IsSafeString(name) and name ~= "" then
                    table.insert(profs, {
                        name = name,
                        icon = icon,
                        skillLevel = ns:IsSafeNumber(skillLevel) and skillLevel or 0,
                        maxSkillLevel = ns:IsSafeNumber(maxSkillLevel) and maxSkillLevel or 0,
                    })
                end
            end
        end
    end

    local count = math.min(#profs, #profSlots)
    if count == 0 then
        statusBarFrame.noProfText:Show()
        for i = 1, #profSlots do
            profSlots[i]:Hide()
        end
        return
    end

    statusBarFrame.noProfText:Hide()
    local totalW = CONTENT_WIDTH - 6
    local slotW = math.floor(totalW / count)

    for i = 1, #profSlots do
        local slot = profSlots[i]
        local p = profs[i]
        if p and i <= count then
            slot.profName = p.name
            slot.skillLevel = p.skillLevel
            slot.maxSkillLevel = p.maxSkillLevel
            slot:SetWidth(slotW)
            slot:ClearAllPoints()
            slot:SetPoint("LEFT", statusBarFrame.profRow, "LEFT", (i - 1) * slotW, 0)
            slot.icon:SetTexture(p.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

            if count <= 2 then
                local shortName = (#p.name > 8) and (p.name:sub(1, 7) .. ".") or p.name
                slot.text:SetText(string.format("%s %d/%d", shortName, p.skillLevel, p.maxSkillLevel))
            elseif count == 3 then
                slot.text:SetText(string.format("%d/%d", p.skillLevel, p.maxSkillLevel))
            else
                slot.text:SetText(tostring(p.skillLevel))
            end

            if p.maxSkillLevel > 0 and p.skillLevel >= p.maxSkillLevel then
                slot.text:SetTextColor(0.30, 1.0, 0.45)
            else
                slot.text:SetTextColor(0.92, 0.92, 0.95)
            end
            slot:Show()
        else
            slot:Hide()
        end
    end
end

local function CreateNearbyFrame()
    if nearbyFrame then
        return nearbyFrame
    end

    local f = CreateFrame("Frame", "QuestGoToZNearbyFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_WIDTH, HEADER_HEIGHT + STATUS_BAR_HEIGHT + 24)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.06, 0.10, 0.48)
    f:SetBackdropBorderColor(0.35, 0.55, 0.80, 0.42)

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(selfFrame)
        if ns:IsInCombat() or (ns.db and ns.db.locked) then
            return
        end
        selfFrame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        SaveNearbyPosition(selfFrame)
    end)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -7)
    header:SetPoint("RIGHT", f, "RIGHT", -118, 0)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    header:SetText("Gorevler")
    f.header = header

    -- Ozellik 2: Tek "Siradaki" butonu (en yuksek puanli gorevi secer, nedenini tooltip'te gosterir)
    local nextBtn = CreateFrame("Button", nil, f)
    nextBtn:SetSize(54, 16)
    nextBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -5)
    local nextBg = nextBtn:CreateTexture(nil, "BACKGROUND")
    nextBg:SetAllPoints()
    nextBg:SetColorTexture(0.18, 0.42, 0.24, 0.88)
    nextBtn.bg = nextBg
    local nextHl = nextBtn:CreateTexture(nil, "HIGHLIGHT")
    nextHl:SetAllPoints()
    nextHl:SetColorTexture(0.35, 0.85, 0.45, 0.28)
    local nextTxt = nextBtn:CreateFontString(nil, "OVERLAY")
    nextTxt:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    nextTxt:SetAllPoints()
    nextTxt:SetText("Siradaki")
    nextTxt:SetTextColor(0.85, 1.0, 0.88)
    nextBtn:SetScript("OnClick", function()
        if ns:IsInCombat() then
            ns:Print("Combat sirasinda UI degisikligi engellendi.")
            return
        end
        if ns.SmartQuest then
            ns.SmartQuest:SelectBestQuest(nil, false)
        end
    end)
    nextBtn:SetScript("OnEnter", function(selfBtn)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Siradaki En Iyi Gorev", 0.3, 1.0, 0.45)
        local best = ns.SmartQuest and ns.SmartQuest:EvaluateBestQuest(nil)
        if best then
            GameTooltip:AddLine(best.title, 1, 0.85, 0.2)
            GameTooltip:AddLine("Secilme nedeni: " .. best.reason, 0.75, 0.90, 1.0, true)
            GameTooltip:AddLine(string.format("Puan: %.1f", best.score), 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Bu haritada uygun gorev bulunamadi.", 0.8, 0.5, 0.5)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Tikla: Waypoint koy ve yonlendir", 0.75, 0.82, 0.90)
        GameTooltip:Show()
    end)
    nextBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.nextBtn = nextBtn

    local radiusLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    radiusLabel:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)
    f.radiusLabel = radiusLabel

    CreateStatusBar(f)

    scrollFrame = CreateFrame("ScrollFrame", "QuestGoToZNearbyScrollFrame", f)
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(HEADER_HEIGHT + STATUS_BAR_HEIGHT + 6))
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 16)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(selfScroll, delta)
        local cur = selfScroll:GetVerticalScroll() or 0
        local maxScroll = selfScroll:GetVerticalScrollRange() or 0
        local nextVal = cur - (delta * (ROW_HEIGHT * 2))
        if nextVal < 0 then
            nextVal = 0
        elseif nextVal > maxScroll then
            nextVal = maxScroll
        end
        selfScroll:SetVerticalScroll(nextVal)
    end)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(CONTENT_WIDTH, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Koseden surukleyerek serbest boyutlandirma (Resize Grip)
    f:SetResizable(true)
    if type(f.SetResizeBounds) == "function" then
        f:SetResizeBounds(220, 140, 560, 740)
    elseif type(f.SetMinResize) == "function" then
        f:SetMinResize(220, 140)
        if type(f.SetMaxResize) == "function" then
            f:SetMaxResize(560, 740)
        end
    end

    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not ns:IsInCombat() and not (ns.db and ns.db.locked) then
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if ns.db then
            ns.db.nearbySize = {
                width = math.floor((f:GetWidth() or FRAME_WIDTH) + 0.5),
                height = math.floor((f:GetHeight() or 360) + 0.5),
            }
        end
        Nearby:SyncContentWidth()
    end)
    resizeBtn:SetScript("OnEnter", function(selfBtn)
        if GameTooltip then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_LEFT")
            GameTooltip:SetText("Surukleyerek boyutlandir", 1, 0.85, 0.2)
            GameTooltip:Show()
        end
    end)
    resizeBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.resizeBtn = resizeBtn

    f:SetScript("OnSizeChanged", function()
        Nearby:SyncContentWidth()
    end)

    nearbyFrame = f
    Nearby:ApplyPosition()
    Nearby:UpdateLockState()
    f:Hide()
    return f
end

-- Sinifa gore Class Trainer konumlari (mapID = Retail/Forever UiMapID, x/y = 0..1)
local CLASS_TRAINERS = {
    WARRIOR = {
        { faction = "Alliance", mapID = 37,   name = "Lyria Du Lac",       x = 0.411, y = 0.658 }, -- Elwynn (Goldshire)
        { faction = "Alliance", mapID = 84,   name = "Wu Shen",            x = 0.786, y = 0.456 }, -- Stormwind
        { faction = "Alliance", mapID = 27,   name = "Granis Swiftaxe",    x = 0.474, y = 0.526 }, -- Dun Morogh (Kharanos)
        { faction = "Alliance", mapID = 87,   name = "Bilban Tosslespanner", x = 0.658, y = 0.884 }, -- Ironforge
        { faction = "Alliance", mapID = 57,   name = "Kyra Windblade",     x = 0.562, y = 0.592 }, -- Teldrassil (Dolanaar)
        { faction = "Alliance", mapID = 89,   name = "Arias'ta Bladesinger", x = 0.588, y = 0.348 }, -- Darnassus
        { faction = "Alliance", mapID = 103,  name = "Behomat",            x = 0.556, y = 0.822 }, -- Exodar
        { faction = "Horde",    mapID = 1,    name = "Tarshaw Jaggedscar", x = 0.542, y = 0.424 }, -- Durotar (Razor Hill)
        { faction = "Horde",    mapID = 85,   name = "Grezz Ragefist",     x = 0.798, y = 0.314 }, -- Orgrimmar
        { faction = "Horde",    mapID = 7,    name = "Krang Stonehoof",    x = 0.495, y = 0.606 }, -- Mulgore (Bloodhoof)
        { faction = "Horde",    mapID = 88,   name = "Torm Ragetotem",     x = 0.576, y = 0.872 }, -- Thunder Bluff
        { faction = "Horde",    mapID = 18,   name = "Austil de Mon",      x = 0.619, y = 0.525 }, -- Tirisfal (Brill)
        { faction = "Horde",    mapID = 90,   name = "Baltus Fowler",      x = 0.473, y = 0.171 }, -- Undercity
        { faction = "Horde",    mapID = 110,  name = "Alsia",              x = 0.916, y = 0.376 }, -- Silvermoon
    },
    PALADIN = {
        { faction = "Alliance", mapID = 37,   name = "Brother Wilhelm",    x = 0.411, y = 0.660 }, -- Elwynn (Goldshire)
        { faction = "Alliance", mapID = 84,   name = "Lord Grayson Shadowbreaker", x = 0.526, y = 0.451 }, -- Stormwind
        { faction = "Alliance", mapID = 27,   name = "Azar Stronghammer",  x = 0.476, y = 0.521 }, -- Dun Morogh
        { faction = "Alliance", mapID = 87,   name = "Brandur Ironhammer", x = 0.232, y = 0.062 }, -- Ironforge
        { faction = "Alliance", mapID = 103,  name = "Jol",                x = 0.380, y = 0.822 }, -- Exodar
        { faction = "Horde",    mapID = 110,  name = "Champion Bachi",     x = 0.920, y = 0.374 }, -- Silvermoon
        { faction = "Horde",    mapID = 85,   name = "Master Pyreanor",    x = 0.492, y = 0.712 }, -- Orgrimmar
        { faction = "Horde",    mapID = 88,   name = "Sunwalker Atohmo",   x = 0.630, y = 0.798 }, -- Thunder Bluff
    },
    HUNTER = {
        { faction = "Alliance", mapID = 37,   name = "Khelden Bremen",     x = 0.418, y = 0.656 }, -- Elwynn
        { faction = "Alliance", mapID = 84,   name = "Einris Brightspear", x = 0.616, y = 0.152 }, -- Stormwind
        { faction = "Alliance", mapID = 27,   name = "Grif Wildheart",     x = 0.458, y = 0.530 }, -- Dun Morogh
        { faction = "Alliance", mapID = 87,   name = "Olmin Burningbeard", x = 0.708, y = 0.836 }, -- Ironforge
        { faction = "Alliance", mapID = 57,   name = "Dazalar",            x = 0.567, y = 0.595 }, -- Teldrassil
        { faction = "Alliance", mapID = 89,   name = "Jocaste",            x = 0.404, y = 0.088 }, -- Darnassus
        { faction = "Alliance", mapID = 103,  name = "Deremiis",           x = 0.474, y = 0.892 }, -- Exodar
        { faction = "Horde",    mapID = 1,    name = "Thotar",             x = 0.518, y = 0.435 }, -- Durotar
        { faction = "Horde",    mapID = 85,   name = "Ormak Grimshot",     x = 0.660, y = 0.185 }, -- Orgrimmar
        { faction = "Horde",    mapID = 7,    name = "Yaw Sharpmane",      x = 0.478, y = 0.557 }, -- Mulgore
        { faction = "Horde",    mapID = 88,   name = "Kary Thunderhorn",   x = 0.584, y = 0.882 }, -- Thunder Bluff
        { faction = "Horde",    mapID = 110,  name = "Zandine",            x = 0.844, y = 0.280 }, -- Silvermoon
    },
    ROGUE = {
        { faction = "Alliance", mapID = 37,   name = "Keryn Sylvius",      x = 0.439, y = 0.659 }, -- Elwynn (Goldshire)
        { faction = "Alliance", mapID = 84,   name = "Osborne the Night Man", x = 0.746, y = 0.528 }, -- Stormwind
        { faction = "Alliance", mapID = 27,   name = "Hogral Bakkan",      x = 0.476, y = 0.526 }, -- Dun Morogh
        { faction = "Alliance", mapID = 87,   name = "Fenthwick",          x = 0.515, y = 0.153 }, -- Ironforge
        { faction = "Alliance", mapID = 57,   name = "Jannok Breezesong",  x = 0.564, y = 0.601 }, -- Teldrassil
        { faction = "Alliance", mapID = 89,   name = "Syurna",             x = 0.370, y = 0.219 }, -- Darnassus
        { faction = "Horde",    mapID = 1,    name = "Kaplak",             x = 0.520, y = 0.437 }, -- Durotar
        { faction = "Horde",    mapID = 85,   name = "Shenthul",           x = 0.431, y = 0.537 }, -- Orgrimmar
        { faction = "Horde",    mapID = 18,   name = "Marion Call",        x = 0.618, y = 0.520 }, -- Tirisfal (Brill)
        { faction = "Horde",    mapID = 90,   name = "Gregory Charles",    x = 0.846, y = 0.732 }, -- Undercity
        { faction = "Horde",    mapID = 110,  name = "Zelanis",            x = 0.796, y = 0.520 }, -- Silvermoon
    },
    PRIEST = {
        { faction = "Alliance", mapID = 37,   name = "Priestess Josetta",  x = 0.433, y = 0.657 }, -- Elwynn (Goldshire)
        { faction = "Alliance", mapID = 84,   name = "High Priestess Laurena", x = 0.497, y = 0.449 }, -- Stormwind
        { faction = "Alliance", mapID = 27,   name = "Maxan Anvol",        x = 0.473, y = 0.522 }, -- Dun Morogh
        { faction = "Alliance", mapID = 87,   name = "High Priest Rohan",  x = 0.250, y = 0.082 }, -- Ironforge
        { faction = "Alliance", mapID = 57,   name = "Laurna Morninglight", x = 0.556, y = 0.568 }, -- Teldrassil
        { faction = "Alliance", mapID = 89,   name = "Jandria",            x = 0.379, y = 0.827 }, -- Darnassus
        { faction = "Alliance", mapID = 103,  name = "Caedmos",            x = 0.386, y = 0.510 }, -- Exodar
        { faction = "Horde",    mapID = 1,    name = "Tai'jin",            x = 0.543, y = 0.429 }, -- Durotar
        { faction = "Horde",    mapID = 85,   name = "Ur'kyo",             x = 0.356, y = 0.878 }, -- Orgrimmar
        { faction = "Horde",    mapID = 18,   name = "Dark Cleric Beryl",  x = 0.616, y = 0.522 }, -- Tirisfal (Brill)
        { faction = "Horde",    mapID = 90,   name = "Aelthalyste",        x = 0.491, y = 0.183 }, -- Undercity
        { faction = "Horde",    mapID = 110,  name = "Belestra",           x = 0.554, y = 0.248 }, -- Silvermoon
    },
    SHAMAN = {
        { faction = "Alliance", mapID = 84,   name = "Farseer Umbrua",     x = 0.618, y = 0.838 }, -- Stormwind
        { faction = "Alliance", mapID = 87,   name = "Farseer Javad",      x = 0.552, y = 0.295 }, -- Ironforge
        { faction = "Alliance", mapID = 103,  name = "Farseer Nobundo",    x = 0.312, y = 0.278 }, -- Exodar
        { faction = "Horde",    mapID = 1,    name = "Swart",              x = 0.544, y = 0.426 }, -- Durotar
        { faction = "Horde",    mapID = 85,   name = "Sagorne Creststrider", x = 0.386, y = 0.360 }, -- Orgrimmar
        { faction = "Horde",    mapID = 7,    name = "Narm Skychaser",     x = 0.484, y = 0.592 }, -- Mulgore
        { faction = "Horde",    mapID = 88,   name = "Beram Skychaser",    x = 0.222, y = 0.190 }, -- Thunder Bluff
    },
    MAGE = {
        { faction = "Alliance", mapID = 37,   name = "Zaldimar Wefhellt",  x = 0.433, y = 0.662 }, -- Elwynn (Goldshire)
        { faction = "Alliance", mapID = 84,   name = "Elsharin",           x = 0.369, y = 0.812 }, -- Stormwind
        { faction = "Alliance", mapID = 27,   name = "Magis Sparkmantle",  x = 0.475, y = 0.521 }, -- Dun Morogh
        { faction = "Alliance", mapID = 87,   name = "Dink",               x = 0.271, y = 0.085 }, -- Ironforge
        { faction = "Alliance", mapID = 89,   name = "Mordent Evenshade",  x = 0.404, y = 0.816 }, -- Darnassus
        { faction = "Alliance", mapID = 103,  name = "Edirah",             x = 0.460, y = 0.614 }, -- Exodar
        { faction = "Horde",    mapID = 1,    name = "Un'Thuwa",           x = 0.563, y = 0.751 }, -- Durotar
        { faction = "Horde",    mapID = 85,   name = "Enyo",               x = 0.388, y = 0.857 }, -- Orgrimmar
        { faction = "Horde",    mapID = 18,   name = "Cain Firesong",      x = 0.619, y = 0.525 }, -- Tirisfal (Brill)
        { faction = "Horde",    mapID = 90,   name = "Anastasia Hartwell", x = 0.851, y = 0.100 }, -- Undercity
        { faction = "Horde",    mapID = 110,  name = "Inethven",           x = 0.570, y = 0.210 }, -- Silvermoon
    },
    WARLOCK = {
        { faction = "Alliance", mapID = 37,   name = "Maximillian Crowe",  x = 0.444, y = 0.662 }, -- Elwynn (Goldshire)
        { faction = "Alliance", mapID = 84,   name = "Demisette Cloyce",   x = 0.254, y = 0.782 }, -- Stormwind
        { faction = "Alliance", mapID = 27,   name = "Gimrizz Shadowcog",  x = 0.473, y = 0.537 }, -- Dun Morogh
        { faction = "Alliance", mapID = 87,   name = "Briarthorn",         x = 0.504, y = 0.062 }, -- Ironforge
        { faction = "Horde",    mapID = 1,    name = "Dhugru Gorelust",    x = 0.547, y = 0.415 }, -- Durotar
        { faction = "Horde",    mapID = 85,   name = "Mirket",             x = 0.486, y = 0.470 }, -- Orgrimmar
        { faction = "Horde",    mapID = 18,   name = "Rupert Boch",        x = 0.616, y = 0.524 }, -- Tirisfal (Brill)
        { faction = "Horde",    mapID = 90,   name = "Kaal Soulreaper",    x = 0.862, y = 0.159 }, -- Undercity
        { faction = "Horde",    mapID = 110,  name = "Alamma",             x = 0.744, y = 0.476 }, -- Silvermoon
    },
    DRUID = {
        { faction = "Alliance", mapID = 84,   name = "Celestine of the Harvest", x = 0.576, y = 0.248 }, -- Stormwind
        { faction = "Alliance", mapID = 57,   name = "Kal",                x = 0.559, y = 0.616 }, -- Teldrassil
        { faction = "Alliance", mapID = 89,   name = "Mathrengyl Bearwalker", x = 0.354, y = 0.084 }, -- Darnassus
        { faction = "Horde",    mapID = 85,   name = "Sesebi",             x = 0.350, y = 0.680 }, -- Orgrimmar
        { faction = "Horde",    mapID = 7,    name = "Gennia Runetotem",   x = 0.485, y = 0.596 }, -- Mulgore
        { faction = "Horde",    mapID = 88,   name = "Turak Runetotem",    x = 0.765, y = 0.272 }, -- Thunder Bluff
    },
    MONK = {
        { faction = "Alliance", mapID = 37,   name = "Bao",                x = 0.416, y = 0.654 }, -- Elwynn
        { faction = "Alliance", mapID = 84,   name = "Master Woo Ping",    x = 0.692, y = 0.194 }, -- Stormwind
        { faction = "Alliance", mapID = 87,   name = "Lo",                 x = 0.312, y = 0.228 }, -- Ironforge
        { faction = "Horde",    mapID = 85,   name = "Master Hwang",       x = 0.708, y = 0.494 }, -- Orgrimmar
        { faction = "Horde",    mapID = 88,   name = "Tuu",                x = 0.320, y = 0.652 }, -- Thunder Bluff
        { faction = "Horde",    mapID = 90,   name = "Ting, Strong of Stomach", x = 0.556, y = 0.506 }, -- Undercity
    },
    DEATHKNIGHT = {
        { faction = "Neutral",  mapID = 84,   name = "Stormwind Keep",     x = 0.786, y = 0.456 },
        { faction = "Neutral",  mapID = 85,   name = "Orgrimmar",          x = 0.798, y = 0.314 },
    },
    DEMONHUNTER = {
        { faction = "Alliance", mapID = 84,   name = "Stormwind Keep",     x = 0.786, y = 0.456 },
        { faction = "Horde",    mapID = 85,   name = "Orgrimmar",          x = 0.798, y = 0.314 },
    },
    EVOKER = {
        { faction = "Alliance", mapID = 84,   name = "Stormwind Keep",     x = 0.786, y = 0.456 },
        { faction = "Horde",    mapID = 85,   name = "Orgrimmar",          x = 0.798, y = 0.314 },
    },
}

-- Karakterin sinifina ve tarafina uygun EN YAKIN 1 Class Trainer'i bulur (limit = 1)
local function FindNearestClassTrainer(playerMapID, px, py, mapWidth, mapHeight)
    local okCls, _, classFile = ns:SafeGlobal("UnitClass", "player")
    if not okCls or not ns:IsSafeString(classFile) then
        return nil
    end

    local list = CLASS_TRAINERS[classFile]
    if type(list) ~= "table" or #list == 0 then
        return nil
    end

    local okFac, playerFaction = ns:SafeGlobal("UnitFactionGroup", "player")
    playerFaction = (okFac and ns:IsSafeString(playerFaction)) and playerFaction or nil

    -- Oyuncunun dunya koordinatini al (farkli haritalardaki ayni kita mesafesi icin)
    local pCont, pWorld = nil, nil
    if playerMapID and ns:IsSafeNumber(px) and ns:IsSafeNumber(py) and type(_G.CreateVector2D) == "function" then
        local okP, cont, wPos = ns:TrySafeC("C_Map", "GetWorldPosFromMapPos", playerMapID, _G.CreateVector2D(px, py))
        if okP and cont and wPos then
            pCont, pWorld = cont, wPos
        end
    end

    local best = nil
    local bestDist = math.huge
    local fallbackFirst = nil

    for i = 1, #list do
        local t = list[i]
        if t.faction == "Neutral" or not playerFaction or t.faction == playerFaction then
            if not fallbackFirst then
                fallbackFirst = t
            end

            local dist = nil
            if playerMapID and mapWidth and t.mapID == playerMapID then
                dist = ns:ComputeDistanceAndAngle(px, py, t.x, t.y, mapWidth, mapHeight)
            elseif pCont and pWorld and type(_G.CreateVector2D) == "function" then
                local okT, tCont, tWorld = ns:TrySafeC("C_Map", "GetWorldPosFromMapPos", t.mapID, _G.CreateVector2D(t.x, t.y))
                if okT and tCont and tCont == pCont and tWorld then
                    local dx = (tWorld.x or 0) - (pWorld.x or 0)
                    local dy = (tWorld.y or 0) - (pWorld.y or 0)
                    dist = math.sqrt(dx * dx + dy * dy) * 0.9144
                end
            end

            if dist and dist < bestDist then
                bestDist = dist
                best = t
            end
        end
    end

    local chosen = best or fallbackFirst
    if not chosen then
        return nil
    end

    local zoneName = ns:GetMapName(chosen.mapID) or "Sehir"
    return {
        questID = -(chosen.mapID * 1000 + math.floor(chosen.x * 100)), -- Benzersiz negatif ID (gorevlerle cakismaz)
        title = chosen.name .. " (" .. zoneName .. ")",
        groupType = "trainer",
        isComplete = false,
        isAvailable = false,
        isTrainer = true,
        mapID = chosen.mapID,
        x = chosen.x,
        y = chosen.y,
        dist = (best and bestDist < math.huge) and bestDist or nil,
        hasLocation = true,
        isNearby = false,
        zoneName = zoneName,
        isInCurrentZone = (playerMapID == chosen.mapID),
    }
end

-- Tum gorevleri bulundugun bolge + diger bolgeler seklinde gruplar
local function CollectZoneGroupedQuests(playerMapID, px, py, mapWidth, mapHeight, radius)
    local currentZoneName = (playerMapID and ns:GetMapName(playerMapID))
    if not currentZoneName then
        local okZone, zText = ns:SafeGlobal("GetRealZoneText")
        if okZone and ns:IsSafeString(zText) and zText ~= "" then
            currentZoneName = zText
        else
            currentZoneName = "Mevcut Bolge"
        end
    end

    local foundByID = {}
    local currentZoneGroups = {
        completed = {},
        active = {},
        available = {},
    }
    local otherZoneBuckets = {}
    local otherZoneOrder = {}

    if playerMapID and lastRequestedQuestLineMap ~= playerMapID then
        lastRequestedQuestLineMap = playerMapID
        ns:TrySafeC("C_QuestLine", "RequestQuestLinesForMap", playerMapID)
    end

    local function ComputeDist(qMapID, tx, ty)
        if playerMapID and mapWidth and qMapID == playerMapID and ns:IsSafeNumber(tx) and ns:IsSafeNumber(ty) and (tx > 0 or ty > 0) then
            return ns:ComputeDistanceAndAngle(px, py, tx, ty, mapWidth, mapHeight)
        end
        return nil
    end

    local function AddItem(questID, groupType, title, qMapID, tx, ty, headerZoneName)
        if not ns:IsSafeNumber(questID) or foundByID[questID] then
            return
        end
        foundByID[questID] = true

        if not ns:IsSafeString(title) or title == "" then
            local okTitle, fetched = ns:TrySafeC("C_QuestLog", "GetTitleForQuestID", questID)
            if okTitle and ns:IsSafeString(fetched) and fetched ~= "" then
                title = fetched
            else
                title = "Gorev #" .. tostring(questID)
            end
        end

        local dist = ComputeDist(qMapID, tx, ty)
        local hasLoc = (ns:IsSafeNumber(qMapID) and ns:IsSafeNumber(tx) and ns:IsSafeNumber(ty) and (tx > 0 or ty > 0))
        local isNearby = (dist ~= nil and dist <= radius)

        -- Gorevin bolge adini belirle
        local mapZone = qMapID and ns:GetMapName(qMapID)
        local zoneName = mapZone or headerZoneName or currentZoneName

        local isInCurrentZone = false
        if playerMapID and qMapID == playerMapID then
            isInCurrentZone = true
        elseif zoneName == currentZoneName then
            isInCurrentZone = true
        end

        local entry = {
            questID = questID,
            title = title,
            groupType = groupType,
            isComplete = (groupType == "completed"),
            isAvailable = (groupType == "available"),
            mapID = qMapID,
            x = tx,
            y = ty,
            dist = dist,
            hasLocation = hasLoc,
            isNearby = isNearby,
            zoneName = zoneName,
            isInCurrentZone = isInCurrentZone,
            difficultyTag = ns.Comfort and ns.Comfort:GetQuestDifficultyTag(questID, nil) or nil,
            isDroppable = ns.Comfort and ns.Comfort:IsQuestDroppable(questID, dist, isInCurrentZone, groupType == "completed") or false,
        }

        if isInCurrentZone then
            table.insert(currentZoneGroups[groupType], entry)
        else
            if not otherZoneBuckets[zoneName] then
                otherZoneBuckets[zoneName] = {}
                table.insert(otherZoneOrder, zoneName)
            end
            table.insert(otherZoneBuckets[zoneName], entry)
        end
    end

    -- 1) Gorev gunlugundeki TUM yapilmakta olan ve tamamlanan gorevler (bolge basliklariyla birlikte)
    local okNum, numEntries = ns:TrySafeC("C_QuestLog", "GetNumQuestLogEntries")
    if okNum and ns:IsSafeNumber(numEntries) then
        local currentHeaderName = nil
        for idx = 1, numEntries do
            local okInfo, info = ns:TrySafeC("C_QuestLog", "GetInfo", idx)
            if okInfo and type(info) == "table" then
                if info.isHeader then
                    if ns:IsSafeString(info.title) and info.title ~= "" then
                        currentHeaderName = info.title
                    end
                elseif not info.isHidden and ns:IsSafeNumber(info.questID) then
                    local qid = info.questID
                    local okComp, isComplete = ns:TrySafeC("C_QuestLog", "IsComplete", qid)
                    local grp = (okComp and isComplete == true) and "completed" or "active"
                    local loc = ns:GetQuestLocation(qid)
                    if loc then
                        AddItem(qid, grp, info.title or loc.title, loc.mapID, loc.x, loc.y, currentHeaderName)
                    else
                        AddItem(qid, grp, info.title, nil, nil, nil, currentHeaderName)
                    end
                end
            end
        end
    end

    -- 2) Mevcut haritadaki gorev POI'leri
    if playerMapID then
        local okOnMap, questsOnMap = ns:SafeC("C_QuestLog", "GetQuestsOnMap", playerMapID)
        if okOnMap and type(questsOnMap) == "table" then
            for i = 1, #questsOnMap do
                local info = questsOnMap[i]
                if type(info) == "table" and ns:IsSafeNumber(info.questID) and not foundByID[info.questID] then
                    local okOn, isOn = ns:TrySafeC("C_QuestLog", "IsOnQuest", info.questID)
                    local okComp, isComp = ns:TrySafeC("C_QuestLog", "IsComplete", info.questID)
                    local grp = "available"
                    if okOn and isOn == true then
                        grp = (okComp and isComp == true) and "completed" or "active"
                    end
                    AddItem(info.questID, grp, nil, playerMapID, info.x, info.y, currentZoneName)
                end
            end
        end

        -- 3) Mevcut haritada alinmayan gorevler (C_QuestLine.GetAvailableQuestLines)
        local okLines, questLines = ns:TrySafeC("C_QuestLine", "GetAvailableQuestLines", playerMapID)
        if okLines and type(questLines) == "table" then
            for i = 1, #questLines do
                local ql = questLines[i]
                if type(ql) == "table" and not ql.isHidden and ns:IsSafeNumber(ql.questID) and not foundByID[ql.questID] then
                    local okDone, isDone = ns:TrySafeC("C_QuestLog", "IsQuestFlaggedCompleted", ql.questID)
                    local okOn, isOn = ns:TrySafeC("C_QuestLog", "IsOnQuest", ql.questID)
                    if not (okDone and isDone == true) and not (okOn and isOn == true) then
                        AddItem(ql.questID, "available", ql.questName, playerMapID, ql.x, ql.y, currentZoneName)
                    end
                end
            end
        end
    end

    local function SortItems(a, b)
        local da = a.dist or math.huge
        local dbVal = b.dist or math.huge
        if da ~= dbVal then
            return da < dbVal
        end
        if a.isComplete ~= b.isComplete then
            return a.isComplete
        end
        return (a.title or "") < (b.title or "")
    end

    table.sort(currentZoneGroups.completed, SortItems)
    table.sort(currentZoneGroups.active, SortItems)
    table.sort(currentZoneGroups.available, SortItems)
    table.sort(otherZoneOrder)
    for i = 1, #otherZoneOrder do
        table.sort(otherZoneBuckets[otherZoneOrder[i]], SortItems)
    end

    -- Render edilecek bolum listesini olustur
    local sections = {}
    local db = ns.db or ns.DEFAULTS

    -- Ozellik 1: Birlikte yapilabilecek gorevler grubu
    if db.showClusters and ns.SmartQuest and playerMapID and mapWidth then
        local clusters = ns.SmartQuest:GetCurrentMapClusters()
        for c = 1, #clusters do
            local cl = clusters[c]
            local clusterItems = {}
            for m = 1, #cl.members do
                local mem = cl.members[m]
                table.insert(clusterItems, {
                    questID = mem.questID,
                    title = mem.title,
                    groupType = mem.isComplete and "completed" or "active",
                    isComplete = mem.isComplete,
                    isAvailable = false,
                    mapID = mem.mapID,
                    x = mem.x,
                    y = mem.y,
                    dist = mem.dist,
                    hasLocation = true,
                    isNearby = (mem.dist <= radius),
                    zoneName = currentZoneName,
                    isInCurrentZone = true,
                    difficultyTag = ns.Comfort and ns.Comfort:GetQuestDifficultyTag(mem.questID, nil) or nil,
                    isDroppable = false,
                })
            end
            table.insert(sections, {
                key = "cluster_" .. c,
                label = string.format("Bu bolgede %d gorev birlikte yapilabilir", cl.count),
                color = "|cff55ffcc",
                bgR = 0.06, bgG = 0.24, bgB = 0.22,
                items = clusterItems,
            })
        end
    end

    if #currentZoneGroups.completed > 0 then
        table.insert(sections, {
            key = "cur_completed",
            label = currentZoneName .. " - Tamamlanan",
            color = "|cff33ff66",
            bgR = 0.08, bgG = 0.25, bgB = 0.12,
            items = currentZoneGroups.completed,
        })
    end
    if #currentZoneGroups.active > 0 then
        table.insert(sections, {
            key = "cur_active",
            label = currentZoneName .. " - Alinan",
            color = "|cffffd100",
            bgR = 0.25, bgG = 0.20, bgB = 0.06,
            items = currentZoneGroups.active,
        })
    end
    if #currentZoneGroups.available > 0 then
        table.insert(sections, {
            key = "cur_available",
            label = currentZoneName .. " - Alinmayan",
            color = "|cff33ccff",
            bgR = 0.06, bgG = 0.18, bgB = 0.26,
            items = currentZoneGroups.available,
        })
    end

    -- Sinifa uygun EN YAKIN 1 Class Trainer (limit = 1)
    local nearestTrainer = FindNearestClassTrainer(playerMapID, px, py, mapWidth, mapHeight)
    if nearestTrainer then
        table.insert(sections, {
            key = "nearest_trainer",
            label = "En Yakin Class Trainer",
            color = "|cffff88ff",
            bgR = 0.22, bgG = 0.08, bgB = 0.26,
            items = { nearestTrainer },
        })
    end

    -- Ozellik 6: En Yakin Hizmetler (Satici, Posta, Han, Ucus Noktasi)
    if ns.Comfort then
        local services = ns.Comfort:GetNearestServices(playerMapID, px, py, mapWidth, mapHeight)
        if #services > 0 then
            table.insert(sections, {
                key = "nearest_services",
                label = "En Yakin Hizmetler",
                color = "|cff88ccff",
                bgR = 0.08, bgG = 0.16, bgB = 0.26,
                items = services,
            })
        end
    end

    for i = 1, #otherZoneOrder do
        local zName = otherZoneOrder[i]
        table.insert(sections, {
            key = "zone_" .. zName,
            label = zName,
            color = "|cffb8c4e0",
            bgR = 0.14, bgG = 0.16, bgB = 0.24,
            items = otherZoneBuckets[zName],
        })
    end

    return currentZoneName, sections
end

function Nearby:ScanOnce()
    if not nearbyFrame or not scrollChild then
        return
    end

    self:UpdateStatusBar()

    if ns:IsInCombat() then
        return
    end

    local playerMapID, px, py, mapWidth, mapHeight = ns:GetPlayerPosition()
    local db = ns.db or ns.DEFAULTS
    local radius = db.nearbyRadius or 150

    local currentZoneName, sections = CollectZoneGroupedQuests(playerMapID, px, py, mapWidth, mapHeight, radius)
    local headerText = currentZoneName
    if ns.Comfort then
        local zDone, zTotal = ns.Comfort:GetZoneProgress(playerMapID, currentZoneName)
        if zDone and zTotal and zTotal > 0 then
            headerText = string.format("%s (%d/%d)", currentZoneName, zDone, zTotal)
        end
        local logCount, logCap = ns.Comfort:GetQuestLogUsage()
        local warnT = db.questLogWarnThreshold or 22
        if logCount >= warnT then
            nearbyFrame.radiusLabel:SetText(string.format("|cffff5555%d/%d|r", logCount, logCap))
        else
            nearbyFrame.radiusLabel:SetText(string.format("%d/%d", logCount, logCap))
        end
    else
        nearbyFrame.radiusLabel:SetText(string.format("<=%dm", radius))
    end
    nearbyFrame.header:SetText(headerText)

    if #sections == 0 then
        for i = 1, #slotPool do
            slotPool[i].questID = nil
            slotPool[i].isGroupHeader = false
            slotPool[i]:Hide()
        end
        scrollChild:SetHeight(1)
        if not nearbyFrame:IsShown() then
            nearbyFrame:Show()
        end
        return
    end

    local slotIdx = 1
    local yCursor = 0

    for s = 1, #sections do
        local sec = sections[s]
        local items = sec.items
        local isCollapsed = collapsedGroups[sec.key] and true or false

        local hSlot = GetSlot(slotIdx)
        slotIdx = slotIdx + 1

        hSlot.isGroupHeader = true
        hSlot.groupKey = sec.key
        hSlot.questID = nil
        hSlot.fallbackLoc = nil
        hSlot:SetHeight(GROUP_HEADER_HEIGHT)
        hSlot:ClearAllPoints()
        hSlot:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yCursor)
        hSlot.bg:SetColorTexture(sec.bgR, sec.bgG, sec.bgB, 0.40)
        hSlot.highlightTex:SetAlpha(0.25)
        hSlot.goBtn:Hide()
        hSlot.titleText:ClearAllPoints()
        hSlot.titleText:SetPoint("LEFT", hSlot, "LEFT", 6, 0)
        hSlot.titleText:SetPoint("RIGHT", hSlot, "RIGHT", -6, 0)
        local arrowMark = isCollapsed and "[+]" or "[-]"
        hSlot.titleText:SetText(string.format("%s%s %s (%d)|r", sec.color, arrowMark, sec.label, #items))
        hSlot.distText:SetText("")
        hSlot:Show()

        yCursor = yCursor + GROUP_HEADER_HEIGHT + 2

        if not isCollapsed then
            for i = 1, #items do
                local item = items[i]
                local rSlot = GetSlot(slotIdx)
                slotIdx = slotIdx + 1

                rSlot.isGroupHeader = false
                rSlot.groupKey = nil
                rSlot.questID = item.questID
                rSlot.questTitle = item.title
                rSlot.zoneName = item.zoneName
                rSlot.groupType = item.groupType
                rSlot.isComplete = item.isComplete
                rSlot.hasLocation = item.hasLocation
                rSlot.fallbackLoc = item.hasLocation and {
                    questID = item.questID,
                    mapID = item.mapID,
                    x = item.x,
                    y = item.y,
                    title = item.title,
                    zoneName = item.zoneName,
                    isComplete = item.isComplete,
                    isAvailable = item.isAvailable,
                    isTrainer = item.isTrainer,
                } or nil

                rSlot:SetHeight(ROW_HEIGHT)
                rSlot:ClearAllPoints()
                rSlot:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yCursor)

                local isActiveTarget = (ns.activeQuestID == item.questID)
                rSlot.bg:SetColorTexture(1, 1, 1, isActiveTarget and 0.14 or 0.05)
                rSlot.highlightTex:SetAlpha(1)

                -- En solda saga dogru bakan mini ok butonu
                rSlot.goBtn:Show()
                if item.hasLocation then
                    rSlot.goBtn:Enable()
                    if isActiveTarget then
                        rSlot.goBtn.icon:SetVertexColor(0.20, 1.0, 0.35, 1.0)
                    elseif item.groupType == "trainer" then
                        rSlot.goBtn.icon:SetVertexColor(0.95, 0.50, 1.0, 0.95)
                    elseif item.groupType == "completed" then
                        rSlot.goBtn.icon:SetVertexColor(0.30, 1.0, 0.50, 0.95)
                    elseif item.groupType == "available" then
                        rSlot.goBtn.icon:SetVertexColor(0.25, 0.85, 1.0, 0.95)
                    else
                        rSlot.goBtn.icon:SetVertexColor(1.0, 0.85, 0.20, 0.95)
                    end
                else
                    rSlot.goBtn:Disable()
                    rSlot.goBtn.icon:SetVertexColor(0.45, 0.45, 0.45, 0.50)
                end

                rSlot.titleText:ClearAllPoints()
                rSlot.titleText:SetPoint("LEFT", rSlot, "LEFT", 22, 0)
                rSlot.titleText:SetPoint("RIGHT", rSlot, "RIGHT", -56, 0)
                local statusPrefix = ""
                if not item.isInCurrentZone and item.isComplete then
                    statusPrefix = "|cff33ff66[Teslim]|r "
                end
                if item.difficultyTag then
                    statusPrefix = statusPrefix .. "|cffff4444" .. item.difficultyTag .. "|r "
                end
                local dropSuffix = item.isDroppable and " |cff999999[Birakilabilir]|r" or ""
                rSlot.titleText:SetText(statusPrefix .. item.title .. dropSuffix)

                if item.dist then
                    local r, gCol, b = ns:GetColorForDistance(item.dist)
                    if item.dist >= 1000 then
                        rSlot.distText:SetText(string.format("%.1f km", item.dist / 1000))
                    else
                        rSlot.distText:SetText(string.format("%d m", math.floor(item.dist + 0.5)))
                    end
                    rSlot.distText:SetTextColor(r, gCol, b)
                elseif item.hasLocation then
                    rSlot.distText:SetText("Harita")
                    rSlot.distText:SetTextColor(0.65, 0.72, 0.85)
                else
                    rSlot.distText:SetText("--")
                    rSlot.distText:SetTextColor(0.5, 0.5, 0.5)
                end

                rSlot:Show()

                if item.isNearby and not notifiedQuests[item.questID] then
                    notifiedQuests[item.questID] = true
                    TriggerFirstApproachAlert(rSlot)
                end

                yCursor = yCursor + ROW_HEIGHT + 1
            end
        end

        yCursor = yCursor + 4
    end

    for i = slotIdx, #slotPool do
        slotPool[i].questID = nil
        slotPool[i].isGroupHeader = false
        slotPool[i]:Hide()
    end

    scrollChild:SetHeight(math.max(1, yCursor))
    scrollChild:SetWidth(CONTENT_WIDTH)

    if not nearbyFrame:IsShown() then
        nearbyFrame:Show()
    end
end

-- XP, Level ve Meslek degisikliklerini aninda yansitan hafif event cercevesi
local statusEventFrame = CreateFrame("Frame", "QuestGoToZStatusEventFrame")
statusEventFrame:RegisterEvent("PLAYER_XP_UPDATE")
statusEventFrame:RegisterEvent("PLAYER_LEVEL_UP")
statusEventFrame:RegisterEvent("UPDATE_EXHAUSTION")
statusEventFrame:RegisterEvent("SKILL_LINES_CHANGED")
statusEventFrame:RegisterEvent("CHAT_MSG_SKILL")
statusEventFrame:SetScript("OnEvent", function()
    Nearby:UpdateStatusBar()
end)

function Nearby:StartTicker()
    if scanTicker then
        return
    end
    local ok, ticker = ns:SafeC("C_Timer", "NewTicker", 1.0, function()
        Nearby:ScanOnce()
    end)
    if ok and ticker then
        scanTicker = ticker
    end
end

ns:RegisterCallback("PLAYER_LOGIN", function()
    CreateNearbyFrame()
    Nearby:StartTicker()
    Nearby:ScanOnce()
end)

ns:RegisterCallback("CONFIG_CHANGED", function()
    Nearby:UpdateLockState()
    Nearby:ScanOnce()
end)

ns:RegisterCallback("TARGET_CHANGED", function()
    Nearby:ScanOnce()
end)

ns:RegisterCallback("QUEST_LOG_UPDATE", function()
    Nearby:ScanOnce()
end)

ns:RegisterCallback("ZONE_CHANGED_NEW_AREA", function()
    lastRequestedQuestLineMap = nil
    Nearby:ScanOnce()
end)

ns:RegisterCallback("QUEST_TURNED_IN", function(questID)
    if questID then
        notifiedQuests[questID] = nil
    end
end)

ns:RegisterCallback("QUEST_REMOVED", function(questID)
    if questID then
        notifiedQuests[questID] = nil
    end
end)
