#!/usr/bin/env bash
#
# api-diff.sh
#
# Detect breaking Swift-visible API changes in KSCrash public library products.
#
# Uses swift-api-digester (ships in the Xcode toolchain) to dump each public
# module's Swift-visible API surface to JSON, then diffs two snapshots and
# classifies each section per the spec at guides/kscrash-api-diff-spec.md.
#
# Subcommands:
#   dump <out-dir>
#       Build the package in cwd and dump every public-library module's API
#       to <out-dir>/<Module>.json.
#
#   diff <old-dir> <new-dir> <report-dir>
#       Run swift-api-digester -diagnose-sdk for every module pair, write
#       <report-dir>/<Module>.diff.txt, print a classified summary, and exit
#       non-zero when any module has a breaking change.
#
#   compare <old-ref> <new-ref> [<work-dir>]
#       End-to-end harness. Materializes both refs as git worktrees (reusing
#       existing ones when present), dumps each, diffs, and reports.
#       Defaults <work-dir> to ${TMPDIR:-/tmp}/kscrash-api-diff.
#
#   snapshot [<dir>]
#       Refresh the on-repo baseline. Default dir: .api-snapshots/baseline
#
#   check [<dir>]
#       Dump current sources to a scratch dir then diff against the baseline.
#       Default dir: .api-snapshots/baseline
#
# Environment overrides:
#   TARGET           default arm64-apple-macos15
#   SDK_NAME         default macosx (e.g. iphoneos for iOS dumps)
#   XCODE_PLATFORM   xcodebuild -destination platform name (e.g. iOS); only
#                    used when SDK_NAME != macosx (then xcodebuild produces
#                    target-correct .swiftmodules; macosx uses swift build)
#   SWIFT_VERSION    default 6
#   SDK              default "$(xcrun --show-sdk-path --sdk $SDK_NAME)"
#   DIGESTER         default "$(xcrun -f swift-api-digester)"
#
# Exit codes:
#   0   no breaking changes (additive or unchanged)
#   1   one or more breaking changes detected
#   2   tool / usage error
#

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
TARGET="${TARGET:-arm64-apple-macos15}"
SDK_NAME="${SDK_NAME:-macosx}"
SWIFT_VERSION="${SWIFT_VERSION:-6}"
SDK="${SDK:-}"
DIGESTER="${DIGESTER:-}"

die() { printf 'api-diff: %s\n' "$*" >&2; exit 2; }

require_tools() {
    command -v swift >/dev/null || die "swift not found in PATH"
    command -v python3 >/dev/null || die "python3 not found in PATH"
    if [ -z "$DIGESTER" ]; then
        DIGESTER="$(xcrun -f swift-api-digester 2>/dev/null || true)"
        [ -n "$DIGESTER" ] || die "swift-api-digester not found (xcrun -f swift-api-digester)"
    fi
    [ -x "$DIGESTER" ] || die "DIGESTER=$DIGESTER is not executable"
    if [ -z "$SDK" ]; then
        SDK="$(xcrun --show-sdk-path --sdk "$SDK_NAME")"
    fi
}

public_modules() {
    swift package describe --type json | python3 -c '
import json, sys
ALLOWLIST = {
    "KSCrashRecording",
    "KSCrashFilters",
    "KSCrashSinks",
    "KSCrashInstallations",
    "KSCrashDiscSpaceMonitor",
    "KSCrashBootTimeMonitor",
    "KSCrashDemangleFilter",
    "KSCrashProfiler",
    "Monitors",
    "Report",
}
d = json.load(sys.stdin)
all_targets = {t.get("name") for t in d.get("targets", []) if t.get("name")}
library_targets = set()
for p in d.get("products", []):
    t = p.get("type")
    if t == "library" or (isinstance(t, dict) and "library" in t):
        for tgt in p.get("targets", []):
            library_targets.add(tgt)
present = ALLOWLIST & all_targets
drifted = present - library_targets
if drifted:
    sys.exit("documented public modules exist as targets but are not exposed as library products in Package.swift: " + ", ".join(sorted(drifted)))
absent = ALLOWLIST - all_targets
if absent:
    sys.stderr.write("note: documented public modules not present in this revision (older snapshot?): " + ", ".join(sorted(absent)) + "\n")
extra = library_targets - ALLOWLIST
if extra:
    sys.stderr.write("note: ignoring library targets not listed as public in .claude/CLAUDE.md: " + ", ".join(sorted(extra)) + "\n")
print("\n".join(sorted(present)))
'
}

