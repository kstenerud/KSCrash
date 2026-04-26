#!/usr/bin/env python3
"""
Filter a swift-api-digester JSON dump in place to keep only declarations that
are part of the Swift-facing API surface, dropping pure-C declarations
(free functions, C structs, plain typedefs).

A top-level decl is kept iff it satisfies any of:
    - has `objc_name` set (Obj-C @interface / @protocol / @property / NS_ENUM)
    - has "ObjC" in declAttributes
    - has "SynthesizedProtocol" in declAttributes (NS_OPTIONS imported as
      Swift OptionSet — Swift synthesises OptionSet/RawRepresentable conformance)

Usage:
    api-diff-filter-c.py <module>.json
"""
import json
import sys


def is_swift_facing(decl):
    if decl.get("objc_name"):
        return True
    attrs = decl.get("declAttributes") or []
    return "ObjC" in attrs or "SynthesizedProtocol" in attrs


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: api-diff-filter-c.py <json-path>")
    path = sys.argv[1]
    with open(path) as f:
        data = json.load(f)
    root = data.get("ABIRoot") or data
    children = root.get("children", [])
    kept = [c for c in children if is_swift_facing(c)]
    dropped = len(children) - len(kept)
    root["children"] = kept
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    sys.stderr.write(
        f"   filter-c: kept {len(kept)}/{len(children)} (dropped {dropped} pure-C) in {path}\n"
    )


if __name__ == "__main__":
    main()
