#!/usr/bin/env python3
"""
Emit GitHub workflow-command annotations for api-diff breaking changes.

Usage:
    api-diff-annotate.py <reports-dir>

Walks every <Module>.diff.txt under <reports-dir>, applies the same classifier
and ignore-list rules used by api-diff-summary.py, and prints one
::error file=...,line=...,title=...:: line per actionable break.
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from api_diff_classify import (  # noqa: E402
    classify_module,
    load_ignore_patterns,
    parse_break_line,
)


def resolve(module, basename):
    if not basename:
        return None
    for cand in glob.glob(f"Sources/{module}/**/{basename}", recursive=True):
        return cand
    for cand in glob.glob(f"Sources/**/{basename}", recursive=True):
        return cand
    return None


def emit(props, msg):
    attrs = ",".join(f"{k}={v}" for k, v in props.items() if v)
    msg = msg.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error {attrs}::{msg}")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: api-diff-annotate.py <reports-dir>")
    reports_dir = sys.argv[1]
    patterns = load_ignore_patterns()
    total = 0
    for path in sorted(glob.glob(os.path.join(reports_dir, "*.diff.txt"))):
        module = os.path.basename(path)[: -len(".diff.txt")]
        breaks, _, _ = classify_module(path, patterns)
        for section, line in breaks:
            mod, basename, msg = parse_break_line(line)
            mod = mod or module
            file_path = resolve(mod, basename) if basename else None
            props = {"title": f"API break in {mod}"}
            if file_path:
                props["file"] = file_path
                props["line"] = "1"
            emit(props, f"[{section}] {msg}")
            total += 1
    print(f"::notice::Annotated {total} breaking change(s); see Files changed for inline highlights.")


if __name__ == "__main__":
    main()
