import struct, subprocess, sys
data=open('/tmp/paste-arm64','rb').read()
BASE=0x100000000
def cstr_at(addr):
    off=addr-BASE
    if off<0 or off>=len(data): return None
    try: end=data.index(b'\0',off)
    except ValueError: return None
    return data[off:end].decode('utf-8','replace')

def fields():
    start,size=0x100d8ae28,0x2a828
    off=start; end=start+size
    res=[]
    while off < end:
        try:
            mt,sup=struct.unpack_from('<ii',data,off-BASE)
            kind,recsize=struct.unpack_from('<HH',data,off+8-BASE)
            num,=struct.unpack_from('<I',data,off+12-BASE)
        except struct.error:
            break
        if recsize==0 or num>3000:
            off+=4; continue
        names=[]; p=off+16; ok=True
        for _ in range(num):
            try:
                fl,mtn,fnoff=struct.unpack_from('<Iii',data,p-BASE)
            except struct.error:
                ok=False;break
            names.append((cstr_at(p+fnoff), cstr_at(p+mtn)))
            p+=recsize
        if not ok: break
        res.append((off+mt, names))
        off=off+16+num*recsize
    return res

def demangle(syms):
    if not syms: return []
    p=subprocess.run(['xcrun','swift-demangle','--simplified'],input='\n'.join(syms),
                     capture_output=True,text=True)
    return p.stdout.splitlines()

fd=fields()
mangled=[m for m,_ in fd if m]
dem=demangle(mangled)
targets=sys.argv[1:] or ['ItemRepository','Item']
for (m,names),d in zip(fd,dem):
    if any(t in d for t in targets):
        print(f'\n## {d}   [{m}]')
        for fn,ft in names:
            print(f'   {fn:34} {ft}')
