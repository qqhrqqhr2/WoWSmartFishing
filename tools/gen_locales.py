import re,glob,sys,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from translations import T
os.chdir(sys.argv[1])
keys=[]
for f in sorted(glob.glob('*.lua')):
    if f in ('Data.lua','Locales.lua'): continue
    for k in re.findall(r'L\["((?:[^"\\]|\\.)*)"\]', open(f,encoding='utf-8').read()):
        if k not in keys: keys.append(k)
missing=[k for k in keys if k not in T]
assert not missing, missing
for k,v in T.items():
    ks=sorted(re.findall(r'%[\d.]*[sdf]|%%',k))
    for t in v:
        assert '"' not in t and '’' not in t, t
        assert sorted(re.findall(r'%[\d.]*[sdf]|%%',t))==ks,(k,t)
langs=['enUS','zhTW','deDE','frFR','esES']
out=['-- 번역: 키는 한국어 원문. 한국어로 표시할 때는 키를 그대로 씀.','-- 자동 생성 (gen_locales.py)','local ADDON, ns = ...','','local T = {}']
for i,lang in enumerate(langs):
    out.append('T.%s = {' % lang)
    for k in keys: out.append('    ["%s"] = "%s",' % (k, T[k][i]))
    out.append('}')
out.append('''
-- 고를 수 있는 언어 (이름은 각 언어로)
ns.LANGUAGE_ORDER = { "auto", "koKR", "enUS", "zhTW", "deDE", "frFR", "esES" }
ns.LANGUAGE_NAMES = {
    koKR = "한국어", enUS = "English", zhTW = "繁體中文",
    deDE = "Deutsch", frFR = "Français", esES = "Español",
}

-- 언어 코드 → 번역 표 (한국어면 nil = 원문 그대로)
local function Resolve(lang)
    if not lang or lang == "auto" then lang = GetLocale() end
    if lang == "esMX" then lang = "esES" end
    if lang == "zhCN" then lang = "zhTW" end
    if lang == "koKR" then return nil end
    return T[lang] or T.enUS
end

local current = Resolve("auto")
local L = {}
-- 번역이 없으면 영어, 그것도 없으면 한국어 원문
setmetatable(L, { __index = function(t, k)
    local v = current and (current[k] or T.enUS[k]) or k
    rawset(t, k, v)
    return v
end })
ns.L = L

-- 저장된 언어 설정 적용 (애드온이 읽힌 직후, 화면을 만들기 전에 부름)
function ns:ApplyLanguage(lang)
    current = Resolve(lang)
    for k in pairs(L) do L[k] = nil end
end''')
open('Locales.lua','w',encoding='utf-8').write('\n'.join(out)+'\n')
print('locales', len(keys))
