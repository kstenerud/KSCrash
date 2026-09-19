#!/bin/bash
#
# Runs the corpse tests on a connected device.
#
# These cannot run anywhere else: CrashReportExtension ships in the device SDK
# only, and the path under test starts with the system handing a real corpse to
# a real extension. They also need an App Group, which a device farm's re-signing
# strips, so a device you control is currently the only place they run at all.
#
# Signing comes from Samples/Corpse/signing.env, which is not committed. Copy
# signing.env.example and fill it in. Manual signing is deliberate: automatic
# signing needs Xcode open to refresh profiles, and with the workspace closed a
# terminal run fails with "Developer App Certificate is not trusted", which
# reads like a device problem rather than a signing one.
#
# Usage:
#   ./run-on-device.sh                    # every test, memory included
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

# Everything runs, memory included. It exhausts the device and evicts whatever
# else is open, which is a reason to name a single test when you are on your own
# phone, not a reason to drop it from a full run.
exec xcodebuild test \
  -workspace KSCrashSamples.xcworkspace \
  -scheme CorpseBrowserStack \
  -destination "id=$DEVICE_ID" \
  -destination-timeout 300 \
  -derivedDataPath build/DD \
  -only-testing:"$ONLY" \
  -allowProvisioningUpdates
