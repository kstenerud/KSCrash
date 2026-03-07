//
//  KSCrashMonitor_UserInfo.h
//
//  Created by Alexander Cohen on 2026-03-01.
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

/**
 * @file KSCrashMonitor_UserInfo.h
 * @brief Per-key user data backed by an mmap'd run sidecar.
 *
 * Provides a per-key API for storing user-supplied metadata that survives
 * crashes with zero crash-time cost. Each setter memcpy's a record into
 * a MAP_SHARED mmap'd file under os_unfair_lock — no syscalls per write.
 *
 * At report delivery time (next launch), the stitch function reads the
 * sidecar, resolves last-write-wins for each key, and merges the resulting
 * dictionary into the report's "user" section.
 *
 * Setters are no-ops before kscrash_install() — the store is only
 * created when the monitor is enabled.
 */

#ifndef HDR_KSCrashMonitor_UserInfo_h
#define HDR_KSCrashMonitor_UserInfo_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Access the Monitor API. */
KSCrashMonitorAPI *kscm_userinfo_getAPI(void);

/** Set a string value for the given key.
 *  Passing NULL for value is equivalent to removeValue.
 *  Strings longer than 1024 bytes are truncated.
 */
void kscm_userinfo_setString(const char *key, const char *value);

/** Set a signed 64-bit integer value. */
void kscm_userinfo_setInt64(const char *key, int64_t value);

/** Set an unsigned 64-bit integer value. */
void kscm_userinfo_setUInt64(const char *key, uint64_t value);

/** Set a double-precision floating point value. */
void kscm_userinfo_setDouble(const char *key, double value);

/** Set a boolean value. */
void kscm_userinfo_setBool(const char *key, bool value);

/** Set a date value (nanoseconds since 1970-01-01 00:00:00 UTC). */
void kscm_userinfo_setDate(const char *key, uint64_t nanosecondsSince1970);

/** Remove the value for the given key (writes a tombstone record). */
void kscm_userinfo_removeValue(const char *key);

/** Stitch function — implemented in KSCrashMonitor_UserInfoStitch.m.
 *
 *  Reads the append-only log sidecar, resolves last-write-wins per key,
 *  and merges the resulting dictionary into report["user"].
 *
 *  Runs at normal app startup time — ObjC and heap allocation are safe.
 */
char *kscm_userinfo_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope, void *context);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashMonitor_UserInfo_h
