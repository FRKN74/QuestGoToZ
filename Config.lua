local _, ns = ...

local Config = {}
ns.Config = Config

local configFrame = nil

-- Retail 10.2.5+ / Midnight ColorPickerFrame:SetupColorPickerAndShow + eski surum yedegi
local function OpenColorPicker(colorTable, swatchTex, onChanged)
    if not ColorPickerFrame then
        ns:PrintError("colorpicker", "ColorPickerFrame bulunamadi.")
        return
    end

    local prevR, prevG, prevB = colorTable.r, colorTable.g, colorTable.b

    if type(ColorPickerFrame.SetupColorPickerAndShow) == "function" then
        local info = {
            r = prevR,
            g = prevG,
            b = prevB,
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                colorTable.r, colorTable.g, colorTable.b = r, g, b
                swatchTex:SetColorTexture(r, g, b, 1)
                if onChanged then onChanged() end
            end,
            cancelFunc = function()
                colorTable.r, colorTable.g, colorTable.b = prevR, prevG, prevB
                swatchTex:SetColorTexture(prevR, prevG, prevB, 1)
                if onChanged then onChanged() end
            end,
        }
        pcall(ColorPickerFrame.SetupColorPickerAndShow, ColorPickerFrame, info)
    elseif type(ColorPickerFrame.SetColorRGB) == "function" then
        ColorPickerFrame.func = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            colorTable.r, colorTable.g, colorTable.b = r, g, b
            swatchTex:SetColorTexture(r, g, b, 1)
            if onChanged then onChanged() end
        end
        ColorPickerFrame.cancelFunc = function()
            colorTable.r, colorTable.g, colorTable.b = prevR, prevG, prevB
            swatchTex:SetColorTexture(prevR, prevG, prevB, 1)
            if onChanged then onChanged() end
        end
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(prevR, prevG, prevB)
        ColorPickerFrame:Show()
    end
end

local function CreateSlider(parent, name, label, minVal, maxVal, step, xOffset, yOffset, width, unitText, getter, setter)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    slider:SetWidth(width or 168)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]
    local suffix = unitText or ""

    if low then low:SetText(tostring(minVal) .. suffix) end
    if high then high:SetText(tostring(maxVal) .. suffix) end

    local function UpdateLabel(val)
        if text then
            text:SetText(string.format("%s: %d%s", label, math.floor(val + 0.5), suffix))
        end
    end

    slider:SetScript("OnValueChanged", function(_, value)
        local rounded = math.floor(value + 0.5)
        setter(rounded)
        UpdateLabel(rounded)
        ns:FireCallback("CONFIG_CHANGED")
    end)

    slider.RefreshValue = function()
        local val = getter()
        slider:SetValue(val)
        UpdateLabel(val)
    end

    return slider
end

local function CreateCheckbox(parent, label, xOffset, yOffset, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    cb:SetSize(22, 22)

    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)

    cb:SetScript("OnClick", function(selfBtn)
        setter(selfBtn:GetChecked() and true or false)
        ns:FireCallback("CONFIG_CHANGED")
    end)

    cb.RefreshValue = function()
        cb:SetChecked(getter() and true or false)
    end

    return cb
end

local function CreateColorSwatch(parent, label, xOffset, yOffset, colorKey)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    btn:SetSize(20, 20)
    btn:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
    })

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.tex = tex

    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", btn, "RIGHT", 5, 0)
    text:SetText(label)

    btn:SetScript("OnClick", function()
        if ns:IsInCombat() then
            ns:Print("Combat sirasinda renk secici acilamaz.")
            return
        end
        local colorTable = ns.db.colors[colorKey]
        OpenColorPicker(colorTable, tex, function()
            ns:FireCallback("CONFIG_CHANGED")
        end)
    end)

    btn.RefreshValue = function()
        local c = ns.db.colors[colorKey]
        tex:SetColorTexture(c.r, c.g, c.b, 1)
    end

    return btn
end

