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
#include "KSSystemSidecar.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
#pragma mark - API -
// ============================================================================

/** Access the Monitor API. */
KSCrashMonitorAPI *kscm_system_getAPI(void);

/** Copies the current system data into *dst. Returns true if the monitor is enabled and the copy succeeded. */
bool kscm_system_getSystemData(KSCrash_SystemData *dst);

/** Reads a system snapshot from a specific run's sidecar file.
 *  Use with kscrash_getRunID() for current run or kscrash_getLastRunID() for previous.
 *  Returns false if the run ID has no valid sidecar or data fails validation.
 */
bool kscm_system_getSystemDataForRunID(const char *runID, KSCrash_SystemData *outData);

/** Stitch system sidecar data into a report at delivery time.
 *
 *  See KSCrashMonitorAPI.h createStitchedReport for the full contract.
 */
CFDictionaryRef kscm_system_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                 KSCrashSidecarScope scope, void *context);

#ifdef __cplusplus
}
#endif

#endif
