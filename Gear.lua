local ADDON, ns = ...
local L = ns.L

local Equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName

local swappedForCombat = false

ns:On("AM_DB_READY", function()
    local db = ns.db
    db.gear = db.gear or {}
    db.gear.fishing, db.gear.normal = nil, nil -- 예전 버전의 장비 세트 기록 정리
    db.gear.weapons = db.gear.weapons or {}   -- 마지막으로 든 평소 무기 [16], [17]
end)

local function Have(itemID)
    return itemID and (C_Item.GetItemCount(itemID) > 0)
end

-- 평소 무기 / 낚싯대 기억 ----------------------------------------------------------
ns:On("PLAYER_EQUIPMENT_CHANGED", function(slot)
    if not ns.db then return end
    if slot ~= 16 and slot ~= 17 and slot ~= nil then return end
    if ns:HasPole() then
        ns.db.gear.pole = GetInventoryItemID("player", 16) or ns.db.gear.pole
    else
        ns.db.gear.weapons[16] = GetInventoryItemID("player", 16)
        ns.db.gear.weapons[17] = GetInventoryItemID("player", 17)
    end
end)

-- 전투 시작: 낚싯대를 평소 무기로 교체 (무기는 전투 중에도 교체 가능)
ns:On("PLAYER_REGEN_DISABLED", function()
    if not ns.settings or not ns.settings.combatSwap or not ns:HasPole() then return end
    local w = ns.db.gear.weapons
    if not Have(w[16]) then return end
    Equip(w[16], 16)
    if Have(w[17]) then Equip(w[17], 17) end
    swappedForCombat = true
end)

-- 전투 끝: 원하면 낚싯대를 다시 듦
ns:On("PLAYER_REGEN_ENABLED", function()
    if not swappedForCombat then return end
    swappedForCombat = false
    if ns.settings.reequipPole and Have(ns.db.gear.pole) and not ns:HasPole() then
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then Equip(ns.db.gear.pole, 16) end
        end)
    end
end)

-- 가방에서 가장 좋은 낚싯대 착용 -----------------------------------------------------
-- 알려진 낚싯대 보너스 (모르는 낚싯대는 툴팁의 "낚시 +N" 을 읽음)
local POLE_BONUS = {
    [6256] = 0,    -- 낚싯대
    [12225] = 3,   -- 블럼프 가문의 낚싯대
    [6365] = 5,    -- 튼튼한 낚싯대
    [6366] = 15,   -- 흑단 낚싯대
    [6367] = 20,   -- 대형 무쇠 낚싯대
    [19022] = 25,  -- 냇 페이글의 낚싯대
    [19970] = 35,  -- 아케이나이트 낚싯대
}

local function TooltipBonus(itemID)
    if not C_TooltipInfo or not C_TooltipInfo.GetItemByID then return 0 end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or not data or not data.lines then return 0 end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text and (text:find("낚시") or text:find("Fishing") or text:find("Angeln") or text:find("Pêche") or text:find("Pesca") or text:find("釣魚")) then
            local n = tonumber(text:match("%+(%d+)"))
            if n then return n end
        end
    end
    return 0
end

local function PoleBonus(itemID)
    return POLE_BONUS[itemID] or TooltipBonus(itemID)
end

local function IsPoleItem(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return (classID == 2 and subClassID == 20) or (classID == 19 and subClassID == 10)
end

-- 반환: 가장 좋은 낚싯대 itemID, 보너스
local function BestPoleInBags()
    local bestID, bestBonus
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if IsPoleItem(id) then
                local b = PoleBonus(id)
                if not bestBonus or b > bestBonus then bestID, bestBonus = id, b end
            end
        end
    end
    return bestID, bestBonus
end

function ns:EquipBestPole()
    local bagID, bagBonus = BestPoleInBags()
    local worn = GetInventoryItemID("player", 16)
    if ns:HasPole() then
        -- 이미 낚싯대를 들고 있으면: 가방에 더 좋은 게 있으면 바꾸고, 아니면 평소 무기로
        if bagID and bagBonus > PoleBonus(worn) then
            Equip(bagID, 16)
            ns:Print(L["더 좋은 낚싯대로 바꿨어요: "] .. ns:ItemName(bagID))
        else
            ns:EquipWeapons()
        end
        return
    end
    if not bagID then
        ns:Print(L["가방에 낚싯대가 없어요."])
        return
    end
    Equip(bagID, 16)
    ns:Print(string.format(L["%s 착용 (낚시 +%d)"], ns:ItemName(bagID), bagBonus))
end

-- 평소 무기로 바꾸기 (무기는 전투 중에도 바꿀 수 있음)
function ns:EquipWeapons()
    local w = ns.db.gear.weapons
    if Have(w[16]) then
        Equip(w[16], 16)
        if Have(w[17]) then Equip(w[17], 17) end
        return true
    end
    ns:Print(L["돌아갈 무기를 가방에서 찾지 못했어요."])
    return false
end

-- 낚시 종료: 이번 세션을 정리하고 평소 무기로
function ns:StopFishing()
    local s = ns:Session()
    if s and s.catches > 0 then
        local dur = math.max(0, s.last - s.start)
        ns:Print(L["낚시를 마쳤어요. 이번 세션: %d마리 · %s"]:format(s.catches, ns:FormatDuration(dur)))
    end
    ns:EndSession()
    if ns:HasPole() then ns:EquipWeapons() end
end
