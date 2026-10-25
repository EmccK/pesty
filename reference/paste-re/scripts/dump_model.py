#!/usr/bin/env python3
"""Dump a Core Data .mom (compiled NSManagedObjectModel) into readable text.

Paste ships its schema as a versioned model bundle:
  /Applications/Paste.app/Contents/Resources/PastePackages_PasteCore.bundle/Contents/Resources/v5Paste.momd/
The .mom files are plain binary plists keyed by NSKeyedArchiver, so no Xcode and no
execution of the app are needed.

Usage:
    python3 dump_model.py <path/to/model.mom> [more.mom ...]

Output sections per model: entities, attributes (with Core Data type names),
relationships (destination / cardinality / optionality / delete rule / inverse),
uniqueness constraints, and fetch indexes.
"""
import plistlib
import sys

ATTR_TYPES = {
    100: "Int16",
    200: "Int32",
    300: "Int64",
    400: "Decimal",
    500: "Double",
    600: "Float",
    700: "String",
    800: "Bool",
    900: "Date",
    1000: "Binary",
    1100: "UUID",
    1200: "URI",
    1800: "Transformable",
}

DELETE_RULES = {0: "NoAction", 1: "Nullify", 2: "Cascade", 3: "Deny"}


def deref(objects, value):
    return objects[value.data] if isinstance(value, plistlib.UID) else value


def text(objects, value):
    obj = deref(objects, value)
    if isinstance(obj, str):
        return obj
    if isinstance(obj, dict):
        for key in ("NS.string", "NS.bytes"):
            if key in obj:
                return text(objects, obj[key])
    return obj


def items(objects, value):
    obj = deref(objects, value)
    if isinstance(obj, dict):
        for key in ("NS.objects", "NS.keys"):
            if key in obj:
                return [deref(objects, entry) for entry in obj[key]]
    return []


def class_name(objects, value):
    obj = deref(objects, value)
    if isinstance(obj, dict):
        return obj.get("$classname")
    return None


def scalar(objects, value):
    """Resolve a value that may be wrapped in an NSKeyedArchiver reference."""
    obj = deref(objects, value)
    if isinstance(obj, dict):
        for key in ("NS.string", "NS.bytes"):
            if key in obj:
                return scalar(objects, obj[key])
        if "NS.objects" in obj:
            return [scalar(objects, entry) for entry in obj["NS.objects"]]
    return obj


def dump(path):
    with open(path, "rb") as handle:
        archive = plistlib.load(handle)
    objects = archive["$objects"]
    root = objects[1]

    print(f"=== {path} ===")
    version = scalar(objects, root.get("NSVersionIdentifiers"))
    print(f"compiler tool version: {scalar(objects, root.get('CDMCompilerToolVersion'))}")
    print(f"compiler Xcode version: {scalar(objects, root.get('CDMCompilerXcodeVersion'))}")
    print(f"version identifiers: {version}")
    print()

    entities = [e for e in items(objects, root["NSEntities"]) if isinstance(e, dict)]
    print(f"entities: {len(entities)}")
    for entity in entities:
        name = text(objects, entity.get("NSEntityName"))
        entity_class = text(objects, entity.get("NSClassNameForEntity"))
        print(f"\n--- {name} (class {entity_class})")

        props = [p for p in items(objects, entity.get("NSProperties")) if isinstance(p, dict)]
        for prop in props:
            prop_name = text(objects, prop.get("NSPropertyName"))
            kind = class_name(objects, prop.get("$class")) or ""
            if "Attribute" in kind:
                raw_type = scalar(objects, prop.get("NSAttributeType"))
                type_name = ATTR_TYPES.get(raw_type, f"raw={raw_type}")
                print(
                    f"    attr  {prop_name:<28} {type_name:<14}"
                    f" optional={scalar(objects, prop.get('NSIsOptional'))}"
                )
            elif "Relationship" in kind:
                dest = text(objects, prop.get("_NSDestinationEntityName")) or text(
                    objects, prop.get("NSDestinationEntityName")
                )
                max_count = scalar(objects, prop.get("NSMaxCount"))
                rule = scalar(objects, prop.get("NSDeleteRule"))
                inverse = text(objects, prop.get("_NSInverseRelationshipName")) or text(
                    objects, prop.get("NSInverseRelationshipName")
                )
                cardinality = "to-many" if max_count is None or max_count == 0 else "to-one"
                print(
                    f"    rel   {prop_name:<28} -> {dest:<20} {cardinality:<8}"
                    f" optional={scalar(objects, prop.get('NSIsOptional'))}"
                    f" delete={DELETE_RULES.get(rule, rule)}"
                    f" inverse={inverse}"
                )
            else:
                print(f"    ?     {prop_name:<28} class={kind}")

        for key in ("NSUniqueTuples",):
            if key in entity:
                tuples = scalar(objects, entity[key])
                print(f"    UNIQUE {tuples}")

        for index in items(objects, entity.get("NSFetchIndexDescriptions")):
            if not isinstance(index, dict):
                continue
            index_name = text(objects, index.get("NSIndexName"))
            elements = [
                (
                    text(objects, element.get("NSPropertyName")),
                    scalar(objects, element.get("NSAscending")),
                )
                for element in items(objects, index.get("NSIndexElements"))
                if isinstance(element, dict)
            ]
            predicate = scalar(objects, index.get("NSPartialIndexPredicate"))
            print(f"    INDEX {index_name}: {elements} partial={predicate}")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    for path in argv[1:]:
        dump(path)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
