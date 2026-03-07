#!/usr/bin/env python3
"""
Measure per-module binary sizes from an iOS Release build and generate a markdown report.

Usage:
    python3 binary_size.py --build-dir DerivedData [--base-build-dir DerivedData] [--output binary_size.md]
"""

import argparse
import csv
import io
import os
import subprocess
import sys

# Modules that make up each user-facing product
PRODUCTS = {
    "Recording": ["KSCrashCore", "KSCrashRecordingCore", "KSCrashRecording"],
    "Reporting": [
        "KSCrashCore",
        "KSCrashRecordingCore",
        "KSCrashRecording",
        "KSCrashReportingCore",
        "KSCrashFilters",
        "KSCrashSinks",
        "KSCrashInstallations",
        "KSCrashDemangleFilter",
    ],
}

# Add-on sizes count only modules NOT already in Recording
ADDONS = {
    "DiscSpaceMonitor": ["KSCrashDiscSpaceMonitor"],
    "BootTimeMonitor": ["KSCrashBootTimeMonitor"],
    "Profiler": ["KSCrashProfiler", "SwiftCore"],
    "Monitors": ["Monitors", "Report", "SwiftCore"],
}

# Artifacts to skip (test targets, benchmarks, etc.)
SKIP_PREFIXES = ("KSCrashBenchmarks", "KSCrashTests", "Tests")
SKIP_SUFFIXES = ("Tests",)


def find_modules(build_dir):
    """Find *.o files in Build/Products/Release-iphoneos/, return {name: path}."""
    products_dir = os.path.join(build_dir, "Build", "Products", "Release-iphoneos")
    if not os.path.isdir(products_dir):
        print(f"Error: products directory not found: {products_dir}", file=sys.stderr)
        sys.exit(1)

    modules = {}
    for entry in sorted(os.listdir(products_dir)):
        if not entry.endswith(".o"):
            continue
        name = entry[:-2]  # strip .o
        if any(name.startswith(p) for p in SKIP_PREFIXES):
            continue
        if any(name.endswith(s) for s in SKIP_SUFFIXES):
            continue
        modules[name] = os.path.join(products_dir, entry)
    return modules


