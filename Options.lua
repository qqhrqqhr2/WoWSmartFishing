local ADDON, ns = ...
local L = ns.L

-- 게임 설정 > 애드온 > 스마트 낚시 ----------------------------------------------------
local category

local function KeyList()
    return {
    { "SPACE", L["스페이스"] },
    { "F", "F" }, { "G", "G" }, { "R", "R" }, { "T", "T" }, { "V", "V" },
    { "BUTTON3", L["마우스 휠 클릭"] },
    { "BUTTON4", L["마우스 4번 버튼"] },
    { "BUTTON5", L["마우스 5번 버튼"] },
    }
end

-- 확인 창 (언어 설정이 적용된 뒤에 만듦) -------------------------------------------------------------------------
local function DefinePopups()
    StaticPopupDialogs["WOWSMARTFISHING_RELOAD"] = {
        text = L["언어를 바꾸려면 UI를 다시 불러와야 해요. 지금 다시 불러올까요?"],
        button1 = L["다시 불러오기"], button2 = L["나중에"],
        OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    StaticPopupDialogs["WOWSMARTFISHING_RESET_ZONE"] = {
        text = L["현재 지역의 낚시 지점 기록을 지울까요?"],
        button1 = YES, button2 = NO,
        OnAccept = function()
            local mapID = C_Map.GetBestMapForUnit("player")
            if mapID then ns.db.spots[mapID] = nil end
            ns:Print(L["현재 지역 낚시 지점 기록을 지웠어요."])
            ns:Fire("AM_DATA_CHANGED")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    StaticPopupDialogs["WOWSMARTFISHING_RESET_ALL"] = {
        text = L["모든 낚시 기록(지점, 기록, 도감, 세션)을 지울까요?\n되돌릴 수 없어요."],
        button1 = YES, button2 = NO,
        OnAccept = function()
            local db = ns.db
            wipe(db.spots)
            wipe(db.recent)
            wipe(db.journal)
            db.totals = { casts = 0, catches = 0, missed = 0 }
            db.session = nil
            ns:Print(L["모든 낚시 기록을 지웠어요."])
            ns:Fire("AM_DATA_CHANGED")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
    }

    StaticPopupDialogs["WOWSMARTFISHING_RESET_SHARED"] = {
        text = L["다른 플레이어에게 공유받은 낚시 기록을 모두 지울까요?"],
        button1 = YES, button2 = NO,
        OnAccept = function() ns:ClearShared() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

-- 도우미 --------------------------------------------------------------------------
local function OnChanged(setting, key)
    local function cb() ns:Fire("AM_SETTINGS_CHANGED", key) end
    if setting.SetValueChangedCallback then
        setting:SetValueChangedCallback(cb)
    elseif Settings.SetOnValueChangedCallback then
        Settings.SetOnValueChangedCallback(setting:GetVariable(), cb)
    end
end

local function Register(key, name, default)
    local variable = "WoWSmartFishing_" .. key
    local setting = Settings.RegisterAddOnSetting(category, variable, key, ns.settings, type(default), name, default)
    OnChanged(setting, key)
    return setting
end

local function Header(layout, text)
    if CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
end

local function Checkbox(key, name, tooltip)
    local setting = Register(key, name, ns.settings[key])
    Settings.CreateCheckbox(category, setting, tooltip)
end

local function Slider(key, name, minV, maxV, step, fmt, tooltip)
    local setting = Register(key, name, ns.settings[key])
    local options = Settings.CreateSliderOptions(minV, maxV, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
    Settings.CreateSlider(category, setting, options, tooltip)
end

local function Button(layout, name, text, onClick, tooltip)
    if CreateSettingsButtonInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
    end
end

-- 패널 만들기 ------------------------------------------------------------------------
local function Build()
    DefinePopups()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory(ns.name)

    Header(layout, L["언어"])
    local langSetting = Register("language", L["애드온 언어"], ns.settings.language)
    Settings.CreateDropdown(category, langSetting, function()
        local c = Settings.CreateControlTextContainer()
        for _, code in ipairs(ns.LANGUAGE_ORDER) do
            c:Add(code, code == "auto" and L["자동 (게임 언어)"] or ns.LANGUAGE_NAMES[code])
        end
        return c:GetData()
    end, L["애드온에 표시되는 언어를 고릅니다. 바꾸면 UI를 다시 불러와야 적용돼요.\n게임 글꼴에 없는 글자(예: 한국어 게임에서 중국어)는 깨져 보일 수 있어요."])

    Header(layout, L["낚시"])
    Checkbox("oneButton", L["원버튼 낚시"],
        L["낚싯대를 들고 있을 때 키 하나로 던지고, 찌가 물면 같은 키로 건져 올립니다."])

    local keySetting = Register("key", L["원버튼 키"], ns.settings.key)
    Settings.CreateDropdown(category, keySetting, function()
        local c = Settings.CreateControlTextContainer()
        local found = false
        for _, k in ipairs(KeyList()) do
            c:Add(k[1], k[2])
            if k[1] == ns.settings.key then found = true end
        end
        if not found then c:Add(ns.settings.key, ns.settings.key) end -- /sf key 로 직접 정한 키
        return c:GetData()
    end, L["원버튼 낚시에 쓸 키. 목록에 없는 키는 /sf key 로 정할 수 있어요.\n낚싯대를 들고 있을 때만 바뀌고, 전투가 시작되면 원래 기능으로 돌아옵니다."])

    Checkbox("autoLoot", L["자동 획득"],
        L["낚은 물고기와 아이템을 전리품 창 없이 바로 가방에 넣습니다."])
    Checkbox("autoLure", L["미끼 자동 사용"],
        L["낚싯대에 미끼가 없으면 원버튼을 눌렀을 때 가방에서 가장 좋은 미끼를 먼저 바릅니다."])
    Checkbox("setSoftInteract", L["찌 자동 인식"],
        L["게임의 상호작용 대상 설정을 켜서 찌를 자동으로 인식하게 합니다. 끄면 원버튼으로 건지기가 안 될 수 있어요."])
    Checkbox("expandInteract", L["찌 인식 범위 넓히기"],
        L["찌가 멀리 떨어지거나 캐릭터 옆쪽에 있어도 인식되도록 상호작용 거리와 각도를 넓힙니다.\n그래도 인식이 안 되면 마우스를 찌에 올리고 키를 누르면 건져집니다."])

    Header(layout, L["장비"])
    Checkbox("combatSwap", L["전투가 시작되면 무기로 교체"],
        L["낚싯대를 든 채로 전투가 시작되면 마지막에 들었던 무기로 바꿉니다."])
    Checkbox("reequipPole", L["전투가 끝나면 낚싯대 다시 들기"],
        L["전투 때문에 무기로 바꿨다면 전투가 끝난 뒤 낚싯대를 다시 듭니다."])
    Button(layout, L["낚싯대 / 평소 무기"], L["바꾸기"], function() ns:EquipBestPole() end,
        L["가방에서 가장 좋은 낚싯대를 착용하고, 낚싯대를 들고 있으면 평소 무기로 바꿉니다."])

    Header(layout, L["화면"])
    Checkbox("showHUD", L["낚싯대를 들면 세션 창 표시"],
        L["숙련도, 미끼 남은 시간, 이번 세션 기록을 보여주는 작은 창입니다."])
    Slider("hudScale", L["세션 창 크기"], 0.7, 1.5, 0.05,
        function(v) return string.format("%d%%", v * 100 + 0.5) end)
    Checkbox("showPins", L["지도에 낚시 지점 표시"],
        L["세계지도에 내가 낚은 지점을 물고기 아이콘으로 표시합니다."])
    Slider("pinScale", L["지도 핀 크기"], 0.6, 1.6, 0.05,
        function(v) return string.format("%d%%", v * 100 + 0.5) end)
    Checkbox("mapButton", L["세계지도에 물고기 선택 버튼 표시"],
        L["세계지도에서 물고기별 낚시 지점을 고르는 버튼입니다. 버튼을 끌어서 원하는 곳으로 옮길 수 있어요."])
    Button(layout, L["세계지도 버튼 위치"], L["처음 위치로"], function() ns:ResetMapButton() end,
        L["다른 애드온 버튼에 가려졌을 때 지도 아래쪽 가운데로 되돌립니다."])
    Checkbox("itemTooltip", L["아이템 툴팁에 잡히는 곳 표시"],
        L["물고기 툴팁에 잘 잡히는 지역, 물고기 떼 위치, 내가 낚은 수를 덧붙입니다."])
    Checkbox("minimapButton", L["미니맵 버튼 표시"],
        L["미니맵 옆 버튼. 왼쪽 클릭: 가장 좋은 낚싯대 착용(들고 있으면 평소 무기로), 오른쪽 클릭: 설정"])

    Header(layout, L["기본 데이터"])
    Checkbox("showLegend", L["세계지도에 일반 낚시 어종 목록 표시"],
        L["지역 지도를 열면 그 지역에서 일반 낚시로 잡히는 물고기와 확률을 목록으로 보여줍니다.\n대륙 지도에서 물고기를 고르면 그 물고기가 잘 잡히는 지역 순위를 보여줘요."])
    Checkbox("showPools", L["물고기 떼 출현 지점 표시"],
        L["물고기 떼가 나타나는 자리를 지도에 파란 테두리 핀으로 표시합니다.\n대륙 지도에서는 물고기를 골랐을 때만 표시돼요."])
    Checkbox("showExpected", L["물고기가 나오는 지역과 확률 표시"],
        L["세계지도에서 물고기를 고르면 그 물고기가 나오는 지역마다 확률을 표시합니다.\n오리지널 클래식 기준 데이터라 와우 포에버 신규 지역·어종은 빠져 있어요."])

    Header(layout, L["공유"])
    Checkbox("shareCatches", L["낚은 위치를 길드·파티에 공유"],
        L["같은 애드온을 쓰는 길드원·파티원에게 낚은 위치와 물고기를 보냅니다."])
    Checkbox("receiveShared", L["다른 플레이어의 공유 받기"],
        L["길드원·파티원이 보낸 낚시 위치를 받아서 저장합니다."])
    Checkbox("showShared", L["공유받은 위치 지도에 표시"],
        L["공유받은 낚시 지점을 금색 테두리 핀으로 표시합니다."])
    Button(layout, L["내 낚시 기록 전체"], L["보내기"], function() ns:SendAllRecords() end,
        L["지금까지 내가 낚은 지점 기록을 길드·파티에 한 번에 보냅니다."])
    Button(layout, L["공유받은 기록"], L["지우기"], function()
        StaticPopup_Show("WOWSMARTFISHING_RESET_SHARED")
    end)

    Header(layout, L["기록"])
    Slider("sessionIdle", L["새 세션 기준 (쉰 시간)"], 5, 60, 5,
        function(v) return string.format(L["%d분"], v) end,
        L["이 시간 동안 낚시를 하지 않으면 다음 낚시부터 새 세션으로 기록합니다."])
    Checkbox("newFishAlert", L["처음 낚은 물고기 알림"],
        L["도감에 없던 물고기를 처음 낚으면 소리와 채팅으로 알려줍니다."])
    Button(layout, L["낚시 기록 창"], L["열기"], function() ns:ToggleWindow("session") end)
    Button(layout, L["현재 지역 낚시 지점"], L["지우기"], function()
        StaticPopup_Show("WOWSMARTFISHING_RESET_ZONE")
    end)
    Button(layout, L["모든 낚시 기록"], L["전부 지우기"], function()
        StaticPopup_Show("WOWSMARTFISHING_RESET_ALL")
    end)

    Header(layout, L["후원"])
    Button(layout, L["애드온이 도움이 되셨나요?"], L["후원하기"], function() ns:ShowDonate() end,
        L["Buy Me a Coffee 후원 주소를 복사할 수 있는 창을 엽니다."])

    Settings.RegisterAddOnCategory(category)
end

function ns:OpenSettings()
    if category and Settings and Settings.OpenToCategory then
        if InCombatLockdown() then
            ns:Print(L["전투 중에는 설정을 열 수 없어요. 대신 기록 창의 설정 탭을 열게요."])
            ns:ToggleWindow("options")
            return
        end
        Settings.OpenToCategory(category:GetID())
    else
        ns:ToggleWindow("options")
    end
end

ns:On("AM_DB_READY", function()
    local ok, err = pcall(Build)
    if not ok then
        category = nil
        geterrorhandler()(err)
    end
end)

-- 처음 낚은 물고기 알림 -------------------------------------------------------------
ns:On("AM_NEW_FISH", function(itemID)
    if not ns.settings.newFishAlert then return end
    ns:Print(L["새 물고기 발견! "] .. ns:ItemName(itemID))
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end)

-- 언어 바꾸기: 저장하고 UI 다시 불러오기를 물어봄
function ns:SetLanguage(code)
    if ns.settings.language ~= code then
        ns.settings.language = code
    end
    ns:Print(L["애드온 언어: %s"]:format(code == "auto" and L["자동 (게임 언어)"] or ns.LANGUAGE_NAMES[code]))
    StaticPopup_Show("WOWSMARTFISHING_RELOAD")
end

ns:On("AM_SETTINGS_CHANGED", function(key)
    if key == "language" then ns:SetLanguage(ns.settings.language) end
end)
