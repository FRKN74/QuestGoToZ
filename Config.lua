local _, ns = ...

local Config = {}
ns.Config = Config

local FONT_MAIN = "Fonts\\ARIALN.TTF"
local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"

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

local function StyleFont(fs, size, r, g, b)
    fs:SetFont(FONT_MAIN, size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    if r then
        fs:SetTextColor(r, g, b)
    end
end

local function CreateGroupBox(parent, titleText, yOffset, height, width)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    box:SetSize(width or 406, height)
    box:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(0.06, 0.09, 0.14, 0.62)
    box:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.14)

    local hdr = box:CreateFontString(nil, "OVERLAY")
    StyleFont(hdr, 12, 1.0, 0.84, 0.30)
    hdr:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -7)
    hdr:SetText(titleText)

    local line = box:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -22)
    line:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -22)
    line:SetColorTexture(1.0, 1.0, 1.0, 0.10)

    return box
end

local function RefreshAllControls(frame)
    if not frame or not frame.controls then return end
    frame._refreshing = true
    for i = 1, #frame.controls do
        if frame.controls[i].RefreshValue then
            frame.controls[i].RefreshValue()
        end
    end
    frame._refreshing = false
end

local function CreateSlider(rootFrame, parent, name, label, minVal, maxVal, step, xOffset, yOffset, width, unitText, getter, setter)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    slider:SetWidth(width or 176)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]
    local suffix = unitText or ""

    if low then
        StyleFont(low, 10, 0.70, 0.75, 0.82)
        low:SetText(tostring(minVal) .. suffix)
    end
    if high then
        StyleFont(high, 10, 0.70, 0.75, 0.82)
        high:SetText(tostring(maxVal) .. suffix)
    end
    if text then
        StyleFont(text, 11, 0.94, 0.96, 1.0)
    end

    local function UpdateLabel(val)
        if text then
            text:SetText(string.format("%s: %d%s", label, math.floor(val + 0.5), suffix))
        end
    end

    slider:SetScript("OnValueChanged", function(_, value)
        if rootFrame._refreshing then return end
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

    table.insert(rootFrame.controls, slider)
    return slider
end

local function CreateCheckbox(rootFrame, parent, label, xOffset, yOffset, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    cb:SetSize(22, 22)

    local text = cb:CreateFontString(nil, "OVERLAY")
    StyleFont(text, 12, 0.92, 0.95, 1.0)
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)

    cb:SetScript("OnClick", function(selfBtn)
        setter(selfBtn:GetChecked() and true or false)
        ns:FireCallback("CONFIG_CHANGED")
        RefreshAllControls(rootFrame)
    end)

    cb.RefreshValue = function()
        cb:SetChecked(getter() and true or false)
    end

    table.insert(rootFrame.controls, cb)
    return cb
end

local function CreateColorSwatch(rootFrame, parent, label, xOffset, yOffset, colorKey)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    btn:SetSize(18, 18)
    btn:SetBackdrop({
        edgeFile = WHITE_TEX,
        edgeSize = 1,
    })
    btn:SetBackdropBorderColor(1, 1, 1, 0.45)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.tex = tex

    local text = parent:CreateFontString(nil, "OVERLAY")
    StyleFont(text, 11, 0.90, 0.94, 1.0)
    text:SetPoint("LEFT", btn, "RIGHT", 4, 0)
    text:SetText(label)

    btn:SetScript("OnClick", function()
        if ns:IsInCombat() then
            ns:Print("Savas sirasinda renk secici acilamaz.")
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

    table.insert(rootFrame.controls, btn)
    return btn
end

local function CreateModernActionBtn(parent, width, height, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(0.10, 0.15, 0.24, 0.85)
    btn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.22)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    StyleFont(fs, 12, 0.95, 0.97, 1.0)
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetText(label)
    btn.label = fs

    btn:SetScript("OnEnter", function(selfBtn)
        selfBtn:SetBackdropColor(0.18, 0.26, 0.40, 0.95)
        selfBtn:SetBackdropBorderColor(0.45, 0.82, 1.0, 0.70)
    end)
    btn:SetScript("OnLeave", function(selfBtn)
        selfBtn:SetBackdropColor(0.10, 0.15, 0.24, 0.85)
        selfBtn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.22)
    end)
    if onClick then
        btn:SetScript("OnClick", onClick)
    end
    return btn
end

local function CreateConfigFrame()
    if configFrame then
        return configFrame
    end

    local f = CreateFrame("Frame", "QuestGoToZConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(570, 500)
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

    -- Modern 1 px ince kenarlikli transparan cam ayar penceresi
    f:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.03, 0.05, 0.09, 0.88)
    f:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.24)

    local topSep = f:CreateTexture(nil, "ARTWORK")
    topSep:SetHeight(1)
    topSep:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    topSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -34)
    topSep:SetColorTexture(1.0, 1.0, 1.0, 0.12)

    local title = f:CreateFontString(nil, "OVERLAY")
    StyleFont(title, 15, 1.0, 0.86, 0.35)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -10)
    title:SetText("QuestGoToZ Ayarlari")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

    f.controls = {}

    -- Sol Kategori Menusu
    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -42)
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 50)
    sidebar:SetWidth(132)
    sidebar:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    sidebar:SetBackdropColor(0.05, 0.08, 0.13, 0.72)
    sidebar:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.12)

    -- Sag Icerik Alani
    local contentRoot = CreateFrame("Frame", nil, f)
    contentRoot:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    contentRoot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 50)

    local tabDefs = {
        { key = "general", label = "Genel & Moduller" },
        { key = "quest",   label = "Gorev & Harita" },
        { key = "party",   label = "Grup, Tank & Rahatlik" },
        { key = "sound",   label = "Ses & Puanlama" },
    }

    local panels = {}
    local navButtons = {}

    local function SelectCategory(index)
        for i = 1, #tabDefs do
            local active = (i == index)
            panels[i]:SetShown(active)
            local btn = navButtons[i]
            if active then
                btn:SetBackdropColor(0.16, 0.28, 0.45, 0.92)
                btn:SetBackdropBorderColor(0.45, 0.82, 1.0, 0.85)
                btn.label:SetTextColor(1.0, 0.90, 0.40)
            else
                btn:SetBackdropColor(0.08, 0.11, 0.17, 0.55)
                btn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.10)
                btn.label:SetTextColor(0.84, 0.88, 0.95)
            end
        end
    end

    for i = 1, #tabDefs do
        local p = CreateFrame("Frame", nil, contentRoot)
        p:SetAllPoints(contentRoot)
        p:Hide()
        panels[i] = p

        local btn = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
        btn:SetSize(120, 30)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, -8 - (i - 1) * 36)
        btn:SetBackdrop({
            bgFile = WHITE_TEX,
            edgeFile = WHITE_TEX,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        StyleFont(lbl, 12, 0.85, 0.90, 0.96)
        lbl:SetPoint("LEFT", btn, "LEFT", 8, 0)
        lbl:SetText(tabDefs[i].label)
        btn.label = lbl

        btn:SetScript("OnClick", function()
            SelectCategory(i)
        end)
        navButtons[i] = btn
    end

    -- =================================================================
    -- KATEGORI 1: Genel & Moduller
    -- =================================================================
    local p1 = panels[1]

    local modBox = CreateGroupBox(p1, "Ana Moduller (Ac / Kapat)", 0, 136)
    CreateCheckbox(f, modBox, "Gorev Modulu (Tumu)", 10, -28,
        function() return ns.db.enableQuestModule ~= false end,
        function(v) ns.db.enableQuestModule = v end
    )
    CreateCheckbox(f, modBox, "Solda 5'li Grup (Heal)", 10, -54,
        function() return ns.db.showPartyFrames end,
        function(v) ns.db.showPartyFrames = v end
    )
    CreateCheckbox(f, modBox, "Tank Aggro Renkleri", 10, -80,
        function() return ns.db.tankThreatColors end,
        function(v)
            ns.db.tankThreatColors = v
            if ns.QuestMobs then ns.QuestMobs:RefreshThreatColors() end
        end
    )
    CreateCheckbox(f, modBox, "Hasar Yazilari (Metin2)", 10, -106,
        function() return ns.db.showCombatText end,
        function(v) ns.db.showCombatText = v end
    )

    CreateCheckbox(f, modBox, "Gorev listesini goster", 206, -28,
        function() return ns.db.showQuestList ~= false end,
        function(v) ns.db.showQuestList = v end
    )
    CreateCheckbox(f, modBox, "Ust-orta aktif kart", 206, -54,
        function() return ns.db.showBanner end,
        function(v) ns.db.showBanner = v end
    )
    CreateCheckbox(f, modBox, "Threat Meter", 206, -80,
        function() return ns.db.showThreatMeter end,
        function(v) ns.db.showThreatMeter = v end
    )
    CreateCheckbox(f, modBox, "Cerceveleri kilitle", 206, -106,
        function() return ns.db.locked end,
        function(v) ns.db.locked = v end
    )

    local lookBox = CreateGroupBox(p1, "Gorunum", -146, 84)
    CreateSlider(f, lookBox, "QuestGoToZAlphaSlider", "Panel Opakligi",
        10, 95, 5, 16, -42, 240, "%",
        function() return ns.db.panelAlpha or 35 end,
        function(v) ns.db.panelAlpha = v end
    )

    local profBox = CreateGroupBox(p1, "Profiller", -240, 74)
    local profLabel = profBox:CreateFontString(nil, "OVERLAY")
    StyleFont(profLabel, 12, 0.90, 0.94, 1.0)
    profLabel:SetPoint("TOPLEFT", profBox, "TOPLEFT", 12, -38)
    profLabel:SetText("Aktif Profil:")

    local profCycleBtn = CreateModernActionBtn(profBox, 146, 22, "Varsayilan", function()
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
        RefreshAllControls(f)
    end)
    profCycleBtn:SetPoint("LEFT", profLabel, "RIGHT", 8, 0)
    profCycleBtn.RefreshValue = function()
        profCycleBtn.label:SetText(ns.activeProfileName or "Varsayilan")
    end
    table.insert(f.controls, profCycleBtn)

    local newProfBtn = CreateModernActionBtn(profBox, 68, 22, "Yeni +", function()
        local names = ns:GetProfileNames()
        local newName = "Profil " .. tostring(#names + 1)
        ns:CreateProfile(newName)
        RefreshAllControls(f)
    end)
    newProfBtn:SetPoint("LEFT", profCycleBtn, "RIGHT", 6, 0)

    local delProfBtn = CreateModernActionBtn(profBox, 52, 22, "Sil", function()
        if ns.activeProfileName == "Varsayilan" then
            ns:Print("Varsayilan profil silinemez.")
            return
        end
        ns:DeleteProfile(ns.activeProfileName)
        RefreshAllControls(f)
    end)
    delProfBtn:SetPoint("LEFT", newProfBtn, "RIGHT", 6, 0)

    local cmdBox = CreateGroupBox(p1, "Hizli Komutlar", -324, 72)
    local cmdInfo = cmdBox:CreateFontString(nil, "OVERLAY")
    StyleFont(cmdInfo, 11, 0.78, 0.84, 0.92)
    cmdInfo:SetPoint("TOPLEFT", cmdBox, "TOPLEFT", 12, -30)
    cmdInfo:SetWidth(382)
    cmdInfo:SetJustifyH("LEFT")
    cmdInfo:SetText("/qgt gorev | /qgt grup | /qgt threat | /qgt threat test\n/qgt list | /qgt kart | /qgt lock | /qgt quiet | /qgt testdmg")

    -- =================================================================
    -- KATEGORI 2: Gorev & Harita
    -- =================================================================
    local p2 = panels[2]

    local qListBox = CreateGroupBox(p2, "Gorev Listesi & Yonlendirme", 0, 186)
    CreateCheckbox(f, qListBox, "Levelling ile devam (al + yap)", 10, -28,
        function() return ns.db.levelingMode end,
        function(v) ns.db.levelingMode = v end
    )
    CreateCheckbox(f, qListBox, "Birlikte yapilabilecek gorevler", 10, -54,
        function() return ns.db.showClusters end,
        function(v) ns.db.showClusters = v end
    )
    CreateCheckbox(f, qListBox, "Gorev seviyesi [Lv] goster", 10, -80,
        function() return ns.db.showQuestLevel end,
        function(v) ns.db.showQuestLevel = v end
    )
    CreateCheckbox(f, qListBox, "Elite / Grup kirmizi rozeti", 10, -106,
        function() return ns.db.showEliteBadge end,
        function(v) ns.db.showEliteBadge = v end
    )
    CreateCheckbox(f, qListBox, "Bolge ilerlemesi (X/Y)", 10, -132,
        function() return ns.db.showZoneProgress end,
        function(v) ns.db.showZoneProgress = v end
    )
    CreateCheckbox(f, qListBox, "Dunya haritasi (M) pinleri", 10, -158,
        function() return ns.db.showWorldMapPins end,
        function(v)
            ns.db.showWorldMapPins = v
            if ns.Waypoint then ns.Waypoint:RefreshWorldMapCompletedCircles() end
        end
    )

    CreateCheckbox(f, qListBox, "Hedef bitince teslim NPC", 206, -28,
        function() return ns.db.autoTurnInRedirect end,
        function(v) ns.db.autoTurnInRedirect = v end
    )
    CreateCheckbox(f, qListBox, "Teslimde siradaki gorev", 206, -54,
        function() return ns.db.autoSelectNearest end,
        function(v) ns.db.autoSelectNearest = v end
    )
    CreateCheckbox(f, qListBox, "Olunce ceset yonu", 206, -80,
        function() return ns.db.corpseWaypoint end,
        function(v) ns.db.corpseWaypoint = v end
    )
    CreateCheckbox(f, qListBox, "Mob / Esya tooltip satiri", 206, -106,
        function() return ns.db.showMobTooltip end,
        function(v) ns.db.showMobTooltip = v end
    )
    CreateCheckbox(f, qListBox, "Gorev esyasi kullan butonu", 206, -132,
        function() return ns.db.showQuestItemButton end,
        function(v) ns.db.showQuestItemButton = v end
    )
    CreateCheckbox(f, qListBox, "Odulde altin vurgusu", 206, -158,
        function() return ns.db.showRewardHighlight end,
        function(v) ns.db.showRewardHighlight = v end
    )

    local distBox = CreateGroupBox(p2, "Mesafe Esikleri & Ok Renkleri", -196, 202)
    CreateSlider(f, distBox, "QuestGoToZNearbySlider", "Yakin Esigi",
        50, 500, 10, 14, -40, 174, " m",
        function() return ns.db.nearbyRadius end,
        function(v) ns.db.nearbyRadius = v end
    )
    CreateSlider(f, distBox, "QuestGoToZClusterSlider", "Birlikte Gorev",
        30, 300, 10, 212, -40, 174, " m",
        function() return ns.db.clusterRadius end,
        function(v) ns.db.clusterRadius = v end
    )
    CreateSlider(f, distBox, "QuestGoToZNearSlider", "Ok Yesil (<)",
        20, 250, 10, 14, -92, 174, " m",
        function() return ns.db.nearThreshold end,
        function(v)
            ns.db.nearThreshold = v
            if ns.db.farThreshold <= v then ns.db.farThreshold = v + 20 end
        end
    )
    CreateSlider(f, distBox, "QuestGoToZFarSlider", "Ok Kirmizi (>)",
        150, 800, 10, 212, -92, 174, " m",
        function() return ns.db.farThreshold end,
        function(v)
            ns.db.farThreshold = v
            if ns.db.nearThreshold >= v then ns.db.nearThreshold = math.max(20, v - 20) end
        end
    )
    CreateSlider(f, distBox, "QuestGoToZArrivalSlider", "Varis Ikonu (<=)",
        10, 80, 5, 14, -146, 174, " m",
        function() return ns.db.arrivalRadius end,
        function(v) ns.db.arrivalRadius = v end
    )

    local colorHdr = distBox:CreateFontString(nil, "OVERLAY")
    StyleFont(colorHdr, 11, 0.90, 0.94, 1.0)
    colorHdr:SetPoint("TOPLEFT", distBox, "TOPLEFT", 212, -132)
    colorHdr:SetText("Mesafe Renkleri:")
    CreateColorSwatch(f, distBox, "Yakin", 212, -152, "near")
    CreateColorSwatch(f, distBox, "Orta", 274, -152, "mid")
    CreateColorSwatch(f, distBox, "Uzak", 332, -152, "far")

    -- =================================================================
    -- KATEGORI 3: Grup, Tank & Canta
    -- =================================================================
    local p3 = panels[3]

    local partyBox = CreateGroupBox(p3, "5'li Grup & Healer (Solda)", 0, 140)
    CreateCheckbox(f, partyBox, "Solda 5'li Grup goster", 10, -28,
        function() return ns.db.showPartyFrames end,
        function(v) ns.db.showPartyFrames = v end
    )
    CreateCheckbox(f, partyBox, "Tek basina goster", 206, -28,
        function() return ns.db.partyShowSolo end,
        function(v) ns.db.partyShowSolo = v end
    )
    CreateCheckbox(f, partyBox, "Parti gorev senkronu", 10, -54,
        function() return ns.db.partySync end,
        function(v) ns.db.partySync = v end
    )

    local healLbl = partyBox:CreateFontString(nil, "OVERLAY")
    StyleFont(healLbl, 11, 0.90, 0.94, 1.0)
    healLbl:SetPoint("TOPLEFT", partyBox, "TOPLEFT", 14, -84)
    healLbl:SetText("Sag Tik Heal (bos=sinif):")

    local healBox = CreateFrame("EditBox", nil, partyBox, "InputBoxTemplate")
    healBox:SetSize(160, 18)
    healBox:SetPoint("LEFT", healLbl, "RIGHT", 10, 0)
    healBox:SetAutoFocus(false)
    healBox:SetScript("OnEnterPressed", function(selfBox)
        ns.db.partyHealSpell = strtrim and strtrim(selfBox:GetText() or "") or (selfBox:GetText() or "")
        selfBox:ClearFocus()
        ns:FireCallback("CONFIG_CHANGED")
    end)
    healBox:SetScript("OnEditFocusLost", function(selfBox)
        ns.db.partyHealSpell = strtrim and strtrim(selfBox:GetText() or "") or (selfBox:GetText() or "")
        ns:FireCallback("CONFIG_CHANGED")
    end)
    healBox.RefreshValue = function()
        healBox:SetText(ns.db.partyHealSpell or "")
    end
    table.insert(f.controls, healBox)

    local sHealLbl = partyBox:CreateFontString(nil, "OVERLAY")
    StyleFont(sHealLbl, 11, 0.90, 0.94, 1.0)
    sHealLbl:SetPoint("TOPLEFT", partyBox, "TOPLEFT", 14, -110)
    sHealLbl:SetText("Shift+Sol Tik Buyusu:")

    local sHealBox = CreateFrame("EditBox", nil, partyBox, "InputBoxTemplate")
    sHealBox:SetSize(160, 18)
    sHealBox:SetPoint("LEFT", healBox, "LEFT", 0, -26)
    sHealBox:SetAutoFocus(false)
    sHealBox:SetScript("OnEnterPressed", function(selfBox)
        ns.db.partyShiftHealSpell = strtrim and strtrim(selfBox:GetText() or "") or (selfBox:GetText() or "")
        selfBox:ClearFocus()
        ns:FireCallback("CONFIG_CHANGED")
    end)
    sHealBox:SetScript("OnEditFocusLost", function(selfBox)
        ns.db.partyShiftHealSpell = strtrim and strtrim(selfBox:GetText() or "") or (selfBox:GetText() or "")
        ns:FireCallback("CONFIG_CHANGED")
    end)
    sHealBox.RefreshValue = function()
        sHealBox:SetText(ns.db.partyShiftHealSpell or "")
    end
    table.insert(f.controls, sHealBox)

    local tankBox = CreateGroupBox(p3, "Tank & Threat Meter", -146, 112)
    CreateCheckbox(f, tankBox, "Tank aggro renkleri (Yesil=sende / Turuncu / Kirmizi=degil)", 10, -28,
        function() return ns.db.tankThreatColors end,
        function(v)
            ns.db.tankThreatColors = v
            if ns.QuestMobs then ns.QuestMobs:RefreshThreatColors() end
        end
    )
    CreateCheckbox(f, tankBox, "Threat Meter goster", 10, -54,
        function() return ns.db.showThreatMeter end,
        function(v) ns.db.showThreatMeter = v end
    )
    CreateCheckbox(f, tankBox, "Sadece threat varken goster", 206, -54,
        function() return ns.db.threatOnlyInCombat end,
        function(v) ns.db.threatOnlyInCombat = v end
    )
    CreateCheckbox(f, tankBox, "Pull Aggro cizgisi", 10, -80,
        function() return ns.db.threatShowPullLine ~= false end,
        function(v) ns.db.threatShowPullLine = v end
    )
    CreateCheckbox(f, tankBox, "Petleri dahil et", 206, -80,
        function() return ns.db.threatIncludePets ~= false end,
        function(v) ns.db.threatIncludePets = v end
    )

    local bagBox = CreateGroupBox(p3, "Levelling Rahatligi & Canta Uyarilari", -266, 112)
    CreateCheckbox(f, bagBox, "Cantada daha iyi esya oku", 10, -28,
        function() return ns.db.showUpgradeArrows end,
        function(v) ns.db.showUpgradeArrows = v end
    )
    CreateCheckbox(f, bagBox, "Canta %90 satici uyarisi", 10, -54,
        function() return ns.db.bagFullVendorAlert end,
        function(v) ns.db.bagFullVendorAlert = v end
    )
    CreateCheckbox(f, bagBox, "Dayaniklilik (<%30) uyarisi", 10, -80,
        function() return ns.db.durabilityAlert end,
        function(v) ns.db.durabilityAlert = v end
    )
    CreateCheckbox(f, bagBox, "En yakin hizmetler", 206, -28,
        function() return ns.db.showNearestServices end,
        function(v) ns.db.showNearestServices = v end
    )
    CreateCheckbox(f, bagBox, "Level up kontrol ozeti", 206, -54,
        function() return ns.db.levelUpChecklist end,
        function(v) ns.db.levelUpChecklist = v end
    )

    -- =================================================================
    -- KATEGORI 4: Ses & Puanlama
    -- =================================================================
    local p4 = panels[4]

    local soundBox = CreateGroupBox(p4, "Ses Ayarlari", 0, 110)
    CreateCheckbox(f, soundBox, "Sessiz Mod (tum sesleri kapat)", 10, -28,
        function() return ns.db.quietMode end,
        function(v) ns.db.quietMode = v end
    )
    CreateCheckbox(f, soundBox, "Yakindaki gorev sesi acik", 10, -54,
        function() return ns.db.soundEnabled end,
        function(v) ns.db.soundEnabled = v end
    )
    CreateCheckbox(f, soundBox, "Hedef tamamlaninca kisa ses cal", 10, -80,
        function() return ns.db.objectiveCompleteSound end,
        function(v) ns.db.objectiveCompleteSound = v end
    )

    local weightBox = CreateGroupBox(p4, "Siradaki Gorev Puanlama Agirliklari", -120, 144)
    CreateSlider(f, weightBox, "QuestGoToZWDistSlider", "Yakinlik",
        0, 100, 5, 14, -42, 174, "",
        function() return ns.db.weights.distance end,
        function(v) ns.db.weights.distance = v end
    )
    CreateSlider(f, weightBox, "QuestGoToZWClustSlider", "Birlikte Gorev",
        0, 100, 5, 212, -42, 174, "",
        function() return ns.db.weights.cluster end,
        function(v) ns.db.weights.cluster = v end
    )
    CreateSlider(f, weightBox, "QuestGoToZWXPSlider", "Gorev XP",
        0, 100, 5, 14, -96, 174, "",
        function() return ns.db.weights.xp end,
        function(v) ns.db.weights.xp = v end
    )
    CreateSlider(f, weightBox, "QuestGoToZWCompSlider", "Tamamlanma",
        0, 100, 5, 212, -96, 174, "",
        function() return ns.db.weights.completion end,
        function(v) ns.db.weights.completion = v end
    )

    local logBox = CreateGroupBox(p4, "Gorev Gunlugu", -274, 84)
    CreateSlider(f, logBox, "QuestGoToZLogWarnSlider", "Gunluk Uyari Esigi",
        15, 25, 1, 14, -42, 200, " gorev",
        function() return ns.db.questLogWarnThreshold end,
        function(v) ns.db.questLogWarnThreshold = v end
    )

    SelectCategory(1)

    -- Alt butonlar
    local resetPosBtn = CreateModernActionBtn(f, 156, 24, "Konum/Boyut Sifirla", function()
        if ns:IsInCombat() then
            ns:Print("Savas sirasinda konum sifirlanamaz.")
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
        ns.db.bannerPos = {
            point = ns.DEFAULTS.bannerPos.point,
            relativePoint = ns.DEFAULTS.bannerPos.relativePoint,
            x = ns.DEFAULTS.bannerPos.x,
            y = ns.DEFAULTS.bannerPos.y,
        }
        ns.db.partyPos = {
            point = ns.DEFAULTS.partyPos.point,
            relativePoint = ns.DEFAULTS.partyPos.relativePoint,
            x = ns.DEFAULTS.partyPos.x,
            y = ns.DEFAULTS.partyPos.y,
        }
        ns.db.partySize = {
            width = ns.DEFAULTS.partySize.width,
            unitHeight = ns.DEFAULTS.partySize.unitHeight,
        }
        ns.db.threatPos = {
            point = ns.DEFAULTS.threatPos.point,
            relativePoint = ns.DEFAULTS.threatPos.relativePoint,
            x = ns.DEFAULTS.threatPos.x,
            y = ns.DEFAULTS.threatPos.y,
        }
        ns.db.threatSize = {
            width = ns.DEFAULTS.threatSize.width,
            height = ns.DEFAULTS.threatSize.height,
        }
        if ns.Arrow then ns.Arrow:ApplyPosition() end
        if ns.Nearby then ns.Nearby:ApplyPosition() end
        if ns.Comfort then ns.Comfort:ApplyQuestItemPosition() end
        if ns.SmartQuest then ns.SmartQuest:ApplyBannerPosition() end
        if ns.PartyFrames then ns.PartyFrames:ApplyPosition() end
        if ns.ThreatMeter then ns.ThreatMeter:ApplyPosition() end
        ns:Print("Cerceve konumlari ve boyutlari sifirlandi.")
    end)
    resetPosBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)

    local doneBtn = CreateModernActionBtn(f, 100, 24, "Kapat", function()
        if not ns:IsInCombat() then
            f:Hide()
        end
    end)
    doneBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)

    f:SetScript("OnShow", function(selfFrame)
        RefreshAllControls(selfFrame)
    end)

    f:Hide()
    configFrame = f
    return f
end

function Config:Toggle()
    if ns:IsInCombat() then
        ns:Print("Savas sirasinda ayar penceresi acilip kapatilamaz.")
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
            ns:Print("Savas sirasinda kilit degistirilemez.")
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
    elseif cmd == "testdmg" or cmd == "test" then
        if ns.CombatText then
            ns.CombatText:RunTest()
        end
    elseif cmd == "list" or cmd == "liste" or cmd == "ac" or cmd == "kapat" or cmd == "toggle" then
        if ns.Nearby then
            ns.Nearby:ToggleVisibility()
        end
    elseif cmd == "level" or cmd == "levelling" or cmd == "leveling" then
        ns.db.levelingMode = not ns.db.levelingMode
        ns:FireCallback("CONFIG_CHANGED")
        ns:Print("Levelling gorevleri ile devam: " .. (ns.db.levelingMode and "ACIK" or "KAPALI"))
    elseif cmd == "kart" or cmd == "banner" then
        if ns.SmartQuest then
            ns.SmartQuest:ToggleBanner()
        end
    elseif cmd == "grup" or cmd == "party" or cmd == "heal" then
        if ns.PartyFrames then
            ns.PartyFrames:Toggle()
        end
    elseif cmd == "gorev" or cmd == "quest" then
        if ns:IsInCombat() then
            ns:Print("Savas sirasinda gorev modulu degistirilemez.")
            return
        end
        ns.db.enableQuestModule = not (ns.db.enableQuestModule ~= false)
        ns:FireCallback("CONFIG_CHANGED")
        ns:Print("Gorev Modulu: " .. (ns.db.enableQuestModule and "ACIK" or "KAPALI"))
    elseif cmd == "threat test" or cmd == "tm test" then
        if ns.ThreatMeter then
            ns.ThreatMeter:ToggleTest()
        end
    elseif cmd == "threat" or cmd == "tm" then
        if ns.ThreatMeter then
            ns.ThreatMeter:Toggle()
        end
    else
        Config:Toggle()
    end
end
