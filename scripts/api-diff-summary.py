#!/usr/bin/env python3
"""
Build a Markdown summary of api-diff.sh results for posting to GitHub.

Usage:
    api-diff-summary.py <reports-dir> <baseline-ref> [<run-url>]

Reads every <Module>.diff.txt under <reports-dir>, applies the same classifier
and ignore-list rules used by api-diff.sh, and prints Markdown on stdout.
"""
import glob
import os
import re
import sys

BREAKING_SECTIONS = {
    "Removed Decls",
    "Renamed Decls",
    "Type Changes",
    "Class Inheritance Change",
    "Protocol Requirement Change",
    "Generic Signature Changes",
}
ATTR_PHRASES = (
    "is now throwing",
    "is no longer throwing",
    "is now not class",
    "is no longer class",
    "is now not static",
    "is no longer static",
)
IGNORE_FILE = os.environ.get("API_BREAK_IGNORE_FILE", "scripts/api-break-ignore.txt")
COMMENT_MARKER = "<!-- api-diff-comment -->"
LINE_RE = re.compile(r"^([A-Za-z_][\w]*)(?:\(([^)]+)\))?:\s*(.+)$")
HEADER_RE = re.compile(r"^/\*\s+(.*?)\s+\*/\s*$")


def load_ignore_patterns():
    pats = []
    if os.path.isfile(IGNORE_FILE):
        with open(IGNORE_FILE) as f:
            for raw in f:
                s = raw.strip()
                if s and not s.startswith("#"):
                    try:
                        pats.append(re.compile(s, re.IGNORECASE))
                    except re.error:
                        pass
    return pats


def classify_module(path, ignore_patterns):
    section = None
    breaks, ignored = [], []
    with open(path) as f:
        for raw in f:
            line = raw.rstrip("\n")
            m = HEADER_RE.match(line)
            if m:
                section = m.group(1)
                continue
            if not line.strip():
                continue
            is_break = (
                section in BREAKING_SECTIONS
                or (section == "Protocol Conformance Change" and "removed conformance to" in line)
                or (section == "Decl Attribute changes" and any(p in line for p in ATTR_PHRASES))
            )
            if not is_break:
                continue
            entry = (section, line)
            if any(p.search(line) for p in ignore_patterns):
                ignored.append(entry)
            else:
                breaks.append(entry)
    return breaks, ignored


def parse_break_line(raw):
    m = LINE_RE.match(raw)
    if not m:
        return None, None, raw
    return m.group(1), m.group(2) or "", m.group(3)


def render(reports_dir, baseline, run_url):
    patterns = load_ignore_patterns()
    modules = []
    total_break = 0
    total_ignored = 0
    for diff_path in sorted(glob.glob(os.path.join(reports_dir, "*.diff.txt"))):
        m = os.path.basename(diff_path)[: -len(".diff.txt")]
        breaks, ignored = classify_module(diff_path, patterns)
        if breaks or ignored:
            modules.append((m, breaks, ignored))
            total_break += len(breaks)
            total_ignored += len(ignored)

    out = [COMMENT_MARKER, ""]
    out.append(f"### Public API Diff vs `{baseline}`")
    out.append("")
    if total_break == 0:
        out.append("**Result:** :white_check_mark: No breaking changes")
        if total_ignored:
            out.append(f"  ({total_ignored} ignored by `{IGNORE_FILE}`)")
    else:
        plural_b = "s" if total_break != 1 else ""
        plural_m = "s" if len(modules) != 1 else ""
        out.append(
            f"**Result:** :x: {total_break} breaking change{plural_b} in "
            f"{len(modules)} module{plural_m}"
            + (f" ({total_ignored} ignored)" if total_ignored else "")
        )
    out.append("")
    for module, breaks, ignored in modules:
        if not breaks and not ignored:
            continue
        head = f"<b>{module}</b> — "
        head += f"{len(breaks)} breaking" if breaks else "0 breaking"
        if ignored:
            head += f", {len(ignored)} ignored"
        out.append(f"<details open><summary>{head}</summary>\n")
        if breaks:
            out.append("| Section | Symbol | File |")
            out.append("|---|---|---|")
            for section, line in breaks:
                _, basename, msg = parse_break_line(line)
                msg = msg.replace("|", "\\|")
                file_disp = f"`{basename}`" if basename else "_(none)_"
                # Truncate over-long messages so the comment stays readable.
                if len(msg) > 200:
                    msg = msg[:197] + "..."
                out.append(f"| {section} | {msg} | {file_disp} |")
            out.append("")
        if ignored:
            out.append("**Ignored** (matched `scripts/api-break-ignore.txt`):")
            for _, line in ignored:
                _, _, msg = parse_break_line(line)
                if len(msg) > 200:
                    msg = msg[:197] + "..."
                out.append(f"- {msg}")
            out.append("")
        out.append("</details>\n")
    if run_url:
        out.append(f"[View workflow run]({run_url})")
    return "\n".join(out).rstrip() + "\n", total_break


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: api-diff-summary.py <reports-dir> <baseline-ref> [<run-url>]")
    reports_dir = sys.argv[1]
    baseline = sys.argv[2]
    run_url = sys.argv[3] if len(sys.argv) > 3 else ""
    text, _ = render(reports_dir, baseline, run_url)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
