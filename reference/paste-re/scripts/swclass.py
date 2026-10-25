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
def cstr(v,limit=300):
    o=fo(v)
    if o is None: return None
    e=d.find(b'\0',o,min(o+limit,len(d)))
    if e<0: return None
    try: return d[o:e].decode()
    except: return None
VM=4309398728; SZ=13176; FO=14431432
TARGETS={'SearchBar':0x100ce69e4,'SearchField':0x100ce6b00,'TabBar':0x100ce7c00,'Toolbar':0x100ce5dc4,'TabBarCell':0x100ce73e8,'TabBarCellIcon':0x100ce5fbc,'FilterView':0x100ce6ac4}
for name,desc in TARGETS.items():
    o=fo(desc)
    flags,pa,na,fu,fl = struct.unpack_from('<IiiII', d, o)
    # ClassDescriptor: flags,parent,name,accessFunction,fields,superclassType,metadataNegativeSize,metadataPositiveSize...
    afo=fo(desc+16+fu) if fu else None
    fields=struct.unpack_from('<i', d, o+20)[0]
    sct=struct.unpack_from('<i', d, o+24)[0]
    print(f'--- {name} desc={hex(desc)} flags={hex(flags)} accessFn+={fu} fields+={fields} superclassType+={sct}')
    # superclassType 是相对指针
    if sct:
        st=desc+24+sct
        print('    superclassType ref ->', hex(st), cstr(st) if fo(st) else None)
