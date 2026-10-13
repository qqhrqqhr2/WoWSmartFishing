import json, re, csv, collections, math
T = json.load(open('vtables.json'))
def rows(t):
    c = T[t]['cols']; return [dict(zip(c, r)) for r in T[t]['rows']]

Z = 'qdb/support/Forever/Zones/'
def lua_map(path, varname):
    s = open(path, encoding='utf-8').read()
    m = re.search(re.escape(varname) + r' = \[\[return \{(.*?)\}\]\]', s, re.S)
    return {int(a): int(b) for a, b in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', m.group(1))}
a2m = lua_map(Z + 'areaIdToUiMapId.lua', 'ZoneDB.private.areaIdToUiMapId')
a2m.update(lua_map(Z + 'areaIdToUiMapId.lua', 'ZoneDB.private.areaIdToUiMapIdOverride'))
sub2p = lua_map(Z + 'subZoneToParentZone.lua', 'ZoneDB.private.subZoneToParentZone')
sub2p.update(lua_map(Z + 'subZoneToParentZone.lua', 'ZoneDB.private.subZoneToParentZoneOverride'))

# Era -> Forever 좌표 보정 (일부 지역 지도 크기 변경)
s = open('qdb/src/support/eraToForever.lua', encoding='utf-8').read()
xf = {int(a): tuple(map(float, b.split(','))) for a, b in re.findall(r'\[(\d+)\] = \{ ([^}]*) \}', s.split('local uiMapToArea')[0])}

# 지역 경계
bounds = {}
with open('questie/ExternalScripts(DONOTINCLUDEINRELEASE)/WorldMapArea_Classic.csv', encoding='utf-8') as f:
    for r in csv.DictReader(f):
        aid = int(r['AreaId']); mid = int(r['MapId'])
        if aid == 0 or mid not in (0, 1): continue
        L, R, Tp, B = (float(r[k].replace(',', '.')) for k in ('LocLeft', 'LocRight', 'LocTop', 'LocBottom'))
        bounds[aid] = (mid, L, R, Tp, B, r['AreaName'])

def zone_of(area):
    seen = 0
    while area not in a2m and area in sub2p and seen < 6:
        area = sub2p[area]; seen += 1
    return area

def to_forever(aid, x, y):
    if aid in xf:
        sx, ox, sy, oy = xf[aid]
        x, y = x * sx + ox, y * sy + oy
    return x, y

items = {r['entry']: r for r in rows('item_template')}

# 지역별 낚시 전리품 -------------------------------------------------------------
fl = collections.defaultdict(list)
for r in rows('fishing_loot_template'):
    if int(r.get('patch_max') or 10) < 10: continue
    if int(r['condition_id']) != 0: continue
    if float(r['ChanceOrQuestChance']) < 0: continue
    if int(r['mincountOrRef']) < 0: continue
    fl[int(r['entry'])].append(r)

def dist(rs):
    groups = collections.defaultdict(list); out = collections.Counter()
    for r in rs: groups[int(r['groupid'])].append(r)
    for g, lst in groups.items():
        if g == 0:
            for r in lst: out[int(r['item'])] += float(r['ChanceOrQuestChance'])
            continue
        explicit = sum(float(r['ChanceOrQuestChance']) for r in lst)
        zeros = [r for r in lst if float(r['ChanceOrQuestChance']) == 0]
        rest = max(0.0, 100.0 - explicit)
        for r in lst:
            c = float(r['ChanceOrQuestChance'])
            out[int(r['item'])] += c if c > 0 else rest / len(zeros)
    return out

skill = {int(r['entry']): int(r['skill']) for r in rows('skill_fishing_base_level')}
def skill_of(area):
    seen = 0
    while area not in skill and area in sub2p and seen < 6:
        area = sub2p[area]; seen += 1
    return skill.get(area)

zones, subzones = {}, {}
for area, rs in fl.items():
    if area == 0: continue
    d = dist(rs)
    fish = sorted(((i, p) for i, p in d.items() if p >= 0.1), key=lambda t: -t[1])
    if not fish: continue
    sk = skill_of(area)
    entry = {'s': (sk + 95) if sk is not None else None, 'f': fish}
    if area in a2m and area not in sub2p:
        zones[a2m[area]] = entry
    else:
        z = zone_of(area)
        if z in a2m:
            entry['m'] = a2m[z]; subzones[area] = entry
print('zones', len(zones), 'subzones', len(subzones))

# 물고기 떼 ------------------------------------------------------------------------
gt = {r['entry']: r for r in rows('gameobject_template') if r['type'] == '25'}
gl = collections.defaultdict(list)
for r in rows('gameobject_loot_template'):
    if int(r['mincountOrRef']) >= 0 and float(r['ChanceOrQuestChance']) >= 0: gl[r['entry']].append(r)
def pool_fish(entry):
    lst = gl.get(gt[entry]['data1'], [])
    d = dist(lst)
    if not d: return None
    return max(d.items(), key=lambda t: t[1])[0]

KIND = {'Floating Wreckage': 'wreckage', 'Floating Debris': 'debris', 'Oil Spill': 'oil',
        'Patch of Elemental Water': 'water', 'Muddy Churning Waters': 'muddy'}
types, type_index = [], {}
pools = collections.defaultdict(list)
miss = 0
for r in rows('gameobject'):
    if r['id'] not in gt or r['map'] not in ('0', '1'): continue
    if int(r.get('patch_max') or 10) < 10: continue
    name = gt[r['id']]['name']
    key = name
    if key not in type_index:
        type_index[key] = len(types) + 1
        types.append({'name': name, 'kind': KIND.get(name, 'school'), 'fish': pool_fish(r['id'])})
    t = type_index[key]
    if types[t - 1]['fish'] is None: types[t - 1]['fish'] = pool_fish(r['id'])
    px, py, mid = float(r['position_x']), float(r['position_y']), int(r['map'])
    best = None
    for aid, (bm, L, R, Tp, B, nm) in bounds.items():
        if bm != mid or aid not in a2m: continue
        x = (L - py) / (L - R) * 100; y = (Tp - px) / (Tp - B) * 100
        if 0 <= x <= 100 and 0 <= y <= 100:
            # 가장자리에서 먼 지역을 고름 (겹치는 지역 경계 문제 방지)
            score = min(x, 100 - x, y, 100 - y)
            if best is None or score > best[0]: best = (score, aid, x, y)
    if not best or best[0] < 1: miss += 1; continue
    _, aid, x, y = best
    x, y = to_forever(aid, x, y)
    pools[a2m[aid]].append((t, round(x, 1), round(y, 1)))
# 같은 자리 중복 제거
for k in pools: pools[k] = sorted(set(pools[k]))
print('pool types', len(types), 'pools', sum(len(v) for v in pools.values()), 'maps', len(pools), 'unassigned', miss)
for t in types: print(' ', t['name'], t['kind'], t['fish'], items.get(str(t['fish']), {}).get('name'))

# Lua 출력 ------------------------------------------------------------------------
def flist(f): return '{' + ','.join('%d,%s' % (i, ('%.2f' % p).rstrip('0').rstrip('.')) for i, p in f) + '}'
out = []
out.append('-- 자동 생성 파일: 기본 낚시 데이터 (클래식 1.12 기준, 와우 포에버 지도 번호로 변환)')
out.append('-- 수정하지 마세요. tools/build_data.py 로 다시 만듭니다.')
out.append('local ADDON, ns = ...')
out.append('local D = {}')
out.append('ns.Data = D')
out.append('')
out.append('-- [지도 번호] = { s = 권장 숙련(놓치지 않는 숙련), f = { 아이템ID, 확률%, ... } }')
out.append('D.zones = {')
for m in sorted(zones):
    e = zones[m]
    out.append('    [%d] = { s = %s, f = %s },' % (m, e['s'] if e['s'] is not None else 'nil', flist(e['f'])))
out.append('}')
out.append('')
out.append('-- 세부 지역: [지역 ID] = { m = 지도 번호, s = 권장 숙련, f = {...} }')
out.append('D.subzones = {')
for a in sorted(subzones):
    e = subzones[a]
    out.append('    [%d] = { m = %d, s = %s, f = %s },' % (a, e['m'], e['s'] if e['s'] is not None else 'nil', flist(e['f'])))
out.append('}')
out.append('')
out.append('-- 물고기 떼 종류: kind = school(물고기 떼) / wreckage / debris / oil / water / muddy, fish = 주로 나오는 아이템')
out.append('D.poolTypes = {')
for i, t in enumerate(types, 1):
    out.append('    [%d] = { kind = "%s", fish = %s }, -- %s' % (i, t['kind'], t['fish'] or 'nil', t['name']))
out.append('}')
out.append('')
out.append('-- 물고기 떼 출현 지점: [지도 번호] = { 종류, x%, y%, 종류, x%, y%, ... }')
out.append('D.pools = {')
for m in sorted(pools):
    flat = ','.join('%d,%s,%s' % (t, ('%.1f' % x).rstrip('0').rstrip('.'), ('%.1f' % y).rstrip('0').rstrip('.')) for t, x, y in pools[m])
    out.append('    [%d] = {%s},' % (m, flat))
out.append('}')
open('Data.lua', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('bytes', len('\n'.join(out)))