local function CreateConfigFrame()
    if configFrame then
        return configFrame
    end

    local f = CreateFrame("Frame", "QuestGoToZConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(420, 490)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(selfFrame)
        if not ns:IsInCombat() then
            selfFrame:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
    end)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0.05, 0.07, 0.11, 0.94)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("QuestGoToZ Ayarlari")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    f.controls = {}

    -- 2 Sekme: Genel & Profiller | Ozellikler & Puanlama
    local tab1Panel = CreateFrame("Frame", nil, f)
    tab1Panel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -64)
    tab1Panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 50)

    local tab2Panel = CreateFrame("Frame", nil, f)
    tab2Panel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -64)
    tab2Panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 50)
    tab2Panel:Hide()

    local tab1Btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tab1Btn:SetSize(185, 22)
    tab1Btn:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)
    tab1Btn:SetText("Genel & Profiller")

    local tab2Btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tab2Btn:SetSize(185, 22)
    tab2Btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -38)
    tab2Btn:SetText("Ozellikler & Puanlama")

    local function SelectTab(idx)
        if idx == 1 then
            tab1Panel:Show()
            tab2Panel:Hide()
            tab1Btn:Disable()
            tab2Btn:Enable()
        else
            tab1Panel:Hide()
            tab2Panel:Show()
            tab1Btn:Enable()
            tab2Btn:Disable()
        end
    end
    tab1Btn:SetScript("OnClick", function() SelectTab(1) end)
    tab2Btn:SetScript("OnClick", function() SelectTab(2) end)
    SelectTab(1)

    -- =================================================================
    -- SEKME 1: Genel, Mesafeler, Renkler, Sesler & Profiller
    -- =================================================================
    local profLabel = tab1Panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profLabel:SetPoint("TOPLEFT", tab1Panel, "TOPLEFT", 8, -4)
    profLabel:SetText("Aktif Profil:")

    local profCycleBtn = CreateFrame("Button", nil, tab1Panel, "UIPanelButtonTemplate")
    profCycleBtn:SetSize(150, 22)
    profCycleBtn:SetPoint("LEFT", profLabel, "RIGHT", 8, 0)
    profCycleBtn:SetScript("OnClick", function()
        local names = ns:GetProfileNames()
        if #names <= 1 then return end
        local curIdx = 1
        for i = 1, #names do
            if names[i] == ns.activeProfileName then
                curIdx = i
                break
            end
        end
        local nextName = names[(curIdx % #names) + 1]
        ns:SwitchProfile(nextName)
        for i = 1, #f.controls do
            if f.controls[i].RefreshValue then f.controls[i].RefreshValue() end
        end
    end)
    profCycleBtn.RefreshValue = function()
        profCycleBtn:SetText(ns.activeProfileName or "Varsayilan")
    end
    table.insert(f.controls, profCycleBtn)

    local newProfBtn = CreateFrame("Button", nil, tab1Panel, "UIPanelButtonTemplate")
    newProfBtn:SetSize(74, 22)
    newProfBtn:SetPoint("LEFT", profCycleBtn, "RIGHT", 6, 0)
    newProfBtn:SetText("Yeni +")
    newProfBtn:SetScript("OnClick", function()
        local names = ns:GetProfileNames()
        local newName = "Profil " .. tostring(#names + 1)
        ns:CreateProfile(newName)
        for i = 1, #f.controls do
            if f.controls[i].RefreshValue then f.controls[i].RefreshValue() end
        end
    end)

    local delProfBtn = CreateFrame("Button", nil, tab1Panel, "UIPanelButtonTemplate")
    delProfBtn:SetSize(56, 22)
    delProfBtn:SetPoint("LEFT", newProfBtn, "RIGHT", 4, 0)
    delProfBtn:SetText("Sil")
    delProfBtn:SetScript("OnClick", function()
        if ns.activeProfileName == "Varsayilan" then
            ns:Print("Varsayilan profil silinemez.")
            return
        end
        ns:DeleteProfile(ns.activeProfileName)
        for i = 1, #f.controls do
            if f.controls[i].RefreshValue then f.controls[i].RefreshValue() end
        end
    end)

    -- Mesafe slider'lari (2 sutun)
    table.insert(f.controls, CreateSlider(
        tab1Panel, "QuestGoToZNearbySlider", "Yakin Esigi",
        50, 500, 10, 10, -48, 172, " m",
        function() return ns.db.nearbyRadius end,
        function(v) ns.db.nearbyRadius = v end
    ))

    table.insert(f.controls, CreateSlider(
        tab1Panel, "QuestGoToZClusterSlider", "Birlikte Gorev",
        30, 300, 10, 206, -48, 172, " m",
        function() return ns.db.clusterRadius end,
        function(v) ns.db.clusterRadius = v end
    ))

    table.insert(f.controls, CreateSlider(
        tab1Panel, "QuestGoToZNearSlider", "Ok Yesil (<)",
        20, 250, 10, 10, -104, 172, " m",
        function() return ns.db.nearThreshold end,
        function(v)
            ns.db.nearThreshold = v
            if ns.db.farThreshold <= v then ns.db.farThreshold = v + 20 end
        end
    ))

    table.insert(f.controls, CreateSlider(
        tab1Panel, "QuestGoToZFarSlider", "Ok Kirmizi (>)",
        150, 800, 10, 206, -104, 172, " m",
        function() return ns.db.farThreshold end,
        function(v)
            ns.db.farThreshold = v
            if ns.db.nearThreshold >= v then ns.db.nearThreshold = math.max(20, v - 20) end
        end
    ))

    table.insert(f.controls, CreateSlider(
        tab1Panel, "QuestGoToZArrivalSlider", "Varis Ikonu (<=)",
        10, 80, 5, 10, -160, 172, " m",
        function() return ns.db.arrivalRadius end,
        function(v) ns.db.arrivalRadius = v end
    ))

    table.insert(f.controls, CreateSlider(
        tab1Panel, "QuestGoToZLogWarnSlider", "Gunluk Uyari",
        15, 25, 1, 206, -160, 172, "",
        function() return ns.db.questLogWarnThreshold end,
        function(v) ns.db.questLogWarnThreshold = v end
    ))

    -- Renk seciciler
    local colorHeader = tab1Panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorHeader:SetPoint("TOPLEFT", tab1Panel, "TOPLEFT", 10, -204)
    colorHeader:SetText("Mesafe Renkleri:")
    table.insert(f.controls, CreateColorSwatch(tab1Panel, "Yakin", 130, -202, "near"))
    table.insert(f.controls, CreateColorSwatch(tab1Panel, "Orta", 215, -202, "mid"))
    table.insert(f.controls, CreateColorSwatch(tab1Panel, "Uzak", 295, -202, "far"))

    -- Ses & genel secenekler
    table.insert(f.controls, CreateCheckbox(tab1Panel, "Sessiz Mod (tum sesleri kapat)", 8, -234,
        function() return ns.db.quietMode end,
        function(v) ns.db.quietMode = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab1Panel, "Yakindaki gorev sesi acik", 8, -260,
        function() return ns.db.soundEnabled end,
        function(v) ns.db.soundEnabled = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab1Panel, "Hedef tamamlaninca kisa ses cal", 8, -286,
        function() return ns.db.objectiveCompleteSound end,
        function(v) ns.db.objectiveCompleteSound = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab1Panel, "Hedef bitince oku teslim NPC'sine cevir", 8, -312,
        function() return ns.db.autoTurnInRedirect end,
        function(v) ns.db.autoTurnInRedirect = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab1Panel, "Teslimde siradaki en iyi goreve gec", 8, -338,
        function() return ns.db.autoSelectNearest end,
        function(v) ns.db.autoSelectNearest = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab1Panel, "Cerceveleri kilitle", 235, -234,
        function() return ns.db.locked end,
        function(v) ns.db.locked = v end
    ))

    -- =================================================================
    -- SEKME 2: Ozellikler & Puanlama Agirliklari
    -- =================================================================
    table.insert(f.controls, CreateCheckbox(tab2Panel, "Birlikte yapilabilecek gorevler", 8, -6,
        function() return ns.db.showClusters end,
        function(v) ns.db.showClusters = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab2Panel, "Mouseover mob tooltip satiri", 8, -32,
        function() return ns.db.showMobTooltip end,
        function(v) ns.db.showMobTooltip = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab2Panel, "Olunce ceset yonune waypoint", 8, -58,
        function() return ns.db.corpseWaypoint end,
        function(v) ns.db.corpseWaypoint = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab2Panel, "Odulde en yuksek altin vurgusu", 8, -84,
        function() return ns.db.showRewardHighlight end,
        function(v) ns.db.showRewardHighlight = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab2Panel, "Elite / Grup gorevi kirmizi rozeti", 8, -110,
        function() return ns.db.showEliteBadge end,
        function(v) ns.db.showEliteBadge = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab2Panel, "Bolge ilerlemesi (X/Y tamam)", 8, -136,
        function() return ns.db.showZoneProgress end,
        function(v) ns.db.showZoneProgress = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab2Panel, "En yakin hizmetler (satici/posta/han/ucus)", 8, -162,
        function() return ns.db.showNearestServices end,
        function(v) ns.db.showNearestServices = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab2Panel, "Canta %90 dolunca satici oner", 8, -188,
        function() return ns.db.bagFullVendorAlert end,
        function(v) ns.db.bagFullVendorAlert = v end
    ))
    table.insert(f.controls, CreateCheckbox(tab2Panel, "Gorev esyasi kullan butonu (buyuk)", 8, -214,
        function() return ns.db.showQuestItemButton end,
        function(v) ns.db.showQuestItemButton = v end
    ))

    local wHeader = tab2Panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wHeader:SetPoint("TOPLEFT", tab2Panel, "TOPLEFT", 10, -248)
    wHeader:SetText("Siradaki Gorev Puanlama Agirliklari:")

    table.insert(f.controls, CreateSlider(
        tab2Panel, "QuestGoToZWDistSlider", "Yakinlik",
        0, 100, 5, 10, -280, 172, "",
        function() return ns.db.weights.distance end,
        function(v) ns.db.weights.distance = v end
    ))
    table.insert(f.controls, CreateSlider(
        tab2Panel, "QuestGoToZWClustSlider", "Birlikte Gorev",
        0, 100, 5, 206, -280, 172, "",
        function() return ns.db.weights.cluster end,
        function(v) ns.db.weights.cluster = v end
    ))
    table.insert(f.controls, CreateSlider(
        tab2Panel, "QuestGoToZWXPSlider", "Gorev XP",
        0, 100, 5, 10, -334, 172, "",
        function() return ns.db.weights.xp end,
        function(v) ns.db.weights.xp = v end
    ))
    table.insert(f.controls, CreateSlider(
        tab2Panel, "QuestGoToZWCompSlider", "Tamamlanma",
        0, 100, 5, 206, -334, 172, "",
        function() return ns.db.weights.completion end,
        function(v) ns.db.weights.completion = v end
    ))

    -- Alt butonlar
    local resetPosBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetPosBtn:SetSize(160, 24)
    resetPosBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
    resetPosBtn:SetText("Konum/Boyut Sifirla")
    resetPosBtn:SetScript("OnClick", function()
        if ns:IsInCombat() then
            ns:Print("Combat sirasinda konum sifirlanamaz.")
            return
        end
        ns.db.arrowPos = {
            point = ns.DEFAULTS.arrowPos.point,
            relativePoint = ns.DEFAULTS.arrowPos.relativePoint,
            x = ns.DEFAULTS.arrowPos.x,
            y = ns.DEFAULTS.arrowPos.y,
        }
        ns.db.nearbyPos = {
            point = ns.DEFAULTS.nearbyPos.point,
            relativePoint = ns.DEFAULTS.nearbyPos.relativePoint,
            x = ns.DEFAULTS.nearbyPos.x,
            y = ns.DEFAULTS.nearbyPos.y,
        }
        ns.db.nearbySize = {
            width = ns.DEFAULTS.nearbySize.width,
            height = ns.DEFAULTS.nearbySize.height,
        }
        ns.db.questItemPos = {
            point = ns.DEFAULTS.questItemPos.point,
            relativePoint = ns.DEFAULTS.questItemPos.relativePoint,
            x = ns.DEFAULTS.questItemPos.x,
            y = ns.DEFAULTS.questItemPos.y,
        }
        if ns.Arrow then ns.Arrow:ApplyPosition() end
        if ns.Nearby then ns.Nearby:ApplyPosition() end
        if ns.Comfort then ns.Comfort:ApplyQuestItemPosition() end
        ns:Print("Cerceve konumlari ve boyutlari sifirlandi.")
    end)

    local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    doneBtn:SetSize(110, 24)
    doneBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    doneBtn:SetText("Kapat")
    doneBtn:SetScript("OnClick", function()
        if not ns:IsInCombat() then
            f:Hide()
        end
    end)

    f:SetScript("OnShow", function(selfFrame)
        for i = 1, #selfFrame.controls do
            if selfFrame.controls[i].RefreshValue then
                selfFrame.controls[i].RefreshValue()
            end
        end
    end)

    f:Hide()
    configFrame = f
    return f
end

function Config:Toggle()
    if ns:IsInCombat() then
        ns:Print("Combat sirasinda ayar penceresi acilip kapatilamaz.")
        return
    end
    local f = CreateConfigFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

-- /qgt slash komutu
SLASH_QUESTGOTOZ1 = "/qgt"
SlashCmdList["QUESTGOTOZ"] = function(msg)
    local cmd = string.lower(strtrim and strtrim(msg or "") or (msg or ""):match("^%s*(.-)%s*$"))
    if cmd == "clear" or cmd == "temizle" then
        ns:ClearQuestWaypoint(false)
    elseif cmd == "lock" or cmd == "kilit" then
        if ns:IsInCombat() then
            ns:Print("Combat sirasinda kilit degistirilemez.")
            return
        end
        ns.db.locked = not ns.db.locked
        ns:FireCallback("CONFIG_CHANGED")
        ns:Print("Cerceveler " .. (ns.db.locked and "kilitlendi." or "acildi."))
    elseif cmd == "nearest" or cmd == "yakin" or cmd == "next" or cmd == "siradaki" then
        if ns.SmartQuest then
            ns.SmartQuest:SelectBestQuest(nil, false)
        end
    elseif cmd == "quiet" or cmd == "sessiz" then
        ns.db.quietMode = not ns.db.quietMode
        ns:FireCallback("CONFIG_CHANGED")
        ns:Print("Sessiz mod: " .. (ns.db.quietMode and "ACIK" or "KAPALI"))
    else
        Config:Toggle()
    end
end
