import json, re, sys
sys.path.insert(0,'.')
WANT = {'fishing_loot_template','gameobject','gameobject_template','pool_gameobject','pool_template',
        'reference_loot_template','skill_fishing_base_level','pool_pool','item_template','gameobject_loot_template'}
exec(open('parse_sql.py').read().split('cols = {}')[0].split('WANT =')[0])  # brings tuples()
import importlib
def tuples(s):
    i, n = 0, len(s); out = []
    while i < n:
        if s[i] != '(':
            i += 1; continue
        i += 1; row = []; cur = ''; inq = False
        while i < n:
            c = s[i]
            if inq:
                if c == '\\': cur += s[i+1]; i += 2; continue
                if c == "'": inq = False; i += 1; continue
                cur += c; i += 1; continue
            if c == "'": inq = True; i += 1; continue
            if c == ',': row.append(cur.strip()); cur = ''; i += 1; continue
            if c == ')': row.append(cur.strip()); i += 1; break
            cur += c; i += 1
        out.append(row)
    return out
data = {t: {'cols': None, 'rows': []} for t in WANT}
cur = None; buf = []
with open('vdb/x/world_full_14_june_2021.sql', encoding='utf-8', errors='replace') as f:
    for line in f:
        if cur is None:
            m = re.match(r'INSERT INTO `(\w+)` \((.*?)\) VALUES\s*(.*)$', line)
            if m and m.group(1) in WANT:
                cur = m.group(1)
                data[cur]['cols'] = [c.strip(' `') for c in m.group(2).split(',')]
                buf = [m.group(3)]
                if line.rstrip().endswith(';'):
                    data[cur]['rows'].extend(tuples(''.join(buf))); cur = None
            continue
        buf.append(line)
        if line.rstrip().endswith(';'):
            data[cur]['rows'].extend(tuples(''.join(buf))); cur = None
for t in WANT: print(t, len(data[t]['rows']), (data[t]['cols'] or [])[:7])
json.dump(data, open('vtables.json','w'))
