local _, ns = ...

local GearAdvisor = {}
ns.GearAdvisor = GearAdvisor

local FONT_MAIN = "Fonts\\ARIALN.TTF"
local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"

local mainFrame = nil
local minimapBtn = nil
local ahScanBtn = nil
local charQuickBtn = nil
local slotButtons = {}
local listRows = {}
local selectedSlotID = 5 -- Varsayilan: Gogus (Chest)
local minLvlFilter = 1
local maxLvlFilter = 80
local onlyUpgradesFilter = false
local filterInitialized = false

local scanActive = false
local scanTicker = nil
local scanIndex = 0
local scanTotal = 0
local scanPending = nil

-- 16 Ekipman Slotu: Sol (8) ve Sag (8) duzeni (C ekrani gibi)
local SLOT_DEFS = {
    -- Sol sutun
    { slotID = 1,  side = "L", row = 1, name = "Kafa",      equipLocs = { INVTYPE_HEAD = true },      emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head" },
    { slotID = 2,  side = "L", row = 2, name = "Boyun",     equipLocs = { INVTYPE_NECK = true },      emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck" },
    { slotID = 3,  side = "L", row = 3, name = "Omuz",      equipLocs = { INVTYPE_SHOULDER = true },  emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder" },
    { slotID = 15, side = "L", row = 4, name = "Pelerin",   equipLocs = { INVTYPE_CLOAK = true },     emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" },
    { slotID = 5,  side = "L", row = 5, name = "Gogus",     equipLocs = { INVTYPE_CHEST = true, INVTYPE_ROBE = true }, emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" },
    { slotID = 9,  side = "L", row = 6, name = "Bilek",     equipLocs = { INVTYPE_WRIST = true },     emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists" },
    { slotID = 10, side = "L", row = 7, name = "Eldiven",   equipLocs = { INVTYPE_HAND = true },      emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands" },
    { slotID = 16, side = "L", row = 8, name = "Ana Silah", equipLocs = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }, emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand" },

    -- Sag sutun
    { slotID = 6,  side = "R", row = 1, name = "Kemer",     equipLocs = { INVTYPE_WAIST = true },     emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist" },
    { slotID = 7,  side = "R", row = 2, name = "Pantolon",  equipLocs = { INVTYPE_LEGS = true },      emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs" },
    { slotID = 8,  side = "R", row = 3, name = "Bot",       equipLocs = { INVTYPE_FEET = true },      emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet" },
    { slotID = 11, side = "R", row = 4, name = "Yuzuk 1",   equipLocs = { INVTYPE_FINGER = true },    emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger" },
    { slotID = 12, side = "R", row = 5, name = "Yuzuk 2",   equipLocs = { INVTYPE_FINGER = true },    emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger" },
    { slotID = 13, side = "R", row = 6, name = "Trinket 1", equipLocs = { INVTYPE_TRINKET = true },   emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket" },
    { slotID = 14, side = "R", row = 7, name = "Trinket 2", equipLocs = { INVTYPE_TRINKET = true },   emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket" },
    { slotID = 17, side = "R", row = 8, name = "Ikincil",   equipLocs = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }, emptyTex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand" },
}

local SLOT_BY_ID = {}
for i = 1, #SLOT_DEFS do
    SLOT_BY_ID[SLOT_DEFS[i].slotID] = SLOT_DEFS[i]
end

-- Siniflara gore giyilebilir zirh (classID=4: 1=Cloth, 2=Leather, 3=Mail, 4=Plate, 6=Shield)
-- ve silah alt siniflari (classID=2)
local CLASS_RULES = {
    WARRIOR     = { armorHigh = { [4] = true, [6] = true }, armorLow = { [3] = true, [4] = true, [6] = true }, weapons = { [0]=true,[1]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[10]=true,[13]=true,[15]=true } },
    PALADIN     = { armorHigh = { [4] = true, [6] = true }, armorLow = { [3] = true, [4] = true, [6] = true }, weapons = { [0]=true,[1]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true } },
    DEATHKNIGHT = { armorHigh = { [4] = true },             armorLow = { [4] = true },                         weapons = { [0]=true,[1]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true } },
    HUNTER      = { armorHigh = { [3] = true },             armorLow = { [2] = true, [3] = true },             weapons = { [0]=true,[1]=true,[2]=true,[3]=true,[6]=true,[7]=true,[8]=true,[10]=true,[13]=true,[15]=true,[18]=true } },
    SHAMAN      = { armorHigh = { [3] = true, [6] = true }, armorLow = { [2] = true, [3] = true, [6] = true }, weapons = { [0]=true,[1]=true,[4]=true,[5]=true,[10]=true,[13]=true,[15]=true } },
    EVOKER      = { armorHigh = { [3] = true },             armorLow = { [3] = true },                         weapons = { [0]=true,[1]=true,[4]=true,[5]=true,[7]=true,[8]=true,[10]=true,[13]=true,[15]=true } },
    ROGUE       = { armorHigh = { [2] = true },             armorLow = { [2] = true },                         weapons = { [0]=true,[4]=true,[7]=true,[13]=true,[15]=true } },
    DRUID       = { armorHigh = { [2] = true },             armorLow = { [2] = true },                         weapons = { [4]=true,[5]=true,[6]=true,[10]=true,[13]=true,[15]=true } },
    MONK        = { armorHigh = { [2] = true },             armorLow = { [2] = true },                         weapons = { [0]=true,[4]=true,[6]=true,[7]=true,[10]=true,[13]=true } },
    DEMONHUNTER = { armorHigh = { [2] = true },             armorLow = { [2] = true },                         weapons = { [0]=true,[7]=true,[9]=true,[13]=true } },
    MAGE        = { armorHigh = { [1] = true },             armorLow = { [1] = true },                         weapons = { [7]=true,[10]=true,[15]=true,[19]=true } },
    PRIEST      = { armorHigh = { [1] = true },             armorLow = { [1] = true },                         weapons = { [4]=true,[10]=true,[15]=true,[19]=true } },
    WARLOCK     = { armorHigh = { [1] = true },             armorLow = { [1] = true },                         weapons = { [7]=true,[10]=true,[15]=true,[19]=true } },
}

local UNIVERSAL_ARMOR_LOCS = {
    INVTYPE_NECK = true,
    INVTYPE_CLOAK = true,
    INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true,
    INVTYPE_HOLDABLE = true,
}

local function StyleFont(fs, size, r, g, b)
    fs:SetFont(FONT_MAIN, size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    if r then fs:SetTextColor(r, g, b) end
end

local function GetRealmCacheKey()
    local okR, rName = ns:SafeGlobal("GetNormalizedRealmName")
    if not (okR and ns:IsSafeString(rName) and rName ~= "") then
        okR, rName = ns:SafeGlobal("GetRealmName")
    end
    local okF, fac = ns:SafeGlobal("UnitFactionGroup", "player")
    return ((okR and ns:IsSafeString(rName) and rName) or "Realm") .. "-" .. ((okF and ns:IsSafeString(fac) and fac) or "Any")
end

local function GetAHStore(create)
    if type(_G.QuestGoToZDB) ~= "table" then return nil end
    if create then
        _G.QuestGoToZDB.ahCache = _G.QuestGoToZDB.ahCache or {}
    end
    if type(_G.QuestGoToZDB.ahCache) ~= "table" then return nil end
    local key = GetRealmCacheKey()
    if create then
        _G.QuestGoToZDB.ahCache[key] = _G.QuestGoToZDB.ahCache[key] or { t = 0, items = {} }
    end
    return _G.QuestGoToZDB.ahCache[key]
end

local function FormatGold(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return "-" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("|cffffd700%dg|r |cffc7c7cf%ds|r", g, s)
    elseif s > 0 then
        return string.format("|cffc7c7cf%ds|r |cffeda55f%dc|r", s, c)
    end
    return string.format("|cffeda55f%dc|r", c)
end

local function FormatAge(ts)
    if not ts or ts <= 0 then return "Henuz taranmadi" end
    local okT, now = ns:SafeGlobal("time")
    if not (okT and ns:IsSafeNumber(now)) then return "Tarandi" end
    local diff = math.max(0, now - ts)
    if diff < 60 then return "Az once" end
    if diff < 3600 then return string.format("%d dk once", math.floor(diff / 60)) end
    return string.format("%d sa once", math.floor(diff / 3600))
end

local function GetQualityRGB(q)
    if type(_G.GetItemQualityColor) == "function" and ns:IsSafeNumber(q) then
        local ok, r, g, b = pcall(_G.GetItemQualityColor, q)
        if ok and ns:IsSafeNumber(r) then return r, g, b end
    end
    if q == 2 then return 0.12, 1.0, 0.0 end
    if q == 3 then return 0.0, 0.55, 1.0 end
    if q == 4 then return 0.72, 0.30, 1.0 end
    if q == 5 then return 1.0, 0.50, 0.0 end
    return 0.92, 0.92, 0.92
end

local function GetSafeItemLevel(link)
    if not ns:IsSafeString(link) then return 0 end
    local ok, lvl = ns:TrySafeC("C_Item", "GetDetailedItemLevelInfo", link)
    if not ok then
        ok, lvl = ns:SafeGlobal("GetDetailedItemLevelInfo", link)
    end
    if ok and ns:IsSafeNumber(lvl) and lvl > 0 then
        return math.floor(lvl)
    end
    return 0
end

local function GetEquippedSlotInfo(slotID)
    local okL, link = ns:SafeGlobal("GetInventoryItemLink", "player", slotID)
    local okT, tex = ns:SafeGlobal("GetInventoryItemTexture", "player", slotID)
    local okQ, q = ns:SafeGlobal("GetInventoryItemQuality", "player", slotID)
    if okL and ns:IsSafeString(link) then
        return {
            link = link,
            icon = (okT and tex) or nil,
            quality = (okQ and ns:IsSafeNumber(q)) and q or 1,
            ilvl = GetSafeItemLevel(link),
        }
    end
    return nil
end

local function IsItemUsableForPlayer(item)
    if type(item) ~= "table" then return false end
    local okCls, _, classFile = ns:SafeGlobal("UnitClass", "player")
    local okLvl, pLvl = ns:SafeGlobal("UnitLevel", "player")
    local level = (okLvl and ns:IsSafeNumber(pLvl)) and pLvl or 60
    local rule = (okCls and ns:IsSafeString(classFile)) and CLASS_RULES[classFile] or nil
    if not rule then return true end

    if item.classID == 4 then
        if UNIVERSAL_ARMOR_LOCS[item.equipLoc] then
            return true
        end
        local allowed = (level < 40) and rule.armorLow or rule.armorHigh
        return allowed[item.subClassID] == true
    elseif item.classID == 2 then
        return rule.weapons[item.subClassID] == true
    end
    return false
end

-- Belirli bir slot icin AH'deki uygun yukseltmeleri (veya tum uygun esyalari) getir
local function GetUpgradesForSlot(slotID, onlyHigherIlvl)
    local store = GetAHStore(false)
    if not store or type(store.items) ~= "table" then
        return {}
    end
    local def = SLOT_BY_ID[slotID]
    if not def then return {} end

    local eq = GetEquippedSlotInfo(slotID)
    local curIlvl = (eq and eq.ilvl) or 0
    local results = {}

    for _, item in pairs(store.items) do
        if type(item) == "table" and def.equipLocs[item.equipLoc] then
            local req = item.reqLvl or 0
            if req >= minLvlFilter and req <= maxLvlFilter and IsItemUsableForPlayer(item) then
                if (not onlyHigherIlvl) or ((item.ilvl or 0) > curIlvl) then
                    table.insert(results, item)
                end
            end
        end
    end

    local sortMode = (ns.db and ns.db.gearSortMode) or "price_asc"
    table.sort(results, function(a, b)
        local ap = a.price or 0
        local bp = b.price or 0
        local ai = a.ilvl or 0
        local bi = b.ilvl or 0
        if sortMode == "price" or sortMode == "price_asc" then
            if ap ~= bp then return ap < bp end
            if ai ~= bi then return ai > bi end
        elseif sortMode == "price_desc" then
            if ap ~= bp then return ap > bp end
            if ai ~= bi then return ai > bi end
        else
            if ai ~= bi then return ai > bi end
            if ap ~= bp then return ap < bp end
        end
        if (a.reqLvl or 0) ~= (b.reqLvl or 0) then
            return (a.reqLvl or 0) > (b.reqLvl or 0)
        end
        return (a.name or "") < (b.name or "")
    end)

    return results
end

-- =================================================================
-- AH TARAMA MOTORU (C_AuctionHouse.ReplicateItems + GetItemInfoInstant + Yedek DB)
-- =================================================================
local scanToken = 0

local function FinishScan(msgOverride)
    if scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
    scanActive = false
    if scanPending then
        local cnt = 0
        for _ in pairs(scanPending) do cnt = cnt + 1 end
        if cnt > 0 then
            local store = GetAHStore(true)
            if store then
                local okT, now = ns:SafeGlobal("time")
                store.t = (okT and ns:IsSafeNumber(now)) and now or 0
                store.items = scanPending
            end
            ns:Print(string.format("AH taramasi tamamlandi: %d giyilebilir esya kaydedildi.", cnt))
        elseif msgOverride then
            ns:Print(msgOverride)
        end
        scanPending = nil
    elseif msgOverride then
        ns:Print(msgOverride)
    end
    if ahScanBtn and ahScanBtn.label then
        ahScanBtn.label:SetText("AH Tara (Frkn)")
    end
    if mainFrame and mainFrame:IsShown() then
        GearAdvisor:RefreshAll()
    end
end

-- Yedek: Auctionator veya OneForAll daha once AH taradiysa ondan aninda ice aktar
local function TryImportExternalAHData()
    local imported = {}
    local count = 0

    local function AddItemByID(itemID, price)
        if not (ns:IsSafeNumber(itemID) and itemID > 0 and ns:IsSafeNumber(price) and price > 0) then return end
        local okInst, _, _, _, equipLoc, icon, classID, subClassID = ns:TrySafeC("C_Item", "GetItemInfoInstant", itemID)
        if not okInst then
            okInst, _, _, _, equipLoc, icon, classID, subClassID = ns:SafeGlobal("GetItemInfoInstant", itemID)
        end
        if not (okInst and (classID == 2 or classID == 4) and ns:IsSafeString(equipLoc) and equipLoc ~= "") then
            return
        end
        local okInfo, iName, iLink, iQual, iLvl, reqLvl = ns:TrySafeC("C_Item", "GetItemInfo", itemID)
        if not okInfo then
            okInfo, iName, iLink, iQual, iLvl, reqLvl = ns:SafeGlobal("GetItemInfo", itemID)
        end
        local link = (okInfo and ns:IsSafeString(iLink)) and iLink or ("item:" .. itemID)
        local realIlvl = GetSafeItemLevel(link)
        if realIlvl <= 0 and okInfo and ns:IsSafeNumber(iLvl) then realIlvl = iLvl end
        local existing = imported[itemID]
        if not existing or price < existing.price then
            if not existing then count = count + 1 end
            imported[itemID] = {
                id = itemID,
                link = link,
                name = (okInfo and ns:IsSafeString(iName)) and iName or ("Esya #" .. itemID),
                icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                quality = (okInfo and ns:IsSafeNumber(iQual)) and iQual or 2,
                ilvl = realIlvl or 0,
                reqLvl = (okInfo and ns:IsSafeNumber(reqLvl) and reqLvl) or 1,
                equipLoc = equipLoc,
                classID = classID,
                subClassID = ns:IsSafeNumber(subClassID) and subClassID or 0,
                price = price,
            }
        end
    end

    -- 1) OneForAll AH taramasi varsa
    if type(_G.OneForAllDB) == "table" and type(_G.OneForAllDB.ahScan) == "table" then
        for _, realmTbl in pairs(_G.OneForAllDB.ahScan) do
            if type(realmTbl) == "table" and type(realmTbl.fixed) == "table" then
                for itemID, price in pairs(realmTbl.fixed) do
                    AddItemByID(tonumber(itemID), price)
                end
            end
            if type(realmTbl) == "table" and type(realmTbl.var) == "table" then
                for key, price in pairs(realmTbl.var) do
                    local id = tonumber(tostring(key):match("^item:(%d+)"))
                    if id then AddItemByID(id, price) end
                end
            end
        end
    end

    -- 2) Auctionator veritabani varsa
    if count == 0 and type(_G.AUCTIONATOR_PRICE_DATABASE) == "table" then
        for realmK, realmTbl in pairs(_G.AUCTIONATOR_PRICE_DATABASE) do
            if type(realmTbl) == "table" and realmK ~= "__dbversion" then
                for k, v in pairs(realmTbl) do
                    local id = tonumber(tostring(k):match("^(%d+)"))
                    local price = (type(v) == "table" and v.m) or nil
                    if id and ns:IsSafeNumber(price) and price > 0 then
                        AddItemByID(id, price)
                    end
                end
            end
        end
    end

    if count > 0 then
        local store = GetAHStore(true)
        if store then
            local okT, now = ns:SafeGlobal("time")
            store.t = (okT and ns:IsSafeNumber(now)) and now or 0
            store.items = imported
        end
        return count
    end
    return 0
end

local function ProcessScanBatch()
    local okRun, err = pcall(function()
        local ah = _G.C_AuctionHouse
        if not (ah and type(ah.GetReplicateItemInfo) == "function") then
            FinishScan()
            return
        end

        local batchEnd = math.min(scanTotal, scanIndex + 600)
        for i = scanIndex, batchEnd - 1 do
            local ok, name, texture, _, quality, _, repLevel, _, _, _, buyout, _, _, _, _, _, _, itemID = pcall(ah.GetReplicateItemInfo, i)
            if ok and ns:IsSafeNumber(itemID) and itemID > 0 and ns:IsSafeNumber(buyout) and buyout > 0 and ns:IsSafeNumber(quality) and quality >= 2 then
                -- GetItemInfoInstant ANINDA calisir (cache bekleyip nil donmez!)
                local okInst, _, _, _, equipLoc, instIcon, classID, subClassID = ns:TrySafeC("C_Item", "GetItemInfoInstant", itemID)
                if not okInst then
                    okInst, _, _, _, equipLoc, instIcon, classID, subClassID = ns:SafeGlobal("GetItemInfoInstant", itemID)
                end
                if okInst and (classID == 2 or classID == 4) and ns:IsSafeString(equipLoc) and equipLoc ~= "" then
                    local okL, link = pcall(ah.GetReplicateItemLink, i)
                    local itemRef = (okL and ns:IsSafeString(link)) and link or ("item:" .. itemID)
                    local okInfo, iName, iLink, iQual, iLvl, reqLvl = ns:TrySafeC("C_Item", "GetItemInfo", itemRef)
                    if not okInfo then
                        okInfo, iName, iLink, iQual, iLvl, reqLvl = ns:SafeGlobal("GetItemInfo", itemRef)
                    end
                    local finalLink = (okInfo and ns:IsSafeString(iLink)) and iLink or itemRef
                    local realIlvl = GetSafeItemLevel(finalLink)
                    if realIlvl <= 0 and okInfo and ns:IsSafeNumber(iLvl) then realIlvl = iLvl end
                    local finalReq = (okInfo and ns:IsSafeNumber(reqLvl) and reqLvl > 0) and reqLvl or (ns:IsSafeNumber(repLevel) and repLevel or 1)

                    local existing = scanPending[itemID]
                    if not existing or buyout < existing.price then
                        scanPending[itemID] = {
                            id = itemID,
                            link = finalLink,
                            name = (okInfo and ns:IsSafeString(iName)) and iName or (ns:IsSafeString(name) and name) or ("Esya #" .. itemID),
                            icon = instIcon or texture or "Interface\\Icons\\INV_Misc_QuestionMark",
                            quality = (okInfo and ns:IsSafeNumber(iQual)) and iQual or quality,
                            ilvl = realIlvl or 0,
                            reqLvl = finalReq,
                            equipLoc = equipLoc,
                            classID = classID,
                            subClassID = ns:IsSafeNumber(subClassID) and subClassID or 0,
                            price = buyout,
                        }
                    end
                end
            end
        end

        scanIndex = batchEnd
        local pct = (scanTotal > 0) and math.floor((scanIndex / scanTotal) * 100) or 100
        if ahScanBtn and ahScanBtn.label then
            ahScanBtn.label:SetText(string.format("Taraniyor %d%%", pct))
        end
        if mainFrame and mainFrame.scanStatusText then
            mainFrame.scanStatusText:SetText(string.format("AH Taraniyor... %d%%", pct))
        end

        if scanIndex >= scanTotal then
            FinishScan()
        end
    end)

    if not okRun then
        FinishScan("AH tarama hatasi: " .. tostring(err))
    end
end

local function BeginReadingReplicateData()
    local ah = _G.C_AuctionHouse
    if not (ah and type(ah.GetNumReplicateItems) == "function") then return end
    local okN, total = pcall(ah.GetNumReplicateItems)
    if not (okN and ns:IsSafeNumber(total) and total > 0) then return end

    scanToken = scanToken + 1
    if scanTicker then scanTicker:Cancel(); scanTicker = nil end
    scanActive = true
    scanIndex = 0
    scanTotal = total
    scanPending = {}

    if _G.C_Timer and type(_G.C_Timer.NewTicker) == "function" then
        scanTicker = _G.C_Timer.NewTicker(0.02, ProcessScanBatch)
    end
end

function GearAdvisor:StartAHScan()
    if scanActive then
        ns:Print("AH taramasi zaten devam ediyor...")
        return
    end

    local ahOpen = (_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown())
    local ah = _G.C_AuctionHouse

    -- 1) Istemci hafizasinda zaten hazir replicate listesi varsa beklemeden oku!
    if ahOpen and ah and type(ah.GetNumReplicateItems) == "function" then
        local okN, existingTotal = pcall(ah.GetNumReplicateItems)
        if okN and ns:IsSafeNumber(existingTotal) and existingTotal > 0 then
            ns:Print(string.format("AH listesi hazir (%d kayit), okunuyor...", existingTotal))
            BeginReadingReplicateData()
            return
        end
    end

    -- 2) AH acik degilse Auctionator / OneForAll verisinden ice aktar
    if not ahOpen then
        local imp = TryImportExternalAHData()
        if imp > 0 then
            ns:Print(string.format("Mevcut AH veritabanindan %d ekipman yuklendi.", imp))
            self:RefreshAll()
        else
            ns:Print("AH taramak icin once Auction House (Muzayede Evi) acin.")
        end
        return
    end

    if not (ah and type(ah.ReplicateItems) == "function") then
        local imp = TryImportExternalAHData()
        if imp > 0 then
            ns:Print(string.format("AH veritabanindan %d ekipman yuklendi.", imp))
            self:RefreshAll()
        else
            ns:Print("Bu surumde ReplicateItems desteklenmiyor.")
        end
        return
    end

    scanToken = scanToken + 1
    local myToken = scanToken
    if ahScanBtn and ahScanBtn.label then
        ahScanBtn.label:SetText("Sunucu bekleniyor...")
    end
    if mainFrame and mainFrame.scanStatusText then
        mainFrame.scanStatusText:SetText("AH sunucusu bekleniyor...")
    end
    ns:Print("AH taramasi istendi (sunucu 10-15 sn surebilir)...")
    pcall(ah.ReplicateItems)

    -- 15 sn timeout: Blizzard 15 dk cooldown'daysa yedek DB'den yukle ve takili kalma!
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(15, function()
            if myToken ~= scanToken or scanActive then return end
            local okN, lateTotal = pcall(ah.GetNumReplicateItems)
            if okN and ns:IsSafeNumber(lateTotal) and lateTotal > 0 then
                BeginReadingReplicateData()
                return
            end
            local imp = TryImportExternalAHData()
            if imp > 0 then
                FinishScan(string.format("AH 15 dk bekleme suresinde — mevcut veritabanindan %d ekipman yuklendi.", imp))
            else
                FinishScan("AH sunucusu yanit vermedi (son 15 dk icinde baska addon taramis olabilir). Biraz sonra tekrar deneyin.")
            end
        end)
    end
end

local function CreateActionBtn(parent, w, h, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w, h)
    btn:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(0.10, 0.15, 0.24, 0.88)
    btn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.24)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    StyleFont(fs, 11, 0.95, 0.97, 1.0)
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetText(label)
    btn.label = fs

    btn:SetScript("OnEnter", function(selfBtn)
        selfBtn:SetBackdropColor(0.18, 0.28, 0.42, 0.96)
        selfBtn:SetBackdropBorderColor(0.45, 0.85, 1.0, 0.78)
    end)
    btn:SetScript("OnLeave", function(selfBtn)
        selfBtn:SetBackdropColor(0.10, 0.15, 0.24, 0.88)
        selfBtn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.24)
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- =================================================================
-- ANA PENCERE: Sol (3D Karakter + 16 Slot + Oklar) | Sag (AH Listesi)
-- =================================================================
local function EnsureMainFrame()
    if mainFrame then return mainFrame end

    local f = CreateFrame("Frame", "QuestGoToZGearAdvisorFrame", UIParent, "BackdropTemplate")
    f:SetSize(690, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(selfF)
        if not ns:IsInCombat() then selfF:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(selfF) selfF:StopMovingOrSizing() end)

    f:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.03, 0.05, 0.09, 0.92)
    f:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.24)

    -- Ust Baslik
    local title = f:CreateFontString(nil, "OVERLAY")
    StyleFont(title, 15, 1.0, 0.86, 0.35)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
    title:SetText("Karakter & AH Ekipman Yukseltme")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

    -- Ust Kontrol Cubugu (Level Araligi + Siralama + AH Tara)
    local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -34)
    bar:SetHeight(32)
    bar:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    bar:SetBackdropColor(0.06, 0.09, 0.15, 0.80)
    bar:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.14)

    local lblLv = bar:CreateFontString(nil, "OVERLAY")
    StyleFont(lblLv, 11, 0.85, 0.90, 0.96)
    lblLv:SetPoint("LEFT", bar, "LEFT", 10, 0)
    lblLv:SetText("Level Araligi:")

    local minBox = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    minBox:SetSize(38, 18)
    minBox:SetPoint("LEFT", lblLv, "RIGHT", 8, 0)
    minBox:SetAutoFocus(false)
    minBox:SetNumeric(true)
    minBox:SetMaxLetters(3)
    f.minBox = minBox

    local dash = bar:CreateFontString(nil, "OVERLAY")
    StyleFont(dash, 12, 0.80, 0.85, 0.92)
    dash:SetPoint("LEFT", minBox, "RIGHT", 5, 0)
    dash:SetText("-")

    local maxBox = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    maxBox:SetSize(38, 18)
    maxBox:SetPoint("LEFT", dash, "RIGHT", 7, 0)
    maxBox:SetAutoFocus(false)
    maxBox:SetNumeric(true)
    maxBox:SetMaxLetters(3)
    f.maxBox = maxBox

    local function ApplyLevelInputs()
        local a = tonumber(minBox:GetText()) or 1
        local b = tonumber(maxBox:GetText()) or 80
        if a < 1 then a = 1 end
        if b < a then b = a end
        minLvlFilter, maxLvlFilter = a, b
        minBox:SetText(tostring(a))
        maxBox:SetText(tostring(b))
        GearAdvisor:RefreshAll()
    end
    minBox:SetScript("OnEnterPressed", function(s) s:ClearFocus(); ApplyLevelInputs() end)
    maxBox:SetScript("OnEnterPressed", function(s) s:ClearFocus(); ApplyLevelInputs() end)
    minBox:SetScript("OnEditFocusLost", ApplyLevelInputs)
    maxBox:SetScript("OnEditFocusLost", ApplyLevelInputs)

    local myLvBtn = CreateActionBtn(bar, 68, 20, "Benim Lv", function()
        local okL, pLvl = ns:SafeGlobal("UnitLevel", "player")
        local lv = (okL and ns:IsSafeNumber(pLvl) and pLvl > 0) and pLvl or 60
        minLvlFilter = math.max(1, lv - 10)
        maxLvlFilter = lv
        minBox:SetText(tostring(minLvlFilter))
        maxBox:SetText(tostring(maxLvlFilter))
        GearAdvisor:RefreshAll()
    end)
    myLvBtn:SetPoint("LEFT", maxBox, "RIGHT", 8, 0)

    local sortBtn = CreateActionBtn(bar, 94, 20, "Fiyat (Ucuz)", function()
        if not ns.db then return end
        local cur = ns.db.gearSortMode or "price_asc"
        if cur == "price" or cur == "price_asc" then
            ns.db.gearSortMode = "price_desc"
        elseif cur == "price_desc" then
            ns.db.gearSortMode = "ilvl"
        else
            ns.db.gearSortMode = "price_asc"
        end
        GearAdvisor:RefreshAll()
    end)
    sortBtn:SetPoint("LEFT", myLvBtn, "RIGHT", 6, 0)
    f.sortBtn = sortBtn

    local upgFilterBtn = CreateActionBtn(bar, 102, 20, "Yukselt: Tumu", function()
        onlyUpgradesFilter = not onlyUpgradesFilter
        GearAdvisor:RefreshAll()
    end)
    upgFilterBtn:SetPoint("LEFT", sortBtn, "RIGHT", 6, 0)
    f.upgFilterBtn = upgFilterBtn

    local scanBtn = CreateActionBtn(bar, 72, 20, "AH Tara", function()
        GearAdvisor:StartAHScan()
    end)
    scanBtn:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    f.scanBtn = scanBtn

    local scanStatus = bar:CreateFontString(nil, "OVERLAY")
    StyleFont(scanStatus, 10, 0.72, 0.80, 0.90)
    scanStatus:SetPoint("RIGHT", scanBtn, "LEFT", -8, 0)
    scanStatus:SetJustifyH("RIGHT")
    scanStatus:SetText("Henuz taranmadi")
    f.scanStatusText = scanStatus

    -- SOL PANEL: 3D Karakter + 16 Slot
    local leftPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    leftPanel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
    leftPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    leftPanel:SetWidth(308)
    leftPanel:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    leftPanel:SetBackdropColor(0.05, 0.08, 0.13, 0.75)
    leftPanel:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.12)

    -- 3D Canli Karakter Modeli (TryOn destekli)
    local model = CreateFrame("DressUpModel", nil, leftPanel)
    model:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 68, -14)
    model:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -68, 34)
    model:EnableMouse(true)
    local rotDragging = false
    local rotLastX = 0
    model:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            rotDragging = true
            rotLastX = GetCursorPosition()
        end
    end)
    model:SetScript("OnMouseUp", function() rotDragging = false end)
    model:SetScript("OnUpdate", function(selfM)
        if not rotDragging then return end
        local curX = GetCursorPosition()
        local dx = curX - rotLastX
        rotLastX = curX
        if type(selfM.GetFacing) == "function" and type(selfM.SetFacing) == "function" then
            selfM:SetFacing((selfM:GetFacing() or 0) + dx * 0.015)
        end
    end)
    f.model = model

    local resetModelBtn = CreateActionBtn(leftPanel, 100, 20, "Modeli Sifirla", function()
        if f.model and type(f.model.SetUnit) == "function" then
            pcall(f.model.SetUnit, f.model, "player")
            if type(f.model.Dress) == "function" then pcall(f.model.Dress, f.model) end
        end
    end)
    resetModelBtn:SetPoint("BOTTOM", leftPanel, "BOTTOM", 0, 8)

    -- 16 Ekipman Slotu + Yanindaki Yesil Yukseltme Oku
    for i = 1, #SLOT_DEFS do
        local def = SLOT_DEFS[i]
        local yOff = -10 - (def.row - 1) * 49

        local sBtn = CreateFrame("Button", nil, leftPanel, "BackdropTemplate")
        sBtn:SetSize(40, 40)
        if def.side == "L" then
            sBtn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 10, yOff)
        else
            sBtn:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -10, yOff)
        end
        sBtn:SetBackdrop({
            bgFile = WHITE_TEX,
            edgeFile = WHITE_TEX,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        sBtn:SetBackdropColor(0.08, 0.11, 0.16, 0.90)
        sBtn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.25)

        local icon = sBtn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(def.emptyTex)
        sBtn.icon = icon

        local ilvlTxt = sBtn:CreateFontString(nil, "OVERLAY")
        StyleFont(ilvlTxt, 10, 1.0, 0.92, 0.55)
        ilvlTxt:SetPoint("BOTTOMRIGHT", sBtn, "BOTTOMRIGHT", -2, 2)
        sBtn.ilvlTxt = ilvlTxt

        -- Secili slot altin cercevesi
        local sel = CreateFrame("Frame", nil, sBtn, "BackdropTemplate")
        sel:SetAllPoints(sBtn)
        sel:SetBackdrop({ edgeFile = WHITE_TEX, edgeSize = 2 })
        sel:SetBackdropBorderColor(1.0, 0.85, 0.20, 1.0)
        sel:Hide()
        sBtn.selBorder = sel

        -- Slotun yanindaki tiklanabilir YESIL YUKSELTME OKU
        local arrowBtn = CreateFrame("Button", nil, leftPanel, "BackdropTemplate")
        arrowBtn:SetSize(18, 22)
        if def.side == "L" then
            arrowBtn:SetPoint("LEFT", sBtn, "RIGHT", 2, 0)
        else
            arrowBtn:SetPoint("RIGHT", sBtn, "LEFT", -2, 0)
        end
        arrowBtn:SetBackdrop({
            bgFile = WHITE_TEX,
            edgeFile = WHITE_TEX,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        arrowBtn:SetBackdropColor(0.08, 0.36, 0.18, 0.88)
        arrowBtn:SetBackdropBorderColor(0.25, 1.0, 0.45, 0.90)
        local aTxt = arrowBtn:CreateFontString(nil, "OVERLAY")
        StyleFont(aTxt, 12, 0.35, 1.0, 0.48)
        aTxt:SetPoint("CENTER", 0, 0)
        aTxt:SetText(def.side == "L" and ">" or "<")
        arrowBtn.txt = aTxt
        arrowBtn:Hide()
        sBtn.arrowBtn = arrowBtn

        local function OnSelectSlot()
            selectedSlotID = def.slotID
            GearAdvisor:RefreshAll()
        end
        sBtn:SetScript("OnClick", OnSelectSlot)
        arrowBtn:SetScript("OnClick", OnSelectSlot)

        sBtn:SetScript("OnEnter", function(selfBtn)
            if not GameTooltip then return end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            local eq = GetEquippedSlotInfo(def.slotID)
            if eq and eq.link then
                pcall(GameTooltip.SetHyperlink, GameTooltip, eq.link)
            else
                GameTooltip:SetText(def.name .. " (Bos)", 0.85, 0.85, 0.85)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Tikla: AH yukseltmelerini listele", 0.35, 1.0, 0.50)
            GameTooltip:Show()
        end)
        sBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        arrowBtn:SetScript("OnEnter", function(selfBtn)
            if not GameTooltip then return end
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            GameTooltip:SetText(def.name .. " — AH Yukseltme Var!", 0.35, 1.0, 0.48)
            GameTooltip:AddLine("Tikla: Daha iyi AH esyalarini gor", 0.90, 0.94, 1.0)
            GameTooltip:Show()
        end)
        arrowBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        sBtn.def = def
        slotButtons[def.slotID] = sBtn
    end

    -- SAG PANEL: Secili Slotun AH Yukseltme Listesi
    local rightPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 8, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    rightPanel:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    rightPanel:SetBackdropColor(0.05, 0.08, 0.13, 0.75)
    rightPanel:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.12)

    local listHdr = rightPanel:CreateFontString(nil, "OVERLAY")
    StyleFont(listHdr, 12, 1.0, 0.86, 0.35)
    listHdr:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 10, -8)
    listHdr:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -10, -8)
    listHdr:SetJustifyH("LEFT")
    f.listHdr = listHdr

    local hdrSep = rightPanel:CreateTexture(nil, "ARTWORK")
    hdrSep:SetHeight(1)
    hdrSep:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 8, -26)
    hdrSep:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -8, -26)
    hdrSep:SetColorTexture(1.0, 1.0, 1.0, 0.12)

    local scroll = CreateFrame("ScrollFrame", "QuestGoToZGearScroll", rightPanel)
    scroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 6, -30)
    scroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -6, 26)
    scroll:EnableMouseWheel(true)

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(336, 1)
    scroll:SetScrollChild(scrollChild)
    scroll:SetScript("OnMouseWheel", function(selfS, delta)
        local cur = selfS:GetVerticalScroll() or 0
        local maxS = selfS:GetVerticalScrollRange() or 0
        local nxt = math.max(0, math.min(maxS, cur - delta * 68))
        selfS:SetVerticalScroll(nxt)
    end)
    f.scroll = scroll
    f.scrollChild = scrollChild

    local emptyListTxt = rightPanel:CreateFontString(nil, "OVERLAY")
    StyleFont(emptyListTxt, 11, 0.70, 0.76, 0.86)
    emptyListTxt:SetPoint("CENTER", scroll, "CENTER", 0, 10)
    emptyListTxt:SetWidth(300)
    emptyListTxt:SetJustifyH("CENTER")
    f.emptyListTxt = emptyListTxt

    local footerHint = rightPanel:CreateFontString(nil, "OVERLAY")
    StyleFont(footerHint, 10, 0.65, 0.72, 0.82)
    footerHint:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 10, 7)
    footerHint:SetText("Sol tik: Karakterde dene (+AH aciksa ara)  |  Shift+Tik: Link")

    f:SetScript("OnShow", function()
        if not filterInitialized then
            filterInitialized = true
            local okL, pLvl = ns:SafeGlobal("UnitLevel", "player")
            local lv = (okL and ns:IsSafeNumber(pLvl) and pLvl > 0) and pLvl or 60
            minLvlFilter = math.max(1, lv - 10)
            maxLvlFilter = lv
            f.minBox:SetText(tostring(minLvlFilter))
            f.maxBox:SetText(tostring(maxLvlFilter))
        end
        if f.model and type(f.model.SetUnit) == "function" then
            pcall(f.model.SetUnit, f.model, "player")
        end
        local st = GetAHStore(false)
        local hasAny = false
        if st and type(st.items) == "table" then
            for _ in pairs(st.items) do hasAny = true; break end
        end
        if not hasAny then
            TryImportExternalAHData()
        end
        GearAdvisor:RefreshAll()
    end)

    f:Hide()
    mainFrame = f
    return f
