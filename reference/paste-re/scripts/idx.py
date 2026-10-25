import plistlib,sys
def load(p):
    with open(p,'rb') as f: return plistlib.load(f)['$objects']
def d(o,v): return o[v.data] if isinstance(v,plistlib.UID) else v
def txt(o,v):
    x=d(o,v)
    if isinstance(x,str): return x
    if isinstance(x,dict):
        for k in ('NS.string','NS.bytes'):
            if k in x: return txt(o,x[k])
    return x
def arr(o,v):
    x=d(o,v)
    if isinstance(x,dict):
        for k in ('NS.objects','NS.keys'):
            if k in x: return [d(o,y) for y in x[k]]
    return []
o=load(sys.argv[1]); root=o[1]
for e in arr(o,root['NSEntities']):
    if not isinstance(e,dict): continue
    nm=txt(o,e.get('NSEntityName'))
    idx=arr(o,e.get('NSFetchIndexDescriptions'))
    print('==',nm,'indexes=',len(idx))
    for i in idx:
        if not isinstance(i,dict): continue
        iname=txt(o,i.get('NSIndexName'))
        els=arr(o,i.get('NSElements'))
        cols=[]
        for el in els:
            if isinstance(el,dict):
                cols.append(txt(o,el.get('NSPartialIndexPredicate') or el.get('NSPropertyName') or el.get('NSElementName')))
        print('   idx',iname,cols)
        for el in els:
            if isinstance(el,dict):
                print('      keys:',[k for k in el.keys() if k!='$class'])
