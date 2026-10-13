local ADDON, ns = ...
local L = ns.L

-- 기본 데이터(Data.lua) 읽기 도우미 ------------------------------------------------
local D = ns.Data

-- 지역 표 → { [itemID] = 확률% }
local function ToMap(f)
    local t = {}
    for i = 1, #f, 2 do t[f[i]] = f[i + 1] end
    return t
end

local zoneCache, subCache = {}, {}

-- 지도(지역) 전체의 예상 어종. 반환: { [itemID] = % }, 권장 숙련
function ns:ExpectedZone(mapID)
    local z = mapID and D.zones[mapID]
    if not z then return nil end
    zoneCache[mapID] = zoneCache[mapID] or ToMap(z.f)
    return zoneCache[mapID], z.s
end

-- 지금 있는 세부 지역 이름으로 세부 지역 표 찾기
local subByName -- [mapID] = { [이름] = areaID }
local function BuildSubIndex()
    subByName = {}
    for areaID, e in pairs(D.subzones) do
        local info = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
        local name = type(info) == "table" and info.name or info
        if name and name ~= "" then
            subByName[e.m] = subByName[e.m] or {}
            subByName[e.m][name] = areaID
        end
    end
end

-- 현재 위치의 세부 지역 예상 어종. 반환: { [itemID] = % }, 권장 숙련, 세부 지역 이름
function ns:ExpectedHere(mapID)
    local sub = ns.Str(ns.Safe(GetSubZoneText))
    if sub and sub ~= "" then
        if not subByName then BuildSubIndex() end
        local areaID = subByName[mapID] and subByName[mapID][sub]
        local e = areaID and D.subzones[areaID]
        if e then
            subCache[areaID] = subCache[areaID] or ToMap(e.f)
            local _, zoneSkill = ns:ExpectedZone(mapID)
            return subCache[areaID], e.s or zoneSkill, sub
        end
    end
    local fish, skill = ns:ExpectedZone(mapID)
    return fish, skill, nil
end

