local ADDON, ns = ...
local L = ns.L
local S = ns.Style

local button

-- 특정 물고기 지점만 지도에 표시 (nil = 전체)
function ns:SetFishFilter(itemID)
    ns.settings.filterFish = itemID
    ns:Fire("AM_SETTINGS_CHANGED", "filterFish")
end

function ns:ShowFishOnMap(itemID, mapID)
    ns:SetFishFilter(itemID)
    if not ns.settings.showPins then
        ns.settings.showPins = true
        ns:Fire("AM_SETTINGS_CHANGED", "showPins")
    end
    if not WorldMapFrame:IsShown() then
        if OpenWorldMap then OpenWorldMap(mapID) else ToggleWorldMap() end
    end
    if mapID then WorldMapFrame:SetMapID(mapID) end
end

local function CurrentMapID()
    return WorldMapFrame:GetMapID()
end

local function UpdateLabel()
    if not button then return end
    local filter = ns.settings.filterFish
    if not ns.settings.showPins then
        button.icon:SetTexture(S.ICON_INNER)
        button.label:SetText(L["낚시 지점 보기"])
        button.label:SetTextColor(unpack(S.muted))
    elseif filter then
        button.icon:SetTexture(ns:ItemIcon(filter))
        button.label:SetText(ns:ItemName(filter, true))
        local mapID = CurrentMapID()
        local here = ns:FishOnMap(mapID)[filter] or ns:ExpectedOnMap(mapID)[filter]
        button.label:SetTextColor(unpack(here and S.text or S.muted))
    else
        button.icon:SetTexture(S.ICON_INNER)
        button.label:SetText(L["모든 물고기"])
        button.label:SetTextColor(unpack(S.text))
    end
    button:SetWidth(math.min(220, button.label:GetStringWidth() + 38))
    button.clear:SetShown(filter ~= nil and ns.settings.showPins)
end
ns.UpdateMapButton = UpdateLabel

