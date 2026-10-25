import struct, subprocess, sys, re

BIN = "/Applications/Paste.app/Contents/MacOS/Paste"

# get sections
out = subprocess.run(["otool","-l",BIN], capture_output=True, text=True).stdout
secs = {}
cur = None
for line in out.splitlines():
    line = line.strip()
    if line.startswith("sectname"):
        cur = line.split()[1]
    elif line.startswith("segname") and cur:
        seg = line.split()[1]
    elif line.startswith("addr") and cur:
        secs[cur] = (seg, int(line.split()[1],16))
        cur = None
print("sections:", {k:(v[0],hex(v[1])) for k,v in secs.items() if 'swift5' in k}, file=sys.stderr)

data = open(BIN,'rb').read()
# file offset == vmaddr for __TEXT in dylibs/exes with standard layout; verify via __TEXT vmaddr 0
# find __TEXT segment vmaddr
seg_info = {}
for m in re.finditer(r'segname (\S+)\n\s+vmaddr (0x[0-9a-f]+)\n\s+vmsize (0x[0-9a-f]+)\n\s+fileoff (\d+)\n\s+filesize (\d+)', out):
    seg_info[m.group(1)] = (int(m.group(2),16), int(m.group(4)))
print("segs:", {k:(hex(a),o) for k,(a,o) in seg_info.items()}, file=sys.stderr)

def read(addr, n):
    # translate vmaddr -> file offset
    for seg,(va,fo) in seg_info.items():
        if va <= addr < va + 0x40000000:
            # find filesize
            return data[fo + (addr-va): fo + (addr-va) + n]
    return b''

def u32(addr): return struct.unpack('<I', read(addr,4))[0]
def i32(addr): return struct.unpack('<i', read(addr,4))[0]

def cstr(addr):
    o = read(addr, 512)
    z = o.find(b'\0')
    return o[:z].decode('utf-8','replace')