cmd_dump() {
    local out_dir="${1:-}"
    [ -n "$out_dir" ] || die "usage: api-diff.sh dump <out-dir>"
    require_tools
    mkdir -p "$out_dir"
    out_dir="$(cd "$out_dir" && pwd)"

    local args=(-target "$TARGET" -sdk "$SDK" -swift-version "$SWIFT_VERSION")
    local mm inc
    if [ "$SDK_NAME" = "macosx" ]; then
        printf '>> swift build (full package)\n'
        swift build >/dev/null
        local build
        build="$(swift build --show-bin-path)"
        args+=(-I "$build/Modules")
        for mm in "$build"/*.build/module.modulemap; do
            [ -e "$mm" ] || continue
            args+=(-Xcc -fmodule-map-file="$mm")
        done
    else
        # Non-macOS targets: swift build only emits host-target .swiftmodules
        # which fail to load with "incompatible target" in the digester. Use
        # xcodebuild against the SwiftPM-generated workspace, which produces
        # target-correct .swiftmodules and module.modulemaps for ObjC modules.
        local platform="${XCODE_PLATFORM:-}"
        [ -n "$platform" ] || die "XCODE_PLATFORM must be set when SDK_NAME=$SDK_NAME (e.g. iOS)"
        local derived="$out_dir/.derived"
        printf '>> xcodebuild build -destination "generic/platform=%s"\n' "$platform"
        xcodebuild build \
            -workspace .swiftpm/xcode/package.xcworkspace \
            -scheme KSCrash-Package \
            -destination "generic/platform=$platform" \
            -derivedDataPath "$derived" \
            -quiet
        local products="$derived/Build/Products/Debug-$SDK_NAME"
        local mm_dir="$derived/Build/Intermediates.noindex/GeneratedModuleMaps-$SDK_NAME"
        [ -d "$products" ] || die "xcodebuild Products dir missing: $products"
        args+=(-I "$products")
        for mm in "$mm_dir"/*.modulemap; do
            [ -e "$mm" ] || continue
            args+=(-Xcc -fmodule-map-file="$mm")
        done
    fi
    for inc in Sources/*/include; do
        [ -d "$inc" ] || continue
        args+=(-I "$inc")
    done

    local mods
    mods="$(public_modules)"
    [ -n "$mods" ] || die "no public-library modules discovered in $(pwd)"

    local objc_only_modules=" KSCrashRecording KSCrashRecordingCore KSCrashFilters KSCrashSinks KSCrashInstallations KSCrashDiscSpaceMonitor KSCrashBootTimeMonitor KSCrashDemangleFilter "
    local filter_script
    filter_script="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)/api-diff-filter-c.py"
    local M failed=0
    while IFS= read -r M; do
        [ -n "$M" ] || continue
        printf '>> dump %s\n' "$M"
        if ! "$DIGESTER" -dump-sdk -module "$M" "${args[@]}" \
                -o "$out_dir/$M.json" 2>"$out_dir/$M.dump.log"; then
            printf '   FAILED to dump %s; see %s\n' "$M" "$out_dir/$M.dump.log" >&2
            sed 's/^/     /' "$out_dir/$M.dump.log" >&2 || true
            rm -f "$out_dir/$M.json"
            failed=$((failed+1))
            continue
        fi
        if [[ " $objc_only_modules " == *" $M "* ]] && [ -f "$filter_script" ]; then
            python3 "$filter_script" "$out_dir/$M.json"
        fi
    done <<<"$mods"
    if [ "$failed" -gt 0 ]; then
        die "$failed module dump(s) failed in $(pwd); see logs in $out_dir"
    fi
}

classify_report() {
    local M="$1" out="$2"
    local ignore_file="${API_BREAK_IGNORE_FILE:-scripts/api-break-ignore.txt}"
    local classifier
    classifier="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)/api_diff_classify.py"
    python3 "$classifier" classify "$M" "$out" "$ignore_file"
}

