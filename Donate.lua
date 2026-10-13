local ADDON, ns = ...
local L = ns.L
local S = ns.Style

-- 후원 창: 애드온은 브라우저를 열 수 없어서 주소를 복사하게 함 -----------------------
ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"

local frame

local function Create()
    local f = CreateFrame("Frame", "WoWSmartFishingDonate", UIParent, "BackdropTemplate")
    S:Panel(f)
    f:SetSize(340, 150)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WoWSmartFishingDonate")

    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetSize(26, 26)
    f.logo:SetPoint("TOPLEFT", 14, -14)
    f.logo:SetTexture(S.ICON)
    S:Round(f, f.logo)

    f.title = S:Text(f, 14)
    f.title:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)
    f.title:SetText(L["후원하기"])

    f.text = S:Text(f, 11, S.muted)
    f.text:SetPoint("TOPLEFT", 14, -50)
    f.text:SetPoint("RIGHT", -14, 0)
    f.text:SetWordWrap(true)
    f.text:SetText(L["도움이 되셨다면 후원해 주세요! 아래 주소를 복사(Ctrl+C)해서 브라우저에 붙여 넣으세요."])

    local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    S:Panel(box, { 0, 0, 0, 0.35 }, S.accent)
    box:SetHeight(26)
    box:SetPoint("BOTTOMLEFT", 14, 14)
    box:SetPoint("BOTTOMRIGHT", -14, 14)
    box:SetFont(S.font, 12, "")
    box:SetTextColor(1, 1, 1)
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    -- 주소를 고칠 수 없게: 바뀌면 다시 채우고 전체 선택
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(ns.DONATE_URL) self:HighlightText() end
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    box:SetScript("OnEnterPressed", function() f:Hide() end)
    f.box = box

    local close = CreateFrame("Button", nil, f)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.t = S:Text(close, 16, S.muted)
    close.t:SetPoint("CENTER")
    close.t:SetText("×")
    close:SetScript("OnEnter", function(self) self.t:SetTextColor(unpack(S.text)) end)
    close:SetScript("OnLeave", function(self) self.t:SetTextColor(unpack(S.muted)) end)
    close:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnShow", function(self)
        self.box:SetText(ns.DONATE_URL)
        self.box:SetFocus()
        self.box:HighlightText()
    end)
    f:Hide()
    return f
end

function ns:ShowDonate()
    frame = frame or Create()
    frame:Show()
end
