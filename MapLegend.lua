local ADDON, ns = ...
local L = ns.L
local S = ns.Style

-- 세계지도 위 "일반 낚시" 패널 ----------------------------------------------------
-- 지역 지도: 그 지역(지금 있는 곳이면 세부 지역)에서 일반 낚시로 잡히는 물고기와 확률
-- 대륙 지도 + 물고기 선택: 그 물고기가 잘 잡히는 지역 순위
local ROWS = 8
local WIDTH = 232
local legend

local function CreateRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(20)
    r:SetPoint("TOPLEFT", 6, -44 - (i - 1) * 20)
    r:SetPoint("RIGHT", -6, 0)

    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 4, 0)
    S:Round(r, r.icon)

    r.pct = S:Text(r, 11, S.muted)
    r.pct:SetPoint("RIGHT", -4, 0)
    r.pct:SetJustifyH("RIGHT")

    r.name = S:Text(r, 11)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 7, 0)
    r.name:SetPoint("RIGHT", r.pct, "LEFT", -6, 0)

    r:SetScript("OnEnter", function(self)
        if not self.selected then self.bg:SetColorTexture(unpack(S.hover)) end
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.hint or "", unpack(S.accent))
            GameTooltip:AddLine("WoW Smart Fishing", unpack(S.muted))
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    return r
end

