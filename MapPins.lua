local ADDON, ns = ...
local L = ns.L
local S = ns.Style

local TEMPLATE = "WoWSmartFishingPinTemplate"
local MAX_TOOLTIP_FISH = 8

-- 핀 종류별 모양 ------------------------------------------------------------------
-- own: 내가 낚은 곳 / shared: 다른 플레이어가 공유한 곳 / pool: 물고기 떼 출현 지점 / zone: 선택한 물고기가 나오는 지역
local RING = {
    own    = { 0.07, 0.08, 0.10, 0.95 },
    shared = { 0.80, 0.62, 0.25, 0.95 },
    pool   = { 0.30, 0.58, 1.00, 1 },
    zone   = { 0.27, 0.78, 0.88, 0.95 },
}
local SIZE = { own = 20, shared = 18, pool = 18, zone = 26 }

-- 핀 --------------------------------------------------------------------------
WoWSmartFishingPinMixin = CreateFromMixins(MapCanvasPinMixin)

function WoWSmartFishingPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1.0, 1.3)
    S:Round(self, self.Ring)
    S:Round(self, self.Icon)

    self.Label = self:CreateFontString(nil, "OVERLAY")
    self.Label:SetFont(S.font, 11, "OUTLINE")
    self.Label:SetPoint("TOP", self, "BOTTOM", 0, -1)
end

function WoWSmartFishingPinMixin:RingColor(highlight)
    local c = highlight and S.accent or RING[self.entry.kind or "own"]
    self.Ring:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

function WoWSmartFishingPinMixin:OnAcquired(entry)
    self.entry = entry
    local kind = entry.kind or "own"
    local filter = ns.settings.filterFish
    local iconID
    self:SetAlpha(1)
    self.Label:Hide()

    if kind == "pool" then
        iconID = entry.poolType.fish
        self:SetAlpha(0.9)
    elseif kind == "zone" then
        iconID = filter
        self.Label:SetText(string.format("%.0f%%", entry.pct))
        self.Label:SetTextColor(unpack(S.accent))
        self.Label:Show()
    else
        local spot = entry.spot
        if filter then
            iconID = filter
            local rate = (spot.fish[filter] or 0) / math.max(1, ns:SpotTotal(spot))
            self:SetAlpha(0.55 + 0.45 * rate) -- 잘 잡히는 곳일수록 진하게
        else
            iconID = ns:TopFish(spot)
        end
    end

    self.Icon:SetTexture(iconID and ns:ItemIcon(iconID) or S.ICON_INNER)
    -- 물고기 떼는 테두리를 두껍게 해서 구분
    local inset = (kind == "pool") and 3 or 2
    self.Icon:ClearAllPoints()
    self.Icon:SetPoint("TOPLEFT", inset, -inset)
    self.Icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    local size = SIZE[kind] * (ns.settings.pinScale or 1)
    if entry.child and kind ~= "zone" then size = size * 0.7 end
    self:SetSize(size, size)
    self:RingColor(false)
    self:SetPosition(entry.x, entry.y)
end

local function AddFishLines(fish, total, filter)
    for i, e in ipairs(ns:SortedFish(fish)) do
        if i > MAX_TOOLTIP_FISH then break end
        local left = "|T" .. ns:ItemIcon(e.id) .. ":14:14:0:0:64:64:5:59:5:59|t " .. ns:ItemName(e.id)
        local pct = string.format("%.0f%%", e.count / total * 100)
        if e.id == filter then
            GameTooltip:AddDoubleLine(left, pct, 1, 1, 1, S.accent[1], S.accent[2], S.accent[3])
        else
            GameTooltip:AddDoubleLine(left, pct, 1, 1, 1, 0.7, 0.72, 0.76)
        end
    end
end