local function OpenMenu(owner)
    if not ns.settings.showPins then
        ns.settings.showPins = true
        ns:Fire("AM_SETTINGS_CHANGED", "showPins")
        return
    end
    local mapID = CurrentMapID()
    local list = ns:FishMenuList(mapID)

    if not MenuUtil or not MenuUtil.CreateContextMenu then
        -- 메뉴 API가 없으면 클릭할 때마다 다음 물고기로 넘김
        local cur, nextID = ns.settings.filterFish, nil
        for i, e in ipairs(list) do
            if e.id == cur then nextID = list[i + 1] and list[i + 1].id break end
        end
        if not cur and list[1] then nextID = list[1].id end
        ns:SetFishFilter(nextID)
        return
    end

    local ICON = "|T%s:16:16:0:0:64:64:5:59:5:59|t "
    local function IsSelected(id) return ns.settings.filterFish == id end
    local function Select(id) ns:SetFishFilter(id) end

    MenuUtil.CreateContextMenu(owner, function(_, root)
        if root.SetScrollMode then root:SetScrollMode(460) end
        root:CreateRadio(L["모든 물고기"], function() return ns.settings.filterFish == nil end,
            function() ns:SetFishFilter(nil) end)

        -- 이 지도의 물고기
        root:CreateTitle(L["이 지도의 물고기"])
        if #list == 0 then
            root:CreateTitle(L["|cff8c94a3이 지도에는 낚시 정보가 없어요|r"])
        end
        for _, e in ipairs(list) do
            local info = {}
            if e.pct then info[#info + 1] = string.format("%.0f%%", e.pct) end
            if e.count > 0 then info[#info + 1] = L["내 기록 %d"]:format(e.count) end
            local text = ICON:format(ns:ItemIcon(e.id)) .. ns:ItemName(e.id) .. "  |cff8c94a3" .. table.concat(info, " · ") .. "|r"
            root:CreateRadio(text, IsSelected, Select, e.id)
        end

        -- 물고기 떼 (종류별)
        local pools = ns:PoolTypesOnMap(mapID)
        if #pools > 0 then
            root:CreateDivider()
            root:CreateTitle(L["물고기 떼"])
            for _, p in ipairs(pools) do
                local text = ICON:format(ns:ItemIcon(p.type.fish)) .. "|cff6fa3ff" .. ns:PoolLabel(p.type) .. "|r  |cff8c94a3" .. L["%d곳"]:format(p.count) .. "|r"
                root:CreateRadio(text, IsSelected, Select, p.type.fish)
            end
        end

        -- 다른 대륙 물고기: 고르면 그 대륙 지도로 이동
        local here = ns:ContinentOf(mapID)
        local others = {}
        for _, c in ipairs(ns:FishByContinent()) do
            if c.continent ~= here and c.continent ~= mapID then others[#others + 1] = c end
        end
        if #others > 0 then
            root:CreateDivider()
            for _, c in ipairs(others) do
                local sub = root:CreateButton(L["다른 대륙: %s"]:format(ns:MapName(c.continent)))
                if sub.SetScrollMode then sub:SetScrollMode(460) end
                for _, e in ipairs(c.fish) do
                    local text = ICON:format(ns:ItemIcon(e.id)) .. ns:ItemName(e.id) .. "  |cff8c94a3" .. string.format("%.0f%%", e.pct) .. "|r"
                    sub:CreateRadio(text, IsSelected, function(id)
                        ns:SetFishFilter(id)
                        WorldMapFrame:SetMapID(c.continent)
                    end, e.id)
                end
            end
        end

        root:CreateDivider()
        root:CreateButton(L["|cff8c94a3지도 핀 숨기기|r"], function()
            ns.settings.showPins = false
            ns:Fire("AM_SETTINGS_CHANGED", "showPins")
        end)
    end)
end

-- 마우스 휠로 이 지도의 물고기를 차례로 고르기
local function CycleFish(delta)
    local list = ns:FishMenuList(CurrentMapID())
    if #list == 0 then return end
    local cur, idx = ns.settings.filterFish, 0
    for i, e in ipairs(list) do if e.id == cur then idx = i break end end
    idx = idx - delta
    if idx < 1 then idx = #list elseif idx > #list then idx = 1 end
    ns:SetFishFilter(list[idx].id)
end

-- 지도 메뉴용 물고기 목록: 기본 데이터 예상 확률 + 내 기록 (확률 높은 순)
function ns:FishMenuList(mapID)
    local expected = ns:ExpectedOnMap(mapID)
    local own = ns:FishOnMap(mapID)
    local seen, list = {}, {}
    for id, p in pairs(expected) do
        if p >= 1 or own[id] then
            seen[id] = true
            list[#list + 1] = { id = id, pct = p, count = own[id] or 0 }
        end
    end
    for id, c in pairs(own) do
        if not seen[id] then list[#list + 1] = { id = id, count = c } end
    end
    table.sort(list, function(a, b)
        local pa, pb = a.pct or -1, b.pct or -1
        if pa ~= pb then return pa > pb end
        return a.count > b.count
    end)
    return list
end

local function CreateButton()
    local container = WorldMapFrame:GetCanvasContainer()
    local b = CreateFrame("Button", "WoWSmartFishingMapButton", container, "BackdropTemplate")
    S:Panel(b)
    b:SetHeight(26)
    b:SetFrameLevel(container:GetFrameLevel() + 500)
    b:RegisterForDrag("LeftButton")
    b:SetClampedToScreen(true)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 5, 0)
    S:Round(b, b.icon)

    b.label = S:Text(b, 12)
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)

    -- 선택 해제(×) 버튼: 물고기를 골랐을 때만
    b.clear = CreateFrame("Button", nil, b, "BackdropTemplate")
    S:Panel(b.clear)
    b.clear:SetSize(22, 26)
    b.clear:SetPoint("LEFT", b, "RIGHT", 4, 0)
    b.clear.t = S:Text(b.clear, 14, S.muted)
    b.clear.t:SetPoint("CENTER", 0, 1)
    b.clear.t:SetText("×")
    b.clear:SetScript("OnEnter", function(self)
        self.t:SetTextColor(unpack(S.text))
        self:SetBackdropBorderColor(unpack(S.accent))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["선택 해제 (모든 물고기 보기)"], 1, 1, 1)
        GameTooltip:Show()
    end)
    b.clear:SetScript("OnLeave", function(self)
        self.t:SetTextColor(unpack(S.muted))
        self:SetBackdropBorderColor(unpack(S.border))
        GameTooltip:Hide()
    end)
    b.clear:SetScript("OnClick", function() ns:SetFishFilter(nil) end)
    b.clear:Hide()

    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(_, delta) CycleFish(delta) end)

    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(S.accent))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("WoW Smart Fishing", 0.27, 0.78, 0.88)
        GameTooltip:AddLine(L["물고기별 낚시 지점"], 1, 1, 1)
        GameTooltip:AddLine(L["왼쪽 클릭: 물고기 고르기"], unpack(S.muted))
        GameTooltip:AddLine(L["오른쪽 클릭: 목록 접기/펴기"], unpack(S.muted))
        GameTooltip:AddLine(L["마우스 휠: 다음 물고기"], unpack(S.muted))
        GameTooltip:AddLine(L["끌기: 위치 옮기기"], unpack(S.muted))
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(S.border))
        GameTooltip:Hide()
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            ns.settings.legendCollapsed = not ns.settings.legendCollapsed
            ns:UpdateMapLegend()
        else
            OpenMenu(self)
        end
    end)

    -- 지도 안에서 끌어 옮기기 (위치는 지도 크기에 대한 비율로 저장 → 지도 크기를 바꿔도 유지)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function(btn)
            local scale = container:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            local left, bottom, w, h = container:GetRect()
            if not w or w == 0 or h == 0 then return end
            local fx = math.min(0.98, math.max(0.02, (cx - left) / w))
            local fy = math.min(0.97, math.max(0.03, (cy - bottom) / h))
            ns.settings.mapButtonPos = { fx, fy }
            ns.PlaceMapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    container:HookScript("OnSizeChanged", function() ns.PlaceMapButton() end)
    return b
