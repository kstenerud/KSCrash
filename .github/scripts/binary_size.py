#!/usr/bin/env python3
"""
Measure what KSCrash adds to an iOS app, from the link maps of the BinarySize apps in
Samples/Project.swift, and write a markdown report.

Each app integrates KSCrash one way and is linked with dead stripping, so its link map
says which of KSCrash's bytes an app integrating that way ships, down to the symbol.
Only KSCrash's own modules are counted: the app's own code, the system libraries and the
Swift runtime are not KSCrash's cost.

Usage:
    python3 binary_size.py --build-dir DerivedData [--base-build-dir DerivedData] [--output binary_size.md]
"""

import argparse
import bisect
import glob
import os
import re
import subprocess
import sys

# The apps, in report order. An add-on's app is SizeKSCrash plus that add-on, so its cost
# is the difference between the two.
APPS = [
    ("SizeRecording", "Recording (C install)", None),
    ("SizeKSCrash", "KSCrash (Swift install and send)", None),
    ("SizeDiskMonitor", "+ DiskMonitor", "SizeKSCrash"),
    ("SizeBootMonitor", "+ BootMonitor", "SizeKSCrash"),
    ("SizeMetricKit", "+ Monitors (MetricKit)", "SizeKSCrash"),
    ("SizeProfiler", "+ Profiler", "SizeKSCrash"),
    ("CorpseReporter", "Crash report extension", None),
]
HEADLINE_APP = "SizeKSCrash"

# Sections that take memory at run time but no space in the download.
ZERO_FILL = {"__bss", "__common", "__thread_bss"}

TOP_SYMBOLS = 15


def kscrash_modules(repo_root):
    """Every module under Sources/, which is what the measurement should cover."""
    sources = os.path.join(repo_root, "Sources")
    return sorted(
        name for name in os.listdir(sources)
        if os.path.isdir(os.path.join(sources, name)) and name != "KSCrashTestTools"
    )


def find_link_maps(build_dir):
    """{app: path} for every BinarySize app's link map in a DerivedData directory."""
    found = {}
    pattern = os.path.join(build_dir, "Build", "Intermediates.noindex", "**", "*-LinkMap-normal-arm64.txt")
    for path in glob.glob(pattern, recursive=True):
        app = os.path.basename(path)[: -len("-LinkMap-normal-arm64.txt")]
        if any(app == name for name, _, _ in APPS):
            found[app] = path
    return found


def symbol_group(name, section):
    """A stable key for a symbol. Compiler-local labels and literals are renumbered from
    one build to the next, so they are pooled per section instead of named."""
    if name.startswith("literal string:"):
        return "(C strings)"
    if re.match(r"^(l_|L|ltmp|lCPI|l\.|___unnamed|_?GCC_except_table|_*block_literal_global|_?anon$)", name) \
            or name.startswith("<"):
        return f"({section})"
    # Blocks and outlined copies carry a counter that moves when an unrelated one is added.
    return re.sub(r"\.\d+$", "", name)


def parse_link_map(path):
    """Return {(module, symbol, zero_fill): bytes} for the KSCrash modules in one link map."""
    objects = {}
    sections = []  # (start, end, name)
    sizes = {}
    mode = None
    with open(path, "rb") as f:
        for raw in f:
            line = raw.decode("utf-8", "replace").rstrip("\n")
            if line.startswith("# Object files:"):
                mode = "objects"
                continue
            if line.startswith("# Sections:"):
                mode = "sections"
                continue
            if line.startswith("# Symbols:"):
                mode = "symbols"
                sections.sort()
                starts = [s[0] for s in sections]
                continue
            if line.startswith("# Dead Stripped Symbols:"):
                break
            if line.startswith("#") or not line:
                continue
            if mode == "objects":
                m = re.match(r"^\[\s*(\d+)\]\s+(.*)$", line)
                if not m:
                    continue
                # Each KSCrash module is one prelinked object in the build's products.
                obj = m.group(2)
                if "/Build/Products/" in obj and obj.endswith(".o"):
                    objects[int(m.group(1))] = os.path.basename(obj)[:-2]
            elif mode == "sections":
                parts = line.split("\t")
                if len(parts) >= 4:
                    start, size = int(parts[0], 16), int(parts[1], 16)
                    sections.append((start, start + size, parts[3]))
            elif mode == "symbols":
                m = re.match(r"^0x([0-9A-Fa-f]+)\t0x([0-9A-Fa-f]+)\t\[\s*(\d+)\]\s(.*)$", line)
                if not m:
                    continue
                module = objects.get(int(m.group(3)))
                if module is None:
                    continue
                addr, size = int(m.group(1), 16), int(m.group(2), 16)
                i = bisect.bisect_right(starts, addr) - 1
                section = sections[i][2] if i >= 0 and addr < sections[i][1] else "?"
                key = (module, symbol_group(m.group(4), section), section in ZERO_FILL)
                sizes[key] = sizes.get(key, 0) + size
    return sizes


