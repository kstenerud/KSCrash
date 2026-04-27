#!/usr/bin/env python3
"""
Build a Markdown summary of api-diff.sh results for posting to GitHub.

Usage:
    api-diff-summary.py <reports-dir> <baseline-ref> [<run-url>] [<platform-label>]

Reads every <Module>.diff.txt under <reports-dir>, applies the same classifier
and ignore-list rules used by api-diff.sh, and prints Markdown on stdout.
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from api_diff_classify import (  # noqa: E402
    TOOL_FAILED_SENTINEL,
    classify_module,
    ignore_file_path,
    load_ignore_patterns,
    parse_break_line,
)


def render(reports_dir, baseline, run_url, platform_label=""):
    if not os.path.isdir(reports_dir):
        sys.exit(f"api-diff-summary: reports dir does not exist: {reports_dir}")
    sentinel = os.path.join(reports_dir, TOOL_FAILED_SENTINEL)
    if os.path.isfile(sentinel):
        with open(sentinel) as f:
            detail = f.read().strip() or "swift-api-digester failed"
        sys.exit(
            f"api-diff-summary: tool-failure sentinel present in {reports_dir}: {detail} "
            "(refusing to render a partial summary from a run where the digester crashed)"
        )
    diff_files = sorted(glob.glob(os.path.join(reports_dir, "*.diff.txt")))
    if not diff_files:
        sys.exit(
            f"api-diff-summary: no *.diff.txt files in {reports_dir} "
            "(refusing to render a green summary from an empty/failed run)"
        )
    patterns = load_ignore_patterns()
    ignore_path = ignore_file_path()
    modules = []
    total_break = 0
    total_ignored = 0
    for diff_path in diff_files:
        m = os.path.basename(diff_path)[: -len(".diff.txt")]
        breaks, ignored, _ = classify_module(diff_path, patterns)
        if breaks or ignored:
            modules.append((m, breaks, ignored))
            total_break += len(breaks)
            total_ignored += len(ignored)

    out = []
    title = f"### Public API Diff vs `{baseline}`"
    if platform_label:
        title = f"### Public API Diff ({platform_label}) vs `{baseline}`"
    out.append(title)
    out.append("")
    if total_break == 0:
        out.append("**Result:** :white_check_mark: No breaking changes")
        if total_ignored:
            out.append(f"  ({total_ignored} ignored by `{ignore_path}`)")
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
                if len(msg) > 200:
                    msg = msg[:197] + "..."
                out.append(f"| {section} | {msg} | {file_disp} |")
            out.append("")
        if ignored:
            out.append(f"**Ignored** (matched `{ignore_path}`):")
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
        sys.exit("usage: api-diff-summary.py <reports-dir> <baseline-ref> [<run-url>] [<platform-label>]")
    reports_dir = sys.argv[1]
    baseline = sys.argv[2]
    run_url = sys.argv[3] if len(sys.argv) > 3 else ""
    platform_label = sys.argv[4] if len(sys.argv) > 4 else ""
    text, _ = render(reports_dir, baseline, run_url, platform_label)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
