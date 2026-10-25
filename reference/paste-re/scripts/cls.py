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
def vsz(v):
    for nm,vm,vs,fof,fs in SG:
        if vs and vm<=v<vm+vs: return vm+vs
    return None
def cstr(v,limit=200):
    o=fo(v)
    if o is None: return None
    end=min(o+limit, len(d))
    e=d.find(b'\0',o,end)
    if e<0: return None
    try: return d[o:e].decode()
    except: return None
def mask(v): return v & 0x7fffffffff
names={}
target='_TtC5Paste11SearchField'
for i in range(839):
    raw=struct.unpack_from('<Q',d,16375320+i*8)[0]
    cands=[raw & 0x7fffffffff, raw & 0xfffffffff, (raw & 0x7fffffffff)+0x100000000]
    hit=False
    for cand in cands:
        o=fo(cand)
        if o is None: continue
        for ro_raw in (struct.unpack_from('<Q',d,o+32)[0],):
            for rm in (ro_raw & 0x7fffffffff, (ro_raw&0x7fffffffff)+0x100000000):
                o2=fo(rm)
                if o2 is None: continue
                np=struct.unpack_from('<Q',d,o2+24)[0]
                for nmv in (np & 0x7fffffffff, (np&0x7fffffffff)+0x100000000):
                    s=cstr(nmv)
                    if s==target:
                        print('FOUND idx',i,'raw',hex(raw),'cls',hex(cand),'ro',hex(rm),'name',hex(nmv))
                        hit=True
    if hit: break