def measure_module(path):
    """Run bloaty on a .o file and return segment sizes.

    Uses sections (not segments) because .o files don't have segment load commands.
    Groups __text/__stubs/__stub_helper into TEXT, __data/__bss/__common/__objc_* into DATA.
    """
    result = {"vm_total": 0, "file_total": 0, "text": 0, "data": 0}

    # Sections whose vmsize counts toward __TEXT
    TEXT_SECTIONS = {"__text", "__stubs", "__stub_helper", "__cstring", "__const",
                     "__gcc_except_tab", "__unwind_info", "__compact_unwind"}
    # Sections whose vmsize counts toward __DATA
    DATA_SECTIONS = {"__data", "__bss", "__common", "__cfstring",
                     "__objc_const", "__objc_data", "__objc_classlist",
                     "__objc_classrefs", "__objc_superrefs", "__objc_protolist",
                     "__objc_catlist", "__objc_selrefs", "__objc_ivar",
                     "__objc_methname", "__objc_methtype", "__objc_classname",
                     "__objc_imageinfo"}

    try:
        proc = subprocess.run(
            ["bloaty", "--csv", "-n", "0", "-d", "sections", path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if proc.returncode != 0:
            size = os.path.getsize(path)
            result["vm_total"] = size
            result["file_total"] = size
            return result

        reader = csv.DictReader(io.StringIO(proc.stdout))
        for row in reader:
            vm = int(row.get("vmsize", 0))
            file_sz = int(row.get("filesize", 0))
            section = row.get("sections", "").strip().strip(",").strip('"').strip()
            result["vm_total"] += vm
            result["file_total"] += file_sz
            if section in TEXT_SECTIONS:
                result["text"] += file_sz
            elif section in DATA_SECTIONS:
                result["data"] += file_sz
    except FileNotFoundError:
        size = os.path.getsize(path)
        result["vm_total"] = size
        result["file_total"] = size
    except Exception:
        size = os.path.getsize(path)
        result["vm_total"] = size
        result["file_total"] = size
    return result


def fmt_size(size_bytes):
    """Format bytes as human-readable KB."""
    if size_bytes == 0:
        return "0"
    kb = size_bytes / 1024
    if kb >= 100:
        return f"{kb:.0f} KB"
    return f"{kb:.1f} KB"


def fmt_delta(current, base):
    """Format a delta value with sign and percentage."""
    if base is None:
        return ""
    diff = current - base
    if diff == 0:
        return "="
    pct = (diff / base * 100) if base != 0 else 0
    sign = "+" if diff > 0 else ""
    return f"{sign}{fmt_size(diff)} ({sign}{pct:.1f}%)"


def generate_report(current_modules, current_sizes, base_sizes=None):
    """Generate the markdown report."""
    has_base = base_sizes is not None
    lines = []
    lines.append("# Binary Size Report")
    lines.append("")
    lines.append(
        "*iOS arm64 Release — per-module object sizes (upper bound before linker dead-code stripping)*"
    )
    lines.append("")

    # Per-module table
    lines.append("## Per-Module Breakdown")
    lines.append("")
    if has_base:
        lines.append("| Module | `__TEXT` | `__DATA` | Total | Delta |")
        lines.append("|--------|---------|---------|-------|-------|")
    else:
        lines.append("| Module | `__TEXT` | `__DATA` | Total |")
        lines.append("|--------|---------|---------|-------|")

    total_current = 0
    total_base = 0

    for name in sorted(current_modules):
        cur = current_sizes[name]
        total_current += cur["file_total"]
        row = f"| {name} | {fmt_size(cur['text'])} | {fmt_size(cur['data'])} | {fmt_size(cur['file_total'])}"
        if has_base:
            base = base_sizes.get(name)
            if base:
                total_base += base["file_total"]
                row += f" | {fmt_delta(cur['file_total'], base['file_total'])}"
            else:
                row += " | *new* "
        row += " |"
        lines.append(row)

    # Modules removed in PR (present in base but not current)
    if has_base:
        for name in sorted(base_sizes):
            if name not in current_sizes:
                base = base_sizes[name]
                total_base += base["file_total"]
                lines.append(
                    f"| ~~{name}~~ | - | - | - | *removed* |"
                )

    # Total row
    if has_base:
        # Add base-only modules that weren't counted yet
        lines.append(
            f"| **Total** | | | **{fmt_size(total_current)}** | **{fmt_delta(total_current, total_base)}** |"
        )
    else:
        lines.append(f"| **Total** | | | **{fmt_size(total_current)}** |")

    lines.append("")

    # User cost by product
    lines.append("## User Cost by Product")
    lines.append("")
    if has_base:
        lines.append("| Product | Size | Delta |")
        lines.append("|---------|------|-------|")
    else:
        lines.append("| Product | Size |")
        lines.append("|---------|------|")

    for product_name, modules in PRODUCTS.items():
        cur_total = sum(
            current_sizes[m]["file_total"] for m in modules if m in current_sizes
        )
        row = f"| **{product_name}** | {fmt_size(cur_total)}"
        if has_base:
            base_total = sum(
                base_sizes[m]["file_total"] for m in modules if m in base_sizes
            )
            row += f" | {fmt_delta(cur_total, base_total)}"
        row += " |"
        lines.append(row)

    lines.append("")

    # Add-ons
    recording_modules = set(PRODUCTS["Recording"])
    lines.append("### Optional Add-ons (additional cost on top of Recording)")
    lines.append("")
    if has_base:
        lines.append("| Add-on | Size | Delta |")
        lines.append("|--------|------|-------|")
    else:
        lines.append("| Add-on | Size |")
        lines.append("|--------|------|")

    for addon_name, modules in ADDONS.items():
        extra = [m for m in modules if m not in recording_modules]
        cur_total = sum(
            current_sizes[m]["file_total"] for m in extra if m in current_sizes
        )
        row = f"| {addon_name} | {fmt_size(cur_total)}"
        if has_base:
            base_total = sum(
                base_sizes[m]["file_total"] for m in extra if m in base_sizes
            )
            row += f" | {fmt_delta(cur_total, base_total)}"
        row += " |"
        lines.append(row)

    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Measure KSCrash module binary sizes")
    parser.add_argument(
        "--build-dir", required=True, help="Path to DerivedData for the current build"
    )
    parser.add_argument(
        "--base-build-dir",
        default=None,
        help="Path to DerivedData for the base build (for delta comparison)",
    )
    parser.add_argument(
        "--output", default="binary_size.md", help="Output markdown file"
    )
    parser.add_argument(
        "--linked-binary",
        default=None,
        help="(Future) Path to a linked binary for actual size measurement",
    )
    args = parser.parse_args()

    # Measure current build
    current_modules = find_modules(args.build_dir)
    if not current_modules:
        print("Error: no .o modules found", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(current_modules)} modules:")
    for name in sorted(current_modules):
        print(f"  {name}")

    current_sizes = {}
    for name, path in current_modules.items():
        current_sizes[name] = measure_module(path)

    # Measure base build if provided
    base_sizes = None
    if args.base_build_dir:
        base_modules = find_modules(args.base_build_dir)
        if base_modules:
            base_sizes = {}
            for name, path in base_modules.items():
                base_sizes[name] = measure_module(path)
            print(f"\nBase has {len(base_modules)} modules")
        else:
            print("Warning: no .o modules found in base build, skipping delta")

    report = generate_report(current_modules, current_sizes, base_sizes)

    with open(args.output, "w") as f:
        f.write(report)

    print(f"\nReport written to {args.output}")
    print(report)


if __name__ == "__main__":
    main()
