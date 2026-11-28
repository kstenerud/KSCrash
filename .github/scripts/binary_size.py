#!/usr/bin/env python3
"""
Measure what KSCrash adds to an iOS app, from the link maps of the BinarySize apps in
Samples/Project.swift, and write a markdown report.

Each app is linked with dead stripping, so its link map says which of KSCrash's bytes an
app integrating that way ships, down to the symbol. Only KSCrash's own modules are
counted: the app's own code, the system libraries and the Swift runtime are not KSCrash's.

Usage:
    python3 binary_size.py --build-dir DerivedData --repo-root CHECKOUT
        [--base-build-dir DerivedData --base-repo-root BASE_CHECKOUT] [--output binary_size.md]
"""

import argparse
import bisect
import glob
import os
import re
import subprocess
import sys

# (target, label), in report order. The first is the one broken down by module.
APPS = [
    ("SizeApp", "App"),
    ("CorpseReporter", "Crash report extension"),
]

# Sections the loader reserves and zero-fills: memory, but nothing in the download.
STATIC_BUFFER_SECTIONS = {"__bss", "__common", "__thread_bss"}

TOP_SYMBOLS = 15

# What the unnamed data pooled per section is, for the sections that hold most of it.
POOLED_SECTION_LABELS = {
    "__cstring": "C strings",
    "__const": "constants",
    "__cfstring": "NSString literals",
    "__objc_methname": "Objective-C method names",
    "__objc_classname": "Objective-C class names",
    "__objc_methtype": "Objective-C type encodings",
    "__text": "unnamed code",
    "__gcc_except_tab": "exception tables",
}

LEGEND = """\
<details>
<summary>Legend</summary>

**Download size**: KSCrash's code, constants and strings in the app, after unused code is stripped.
**Static buffers**: zero-filled memory KSCrash reserves. It counts toward memory only once written, and adds nothing to the download.
**App**: a normal install with every product. **Crash report extension**: the extension's own install.
"=" is no change, "new" is not in the base.

</details>
"""


def kscrash_modules(repo_root):
    """Every module under Sources/, which is what the measurement should cover."""
    sources = os.path.join(repo_root, "Sources")
    return sorted(
        name for name in os.listdir(sources)
        if os.path.isdir(os.path.join(sources, name)) and name != "KSCrashTestTools"
    )


def find_link_maps(build_dir):
    """{target: path} for every BinarySize app's Release device link map in a DerivedData
    directory. Only Release-iphoneos counts, since that is what the report says it measures,
    and a second map for one app is an error rather than a guess at which one is current."""
    found = {}
    for name, _ in APPS:
        pattern = os.path.join(build_dir, "Build", "Intermediates.noindex", "*", "Release-iphoneos",
                               f"{name}.build", f"{name}-LinkMap-normal-arm64.txt")
        paths = glob.glob(pattern)
        if len(paths) > 1:
            print(f"Error: more than one Release-iphoneos link map for {name}: {', '.join(paths)}",
                  file=sys.stderr)
            sys.exit(1)
        if paths:
            found[name] = paths[0]
    return found


def symbol_group(name, section):
    """A stable key for a symbol. Compiler-local labels and literals are renumbered from
    one build to the next, so they are pooled per section instead of named."""
    if name.startswith("literal string:"):
        return "(C strings)"
    if re.match(r"^(l_|L|ltmp|lCPI|l\.|___unnamed|_?GCC_except_table|_*block_literal_global|_?anon$)", name) \
            or name.startswith("<"):
        return f"({POOLED_SECTION_LABELS.get(section, section)})"
    # Blocks and outlined copies carry a counter that moves when an unrelated one is added.
    name = re.sub(r"\.\d+$", "", name)
    # A block is also numbered by its place in the function that holds it, so adding one
    # renumbers the rest. They are pooled under that function, which is the name that stays put.
    block = re.match(r"^_*\d*(.+?)_block_invoke(?:_\d+)?$", name)
    if block:
        return f"blocks in {block.group(1)}"
    return name


def parse_link_map(path, modules):
    """{(module, symbol, is_static_buffer): bytes} for the KSCrash modules in one link map.
    The build's products also hold the samples' own dependencies, so an object counts only
    when it is one of `modules`, the revision's own."""
    objects = {}
    sections = []  # (start, end, name)
    starts = []
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
                # Each KSCrash module is one prelinked object in the build's products.
                if m and "/Build/Products/" in m.group(2) and m.group(2).endswith(".o"):
                    module = os.path.basename(m.group(2))[:-2]
                    if module in modules:
                        objects[int(m.group(1))] = module
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
                key = (module, symbol_group(m.group(4), section), section in STATIC_BUFFER_SECTIONS)
                sizes[key] = sizes.get(key, 0) + size
    return sizes


