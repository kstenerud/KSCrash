//
//  KSSystemSidecar.h
//
//  Created by Alexander Cohen on 2026-09-28.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

/* The System monitor's run sidecar: the device, OS, app and process a run ran
 * on.
 *
 * Written once at init and flushed to disk by the kernel. Dynamic fields
 * (freeMemory, usableMemory) are updated in place at crash time via
 * addContextualInfoToEvent. All fields use fixed-width types (no platform
 * typedefs like cpu_type_t, pid_t, or bool) so the on-disk layout is stable.
 *
 * Version history:
 *   1: original layout (through processStartMonotonicNs)
 *   2: adds isBeingDebugged
 *
 * See KSSidecarFormat.h for the format every sidecar shares.
 */

#ifndef HDR_KSSystemSidecar_h
#define HDR_KSSystemSidecar_h

#include <stddef.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"
#include "KSSidecarFormat.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KSSYS_MAX_SHORT 64
#define KSSYS_MAX_STRING 256
#define KSSYS_MAX_PATH 512

#define KSSYS_MAGIC ((int32_t)0x6B737973)  // 'ksys'

#define KSCrash_System_V1Size ((size_t)2984)
#define KSCrash_System_V2Size ((size_t)2992)
#define KSCrash_System_CurrentVersion ((uint8_t)2)

typedef struct {
    KSSidecarHeader header;

    char systemName[KSSYS_MAX_SHORT];
    char systemVersion[KSSYS_MAX_SHORT];
    char machine[KSSYS_MAX_SHORT];
    char model[KSSYS_MAX_SHORT];
    char kernelVersion[KSSYS_MAX_STRING];
    char osVersion[KSSYS_MAX_SHORT];
    uint8_t isJailbroken;
    uint8_t procTranslated;
    int64_t appStartTimestamp;
    char executablePath[KSSYS_MAX_PATH];
    char executableName[KSSYS_MAX_STRING];
    char bundleID[KSSYS_MAX_STRING];
    char bundleName[KSSYS_MAX_STRING];
    char bundleVersion[KSSYS_MAX_SHORT];
    char bundleShortVersion[KSSYS_MAX_SHORT];
    char appID[KSSYS_MAX_SHORT];
    char cpuArchitecture[KSSYS_MAX_SHORT];
    char binaryArchitecture[KSSYS_MAX_SHORT];
    char clangVersion[KSSYS_MAX_STRING];
    int32_t cpuType;
    int32_t cpuSubType;
    int32_t binaryCPUType;
    int32_t binaryCPUSubType;
    char timezone[KSSYS_MAX_SHORT];
    char processName[KSSYS_MAX_STRING];
    int32_t processID;
    int32_t parentProcessID;
    char deviceAppHash[KSSYS_MAX_SHORT];
    char buildType[KSSYS_MAX_SHORT];
    uint64_t memorySize;
    int64_t bootTimestamp;
    uint64_t storageSize;
    uint64_t freeStorageSize;
    uint64_t freeMemory;
    uint64_t usableMemory;
    uint64_t processStartWallClockNs;  // unix epoch nanoseconds at sidecar creation
    uint64_t processStartMonotonicNs;  // CLOCK_MONOTONIC_RAW nanoseconds at sidecar creation

    // --- v2 ---
    uint8_t isBeingDebugged;  // a debugger was attached (P_TRACED) at sidecar creation
} KSCrash_SystemData;

KSSIDECAR_ASSERT_LAYOUT(KSCrash_SystemData, KSCrash_System_V2Size);
KSSIDECAR_ASSERT_VERSION_START(KSCrash_SystemData, isBeingDebugged, KSCrash_System_V1Size);

/** Reads a system sidecar file. See kssidecar_read for the verdicts.
 *
 * @param path The file to read.
 * @param out The struct to fill; fields newer than the file's version read as
 *            zero, and the whole struct is zeroed on anything but OK.
 *
 * @return OK, Unrecoverable (no later read gets further), or Failure (the I/O
 *         failed, and a later read may get past it).
 */
KSCrashSidecarReadResult kssidecar_readSystem(const char *path, KSCrash_SystemData *out);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSSystemSidecar_h
