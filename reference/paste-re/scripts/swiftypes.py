import struct, subprocess, re, sys

BIN = "/Applications/Paste.app/Contents/MacOS/Paste"
out = subprocess.run(["otool","-l",BIN], capture_output=True, text=True).stdout
data = open(BIN,'rb').read()

# parse sections with size
secs = {}
cur = {}; seg=None
for line in out.splitlines():
    s=line.strip()
    if s.startswith("sectname"): cur['name']=s.split()[1]
    elif s.startswith("segname"): seg=s.split()[1]; cur['seg']=seg
    elif s.startswith("addr") and 'name' in cur: cur['addr']=int(s.split()[1],16)
    elif s.startswith("size") and 'addr' in cur:
        cur['size']=int(s.split()[1],16)
        secs[cur['name']]=(cur['seg'],cur['addr'],cur['size']); cur={}
seg_info={}
for m in re.finditer(r'segname (\S+)\n\s+vmaddr (0x[0-9a-f]+)\n\s+vmsize (0x[0-9a-f]+)\n\s+fileoff (\d+)\n\s+filesize (\d+)', out):
    seg_info[m.group(1)]=(int(m.group(2),16),int(m.group(4)),int(m.group(5),16))

def foff(a):
    for s,(va,fo,fs) in seg_info.items():
        if va<=a<va+fs: return fo+(a-va)
    return None
def rd(a,n):
    o=foff(a); return data[o:o+n] if o is not None else b''
def i32(a): return struct.unpack('<i',rd(a,4))[0]
def u32(a): return struct.unpack('<I',rd(a,4))[0]
def cstr(a):
    o=rd(a,1024); z=o.find(b'\0')
    return o[:z].decode('utf-8','replace')

def parse_ctx(addr):
    flags=u32(addr); kind=flags&0x1F
    if kind in (1,):  # class: parent at +4
        pass
    prel=i32(addr+4)
    parent=addr+4+prel if prel else 0
    nrel=i32(addr+8)
    name=cstr(addr+8+nrel) if nrel else ''
    return parent,name

def full(addr,d=0):
    parts=[]
    while addr and d<12:
        p,n=parse_ctx(addr)
        if n: parts.append(n)
        addr=p; d+=1
    return '.'.join(reversed(parts))

names=[]
for key in ('__swift5_types','__swift5_types2'):
    if key not in secs: continue
    seg,base,size=secs[key]
    for off in range(0,size,4):
        a=base+off
        r=i32(a)
        if r==0: continue
        tgt=a+r
        try:
            nm=full(tgt)
        except Exception:
            continue
        if nm: names.append(nm)
names=sorted(set(names))
print("types:",len(names))
open('/tmp/paste_types.txt','w').write('\n'.join(names))
