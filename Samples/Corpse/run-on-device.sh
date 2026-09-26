#!/bin/bash
#
# Runs the corpse tests on a connected device.
#
# These cannot run anywhere else: CrashReportExtension ships in the device SDK
# only, and the path under test starts with the system handing a real corpse to
# a real extension. CI runs them on BrowserStack; this script is for running
# them against a device on your desk.
#
# Signing comes from Samples/Corpse/signing.env, which is not committed. Copy
# signing.env.example and fill it in. Signing is automatic, and
# -allowProvisioningUpdates lets xcodebuild refresh the Xcode-managed profiles
# without Xcode open.
#
# Usage:
#   ./run-on-device.sh                    # every test
#   ./run-on-device.sh testMachBadAccessIsCapturedFromTheCorpse
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SAMPLES=$(cd "$HERE/.." && pwd)
ENV_FILE="$HERE/signing.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "error: $ENV_FILE is missing. Copy signing.env.example and fill it in." >&2
  exit 1
fi
# shellcheck disable=SC1090
set -a && . "$ENV_FILE" && set +a

DEVICE_ID=${CORPSE_DEVICE_ID:-}
if [ -z "$DEVICE_ID" ]; then
  # The first connected physical device, which is almost always the intended one.
  DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/physical/ && /connected|available/ {print $(NF-3); exit}' | tr -d '()')
fi
[ -n "$DEVICE_ID" ] || { echo "error: no connected device; set CORPSE_DEVICE_ID" >&2; exit 1; }

ONLY="CorpseTests"
[ $# -gt 0 ] && ONLY="CorpseTests/CorpseTests/$1"

cd "$SAMPLES"
mise exec -- tuist generate --no-open

xcodebuild test \
  -workspace KSCrashSamples.xcworkspace \
  -scheme CorpseBrowserStack \
  -destination "id=$DEVICE_ID" \
  -destination-timeout 300 \
  -derivedDataPath build/DD \
  -only-testing:"$ONLY" \
  -allowProvisioningUpdates
