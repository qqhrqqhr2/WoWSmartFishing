local ADDON, ns = ...

-- 낚시 주문 ID (클래식 랭크 + 현행 클라이언트). 알려진 것 중 첫 번째를 사용.
local FISHING_IDS = { 131474, 7620, 7731, 7732, 18248 }
local FISHING_SET = {}
for _, id in ipairs(FISHING_IDS) do FISHING_SET[id] = true end

-- 미끼: 효과 큰 순서
local LURES = {
    { id = 6533, bonus = 100 }, -- 수생 물고기 유인기
    { id = 6532, bonus = 75 },  -- 밝게 빛나는 미끼
    { id = 7307, bonus = 75 },  -- 살점 먹는 벌레
    { id = 6811, bonus = 50 },  -- 수생 물고기 렌즈
    { id = 6530, bonus = 50 },  -- 지렁이
    { id = 6529, bonus = 25 },  -- 반짝이는 미끼
}

local owner = CreateFrame("Frame", "WoWSmartFishingBindingOwner")
local castButton = CreateFrame("Button", "WoWSmartFishingCastButton", UIParent, "SecureActionButtonTemplate")
castButton:RegisterForClicks("AnyUp", "AnyDown")
castButton:SetAttribute("type", "macro")
castButton:Hide()

local mode           -- nil | "cast" | "interact"
local channeling = false

local function FishingSpellName()
    for _, id in ipairs(FISHING_IDS) do
        if IsPlayerSpell(id) then
            return C_Spell.GetSpellName(id)
        end
    end
    return C_Spell.GetSpellName(7620)
end

local function IsFishingSpell(spellID)
    spellID = ns.Num(spellID)
    if spellID and FISHING_SET[spellID] then return true end
    local name = spellID and C_Spell.GetSpellName(spellID)
    return name ~= nil and name == FishingSpellName()
end

ns.IsFishingSpell = IsFishingSpell

-- 낚시 숙련도 (현재, 최대, 미끼·장비 보너스). 못 얻으면 nil
function ns:FishingSkill()
    if not GetProfessions then return nil end
    local ok, _, _, _, fishing = pcall(GetProfessions)
    if not ok or not fishing then return nil end
    local ok2, _, _, rank, maxRank, _, _, _, modifier = pcall(GetProfessionInfo, fishing)
    if not ok2 or not rank then return nil end
    return rank, maxRank, modifier or 0
end

-- 미끼 남은 시간(초). 없으면 nil
function ns:LureRemaining()
    local hasMain, expiration = GetWeaponEnchantInfo()
    if hasMain and expiration then return expiration / 1000 end
end

