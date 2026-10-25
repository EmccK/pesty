import struct
data=open('/tmp/paste-arm64','rb').read()
BASE=0x100000000
def cstr_at(addr):
    off=addr-BASE
    if off<0 or off>=len(data): return None
    try: end=data.index(b'\0',off)
    except ValueError: return None
    return data[off:end].decode('utf-8','replace')

def swift_types():
    start,size=0x100dc34c8,0x3378
    out={}
    for i in range(size//4):
        rel,=struct.unpack_from('<i',data,start-BASE+i*4)
        addr=start+i*4+rel
        flags,=struct.unpack_from('<I',data,addr-BASE)
        kind=flags&0x1f
        nameoff,=struct.unpack_from('<i',data,addr+8-BASE)
        nm=cstr_at(addr+8+nameoff)
        out[addr]=(kind,nm)
    return out

KIND={0:'class',1:'struct',2:'enum',3:'protocol',4:'extension',5:'anonymous',6:'opaque'}

def fields():
    start,size=0x100d8ae28,0x2a828
    off=start; end=start+size
    res={}
    while off < end:
        try:
            mt,sup=struct.unpack_from('<ii',data,off-BASE)
            kind,recsize=struct.unpack_from('<HH',data,off+8-BASE)
            num,=struct.unpack_from('<I',data,off+12-BASE)
        except struct.error:
            break
        if recsize==0 or num>2000:
            off+=4; continue
        names=[]
        p=off+16
        ok=True
        for _ in range(num):
            try:
                fl,mtn,fnoff=struct.unpack_from('<Iii',data,p-BASE)
            except struct.error:
                ok=False;break
            fn=cstr_at(p+fnoff)
            names.append((fn, cstr_at(p+mtn)))
            p+=recsize
        if not ok: break
        parent=off+mt  # mangled type name offset is relative to field descriptor start
        res[parent]=names
        off=off+16+num*recsize
    return res

if __name__=='__main__':
    types=swift_types(); f=fields()
    print('field descriptors:',len(f))
    want=['ItemRepository','ItemRepositoryItemUpdate','Item','ListRepository','PasteboardItem','Pasteboard','ItemType','ListType','ListAttributes','PinboardAttributes','ClipboardAttributes','ItemSerializationFormat','HashAlgorithm','ItemRepositoryError','PasteboardItemComposer','SearchableItemEntity','PasteboardCapture','ItemDataEntity','ListData','ListUpdate','ItemClass']
    for addr,(k,nm) in types.items():
        if nm in want and addr in f:
            print(f'\n## {KIND.get(k,k)} {nm}')
            for fn,ft in f[addr]:
                print(f'   {fn}  ::  {ft}')
