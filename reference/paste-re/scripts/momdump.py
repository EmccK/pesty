import plistlib,sys

def load(path):
    with open(path,'rb') as f: d=plistlib.load(f)
    return d['$objects']

def d(objs,v):
    if isinstance(v, plistlib.UID): return objs[v.data]
    return v

def txt(objs,v):
    o=d(objs,v)
    if isinstance(o,str): return o
    if isinstance(o,dict):
        for k in ('NS.string','NS.bytes'):
            if k in o: return txt(objs,o[k])
    return o

def arr(objs,v):
    o=d(objs,v)
    if isinstance(o,dict):
        for k in ('NS.objects','NS.keys'):
            if k in o: return [d(objs,x) for x in o[k]]
    return []

def main(path):
    objs=load(path)
    root=objs[1]
    ents=arr(objs, root['NSEntities'])
    print(f'=== {path}  entities={len(ents)} ===')
    for e in ents:
        if not isinstance(e,dict): continue
        name=txt(objs,e.get('NSEntityName') or e.get('name'))
        parent=txt(objs,e.get('NSParentEntityName')) if 'NSParentEntityName' in e else None
        abstract=e.get('NSIsAbstract')
        print(f'\n--- Entity: {name}  parent={parent} abstract={abstract}')
        for key in ('NSProperties','properties'):
            if key in e:
                props=arr(objs,e[key]); break
        else:
            props=[]
        for p in props:
            if not isinstance(p,dict): continue
            cls=d(objs,p.get('$class'))
            cname=cls.get('$classname') if isinstance(cls,dict) else None
            pname=txt(objs,p.get('NSPropertyName') or p.get('name'))
            if cname and 'Attribute' in str(cname):
                typ=p.get('NSAttributeType')
                opt=p.get('NSIsOptional')
                print(f'    attr  {pname:32} type={typ} optional={opt}')
            elif cname and 'Relationship' in str(cname):
                dst=txt(objs,p.get('NSDestinationEntityName')) if 'NSDestinationEntityName' in p else None
                toMany=p.get('NSIsToMany') or p.get('NSMaxCount')
                inv=p.get('NSInverseRelationshipName')
                invn=txt(objs,inv) if inv is not None else None
                print(f'    rel   {pname:32} -> {dst}  toMany={toMany} inverse={invn}')
            else:
                print(f'    ?     {pname:32} class={cname}')
        # uniqueness constraints
        for key in ('NSUniquenessConstraints','NSUniquenessConstraint','NSEntityUniquenessConstraints'):
            if key in e:
                print('    UNIQUE:', [ [txt(objs,x) for x in arr(objs,c)] for c in arr(objs,e[key]) ])
        for k in e:
            if 'nique' in k:
                print('    rawkey',k,'=',e[k])
main(sys.argv[1])
