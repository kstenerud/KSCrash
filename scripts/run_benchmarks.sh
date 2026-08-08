#!/bin/bash
#
# run_benchmarks.sh
#
# Runs benchmarks locally, simulating CI behavior.
# Outputs results to stdout and optionally to a markdown file.
#
# Usage:
#   ./scripts/run_benchmarks.sh                    # Run on simulator
#   ./scripts/run_benchmarks.sh -d -t TEAM_ID      # Run on connected device
#   ./scripts/run_benchmarks.sh -o results.md      # Save results to file
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCHMARKS_DIR="$REPO_ROOT/Benchmarks"
RESULTS_DIR=$(mktemp -d)
OUTPUT_FILE=""
USE_DEVICE=false
TEAM_ID="${KSCRASH_BUILD_DEVELOPMENT_TEAM:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--device)
            USE_DEVICE=true
            shift
            ;;
        -t|--team)
            TEAM_ID="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-d] [-t TEAM_ID] [-o output.md]"
            echo ""
            echo "Options:"
            echo "  -d, --device         Run on connected iOS device"
            echo "  -t, --team TEAM_ID   Apple development team ID (or set KSCRASH_BUILD_DEVELOPMENT_TEAM)"
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

# Generate project
cd "$BENCHMARKS_DIR"
echo "Generating project..."
mise exec -- tuist generate --no-open

# Run benchmarks (matching CI parameters)
XCRESULT_PATH="$RESULTS_DIR/benchmarks.xcresult"

# Set destination based on device flag
if [ "$USE_DEVICE" = true ]; then
    # Find first connected iOS device using devicectl
    DEVICE_INFO=$(xcrun devicectl list devices --json-output - 2>/dev/null | \
        jq -r '.result.devices[] | select(.hardwareProperties.platform == "iOS" and .connectionProperties.tunnelState == "connected") | "\(.hardwareProperties.udid)\n\(.deviceProperties.name)"' | \
        head -2)
    DEVICE_ID=$(echo "$DEVICE_INFO" | head -1)
    DEVICE_NAME=$(echo "$DEVICE_INFO" | tail -1)
    if [ -z "$DEVICE_ID" ]; then
        echo "Error: No iOS device connected"
        exit 1
    fi
    DESTINATION="platform=iOS,id=$DEVICE_ID"
    echo "Running benchmarks on device: $DEVICE_NAME"
else
    DESTINATION="platform=iOS Simulator,name=iPhone 17"
    echo "Running benchmarks on simulator..."
fi

set -o pipefail
XCODEBUILD_ARGS=(
    -workspace KSCrashBenchmarks.xcworkspace
    -scheme Benchmarks
    -destination "$DESTINATION"
    -resultBundlePath "$XCRESULT_PATH"
)

# Device builds need signing
if [ "$USE_DEVICE" = true ]; then
    if [ -z "$TEAM_ID" ]; then
        echo "Error: Device builds require a development team."
        echo "Set KSCRASH_BUILD_DEVELOPMENT_TEAM or use -t TEAM_ID"
        exit 1
    fi
    XCODEBUILD_ARGS+=(
        -allowProvisioningUpdates
        -allowProvisioningDeviceRegistration
        DEVELOPMENT_TEAM="$TEAM_ID"
    )
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" clean test 2>&1 | xcbeautify

echo ""
echo "xcresult file: $XCRESULT_PATH"

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
