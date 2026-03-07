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

# Artifacts to skip (test targets, benchmarks, internal-only helpers)
SKIP_PREFIXES = ("KSCrashBenchmarks", "KSCrashTests", "Tests")
SKIP_SUFFIXES = ("Tests",)
SKIP_EXACT = {"KSCrashTestTools", "KSCrashRecordingCoreSwift"}


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
        if _should_skip(name):
            continue
        modules[name] = os.path.join(products_dir, entry)
    return modules


def _should_skip(name):
    """Check if a module name should be excluded from measurement."""
    if name in SKIP_EXACT:
        return True
    if any(name.startswith(p) for p in SKIP_PREFIXES):
        return True
    if any(name.endswith(s) for s in SKIP_SUFFIXES):
        return True
    return False


def _reported_modules():
    """All modules referenced by PRODUCTS and ADDONS — the set we actually report on."""
    modules = set()
    for mods in PRODUCTS.values():
        modules.update(mods)
    for mods in ADDONS.values():
        modules.update(mods)
    return modules


def check_completeness(found_modules):
    """Check if all reported modules were built. Returns list of missing module names."""
    return sorted(_reported_modules() - set(found_modules))


def measure_module(path):
    """Run bloaty on a .o file and return section sizes.

    Uses sections (not segments) because .o files don't have segment load commands.
    Reports vmsize for sections that map to __TEXT or __DATA in the linked binary.
    Zero-fill sections (__bss, __common, __thread_bss) are excluded — they cost
    runtime memory but no file/download size.
    """
    result = {"vm_total": 0, "file_total": 0, "text": 0, "data": 0}

    # Sections that land in __TEXT segment in the linked binary
    TEXT_SECTIONS = {
        "__text", "__stubs", "__stub_helper", "__cstring", "__const",
        "__constg_swiftt", "__literal8", "__literal16",
        "__gcc_except_tab", "__unwind_info", "__compact_unwind", "__eh_frame",
        "__swift5_typeref", "__swift5_reflstr", "__swift5_fieldmd",
        "__swift5_assocty", "__swift5_proto", "__swift5_protos",
        "__swift5_types", "__swift5_builtin", "__swift5_capture",
        "__swift_modhash",
    }
    # Sections that land in __DATA segment (initialized data only, not zero-fill)
    DATA_SECTIONS = {
        "__data", "__cfstring", "__mod_init_func",
        "__objc_const", "__objc_data", "__objc_classlist", "__objc_nlclslist",
        "__objc_classrefs", "__objc_superrefs", "__objc_protolist",
        "__objc_protorefs", "__objc_catlist", "__objc_clsrolist",
        "__objc_selrefs", "__objc_ivar",
        "__objc_methname", "__objc_methtype", "__objc_classname",
        "__objc_imageinfo",
        "__thread_vars",
    }

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
                result["text"] += vm
            elif section in DATA_SECTIONS:
                result["data"] += vm
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
    if abs(diff) < 100:
        return "="
    if base == 0:
        return "*new*"
    pct = diff / base * 100
    sign = "+" if diff > 0 else ""
    return f"{sign}{fmt_size(diff)} ({sign}{pct:.1f}%)"


