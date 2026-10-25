import struct
d=open('/tmp/paste-arm64','rb').read()
D=0x100000000  # file offset + D = vmaddr for __TEXT/__DATA (both)
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
def cstr(v,limit=200):
    o=fo(v)
    if o is None: return None
    e=d.find(b'\0',o,min(o+limit,len(d)))
    if e<0: return None
    try: return d[o:e].decode()
    except: return None
names=[]
CL=16375320
for i in range(839):
    raw=struct.unpack_from('<Q',d,CL+i*8)[0]
    cls=raw & 0xfffffffff  # 36 bit
    o=fo(cls)
    if o is None: continue
    # class_t: isa(8) super(8) cache(8) vtable(8) data(8) -> ro at +32
    ro=struct.unpack_from('<Q',d,o+32)[0] & 0xfffffffff
    o2=fo(ro)
    if o2 is None: continue
    np=struct.unpack_from('<Q',d,o2+24)[0] & 0xfffffffff
    nm=cstr(np)
    if nm: names.append(nm)
print('resolved', len(names))
for n in sorted(set(names)):
    if '_TtC' in n or any(k in n for k in ('Search','TabBar','Toolbar','Filter','Pinboard')):
        print('  ', n)
