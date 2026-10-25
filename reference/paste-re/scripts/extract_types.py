import struct, subprocess

out = subprocess.check_output(['otool','-l','paste-arm64'], text=True)
sects, cur = {}, None
for line in out.splitlines():
    s = line.strip()
    if s.startswith('sectname '):
        cur = s.split()[1]
        sects.setdefault(cur, {'addr': 0, 'size': 0, 'offset': 0})
    elif cur:
        if s.startswith('addr '):   sects[cur]['addr']   = int(s.split()[1], 0)
        elif s.startswith('size '): sects[cur]['size']   = int(s.split()[1], 0)
        elif s.startswith('offset '): sects[cur]['offset'] = int(s.split()[1], 0); cur = None

t = sects['__swift5_types']
off, size, va = t['offset'], t['size'], t['addr']
data = open('paste-arm64','rb').read()
print(f"__swift5_types: file_off={off} vmaddr=0x{va:x} size={size} records={size//4}")

def va2off(a):
    return off + (a - va)

targets = [va + i + struct.unpack_from('<i', data, off+i)[0] for i in range(0, size, 4)]
names = set()
for a in targets:
    fo = va2off(a)
    if not (0 <= fo < len(data)-12): continue
    name_rel = struct.unpack_from('<i', data, fo+8)[0]
    np_ = a + 8 + name_rel
    npf = va2off(np_)
    if not (0 <= npf < len(data)): continue
    end = data.find(b'\x00', npf, npf+256)
    if end < 0: continue
    names.add(data[npf:end].decode('utf-8','replace'))

uniq = sorted(names)
print(f"去重后 {len(uniq)} 个类型名 -> paste_typenames.txt")
open('paste_typenames.txt','w').write('\n'.join(uniq))
for n in uniq[:20]: print(' ', n)
