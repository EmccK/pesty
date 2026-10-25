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
    if nm not in ('ItemEntity','ListEntity'): continue
    print('=====',nm)
    for p in arr(o,e.get('NSProperties')):
        if not isinstance(p,dict): continue
        cls=d(o,p.get('$class')); cn=cls.get('$classname') if isinstance(cls,dict) else None
        if 'Relationship' not in str(cn): continue
        pn=txt(o,p.get('NSPropertyName'))
        print(' REL',pn)
        for k,v in p.items():
            if k in ('$class',): continue
            t=d(o,v)
            if isinstance(t,dict):
                inner={kk:(txt(o,vv) if kk.startswith('NS') and not kk.startswith('NS.objects') else vv) for kk,vv in t.items() if kk!='$class'}
                print('    ',k,'=',inner)
            else:
                print('    ',k,'=',repr(t))
