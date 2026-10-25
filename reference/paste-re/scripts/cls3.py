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
def cstr(v,limit=200):
    o=fo(v)
    if o is None: return None
    e=d.find(b'\0',o,min(o+limit,len(d)))
    if e<0: return None
    try: return d[o:e].decode()
    except: return None
TARGET=0x100dc7030
# 扫 __DATA_CONST.__objc_const (vm 4311400448 fo 16433152 size 267768)
base_vm=4311400448; base_fo=16433152; size=267768
found=[]
for p in range(0, size-8, 4):
    v=struct.unpack_from('<Q', d, base_fo+p)[0]
    if v==TARGET:
        found.append(base_fo+p)
print('exact hits', [(hex(x), hex(x+0x100000000)) for x in found])
# 也许 name 字段存的是 (file_offset + 0x100000000) 也就是 "chained fixup already rebased"
