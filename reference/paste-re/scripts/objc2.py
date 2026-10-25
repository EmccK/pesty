import struct
d=open('/tmp/paste-arm64','rb').read()
def parse():
    magic,cpu,sub,ftype,ncmds,size,flags,res=struct.unpack_from('<IiiIIIII',d,0)
    off=32; out=[]
    for _ in range(ncmds):
        cmd,cmdsize=struct.unpack_from('<II',d,off)
        if cmd==0x19:
            nsects=struct.unpack_from('<I',d,off+64)[0]; so=off+72
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
def u64(vo):
    o=fo(vo); return struct.unpack_from('<Q',d,o)[0] if o is not None else None
def u32(vo):
    o=fo(vo); return struct.unpack_from('<I',d,o)[0] if o is not None else None
def i32(vo):
    o=fo(vo); return struct.unpack_from('<i',d,o)[0] if o is not None else None
def cstr(vo,limit=200):
    o=fo(vo)
    if o is None: return None
    e=d.find(b'\0',o,o+limit)
    if e<0: return None
    try: return d[o:e].decode()
    except: return None
names=[]
for sname,saddr,ssize,sfoff in secs:
    if sname!='__objc_classlist': continue
    for i in range(ssize//8):
        cls=struct.unpack_from('<Q',d,sfoff+i*8)[0]
        ro=u64(cls+32)
        if ro is None: continue
        flags=u32(ro); 
        namePtr=u64(ro+24)
        if namePtr is None: continue
        nm=cstr(namePtr)
        if nm: names.append(nm)
print('class count', len(names))
for n in sorted(set(names)): print(' ', n)
