#!/usr/bin/env python3
"""
Shared classifier for swift-api-digester -diagnose-sdk output.

Imported by api-diff-summary.py and api-diff-annotate.py; invoked as a CLI by
api-diff.sh's classify_report. Single source of truth for what counts as a
breaking change, the ignore-list mechanism, and the report-layout constants.

Subcommands:
    classify <module> <report-path> [<ignore-file>]
        Print one summary line per module, exit 1 on break, 0 otherwise.
"""
import os
import re
import sys

BREAKING_SECTIONS = frozenset(
    {
        "Removed Decls",
        "Renamed Decls",
        "Type Changes",
        "Class Inheritance Change",
        "Protocol Requirement Change",
        "Generic Signature Changes",
    }
)
ATTR_PHRASES = (
    "is now throwing",
    "is no longer throwing",
    "is now not class",
    "is no longer class",
    "is now not static",
    "is no longer static",
)
LINE_RE = re.compile(r"^([A-Za-z_][\w]*)(?:\(([^)]+)\))?:\s*(.+)$")
HEADER_RE = re.compile(r"^/\*\s+(.*?)\s+\*/\s*$")
DEFAULT_IGNORE_FILE = "scripts/api-break-ignore.txt"
TOOL_FAILED_SENTINEL = ".tool-failed"


def ignore_file_path():
    return os.environ.get("API_BREAK_IGNORE_FILE", DEFAULT_IGNORE_FILE)


def load_ignore_patterns(path=None):
    if path is None:
        path = ignore_file_path()
    pats = []
    if not os.path.isfile(path):
        return pats
    with open(path) as f:
        for raw in f:
            s = raw.strip()
            if not s or s.startswith("#"):
                continue
            try:
                pats.append(re.compile(s, re.IGNORECASE))
            except re.error as e:
                sys.stderr.write(f"warning: bad regex in {path}: {s} ({e})\n")
    return pats


def is_breaking(section, line):
    if section in BREAKING_SECTIONS:
        return True
    if section == "Protocol Conformance Change" and "removed conformance to" in line:
        return True
    if section == "Decl Attribute changes" and any(p in line for p in ATTR_PHRASES):
        return True
    return False


def classify_module(diff_path, ignore_patterns):
    section = None
    breaks, ignored, nonbreaks = [], [], []
    with open(diff_path) as f:
        for raw in f:
            line = raw.rstrip("\n")
            m = HEADER_RE.match(line)
            if m:
                section = m.group(1)
                continue
            if not line.strip():
                continue
            if not is_breaking(section, line):
                nonbreaks.append((section or "(no section)", line))
                continue
            entry = (section, line)
            if any(p.search(line) for p in ignore_patterns):
                ignored.append(entry)
            else:
                breaks.append(entry)
    return breaks, ignored, nonbreaks


def parse_break_line(raw):
    m = LINE_RE.match(raw)
    if not m:
        return None, None, raw
    return m.group(1), m.group(2) or "", m.group(3)


def cmd_classify(argv):
    if len(argv) < 2:
        sys.exit("usage: api_diff_classify.py classify <module> <report-path> [<ignore-file>]")
    module, path = argv[0], argv[1]
    ignore = argv[2] if len(argv) > 2 else None
    patterns = load_ignore_patterns(ignore)
    breaks, ignored, nonbreaks = classify_module(path, patterns)
    tail = f", {len(ignored)} ignored" if ignored else ""
    if breaks:
        print(f"[BREAK] {module}: {len(breaks)} breaking, {len(nonbreaks)} additive/other{tail}")
        return 1
    if nonbreaks or ignored:
        print(f"[ok]    {module}: {len(nonbreaks)} additive/other change(s){tail}")
    else:
        print(f"[ok]    {module}: no changes")
    return 0


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: api_diff_classify.py <subcommand> [args...]")
    sub, rest = sys.argv[1], sys.argv[2:]
    if sub == "classify":
        sys.exit(cmd_classify(rest))
    sys.exit(f"unknown subcommand: {sub}")


if __name__ == "__main__":
    main()
