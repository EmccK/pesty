import struct
d=open('/tmp/paste-arm64','rb').read()
B=17235968
# struct dyld_chained_fixups_header { u32 fixups_version; u32 starts_offset; u32 imports_offset; u32 symbols_offset; u32 imports_count; u32 imports_format; u32 symbols_format; }
fixups_version, starts_offset, imports_offset, symbols_offset, imports_count, imports_format, symbols_format = struct.unpack_from('<IIIIIII', d, B)
print('version',fixups_version,'starts',starts_offset,'imports',imports_offset,'syms',symbols_offset,'count',imports_count,'ifmt',imports_format,'sfmt',symbols_format)
# starts_in_image
S=B+starts_offset
seg_count,seg_info_offset0=struct.unpack_from('<II',d,S)
print('seg_count',seg_count, 'info_off0', seg_info_offset0)
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
    o=struct.unpack_from('<I',d,S+4+i*4)[0]
    if o==0: 
        print(f'  seg{i} (no fixups)'); continue
    SI=S+o
    page_size,=struct.unpack_from('<H',d,SI)
    seg_offset,=struct.unpack_from('<Q',d,SI+2)
    max_valid,=struct.unpack_from('<H',d,SI+10)
    page_count,=struct.unpack_from('<H',d,SI+12)
    print(f'  seg{i} {segs[i][0]} page_size={page_size} seg_offset={hex(seg_offset)} pages={page_count}')
