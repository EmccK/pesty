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
def target_fn(desc, slot):
    """desc+16 = target function pointer (relative). slot = immediate member index"""
    rel=struct.unpack_from('<i', d, fo(desc)+16)[0]
    fn=desc+16+rel
    # jump table 在 fn 前
    return fn, slot
def describe(name, desc):
    o=fo(desc)
    flags,pa,na,fu,fl,sc = struct.unpack_from('<IiiIII', d, o)
    numImm = struct.unpack_from('<i', d, o+28)[0]
    rel=struct.unpack_from('<i', d, o+16)[0]
    fn=desc+16+rel
    jt=fn - numImm*4
    entries=[]
    for i in range(numImm):
        e=struct.unpack_from('<i', d, fo(jt)+i*4)[0]
        if e==0: entries.append(None)
        else: entries.append(jt + i*4 + e)
    print(f'=== {name}  imm={numImm} jumptable={hex(jt)} fn={hex(fn)}')
    return entries, jt
for name,desc in (('SearchBar',0x100ce69e4),('SearchField',0x100ce6b00),('TabBar',0x100ce7c00),('TabBarCell',0x100ce73e8),('Toolbar',0x100ce5dc4)):
    describe(name, desc)