def measure(build_dir, modules):
    """{target: {(module, symbol, is_static_buffer): bytes}} for every app found in a build."""
    return {name: parse_link_map(path, set(modules)) for name, path in find_link_maps(build_dir).items()}


def totals(symbols):
    """(download bytes, static buffer bytes) of one app's KSCrash symbols."""
    download = sum(n for (_, _, static), n in symbols.items() if not static)
    static = sum(n for (_, _, is_static), n in symbols.items() if is_static)
    return download, static


def modules_of(symbols):
    out = {}
    for (module, _, static), n in symbols.items():
        if not static:
            out[module] = out.get(module, 0) + n
    return out


def symbol_changes(current, base):
    """[(change, key, is_new, is_removed, apps)]: each app compared with its own base. Pooled
    rows such as C strings differ from app to app, and the same row can grow in one and
    shrink in the other, so every app's change is its own row. The same change in both
    apps, which is what a symbol they share shows, is one row naming both."""
    by_change = {}
    for name, label in APPS:
        now, before = current.get(name), base.get(name)
        if now is None or before is None:
            continue
        for key in set(now) | set(before):
            d = now.get(key, 0) - before.get(key, 0)
            if d:
                row = (d, key, key not in before, key not in now)
                by_change.setdefault(row, []).append(label)
    return [row + (apps,) for row, apps in by_change.items()]


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


def by_readable_name(*builds):
    """The same builds keyed by readable names. Distinct symbols can read the same, such as
    two specializations of one generic function, and a report naming both twice says nothing
    about which is which, so they are summed under the name the reader sees."""
    builds = [b for b in builds if b]
    names = sorted({key[1] for b in builds for symbols in b.values() for key in symbols})
    readable = dict(zip(names, demangle(names)))
    out = []
    for b in builds:
        rekeyed = {}
        for app, symbols in b.items():
            merged = {}
            for (module, name, static), n in symbols.items():
                key = (module, readable[name], static)
                merged[key] = merged.get(key, 0) + n
            rekeyed[app] = merged
        out.append(rekeyed)
    return out


def fmt_size(n):
    if abs(n) < 1024:
        return f"{n} B"
    if abs(n) < 1024 * 1024:
        return f"{n / 1024:.1f} KB"
    return f"{n / (1024 * 1024):.2f} MB"


def fmt_delta(current, base):
    if base is None:
        return "new"
    d = current - base
    if d == 0:
        return "="
    sign = "+" if d > 0 else "−"
    pct = abs(d) / base * 100 if base else 0
    # A change too small to show as a percentage is shown as bytes alone, not as "0.0%".
    pct = f" ({sign}{pct:.1f}%)" if pct >= 0.05 else ""
    return f"{sign}{fmt_size(abs(d))}{pct}"


def md_name(name):
    """A symbol as code that can wrap. A browser never breaks inside a long name, which pushes
    the table past the page, so a zero-width space follows each separator (GitHub strips
    <wbr>, the tag meant for this)."""
    name = re.sub(r"([.:,]|(?<=\w)\()", "\\1\u200b", name.replace("`", "'"))
    return "`" + name.replace("|", "\\|") + "`"


