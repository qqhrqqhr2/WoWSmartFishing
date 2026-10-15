local ADDON, ns = ...
local L = ns.L

-- 같은 낚시 지점으로 묶는 거리 (지도 좌표 0~1 기준)
local MERGE_RADIUS = 0.015
-- 마지막으로 던진 뒤 이 시간이 지나면 새 세션
local RECENT_MAX = 100

local lastLootTime = 0
local pendingCast      -- 던졌는데 아직 결과가 없는 낚시 (번호)
local castSerial = 0

-- 저장 구조 준비 ----------------------------------------------------------------
ns:On("AM_DB_READY", function()
    local db = ns.db
    db.journal = db.journal or {}   -- [itemID] = { n, first, firstMap, lastMap, last }
    db.recent = db.recent or {}     -- 최근 낚은 기록 (최신이 앞)
    db.totals = db.totals or { casts = 0, catches = 0, missed = 0 }
    db.session = db.session or nil
end)

local function NewSession()
    local s = { start = time(), last = time(), casts = 0, catches = 0, missed = 0, fish = {} }
    ns.db.session = s
    return s
end

function ns:Session()
    local s = ns.db and ns.db.session
    if not s then return nil end
    if time() - (s.last or 0) > (ns.settings.sessionIdle or 15) * 60 then return nil end
    return s
end

function ns:EndSession()
    ns.db.session = nil
    ns:Fire("AM_DATA_CHANGED")
end

function ns:ResetSession()
    NewSession()
    ns:Fire("AM_DATA_CHANGED")
end

local function ActiveSession()
    return ns:Session() or NewSession()
end

-- 지점 기록 ---------------------------------------------------------------------
local function FindSpot(spots, x, y)
    local best, bestDist
    for _, s in ipairs(spots) do
        local dx, dy = s.x - x, s.y - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d <= MERGE_RADIUS and (not bestDist or d < bestDist) then
            best, bestDist = s, d
        end
    end
    return best
end

function ns:AddCatch(mapID, x, y, items)
    local db = ns.db
    local spots = db.spots[mapID]
    if not spots then
        spots = {}
        db.spots[mapID] = spots
    end

    local spot = FindSpot(spots, x, y)
    if not spot then
        spot = { x = x, y = y, n = 0, fish = {} }
        table.insert(spots, spot)
    end
    spot.x = (spot.x * spot.n + x) / (spot.n + 1)
    spot.y = (spot.y * spot.n + y) / (spot.n + 1)
    spot.n = spot.n + 1
    spot.last = time()
    local sub = ns.Str(ns.Safe(GetSubZoneText))
    if sub and sub ~= "" then spot.sub = sub end

    local session = ActiveSession()
    session.last = time()
    session.catches = session.catches + 1
    db.totals.catches = db.totals.catches + 1

    local now = time()
    for itemID, qty in pairs(items) do
        spot.fish[itemID] = (spot.fish[itemID] or 0) + qty
        session.fish[itemID] = (session.fish[itemID] or 0) + qty

        local j = db.journal[itemID]
        if not j then
            j = { n = 0, first = now, firstMap = mapID }
            db.journal[itemID] = j
            ns:Fire("AM_NEW_FISH", itemID)
        end
        j.n = j.n + qty
        j.last = now
        j.lastMap = mapID

        table.insert(db.recent, 1, { id = itemID, q = qty, t = now, m = mapID, x = x, y = y, sub = spot.sub })
    end
    while #db.recent > RECENT_MAX do table.remove(db.recent) end

    ns:Fire("AM_CATCH", mapID, x, y, items)
    ns:Fire("AM_DATA_CHANGED")
end

-- 던지기 / 놓침 추적 --------------------------------------------------------------
ns:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if ns.Str(unit) ~= "player" or not ns.db or not ns.IsFishingSpell(spellID) then return end
    local session = ActiveSession()
    session.casts = session.casts + 1
    session.last = time()
    ns.db.totals.casts = ns.db.totals.casts + 1
    castSerial = castSerial + 1
    pendingCast = castSerial
    ns:Fire("AM_DATA_CHANGED")
end)

ns:On("UNIT_SPELLCAST_CHANNEL_STOP", function(unit)
    if ns.Str(unit) ~= "player" or not pendingCast then return end
    local serial = pendingCast
    -- 채널이 끝나고 잠시 뒤에도 전리품이 없으면 놓친 것으로 봄
    C_Timer.After(1.2, function()
        if pendingCast ~= serial then return end
        pendingCast = nil
        local session = ns:Session()
        if session then session.missed = session.missed + 1 end
        ns.db.totals.missed = ns.db.totals.missed + 1
        ns:Fire("AM_DATA_CHANGED")
    end)
end)

