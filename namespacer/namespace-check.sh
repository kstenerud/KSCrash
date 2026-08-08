#!/usr/bin/env bash

set -eu -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SRC_DIR="$SCRIPT_DIR/../Sources"
COMPARE_HEADER_FILE="$SCRIPT_DIR/../Sources/KSCrashCore/include/KSCrashNamespace.h"

cd "$SCRIPT_DIR"

echo "[1/3] Setting up Python virtual environment..."
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

echo "[2/3] Scanning symbols..."
python3 namespacer.py "$SRC_DIR" "$DST_HEADER_FILE"
COUNT=$(grep -c '^#define ' "$DST_HEADER_FILE" || true)
echo "      $COUNT symbols found."

echo "[3/3] Comparing with checked-in header..."
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
