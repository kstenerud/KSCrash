#!/usr/bin/env bash

set -eu -o pipefail

# -----------------------------------------------------------------------------
# Synchronize all generated code with the main KSCrash repository
#
# This is a demonstration of how you might use merge_spm_project.py to
# generate the necessary code to incorporate a namespaced KSCrash into your
# library.
#
# This demonstration will generate code for CrashLibA and CrashLibB.
#
# Note: You will need to run this script once before building anything.
# -----------------------------------------------------------------------------

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd $SCRIPT_DIR

# The SPM package to merge from (we're using the root KSCrash dir,
# but you'd likely have KSCrash as a submodule or vendored copy)
SRC_PACKAGE_DIR="${SCRIPT_DIR}/../../.."

# The targets from KSCrash that you want to merge into your library.
# We're including all of them because this will be part of the CI namespacing tests.
TARGETS=(
    KSCrashBootTimeMonitor
    KSCrashDemangleFilter
    KSCrashFilters
    KSCrashRecording
    KSCrashReportingCore
    KSCrashCore
    KSCrashDiscSpaceMonitor
    KSCrashInstallations
    KSCrashRecordingCore
    KSCrashSinks
)

# Which headers to declare as the merged target module's public API.
# CrashLibA and CrashLibB only use KSCrashInstallationConsole and KSCrashConfiguration.
MODULE_HEADERS=(
  KSCrash.h
  KSCrashInstallationConsole.h
)

printf -v TARGETS_ARG '%s,' "${TARGETS[@]}"
TARGETS_ARG="${TARGETS_ARG%,}"
printf -v MODULE_HEADERS_ARG '%s,' "${MODULE_HEADERS[@]}"
MODULE_HEADERS_ARG="${MODULE_HEADERS_ARG%,}"

# Insert KSCrash into a project as the specified target name.
# @param project_name The name of the project to insert KSCrash into (this must also be its directory name).
# @param target_name The name of the new target to create for KSCrash (make sure to artificially namespace it).
insert_kscrash_into_project() {
  local project_name=$1
  local target_name=$2
  local dst_project_dir="${SCRIPT_DIR}/${project_name}"
  ./merge_spm_project.py -c -s -t $TARGETS_ARG -m $MODULE_HEADERS_ARG $SRC_PACKAGE_DIR $dst_project_dir $target_name
}

# Example of building two separate crash libraries that each use their own namespaced KSCrash internally
insert_kscrash_into_project CrashLibA KSCrashLibA
insert_kscrash_into_project CrashLibB KSCrashLibB
