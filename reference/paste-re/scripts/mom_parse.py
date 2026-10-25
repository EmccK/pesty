import plistlib, sys, json

def ref_index(v):
    if isinstance(v, plistlib.UID):
        return v.data
    if isinstance(v, dict) and 'CF$UID' in v:
        return v['CF$UID']
    return None

def load_objs(path):
    d = plistlib.load(open(path,'rb'))
    return d['$objects']

def cls_of(objs, o):
    i = ref_index(o.get('$class'))
    if i is None: return None
    return objs[i].get('$classname')

ATTR_TYPES = {
 100:'int16',200:'int32',300:'int64',400:'decimal',500:'double',600:'float',
 700:'string',800:'date?',900:'date',1000:'data',1100:'binary',1200:'uuid',
 1800:'uri',2000:'transformable',2100:'objectID'}

def parse(path):
    objs = load_objs(path)
    model = None
    for o in objs:
        if isinstance(o, dict) and 'NSEntities' in o and '$archiver' not in o:
            model = o; break
    ents = objs[ref_index(model['NSEntities'])]
    keys = [objs[ref_index(k)] for k in ents['NS.keys']]
    vals = [ref_index(v) for v in ents['NS.objects']]
    out = {}
    for name, eidx in zip(keys, vals):
        ent = objs[eidx]
        props_ref = objs[ref_index(ent['NSProperties'])]
        pkeys = [objs[ref_index(k)] for k in props_ref['NS.keys']]
        pvals = [ref_index(v) for v in props_ref['NS.objects']]
        props = []
        for pname, pidx in zip(pkeys, pvals):
            p = objs[pidx]
            cls = cls_of(objs, p)
            if cls == 'NSAttributeDescription':
                t = p.get('NSAttributeType')
                props.append(('attr', pname, ATTR_TYPES.get(t, f'type{t}'),
                              'optional' if p.get('NSIsOptional') else 'required'))
            elif cls == 'NSRelationshipDescription':
                props.append(('rel', pname,
                              p.get('_NSDestinationEntityName'),
                              f"min={p.get('NSMinCount')} max={p.get('NSMaxCount')} "
                              f"inverse={p.get('_NSInverseRelationshipName')} delete={p.get('NSDeleteRule')}"))
            else:
                props.append(('?', pname, cls, ''))
        cname = ent.get('NSClassNameForEntity')
        out[name] = {
            'class': objs[ref_index(cname)] if ref_index(cname) is not None else cname,
            'uniqueTuples': ent.get('NSUniqueTuples'),
            'indexes': [objs[ref_index(i)].get('NSIndexName') for i in (objs[ref_index(ent['NSFetchIndexDescriptions'])].get('NS.objects') or [])] if ent.get('NSFetchIndexDescriptions') else [],
            'props': props,
        }
    return out

if __name__ == '__main__':
    for path in sys.argv[1:]:
        print('='*72); print(path); print('='*72)
        for name, info in parse(path).items():
            print(f"\n## {name}  (class={info['class']})")
            if info['uniqueTuples']:
                print('   UNIQUE:', info['uniqueTuples'])
            if info['indexes']:
                print('   INDEX :', [i for i in info['indexes'] if i])
            for kind, pname, a, b in info['props']:
                print(f'   {kind:4} {str(pname):34} {str(a):26} {b}')
