import plistlib,sys

def load(path):
    with open(path,'rb') as f: d=plistlib.load(f)
    return d['$objects']

def deref(objs, v):
    if isinstance(v, plistlib.UID):
        return objs[v.data]
    return v

def resolve(objs, v, depth=0):
    """Return plain python for a keyed-archive value."""
    if isinstance(v, plistlib.UID):
        return resolve(objs, objs[v.data], depth+1)
    if isinstance(v, dict):
        return {k: resolve(objs,x,depth+1) for k,x in v.items()}
    if isinstance(v, list):
        return [resolve(objs,x,depth+1) for x in v]
    return v

if __name__=='__main__':
    objs=load(sys.argv[1])
    print('objects:', len(objs))
    for i,o in enumerate(objs[:6]):
        print(i, repr(o)[:200])