def measure(build_dir):
    """{app: {(module, symbol, zero_fill): bytes}} for every app found in a build."""
    return {app: parse_link_map(path) for app, path in find_link_maps(build_dir).items()}


def totals(symbols):
    """(download bytes, zero-fill bytes) of one app's KSCrash symbols."""
    download = sum(n for (_, _, zf), n in symbols.items() if not zf)
    zero = sum(n for (_, _, zf), n in symbols.items() if zf)
    return download, zero


def app_cost(apps, name, relative_to):
    """An app's KSCrash bytes, or an add-on's: the app's minus the app it adds onto."""
    download, zero = totals(apps[name])
    if relative_to:
        if relative_to not in apps:
            return None
        base_download, base_zero = totals(apps[relative_to])
        download, zero = download - base_download, zero - base_zero
    return download, zero


def modules_of(symbols):
    out = {}
    for (module, _, zf), n in symbols.items():
        if not zf:
            out[module] = out.get(module, 0) + n
    return out


def all_symbols(apps):
    """Every KSCrash symbol any app links, at its size. A symbol is the same size in every
    app that links it, so the largest one seen is that size."""
    out = {}
    for symbols in apps.values():
        for key, n in symbols.items():
            out[key] = max(out.get(key, 0), n)
    return out


def demangle(names):
    """Readable names for C, ObjC and Swift symbols, in the same order."""
    try:
        proc = subprocess.run(
            ["xcrun", "swift-demangle", "--simplified"],
            input="\n".join(names), capture_output=True, text=True, timeout=60,
        )
        out = proc.stdout.split("\n")
        if proc.returncode == 0 and len(out) >= len(names):
            names = out[: len(names)]
    except (OSError, subprocess.SubprocessError):
        pass
    # C and ObjC names carry the linker's leading underscore.
    return [n[1:] if n.startswith("_") and not n.startswith("_$") else n for n in names]


def fmt_size(n):
    if abs(n) < 1024:
        return f"{n} B"
    if abs(n) < 1024 * 1024:
        return f"{n / 1024:.1f} KB"
    return f"{n / (1024 * 1024):.2f} MB"


def fmt_delta(current, base):
    if base is None:
        return "*new*"
    d = current - base
    if d == 0:
        return "="
    sign = "+" if d > 0 else "-"
    pct = f" ({sign}{abs(d) / base * 100:.1f}%)" if base else ""
    return f"{sign}{fmt_size(abs(d))}{pct}"


def md_name(name):
    return "`" + name.replace("`", "'").replace("|", "\\|") + "`"


