import struct, subprocess, sys
data=open('/tmp/paste-arm64','rb').read()
BASE=0x100000000
def cstr_at(addr):
    off=addr-BASE
    if off<0 or off>=len(data): return None
    try: end=data.index(b'\0',off)
    except ValueError: return None
    return data[off:end].decode('utf-8','replace')

def parse_fields():
    start,size=0x100d8ae28,0x2a828
    off=start; end=start+size
    out=[]
    while off+16<=end:
        try:
            mt,sup=struct.unpack_from('<ii',data,off-BASE)
            kind,recsize=struct.unpack_from('<HH',data,off+8-BASE)
            num,=struct.unpack_from('<I',data,off+12-BASE)
        except struct.error: break
        if recsize==0 or num>2000:
            off+=4; continue
        type_name=cstr_at(off+mt)
        names=[];p=off+16;ok=True
        for _ in range(num):
            try: fl,mtn,fnoff=struct.unpack_from('<Iii',data,p-BASE)
            except struct.error: ok=False;break
            names.append((cstr_at(p+fnoff), cstr_at(p+mtn)))
            p+=recsize
        if not ok: break
        out.append((off, kind, type_name, names))
        off=off+16+num*recsize
    return out

def demangle(syms):
    syms=[s for s in syms if s and s.startswith('$s')]
    if not syms: return {}
    p=subprocess.run(['xcrun','swift-demangle','--simplified'],input='\n'.join(syms),capture_output=True,text=True)
    lines=p.stdout.splitlines()
    return dict(zip(syms,lines))

if __name__=='__main__':
    fd=parse_fields()
    print('descriptors:',len(fd))
    dm=demangle([t for _,_,t,_ in fd])
    targets=sys.argv[1:]
    for off,kind,t,names in fd:
        nice=dm.get(t,t)
        if targets and not any(x in (nice or '') for x in targets): continue
        if not targets and not names: continue
        print(f'\n## {nice}')
        for fn,ft in names:
            print(f'   {fn:32} {ft}')
