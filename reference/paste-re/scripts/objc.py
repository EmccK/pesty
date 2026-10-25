import struct
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
for s in secs:
    if 'objc' in s[0] or 'swift5' in s[0]: print(s)
