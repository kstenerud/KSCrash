#!/bin/bash
#
# run_benchmarks.sh
#
# Runs benchmarks locally, simulating CI behavior.
# Outputs results to stdout and optionally to a markdown file.
#
# Usage:
#   ./scripts/run_benchmarks.sh                # Run all benchmarks
#   ./scripts/run_benchmarks.sh -o results.md  # Save results to file
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCHMARKS_DIR="$REPO_ROOT/Benchmarks"
RESULTS_DIR=$(mktemp -d)
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-o output.md]"
            echo ""
            echo "Options:"
            echo "  -o, --output FILE    Save markdown results to FILE"
            echo "  -h, --help           Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Generate project if needed
cd "$BENCHMARKS_DIR"
if [ ! -d "KSCrashBenchmarks.xcworkspace" ]; then
    echo "Generating project..."
    mise exec -- tuist generate
fi

# Run benchmarks (matching CI parameters)
XCRESULT_PATH="$RESULTS_DIR/benchmarks.xcresult"

echo "Running benchmarks..."
set -o pipefail
xcodebuild -workspace KSCrashBenchmarks.xcworkspace \
    -scheme Benchmarks \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -resultBundlePath "$XCRESULT_PATH" \
    clean test 2>&1 | xcbeautify

# Parse results
echo ""
echo "Parsing results..."

PARSE_CMD=(
    python3 "$REPO_ROOT/.github/scripts/parse_benchmarks.py"
    --pr-results "$XCRESULT_PATH"
    --config "$REPO_ROOT/.github/data/benchmark-tests.json"
)

if [ -n "$OUTPUT_FILE" ]; then
    PARSE_CMD+=(--output "$OUTPUT_FILE")
fi

"${PARSE_CMD[@]}"