-- 이 물고기가 나오는 지역들. 반환: { { mapID, % }, ... } (세부 지역 포함 최고 확률)
local byFish
function ns:ZonesForFish(itemID)
    if not byFish then
        byFish = {}
        local function add(mapID, f)
            for i = 1, #f, 2 do
                local id, p = f[i], f[i + 1]
                byFish[id] = byFish[id] or {}
                if not byFish[id][mapID] or byFish[id][mapID] < p then byFish[id][mapID] = p end
            end
        end
        for mapID, z in pairs(D.zones) do add(mapID, z.f) end
        for _, e in pairs(D.subzones) do add(e.m, e.f) end
    end
    local out = {}
    for mapID, p in pairs(byFish[itemID] or {}) do out[#out + 1] = { mapID = mapID, pct = p } end
    table.sort(out, function(a, b) return a.pct > b.pct end)
    return out
end

-- 지도(하위 지역 포함)에 나오는 예상 어종 { [itemID] = 최고 % }
function ns:ExpectedOnMap(mapID)
    local out = {}
    local own = ns:ExpectedZone(mapID)
    if own then
        for id, p in pairs(own) do out[id] = p end
        return out
    end
    for zoneID, z in pairs(D.zones) do
        if ns:ChildRect(zoneID, mapID) then
            for i = 1, #z.f, 2 do
                local id, p = z.f[i], z.f[i + 1]
                if not out[id] or out[id] < p then out[id] = p end
            end
        end
    end
    return out
end

-- 물고기 떼 출현 지점 (mapID 지도 기준 좌표)
-- 대륙 지도에서는 filterFish가 있을 때만 (너무 많아서)
function ns:PoolsOnMap(mapID, filterFish)
    local out = {}
    for zoneID, list in pairs(D.pools) do
        local isChild = zoneID ~= mapID
        if not isChild or filterFish then
            for i = 1, #list, 3 do
                local t = D.poolTypes[list[i]]
                if t and (not filterFish or t.fish == filterFish) then
                    local x, y, child = ns:Project(zoneID, mapID, list[i + 1] / 100, list[i + 2] / 100)
                    if x then
                        out[#out + 1] = { kind = "pool", poolType = t, x = x, y = y, mapID = zoneID, child = child }
                    end
                end
            end
        end
    end
    return out
end

-- 물고기 떼 종류 이름
local function KindLabel(kind)
    local t = {
    wreckage = L["떠다니는 잔해"],
    debris = L["떠다니는 부유물"],
    oil = L["기름 웅덩이"],
    water = L["정기의 물 웅덩이"],
    muddy = L["흙탕물"],
    }
    return t[kind]
end
function ns:PoolLabel(t)
    if t.kind ~= "school" and KindLabel(t.kind) then return KindLabel(t.kind) end
    if t.fish then return L["%s 떼"]:format(ns:ItemName(t.fish, true)) end
    return L["물고기 떼"]
end

-- 대륙 찾기 ----------------------------------------------------------------------
local continentCache = {}
function ns:ContinentOf(mapID)
    if not mapID then return nil end
    if continentCache[mapID] ~= nil then return continentCache[mapID] or nil end
    local id, guard, found = mapID, 0, false
    while id and id ~= 0 and guard < 10 do
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent then found = id break end
        id = info.parentMapID
        guard = guard + 1
    end
    continentCache[mapID] = found
    return found or nil
end

-- 대륙별 물고기: { { continent = mapID, fish = { { id, pct }, ... } }, ... }
local byContinent
function ns:FishByContinent()
    if byContinent then return byContinent end
    local tmp = {}
    local function add(mapID, f)
        local c = ns:ContinentOf(mapID)
        if not c then return end
        tmp[c] = tmp[c] or {}
        for i = 1, #f, 2 do
            local id, p = f[i], f[i + 1]
            if p >= 1 and (not tmp[c][id] or tmp[c][id] < p) then tmp[c][id] = p end
        end
    end
    for mapID, z in pairs(D.zones) do add(mapID, z.f) end
    for _, e in pairs(D.subzones) do add(e.m, e.f) end
    byContinent = {}
    for c, fish in pairs(tmp) do
        local list = {}
        for id, p in pairs(fish) do list[#list + 1] = { id = id, pct = p } end
        table.sort(list, function(a, b) return a.pct > b.pct end)
        byContinent[#byContinent + 1] = { continent = c, fish = list }
    end
    table.sort(byContinent, function(a, b) return a.continent < b.continent end)
    return byContinent
end

-- 이 지도(하위 지역 포함)에 있는 물고기 떼 종류: { { type = t, count = n }, ... }
function ns:PoolTypesOnMap(mapID)
    local counts = {}
    for zoneID, list in pairs(D.pools) do
        if zoneID == mapID or ns:ChildRect(zoneID, mapID) then
            for i = 1, #list, 3 do
                local t = list[i]
                counts[t] = (counts[t] or 0) + 1
            end
        end
    end
    local out = {}
    for t, n in pairs(counts) do
        if D.poolTypes[t] and D.poolTypes[t].fish then out[#out + 1] = { type = D.poolTypes[t], count = n } end
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

-- 물고기 떼에서 이 아이템이 나오는 지역들: { { mapID, count }, ... }
local poolsByFish
function ns:PoolZonesForFish(itemID)
    if not poolsByFish then
        poolsByFish = {}
        for zoneID, list in pairs(D.pools) do
            for i = 1, #list, 3 do
                local t = D.poolTypes[list[i]]
                if t and t.fish then
                    poolsByFish[t.fish] = poolsByFish[t.fish] or {}
                    poolsByFish[t.fish][zoneID] = (poolsByFish[t.fish][zoneID] or 0) + 1
                end
            end
        end
    end
    local out = {}
    for mapID, n in pairs(poolsByFish[itemID] or {}) do out[#out + 1] = { mapID = mapID, count = n } end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end
