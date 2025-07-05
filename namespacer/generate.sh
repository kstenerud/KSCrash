#!/usr/bin/env bash

set -eu -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SRC_DIR="$SCRIPT_DIR/../Sources"
DST_HEADER_FILE="$SCRIPT_DIR/../Sources/KSCrashCore/include/KSCrashNamespace.h"

cd "$SCRIPT_DIR"
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python namespacer.py "$SRC_DIR" "$DST_HEADER_FILE"
deactivate

