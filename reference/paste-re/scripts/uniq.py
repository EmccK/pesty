import plistlib,sys
def load(p):
    with open(p,'rb') as f: return plistlib.load(f)['$objects']
def d(o,v):
    return o[v.data] if isinstance(v,plistlib.UID) else v
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
    for k,v in e.items():
        if 'nique' in k:
            t=d(o,v)
            print('==',nm,k,type(t).__name__)
            def walk(x,ind=1):
                if isinstance(x,dict):
                    for kk,vv in x.items():
                        if kk in ('NS.objects','NS.keys'):
                            for y in vv: walk(d(o,y),ind+1)
                        elif kk=='NS.string': print(' '*ind+'str:',x[kk])
                        else: walk(vv,ind+1)
                elif isinstance(x,list):
                    for y in x: walk(y,ind)
                else: print(' '*ind+repr(x))
            walk(t)
