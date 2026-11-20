local _, ns = ...

local PartySync = {}
ns.PartySync = PartySync

local PREFIX = "QUESTGOTOZ"
local lastBroadcastTime = 0
local BROADCAST_THROTTLE = 2.0

-- [questID] = { [senderShortName] = { text = "5/8", ts = GetTime() } }
local partyProgress = {}

local function StripRealm(name)
    if not ns:IsSafeString(name) then
        return nil
    end
    local short = name:match("^([^%-]+)")
    return short or name
end

local function GetSelfShortName()
    local okN, n = ns:SafeGlobal("UnitName", "player")
    if okN and ns:IsSafeString(n) then
        return StripRealm(n)
    end
    return nil
end

local function GetGroupChannel()
    local okInst, inInst = ns:SafeGlobal("IsInGroup", _G.LE_PARTY_CATEGORY_INSTANCE or 2)
    if okInst and inInst then
        return "INSTANCE_CHAT"
    end
    local okRaid, inRaid = ns:SafeGlobal("IsInRaid")
    if okRaid and inRaid then
        return "RAID"
    end
    local okGrp, inGrp = ns:SafeGlobal("IsInGroup")
    if okGrp and inGrp then
        return "PARTY"
    end
    return nil
end

-- Kendi gorev ilerlememizi kisa formatta paketler (orn: "123:3/8;456:OK")
local function BuildProgressPayload()
    local okNum, numEntries = ns:TrySafeC("C_QuestLog", "GetNumQuestLogEntries")
    if not okNum or not ns:IsSafeNumber(numEntries) then
        return nil
    end

    local parts = {}
    local totalLen = 0
    for idx = 1, numEntries do
        local okInfo, info = ns:TrySafeC("C_QuestLog", "GetInfo", idx)
        if okInfo and type(info) == "table" and not info.isHeader and not info.isHidden and ns:IsSafeNumber(info.questID) then
            local qid = info.questID
            local okComp, isComp = ns:TrySafeC("C_QuestLog", "IsComplete", qid)
            local statusStr = nil
            if okComp and isComp == true then
                statusStr = "OK"
            else
                local okObj, objectives = ns:TrySafeC("C_QuestLog", "GetQuestObjectives", qid)
                if okObj and type(objectives) == "table" and #objectives > 0 then
                    local sumCur, sumReq = 0, 0
                    for i = 1, #objectives do
                        local obj = objectives[i]
                        if type(obj) == "table" and ns:IsSafeNumber(obj.numFulfilled) and ns:IsSafeNumber(obj.numRequired) and obj.numRequired > 0 then
                            sumCur = sumCur + obj.numFulfilled
                            sumReq = sumReq + obj.numRequired
                        end
                    end
                    if sumReq > 0 then
                        statusStr = string.format("%d/%d", sumCur, sumReq)
                    end
                end
            end

            if statusStr then
                local token = tostring(qid) .. ":" .. statusStr
                if totalLen + #token + 1 > 230 then
                    break
                end
                table.insert(parts, token)
                totalLen = totalLen + #token + 1
            end
        end
    end

    if #parts == 0 then
        return nil
    end
    return table.concat(parts, ";")
end

function PartySync:BroadcastNow(force)
    local db = ns.db or ns.DEFAULTS
    if not db.partySync then
        return
    end

    local channel = GetGroupChannel()
    if not channel then
        return
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    if not force and (now - lastBroadcastTime) < BROADCAST_THROTTLE then
        return
    end

    local payload = BuildProgressPayload()
    if not payload then
        return
    end

    lastBroadcastTime = now
    ns:TrySafeC("C_ChatInfo", "SendAddonMessage", PREFIX, payload, channel)
end

local function ParseIncoming(sender, message)
    local db = ns.db or ns.DEFAULTS
    if not db.partySync then
        return
    end
    if not ns:IsSafeString(sender) or not ns:IsSafeString(message) then
        return
    end

    local shortSender = StripRealm(sender)
    local selfName = GetSelfShortName()
    if not shortSender or (selfName and shortSender == selfName) then
        return
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    for token in message:gmatch("[^;]+") do
        local qStr, st = token:match("^(%d+):([%w/%-]+)$")
        local qid = qStr and tonumber(qStr)
        if qid and st then
            partyProgress[qid] = partyProgress[qid] or {}
            partyProgress[qid][shortSender] = {
                text = (st == "OK") and "Tamam" or st,
                ts = now,
            }
        end
    end
end

-- Belirli bir gorev icin gruptaki arkadaslarin ilerlemesini dondurur
function PartySync:GetPartyProgress(questID)
    local db = ns.db or ns.DEFAULTS
    if not db.partySync or not ns:IsSafeNumber(questID) then
        return nil
    end

    local bucket = partyProgress[questID]
    if type(bucket) ~= "table" then
        return nil
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    local result = {}
    for name, info in pairs(bucket) do
        if type(info) == "table" and (now - (info.ts or 0)) <= 180 then
            table.insert(result, { name = name, text = info.text })
        else
            bucket[name] = nil
        end
    end

    if #result == 0 then
        return nil
    end
    table.sort(result, function(a, b)
        return a.name < b.name
    end)
    return result
end

local syncEventFrame = CreateFrame("Frame", "QuestGoToZPartySyncEventFrame")
syncEventFrame:RegisterEvent("CHAT_MSG_ADDON")
syncEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
syncEventFrame:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
    if event == "CHAT_MSG_ADDON" then
        if prefix == PREFIX then
            ParseIncoming(sender, msg)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not GetGroupChannel() then
            wipe(partyProgress)
        else
            ns:TrySafeC("C_Timer", "After", 1.0, function()
                PartySync:BroadcastNow(true)
            end)
        end
    end
end)

ns:RegisterCallback("PLAYER_LOGIN", function()
    ns:TrySafeC("C_ChatInfo", "RegisterAddonMessagePrefix", PREFIX)
    ns:TrySafeC("C_Timer", "After", 2.0, function()
        PartySync:BroadcastNow(true)
    end)
end)

ns:RegisterCallback("QUEST_LOG_UPDATE", function()
    PartySync:BroadcastNow(false)
end)
