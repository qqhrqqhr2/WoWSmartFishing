local ADDON, ns = ...
local L = ns.L
local S = ns.Style

-- 낚싯대를 들면 나오는 작은 세션 창 -------------------------------------------------
local hud

local function CreateHUD()
    local f = CreateFrame("Button", "WoWSmartFishingHUD", UIParent, "BackdropTemplate")
    S:Panel(f)
    f:SetSize(236, 84)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local pos = ns.db.hudPos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.db.hudPos = { p, rp, x, y }
    end)
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns:ToggleWindow("options") else ns:ToggleWindow("session") end
    end)
    f:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(S.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.name, 0.27, 0.78, 0.88)
        GameTooltip:AddLine(L["왼쪽 클릭: 기록 창"], unpack(S.muted))
        GameTooltip:AddLine(L["오른쪽 클릭: 설정"], unpack(S.muted))
        GameTooltip:AddLine(L["끌기: 위치 옮기기"], unpack(S.muted))
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(S.border))
        GameTooltip:Hide()
    end)

    -- 윗줄: 숙련도 · 미끼
    f.skill = S:Text(f, 11, S.muted)
    f.skill:SetPoint("TOPLEFT", 10, -9)
    f.lure = S:Text(f, 11, S.muted)
    f.lure:SetPoint("TOPRIGHT", -10, -9)
    f.lure:SetJustifyH("RIGHT")

    -- 가운데: 숫자 4칸
    local labels = { L["시간"], L["낚음"], L["성공률"], L["시간당"] }
    f.vals = {}
    local cellW = (236 - 20) / 4
    for i, label in ipairs(labels) do
        local v = S:Text(f, 14)
        v:SetPoint("TOPLEFT", 10 + (i - 1) * cellW, -26)
        local l = S:Text(f, 9, S.muted)
        l:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -2)
        l:SetText(label)
        f.vals[i] = v
    end

    local line = S:Line(f)
    line:SetPoint("BOTTOMLEFT", 0, 24)
    line:SetPoint("BOTTOMRIGHT", 0, 24)

    -- 아랫줄: 마지막에 잡은 것
    f.lastIcon = f:CreateTexture(nil, "ARTWORK")
    f.lastIcon:SetSize(14, 14)
    f.lastIcon:SetPoint("BOTTOMLEFT", 10, 5)
    S:Round(f, f.lastIcon)
    -- 낚시 종료: 세션을 마치고 평소 무기로
    f.stop = CreateFrame("Button", nil, f, "BackdropTemplate")
    S:Panel(f.stop, { 1, 1, 1, 0.04 }, S.border)
    f.stop:SetHeight(18)
    f.stop:SetPoint("BOTTOMRIGHT", -6, 3)
    f.stop.t = S:Text(f.stop, 10)
    f.stop.t:SetPoint("CENTER")
    f.stop.t:SetJustifyH("CENTER")
    f.stop.t:SetText(L["낚시 종료"])
    f.stop:SetWidth(f.stop.t:GetStringWidth() + 16)
    f.stop:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.85, 0.40, 0.40, 1)
        self.t:SetTextColor(1, 0.75, 0.75)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["낚시 종료"], 1, 1, 1)
        GameTooltip:AddLine(L["이번 세션을 마치고 평소 무기로 바꿉니다."], unpack(S.muted))
        GameTooltip:Show()
    end)
    f.stop:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(S.border))
        self.t:SetTextColor(unpack(S.text))
        GameTooltip:Hide()
    end)
    f.stop:SetScript("OnClick", function() ns:StopFishing() end)

    f.last = S:Text(f, 11)
    f.last:SetPoint("LEFT", f.lastIcon, "RIGHT", 6, 0)
    f.last:SetPoint("RIGHT", f.stop, "LEFT", -6, 0)

    function f:Update()
        local s = ns:Session()
        local catches, casts = s and s.catches or 0, s and s.casts or 0
        local dur = 0
        if s then
            dur = (time() - s.last > 60) and (s.last - s.start) or (time() - s.start)
        end
        self.vals[1]:SetText(ns:FormatDuration(dur))
        self.vals[2]:SetText(catches)
        self.vals[3]:SetText(casts > 0 and string.format("%.0f%%", catches / casts * 100) or "-")
        self.vals[4]:SetText(dur > 60 and string.format("%.0f", catches / dur * 3600) or "-")

        local rank, maxRank, mod = ns:FishingSkill()
        if rank then
            local _, need = ns:ExpectedHere(C_Map.GetBestMapForUnit("player"))
            local mine = rank + (mod or 0)
            local color = (need and mine < need) and "|cffd9a066" or "|cffeeeff2"
            self.skill:SetText(string.format(L["숙련 %s%d|r%s%s"], color, mine,
                (mod and mod > 0) and ("|cff8c94a3(+" .. mod .. ")|r") or "",
                need and ("  |cff8c94a3" .. L["권장 %d"]:format(need) .. "|r") or ""))
        else
            self.skill:SetText(L["낚시"])
        end

        local lure = ns:LureRemaining()
        if lure then
            self.lure:SetText(L["미끼 %s"]:format("|cff45c7e0" .. ns:FormatDuration(lure) .. "|r"))
        else
            self.lure:SetText(L["|cffd9a066미끼 없음|r"])
        end

        local r = ns.db.recent[1]
        if r and s and r.t >= s.start then
            self.lastIcon:SetTexture(ns:ItemIcon(r.id))
            self.lastIcon:Show()
            self.last:SetText(ns:ItemName(r.id))
        else
            self.lastIcon:Hide()
            self.last:SetText(L["|cff8c94a3낚시를 시작해 보세요|r"])
            self.last:SetPoint("LEFT", f, "BOTTOMLEFT", 10, 12)
        end
        if self.lastIcon:IsShown() then
            self.last:SetPoint("LEFT", self.lastIcon, "RIGHT", 6, 0)
        end

        -- 찌를 자동으로 못 잡았을 때 안내
        if ns.bobberFound == false then
            self.lastIcon:Hide()
            self.last:SetPoint("LEFT", self, "BOTTOMLEFT", 10, 12)
            self.last:SetText(L["|cffd9a066찌 인식 안 됨 · 마우스를 찌에 올리고 키를 누르세요|r"])
        end
    end

    local elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        self:Update()
    end)
    f:Hide()
    return f
end

local function UpdateVisibility()
    if not ns.settings then return end
    local show = ns.settings.showHUD and ns:HasPole()
    if show and not hud then hud = CreateHUD() end
    if hud then
        hud:SetScale(ns.settings.hudScale or 1)
        hud:SetShown(show)
        if show then hud:Update() end
    end
end

ns:On("PLAYER_ENTERING_WORLD", UpdateVisibility)
ns:On("PLAYER_EQUIPMENT_CHANGED", UpdateVisibility)
ns:On("AM_SETTINGS_CHANGED", function(key)
    if key == "showHUD" or key == "hudScale" then UpdateVisibility() end
end)
ns:On("AM_BOBBER_CHANGED", function()
    if hud and hud:IsShown() then hud:Update() end
end)
ns:On("AM_DATA_CHANGED", function()
    if hud and hud:IsShown() then hud:Update() end
end)
