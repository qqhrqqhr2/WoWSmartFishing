import lupa, sys, os
os.chdir(sys.argv[1])
import lupa.lua51 as LL
L = LL.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
ns = { handlers = {} }
function ns:On(e, fn) self.handlers[e] = self.handlers[e] or {}; table.insert(self.handlers[e], fn) end
function ns:Fire(e, ...) for _, fn in ipairs(self.handlers[e] or {}) do fn(...) end end
function ns:Print(m) print("PRINT", m) end
function ns.Safe(fn, ...) if type(fn)~='function' then return end local r = {pcall(fn, ...)} if r[1] then return unpack(r, 2) end end
function ns.Readable(v) return v ~= nil end
function ns.Str(v) if type(v)=='string' then return v end end
function ns.Num(v) if type(v)=='number' then return v end end
function ns:ItemName(id, plain) return "item"..id end
function ns:ItemIcon(id) return "icon" end
fired = {}
-- WoW API stubs
local parents = { [1434]=1415, [1429]=1415, [1436]=1415, [1413]=1414, [1415]=947, [1414]=947 }
C_Map = {
  GetMapInfo = function(id) if id==0 then return nil end return { name="map"..id, parentMapID = parents[id] or 0 } end,
  GetMapRectOnMap = function(z, m) if parents[z]==m then return 0.4, 0.6, 0.5, 0.8 end end,
  GetAreaInfo = function(a) return "area"..a end,
  GetBestMapForUnit = function() return 1434 end,
}
GetSubZoneText = function() return "area"..(subzone or 0) end
time = os.time; GetTime = os.clock
C_Timer = { After = function(t, f) table.insert(timers, f) end }
timers = {}
C_ChatInfo = { SendAddonMessage = function(p, m, ch) table.insert(sent, ch..":"..m) end, RegisterAddonMessagePrefix = function() end }
sent = {}
IsInGuild = function() return true end; IsInRaid = function() return false end; IsInGroup = function() return false end
LE_PARTY_CATEGORY_HOME = 1
UnitName = function() return "Me" end; GetNormalizedRealmName = function() return "Realm" end
Ambiguate = function(s) return (s:gsub("%-.*", "")) end
strsplit = function(sep, s) local t = {} for p in (s..sep):gmatch("(.-)"..sep:gsub("%p","%%%0")) do t[#t+1]=p end return unpack(t) end
CreateFrame = function() return setmetatable({}, {__index=function() return function() end end}) end
IsFishingLoot = function() return false end
''')
def load(f):
    L.execute('local f = assert(loadfile("%s")); f("WoWSmartFishing", ns)' % f)
L.execute('GetLocale=function() return "enUS" end')
for f in ['Locales.lua','Data.lua','Log.lua','Expected.lua','Share.lua']: load(f)
L.execute('''
ns.db = { spots = {}, recent = {}, journal = {}, totals = {casts=0,catches=0,missed=0} }
ns.settings = { receiveShared = true, shareCatches = true, sessionIdle = 15 }
ns:Fire("AM_DB_READY")
''')
print('zones for Rockscale Cod 6362:', L.eval('''(function() local t = ns:ZonesForFish(6362); local s = {} for i=1,math.min(5,#t) do s[#s+1] = t[i].mapID..":"..t[i].pct end return table.concat(s, " ") end)()'''))
print('expected STV:', L.eval('(function() local f, s = ns:ExpectedZone(1434); local n=0 for _ in pairs(f) do n=n+1 end return n.." fish, skill "..tostring(s) end)()'))
print('expected on EK continent:', L.eval('(function() local t = ns:ExpectedOnMap(1415); local n=0 for _ in pairs(t) do n=n+1 end return n end)()'))
print('pools STV:', L.eval('#ns:PoolsOnMap(1434)'), 'pools EK no filter:', L.eval('#ns:PoolsOnMap(1415)'), 'EK filter tastyfish:', L.eval('#ns:PoolsOnMap(1415, 19807)'))
print('pool label:', L.eval('ns:PoolLabel(ns.PoolsOnMap(ns, 1434)[1].poolType)'))
# subzone lookup
k = L.eval('(function() for a, e in pairs(ns.Data.subzones) do if e.m == 1434 then return a end end end)()')
L.execute('subzone = %d' % k)
print('subzone here:', L.eval('(function() local f, s, name = ns:ExpectedHere(1434); return tostring(name).." skill "..tostring(s) end)()'))
# catch -> share
L.execute('ns:AddCatch(1434, 0.3, 0.4, {[6362]=1}); for _, f in ipairs(timers) do f() end')
print('sent:', list(L.eval('sent').values()))
# receive
L.execute('''ns:Fire("CHAT_MSG_ADDON", "WSFish", "C|1434|500|600|6362|2", "GUILD", "Other-Realm")
ns:Fire("CHAT_MSG_ADDON", "WSFish", "S|1434|500|600|6362|5;100,100,6359,3", "GUILD", "Other-Realm")
ns:Fire("CHAT_MSG_ADDON", "WSFish", "S|1434|500,600,6362,4;100,100,6359,3;bad", "GUILD", "Other-Realm")
ns:Fire("CHAT_MSG_ADDON", "WSFish", "C|1434|5000|600|6362|2", "GUILD", "Other-Realm")
ns:Fire("CHAT_MSG_ADDON", "WSFish", "C|1434|500|600|6362|2", "GUILD", "Me-Realm")''')
print('shared count:', L.eval('ns:SharedCount()'), 'spot1 6362:', L.eval('ns.db.shared[1434][1].fish[6362]'), 'spot2 6359:', L.eval('ns.db.shared[1434][2] and ns.db.shared[1434][2].fish[6359]'))
L.execute('sent = {}; ns:SendAllRecords(); for i=1,5 do local t = timers; timers = {}; for _, f in ipairs(t) do f() end end')
print('sync sent:', list(L.eval('sent').values()))
print('collect EK own:', L.eval('#ns:CollectSpots(1415)'), 'collect EK shared:', L.eval('#ns:CollectSpots(1415, ns.db.shared)'))
