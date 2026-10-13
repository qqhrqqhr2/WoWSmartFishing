local ADDON, ns = ...
local L = ns.L

-- 공통 스타일: 어두운 단색 + 얇은 테두리 + 청록 포인트 색
local S = {}
ns.Style = S

S.bg      = { 0.07, 0.08, 0.10, 0.96 }
S.border  = { 0.20, 0.22, 0.27, 1 }
S.line    = { 1, 1, 1, 0.06 }
S.hover   = { 1, 1, 1, 0.04 }
S.accent  = { 0.27, 0.78, 0.88, 1 }
S.text    = { 0.93, 0.94, 0.96, 1 }
S.muted   = { 0.55, 0.58, 0.64, 1 }
S.font    = STANDARD_TEXT_FONT

S.CIRCLE  = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
S.WHITE   = "Interface\\Buttons\\WHITE8x8"
-- 대표 아이콘 (테두리 포함 / 작은 원 안에 넣는 안쪽 그림)
S.ICON       = "Interface\\AddOns\\WoWSmartFishing\\Media\\icon"
S.ICON_INNER = "Interface\\AddOns\\WoWSmartFishing\\Media\\icon_inner"

function S:Panel(frame, bg, border)
    frame:SetBackdrop({ bgFile = S.WHITE, edgeFile = S.WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(bg or S.bg))
    frame:SetBackdropBorderColor(unpack(border or S.border))
end

function S:Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(S.font, size or 12, "")
    fs:SetTextColor(unpack(color or S.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function S:Line(parent, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(unpack(S.line))
    t:SetHeight(1)
    return t
end

-- 텍스처를 원형으로 잘라냄
function S:Round(parent, texture)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(S.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

-- 켜기/끄기 스위치
function S:Toggle(parent, onChange)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(30, 16)

    b.track = b:CreateTexture(nil, "BACKGROUND")
    b.track:SetAllPoints()

    b.knob = b:CreateTexture(nil, "ARTWORK")
    b.knob:SetSize(12, 12)
    b.knob:SetColorTexture(1, 1, 1, 1)
    S:Round(b, b.knob)

    function b:SetOn(on)
        self.on = on and true or false
        self.track:SetColorTexture(unpack(self.on and S.accent or S.border))
        self.knob:ClearAllPoints()
        self.knob:SetPoint(self.on and "RIGHT" or "LEFT", self.on and -2 or 2, 0)
    end

    b:SetScript("OnClick", function(self)
        self:SetOn(not self.on)
        onChange(self.on)
    end)
    return b
end

-- 아이템 이름 (품질 색 포함)
function ns:ItemName(itemID, plain)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
        return L["불러오는 중..."]
    end
    if plain then return name end
    local quality = C_Item.GetItemQualityByID(itemID)
    local color = quality and ITEM_QUALITY_COLORS[quality]
    if color then return color.hex .. name .. "|r" end
    return name
end

function ns:ItemIcon(itemID)
    return C_Item.GetItemIconByID(itemID) or S.ICON_INNER
end