function WoWSmartFishingPinMixin:OnMouseEnter()
    local entry = self.entry
    if not entry then return end
    self:RingColor(true)
    local kind = entry.kind or "own"
    local filter = ns.settings.filterFish
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

    if kind == "zone" then
        GameTooltip:AddLine(ns:MapName(entry.mapID), 1, 1, 1)
        GameTooltip:AddLine(string.format(L["%s 예상 확률 %.1f%%"], ns:ItemName(filter), entry.pct), unpack(S.muted))
        if entry.skill then
            GameTooltip:AddLine(L["권장 숙련 %d"]:format(entry.skill), unpack(S.muted))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["클릭하면 이 지역 지도로 이동"], unpack(S.muted))
    elseif kind == "pool" then
        GameTooltip:AddLine(ns:PoolLabel(entry.poolType), 1, 1, 1)
        GameTooltip:AddLine(L["물고기 떼가 나타나는 자리 (기본 데이터)"], unpack(S.muted))
        if entry.child then GameTooltip:AddLine(ns:MapName(entry.mapID), unpack(S.muted)) end
    else
        local spot = entry.spot
        local title = spot.sub
        if entry.child then
            title = ns:MapName(entry.mapID) .. (spot.sub and (" · " .. spot.sub) or "")
        end
        GameTooltip:AddLine(title or L["낚시 지점"], 1, 1, 1)
        if kind == "shared" then
            GameTooltip:AddLine(string.format(L["다른 플레이어 기록 · %d번 낚음"], spot.n), S.accent[1], S.accent[2], S.accent[3])
        else
            GameTooltip:AddLine(string.format(L["내 기록 · %d번 낚음"], spot.n), unpack(S.muted))
        end
        GameTooltip:AddLine(" ")
        AddFishLines(spot.fish, ns:SpotTotal(spot), filter)
        if entry.child then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["클릭하면 이 지역 지도로 이동"], unpack(S.muted))
        end
    end
    -- 어떤 애드온의 아이콘인지 표시
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|T" .. S.ICON .. ":12:12|t WoW Smart Fishing", 0.27, 0.78, 0.88)
    GameTooltip:Show()
end

function WoWSmartFishingPinMixin:OnMouseLeave()
    self:RingColor(false)
    GameTooltip:Hide()
end

-- 지도는 핀을 꺼낼 때마다 SetPassThroughButtons("RightButton")를 불러
-- 핀 위 우클릭이 지도로 넘어가(지도 축소) 하게 한다. 이 함수는 전투 중에
-- 애드온 코드에서 불리면 막히는 보호 함수라 ADDON_ACTION_BLOCKED 오류가 난다.
-- 전투 중에는 건너뛴다 (재사용 핀은 전투 전 설정이 그대로 남아 있음).
function WoWSmartFishingPinMixin:SetPassThroughButtons(...)
    if InCombatLockdown() then return end
    getmetatable(self).__index.SetPassThroughButtons(self, ...)
end

-- 마우스 올리기/떼기/클릭은 지도(MapCanvas)가 직접 연결해서
-- OnMouseEnter / OnMouseLeave / OnMouseClickAction 을 불러줌
function WoWSmartFishingPinMixin:OnMouseClickAction(button)
    if button == "LeftButton" and self.entry and self.entry.child then
        ns:GoToMap(self.entry.mapID)
    end
end

-- 데이터 제공자 -------------------------------------------------------------
local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

local function AddSpots(map, mapID, source, kind, filter)
    for _, entry in ipairs(ns:CollectSpots(mapID, source)) do
        if not filter or entry.spot.fish[filter] then
            entry.kind = kind
            map:AcquirePin(TEMPLATE, entry)
        end
    end
end

function Provider:RefreshAllData()
    self:RemoveAllData()
    local set = ns.settings
    if not set or not set.showPins then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    local filter = set.filterFish

    -- 선택한 물고기가 나오는 지역 (대륙 지도에서 지역마다 확률 표시)
    if filter and set.showExpected then
        for _, z in ipairs(ns:ZonesForFish(filter)) do
            local r = ns:ChildRect(z.mapID, mapID)
            if r and z.pct >= 0.5 then
                local zd = ns.Data.zones[z.mapID]
                map:AcquirePin(TEMPLATE, {
                    kind = "zone", mapID = z.mapID, child = true, pct = z.pct, skill = zd and zd.s,
                    x = (r[1] + r[2]) / 2, y = (r[3] + r[4]) / 2,
                })
            end
        end
    end

    if set.showPools then
        for _, entry in ipairs(ns:PoolsOnMap(mapID, filter)) do
            map:AcquirePin(TEMPLATE, entry)
        end
    end
    if set.showShared and ns.db.shared then
        AddSpots(map, mapID, ns.db.shared, "shared", filter)
    end
    AddSpots(map, mapID, ns.db.spots, "own", filter)
end

function ns:RefreshPins()
    if Provider:GetMap() and WorldMapFrame:IsShown() then
        Provider:RefreshAllData()
    end
end

ns:On("AM_DB_READY", function()
    WorldMapFrame:AddDataProvider(Provider)
end)
ns:On("AM_DATA_CHANGED", function() ns:RefreshPins() end)
local PIN_KEYS = { showPins = true, filterFish = true, pinScale = true, showPools = true, showShared = true, showExpected = true }
ns:On("AM_SETTINGS_CHANGED", function(key)
    if PIN_KEYS[key] then ns:RefreshPins() end
end)