cmd_diff() {
    local old_dir="${1:-}" new_dir="${2:-}" report_dir="${3:-}"
    [ -n "$old_dir" ] && [ -n "$new_dir" ] && [ -n "$report_dir" ] \
        || die "usage: api-diff.sh diff <old-dir> <new-dir> <report-dir>"
    require_tools
    [ -d "$old_dir" ] || die "old-dir not found: $old_dir"
    [ -d "$new_dir" ] || die "new-dir not found: $new_dir"
    mkdir -p "$report_dir"

    local total=0 broke=0 changed=0 tool_failed=0
    local new_json M old_json out diag_log rc
    for new_json in "$new_dir"/*.json; do
        [ -e "$new_json" ] || continue
        M="$(basename "$new_json" .json)"
        old_json="$old_dir/$M.json"
        out="$report_dir/$M.diff.txt"
        diag_log="$report_dir/$M.diagnose.log"
        total=$((total+1))
        if [ ! -f "$old_json" ]; then
            printf '[NEW]   %s: module did not exist in baseline\n' "$M"
            : >"$out"
            changed=$((changed+1))
            continue
        fi
        rc=0
        "$DIGESTER" -diagnose-sdk \
            -input-paths "$old_json" \
            -input-paths "$new_json" \
            -print-module \
            -o "$out" >/dev/null 2>"$diag_log" || rc=$?
        if [ "$rc" -ne 0 ] || [ ! -f "$out" ]; then
            printf '[FAIL]  %s: swift-api-digester exited %d; see %s\n' "$M" "$rc" "$diag_log" >&2
            sed 's/^/     /' "$diag_log" >&2 || true
            tool_failed=$((tool_failed+1))
            continue
        fi
        [ -s "$diag_log" ] || rm -f "$diag_log"
        rc=0
        classify_report "$M" "$out" || rc=$?
        if [ "$rc" -ne 0 ]; then
            broke=$((broke+1))
        else
            if grep -vE '^/\*|^$' "$out" >/dev/null 2>&1; then
                changed=$((changed+1))
            fi
        fi
    done
    local removed=0
    for old_json in "$old_dir"/*.json; do
        [ -e "$old_json" ] || continue
        M="$(basename "$old_json" .json)"
        if [ ! -f "$new_dir/$M.json" ]; then
            printf '[BREAK] %s: MODULE REMOVED (was in baseline, not in new)\n' "$M"
            out="$report_dir/$M.diff.txt"
            {
                printf '/* Removed Decls */\n'
                printf '%s: module has been removed (was present in baseline, absent in new)\n' "$M"
            } >"$out"
            removed=$((removed+1))
        fi
    done
    broke=$((broke+removed))
    if [ "$tool_failed" -gt 0 ]; then
        # Sentinel for api-diff-summary.py — refuse to render green on partial digester failure.
        printf '%d module diff(s) failed in swift-api-digester; see *.diagnose.log\n' "$tool_failed" \
            >"$report_dir/.tool-failed"
        die "$tool_failed module diff(s) failed in swift-api-digester; see logs in $report_dir"
    fi

    printf '\nSummary: %d module(s); %d breaking, %d non-breaking change(s), %d unchanged\n' \
        "$total" "$broke" "$changed" "$((total-broke-changed))"
    printf 'Reports: %s/<Module>.diff.txt\n' "$report_dir"
    [ "$broke" -eq 0 ]
}

setup_worktree() {
    local ref="$1" dir="$2"
    if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
        local cur
        cur="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "")"
        local want
        want="$(git rev-parse "$ref" 2>/dev/null || echo "")"
        if [ -n "$cur" ] && [ -n "$want" ] && [ "$cur" = "$want" ]; then
            printf '>> reuse worktree %s @ %s\n' "$dir" "$ref"
            return 0
        fi
        printf '>> existing worktree %s is at %s, checking out %s\n' "$dir" "${cur:0:8}" "$ref"
        git -C "$dir" checkout --quiet "$ref"
        return 0
    fi
    printf '>> git worktree add %s %s\n' "$dir" "$ref"
    git worktree add --detach "$dir" "$ref"
}

cmd_compare() {
    local old_ref="${1:-}" new_ref="${2:-}" work="${3:-${TMPDIR:-/tmp}/kscrash-api-diff}"
    [ -n "$old_ref" ] && [ -n "$new_ref" ] \
        || die "usage: api-diff.sh compare <old-ref> <new-ref> [<work-dir>]"
    require_tools
    mkdir -p "$work"
    work="$(cd "$work" && pwd)"

    local old_wt="$work/old" new_wt="$work/new"
    local old_dump="$work/old-json" new_dump="$work/new-json"
    local reports="$work/reports"
    rm -rf "$old_dump" "$new_dump" "$reports"

    setup_worktree "$old_ref" "$old_wt"
    setup_worktree "$new_ref" "$new_wt"

    printf '\n=== Dump old (%s) ===\n' "$old_ref"
    ( cd "$old_wt" && bash "$SCRIPT_PATH" dump "$old_dump" )
    printf '\n=== Dump new (%s) ===\n' "$new_ref"
    ( cd "$new_wt" && bash "$SCRIPT_PATH" dump "$new_dump" )

    printf '\n=== Diff ===\n'
    cmd_diff "$old_dump" "$new_dump" "$reports"
}

cmd_snapshot() {
    local dir="${1:-.api-snapshots/baseline}"
    cmd_dump "$dir"
}

cmd_check() {
    local baseline="${1:-.api-snapshots/baseline}"
    [ -d "$baseline" ] || die "baseline not found: $baseline (run: api-diff.sh snapshot)"
    local scratch
    scratch="$(mktemp -d -t kscrash-api-check.XXXXXX)"
    trap 'rm -rf "$scratch"' EXIT
    cmd_dump "$scratch/current"
    cmd_diff "$baseline" "$scratch/current" "$scratch/reports"
}

main() {
    local sub="${1:-}"
    [ -n "$sub" ] || { sed -n '3,40p' "$SCRIPT_PATH"; exit 2; }
    shift
    case "$sub" in
        dump)     cmd_dump     "$@" ;;
        diff)     cmd_diff     "$@" ;;
        compare)  cmd_compare  "$@" ;;
        snapshot) cmd_snapshot "$@" ;;
        check)    cmd_check    "$@" ;;
        -h|--help|help) sed -n '3,50p' "$SCRIPT_PATH"; exit 0 ;;
        *) die "unknown subcommand: $sub" ;;
    esac
}

main "$@"
