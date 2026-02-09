#!/usr/bin/env bash

set -eu -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SRC_DIR="$SCRIPT_DIR/../Sources"
DST_HEADER_FILE="$SCRIPT_DIR/../Sources/KSCrashCore/include/KSCrashNamespace.h"

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

echo "[2/3] Scanning symbols..."
python3 namespacer.py "$SRC_DIR" "$DST_HEADER_FILE"
COUNT=$(grep -c '^#define ' "$DST_HEADER_FILE" || true)
echo "      $COUNT symbols found."

echo "[3/3] Header written to $(basename "$DST_HEADER_FILE")"
