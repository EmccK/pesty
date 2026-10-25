import struct
d=open('/tmp/paste-arm64','rb').read()
def parse_segs():
    magic,cpu,sub,ftype,ncmds,size,flags,res=struct.unpack_from('<IiiIIIII',d,0)
    off=32; out=[]
    for _ in range(ncmds):
        cmd,cmdsize=struct.unpack_from('<II',d,off)
        if cmd==0x19:
            nm=d[off+8:off+24].rstrip(b'\0').decode()
            vmaddr,vmsize,fileoff,filesize=struct.unpack_from('<QQQQ',d,off+24)
            out.append((nm,vmaddr,vmsize,fileoff,filesize))
        off+=cmdsize
    return out
SG=parse_segs()
def fo(v):
    for nm,vm,vs,fof,fs in SG:
        if vs and vm<=v<vm+vs: return fof+(v-vm)
    return None
def cstr_at(foff,limit=300):
    e=d.find(b'\0',foff,min(foff+limit,len(d)))
    if e<0: return None
    try: return d[foff:e].decode()
    except: return None
def cstr_vo(v,limit=300):
    o=fo(v)
    return cstr_at(o,limit) if o is not None else None
for label,finfo,num in (('SearchBar',0x100d8be28,12),('SearchField',0x100d8bfb0,13),('TabBar',0x100d8cdf4,10),('Toolbar',0x100d8b254,16)):
    print(f'=== {label}')
    rec=finfo
    for i in range(num):
        ro=fo(rec)
        if ro is None: break
        flags=struct.unpack_from('<I',d,ro)[0]
        trel=struct.unpack_from('<i',d,ro+4)[0]
        nrel=struct.unpack_from('<i',d,ro+8)[0]
        nm=cstr_vo(rec+8+nrel)
        print(f'  [{i:2d}] name={nm!r}')
        rec+=12