end

-- 기본 위치: 지도 아래쪽 가운데 (왼쪽 위는 다른 애드온 버튼이 많음)
local DEFAULT_POS = { 0.5, 0.05 }

function ns.PlaceMapButton()
    if not button then return end
    local container = WorldMapFrame:GetCanvasContainer()
    local pos = ns.settings.mapButtonPos or DEFAULT_POS
    local w, h = container:GetSize()
    button:ClearAllPoints()
    button:SetPoint("CENTER", container, "BOTTOMLEFT", pos[1] * w, pos[2] * h)
    ns:PlaceMapLegend(button)
end

function ns:ResetMapButton()
    ns.settings.mapButtonPos = nil
    ns.PlaceMapButton()
    ns:Print(L["지도 버튼 위치를 처음으로 되돌렸어요."])
end

ns:On("AM_DB_READY", function()
    button = CreateButton()
    ns:CreateMapLegend(button)
    button:SetShown(ns.settings.mapButton)
    ns.PlaceMapButton()
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        UpdateLabel()
        ns:UpdateMapLegend()
    end)
    WorldMapFrame:HookScript("OnShow", function()
        ns.PlaceMapButton()
        UpdateLabel()
        ns:UpdateMapLegend()
    end)
    UpdateLabel()
end)
ns:On("AM_SETTINGS_CHANGED", function(key)
    if key == "filterFish" or key == "showPins" then UpdateLabel() end
    if key == "mapButton" and button then button:SetShown(ns.settings.mapButton) end
end)
ns:On("AM_DATA_CHANGED", UpdateLabel)
local pending = false
ns:On("GET_ITEM_INFO_RECEIVED", function()
    if pending or not WorldMapFrame:IsShown() then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        UpdateLabel()
        ns:UpdateMapLegend()
    end)
end)