local function IsPole(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    -- 무기/낚싯대(2,20) 또는 전문 기술 도구/낚시(19,10)
    return (classID == 2 and subClassID == 20) or (classID == 19 and subClassID == 10)
end

local function HasPole()
    return IsPole(GetInventoryItemID("player", 16)) or IsPole(GetInventoryItemID("player", 28))
end

function ns:HasPole() return HasPole() end

local function BestLure()
    for _, lure in ipairs(LURES) do
        if C_Item.GetItemCount(lure.id) > 0 then return lure end
    end
end

local function NeedsLure()
    if not ns.settings.autoLure then return false end
    local hasMainHandEnchant = GetWeaponEnchantInfo()
    if hasMainHandEnchant then return false end
    return BestLure() ~= nil
end

local function BuildMacro()
    if NeedsLure() then
        local lure = BestLure()
        return "/use item:" .. lure.id .. "\n/use 16"
    end
    local name = FishingSpellName()
    if name then return "/cast " .. name end
    return ""
end

local function SetMode(newMode)
    if InCombatLockdown() then return end
    if newMode == mode then return end
    ClearOverrideBindings(owner)
    local key = ns.settings and ns.settings.key or "SPACE"
    if newMode == "cast" then
        SetOverrideBindingClick(owner, true, key, "WoWSmartFishingCastButton", "LeftButton")
    elseif newMode == "interact" then
        SetOverrideBinding(owner, true, key, "INTERACTTARGET")
    elseif newMode == "mouseover" then
        -- 찌가 자동 인식되지 않을 때: 마우스를 찌에 올리고 누르면 건짐
        SetOverrideBinding(owner, true, key, "INTERACTMOUSEOVER")
    end
    mode = newMode
end

-- 낚시찌 오브젝트 번호
local BOBBER_ID = "35591"

-- 지금 상호작용 대상(소프트 타겟)이 낚시찌인지
local function BobberTargeted()
    local guid = ns.Str(ns.Safe(UnitGUID, "softinteract"))
    if not guid then return false end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "GameObject" then return false end
    if id == BOBBER_ID then return true end
    local name = ns.Str(ns.Safe(UnitName, "softinteract"))
    return name ~= nil and (name:find("찌") or name:find("Bobber") or name:find("Schwimmer") or name:find("Flotteur") or name:find("Corcho") or name:find("浮標")) ~= nil
end

-- 낚는 중 찌 인식 상태: nil(낚는 중 아님) / true / false
ns.bobberFound = nil

local function Refresh()
    if not ns.settings or InCombatLockdown() then return end
    if not ns.settings.oneButton or not HasPole() then
        SetMode(nil)
        return
    end
    if channeling then
        ns.bobberFound = BobberTargeted()
        SetMode(ns.bobberFound and "interact" or "mouseover")
    else
        ns.bobberFound = nil
        castButton:SetAttribute("macrotext", BuildMacro())
        SetMode("cast")
    end
end
ns.RefreshFishing = Refresh

local function SetCVarSafe(name, value)
    pcall(function()
        if GetCVar(name) ~= nil and GetCVar(name) ~= tostring(value) then SetCVar(name, value) end
    end)
end

local function ApplySoftInteract()
    if InCombatLockdown() or not ns.settings.setSoftInteract then return end
    -- 3 = 항상: 찌 같은 오브젝트를 자동으로 상호작용 대상으로 잡음
    SetCVarSafe("SoftTargetInteract", 3)
    if ns.settings.expandInteract then
        -- 찌가 멀리 떨어지거나 옆에 있어도 잡히도록 범위·각도를 넓힘
        SetCVarSafe("SoftTargetInteractRange", 30)
        SetCVarSafe("SoftTargetInteractArc", 2)
    end
end

ns:On("AM_DB_READY", function()
    ns:On("PLAYER_ENTERING_WORLD", function()
        ApplySoftInteract()
        Refresh()
    end)
end)

ns:On("AM_SETTINGS_CHANGED", function(key)
    if key == "setSoftInteract" or key == "expandInteract" then ApplySoftInteract() end
    if key == "key" then
        SetMode(nil) -- 이전 키 해제 후 새 키로 다시 등록
    end
    Refresh()
end)

ns:On("PLAYER_EQUIPMENT_CHANGED", Refresh)
ns:On("BAG_UPDATE_DELAYED", Refresh)
ns:On("UNIT_INVENTORY_CHANGED", function(unit) if unit == "player" then Refresh() end end)
ns:On("PLAYER_REGEN_ENABLED", Refresh)

-- 전투 시작: 키를 원래대로 돌려서 점프 등이 정상 동작하게
ns:On("PLAYER_REGEN_DISABLED", function()
    ClearOverrideBindings(owner)
    mode = nil
end)

-- 낚는 동안 찌 인식 상태를 계속 확인 (찌가 늦게 잡히거나 놓쳤다 다시 잡힐 때)
local watcher = CreateFrame("Frame")
local acc = 0
watcher:Hide()
watcher:SetScript("OnUpdate", function(self, dt)
    acc = acc + dt
    if acc < 0.15 then return end
    acc = 0
    if not channeling then self:Hide() return end
    local before = ns.bobberFound
    Refresh()
    if before ~= ns.bobberFound then ns:Fire("AM_BOBBER_CHANGED") end
end)

ns:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if ns.Str(unit) ~= "player" or not IsFishingSpell(spellID) then return end
    channeling = true
    Refresh()
    watcher:Show()
    ns:Fire("AM_BOBBER_CHANGED")
end)

ns:On("UNIT_SPELLCAST_CHANNEL_STOP", function(unit, _, spellID)
    if ns.Str(unit) ~= "player" or not channeling then return end
    channeling = false
    Refresh()
    ns:Fire("AM_BOBBER_CHANGED")
end)
