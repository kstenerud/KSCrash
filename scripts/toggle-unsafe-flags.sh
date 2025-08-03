#!/bin/bash

# Script to toggle unsafe flags in Package.swift for release process
# Usage: ./toggle-unsafe-flags.sh [remove|restore]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_SWIFT="$PROJECT_ROOT/Package.swift"

if [ ! -f "$PACKAGE_SWIFT" ]; then
    echo "Error: Package.swift not found at $PACKAGE_SWIFT"
    exit 1
fi

case "$1" in
    "remove")
        echo "Removing unsafe flags from Package.swift..."
        
        # Create a temporary file
        TEMP_FILE=$(mktemp)
        
        # Use awk to find and replace the warningFlags array with an empty array
        awk '
            /^let warningFlags = \[/ {
                print "let warningFlags: [String] = []"
                in_array = 1
                next
            }
            in_array && /^\]/ {
                in_array = 0
                next
            }
            !in_array {
                print
            }
        ' "$PACKAGE_SWIFT" > "$TEMP_FILE"
        
        # Replace the original file
        mv "$TEMP_FILE" "$PACKAGE_SWIFT"
        
        echo "Successfully removed unsafe flags from Package.swift"
        ;;
        
    "restore")
        echo "Restoring Package.swift from git..."
        git checkout -- "$PACKAGE_SWIFT"
        echo "Successfully restored Package.swift"
        ;;
        
    *)
        echo "Usage: $0 [remove|restore]"
        echo "  remove  - Replace warningFlags array with empty array"
        echo "  restore - Restore Package.swift from git"
        exit 1
        ;;
esac