import struct, re
d=open('/tmp/paste-arm64','rb').read()
def parse():
    magic,cpu,sub,ftype,ncmds,size,flags,res=struct.unpack_from('<IiiIIIII',d,0)
    off=32; out=[]
    for _ in range(ncmds):
        cmd,cmdsize=struct.unpack_from('<II',d,off)
        if cmd==0x19:
            nsects=struct.unpack_from('<I',d,off+64)[0]
            so=off+72
            for i in range(nsects):
                sname=d[so:so+16].rstrip(b'\0').decode()
                saddr,ssize=struct.unpack_from('<QQ',d,so+32)
                sfoff=struct.unpack_from('<I',d,so+48)[0]
                out.append((sname,saddr,ssize,sfoff)); so+=80
        off+=cmdsize
    return out
secs=parse()
def fo(vo):
    for sname,saddr,ssize,sfoff in secs:
        if ssize and saddr<=vo<saddr+ssize: return sfoff+(vo-saddr)
    return None
def cstr(vo,limit=160):
    o=fo(vo)
    if o is None: return None
    e=d.find(b'\0',o,o+limit)
    if e<0: return None
    try: return d[o:e].decode()
    except: return None
def uint32(vo):
    o=fo(vo)
    return struct.unpack_from('<I',d,o)[0] if o is not None else None
def int32(vo):
    o=fo(vo)
    return struct.unpack_from('<i',d,o)[0] if o is not None else None
out={}
for sname,saddr,ssize,sfoff in secs:
    if sname not in ('__swift5_types','__swift5_types2'): continue
    for i in range(ssize//4):
        item=saddr+i*4
        rel=struct.unpack_from('<i',d,sfoff+i*4)[0]
        desc=item+rel
        flags=uint32(desc)
        if flags is None: continue
        kind=flags & 0x1f
        parent=desc+ (int32(desc+4) or 0)  # 相对偏移实际以字段地址为基
        # 正确：parent 字段地址 = desc+4
        prel=int32(desc+4)
        parent=desc+4+prel if prel else 0
        nrel=int32(desc+8); nameAddr=desc+8+nrel if nrel else 0
        nm=cstr(nameAddr) if nameAddr else None
        if nm: out.setdefault(kind,[]).append(nm)
tot=0
for k in sorted(out):
    tot+=len(out[k])
print('kinds', {k:len(v) for k,v in out.items()}, 'total', tot)
for n in sorted(set(out.get(17,[]))):
    print(' 17 ', n)

# ObjC 可见的 Swift 类：从 __objc_classlist 解析
print('\n=== ObjC-visible Swift classes ===')
objs=[]
for sname,saddr,ssize,sfoff in secs:
    if sname!='__objc_classlist': continue
    for i in range(ssize//8):
        cls=struct.unpack_from('<Q',d,sfoff+i*8)[0]
        # class_ro_t: isa(u64) superclass(u64) cache(u64) vtable(u64) data(u64)
        o=fo(cls)
        if o is None: continue
        isa,sup,cache,vt,ro=struct.unpack_from('<QQQQQ',d,o)
        o2=fo(ro)
        if o2 is None: continue
        flags,instStart,instSize,ivarLayout,namePtr,baseMethods,baseProto,ivars,weak,fields=struct.unpack_from('<IIIIQQQQQQ',d,o2)
        nm=cstr(namePtr)
        objs.append(nm)
for n in sorted(set(x for x in objs if x)): print('  ', n)
