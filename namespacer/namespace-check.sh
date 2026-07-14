#!/usr/bin/env bash

set -eu -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SRC_DIR="$SCRIPT_DIR/../Sources"
COMPARE_HEADER_FILE="$SCRIPT_DIR/../Sources/KSCrashCore/include/KSCrashNamespace.h"

cd "$SCRIPT_DIR"

echo "[1/5] Setting up Python virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
    source venv/bin/activate
    pip3 install -r requirements.txt > /dev/null
else
    source venv/bin/activate
fi
echo "      Python $(python3 --version | cut -d' ' -f2)"
echo "      libclang $(pip3 show libclang 2>/dev/null | grep '^Version:' | cut -d' ' -f2)"

TMP_DIR=${RUNNER_TEMP:-$(mktemp -d)}
DST_HEADER_FILE="$TMP_DIR/KSCrashNamespace.h"

echo "[2/5] Running namespacer regression tests..."
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest test_namespacer.py

echo "[3/5] Scanning symbols..."
python3 namespacer.py "$SRC_DIR" "$DST_HEADER_FILE"
COUNT=$(grep -c '^#define ' "$DST_HEADER_FILE" || true)
echo "      $COUNT symbols found."

echo "[4/5] Comparing with checked-in header..."
if diff -q "$COMPARE_HEADER_FILE" "$DST_HEADER_FILE" > /dev/null 2>&1; then
    echo "      Namespace header is up to date. All clean!"
else
    echo ""
    diff "$COMPARE_HEADER_FILE" "$DST_HEADER_FILE" || true
    echo ""
    echo "      Namespace header is out of date."
    echo "      Please run 'make namespace' to regenerate it."
    exit 1
fi

echo "[5/5] Compiling namespaced Objective-C headers..."
CLANG_ARGS=(
    -fsyntax-only
    -fobjc-arc
    -DKSCRASH_NAMESPACE=_NamespaceCheck
    -I "$SRC_DIR/KSCrashCore/include"
    -I "$SRC_DIR/KSCrashRecording"
    -I "$SRC_DIR/KSCrashRecording/include"
    -I "$SRC_DIR/KSCrashRecordingCore/include"
    -x objective-c-header
)
xcrun clang "${CLANG_ARGS[@]}" "$SRC_DIR/KSCrashRecording/KSCrashSessionLog.h"
xcrun clang "${CLANG_ARGS[@]}" "$SRC_DIR/KSCrashRecording/include/KSCrashRunSummary.h"
echo "      Namespaced headers compile cleanly."