local function CreateLegend(anchor)
    local container = WorldMapFrame:GetCanvasContainer()
    local f = CreateFrame("Frame", "WoWSmartFishingMapLegend", container, "BackdropTemplate")
    S:Panel(f)
    f:SetWidth(WIDTH)
    f:SetFrameLevel(anchor:GetFrameLevel())
    f:EnableMouse(true)

    -- 머리말 전체를 누르면 접기/펴기
    f.header = CreateFrame("Button", nil, f)
    f.header:SetPoint("TOPLEFT")
    f.header:SetPoint("TOPRIGHT")
    f.header:SetHeight(28)
    f.header:SetScript("OnClick", function()
        ns.settings.legendCollapsed = not ns.settings.legendCollapsed
        ns:UpdateMapLegend()
    end)
    f.header:SetScript("OnEnter", function(self)
        f.toggle:SetTextColor(unpack(S.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.settings.legendCollapsed and L["눌러서 펼치기"] or L["눌러서 접기"], 1, 1, 1)
        GameTooltip:Show()
    end)
    f.header:SetScript("OnLeave", function()
        f.toggle:SetTextColor(unpack(S.muted))
        GameTooltip:Hide()
    end)

    f.toggle = S:Text(f.header, 14, S.muted)
    f.toggle:SetPoint("TOPRIGHT", -10, -6)
    f.toggle:SetJustifyH("RIGHT")

    f.title = S:Text(f, 12)
    f.title:SetPoint("TOPLEFT", 10, -9)
    f.title:SetPoint("RIGHT", -28, 0)

    f.sub = S:Text(f, 10, S.muted)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.sub:SetPoint("RIGHT", -10, 0)

    f.line = S:Line(f)
    f.line:SetPoint("TOPLEFT", 0, -40)
    f.line:SetPoint("TOPRIGHT", 0, -40)

    f.rows = {}
    for i = 1, ROWS do f.rows[i] = CreateRow(f, i) end

    f.brand = f:CreateTexture(nil, "ARTWORK")
    f.brand:SetSize(12, 12)
    f.brand:SetPoint("BOTTOMRIGHT", -8, 6)
    f.brand:SetTexture(S.ICON)
    f.brand:SetAlpha(0.7)
    S:Round(f, f.brand)

    f.foot = S:Text(f, 9, S.muted)
    f.foot:SetPoint("BOTTOMLEFT", 10, 7)
    f.foot:SetPoint("RIGHT", f.brand, "LEFT", -6, 0)
    return f
end

local function SetRow(r, d)
    r.itemID, r.onClick, r.hint = d.itemID, d.onClick, d.hint
    r.icon:SetTexture(d.icon)
    r.name:SetText(d.name)
    r.pct:SetText(d.pct)
    r.selected = d.selected
    if d.selected then
        r.bg:SetColorTexture(S.accent[1], S.accent[2], S.accent[3], 0.12)
        r.pct:SetTextColor(unpack(S.accent))
    else
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.pct:SetTextColor(unpack(S.muted))
    end
    r:Show()
end

local function Pct(p)
    if p >= 10 then return string.format("%.0f%%", p) end
    return string.format("%.1f%%", p)
end

function ns:UpdateMapLegend()
    if not legend then return end
    local set = ns.settings
    if not set.showLegend or not set.showPins or not set.mapButton or not WorldMapFrame:IsShown() then
        legend:Hide()
        return
    end

    local mapID = WorldMapFrame:GetMapID()
    local filter = set.filterFish
    local data = {}

    if ns.Data.zones[mapID] then
        -- 지역 지도: 일반 낚시 어종
        local fish, skill, sub
        if mapID == C_Map.GetBestMapForUnit("player") then
            fish, skill, sub = ns:ExpectedHere(mapID)
        else
            fish, skill = ns:ExpectedZone(mapID)
        end
        legend.title:SetText(L["일반 낚시 · %s"]:format(sub or ns:MapName(mapID)))
        local info = {}
        if skill then info[#info + 1] = L["권장 숙련 %d"]:format(skill) end
        info[#info + 1] = sub and L["지금 있는 세부 지역 기준"] or L["지역 전체 기준"]
        legend.sub:SetText(table.concat(info, " · "))

        local list = {}
        for id, p in pairs(fish or {}) do list[#list + 1] = { id = id, p = p } end
        table.sort(list, function(a, b) return a.p > b.p end)
        for i = 1, math.min(ROWS, #list) do
            local e = list[i]
            data[i] = {
                itemID = e.id, icon = ns:ItemIcon(e.id), name = ns:ItemName(e.id), pct = Pct(e.p),
                selected = filter == e.id,
                hint = L["클릭: 지도에서 이 물고기 기록·물고기 떼만 보기"],
                onClick = function() ns:SetFishFilter(filter == e.id and nil or e.id) end,
            }
        end
        legend.foot:SetText(#list > ROWS and string.format(L["외 %d가지 · 확률은 예상치"], #list - ROWS) or L["확률은 예상치예요"])
    elseif filter then
        -- 대륙 지도 + 물고기 선택: 잘 잡히는 지역 순위
        legend.title:SetText(L["%s 잡히는 곳"]:format(ns:ItemName(filter, true)))
        legend.sub:SetText(L["일반 낚시 확률이 높은 지역"])
        local n = 0
        for _, z in ipairs(ns:ZonesForFish(filter)) do
            if ns:ChildRect(z.mapID, mapID) then
                n = n + 1
                if n <= ROWS then
                    local zd = ns.Data.zones[z.mapID]
                    data[n] = {
                        icon = ns:ItemIcon(filter),
                        name = ns:MapName(z.mapID) .. ((zd and zd.s) and ("  |cff8c94a3" .. zd.s .. "|r") or ""),
                        pct = Pct(z.pct),
                        onClick = function() ns:GoToMap(z.mapID) end,
                    }
                end
            end
        end
        legend.foot:SetText(n == 0 and L["이 대륙에는 기본 데이터가 없어요"] or L["지역을 누르면 그 지도로 이동 · 회색 숫자는 권장 숙련"])
    else
        -- 대륙 지도 + 선택 없음: 이 대륙에서 잡히는 물고기 (지역 최고 확률 순)
        local list = {}
        for id, p in pairs(ns:ExpectedOnMap(mapID)) do
            if p >= 1 then list[#list + 1] = { id = id, p = p } end
        end
        if #list == 0 then
            legend:Hide()
            return
        end
        table.sort(list, function(a, b) return a.p > b.p end)
        legend.title:SetText(L["%s의 물고기"]:format(ns:MapName(mapID)))
        legend.sub:SetText(L["물고기를 누르면 잡히는 지역이 보여요"])
        for i = 1, math.min(ROWS, #list) do
            local e = list[i]
            data[i] = {
                itemID = e.id, icon = ns:ItemIcon(e.id), name = ns:ItemName(e.id),
                pct = L["최대 %s"]:format(Pct(e.p)),
                hint = L["클릭: 이 물고기가 잡히는 지역 보기"],
                onClick = function() ns:SetFishFilter(e.id) end,
            }
        end
        legend.foot:SetText(#list > ROWS and L["외 %d가지 · 지도 버튼에서 전체 보기"]:format(#list - ROWS) or L["확률은 예상치예요"])
    end

    local collapsed = set.legendCollapsed
    legend.toggle:SetText(collapsed and "+" or "-")
    legend.sub:SetShown(not collapsed)
    legend.line:SetShown(not collapsed)
    legend.foot:SetShown(not collapsed)
    for i, r in ipairs(legend.rows) do
        if data[i] and not collapsed then SetRow(r, data[i]) else r:Hide() end
    end
    if #data == 0 then
        legend.foot:SetText(L["이 지역은 일반 낚시 정보가 없어요"])
    end
    if collapsed then
        legend:SetHeight(28)
    else
        legend:SetHeight(44 + math.max(1, #data) * 20 + 24)
    end
    legend:Show()
end

-- 지도 버튼 옆에 붙임 (버튼이 아래쪽이면 위로, 위쪽이면 아래로)
function ns:PlaceMapLegend(button)
    if not legend then return end
    local pos = ns.settings.mapButtonPos or { 0.5, 0.05 }
    legend:ClearAllPoints()
    if pos[2] < 0.5 then
        legend:SetPoint("BOTTOM", button, "TOP", 0, 6)
    else
        legend:SetPoint("TOP", button, "BOTTOM", 0, -6)
    end
end

function ns:CreateMapLegend(button)
    legend = CreateLegend(button)
    ns:PlaceMapLegend(button)
end

local function Update() ns:UpdateMapLegend() end
local KEYS = { showLegend = true, showPins = true, mapButton = true, filterFish = true }
ns:On("AM_SETTINGS_CHANGED", function(key) if KEYS[key] then Update() end end)
ns:On("ZONE_CHANGED", Update)
ns:On("ZONE_CHANGED_NEW_AREA", Update)

