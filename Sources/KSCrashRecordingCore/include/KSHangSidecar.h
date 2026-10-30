//
//  KSHangSidecar.h
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

/* The Watchdog monitor's run sidecar: the hang in progress, or the last one,
 * written during hang detection (pure C, mmap'd). Read when a report from its
 * run is finalized, it adds crash.error.hang to that report and decides whether
 * a watchdog hang report became fatal.
 *
 * Layout (the same on 32-bit and 64-bit, no pointer-sized fields):
 *   offset  0: KSSidecarHeader header                (5 bytes + 3 padding)
 *   offset  8: uint64_t        startTimestamp        (8 bytes)
 *   offset 16: int32_t         startRole             (4 bytes)
 *   offset 20: uint8_t         startTransitionState  (1 byte + 3 padding)
 *   offset 24: uint64_t        endTimestamp          (8 bytes)
 *   offset 32: int32_t         endRole               (4 bytes)
 *   offset 36: uint8_t         endTransitionState    (1 byte)
 *   offset 37: uint8_t         recovered             (1 byte + 2 padding)
 *   total: 40 bytes
 *
 * See KSSidecarFormat.h for the format every sidecar shares.
 */

#ifndef HDR_KSHangSidecar_h
#define HDR_KSHangSidecar_h

#include <stddef.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"
#include "KSSidecarFormat.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KSHANG_MAGIC ((int32_t)0x6b736873)  // 'kshs'

#define KSCrash_Hang_V1Size ((size_t)40)
#define KSCrash_Hang_CurrentVersion ((uint8_t)1)

typedef struct {
    KSSidecarHeader header;
    uint64_t startTimestamp;
    int32_t startRole;             // task_role_t at hang start
    uint8_t startTransitionState;  // KSCrashAppTransitionState at hang start
    uint64_t endTimestamp;
    int32_t endRole;             // task_role_t at hang end/current
    uint8_t endTransitionState;  // KSCrashAppTransitionState at hang end/current
    uint8_t recovered;           // 1 once the main thread recovered from the hang
} KSCrash_HangData;

KSSIDECAR_ASSERT_LAYOUT(KSCrash_HangData, KSCrash_Hang_V1Size);

/** Reads a hang sidecar file. See kssidecar_read for the verdicts.
 *
 * @param path The file to read.
 * @param out The struct to fill; fields newer than the file's version read as
 *            zero, and the whole struct is zeroed on anything but OK.
 *
 * @return OK, Unrecoverable (no later read gets further), or Failure (the I/O
 *         failed, and a later read may get past it).
 */
KSCrashSidecarReadResult kssidecar_readHang(const char *path, KSCrash_HangData *out);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSHangSidecar_h