def generate_report(current_modules, current_sizes, base_sizes=None,
                    missing_current=None, missing_base=None):
    """Generate the markdown report."""
    has_base = base_sizes is not None
    lines = []

    # Compute totals upfront for the summary
    total_current = sum(current_sizes[m]["file_total"] for m in current_modules)
    total_base = 0
    if has_base:
        total_base = sum(base_sizes[m]["file_total"] for m in base_sizes)

    # Detect coverage changes (modules added/removed between base and PR)
    added_modules = []
    removed_modules = []
    if has_base:
        added_modules = sorted(set(current_sizes) - set(base_sizes))
        removed_modules = sorted(set(base_sizes) - set(current_sizes))

    # Status indicator
    if has_base and total_base > 0:
        pct = (total_current - total_base) / total_base * 100
        if pct > 5:
            indicator = "&#x1F534;"  # red circle
        elif pct > 1:
            indicator = "&#x1F7E1;"  # yellow circle
        else:
            indicator = "&#x1F7E2;"  # green circle
    else:
        indicator = "&#x2139;&#xFE0F;"  # info icon

    # Summary line
    lines.append(f"# {indicator} Binary Size Report")
    lines.append("")
    summary = f"**Total: {fmt_size(total_current)}**"
    if has_base:
        summary += f" ({fmt_delta(total_current, total_base)})"
    summary += " — iOS arm64 Release, per-module object sizes (upper bound before linker dead-code stripping)"
    lines.append(summary)

    # Coverage change note
    if added_modules or removed_modules:
        lines.append("")
        parts = []
        if added_modules:
            parts.append(f"+{len(added_modules)} module(s): {', '.join(added_modules)}")
        if removed_modules:
            parts.append(f"-{len(removed_modules)} module(s): {', '.join(removed_modules)}")
        lines.append(f"> **Coverage change:** {'; '.join(parts)}. "
                      "Delta includes these modules — not purely a source-size change.")

    # Completeness warnings
    if missing_current:
        lines.append("")
        lines.append(f"> **Warning:** measurement incomplete — missing module(s): "
                      f"{', '.join(missing_current)}")
    if missing_base:
        lines.append("")
        lines.append(f"> **Warning:** base measurement incomplete — missing module(s): "
                      f"{', '.join(missing_base)}. "
                      "Deltas may overstate the actual size change.")

    lines.append("")

    # Column labels: __TEXT = code + read-only data (download cost),
    # __DATA = initialized writable data (download cost)
    text_col = "Code (`__TEXT`)"
    data_col = "Data (`__DATA`)"

    # Per-module table (collapsible), sorted by absolute delta when base exists
    lines.append("<details>")
    lines.append("<summary>Per-Module Breakdown</summary>")
    lines.append("")
    if has_base:
        lines.append(f"| Module | {text_col} | {data_col} | File Total | Delta |")
        lines.append("|--------|---------|---------|-------|-------|")
    else:
        lines.append(f"| Module | {text_col} | {data_col} | File Total |")
        lines.append("|--------|---------|---------|-------|")

    # Sort by absolute delta (biggest movers first) when base exists, else by name
    module_names = sorted(current_modules)
    if has_base:
        def sort_key(name):
            cur = current_sizes[name]["file_total"]
            base = base_sizes.get(name, {}).get("file_total", 0)
            return -abs(cur - base)
        module_names = sorted(current_modules, key=sort_key)

    for name in module_names:
        cur = current_sizes[name]
        row = f"| {name} | {fmt_size(cur['text'])} | {fmt_size(cur['data'])} | {fmt_size(cur['file_total'])}"
        if has_base:
            base = base_sizes.get(name)
            if base:
                row += f" | {fmt_delta(cur['file_total'], base['file_total'])}"
            else:
                row += " | *new* "
        row += " |"
        lines.append(row)

    # Modules removed in PR (present in base but not current)
    if has_base:
        for name in sorted(base_sizes):
            if name not in current_sizes:
                lines.append(
                    f"| ~~{name}~~ | - | - | - | *removed* |"
                )

    # Total row
    if has_base:
        lines.append(
            f"| **Total** | | | **{fmt_size(total_current)}** | **{fmt_delta(total_current, total_base)}** |"
        )
    else:
        lines.append(f"| **Total** | | | **{fmt_size(total_current)}** |")

    lines.append("")
    lines.append("</details>")
    lines.append("")

    # User cost by product (collapsible)
    lines.append("<details>")
    lines.append("<summary>User Cost by Product</summary>")
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
    lines.append("**Optional Add-ons** (additional cost on top of Recording)")
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
    lines.append("</details>")
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

    missing_current = check_completeness(current_modules)
    if missing_current:
        print(f"Warning: missing reported module(s): {', '.join(missing_current)}")

    print(f"Found {len(current_modules)} modules:")
    for name in sorted(current_modules):
        print(f"  {name}")

    current_sizes = {}
    for name, path in current_modules.items():
        current_sizes[name] = measure_module(path)

    # Measure base build if provided
    base_sizes = None
    missing_base = None
    if args.base_build_dir:
        base_modules = find_modules(args.base_build_dir)
        if base_modules:
            missing_base = check_completeness(base_modules)
            base_sizes = {}
            for name, path in base_modules.items():
                base_sizes[name] = measure_module(path)
            print(f"\nBase has {len(base_modules)} modules")
        else:
            print("Warning: no .o modules found in base build, skipping delta")

    report = generate_report(current_modules, current_sizes, base_sizes,
                             missing_current, missing_base)

    with open(args.output, "w") as f:
        f.write(report)

    print(f"\nReport written to {args.output}")
    print(report)


if __name__ == "__main__":
    main()
