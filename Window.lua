local ADDON, ns = ...
local L = ns.L
local S = ns.Style

local WIDTH, HEIGHT = 320, 520
local PAD = 14
local function Tabs() return {
    { key = "session", label = L["세션"] },
    { key = "recent",  label = L["기록"] },
    { key = "journal", label = L["도감"] },
    { key = "zone",    label = L["지역"] },
    { key = "options", label = L["설정"] },
} end

local window

local function Ago(t)
    local d = time() - t
    if d < 60 then return L["방금"] end
    if d < 3600 then return L["%d분 전"]:format(math.floor(d / 60)) end
    if d < 86400 then return L["%d시간 전"]:format(math.floor(d / 3600)) end
    return date("%m/%d", t)
end

local function Pct(a, b)
    if not b or b == 0 then return "-" end
    return string.format("%.0f%%", a / b * 100)
end

-- 페이지: 세션 ------------------------------------------------------------------
local function BuildSession(page)
    local labels = { L["시간"], L["던짐"], L["낚음"], L["놓침"], L["성공률"], L["시간당"] }
    local gap = 6
    local w = (WIDTH - PAD * 2 - gap * 2) / 3
    page.stats = {}
    for i, label in ipairs(labels) do
        local tile = S:Stat(page, label)
        tile:SetSize(w, 50)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        tile:SetPoint("TOPLEFT", col * (w + gap), -row * (50 + gap))
        page.stats[i] = tile
    end

    page.skill = S:Text(page, 11, S.muted)
    page.skill:SetPoint("TOPLEFT", 0, -120)
    page.lure = S:Text(page, 11, S.muted)
    page.lure:SetPoint("TOPRIGHT", 0, -120)
    page.lure:SetJustifyH("RIGHT")

    local line = S:Line(page)
    line:SetPoint("TOPLEFT", -PAD, -142)
    line:SetPoint("TOPRIGHT", PAD, -142)

    page.head = S:Text(page, 12)
    page.head:SetPoint("TOPLEFT", 0, -154)
    page.head:SetText(L["이번 세션에 잡은 것"])

    page.reset = S:Button(page, L["새 세션"], function() ns:ResetSession() end)
    page.reset:SetPoint("TOPRIGHT", 0, -149)
    page.reset:SetHeight(22)

    page.list = S:List(page)
    page.list:SetPoint("TOPLEFT", -6, -182)
    page.list:SetPoint("BOTTOMRIGHT", 6, 0)
    page.list:SetEmptyText(L["낚싯대를 들고 낚시를 시작하면\n이번 세션 기록이 여기에 쌓여요."])

    function page:Tick()
        local s = ns:Session()
        local casts, catches, missed = s and s.casts or 0, s and s.catches or 0, s and s.missed or 0
        local dur = s and (math.max(s.last, time()) - s.start) or 0
        if s and time() - s.last > 60 then dur = s.last - s.start end -- 쉬는 동안은 멈춤
        local perHour = dur > 60 and (catches / dur * 3600) or 0
        local v = {
            ns:FormatDuration(dur), casts, catches, missed,
            Pct(catches, casts), dur > 60 and string.format("%.0f", perHour) or "-",
        }
        for i, tile in ipairs(self.stats) do tile.value:SetText(v[i]) end

        local rank, maxRank, mod = ns:FishingSkill()
        if rank then
            local bonus = (mod and mod > 0) and ("  |cff45c7e0+" .. mod .. "|r") or ""
            self.skill:SetText(string.format(L["낚시 숙련 |cffeeeff2%d / %d|r%s"], rank, maxRank, bonus))
        else
            self.skill:SetText("")
        end
        local lure = ns:LureRemaining()
        if lure then
            self.lure:SetText(L["미끼 %s"]:format("|cff45c7e0" .. ns:FormatDuration(lure) .. "|r"))
        else
            self.lure:SetText(ns:HasPole() and L["미끼 없음"] or "")
        end
    end

    function page:Refresh()
        self:Tick()
        local s = ns:Session()
        local data = {}
        if s then
            local list = ns:SortedFish(s.fish)
            local total = 0
            for _, e in ipairs(list) do total = total + e.count end
            for _, e in ipairs(list) do
                data[#data + 1] = {
                    itemID = e.id, icon = ns:ItemIcon(e.id), title = ns:ItemName(e.id),
                    bar = e.count / list[1].count,
                    right = Pct(e.count, total), right2 = L["%d마리"]:format(e.count),
                }
            end
        end
        self.list:SetData(data)
    end
