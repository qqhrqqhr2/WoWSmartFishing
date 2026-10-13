local ADDON, ns = ...
local L = ns.L

-- 플레이어끼리 낚시 위치 공유 (길드 · 파티 · 공격대) ---------------------------------
-- 메시지
--   C|지도|x|y|아이템|개수            낚을 때마다 바로 보냄 (x, y는 0~1000)
--   S|지도|x,y,아이템,개수;x,y,...    "내 기록 보내기"로 모아서 보냄
local PREFIX = "WSFish"
local MERGE_RADIUS = 0.015
local MAX_SPOTS_PER_MAP = 400
local MAX_MSG = 240

local playerName

local function Channels()
    local list = {}
    if IsInGuild() then list[#list + 1] = "GUILD" end
    if IsInRaid() then
        list[#list + 1] = "RAID"
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        list[#list + 1] = "PARTY"
    end
    return list
end

local function Send(msg)
    for _, ch in ipairs(Channels()) do
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
    end
end

-- 보내기 대기열 (한꺼번에 많이 보내면 끊기므로 천천히)
local queue, sending = {}, false
local function Pump()
    local msg = table.remove(queue, 1)
    if not msg then sending = false return end
    Send(msg)
    C_Timer.After(0.35, Pump)
end
local function Queue(msg)
    queue[#queue + 1] = msg
    if not sending then sending = true Pump() end
end

-- 공유받은 지점 저장 --------------------------------------------------------------
local function FindSpot(spots, x, y)
    for _, s in ipairs(spots) do
        local dx, dy = s.x - x, s.y - y
        if dx * dx + dy * dy <= MERGE_RADIUS * MERGE_RADIUS then return s end
    end
end

-- merge: true면 개수를 더하지 않고 큰 값으로 (같은 기록을 여러 번 받아도 부풀지 않게)
local function AddShared(mapID, x, y, itemID, count, merge)
    local db = ns.db
    db.shared = db.shared or {}
    local spots = db.shared[mapID]
    if not spots then
        spots = {}
        db.shared[mapID] = spots
    end
    local spot = FindSpot(spots, x, y)
    if not spot then
        if #spots >= MAX_SPOTS_PER_MAP then return end
        spot = { x = x, y = y, n = 0, fish = {} }
        spots[#spots + 1] = spot
    end
    local before = spot.fish[itemID] or 0
    if merge then
        spot.fish[itemID] = math.max(before, count)
    else
        spot.fish[itemID] = before + count
    end
    spot.n = spot.n + math.max(0, spot.fish[itemID] - before)
    spot.last = time()
end

-- 받은 값 검사
local function Num(v, minV, maxV)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < minV or v > maxV then return nil end
    return v
end

local received = {} -- [보낸 사람] = { 시각, 개수 } (너무 많이 보내는 사람 막기)
local function Allow(sender, n)
    local now = GetTime()
    local r = received[sender]
    if not r or now - r.t > 60 then r = { t = now, n = 0 } received[sender] = r end
    r.n = r.n + n
    return r.n <= 2000
end

local function OnMessage(prefix, msg, channel, sender)
    prefix, msg, sender = ns.Str(prefix), ns.Str(msg), ns.Str(sender)
    if prefix ~= PREFIX or not msg or not sender or not ns.db or not ns.settings.receiveShared then return end
    if sender == playerName or Ambiguate(sender, "none") == UnitName("player") then return end
    local kind, rest = msg:match("^(%u)|(.*)$")
    if kind == "C" then
        local m, x, y, item, q = strsplit("|", rest)
        m, x, y = Num(m, 1, 100000), Num(x, 0, 1000), Num(y, 0, 1000)
        item, q = Num(item, 1, 1000000), Num(q, 1, 50)
        if not (m and x and y and item and q) or not Allow(sender, 1) then return end
        AddShared(m, x / 1000, y / 1000, item, q, false)
        ns:Fire("AM_DATA_CHANGED")
    elseif kind == "S" then
        local m, body = rest:match("^(%d+)|(.*)$")
        m = Num(m, 1, 100000)
        if not m or not body then return end
        local n = 0
        for sx, sy, sitem, sc in body:gmatch("(%d+),(%d+),(%d+),(%d+)") do
            local x, y = Num(sx, 0, 1000), Num(sy, 0, 1000)
            local item, c = Num(sitem, 1, 1000000), Num(sc, 1, 100000)
            if x and y and item and c then
                n = n + 1
                if not Allow(sender, 1) then break end
                AddShared(m, x / 1000, y / 1000, item, c, true)
            end
        end
        if n > 0 then ns:Fire("AM_DATA_CHANGED") end
    end
end

-- 내 낚시 기록 바로 공유 --------------------------------------------------------------
ns:On("AM_CATCH", function(mapID, x, y, items)
    if not ns.settings.shareCatches or mapID == 0 then return end
    for itemID, q in pairs(items) do
        Queue(string.format("C|%d|%d|%d|%d|%d", mapID, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5), itemID, math.min(q, 50)))
    end
end)

-- 내 기록 전체 보내기
function ns:SendAllRecords()
    if #Channels() == 0 then
        ns:Print(L["길드나 파티에 있어야 기록을 보낼 수 있어요."])
        return
    end
    local count = 0
    for mapID, spots in pairs(ns.db.spots) do
        if mapID ~= 0 then
            local head = "S|" .. mapID .. "|"
            local parts = {}
            local len = #head
            local function flush()
                if #parts > 0 then Queue(head .. table.concat(parts, ";")) end
                parts, len = {}, #head
            end
            for _, s in ipairs(spots) do
                for itemID, c in pairs(s.fish) do
                    local part = string.format("%d,%d,%d,%d", math.floor(s.x * 1000 + 0.5), math.floor(s.y * 1000 + 0.5), itemID, c)
                    if len + #part + 1 > MAX_MSG then flush() end
                    parts[#parts + 1] = part
                    len = len + #part + 1
                    count = count + 1
                end
            end
            flush()
        end
    end
    ns:Print(string.format(L["내 낚시 기록 %d건을 길드/파티에 보내는 중이에요."], count))
end

function ns:ClearShared()
    ns.db.shared = {}
    ns:Print(L["공유받은 낚시 기록을 지웠어요."])
    ns:Fire("AM_DATA_CHANGED")
end

function ns:SharedCount()
    local n = 0
    for _, spots in pairs(ns.db.shared or {}) do n = n + #spots end
    return n
end

ns:On("AM_DB_READY", function()
    ns.db.shared = ns.db.shared or {}
    playerName = UnitName("player") .. "-" .. (GetNormalizedRealmName() or "")
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end)
ns:On("CHAT_MSG_ADDON", OnMessage)
