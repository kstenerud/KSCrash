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

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSHangSidecar.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Stitch watchdog sidecar data into a crash report.
 *
 * Called at report delivery time (next app launch) to merge the
 * sidecar data into the report dictionary. Runs at normal startup,
 * not during crash handling.
 *
 * See KSCrashMonitorAPI.h createStitchedReport for the full contract.
 */
CFDictionaryRef kscm_watchdog_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                   KSCrashSidecarScope scope, void *context);

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitor_WatchdogSidecar_h */
