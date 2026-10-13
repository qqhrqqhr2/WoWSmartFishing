local ADDON, ns = ...
local S = ns.Style

-- 공용 목록: 아이콘 · 제목 · 보조 줄 · 오른쪽 값 · 비율 막대 -----------------------
local ROW_H = 36

local function CreateRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)

    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0)

    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetPoint("TOPLEFT")
    r.mark:SetPoint("BOTTOMLEFT")
    r.mark:SetWidth(2)
    r.mark:SetColorTexture(unpack(S.accent))

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", 8, 0)
    S:Round(r, r.icon)

    r.right = S:Text(r, 12)
    r.right:SetPoint("TOPRIGHT", -8, -6)
    r.right:SetJustifyH("RIGHT")

    r.right2 = S:Text(r, 10, S.muted)
    r.right2:SetPoint("TOPRIGHT", r.right, "BOTTOMRIGHT", 0, -3)
    r.right2:SetJustifyH("RIGHT")

    r.title = S:Text(r, 12)
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 1)
    r.title:SetPoint("RIGHT", r.right, "LEFT", -8, 0)

    r.sub = S:Text(r, 10, S.muted)
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
    r.sub:SetPoint("RIGHT", r.right2, "LEFT", -8, 0)

    r.track = r:CreateTexture(nil, "ARTWORK")
    r.track:SetHeight(3)
    r.track:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 1)
    r.track:SetPoint("RIGHT", -64, 0)
    r.track:SetColorTexture(1, 1, 1, 0.07)

    r.fill = r:CreateTexture(nil, "OVERLAY")
    r.fill:SetHeight(3)
    r.fill:SetPoint("LEFT", r.track, "LEFT")
    r.fill:SetColorTexture(unpack(S.accent))

    r:SetScript("OnEnter", function(self)
        if not self.data.selected then self.bg:SetColorTexture(unpack(S.hover)) end
        if self.data.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.data.itemID)
            if self.data.hint then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.data.hint, unpack(S.accent))
            end
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        if not self.data.selected then self.bg:SetColorTexture(0, 0, 0, 0) end
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        if self.data.onClick then self.data.onClick(self.data) end
    end)
    return r
end

local function FillRow(r, d)
    r.data = d
    r.icon:SetTexture(d.icon or S.ICON_INNER)
    r.title:SetText(d.title or "")
    r.sub:SetText(d.sub or "")
    r.right:SetText(d.right or "")
    r.right2:SetText(d.right2 or "")

    -- 막대가 있으면 보조 줄 대신 막대 표시
    local hasBar = d.bar ~= nil
    r.track:SetShown(hasBar)
    r.fill:SetShown(hasBar)
    r.sub:SetShown(not hasBar)
    if hasBar then
        local w = r.track:GetWidth()
        if not w or w <= 0 then w = 150 end
        r.fill:SetWidth(math.max(1, w * math.min(1, d.bar)))
    end

    r.mark:SetShown(d.selected and true or false)
    if d.selected then
        r.bg:SetColorTexture(S.accent[1], S.accent[2], S.accent[3], 0.10)
    else
        r.bg:SetColorTexture(0, 0, 0, 0)
    end
    r:Show()
end

-- 스크롤 목록 (마우스 휠, 스크롤바 없음)
function S:List(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(self, w) child:SetWidth(w) end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * ROW_H * 2)))
    end)

    scroll.rows = {}
    scroll.empty = S:Text(child, 11, S.muted)
    scroll.empty:SetPoint("TOP", 0, -30)
    scroll.empty:SetJustifyH("CENTER")
    scroll.empty:SetWordWrap(true)
    scroll.empty:SetWidth(240)

    function scroll:SetEmptyText(text) self.empty:SetText(text) end

    function scroll:SetData(list)
        for _, r in ipairs(self.rows) do r:Hide() end
        self.empty:SetShown(#list == 0)
        for i, d in ipairs(list) do
            local r = self.rows[i]
            if not r then
                r = CreateRow(child)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
                r:SetPoint("RIGHT", child, "RIGHT")
                self.rows[i] = r
            end
            FillRow(r, d)
        end
        child:SetHeight(math.max(1, #list * ROW_H))
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        if self:GetVerticalScroll() > maxScroll then self:SetVerticalScroll(maxScroll) end
    end
    return scroll
end

-- 숫자 칸: 큰 값 + 작은 설명 ----------------------------------------------------
function S:Stat(parent, label)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    S:Panel(f, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.06 })
    f.value = S:Text(f, 16)
    f.value:SetPoint("TOPLEFT", 10, -8)
    f.label = S:Text(f, 10, S.muted)
    f.label:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -4)
    f.label:SetText(label)
    return f
end

-- 글자 버튼 (테두리 얇은 버튼) ---------------------------------------------------
function S:Button(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    S:Panel(b, { 1, 1, 1, 0.03 }, S.border)
    b:SetHeight(26)
    b.t = S:Text(b, 12)
    b.t:SetPoint("CENTER")
    b.t:SetJustifyH("CENTER")
    function b:SetLabel(s)
        self.t:SetText(s)
        self:SetWidth(self.t:GetStringWidth() + 24)
    end
    b:SetLabel(text)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(S.accent)) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(S.border)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- 설정 줄: 라벨 + 스위치
function S:SettingRow(parent, label, key)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(26)
    row.label = S:Text(row, 12)
    row.label:SetPoint("LEFT")
    row.label:SetText(label)
    row.toggle = S:Toggle(row, function(on)
        ns.settings[key] = on
        ns:Fire("AM_SETTINGS_CHANGED", key)
    end)
    row.toggle:SetPoint("RIGHT")
    row.key = key
    return row
end
