local ADDON, ns = ...
local L = ns.L

ns.name = "WoW Smart Fishing"

local DEFAULTS = {
    oneButton = true,   -- 원버튼 낚시
    key = "SPACE",      -- 원버튼 키
    autoLure = true,    -- 미끼 자동 사용
    showPins = true,    -- 세계지도 핀 표시
    setSoftInteract = true, -- 찌 자동 타겟(상호작용 키) CVar 설정
    combatSwap = true,  -- 전투 시작 시 낚싯대 → 평소 무기
    reequipPole = true, -- 전투가 끝나면 낚싯대 다시 들기
    showHUD = true,     -- 낚싯대를 들면 세션 창 표시
    hudScale = 1.0,     -- 세션 창 크기
    pinScale = 1.0,     -- 지도 핀 크기
    sessionIdle = 15,   -- 이 시간(분) 동안 안 던지면 새 세션
    newFishAlert = true, -- 처음 낚은 물고기 알림
    autoLoot = true,    -- 낚은 것 자동 획득
    expandInteract = true, -- 찌 인식 범위 넓히기
    minimapButton = true, -- 미니맵 버튼 표시
    mapButton = true,   -- 세계지도의 물고기 선택 버튼 표시
    showPools = true,   -- 기본 데이터: 물고기 떼 출현 지점 표시
    showExpected = true, -- 기본 데이터: 물고기를 고르면 나오는 지역과 확률 표시
    showLegend = true,  -- 세계지도에 일반 낚시 어종 목록 표시
    itemTooltip = true, -- 아이템 툴팁에 잡히는 곳 표시
    language = "auto",  -- 애드온 언어 (auto = 게임 언어)
    legendCollapsed = false, -- 어종 목록 접힘
    shareCatches = true, -- 낚을 때 길드/파티에 위치 공유
    receiveShared = true, -- 다른 플레이어가 공유한 위치 받기
    showShared = true,  -- 공유받은 위치 지도에 표시
    minimapAngle = 200, -- 미니맵 버튼 위치(각도)
}

-- 이벤트 디스패처 -----------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if not event:match("^AM_") then
            frame:RegisterEvent(event)
        end
    end
    table.insert(handlers[event], fn)
end

function ns:Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    ns:Fire(event, ...)
end)

-- 와우 포에버는 일부 값을 보호된 값(secret value)으로 줌: 읽기 전에 확인
local function pass(ok, ...)
    if ok then return ... end
end

function ns.Safe(fn, ...)
    if type(fn) ~= "function" then return end
    return pass(pcall(fn, ...))
end

function ns.Readable(v)
    if v == nil then return false end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return false end
    end
    if canaccessvalue then
        local ok, can = pcall(canaccessvalue, v)
        if not ok or not can then return false end
    end
    return true
end

function ns.Str(v) if ns.Readable(v) and type(v) == "string" then return v end end
function ns.Num(v) if ns.Readable(v) and type(v) == "number" and v == v then return v end end

function ns:Print(msg)
    print("|cff45c7e0[WoW Smart Fishing]|r " .. tostring(msg))
end

-- 저장 데이터 ---------------------------------------------------------------
ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    WoWSmartFishingDB = WoWSmartFishingDB or {}
    local db = WoWSmartFishingDB
    db.version = 1
    db.spots = db.spots or {}       -- [mapID] = { spot, spot, ... }
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULTS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    ns.db = db
    ns.settings = db.settings
    -- 언어: 저장된 설정을 먼저 적용한 뒤 화면을 만듦
    ns:ApplyLanguage(db.settings.language)
    ns:Fire("AM_DB_READY")
end)

-- 슬래시 명령 ---------------------------------------------------------------
local function OnOff(v) return v and L["|cff00ff00켜짐|r"] or L["|cffff4040꺼짐|r"] end

local function Toggle(key, label)
    ns.settings[key] = not ns.settings[key]
    ns:Print(label .. ": " .. OnOff(ns.settings[key]))
    ns:Fire("AM_SETTINGS_CHANGED", key)
end

SLASH_WOWSMARTFISHING1 = "/sf"
SLASH_WOWSMARTFISHING2 = "/스마트낚시"
SlashCmdList.WOWSMARTFISHING = function(msg)
    local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        ns:ToggleWindow()
    elseif cmd == "onebutton" or cmd == "원버튼" then
        Toggle("oneButton", L["원버튼 낚시"])
    elseif cmd == "lure" or cmd == "미끼" then
        Toggle("autoLure", L["자동 미끼"])
    elseif cmd == "pins" or cmd == "핀" then
        Toggle("showPins", L["지도 핀"])
    elseif cmd == "key" or cmd == "키" then
        if arg == "" then
            ns:Print(L["현재 원버튼 키: %s  (예: /sf key F)"]:format(ns.settings.key))
            return
        end
        ns.settings.key = arg:upper()
        ns:Print(L["원버튼 키를 %s(으)로 바꿨습니다."]:format(ns.settings.key))
        ns:Fire("AM_SETTINGS_CHANGED", "key")
    elseif cmd == "lang" or cmd == "언어" then
        local codes = { ko = "koKR", en = "enUS", tw = "zhTW", zh = "zhTW", de = "deDE", fr = "frFR", es = "esES", auto = "auto" }
        local code = codes[arg:lower()] or (ns.LANGUAGE_NAMES[arg] and arg)
        if not code then
            ns:Print(L["사용법: /sf lang auto | ko | en | tw | de | fr | es"])
            return
        end
        ns:SetLanguage(code)
    elseif cmd == "donate" or cmd == "후원" then
        ns:ShowDonate()
    elseif cmd == "config" or cmd == "설정" then
        ns:OpenSettings()
    elseif cmd == "gear" or cmd == "장비" or cmd == "pole" then
        ns:EquipBestPole()
    elseif cmd == "hud" then
        Toggle("showHUD", L["세션 창"])
    elseif cmd == "session" or cmd == "세션" then
        ns:ResetSession()
        ns:Print(L["새 낚시 세션을 시작했어요."])
    elseif cmd == "reset" or cmd == "초기화" then
        local mapID = C_Map.GetBestMapForUnit("player")
        if arg == "all" or arg == "전체" then
            wipe(ns.db.spots)
            ns:Print(L["모든 낚시 기록을 지웠습니다."])
        elseif mapID then
            ns.db.spots[mapID] = nil
            ns:Print(L["현재 지역 낚시 기록을 지웠습니다."])
        end
        ns:Fire("AM_DATA_CHANGED")
    else
        ns:Print(L["명령어:"])
        print(L["  /sf — 낚시 기록 창 열기/닫기"])
        print(L["  /sf config — 설정 열기 (게임 설정 > 애드온)"])
        print(L["  /sf onebutton — 원버튼 낚시 켜기/끄기"])
        print(L["  /sf key F — 원버튼 키 변경 (기본 SPACE)"])
        print(L["  /sf lure — 자동 미끼 켜기/끄기"])
        print(L["  /sf pins — 세계지도 핀 켜기/끄기"])
        print(L["  /sf pole — 가장 좋은 낚싯대 착용 / 평소 무기로"])
        print(L["  /sf hud — 세션 창 켜기/끄기"])
        print(L["  /sf session — 새 세션 시작"])
        print(L["  /sf reset — 현재 지역 지점 기록 삭제 (/sf reset all: 전체)"])
        print(L["  /sf lang en — 애드온 언어 변경 (auto, ko, en, tw, de, fr, es)"])
        print(L["  /sf donate — 후원 링크"])
    end
end