def generate_report(current, base, expected_modules):
    has_base = base is not None
    if has_base:
        current, base = by_readable_name(current, base)
    else:
        (current,) = by_readable_name(current)
    lines = []
    main_app, main_label = APPS[0]

    indicator = "&#x2139;&#xFE0F;"
    if has_base and main_app in current and main_app in base:
        now, before = totals(current[main_app])[0], totals(base[main_app])[0]
        if before:
            pct = (now - before) / before * 100
            indicator = "&#x1F534;" if pct > 5 else "&#x1F7E1;" if pct > 1 else "&#x1F7E2;"

    lines.append(f"# {indicator} Binary Size Report")
    lines.append("")
    lines.append("KSCrash's own code and data in each app, iOS arm64 Release, linked with dead stripping.")

    measured = set()
    for symbols in current.values():
        measured.update(modules_of(symbols))
    unmeasured = [m for m in expected_modules if m not in measured]
    missing = [label for name, label in APPS if name not in current]
    if missing:
        lines.append("")
        lines.append(f"> **Warning:** no link map for: {', '.join(missing)}.")
    if unmeasured:
        lines.append("")
        lines.append(f"> **Not measured:** neither app links {', '.join(unmeasured)}. "
                     "Add it to `Samples/BinarySize/SizeApp`.")
    if not has_base:
        lines.append("")
        lines.append("> No changes shown: the base branch has no BinarySize apps.")
    lines.append("")

    # Each change sits under its size, so the table stays three columns wide.
    lines.append("| App | Download size | Static buffers |")
    lines.append("|---|---|---|")
    for name, label in APPS:
        if name not in current:
            continue
        download, static = totals(current[name])
        if has_base:
            before = totals(base[name]) if name in base else (None, None)
            lines.append(f"| {label} | {fmt_size(download)}<br>{fmt_delta(download, before[0])} | "
                         f"{fmt_size(static)}<br>{fmt_delta(static, before[1])} |")
        else:
            lines.append(f"| {label} | {fmt_size(download)} | {fmt_size(static)} |")
    lines.append("")

    if main_app in current:
        mods = modules_of(current[main_app])
        base_mods = modules_of(base[main_app]) if has_base and main_app in base else {}
        lines.append("<details>")
        lines.append(f"<summary>By module, in the {main_label}</summary>")
        lines.append("")
        if has_base:
            lines.append("| Module | Download size | Change |")
            lines.append("|---|---|---|")
        else:
            lines.append("| Module | Download size |")
            lines.append("|---|---|")
        for module in sorted(set(mods) | set(base_mods), key=lambda m: -mods.get(m, 0)):
            size = mods.get(module, 0)
            if has_base:
                lines.append(f"| {module} | {fmt_size(size)} | {fmt_delta(size, base_mods.get(module))} |")
            else:
                lines.append(f"| {module} | {fmt_size(size)} |")
        lines.append("")
        lines.append("</details>")
        lines.append("")

    if has_base:
        changes = symbol_changes(current, base)
        grew = sorted([c for c in changes if c[0] > 0], key=lambda c: -c[0])[:TOP_SYMBOLS]
        shrank = sorted([c for c in changes if c[0] < 0], key=lambda c: c[0])[:TOP_SYMBOLS]
        for title, rows in (("Largest symbol growth", grew), ("Largest symbol shrinkage", shrank)):
            if not rows:
                continue
            lines.append("<details>")
            lines.append(f"<summary>{title}</summary>")
            lines.append("")
            lines.append("| Symbol | Module | Change |")
            lines.append("|---|---|---|")
            for d, key, is_new, is_removed, apps in rows:
                module, symbol, static = key
                change = ("+" if d > 0 else "−") + fmt_size(abs(d))
                if static:
                    change += " static buffers"
                if is_new:
                    change += " (new)"
                elif is_removed:
                    change += " (removed)"
                # A change seen in every app is the usual case and goes unmarked.
                where = module if len(apps) == len(APPS) else f"{module}<br><sub>{', '.join(apps)} only</sub>"
                lines.append(f"| {md_name(symbol)} | {where} | {change} |")
            lines.append("")
            lines.append("</details>")
            lines.append("")

    lines.append(LEGEND)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Measure what KSCrash adds to an iOS app")
    parser.add_argument("--build-dir", required=True, help="DerivedData of the BinarySize build")
    parser.add_argument("--base-build-dir", default=None, help="DerivedData of the base branch's build")
    parser.add_argument("--repo-root", default=os.path.join(os.path.dirname(__file__), "..", ".."),
                        help="The checkout whose Sources/ lists the modules to measure")
    parser.add_argument("--base-repo-root", default=None,
                        help="The base checkout, whose Sources/ lists the modules it is measured by. "
                             "Required with --base-build-dir: the current list would drop a module "
                             "the change removed from both sides.")
    parser.add_argument("--output", default="binary_size.md", help="Output markdown file")
    args = parser.parse_args()
    if args.base_build_dir and not args.base_repo_root:
        parser.error("--base-build-dir needs --base-repo-root")

    modules = kscrash_modules(args.repo_root)
    current = measure(args.build_dir, modules)
    if not current:
        print("Error: no BinarySize link maps found", file=sys.stderr)
        sys.exit(1)
    base = None
    if args.base_build_dir:
        base = measure(args.base_build_dir, kscrash_modules(args.base_repo_root)) or None
        if base is None:
            print("Warning: no BinarySize link maps in the base build, skipping changes")

    report = generate_report(current, base, modules)
    with open(args.output, "w") as f:
        f.write(report)
    print(report)


if __name__ == "__main__":
    main()
