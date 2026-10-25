import struct
d=open('/tmp/paste-arm64','rb').read()
BASE=17235968
# starts_in_image
voff=struct.unpack_from('<i',d,BASE+0)[0]
ssize,page=struct.unpack_from('<HH',d,BASE+4)
seg_count=struct.unpack_from('<I',d,BASE+6)[0]
seginfo_off=struct.unpack_from('<I',d,BASE+10)[0]
print('starts_in_image', voff, 'segs', seg_count, 'seginfo_off', seginfo_off)
seginfo_off+= BASE
imports=[]
ISF=BASE+voff
# 收集 segments vmaddr/fo
def parse_segs():
    magic,cpu,sub,ftype,ncmds,size,flags,res=struct.unpack_from('<IiiIIIII',d,0)
    off=32; out=[]
    for _ in range(ncmds):
        cmd,cmdsize=struct.unpack_from('<II',d,off)
        if cmd==0x19:
            name=d[off+8:off+24].rstrip(b'\0').decode()
            vmaddr,vmsize,fileoff,filesize=struct.unpack_from('<QQQQ',d,off+24)
            out.append((name,vmaddr,vmsize,fileoff,filesize))
        off+=cmdsize
    return out
segs=parse_segs()
for i in range(seg_count):
    off,page_start,seg_index,psize=struct.unpack_from('<IHHI',d,seginfo_off+i*8)
    name,vm,vs,fof,fs = segs[seg_index]
    print(f'  seg{seg_index} {name} page_start={page_start} psize={psize} off={off} vm={hex(vm)}')