def generate_report(current, base, expected_modules):
    has_base = base is not None
    lines = []

    headline = app_cost(current, HEADLINE_APP, None) if HEADLINE_APP in current else None
    base_headline = app_cost(base, HEADLINE_APP, None) if has_base and HEADLINE_APP in base else None

    indicator = "&#x2139;&#xFE0F;"
    if headline and base_headline and base_headline[0]:
        pct = (headline[0] - base_headline[0]) / base_headline[0] * 100
        indicator = "&#x1F534;" if pct > 5 else "&#x1F7E1;" if pct > 1 else "&#x1F7E2;"

    lines.append(f"# {indicator} Binary Size Report")
    lines.append("")
    if headline:
        summary = f"**KSCrash in an app: {fmt_size(headline[0])}**"
        if base_headline:
            summary += f" ({fmt_delta(headline[0], base_headline[0])})"
        lines.append(summary + ", iOS arm64 Release, linked with dead stripping")
    lines.append("")
    lines.append("Each row is an app that integrates KSCrash one way. Sizes count KSCrash's own code "
                 "and data in that app; an add-on's row is what it adds on top of the KSCrash app. "
                 "Zero-fill is memory reserved at launch that takes no space in the download.")

    measured = set()
    for symbols in current.values():
        measured.update(modules_of(symbols))
    unmeasured = [m for m in expected_modules if m not in measured]
    missing_apps = [label for name, label, _ in APPS if name not in current]
    if missing_apps:
        lines.append("")
        lines.append(f"> **Warning:** no link map for: {', '.join(missing_apps)}.")
    if unmeasured:
        lines.append("")
        lines.append(f"> **Not measured:** no app links {', '.join(unmeasured)}. "
                     "Add one to the BinarySize apps in `Samples/Project.swift`.")
    if not has_base:
        lines.append("")
        lines.append("> No base measurement: the base branch has no BinarySize apps.")
    lines.append("")

    # Per app
    if has_base:
        lines.append("| App | Download | Delta | Zero-fill | Delta |")
        lines.append("|-----|----------|-------|-----------|-------|")
    else:
        lines.append("| App | Download | Zero-fill |")
        lines.append("|-----|----------|-----------|")
    for name, label, relative_to in APPS:
        if name not in current:
            continue
        cost = app_cost(current, name, relative_to)
        if cost is None:
            continue
        if has_base:
            base_cost = app_cost(base, name, relative_to) if name in base else None
            lines.append(f"| {label} | {fmt_size(cost[0])} | "
                         f"{fmt_delta(cost[0], base_cost[0] if base_cost else None)} | "
                         f"{fmt_size(cost[1])} | {fmt_delta(cost[1], base_cost[1] if base_cost else None)} |")
        else:
            lines.append(f"| {label} | {fmt_size(cost[0])} | {fmt_size(cost[1])} |")
    lines.append("")

    # Per module, in the headline app
    if HEADLINE_APP in current:
        mods = modules_of(current[HEADLINE_APP])
        base_mods = modules_of(base[HEADLINE_APP]) if has_base and HEADLINE_APP in base else {}
        lines.append("<details>")
        lines.append("<summary>By module, in the KSCrash app</summary>")
        lines.append("")
        lines.append("| Module | Download | Delta |" if has_base else "| Module | Download |")
        lines.append("|--------|----------|-------|" if has_base else "|--------|----------|")
        for module in sorted(set(mods) | set(base_mods), key=lambda m: -mods.get(m, 0)):
            size = mods.get(module, 0)
            if has_base:
                lines.append(f"| {module} | {fmt_size(size)} | {fmt_delta(size, base_mods.get(module))} |")
            else:
                lines.append(f"| {module} | {fmt_size(size)} |")
        lines.append("")
        lines.append("</details>")
        lines.append("")

    # Per symbol, across every app
    if has_base:
        now, before = all_symbols(current), all_symbols(base)
        changes = [(now.get(k, 0) - before.get(k, 0), k) for k in set(now) | set(before)]
        grew = sorted([c for c in changes if c[0] > 0], key=lambda c: -c[0])[:TOP_SYMBOLS]
        shrank = sorted([c for c in changes if c[0] < 0], key=lambda c: c[0])[:TOP_SYMBOLS]
        shown = grew + shrank
        if shown:
            readable = dict(zip([k for _, k in shown], demangle([k[1] for _, k in shown])))
            for title, rows in (("Largest symbol growth", grew), ("Largest symbol shrinkage", shrank)):
                if not rows:
                    continue
                lines.append("<details>")
                lines.append(f"<summary>{title}</summary>")
                lines.append("")
                lines.append("| Symbol | Module | Change |")
                lines.append("|--------|--------|--------|")
                for d, key in rows:
                    module, _, zero_fill = key
                    change = ("+" if d > 0 else "-") + fmt_size(abs(d))
                    if zero_fill:
                        change += " zero-fill"
                    if key not in before:
                        change += " (new)"
                    elif key not in now:
                        change += " (removed)"
                    lines.append(f"| {md_name(readable[key])} | {module} | {change} |")
                lines.append("")
                lines.append("</details>")
                lines.append("")

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Measure what KSCrash adds to an iOS app")
    parser.add_argument("--build-dir", required=True, help="DerivedData of the BinarySize build")
    parser.add_argument("--base-build-dir", default=None, help="DerivedData of the base branch's build")
    parser.add_argument("--repo-root", default=os.path.join(os.path.dirname(__file__), "..", ".."),
                        help="The checkout whose Sources/ lists the modules to cover")
    parser.add_argument("--output", default="binary_size.md", help="Output markdown file")
    args = parser.parse_args()

    current = measure(args.build_dir)
    if not current:
        print("Error: no BinarySize link maps found", file=sys.stderr)
        sys.exit(1)
    base = None
    if args.base_build_dir:
        base = measure(args.base_build_dir) or None
        if base is None:
            print("Warning: no BinarySize link maps in the base build, skipping deltas")

    report = generate_report(current, base, kscrash_modules(args.repo_root))
    with open(args.output, "w") as f:
        f.write(report)
    print(report)


if __name__ == "__main__":
    main()
