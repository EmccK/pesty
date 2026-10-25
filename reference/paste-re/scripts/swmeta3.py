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
def u32(v):
    o=fo(v); return struct.unpack_from('<I',d,o)[0] if o is not None else None
def i32(v):
    o=fo(v); return struct.unpack_from('<i',d,o)[0] if o is not None else None
def u64(v):
    o=fo(v); return struct.unpack_from('<Q',d,o)[0] if o is not None else None
def cstr(v,limit=400):
    o=fo(v)
    if o is None: return None
    e=d.find(b'\0',o,min(o+limit,len(d)))
    if e<0: return None
    try: return d[o:e].decode()
    except: return None
# 尝试 ABI 顺序：flags, parent, name, accessFn, fields, superclassType, metadataNegativeSizeInWords,
# metadataPositiveSizeInWords, numImmediateMembers, numFields
TARGETS={'SearchBar':0x100ce69e4,'SearchField':0x100ce6b00,'TabBar':0x100ce7c00,'TabBarCell':0x100ce73e8,'Toolbar':0x100ce5dc4,'FilterView':0x100ce6ac4}
for name,desc in TARGETS.items():
    o=fo(desc)
    flags,pa,na,fu,fl,sc = struct.unpack_from('<IiiIII', d, o)
    nego, poso, immo, numfo = struct.unpack_from('<iiii', d, o+28)
    finfo = desc+20+fl
    rec = None
    if fo(finfo) is not None:
        frflags,kind,layout,ftype = struct.unpack_from('<HHHI', d, fo(finfo))
        rec=(hex(frflags), kind, layout, 'type+t=%d'%ftype)
    print(f'{name:14s} neg={nego:3d} pos={poso:3d} imm={immo:3d} numFields={numfo:3d} fieldInfo@{hex(finfo)} rec={rec}')