end

-- 페이지: 기록 (내가 낚은 위치) ----------------------------------------------------
local function BuildRecent(page)
    page.head = S:Text(page, 12)
    page.head:SetPoint("TOPLEFT", 0, -2)
    page.head:SetText(L["최근에 낚은 기록"])
    page.info = S:Text(page, 10, S.muted)
    page.info:SetPoint("TOPRIGHT", 0, -4)
    page.info:SetJustifyH("RIGHT")

    page.list = S:List(page)
    page.list:SetPoint("TOPLEFT", -6, -26)
    page.list:SetPoint("BOTTOMRIGHT", 6, 0)
    page.list:SetEmptyText(L["아직 기록이 없어요.\n물고기를 낚으면 시간과 위치가 남아요."])

    local function OnClick(d)
        if d.mapID and d.mapID ~= 0 then ns:ShowFishOnMap(d.itemID, d.mapID) end
    end

    function page:Refresh()
        local data = {}
        for _, r in ipairs(ns.db.recent) do
            local place = ns:MapName(r.m)
            if r.sub then place = place .. " · " .. r.sub end
            data[#data + 1] = {
                itemID = r.id, mapID = r.m, icon = ns:ItemIcon(r.id),
                title = ns:ItemName(r.id) .. ((r.q or 1) > 1 and ("  |cff8c94a3x" .. r.q .. "|r") or ""),
                sub = place,
                right = Ago(r.t),
                right2 = (r.m ~= 0) and string.format("%.0f, %.0f", r.x * 100, r.y * 100) or "",
                hint = (r.m ~= 0) and L["클릭: 지도에서 이 물고기 지점 보기"] or nil,
                onClick = OnClick,
            }
        end
        self.info:SetText(#data > 0 and L["%d개"]:format(#data) or "")
        self.list:SetData(data)
    end
end

-- 페이지: 도감 --------------------------------------------------------------------
local function BuildJournal(page)
    page.head = S:Text(page, 12)
    page.head:SetPoint("TOPLEFT", 0, -2)
    page.head:SetText(L["내 낚시 도감"])
    page.info = S:Text(page, 10, S.muted)
    page.info:SetPoint("TOPRIGHT", 0, -4)
    page.info:SetJustifyH("RIGHT")

    page.totals = S:Text(page, 10, S.muted)
    page.totals:SetPoint("TOPLEFT", 0, -22)

    page.list = S:List(page)
    page.list:SetPoint("TOPLEFT", -6, -42)
    page.list:SetPoint("BOTTOMRIGHT", 6, 0)
    page.list:SetEmptyText(L["처음 낚은 물고기부터 도감에 등록돼요."])

    local function OnClick(d)
        ns:ShowFishOnMap(d.itemID, d.mapID ~= 0 and d.mapID or nil)
    end

    function page:Refresh()
        local data, kinds = {}, 0
        local list = {}
        for id, j in pairs(ns.db.journal) do list[#list + 1] = { id = id, j = j } end
        table.sort(list, function(a, b) return a.j.n > b.j.n end)
        for _, e in ipairs(list) do
            kinds = kinds + 1
            data[#data + 1] = {
                itemID = e.id, mapID = e.j.lastMap, icon = ns:ItemIcon(e.id),
                title = ns:ItemName(e.id),
                sub = L["처음: %s · %s"]:format(ns:MapName(e.j.firstMap), date("%m/%d", e.j.first)),
                right = tostring(e.j.n), right2 = L["마리"],
                hint = L["클릭: 지도에서 이 물고기 지점 보기"],
                onClick = OnClick,
            }
        end
        local t = ns.db.totals
        self.info:SetText(L["%d종"]:format(kinds))
        self.totals:SetText(string.format(L["총 %d마리 · 던짐 %d · 성공률 %s"], t.catches, t.casts, Pct(t.catches, t.casts)))
        self.list:SetData(data)
    end
end

-- 페이지: 지역 --------------------------------------------------------------------
local function BuildZone(page)
    page.head = S:Text(page, 12)
    page.head:SetPoint("TOPLEFT", 0, -2)
    page.info = S:Text(page, 10, S.muted)
    page.info:SetPoint("TOPRIGHT", 0, -4)
    page.info:SetJustifyH("RIGHT")

    page.list = S:List(page)
    page.list:SetPoint("TOPLEFT", -6, -26)
    page.list:SetPoint("BOTTOMRIGHT", 6, 34)
    page.list:SetEmptyText(L["이 지역은 낚시 정보가 없어요.\n낚시를 하면 기록이 쌓여요."])

    page.hint = S:Text(page, 10, S.muted)
    page.hint:SetPoint("BOTTOMLEFT", 0, 6)
    page.hint:SetText(L["확률은 기본 데이터 예상치예요"])

    page.map = S:Button(page, L["지도 열기"], function()
        ns:ShowFishOnMap(ns.settings.filterFish, page.mapID)
    end)
    page.map:SetPoint("BOTTOMRIGHT", 0, 0)

    local function OnClick(d)
        if ns.settings.filterFish == d.itemID then
            ns:SetFishFilter(nil)
        else
            ns:ShowFishOnMap(d.itemID, page.mapID)
        end
    end

    function page:Refresh()
        local mapID = C_Map.GetBestMapForUnit("player")
        self.mapID = mapID
        local expected, skill, sub = ns:ExpectedHere(mapID)
        self.head:SetText(ns:MapName(mapID) .. (sub and ("  |cff8c94a3" .. sub .. "|r") or ""))

        local own, total, spots = ns:FishOnMap(mapID)
        local info = {}
        if skill then
            local rank, _, mod = ns:FishingSkill()
            local mine = rank and (rank + (mod or 0))
            local color = (mine and mine < skill) and "|cffd9a066" or "|cff45c7e0"
            info[#info + 1] = L["권장 숙련 %s"]:format(color .. skill .. "|r")
        end
        if total > 0 then info[#info + 1] = string.format(L["내 기록 %d마리"], total) end
        self.info:SetText(table.concat(info, " · "))

        -- 기본 데이터 예상 확률 + 내 기록
        local list, seen = {}, {}
        for id, p in pairs(expected or {}) do
            seen[id] = true
            list[#list + 1] = { id = id, pct = p, count = own[id] or 0 }
        end
        for id, c in pairs(own) do
            if not seen[id] then list[#list + 1] = { id = id, count = c } end
        end
        table.sort(list, function(a, b)
            local pa, pb = a.pct or -1, b.pct or -1
            if pa ~= pb then return pa > pb end
            return a.count > b.count
        end)
        local top = 0
        for _, e in ipairs(list) do top = math.max(top, e.pct or 0) end

        local data = {}
        for _, e in ipairs(list) do
            data[#data + 1] = {
                itemID = e.id, icon = ns:ItemIcon(e.id), title = ns:ItemName(e.id),
                bar = e.pct and top > 0 and (e.pct / top) or 0,
                right = e.pct and string.format("%.1f%%", e.pct) or "-",
                right2 = e.count > 0 and L["내 기록 %d"]:format(e.count) or "",
                selected = ns.settings.filterFish == e.id,
                hint = L["클릭: 지도에 이 물고기 위치 표시"],
                onClick = OnClick,
            }
        end
        self.list:SetData(data)
    end
end

-- 페이지: 설정 --------------------------------------------------------------------
local function BuildOptions(page)
    local y = 0
    local function Section(title)
        local t = S:Text(page, 10, S.muted)
        t:SetPoint("TOPLEFT", 0, y - 2)
        t:SetText(title)
        y = y - 22
    end
    page.rows = {}
    local function Row(label, key)
        local r = S:SettingRow(page, label, key)
        r:SetPoint("TOPLEFT", 0, y)
        r:SetPoint("TOPRIGHT", 0, y)
        page.rows[#page.rows + 1] = r
        y = y - 28
    end

    Section(L["낚시"])
    Row(L["원버튼 낚시"], "oneButton")
    Row(L["자동 획득"], "autoLoot")
    Row(L["미끼 자동 사용"], "autoLure")

    local keyRow = CreateFrame("Frame", nil, page)
    keyRow:SetPoint("TOPLEFT", 0, y)
    keyRow:SetPoint("TOPRIGHT", 0, y)
    keyRow:SetHeight(26)
    keyRow.label = S:Text(keyRow, 12)
    keyRow.label:SetPoint("LEFT")
    keyRow.label:SetText(L["원버튼 키"])
    keyRow.value = S:Text(keyRow, 12, S.accent)
    keyRow.value:SetPoint("RIGHT")
    keyRow.value:SetJustifyH("RIGHT")
    keyRow.hint = S:Text(keyRow, 10, S.muted)
    keyRow.hint:SetPoint("RIGHT", keyRow.value, "LEFT", -8, 0)
    keyRow.hint:SetText(L["/sf key 로 변경"])
    page.keyRow = keyRow
    y = y - 36

    Section(L["화면"])
    Row(L["지도에 낚시 지점 표시"], "showPins")
    Row(L["낚싯대를 들면 세션 창 표시"], "showHUD")
    y = y - 8

    Section(L["장비"])
    Row(L["전투가 시작되면 무기로 교체"], "combatSwap")
    Row(L["전투가 끝나면 낚싯대 다시 들기"], "reequipPole")

    -- 낚싯대 ↔ 평소 무기 (미니맵 버튼 왼쪽 클릭과 같음)
    page.wear = S:Button(page, L["낚싯대 착용"], function() ns:EquipBestPole() end)
    page.wear:SetPoint("TOPLEFT", 0, y - 6)

    page.all = S:Button(page, L["모든 설정 열기"], function() ns:OpenSettings() end)
    page.all:SetPoint("BOTTOMLEFT", 0, 0)
    page.donate = S:Button(page, "|cffff8fb3" .. L["후원하기"] .. "|r", function() ns:ShowDonate() end)
    page.donate:SetPoint("BOTTOMRIGHT", 0, 0)

    function page:Refresh()
        for _, r in ipairs(self.rows) do r.toggle:SetOn(ns.settings[r.key]) end
        self.keyRow.value:SetText(ns.settings.key)
        self.wear:SetLabel(ns:HasPole() and L["평소 무기로"] or L["낚싯대 착용"])
    end
end

local BUILDERS = {
    session = BuildSession, recent = BuildRecent, journal = BuildJournal,
    zone = BuildZone, options = BuildOptions,
}

-- 창 -------------------------------------------------------------------------------
local function CreateWindow()
    local f = CreateFrame("Frame", "WoWSmartFishingWindow", UIParent, "BackdropTemplate")
    S:Panel(f)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WoWSmartFishingWindow") -- ESC로 닫기

    -- 머리말
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetSize(26, 26)
    f.logo:SetPoint("TOPLEFT", PAD, -PAD)
    f.logo:SetTexture(S.ICON)
    S:Round(f, f.logo)

    f.title = S:Text(f, 14)
    f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 10, -1)
    f.title:SetText(ns.name)

    f.zone = S:Text(f, 11, S.muted)
    f.zone:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.t = S:Text(close, 16, S.muted)
    close.t:SetPoint("CENTER")
    close.t:SetText("×")
    close:SetScript("OnEnter", function(self) self.t:SetTextColor(unpack(S.text)) end)
    close:SetScript("OnLeave", function(self) self.t:SetTextColor(unpack(S.muted)) end)
    close:SetScript("OnClick", function() f:Hide() end)

    -- 탭
    local tabs = Tabs()
    local tabW = (WIDTH - PAD * 2) / #tabs
    f.tabs, f.pages = {}, {}
    for i, t in ipairs(tabs) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(tabW, 30)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * tabW, -52)
        b.t = S:Text(b, 12, S.muted)
        b.t:SetPoint("CENTER")
        b.t:SetJustifyH("CENTER")
        b.t:SetText(t.label)
        b.bar = b:CreateTexture(nil, "OVERLAY")
        b.bar:SetHeight(2)
        b.bar:SetPoint("BOTTOMLEFT", 8, 0)
        b.bar:SetPoint("BOTTOMRIGHT", -8, 0)
        b.bar:SetColorTexture(unpack(S.accent))
        b:SetScript("OnEnter", function(self) if f.current ~= t.key then self.t:SetTextColor(unpack(S.text)) end end)
        b:SetScript("OnLeave", function(self) if f.current ~= t.key then self.t:SetTextColor(unpack(S.muted)) end end)
        b:SetScript("OnClick", function() f:SelectTab(t.key) end)
        b.key = t.key
        f.tabs[i] = b

        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", PAD, -96)
        page:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        page:Hide()
        BUILDERS[t.key](page)
        f.pages[t.key] = page
    end
    local tabLine = S:Line(f)
    tabLine:SetPoint("TOPLEFT", 0, -82)
    tabLine:SetPoint("TOPRIGHT", 0, -82)

    function f:SelectTab(key)
        self.current = key
        ns.settings.tab = key
        for _, b in ipairs(self.tabs) do
            local on = b.key == key
            b.t:SetTextColor(unpack(on and S.text or S.muted))
            b.bar:SetShown(on)
        end
        for k, page in pairs(self.pages) do page:SetShown(k == key) end
        self:Refresh()
    end

    function f:Refresh()
        local mapID = C_Map.GetBestMapForUnit("player")
        self.zone:SetText(ns:MapName(mapID))
        local page = self.pages[self.current]
        if page and page.Refresh then page:Refresh() end
    end

    -- 세션 탭은 1초마다 시간 갱신
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        if self.current == "session" then self.pages.session:Tick() end
    end)

    f:SetScript("OnShow", function(self) self:SelectTab(self.current or ns.settings.tab or "session") end)
    f:Hide()
    return f
end

function ns:ToggleWindow(tab)
    window = window or CreateWindow()
    if tab then
        -- 같은 탭이 이미 열려 있으면 닫기
        if window:IsShown() and window.current == tab then
            window:Hide()
            return
        end
        window:Show()
        window:SelectTab(tab)
        return
    end
    window:SetShown(not window:IsShown())
end

local pending = false
local function RefreshIfShown()
    if not window or not window:IsShown() or pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if window:IsShown() then window:Refresh() end
    end)
end
ns:On("AM_DATA_CHANGED", RefreshIfShown)
ns:On("AM_SETTINGS_CHANGED", RefreshIfShown)
ns:On("ZONE_CHANGED_NEW_AREA", RefreshIfShown)
ns:On("ZONE_CHANGED", RefreshIfShown)
ns:On("GET_ITEM_INFO_RECEIVED", RefreshIfShown)
ns:On("PLAYER_EQUIPMENT_CHANGED", RefreshIfShown)
