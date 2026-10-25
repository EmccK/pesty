import struct
d=open('/tmp/paste-arm64','rb').read()
B=17235968
fixups_version, starts_offset, imports_offset, symbols_offset, imports_count, imports_format, symbols_format = struct.unpack_from('<IIIIIII', d, B)
S=B+starts_offset
seg_count,=struct.unpack_from('<I',d,S)
def segs():
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
SG=segs()
def fo(vo):
    for nm,vm,vs,fof,fs in SG:
        if vs and vm<=vo<vm+vs: return fof+(vo-vm)
    return None
def u32(a):
    return struct.unpack_from('<I',d,a)[0]
CACHE={}
def fixups_for_seg(i):
    o=u32(S+4+i*4)
    if o==0: return None
    SI=S+o
    page_size=struct.unpack_from('<H',d,SI)[0]
    seg_offset=struct.unpack_from('<Q',d,SI+2)[0]
    max_valid=struct.unpack_from('<H',d,SI+10)[0]
    page_count=struct.unpack_from('<H',d,SI+12)[0]
    pg=SI+22
    pages=[]
    for p in range(page_count):
        start=struct.unpack_from('<H',d,pg+p*2)[0]
        pages.append(start)
    return dict(page_size=page_size, seg_offset=seg_offset, page_count=page_count, pages=pages, page_start=pg+page_count*2, seg=i)
def resolve(vo):
    # 找到所在段
    for i,(nm,vm,vs,fof,fs) in enumerate(SG):
        if vs and vm<=vo<vm+vs:
            info=fixups_for_seg(i)
            if not info: return None
            rel=vo-info['seg_offset']
            page=rel//info['page_size']
            if page>=info['page_count']: return None
            raw=info['pages'][page]
            start=info['page_start']+raw+ (rel % info['page_size'])
            o=fo(info['seg_offset']+page*info['page_size']+(rel%info['page_size']))
            chain=struct.unpack_from('<Q',d,o)[0]
            return dict(chain=chain, page=page, seg=nm)
    return None
r=resolve(0x100000010105b8)
print(r)
# 拆 arm64e auth/rebase
c=r['chain']
print('bind?', (c>>62), ' next', (c>>51)&0xfff)
if (c>>62)==0:
    target = c & 0x7ffffffffff
    print('rebase target', hex(target))
