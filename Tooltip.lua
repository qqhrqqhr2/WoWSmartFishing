local ADDON, ns = ...
local L = ns.L

-- 아이템 툴팁에 "어디서 잡히는지" 덧붙이기 ------------------------------------------
local MAX_ZONES = 3

local function Add(tooltip, data)
    if not ns.settings or not ns.settings.itemTooltip then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local itemID = data and ns.Num(data.id) -- 보호된 값(secret)이면 건너뜀
    if not itemID then return end

    local zones = ns:ZonesForFish(itemID)
    local pools = ns:PoolZonesForFish(itemID)
    if (not zones[1] or zones[1].pct < 1) and not pools[1] then return end

    tooltip:AddLine(" ")
    tooltip:AddLine("WoW Smart Fishing", 0.27, 0.78, 0.88)
    local shown = 0
    for _, z in ipairs(zones) do
        if shown >= MAX_ZONES or z.pct < 1 then break end
        local zd = ns.Data.zones[z.mapID]
        local left = ns:MapName(z.mapID) .. ((zd and zd.s) and ("  |cff8c94a3" .. zd.s .. "|r") or "")
        tooltip:AddDoubleLine(left, string.format("%.0f%%", z.pct), 0.85, 0.86, 0.9, 1, 1, 1)
        shown = shown + 1
    end
    if pools[1] then
        local names = {}
        for i = 1, math.min(2, #pools) do names[#names + 1] = ns:MapName(pools[i].mapID) end
        tooltip:AddLine(L["물고기 떼: %s"]:format(table.concat(names, ", ")), 0.43, 0.64, 1)
    end
    local j = ns.db and ns.db.journal[itemID]
    if j then
        tooltip:AddLine(L["내가 낚은 수: %d"]:format(j.n), 0.55, 0.58, 0.64)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Add)
end
