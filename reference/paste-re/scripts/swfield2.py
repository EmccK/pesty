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
def cstroff(v,limit=300):
    o=fo(v)
    if o is None: return None
    e=d.find(b'\0',o,min(o+limit,len(d)))
    if e<0: return None
    try: return d[o:e].decode()
    except: return None
# ContextDescriptor 公共前缀：flags(u32) parent(i32)
# StructDescriptor: flags,parent,name(rel),accessFn(rel),fields(rel)
# ClassDescriptor : flags,parent,name(rel),accessFn(rel),fields(rel),superclassType(rel),metadataNeg,
#                   metadataPos, numImmediateMembers, numFields(?)  ← 实测顺序见下
def read_desc(desc, is_class):
    o=fo(desc)
    flags,pa,na,fu,fl = struct.unpack_from('<Iiiii', d, o)
    name=cstroff(desc+8+na) if na else None
    finfo=desc+20+fl
    vals=struct.unpack_from('<iiii', d, o+24)  # sc, neg, pos, imm
    return name, finfo, vals
for label,desc in (('SearchBar',0x100ce69e4),('SearchField',0x100ce6b00),('TabBar',0x100ce7c00),('Toolbar',0x100ce5dc4)):
    name,finfo,vals=read_desc(desc, True)
    o=fo(finfo)
    fflags,kind,layout=struct.unpack_from('<HHI', d, o)
    numFields=struct.unpack_from('<I', d, o+8)[0]
    fn=desc+20+(finfo-desc-20)  # placeholder
    print(f'=== {name}  finfo={hex(finfo)} fflags={hex(fflags)} kind={hex(kind)} layout={layout} numFields={numFields}')
    # 依次读取 record
    rec=finfo+16
    for i in range(numFields):
        ro=fo(rec)
        if ro is None: break
        rf=struct.unpack_from('<I', d, ro)[0]
        # FieldRecord: flags(4) mangledTypeName(rel 4) fieldName(rel 4)
        tn=struct.unpack_from('<i', d, ro+4)[0]
        fnrel=struct.unpack_from('<i', d, ro+8)[0]
        fname=cstroff(rec+8+fnrel)
        print(f'   [{i}] flags={hex(rf)} name={fname!r}')
        rec = rec+12
