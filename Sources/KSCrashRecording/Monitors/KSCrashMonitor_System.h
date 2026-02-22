//
//  KSCrashMonitor_System.h
//
//  Created by Karl Stenerud on 2012-02-05.
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

#ifndef KSCrashMonitor_System_h
#define KSCrashMonitor_System_h

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
#pragma mark - mmap'd System Data -
// ============================================================================

#define KSSYS_MAX_SHORT 64
#define KSSYS_MAX_STRING 256
#define KSSYS_MAX_PATH 512

#define KSSYS_MAGIC ((int32_t)0x6B737973)  // 'ksys'

static const uint8_t KSCrash_System_CurrentVersion = 1;

/** mmap'd struct written once at init and flushed to disk by the kernel.
 *  No pointers — all data is inline so it survives across launches.
 *  Dynamic fields (freeMemory, usableMemory) are updated in-place
 *  at crash time via addContextualInfoToEvent.
 *
 *  All fields use fixed-width types (no platform typedefs like cpu_type_t,
 *  pid_t, or bool) so the on-disk layout is self-documenting and stable.
 */
typedef struct {
    int32_t magic;
    uint8_t version;

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
} KSCrash_SystemData;

_Static_assert(sizeof(KSCrash_SystemData) == 2968, "KSCrash_SystemData size changed — update sidecar version");

// ============================================================================
#pragma mark - API -
// ============================================================================

/** Access the Monitor API. */
KSCrashMonitorAPI *kscm_system_getAPI(void);

/** Copies the current system data into *dst. Returns true if the monitor is enabled and the copy succeeded. */
bool kscm_system_getSystemData(KSCrash_SystemData *dst);

/** Set the boot timestamp (seconds since epoch) on the system monitor's mmap'd struct. */
void kscm_system_setBootTime(int64_t bootTimestamp);

/** Set storage and free storage sizes on the system monitor's mmap'd struct. */
void kscm_system_setDiscSpace(uint64_t storageSize, uint64_t freeStorageSize);

/** Update just the free storage size on the system monitor's mmap'd struct. */
void kscm_system_setFreeStorageSize(uint64_t freeStorageSize);

#ifdef __cplusplus
}
#endif

#endif
