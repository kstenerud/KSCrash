#!/usr/bin/env bash

set -eu -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SRC_DIR="$SCRIPT_DIR/../Sources"
COMPARE_HEADER_FILE="$SCRIPT_DIR/../Sources/KSCrashCore/include/KSCrashNamespace.h"

cd "$SCRIPT_DIR"
if [ ! -d "venv" ]; then
    python3 -m venv venv
    source venv/bin/activate
    pip3 install -r requirements.txt
else
    source venv/bin/activate
fi

TMP_DIR=${RUNNER_TEMP:-$(mktemp -d)}
DST_HEADER_FILE="$TMP_DIR/KSCrashNamespace.h"

python3 namespacer.py "$SRC_DIR" "$DST_HEADER_FILE"

diff "$COMPARE_HEADER_FILE" "$DST_HEADER_FILE" || {
    echo "Changes in public symbols discovered"
    exit 1
}
