//
//  KSCrashRunContext.h
//
//  Created by Alexander Cohen on 2026-03-15.
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

/* Shared layer for cross-monitor state.
 *
 * Monitors never import each other's headers — all cross-cutting reads
 * go through RunContext.
 */

#ifndef KSCrashRunContext_h
#define KSCrashRunContext_h

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashMonitor_Lifecycle.h"
#include "KSCrashMonitor_Resource.h"
#include "KSCrashMonitor_System.h"
#include "KSCrashNamespace.h"
#include "KSTaskRole.h"
#include "KSTerminationReason.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
#pragma mark - Run Context -
// ============================================================================

#define KSRUNCONTEXT_RUN_ID_LENGTH 37  // UUID string (36) + null

/** Analyzed snapshot of a single run's sidecar data. */
typedef struct {
    char runID[KSRUNCONTEXT_RUN_ID_LENGTH];

    KSTerminationReason terminationReason;
    bool producedReport;

    bool lifecycleValid;
    KSCrash_LifecycleData lifecycle;

    bool resourceValid;
    KSCrash_ResourceData resource;

    bool systemValid;
    KSCrash_SystemData system;

    uint64_t mostRecentTimestampNs;
} KSCrashRunContext;

/** Store the sidecar path resolver and analyze the previous run.
 *
 *  Must be called after monitors are enabled and before
 *  kscm_notifyPostSystemEnable().
 */
void ksruncontext_init(KSCrashSidecarRunPathForRunIDProviderFunc pathForRunID);

/** Load the context for any run ID.
 *
 *  Reads all sidecars for the given run, determines the termination reason
 *  by comparing against the current system state, and populates outContext.
 *
 *  @param runID      The run ID whose sidecars to read.
 *  @param pathForRunID  Callback that resolves sidecar file paths for a given run ID.
 *  @param outContext Populated on return.
 *  @return true if at least one sidecar was successfully read.
 */
bool ksruncontext_contextForRunID(const char *runID, KSCrashSidecarRunPathForRunIDProviderFunc pathForRunID,
                                  KSCrashRunContext *outContext);

/** Returns the cached previous run context.
 *  Only valid after ksruncontext_init().
 */
const KSCrashRunContext *ksruncontext_previousRunContext(void);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashRunContext_h
