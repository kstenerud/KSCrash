#!/usr/bin/env bash

# Note: OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface" is a workaround
# for a compiler bug introduced in XCode 14.3.
# https://github.com/swiftlang/swift/issues/64669

set -eux -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PRODUCT_DIR="${SCRIPT_DIR}/products"
ROOT_DIR="${SCRIPT_DIR}/../../.."

compile_framework() {
    local product_name=$1
    local namespace=$2
    local destination=$3
    local archive_name_suffix=$4
    xcodebuild archive \
        -scheme $product_name \
        -destination "$destination" \
        -archivePath "$PRODUCT_DIR/$product_name-$archive_name_suffix" \
        -derivedDataPath "$PRODUCT_DIR/DerivedData" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        GCC_PREPROCESSOR_DEFINITIONS=\"KSCRASH_NAMESPACE\=$namespace\"
        # OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface"
}

build_xcframework() {
    local product_name=$1
    local namespace=$2
    cd "$SCRIPT_DIR/$product_name"

    compile_framework $product_name $namespace "generic/platform=iOS"           "ios.xcarchive"
    compile_framework $product_name $namespace "generic/platform=iOS Simulator" "ios-simulator.xcarchive"

    xcodebuild -create-xcframework \
    -framework "$PRODUCT_DIR/$product_name-ios.xcarchive/Products/Library/Frameworks/$product_name.framework" \
    -framework "$PRODUCT_DIR/$product_name-ios-simulator.xcarchive/Products/Library/Frameworks/$product_name.framework" \
    -output "$PRODUCT_DIR/$product_name.xcframework"
}

build_app() {
    cd "$SCRIPT_DIR/CrashyApp"
    xcodebuild archive \
        -scheme CrashyApp \
        -destination "generic/platform=iOS" \
        -archivePath "$PRODUCT_DIR/CrashyApp.xcarchive" \
        -derivedDataPath "$PRODUCT_DIR/DerivedData"
        # OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface"
}

customize_kscrash() {
    local namespace=$1
    local kscrash_dir="$PRODUCT_DIR/KSCrash${namespace}"
    local root_dir="$ROOT_DIR"
    mkdir -p "$kscrash_dir"
    ln -s "$root_dir/Sources" "$kscrash_dir/Sources"
    ln -s "$root_dir/Tests" "$kscrash_dir/Tests"
    cat "$root_dir/Package.swift" | sed "s/\"KSCrash\"/\"KSCrash${namespace}\"/g" > "$kscrash_dir/Package.swift"
}

cd "$SCRIPT_DIR"
rm -rf "$PRODUCT_DIR"
mkdir -p "$PRODUCT_DIR"

customize_kscrash LibA
customize_kscrash LibB

build_xcframework CrashLibA LibA
build_xcframework CrashLibB LibB

build_app
