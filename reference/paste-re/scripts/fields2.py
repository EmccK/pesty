import struct, subprocess
data=open('/tmp/paste-arm64','rb').read()
BASE=0x100000000
SECTIONS={
 '__swift5_reflstr':(0x100d67b50,0x232d7),
 '__swift5_fieldmd':(0x100d8ae28,0x2a828),
}
REFL=range(SECTIONS['__swift5_reflstr'][0], sum(SECTIONS['__swift5_reflstr']))
FMSTART,FMSIZE=SECTIONS['__swift5_fieldmd']
def cstr(addr):
    if addr not in REFL: return None
    o=addr-BASE; e=data.index(b'\0',o)
    return data[o:e].decode('utf-8','replace')

# Walk fieldmd scanning for field records: 12-byte records whose FieldName delta resolves into reflstr.
records={}
for off in range(FMSTART, FMSTART+FMSIZE-12, 4):
    v,=struct.unpack_from('<i',data,off-BASE)
    target=off+4+v          # FieldName field is at record_start+8; record_start=off-4
    name=cstr(target)
    if not name: continue
    if not (name[0].isalpha() or name[0]=='_'): continue
    mt,=struct.unpack_from('<i',data,off-4-BASE)   # mangledTypeName at record_start+4
    mtaddr=off+mt
    mangled=cstr(mtaddr)
    if not mangled or not mangled.startswith('$'): continue
    flags,=struct.unpack_from('<I',data,off-8-BASE)
    if flags>0xFFFF: continue
    records.setdefault(off-4, []).append((flags,name,mangled))

def demangle(syms):
    syms=[s for s in syms if s]
    if not syms: return {}
    p=subprocess.run(['xcrun','swift-demangle','--simplified'],input='\n'.join(syms),capture_output=True,text=True)
    return dict(zip(syms,p.stdout.splitlines()))

alltypes=[]
for k,recs in records.items():
    for f,n,m in recs: alltypes.append(m)
dm=demangle(sorted(set(alltypes)))
print('field records:',sum(len(v) for v in records.values()))
import sys
targets=sys.argv[1:]
for k,recs in sorted(records.items()):
    nice=dm.get(recs[0][2],recs[0][2])
    if targets and not any(t in nice for t in targets): continue
    print(f'\n## {nice}')
    for f,n,m in recs:
        print(f'   {n:34} {dm.get(m,m)}')
