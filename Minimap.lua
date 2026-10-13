local ADDON, ns = ...
local L = ns.L
local S = ns.Style

-- 미니맵 둘레의 동그란 버튼 ----------------------------------------------------------
local button

local function UpdatePosition()
    local angle = math.rad(ns.settings.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

local function CreateButton()
    local b = CreateFrame("Button", "WoWSmartFishingMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("TOPLEFT", 7, -6)
    b.icon:SetTexture(S.ICON_INNER)
    S:Round(b, b.icon)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns:ToggleWindow("options")
        else
            ns:EquipBestPole()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("WoW Smart Fishing", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["왼쪽 클릭"], ns:HasPole() and L["평소 무기로"] or L["낚싯대 착용"], S.accent[1], S.accent[2], S.accent[3], 1, 1, 1)
        GameTooltip:AddDoubleLine(L["오른쪽 클릭"], L["설정"], S.accent[1], S.accent[2], S.accent[3], 1, 1, 1)
        GameTooltip:AddDoubleLine(L["끌기"], L["버튼 위치 이동"], S.accent[1], S.accent[2], S.accent[3], 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function UpdateMinimapButton()
    if not ns.settings then return end
    if ns.settings.minimapButton then
        button = button or CreateButton()
        UpdatePosition()
        button:Show()
    elseif button then
        button:Hide()
    end
end

ns:On("AM_DB_READY", UpdateMinimapButton)
ns:On("AM_SETTINGS_CHANGED", function(key)
    if key == "minimapButton" then UpdateMinimapButton() end
end)

-- 애드온 모음 버튼(미니맵 위 애드온 목록)에서 눌렀을 때
function WoWSmartFishing_OnAddonCompartmentClick(_, mouse)
    if mouse == "RightButton" then ns:ToggleWindow("options") else ns:EquipBestPole() end
end