end

local function GetOrCreateListRow(parent, idx)
    local row = listRows[idx]
    if row then return row end

    row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(336, 36)
    row:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.07, 0.10, 0.16, 0.78)
    row:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.10)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local nameTxt = row:CreateFontString(nil, "OVERLAY")
    StyleFont(nameTxt, 11, 1, 1, 1)
    nameTxt:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
    nameTxt:SetPoint("RIGHT", row, "RIGHT", -84, 0)
    nameTxt:SetJustifyH("LEFT")
    nameTxt:SetWordWrap(false)
    row.nameTxt = nameTxt

    local subTxt = row:CreateFontString(nil, "OVERLAY")
    StyleFont(subTxt, 10, 0.72, 0.80, 0.90)
    subTxt:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 1)
    subTxt:SetJustifyH("LEFT")
    row.subTxt = subTxt

    local priceTxt = row:CreateFontString(nil, "OVERLAY")
    StyleFont(priceTxt, 11, 1.0, 0.90, 0.55)
    priceTxt:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    priceTxt:SetJustifyH("RIGHT")
    row.priceTxt = priceTxt

    row:SetScript("OnEnter", function(selfR)
        selfR:SetBackdropBorderColor(0.45, 0.85, 1.0, 0.75)
        if GameTooltip and selfR.item and selfR.item.link then
            GameTooltip:SetOwner(selfR, "ANCHOR_LEFT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, selfR.item.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(selfR)
        selfR:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.10)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(selfR)
        local item = selfR.item
        if not item then return end
        if type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() and type(_G.ChatEdit_InsertLink) == "function" then
            pcall(_G.ChatEdit_InsertLink, item.link)
            return
        end
        -- 1) 3D Karakter modelinde uzerinde dene!
        if mainFrame and mainFrame.model and type(mainFrame.model.TryOn) == "function" then
            pcall(mainFrame.model.TryOn, mainFrame.model, item.link)
        end
        -- 2) AH aciksa dogrudan AH'de o esyayi ara!
        if _G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown() and _G.C_AuctionHouse and type(_G.C_AuctionHouse.SendBrowseQuery) == "function" then
            pcall(_G.C_AuctionHouse.SendBrowseQuery, {
                searchString = item.name or "",
                sorts = {},
                filters = {},
            })
            ns:Print("AH'de araniyor: " .. (item.link or item.name or ""))
        end
    end)

    row:Hide()
    listRows[idx] = row
    return row