ns:On("LOOT_READY", function()
    if not ns.db or not ns.Safe(IsFishingLoot) then return end

    -- LOOT_READY는 한 번 낚을 때 여러 번 올 수 있음
    local now = GetTime()
    if now - lastLootTime < 1.5 then return end

    local items, any = {}, false
    for slot = 1, (ns.Num(ns.Safe(GetNumLootItems)) or 0) do
        local link = ns.Str(ns.Safe(GetLootSlotLink, slot))
        if link then
            local itemID = ns.Num(ns.Safe(C_Item.GetItemInfoInstant, link))
            local _, _, quantity = ns.Safe(GetLootSlotInfo, slot)
            quantity = ns.Num(quantity)
            if itemID then
                items[itemID] = (items[itemID] or 0) + (quantity or 1)
                any = true
            end
        end
    end
    if not any then return end

    pendingCast = nil
    lastLootTime = now

    local mapID = ns.Num(ns.Safe(C_Map.GetBestMapForUnit, "player"))
    local pos = mapID and ns.Safe(C_Map.GetPlayerMapPosition, mapID, "player")
    local x, y
    if pos then
        local px, py = ns.Safe(pos.GetXY, pos)
        x, y = ns.Num(px), ns.Num(py)
    end
    if not x or (x == 0 and y == 0) then
        -- 위치를 못 얻는 곳(인스턴스 등): 지도 없이 기록만
        mapID, x, y = mapID or 0, 0, 0
    end
    ns:AddCatch(mapID, x, y, items)
end)

-- 자동 획득: 기록이 끝난 뒤(위 핸들러 다음) 전리품을 모두 가져감
ns:On("LOOT_READY", function(isAutoLoot)
    if not ns.settings or not ns.settings.autoLoot or isAutoLoot then return end
    if not ns.Safe(IsFishingLoot) then return end
    for slot = (ns.Num(ns.Safe(GetNumLootItems)) or 0), 1, -1 do
        LootSlot(slot)
    end
end)

-- 통계 도우미 -----------------------------------------------------------------
function ns:SpotTotal(spot)
    local total = 0
    for _, c in pairs(spot.fish) do total = total + c end
    return total
end

function ns:TopFish(spot)
    local bestID, bestCount = nil, 0
    for id, c in pairs(spot.fish) do
        if c > bestCount then bestID, bestCount = id, c end
    end
    return bestID, bestCount
end

function ns:SortedFish(fishTable)
    local list = {}
    for id, c in pairs(fishTable) do
        table.insert(list, { id = id, count = c })
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
end

function ns:FormatDuration(sec)
    sec = math.max(0, math.floor(sec))
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

function ns:MapName(mapID)
    local info = mapID and mapID ~= 0 and C_Map.GetMapInfo(mapID)
    return info and info.name or L["알 수 없는 곳"]
end

-- 상위 지도(대륙 등) 관계 캐시
local ancestorCache = {}
local function IsAncestor(childID, ancestorID)
    local key = childID .. ":" .. ancestorID
    if ancestorCache[key] ~= nil then return ancestorCache[key] end
    local result = false
    local info = C_Map.GetMapInfo(childID)
    local guard = 0
    while info and info.parentMapID and info.parentMapID ~= 0 and guard < 10 do
        if info.parentMapID == ancestorID then result = true break end
        info = C_Map.GetMapInfo(info.parentMapID)
        guard = guard + 1
    end
    ancestorCache[key] = result
    return result
end

-- zoneID 지도의 사각형이 mapID 지도에서 차지하는 범위 (하위 지역일 때만)
local rectCache = {}
function ns:ChildRect(zoneID, mapID)
    if not zoneID or not mapID then return nil end -- 지도 번호를 못 얻었을 때
    if zoneID == mapID or not IsAncestor(zoneID, mapID) then return nil end
    local key = zoneID .. ":" .. mapID
    local r = rectCache[key]
    if r == nil then
        local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(zoneID, mapID)
        if minX and maxX and maxX > minX then
            r = { minX, maxX, minY, maxY }
        else
            r = false
        end
        rectCache[key] = r
    end
    return r or nil
end

-- zoneID 지도 좌표(0~1)를 mapID 지도 좌표로. 표시할 수 없으면 nil
function ns:Project(zoneID, mapID, x, y)
    if zoneID == mapID then return x, y, false end
    local r = ns:ChildRect(zoneID, mapID)
    if not r then return nil end
    return r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3]), true
end

-- mapID 지도에 표시할 지점 목록 (하위 지역 지점은 좌표 변환)
-- source: 지점 표 (기본: 내 기록)
function ns:CollectSpots(mapID, source)
    local out = {}
    source = source or (ns.db and ns.db.spots)
    if not mapID or not source then return out end
    for zoneID, spots in pairs(source) do
        if zoneID ~= 0 then
            for _, s in ipairs(spots) do
                local x, y, child = ns:Project(zoneID, mapID, s.x, s.y)
                if x then
                    out[#out + 1] = { spot = s, x = x, y = y, mapID = zoneID, child = child }
                end
            end
        end
    end
    return out
end

-- mapID 지도(하위 지역 포함)의 내 기록 물고기 합계
function ns:FishOnMap(mapID)
    local fish, total, entries = {}, 0, ns:CollectSpots(mapID)
    for _, e in ipairs(entries) do
        for id, c in pairs(e.spot.fish) do
            fish[id] = (fish[id] or 0) + c
            total = total + c
        end
    end
    return fish, total, #entries
end
