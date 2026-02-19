//
//  KSCrashMonitor_WatchdogSidecar.h
//
//  Created by Alexander Cohen on 2026-02-01.
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

#ifndef KSCrashMonitor_WatchdogSidecar_h
#define KSCrashMonitor_WatchdogSidecar_h

#include <mach/task_policy.h>
#include <stdbool.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KSHANG_SIDECAR_MAGIC 0x6b736873  // 'kshs'
#define KSHANG_SIDECAR_VERSION_1_0 1
#define KSHANG_SIDECAR_CURRENT_VERSION KSHANG_SIDECAR_VERSION_1_0

/** Memory-mapped sidecar struct persisted alongside a hang report.
 *
 * Written by the watchdog monitor during hang detection (pure C, mmap'd).
 * Read by the stitch logic at next launch (ObjC, safe context).
 */
typedef struct {
    int32_t magic;
    uint8_t version;
    uint64_t endTimestamp;
    task_role_t endRole;
    bool recovered;
} KSHangSidecar;

// Expected layout (same on 32-bit and 64-bit — no pointer-sized fields):
//   offset  0: int32_t    magic          (4 bytes)
//   offset  4: uint8_t    version        (1 byte + 3 padding)
//   offset  8: uint64_t   endTimestamp   (8 bytes)
//   offset 16: task_role_t endRole       (4 bytes)
//   offset 20: bool       recovered      (1 byte + 3 padding)
//   total: 24 bytes
_Static_assert(sizeof(KSHangSidecar) == 24, "KSHangSidecar size changed — update sidecar version");

/** Stitch watchdog sidecar data into a crash report.
 *
 * Called at report delivery time (next app launch) to merge the mmap'd
 * sidecar data into the JSON report. This function uses ObjC/Foundation
 * for JSON parsing, which is safe because it runs at normal startup.
 *
 * @param report The NULL-terminated JSON report string.
 * @param sidecarPath Path to the mmap'd KSHangSidecar file.
 * @param scope The sidecar scope (report or run).
 * @param context The monitor's opaque context pointer (unused).
 *
 * @return A malloc'd NULL-terminated string with the updated report,
 *         or NULL to leave the report unchanged. Caller frees the buffer.
 */
char *kscm_watchdog_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope, void *context);

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitor_WatchdogSidecar_h */