end

function GearAdvisor:RefreshAll()
    if not mainFrame or not mainFrame:IsShown() then return end

    local sortMode = (ns.db and ns.db.gearSortMode) or "price_asc"
    if sortMode == "price" or sortMode == "price_asc" then
        mainFrame.sortBtn.label:SetText("Fiyat (Ucuz)")
    elseif sortMode == "price_desc" then
        mainFrame.sortBtn.label:SetText("Fiyat (Pahali)")
    else
        mainFrame.sortBtn.label:SetText("Sirala: iLvl")
    end

    if mainFrame.upgFilterBtn then
        if onlyUpgradesFilter then
            mainFrame.upgFilterBtn.label:SetText("Sadece +iLvl")
            mainFrame.upgFilterBtn.label:SetTextColor(0.35, 1.0, 0.50)
            mainFrame.upgFilterBtn:SetBackdropBorderColor(0.30, 0.95, 0.45, 0.85)
        else
            mainFrame.upgFilterBtn.label:SetText("Yukselt: Tumu")
            mainFrame.upgFilterBtn.label:SetTextColor(0.95, 0.97, 1.0)
            mainFrame.upgFilterBtn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.24)
        end
    end

    local store = GetAHStore(false)
    local totalCached = 0
    if store and type(store.items) == "table" then
        for _ in pairs(store.items) do totalCached = totalCached + 1 end
    end
    if not scanActive then
        if totalCached > 0 then
            mainFrame.scanStatusText:SetText(string.format("%s | %d esya", FormatAge(store.t), totalCached))
        else
            mainFrame.scanStatusText:SetText("AH'ye gidip 'AH Tara'ya basin")
        end
    end

    -- 1) Sol 16 slotu ve yesil yukseltme oklarini guncelle
    for i = 1, #SLOT_DEFS do
        local def = SLOT_DEFS[i]
        local sBtn = slotButtons[def.slotID]
        if sBtn then
            local eq = GetEquippedSlotInfo(def.slotID)
            if eq then
                sBtn.icon:SetTexture(eq.icon or def.emptyTex)
                local r, g, b = GetQualityRGB(eq.quality)
                sBtn:SetBackdropBorderColor(r, g, b, 0.85)
                sBtn.ilvlTxt:SetText(eq.ilvl > 0 and tostring(eq.ilvl) or "")
            else
                sBtn.icon:SetTexture(def.emptyTex)
                sBtn:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.22)
                sBtn.ilvlTxt:SetText("")
            end

            sBtn.selBorder:SetShown(def.slotID == selectedSlotID)

            local ups = GetUpgradesForSlot(def.slotID, true)
            if #ups > 0 then
                sBtn.arrowBtn:Show()
            else
                sBtn.arrowBtn:Hide()
            end
        end
    end

    -- 2) Sag listede secili slotun AH esyalarini goster
    local selDef = SLOT_BY_ID[selectedSlotID] or SLOT_DEFS[1]
    local eqSel = GetEquippedSlotInfo(selDef.slotID)
    local curIlvl = (eqSel and eqSel.ilvl) or 0
    local items = GetUpgradesForSlot(selDef.slotID, onlyUpgradesFilter)

    mainFrame.listHdr:SetText(string.format("%s (Mevcut: %d iLvl) — %d AH esyasi", selDef.name, curIlvl, #items))

    if #items == 0 then
        for i = 1, #listRows do listRows[i]:Hide() end
        if totalCached == 0 then
            mainFrame.emptyListTxt:SetText("Henuz AH verisi yok.\nAuction House (Muzayede Evi) acip 'AH Tara' butonuna basin (veya Auctionator Full Scan yapin).")
        else
            mainFrame.emptyListTxt:SetText(string.format("Lv %d-%d araliginda '%s' icin uygun AH esyasi bulunamadi.", minLvlFilter, maxLvlFilter, selDef.name))
        end
        mainFrame.emptyListTxt:Show()
        mainFrame.scrollChild:SetHeight(1)
        return
    end

    mainFrame.emptyListTxt:Hide()
    local maxShow = math.min(#items, 60)
    for i = 1, math.max(maxShow, #listRows) do
        local row = (i <= maxShow) and GetOrCreateListRow(mainFrame.scrollChild, i) or listRows[i]
        local item = (i <= maxShow) and items[i] or nil
        if row and item then
            row.item = item
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", mainFrame.scrollChild, "TOPLEFT", 0, -((i - 1) * 39))
            row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

            local r, g, b = GetQualityRGB(item.quality)
            row.nameTxt:SetText(item.name or "?")
            row.nameTxt:SetTextColor(r, g, b)

            local diff = (item.ilvl or 0) - curIlvl
            local diffStr = ""
            if diff > 0 then
                diffStr = string.format(" |cff33ff66(+%d)|r", diff)
            elseif diff < 0 then
                diffStr = string.format(" |cffff5555(%d)|r", diff)
            end
            row.subTxt:SetText(string.format("iLvl %d%s  •  Req Lv %d", item.ilvl or 0, diffStr, item.reqLvl or 1))
            row.priceTxt:SetText(FormatGold(item.price))
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    mainFrame.scrollChild:SetHeight(maxShow * 39 + 4)
    mainFrame.scroll:SetVerticalScroll(0)
end

function GearAdvisor:Toggle()
    if ns:IsInCombat() then
        ns:Print("Savas sirasinda ekipman penceresi acilamaz.")
        return
    end
    local f = EnsureMainFrame()
    if f:IsShown() then f:Hide() else f:Show() end
end

-- =================================================================
-- MINIMAP BUTONU (OneForAll ikonunun hemen yaninda) + C PENCERE KISAYOLU
-- =================================================================
local function PositionMinimapButton(angle)
    if not minimapBtn or not _G.Minimap then return end
    local half = (_G.Minimap:GetWidth() or 140) / 2
    local radius = half + 5
    local rad = math.rad(angle or 252)
    local x, y = math.cos(rad), math.sin(rad)
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", _G.Minimap, "CENTER", x * radius, y * radius)
end

local function CreateMinimapButton()
    if minimapBtn or not _G.Minimap then return end

    local btn = CreateFrame("Button", "QuestGoToZGearMinimapBtn", _G.Minimap, "BackdropTemplate")
    btn:SetSize(28, 28)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(0.05, 0.08, 0.14, 0.92)
    btn:SetBackdropBorderColor(1.0, 0.82, 0.25, 0.90)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.22)

    local dragging = false
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(selfB)
        dragging = true
        selfB:SetScript("OnUpdate", function()
            if not dragging then return end
            local mx, my = _G.Minimap:GetCenter()
            if not mx then return end
            local scale = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            local ang = math.deg(math.atan2(cy - my, cx - mx))
            if ang < 0 then ang = ang + 360 end
            if ns.db then ns.db.gearMinimapAngle = ang end
            PositionMinimapButton(ang)
        end)
    end)
    btn:SetScript("OnDragStop", function(selfB)
        dragging = false
        selfB:SetScript("OnUpdate", nil)
    end)
    btn:SetScript("OnClick", function()
        GearAdvisor:Toggle()
    end)
    btn:SetScript("OnEnter", function(selfB)
        if not GameTooltip then return end
        GameTooltip:SetOwner(selfB, "ANCHOR_LEFT")
        GameTooltip:SetText("QuestGoToZ — AH Ekipman Yukseltme", 1, 0.85, 0.2)
        GameTooltip:AddLine("Sol tik: Karakter & AH yukseltme ekranini ac", 0.85, 0.90, 0.96)
        GameTooltip:AddLine("Surukle: Minimap kenarinda konum degistir", 0.65, 0.72, 0.82)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    minimapBtn = btn

    -- OneForAll ikonu varsa onun hemen yanina yerlestir
    local angle = (ns.db and ns.db.gearMinimapAngle) or 252
    if type(_G.OneForAllDB) == "table" and ns:IsSafeNumber(_G.OneForAllDB.minimapAngle)
        and (not ns.db or ns.db.gearMinimapAngle == ns.DEFAULTS.gearMinimapAngle) then
        angle = (_G.OneForAllDB.minimapAngle + 27) % 360
    end
    PositionMinimapButton(angle)
end

-- AH penceresi acilinca ustte UIParent-parented hizli "AH Tara" butonu
local function EnsureAHScanButton()
    if ahScanBtn then return ahScanBtn end
    ahScanBtn = CreateActionBtn(UIParent, 118, 22, "AH Tara (Frkn)", function()
        GearAdvisor:StartAHScan()
    end)
    ahScanBtn:SetFrameStrata("HIGH")
    ahScanBtn:Hide()
    return ahScanBtn
end

-- C penceresi (CharacterFrame) acilinca sag ustte UIParent-parented kisayol butonu
local function EnsureCharacterQuickButton()
    if charQuickBtn then return charQuickBtn end
    charQuickBtn = CreateActionBtn(UIParent, 98, 20, "AH Yukseltme", function()
        GearAdvisor:Toggle()
    end)
    charQuickBtn:SetFrameStrata("HIGH")
    charQuickBtn:Hide()
    return charQuickBtn
end

function GearAdvisor:RefreshButtons()
    local show = (not ns.db) or (ns.db.showGearAdvisorBtn ~= false)
    if minimapBtn then
        minimapBtn:SetShown(show)
    end
    if not show and charQuickBtn then
        charQuickBtn:Hide()
    end
end

local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
evFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
evFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
evFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
evFrame:SetScript("OnEvent", function(_, event)
    if event == "REPLICATE_ITEM_LIST_UPDATE" then
        BeginReadingReplicateData()
    elseif event == "AUCTION_HOUSE_SHOW" then
        if not ns:IsInCombat() and _G.AuctionHouseFrame then
            local b = EnsureAHScanButton()
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", _G.AuctionHouseFrame, "TOPRIGHT", -34, -2)
            b:Show()
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if ahScanBtn then ahScanBtn:Hide() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if mainFrame and mainFrame:IsShown() then
            GearAdvisor:RefreshAll()
        end
    end
end)

ns:RegisterCallback("PLAYER_LOGIN", function()
    CreateMinimapButton()
    GearAdvisor:RefreshButtons()

    if type(_G.CharacterFrame) == "table" and type(_G.CharacterFrame.HookScript) == "function" then
        _G.CharacterFrame:HookScript("OnShow", function()
            if ns:IsInCombat() or (ns.db and ns.db.showGearAdvisorBtn == false) then return end
            local qb = EnsureCharacterQuickButton()
            qb:ClearAllPoints()
            qb:SetPoint("BOTTOMRIGHT", _G.CharacterFrame, "TOPRIGHT", -28, 2)
            qb:Show()
        end)
        _G.CharacterFrame:HookScript("OnHide", function()
            if charQuickBtn then charQuickBtn:Hide() end
        end)
    end
end)

ns:RegisterCallback("CONFIG_CHANGED", function()
    GearAdvisor:RefreshButtons()
end)
