import struct, subprocess, sys
data=open('/tmp/paste-arm64','rb').read()
BASE=0x100000000
REFL_START,REFL_SIZE=0x100d67b50,0x232d7
FM_START,FM_SIZE=0x100d8ae28,0x2a828
REFL_END=REFL_START+REFL_SIZE
def cstr(addr):
    if not (REFL_START<=addr<REFL_END): return None
    o=addr-BASE
    try: e=data.index(b'\0',o)
    except ValueError: return None
    s=data[o:e]
    try: return s.decode('utf-8')
    except UnicodeDecodeError: return None

descs=[]
off=FM_START
end=FM_START+FM_SIZE
while off+16<=end:
    mt,sup=struct.unpack_from('<ii',data,off-BASE)
    kind,recsize=struct.unpack_from('<HH',data,off+8-BASE)
    num,=struct.unpack_from('<I',data,off+12-BASE)
    if recsize not in (12,) or num>500:
        off+=4; continue
    tn=cstr(off+mt)
    if tn is None or not tn.startswith('$'):
        off+=4; continue
    fields=[]
    ok=True
    for i in range(num):
        rs=off+16+i*recsize
        fn,ft,fl=struct.unpack_from('<iiI',data,rs-BASE)
        n=cstr(rs+fn); t=cstr(rs+ft)
        if n is None or t is None: ok=False; break
        fields.append((n,t,fl))
    if not ok: continue
    descs.append((off,kind,tn,fields))
    off=off+16+num*recsize

def demangle(syms):
    syms=[s for s in syms if s]
    if not syms: return {}
    p=subprocess.run(['xcrun','swift-demangle','--simplified'],input='\n'.join(syms),capture_output=True,text=True)
    return dict(zip(syms,p.stdout.splitlines()))
dm=demangle([t for _,_,t,_ in descs])
print('descriptors:',len(descs))
if __name__=='__main__':
    pats=sys.argv[1:]
    for off,kind,tn,fields in descs:
        nice=dm.get(tn,tn)
        if pats and not any(p in nice for p in pats): continue
        print(f'\n## kind={kind} {nice}')
        for n,t,fl in fields:
            print(f'   {n:34} {dm.get(t,t)}')
