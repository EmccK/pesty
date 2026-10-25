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
def cstr(v,limit=400):
    o=fo(v)
    if o is None: return None
    e=d.find(b'\0',o,min(o+limit,len(d)))
    if e<0: return None
    try: return d[o:e].decode()
    except: return None
def hexdump(v,n=64):
    o=fo(v)
    return d[o:o+n].hex() if o is not None else None
def dump_method_names(desc):
    """Swift 类的方法名存在 __swift5_reflstr，通过 fieldmd 顺序访问"""
    pass
TARGETS={'SearchBar':0x100ce69e4,'SearchField':0x100ce6b00,'TabBar':0x100ce7c00,'Toolbar':0x100ce5dc4}
for name,desc in TARGETS.items():
    o=fo(desc)
    flags,pa,na,fu,fl = struct.unpack_from('<IiiII', d, o)
    print(f'=== {name} desc={hex(desc)}')
    print('  raw:', d[o:o+48].hex())
    # 试猜测：flags, parent(+4), name(+8), accessFn(+12/+16?), fields, superclassType, metalNeg, metalPos, numImmediateMembers
    for off in range(12, 44, 4):
        print(f'   +{off}: {struct.unpack_from("<i", d, o+off)[0]}')
